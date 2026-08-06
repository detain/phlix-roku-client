# BLOCKED — R0.8: Re-verify on the device

**Blocked by:** No Roku device available (ROKU_HOST not set, no physical device on network)

**What this step requires:**
- Physical Roku device or emulator
- Repeat R0.1's procedure after all fixes
- Capture first-boot console log
- Diff against `docs/first-boot-console.log` — the diff is the evidence

**Why it is blocked:**
Same as R0.1 — no device was available in this remediation session.

**What this step verifies:**
- All R0.2-R0.6 fixes actually work at runtime (not just statically)
- The channel can boot past the first frame
- Auth flow works end-to-end on real hardware

**Static verification only:** All static checks in `scripts/verify-runtime.sh` pass (11+ CHECKs).

**Created:** 2026-08-06
