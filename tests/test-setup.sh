#!/bin/bash
#
# test-setup.sh - Unit tests for setup-gateway.sh functions
#
# This script tests individual functions from the setup libraries.
#
# Usage:
#   ./tests/test-setup.sh           # Run all tests
#   ./tests/test-setup.sh -v        # Verbose output
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source mock environment
source "$TEST_DIR/mock-environment.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=false

#######################################
# Test Framework
#######################################

run_test() {
    local test_name="$1"
    local test_func="$2"

    (( ++TESTS_RUN ))
    echo ""
    echo "Running: $test_name"

    if $test_func; then
        (( ++TESTS_PASSED ))
        echo "  Result: PASSED"
    else
        (( ++TESTS_FAILED ))
        echo "  Result: FAILED"
    fi
}

print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "  Total:  $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "All tests passed!"
        return 0
    else
        echo "Some tests failed."
        return 1
    fi
}

#######################################
# Setup/Teardown
#######################################

setup_test_env() {
    # Create temporary test directory
    TEST_TEMP=$(mktemp -d)
    export TEST_TEMP

    # Source the library files
    source "$SCRIPT_DIR/lib/common.sh"
    source "$SCRIPT_DIR/lib/validation.sh"

    # Set required global variables
    export BOARD_CONF_TEMPLATE="$SCRIPT_DIR/examples/corecell/cups-ttn/board.conf.template"
    export NON_INTERACTIVE=false
    export CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

    # Initialize logging to temp file
    init_logging "$TEST_TEMP/test.log"
}

teardown_test_env() {
    # Clean up temporary directory
    if [[ -n "${TEST_TEMP:-}" && -d "$TEST_TEMP" ]]; then
        rm -rf "$TEST_TEMP"
    fi
}

#######################################
# Validation Tests
#######################################

test_validate_eui_valid() {
    local result=true

    # Valid EUIs
    validate_eui "AABBCCDDEEFF0011" || result=false
    validate_eui "0123456789ABCDEF" || result=false
    validate_eui "0123456789abcdef" || result=false

    $result
}

test_validate_eui_invalid() {
    local result=true

    # Invalid EUIs (should return false)
    validate_eui "AABBCCDD" && result=false  # Too short
    validate_eui "AABBCCDDEEFF00112233" && result=false  # Too long
    validate_eui "GGHHIIJJKKLLMMNN" && result=false  # Invalid hex chars
    validate_eui "" && result=false  # Empty

    $result
}

test_validate_region_valid() {
    local result=true

    validate_region "eu1" || result=false
    validate_region "nam1" || result=false
    validate_region "au1" || result=false

    $result
}

test_validate_region_invalid() {
    local result=true

    validate_region "eu2" && result=false
    validate_region "us1" && result=false
    validate_region "EUR" && result=false
    validate_region "" && result=false

    $result
}

test_validate_board_type_valid() {
    local result=true

    validate_board_type "WM1302" || result=false
    validate_board_type "PG1302" || result=false
    validate_board_type "LR1302" || result=false
    validate_board_type "SX1302_WS" || result=false
    validate_board_type "SEMTECH" || result=false

    $result
}

test_validate_board_type_invalid() {
    local result=true

    validate_board_type "INVALID_BOARD" && result=false
    validate_board_type "wm1302" && result=false  # Case sensitive
    validate_board_type "" && result=false

    $result
}

test_validate_gpio_valid() {
    local result=true

    validate_gpio "0" || result=false
    validate_gpio "17" || result=false
    validate_gpio "27" || result=false

    $result
}

test_validate_gpio_invalid() {
    local result=true

    validate_gpio "28" && result=false
    validate_gpio "-1" && result=false
    validate_gpio "abc" && result=false
    validate_gpio "" && result=false

    $result
}

test_get_board_config() {
    local result=true

    # Test getting config for a known board
    if get_board_config "WM1302"; then
        [[ "$SX1302_RESET_BCM" == "17" ]] || result=false
        [[ "$SX1302_POWER_EN_BCM" == "18" ]] || result=false
    else
        result=false
    fi

    $result
}

#######################################
# Sanitization Tests
#######################################

test_sanitize_for_sed() {
    local result=true

    # Test basic string (no special chars)
    local input="hello"
    local sanitized
    sanitized=$(sanitize_for_sed "$input")
    [[ "$sanitized" == "hello" ]] || result=false

    # Test string with forward slash
    input="path/to/file"
    sanitized=$(sanitize_for_sed "$input")
    [[ "$sanitized" == "path\\/to\\/file" ]] || result=false

    # Test string with ampersand
    input="foo&bar"
    sanitized=$(sanitize_for_sed "$input")
    [[ "$sanitized" == "foo\\&bar" ]] || result=false

    $result
}

#######################################
# Confirm Function Tests
#######################################

test_confirm_non_interactive_default_yes() {
    NON_INTERACTIVE=true
    local result=true

    # With default "y", should return true (0)
    if confirm "Test?" "y"; then
        result=true
    else
        result=false
    fi

    NON_INTERACTIVE=false
    $result
}

test_confirm_non_interactive_default_no() {
    NON_INTERACTIVE=true
    local result=true

    # With default "n", should return false (1)
    if confirm "Test?" "n"; then
        result=false
    else
        result=true
    fi

    NON_INTERACTIVE=false
    $result
}

#######################################
# File Check Tests
#######################################

test_file_exists() {
    local result=true

    # Create a test file
    echo "test" > "$TEST_TEMP/testfile"

    file_exists "$TEST_TEMP/testfile" || result=false
    file_exists "$TEST_TEMP/nonexistent" && result=false

    $result
}

test_dir_exists() {
    local result=true

    mkdir -p "$TEST_TEMP/testdir"

    dir_exists "$TEST_TEMP/testdir" || result=false
    dir_exists "$TEST_TEMP/nonexistent" && result=false

    $result
}

test_command_exists() {
    local result=true

    command_exists "bash" || result=false
    command_exists "nonexistent_command_12345" && result=false

    $result
}

#######################################
# Main
#######################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo "========================================"
    echo "Setup Function Unit Tests"
    echo "========================================"

    # Setup
    setup_test_env

    # Run validation tests
    run_test "validate_eui - valid inputs" test_validate_eui_valid
    run_test "validate_eui - invalid inputs" test_validate_eui_invalid
    run_test "validate_region - valid inputs" test_validate_region_valid
    run_test "validate_region - invalid inputs" test_validate_region_invalid
    run_test "validate_board_type - valid inputs" test_validate_board_type_valid
    run_test "validate_board_type - invalid inputs" test_validate_board_type_invalid
    run_test "validate_gpio - valid inputs" test_validate_gpio_valid
    run_test "validate_gpio - invalid inputs" test_validate_gpio_invalid
    run_test "get_board_config" test_get_board_config

    # Run sanitization tests
    run_test "sanitize_for_sed" test_sanitize_for_sed

    # Run confirm tests
    run_test "confirm - non-interactive default yes" test_confirm_non_interactive_default_yes
    run_test "confirm - non-interactive default no" test_confirm_non_interactive_default_no

    # Run file check tests
    run_test "file_exists" test_file_exists
    run_test "dir_exists" test_dir_exists
    run_test "command_exists" test_command_exists

    # Teardown
    teardown_test_env

    # Print summary
    print_summary
}

main "$@"
