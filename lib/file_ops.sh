#!/bin/bash
#
# file_ops.sh - Secure file operations and template processing
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh, validation.sh
#

#######################################
# File Operations (Security-focused)
#######################################

# Write content to file with secure permissions (atomic)
# Args: $1 = file path, $2 = content, $3 = permissions (default: 600)
write_file_secure() {
    local file_path="$1"
    local content="$2"
    local permissions="${3:-600}"
    local temp_file

    temp_file=$(mktemp)

    # Set restrictive permissions before writing content
    chmod "$permissions" "$temp_file"

    # Write content using printf to avoid process listing
    printf '%s\n' "$content" > "$temp_file"

    # Atomic move to final location
    mv "$temp_file" "$file_path"
}

# Write secret to file (extra secure - no echo)
# Args: $1 = file path, $2 = content
write_secret_file() {
    local file_path="$1"
    local content="$2"

    # Create file with restricted permissions first
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"

    # Use here-string to avoid secret in process listing
    cat > "$temp_file" <<< "$content"

    mv "$temp_file" "$file_path"
}

# Copy file with permission preservation
# Args: $1 = source, $2 = destination, $3 = permissions (optional)
copy_file() {
    local src="$1"
    local dst="$2"
    local permissions="${3:-}"

    if [[ ! -f "$src" ]]; then
        print_error "Source file not found: $src"
        return 1
    fi

    cp "$src" "$dst"

    if [[ -n "$permissions" ]]; then
        chmod "$permissions" "$dst"
    fi
}

#######################################
# Template Processing
#######################################

# Process a template file with variable substitution
# Args: $1 = template file, $2 = output file, $3... = "KEY=VALUE" pairs
process_template() {
    local template="$1"
    local output="$2"
    shift 2

    if [[ ! -f "$template" ]]; then
        print_error "Template not found: $template"
        return 1
    fi

    local content
    content=$(cat "$template")

    # Process each KEY=VALUE pair
    for pair in "$@"; do
        local key="${pair%%=*}"
        local value="${pair#*=}"
        local safe_value
        safe_value=$(sanitize_for_sed "$value")
        content=$(printf '%s' "$content" | sed "s|{{${key}}}|${safe_value}|g")
    done

    printf '%s\n' "$content" > "$output"
}
