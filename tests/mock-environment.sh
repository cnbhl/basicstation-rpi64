#!/bin/bash
#
# mock-environment.sh - Mock environment for testing setup-gateway.sh without hardware
#
# This script creates mock devices and tools for CI/CD testing.
# It should be sourced before running tests.
#
# Usage:
#   source tests/mock-environment.sh
#   setup_mock_environment
#   # ... run tests ...
#   cleanup_mock_environment
#

set -euo pipefail

# Directory for mock files
MOCK_DIR=""
MOCK_CHIP_ID=""
ORIGINAL_PATH=""

#######################################
# Setup Functions
#######################################

# Create a mock chip_id tool that returns a fake EUI
create_mock_chip_id() {
    local mock_eui="${1:-AABBCCDDEEFF0011}"

    MOCK_CHIP_ID="$MOCK_DIR/chip_id"

    cat > "$MOCK_CHIP_ID" << EOF
#!/bin/bash
# Mock chip_id tool for testing
echo "SX1302 concentrator EUI: 0x$mock_eui"
exit 0
EOF
    chmod +x "$MOCK_CHIP_ID"

    echo "Created mock chip_id at $MOCK_CHIP_ID"
}

# Create mock SPI device
create_mock_spi() {
    # We can't create actual device nodes without root, but we can create
    # a file that the tests can check for
    touch "$MOCK_DIR/spidev0.0"
    echo "Created mock SPI device marker"
}

# Create mock I2C device
create_mock_i2c() {
    touch "$MOCK_DIR/i2c-1"
    echo "Created mock I2C device marker"
}

# Create mock GPS device
create_mock_gps() {
    local gps_device="${1:-$MOCK_DIR/ttyAMA0}"

    # Create a named pipe that outputs fake NMEA data
    if [[ ! -p "$gps_device" ]]; then
        mkfifo "$gps_device" 2>/dev/null || touch "$gps_device"
    fi

    echo "Created mock GPS device at $gps_device"
}

# Create mock reset_lgw.sh
create_mock_reset_lgw() {
    local reset_script="$MOCK_DIR/reset_lgw.sh"

    cat > "$reset_script" << 'EOF'
#!/bin/bash
# Mock reset_lgw.sh for testing
echo "Mock: GPIO reset performed"
exit 0
EOF
    chmod +x "$reset_script"

    echo "Created mock reset_lgw.sh"
}

# Create mock sudo that allows commands through
create_mock_sudo() {
    local mock_sudo="$MOCK_DIR/sudo"

    cat > "$mock_sudo" << 'EOF'
#!/bin/bash
# Mock sudo for testing - just run the command
"$@"
EOF
    chmod +x "$mock_sudo"

    echo "Created mock sudo"
}

# Create mock systemctl
create_mock_systemctl() {
    local mock_systemctl="$MOCK_DIR/systemctl"

    cat > "$mock_systemctl" << 'EOF'
#!/bin/bash
# Mock systemctl for testing
case "$1" in
    is-active)
        echo "inactive"
        exit 3
        ;;
    is-enabled)
        echo "disabled"
        exit 1
        ;;
    start|stop|restart|enable|disable|daemon-reload)
        echo "Mock: systemctl $*"
        exit 0
        ;;
    status)
        echo "Mock: service status"
        exit 0
        ;;
    *)
        echo "Mock systemctl: unknown command $1"
        exit 0
        ;;
esac
EOF
    chmod +x "$mock_systemctl"

    echo "Created mock systemctl"
}

#######################################
# Main Setup/Cleanup Functions
#######################################

setup_mock_environment() {
    echo "Setting up mock environment..."

    # Create temporary directory for mocks
    MOCK_DIR=$(mktemp -d)
    echo "Mock directory: $MOCK_DIR"

    # Save original PATH
    ORIGINAL_PATH="$PATH"

    # Create mock tools
    create_mock_chip_id
    create_mock_spi
    create_mock_i2c
    create_mock_reset_lgw
    create_mock_sudo
    create_mock_systemctl

    # Add mock directory to PATH (prepend so mocks take precedence)
    export PATH="$MOCK_DIR:$PATH"

    # Export mock directory for tests to use
    export MOCK_DIR

    echo "Mock environment ready"
}

cleanup_mock_environment() {
    echo "Cleaning up mock environment..."

    # Restore original PATH
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi

    # Remove mock directory
    if [[ -n "${MOCK_DIR:-}" && -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
        echo "Removed mock directory"
    fi

    echo "Mock environment cleaned up"
}

#######################################
# Test Helper Functions
#######################################

# Assert that a condition is true
assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if eval "$condition"; then
        echo "  PASS: $message"
        return 0
    else
        echo "  FAIL: $message"
        return 1
    fi
}

# Assert that two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $message"
        return 0
    else
        echo "  FAIL: $message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    if [[ -f "$file" ]]; then
        echo "  PASS: $message"
        return 0
    else
        echo "  FAIL: $message"
        return 1
    fi
}

# Assert that a file contains a string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain pattern}"

    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $message"
        return 0
    else
        echo "  FAIL: $message (pattern: '$pattern' not found in $file)"
        return 1
    fi
}

# Assert that a command exits with expected code
assert_exit_code() {
    local expected="$1"
    shift
    local message="${*: -1}"
    set -- "${@:1:$#-1}"

    set +e
    "$@" >/dev/null 2>&1
    local actual=$?
    set -e

    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $message"
        return 0
    else
        echo "  FAIL: $message (expected exit code: $expected, got: $actual)"
        return 1
    fi
}

# Run if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Mock environment script"
    echo ""
    echo "This script should be sourced, not executed directly."
    echo ""
    echo "Usage:"
    echo "  source tests/mock-environment.sh"
    echo "  setup_mock_environment"
    echo "  # ... run tests ..."
    echo "  cleanup_mock_environment"
fi
