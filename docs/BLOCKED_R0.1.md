# BLOCKED — R0.1: Sideload once and read the telnet console

**Blocked by:** No Roku device available (ROKU_HOST not set, no physical device on network)

**What this step requires:**
- Physical Roku device or emulator
- Sideload the channel via `make install ROKU_IP=...`
- Connect to telnet port 8080 to read the console
- Capture first-boot errors (R0.2 Storage, R0.4 m.top.Close are the known boot-fatals)

**Why it is blocked:**
No device was available in this remediation session. The plan documents that this channel has never been tested on hardware.

**What the fix is regardless of device:**
- R0.2 (`GetStorage()` pattern): Verified by grep — Storage.get/set/delete/clear are all via GetStorage() factory
- R0.4 (`m.top.Close()`): Verified by grep — no `m.top.Close()` calls exist in the codebase
- R0.6 (`halign=`): Verified by grep — no `halign=` XML attributes exist

**Static verification only:** The `scripts/verify-runtime.sh` checks (CHECK 1, 2, 5) provide the only automated quality bar without a device.

**Created:** 2026-08-06
