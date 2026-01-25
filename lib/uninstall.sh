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

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_header "Checking systemd service..."
    fi

    if [[ ! -f "$service_file" ]]; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  Service file not found at $service_file"
            echo "  Skipping service removal."
        fi
        log_info "Service file not found, skipping"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo "  Found: $service_file"

        if service_is_active "$service_name"; then
            echo "  Service is currently running."
        fi

        # In interactive mode, ask for confirmation (default: no)
        if ! confirm "Remove the systemd service?"; then
            echo "  Skipping service removal."
            return 0
        fi
    else
        log_info "Removing systemd service: $service_name"
    fi

    # Stop the service if running
    if service_is_active "$service_name"; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  Stopping service..."
        fi
        sudo systemctl stop "$service_name" || true
    fi

    # Disable the service if enabled
    if service_is_enabled "$service_name"; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  Disabling service..."
        fi
        sudo systemctl disable "$service_name" || true
    fi

    # Remove the service file
    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo "  Removing service file..."
    fi
    sudo rm -f "$service_file"
    sudo systemctl daemon-reload

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_success "  Service removed."
    fi
    log_info "Service removed"
}

# Remove credential files
uninstall_credentials() {
    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_header "Checking credential files..."
    fi

    local files_found=false
    local cred_files=(
        "$CUPS_DIR/cups.uri"
        "$CUPS_DIR/cups.key"
        "$CUPS_DIR/cups.trust"
        "$CUPS_DIR/station.conf"
        "$CUPS_DIR/tc.key"
        "$CUPS_DIR/tc.uri"
        "$CUPS_DIR/tc.trust"
        "$CUPS_DIR/board.conf"
    )

    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo "  Checking in: $CUPS_DIR"
    fi

    for f in "${cred_files[@]}"; do
        if [[ -f "$f" ]]; then
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Found: $(basename "$f")"
            fi
            files_found=true
        fi
    done

    if [[ "$files_found" == false ]]; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  No credential files found."
        fi
        log_info "No credential files found"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" != true ]]; then
        if ! confirm "Remove these credential files?"; then
            echo "  Skipping credential removal."
            return 0
        fi
    else
        log_info "Removing credential files"
    fi

    for f in "${cred_files[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Removed: $(basename "$f")"
            fi
            log_debug "Removed: $f"
        fi
    done

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_success "  Credential files removed."
    fi
    log_info "Credential files removed"
}

# Remove log files
uninstall_logs() {
    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_header "Checking log files..."
    fi

    local log_files=(
        "/var/log/station.log"
        "$CUPS_DIR/station.log"
    )

    local files_found=false

    for f in "${log_files[@]}"; do
        if [[ -f "$f" ]]; then
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Found: $f"
            fi
            files_found=true
        fi
    done

    if [[ "$files_found" == false ]]; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  No log files found."
        fi
        log_info "No log files found"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_warning "  Note: Log files may contain useful diagnostic information."

        if ! confirm "Remove log files?"; then
            echo "  Skipping log removal."
            return 0
        fi
    else
        log_info "Removing log files"
    fi

    for f in "${log_files[@]}"; do
        if [[ -f "$f" ]]; then
            if [[ "$f" == /var/log/* ]]; then
                sudo rm -f "$f"
            else
                rm -f "$f"
            fi
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Removed: $f"
            fi
            log_debug "Removed: $f"
        fi
    done

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_success "  Log files removed."
    fi
    log_info "Log files removed"
}

# Remove build artifacts
uninstall_build() {
    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_header "Checking build artifacts..."
    fi

    local build_dirs=(
        "$SCRIPT_DIR/build-corecell-std"
        "$SCRIPT_DIR/build-corecell-debug"
    )

    local dirs_found=false

    for d in "${build_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Found: $d"
            fi
            dirs_found=true
        fi
    done

    if [[ "$dirs_found" == false ]]; then
        if [[ "$NON_INTERACTIVE" != true ]]; then
            echo "  No build directories found."
        fi
        log_info "No build directories found"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_warning "  Note: Removing build artifacts will require a full rebuild."

        if ! confirm "Remove build directories?"; then
            echo "  Skipping build artifact removal."
            return 0
        fi
    else
        log_info "Removing build artifacts"
    fi

    for d in "${build_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            rm -rf "$d"
            if [[ "$NON_INTERACTIVE" != true ]]; then
                echo "  Removed: $d"
            fi
            log_debug "Removed: $d"
        fi
    done

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_success "  Build artifacts removed."
    fi
    log_info "Build artifacts removed"
}

#######################################
# Main Uninstall Function
#######################################

run_uninstall() {
    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_banner "LoRa Basic Station Uninstall"
    fi

    log_info "=== Starting uninstall wizard ==="

    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo "This will remove the Basic Station installation components."
        echo "You will be prompted before each removal step."
        echo ""

        if ! confirm "Proceed with uninstall?"; then
            log_info "Uninstall cancelled by user"
            echo "Uninstall cancelled."
            exit 0
        fi
        echo ""
    else
        log_info "Running uninstall in non-interactive mode (all steps will proceed)"
    fi

    uninstall_service
    log_debug "Completed: uninstall_service"
    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo ""
    fi

    uninstall_credentials
    log_debug "Completed: uninstall_credentials"
    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo ""
    fi

    uninstall_logs
    log_debug "Completed: uninstall_logs"
    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo ""
    fi

    uninstall_build
    log_debug "Completed: uninstall_build"
    if [[ "$NON_INTERACTIVE" != true ]]; then
        echo ""
    fi

    log_info "=== Uninstall wizard completed ==="

    if [[ "$NON_INTERACTIVE" != true ]]; then
        print_banner "Uninstall Complete"
        echo "The following may still remain:"
        echo "  - Source code in: $SCRIPT_DIR"
        echo "  - Dependencies in: $SCRIPT_DIR/deps/"
        echo ""
        echo "To completely remove, delete the repository folder:"
        print_warning "  rm -rf $SCRIPT_DIR"
    else
        log_info "Uninstall completed successfully"
    fi
}
