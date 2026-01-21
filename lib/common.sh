#!/bin/bash
#
# common.sh - Common output and input functions
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
