#!/bin/bash
#
# uninstall.sh - Uninstall functions
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh (including logging), service.sh
#
# Expected global variables from main script:
#   SCRIPT_DIR, CUPS_DIR
#

#######################################
# Uninstall Functions
#######################################

# Remove the systemd service
uninstall_service() {
    local service_name="basicstation.service"
    local service_file="/etc/systemd/system/$service_name"

    print_header "Checking systemd service..."

    if [[ ! -f "$service_file" ]]; then
        echo "  Service file not found at $service_file"
        echo "  Skipping service removal."
        return 0
    fi

    echo "  Found: $service_file"

    if service_is_active "$service_name"; then
        echo "  Service is currently running."
    fi

    if ! confirm "Remove the systemd service?"; then
        echo "  Skipping service removal."
        return 0
    fi

    # Stop the service if running
    if service_is_active "$service_name"; then
        echo "  Stopping service..."
        sudo systemctl stop "$service_name" || true
    fi

    # Disable the service if enabled
    if service_is_enabled "$service_name"; then
        echo "  Disabling service..."
        sudo systemctl disable "$service_name" || true
    fi

    # Remove the service file
    echo "  Removing service file..."
    sudo rm -f "$service_file"
    sudo systemctl daemon-reload

    print_success "  Service removed."
}

# Remove credential files
uninstall_credentials() {
    print_header "Checking credential files..."

    local files_found=false
    local cred_files=(
        "$CUPS_DIR/cups.uri"
        "$CUPS_DIR/cups.key"
        "$CUPS_DIR/cups.trust"
        "$CUPS_DIR/station.conf"
        "$CUPS_DIR/tc.key"
        "$CUPS_DIR/tc.uri"
        "$CUPS_DIR/tc.trust"
    )

    echo "  Checking in: $CUPS_DIR"

    for f in "${cred_files[@]}"; do
        if [[ -f "$f" ]]; then
            echo "  Found: $(basename "$f")"
            files_found=true
        fi
    done

    if [[ "$files_found" == false ]]; then
        echo "  No credential files found."
        return 0
    fi

    if ! confirm "Remove these credential files?"; then
        echo "  Skipping credential removal."
        return 0
    fi

    for f in "${cred_files[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            echo "  Removed: $(basename "$f")"
        fi
    done

    print_success "  Credential files removed."
}

# Remove log files
uninstall_logs() {
    print_header "Checking log files..."

    local log_files=(
        "/var/log/station.log"
        "$CUPS_DIR/station.log"
    )

    local files_found=false

    for f in "${log_files[@]}"; do
        if [[ -f "$f" ]]; then
            echo "  Found: $f"
            files_found=true
        fi
    done

    if [[ "$files_found" == false ]]; then
        echo "  No log files found."
        return 0
    fi

    print_warning "  Note: Log files may contain useful diagnostic information."

    if ! confirm "Remove log files?"; then
        echo "  Skipping log removal."
        return 0
    fi

    for f in "${log_files[@]}"; do
        if [[ -f "$f" ]]; then
            if [[ "$f" == /var/log/* ]]; then
                sudo rm -f "$f"
            else
                rm -f "$f"
            fi
            echo "  Removed: $f"
        fi
    done

    print_success "  Log files removed."
}

# Remove build artifacts
uninstall_build() {
    print_header "Checking build artifacts..."

    local build_dirs=(
        "$SCRIPT_DIR/build-corecell-std"
        "$SCRIPT_DIR/build-corecell-debug"
    )

    local dirs_found=false

    for d in "${build_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            echo "  Found: $d"
            dirs_found=true
        fi
    done

    if [[ "$dirs_found" == false ]]; then
        echo "  No build directories found."
        return 0
    fi

    print_warning "  Note: Removing build artifacts will require a full rebuild."

    if ! confirm "Remove build directories?"; then
        echo "  Skipping build artifact removal."
        return 0
    fi

    for d in "${build_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            rm -rf "$d"
            echo "  Removed: $d"
        fi
    done

    print_success "  Build artifacts removed."
}

#######################################
# Main Uninstall Function
#######################################

run_uninstall() {
    print_banner "LoRa Basic Station Uninstall"

    log_info "=== Starting uninstall wizard ==="

    echo "This will remove the Basic Station installation components."
    echo "You will be prompted before each removal step."
    echo ""

    if ! confirm "Proceed with uninstall?"; then
        log_info "Uninstall cancelled by user"
        echo "Uninstall cancelled."
        exit 0
    fi

    echo ""

    uninstall_service
    log_debug "Completed: uninstall_service"
    echo ""

    uninstall_credentials
    log_debug "Completed: uninstall_credentials"
    echo ""

    uninstall_logs
    log_debug "Completed: uninstall_logs"
    echo ""

    uninstall_build
    log_debug "Completed: uninstall_build"
    echo ""

    log_info "=== Uninstall wizard completed ==="
    print_banner "Uninstall Complete"
    echo "The following may still remain:"
    echo "  - Source code in: $SCRIPT_DIR"
    echo "  - Dependencies in: $SCRIPT_DIR/deps/"
    echo ""
    echo "To completely remove, delete the repository folder:"
    print_warning "  rm -rf $SCRIPT_DIR"
}
