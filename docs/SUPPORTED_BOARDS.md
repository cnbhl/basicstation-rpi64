# Supported Concentrator Boards

This document lists the SX1302/SX1303 LoRaWAN concentrator HATs supported by this fork.

## Quick Reference

| Board | Manufacturer | SX1302 Reset | Power EN | SX1261 Reset |
|-------|--------------|--------------|----------|--------------|
| WM1302 | Seeed Studio | BCM 17 | BCM 18 | BCM 5 |
| PG1302 | Dragino | BCM 23 | BCM 27 | BCM 22 |
| LR1302 | Elecrow | BCM 17 | BCM 18 | BCM 5 |
| SX1302_WS | Waveshare | BCM 23 | BCM 18 | BCM 22 |
| SEMTECH | Semtech Reference | BCM 23 | BCM 18 | BCM 22 |

## Board Selection

During `./setup-gateway.sh`, you'll be prompted to select your board:

```
Step 1: Select your concentrator board

  1) WM1302     - Seeed Studio WM1302 (SPI version)
  2) PG1302     - Dragino PG1302
  3) LR1302     - Elecrow LR1302
  4) SX1302_WS  - Waveshare SX1302 LoRaWAN Gateway HAT
  5) SEMTECH    - Semtech CoreCell Reference Design
  6) CUSTOM     - Enter custom GPIO pins

Enter board number [1-6]:
```

The selected configuration is saved to `examples/corecell/cups-ttn/board.conf`.

## Detailed Board Information

### Seeed Studio WM1302 (SPI)

- **Product page**: [WM1302 Wiki](https://wiki.seeedstudio.com/WM1302_module/)
- **GPIO Configuration**:
  - SX1302 Reset: BCM 17 (physical pin 11)
  - Power Enable: BCM 18 (physical pin 12)
  - SX1261 Reset: BCM 5 (physical pin 29)
- **Notes**: Also available in USB version (not supported by this setup)

### Dragino PG1302

- **Product page**: [Dragino PG1302 Wiki](https://wiki.dragino.com/xwiki/bin/view/Main/User%20Manual%20for%20All%20Gateway%20models/PG1302/)
- **GPIO Configuration**:
  - SX1302 Reset: BCM 23 (physical pin 16)
  - Power Enable: BCM 27 (physical pin 13)
  - SX1261 Reset: BCM 22 (physical pin 15)
- **Notes**: Does NOT have a temperature sensor - this fork includes patches to handle this gracefully

### Elecrow LR1302

- **Product page**: [Elecrow LR1302 Datasheet](https://www.elecrow.com/download/product/CRT01265M/LR1302_LoRaWAN_Hat_for_RPI_DataSheet.pdf)
- **GPIO Configuration**:
  - SX1302 Reset: BCM 17 (physical pin 11)
  - Power Enable: BCM 18 (physical pin 12)
  - SX1261 Reset: BCM 5 (physical pin 29)
- **Notes**: Same pinout as WM1302

### Waveshare SX1302

- **Product page**: [Waveshare SX1302 Wiki](https://www.waveshare.com/wiki/SX1302_LoRaWAN_Gateway_HAT)
- **GPIO Configuration**:
  - SX1302 Reset: BCM 23 (physical pin 16)
  - Power Enable: BCM 18 (physical pin 12)
  - SX1261 Reset: BCM 22 (physical pin 15)
- **Notes**: Follows Semtech reference design pinout

### Semtech CoreCell Reference Design

- **Reference**: [Semtech sx1302_hal](https://github.com/Lora-net/sx1302_hal)
- **GPIO Configuration**:
  - SX1302 Reset: BCM 23 (physical pin 16)
  - Power Enable: BCM 18 (physical pin 12)
  - SX1261 Reset: BCM 22 (physical pin 15)
  - AD5338R Reset: BCM 13 (optional, for full-duplex)

## GPIO Pin Reference

### BCM to Physical Pin Mapping

| BCM | Physical | Common Use |
|-----|----------|------------|
| 5 | 29 | SX1261 Reset (WM1302, LR1302) |
| 13 | 33 | AD5338R Reset (optional) |
| 17 | 11 | SX1302 Reset (WM1302, LR1302) |
| 18 | 12 | Power Enable (most boards) |
| 22 | 15 | SX1261 Reset (PG1302, Waveshare, Semtech) |
| 23 | 16 | SX1302 Reset (PG1302, Waveshare, Semtech) |
| 27 | 13 | Power Enable (PG1302) |

### Raspberry Pi GPIO Base Offsets

The `reset_lgw.sh` script auto-detects the GPIO base offset:

| Raspberry Pi Model | GPIO Base | Example: BCM 23 → sysfs |
|--------------------|-----------|-------------------------|
| Pi 5 | 571 | 594 |
| Pi 4, Pi 3, CM4 | 512 | 535 |
| Pi 2, Pi 1, Zero | 0 | 23 |

## Custom Board Configuration

If your board isn't listed, select "CUSTOM" during setup and enter:

1. **SX1302 Reset BCM pin** - GPIO connected to SX1302 reset
2. **Power Enable BCM pin** - GPIO for power control (or same as reset if not separate)
3. **SX1261 Reset BCM pin** - GPIO for SX1261 fine timestamp chip (if present)

The configuration is saved to `board.conf`:

```bash
# Example custom configuration
SX1302_RESET_BCM=23
SX1302_POWER_EN_BCM=18
SX1261_RESET_BCM=22
BOARD_TYPE=CUSTOM
```

## Adding a New Board

### For Your Local Setup

To add a new board to your local supported list, edit `examples/corecell/cups-ttn/board.conf.template`:

```
BOARD_ID:Description:SX1302_RESET:POWER_EN:SX1261_RESET
```

Example:
```
MYBOARD:My Custom Board:17:18:5
```

### Contributing to This Project

If you have a working configuration for a board not in the list, please contribute it so others can benefit:

1. Fork this repository on GitHub
2. Add your board to `examples/corecell/cups-ttn/board.conf.template`
3. Test that `./setup-gateway.sh` works with your board
4. Submit a Pull Request to [github.com/cnbhl/basicstation-rpi64](https://github.com/cnbhl/basicstation-rpi64)

Include in your PR:
- Board manufacturer and model name
- Link to product page or datasheet
- Verified GPIO pinout (BCM numbers)
- Any special notes (e.g., missing temperature sensor)

## Troubleshooting

### GPIO Permission Errors

If you see "cannot export GPIO" errors:
```bash
# Check if GPIO is already exported
ls /sys/class/gpio/

# Run with sudo
sudo ./reset_lgw.sh start
```

### Wrong GPIO Base Detected

Override auto-detection by setting `GPIO_BASE` before running:
```bash
export GPIO_BASE=512
./reset_lgw.sh start
```

### Board Not Responding

1. Check SPI is enabled: `ls /dev/spidev*`
2. Verify wiring matches your board's pinout
3. Check dmesg for errors: `dmesg | grep -i spi`
