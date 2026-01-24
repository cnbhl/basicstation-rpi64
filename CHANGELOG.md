# Changelog

## 2.0.6-cnbhl.5 - 2025-01-24

* deps: Extended required dependency checks (gcc, make, curl, sed, grep, tr, cat, cp, mv, chmod, mktemp, tee, stty, timeout, sudo, systemctl)
* security: Atomic temp file writes with restrictive umask (077)
* security: Cleanup trap on EXIT for orphaned temp files
* feature: `--skip-gps` flag to bypass GPS auto-detection
* feature: Privilege detection with `is_root()`, `check_sudo_available()`, `run_privileged()`, `require_privilege()`
* fix: GPS detection avoids duplicate scans via symlink tracking

## 2.0.6-cnbhl.3 - 2025-01-21

* security: Use `set -euo pipefail` for stricter error handling
* security: Write secrets via here-string to prevent process listing exposure
* security: Atomic file writes with permissions set before content written
* security: Sanitize user input for sed to prevent injection attacks
* security: Consistent quoting of all variables
* refactor: Added reusable input functions (confirm, read_secret, read_validated)
* refactor: Added validation functions (validate_eui, validate_not_empty, sanitize_for_sed)
* refactor: Added secure file operations (write_file_secure, write_secret_file, copy_file)
* refactor: Added system check functions (command_exists, file_exists, check_spi_available)
* refactor: Added service management functions (service_is_active, service_start, service_restart)
* refactor: Added safe template processing with process_template()

## 2.0.6-cnbhl.2 - 2025-01-20

* setup: Build chip_id from source for architecture-independent EUI detection
* setup: Added log_hal stub to link chip_id with station's libloragw
* setup: Show chip_id build errors for easier debugging
* setup: Auto-detect ARM architecture (32-bit and 64-bit) for corecell platform
* setup: Fix sysfs GPIO access and auto-restart service on update
* docs: Added Raspberry Pi interface configuration guide (SPI, I2C, serial)
* docs: Updated README with raspi-config requirements

## 2.0.6-cnbhl.1 - 2025-01-19

* Initial fork release with Raspberry Pi 5 support
* Added automated setup script for TTN CUPS configuration
* Added Gateway EUI auto-detection from SX1302/SX1303 chip
* Added systemd service configuration
* Added Pi 5 GPIO compatibility (base offset 571)

## 2.0.6 - 2022-01-17

* deps: Updated sx1302_hal dependency to version 2.1.0 (no LBT yet) (#89, #103, #121, #130)
* deps: Added sx1302_hal patch for handling of latched xticks rollover
* deps: Updated mbedTLS dependency to version 2.28.0 (LTS)
* deps: Fixed lgw patch causing IQ inversion in 500kHz channel (#81)
* s2e: Added support for AU915 (#43)
* s2e: Added support for LoRaWAN Regional Parameters Common Names (#18)
* s2e: Fixed dnchnl2 issue (#79)
* s2e: Fixed class C backoff logic (#87)
* s2e: Fixed class B beacon format (#129, #131)
* s2e: Fixed DR range check in upchannels list parser (#141)
* ral: Changed handling of xticks for lgw1302
* ral: Fixed radio in use issue (#53, #62)
* ral: Fixed types in txpow assignment (master/slave) (#118)
* ral: Fixed class B beacon parameters (#132)
* sx130xconf: Fixed parsing of rssi_tcomp values for sx1302 (#144)
* tls: Fixed TLS cert parsing issue (#76)
* sys_linux: Added support for usb/spi prefix in radio devname
* sys_linux: Added mbedTLS version to startup log
* sys_linux: Changed version to be printed to stdout (#51)
* sys_linux: Changed default max dbuf size (#95)
* sys_linux: Fixed relative home path handling (#140)
* sys_linux: Fixed memory corruption during system command execution (#146)
* tc/cups: Fixed sync on credset file IO (#94)
* timesync: Fixed UTC to PPS alignment
* log: Changed verbosity of XDEBUG log level
* log: Changed logging experience for improved clarity
* log: Added HAL log integration into logging module
* make: Changed makefiles for more space-friendliness (#66)
* net: Changed strictness on line-endings in key files (#68)
* gps: Fixed parsing of ublox NAV-TIMEGPS message
* Restored LICENSE file (#63, #67)

## 2.0.5 - 2020-06-05

* Remove LICENSE & ROADMAP.md file
* Based on v2.0.4 with no source code/functional changes

## 2.0.4 - 2020-03-17

* cups: Added Content-Type header to CUPS request
* cups: Fixed nullify sig pointer after free
* cups: Added segment length checks
* cups: Fixed freeing the key buffer
* deps: Added sx1302 hal and integrated with corecell platform
* sys_linux: Fixed decoder pointer dereferencing (#39)
* sys_linux: Fixed cups update abort should unlink the right file
* sys_linux: Fixed truncate update file instead of append
* s2e: Fixed memory corruption bug in JoinEui filter parsing (#31)
* s2e: Added DR and Freq fields to dntxed message (#37)
* s2e: Added error message type for printing LNS error into Station's log (#33)
* s2e: Added fts field to updf message
* net: Added Websocket PONG (#29)
* net: Added option for TLS server name indication/verification (#57)
* rt: Added MCU clock drift compensation for UTC time offset
* ral: Fixed dntxed message for short transmissions
* ral: Added Automatic channel allocation feature
* ral: Added fine timestamping in lgw2
* ral: Added automatic AES key derivation in lgw2
* ral: Added support for smtcpico platform (experimental) (#16)
* timesync: Correct UTC offset in case PPS offset is known
* lgwsim: Added lgw2 support
* pysys: Fixed Id6 category parsing (#28)
* tests: Added regression tests
* tests: Added Dockerfile

## 2.0.3 - 2019-03-14

* sys_linux: Fixed stdout/stderr redirection for logging
* sys_linux: Added detection of implicit no-cups mode by uri files
* net: Fixed authtoken cleanup in http close
* cups: Fixed skipping credentials during rotation
* ral: Changed pipe read strategy in ral_master to allow partial reads
* tc: Fixed last-resort CUPS triggering from TC backoff
* lgwsim: Changed socket read strategy in lgwsim
* examples: Added CUPS example

## 2.0.2 - 2019-01-30

* cups: Fixed CUPS HTTP POST request. Now contains `Hosts` header.
* tc: Changed backoff strategy of LNS connection.
* ral: Fixed FSK parameters for TX
* ral: Added starvation prevention measure in lgw1 rxpolling loop.
* net: Fixed large file delivery in httpd/web.
* net: Fixed gzip detection heuristic in httpd/web

## 2.0.1 - 2019-01-07

* Initial public release.
