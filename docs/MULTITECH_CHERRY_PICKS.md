# MultiTech Fork Cherry-Pick Analysis

Analysis of [MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) commits beyond upstream for potential cherry-picking into our fork. Updated 2026-01-30.

**Context**: Our fork targets Raspberry Pi with SX1302/SX1303 concentrator HATs (WM1302, PG1302, LR1302, SX1302_WS, SEMTECH) for TTN. We support direct serial GPS and gpsd (`CFG_usegpsd`), mbedtls 3.6.0 (default), and corecell platform only.

---

## Already Merged to Master

| Feature | Origin | Status |
|---------|--------|--------|
| IN865 region support | MultiTech `b10bd10` | Merged |
| mbedtls 3.x compatibility | MultiTech `cb9d67b` + `e75b882` + `7a344b8` + `6944075` | Merged |
| ifconf memset initialization | MultiTech `64f634f` | Merged |
| Duty cycle sliding window | MultiTech `feature/duty-cycle` branch | Merged |
| GPS/PPS recovery | MultiTech `feature/gps-recovery` branch | Merged |
| GPSD support | MultiTech `feature/gpsd-support` branch | Merged |
| GPS control | MultiTech `dd1035f` + `f5a5f8d` | Merged |
| Fine timestamp support | MultiTech `feature/fine-timestamp` branch | Merged |
| SF5/SF6 spreading factors | MultiTech `799ac21` (partial) | Merged |
| SX1302 LBT error handling | MultiTech `20c64c9` (partial) | Merged |
| Timesync exit on stuck concentrator | MultiTech `eee8f10` | Merged |
| nocca TX command fix | MultiTech `5c54f11` (partial) | Merged |

---

## Potential Future Cherry-Picks

### 1. US915 EIRP increase to 36 dBm
**Commit**: `0a54574`
**File**: `src/s2e.c`
**Change**: Increases US915 default EIRP from 26 to 36 dBm. FCC allows 30 dBm conducted + 6 dBi antenna gain. Setting 36 here supports +3, +6, or +10 dBi antennas since antenna gain is subtracted in the radio layer.

### 2. Antenna gain parsing from config
**Commit**: `38e5fa6` (partial - just the `antenna_gain` JSON case, skip temp comp)
**File**: `src/sx130xconf.c`
**Change**: Parses `antenna_gain` from SX130x JSON config and adjusts `txpowAdjust` to subtract it from TX power. Ensures radiated power stays within regulatory limits when antenna gain is configured.

### 3. AS923-2/3/4 region support
**Commits**: `addbe03` + `57456fa` + `65e9e09` + `cbbc0be` (write clean combined patch)
**Files**: `src/kwlist.txt`, `src/kwcrc.h`, `src/s2e.c`
**Change**: Adds AS923-2 (Indonesia, Vietnam), AS923-3 (Philippines, Cuba), AS923-4 (Israel) region handling. Without this, gateways in these regions get "Unrecognized region" with fallback 14 dBm EIRP. Also fixes CCA (Listen Before Talk) enablement for all AS923 variants, not just AS923JP.
**Note**: MultiTech later changed txpow from 13 to 16 for AS923 variants. Whether to use 13 or 16 depends on regulatory interpretation (LoRaWAN RP2 says 16 dBm EIRP for AS923).

### 4. nodc/nocca/nodwell in production builds
**Commit**: `6526117`
**Files**: `src-linux/sys_linux.c`, `src/s2e.c`
**Change**: Upstream blocks `nodc`, `nocca`, `nodwell` in `CFG_prod` builds, silently ignoring them. This is problematic because the LNS may send these settings (TTN sets `nodc: true` for some configs, relying on server-side enforcement). Fix moves only `device_mode` behind `CFG_prod`, letting regulatory overrides pass through. Also adds early return in `update_DC()` when DC is disabled.

---

## Low Priority / Needs Investigation

### 5. PPS reset count tracking
**Commit**: `30f65f4`
**File**: `src/timesync.c`
**Change**: If PPS is lost and GPS resets exceed 6 times, forces station exit. Prevents infinite PPS reset loops when GPS is physically disconnected but station keeps trying.
**Note**: Interacts with GPS recovery code.

### 6. TX AIM gap increase
**Commit**: `69a4c2d` (supersedes `2d8cd44`)
**File**: `src/s2conf.h`
**Change**: Increases TX scheduling margin from upstream 20ms to 75ms. Packets to radio were sometimes late. SPI timing on Raspberry Pi can be variable, especially Pi 5 with different GPIO controller. A conservative margin prevents missed TX windows.
**Note**: Test whether 50ms or 75ms is needed for RPi + WM1302/PG1302 combos. 20ms might be fine for SPI-connected corecell HATs.

### 7. SX1302/SX1303 LBT support (large)
**Commit**: `799ac21` (full LBT parts) + `07a5ff2` (fix duplicate frequencies)
**Files**: `src/sx130xconf.c`, `src/sx130xconf.h`
**Change**: Adds Listen Before Talk for SX1302/SX1303 via SX1261 companion radio. Legally required for AS923-JP (Japan) and KR920 (Korea) deployments. Large change: adds `sx1261_cfg` to config struct, LBT setup logic, dump functions, SPI path auto-selection.

### 8. TX power LUT limit for AU/AS
**Commit**: `0b0827c`
**File**: `src/sx130xconf.c`
**Change**: Strips TX power LUT entries above 26 dBm for AU915 and AS923 regions. Regulatory safeguard. Depends on whether board's `global_conf.json` has entries above 26 dBm.

---

## Skipped (MultiTech-specific or not applicable)

| Category | Commits |
|----------|---------|
| MultiTech hardware (MTCAP, MTAC-003, MTAC-LORA-1.5) | `3869ce4`, `8c9e3b0`, `994d917`, `fccdc4d`, `da22ab6`, `69a4c2d` (MTAC parts), `57fc081` (RETRY_PIPE_IO) |
| SX1301 temperature compensation | `38e5fa6` (temp parts), `1dd8bbe`, `dbfbdfc`, `d3e8658`, `d4a25ea`, `8bc3807`, `3f28afc` |
| gpsd integration | `09ff50d`, `86f801e`, `68a50a6`-`72be8b8`, `466442f`, `96c8acb` |
| CI/Docker/test infrastructure | `eae86c8`, `5f6eed4`, `90a257e`, `deebb21`, `41b197b`, `8a94630`, `74bcabb`-`4e5b974`, `85cf523`-`97bcde6`, `35182b8`, `5d263e6`, `708bb22`, `4aa72db`, `b6482d2`, `acbb336` |
| Master/slave specific | `0941a92`, `0590973`, `4048575` |
| Test adjustments | `1d58126`, `abcfd10`, `683d511`, `ae8ce67`, `4e79582`, `ab47ebe`, `8cbaf38`, `ea908bc`-`1ce4614`, `32cf807`, `df8a688`, `2ac19cf` |
| Already covered / not applicable | `fc128fe` (license), `165aa4f` (PID check disable), `9bf8241` (SPI path SX1301), `fad4cf5` (#if fix for MultiTech code), `8c73afd` (retry fix - evaluate separately) |
