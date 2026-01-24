# chip_id - SX1302 Gateway EUI Detection

Reads the unique Gateway EUI from SX1302/SX1303 concentrator chips.

## Source

Derived from [Semtech sx1302_hal](https://github.com/Lora-net/sx1302_hal) (`util_chip_id/`).

**License:** BSD 3-Clause (see [LICENSE](LICENSE))

## Building

Built automatically by `setup-gateway.sh` after station compilation. Uses `build-corecell-std/lib/liblgw1302.a`.

Manual build:
```bash
gcc -std=gnu11 -O2 \
    -I build-corecell-std/include/lgw \
    tools/chip_id/chip_id.c tools/chip_id/log_stub.c \
    -L build-corecell-std/lib -llgw1302 -lm -lpthread -lrt \
    -o build-corecell-std/bin/chip_id
```

## Usage

```bash
sudo ./build-corecell-std/bin/chip_id -d /dev/spidev0.0
```

Output:
```
INFO: concentrator EUI: 0xAABBCCDDEEFF0011
```

Requires root for SPI/GPIO access and `reset_lgw.sh` in the same directory.
