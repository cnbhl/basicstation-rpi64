# LoRa Basic Station - Raspberry Pi 5 + TTN CUPS Fork

Fork of [lorabasics/basicstation](https://github.com/lorabasics/basicstation) (v2.0.6) adding:
- Raspberry Pi 5 GPIO compatibility
- Automated TTN CUPS setup with `setup-gateway.sh`
- Automatic Gateway EUI detection from SX1302/SX1303
- Systemd service configuration

For upstream documentation: [doc.sm.tc/station](https://doc.sm.tc/station)

## Quick Start

```bash
git clone https://github.com/cnbhl/basicstation.git
cd basicstation
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

## Prerequisites

- Raspberry Pi 3/4/5 with SPI and I2C enabled
- SX1302/SX1303 concentrator (WM1302, RAK2287, etc.)
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
├── tools/chip_id/                # EUI detection (from sx1302_hal)
└── examples/corecell/cups-ttn/   # TTN CUPS configuration
```

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
