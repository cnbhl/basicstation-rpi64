#!/bin/bash
#
# setup.sh - Setup wizard steps
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh (including logging), validation.sh, file_ops.sh, service.sh, gps.sh
#
# Expected global variables from main script:
#   SCRIPT_DIR, CUPS_DIR, BUILD_DIR, STATION_BINARY
#   CHIP_ID_DIR, CHIP_ID_SOURCE, CHIP_ID_LOG_STUB, CHIP_ID_TOOL
#   RESET_LGW_SCRIPT
#   TTN_REGION, CUPS_URI, GATEWAY_EUI, CUPS_KEY, LOG_FILE, GPS_DEVICE
#   SKIP_DEPS
#

#######################################
# Build Functions
#######################################

build_chip_id() {
    local lgw_inc="$BUILD_DIR/include/lgw"
    local lgw_lib="$BUILD_DIR/lib"

    if [[ ! -d "$lgw_inc" ]] || [[ ! -f "$lgw_lib/liblgw1302.a" ]]; then
        print_warning "Cannot build chip_id: libloragw not found (station build required first)"
        return 1
    fi

    if [[ ! -f "$CHIP_ID_SOURCE" ]]; then
        print_warning "Cannot build chip_id: source file not found at $CHIP_ID_SOURCE"
        return 1
    fi

    echo "  Building chip_id tool..."
    local build_err
    build_err=$(mktemp)

    if gcc -std=gnu11 -O2 \
        -I"$lgw_inc" \
        "$CHIP_ID_SOURCE" "$CHIP_ID_LOG_STUB" \
        -L"$lgw_lib" -llgw1302 -lm -lpthread -lrt \
        -o "$CHIP_ID_TOOL" 2>"$build_err"; then
        rm -f "$build_err"
        echo "  Created: $CHIP_ID_TOOL"
        return 0
    else
        print_warning "  Failed to build chip_id (non-critical, manual EUI entry available)"
        if [[ -s "$build_err" ]]; then
            echo "  Build error:"
            sed 's/^/    /' "$build_err"
        fi
        rm -f "$build_err"
        return 1
    fi
}

#######################################
# Setup Step Functions
#######################################

step_check_existing_credentials() {
    if file_exists "$CUPS_DIR/cups.key"; then
        print_warning "Warning: Credentials already exist in $CUPS_DIR"
        if ! confirm "Do you want to overwrite them?"; then
            echo "Setup cancelled."
            exit 0
        fi
    fi
}

step_build_station() {
    print_header "Step 1: Build the station binary"
    echo ""
    echo "This step will compile the Basic Station software for the SX1302 Corecell platform."
    echo ""
    echo "The build process will:"
    echo "  - Download and compile dependencies (mbedTLS, libloragw)"
    echo "  - Compile the Basic Station source code"
    echo "  - Create the executable at: build-corecell-std/bin/station"
    echo "  - Build the chip_id tool for EUI detection"
    echo ""

    if file_exists "$STATION_BINARY"; then
        print_warning "Note: A station binary already exists."
        if ! confirm "Do you want to rebuild?"; then
            print_success "Skipping build, using existing binary."
            # Still try to build chip_id if it doesn't exist
            if ! file_executable "$CHIP_ID_TOOL"; then
                build_chip_id || true
            fi
            echo ""
            return 0
        fi
    fi

    if ! confirm "Start the build process now?" "y"; then
        echo "Setup cancelled. You can build manually with:"
        echo "  make platform=corecell variant=std"
        exit 0
    fi

    echo ""
    print_warning "Building... This may take several minutes on first build."
    echo ""

    cd "$SCRIPT_DIR"
    if make platform=corecell variant=std; then
        echo ""
        print_success "Station build completed successfully."
        build_chip_id || true
    else
        print_error "Build failed. Please check the error messages above."
        echo "You can try building manually with: make platform=corecell variant=std"
        exit 1
    fi
    echo ""
}

step_select_region() {
    print_header "Step 2: Select your TTN region"
    echo "  1) EU1  - Europe (eu1.cloud.thethings.network)"
    echo "  2) NAM1 - North America (nam1.cloud.thethings.network)"
    echo "  3) AU1  - Australia (au1.cloud.thethings.network)"
    echo ""

    local region_choice
    read -rp "Enter region number [1-3]: " region_choice

    case $region_choice in
        1) TTN_REGION="eu1" ;;
        2) TTN_REGION="nam1" ;;
        3) TTN_REGION="au1" ;;
        *)
            print_warning "Invalid selection. Defaulting to EU1."
            TTN_REGION="eu1"
            ;;
    esac

    CUPS_URI="https://${TTN_REGION}.cloud.thethings.network:443"
    echo -e "Selected: ${GREEN}$CUPS_URI${NC}"
    echo ""
}

step_detect_eui() {
    local detected_eui=""

    print_header "Step 3: Gateway EUI Detection"
    echo ""
    echo "The Gateway EUI is a unique 64-bit identifier for your gateway."
    echo "This EUI is required to register your gateway on The Things Network."
    echo ""
    echo "Attempting to read EUI from SX1302 chip..."
    echo ""

    if file_executable "$CHIP_ID_TOOL"; then
        log_debug "Using chip_id tool at $CHIP_ID_TOOL"

        # chip_id requires reset_lgw.sh in the same directory
        local chip_id_dir
        chip_id_dir="$(dirname "$CHIP_ID_TOOL")"

        if [[ ! -f "$chip_id_dir/reset_lgw.sh" ]] && file_exists "$RESET_LGW_SCRIPT"; then
            copy_file "$RESET_LGW_SCRIPT" "$chip_id_dir/reset_lgw.sh" "755"
            log_debug "Copied reset_lgw.sh to $chip_id_dir"
        fi

        local chip_output
        log_debug "Running: sudo ./chip_id -d /dev/spidev0.0"
        chip_output=$(cd "$chip_id_dir" && sudo ./chip_id -d /dev/spidev0.0 2>&1) || true
        log_debug "chip_id output: $chip_output"

        detected_eui=$(printf '%s' "$chip_output" | grep -i "concentrator EUI" | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' | tr '[:lower:]' '[:upper:]')

        if [[ -n "$detected_eui" ]] && validate_eui "$detected_eui"; then
            log_info "Detected Gateway EUI: $detected_eui"
            echo -e "Detected EUI from SX1302 chip: ${GREEN}$detected_eui${NC}"
            echo ""
            if confirm "Use this EUI?" "y"; then
                GATEWAY_EUI="$detected_eui"
                return 0
            fi
            detected_eui=""
        else
            print_warning "Could not auto-detect EUI from SX1302 chip."
            log_warning "EUI detection failed. chip_id output: $chip_output"
            if [[ -n "$chip_output" ]]; then
                echo "chip_id output: $chip_output"
            fi
        fi
    else
        print_warning "chip_id tool not found at $CHIP_ID_TOOL"
        log_warning "chip_id tool not found at $CHIP_ID_TOOL"
        echo "The tool will be built automatically when you build the station."
    fi

    echo ""
    echo "Please enter your Gateway EUI manually."
    echo "This is a 16-character hex string (e.g., AABBCCDDEEFF0011)"
    echo "You can find this in your TTN Console under Gateway settings."
    echo ""
    read -rp "Gateway EUI: " GATEWAY_EUI

    if ! validate_eui "$GATEWAY_EUI"; then
        print_warning "Warning: Gateway EUI should be 16 hex characters."
        if ! confirm "Continue anyway?"; then
            echo "Setup cancelled."
            exit 1
        fi
    fi

    GATEWAY_EUI=$(printf '%s' "$GATEWAY_EUI" | tr '[:lower:]' '[:upper:]')
}

step_show_registration_instructions() {
    echo -e "Gateway EUI: ${GREEN}$GATEWAY_EUI${NC}"
    echo ""
    print_warning "────────────────────────────────────────────────────────────────"
    print_warning "IMPORTANT: Register this gateway in TTN Console before continuing"
    print_warning "────────────────────────────────────────────────────────────────"
    echo ""
    echo "If you haven't already, you need to register this gateway in TTN:"
    echo ""
    echo "  1. Go to: https://console.cloud.thethings.network/"
    echo "  2. Select your region (${TTN_REGION})"
    echo "  3. Navigate to: Gateways > + Register gateway"
    echo "  4. Enter Gateway EUI: ${GATEWAY_EUI}"
    echo "  5. Choose frequency plan matching your hardware"
    echo "  6. Click 'Register gateway'"
    echo ""
    echo "After registration, you'll need to create an API key (next step)."
    echo ""
    read -rp "Press Enter when your gateway is registered in TTN Console... "
    echo ""
}

step_get_cups_key() {
    print_header "Step 4: Enter your CUPS API Key"
    echo ""
    echo "Now create an API key for CUPS in TTN Console:"
    echo ""
    echo "  1. Go to your gateway in TTN Console"
    echo "  2. Navigate to: API Keys > + Add API Key"
    echo "  3. Name it (e.g., 'CUPS Key')"
    echo "  4. Grant rights: 'Link as Gateway to a Gateway Server for traffic"
    echo "     exchange, i.e. write uplink and read downlink'"
    echo "  5. Click 'Create API Key' and copy the key"
    echo ""
    print_warning "Note: The key is only shown once - copy it now!"
    echo ""

    if ! read_secret CUPS_KEY "Paste your API key (it will not be displayed):"; then
        print_error "Error: API key cannot be empty."
        exit 1
    fi

    # Strip "Authorization: Bearer " prefix if user pasted the full string
    CUPS_KEY="${CUPS_KEY#Authorization: Bearer }"

    print_success "API key received."
    echo ""
}

step_setup_trust_cert() {
    print_header "Step 5: Setting up trust certificate..."

    local trust_cert="$CUPS_DIR/cups.trust"

    if file_exists /etc/ssl/certs/ca-certificates.crt; then
        copy_file /etc/ssl/certs/ca-certificates.crt "$trust_cert" "644"
        print_success "Trust certificate installed (system CA bundle)."
    else
        echo "System CA bundle not found, downloading Let's Encrypt root..."
        if curl -sf https://letsencrypt.org/certs/isrgrootx1.pem -o "$trust_cert"; then
            chmod 644 "$trust_cert"
            if [[ ! -s "$trust_cert" ]]; then
                print_error "Error: Downloaded certificate is empty."
                exit 1
            fi
            print_success "Trust certificate downloaded."
        else
            print_error "Error: Could not download trust certificate."
            exit 1
        fi
    fi
    echo ""
}

step_select_log_location() {
    print_header "Step 6: Select log file location"
    echo "  1) Local directory ($CUPS_DIR/station.log)"
    echo "  2) System log (/var/log/station.log) - requires sudo"
    echo ""

    local log_choice
    read -rp "Enter choice [1-2]: " log_choice

    case $log_choice in
        2)
            LOG_FILE="/var/log/station.log"
            print_warning "Note: Creating system log file with proper permissions."
            if confirm "Create log file now with sudo?" "y"; then
                sudo touch "$LOG_FILE"
                sudo chown "${USER}:${USER}" "$LOG_FILE"
                sudo chmod 644 "$LOG_FILE"
                print_success "Log file created: $LOG_FILE"
            fi
            ;;
        *)
            LOG_FILE="$CUPS_DIR/station.log"
            touch "$LOG_FILE"
            chmod 644 "$LOG_FILE"
            print_success "Log file will be: $LOG_FILE"
            ;;
    esac
    echo ""
}

step_detect_gps() {
    print_header "Step 7: GPS Configuration"
    echo ""
    echo "Basic Station can use a GPS module for precise timing and location."
    echo ""
    print_warning "Note: Scanning serial ports requires sudo for device access."
    echo ""
    echo "Scanning serial ports for GPS NMEA data..."
    echo ""

    if detect_gps_port; then
        echo ""
        echo -e "GPS detected on: ${GREEN}$GPS_DEVICE${NC}"
        echo ""
        if ! confirm "Use this GPS device?" "y"; then
            GPS_DEVICE=""
        fi
    else
        echo ""
        print_warning "No GPS module detected on standard serial ports."
        echo ""
        echo "This could mean:"
        echo "  - No GPS module is connected"
        echo "  - Serial port is not enabled (check raspi-config)"
        echo "  - GPS module uses a non-standard port/baud rate"
        echo ""
    fi

    if [[ -z "$GPS_DEVICE" ]]; then
        echo "Options:"
        echo "  1) Disable GPS (use network time only)"
        echo "  2) Enter GPS device path manually"
        echo ""

        local gps_choice
        read -rp "Enter choice [1-2]: " gps_choice

        case $gps_choice in
            2)
                echo ""
                echo "Common GPS device paths:"
                echo "  /dev/ttyAMA0   - Pi 5 primary UART"
                echo "  /dev/ttyS0     - Pi 4/3 mini UART"
                echo "  /dev/serial0   - Symlink (varies by Pi model)"
                echo "  /dev/ttyAMA10  - Pi 5 secondary UART"
                echo ""
                read -rp "Enter GPS device path: " GPS_DEVICE
                if [[ ! -c "$GPS_DEVICE" ]]; then
                    print_warning "Warning: Device $GPS_DEVICE does not exist."
                    if ! confirm "Continue anyway?"; then
                        GPS_DEVICE=""
                    fi
                fi
                ;;
            *)
                GPS_DEVICE=""
                print_warning "GPS disabled. Gateway will use network time synchronization."
                ;;
        esac
    fi

    if [[ -n "$GPS_DEVICE" ]]; then
        echo -e "GPS device: ${GREEN}$GPS_DEVICE${NC}"
    fi
    echo ""
}

step_create_credentials() {
    print_header "Step 8: Creating credential files..."

    # Write URI file (not sensitive)
    write_file_secure "$CUPS_DIR/cups.uri" "$CUPS_URI" "644"
    echo "  Created: cups.uri"

    # Write API key file (sensitive - use secure write)
    write_secret_file "$CUPS_DIR/cups.key" "Authorization: Bearer $CUPS_KEY"
    echo "  Created: cups.key (permissions: 600)"

    print_header "Step 9: Generating station.conf..."

    local template="$CUPS_DIR/station.conf.template"
    if file_exists "$template"; then
        # Format GPS_DEVICE for JSON: either false or quoted string
        local gps_json_value
        if [[ -n "$GPS_DEVICE" ]]; then
            gps_json_value="\"$GPS_DEVICE\""
        else
            gps_json_value="false"
        fi

        process_template "$template" "$CUPS_DIR/station.conf" \
            "GATEWAY_EUI=$GATEWAY_EUI" \
            "INSTALL_DIR=$SCRIPT_DIR" \
            "LOG_FILE=$LOG_FILE" \
            "GPS_DEVICE=$gps_json_value"
        chmod 644 "$CUPS_DIR/station.conf"
        echo "  Created: station.conf"
    else
        print_warning "Warning: station.conf.template not found. Please configure station.conf manually."
    fi

    print_header "Step 10: Setting file permissions..."
    chmod 600 "$CUPS_DIR/cups.key" 2>/dev/null || true
    chmod 600 "$CUPS_DIR/tc.key" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/cups.uri" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/cups.trust" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/station.conf" 2>/dev/null || true
    echo "  Permissions set."
}

step_setup_service() {
    echo ""
    print_header "Step 11: Gateway startup configuration"
    echo ""

    local service_name="basicstation.service"
    local service_was_active=false

    if service_is_active "$service_name"; then
        service_was_active=true
    fi

    if ! confirm "Do you want to run the gateway as a systemd service?"; then
        print_summary "manual"
        return 0
    fi

    echo ""
    print_success "Setting up systemd service..."

    local service_file="/etc/systemd/system/$service_name"

    # Create service file content
    local service_content
    read -r -d '' service_content << EOF || true
[Unit]
Description=LoRa Basics Station (SX1302/Corecell) for TTN (CUPS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR

ExecStart=$STATION_BINARY --home $CUPS_DIR

Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false
ProtectKernelTunables=false
ProtectKernelModules=true
ProtectControlGroups=true

# Logs
StandardOutput=journal
StandardError=journal
SyslogIdentifier=basicstation

[Install]
WantedBy=multi-user.target
EOF

    # Write service file via sudo
    printf '%s\n' "$service_content" | sudo tee "$service_file" > /dev/null
    echo "  Created: $service_file"

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    echo "  Service enabled."

    echo ""
    if [[ "$service_was_active" == true ]]; then
        print_warning "Service was already running. Restarting with new configuration..."
        service_restart "$service_name" || true
    elif confirm "Do you want to start the service now?" "y"; then
        service_start "$service_name" || true
    else
        echo ""
        echo "To start the service later, run:"
        print_warning "  sudo systemctl start $service_name"
    fi

    print_summary "service"
}

print_summary() {
    local mode="$1"

    echo ""
    print_banner "Setup Complete!"
    echo "Your gateway is configured with:"
    echo "  Region:      $TTN_REGION"
    echo "  Gateway EUI: $GATEWAY_EUI"
    echo "  GPS device:  ${GPS_DEVICE:-disabled}"
    echo "  Config dir:  $CUPS_DIR"
    echo "  Log file:    $LOG_FILE"
    echo ""
    echo "Setup log:     $(get_log_file)"
    echo ""

    if [[ "$mode" == "service" ]]; then
        echo "Useful commands:"
        print_warning "  sudo systemctl status basicstation.service  - Check service status"
        print_warning "  sudo systemctl stop basicstation.service   - Stop the service"
        print_warning "  sudo systemctl restart basicstation.service - Restart the service"
        print_warning "  sudo journalctl -u basicstation.service -f  - View live logs"
    else
        echo "To start the gateway manually:"
        print_warning "  cd $SCRIPT_DIR/examples/corecell"
        print_warning "  ./start-station.sh -l ./cups-ttn"
        echo ""
        print_warning "Note: You may need to run start-station.sh with sudo for GPIO access."
    fi
}

#######################################
# Main Setup Function
#######################################

run_setup() {
    print_banner "LoRa Basic Station Setup for TTN"

    log_info "=== Starting setup wizard ==="

    # Check dependencies before proceeding
    if [[ "$SKIP_DEPS" == true ]]; then
        log_warning "Skipping dependency checks (--skip-deps flag)"
        print_warning "Skipping dependency checks as requested."
        echo ""
    elif ! check_all_dependencies; then
        print_error "Cannot proceed without required dependencies."
        echo "Please install the missing packages and try again."
        echo ""
        echo "Use --skip-deps to bypass this check (not recommended)."
        exit 1
    fi

    step_check_existing_credentials
    log_debug "Completed: check_existing_credentials"

    step_build_station
    log_debug "Completed: build_station"

    step_select_region
    log_info "Selected region: $TTN_REGION"

    step_detect_eui
    log_info "Gateway EUI: $GATEWAY_EUI"

    step_show_registration_instructions

    step_get_cups_key
    log_debug "Completed: get_cups_key (key received)"

    step_setup_trust_cert
    log_debug "Completed: setup_trust_cert"

    step_select_log_location
    log_info "Log file location: $LOG_FILE"

    step_detect_gps
    log_info "GPS device: ${GPS_DEVICE:-disabled}"

    step_create_credentials
    log_debug "Completed: create_credentials"

    step_setup_service
    log_info "=== Setup wizard completed ==="
}
