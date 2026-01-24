#!/bin/bash
#
# LoRa Basic Station Setup Script for Raspberry Pi with TTN
# This script configures the gateway credentials for The Things Network
#
# Security: This script handles sensitive credentials (API keys).
# Files containing secrets are created with restricted permissions.
#
# Usage:
#   ./setup-gateway.sh              Run setup wizard
#   ./setup-gateway.sh --uninstall  Remove installation
#   ./setup-gateway.sh --help       Show help
#

set -euo pipefail

#######################################
# Script Location and Paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly CUPS_DIR="$SCRIPT_DIR/examples/corecell/cups-ttn"
readonly BUILD_DIR="$SCRIPT_DIR/build-corecell-std"
readonly STATION_BINARY="$BUILD_DIR/bin/station"
readonly CHIP_ID_DIR="$SCRIPT_DIR/tools/chip_id"
readonly CHIP_ID_SOURCE="$CHIP_ID_DIR/chip_id.c"
readonly CHIP_ID_LOG_STUB="$CHIP_ID_DIR/log_stub.c"
readonly CHIP_ID_TOOL="$BUILD_DIR/bin/chip_id"
readonly RESET_LGW_SCRIPT="$CUPS_DIR/reset_lgw.sh"

#######################################
# Global State Variables
#######################################
TTN_REGION=""
CUPS_URI=""
GATEWAY_EUI=""
CUPS_KEY=""
LOG_FILE=""
GPS_DEVICE=""
MODE="setup"
SKIP_DEPS=false
SKIP_GPS=false

#######################################
# Source Library Files
#######################################
source_lib() {
    local lib_file="$1"
    if [[ ! -f "$lib_file" ]]; then
        echo "Error: Library file not found: $lib_file" >&2
        echo "Please ensure the lib/ directory is intact." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$lib_file"
}

source_lib "$LIB_DIR/common.sh"
source_lib "$LIB_DIR/validation.sh"
source_lib "$LIB_DIR/file_ops.sh"
source_lib "$LIB_DIR/service.sh"
source_lib "$LIB_DIR/gps.sh"
source_lib "$LIB_DIR/setup.sh"
source_lib "$LIB_DIR/uninstall.sh"

#######################################
# Usage / Help
#######################################
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "LoRa Basic Station Setup Script for Raspberry Pi with TTN"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -u, --uninstall  Remove installed service, credentials, and logs"
    echo "  -v, --verbose    Enable verbose (debug) logging"
    echo "  --skip-deps      Skip dependency checks (advanced users only)"
    echo "  --skip-gps       Skip GPS auto-detection (manual entry or disable)"
    echo ""
    echo "Without options, runs the interactive setup wizard."
    echo ""
    echo "Logs are written to: \$SCRIPT_DIR/setup.log"
    echo ""
    echo "Notes:"
    echo "  GPS detection requires sudo and scans serial ports (may take 30-60 seconds)."
    echo "  Use --skip-gps to bypass scanning if no GPS module is connected."
    echo ""
    echo "Examples:"
    echo "  $0               Run setup wizard"
    echo "  $0 --uninstall   Remove installation"
    echo "  $0 -v            Run setup with debug logging"
    echo "  $0 --skip-gps    Skip GPS port scanning"
}

#######################################
# Argument Parsing
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -u|--uninstall)
                MODE="uninstall"
                shift
                ;;
            -v|--verbose)
                CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --skip-gps)
                SKIP_GPS=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                print_usage
                exit 1
                ;;
        esac
    done
}

#######################################
# Main
#######################################
main() {
    parse_args "$@"

    # Initialize logging (logs to $SCRIPT_DIR/setup.log)
    init_logging "$SCRIPT_DIR/setup.log"
    log_info "Starting setup-gateway.sh in $MODE mode"

    case "$MODE" in
        setup)
            run_setup
            ;;
        uninstall)
            run_uninstall
            ;;
        *)
            print_error "Unknown mode: $MODE"
            exit 1
            ;;
    esac

    log_info "Script completed successfully"
}

main "$@"
