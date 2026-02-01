#!/bin/bash
# GPIO Brute Force Test for PG1302 on Pi 4
# Tests all reasonable GPIO combinations to find working init sequence
#
# Usage: sudo ./gpio-brute-force.sh [chip_id_path] [spi_device]
#
# The PG1302 works on Pi Zero but fails on Pi 4 with SPI MISO returning zeros.
# This script tests various GPIO configurations including:
# - BCM 4 (MCU_NRESET) - documented but never used in reset scripts
# - BCM 5, 6 - labeled as LEDs but function unknown
# - Various power sequencing combinations

set -euo pipefail

# Defaults
CHIP_ID="${1:-./chip_id}"
SPI_DEV="${2:-/dev/spidev0.0}"
DELAY_POWER="${DELAY_POWER:-2}"      # Power down duration (seconds)
DELAY_SETTLE="${DELAY_SETTLE:-0.5}"  # Settling time after changes
DELAY_RESET="${DELAY_RESET:-0.1}"    # Reset pulse width

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Cleanup GPIOs on exit
cleanup() {
    log_info "Cleaning up GPIOs..."
    # Set all test pins to input mode (safe state)
    for pin in 4 5 6 17 22 23 27; do
        # gpioset releases line when it exits, so just ensure power is off
        gpioset gpiochip0 27=0 2>/dev/null || true
    done
}
trap cleanup EXIT

# Check prerequisites
check_prereqs() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (sudo)"
        exit 1
    fi

    if ! command -v gpioset &>/dev/null; then
        echo "gpioset not found. Install with: apt install gpiod"
        exit 1
    fi

    if [[ ! -x "$CHIP_ID" ]]; then
        echo "chip_id not found or not executable: $CHIP_ID"
        echo "Build with: make platform=corecell variant=std"
        exit 1
    fi

    if [[ ! -c "$SPI_DEV" ]]; then
        echo "SPI device not found: $SPI_DEV"
        echo "Enable SPI with: raspi-config"
        exit 1
    fi
}

# Run chip_id and check result
# Returns 0 on success (chip version 0x10), 1 on failure
run_test() {
    local test_name="$1"
    local result
    local exit_code=0

    ((++TESTS_RUN))
    log_test "$test_name"

    # Capture output and exit code
    result=$("$CHIP_ID" -d "$SPI_DEV" 2>&1) || exit_code=$?

    # Check for success (chip version 0x10)
    if echo "$result" | grep -q "chip version is 0x10"; then
        ((++TESTS_PASSED))
        log_pass "$test_name - chip version 0x10!"
        echo ""
        echo "=============================================="
        echo -e "${GREEN}SUCCESS! Working configuration found!${NC}"
        echo "Test: $test_name"
        echo "=============================================="
        echo ""
        echo "Full output:"
        echo "$result"
        return 0
    fi

    # Extract chip version for logging
    local version
    version=$(echo "$result" | grep "chip version" | head -1 || echo "no version")
    ((++TESTS_FAILED))
    log_fail "$test_name - $version"
    return 1
}

# Full power down - all control GPIOs to safe/off state
power_down() {
    # Power off, resets active (active low for NRESET pins)
    gpioset gpiochip0 27=0  # POWER_EN off
    gpioset gpiochip0 23=1  # SX1302 RESET active (high = in reset)
    gpioset gpiochip0 22=0  # SX1261 RESET active (assuming active low)
    gpioset gpiochip0 4=0   # MCU RESET active (assuming active low)
    gpioset gpiochip0 5=0   # Unknown, set low
    gpioset gpiochip0 6=0   # Unknown, set low
    sleep "$DELAY_POWER"
}

# Standard reset sequence (what we currently do)
standard_reset() {
    gpioset gpiochip0 23=1  # Reset high
    sleep "$DELAY_RESET"
    gpioset gpiochip0 23=0  # Reset low (release)
    sleep "$DELAY_SETTLE"
}

# Print current GPIO states
show_gpio_state() {
    log_info "Current GPIO states:"
    for pin in 4 5 6 17 22 23 27; do
        local state
        state=$(gpioget gpiochip0 "$pin" 2>/dev/null || echo "?")
        echo "  BCM $pin: $state"
    done
}

# ============================================================================
# TEST PHASES
# ============================================================================

phase1_bcm4() {
    echo ""
    echo "=============================================="
    echo "PHASE 1: BCM 4 (MCU_NRESET) Tests"
    echo "=============================================="
    echo "BCM 4 is documented as MCU_NRESET but never used."
    echo "This is the most likely missing piece."
    echo ""

    # Test 1.1: Hold BCM 4 HIGH during init
    power_down
    gpioset gpiochip0 4=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "1.1: BCM4=HIGH throughout" && return 0

    # Test 1.2: Pulse BCM 4 LOW->HIGH
    power_down
    gpioset gpiochip0 27=1 22=1
    gpioset gpiochip0 4=0
    sleep "$DELAY_RESET"
    gpioset gpiochip0 4=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "1.2: BCM4 pulsed LOW->HIGH" && return 0

    # Test 1.3: Hold BCM 4 LOW during init
    power_down
    gpioset gpiochip0 27=1 4=0 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "1.3: BCM4=LOW throughout" && return 0

    # Test 1.4: BCM 4 reset BEFORE power on
    power_down
    gpioset gpiochip0 4=0  # MCU reset first
    sleep "$DELAY_RESET"
    gpioset gpiochip0 27=1  # Then power on
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 4=1 22=1  # Release MCU reset
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "1.4: BCM4 reset before power" && return 0

    # Test 1.5: Pulse BCM 4 HIGH->LOW->HIGH
    power_down
    gpioset gpiochip0 27=1 22=1 4=1
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 4=0
    sleep "$DELAY_RESET"
    gpioset gpiochip0 4=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "1.5: BCM4 pulse HIGH->LOW->HIGH after power" && return 0

    return 1
}

phase2_bcm5_6() {
    echo ""
    echo "=============================================="
    echo "PHASE 2: BCM 5, 6 (Unknown Pins) Tests"
    echo "=============================================="
    echo "These are labeled as LEDs but may have other functions."
    echo ""

    # Test 2.1: Both HIGH
    power_down
    gpioset gpiochip0 5=1 6=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "2.1: BCM5=HIGH, BCM6=HIGH" && return 0

    # Test 2.2: Both LOW
    power_down
    gpioset gpiochip0 5=0 6=0 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "2.2: BCM5=LOW, BCM6=LOW" && return 0

    # Test 2.3: BCM 5 HIGH, BCM 6 LOW
    power_down
    gpioset gpiochip0 5=1 6=0 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "2.3: BCM5=HIGH, BCM6=LOW" && return 0

    # Test 2.4: BCM 5 LOW, BCM 6 HIGH
    power_down
    gpioset gpiochip0 5=0 6=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "2.4: BCM5=LOW, BCM6=HIGH" && return 0

    return 1
}

phase3_combined() {
    echo ""
    echo "=============================================="
    echo "PHASE 3: Combined BCM 4+5+6 Tests"
    echo "=============================================="
    echo ""

    # Test 3.1: All extra GPIOs HIGH
    power_down
    gpioset gpiochip0 4=1 5=1 6=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "3.1: All HIGH (4,5,6)" && return 0

    # Test 3.2: BCM 4 pulsed, 5/6 HIGH
    power_down
    gpioset gpiochip0 5=1 6=1 27=1 22=1
    gpioset gpiochip0 4=0
    sleep "$DELAY_RESET"
    gpioset gpiochip0 4=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "3.2: BCM4 pulsed, 5+6 HIGH" && return 0

    # Test 3.3: BCM 4 LOW, 5+6 HIGH
    power_down
    gpioset gpiochip0 4=0 5=1 6=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "3.3: BCM4=LOW, 5+6 HIGH" && return 0

    # Test 3.4: BCM 4 HIGH, 5+6 LOW
    power_down
    gpioset gpiochip0 4=1 5=0 6=0 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "3.4: BCM4=HIGH, 5+6 LOW" && return 0

    return 1
}

phase4_input_pins() {
    echo ""
    echo "=============================================="
    echo "PHASE 4: Input Pins Driven as Outputs"
    echo "=============================================="
    echo "These are normally inputs but may need pull-up/down."
    echo ""

    # Test 4.1: BCM 17 (BUSY) driven LOW
    power_down
    gpioset gpiochip0 17=0 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "4.1: BCM17 (BUSY) = LOW" && return 0

    # Test 4.2: BCM 17 (BUSY) driven HIGH
    power_down
    gpioset gpiochip0 17=1 27=1 22=1
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "4.2: BCM17 (BUSY) = HIGH" && return 0

    return 1
}

phase5_sequencing() {
    echo ""
    echo "=============================================="
    echo "PHASE 5: Power Sequencing Variations"
    echo "=============================================="
    echo ""

    # Test 5.1: MCU first, then power, then radios
    power_down
    gpioset gpiochip0 4=1    # MCU out of reset first
    sleep "$DELAY_RESET"
    gpioset gpiochip0 27=1   # Then power on
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 22=1   # Then SX1261 out of reset
    sleep "$DELAY_RESET"
    gpioset gpiochip0 23=1
    sleep "$DELAY_RESET"
    gpioset gpiochip0 23=0   # Then SX1302 reset pulse
    sleep "$DELAY_SETTLE"
    run_test "5.1: MCU->Power->SX1261->SX1302" && return 0

    # Test 5.2: Power first, then resets
    power_down
    gpioset gpiochip0 27=1   # Power on first
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 23=1
    sleep "$DELAY_RESET"
    gpioset gpiochip0 23=0   # SX1302 reset
    sleep "$DELAY_RESET"
    gpioset gpiochip0 22=1   # SX1261 out of reset
    sleep "$DELAY_RESET"
    gpioset gpiochip0 4=1    # MCU out of reset last
    sleep "$DELAY_SETTLE"
    run_test "5.2: Power->SX1302->SX1261->MCU" && return 0

    # Test 5.3: Long delays (1 second each)
    power_down
    sleep 3  # Extra long power off
    gpioset gpiochip0 27=1 22=1 4=1
    sleep 1
    gpioset gpiochip0 23=1
    sleep 1
    gpioset gpiochip0 23=0
    sleep 1
    run_test "5.3: Long delays (1s each step)" && return 0

    return 1
}

phase6_exhaustive() {
    echo ""
    echo "=============================================="
    echo "PHASE 6: Exhaustive BCM 4,5,6 Combinations"
    echo "=============================================="
    echo "Testing all 8 combinations of BCM 4, 5, 6"
    echo ""

    for b4 in 0 1; do
        for b5 in 0 1; do
            for b6 in 0 1; do
                power_down
                gpioset gpiochip0 4=$b4 5=$b5 6=$b6 27=1 22=1
                sleep "$DELAY_SETTLE"
                standard_reset
                run_test "6.x: BCM4=$b4, BCM5=$b5, BCM6=$b6" && return 0
            done
        done
    done

    return 1
}

phase7_sx1261_variations() {
    echo ""
    echo "=============================================="
    echo "PHASE 7: SX1261 Reset Variations"
    echo "=============================================="
    echo "Testing different SX1261 (BCM 22) reset sequences"
    echo ""

    # Test 7.1: SX1261 pulsed before SX1302
    power_down
    gpioset gpiochip0 27=1
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 22=0  # SX1261 reset
    sleep "$DELAY_RESET"
    gpioset gpiochip0 22=1  # SX1261 release
    sleep "$DELAY_SETTLE"
    standard_reset
    run_test "7.1: SX1261 pulsed before SX1302" && return 0

    # Test 7.2: SX1261 held low during SX1302 reset
    power_down
    gpioset gpiochip0 27=1 22=0
    sleep "$DELAY_SETTLE"
    standard_reset
    gpioset gpiochip0 22=1  # Release after SX1302
    sleep "$DELAY_SETTLE"
    run_test "7.2: SX1261 held low during SX1302 reset" && return 0

    # Test 7.3: Both reset simultaneously
    power_down
    gpioset gpiochip0 27=1
    sleep "$DELAY_SETTLE"
    gpioset gpiochip0 22=0 23=1  # Both reset active
    sleep "$DELAY_RESET"
    gpioset gpiochip0 22=1 23=0  # Both release
    sleep "$DELAY_SETTLE"
    run_test "7.3: SX1261+SX1302 reset simultaneously" && return 0

    return 1
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    check_prereqs

    echo "=============================================="
    echo "PG1302 GPIO Brute Force Test"
    echo "=============================================="
    echo ""
    echo "Configuration:"
    echo "  chip_id:    $CHIP_ID"
    echo "  SPI device: $SPI_DEV"
    echo "  Power off:  ${DELAY_POWER}s"
    echo "  Settle:     ${DELAY_SETTLE}s"
    echo "  Reset:      ${DELAY_RESET}s"
    echo ""
    echo "Testing GPIOs:"
    echo "  BCM 4:  MCU_NRESET (documented but unused)"
    echo "  BCM 5:  LORAWAN LED (unknown)"
    echo "  BCM 6:  WAN LED (unknown)"
    echo "  BCM 17: SX1261_BUSY (normally input)"
    echo "  BCM 22: SX1261_NRESET (known)"
    echo "  BCM 23: SX1302_RESET (known)"
    echo "  BCM 27: POWER_EN (known)"
    echo ""

    # Run phases, stop on first success
    phase1_bcm4 && exit 0
    phase2_bcm5_6 && exit 0
    phase3_combined && exit 0
    phase4_input_pins && exit 0
    phase5_sequencing && exit 0
    phase6_exhaustive && exit 0
    phase7_sx1261_variations && exit 0

    echo ""
    echo "=============================================="
    echo "All tests completed - no working configuration found"
    echo "=============================================="
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""
    echo "If all GPIO combinations fail, the issue is likely:"
    echo "  1. SPI signal integrity (BCM2711 vs BCM2835 differences)"
    echo "  2. Power supply characteristics"
    echo "  3. Hardware-level incompatibility"
    echo ""
    echo "Next steps:"
    echo "  - Oscilloscope analysis of SPI signals"
    echo "  - Voltage level measurements"
    echo "  - Test with a different PG1302 unit"

    exit 1
}

main "$@"
