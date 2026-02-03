#!/bin/bash
# Docker entrypoint for cnbhl/basicstation-rpi64
# Validates environment, generates configuration, and starts station
set -euo pipefail

# =============================================================================
# Configuration paths
# =============================================================================
APP_DIR="/app"
BIN_DIR="$APP_DIR/bin"
SCRIPTS_DIR="$APP_DIR/scripts"
TEMPLATES_DIR="$APP_DIR/templates"
CONFIG_DIR="$APP_DIR/config"

STATION_BIN="$BIN_DIR/station"
CHIP_ID_BIN="$BIN_DIR/chip_id"
BOARD_CONF_TEMPLATE="$TEMPLATES_DIR/board.conf.template"
STATION_CONF_TEMPLATE="$TEMPLATES_DIR/station.conf.template"

# =============================================================================
# Helper functions
# =============================================================================
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }

# =============================================================================
# Validate required environment variables
# =============================================================================
[[ -z "${BOARD:-}" ]]       && die "BOARD is required (WM1302, PG1302, LR1302, SX1302_WS, SEMTECH, or custom)"
[[ -z "${REGION:-}" ]]      && die "REGION is required (eu1, nam1, au1)"
[[ -z "${GATEWAY_EUI:-}" ]] && die "GATEWAY_EUI is required (16 hex chars or 'auto')"
[[ -z "${CUPS_KEY:-}" ]]    && die "CUPS_KEY is required (TTN CUPS API key)"

# Validate region
case "$REGION" in
    eu1|nam1|au1) ;;
    *) die "Invalid REGION '$REGION'. Must be eu1, nam1, or au1" ;;
esac

# =============================================================================
# Resolve board GPIO pins
# =============================================================================
if [[ "$BOARD" == "custom" ]]; then
    [[ -z "${SX1302_RESET_GPIO:-}" ]]  && die "SX1302_RESET_GPIO is required for custom board"
    [[ -z "${POWER_EN_GPIO:-}" ]]      && die "POWER_EN_GPIO is required for custom board"
    [[ -z "${SX1261_RESET_GPIO:-}" ]]  && die "SX1261_RESET_GPIO is required for custom board"
    SX1302_RESET_BCM="$SX1302_RESET_GPIO"
    SX1302_POWER_EN_BCM="$POWER_EN_GPIO"
    SX1261_RESET_BCM="$SX1261_RESET_GPIO"
else
    # Look up GPIO pins from board.conf.template
    board_line=$(grep "^${BOARD}:" "$BOARD_CONF_TEMPLATE" 2>/dev/null) || true
    [[ -z "$board_line" ]] && die "Unknown BOARD '$BOARD'. Check board.conf.template for supported boards."

    SX1302_RESET_BCM=$(echo "$board_line" | cut -d: -f3)
    SX1302_POWER_EN_BCM=$(echo "$board_line" | cut -d: -f4)
    SX1261_RESET_BCM=$(echo "$board_line" | cut -d: -f5)
fi

# =============================================================================
# Write board.conf for reset_lgw.sh
# =============================================================================
cat > "$SCRIPTS_DIR/board.conf" <<EOF
BOARD_TYPE="$BOARD"
SX1302_RESET_BCM=$SX1302_RESET_BCM
SX1302_POWER_EN_BCM=$SX1302_POWER_EN_BCM
SX1261_RESET_BCM=$SX1261_RESET_BCM
EOF
info "Board configuration written ($BOARD: reset=$SX1302_RESET_BCM, power=$SX1302_POWER_EN_BCM, sx1261=$SX1261_RESET_BCM)"

# =============================================================================
# Resolve Gateway EUI
# =============================================================================
if [[ "$GATEWAY_EUI" == "auto" ]]; then
    info "Auto-detecting Gateway EUI from SX1302 chip..."
    if [[ ! -x "$CHIP_ID_BIN" ]]; then
        die "chip_id binary not found. Cannot auto-detect EUI."
    fi

    SPI_DEV="${SPI_DEV:-/dev/spidev0.0}"

    # chip_id calls system("./reset_lgw.sh start"), so we must cd to scripts dir
    chip_output=$(cd "$SCRIPTS_DIR" && "$CHIP_ID_BIN" -d "$SPI_DEV" 2>&1) || true
    GATEWAY_EUI=$(printf '%s' "$chip_output" | grep -i "concentrator EUI" | sed 's/.*0x\([0-9a-fA-F]*\).*/\1/' | tr '[:lower:]' '[:upper:]') || true

    if [[ -z "$GATEWAY_EUI" ]] || [[ ${#GATEWAY_EUI} -ne 16 ]]; then
        die "Failed to auto-detect EUI. chip_id output: $chip_output"
    fi
    info "Detected Gateway EUI: $GATEWAY_EUI"
else
    # Validate provided EUI
    GATEWAY_EUI=$(echo "$GATEWAY_EUI" | tr '[:lower:]' '[:upper:]')
    if ! [[ "$GATEWAY_EUI" =~ ^[0-9A-F]{16}$ ]]; then
        die "Invalid GATEWAY_EUI '$GATEWAY_EUI'. Must be 16 hex characters."
    fi
fi

# =============================================================================
# Resolve GPS configuration
# =============================================================================
GPS_DEV="${GPS_DEV:-}"
if [[ -n "$GPS_DEV" && "$GPS_DEV" != "none" ]]; then
    GPS_DEVICE="\"$GPS_DEV\""
    PPS_SOURCE='"gps"'
else
    GPS_DEVICE='""'
    PPS_SOURCE='"fuzzy"'
fi

# =============================================================================
# Resolve other settings
# =============================================================================
ANTENNA_GAIN="${ANTENNA_GAIN:-0}"
LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
SPI_DEV="${SPI_DEV:-/dev/spidev0.0}"

# =============================================================================
# Generate station.conf from template
# =============================================================================
sed -e "s|{{GATEWAY_EUI}}|$GATEWAY_EUI|g" \
    -e "s|{{INSTALL_DIR}}/examples/corecell/cups-ttn/rinit.sh|/app/scripts/rinit.sh|g" \
    -e "s|{{GPS_DEVICE}}|$GPS_DEVICE|g" \
    -e "s|{{PPS_SOURCE}}|$PPS_SOURCE|g" \
    -e "s|{{ANTENNA_GAIN}}|$ANTENNA_GAIN|g" \
    -e "s|{{LOG_FILE}}|/dev/stderr|g" \
    -e "s|/dev/spidev0.0|$SPI_DEV|g" \
    -e "s|\"log_level\": \"DEBUG\"|\"log_level\": \"$LOG_LEVEL\"|g" \
    -e "s|\"log_size\":  10000000|\"log_size\":  0|g" \
    -e "s|\"log_rotate\":  3|\"log_rotate\":  0|g" \
    "$STATION_CONF_TEMPLATE" > "$CONFIG_DIR/station.conf"

info "station.conf generated"

# =============================================================================
# Write CUPS credentials
# =============================================================================
CUPS_URI="https://${REGION}.cloud.thethings.network:443"

echo "$CUPS_URI" > "$CONFIG_DIR/cups.uri"
echo "Authorization: Bearer $CUPS_KEY" > "$CONFIG_DIR/cups.key"
chmod 600 "$CONFIG_DIR/cups.key"

# Trust certificate
if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
    cp /etc/ssl/certs/ca-certificates.crt "$CONFIG_DIR/cups.trust"
else
    die "CA certificates not found. Cannot establish CUPS TLS trust."
fi

info "CUPS credentials written"

# =============================================================================
# Print summary
# =============================================================================
echo ""
echo "========================================="
echo " Basic Station Configuration"
echo "========================================="
echo "  Board:        $BOARD"
echo "  Region:       $REGION ($CUPS_URI)"
echo "  Gateway EUI:  $GATEWAY_EUI"
echo "  GPS:          ${GPS_DEV:-disabled}"
echo "  Antenna Gain: ${ANTENNA_GAIN} dBi"
echo "  SPI Device:   $SPI_DEV"
echo "  Log Level:    $LOG_LEVEL"
echo "========================================="
echo ""

# =============================================================================
# Start station
# =============================================================================
# Remove stale PID file from previous container run (station checks this on startup)
rm -f "$CONFIG_DIR/station.pid"

info "Starting Basic Station..."
exec "$STATION_BIN" -h "$CONFIG_DIR"
