# MultiTech Fork Cherry-Pick Analysis

Analysis of [MultiTechSystems/basicstation](https://github.com/MultiTechSystems/basicstation) commits beyond upstream for potential cherry-picking into our fork. Generated 2026-01-27.

**Context**: Our fork targets Raspberry Pi with SX1302/SX1303 concentrator HATs (WM1302, PG1302, LR1302, SX1302_WS, SEMTECH) for TTN. We use direct serial GPS (not gpsd), mbedtls 2.x, and corecell platform only.

---

## ~~CRITICAL WARNING: Fine Timestamp rxtime Issue~~ FIXED

~~**DO NOT MERGE `feature/fine-timestamp` branch as-is!**~~

The fine timestamp implementation originally embedded `fts` into `rxtime`, but MultiTech **reverted** this approach in commit `5c54f11`. See [lorabasics/basicstation#177](https://github.com/lorabasics/basicstation/issues/177).

**Problem**: `rt_getUTC()` cannot be reliably synchronized to GPS time. Calling it later can advance by a full second, making the sub-second portion misaligned with the fts value.

**Resolution**: The `rxtime` modification has been reverted. The `fts` field is now sent as a separate JSON field, allowing the LNS to combine them server-side with proper GPS-synced time. The branch is now safe to merge.

---

## Already Merged to Master

| Feature | Origin | Status |
|---------|--------|--------|
| IN865 region support | MultiTech `b10bd10` | Merged |
| mbedtls 3.x compatibility | MultiTech `cb9d67b` + `e75b882` + `7a344b8` + `6944075` | Merged |
| ifconf memset initialization | MultiTech `64f634f` | Merged |

## On Existing Branches (not yet merged)

| Branch | Feature | Origin |
|--------|---------|--------|
| `feature/duty-cycle-sliding-window` | EU868 duty cycle bands K, L, N (ETSI EN 300 220) | MultiTech `8a36b49` + `48f8700` |

---

## New Cherry-Picks - Low Effort

### ~~1. ifconf memset initialization~~ MERGED
**Commit**: `64f634f` (partial - just the memset line, skip dac_gain=3 SX1301 part)
**File**: `src/sx130xconf.c`
**Status**: **Merged to master.** Zero-initializes `ifconf` struct before JSON parsing to prevent stale/garbage values in fields not explicitly set by the config.

### ~~2. SF5/SF6 spreading factor support~~ DONE
**Commit**: `799ac21` (partial - just `parse_spread_factor()`)
**File**: `src/sx130xconf.c`
**Status**: Applied on `feature/fine-timestamp` branch. Adds SF5/SF6 cases inside `#if defined(CFG_sx1302)` to prevent crash when LNS sends these datarates. HAL V2.1.0 defines `DR_LORA_SF5`/`DR_LORA_SF6`.

### 3. US915 EIRP increase to 36 dBm
**Commit**: `0a54574`
**File**: `src/s2e.c`
**Change**: Increases US915 default EIRP from 26 to 36 dBm. FCC allows 30 dBm conducted + 6 dBi antenna gain. Setting 36 here supports +3, +6, or +10 dBi antennas since antenna gain is subtracted in the radio layer.

### ~~4. SX1302 LBT error handling fix~~ DONE
**Commit**: `20c64c9` (partial)
**Files**: `src/ral_lgw.c`, `src-linux/ral_slave.c`
**Status**: Applied on `feature/fine-timestamp` branch. Separated SX1302 (`LGW_LBT_NOT_ALLOWED`) vs SX1301 (`LGW_LBT_ISSUE`) error paths in both single-process and slave mode. Note: values are numerically identical (both `1`) due to our HAL patch alias, but the code structure is now correct.

### 5. Antenna gain parsing from config
**Commit**: `38e5fa6` (partial - just the `antenna_gain` JSON case, skip temp comp)
**File**: `src/sx130xconf.c`
**Change**: Parses `antenna_gain` from SX130x JSON config and adjusts `txpowAdjust` to subtract it from TX power. Ensures radiated power stays within regulatory limits when antenna gain is configured.

---

## New Cherry-Picks - Medium Effort

### 6. AS923-2/3/4 region support
**Commits**: `addbe03` + `57456fa` + `65e9e09` + `cbbc0be` (write clean combined patch)
**Files**: `src/kwlist.txt`, `src/kwcrc.h`, `src/s2e.c`
**Change**: Adds AS923-2 (Indonesia, Vietnam), AS923-3 (Philippines, Cuba), AS923-4 (Israel) region handling. Without this, gateways in these regions get "Unrecognized region" with fallback 14 dBm EIRP. Also fixes CCA (Listen Before Talk) enablement for all AS923 variants, not just AS923JP.
**Note**: MultiTech later changed txpow from 13 to 16 for AS923 variants. Whether to use 13 or 16 depends on regulatory interpretation (LoRaWAN RP2 says 16 dBm EIRP for AS923).

### 7. nodc/nocca/nodwell in production builds
**Commit**: `6526117`
**Files**: `src-linux/sys_linux.c`, `src/s2e.c`
**Change**: Upstream blocks `nodc`, `nocca`, `nodwell` in `CFG_prod` builds, silently ignoring them. This is problematic because the LNS may send these settings (TTN sets `nodc: true` for some configs, relying on server-side enforcement). Fix moves only `device_mode` behind `CFG_prod`, letting regulatory overrides pass through. Also adds early return in `update_DC()` when DC is disabled.

---

## Needs Investigation

### 8. Fine timestamp rxtime revert (CRITICAL for feature/fine-timestamp)
**Commit**: `5c54f11` (the `s2e.c` part)
**Issue**: [lorabasics/basicstation#177](https://github.com/lorabasics/basicstation/issues/177)
**Problem**: MultiTech **reverted** embedding `fts` into `rxtime`. The Semtech maintainer explained that `rt_getUTC()` cannot be reliably synchronized to GPS time, and calling it later can advance by a full second, making the sub-second portion misaligned with the fts value. Our `feature/fine-timestamp` (`e65f32a`) uses the same approach that was reverted:
```c
"rxtime", j->fts > -1 ? 'F' : 'T',
    j->fts > -1 ? (sL_t)(rt_getUTC()/1e6) + (double)j->fts/1e9 : rt_getUTC()/1e6,
```
**Recommendation**: Keep `fts` as a separate field in the JSON but revert the `rxtime` modification. The LNS can combine them server-side with proper GPS-synced time.

### ~~9. Timesync exit on stuck concentrator~~ DONE
**Commits**: `5c54f11` + `eee8f10` + `d123cae`
**File**: `src/timesync.c`
**Status**: Applied on `feature/fine-timestamp` branch. Added `exit(EXIT_FAILURE)` after `5*QUICK_RETRIES` excessive drift cycles to force systemd restart when the SX130x concentrator is stuck.

### 10. PPS reset count tracking
**Commit**: `30f65f4`
**File**: `src/timesync.c`
**Change**: If PPS is lost and GPS resets exceed 6 times, forces station exit. Prevents infinite PPS reset loops when GPS is physically disconnected but station keeps trying.
**Note**: Interacts with GPS recovery code.

### 11. TX AIM gap increase
**Commit**: `69a4c2d` (supersedes `2d8cd44`)
**File**: `src/s2conf.h`
**Change**: Increases TX scheduling margin from upstream 20ms to 75ms. Packets to radio were sometimes late. SPI timing on Raspberry Pi can be variable, especially Pi 5 with different GPIO controller. A conservative margin prevents missed TX windows.
**Note**: Test whether 50ms or 75ms is needed for RPi + WM1302/PG1302 combos. 20ms might be fine for SPI-connected corecell HATs.

### 12. SX1302/SX1303 LBT support (large)
**Commit**: `799ac21` (full LBT parts) + `07a5ff2` (fix duplicate frequencies)
**Files**: `src/sx130xconf.c`, `src/sx130xconf.h`
**Change**: Adds Listen Before Talk for SX1302/SX1303 via SX1261 companion radio. Legally required for AS923-JP (Japan) and KR920 (Korea) deployments. Large change: adds `sx1261_cfg` to config struct, LBT setup logic, dump functions, SPI path auto-selection.

### 13. TX power LUT limit for AU/AS
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
