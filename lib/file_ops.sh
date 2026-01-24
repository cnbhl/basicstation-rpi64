#!/bin/bash
#
# file_ops.sh - Secure file operations and template processing
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh, validation.sh
#

#######################################
# Temp File Management
#######################################

# Array to track temp files for cleanup
declare -a _TEMP_FILES=()

# Register cleanup trap (called once when this file is sourced)
_cleanup_temp_files() {
    for tmp in "${_TEMP_FILES[@]}"; do
        [[ -f "$tmp" ]] && rm -f "$tmp" 2>/dev/null
    done
}
trap _cleanup_temp_files EXIT

# Create a temp file in the same directory as target (ensures atomic mv)
# Args: $1 = target file path
# Returns: path to temp file (also registered for cleanup)
_create_temp_file() {
    local target_path="$1"
    local target_dir
    local temp_file

    target_dir="$(dirname "$target_path")"

    # Ensure target directory exists
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" || {
            print_error "Cannot create directory: $target_dir"
            return 1
        }
    fi

    # Save current umask and set restrictive one
    local old_umask
    old_umask=$(umask)
    umask 077

    # Create temp file in target directory for atomic rename
    temp_file=$(mktemp "${target_dir}/.tmp.XXXXXX") || {
        umask "$old_umask"
        print_error "Cannot create temp file in: $target_dir"
        return 1
    }

    # Restore umask
    umask "$old_umask"

    # Register for cleanup
    _TEMP_FILES+=("$temp_file")

    echo "$temp_file"
}

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

    # Create temp file in same directory as target (atomic mv, restrictive perms)
    temp_file=$(_create_temp_file "$file_path") || return 1

    # Set final permissions
    chmod "$permissions" "$temp_file"

    # Write content using printf to avoid process listing
    printf '%s\n' "$content" > "$temp_file"

    # Atomic move to final location (same filesystem guaranteed)
    mv "$temp_file" "$file_path"
}

# Write secret to file (extra secure - no echo)
# Args: $1 = file path, $2 = content
write_secret_file() {
    local file_path="$1"
    local content="$2"
    local temp_file

    # Create temp file in same directory (atomic mv, created with umask 077)
    temp_file=$(_create_temp_file "$file_path") || return 1

    # Ensure 600 permissions for secrets
    chmod 600 "$temp_file"

    # Use here-string to avoid secret in process listing
    cat > "$temp_file" <<< "$content"

    # Atomic move to final location
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
