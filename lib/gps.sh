#!/bin/bash
#
# gps.sh - GPS serial port detection functions
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh (for print_*, confirm, log_*, GREEN, NC, run_privileged)
#
# Expected global variables from main script:
#   GPS_DEVICE (will be set by detect_gps_port)
#   SKIP_GPS (if true, skip auto-detection)
#
# IMPORTANT: GPS detection requires sudo for serial port access.
# The scan tests multiple ports and baud rates, which may take 30-60 seconds.
# Use --skip-gps flag to bypass scanning if no GPS module is connected.
#

#######################################
# GPS Detection Constants
#######################################

# Common serial ports where GPS modules are found
# Pi 5: /dev/ttyAMA0 is primary UART
# Pi 4/3: /dev/ttyS0 is mini UART, /dev/ttyAMA0 is PL011
# /dev/serial0 is a symlink that varies by model
readonly GPS_PORTS=("/dev/ttyAMA0" "/dev/ttyS0" "/dev/serial0" "/dev/ttyAMA10")

# Common baud rates for GPS modules (most common first)
readonly GPS_BAUD_RATES=(9600 4800 19200 38400 57600 115200)

# Timeout for reading GPS data (seconds)
readonly GPS_READ_TIMEOUT=2

# Maximum bytes to read from serial port
readonly GPS_READ_BYTES=1024

#######################################
# GPS Detection Functions
#######################################

# Check if data contains NMEA sentences
# Args: $1 = data to check
# Returns: 0 if NMEA found, 1 otherwise
contains_nmea() {
    local data="$1"
    # NMEA sentences start with $ followed by talker ID (GP, GN, GL, GA, GB)
    [[ "$data" =~ \$G[PNLAB] ]]
}

# Try to read GPS data from a serial port at a specific baud rate
# Args: $1 = port, $2 = baud rate
# Returns: 0 if NMEA data found, 1 otherwise
# Note: Requires sudo for serial port access
try_gps_port() {
    local port="$1"
    local baud="$2"
    local data
    local stty_result

    # Check if port exists and is a character device
    if [[ ! -c "$port" ]]; then
        log_debug "Port $port is not a character device"
        return 1
    fi

    # Configure serial port (requires sudo for serial port access)
    # Using standard stty options that work across Linux systems
    # raw: raw input/output mode
    # -echo -echoe -echok: disable echo modes
    if ! run_privileged stty -F "$port" "$baud" raw -echo -echoe -echok 2>/dev/null; then
        log_debug "Failed to configure $port at $baud baud"
        return 1
    fi

    # Read data with timeout
    # - timeout: prevents blocking indefinitely on ports with no data
    # - head -c: limits bytes read to prevent buffer overflow
    # - tr: strips non-printable characters except newlines and $
    # The || true prevents set -e from triggering on timeout exit code 124
    data=$(run_privileged timeout "${GPS_READ_TIMEOUT}s" cat "$port" 2>/dev/null \
        | head -c "$GPS_READ_BYTES" \
        | tr -cd '[:print:]\n$' || true)

    if [[ -z "$data" ]]; then
        log_debug "No data received from $port"
        return 1
    fi

    if contains_nmea "$data"; then
        log_debug "NMEA data found on $port: ${data:0:50}..."
        return 0
    fi

    log_debug "Data received but no NMEA pattern: ${data:0:50}..."
    return 1
}

# Detect GPS port and baud rate by scanning available ports
# Sets GPS_DEVICE global variable on success
# Returns: 0 if GPS found, 1 otherwise
# Note: This scan requires sudo and may take 30-60 seconds
detect_gps_port() {
    local port baud
    local tested_ports=()
    local total_tests=0
    local port_count=0

    log_info "Starting GPS port detection"

    # Count available ports for progress estimation
    for port in "${GPS_PORTS[@]}"; do
        if [[ -e "$port" ]]; then
            ((port_count++))
        fi
    done

    if [[ $port_count -eq 0 ]]; then
        log_warning "No serial ports found to scan"
        echo "  No serial ports available for GPS detection."
        return 1
    fi

    total_tests=$((port_count * ${#GPS_BAUD_RATES[@]}))
    local est_time=$((total_tests * GPS_READ_TIMEOUT))
    log_info "Scanning $port_count ports x ${#GPS_BAUD_RATES[@]} baud rates (est. ${est_time}s max)"

    for port in "${GPS_PORTS[@]}"; do
        # Skip if port doesn't exist
        if [[ ! -e "$port" ]]; then
            log_debug "Port $port does not exist, skipping"
            continue
        fi

        # Resolve symlinks to avoid testing the same device twice
        local real_port
        real_port=$(readlink -f "$port" 2>/dev/null || echo "$port")

        # Skip if we already tested this real device
        local already_tested=false
        for tested in "${tested_ports[@]}"; do
            if [[ "$tested" == "$real_port" ]]; then
                log_debug "Port $port -> $real_port already tested, skipping"
                already_tested=true
                break
            fi
        done
        [[ "$already_tested" == true ]] && continue

        tested_ports+=("$real_port")
        log_debug "Testing port $port (resolves to $real_port)"

        for baud in "${GPS_BAUD_RATES[@]}"; do
            echo -n "  Trying $port @ ${baud}bps... "
            log_debug "Trying $port at ${baud} baud"

            if try_gps_port "$port" "$baud"; then
                echo -e "${GREEN}NMEA data found!${NC}"
                log_info "GPS detected on $port at ${baud} baud"
                GPS_DEVICE="$port"
                return 0
            else
                echo "no data"
            fi
        done
    done

    log_warning "No GPS module detected on any port"
    return 1
}
