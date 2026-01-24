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

#######################################
# Privilege / Sudo Detection
#######################################

# Global flag set by check_sudo_available()
HAVE_SUDO=false
IS_ROOT=false

# Check if running as root
# Returns: 0 if root, 1 otherwise
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if sudo is available and user can use it
# Sets global HAVE_SUDO and IS_ROOT flags
# Returns: 0 if root or sudo available, 1 otherwise
check_sudo_available() {
    # Check if already root
    if is_root; then
        IS_ROOT=true
        HAVE_SUDO=true
        log_debug "Running as root (EUID=0)"
        return 0
    fi

    # Check if sudo command exists
    if ! command_exists sudo; then
        HAVE_SUDO=false
        print_error "sudo command not found"
        echo ""
        echo "This script requires elevated privileges for:"
        echo "  - Hardware access (SPI, I2C, GPIO)"
        echo "  - Serial port configuration (GPS)"
        echo "  - System service management"
        echo ""
        echo "Please install sudo or run as root:"
        echo "  su -c '$0'"
        echo ""
        return 1
    fi

    # Test if user can use sudo (non-interactive check)
    if sudo -n true 2>/dev/null; then
        HAVE_SUDO=true
        log_debug "sudo available (passwordless)"
        return 0
    fi

    # sudo exists but may require password - that's OK
    HAVE_SUDO=true
    log_debug "sudo available (may require password)"
    return 0
}

# Run a command with sudo if not root
# Args: $@ = command and arguments
# Returns: command exit code
run_privileged() {
    if is_root; then
        "$@"
    else
        sudo "$@"
    fi
}

# Check sudo and provide helpful message on failure
# Args: $1 = description of what needs sudo
# Returns: 0 if sudo available, 1 with message otherwise
require_privilege() {
    local purpose="${1:-perform this operation}"

    if is_root || [[ "$HAVE_SUDO" == true ]]; then
        return 0
    fi

    print_error "Elevated privileges required to $purpose"
    echo ""
    echo "Please either:"
    echo "  1. Run this script with sudo:"
    echo "     sudo $0"
    echo ""
    echo "  2. Or run as root:"
    echo "     su -c '$0'"
    echo ""
    return 1
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

# Check if I2C is available (required for SX1302/SX1303 temperature sensor)
# Note: The SX1302 HAL hardcodes "/dev/i2c-1" in loragw_i2c.h
check_i2c_available() {
    if [[ -e /dev/i2c-1 ]]; then
        return 0
    fi

    # Check if I2C exists on other buses (for diagnostic purposes)
    local other_i2c
    other_i2c=$(ls /dev/i2c-* 2>/dev/null | grep -v i2c-1 | head -1)

    print_error "I2C device not found at /dev/i2c-1"
    echo ""

    if [[ -n "$other_i2c" ]]; then
        print_warning "Note: I2C found at $other_i2c, but the SX1302/SX1303 HAL requires /dev/i2c-1"
        echo ""
    fi

    echo "The SX1302/SX1303 concentrator requires I2C bus 1 for the temperature sensor."
    echo ""
    echo "To enable I2C, use one of these methods:"
    echo ""
    echo "  Method 1 - Using raspi-config:"
    echo "    sudo raspi-config"
    echo "    Navigate to: Interface Options > I2C > Enable"
    echo "    Reboot when prompted"
    echo ""
    echo "  Method 2 - Command line:"
    echo "    sudo raspi-config nonint do_i2c 0"
    echo "    sudo reboot"
    echo ""
    echo "  Method 3 - Manual (add to /boot/config.txt):"
    echo "    echo 'dtparam=i2c_arm=on' | sudo tee -a /boot/config.txt"
    echo "    sudo reboot"
    echo ""
    return 1
}

#######################################
# Dependency Validation
#######################################

# Required dependencies for setup script
# Format: "command:package:purpose"
readonly REQUIRED_DEPS=(
    # Build tools
    "gcc:gcc:compiling station and chip_id"
    "make:make:building station"
    # Network tools
    "curl:curl:downloading certificates"
    # Text processing
    "sed:sed:template processing"
    "grep:grep:text pattern matching"
    "tr:coreutils:character translation"
    "cat:coreutils:file concatenation"
    # File operations
    "cp:coreutils:copying files"
    "mv:coreutils:moving files"
    "chmod:coreutils:setting file permissions"
    "mktemp:coreutils:creating temporary files"
    "tee:coreutils:writing to files"
    # Serial/GPS
    "stty:coreutils:GPS serial port configuration"
    "timeout:coreutils:GPS detection timeouts"
    # System
    "sudo:sudo:elevated privileges for hardware access"
    "systemctl:systemd:service management"
)

# Optional dependencies (warn if missing but don't fail)
readonly OPTIONAL_DEPS=(
    # None currently - all required deps moved above
)

# Check if a single dependency is available
# Args: $1 = command, $2 = package name, $3 = purpose
# Returns: 0 if found, 1 if missing
check_dependency() {
    local cmd="$1"
    local package="$2"
    local purpose="$3"

    if command_exists "$cmd"; then
        log_debug "Dependency check: $cmd found"
        return 0
    else
        log_error "Missing dependency: $cmd (package: $package, needed for: $purpose)"
        return 1
    fi
}

# Check all required dependencies
# Returns: 0 if all found, 1 if any missing
check_required_dependencies() {
    local missing=()
    local dep cmd package purpose

    log_info "Checking required dependencies"

    for dep in "${REQUIRED_DEPS[@]}"; do
        IFS=':' read -r cmd package purpose <<< "$dep"
        if ! check_dependency "$cmd" "$package" "$purpose"; then
            missing+=("$cmd ($package)")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        echo ""
        echo "Please install missing packages:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install ${missing[*]// (*)/}"
        return 1
    fi

    log_info "All required dependencies found"
    return 0
}

# Check optional dependencies and warn if missing
check_optional_dependencies() {
    local dep cmd package purpose

    log_info "Checking optional dependencies"

    for dep in "${OPTIONAL_DEPS[@]}"; do
        IFS=':' read -r cmd package purpose <<< "$dep"
        if ! command_exists "$cmd"; then
            log_warning "Optional dependency missing: $cmd (needed for: $purpose)"
            print_warning "Note: '$cmd' not found - $purpose will not be available"
        fi
    done
}

# Run all dependency checks
# Args: $1 = "strict" to fail on missing required deps (default), "warn" to only warn
# Returns: 0 if OK (or warn mode), 1 if missing required deps in strict mode
check_all_dependencies() {
    local mode="${1:-strict}"
    local result=0

    echo "Checking system dependencies..."
    log_info "Running dependency checks (mode: $mode)"

    # Check sudo/root privileges first
    if ! check_sudo_available; then
        if [[ "$mode" == "strict" ]]; then
            result=1
        fi
    else
        if is_root; then
            log_info "Running as root"
        else
            log_info "sudo available for elevated operations"
        fi
    fi

    # Check required dependencies
    if ! check_required_dependencies; then
        if [[ "$mode" == "strict" ]]; then
            result=1
        fi
    fi

    # Check optional dependencies (always just warn)
    check_optional_dependencies

    # Check SPI availability
    if ! check_spi_available; then
        if [[ "$mode" == "strict" ]]; then
            result=1
        fi
    else
        log_debug "SPI device available"
    fi

    # Check I2C availability (required for SX1302/SX1303 temperature sensor)
    if ! check_i2c_available; then
        if [[ "$mode" == "strict" ]]; then
            result=1
        fi
    else
        log_debug "I2C device available"
    fi

    if [[ $result -eq 0 ]]; then
        print_success "All dependencies satisfied"
    fi

    echo ""
    return $result
}
