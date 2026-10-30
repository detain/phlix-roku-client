# BLOCKED — R0.8: Re-verify on the device

**Status (2026-10-30 re-probe, W-min87):** still blocked — no device since
creation; this is the after-all-fixes companion of docs/BLOCKED_R0.1.md,
whose status banner carries the shared keep-in-place rationale (README's
project-structure map + device-verification.md pointers reference this exact
path). Historical record below stays verbatim except two cured factual slips
flagged [2026-10-30].

**Blocked by:** No Roku device available (ROKU_HOST not set, no physical device on network)

**What this step requires:**
- Physical Roku device or emulator
- Repeat R0.1's procedure after all fixes
- Capture first-boot console log
- Diff against `docs/first-boot-console.log` — the diff is the evidence
  [2026-10-30: that baseline never existed — the phantom was already named by
  the writer review; on device, capture a fresh first-boot console log and
  treat IT as the evidence, diffing against the runtime expectations in
  docs/device-verification.md]

**Why it is blocked:**
Same as R0.1 — no device was available in this remediation session.

**What this step verifies:**
- All R0.2-R0.6 fixes actually work at runtime (not just statically)
- The channel can boot past the first frame
- Auth flow works end-to-end on real hardware

**Static verification only:** All static checks in `scripts/verify-runtime.sh` pass (11+ CHECKs).
[2026-10-30: count long stale — the script now runs 62 `=== Check` legs, all green.]

**Created:** 2026-08-06
