# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

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
Main entry point that sources modular libraries from `lib/`. Supports:
- `--help` - Show usage
- `--uninstall` - Remove installation
- `-v, --verbose` - Enable debug logging
- `--skip-deps` - Skip dependency checks
- `--skip-gps` - Skip GPS auto-detection

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
2. `step_build_station()` - Build station binary and chip_id
3. `step_select_region()` - TTN region selection (eu1/nam1/au1)
4. `step_detect_eui()` - Auto-detect or manual EUI entry
5. `step_show_registration_instructions()` - TTN Console guidance
6. `step_get_cups_key()` - Collect CUPS API key
7. `step_setup_trust_cert()` - Download/copy trust certificate
8. `step_select_log_location()` - Choose log file path
9. `step_detect_gps()` - GPS port detection
10. `step_create_credentials()` - Write credential files and station.conf
11. `step_setup_service()` - Optional systemd setup

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
- `TTN_REGION`, `CUPS_URI`, `GATEWAY_EUI`, `CUPS_KEY`
- `LOG_FILE`, `GPS_DEVICE`, `MODE`, `SKIP_DEPS`

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
  - `{{GPS_DEVICE}}` - GPS device path or `false`
- `reset_lgw.sh` - GPIO reset script with Pi 5 support (single source of truth)
- `start-station.sh` - Launch script (`-d` flag for debug variant)
- `rinit.sh` - Radio initialization called by station (invokes `reset_lgw.sh`)

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
