#!/bin/bash
#
# LoRa Basic Station Setup Script for Raspberry Pi 5 with TTN
# This script configures the gateway credentials for The Things Network
#

set -e

#######################################
# Constants
#######################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly CUPS_DIR="$SCRIPT_DIR/examples/corecell/cups-ttn"
readonly BUILD_DIR="$SCRIPT_DIR/build-corecell-std"
readonly STATION_BINARY="$BUILD_DIR/bin/station"
readonly CHIP_ID_DIR="$SCRIPT_DIR/tools/chip_id"
readonly CHIP_ID_SOURCE="$CHIP_ID_DIR/chip_id.c"
readonly CHIP_ID_LOG_STUB="$CHIP_ID_DIR/log_stub.c"
readonly CHIP_ID_TOOL="$BUILD_DIR/bin/chip_id"
readonly RESET_LGW_SCRIPT="$CHIP_ID_DIR/reset_lgw.sh"

#######################################
# Utility Functions
#######################################

print_header() {
    echo -e "${GREEN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_banner() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} $1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Prompt for yes/no confirmation
# Usage: confirm "Question?" && do_something
# Returns 0 (true) for y/Y, 1 (false) for n/N or empty
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [ "$default" = "y" ]; then
        read -rp "$prompt (Y/n): " response
        [ "$response" != "n" ] && [ "$response" != "N" ]
    else
        read -rp "$prompt (y/N): " response
        [ "$response" = "y" ] || [ "$response" = "Y" ]
    fi
}

# Validate 16-character hex string
validate_eui() {
    local eui="$1"
    [[ "$eui" =~ ^[0-9A-Fa-f]{16}$ ]]
}

#######################################
# Step Functions
#######################################

step_check_existing_credentials() {
    if [ -f "$CUPS_DIR/cups.key" ]; then
        print_warning "Warning: Credentials already exist in $CUPS_DIR"
        if ! confirm "Do you want to overwrite them?"; then
            echo "Setup cancelled."
            exit 0
        fi
    fi
}

build_chip_id() {
    # Build chip_id tool using the libloragw from the station build
    local lgw_inc="$BUILD_DIR/include/lgw"
    local lgw_lib="$BUILD_DIR/lib"

    if [ ! -d "$lgw_inc" ] || [ ! -f "$lgw_lib/liblgw1302.a" ]; then
        print_warning "Cannot build chip_id: libloragw not found (station build required first)"
        return 1
    fi

    if [ ! -f "$CHIP_ID_SOURCE" ]; then
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
        if [ -s "$build_err" ]; then
            echo "  Build error:"
            sed 's/^/    /' "$build_err"
        fi
        rm -f "$build_err"
        return 1
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

    if [ -f "$STATION_BINARY" ]; then
        print_warning "Note: A station binary already exists."
        if ! confirm "Do you want to rebuild?"; then
            print_success "Skipping build, using existing binary."
            # Still try to build chip_id if it doesn't exist
            if [ ! -x "$CHIP_ID_TOOL" ]; then
                build_chip_id
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
        build_chip_id
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
    read -rp "Enter region number [1-3]: " region_choice

    case $region_choice in
        1) TTN_REGION="eu1" ;;
        2) TTN_REGION="nam1" ;;
        3) TTN_REGION="au1" ;;
        *)
            print_error "Invalid selection. Defaulting to EU1."
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

    if [ -x "$CHIP_ID_TOOL" ]; then
        # chip_id requires reset_lgw.sh in the same directory
        # Copy it to the build/bin directory if not present
        local chip_id_dir
        chip_id_dir="$(dirname "$CHIP_ID_TOOL")"
        if [ ! -f "$chip_id_dir/reset_lgw.sh" ] && [ -f "$RESET_LGW_SCRIPT" ]; then
            cp "$RESET_LGW_SCRIPT" "$chip_id_dir/"
            chmod +x "$chip_id_dir/reset_lgw.sh"
        fi

        cd "$chip_id_dir"
        local chip_output
        chip_output=$(sudo ./chip_id -d /dev/spidev0.0 2>&1) || true
        cd "$SCRIPT_DIR"

        detected_eui=$(echo "$chip_output" | grep -i "concentrator EUI" | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' | tr '[:lower:]' '[:upper:]')

        if [ -n "$detected_eui" ] && validate_eui "$detected_eui"; then
            echo -e "Detected EUI from SX1302 chip: ${GREEN}$detected_eui${NC}"
            echo ""
            if confirm "Use this EUI?" "y"; then
                GATEWAY_EUI="$detected_eui"
                return 0
            fi
            detected_eui=""
        else
            print_warning "Could not auto-detect EUI from SX1302 chip."
            if [ -n "$chip_output" ]; then
                echo "chip_id output: $chip_output"
            fi
        fi
    else
        print_warning "chip_id tool not found at $CHIP_ID_TOOL"
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

    GATEWAY_EUI=$(echo "$GATEWAY_EUI" | tr '[:lower:]' '[:upper:]')
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
    echo "Paste your API key (it will not be displayed):"
    read -rs CUPS_KEY
    echo ""

    if [ -z "$CUPS_KEY" ]; then
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

    if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        cp /etc/ssl/certs/ca-certificates.crt "$trust_cert"
        print_success "Trust certificate installed (system CA bundle)."
    else
        echo "System CA bundle not found, downloading Let's Encrypt root..."
        curl -sf https://letsencrypt.org/certs/isrgrootx1.pem -o "$trust_cert"
        if [ ! -f "$trust_cert" ] || [ ! -s "$trust_cert" ]; then
            print_error "Error: Could not obtain trust certificate."
            exit 1
        fi
        print_success "Trust certificate downloaded."
    fi
    echo ""
}

step_select_log_location() {
    print_header "Step 6: Select log file location"
    echo "  1) Local directory ($CUPS_DIR/station.log)"
    echo "  2) System log (/var/log/station.log) - requires sudo"
    echo ""
    read -rp "Enter choice [1-2]: " log_choice

    case $log_choice in
        2)
            LOG_FILE="/var/log/station.log"
            print_warning "Note: You will need to create the log file with proper permissions:"
            print_warning "  sudo touch /var/log/station.log"
            print_warning "  sudo chown $USER:$USER /var/log/station.log"
            if confirm "Create log file now with sudo?" "y"; then
                sudo touch /var/log/station.log
                sudo chown "$USER:$USER" /var/log/station.log
                chmod 644 /var/log/station.log
                print_success "Log file created: /var/log/station.log"
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

step_create_credentials() {
    print_header "Step 7: Creating credential files..."

    echo "$CUPS_URI" > "$CUPS_DIR/cups.uri"
    echo "  Created: cups.uri"

    echo "Authorization: Bearer $CUPS_KEY" > "$CUPS_DIR/cups.key"
    echo "  Created: cups.key"

    print_header "Step 8: Generating station.conf..."

    if [ -f "$CUPS_DIR/station.conf.template" ]; then
        sed -e "s|{{GATEWAY_EUI}}|$GATEWAY_EUI|g" \
            -e "s|{{INSTALL_DIR}}|$SCRIPT_DIR|g" \
            -e "s|{{LOG_FILE}}|$LOG_FILE|g" \
            "$CUPS_DIR/station.conf.template" > "$CUPS_DIR/station.conf"
        echo "  Created: station.conf"
    else
        print_warning "Warning: station.conf.template not found. Please configure station.conf manually."
    fi

    print_header "Step 9: Setting file permissions..."
    chmod 600 "$CUPS_DIR/cups.key" 2>/dev/null || true
    chmod 600 "$CUPS_DIR/tc.key" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/cups.uri" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/cups.trust" 2>/dev/null || true
    chmod 644 "$CUPS_DIR/station.conf" 2>/dev/null || true
    echo "  Permissions set."
}

step_setup_service() {
    echo ""
    print_header "Step 10: Gateway startup configuration"
    echo ""

    # Check if service is already running (for later reload/restart)
    local service_was_active=false
    if systemctl is-active --quiet basicstation.service 2>/dev/null; then
        service_was_active=true
    fi

    if ! confirm "Do you want to run the gateway as a systemd service?"; then
        print_summary "manual"
        return 0
    fi

    echo ""
    print_success "Setting up systemd service..."

    local service_file="/etc/systemd/system/basicstation.service"

    sudo tee "$service_file" > /dev/null << EOF
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

    echo "  Created: $service_file"

    sudo systemctl daemon-reload
    sudo systemctl enable basicstation.service
    echo "  Service enabled."

    echo ""
    if [ "$service_was_active" = true ]; then
        print_warning "Service was already running. Restarting with new configuration..."
        sudo systemctl restart basicstation.service
        sleep 2
        if systemctl is-active --quiet basicstation.service; then
            print_success "Service restarted successfully!"
        else
            print_warning "Service may have failed to restart. Check status with:"
            echo "  sudo systemctl status basicstation.service"
            echo "  sudo journalctl -u basicstation.service -f"
        fi
    elif confirm "Do you want to start the service now?" "y"; then
        sudo systemctl start basicstation.service
        sleep 2
        if systemctl is-active --quiet basicstation.service; then
            print_success "Service started successfully!"
        else
            print_warning "Service may have failed to start. Check status with:"
            echo "  sudo systemctl status basicstation.service"
            echo "  sudo journalctl -u basicstation.service -f"
        fi
    else
        echo ""
        echo "To start the service later, run:"
        print_warning "  sudo systemctl start basicstation.service"
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
    echo "  Config dir:  $CUPS_DIR"
    echo "  Log file:    $LOG_FILE"
    echo ""

    if [ "$mode" = "service" ]; then
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
# Main
#######################################

main() {
    print_banner "LoRa Basic Station Setup for TTN"

    step_check_existing_credentials
    step_build_station
    step_select_region
    step_detect_eui
    step_show_registration_instructions
    step_get_cups_key
    step_setup_trust_cert
    step_select_log_location
    step_create_credentials
    step_setup_service
}

main "$@"
