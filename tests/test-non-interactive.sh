#!/bin/bash
#
# test-non-interactive.sh - Integration tests for non-interactive mode
#
# This script tests the non-interactive setup mode end-to-end.
#
# Usage:
#   ./tests/test-non-interactive.sh           # Run all tests
#   ./tests/test-non-interactive.sh -v        # Verbose output
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

# Test temp directory
TEST_TEMP=""

#######################################
# Test Framework
#######################################

run_test() {
    local test_name="$1"
    local test_func="$2"

    ((TESTS_RUN++))
    echo ""
    echo "Running: $test_name"

    if $test_func; then
        ((TESTS_PASSED++))
        echo "  Result: PASSED"
    else
        ((TESTS_FAILED++))
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
    echo "Setting up test environment..."

    # Create temporary test directory
    TEST_TEMP=$(mktemp -d)
    export TEST_TEMP

    # Create mock cups-ttn directory structure
    mkdir -p "$TEST_TEMP/cups-ttn"
    mkdir -p "$TEST_TEMP/build-corecell-std/bin"

    # Copy template files
    cp "$SCRIPT_DIR/examples/corecell/cups-ttn/board.conf.template" "$TEST_TEMP/cups-ttn/"
    cp "$SCRIPT_DIR/examples/corecell/cups-ttn/station.conf.template" "$TEST_TEMP/cups-ttn/" 2>/dev/null || \
        echo '{"station_conf":{"routerid":"{{GATEWAY_EUI}}"}}' > "$TEST_TEMP/cups-ttn/station.conf.template"

    # Create mock station binary
    echo "#!/bin/bash" > "$TEST_TEMP/build-corecell-std/bin/station"
    echo "echo 'Mock station'" >> "$TEST_TEMP/build-corecell-std/bin/station"
    chmod +x "$TEST_TEMP/build-corecell-std/bin/station"

    # Setup mock environment (chip_id, sudo, systemctl, etc.)
    setup_mock_environment

    echo "Test environment ready at $TEST_TEMP"
}

teardown_test_env() {
    echo "Cleaning up test environment..."

    # Cleanup mock environment
    cleanup_mock_environment

    # Clean up temporary directory
    if [[ -n "${TEST_TEMP:-}" && -d "$TEST_TEMP" ]]; then
        rm -rf "$TEST_TEMP"
    fi
}

#######################################
# Argument Parsing Tests
#######################################

test_help_flag() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1) || true

    # Check that help output contains expected content
    [[ "$output" == *"Non-Interactive Mode"* ]] && \
    [[ "$output" == *"--board"* ]] && \
    [[ "$output" == *"--region"* ]] && \
    [[ "$output" == *"--eui"* ]] && \
    [[ "$output" == *"--cups-key"* ]]
}

test_missing_required_args() {
    local result=true

    # Run with -y but missing required args - should fail
    if "$SCRIPT_DIR/setup-gateway.sh" -y 2>&1 | grep -q "Missing or invalid arguments"; then
        result=true
    else
        result=false
    fi

    $result
}

test_invalid_board() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board INVALID_BOARD \
        --region eu1 \
        --eui AABBCCDDEEFF0011 \
        --cups-key "test-key" \
        --no-service 2>&1) || true

    [[ "$output" == *"Invalid board type"* ]]
}

test_invalid_region() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region invalid \
        --eui AABBCCDDEEFF0011 \
        --cups-key "test-key" \
        --no-service 2>&1) || true

    [[ "$output" == *"Invalid region"* ]]
}

test_invalid_eui() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region eu1 \
        --eui "INVALID" \
        --cups-key "test-key" \
        --no-service 2>&1) || true

    [[ "$output" == *"Invalid EUI"* ]]
}

test_missing_cups_key() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region eu1 \
        --eui AABBCCDDEEFF0011 \
        --no-service 2>&1) || true

    [[ "$output" == *"--cups-key or --cups-key-file is required"* ]]
}

test_missing_service_flag() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region eu1 \
        --eui AABBCCDDEEFF0011 \
        --cups-key "test-key" 2>&1) || true

    [[ "$output" == *"--service or --no-service is required"* ]]
}

#######################################
# CUPS Key File Tests
#######################################

test_cups_key_file_valid() {
    local key_file="$TEST_TEMP/cups.key"
    echo "NNSXS.test-key-from-file" > "$key_file"

    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region eu1 \
        --eui AABBCCDDEEFF0011 \
        --cups-key-file "$key_file" \
        --no-service \
        --skip-deps 2>&1) || true

    # Should not error about missing cups key
    [[ "$output" != *"--cups-key or --cups-key-file is required"* ]]
}

test_cups_key_file_not_found() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" -y \
        --board WM1302 \
        --region eu1 \
        --eui AABBCCDDEEFF0011 \
        --cups-key-file "/nonexistent/path/cups.key" \
        --no-service 2>&1) || true

    [[ "$output" == *"CUPS key file not found"* ]]
}

#######################################
# GPS Option Tests
#######################################

test_gps_none() {
    # Test that --gps none is accepted
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1)

    [[ "$output" == *"--gps <device|none>"* ]]
}

#######################################
# Force Overwrite Tests
#######################################

test_force_flag_accepted() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1)

    [[ "$output" == *"--force"* ]] && \
    [[ "$output" == *"Overwrite existing credentials"* ]]
}

#######################################
# Skip Build Tests
#######################################

test_skip_build_flag_accepted() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1)

    [[ "$output" == *"--skip-build"* ]] && \
    [[ "$output" == *"Skip build if binary exists"* ]]
}

#######################################
# Service Flag Tests
#######################################

test_service_flags_accepted() {
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1)

    [[ "$output" == *"--service"* ]] && \
    [[ "$output" == *"--no-service"* ]]
}

#######################################
# Uninstall Tests
#######################################

test_uninstall_non_interactive() {
    # Test that -y flag is documented for uninstall
    local output
    output=$("$SCRIPT_DIR/setup-gateway.sh" --help 2>&1)

    [[ "$output" == *"--uninstall -y"* ]]
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
    echo "Non-Interactive Mode Integration Tests"
    echo "========================================"

    # Setup
    setup_test_env

    # Run argument parsing tests
    run_test "Help flag shows non-interactive options" test_help_flag
    run_test "Missing required args shows error" test_missing_required_args
    run_test "Invalid board type rejected" test_invalid_board
    run_test "Invalid region rejected" test_invalid_region
    run_test "Invalid EUI rejected" test_invalid_eui
    run_test "Missing CUPS key rejected" test_missing_cups_key
    run_test "Missing service flag rejected" test_missing_service_flag

    # CUPS key file tests
    run_test "CUPS key file - valid file" test_cups_key_file_valid
    run_test "CUPS key file - not found" test_cups_key_file_not_found

    # GPS option tests
    run_test "GPS none option documented" test_gps_none

    # Force flag tests
    run_test "Force flag accepted" test_force_flag_accepted

    # Skip build tests
    run_test "Skip build flag accepted" test_skip_build_flag_accepted

    # Service flag tests
    run_test "Service flags accepted" test_service_flags_accepted

    # Uninstall tests
    run_test "Uninstall non-interactive documented" test_uninstall_non_interactive

    # Teardown
    teardown_test_env

    # Print summary
    print_summary
}

main "$@"
