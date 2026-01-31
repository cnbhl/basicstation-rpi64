# SX1250 Initialization Failure Investigation

## Hardware Under Test

- **Concentrator**: PG1302 (Dragino) — SX1302 + dual SX1250
- **Host**: Raspberry Pi 4B (`lorapi4-32`), kernel 6.12.47+rpt-rpi-v7l, **32-bit userspace** (Bookworm)
- **SPI**: `/dev/spidev0.0`
- **GPIO Pins** (from [Dragino PG1302 Pin Mapping](https://wiki.dragino.com/xwiki/bin/view/Main/User%20Manual%20for%20All%20Gateway%20models/PG1302/)):
  - SX1302 RESET: BCM 23 (physical pin 16)
  - POWER_EN: BCM 27 (physical pin 13)
  - SX1261_NRESET: BCM 22 (physical pin 15)

**Reference setup that works**: WM1302 (Seeed) on Raspberry Pi 5 (`raspberrypi`), kernel 6.12.47+rpt-rpi-2712, **64-bit userspace**, same codebase.

**Reported working**: Dragino PG1302 on Raspberry Pi Zero (32-bit), older kernel — using Dragino's native deb package.

## Symptom

`chip_id` and `station` fail during SX1250 radio initialization:
```
ERROR: Failed to set SX1250_0 in STANDBY_RC mode (status=0x00, chipMode=0, expected 2)
```

The SX1302 chip version reads inconsistently (0x00, 0x08, 0x10, or 0xFF depending on attempt), and the SX1250 radio never responds on the SX1302's internal SPI bus.

## Root Cause: GPIO sysfs Deprecation

**The primary root cause is that the GPIO sysfs interface (`/sys/class/gpio/`) is deprecated and unreliable on kernel 6.6+.**

Reference: [Lora-net/sx1302_hal#120](https://github.com/Lora-net/sx1302_hal/issues/120)

### Evidence

| GPIO Method | SX1302 Chip Version | SX1250 Status | Consistency |
|---|---|---|---|
| sysfs (`term; init; reset`) | 0x00 or 0x10 (random) | 0x00 or 0xFF | ~20% success for SX1302, 0% for SX1250 |
| sysfs (proper power cycle) | 0x00 (always) | 0x00 | 0% |
| libgpiod (`gpioset`) | 0x00 or 0x10 | 0x00 | ~20% success for SX1302, 0% for SX1250 |
| libgpiod (no power cycle, just reset) | Not tested yet | — | — |

### What Changed

On kernel 6.6+ (Raspberry Pi OS Bookworm):
- GPIO sysfs (`/sys/class/gpio/export`) is deprecated, superseded by `libgpiod`
- GPIO chip base offset changed: `gpiochip0` (pinctrl-bcm2711) has base 512 on Pi 4, 571 on Pi 5
- The sysfs interface still partially works (exports succeed, values can be written and read back), but **hardware pin behavior is unreliable** — writes may not consistently drive the physical pins
- Source: [The One Where Dave Breaks Stuff](https://waldorf.waveform.org.uk/2022/the-one-where-dave-breaks-stuff.html) (Raspberry Pi kernel team)

### Why the WM1302 on Pi 5 Works

The `fix/gps-json-string` branch was only ever tested with the WM1302 on a Pi 5. It works there because:
1. Different board (WM1302 has different TCXO characteristics)
2. Different GPIO pins (17/18/5 vs 23/27/22)
3. Possibly different kernel behavior for those specific pins
4. The WM1302 may not require POWER_EN GPIO control (always-on)

## Complete PG1302 GPIO Pinout

From Dragino's official pinout diagram (all active GPIO connections):

| BCM | Physical | Function | Direction | Controlled by Dragino deb? |
|-----|----------|----------|-----------|---------------------------|
| 2 | 3 | I2C_SDA | I2C | Kernel driver |
| 3 | 5 | I2C_SCL | I2C | Kernel driver |
| 4 | 7 | MCU_NRESET | Output | **NO** |
| 7 | 26 | SX1261_NSS | SPI CS | Kernel driver |
| 8 | 24 | HOST_CSN (SX1302) | SPI CS | Kernel driver |
| 9 | 21 | HOST_MISO | SPI | Kernel driver |
| 10 | 19 | HOST_MOSI | SPI | Kernel driver |
| 11 | 23 | HOST_SCK | SPI | Kernel driver |
| 14 | 8 | GPS_TXD | UART | Kernel driver |
| 15 | 10 | GPS_RXD | UART | Kernel driver |
| 17 | 11 | SX1261_BUSY | Input | Read by HAL |
| 18 | 12 | PPS | Input | GPS pulse |
| 22 | 15 | SX1261_NRESET | Output | **NO** |
| 23 | 16 | SX1302_RESET | Output | **YES** (only this one!) |
| 24 | 18 | SX1261_DIO1 | Input | Read by HAL |
| 25 | 22 | SX1261_DIO2 | Input | Read by HAL |
| 27 | 13 | POWER_EN | Output | **NO** |
| 5 | 29 | LORAWAN (LED?) | Output | Unknown |
| 6 | 31 | WAN (LED?) | Output | Unknown |

## Two-Level GPIO Architecture

### Level 1: Raspberry Pi GPIOs (controlled by `reset_lgw.sh`)

These are controlled via sysfs or libgpiod from the Pi:

| BCM | Function | Required for init? | Notes |
|-----|----------|-------------------|-------|
| 23 | SX1302_RESET | **YES** | Resets main concentrator chip |
| 27 | POWER_EN | **YES** | Enables LDO power to module |
| 22 | SX1261_NRESET | Optional | Only for LBT/spectral scan |

### Level 2: SX1302 Internal GPIOs (controlled via SPI by HAL)

After the Pi resets the SX1302, the HAL controls the SX1250 radios via SPI commands:

- `sx1302_radio_reset()` → writes to SX1302 registers that toggle internal reset lines
- `sx1250_setup()` → configures SX1250 via SX1302's internal SPI bus
- The SX1250 radios are **slaves of the SX1302**, not directly connected to Pi GPIOs

**Initialization flow:**
1. Pi drives POWER_EN (BCM 27) HIGH → module gets power
2. Pi pulses SX1302_RESET (BCM 23) HIGH→LOW → SX1302 chip resets
3. Pi pulses SX1261_NRESET (BCM 22) if LBT is used
4. HAL calls `lgw_start()` → `sx1302_radio_reset()` via SPI → resets SX1250 internally
5. HAL calls `sx1250_setup()` → configures SX1250 via SPI

## Findings from Dragino's Own Software

Extracted from `draginofwd-64bit.deb` ([download](https://www.dragino.com/downloads/downloads/LoRa_Gateway/PG1302/software/draginofwd-64bit.deb)):

### Dragino's `reset_lgw.sh` (from their deb)

```bash
SX1302_RESET_PIN=23     # Raw BCM number, NO base offset!

reset() {
    echo "1" > /sys/class/gpio/gpio$SX1302_RESET_PIN/value; WAIT_GPIO
    echo "0" > /sys/class/gpio/gpio$SX1302_RESET_PIN/value; WAIT_GPIO
}
```

**Critical differences from our approach:**
1. **Only uses GPIO 23 (RESET)** — no POWER_EN, no SX1261_NRESET
2. **No GPIO base offset** — uses raw BCM numbers (designed for older kernels where base=0)
3. **No power cycling** — just a reset pulse
4. **`WAIT_GPIO` = `sleep 1`** (1 second!) vs our 100ms

This confirms: Dragino's software was designed for older kernels and does not work on kernel 6.6+.

### Why Pi Zero 32-bit Works but Pi 4 32-bit Fails

| Factor | Pi Zero (BCM2835) | Pi 4 (BCM2711) |
|--------|-------------------|----------------|
| GPIO chip base | 0 | 512 (kernel 6.x) |
| `echo 23 > export` | Works → BCM 23 | **Wrong pin** (line 23 ≠ BCM 23) |
| GPIO 27 default pull | Unknown/floating? | **Pull-DOWN** |
| POWER_EN without drive | Module may work | **Module unpowered** |
| Kernel sysfs support | Fully functional | Deprecated, unreliable |

**Critical insight:** Dragino's deb was likely tested on their DLOS8 gateway where:
- POWER_EN may be tied to 3.3V on the PCB (always-on)
- Or tested on older kernels where GPIO base = 0

On a bare Pi + PG1302 HAT setup with modern kernel:
- GPIO 27 (POWER_EN) has a pull-down resistor on BCM2711
- Without active drive HIGH, the concentrator has no power
- Even if GPIO 23 reset works, the module is off

### Dragino's `station.conf`

Uses `/dev/spidev1.0` (not `/dev/spidev0.0`) — likely designed for their DLOS8 gateway product, not a bare Pi + PG1302 setup.

### Analysis of `libsx1302hal.so` (from deb)

The HAL library contains these GPIO-related functions:

```
mcu_gpio_write          # Write to SX1302 MCU internal GPIO (via SPI)
sx1302_radio_reset      # Reset SX1250 radios via SX1302 internal SPI
sx1302_set_gpio         # Configure SX1302 GPIO pins
```

Key finding: `mcu_gpio_write` controls **SX1302 MCU internal GPIOs** (PA1, PA8), not Raspberry Pi GPIOs. This is used for USB-to-SPI bridge mode. For SPI mode on Pi, GPIO control happens entirely in `reset_lgw.sh`.

The `fwd_sx1302` binary calls:
```
/usr/bin/reset_lgw.sh start   # Before HAL init
/usr/bin/reset_lgw.sh stop    # On shutdown
```

So all Pi GPIO control is in the shell script, and Dragino's script only controls GPIO 23.

## Tests Performed

### Test 1: Wrong Board Type (WM1302 pins)
- GPIOs 17/18/5 (WM1302 defaults)
- Result: chip version always 0x00
- **Fix**: Changed to PG1302 pins 23/27/22

### Test 2: Original sysfs Reset Script (`term; init; reset`)
- PG1302 pins with 512 base offset
- Result: chip version alternates 0x00/0x10; SX1250 always 0x00 or 0xFF
- The `term; init; reset` sequence creates a brief power glitch (microseconds) when GPIO27 (POWER_EN) defaults to LOW during export

### Test 3: Sysfs with Proper Power Cycle (3-10 seconds off)
- Explicit POWER_EN=0, sleep, POWER_EN=1, reset pulse
- Result: chip version always 0x00
- Hypothesis: after the long power-off, sysfs GPIO writes don't reliably drive the pins

### Test 4: Manual GPIO Power Cycle + No-Op Reset Script
- Manually toggled GPIOs via sysfs, then ran chip_id with no-op reset_lgw.sh
- Result: chip version always 0x00
- The no-op script means chip_id does no reset at all — relies on pre-set GPIO state

### Test 5: libgpiod (`gpioset`) Power Cycle
- Used `gpioset gpiochip0` with BCM pin numbers (no base offset needed)
- Verified with `gpioget` (reads correct values)
- Result: chip version 0x00
- **Problem**: `gpioget` temporarily sets pins to INPUT mode, potentially causing POWER_EN to drift LOW via pull-down

### Test 6: Dragino-Style Reset (Only GPIO 23, No POWER_EN)
- Only exported/drove BCM 23 via sysfs
- Left GPIO 27 (POWER_EN) floating (not exported)
- Result: chip version 0x00
- Confirms GPIO 27 has a pull-down on BCM2711 — without active drive, power is off

### Test 7: libgpiod Reset Script (gpioset with power cycle)
- Full `gpioset`-based script: power off 3s, power on, reset pulse
- Result: chip version 0x00 (4/5), **0x10 (1/5)**
- The 0x10 result (attempt 5) confirms libgpiod CAN drive the pins correctly
- Inconsistency likely due to `gpioset -m time -u 100000` releasing the line after 100ms hold

### Test 8: Original sysfs Reset Script (5 consecutive runs)
- Rapid sequential chip_id runs with `term; init; reset`
- Results: 0x10, 0x08, 0x00, 0x00, 0x00
- Chip version 0x10 on first run confirms the SX1302 hardware is functional
- SX1250 status: 0xFF (attempt 1), then 0x00 (rest)

---

## Diagnostic Session: 2026-01-31 (Pi 4 32-bit)

### System Under Test

- **Host**: Raspberry Pi 4 Model B Rev 1.4 (`lorapi4-32`, 192.168.10.119)
- **Kernel**: 6.12.47+rpt-rpi-v7l (armv7l)
- **Userspace**: **32-bit** (ELF 32-bit ARM, ld-linux-armhf.so.3)
- **Branch**: `fix/sx1250-init-failure`
- **SPI**: `/dev/spidev0.0`, `/dev/spidev0.1` available

### GPIO State Verification

```
GPIO 27 (POWER_EN):    level=1, func=INPUT, pull=DOWN  ← CONFIRMED pull-down!
GPIO 23 (RESET):       level=0, func=INPUT, pull=DOWN
GPIO 22 (SX1261_NRESET): level=1, func=INPUT, pull=DOWN
```

GPIO chip configuration:
- `gpiochip0`: GPIOs 512-569 (pinctrl-bcm2711)
- `gpiochip1`: GPIOs 570-577 (raspberrypi-exp-gpio)

For libgpiod (`gpioset gpiochip0`), line numbers map directly to BCM pins (no offset needed).
For sysfs, GPIO 23 = 535 (512 + 23), GPIO 27 = 539 (512 + 27).

### Test 9: chip_id with sysfs reset (5 consecutive runs)

```bash
cd /home/pi/basicstation-rpi64/build-corecell-std/bin
for i in 1 2 3 4 5; do sudo ./chip_id -d /dev/spidev0.0 2>&1 | grep "chip version"; done
```

**Results**: All 5 runs returned `chip version is 0x00 (v0.0)`

GPIO state after run: GPIO 27=1 (OUTPUT), GPIO 23=0 (OUTPUT), GPIO 22=1 (OUTPUT) — correct values, but chip still returns 0x00.

### Test 10: libgpiod manual reset with 1-second delays

```bash
# Unexport sysfs GPIOs
echo 534 > /sys/class/gpio/unexport
echo 535 > /sys/class/gpio/unexport
echo 539 > /sys/class/gpio/unexport

# Power OFF for 3 seconds
gpioset -m time -s 3 gpiochip0 27=0

# Power ON
gpioset gpiochip0 27=1
sleep 1

# Reset HIGH (1 sec) then LOW
gpioset -m time -s 1 gpiochip0 23=1
gpioset -m time -s 1 gpiochip0 23=0
sleep 1
```

GPIO state after: `GPIO 27: level=1 func=OUTPUT`, `GPIO 23: level=0 func=OUTPUT`
Lines remain as OUTPUT and retain values after gpioset exits.

**Result with no-op reset script**: `chip version is 0x00 (v0.0)`

### Test 11: gpioset -b (background mode) holding POWER_EN

```bash
gpioset -b gpiochip0 27=1  # Hold POWER_EN in background
gpioset -m time -s 1 gpiochip0 23=1
gpioset gpiochip0 23=0
./chip_id -d /dev/spidev0.0
```

**Result**: `chip version is 0x00 (v0.0)` — same failure even with POWER_EN explicitly held.

### Test 12: Dragino's own test tools

Extracted from `draginofwd-32bit.deb`:

1. **Dragino's reset_lgw.sh fails on Pi 4**:
   ```
   echo: write error: Invalid argument
   /sys/class/gpio/gpio23/direction: No such file or directory
   ```
   Uses raw GPIO 23 (no base offset) — incompatible with kernel 6.x where base=512.

2. **Dragino's sx1250_test with our reset script**:
   ```
   Note: chip version is 0x00 (v0.0)
   Radio0: get_status: 0x00
   Radio1: get_status: 0x00
   Cycle 0 > error during the buffer comparison
   Written value: 67C66973
   Read value:    00000000
   ```

3. **Dragino's com_test (SPI communication test)**:
   ```
   SX1302 version: 0x00
   Written values: 5D 7F 23 D3 C7 BD 78 81 ...
   Read values:    00 00 00 00 00 00 00 00 ...
   ```
   **Complete SPI failure** — all 275 bytes read as 0x00.

4. **Dragino's global_conf.json**: Uses `/dev/spidev0.0` (same as us).

### Conclusion: Hardware-Level SPI Failure

**The SPI bus is not communicating with the PG1302 module at all.**

---

## Final Diagnosis: 2026-01-31

### Test Systems

| Host | Model | Kernel | Arch | Userspace | IP |
|------|-------|--------|------|-----------|-----|
| lorapi4-32 | Pi 4 Model B | 6.12.47+rpt-rpi-v7l | armv7l | **32-bit** | 192.168.10.119 |
| raspberrypi | Pi 5 | 6.12.47+rpt-rpi-2712 | aarch64 | **64-bit** | 192.168.10.51 |

### Cross-Platform Test Results

| Test | Host | HAT | Result |
|------|------|-----|--------|
| Tests 9-12 | Pi 4 32-bit (lorapi4-32) | PG1302 (Dragino) | ❌ SPI failure, chip version 0x00 |
| Test B | Pi 5 64-bit (raspberrypi) | PG1302 (Dragino) | ❌ Same SPI failure |
| **Test A** | **Pi 4 32-bit (lorapi4-32)** | **WM1302 (Seeed)** | **✅ Working** |
| **Final** | **Pi 5 64-bit (raspberrypi)** | **WM1302 (Seeed)** | **✅ Working** |

### Root Cause: Defective PG1302 Module

**The Dragino PG1302 concentrator module is defective.**

Evidence:
- WM1302 works on Pi 4 → Pi 4 SPI/GPIO hardware is fine
- PG1302 fails on both Pi 4 and Pi 5 → module itself is faulty
- Complete SPI failure (all reads return 0x00) → likely dead SX1302 chip or broken PCB traces

### Resolution

- **Immediate**: Use WM1302 on Pi 4 (working)
- **Long-term**: Contact Dragino for RMA/replacement of PG1302

### Lessons Learned

1. **GPIO base offset is real** — kernel 6.x uses base 512 on Pi 4, 571 on Pi 5
2. **GPIO 27 has pull-down on BCM2711** — must actively drive POWER_EN HIGH
3. **Dragino's deb is incompatible with kernel 6.x** — uses raw GPIO numbers without offset
4. **Cross-platform testing isolates hardware faults** — essential diagnostic technique
5. **Our reset_lgw.sh with base offset detection works correctly** — verified on both Pi 4 and Pi 5
6. **Codebase works on both 32-bit and 64-bit** — tested on Pi 4 (armv7l/32-bit) and Pi 5 (aarch64/64-bit)

Evidence:
- Chip version always 0x00 (never 0x10)
- All SPI reads return zeros
- Both our code and Dragino's own test tools fail identically
- GPIO states are correct (verified with raspi-gpio)

Possible causes:
1. **Physical connection issue** — HAT not properly seated on GPIO header
2. **SPI wiring fault** — broken trace, cold solder joint
3. **Wrong SPI chip select** — module expects different CS pin
4. **Module damage** — SX1302 chip defective
5. **Power delivery** — 3.3V rail insufficient or noisy

### Next Steps: Hardware Isolation Testing

To isolate whether the problem is the Pi 4 or the PG1302 module:

1. **Test WM1302 (Seeed) on Pi 4** — known-working HAT from Pi 5
   - If WM1302 works on Pi 4: Pi 4 SPI is OK, PG1302 module is suspect
   - If WM1302 fails on Pi 4: Pi 4 SPI or GPIO has issues

2. **Test PG1302 (Dragino) on Pi 5** — known-working host
   - If PG1302 works on Pi 5: Pi 4 has GPIO/SPI issues
   - If PG1302 fails on Pi 5: PG1302 module is defective

3. **SPI loopback test** — connect MOSI to MISO on Pi 4
   - Verifies SPI hardware without concentrator

## Key Observations

1. ~~**The SX1302 hardware is functional** — chip version 0x10 has been read successfully multiple times~~ **OUTDATED** — on Pi 4 32-bit, chip version is consistently 0x00
2. **Complete SPI failure on Pi 4** — all reads return zeros, even with Dragino's own test tools
3. **BCM2711 GPIO 27 (POWER_EN) has a pull-down** — confirmed via `raspi-gpio get 27`
4. **GPIO state is correct** — GPIOs set to OUTPUT with proper values, but SPI still fails
5. **`gpioset` retains output state** — GPIO values persist after gpioset exits (contrary to earlier hypothesis)
6. **Dragino's reset_lgw.sh incompatible with kernel 6.x** — uses raw GPIO numbers without base offset
7. **Problem is hardware-level** — need cross-platform testing to isolate Pi 4 vs PG1302 module

## Remaining Hypotheses

### ~~H1: `gpioset` Line Release Causes Power Drop~~ DISPROVEN
Tested with `gpioset -b` (background mode) — same failure. GPIO values persist after gpioset exits.

### ~~H2/H3: SX1250 Timing Issues~~ NOT APPLICABLE
The SX1302 itself isn't responding (chip version 0x00). SX1250 timing is irrelevant until we can talk to SX1302.

### ~~H4: SPI Speed Too Fast~~ UNLIKELY
Complete read failure (all zeros) suggests no SPI communication at all, not signal integrity issues.

### H5: Physical Connection Issue (NEW - MOST LIKELY)
The PG1302 HAT may not be properly seated on the GPIO header, or there's a broken SPI trace.
**Test**: Try WM1302 (known-working) on same Pi 4.

### H6: PG1302 Module Defective (NEW)
The SX1302 chip on the PG1302 may be damaged.
**Test**: Try PG1302 on Pi 5 (known-working host).

### H7: Pi 4 SPI/GPIO Hardware Issue (NEW)
The Pi 4's SPI peripheral may have issues.
**Test**: SPI loopback test (connect MOSI to MISO).

## Recommended Next Steps

### Priority 1: Hardware Isolation Testing

The SPI failure is at the hardware level. Cross-platform testing will identify the faulty component.

| Test | Host | HAT | Expected Outcome |
|------|------|-----|------------------|
| A | Pi 4 (lorapi4-32) | WM1302 (Seeed) | If works: Pi 4 SPI OK, PG1302 suspect |
| B | Pi 5 (production) | PG1302 (Dragino) | If works: Pi 4 has issues |
| C | Pi 4 | Loopback (MOSI→MISO) | Verifies SPI hardware |

**Test A: WM1302 on Pi 4**
```bash
# Update board.conf for WM1302
cat > /home/pi/basicstation-rpi64/build-corecell-std/bin/board.conf << 'EOF'
BOARD_TYPE=WM1302
SX1302_RESET_BCM=17
SX1302_POWER_EN_BCM=18
SX1261_RESET_BCM=5
EOF

# Run chip_id
cd /home/pi/basicstation-rpi64/build-corecell-std/bin
sudo ./reset_lgw.sh start
sudo ./chip_id -d /dev/spidev0.0
```

**Test B: PG1302 on Pi 5**
```bash
# On Pi 5, update board.conf for PG1302
cat > board.conf << 'EOF'
BOARD_TYPE=PG1302
SX1302_RESET_BCM=23
SX1302_POWER_EN_BCM=27
SX1261_RESET_BCM=22
EOF

# Run chip_id
sudo ./reset_lgw.sh start
sudo ./chip_id -d /dev/spidev0.0
```

**Test C: SPI Loopback**
```bash
# Physically connect GPIO 10 (MOSI) to GPIO 9 (MISO) on Pi 4
python3 -c "
import spidev
spi = spidev.SpiDev()
spi.open(0, 0)
spi.max_speed_hz = 1000000
test = [0xAA, 0x55, 0xDE, 0xAD]
result = spi.xfer2(test[:])
print(f'Sent: {[hex(b) for b in test]}')
print(f'Recv: {[hex(b) for b in result]}')
print('PASS' if result == test else 'FAIL')
"
```

### Priority 2: Physical Inspection

1. **Reseat the HAT** — remove and reinsert PG1302 on GPIO header
2. **Check for bent pins** — inspect GPIO header for damage
3. **Verify SPI pins** — confirm physical pins 19 (MOSI), 21 (MISO), 23 (SCLK), 24 (CE0) are making contact
4. **Check power** — measure 3.3V on physical pin 1, 5V on pin 2

### Priority 3: Software Tests (after hardware verified)

1. **SPI speed reduction** — try 500kHz instead of 2MHz
2. **Alternative SPI device** — try `/dev/spidev0.1` (CE1 instead of CE0)
3. **Kernel SPI debug** — enable `spidev` debug in dmesg

## Code Changes in This Branch

### Tracked (git)
- `examples/corecell/cups-ttn/board.conf` — Changed to PG1302 config
- `examples/corecell/cups-ttn/reset_lgw.sh` — Added power cycle to reset sequence
- `lib/setup.sh` — Added `power_cycle_concentrator()` + retry logic in `step_detect_eui()`

### Untracked (deps/ is gitignored)
- `deps/lgw1302/platform-corecell/libloragw/src/loragw_sx1250.c` — Increased wait_ms delays (10→50ms), added debug printf for SX1250 status byte
- `deps/lgw1302/platform-corecell/libloragw/src/loragw_sx1302.c` — Increased post-reset delay (10→100ms)

### In build directory (not committed)
- `build-corecell-std/bin/reset_lgw.sh` — libgpiod-based reset script (latest test version)

## References

- [sx1302_hal#120](https://github.com/Lora-net/sx1302_hal/issues/120) — GPIO sysfs deprecation on kernel 6.6+
- [sx1302_hal#67](https://github.com/Lora-net/sx1302_hal/issues/67) — SX1250 STANDBY_RC failure, incomplete GPIO reset
- [xoseperez/basicstation-docker reset.sh.gpiod](https://github.com/xoseperez/basicstation-docker/blob/master/runner/reset.sh.gpiod) — libgpiod-based reset script reference
- [Dragino PG1302 Pin Mapping](https://wiki.dragino.com/xwiki/bin/view/Main/User%20Manual%20for%20All%20Gateway%20models/PG1302/) — Official GPIO pin diagram
- [GPIO sysfs deprecation blog post](https://waldorf.waveform.org.uk/2022/the-one-where-dave-breaks-stuff.html) — Raspberry Pi kernel team explanation
- [Dragino draginofwd-64bit.deb](https://www.dragino.com/downloads/downloads/LoRa_Gateway/PG1302/software/draginofwd-64bit.deb) — Official Dragino packet forwarder (64-bit)
- [Dragino draginofwd-32bit.deb](https://www.dragino.com/downloads/downloads/LoRa_Gateway/PG1302/software/draginofwd-32bit.deb) — Official Dragino packet forwarder (32-bit, works on Pi Zero)
- [Semtech sx1302_hal reset_lgw.sh](https://github.com/Lora-net/sx1302_hal/blob/master/tools/reset_lgw.sh) — Reference reset script with all 4 GPIOs
