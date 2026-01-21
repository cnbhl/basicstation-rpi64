# LoRa Basic Station - Raspberry Pi 5 + TTN CUPS Fork

This is a fork of [lorabasics/basicstation](https://github.com/lorabasics/basicstation) with added support for:

- **Raspberry Pi 5** GPIO compatibility
- **Automated setup** for The Things Network (TTN) using CUPS protocol
- **Automatic Gateway EUI detection** from SX1302/SX1303 chip
- **Systemd service** configuration

For general Basic Station documentation, building instructions, and protocol details, please refer to the [original repository](https://github.com/lorabasics/basicstation) and [official documentation](https://doc.sm.tc/station).

---

## Quick Start

```bash
git clone https://github.com/cnbhl/basicstation.git
cd basicstation
./setup-gateway.sh
```

The setup script guides you through a complete gateway configuration:

| Step | Description |
|------|-------------|
| - | Check system dependencies |
| 1 | Build the station binary |
| 2 | Select TTN region (EU1, NAM1, AU1) |
| 3 | Auto-detect Gateway EUI from SX1302 chip |
| 4 | Enter CUPS API Key from TTN Console |
| 5 | Download TTN trust certificate |
| 6 | Select log file location |
| 7 | Auto-detect GPS serial port |
| 8 | Create credential files |
| 9 | Generate station.conf |
| 10 | Set file permissions |
| 11 | Configure systemd service (optional) |

### Command Line Options

```bash
./setup-gateway.sh              # Run setup wizard
./setup-gateway.sh --uninstall  # Remove installation
./setup-gateway.sh -v           # Verbose/debug logging
./setup-gateway.sh --skip-deps  # Skip dependency checks
```

---

## Features Added in This Fork

### Automated Setup Script

`setup-gateway.sh` provides a guided setup process for configuring Basic Station with TTN CUPS. It handles:

- Dependency validation at startup
- Building the station binary
- Gateway EUI detection
- GPS serial port auto-detection
- Credential file generation
- Certificate downloads
- Systemd service installation

The script uses a modular architecture with reusable library functions in `lib/`.

### Dependency Validation

The setup script checks for required dependencies before proceeding:

| Dependency | Purpose |
|------------|---------|
| `curl` | Downloading certificates |
| `gcc` | Compiling station and chip_id |
| `make` | Building station |
| `sed` | Template processing |
| `stty` | GPS serial port configuration |
| `grep` | Text processing |
| `timeout` | GPS detection timeouts |

Optional: `systemctl` for service management.

If dependencies are missing, install them with:
```bash
sudo apt-get update
sudo apt-get install curl gcc make sed coreutils grep
```

### Setup Logging

All setup operations are logged to `setup.log` in the script directory:

```bash
# View setup log
cat setup.log

# Run with verbose/debug logging
./setup-gateway.sh -v
```

Log format:
```
[2026-01-22 10:30:45] [INFO] Starting setup-gateway.sh in setup mode
[2026-01-22 10:30:46] [DEBUG] Using chip_id tool at ...
[2026-01-22 10:30:47] [WARNING] Could not auto-detect EUI
```

### Gateway EUI Auto-Detection

The `chip_id` tool reads the unique EUI directly from the SX1302/SX1303 concentrator chip, eliminating manual entry:

```
Step 3: Detecting Gateway EUI from SX1302 chip...

Detected EUI from SX1302 chip: AABBCCDDEEFF0011

Use this EUI? (Y/n):
```

### Raspberry Pi 5 GPIO Support

The included reset scripts automatically detect the GPIO base offset for different Raspberry Pi models:

| Model | GPIO Base |
|-------|-----------|
| Raspberry Pi 5 | 571 |
| Raspberry Pi 4/3 | 512 |
| Older models | 0 |

### GPS Serial Port Auto-Detection

The setup script automatically detects GPS modules by scanning serial ports for NMEA data:

| Port | Description |
|------|-------------|
| `/dev/ttyAMA0` | Pi 5 primary UART |
| `/dev/ttyS0` | Pi 4/3 mini UART |
| `/dev/serial0` | Symlink (varies by model) |
| `/dev/ttyAMA10` | Pi 5 secondary UART |

Baud rates tested: 9600, 4800, 19200, 38400, 57600, 115200

If no GPS is detected, you can enter the device path manually or disable GPS (the gateway will use network time synchronization instead).

### Systemd Service

Optional automatic service setup for running the gateway at boot:

```bash
sudo systemctl status basicstation.service   # Check status
sudo systemctl stop basicstation.service     # Stop service
sudo systemctl restart basicstation.service  # Restart service
sudo journalctl -u basicstation.service -f   # View live logs
```

### Manual Start

If you chose not to set up a service:

```bash
cd examples/corecell
./start-station.sh -l ./cups-ttn
```

---

## Repository Structure (Added Files)

```
basicstation/
├── setup-gateway.sh                      # Main entry point
├── setup.log                             # Setup log file (created on run)
├── lib/                                  # Modular library functions
│   ├── common.sh                         # Output, input, logging, dependency checks
│   ├── validation.sh                     # Input validation functions
│   ├── file_ops.sh                       # File operations (secure writes, templates)
│   ├── service.sh                        # Systemd service management
│   ├── gps.sh                            # GPS serial port detection
│   ├── setup.sh                          # Setup wizard steps
│   └── uninstall.sh                      # Uninstall functions
├── tools/
│   ├── README.md
│   └── chip_id/                          # EUI detection tool
│       ├── chip_id.c                     # Source code (from sx1302_hal)
│       ├── log_stub.c                    # Logging stub for standalone build
│       ├── LICENSE                       # Semtech BSD 3-Clause
│       └── README.md
└── examples/
    └── corecell/
        └── cups-ttn/                     # TTN CUPS configuration
            ├── station.conf.template     # Template with {{GATEWAY_EUI}}, {{GPS_DEVICE}}, etc.
            ├── cups.uri.example
            ├── reset_lgw.sh              # Pi 5 compatible reset (single source)
            ├── start-station.sh
            ├── rinit.sh
            └── README.md
```

> **Note:** The `chip_id` binary is built automatically from source during the setup process, ensuring compatibility with both 32-bit and 64-bit ARM systems.

---

## Raspberry Pi Configuration

Before running the setup script, you must configure your Raspberry Pi interfaces. The SX1302/SX1303 concentrator requires SPI, I2C, and proper serial port settings.

### Using raspi-config

```bash
sudo raspi-config
```

Navigate to **Interface Options** and configure:

| Interface | Setting | Reason |
|-----------|---------|--------|
| **SPI** | Enable | Primary communication with SX1302 chip |
| **I2C** | Enable | Required for temperature sensor and EEPROM |
| **Serial Port** | Disable shell, Enable hardware | GPS module uses UART (if equipped) |

For the serial port, select:
- "Would you like a login shell over serial?" → **No**
- "Would you like the serial port hardware enabled?" → **Yes**

### Reboot Required

After changing interface settings, reboot your Pi:

```bash
sudo reboot
```

### Verify SPI is Enabled

```bash
ls -la /dev/spidev*
```

You should see `/dev/spidev0.0` and `/dev/spidev0.1`.

For more details, see the [Seeed WM1302 documentation](https://wiki.seeedstudio.com/WM1302_module/) and [Waveshare SX1302 wiki](https://www.waveshare.com/wiki/SX1302_LoRaWAN_Gateway_HAT).

---

## Prerequisites

- Raspberry Pi 3/4/5 (32-bit or 64-bit OS)
- SPI, I2C enabled (see configuration above)
- SX1302 or SX1303 LoRa concentrator (e.g., WM1302, RAK2287)
- Gateway registered on [The Things Network](https://console.cloud.thethings.network/)
- CUPS API Key from TTN Console

---

## Third-Party Components

| Component | Source | License |
|-----------|--------|---------|
| chip_id | [Semtech sx1302_hal](https://github.com/Lora-net/sx1302_hal) | BSD 3-Clause |

---

## Upstream

This fork is based on [lorabasics/basicstation](https://github.com/lorabasics/basicstation) Release 2.0.6.

For complete documentation on Basic Station features, protocols (LNS, CUPS), configuration options, and supported platforms, see:

- **Repository:** https://github.com/lorabasics/basicstation
- **Documentation:** https://doc.sm.tc/station

---

## License

Basic Station is licensed under the BSD 3-Clause License. See [LICENSE](LICENSE) for details.

The `chip_id` tool is derived from Semtech sx1302_hal and is licensed under the Semtech BSD 3-Clause License. See [tools/chip_id/LICENSE](tools/chip_id/LICENSE).
