#!/bin/bash
#
# LoRa Basic Station Setup Script for Raspberry Pi 5 with TTN
# This script configures the gateway credentials for The Things Network
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CUPS_DIR="$SCRIPT_DIR/examples/corecell/cups-ttn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} LoRa Basic Station Setup for TTN${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if credentials already exist
if [ -f "$CUPS_DIR/cups.key" ]; then
    echo -e "${YELLOW}Warning: Credentials already exist in $CUPS_DIR${NC}"
    read -p "Do you want to overwrite them? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Step 1: Build the station binary
echo -e "${GREEN}Step 1: Build the station binary${NC}"
echo ""
echo "This step will compile the Basic Station software for the SX1302 Corecell platform."
echo ""
echo "The build process will:"
echo "  - Download and compile dependencies (mbedTLS, libloragw)"
echo "  - Compile the Basic Station source code"
echo "  - Create the executable at: build-corecell-std/bin/station"
echo ""

# Check if binary already exists
if [ -f "$SCRIPT_DIR/build-corecell-std/bin/station" ]; then
    echo -e "${YELLOW}Note: A station binary already exists.${NC}"
    read -p "Do you want to rebuild? (y/N): " rebuild
    if [ "$rebuild" != "y" ] && [ "$rebuild" != "Y" ]; then
        echo -e "${GREEN}Skipping build, using existing binary.${NC}"
        echo ""
    else
        echo ""
        read -p "Start the build process now? (Y/n): " start_build
        if [ "$start_build" = "n" ] || [ "$start_build" = "N" ]; then
            echo "Setup cancelled. You can build manually with:"
            echo "  make platform=corecell variant=std"
            exit 0
        fi
        echo ""
        echo -e "${YELLOW}Building... This may take several minutes on first build.${NC}"
        echo ""
        cd "$SCRIPT_DIR"
        if make platform=corecell variant=std; then
            echo ""
            echo -e "${GREEN}Build completed successfully.${NC}"
        else
            echo -e "${RED}Build failed. Please check the error messages above.${NC}"
            echo "You can try building manually with: make platform=corecell variant=std"
            exit 1
        fi
    fi
else
    read -p "Start the build process now? (Y/n): " start_build
    if [ "$start_build" = "n" ] || [ "$start_build" = "N" ]; then
        echo "Setup cancelled. You can build manually with:"
        echo "  make platform=corecell variant=std"
        exit 0
    fi
    echo ""
    echo -e "${YELLOW}Building... This may take several minutes on first build.${NC}"
    echo ""
    cd "$SCRIPT_DIR"
    if make platform=corecell variant=std; then
        echo ""
        echo -e "${GREEN}Build completed successfully.${NC}"
    else
        echo -e "${RED}Build failed. Please check the error messages above.${NC}"
        echo "You can try building manually with: make platform=corecell variant=std"
        exit 1
    fi
fi
echo ""

# Step 2: Select TTN Region
echo -e "${GREEN}Step 2: Select your TTN region${NC}"
echo "  1) EU1  - Europe (eu1.cloud.thethings.network)"
echo "  2) NAM1 - North America (nam1.cloud.thethings.network)"
echo "  3) AU1  - Australia (au1.cloud.thethings.network)"
echo ""
read -p "Enter region number [1-3]: " region_choice

case $region_choice in
    1) TTN_REGION="eu1" ;;
    2) TTN_REGION="nam1" ;;
    3) TTN_REGION="au1" ;;
    *)
        echo -e "${RED}Invalid selection. Defaulting to EU1.${NC}"
        TTN_REGION="eu1"
        ;;
esac

CUPS_URI="https://${TTN_REGION}.cloud.thethings.network:443"
echo -e "Selected: ${GREEN}$CUPS_URI${NC}"
echo ""

# Step 3: Gateway EUI (auto-detect from SX1302 chip)
echo -e "${GREEN}Step 3: Detecting Gateway EUI from SX1302 chip...${NC}"
echo ""

CHIP_ID_TOOL="$SCRIPT_DIR/tools/chip_id/chip_id"
CHIP_ID_DIR="$SCRIPT_DIR/tools/chip_id"
DETECTED_EUI=""

if [ -x "$CHIP_ID_TOOL" ]; then
    # Run chip_id to get the concentrator EUI
    cd "$CHIP_ID_DIR"
    CHIP_OUTPUT=$(sudo ./chip_id -d /dev/spidev0.0 2>&1) || true
    cd "$SCRIPT_DIR"

    # Extract EUI from output (format: "concentrator EUI: 0xAABBCCDDEEFF0011")
    DETECTED_EUI=$(echo "$CHIP_OUTPUT" | grep -i "concentrator EUI" | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' | tr '[:lower:]' '[:upper:]')

    if [ -n "$DETECTED_EUI" ] && [[ "$DETECTED_EUI" =~ ^[0-9A-F]{16}$ ]]; then
        echo -e "Detected EUI from SX1302 chip: ${GREEN}$DETECTED_EUI${NC}"
        echo ""
        read -p "Use this EUI? (Y/n): " use_detected
        if [ "$use_detected" = "n" ] || [ "$use_detected" = "N" ]; then
            DETECTED_EUI=""
        fi
    else
        echo -e "${YELLOW}Could not auto-detect EUI from SX1302 chip.${NC}"
        DETECTED_EUI=""
    fi
else
    echo -e "${YELLOW}chip_id tool not found at $CHIP_ID_TOOL${NC}"
    echo "You can build it from sx1302_hal or enter the EUI manually."
fi

if [ -n "$DETECTED_EUI" ]; then
    GATEWAY_EUI="$DETECTED_EUI"
else
    echo ""
    echo "Please enter your Gateway EUI manually."
    echo "This is a 16-character hex string (e.g., AABBCCDDEEFF0011)"
    echo "You can find this in your TTN Console under Gateway settings."
    echo ""
    read -p "Gateway EUI: " GATEWAY_EUI

    # Validate Gateway EUI format
    if ! [[ "$GATEWAY_EUI" =~ ^[0-9A-Fa-f]{16}$ ]]; then
        echo -e "${RED}Warning: Gateway EUI should be 16 hex characters.${NC}"
        read -p "Continue anyway? (y/N): " continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            echo "Setup cancelled."
            exit 1
        fi
    fi

    # Convert to uppercase
    GATEWAY_EUI=$(echo "$GATEWAY_EUI" | tr '[:lower:]' '[:upper:]')
fi

echo -e "Gateway EUI: ${GREEN}$GATEWAY_EUI${NC}"
echo ""

# Step 4: CUPS API Key
echo -e "${GREEN}Step 4: Enter your CUPS API Key${NC}"
echo "Generate this in TTN Console: Gateway > API Keys > Add API Key"
echo "Required rights: 'Link as Gateway to a Gateway Server for traffic exchange, i.e. write uplink and read downlink'"
echo ""
echo "Paste your API key (it will not be displayed):"
read -s CUPS_KEY
echo ""

if [ -z "$CUPS_KEY" ]; then
    echo -e "${RED}Error: API key cannot be empty.${NC}"
    exit 1
fi

echo -e "${GREEN}API key received.${NC}"
echo ""

# Step 5: Download TTN Trust Certificate
echo -e "${GREEN}Step 5: Downloading TTN trust certificate...${NC}"

# TTN uses Let's Encrypt certificates, we need the ISRG Root X1
TRUST_CERT="$CUPS_DIR/cups.trust"
curl -sf https://letsencrypt.org/certs/isrgrootx1.pem -o "$TRUST_CERT"

if [ ! -f "$TRUST_CERT" ] || [ ! -s "$TRUST_CERT" ]; then
    echo -e "${YELLOW}Could not download certificate. Using system CA bundle...${NC}"
    # Fallback to system CA certificates
    if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        cp /etc/ssl/certs/ca-certificates.crt "$TRUST_CERT"
    else
        echo -e "${RED}Error: Could not obtain trust certificate.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}Trust certificate saved.${NC}"
echo ""

# Step 6: Select log file location
echo -e "${GREEN}Step 6: Select log file location${NC}"
echo "  1) Local directory ($CUPS_DIR/station.log)"
echo "  2) System log (/var/log/station.log) - requires sudo"
echo ""
read -p "Enter choice [1-2]: " log_choice

case $log_choice in
    2)
        LOG_FILE="/var/log/station.log"
        echo -e "${YELLOW}Note: You will need to create the log file with proper permissions:${NC}"
        echo -e "${YELLOW}  sudo touch /var/log/station.log${NC}"
        echo -e "${YELLOW}  sudo chown $USER:$USER /var/log/station.log${NC}"
        read -p "Create log file now with sudo? (Y/n): " create_log
        if [ "$create_log" != "n" ] && [ "$create_log" != "N" ]; then
            sudo touch /var/log/station.log
            sudo chown $USER:$USER /var/log/station.log
            chmod 644 /var/log/station.log
            echo -e "${GREEN}Log file created: /var/log/station.log${NC}"
        fi
        ;;
    *)
        LOG_FILE="$CUPS_DIR/station.log"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
        echo -e "${GREEN}Log file will be: $LOG_FILE${NC}"
        ;;
esac
echo ""

# Step 7: Create credential files
echo -e "${GREEN}Step 7: Creating credential files...${NC}"

# Create cups.uri
echo "$CUPS_URI" > "$CUPS_DIR/cups.uri"
echo "  Created: cups.uri"

# Create cups.key with proper format
# TTN expects: Authorization: <key>
echo "Authorization: Bearer $CUPS_KEY" > "$CUPS_DIR/cups.key"
echo "  Created: cups.key"

# Note: tc.* files are not created here - CUPS will populate them automatically
# Creating empty tc.* files causes the station to fail with "Malformed URI" error

# Step 8: Generate station.conf from template
echo -e "${GREEN}Step 8: Generating station.conf...${NC}"

if [ -f "$CUPS_DIR/station.conf.template" ]; then
    sed -e "s|{{GATEWAY_EUI}}|$GATEWAY_EUI|g" \
        -e "s|{{INSTALL_DIR}}|$SCRIPT_DIR|g" \
        -e "s|{{LOG_FILE}}|$LOG_FILE|g" \
        "$CUPS_DIR/station.conf.template" > "$CUPS_DIR/station.conf"
    echo "  Created: station.conf"
else
    echo -e "${YELLOW}Warning: station.conf.template not found. Please configure station.conf manually.${NC}"
fi

# Step 9: Set permissions
echo -e "${GREEN}Step 9: Setting file permissions...${NC}"
chmod 600 "$CUPS_DIR/cups.key" 2>/dev/null || true
chmod 600 "$CUPS_DIR/tc.key" 2>/dev/null || true
chmod 644 "$CUPS_DIR/cups.uri" 2>/dev/null || true
chmod 644 "$CUPS_DIR/cups.trust" 2>/dev/null || true
chmod 644 "$CUPS_DIR/station.conf" 2>/dev/null || true
echo "  Permissions set."

# Step 10: Service setup
echo ""
echo -e "${GREEN}Step 10: Gateway startup configuration${NC}"
echo ""
read -p "Do you want to run the gateway as a systemd service? (y/N): " setup_service

if [ "$setup_service" = "y" ] || [ "$setup_service" = "Y" ]; then
    echo ""
    echo -e "${GREEN}Setting up systemd service...${NC}"

    SERVICE_FILE="/etc/systemd/system/basicstation.service"

    # Create the service file
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=LoRa Basics Station (SX1302/Corecell) for TTN (CUPS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR

ExecStart=$SCRIPT_DIR/build-corecell-std/bin/station --home $CUPS_DIR

Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Logs
StandardOutput=journal
StandardError=journal
SyslogIdentifier=basicstation

[Install]
WantedBy=multi-user.target
EOF

    echo "  Created: $SERVICE_FILE"

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable basicstation.service
    echo "  Service enabled."

    echo ""
    read -p "Do you want to start the service now? (Y/n): " start_now
    if [ "$start_now" != "n" ] && [ "$start_now" != "N" ]; then
        sudo systemctl start basicstation.service
        sleep 2
        if systemctl is-active --quiet basicstation.service; then
            echo -e "${GREEN}Service started successfully!${NC}"
        else
            echo -e "${YELLOW}Service may have failed to start. Check status with:${NC}"
            echo "  sudo systemctl status basicstation.service"
            echo "  sudo journalctl -u basicstation.service -f"
        fi
    else
        echo ""
        echo "To start the service later, run:"
        echo -e "  ${YELLOW}sudo systemctl start basicstation.service${NC}"
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Your gateway is configured with:"
    echo "  Region:      $TTN_REGION"
    echo "  Gateway EUI: $GATEWAY_EUI"
    echo "  Config dir:  $CUPS_DIR"
    echo "  Log file:    $LOG_FILE"
    echo ""
    echo "Useful commands:"
    echo -e "  ${YELLOW}sudo systemctl status basicstation.service${NC}  - Check service status"
    echo -e "  ${YELLOW}sudo systemctl stop basicstation.service${NC}   - Stop the service"
    echo -e "  ${YELLOW}sudo systemctl restart basicstation.service${NC} - Restart the service"
    echo -e "  ${YELLOW}sudo journalctl -u basicstation.service -f${NC}  - View live logs"
else
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Your gateway is configured with:"
    echo "  Region:      $TTN_REGION"
    echo "  Gateway EUI: $GATEWAY_EUI"
    echo "  Config dir:  $CUPS_DIR"
    echo "  Log file:    $LOG_FILE"
    echo ""
    echo "To start the gateway manually:"
    echo -e "  ${YELLOW}cd $SCRIPT_DIR/examples/corecell${NC}"
    echo -e "  ${YELLOW}./start-station.sh -l ./cups-ttn${NC}"
    echo ""
    echo -e "${YELLOW}Note: You may need to run start-station.sh with sudo for GPIO access.${NC}"
fi
