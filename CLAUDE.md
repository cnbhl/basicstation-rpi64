# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Repository**: [cnbhl/basicstation-rpi64](https://github.com/cnbhl/basicstation-rpi64)

This is a fork of [lorabasics/basicstation](https://github.com/lorabasics/basicstation) (Release 2.0.6) that adds:
- Raspberry Pi 5 GPIO compatibility
- Automated TTN CUPS setup via `setup-gateway.sh`
- Automatic Gateway EUI detection from SX1302/SX1303 chips
- Systemd service configuration

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

### `tools/chip_id/`
Standalone EUI detection tool derived from Semtech sx1302_hal:
- `chip_id.c` - Reads EUI from SX1302 via SPI
- `log_stub.c` - Logging stub for standalone build
- Built against `build-corecell-std/lib/liblgw1302.a`

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

## Versioning Convention

Format: `2.0.6-cnbhl.X.Y` or `2.0.6-cnbhl.X.Ya`

- **Major release**: `2.0.6-cnbhl.X.0` where X increments for major feature additions
- **Minor release**: `2.0.6-cnbhl.X.Y` where Y increments for smaller changes within a major release
- **Hotfix**: `2.0.6-cnbhl.X.Ya` where a is an incrementing letter (a, b, c...)
- **Tag**: No "v" prefix (e.g., `2.0.6-cnbhl.1.0`)
- **Release title**: `Release 2.0.6-cnbhl.X.Y` (prefix with "Release ")

**History**: Versions `2.0.6-cnbhl.1` through `2.0.6-cnbhl.5` used the old single-number scheme.
Starting with `2.0.6-cnbhl.1.0`, we use the new X.Y format.

Examples: Tag `2.0.6-cnbhl.1.0` → Title "Release 2.0.6-cnbhl.1.0"

## Git Workflow

- **Master branch is protected**: Cannot push directly to master
- **All changes require a PR**: Create a feature/fix branch, then open a pull request
- **Branch naming**: Use prefixes like `fix/`, `feature/`, `docs/` (e.g., `fix/skip-gps-option`)
- **Before every commit**: Review CLAUDE.md and update it if the commit introduces new features, changes conventions, modifies the project structure, or adds/removes files that are documented here. Keep CLAUDE.md as the single source of truth for project context.
