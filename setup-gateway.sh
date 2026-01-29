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
BUILD_DIR="$SCRIPT_DIR/build-corecell-std"
STATION_BINARY="$BUILD_DIR/bin/station"
readonly CHIP_ID_DIR="$SCRIPT_DIR/tools/chip_id"
readonly CHIP_ID_SOURCE="$CHIP_ID_DIR/chip_id.c"
readonly CHIP_ID_LOG_STUB="$CHIP_ID_DIR/log_stub.c"
CHIP_ID_TOOL="$BUILD_DIR/bin/chip_id"
readonly RESET_LGW_SCRIPT="$CUPS_DIR/reset_lgw.sh"
readonly BOARD_CONF="$CUPS_DIR/board.conf"
readonly BOARD_CONF_TEMPLATE="$CUPS_DIR/board.conf.template"

#######################################
# Global State Variables
#######################################
TTN_REGION=""
CUPS_URI=""
GATEWAY_EUI=""
CUPS_KEY=""
LOG_FILE=""
GPS_DEVICE=""
USE_GPSD="serial"
MODE="setup"
SKIP_DEPS=false
SKIP_GPS=false

# Board configuration (set by step_select_board)
BOARD_TYPE=""
SX1302_RESET_BCM=""
SX1302_POWER_EN_BCM=""

#######################################
# Non-Interactive Mode Variables
#######################################
NON_INTERACTIVE=false
FORCE_OVERWRITE=false

# CLI-provided values (empty = not set, use interactive)
CLI_BOARD=""
CLI_REGION=""
CLI_EUI=""
CLI_CUPS_KEY=""
CLI_CUPS_KEY_FILE=""
CLI_LOG_FILE=""
CLI_GPS=""
CLI_GPS_MODE=""
CLI_SERVICE=""  # "yes", "no", or ""
CLI_SKIP_BUILD=false

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
    echo "General Options:"
    echo "  -h, --help       Show this help message and exit"
    echo "  -u, --uninstall  Remove installed service, credentials, and logs"
    echo "  -v, --verbose    Enable verbose (debug) logging"
    echo "  --skip-deps      Skip dependency checks (advanced users only)"
    echo "  --skip-gps       Skip GPS auto-detection (manual entry or disable)"
    echo ""
    echo "Non-Interactive Mode:"
    echo "  -y, --non-interactive  Enable non-interactive mode (required for automation)"
    echo "  --force                Overwrite existing credentials without prompting"
    echo "  --board <type>         Board type: WM1302, PG1302, LR1302, SX1302_WS, SEMTECH"
    echo "  --region <code>        TTN region: eu1, nam1, au1"
    echo "  --eui <hex|auto>       Gateway EUI (16 hex chars) or 'auto' for detection"
    echo "  --cups-key <key>       CUPS API key"
    echo "  --cups-key-file <path> Read CUPS key from file (alternative to --cups-key)"
    echo "  --log-file <path>      Station log file path"
    echo "  --gps <device|none>    GPS device path or 'none' to disable"
    echo "  --gps-mode <mode>      GPS communication mode: serial (default) or gpsd"
    echo "  --service              Enable systemd service setup"
    echo "  --no-service           Disable systemd service setup"
    echo "  --skip-build           Skip build if binary exists"
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
    echo "  Interactive mode:"
    echo "    $0                     Run setup wizard"
    echo "    $0 --uninstall         Remove installation"
    echo "    $0 -v                  Run setup with debug logging"
    echo "    $0 --skip-gps          Skip GPS port scanning"
    echo ""
    echo "  Non-interactive mode:"
    echo "    $0 -y --board WM1302 --region eu1 --eui auto \\"
    echo "       --cups-key \"NNSXS.xxx...\" --service"
    echo ""
    echo "    $0 --non-interactive --force --board PG1302 --region nam1 \\"
    echo "       --eui AABBCCDDEEFF0011 --cups-key-file /etc/ttn/cups.key \\"
    echo "       --log-file /var/log/station.log --gps /dev/ttyAMA0 --service"
    echo ""
    echo "    $0 --uninstall -y      Uninstall without prompts"
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
            # Non-interactive mode flags
            -y|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --board)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --board requires a value"
                    exit 1
                fi
                CLI_BOARD="$2"
                shift 2
                ;;
            --region)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --region requires a value"
                    exit 1
                fi
                CLI_REGION="$2"
                shift 2
                ;;
            --eui)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --eui requires a value"
                    exit 1
                fi
                CLI_EUI="$2"
                shift 2
                ;;
            --cups-key)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --cups-key requires a value"
                    exit 1
                fi
                CLI_CUPS_KEY="$2"
                shift 2
                ;;
            --cups-key-file)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --cups-key-file requires a value"
                    exit 1
                fi
                CLI_CUPS_KEY_FILE="$2"
                shift 2
                ;;
            --log-file)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --log-file requires a value"
                    exit 1
                fi
                CLI_LOG_FILE="$2"
                shift 2
                ;;
            --gps)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --gps requires a value"
                    exit 1
                fi
                CLI_GPS="$2"
                shift 2
                ;;
            --gps-mode)
                if [[ -z "${2:-}" ]]; then
                    print_error "Error: --gps-mode requires a value"
                    exit 1
                fi
                if [[ "$2" != "serial" && "$2" != "gpsd" ]]; then
                    print_error "Error: --gps-mode must be 'serial' or 'gpsd'"
                    exit 1
                fi
                CLI_GPS_MODE="$2"
                shift 2
                ;;
            --service)
                CLI_SERVICE="yes"
                shift
                ;;
            --no-service)
                CLI_SERVICE="no"
                shift
                ;;
            --skip-build)
                CLI_SKIP_BUILD=true
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
# Non-Interactive Validation
#######################################
validate_non_interactive_args() {
    local errors=()

    # Board validation
    if [[ -z "$CLI_BOARD" ]]; then
        errors+=("--board is required")
    elif ! validate_board_type "$CLI_BOARD"; then
        errors+=("Invalid board type: $CLI_BOARD (use: WM1302, PG1302, LR1302, SX1302_WS, SEMTECH)")
    fi

    # Region validation
    if [[ -z "$CLI_REGION" ]]; then
        errors+=("--region is required")
    elif ! validate_region "$CLI_REGION"; then
        errors+=("Invalid region: $CLI_REGION (use: eu1, nam1, au1)")
    fi

    # EUI validation
    if [[ -z "$CLI_EUI" ]]; then
        errors+=("--eui is required")
    elif [[ "$CLI_EUI" != "auto" ]] && ! validate_eui "$CLI_EUI"; then
        errors+=("Invalid EUI: $CLI_EUI (must be 16 hex chars or 'auto')")
    fi

    # CUPS key validation
    if [[ -z "$CLI_CUPS_KEY" && -z "$CLI_CUPS_KEY_FILE" ]]; then
        errors+=("--cups-key or --cups-key-file is required")
    fi

    # If cups-key-file provided, validate it exists and read the key
    if [[ -n "$CLI_CUPS_KEY_FILE" ]]; then
        if [[ ! -f "$CLI_CUPS_KEY_FILE" ]]; then
            errors+=("CUPS key file not found: $CLI_CUPS_KEY_FILE")
        elif [[ ! -r "$CLI_CUPS_KEY_FILE" ]]; then
            errors+=("CUPS key file not readable: $CLI_CUPS_KEY_FILE")
        else
            # Read the key from file
            CLI_CUPS_KEY=$(cat "$CLI_CUPS_KEY_FILE")
            if [[ -z "$CLI_CUPS_KEY" ]]; then
                errors+=("CUPS key file is empty: $CLI_CUPS_KEY_FILE")
            fi
        fi
    fi

    # Service validation - must specify either --service or --no-service in non-interactive mode
    if [[ -z "$CLI_SERVICE" ]]; then
        errors+=("--service or --no-service is required")
    fi

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        print_error "Missing or invalid arguments for non-interactive mode:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "See '$0 --help' for usage information."
        exit 1
    fi
}

#######################################
# Main
#######################################
main() {
    parse_args "$@"

    # Initialize logging (logs to $SCRIPT_DIR/setup.log)
    init_logging "$SCRIPT_DIR/setup.log"
    log_info "Starting setup-gateway.sh in $MODE mode"

    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_info "Running in non-interactive mode"
        # Validate required arguments for non-interactive setup mode
        if [[ "$MODE" == "setup" ]]; then
            validate_non_interactive_args
        fi
    fi

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
