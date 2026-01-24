#!/bin/bash
#
# service.sh - Systemd service management functions
#
# This file is sourced by setup-gateway.sh
# Requires: common.sh
#

#######################################
# Service Management Functions
#######################################

# Check if systemd service is active
# Args: $1 = service name
service_is_active() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Check if systemd service is enabled
# Args: $1 = service name
service_is_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

# Start a systemd service with status check
# Args: $1 = service name
# Returns: 0 on success, 1 on failure
service_start() {
    local service="$1"

    sudo systemctl start "$service"
    sleep 2

    if service_is_active "$service"; then
        print_success "Service $service started successfully!"
        return 0
    else
        print_warning "Service $service may have failed to start."
        echo "  Check status: sudo systemctl status $service"
        echo "  View logs: sudo journalctl -u $service -f"
        return 1
    fi
}

# Restart a systemd service with status check
# Args: $1 = service name
service_restart() {
    local service="$1"

    sudo systemctl restart "$service"
    sleep 2

    if service_is_active "$service"; then
        print_success "Service $service restarted successfully!"
        return 0
    else
        print_warning "Service $service may have failed to restart."
        echo "  Check status: sudo systemctl status $service"
        echo "  View logs: sudo journalctl -u $service -f"
        return 1
    fi
}
