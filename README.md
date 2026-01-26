# LoRa Basic Station - Raspberry Pi 5 + TTN CUPS Fork

Fork of [lorabasics/basicstation](https://github.com/lorabasics/basicstation) (v2.0.6) adding:
- Raspberry Pi 5 GPIO compatibility
- **Multi-board support** (Seeed WM1302, Dragino PG1302, Elecrow LR1302, Waveshare SX1302)
- Automated TTN CUPS setup with `setup-gateway.sh`
- Automatic Gateway EUI detection from SX1302/SX1303
- Systemd service configuration

For upstream documentation: [doc.sm.tc/station](https://doc.sm.tc/station)

## Quick Start

```bash
git clone https://github.com/cnbhl/basicstation-rpi64.git
cd basicstation-rpi64
./setup-gateway.sh
```

The setup wizard builds the station, detects your Gateway EUI, configures TTN CUPS credentials, and optionally sets up a systemd service.

### Options

```bash
./setup-gateway.sh              # Run setup wizard
./setup-gateway.sh --uninstall  # Remove installation
./setup-gateway.sh -v           # Verbose logging
./setup-gateway.sh --skip-deps  # Skip dependency checks
./setup-gateway.sh --skip-gps   # Skip GPS auto-detection
```

### Non-Interactive Mode

For CI/CD pipelines and scripted deployments:

```bash
./setup-gateway.sh -y \
    --board WM1302 \
    --region eu1 \
    --eui auto \
    --cups-key "NNSXS.xxx..." \
    --service
```

**Non-interactive options:**
| Option | Description |
|--------|-------------|
| `-y, --non-interactive` | Enable non-interactive mode |
| `--force` | Overwrite existing credentials |
| `--board <type>` | Board type: WM1302, PG1302, LR1302, SX1302_WS, SEMTECH |
| `--region <code>` | TTN region: eu1, nam1, au1 |
| `--eui <hex\|auto>` | Gateway EUI (16 hex chars) or 'auto' |
| `--cups-key <key>` | CUPS API key |
| `--cups-key-file <path>` | Read CUPS key from file |
| `--log-file <path>` | Station log file path |
| `--gps <device\|none>` | GPS device path or 'none' |
| `--service / --no-service` | Enable/disable systemd service |
| `--skip-build` | Skip build if binary exists |

## Supported Boards

| Board | Manufacturer | Status |
|-------|--------------|--------|
| WM1302 | Seeed Studio | Tested |
| PG1302 | Dragino | Tested |
| LR1302 | Elecrow | Supported |
| SX1302 HAT | Waveshare | Supported |
| CoreCell | Semtech Reference | Supported |

The setup wizard auto-configures GPIO pins for your board. Custom boards can specify pins manually.

See [docs/SUPPORTED_BOARDS.md](docs/SUPPORTED_BOARDS.md) for detailed GPIO pinouts and adding new boards.

## Tested Platforms

| Device | Model | OS | Userspace | Kernel |
|--------|-------|-----|-----------|--------|
| Pi Zero W | Rev 1.1 | Raspbian 13 (trixie) | armv6l | armv6l |
| Pi 4 (32-bit) | Model B Rev 1.4 | Raspbian 13 (trixie) | armhf | aarch64 |
| Pi 4 (64-bit) | Model B Rev 1.4 | Raspbian 12 (bookworm) | aarch64 | aarch64 |
| Pi 5 | Model B Rev 1.0 | Debian 12 (bookworm) | aarch64 | aarch64 |

All three ARM userspace architectures are supported: **armv6l** (Pi Zero/1), **armhf** (32-bit Pi 2/3/4), **aarch64** (64-bit Pi 3/4/5).

## Prerequisites

- Raspberry Pi Zero W/3/4/5 with SPI and I2C enabled
- SX1302/SX1303 concentrator HAT (see supported boards above)
- Gateway registered on [TTN Console](https://console.cloud.thethings.network/)
- CUPS API Key from TTN

### Enable Interfaces

Run `sudo raspi-config` → Interface Options:
- **SPI**: Enable (concentrator communication)
- **I2C**: Enable (temperature sensor)
- **Serial Port**: Disable shell, enable hardware (for GPS)

Reboot after changes.

## Running

**Via systemd** (if configured during setup):
```bash
sudo systemctl start basicstation.service
sudo journalctl -u basicstation.service -f
```

**Manual start**:
```bash
cd examples/corecell/cups-ttn
./start-station.sh        # std variant
./start-station.sh -d     # debug variant
```

## Repository Structure

```
basicstation/
├── setup-gateway.sh              # Main setup script
├── lib/                          # Modular shell libraries
│   ├── common.sh                 # Output, logging, dependency checks
│   ├── validation.sh             # Input validation
│   ├── file_ops.sh               # Secure file operations
│   ├── service.sh                # Systemd management
│   ├── gps.sh                    # GPS port detection
│   ├── setup.sh                  # Setup wizard steps
│   └── uninstall.sh              # Uninstall functions
├── tests/                        # Test suite
│   ├── test-setup.sh             # Unit tests (15 tests)
│   ├── test-non-interactive.sh   # Integration tests (14 tests)
│   └── mock-environment.sh       # Mock hardware environment
├── tools/chip_id/                # EUI detection (from sx1302_hal)
└── examples/corecell/cups-ttn/   # TTN CUPS configuration
```

## Testing

Run the test suite (no hardware required):

```bash
./tests/test-setup.sh           # Unit tests for validation functions
./tests/test-non-interactive.sh # Integration tests for CLI argument parsing
```

Tests use a mock environment that simulates `chip_id`, `sudo`, and `systemctl` for CI/CD compatibility.

## Raspberry Pi GPIO Support

The `reset_lgw.sh` script auto-detects GPIO base offsets:
- Pi 5: 571
- Pi 4/3: 512
- Older: 0

## Dependencies

Required: `gcc`, `make`, `curl`, `sed`, `grep`, `stty`, `timeout`, `sudo`, `systemctl`

Install missing deps:
```bash
sudo apt-get install build-essential curl coreutils
```

## Third-Party Components

| Component | Source | License |
|-----------|--------|---------|
| chip_id | [Semtech sx1302_hal](https://github.com/Lora-net/sx1302_hal) | BSD 3-Clause |

## License

BSD 3-Clause. See [LICENSE](LICENSE).
