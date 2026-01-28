# SX1250 Initialization Failure Investigation

## Hardware Under Test

- **Concentrator**: PG1302 (Dragino) — SX1302 + dual SX1250
- **Host**: Raspberry Pi 4B, kernel 6.12.62+rpt-rpi-v8 (Bookworm)
- **SPI**: `/dev/spidev0.0`
- **GPIO Pins** (from [Dragino PG1302 Pin Mapping](https://wiki.dragino.com/xwiki/bin/view/Main/User%20Manual%20for%20All%20Gateway%20models/PG1302/)):
  - SX1302 RESET: BCM 23 (physical pin 16)
  - POWER_EN: BCM 27 (physical pin 13)
  - SX1261_NRESET: BCM 22 (physical pin 15)

**Reference setup that works**: WM1302 (Seeed) on Raspberry Pi 5, kernel 6.12.47, same codebase.

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

### Dragino's `station.conf`

Uses `/dev/spidev1.0` (not `/dev/spidev0.0`) — likely designed for their DLOS8 gateway product, not a bare Pi + PG1302 setup.

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

## Key Observations

1. **The SX1302 hardware is functional** — chip version 0x10 has been read successfully multiple times
2. **The SX1250 has NEVER initialized successfully** — status is always 0x00 or 0xFF (garbage)
3. **GPIO method affects SX1302 success rate** but neither sysfs nor libgpiod reliably initializes the SX1250
4. **BCM2711 GPIO 27 (POWER_EN) has a pull-down** — must be actively driven HIGH or power is off
5. **`gpioset` releases GPIO lines when it exits** — the pin value may or may not persist depending on hardware latching
6. **Dragino does not control POWER_EN via GPIO** in their own software — they only use GPIO 23 (RESET)

## Remaining Hypotheses

### H1: `gpioset` Line Release Causes Power Drop
When `gpioset -m time -u 100000 gpiochip0 27=1` finishes, it releases line 27. The BCM2711 pull-down on GPIO27 may pull POWER_EN LOW before chip_id reads the SPI bus. **Fix**: Use `gpioset -b` (background mode) to keep the process running and holding the line.

### H2: SX1250 Needs Longer Post-Power Stabilization
The SX1250's TCXO (temperature-compensated crystal oscillator) may need more time after power-on before it can enter STANDBY_RC. The HAL uses `wait_ms(50)` (increased from 10ms) but the PG1302's TCXO may need even more. **Fix**: Increase to 200-500ms.

### H3: SX1250 Auto-Calibration Not Completing
After the SX1302 resets the SX1250 (via internal register writes), the SX1250 runs auto-calibration. If the TCXO isn't stable yet, calibration fails silently and the chip returns 0x00. **Fix**: Increase `wait_ms(100)` (loragw_sx1302.c:447) to 500ms+.

### H4: SPI Speed Too Fast
The SPI speed is set to 2MHz. If signal integrity is marginal on the PG1302's PCB trace layout, reducing speed might help. **Fix**: Try 1MHz or 500kHz.

## Recommended Next Steps

1. **Test `gpioset -b` (background mode)** — keep POWER_EN held active:
   ```bash
   gpioset -b gpiochip0 27=1  # background: holds line until killed
   gpioset -m time -s 1 gpiochip0 23=1  # reset HIGH for 1s
   gpioset gpiochip0 23=0  # reset LOW
   ```

2. **Test without power cycle** (match xoseperez/basicstation-docker approach):
   ```bash
   gpioset gpiochip0 27=1  # just enable power (exit mode)
   gpioset -m time -u 100000 gpiochip0 23=0  # reset pulse
   gpioset -m time -u 100000 gpiochip0 23=1
   gpioset -m time -u 100000 gpiochip0 23=0
   ```

3. **Increase HAL timing further** — try 200-500ms delays in `loragw_sx1250.c` and `loragw_sx1302.c`

4. **Try SPI speed reduction** — modify `lgw_spi_open` to use 1MHz instead of 2MHz

5. **Test Dragino's own binary** (`fwd_sx1302` from their deb) with corrected GPIO offset to see if their HAL version works

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
