# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Repository**: [cnbhl/basicstation-rpi64](https://github.com/cnbhl/basicstation-rpi64)

This is a fork of [lorabasics/basicstation](https://github.com/lorabasics/basicstation) (Release 2.0.6) that adds:
- Raspberry Pi 5 GPIO compatibility
- Automated TTN CUPS setup via `setup-gateway.sh`
- Automatic Gateway EUI detection from SX1302/SX1303 chips
- Systemd service configuration
- Fine timestamp support for SX1302/SX1303 with GPS PPS
- Docker support for containerized deployment

For upstream Basic Station documentation: https://doc.sm.tc/station

## Build Commands

Build for Raspberry Pi with SX1302/SX1303:
```bash
make platform=corecell variant=std
```

Build debug variant:
```bash
make platform=corecell variant=debug
```

Output: `build-corecell-{variant}/bin/station`

## Running Tests

```bash
cd regr-tests
./run-regression-tests        # All tests
./run-regression-tests -v     # Verbose
./run-regression-tests -n     # Exclude hardware tests
./run-tests-dc                # Duty cycle tests only (test9a/9b/9c)
```

## Fork-Specific Development

The main development work in this fork is in:

### `setup-gateway.sh`
Main entry point that sources modular libraries from `lib/`. Supports both interactive and non-interactive modes.

**General Options:**
- `--help` - Show usage
- `--uninstall` - Remove installation
- `-v, --verbose` - Enable debug logging
- `--skip-deps` - Skip dependency checks
- `--skip-gps` - Skip GPS auto-detection

**Non-Interactive Mode Options** (for CI/CD and scripted deployments):
- `-y, --non-interactive` - Enable non-interactive mode (required for automation)
- `--force` - Overwrite existing credentials without prompting
- `--board <type>` - Board type: WM1302, PG1302, LR1302, SX1302_WS, SEMTECH
- `--region <code>` - TTN region: eu1, nam1, au1
- `--eui <hex|auto>` - Gateway EUI (16 hex chars) or 'auto' for hardware detection
- `--cups-key <key>` - CUPS API key
- `--cups-key-file <path>` - Read CUPS key from file (alternative to --cups-key)
- `--log-file <path>` - Station log file path
- `--gps <device|none>` - GPS device path or 'none' to disable
- `--antenna-gain <dBi>` - Antenna gain in dBi (0-15, default: 0)
- `--service` / `--no-service` - Enable/disable systemd service setup
- `--skip-build` - Skip build if binary exists

**Non-Interactive Mode Example:**
```bash
./setup-gateway.sh -y --board WM1302 --region eu1 --eui auto --cups-key "NNSXS.xxx..." --service
```

### Board Configuration System
The setup wizard supports multiple SX1302 concentrator boards with different GPIO pinouts:

**Supported boards** (defined in `examples/corecell/cups-ttn/board.conf.template`):
- **WM1302** (Seeed Studio) - Reset=17, PowerEN=18, SX1261=5
- **PG1302** (Dragino) - Reset=23, PowerEN=27, SX1261=22
- **LR1302** (Elecrow) - Reset=17, PowerEN=18, SX1261=5
- **SX1302_WS** (Waveshare) - Reset=23, PowerEN=18, SX1261=22
- **SEMTECH** (Reference Design) - Reset=23, PowerEN=18, SX1261=22

**Configuration flow**:
1. `step_select_board()` in `lib/setup.sh` presents board menu
2. User selects board or enters custom GPIO pins
3. Configuration saved to `examples/corecell/cups-ttn/board.conf`
4. `reset_lgw.sh` reads `board.conf` at runtime for GPIO control

**Adding new boards**: Edit `board.conf.template` with format:
```
BOARD_ID:Description:SX1302_RESET_BCM:POWER_EN_BCM:SX1261_RESET_BCM
```

See [docs/SUPPORTED_BOARDS.md](docs/SUPPORTED_BOARDS.md) for detailed GPIO reference.

### `lib/` - Modular Library Structure

#### `lib/common.sh`
Core utilities including:
- **Output functions**: `print_header()`, `print_success()`, `print_warning()`, `print_error()`, `print_banner()`
- **Input functions**: `confirm()`, `read_secret()`, `read_validated()`
- **System checks**: `command_exists()`, `file_exists()`, `file_executable()`, `dir_exists()`, `check_spi_available()`, `check_i2c_available()`
- **Privilege detection**:
  - `is_root()` - Check if running as root (EUID=0)
  - `check_sudo_available()` - Check sudo availability, sets `HAVE_SUDO` and `IS_ROOT` flags
  - `run_privileged(cmd...)` - Run command with sudo if not root
  - `require_privilege(purpose)` - Check privileges with helpful error message
- **Logging system**:
  - `init_logging(path)` - Initialize log file with timestamp header
  - `log_debug(msg)`, `log_info(msg)`, `log_warning(msg)`, `log_error(msg)`
  - `get_log_file()` - Returns current log path
  - Log levels: `LOG_LEVEL_DEBUG`, `LOG_LEVEL_INFO`, `LOG_LEVEL_WARNING`, `LOG_LEVEL_ERROR`
- **Dependency validation**:
  - `check_dependency(cmd, package, purpose)` - Check single dependency
  - `check_required_dependencies()` - Check all required deps (gcc, make, curl, sed, grep, tr, cat, cp, mv, chmod, mktemp, tee, stty, timeout, sudo, systemctl)
  - `check_optional_dependencies()` - Check optional deps
  - `check_all_dependencies(mode)` - Run all checks ("strict" or "warn")

#### `lib/validation.sh`
Input validation:
- `validate_eui(eui)` - Validate 16-char hex Gateway EUI
- `validate_not_empty(value)` - Check non-empty string
- `validate_gpio(pin)` - Validate BCM GPIO pin number (0-27)
- `validate_region(region)` - Validate TTN region code (eu1, nam1, au1)
- `validate_board_type(board)` - Validate board type against template
- `get_board_config(board)` - Get GPIO config for board, sets `SX1302_RESET_BCM`, `SX1302_POWER_EN_BCM`, `SX1261_RESET_BCM`
- `sanitize_for_sed(input)` - Escape special chars for sed

#### `lib/file_ops.sh`
Secure file operations:
- `write_file_secure(path, content, perms)` - Atomic write with permissions
- `write_secret_file(path, content)` - Write secrets (600 perms, here-string)
- `copy_file(src, dst, perms)` - Copy with optional permission setting
- `process_template(template, output, KEY=VALUE...)` - Template variable substitution

#### `lib/service.sh`
Systemd service management:
- `service_is_active(name)` - Check if service running
- `service_is_enabled(name)` - Check if service enabled
- `service_start(name)` - Start with status check
- `service_restart(name)` - Restart with status check

#### `lib/gps.sh`
GPS serial port detection:
- `GPS_PORTS` - Array of ports to scan (`/dev/ttyAMA0`, `/dev/ttyS0`, `/dev/serial0`, `/dev/ttyAMA10`)
- `GPS_BAUD_RATES` - Baud rates to try (9600, 4800, 19200, 38400, 57600, 115200)
- `contains_nmea(data)` - Check for NMEA sentence patterns ($GP, $GN, $GL, $GA, $GB)
- `try_gps_port(port, baud)` - Test port at specific baud rate
- `detect_gps_port()` - Scan all ports, sets `GPS_DEVICE` global

#### `lib/setup.sh`
Setup wizard steps (in order):
1. `step_check_existing_credentials()` - Warn if overwriting
2. `step_select_board()` - Select concentrator board (GPIO config)
3. `step_build_station()` - Build station binary and chip_id
4. `step_select_region()` - TTN region selection (eu1/nam1/au1)
5. `step_detect_eui()` - Auto-detect or manual EUI entry
6. `step_show_registration_instructions()` - TTN Console guidance
7. `step_get_cups_key()` - Collect CUPS API key
8. `step_setup_trust_cert()` - Download/copy trust certificate
9. `step_select_log_location()` - Choose log file path
10. `step_detect_gps()` - GPS port detection
11. `step_create_credentials()` - Write credential files and station.conf
12. `step_setup_service()` - Optional systemd setup (includes startup verification)

Additional functions:
- `verify_gateway_started()` - Waits up to 30s for "Concentrator started" in logs

Main function: `run_setup()` - Orchestrates all steps with logging

#### `lib/uninstall.sh`
Uninstall functions:
- `uninstall_service()` - Remove systemd service
- `uninstall_credentials()` - Remove credential files
- `uninstall_logs()` - Remove log files
- `uninstall_build()` - Remove build artifacts
- `run_uninstall()` - Interactive uninstall wizard

### Global Variables
Set in `setup-gateway.sh`, used across libs:
- `SCRIPT_DIR`, `LIB_DIR`, `CUPS_DIR`, `BUILD_DIR`
- `STATION_BINARY`, `CHIP_ID_TOOL`, `RESET_LGW_SCRIPT`
- `BOARD_CONF`, `BOARD_CONF_TEMPLATE` - Board configuration files
- `BOARD_TYPE`, `SX1302_RESET_BCM`, `SX1302_POWER_EN_BCM` - Board GPIO settings
- `TTN_REGION`, `CUPS_URI`, `GATEWAY_EUI`, `CUPS_KEY`
- `LOG_FILE`, `GPS_DEVICE`, `MODE`, `SKIP_DEPS`

**Non-Interactive Mode Variables:**
- `NON_INTERACTIVE` - Boolean, true when -y/--non-interactive is set
- `FORCE_OVERWRITE` - Boolean, true when --force is set
- `CLI_BOARD`, `CLI_REGION`, `CLI_EUI` - CLI-provided configuration values
- `CLI_CUPS_KEY`, `CLI_CUPS_KEY_FILE` - CUPS key from CLI or file
- `CLI_LOG_FILE`, `CLI_GPS` - Log and GPS settings from CLI
- `CLI_SERVICE` - "yes", "no", or "" for service setup preference
- `CLI_SKIP_BUILD` - Boolean, skip build if binary exists

### Security Patterns
- `set -euo pipefail` for strict error handling
- Atomic file writes via temp file + `mv`
- Here-strings (`<<<`) for secrets to avoid process listing exposure
- Pre-set restrictive permissions (600) before writing secrets
- Input sanitization for sed replacement (`sanitize_for_sed()`)

### `examples/corecell/cups-ttn/`
TTN CUPS configuration directory:
- `station.conf.template` - Template with placeholders:
  - `{{GATEWAY_EUI}}` - 16-char hex Gateway EUI
  - `{{INSTALL_DIR}}` - Script directory path
  - `{{LOG_FILE}}` - Station log file path
  - `{{GPS_DEVICE}}` - GPS device path (quoted string) or empty string `""`
  - `{{PPS_SOURCE}}` - PPS timing mode: `"gps"` (with GPS) or `"fuzzy"` (network time sync)
- `reset_lgw.sh` - GPIO reset script with Pi 5 support (single source of truth)
- `start-station.sh` - Launch script (`-d` flag for debug variant)
- `rinit.sh` - Radio initialization called by station (invokes `reset_lgw.sh`)

**GPS/PPS Configuration Logic** (in `lib/setup.sh` `step_create_credentials()`):
| GPS Status | `gps` value | `pps` value | Description |
|------------|-------------|-------------|-------------|
| Enabled | `"/dev/ttyXXX"` | `"gps"` | Uses GPS for location and PPS timing |
| Disabled | `""` | `"fuzzy"` | No GPS, uses network time synchronization |

### `examples/corecell/cups-ttn/reset_lgw.sh`
Single location for the GPIO reset script. Used by:
- `rinit.sh` at runtime (station calls it via `radio_init`)
- `setup-gateway.sh` copies it to build directory for `chip_id` EUI detection

Handles Raspberry Pi GPIO offset differences:
- Pi 5: GPIO base 571
- Pi 4/3: GPIO base 512
- Older: GPIO base 0

Auto-detection via `/sys/kernel/debug/gpio`, `/sys/class/gpio/gpiochip*/base`, or `/proc/device-tree/model` fallback.

### Duty Cycle Enforcement (cherry-picked from MultiTech)

Sliding window duty cycle tracking for ETSI EN 300 220 compliance. Cherry-picked from
[MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) `feature/duty-cycle` branch.

**Source files:**
- `src/s2e.c` - Core duty cycle implementation:
  - `dc_tx_record_t`, `dc_history_t` - Circular buffer for TX records per band/channel
  - `DC_MODE_*` enums: `LEGACY`, `BAND`, `CHANNEL`, `POWER`
  - `s2e_canTx_sliding()` - Sliding window TX check
  - `dc_record_tx()`, `dc_expire_old()`, `dc_cumulative()` - History management
  - EU868 independent band tracking (K/L/M/N/P/Q bands with per-band limits)
- `src/s2e.h` - Duty cycle data structures and mode definitions
- `src/kwcrc.h` / `src/kwlist.txt` - JSON keywords: `duty_cycle_enabled`, `duty_cycle_mode`, `duty_cycle_window`, `duty_cycle_limits`
- `src-linux/sys_linux.c` - `dutyconf` feature flag advertisement

**router_config options:**
- `duty_cycle_enabled` (Boolean) - When false, disables station-side DC enforcement (LNS controls scheduling)
- `duty_cycle_mode` (String) - `"legacy"`, `"band"`, `"channel"`, or `"power"`
- `duty_cycle_window` (Integer) - Sliding window duration in seconds (60-86400)
- `duty_cycle_limits` (Object/Integer) - Per-band limits object or per-channel permille value

**EU868 band limits (ETSI EN 300 220):**
- Band K (863-865 MHz): 0.1%
- Band L (865-868 MHz): 1%
- Band M (868.0-868.6 MHz): 1%
- Band N (868.7-869.2 MHz): 0.1%
- Band P (869.4-869.65 MHz): 10%
- Band Q (869.7-870.0 MHz): 1%

**ETSI-compliant `freq2band()` implementation:**
Our implementation in `src/s2e.c` correctly maps all 6 EU868 bands per ETSI EN 300 220. The original upstream Semtech code had a simplified 3-band mapping that defaulted most frequencies to 0.1%:
```c
// Original Semtech (incorrect):
// - 869.4-869.65 MHz → 10%
// - 868.0-868.6 MHz or 869.7-870.0 MHz → 1%
// - Everything else → 0.1% (default)

// Our ETSI-compliant implementation:
// - 863-865 MHz (Band K) → 0.1%
// - 865-868 MHz (Band L) → 1%
// - 868.0-868.6 MHz (Band M) → 1%
// - 868.7-869.2 MHz (Band N) → 0.1%
// - 869.4-869.65 MHz (Band P) → 10%
// - 869.7-870.0 MHz (Band Q) → 1%
```

**Regression tests:**
- `regr-tests/test9a-dc-eu868/` - EU868 band-based DC tests (DISABLED, BAND_10PCT/1PCT/01PCT, MULTIBAND, WINDOW)
- `regr-tests/test9b-dc-as923/` - AS923 per-channel DC tests (DISABLED, SINGLE_CH, MULTI_CH, WINDOW)
- `regr-tests/test9c-dc-kr920/` - KR920 per-channel DC tests (DISABLED, SINGLE_CH, MULTI_CH)
- `regr-tests/run-tests-dc` - CI runner script for duty cycle test category

**TLS/CUPS test frequency fix:**
The tls-cups tests (`test3-updn-tls`, `test3a-updn-tls`, `test4-cups`, `test5-runcmd`) were updated to use 864.1 MHz (Band K, 0.1%) instead of 867.1 MHz (Band L, 1%) for duty cycle blocking tests. The original tests assumed 867.1 MHz had 0.1% duty cycle (per the simplified upstream `freq2band`), but our ETSI-compliant implementation correctly maps it to 1%.

**Design doc:** `docs/Duty-Cycle-Sliding-Window-Plan.md`

### GPS/PPS Improvements (cherry-picked from MultiTech)

Enhanced GPS and PPS handling for SX1302/SX1303 concentrators. Cherry-picked from
[MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) `feature/gps-recovery` and `feature/gpsd-support` branches.

**Features:**
- **GPS/PPS Recovery**: Auto-reset GPS/PPS if PPS signal lost for >90 seconds, restart station after 6 consecutive failures
- **GPSD Support**: Use gpsd daemon instead of direct serial port access (compile with `CFG_usegpsd`)
- **GPS Control**: LNS can enable/disable GPS via `router_config` with `gps_enable` field

**Source files:**
- `src/timesync.c` - PPS reset tracking and recovery logic
- `src-linux/gps.c` - GPSD daemon integration
- `src-linux/sys_linux.c` - GPS control feature, `gps-ctrl` capability flag
- `src/s2e.c` - `gps_enable` router_config option parsing

**Environment variables:**
- `NO_PPS_RESET_THRES` - Seconds without PPS before reset (default: 90)
- `NO_PPS_RESET_FAIL_THRES` - Max resets before station restart (default: 6)

**Build with GPSD support:**
```bash
make platform=corecell variant=std CFG_usegpsd=1
```

**Design doc:** `docs/GPS-PPS-Recovery.md`

### GPS Diagnostics Helper (planned)

**Location:** `tools/check-gps.sh`

Standalone diagnostic script for troubleshooting GPS issues. Separate from setup-gateway.sh
because GPS diagnostics are operational tasks that may be run repeatedly.

**Planned features:**
```bash
./tools/check-gps.sh [OPTIONS]
  --device <path>    GPS device (default: auto-detect from station.conf or /dev/ttyAMA0)
  --duration <sec>   Monitoring duration (default: 30)
  --reset            Send cold start command before monitoring
  --json             Output in JSON format for scripting
```

**Diagnostic output:**
- Satellite count (GPS, GLONASS, Galileo, BeiDou)
- Signal strength per satellite (dB)
- Fix status (none/2D/3D)
- Position if available
- DOP (dilution of precision)
- Antenna status
- Comparison with expected values

**GPS troubleshooting reference:**

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| 0 satellites | Antenna disconnected or no power | Check SMA connectors, antenna power |
| 1-3 satellites, no fix | Severe sky obstruction | Move antenna to clear sky view |
| 4+ satellites, no fix, no elev/azimuth | Weak signals, marginal tracking | Improve antenna position, check cable |
| 4+ satellites, no fix, has elev/azimuth | Waiting for ephemeris | Wait 2-5 minutes for cold start |
| Fix but high DOP (>5) | Poor satellite geometry | Wait for better satellite positions |
| Intermittent fix | Partial sky obstruction | Improve antenna sky view |

**Signal strength reference:**
- < 20 dB: Very weak, unlikely to track
- 20-30 dB: Weak, marginal tracking
- 30-40 dB: Good signal
- 40-50 dB: Excellent signal

**NMEA sentence reference:**
- `$GxGGA` - Position fix, quality, satellites used, DOP
- `$GxGSV` - Satellites in view with elevation, azimuth, signal strength
- `$GxRMC` - Position, velocity, date/time, fix status (A=valid, V=void)
- `$GPTXT` - Antenna status messages

### `tools/chip_id/`
Standalone EUI detection tool derived from Semtech sx1302_hal:
- `chip_id.c` - Reads EUI from SX1302 via SPI
- `log_stub.c` - Logging stub for standalone build
- Built against `build-corecell-std/lib/liblgw1302.a`

### Fine Timestamp Support (SX1302/SX1303)
Adds nanosecond-precision fine timestamps to uplink frames when GPS PPS is available. This is a core station C code modification (not shell/setup tooling).

**Hardware requirement:** Fine timestamps require **SX1303** or newer SX1302 revisions. Older SX1302 chips (Model ID 0x00) do not support fine timestamps.

**How to enable:**
Add `"ftime": true` to the `SX1302_conf` section of `station.conf`:
```json
{
    "SX1302_conf": {
        "pps": true,
        "ftime": true,
        ...
    }
}
```

**How it works:**
- Fine timestamping requires explicit opt-in via `"ftime": true` in `station.conf`
- Also requires `"pps": true` for GPS time synchronization
- The SX1302/SX1303 HAL provides fine timestamps for all spreading factors (SF5-SF12)
- Fine timestamps are in nanoseconds; the `fts` field is `-1` when unavailable
- The `fts` field is sent as a separate JSON field; the LNS combines it with GPS-synchronized time server-side for geolocation
- When duplicate/mirror frames are detected from multiple modems, the fine timestamp is preserved from whichever copy has it

**Why `fts` is separate from `rxtime`:** Per [lorabasics/basicstation#177](https://github.com/lorabasics/basicstation/issues/177), `rt_getUTC()` cannot be reliably synchronized to GPS time, and may advance by a full second between packet reception and JSON encoding. Embedding `fts` into `rxtime` would cause misalignment. The LNS has proper GPS-synced time and can combine them correctly.

**Files modified:**
- `src/kwlist.txt` - Added `ftime` keyword for config parsing
- `src/sx130xconf.h` - Added `struct lgw_conf_ftime_s ftime` to `sx130xconf` (SX1302 builds)
- `src/sx130xconf.c` - Parses `"ftime"` config option, enables fine timestamping via `lgw_ftime_setconf()`
- `src-linux/ralsub.h` - Added `s4_t fts` field to `ral_rx_resp` struct
- `src-linux/ral_slave.c` - Populates `fts` from HAL `ftime_received`/`ftime`; zero-initializes `sx130xconf` with `memset`
- `src-linux/ral_master.c` - Propagates `fts` from slave response to `rxjob`
- `src/ral_lgw.c` - Populates `fts` from HAL in single-process mode
- `src/s2e.c` - Copies fine timestamp between mirror frames during dedup, includes `fts` as separate field in uplink JSON

**Uplink JSON output:**
The `fts` field (nanoseconds, `-1` if unavailable) is included as a separate field:
```json
{"fts": 123456789, "rxtime": 1706000000.123456, ...}
```

### Timesync: Exit on Stuck Concentrator
Cherry-picked from MultiTech fork (`eee8f10`). If the SX130x trigger counter stops ticking (concentrator locked up), the station now exits after `5 * QUICK_RETRIES` consecutive excessive clock drift cycles, allowing systemd to restart the service and re-initialize the hardware. Without this, a stuck concentrator causes the station to run indefinitely doing nothing.

**File modified:** `src/timesync.c` - Added `exit(EXIT_FAILURE)` with `CRITICAL` log after excessive drift threshold.

### ifconf Zero-Initialization
Cherry-picked from MultiTech fork (`64f634f`, partial). Adds `memset(ifconf, 0, sizeof(struct lgw_conf_rxif_s))` at the start of `parse_ifconf()` in `src/sx130xconf.c`. Prevents stale or uninitialized values in channel configuration fields not explicitly set by JSON from the LNS.

### SF5/SF6 Spreading Factor Support
Cherry-picked from MultiTech fork (`799ac21`, partial). Adds SF5 and SF6 cases to `parse_spread_factor()` in `src/sx130xconf.c` inside `#if defined(CFG_sx1302)`. The SX1303 (and some SX1302 revisions) support SF5/SF6, defined in LoRaWAN RP2 1.0.5. Without this, an LNS sending SF5/SF6 channel config crashes the station with "Illegal spread factor."

### SX1302 LBT Error Handling Fix
Cherry-picked from MultiTech fork (`20c64c9`, partial). Separates SX1302 and SX1301 `lgw_send()` error paths in `src/ral_lgw.c` and `src-linux/ral_slave.c`. SX1302 HAL returns `LGW_LBT_NOT_ALLOWED` while SX1301 returns `LGW_LBT_ISSUE`. Upstream shared a single error check which used the wrong constant for SX1302 builds (worked by accident since both are `1` via our HAL patch alias).

### `tests/` - Test Scripts
Test scripts for validating setup functionality:
- `test-setup.sh` - Unit tests for validation and utility functions (no hardware required)
- `test-non-interactive.sh` - Integration tests for non-interactive mode argument parsing
- `mock-environment.sh` - Mock environment for testing without hardware (creates fake chip_id, sudo, systemctl)

**Running tests:**
```bash
./tests/test-setup.sh           # Unit tests (15 tests)
./tests/test-non-interactive.sh # Integration tests (14 tests)
```

**Unit tests (`test-setup.sh`)** cover:
- EUI validation (valid/invalid 16-char hex)
- Region validation (eu1, nam1, au1)
- Board type validation (WM1302, PG1302, etc.)
- GPIO pin validation (BCM 0-27)
- Board config lookup (GPIO pins for each board)
- Sed sanitization (escaping `/` and `&`)
- Non-interactive confirm behavior
- File/directory/command existence checks

**Integration tests (`test-non-interactive.sh`)** cover:
- Help flag displays all non-interactive options
- Missing required args error handling
- Invalid board/region/EUI rejection
- CUPS key and key-file validation
- Service flag requirement
- GPS option documentation
- Force and skip-build flags

**Test helpers (in mock-environment.sh):**
- `setup_mock_environment()` / `cleanup_mock_environment()` - Setup/teardown mocks
- `assert_true()`, `assert_equals()`, `assert_file_exists()`, `assert_file_contains()` - Test assertions

**Note on bash arithmetic:** Tests use pre-increment `(( ++VAR ))` instead of post-increment `(( VAR++ ))` to avoid exit code 1 with `set -e` when counters start at 0.

## Running the Station

After setup:
```bash
cd examples/corecell/cups-ttn
./start-station.sh           # std variant
./start-station.sh -d        # debug variant
```

Or via systemd:
```bash
sudo systemctl start basicstation.service
sudo journalctl -u basicstation.service -f
```

## Docker Support

Build and run the station as a Docker container on Raspberry Pi.

### Build

```bash
docker build -t basicstation .
# Debug variant:
docker build -t basicstation --build-arg VARIANT=debug .
```

### Run

```bash
# Using docker-compose (recommended)
CUPS_KEY="NNSXS.xxx..." docker compose up -d
docker logs -f basicstation

# Using docker run
docker run -d --privileged --network host \
  -e BOARD=PG1302 -e REGION=eu1 \
  -e GATEWAY_EUI=auto \
  -e CUPS_KEY="NNSXS.xxx..." \
  basicstation
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BOARD` | Yes | -- | WM1302, PG1302, LR1302, SX1302_WS, SEMTECH, or `custom` |
| `REGION` | Yes | -- | TTN region: eu1, nam1, au1 |
| `GATEWAY_EUI` | Yes | -- | 16 hex chars or `auto` (chip detection) |
| `CUPS_KEY` | Yes | -- | TTN CUPS API key (NNSXS.xxx...) |
| `EUI_ONLY` | No | -- | Set to `1` to detect Gateway EUI and exit (only `BOARD` required) |
| `GPS_DEV` | No | _(disabled)_ | GPS device path (e.g. `/dev/ttyS0`) or `none` |
| `ANTENNA_GAIN` | No | `0` | Antenna gain in dBi (0-15) |
| `SPI_DEV` | No | `/dev/spidev0.0` | SPI device path |
| `LOG_LEVEL` | No | `DEBUG` | Station log level |
| `SX1302_RESET_GPIO` | If custom | -- | BCM pin for SX1302 reset |
| `POWER_EN_GPIO` | If custom | -- | BCM pin for power enable |
| `SX1261_RESET_GPIO` | If custom | -- | BCM pin for SX1261 reset |

### Docker Files

- `Dockerfile` - Multi-stage build (builder compiles station + chip_id, runner is minimal)
- `docker/entrypoint.sh` - Validates env vars, generates config, starts station
- `docker-compose.yml` - Example compose file with all env vars documented
- `.dockerignore` - Excludes build artifacts, credentials, tests from context

### Container Layout

```
/app/
├── bin/station              # Station binary
├── bin/chip_id              # EUI detection tool
├── scripts/
│   ├── reset_lgw.sh         # GPIO reset (SX1302 + SX1261 + Power EN)
│   ├── rinit.sh             # Radio init wrapper
│   └── board.conf           # Generated at runtime by entrypoint
├── templates/
│   ├── station.conf.template
│   └── board.conf.template
├── config/                  # Station home dir (generated at runtime)
│   ├── station.conf
│   ├── cups.uri
│   ├── cups.key
│   └── cups.trust
└── entrypoint.sh
```

### Notes

- Requires `privileged: true` or sysfs GPIO access for concentrator reset
- Requires `network_mode: host` for LoRaWAN packet reception
- Logs go to stderr via station's built-in stderr mode (`log_file: "stderr"`) — visible via `docker logs`
- Uses the same `station.conf.template` and `board.conf.template` as `setup-gateway.sh`
- Builder stage requires `python3`, `python3-jsonschema`, `python3-jinja2` for mbedtls 3.6.0 PSA crypto wrapper generation
- Stale PID files (`/var/tmp/station.pid`, `/tmp/station.pid`) are cleaned up before station start to prevent restart failures

## Build System Notes

Platform/variant configuration in `setup.gmk`:
- `platform=corecell` selects SX1302 HAL (`deps/lgw1302`)
- Auto-detects ARM32/ARM64 for native builds
- Cross-compilation via `$HOME/toolchain-corecell/` if available

**Future: Multi-arch Docker builds**
The [xoseperez/basicstation](https://github.com/xoseperez/basicstation) fork has a multi-arch build system
(commit `e8d893a`) that adds an `arch` parameter for explicit target selection:
```bash
make platform=corecell arch=aarch64  # 64-bit ARM
make platform=corecell arch=armv7hf  # 32-bit ARM (Pi 2/3/4)
make platform=corecell arch=armv6l   # Pi Zero/1
make platform=corecell arch=amd64    # x86_64
```
This conflicts with our auto-detection but may be useful for Docker multi-arch builds.

**Future: NetID/OUI Whitelist**
The [xoseperez/basicstation](https://github.com/xoseperez/basicstation) fork has local packet filtering
(commit `4aabf75`) that allows filtering packets at the gateway before forwarding to the LNS:
```json
{
    "whitelist_netids": ["0x000013"],
    "whitelist_ouis": ["0xA81758", "0x70B3D5"]
}
```
- **OUI filter**: Filters join requests by DevEUI manufacturer prefix (e.g., `0xA81758` = RAK)
- **NetID filter**: Filters data frames by network ID extracted from DevAddr (e.g., `0x000013` = TTN)
Useful for multi-tenant gateways or shared infrastructure. Not needed for single-network setups.

## mbedtls Version

The codebase uses **mbedtls 3.6.0** (default) with TLS 1.3 support.

### mbedtls 3.x Features

| File | Changes |
|------|---------|
| `deps/mbedtls/makefile` | Copy PSA headers (`include/psa/*.h`) for mbedtls 3.x crypto API |
| `src/tls.c` | PSA crypto initialization, version-conditional includes, TLS 1.3 NewSessionTicket handling |
| `src/tls.h` | Add `tls_ensurePsaInit()` function, version-conditional net includes |
| `src/cups.c` | ECDSA signature verification updated for mbedtls 3.x private struct members |

### Key mbedtls 3.x API Notes

- `mbedtls/net.h` → `mbedtls/net_sockets.h`
- `mbedtls/certs.h` removed
- `ecp_keypair` struct members are now private (use accessor functions)
- `mbedtls_pk_parse_key()` requires RNG function parameter
- PSA crypto must be initialized with `psa_crypto_init()` before use
- TLS 1.3 sends `NewSessionTicket` after handshake (not an error, retry read)

### Legacy mbedtls 2.x Support

The source code retains backward compatibility with mbedtls 2.x via `#if MBEDTLS_VERSION_NUMBER` conditionals, but this is no longer tested in CI. To use mbedtls 2.x:
```bash
rm -rf deps/mbedtls/git-repo deps/mbedtls/platform-*
MBEDTLS_VERSION=2.28.8 make platform=corecell variant=std
```

## Cherry-Picked Fixes from MultiTech Fork

Some fixes have been cherry-picked from [MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) (BSD-3-Clause license, same as upstream Semtech).

### Applied Cherry-Picks

| Fix | MultiTech Commit | File | Description |
|-----|------------------|------|-------------|
| ifconf memset | `64f634f` (partial) | `src/sx130xconf.c` | Zero-initialize `ifconf` struct before JSON parsing to prevent stale/garbage values in channel config fields not explicitly set by LNS |
| mbedtls 3.x | `cb9d67b`, `e75b882`, `7a344b8`, `6944075` | `src/tls.c`, `src/cups.c` | Compatibility with mbedtls 3.x including PSA crypto and ECDSA API changes |
| Duty cycle sliding window | `2e15d53`, `fa0d896`, `27c337e`, `a8bf871`, `ad6d5fb` | `src/s2e.c`, `src/s2e.h`, `src/kwcrc.h` | ETSI-compliant sliding window duty cycle tracking with per-band limits for EU868 |
| IN865 region | N/A (custom) | `src/s2e.c` | Add IN865 (India 865 MHz) region support with 30 dBm max EIRP |
| GPS/PPS recovery | `9438ff9` | `src/timesync.c` | Auto-reset GPS/PPS for SX1302/SX1303 if PPS lost >90s, restart after 6 failures |
| GPSD support | `57b2503`, `d429908` | `src-linux/gps.c`, `src-linux/sys_linux.c` | Use gpsd daemon instead of direct serial, compile with `CFG_usegpsd` |
| GPS control | `dd1035f`, `f5a5f8d` | `src/s2e.c`, `src-linux/sys_linux.c` | LNS can enable/disable GPS via `router_config` with `gps_enable` field |
| nocca TX fix | `5c54f11` (partial) | `src-linux/ral_master.c` | Use correct command when checking TX response with LBT disabled |

### Potential Future Cherry-Picks

See [docs/MULTITECH_CHERRY_PICKS.md](docs/MULTITECH_CHERRY_PICKS.md) for detailed analysis of additional MultiTech commits:
- SF5/SF6 spreading factor support
- SX1302 LBT error handling
- Fine timestamp support
- Timesync exit on stuck concentrator
- AS923-2/3/4 region support

## Versioning Convention

Format: `2.0.6-cnbhl.X.Y` or `2.0.6-cnbhl.X.Ya`

- **Major release**: `2.0.6-cnbhl.X.0` where X increments for major feature additions
- **Minor release**: `2.0.6-cnbhl.X.Y` where Y increments for smaller changes within a major release
- **Hotfix**: `2.0.6-cnbhl.X.Ya` where a is an incrementing letter (a, b, c...)
- **Tag**: No "v" prefix (e.g., `2.0.6-cnbhl.1.0`)
- **Release title**: `Release 2.0.6-cnbhl.X.Y` (prefix with "Release ")

**Current version**: `2.0.6-cnbhl.1.6`

**History**: Versions `2.0.6-cnbhl.1` through `2.0.6-cnbhl.5` used the old single-number scheme.
Starting with `2.0.6-cnbhl.1.0`, we use the new X.Y format.

Examples: Tag `2.0.6-cnbhl.1.3` → Title "Release 2.0.6-cnbhl.1.3"

## Git Workflow

- **Master branch is protected**: Cannot push directly to master
- **All changes require a PR**: Create a feature/fix branch, then open a pull request
- **Branch naming**: Use prefixes like `fix/`, `feature/`, `docs/` (e.g., `fix/skip-gps-option`)
- **Before every commit**: Review CLAUDE.md and update it if the commit introduces new features, changes conventions, modifies the project structure, or adds/removes files that are documented here. Keep CLAUDE.md as the single source of truth for project context.

## MultiTech Cherry-Pick Tracker

Cherry-picks from [MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation).
Remote: `multitech` pointing to `https://github.com/MultiTechSystems/basicstation.git`.

### Completed

**`feature/duty-cycle` → `feature/duty-cycle-sliding-window`** (all 5 feature commits):
- `2e15d53` - Add `duty_cycle_enabled` router_config option
- `fa0d896` - Add region-specific duty cycle tests
- `27c337e` - Implement sliding window duty cycle tracking
- `a8bf871` - Add duty cycle tests to CI workflow
- `ad6d5fb` - Fix EU868 independent band tracking per ETSI EN 300 220

**`feature/in865-region`** (1 commit, custom — not from multitech):
- `02c88ea` - Add IN865 region support

**`feature/mbedtls-3x`** (4 commits, custom — not from multitech):
- `67edf21` - Copy PSA headers for mbedtls 3.x compatibility
- `5dfb7ae` - Add mbedtls 3.x compatibility with backward compatibility for 2.x
- `a7df227` - Initialize PSA crypto for mbedtls 3.x TLS 1.3 support
- `4cae440` - Fix mbedtls 3.x key parsing for DER format credentials

**`feature/gps-improvements`** (GPS/PPS recovery + GPSD support + GPS control):
- `9438ff9` - Add GPS/PPS recovery for SX1302/SX1303
- `57b2503` - Updated GPS handler to use gpsd instead of file stream
- `d429908` - Add gpsd support with `CFG_usegpsd` compiler flag
- `dd1035f` - Add GPS control feature for LNS to disable/enable GPS
- `f5a5f8d` - Improve GPS control and timesync recovery
- `5c54f11` (partial) - Fix nocca TX command in ral_master.c

### Candidates (not yet cherry-picked)

**`multitech/feature/fine-timestamp`** — Fine timestamp for SX1302/SX1303:
- `505bb59` - Add fine timestamp support for SX1302/SX1303 with GPS
- `229abc5` - Add memset initialization for sx130xconf struct

**`multitech/feature/channel-plans`** — Additional region support:
- `926ff01` - Add channel plan support for additional regions
- `1c60f53` - Add IL915 region support and CCA/LBT for SX1302/SX1303

**`multitech/feature/updn-dr`** — SF5/SF6 asymmetric datarate (RP002-1.0.5):
- `871d558` - Add SF5/SF6 and asymmetric datarate support for RP002-1.0.5

**`multitech/feature/rejoin`** — Rejoin request handling:
- `cf6eaf1` - Implement rejoin request handling with raw PDU format

**`multitech/feature/lbtconf`** — LBT channel configuration:
- `571f830` - Implement LBT channel configuration via router_config

**`multitech/feature/pdu-only`** — Raw frame forwarding:
- `93340bb` - Add pdu-only mode for raw frame forwarding

**`multitech/feature/remove-v2-code`** — Cleanup:
- `36debf0` - Remove SX1301AR (v2 gateway) code
