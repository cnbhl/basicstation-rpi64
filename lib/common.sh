#!/bin/bash
#
# common.sh - Common output, input, and logging functions
#
# This file is sourced by setup-gateway.sh
#

#######################################
# Constants - Colors
#######################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

#######################################
# Logging Configuration
#######################################

# Setup log file path (set by init_logging, distinct from station runtime log)
SETUP_LOG_FILE=""

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Current log level (default: INFO)
CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

#######################################
# Logging Functions
#######################################

# Initialize logging system
# Args: $1 = log file path (optional, defaults to /tmp/basicstation-setup.log)
# Creates log file with timestamp header
init_logging() {
    SETUP_LOG_FILE="${1:-/tmp/basicstation-setup.log}"

    # Create or truncate log file with header
    {
        echo "========================================"
        echo "Basic Station Setup Log"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "User: ${USER:-unknown}"
        echo "Host: $(hostname 2>/dev/null || echo 'unknown')"
        echo "========================================"
        echo ""
    } > "$SETUP_LOG_FILE" 2>/dev/null || {
        # Fallback if we can't write to the specified location
        SETUP_LOG_FILE="/tmp/basicstation-setup-$$.log"
        {
            echo "========================================"
            echo "Basic Station Setup Log"
            echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "========================================"
            echo ""
        } > "$SETUP_LOG_FILE"
    }

    # Set up trap to log script exit
    trap 'log_info "Setup script exited with code: $?"' EXIT
}

# Internal: Write to log file with timestamp
# Args: $1 = level string, $2 = message
_write_log() {
    local level="$1"
    local message="$2"

    if [[ -n "$SETUP_LOG_FILE" && -w "$SETUP_LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$SETUP_LOG_FILE"
    fi
}

# Log debug message (only to file, not console)
# Args: $1 = message
log_debug() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]]; then
        _write_log "DEBUG" "$1"
    fi
}

# Log info message
# Args: $1 = message
log_info() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        _write_log "INFO" "$1"
    fi
}

# Log warning message
# Args: $1 = message
log_warning() {
    if [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARNING ]]; then
        _write_log "WARNING" "$1"
    fi
}

# Log error message
# Args: $1 = message
log_error() {
    _write_log "ERROR" "$1"
}

# Get path to the setup log file
# Returns: path to current log file
get_log_file() {
    echo "$SETUP_LOG_FILE"
}

#######################################
# Output Functions
#######################################

print_header() {
    echo -e "${GREEN}$1${NC}"
    log_info "$1"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
    log_info "[SUCCESS] $1"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
    log_warning "$1"
}

print_error() {
    echo -e "${RED}$1${NC}" >&2
    log_error "$1"
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
