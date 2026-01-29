# Features and Changes

Changes in [cnbhl/basicstation-rpi64](https://github.com/cnbhl/basicstation-rpi64) compared to upstream [lorabasics/basicstation](https://github.com/lorabasics/basicstation) Release 2.0.6.

---

## Features

- **Raspberry Pi 5 GPIO support** - Auto-detect GPIO base offset for Pi 5/4/3/older
- **Automated TTN CUPS setup** - Interactive and non-interactive setup wizard (`setup-gateway.sh`)
- **Board configuration system** - Support for WM1302, PG1302, LR1302, SX1302_WS, SEMTECH boards
- **Automatic Gateway EUI detection** - Read EUI from SX1302/SX1303 chip via SPI
- **GPS auto-detection** - Scan serial ports and baud rates to find GPS module
- **Systemd service integration** - Automatic service setup with startup verification
- **Duty cycle enforcement** - ETSI EN 300 220 compliant sliding window tracking (EU868 per-band, AS923/KR920 per-channel)
- **GPS/PPS recovery** - Auto-reset when PPS signal lost >90s, restart after 6 failures
- **GPSD support** - Use gpsd daemon instead of direct serial (compile with `CFG_usegpsd`)
- **GPS control** - LNS can enable/disable GPS via `router_config`
- **Fine timestamp support** - Nanosecond-precision timestamps for SX1303 (opt-in via `"ftime": true`)
- **SF5/SF6 spreading factors** - Support for LoRaWAN RP2 1.0.5 datarates
- **IN865 region** - India 865 MHz band support
- **mbedtls 3.x compatibility** - TLS 1.3 support with PSA crypto

## Fixes

- **Stuck concentrator handling** - Exit after excessive clock drift when SX130x is stuck
- **ifconf zero-initialization** - Prevent stale values in channel config
- **SX1302 LBT error handling** - Correct error constants for SX1302 vs SX1301
- **nocca TX command** - Use correct command when checking response with LBT disabled
- **Fine timestamp rxtime** - Send `fts` as separate field per [#177](https://github.com/lorabasics/basicstation/issues/177)

## Tests

- **Duty cycle regression tests** - EU868, AS923, KR920 test suites
- **PPS recovery test** - Simulated PPS loss and recovery
- **Setup unit tests** - Validation and utility function tests
- **Non-interactive mode tests** - CLI argument parsing tests

---

## Origin

Based on [lorabasics/basicstation](https://github.com/lorabasics/basicstation) Release 2.0.6 with cherry-picks from:
- [MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) - Duty cycle, GPS/PPS, fine timestamps, SF5/SF6, fixes
- [xoseperez/basicstation](https://github.com/xoseperez/basicstation) - Build system reference
