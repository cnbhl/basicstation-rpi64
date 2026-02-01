# GPIO Brute Force Test Plan for PG1302 on Pi 4

## Objective

Systematically test GPIO combinations to find the correct initialization sequence for PG1302 on BCM2711 (Pi 4). The module works on BCM2835 (Pi Zero) but fails on Pi 4 with SPI MISO returning all zeros.

## GPIO Classification

### Hard-Wired (DO NOT TEST)

These GPIOs are managed by kernel drivers and must not be modified:

| BCM | Function | Why |
|-----|----------|-----|
| 2 | I2C_SDA | Kernel I2C driver |
| 3 | I2C_SCL | Kernel I2C driver |
| 7 | SX1261_NSS (SPI CS1) | Kernel SPI driver |
| 8 | HOST_CSN (SPI CS0) | Kernel SPI driver |
| 9 | HOST_MISO | Kernel SPI driver |
| 10 | HOST_MOSI | Kernel SPI driver |
| 11 | HOST_SCK | Kernel SPI driver |
| 14 | GPS_TXD | Kernel UART driver |
| 15 | GPS_RXD | Kernel UART driver |

### Currently Controlled (Known)

| BCM | Function | Current Behavior |
|-----|----------|------------------|
| 22 | SX1261_NRESET | Drive HIGH (release reset) |
| 23 | SX1302_RESET | Pulse HIGH→LOW (reset) |
| 27 | POWER_EN | Drive HIGH (power on) |

### Test Candidates

| BCM | Function | Priority | Rationale |
|-----|----------|----------|-----------|
| **4** | MCU_NRESET | **HIGH** | Documented but never used - could be required on BCM2711 |
| 5 | LORAWAN (LED?) | Medium | Unknown function, might affect power state |
| 6 | WAN (LED?) | Medium | Unknown function, might affect power state |
| 17 | SX1261_BUSY | Low | Normally input, but might need pull-up/down |
| 18 | PPS | Low | GPS input, unlikely to affect SPI |
| 24 | SX1261_DIO1 | Low | Input, unlikely to affect core init |
| 25 | SX1261_DIO2 | Low | Input, unlikely to affect core init |

## Test Phases

### Phase 1: BCM 4 (MCU_NRESET) - HIGH PRIORITY

BCM 4 is documented as "MCU_NRESET" on the PG1302 pinout but our reset script never touches it. This is the most likely candidate.

#### Test 1.1: Hold BCM 4 HIGH during init
```bash
# Hypothesis: MCU needs to be held out of reset
gpioset gpiochip0 4=1 27=1 22=1  # Power on, MCU not reset, SX1261 not reset
sleep 0.5
gpioset gpiochip0 23=1  # SX1302 reset HIGH
sleep 0.1
gpioset gpiochip0 23=0  # SX1302 reset LOW (release)
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 1.2: Pulse BCM 4 like other resets
```bash
# Hypothesis: MCU needs a reset pulse
gpioset gpiochip0 27=1 4=1 22=1
sleep 0.5
gpioset gpiochip0 4=0  # MCU reset
sleep 0.1
gpioset gpiochip0 4=1  # MCU release
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 1.3: Hold BCM 4 LOW during init
```bash
# Hypothesis: MCU should be held in reset during SX1302 init
gpioset gpiochip0 27=1 4=0 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 1.4: BCM 4 reset BEFORE power on
```bash
# Hypothesis: MCU must be reset before power enable
gpioset gpiochip0 4=0  # MCU reset first
sleep 0.1
gpioset gpiochip0 27=1  # Then power on
sleep 0.5
gpioset gpiochip0 4=1 22=1  # Release MCU reset
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

### Phase 2: BCM 5, 6 (Unknown Pins)

These are labeled as LED pins but may have other functions.

#### Test 2.1: Both HIGH
```bash
gpioset gpiochip0 5=1 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 2.2: Both LOW
```bash
gpioset gpiochip0 5=0 6=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 2.3: BCM 5 HIGH, BCM 6 LOW
```bash
gpioset gpiochip0 5=1 6=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 2.4: BCM 5 LOW, BCM 6 HIGH
```bash
gpioset gpiochip0 5=0 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

### Phase 3: Combined BCM 4 + BCM 5/6

If Phase 1 or 2 shows partial success, test combinations.

#### Test 3.1: All extra GPIOs HIGH
```bash
gpioset gpiochip0 4=1 5=1 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 3.2: BCM 4 pulsed, 5/6 HIGH
```bash
gpioset gpiochip0 5=1 6=1 27=1 22=1
gpioset gpiochip0 4=0 && sleep 0.1 && gpioset gpiochip0 4=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

### Phase 4: Input Pins as Outputs (Low Priority)

Only if Phase 1-3 fail. These are normally inputs but may need to be driven.

#### Test 4.1: BCM 17 (BUSY) driven LOW
```bash
gpioset gpiochip0 17=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

#### Test 4.2: BCM 17 (BUSY) driven HIGH
```bash
gpioset gpiochip0 17=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
./chip_id -d /dev/spidev0.0
```

### Phase 5: Power Sequencing Variations

Test different power-on sequences with the extra GPIOs.

#### Test 5.1: Full sequence with BCM 4
```bash
# Complete power-down
gpioset gpiochip0 27=0 4=0 22=0 23=1
sleep 3

# Power-up sequence
gpioset gpiochip0 4=1    # MCU out of reset first
sleep 0.1
gpioset gpiochip0 27=1   # Then power on
sleep 0.5
gpioset gpiochip0 22=1   # Then SX1261 out of reset
sleep 0.1
gpioset gpiochip0 23=0   # Then SX1302 out of reset
sleep 0.5

./chip_id -d /dev/spidev0.0
```

#### Test 5.2: Reverse order
```bash
# Complete power-down
gpioset gpiochip0 27=0 4=0 22=0 23=1
sleep 3

# Alternative power-up sequence
gpioset gpiochip0 27=1   # Power on first
sleep 0.5
gpioset gpiochip0 23=0   # SX1302 out of reset
sleep 0.1
gpioset gpiochip0 22=1   # SX1261 out of reset
sleep 0.1
gpioset gpiochip0 4=1    # MCU out of reset last
sleep 0.5

./chip_id -d /dev/spidev0.0
```

## Automated Test Script

Save as `tools/gpio-brute-force.sh`:

```bash
#!/bin/bash
# GPIO Brute Force Test for PG1302 on Pi 4
# Tests all reasonable GPIO combinations to find working init sequence

set -euo pipefail

CHIP_ID="${1:-./chip_id}"
SPI_DEV="${2:-/dev/spidev0.0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Cleanup GPIOs on exit
cleanup() {
    # Release all GPIOs by setting to input
    for pin in 4 5 6 17 22 23 27; do
        gpioset gpiochip0 $pin=0 2>/dev/null || true
    done
}
trap cleanup EXIT

# Run chip_id and check result
run_test() {
    local test_name="$1"
    local result

    log_test "$test_name"

    # Capture output and exit code
    if result=$("$CHIP_ID" -d "$SPI_DEV" 2>&1); then
        if echo "$result" | grep -q "chip version is 0x10"; then
            log_pass "$test_name - chip version 0x10!"
            echo "$result"
            echo ""
            echo "SUCCESS! Working configuration found with: $test_name"
            return 0
        fi
    fi

    # Extract chip version for logging
    local version=$(echo "$result" | grep "chip version" | head -1)
    log_fail "$test_name - $version"
    return 1
}

# Full power down
power_down() {
    gpioset gpiochip0 27=0 4=0 22=0 5=0 6=0 17=0
    gpioset gpiochip0 23=1  # Reset active
    sleep 2
}

echo "=================================="
echo "PG1302 GPIO Brute Force Test"
echo "=================================="
echo "chip_id: $CHIP_ID"
echo "SPI device: $SPI_DEV"
echo ""

# Phase 1: BCM 4 (MCU_NRESET) tests
echo ""
echo "=== PHASE 1: BCM 4 (MCU_NRESET) ==="

power_down
gpioset gpiochip0 4=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "1.1: BCM4=HIGH throughout" || true

power_down
gpioset gpiochip0 27=1 22=1
gpioset gpiochip0 4=0 && sleep 0.1 && gpioset gpiochip0 4=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "1.2: BCM4 pulsed LOW->HIGH" || true

power_down
gpioset gpiochip0 27=1 4=0 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "1.3: BCM4=LOW throughout" || true

power_down
gpioset gpiochip0 4=0
sleep 0.1
gpioset gpiochip0 27=1
sleep 0.5
gpioset gpiochip0 4=1 22=1
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "1.4: BCM4 reset before power" || true

# Phase 2: BCM 5, 6 tests
echo ""
echo "=== PHASE 2: BCM 5, 6 (Unknown) ==="

power_down
gpioset gpiochip0 5=1 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "2.1: BCM5=HIGH, BCM6=HIGH" || true

power_down
gpioset gpiochip0 5=0 6=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "2.2: BCM5=LOW, BCM6=LOW" || true

power_down
gpioset gpiochip0 5=1 6=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "2.3: BCM5=HIGH, BCM6=LOW" || true

power_down
gpioset gpiochip0 5=0 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "2.4: BCM5=LOW, BCM6=HIGH" || true

# Phase 3: Combined BCM 4 + 5 + 6
echo ""
echo "=== PHASE 3: Combined BCM 4+5+6 ==="

power_down
gpioset gpiochip0 4=1 5=1 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "3.1: All HIGH (4,5,6)" || true

power_down
gpioset gpiochip0 5=1 6=1 27=1 22=1
gpioset gpiochip0 4=0 && sleep 0.1 && gpioset gpiochip0 4=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "3.2: BCM4 pulsed, 5+6 HIGH" || true

power_down
gpioset gpiochip0 4=0 5=1 6=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "3.3: BCM4=LOW, 5+6 HIGH" || true

# Phase 4: Input pins as outputs
echo ""
echo "=== PHASE 4: Input pins driven ==="

power_down
gpioset gpiochip0 17=0 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "4.1: BCM17 (BUSY) = LOW" || true

power_down
gpioset gpiochip0 17=1 27=1 22=1
sleep 0.5
gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
sleep 0.5
run_test "4.2: BCM17 (BUSY) = HIGH" || true

# Phase 5: Power sequencing
echo ""
echo "=== PHASE 5: Power sequencing ==="

power_down
gpioset gpiochip0 4=1
sleep 0.1
gpioset gpiochip0 27=1
sleep 0.5
gpioset gpiochip0 22=1
sleep 0.1
gpioset gpiochip0 23=0
sleep 0.5
run_test "5.1: MCU->Power->SX1261->SX1302" || true

power_down
gpioset gpiochip0 27=1
sleep 0.5
gpioset gpiochip0 23=0
sleep 0.1
gpioset gpiochip0 22=1
sleep 0.1
gpioset gpiochip0 4=1
sleep 0.5
run_test "5.2: Power->SX1302->SX1261->MCU" || true

# Phase 6: Exhaustive BCM 4,5,6 combinations
echo ""
echo "=== PHASE 6: Exhaustive 4,5,6 combos ==="

for b4 in 0 1; do
    for b5 in 0 1; do
        for b6 in 0 1; do
            power_down
            gpioset gpiochip0 4=$b4 5=$b5 6=$b6 27=1 22=1
            sleep 0.5
            gpioset gpiochip0 23=1 && sleep 0.1 && gpioset gpiochip0 23=0
            sleep 0.5
            run_test "6.x: BCM4=$b4, BCM5=$b5, BCM6=$b6" || true
        done
    done
done

echo ""
echo "=================================="
echo "All tests completed"
echo "=================================="
```

## Expected Results

- **Success**: `chip version is 0x10 (v1.0)`
- **Failure**: `chip version is 0x00 (v0.0)` or SX1250 STANDBY_RC error

## If All Tests Fail

If brute-force GPIO testing fails, the issue is likely:

1. **SPI signal integrity** - BCM2711 SPI electrical characteristics differ from BCM2835
2. **Power supply** - 3.3V rail differences between Pi models
3. **Hardware defect** - specific to this PG1302 unit on BCM2711

Next steps would require:
- Oscilloscope analysis of SPI signals
- Voltage level measurements
- Testing with a different PG1302 unit

## References

- [Dragino PG1302 Pin Mapping](https://wiki.dragino.com/xwiki/bin/view/Main/User%20Manual%20for%20All%20Gateway%20models/PG1302/)
- [SX1250_INIT_INVESTIGATION.md](./SX1250_INIT_INVESTIGATION.md)
