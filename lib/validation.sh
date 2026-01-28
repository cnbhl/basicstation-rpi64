#!/bin/bash
#
# validation.sh - Input validation and sanitization functions
#
# This file is sourced by setup-gateway.sh
#

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

# Validate GPIO BCM pin number (0-27 for standard Pi header)
validate_gpio() {
    local pin="$1"
    [[ "$pin" =~ ^[0-9]+$ ]] && [ "$pin" -ge 0 ] && [ "$pin" -le 27 ]
}

# Sanitize string for use in sed replacement
# Escapes special characters: \ / & and newlines
sanitize_for_sed() {
    local input="$1"
    printf '%s' "$input" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\/' -e '$s/\\$//'
}

# Validate TTN region code
# Args: $1 = region code
# Returns: 0 if valid (eu1, nam1, au1), 1 otherwise
validate_region() {
    local region="$1"
    [[ "$region" == "eu1" || "$region" == "nam1" || "$region" == "au1" ]]
}

# Validate board type against template
# Args: $1 = board type
# Returns: 0 if valid, 1 otherwise
# Note: This function requires BOARD_CONF_TEMPLATE to be set
validate_board_type() {
    local board="$1"

    # Check if template file exists
    if [[ ! -f "$BOARD_CONF_TEMPLATE" ]]; then
        # If template not found, accept known board types
        [[ "$board" == "WM1302" || "$board" == "PG1302" || "$board" == "LR1302" || \
           "$board" == "SX1302_WS" || "$board" == "SEMTECH" ]]
        return
    fi

    # Check if board type exists in template (first field before colon)
    while IFS=: read -r btype _; do
        # Skip comments and empty lines
        [[ "$btype" =~ ^#.*$ || -z "$btype" ]] && continue
        if [[ "$btype" == "$board" ]]; then
            return 0
        fi
    done < "$BOARD_CONF_TEMPLATE"

    return 1
}

# Get board configuration from template
# Args: $1 = board type
# Sets: SX1302_RESET_BCM, SX1302_POWER_EN_BCM, SX1261_RESET_BCM (global vars)
# Returns: 0 if found, 1 otherwise
get_board_config() {
    local board="$1"

    if [[ ! -f "$BOARD_CONF_TEMPLATE" ]]; then
        return 1
    fi

    while IFS=: read -r btype bdesc breset bpower bsx1261; do
        # Skip comments and empty lines
        [[ "$btype" =~ ^#.*$ || -z "$btype" ]] && continue
        if [[ "$btype" == "$board" ]]; then
            SX1302_RESET_BCM="$breset"
            SX1302_POWER_EN_BCM="$bpower"
            SX1261_RESET_BCM="${bsx1261:-5}"
            return 0
        fi
    done < "$BOARD_CONF_TEMPLATE"

    return 1
}
