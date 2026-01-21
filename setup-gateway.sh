#!/bin/bash
#
# LoRa Basic Station Setup Script for Raspberry Pi with TTN
# This script configures the gateway credentials for The Things Network
#
# Security: This script handles sensitive credentials (API keys).
# Files containing secrets are created with restricted permissions.
#

set -euo pipefail

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
readonly RESET_LGW_SCRIPT="$CUPS_DIR/reset_lgw.sh"

# Global state variables (set during setup)
TTN_REGION=""
CUPS_URI=""
GATEWAY_EUI=""
CUPS_KEY=""
LOG_FILE=""

#######################################
# Output Functions
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

#######################################
# Input Functions
#######################################

# Prompt for yes/no confirmation
# Usage: confirm "Question?" && do_something
# Args: $1 = prompt, $2 = default (y/n, default: n)
# Returns: 0 (true) for yes, 1 (false) for no
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        read -rp "$prompt (Y/n): " response
        [[ "$response" != "n" && "$response" != "N" ]]
    else
        read -rp "$prompt (y/N): " response
        [[ "$response" == "y" || "$response" == "Y" ]]
    fi
}

# Read a secret value without echoing
# Args: $1 = variable name to set, $2 = prompt
# Returns: 0 on success, 1 if empty
read_secret() {
    local -n ref=$1
    local prompt="$2"

    echo "$prompt"
    read -rs ref
    echo ""

    [[ -n "$ref" ]]
}

# Read input with validation
# Args: $1 = variable name, $2 = prompt, $3 = validation function
# Returns: 0 on success
read_validated() {
    local -n ref=$1
    local prompt="$2"
    local validator="$3"

    read -rp "$prompt" ref

    if ! "$validator" "$ref"; then
        return 1
    fi
    return 0
}

#######################################
# Validation Functions
#######################################

# Validate 16-character hex string (Gateway EUI)
validate_eui() {
    local eui="$1"
    [[ "$eui" =~ ^[0-9A-Fa-f]{16}$ ]]
}

# Validate string is not empty
validate_not_empty() {
    local value="$1"
    [[ -n "$value" ]]
}

# Sanitize string for use in sed replacement
# Escapes special characters: \ / & and newlines
sanitize_for_sed() {
    local input="$1"
    printf '%s' "$input" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\/' -e '$s/\\$//'
}

#######################################
# File Operations (Security-focused)
#######################################

# Write content to file with secure permissions (atomic)
# Args: $1 = file path, $2 = content, $3 = permissions (default: 600)
write_file_secure() {
    local file_path="$1"
    local content="$2"
    local permissions="${3:-600}"
    local temp_file

    temp_file=$(mktemp)

    # Set restrictive permissions before writing content
    chmod "$permissions" "$temp_file"

    # Write content using printf to avoid process listing
    printf '%s\n' "$content" > "$temp_file"

    # Atomic move to final location
    mv "$temp_file" "$file_path"
}

# Write secret to file (extra secure - no echo)
# Args: $1 = file path, $2 = content
write_secret_file() {
    local file_path="$1"
    local content="$2"

    # Create file with restricted permissions first
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"

    # Use here-string to avoid secret in process listing
    cat > "$temp_file" <<< "$content"

    mv "$temp_file" "$file_path"
}

# Copy file with permission preservation
# Args: $1 = source, $2 = destination, $3 = permissions (optional)
copy_file() {
    local src="$1"
    local dst="$2"
    local permissions="${3:-}"

    if [[ ! -f "$src" ]]; then
        print_error "Source file not found: $src"
        return 1
    fi

    cp "$src" "$dst"

    if [[ -n "$permissions" ]]; then
        chmod "$permissions" "$dst"
    fi
}

#######################################
# System Check Functions
#######################################

# Check if a command exists
# Args: $1 = command name
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if file exists and is readable
# Args: $1 = file path
file_exists() {
    [[ -f "$1" && -r "$1" ]]
}

# Check if file exists and is executable
# Args: $1 = file path
file_executable() {
    [[ -x "$1" ]]
}

# Check if directory exists
# Args: $1 = directory path
dir_exists() {
    [[ -d "$1" ]]
}

# Check if SPI is available
check_spi_available() {
    if [[ ! -e /dev/spidev0.0 ]]; then
        print_error "SPI device not found at /dev/spidev0.0"
        echo "Please enable SPI using: sudo raspi-config"
        echo "Navigate to: Interface Options > SPI > Enable"
        return 1
    fi
    return 0
}

#######################################
# Service Management Functions
#######################################

# Check if systemd service is active
# Args: $1 = service name
service_is_active() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Check if systemd service is enabled
# Args: $1 = service name
service_is_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

# Start a systemd service with status check
# Args: $1 = service name
# Returns: 0 on success, 1 on failure
service_start() {
    local service="$1"

    sudo systemctl start "$service"
    sleep 2

    if service_is_active "$service"; then
        print_success "Service $service started successfully!"
        return 0
    else
        print_warning "Service $service may have failed to start."
        echo "  Check status: sudo systemctl status $service"
        echo "  View logs: sudo journalctl -u $service -f"
        return 1
    fi
}

# Restart a systemd service with status check
# Args: $1 = service name
service_restart() {
    local service="$1"

    sudo systemctl restart "$service"
    sleep 2

    if service_is_active "$service"; then
        print_success "Service $service restarted successfully!"
        return 0
    else
        print_warning "Service $service may have failed to restart."
        echo "  Check status: sudo systemctl status $service"
        echo "  View logs: sudo journalctl -u $service -f"
        return 1
    fi
}

#######################################
# Template Processing
#######################################

# Process a template file with variable substitution
# Args: $1 = template file, $2 = output file, $3... = "KEY=VALUE" pairs
process_template() {
    local template="$1"
    local output="$2"
    shift 2

    if [[ ! -f "$template" ]]; then
        print_error "Template not found: $template"
        return 1
    fi

    local content
    content=$(cat "$template")

    # Process each KEY=VALUE pair
    for pair in "$@"; do
        local key="${pair%%=*}"
        local value="${pair#*=}"
        local safe_value
        safe_value=$(sanitize_for_sed "$value")
        content=$(printf '%s' "$content" | sed "s|{{${key}}}|${safe_value}|g")
    done

    printf '%s\n' "$content" > "$output"
}

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
        # chip_id requires reset_lgw.sh in the same directory
        local chip_id_dir
        chip_id_dir="$(dirname "$CHIP_ID_TOOL")"

        if [[ ! -f "$chip_id_dir/reset_lgw.sh" ]] && file_exists "$RESET_LGW_SCRIPT"; then
            copy_file "$RESET_LGW_SCRIPT" "$chip_id_dir/reset_lgw.sh" "755"
        fi

        local chip_output
        chip_output=$(cd "$chip_id_dir" && sudo ./chip_id -d /dev/spidev0.0 2>&1) || true

        detected_eui=$(printf '%s' "$chip_output" | grep -i "concentrator EUI" | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' | tr '[:lower:]' '[:upper:]')

        if [[ -n "$detected_eui" ]] && validate_eui "$detected_eui"; then
            echo -e "Detected EUI from SX1302 chip: ${GREEN}$detected_eui${NC}"
            echo ""
            if confirm "Use this EUI?" "y"; then
                GATEWAY_EUI="$detected_eui"
                return 0
            fi
            detected_eui=""
        else
            print_warning "Could not auto-detect EUI from SX1302 chip."
            if [[ -n "$chip_output" ]]; then
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

step_create_credentials() {
    print_header "Step 7: Creating credential files..."

    # Write URI file (not sensitive)
    write_file_secure "$CUPS_DIR/cups.uri" "$CUPS_URI" "644"
    echo "  Created: cups.uri"

    # Write API key file (sensitive - use secure write)
    write_secret_file "$CUPS_DIR/cups.key" "Authorization: Bearer $CUPS_KEY"
    echo "  Created: cups.key (permissions: 600)"

    print_header "Step 8: Generating station.conf..."

    local template="$CUPS_DIR/station.conf.template"
    if file_exists "$template"; then
        process_template "$template" "$CUPS_DIR/station.conf" \
            "GATEWAY_EUI=$GATEWAY_EUI" \
            "INSTALL_DIR=$SCRIPT_DIR" \
            "LOG_FILE=$LOG_FILE"
        chmod 644 "$CUPS_DIR/station.conf"
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
    echo "  Config dir:  $CUPS_DIR"
    echo "  Log file:    $LOG_FILE"
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
