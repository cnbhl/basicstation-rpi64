#!/bin/bash
#
# gps.sh - GPS serial port detection functions
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh (for print_*, confirm, log_*, GREEN, NC)
#
# Expected global variables from main script:
#   GPS_DEVICE (will be set by detect_gps_port)
#

#######################################
# GPS Detection Constants
#######################################

# Common serial ports where GPS modules are found
readonly GPS_PORTS=("/dev/ttyAMA0" "/dev/ttyS0" "/dev/serial0" "/dev/ttyAMA10")

# Common baud rates for GPS modules (most common first)
readonly GPS_BAUD_RATES=(9600 4800 19200 38400 57600 115200)

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
try_gps_port() {
    local port="$1"
    local baud="$2"
    local data

    # Check if port exists
    if [[ ! -c "$port" ]]; then
        return 1
    fi

    # Configure serial port (requires sudo for serial port access)
    if ! sudo stty -F "$port" "$baud" raw -echo -echoe -echok 2>/dev/null; then
        return 1
    fi

    # Read data for 2 seconds, capture output
    data=$(sudo timeout 2s cat "$port" 2>/dev/null | head -c 1024 | tr -cd '[:print:]\n$' || true)

    if contains_nmea "$data"; then
        return 0
    fi

    return 1
}

# Detect GPS port and baud rate by scanning available ports
# Sets GPS_DEVICE global variable on success
# Returns: 0 if GPS found, 1 otherwise
detect_gps_port() {
    local port baud

    log_info "Starting GPS port detection"

    for port in "${GPS_PORTS[@]}"; do
        # Skip if port doesn't exist
        if [[ ! -e "$port" ]]; then
            log_debug "Port $port does not exist, skipping"
            continue
        fi

        # Resolve symlinks to avoid testing the same device twice
        local real_port
        real_port=$(readlink -f "$port" 2>/dev/null || echo "$port")
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
