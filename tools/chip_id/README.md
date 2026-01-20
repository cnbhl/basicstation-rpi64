# chip_id - SX1302 Gateway EUI Detection Tool

This utility reads the unique Gateway EUI directly from the SX1302/SX1303 LoRa concentrator chip.

## Source

This tool is derived from the **Semtech SX1302/SX1303 HAL** (Hardware Abstraction Layer):

- **Repository:** https://github.com/Lora-net/sx1302_hal
- **Location:** `util_chip_id/` directory
- **License:** BSD 3-Clause License (see [LICENSE](LICENSE))

## Files

| File | Description |
|------|-------------|
| `chip_id.c` | Source code from sx1302_hal |
| `reset_lgw.sh` | GPIO reset script with Raspberry Pi 5 support |
| `LICENSE` | Semtech BSD 3-Clause License |

## Building

The `chip_id` tool is automatically built by `setup-gateway.sh` after the station build completes. It uses the same libloragw library and is placed in `build-corecell-std/bin/`.

To build manually after the station is built:

```bash
gcc -std=gnu11 -O2 \
    -I build-corecell-std/include/lgw \
    tools/chip_id/chip_id.c \
    -L build-corecell-std/lib -llgw1302 -lm -lpthread -lrt \
    -o build-corecell-std/bin/chip_id
```

## Usage

```bash
cd build-corecell-std/bin
sudo ./chip_id -d /dev/spidev0.0
```

### Output Example

```
Opening SPI communication interface
Note: chip version is 0x10 (v1.0)
INFO: concentrator EUI: 0xAABBCCDDEEFF0011
Closing SPI communication interface
```

## Requirements

- SX1302 or SX1303 concentrator connected via SPI
- `reset_lgw.sh` script in the same directory (copied automatically by setup script)
- Root privileges (sudo) for SPI and GPIO access

## Raspberry Pi 5 Compatibility

The included `reset_lgw.sh` script automatically detects the GPIO base offset for different Raspberry Pi models:

- Raspberry Pi 5: GPIO base 571
- Raspberry Pi 4/3: GPIO base 512
- Older models: GPIO base 0

## License

Copyright (c) 2019, SEMTECH S.A. - BSD 3-Clause License

See [LICENSE](LICENSE) for full license text.
