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

# Sanitize string for use in sed replacement
# Escapes special characters: \ / & and newlines
sanitize_for_sed() {
    local input="$1"
    printf '%s' "$input" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\/' -e '$s/\\$//'
}
