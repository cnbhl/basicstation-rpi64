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
Automated setup wizard that:
1. Builds the station binary (`make platform=corecell variant=std`)
2. Builds `chip_id` tool from `tools/chip_id/` for EUI detection
3. Prompts for TTN region (eu1/nam1/au1)
4. Detects Gateway EUI from SX1302 chip via SPI
5. Collects CUPS API key securely
6. Downloads trust certificates
7. Creates credential files (`cups.uri`, `cups.key`, `cups.trust`)
8. Generates `station.conf` from template with variable substitution
9. Optionally configures systemd service

Security patterns used:
- `set -euo pipefail` for strict error handling
- Atomic file writes via temp file + `mv`
- Here-strings (`<<<`) for secrets to avoid process listing exposure
- Pre-set restrictive permissions (600) before writing secrets
- Input sanitization for sed replacement (`sanitize_for_sed()`)

### `examples/corecell/cups-ttn/`
TTN CUPS configuration directory:
- `station.conf.template` - Template with `{{GATEWAY_EUI}}`, `{{INSTALL_DIR}}`, `{{LOG_FILE}}` placeholders
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
