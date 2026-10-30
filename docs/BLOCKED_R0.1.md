# BLOCKED — R0.1: Sideload once and read the telnet console

**Status (2026-10-30 re-probe, W-min87):** still blocked — no device has
reached this project since the note was created (docs/device-verification.md
records the same queue). Kept in place, not archived: README's project-structure
map and four device-verification.md pointers reference this exact path
(CHECK60 self-pins the map). Historical record below stays verbatim except
one cured factual slip flagged [2026-10-30].

**Blocked by:** No Roku device available (ROKU_HOST not set, no physical device on network)

**What this step requires:**
- Physical Roku device or emulator
- Sideload the channel via `make install ROKU_IP=...`
- Connect to telnet port 8080 to read the console [2026-10-30: wrong port —
  the debug console listens on 8085; see docs/device-verification.md, which
  already states "8080 is not the console port"]
- Capture first-boot errors (R0.2 Storage, R0.4 m.top.Close are the known boot-fatals)

**Why it is blocked:**
No device was available in this remediation session. The plan documents that this channel has never been tested on hardware.

**What the fix is regardless of device:**
- R0.2 (`GetStorage()` pattern): Verified by grep — Storage.get/set/delete/clear are all via GetStorage() factory
- R0.4 (`m.top.Close()`): Verified by grep — no `m.top.Close()` calls exist in the codebase
- R0.6 (`halign=`): Verified by grep — no `halign=` XML attributes exist

**Static verification only:** The `scripts/verify-runtime.sh` checks (CHECK 1, 2, 5) provide the only automated quality bar without a device.

**Created:** 2026-08-06
