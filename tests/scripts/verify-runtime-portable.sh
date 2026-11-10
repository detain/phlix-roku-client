#!/usr/bin/env bash
# tests/scripts/verify-runtime-portable.sh
#
# S335 regression test for scripts/verify-runtime.sh's layout-independent path
# resolution.
#
# WHY: pre-fix verify-runtime.sh hardcoded REPO=/home/sites/phlix/phlix-roku-client
# and SERVER_DIR=/home/sites/phlix/phlix-server in all 8 python heredocs. Run from
# any other location the checks crashed ("directory not found") and, under
# `set -euo pipefail`, the FIRST failing check aborted the whole script — later
# checks never ran. The fix derives both paths from the script's own location
# (SCRIPT_DIR -> REPO -> SERVER_DIR), exports REPO/SERVER_DIR for the python
# heredocs, and absorbs per-check failures (PYRET/PYOUT) so every check runs and
# VIOLATIONS accumulate.
#
# WHAT: builds a scratch CI-layout in /tmp:
#     $tmp/repo/           fake checkout — the REAL scripts/verify-runtime.sh,
#                          source/lib/Utilities.brs,
#                          source/lib/Storage.brs + source/main.brs +
#                          source/lib/AppContext.brs (Check 35's wrapper home) +
#                          README.md + tests/fixtures/server-route-manifest.json
#                          + tests/fixtures/error-codes.json (the CHECK99
#                          vendored-registry pin rides the whole-tests cp -a)
#                          (Checks 30-33's inputs - README + route-manifest
#                          truth, root-back exit law, surgical-wipe logout
#                          law),
#                          components/SettingsScene.brs + DetailScene.brs
#                          + PlayerScene.brs (Check 19's fixed target list;
#                          PlayerScene joined via R-ROKU-08, rides the
#                          whole-components cp -a) + SyncPlayTask.brs
#                          (Checks 22/23's wire-in) + SyncPlayScene.brs
#                          (Check 24's only syncplay_members_count consumer -
#                          without it the dead-copy leg would false-red) +
#                          locale/<all shipped
#                          folders> (Check 20's catalog + Check 21's mirrors),
#                          images/, package.json,
#                          manifest; a git index so checks 1-13 (git grep /
#                          git ls-files) work
#     $tmp/phlix-server/migrations/034_media_items_type_audiobook.sql
#                          — the 13-member ENUM, the ONLY migration present
# then runs `bash $tmp/repo/scripts/verify-runtime.sh` from that OTHER location,
# WITHOUT PHLIX_SERVER_DIR set, so the sibling-default resolution is what is
# exercised. Asserts:
#   (1) exit code 0
#   (2) stdout contains "Check 14", "034_media_items_type_audiobook.sql", "PASS"
#   (3) stdout contains every "=== Check 11:" .. "=== Check 24:" header
#   (4) negative: audiobook removed from the Utilities.brs ENUM comment ->
#       exit code non-zero with a CHECK14 diagnostic
#   (5) locale-resolution leg: a "ja-JP"-style device locale normalizes
#       (Trim + Replace("-","_"), the contract in Utilities.brs
#       LoadLocaleStrings) onto locale/ja_JP/, and EVERY literal
#       Translate("key") in the scanned .brs set resolves against that
#       catalog's flattened table — a ja device renders no raw keys (mirrors
#       how Check 20 proves the same for the en_US base)
#   (6) negative: common.ok dropped from the ja_JP mirror in a separate
#       scratch copy -> exit non-zero with a CHECK21 diagnostic, while
#       CHECK14 stays green in that run (per-check gates stay independent)
#   (7) negative: an EmitError call site regressed to a raw display literal in
#       another scratch copy -> exit non-zero with a CHECK23 diagnostic, while
#       CHECK21/CHECK22 stay green (the local family gate is independent)
#   (8) negative: a token-concat regression (a token-bearing catalog key
#       consumed via bare Translate + string append) in another scratch copy
#       -> exit non-zero with a CHECK24 diagnostic naming file:line, while
#       CHECK20/21/22/23 stay green (the token law gate is independent)
#   (9) negative (twin-flip split, post-flip 2026-09-25): a rogue 21st code
#       pushed into the wire census -> exit non-zero with a CHECK22
#       content-pin diagnostic naming the code, while CHECK21 stays green;
#       a rogue declaration in the now-EMPTY reserved function -> CHECK22
#       reserved-leg red ("reserved census drifted"), CHECK21 green; and
#       collapsing SyncPlayReservedErrorCodes() away -> CHECK22 existence-leg
#       red, proving the declaration gate stays armed even with an empty
#       reserved set
#  (10) negative (twin-flip split): an orphan key squatting in the en_US
#       errors registry -> CHECK23 section-purity red naming the key, while
#       CHECK22 stays green (bidirectional registry honesty)
#  (11) negative (CHECK19 exempt anchoring, review #91 LOW): a UI string whose
#       prose contains " for " used to exempt its OWN line via the unanchored
#       \bfor\s+ EXEMPT regex. With the exemptions split into a raw-content
#       family and a code_view family (comments cut, string contents blanked)
#       and the for-exemption anchored to the BrightScript loop-header
#       grammar, the prose plant fires CHECK19 while a real `for i = 0 to 2`
#       colon header carrying a string stays exempt, and CHECK20-24 stay green
#  (12) negative+restore (CHECK20 dotted-key blind spot, df4e7a2 follow-up):
#       CHECK 20's key regex was the dotless class [A-Za-z0-9_], so a dotted
#       Translate("section.key") literal was INVISIBLE — it can never resolve
#       against the flat "section_bareKey" table yet shipped rendering raw keys
#       (AudiobookPlayerScene.brs). The regex now includes '.'; planting a
#       dotted Translate in a scratch copy must fire CHECK20 red naming the
#       file and both the dotted key and its underscore suggestion, and
#       removing the plant must return the run to exit 0 (falsifiability).
#  (13) validate-xml zero-file-guard legs (estate CI-gate audit 2026-10-02):
#       the pre-fix `make validate-xml` was an inline Makefile glob loop that
#       exited 0 whenever it discovered ZERO files — a renamed components dir
#       or drifted path pattern validated nothing yet greened the gate
#       (vacuous pass). scripts/validate-xml.sh now counts its discovery and
#       halts loud. Legs: (a) the real repo's components/ validates green
#       (exit 0 + "XML validation passed"); (b) an EMPTY scratch root ->
#       non-zero + the loud "discovered ZERO XML files" message; (c) a
#       MISSING root -> non-zero + "does not exist"; (d) a planted malformed
#       XML in a scratch COPY of the real components -> non-zero naming the
#       plant (extraction fidelity), and removing the plant -> exit 0
#       (falsifiability, house planted-red tradition); (e) W-min92/M-ROKU-19:
#       a malformed XML planted in a NESTED directory -> convicted by its
#       relative path (the post-audit era still scanned a FLAT
#       components/*.xml glob — nested files had zero coverage while
#       total_files stayed > 0); (f) a planted file that passes BOTH legacy
#       substring greps yet is not well-formed XML -> convicted with the
#       parser's reason (the two greps were never a parse).
#  (14) negative+restore (M-ROKU-08 aggregation, the print-only-gate class):
#       checks 1-10 re-zeroed the shared VIOLATIONS accumulator at the check
#       8/9/10/11 headers, so their violations printed but never gated
#       `exit $((VIOLATIONS))` (planted CHECK1 hit -> printed, exit 0). The
#       cured script has ONE sink: a planted CHECK1 violation in a scratch copy
#       must exit non-zero (plant rides the earliest leg = maximum wipe
#       distance, so any re-zero re-added in the cured range reddens this
#       leg — mutation-proven), CHECK20/21/39 stay green (gate independence),
#       and removing the plant returns exit 0 (falsifiability).
#  (15) negative+restore (M-ROKU-09 dead versioning design): re-planting the
#       cured class into a scratch copy of scripts/derive-version.sh — a
#       function reachable from nothing (the deleted get_git_count/
#       get_ci_build_version twin) plus a usage-header flag no main() arm
#       dispatches (--ghost) — must fire CHECK40 R1+R2 naming both plants,
#       with CHECK18/CHECK39 gate independence, and restoring the cured file
#       returns exit 0. Check 40 also asserts green on the positive run (its
#       inputs — derive-version.sh, .github/workflows/package.yml,
#       docs/publishing.md — joined the stage list).
#  (16) negative+restore (M-ROKU-10 signing-claim honesty): re-planting the
#       cured class into a scratch copy of scripts/package-signed.sh — the
#       phantom password-env claim (ROKU_DEV_PASSWORD), the rename-unsigned-
#       zip-into-.pkg fallback line, and a hardcoded PKG_VERSION default —
#       plus an un-provisioned package-signed stub job into a scratch
#       package.yml must fire CHECK41 R1+R2+R3+R4 naming each plant, with
#       CHECK18/CHECK40 gate independence; restoring the cured files returns
#       exit 0. Check 41's inputs (package-signed.sh and the Makefile joined
#       the stage list beside package.yml/publishing.md) also assert green on
#       the positive run. The M-ROKU-29 rider (R5) joins the family: the
#       self-signed-sideload fiction planted into package-signed.sh, the
#       sagas.xml + sideload-testing lines planted into docs/publishing.md,
#       and the "self-signed cert only sideloads" line planted into README.md
#       must fire CHECK41 R5 naming each of the three files.
#
# RUN:  bash tests/scripts/verify-runtime-portable.sh
# There is no Makefile slot: `make check` is a prerequisites probe, not a script
# runner, so this test is intentionally standalone. Wire it into a CI job or a
# future tests/ runner if one appears.

set -euo pipefail

for tool in bash git python3 cp rm mktemp mkdir printf; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "FAIL: required tool '$tool' not found" >&2
		exit 1
	}
done

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/s335-portable.XXXXXX")
FAKE_REPO="$TEST_ROOT/repo"
FAKE_SERVER="$TEST_ROOT/phlix-server"
REAL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_REPO="$(cd "$REAL_SCRIPT_DIR/../.." && pwd)"

cleanup() {
	rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	local needle="$1" haystack="$2"
	if ! grep -qF "$needle" <<<"$haystack"; then
		fail "expected output to contain '$needle'"
	fi
}

# --- source files (resolve the migration the same way the script does) ------
REAL_SERVER="${PHLIX_SERVER_DIR:-$(dirname "$REAL_REPO")/phlix-server}"
MIGRATION="$REAL_SERVER/migrations/034_media_items_type_audiobook.sql"
[ -f "$MIGRATION" ] || fail "migration not found at $MIGRATION — set PHLIX_SERVER_DIR or have phlix-server as a sibling of $REAL_REPO"

mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/source/lib" "$FAKE_REPO/components" "$FAKE_REPO/images"
mkdir -p "$FAKE_SERVER/migrations"

cp "$REAL_REPO/scripts/verify-runtime.sh" "$FAKE_REPO/scripts/verify-runtime.sh"
# Check 40 (M-ROKU-09) probes scripts/derive-version.sh behavior and reads the
# publish workflow + version-discipline docs; stage its four inputs.
cp "$REAL_REPO/scripts/derive-version.sh" "$FAKE_REPO/scripts/derive-version.sh"
mkdir -p "$FAKE_REPO/.github/workflows" "$FAKE_REPO/docs"
cp "$REAL_REPO/.github/workflows/package.yml" "$FAKE_REPO/.github/workflows/package.yml"
# CHECK65 R5 (M-ROKU-17 wiring law) reads the unit-test workflow for the
# headless-gate step and the dead-step shape: stage test.yml beside
# package.yml, or the positive leg crashes FileNotFoundError in the CI layout.
cp "$REAL_REPO/.github/workflows/test.yml" "$FAKE_REPO/.github/workflows/test.yml"
cp "$REAL_REPO/docs/publishing.md" "$FAKE_REPO/docs/publishing.md"
# Check 41 (M-ROKU-10) pins the signing wrapper's claims to its enforcement
# and the Makefile's version threading: stage package-signed.sh + Makefile
# beside the package.yml/docs publishing.md already stages.
cp "$REAL_REPO/scripts/package-signed.sh" "$FAKE_REPO/scripts/package-signed.sh"
cp "$REAL_REPO/Makefile" "$FAKE_REPO/Makefile"
cp "$REAL_REPO/source/lib/Utilities.brs" "$FAKE_REPO/source/lib/Utilities.brs"
# Checks 30/32 read README.md, Check 31 reads source/main.brs and Check 33
# reads source/lib/Storage.brs. They joined the stage list when those checks
# landed (M-ROKU-02/M-ROKU-03/C33 wave); without them the positive leg crashed
# FileNotFoundError in the CI layout.
cp "$REAL_REPO/source/lib/Storage.brs" "$FAKE_REPO/source/lib/Storage.brs"
# Check 35's wrapper-home leg reads source/lib/AppContext.brs; without it the
# leg reports "wrapper file gone" in the fake layout (staging gap found while
# landing Check 36, M-ROKU-04 closeout).
cp "$REAL_REPO/source/lib/AppContext.brs" "$FAKE_REPO/source/lib/AppContext.brs"
# Check 60 (M-ROKU-32) walks source/ + components/ for the shipped .brs set and
# compares it against the README structure map: the last three unstaged source
# files join the stage list (components ride the whole-components cp -a), so the
# bidirectional law sees the complete tree in the CI layout too.
cp "$REAL_REPO/source/lib/AuthManager.brs" "$FAKE_REPO/source/lib/AuthManager.brs"
mkdir -p "$FAKE_REPO/source/player"
cp "$REAL_REPO/source/player/SkipButton.brs" "$FAKE_REPO/source/player/SkipButton.brs"
cp "$REAL_REPO/source/player/SleepTimer.brs" "$FAKE_REPO/source/player/SleepTimer.brs"
# MJ-12 era: the panel-stack decision module rides too — PlayerScene.xml lists
# it as a scoped script and Check 60 convicts it as a phantom landmark without
# it (the new-files-join-the-stage-list law, :213 comment).
cp "$REAL_REPO/source/player/PanelStack.brs" "$FAKE_REPO/source/player/PanelStack.brs"
# Check 42 (M-ROKU-11) pins the three ApiClient send sites, the roAppInfo
# single source and the docs/debugging.md support story: both ride along.
cp "$REAL_REPO/source/lib/ApiClient.brs" "$FAKE_REPO/source/lib/ApiClient.brs"
cp "$REAL_REPO/docs/debugging.md" "$FAKE_REPO/docs/debugging.md"
# Check 47 (M-ROKU-16) R3 pins the bootstrap Back law docs truth —
# docs/navigation.md + docs/certification.md join the stage list.
cp "$REAL_REPO/docs/navigation.md" "$FAKE_REPO/docs/navigation.md"
cp "$REAL_REPO/docs/certification.md" "$FAKE_REPO/docs/certification.md"
# Check 54 (M-ROKU-22 residual) R3 scans the checks ledger itself for the
# vanished-history pointer family: docs/static-checks.md joins the stage list
# (its row 46 carries the scoped transport truth the same leg's R2 family
# guards).
cp "$REAL_REPO/docs/static-checks.md" "$FAKE_REPO/docs/static-checks.md"
# Check 56 (M-ROKU-26) R2 reads the docs that name the dead SyncPlay room pair
# and the manager file's own banner: docs/api-envelope.md, docs/i18n.md and
# source/lib/SyncPlayManager.brs join the stage list (the two room files ride
# via the whole-components cp -a and the SyncPlayScene.brs cp above; README,
# Utilities and the locale/ set are staged already).
cp "$REAL_REPO/docs/api-envelope.md" "$FAKE_REPO/docs/api-envelope.md"
cp "$REAL_REPO/docs/i18n.md" "$FAKE_REPO/docs/i18n.md"
cp "$REAL_REPO/source/lib/SyncPlayManager.brs" "$FAKE_REPO/source/lib/SyncPlayManager.brs"
# Check 69 (R-ROKU-26) R2 censuses per-file canonical Roku-doc citations; its
# carrier list includes docs/bif_thumbs.md (the bifdisplay rotation), so that
# file joins the stage list — a carrier missing from the layout would convict
# the positive CI-layout run itself.
cp "$REAL_REPO/docs/bif_thumbs.md" "$FAKE_REPO/docs/bif_thumbs.md"
# Check 75 (R-ROKU-31) R1 scans the WHOLE shipped doc surface (Makefile,
# README, CLAUDE.md, every docs/*.md except the checks ledger, every workflow
# YAML, every shipped .brs) and R3 floors the count at 70 with mandatory root
# anchors — so CI layout and repo must measure the identical 77-file set
# (the RT-096 pass added DEVELOPER.md to the scan set in both layouts).
# CLAUDE.md, lint.yml and the five previously unstaged docs join the stage
# list (CHECK41/CHECK60 staging-gap precedent); the source/ .brs set and the
# whole components/ tree are already staged above.
cp "$REAL_REPO/CLAUDE.md" "$FAKE_REPO/CLAUDE.md"
cp "$REAL_REPO/.github/workflows/lint.yml" "$FAKE_REPO/.github/workflows/lint.yml"
cp "$REAL_REPO/docs/architecture-apitask.md" "$FAKE_REPO/docs/architecture-apitask.md"
cp "$REAL_REPO/docs/BLOCKED_R0.1.md" "$FAKE_REPO/docs/BLOCKED_R0.1.md"
cp "$REAL_REPO/docs/BLOCKED_R0.8.md" "$FAKE_REPO/docs/BLOCKED_R0.8.md"
cp "$REAL_REPO/docs/device-verification.md" "$FAKE_REPO/docs/device-verification.md"
cp "$REAL_REPO/docs/image_generation_info.md" "$FAKE_REPO/docs/image_generation_info.md"
# Check 44 (M-ROKU-11 completion) pins the task-thread version leaf in
# source/lib/SyncPlayProtocol.brs (the two task components ride via cp -a).
cp "$REAL_REPO/source/lib/SyncPlayProtocol.brs" "$FAKE_REPO/source/lib/SyncPlayProtocol.brs"
cp "$REAL_REPO/source/main.brs" "$FAKE_REPO/source/main.brs"
cp "$REAL_REPO/README.md" "$FAKE_REPO/README.md"
# M-ROKU-23: CHECK54 R5 reads the CHANGELOG naming law; it joins the stage list.
cp "$REAL_REPO/CHANGELOG.md" "$FAKE_REPO/CHANGELOG.md"
# CHECK96 (w07 hygiene wave): R3 reads scripts/verify-package.sh and R5 reads
# .gitignore — both are tracked repo members whose absence would convict
# 'unreadable' in the CI layout. They join the stage list (M-ROKU-23 precedent:
# each era stages the files its own pins read).
cp "$REAL_REPO/scripts/verify-package.sh" "$FAKE_REPO/scripts/verify-package.sh"
cp "$REAL_REPO/.gitignore" "$FAKE_REPO/.gitignore"
# Check 46 (M-ROKU-14) R4 pins the SyncPlay origin/accept unit suite by name,
# so tests/unit must ride the CI layout (the R1-R3 inputs — Utilities, the
# Protocol trio, PlayerScene via the whole-components cp -a, SyncPlayTask, the
# seven catalogs and README — are all staged already).
mkdir -p "$FAKE_REPO/tests/unit"
cp "$REAL_REPO/tests/unit/SyncPlayWsTls.test.brs" "$FAKE_REPO/tests/unit/SyncPlayWsTls.test.brs"
# Check 48 (M-ROKU-15) R4 pins the credential-custody unit suite by name; its
# R1-R3 inputs (ApiClient, Utilities, ConnectScene, the seven catalogs) are all
# staged already.
cp "$REAL_REPO/tests/unit/RedirectCustody.test.brs" "$FAKE_REPO/tests/unit/RedirectCustody.test.brs"
# Check 49 (M-ROKU-17) R6 pins the ToastManager root walk in
# source/lib/ToastManager.brs; its other inputs (ToastScene.xml + the
# ToastScene.brs absence via the whole-components cp -a, the PhlixApp
# coordinator, the PlayerScene delivery wire) are staged already. M-ROKU-17r2's R7 (dispatch contract + pre-attach drain) pins the same staged ToastManager.brs and the whole-components PhlixApp.brs.
cp "$REAL_REPO/source/lib/ToastManager.brs" "$FAKE_REPO/source/lib/ToastManager.brs"
mkdir -p "$FAKE_REPO/tests/fixtures"
cp "$REAL_REPO/tests/fixtures/server-route-manifest.json" "$FAKE_REPO/tests/fixtures/server-route-manifest.json"
# Check 62 (M-ROKU-31) censuses the WHOLE tests/ tree against README.md, so every
# *.test.brs (unit + integration) and the scripts/ members must ride the CI layout.
# The superset keeps Check 46/48's two name-pinned files above staged (they are
# members of the same tree); the real repo passes this leg with the same inventory.
cp -a "$REAL_REPO/tests"/. "$FAKE_REPO/tests/"
cp "$REAL_REPO/components/SettingsScene.brs" "$FAKE_REPO/components/SettingsScene.brs"
cp "$REAL_REPO/components/DetailScene.brs" "$FAKE_REPO/components/DetailScene.brs"
# Check 22 requires the syncplay_error wire-in file to exist in the checkout.
cp "$REAL_REPO/components/SyncPlayTask.brs" "$FAKE_REPO/components/SyncPlayTask.brs"
# Check 24's dead-copy leg needs every token-bearing key's consumer present:
# syncplay_members_count is consumed only in SyncPlayScene.brs.
cp "$REAL_REPO/components/SyncPlayScene.brs" "$FAKE_REPO/components/SyncPlayScene.brs"
# Check 25 scans components/**/*.xml chrome literals and the paired .brs
# override paths, so the whole components/ dir rides along. Checks 1-13 only
# read .brs content that is green upstream, so the superset stays green.
cp -a "$REAL_REPO/components"/. "$FAKE_REPO/components/"
cp -a "$REAL_REPO/images"/. "$FAKE_REPO/images/"
cp "$REAL_REPO/package.json" "$FAKE_REPO/package.json"
cp "$REAL_REPO/manifest" "$FAKE_REPO/manifest"
cp "$MIGRATION" "$FAKE_SERVER/migrations/034_media_items_type_audiobook.sql"
# Check 20 resolves Translate() keys against the real catalog — ship it in the fake repo.
cp -a "$REAL_REPO/locale" "$FAKE_REPO/locale"

# Checks 1-13 use `git grep` / `git ls-files`, so the fake repo needs an index.
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" add -A

# --- positive: sibling-default resolution, PHLIX_SERVER_DIR deliberately unset
unset PHLIX_SERVER_DIR
set +e
POSITIVE_OUT=$(cd /tmp && bash "$FAKE_REPO/scripts/verify-runtime.sh" 2>&1)
POSITIVE_RC=$?
set -e

[ "$POSITIVE_RC" -eq 0 ] || fail "verify-runtime.sh should exit 0 from a CI layout (got $POSITIVE_RC)"
assert_contains "=== Check 14:" "$POSITIVE_OUT"
assert_contains "034_media_items_type_audiobook.sql" "$POSITIVE_OUT"
assert_contains "PASS" "$POSITIVE_OUT"
for i in $(seq 11 26); do
	assert_contains "=== Check $i:" "$POSITIVE_OUT"
done
# M-ROKU-04 r2: Check 37's inputs (components/*.brs + source/lib/Utilities.brs)
# are all staged in the fake layout, so the leg must also run green there.
assert_contains "=== Check 37:" "$POSITIVE_OUT"
# M-ROKU-06: Check 38's inputs (manifest + components/*.xml) are all staged in
# the fake layout, so the design-plane leg must also run green there.
assert_contains "=== Check 38:" "$POSITIVE_OUT"
# M-ROKU-07: Check 39's inputs (manifest + shipped .brs for the Eval() leg) are
# all staged in the fake layout, so the rsg_version value-space leg must also
# run green there.
assert_contains "=== Check 39:" "$POSITIVE_OUT"
assert_contains "CHECK39: rsg_version=1.3 inside" "$POSITIVE_OUT"
# M-ROKU-09: Check 40's inputs (derive-version.sh + package.yml +
# docs/publishing.md + README) are all staged, so the version-discipline and
# publish-vehicle leg must run green in the CI layout too.
assert_contains "=== Check 40:" "$POSITIVE_OUT"
assert_contains "CHECK40: derive-version.sh fully reachable" "$POSITIVE_OUT"
# M-ROKU-10: Check 41's inputs (package-signed.sh + Makefile + package.yml +
# docs/publishing.md) are all staged, so the signing-honesty leg must run
# green in the CI layout too.
assert_contains "=== Check 41:" "$POSITIVE_OUT"
assert_contains "=== Check 44:" "$POSITIVE_OUT"
assert_contains "CHECK41: no phantom password-secret claim" "$POSITIVE_OUT"
assert_contains "CHECK21: all" "$POSITIVE_OUT"
assert_contains "CHECK22: all" "$POSITIVE_OUT"
assert_contains "CHECK23: all" "$POSITIVE_OUT"
assert_contains "CHECK24: all" "$POSITIVE_OUT"
assert_contains "CHECK25: all" "$POSITIVE_OUT"
assert_contains "CHECK26: all" "$POSITIVE_OUT"
# M-ROKU-12: Check 43's inputs (all staged .brs + the Utilities/ApiTask cure
# choke) are in the fake layout, so the wire-text type-guard leg must run
# green in the CI layout too — with the in-flight ApiClient-choke pair
# WARN-listed, never counted.
assert_contains "=== Check 43:" "$POSITIVE_OUT"
assert_contains "CHECK43: all wire" "$POSITIVE_OUT"
# M-ROKU-13: Check 45's inputs (the Utilities guard family, the PhlixApp
# entry/choke via the whole-components cp -a, and the staged source/main.brs
# launch entry) are all in the fake layout, so the content-id shape law must
# run green in the CI layout too.
assert_contains "=== Check 45:" "$POSITIVE_OUT"
assert_contains "CHECK45: content-id allowlist" "$POSITIVE_OUT"
# M-ROKU-14: Check 46's inputs (PlayerScene origin choke, SyncPlayTask accept
# proof, the Protocol trio, the Utilities predicate + census, the seven
# catalogs and the unit suite) are all in the fake layout, so the SyncPlay
# origin/accept law must run green in the CI layout too.
assert_contains "=== Check 46:" "$POSITIVE_OUT"
assert_contains "CHECK46: https origins refuse the plaintext :8097 dial" "$POSITIVE_OUT"
# M-ROKU-16: Check 47 inputs (the four bootstrap scenes and the PhlixApp
# boot chrome ride the whole-components cp -a; the two docs join the stage
# list), so the bootstrap Back law must run green in the CI layout too.
assert_contains "=== Check 47:" "$POSITIVE_OUT"
assert_contains "CHECK47: bootstrap scenes never consume Back" "$POSITIVE_OUT"
# M-ROKU-15: Check 48's inputs (the two credentialed send sites + the Location
# reader, the ConnectScene consent choke, the Utilities custody leaves, the
# seven catalogs and the unit suite) are all in the fake layout, so the
# credential-custody law must run green in the CI layout too.
assert_contains "=== Check 48:" "$POSITIVE_OUT"
assert_contains "CHECK48: credentialed sends decide redirects" "$POSITIVE_OUT"
# M-ROKU-17: Check 49's inputs (the re-based ToastScene.xml and the root
# coordinator ride the whole-components cp -a; the PlayerScene delivery wire,
# the ToastManager root walk, and the ToastScene.brs ABSENCE pin ride their
# staged paths), so the toast-display law must run green in the CI layout too.
assert_contains "=== Check 49:" "$POSITIVE_OUT"
assert_contains "CHECK49: the toast overlay is a built-in-Dialog node" "$POSITIVE_OUT"
# M-ROKU-17r2: the two-arg onMessage contract, its guarded arm and the
# pre-attach queue drain ride PhlixApp.brs + the staged ToastManager.brs —
# both in the fake layout — so R7 must run green in the CI layout too.
assert_contains "fiction stays extinct repo-wide and the pre-attach queue drain" "$POSITIVE_OUT"

# M-ROKU-19: Check 50's inputs (PlayerScene.xml + PlayerScene.brs ride the
# whole-components cp -a), so the party-attribution law must run green in the
# CI layout too.
assert_contains "=== Check 50:" "$POSITIVE_OUT"
assert_contains "CHECK50: host pause/seek/resume, joins, host elections" "$POSITIVE_OUT"

# M-ROKU-20: Check 51's inputs (PlayerScene.brs via the whole-components
# cp -a; the seven locale catalogs via the locale staging), so the live-error
# i18n law — three Translate-backed overlay arms, no re-grown raw English,
# per-locale speakability — must run green in the CI layout too.
assert_contains "=== Check 51:" "$POSITIVE_OUT"
assert_contains "CHECK51: the error-overlay trio" "$POSITIVE_OUT"

# M-ROKU-21: Check 52's inputs (DashboardScene.brs/.xml + HomeScene.brs/.xml via
# the whole-components cp -a; the three new keys via the locale staging) are all
# in the fake layout, so the failure-vs-emptiness law — invalid-not-[] failure
# classification, owned failure branches, focusable Retry, per-locale speakable
# copy — must run green in the CI layout too.
assert_contains "=== Check 52:" "$POSITIVE_OUT"
assert_contains "CHECK52: a failed read yields invalid (never" "$POSITIVE_OUT"

# M-ROKU-24: Check 53's inputs (components/ConnectScene.brs + PhlixApp.brs via
# the whole-components cp -a) are in the fake layout, so the custody-at-the-choke
# law — conditional six-key wipe preceding the server_url write and the connected
# signal, the single R1.6 primitive, the pure-rebuild OnConnected — must run
# green in the CI layout too.
assert_contains "=== Check 53:" "$POSITIVE_OUT"
assert_contains "CHECK53: the one server_url write-site wipes" "$POSITIVE_OUT"

# M-ROKU-22 residual: Check 54's inputs (components/PlayerScene.brs +
# components/SyncPlayTask.brs via the whole-components cp -a, README.md +
# source/lib/SyncPlayProtocol.brs + docs/static-checks.md via the stage list)
# are all in the fake layout, so the dial-composition census and the
# truth-presence/dead-pointer arms must run green in the CI layout too.
assert_contains "=== Check 54:" "$POSITIVE_OUT"
assert_contains "CHECK54: the SyncPlayTask dial composes" "$POSITIVE_OUT"
# M-ROKU-23: Check 55's inputs (components/PhlixApp.brs + HubCommandTask.brs +
# source/lib/Utilities.brs + README.md via the staging copies) are in the fake
# layout, so the hub-relay origin law — predicate shape + device-safe globals,
# refuse-before-credential scene choke, refuse-before-mint task choke, the
# no-fabricated-TLS pin and the docs law — must run green in the CI layout too.
assert_contains "=== Check 55:" "$POSITIVE_OUT"
assert_contains "CHECK55: the hub relay refuses" "$POSITIVE_OUT"
# M-ROKU-25: Check 57's inputs (the seven catalogs via the locale staging,
# components/PlayerScene.brs via the whole-components cp -a, README.md +
# docs/i18n.md via the stage list) are all in the fake layout, so the co-watch
# one-name law — value convictions over the key scope, the renamed default, the
# frozen identifier census and the docs vocabulary — must run green in the CI
# layout too.
assert_contains "=== Check 57:" "$POSITIVE_OUT"
assert_contains "CHECK57: the co-watch feature speaks with one name" "$POSITIVE_OUT"

# M-ROKU-21f: Check 58's input (components/HomeScene.brs via the whole-components
# cp -a; the R2 census walks components/ + source/ .brs, all staged) is in the
# fake layout, so the stand-down-guard recognition arm and the sole-writer
# census run green in the CI layout too.
assert_contains "=== Check 58:" "$POSITIVE_OUT"
assert_contains "CHECK58: the stand-down guard restores the default strip" "$POSITIVE_OUT"
# M-ROKU-32: Check 60's inputs (README.md via the whole-README stage + the now
# complete source/ tree beside the whole-components cp -a) pin the structure map
# bidirectionally — the fake CI layout must see exactly the same 57 .brs names.
assert_contains "=== Check 60:" "$POSITIVE_OUT"
assert_contains "CHECK60: the Project Structure map lists exactly the 58 shipped .brs" "$POSITIVE_OUT"

# M-ROKU-37: Check 61's inputs (README.md, docs/i18n.md and the locale/ set are
# all staged already) — the locale-family enumeration law — Overview total in
# words, both docs trees enumerating every directory, folder self-identity —
# runs green in the CI layout too.
assert_contains "=== Check 61:" "$POSITIVE_OUT"
assert_contains "CHECK61: the family set is the directory" "$POSITIVE_OUT"

# M-ROKU-33: Check 59's inputs (CHANGELOG.md via the stage list beside Check 54's
# naming law, package.json staged for Check 18, and the fake repo's git-init for
# the R3 tag census) are all in the fake layout, so the release-truth law —
# rolling header, model-block cross-truth, anti-fabrication census — runs green
# in the CI layout too.
assert_contains "=== Check 59:" "$POSITIVE_OUT"
assert_contains "CHECK59: the CHANGELOG names the vehicle that exists" "$POSITIVE_OUT"

# M-ROKU-26: Check 56's inputs (the dead room pair via the whole-components
# cp -a, the manager via the stage list, README + Utilities + the three docs +
# the seven catalogs staged) are all in the fake layout, so the
# instantiation-census, truth-presence and provenance-kept arms run green in
# the CI layout too.
assert_contains "=== Check 56:" "$POSITIVE_OUT"
assert_contains "CHECK56: the SyncPlay room scene has zero instantiation sites" "$POSITIVE_OUT"

# R-ROKU-25: Check 35's inputs (the staged AppContext.brs wrapper home + the
# whole source/components cp families) run green in the CI layout too — the
# balanced-walk R1 amnesty for the shipped options-AA call is what makes the
# positive leg non-vacuous for this check — and its conviction family is
# proven red-side by the plant leg near the file's end.
assert_contains "=== Check 35:" "$POSITIVE_OUT"
assert_contains "CHECK35: options-AA call shape, result-key parse, and three fail-open " "$POSITIVE_OUT"

# --- locale resolution: simulate the device selecting a ja_JP-style locale ---
# LoadLocaleStrings normalizes roAppInfo.GetCurrentLocale() with .Trim().
# Replace("-", "_") and reads pkg:/locale/<tag>/strings.json, falling back to
# pkg:/locale/en_US/strings.json only when that read misses. Here we walk the
# SAME synthetic tree the checks just blessed: normalize a "ja-JP" firmware
# string the way the loader does, require the folder to exist (no fallback),
# flatten its catalog the way FlattenLocaleCatalog does, and resolve every
# literal Translate("key") from the scanned .brs set against it — exactly the
# guarantee Check 20 gives the en_US base, now proven for a shipped sibling.
export FAKE_REPO
python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ['FAKE_REPO']

def fail(msg):
    print(f"FAIL: locale-resolution leg: {msg}", file=sys.stderr)
    raise SystemExit(1)

# (i) The loader's normalization contract must still live in Utilities.brs —
# this leg's simulation is only faithful while the real code agrees with it.
with open(os.path.join(repo, 'source/lib/Utilities.brs'), encoding='utf-8') as f:
    util = f.read()
if '.Trim().Replace("-", "_")' not in util:
    fail('Utilities.brs no longer normalizes the device locale with .Trim().Replace("-", "_") — update this leg in lockstep')
if '"pkg:/locale/en_US/strings.json"' not in util:
    fail('Utilities.brs no longer names pkg:/locale/en_US/strings.json as the fallback base')

# (ii) Simulate a device reporting "ja-JP" (firmware emits both separator
# styles; the loader normalizes to underscore).
device_locale = "  ja-JP "  # padded on purpose: Trim is part of the contract
tag = device_locale.strip().replace("-", "_")
catalog_path = os.path.join(repo, 'locale', tag, 'strings.json')
if not os.path.isfile(catalog_path):
    fail(f"device locale {device_locale!r} normalizes to {tag!r} but {catalog_path} is not in the package — loader would silently fall back to en_US")

# (iii) Flatten section+bareKey exactly like FlattenLocaleCatalog().
with open(catalog_path, encoding='utf-8') as f:
    catalog = json.load(f)
flat = set()
for section, data in catalog.items():
    if section == '_metadata' or not isinstance(data, dict):
        continue
    for bare_key, value in data.items():
        if isinstance(value, str):
            flat.add(section + '_' + bare_key)

# (iv) Every literal Translate("key") in Check 19/20's scanned set resolves.
tr = re.compile(r'Translate\(\s*"([A-Za-z0-9_]+)"')
missing = []
for rel in ('source/lib/Utilities.brs', 'components/SettingsScene.brs', 'components/DetailScene.brs'):
    with open(os.path.join(repo, rel), encoding='utf-8', errors='replace') as f:
        text = f.read()
    for line in text.split('\n'):
        # BrightScript comment masking: a single quote outside a double-quoted
        # string comments the rest of the line; a line opening on a double
        # quote is doc-style noise (mirrors Check 20's skip rule).
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        code = line[:cut]
        if code.lstrip().startswith('"'):
            continue
        for mo in tr.finditer(code):
            if mo.group(1) not in flat:
                missing.append(f"{rel}: {mo.group(1)}")
# The dynamic RatingLabel labels[] array (Check 20's other scan) too.
fn = re.search(r'function RatingLabel\(.*?\nend function', util, re.DOTALL)
if fn is None:
    fail('RatingLabel function not found in Utilities.brs')
labels = re.search(r'labels\s*=\s*\[([^\]]*)\]', fn.group(0))
if labels is None:
    fail('labels array not found inside RatingLabel')
for key in re.findall(r'"([A-Za-z0-9_]+)"', labels.group(1)):
    if key not in flat:
        missing.append(f'Utilities.brs RatingLabel: {key}')

if missing:
    fail('ja_JP catalog would render raw keys for: ' + ', '.join(sorted(set(missing))))
print(f"  locale-resolution leg: device locale {device_locale!r} -> {tag} -> "
      f"{len(flat)} flattened keys, all literal Translate keys resolve (no en_US fallback needed)")
PYEOF

# --- Check 21 red proof on an independent scratch copy (FAKE_REPO stays
# pristine for the ENUM leg below; per-check gates must not entangle) --------
RED21_ROOT="$TEST_ROOT/red21"
mkdir -p "$RED21_ROOT"
cp -a "$TEST_ROOT/repo" "$RED21_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED21_ROOT/phlix-server"
python3 - "$RED21_ROOT/repo/locale/ja_JP/strings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    d = json.load(f)
del d['common']['ok']
with open(p, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
PYEOF
set +e
RED21_OUT=$(bash "$RED21_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED21_RC=$?
set -e
[ "$RED21_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a locale mirror loses a key (got 0)"
assert_contains "CHECK21" "$RED21_OUT"
assert_contains "common_ok" "$RED21_OUT"
# Section-scoped (output length between header and verdict varies per check):
sed -n '/=== Check 14:/,/=== Check 15:/p' <<<"$RED21_OUT" | grep -q "  PASS" ||
	fail "Check 14 must stay PASS while Check 21 is red (gate independence)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED21_OUT" | grep -q "  PASS" ||
	fail "Check 20 must stay PASS while Check 21 is red (gate independence)"
# Check 22 reads en_US + Utilities + SyncPlayTask only - a ja_JP mirror hole
# must NOT fire it (proves the two locale gates stay independent). Same for
# Check 23: its catalog face is en_US purity only, sibling holes are CHECK21
# territory.
# Era pin: CHECK22's PASS echo carries the census count; "all 19" rotated to
# "all 20" with the W-min92 queue_limit_exceeded promotion (the digit IS the
# assertion — bare "all" would not prove the content pin ran at the new size).
sed -n '/=== Check 22:/,$p' <<<"$RED21_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while Check 21 is red (gate independence)"
sed -n '/=== Check 23:/,$p' <<<"$RED21_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 21 is red (gate independence)"
# CHECK24's token set is brace-driven; a non-token key (common.ok) removed
# from a mirror must not entangle the token law gate either.
sed -n '/=== Check 24:/,$p' <<<"$RED21_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 21 is red (gate independence)"

# --- Check 22 red proof (twin-flip split, leg 1): a rogue 21st code is pushed
# into the wire census without evidence or reservation (census is 20 since the
# W-min92 queue_limit_exceeded promotion). The content pin must
# fire - the pre-split bare count pin could not distinguish renamed/re-admitted
# members from honest ones, which is exactly why the law was redesigned.
# CHECK21 (catalogs untouched) and CHECK23's local-family legs stay green. ----
RED22_ROOT="$TEST_ROOT/red22"
mkdir -p "$RED22_ROOT"
cp -a "$TEST_ROOT/repo" "$RED22_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED22_ROOT/phlix-server"
python3 - "$RED22_ROOT/repo/source/lib/Utilities.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
needle = 'codes.push("syncplay.group_full")'
assert text.count(needle) == 1, "planted-red anchor missing from SyncPlayKnownErrorCodes()"
text = text.replace(
    needle,
    needle + '\n    codes.push("syncplay.rogue_unreserved_code")',
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED22_OUT=$(bash "$RED22_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED22_RC=$?
set -e
[ "$RED22_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a rogue code enters the wire census (got 0)"
assert_contains "CHECK22" "$RED22_OUT"
assert_contains "syncplay.rogue_unreserved_code" "$RED22_OUT"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED22_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 22 is red (gate independence)"

# --- Check 22 red proof (twin-flip split, leg 2, post-flip): the DECLARED-
# reserved ledger is EMPTY since the 9b2394ee flip promoted its trio. A rogue
# declaration must still fire the content pin - the arm guards the NEXT
# flip-pending code, not just the last one. CHECK21 stays green. -------------
RED22B_ROOT="$TEST_ROOT/red22b"
mkdir -p "$RED22B_ROOT"
cp -a "$TEST_ROOT/repo" "$RED22B_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED22B_ROOT/phlix-server"
python3 - "$RED22B_ROOT/repo/source/lib/Utilities.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
needle = ('function SyncPlayReservedErrorCodes() as Object\n'
          '    codes = []\n    return codes')
assert text.count(needle) == 1, "planted-red anchor missing from empty SyncPlayReservedErrorCodes()"
text = text.replace(
    needle,
    needle.replace('    return codes',
                   '    codes.push("syncplay.rogue_pending_twin")\n    return codes'),
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED22B_OUT=$(bash "$RED22B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED22B_RC=$?
set -e
[ "$RED22B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the reserved census drifts (got 0)"
assert_contains "CHECK22" "$RED22B_OUT"
assert_contains "reserved census drifted" "$RED22B_OUT"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED22B_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while the reserved-census leg of Check 22 is red"

# --- Check 22 red proof (twin-flip split, leg 3, post-flip): collapsing the
# now-empty SyncPlayReservedErrorCodes() away must fire the existence leg -
# the declaration-before-census-entry gate is only alive while the function
# is required. CHECK21 stays green. ------------------------------------------
RED22C_ROOT="$TEST_ROOT/red22c"
mkdir -p "$RED22C_ROOT"
cp -a "$TEST_ROOT/repo" "$RED22C_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED22C_ROOT/phlix-server"
python3 - "$RED22C_ROOT/repo/source/lib/Utilities.brs" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
new, n = re.subn(
    r"function SyncPlayReservedErrorCodes\(\) as Object.*?end function\n",
    "", text, count=1, flags=re.S)
assert n == 1, "planted-red anchor missing: SyncPlayReservedErrorCodes() block"
with open(path, "w", encoding="utf-8") as f:
    f.write(new)
PYEOF
set +e
RED22C_OUT=$(bash "$RED22C_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED22C_RC=$?
set -e
[ "$RED22C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the reserved-declaration function is removed (got 0)"
assert_contains "CHECK22" "$RED22C_OUT"
assert_contains "SyncPlayReservedErrorCodes() not found" "$RED22C_OUT"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED22C_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while the reserved-existence leg of Check 22 is red"

# --- Check 23 red proof (twin-flip split, orphan leg): an unaccounted key
# squats in the en_US errors registry. Section purity (CHECK23(d)) fires while
# CHECK22 stays green (census and resolution untouched); CHECK21 may co-fire
# (mirror holes are its own leg), so only CHECK22 independence is asserted. --
RED23B_ROOT="$TEST_ROOT/red23b"
mkdir -p "$RED23B_ROOT"
cp -a "$TEST_ROOT/repo" "$RED23B_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED23B_ROOT/phlix-server"
python3 - "$RED23B_ROOT/repo/locale/en_US/strings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
assert "orphan_squatter" not in doc["errors"]
doc["errors"]["orphan_squatter"] = "Unaccounted registry entry."
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
PYEOF
set +e
RED23B_OUT=$(bash "$RED23B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED23B_RC=$?
set -e
[ "$RED23B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an orphan key squats in the errors registry (got 0)"
assert_contains "CHECK23" "$RED23B_OUT"
assert_contains "orphan_squatter" "$RED23B_OUT"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED23B_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while the orphan-key leg of Check 23 is red (gate independence)"

# --- Check 23 red proof on an independent scratch copy: a task call site
# regressed to a raw display literal (the exact defect class the local family
# law forbids). CHECK21/CHECK22 must stay green in that run. ---------------
RED23_ROOT="$TEST_ROOT/red23"
mkdir -p "$RED23_ROOT"
cp -a "$TEST_ROOT/repo" "$RED23_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED23_ROOT/phlix-server"
python3 - "$RED23_ROOT/repo/components/SyncPlayTask.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
needle = 'EmitError("local.connect_failed")'
assert text.count(needle) == 1, "planted-red anchor missing from SyncPlayTask.brs"
text = text.replace(needle, 'EmitError("Connect failed")')
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED23_OUT=$(bash "$RED23_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED23_RC=$?
set -e
[ "$RED23_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an EmitError carries a raw literal (got 0)"
assert_contains "CHECK23" "$RED23_OUT"
assert_contains "Connect failed" "$RED23_OUT"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED23_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 23 is red (gate independence)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED23_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while Check 23 is red (gate independence)"

# --- Check 24 red proof on an independent scratch copy: a token-bearing
# catalog key regressed to the historical raw-concat shape (the exact defect
# class of this lane). CHECK20/21/22/23 must stay green in that run. --------
RED24_ROOT="$TEST_ROOT/red24"
mkdir -p "$RED24_ROOT"
cp -a "$TEST_ROOT/repo" "$RED24_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED24_ROOT/phlix-server"
python3 - "$RED24_ROOT/repo/components/SettingsScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
needle = 'm.statusLabel.text = TranslateWithParams("settings_status_logged_in_as", { email: userEmail })'
assert text.count(needle) == 1, "planted-red anchor missing from SettingsScene.brs"
# Regression to the pre-fix shape: raw Translate + append renders literal
# braces and freezes the token position.
text = text.replace(
    needle,
    'm.statusLabel.text = Translate("settings_status_logged_in_as") + userEmail',
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED24_OUT=$(bash "$RED24_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED24_RC=$?
set -e
[ "$RED24_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a token key is concatenated raw (got 0)"
assert_contains "CHECK24" "$RED24_OUT"
assert_contains "settings_status_logged_in_as" "$RED24_OUT"
grep -qE "SettingsScene\.brs:[0-9]+ - CHECK24" <<<"$RED24_OUT" ||
	fail "CHECK24 red must name the offending file:line (got: $RED24_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED24_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 24 is red (gate independence)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED24_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 24 is red (gate independence)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED24_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while Check 24 is red (gate independence)"
sed -n '/=== Check 23:/,/=== Check 24:/p' <<<"$RED24_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 24 is red (gate independence)"

# --- Check 19 exempt-anchoring red proof on an independent scratch copy: the
# unanchored-substring defect class (review #91 LOW). A user-facing literal
# containing prose " for " must NOT exempt its own line any more (the old
# \bfor\s+ EXEMPT regex let it escape silently); a genuine BrightScript
# for-header line carrying a string must STAY exempt (grammar-anchored
# `for <var> =` / `for each <var> in` forms survive masking). Exactly one
# CHECK19 violation may fire, and CHECK20-24 stay green (gate independence). --
RED19_ROOT="$TEST_ROOT/red19"
mkdir -p "$RED19_ROOT"
cp -a "$TEST_ROOT/repo" "$RED19_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED19_ROOT/phlix-server"
python3 - "$RED19_ROOT/repo/components/SettingsScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check19Plants()\n"
    '    m.text = "Pay $5 for entry"\n'
    '    for i = 0 to 2 : m.statusLabel.text = "row count" : next\n'
    "end sub\n"
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
RED19_OUT=$(bash "$RED19_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED19_RC=$?
set -e
[ "$RED19_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a UI string escapes CHECK19 via prose ' for ' (got 0)"
sed -n '/=== Check 19:/,/=== Check 20:/p' <<<"$RED19_OUT" | grep -qF 'Pay $5 for entry' ||
	fail "CHECK19 red must name the offending literal (got: $RED19_OUT)"
if sed -n '/=== Check 19:/,/=== Check 20:/p' <<<"$RED19_OUT" | grep -q 'row count'; then
	fail "a real 'for i = 0 to 2' header line must stay exempt under the anchored grammar"
fi
N19=$(sed -n '/=== Check 19:/,/=== Check 20:/p' <<<"$RED19_OUT" | grep -c "CHECK19:" || true)
[ "$N19" -eq 1 ] || fail "exactly one CHECK19 violation expected (prose-'for' plant fires, loop plant stays exempt); got $N19"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED19_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED19_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED19_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 23:/,/=== Check 24:/p' <<<"$RED19_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 24:/,$p' <<<"$RED19_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 19 is red (gate independence)"

# --- Check 19 raw-argument escape red proof (RT-095, REVIEW-w15L9roku.md
# R-C): the legacy ShowErrorDialog arm only indicted lines carrying >=3
# string literals, so a dialog call with ONE Translate'd title and ONE raw
# message arg - the exact shape that shipped as 'No chapters available for
# this content' through two review eras - waved past it. The pre-exemption
# raw-argument law must convict that escape on its own line, name the
# literal, fire exactly once, and keep the sibling copy checks green.
RED19E_ROOT="$TEST_ROOT/red19e"
mkdir -p "$RED19E_ROOT"
cp -a "$TEST_ROOT/repo" "$RED19E_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED19E_ROOT/phlix-server"
python3 - "$RED19E_ROOT/repo/components/SettingsScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check19EscapePlant()\n"
    '    ShowErrorDialog(m.top, Translate("common_notice"), "escape probe literal")\n'
    "end sub\n"
)
assert "escape probe literal" not in text, "CHECK19 escape plant: probe string already on the surface"
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
RED19E_OUT=$(bash "$RED19E_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED19E_RC=$?
set -e
[ "$RED19E_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a ShowErrorDialog raw arg hides beside a Translate sibling (got 0 - CHECK19 raw-argument law is toothless)"
sed -n '/=== Check 19:/,/=== Check 20:/p' <<<"$RED19E_OUT" | grep -qF 'CHECK19: hardcoded user-facing string: escape probe literal' ||
	fail "CHECK19 escape leg must name the raw ShowErrorDialog argument (got: $RED19E_OUT)"
NE19=$(sed -n '/=== Check 19:/,/=== Check 20:/p' <<<"$RED19E_OUT" | grep -c "CHECK19:" || true)
[ "$NE19" -eq 1 ] || fail "exactly one CHECK19 violation expected for the escape plant (the Translate sibling must stay exempt); got $NE19"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED19E_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 19 is red (gate independence, escape leg)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED19E_OUT" | grep -q "CHECK25: chrome literals" ||
	fail "Check 25 must stay PASS while Check 19 is red (gate independence, escape leg)"

# --- Check 25 red proof on an independent scratch copy: the XML-chrome
# invisibility defect class (i18n lane 2026-09-25). A raw literal added as a
# text= attribute in component markup touches no .brs string, so CHECKs 19-24
# stay silent on it - that invisibility was the gap CHECK25 closes. A planted
# un-catalogued label must fire CHECK25 red (naming file:line + the literal)
# while CHECKs 20-24 stay green (gate independence). --
RED25_ROOT="$TEST_ROOT/red25"
mkdir -p "$RED25_ROOT"
cp -a "$TEST_ROOT/repo" "$RED25_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED25_ROOT/phlix-server"
python3 - "$RED25_ROOT/repo/components/HomeScene.xml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
marker = '    <Label id="loadingLabel"'
assert marker in text, "loadingLabel anchor not found in HomeScene.xml"
plant = '<Label id="plantedRawLabel" text="Planted raw chrome string" />\n    '
text = text.replace(marker, plant + '<Label id="loadingLabel"', 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED25_OUT=$(bash "$RED25_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED25_RC=$?
set -e
[ "$RED25_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when XML chrome literal escapes the translate net (got 0)"
sed -n '/=== Check 25:/,$p' <<<"$RED25_OUT" | grep -qF 'Planted raw chrome string' ||
	fail "CHECK25 red must name the planted literal (got: $RED25_OUT)"
sed -n '/=== Check 25:/,$p' <<<"$RED25_OUT" | grep -qF 'components/HomeScene.xml:' ||
	fail "CHECK25 red must name the planted file"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED25_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 25 is red (gate independence)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED25_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 25 is red (gate independence)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED25_OUT" | grep -q "CHECK22: all" ||
	fail "Check 22 must stay PASS while Check 25 is red (gate independence)"
sed -n '/=== Check 23:/,/=== Check 24:/p' <<<"$RED25_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 25 is red (gate independence)"
sed -n '/=== Check 24:/,/=== Check 25:/p' <<<"$RED25_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 25 is red (gate independence)"

# --- Check 26 red proof on an independent scratch copy: the envelope-leak
# defect class (2c119f9 follow-through, 2026-09-29). The systemic bug was code
# reading server payload keys directly off the {status,ok,data,error} transport
# envelope (resp.libraries-style) - invisible to every pre-existing gate. A
# planted leak line must fire CHECK26 red naming file:line while CHECKs 20-25
# stay green (gate independence). --
RED26_ROOT="$TEST_ROOT/red26"
mkdir -p "$RED26_ROOT"
cp -a "$TEST_ROOT/repo" "$RED26_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED26_ROOT/phlix-server"
python3 - "$RED26_ROOT/repo/components/DetailScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check26PlantedLeak()\n"
    "    planted = resp.libraries\n"
    "end sub\n"
)
text = text + plant
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED26_OUT=$(bash "$RED26_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED26_RC=$?
set -e
[ "$RED26_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a server payload key is read off an envelope-level variable (got 0)"
sed -n '/=== Check 26:/,$p' <<<"$RED26_OUT" | grep -qF 'components/DetailScene.brs' ||
	fail "CHECK26 red must name the planted file (got: $RED26_OUT)"
sed -n '/=== Check 26:/,$p' <<<"$RED26_OUT" | grep -qF 'resp.libraries' ||
	fail "CHECK26 red must name the planted read (got: $RED26_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED26_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 26 is red (gate independence)"
sed -n '/=== Check 24:/,/=== Check 25:/p' <<<"$RED26_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 26 is red (gate independence)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED26_OUT" | grep -q "CHECK25: all" ||
	fail "Check 25 must stay PASS while Check 26 is red (gate independence)"

# --- Check 20 red proof + restore (dotted-key blind spot, df4e7a2 review
# follow-up): the dotless key class let Translate("player.playback_error") ship
# invisible — dotted literals can never resolve against the flat underscore
# table and render raw keys on device. The tightened regex must catch the plant,
# name file + dotted key + underscore suggestion, keep CHECKs 21-26 green, and
# the run must return to exit 0 once the plant is removed (falsifiability). ----
RED20_ROOT="$TEST_ROOT/red20"
mkdir -p "$RED20_ROOT"
cp -a "$TEST_ROOT/repo" "$RED20_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED20_ROOT/phlix-server"
python3 - "$RED20_ROOT/repo/components/DetailScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check20PlantedDottedKey()\n"
    '    planted = Translate("player.playback_error")\n'
    "end sub\n"
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
RED20_OUT=$(bash "$RED20_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED20_RC=$?
set -e
[ "$RED20_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a dotted Translate literal is planted (got 0)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED20_OUT" | grep -qF 'components/DetailScene.brs' ||
	fail "CHECK20 red must name the planted file (got: $RED20_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED20_OUT" | grep -qF "'player.playback_error'" ||
	fail "CHECK20 red must name the planted dotted key (got: $RED20_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED20_OUT" | grep -qF 'player_playback_error' ||
	fail "CHECK20 dotted-key red must suggest the underscore form (got: $RED20_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED20_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 20 is red (gate independence)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED20_OUT" | grep -q "CHECK22: all 20" ||
	fail "Check 22 must stay PASS while Check 20 is red (gate independence)"
sed -n '/=== Check 23:/,/=== Check 24:/p' <<<"$RED20_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 20 is red (gate independence)"
sed -n '/=== Check 24:/,/=== Check 25:/p' <<<"$RED20_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 20 is red (gate independence)"
sed -n '/=== Check 25:/,$p' <<<"$RED20_OUT" | grep -q "CHECK25: all" ||
	fail "Check 25 must stay PASS while Check 20 is red (gate independence)"
sed -n '/=== Check 26:/,$p' <<<"$RED20_OUT" | grep -q "CHECK26: all" ||
	fail "Check 26 must stay PASS while Check 20 is red (gate independence)"
# Remove → green: same scratch tree, plant stripped, full run exits 0.
python3 - "$RED20_ROOT/repo/components/DetailScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
marker = "\nsub Check20PlantedDottedKey()"
assert marker in text, "restore anchor missing — plant not written as expected"
text = text[:text.index(marker)]
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
GREEN20_OUT=$(bash "$RED20_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN20_RC=$?
set -e
[ "$GREEN20_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the dotted-key plant is removed (got $GREEN20_RC)"
assert_contains "CHECK20: all" "$GREEN20_OUT"

# --- Check 39 red proof + restore on an independent scratch copy: the
# rsg_version fiction class (M-ROKU-07). The channel shipped rsg_version=7.0
# for its whole life — outside Roku's documented 1.0/1.1/1.2/1.3 observer
# callback value space — and no vendored tool could flag it (brighterscript
# treats unknown-but-semver values as valid). Re-planting 7.0 AND stripping
# the rationale comment must fire CHECK39 R2+R4 red while the sibling manifest
# readers (CHECK18 version drift, CHECK38 design plane) stay green (gate
# independence); restoring the cured manifest must return exit 0
# (falsifiability, house planted-red tradition). --
RED39_ROOT="$TEST_ROOT/red39"
mkdir -p "$RED39_ROOT"
cp -a "$TEST_ROOT/repo" "$RED39_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED39_ROOT/phlix-server"
python3 - "$RED39_ROOT/repo/manifest" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
start = text.index("' M-ROKU-07")
end = text.index("\n", text.index("rsg_version=")) + 1
with open(path, "w", encoding="utf-8") as f:
    f.write(text[:start] + "rsg_version=7.0\n" + text[end:])
PYEOF
set +e
RED39_OUT=$(bash "$RED39_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED39_RC=$?
set -e
[ "$RED39_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the manifest declares rsg_version=7.0 (got 0)"
sed -n '/=== Check 39:/,$p' <<<"$RED39_OUT" | grep -qF "rsg_version='7.0' is outside" ||
	fail "CHECK39 red must name the planted illegal value (got: $RED39_OUT)"
sed -n '/=== Check 39:/,$p' <<<"$RED39_OUT" | grep -qF "CHECK39 R4" ||
	fail "CHECK39 red must also fire the lost-rationale leg when the comment is stripped"
sed -n '/=== Check 18:/,/=== Check 19:/p' <<<"$RED39_OUT" | grep -qF 'PASS — package.json=' ||
	fail "Check 18 (the other manifest reader) must stay PASS while Check 39 is red (gate independence)"
sed -n '/=== Check 38:/,$p' <<<"$RED39_OUT" | grep -qF "CHECK38: ui_resolutions=hd agrees" ||
	fail "Check 38 must stay PASS while Check 39 is red (gate independence)"
cp "$FAKE_REPO/manifest" "$RED39_ROOT/repo/manifest"
set +e
GREEN39_OUT=$(bash "$RED39_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN39_RC=$?
set -e
[ "$GREEN39_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the cured rsg_version=1.3 manifest is restored (got $GREEN39_RC)"
assert_contains "CHECK39: rsg_version=1.3 inside" "$GREEN39_OUT"

# --- M-ROKU-08 aggregation red proof + restore (the print-only-gate class):
# checks 1-10 shared the VIOLATIONS accumulator that checks 8/9/10/11 RE-ZEROED
# at their headers, so a violation anywhere before Check 11 printed yet could
# never gate the exit (measured from red at b8dd771: planted CHECK1 hit printed,
# gate exited 0; planted CHECK39 hit after the last reset exited 1). The cure
# kills the four re-zeros — one sink, exit $((VIOLATIONS)) sees every leg. The
# plant rides the EARLIEST leg (CHECK1, maximum wipe distance): re-adding ANY
# re-zero in the cured range (old :110/:124/:142/:153) redds this leg
# (mutation-proven at fix time: one re-added reset -> plant printed, exit 0). --
AGG_ROOT="$TEST_ROOT/agg-plant"
mkdir -p "$AGG_ROOT"
cp -a "$TEST_ROOT/repo" "$AGG_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$AGG_ROOT/phlix-server"
python3 - "$AGG_ROOT/repo/source/lib/AppContext.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub AggPlantedCheck1()\n"
    '    planted = Storage.get("aggregation_probe")\n'
    "end sub\n"
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
AGG_OUT=$(bash "$AGG_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
AGG_RC=$?
set -e
[ "$AGG_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a CHECK1 violation is planted in leg 1 (got 0 — the aggregation re-zero bug is back)"
sed -n '/=== Check 1:/,/=== Check 2:/p' <<<"$AGG_OUT" | grep -qF 'CHECK1: Storage.factory used directly' ||
	fail "the aggregation red leg must see the planted CHECK1 violation printed (got: $AGG_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$AGG_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 1 is red (gate independence)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$AGG_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 1 is red (gate independence)"
sed -n '/=== Check 39:/,$p' <<<"$AGG_OUT" | grep -q "CHECK39: rsg_version=1.3 inside" ||
	fail "Check 39 must stay PASS while Check 1 is red (gate independence)"
# Remove → green: same scratch tree, plant stripped, full run exits 0
# (falsifiability, house planted-red tradition).
python3 - "$AGG_ROOT/repo/source/lib/AppContext.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
marker = "\nsub AggPlantedCheck1()"
assert marker in text, "restore anchor missing — plant not written as expected"
text = text[:text.index(marker)]
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
GREENAGG_OUT=$(bash "$AGG_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREENAGG_RC=$?
set -e
[ "$GREENAGG_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the aggregation plant is removed (got $GREENAGG_RC)"
assert_contains "CHECK20: all" "$GREENAGG_OUT"

# --- Check 40 red proof + restore on an independent scratch copy: the
# designed-but-dead versioning class (M-ROKU-09). The version script carried
# get_git_count/get_ci_build_version that no main() case dispatched and no
# caller consumed, plus a usage header advertising a no-arg "manifest format"
# mode that crashed under set -u. Re-planting the class (an unreachable
# function + a documented-but-never-dispatched --ghost flag) must fire CHECK40
# R1 and R40 R2 naming both plants, while the sibling gates CHECK18 (version
# drift) and CHECK39 (rsg_version) stay green (gate independence); restoring
# the cured script must return exit 0 (falsifiability, house planted-red
# tradition). The R3 behavior probes (no-arg works, unknown flag fails loud)
# were mutation-proven at fix time against the parent script; see the
# M-ROKU-09 fixlog. --
RED40_ROOT="$TEST_ROOT/red40"
mkdir -p "$RED40_ROOT"
cp -a "$TEST_ROOT/repo" "$RED40_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED40_ROOT/phlix-server"
python3 - "$RED40_ROOT/repo/scripts/derive-version.sh" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\n#   derive-version.sh --ghost — documented but never dispatched (CHECK40 R2 plant)\n"
    "get_never_called() {\n    echo ghost\n}\n"
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
RED40_OUT=$(bash "$RED40_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED40_RC=$?
set -e
[ "$RED40_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an unreachable function + ghost flag are planted in derive-version.sh (got 0 — the dead-design guard is toothless)"
sed -n '/=== Check 40:/,$p' <<<"$RED40_OUT" | grep -qF "get_never_called()" ||
	fail "CHECK40 red must name the planted unreachable function (got: $RED40_OUT)"
sed -n '/=== Check 40:/,$p' <<<"$RED40_OUT" | grep -qF "CHECK40 R2" ||
	fail "CHECK40 red must also fire the usage/dispatch bijection leg on the planted --ghost flag"
sed -n '/=== Check 18:/,/=== Check 19:/p' <<<"$RED40_OUT" | grep -qF 'PASS — package.json=' ||
	fail "Check 18 (the other version reader) must stay PASS while Check 40 is red (gate independence)"
sed -n '/=== Check 39:/,$p' <<<"$RED40_OUT" | grep -qF "CHECK39: rsg_version=1.3 inside" ||
	fail "Check 39 must stay PASS while Check 40 is red (gate independence)"
cp "$FAKE_REPO/scripts/derive-version.sh" "$RED40_ROOT/repo/scripts/derive-version.sh"
set +e
GREEN40_OUT=$(bash "$RED40_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN40_RC=$?
set -e
[ "$GREEN40_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the cured derive-version.sh is restored (got $GREEN40_RC)"
assert_contains "CHECK40: derive-version.sh fully reachable" "$GREEN40_OUT"

# --- Check 41 red proof + restore on an independent scratch copy: the
# signing-claim dishonesty class (M-ROKU-10). The wrapper once claimed a
# password env var nothing read, fell back to renaming the unsigned zip into
# a "signed" .pkg, stamped versions from a hardcoded 1.0.1 make never
# exported, and CI carried a signer-less package-signed stub. Re-planting all
# four must fire CHECK41 R1+R2+R3+R4 naming each plant, while CHECK18 (other
# version reader) and CHECK40 (version-discipline/vehicle) stay green (gate
# independence); restoring the cured files returns exit 0 (falsifiability).
# The M-ROKU-29 rider joins the family: a self-signed-sideload echo in the
# script, sagas.xml + sideload-testing lines in publishing.md, and a line-
# wrapped only-sideloads claim in README must fire CHECK41 R5 naming each.
RED41_ROOT="$TEST_ROOT/red41"
mkdir -p "$RED41_ROOT"
cp -a "$TEST_ROOT/repo" "$RED41_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED41_ROOT/phlix-server"
python3 - "$RED41_ROOT/repo/scripts/package-signed.sh" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\n#   - ROKU_DEV_PASSWORD environment variable set (CHECK41 R1 plant)\n"
    'PKG_VERSION="${PKG_VERSION:-1.0.1}"  # CHECK41 R3 plant: hardcoded default\n'
    'cp "${PKG_NAME}.zip" "$SIGNED_PKG"  # CHECK41 R2 plant: rename-fake-pkg\n'
    'echo "  CHECK41 R5 plant: the dev-signed pkg can be sideloaded for testing"\n'
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
python3 - "$RED41_ROOT/repo/docs/publishing.md" "$RED41_ROOT/repo/README.md" <<'PYEOF'
import sys
# CHECK41 R5 plants (M-ROKU-29): the fabricated sagas.xml troubleshooting
# item + the self-signed sideload-testing claim re-enter the publishing doc;
# the README gets the line-wrapped "self-signed cert only sideloads" claim,
# proving the leg is wrap-tolerant (whitespace-joined needles).
pub, rdme = sys.argv[1], sys.argv[2]
with open(pub, "a", encoding="utf-8") as f:
    f.write(
        "\n- `sagas.xml` or required assets missing (CHECK41 R5 plant: fabricated artifact)\n"
        "- CHECK41 R5 plant: dev-signed packages are for sideload testing only\n"
    )
with open(rdme, "a", encoding="utf-8") as f:
    f.write("\nCHECK41 R5 plant: a self-signed cert\n  only sideloads.\n")
PYEOF
python3 - "$RED41_ROOT/repo/.github/workflows/package.yml" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\n  package-signed-stub:\n"
    "    name: CHECK41 R4 plant (signer-less)\n"
    "    needs: package\n"
    "    runs-on: ubuntu-26.04\n"
    "    steps:\n"
    "      - name: Sign\n"
    "        run: make package-signed\n"
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
PYEOF
set +e
RED41_OUT=$(bash "$RED41_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED41_RC=$?
set -e
[ "$RED41_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the M-ROKU-10 class is re-planted (got 0 — the signing-honesty guard is toothless)"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "CHECK41 R1" ||
	fail "CHECK41 red must fire the phantom-secret R1 leg on the planted ROKU_DEV_PASSWORD claim"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "CHECK41 R2" ||
	fail "CHECK41 red must fire the rename-into-.pkg R2 leg on the planted cp fallback"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "CHECK41 R3" ||
	fail "CHECK41 red must fire the version-truth R3 leg on the planted hardcoded default"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "CHECK41 R4" ||
	fail "CHECK41 red must fire the CI-signer R4 leg on the planted signer-less package-signed stub"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "CHECK41 R5" ||
	fail "CHECK41 red must fire the smoke-truth R5 leg on the planted self-signed-sideload fiction + sagas.xml claim (M-ROKU-29)"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "scripts/package-signed.sh - CHECK41 R5" ||
	fail "CHECK41 R5 must name scripts/package-signed.sh for the planted sideloaded-for-testing echo"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "docs/publishing.md - CHECK41 R5" ||
	fail "CHECK41 R5 must name docs/publishing.md for the planted sagas.xml + sideload-testing lines"
sed -n '/=== Check 41:/,$p' <<<"$RED41_OUT" | grep -qF "README.md - CHECK41 R5" ||
	fail "CHECK41 R5 must name README.md for the planted wrap-across-lines only-sideloads claim (wrap tolerance proof)"
sed -n '/=== Check 40:/,/=== Check 41:/p' <<<"$RED41_OUT" | grep -qF "CHECK40: derive-version.sh fully reachable" ||
	fail "Check 40 must stay PASS while Check 41 is red (gate independence)"
sed -n '/=== Check 18:/,/=== Check 19:/p' <<<"$RED41_OUT" | grep -qF 'PASS — package.json=' ||
	fail "Check 18 (the other version reader) must stay PASS while Check 41 is red (gate independence)"
cp "$FAKE_REPO/scripts/package-signed.sh" "$RED41_ROOT/repo/scripts/package-signed.sh"
cp "$FAKE_REPO/.github/workflows/package.yml" "$RED41_ROOT/repo/.github/workflows/package.yml"
cp "$FAKE_REPO/docs/publishing.md" "$RED41_ROOT/repo/docs/publishing.md"
cp "$FAKE_REPO/README.md" "$RED41_ROOT/repo/README.md"
set +e
GREEN41_OUT=$(bash "$RED41_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN41_RC=$?
set -e
[ "$GREEN41_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the cured signing wrapper + workflow are restored (got $GREEN41_RC)"
assert_contains "CHECK41: no phantom password-secret claim" "$GREEN41_OUT"

# --- Check 42 red proof + restore on an independent scratch copy: the
# no-retail-user-visibility class (M-ROKU-11). The channel once sent no
# version anywhere, Settings -> About rendered a hardcoded "1.0.1" into a
# 40px single-line Label that could not show the block anyway, and the only
# crash story was a dev-mode telnet. Re-planting three members of that class
# must fire CHECK42 R1 (a send site that stopped carrying the header), R2 (a
# version literal back in code) and R6 (multi-line block back on the
# non-wrapping statusLabel), while CHECK41 (the sibling honesty gate) and
# CHECK20 (the catalog reader over the same SettingsScene file) stay green
# (gate independence); restoring the cured files returns exit 0
# (falsifiability, house planted-red tradition).
RED42_ROOT="$TEST_ROOT/red42"
mkdir -p "$RED42_ROOT"
cp -a "$TEST_ROOT/repo" "$RED42_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED42_ROOT/phlix-server"
python3 - "$RED42_ROOT/repo/source/lib/ApiClient.brs" "$RED42_ROOT/repo/components/SettingsScene.brs" <<'PYEOF'
import sys
ac_path, scene_path = sys.argv[1], sys.argv[2]

with open(ac_path, encoding="utf-8") as f:
    ac = f.read()
plant_header = '            http.AddHeader("X-Phlix-Client-Version", m.clientVersion)\n'
head, sep, rest = ac.rpartition(plant_header)
assert sep, "CHECK42 plant: no send-site X-Phlix-Client-Version header line found (shape drift)"
with open(ac_path, "w", encoding="utf-8") as f:
    f.write(head + rest)          # R1 plant: strip the LAST send-site header

with open(scene_path, encoding="utf-8") as f:
    scene = f.read()
assert '    version = GetChannelVersion()\n' in scene, "CHECK42 plant: About version read missing"
scene = scene.replace('    version = GetChannelVersion()\n',
                      '    version = "1.0.1"  # CHECK42 R2 plant: the About lie\n', 1)
assert 'm.detailLabel.text = info' in scene, "CHECK42 plant: detailLabel target missing"
scene = scene.replace('m.detailLabel.text = info', 'm.statusLabel.text = info', 1)  # R6 plant
with open(scene_path, "w", encoding="utf-8") as f:
    f.write(scene)
PYEOF
set +e
RED42_OUT=$(bash "$RED42_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED42_RC=$?
set -e
[ "$RED42_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the M-ROKU-11 class is re-planted (got 0 — the channel-identity/diagnostics guard is toothless)"
sed -n '/=== Check 42:/,$p' <<<"$RED42_OUT" | grep -qF "CHECK42 R1" ||
	fail "CHECK42 red must fire the send-site R1 leg on the stripped X-Phlix-Client-Version header"
sed -n '/=== Check 42:/,$p' <<<"$RED42_OUT" | grep -qF "CHECK42 R2" ||
	fail "CHECK42 red must fire the no-version-literal R2 leg on the planted \"1.0.1\""
sed -n '/=== Check 42:/,$p' <<<"$RED42_OUT" | grep -qF "CHECK42 R6" ||
	fail "CHECK42 red must fire the readable-surface R6 leg on the statusLabel retarget"
sed -n '/=== Check 41:/,/=== Check 42:/p' <<<"$RED42_OUT" | grep -qF "CHECK41: no phantom password-secret claim" ||
	fail "Check 41 must stay PASS while Check 42 is red (gate independence)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED42_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 (the other SettingsScene reader) must stay PASS while Check 42 is red (gate independence)"
cp "$FAKE_REPO/source/lib/ApiClient.brs" "$RED42_ROOT/repo/source/lib/ApiClient.brs"
cp "$FAKE_REPO/components/SettingsScene.brs" "$RED42_ROOT/repo/components/SettingsScene.brs"
set +e
GREEN42_OUT=$(bash "$RED42_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN42_RC=$?
set -e
[ "$GREEN42_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the cured ApiClient/SettingsScene are restored (got $GREEN42_RC)"
assert_contains "CHECK42: all three ApiClient send sites" "$GREEN42_OUT"
# --- Check 44 red proof on an independent scratch copy: the dial stamp
# stripped from the relay mint must fire CHECK44 R1 naming HubCommandTask,
# while CHECK42 (the REST send-site leg) stays PASS — gate independence.
RED44_ROOT="$TEST_ROOT/red44"
mkdir -p "$RED44_ROOT"
cp -a "$TEST_ROOT/repo" "$RED44_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED44_ROOT/phlix-server"
python3 - "$RED44_ROOT/repo/components/HubCommandTask.brs" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'transfer.AddHeader("X-Phlix-Client-Version", ProtocolChannelVersion())'
assert text.count(needle) == 1, "CHECK44 plant: mint stamp line missing (shape drift)"
text = text.replace(needle + "\n", "", 1)
assert 'transfer.AddHeader("X-Phlix-Client-Version"' not in text, "CHECK44 plant: strip failed"
open(path, "w").write(text)
PYEOF
set +e
RED44_OUT=$(bash "$RED44_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED44_RC=$?
set -e
[ "$RED44_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the M-ROKU-11 dial class is re-planted (got 0 — the CHECK44 guard is toothless)"
sed -n '/=== Check 44:/,$p' <<<"$RED44_OUT" | grep -qF "CHECK44 R1" ||
	fail "CHECK44 red must fire the relay-mint R1 leg on the stripped AddHeader"
sed -n '/=== Check 44:/,$p' <<<"$RED44_OUT" | grep -qF "HubCommandTask" ||
	fail "CHECK44 red must name components/HubCommandTask.brs"
sed -n '/=== Check 42:/,/=== Check 44:/p' <<<"$RED44_OUT" | grep -qF "CHECK42: all three ApiClient send sites" ||
	fail "Check 42 must stay PASS while Check 44 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$RED44_ROOT/repo/components/HubCommandTask.brs"
set +e
GREEN44_OUT=$(bash "$RED44_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN44_RC=$?
set -e
[ "$GREEN44_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the restored HubCommandTask dial (got $GREEN44_RC)"

# --- Check 43 red proof + restore (M-ROKU-12, review roku__exploiter M1): the
# hostile-server class — {"error":123} meeting `<> ""`, a string op, a
# concat, or an `as String` sink — crashed the render thread. The plant
# reproduces ALL FIVE arms on DetailScene (the scene most fed by wire text):
# the original three (raw lift / literal compare / lcase) plus the two the
# r1/r2 reviews proved invisible to the first gate generation (concat-into-
# string and the bare-argument typed sink — r2's own plant ran green at the
# pre-r3 tip) — plus the two R-ROKU-04 covers (an unrelated `"String"`
# literal silencing the arms on a raw-compare line, and the `<> "String"`
# compare the verbatim mask-keep hid from arm (a); both ran GREEN under the
# coarse token, measured at 349933e before the tightening landed). Each
# must be named, sibling gates (CHECK26 envelope law,
# CHECK41 signing honesty) stay green, and the restore must return the whole
# script to exit 0 (falsifiability).
RED43_ROOT="$TEST_ROOT/red43"
mkdir -p "$RED43_ROOT"
cp -a "$TEST_ROOT/repo" "$RED43_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED43_ROOT/phlix-server"
python3 - "$RED43_ROOT/repo/components/DetailScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check43PlantedWireLeak()\n"
    "    lifted = resp.error\n"
    "    if resp.data.message <> \"\" then\n"
    "    end if\n"
    "    detail = lcase(env.message)\n"
    "    x = \"Server error: \" + resp.error\n"
    "    if IsTransportReason(resp.error) then\n"
    "    end if\n"
    "    if Type(kind) = \"String\" and resp04cover.error <> \"\" then\n"
    "    end if\n"
    "    holeText = resp04hole.message <> \"String\"\n"
    "end sub\n"
)
text = text + plant
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
RED43_OUT=$(bash "$RED43_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED43_RC=$?
set -e
[ "$RED43_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a raw wire .error read is planted (got 0)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'components/DetailScene.brs' ||
	fail "CHECK43 red must name the planted file (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'resp.error' ||
	fail "CHECK43 red must name the planted raw read (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'raw wire .error/.message read/return' ||
	fail "CHECK43 red must fire the raw-read arm on the planted lift (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'compares wire .error/.message against a string literal' ||
	fail "CHECK43 red must fire the literal-compare arm on the planted compare (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'string operation on a raw wire .error/.message value' ||
	fail "CHECK43 red must fire the string-op arm on the planted lcase (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'concatenates a raw wire .error/.message value' ||
	fail "CHECK43 red must fire the concat arm on the planted string concatenation (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'to a call sink not proven to take Object (IsTransportReason)' ||
	fail "CHECK43 red must fire the typed-sink arm on the planted IsTransportReason argument (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'resp04cover' ||
	fail "CHECK43 red must convict the R-ROKU-04 bare-String cover line (got: $RED43_OUT)"
sed -n '/=== Check 43:/,$p' <<<"$RED43_OUT" | grep -qF 'resp04hole' ||
	fail "CHECK43 red must convict the R-ROKU-04 <>-String compare line (got: $RED43_OUT)"
sed -n '/=== Check 26:/,/=== Check 27:/p' <<<"$RED43_OUT" | grep -q "CHECK26: all" ||
	fail "Check 26 must stay PASS while Check 43 is red (gate independence)"
sed -n '/=== Check 41:/,/=== Check 43:/p' <<<"$RED43_OUT" | grep -qF "CHECK41: no phantom password-secret claim" ||
	fail "Check 41 must stay PASS while Check 43 is red (gate independence)"
cp "$FAKE_REPO/components/DetailScene.brs" "$RED43_ROOT/repo/components/DetailScene.brs"
set +e
GREEN43_OUT=$(bash "$RED43_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN43_RC=$?
set -e
[ "$GREEN43_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted wire leak is removed (got $GREEN43_RC)"
assert_contains "CHECK43: all wire" "$GREEN43_OUT"

# --- Check 43 sanctioned-gate green proof (R-ROKU-04): the tightened
# whole-line type-gate token must keep exempting the single-sided WIRE-BOUND
# shape `type(x.error) = "String"` (convicting it would over-tighten past
# the ask — the sanctioned roString family's single-sided analogue), both
# bare and sharing a line with a `<> "text"` compare the gate governs. A
# scratch copy planted with ONLY that shape must return exit 0.
GREEN43S_ROOT="$TEST_ROOT/green43s"
mkdir -p "$GREEN43S_ROOT"
cp -a "$TEST_ROOT/repo" "$GREEN43S_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$GREEN43S_ROOT/phlix-server"
python3 - "$GREEN43S_ROOT/repo/components/DetailScene.brs" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
plant = (
    "\nsub Check43SanctionedStringGates()\n"
    "    if type(plant04resp.error) = \"String\" then\n"
    "    end if\n"
    "    if plant04resp.message <> \"x\" and type(plant04resp.message) = \"String\" then\n"
    "    end if\n"
    "end sub\n"
)
text = text + plant
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
set +e
GREEN43S_OUT=$(bash "$GREEN43S_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN43S_RC=$?
set -e
[ "$GREEN43S_RC" -eq 0 ] || fail "CHECK43 must stay green on the sanctioned wire-bound =\"String\" gate shape (got $GREEN43S_RC): $(sed -n '/=== Check 43:/,$p' <<<"$GREEN43S_OUT" | head -20)"
assert_contains "CHECK43: all wire" "$GREEN43S_OUT"

# --- Check 45 red proof + restore (M-ROKU-13, review roku__exploiter M2): the
# path-injection class — a plaintext-relay or ECP-settable mediaId shaped like
# "x?profile=1" / "x/../../admin/users" steered an arbitrary Bearer GET. The
# plant re-grows BOTH cured defect forms: the invalid/"" relay check (R2) and
# the printable-only launch validator (R4), each must be named, sibling gates
# (CHECK43 wire-text law, CHECK44 dial-stamp law) stay green, and the restore
# must return the whole script to exit 0 (falsifiability).
RED45_ROOT="$TEST_ROOT/red45"
mkdir -p "$RED45_ROOT"
cp -a "$TEST_ROOT/repo" "$RED45_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED45_ROOT/phlix-server"
python3 - "$RED45_ROOT/repo/components/PhlixApp.brs" "$RED45_ROOT/repo/source/main.brs" <<'PYEOF'
import sys
pa_path, main_path = sys.argv[1], sys.argv[2]

pa_text = open(pa_path, encoding="utf-8").read()
needle = "    if not IsSafeContentId(data.mediaId) then return\n"
assert pa_text.count(needle) == 1, "CHECK45 plant: relay guard line missing (shape drift)"
pa_text = pa_text.replace(
    needle,
    '    if data.mediaId = invalid or data.mediaId = "" then return\n',
    1,
)
assert "IsSafeContentId(data.mediaId)" not in pa_text, "CHECK45 plant: relay guard strip failed"
open(pa_path, "w", encoding="utf-8").write(pa_text)

main_text = open(main_path, encoding="utf-8").read()
needle = "    return IsSafeContentId(contentId)\n"
assert main_text.count(needle) == 1, "CHECK45 plant: launch delegation line missing (shape drift)"
main_text = main_text.replace(
    needle,
    "    if contentId = invalid then return false\n"
    "    trimmed = contentId.Trim()\n"
    "    if trimmed = \"\" then return false\n"
    "    for i = 1 to trimmed.Len()\n"
    "        c = Asc(Mid(trimmed, i, 1))\n"
    "        if c < 32 or c > 126 then return false\n"
    "    end for\n"
    "    return true\n",
    1,
)
assert "IsSafeContentId(contentId)" not in main_text, "CHECK45 plant: launch delegation strip failed"
open(main_path, "w", encoding="utf-8").write(main_text)
PYEOF
set +e
RED45_OUT=$(bash "$RED45_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED45_RC=$?
set -e
[ "$RED45_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the mediaId path-injection class is re-planted (got 0 — the CHECK45 guard is toothless)"
sed -n '/=== Check 45:/,$p' <<<"$RED45_OUT" | grep -qF "CHECK45 R2" ||
	fail "CHECK45 red must fire the relay-entry R2 leg on the re-planted invalid/\"\" form (got: $RED45_OUT)"
sed -n '/=== Check 45:/,$p' <<<"$RED45_OUT" | grep -qF "components/PhlixApp.brs" ||
	fail "CHECK45 red must name components/PhlixApp.brs"
sed -n '/=== Check 45:/,$p' <<<"$RED45_OUT" | grep -qF "CHECK45 R4" ||
	fail "CHECK45 red must fire the launch-entry R4 leg on the re-fattened printable loop (got: $RED45_OUT)"
sed -n '/=== Check 45:/,$p' <<<"$RED45_OUT" | grep -qF "source/main.brs" ||
	fail "CHECK45 red must name source/main.brs"
sed -n '/=== Check 43:/,/=== Check 44:/p' <<<"$RED45_OUT" | grep -qF "CHECK43: all wire" ||
	fail "Check 43 must stay PASS while Check 45 is red (gate independence)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED45_OUT" | grep -qF "CHECK44: relay mint + handshake map" ||
	fail "Check 44 must stay PASS while Check 45 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED45_ROOT/repo/components/PhlixApp.brs"
cp "$FAKE_REPO/source/main.brs" "$RED45_ROOT/repo/source/main.brs"
set +e
GREEN45_OUT=$(bash "$RED45_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN45_RC=$?
set -e
[ "$GREEN45_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both planted mediaId defects are removed (got $GREEN45_RC)"
assert_contains "CHECK45: content-id allowlist" "$GREEN45_OUT"

# --- Check 46 red proof + restore (M-ROKU-14, review roku__exploiter M3): the
# cleartext-JWT class — the main account JWT offered over plaintext TCP behind
# an https origin, and a 101 accepted without the Sec-WebSocket-Accept proof.
# The plant re-grows THREE cured defect forms: the PlayerScene origin choke
# removed (R1), the SyncPlayTask accept verification neutralised (R2), and the
# SecWebSocketAcceptValue blank-line stop stripped (R2 body-spoof tooth — the
# r1 MAJOR-1 era where a CRLF terminator hid a body header), each must be
# named, sibling gates (CHECK44 dial-completion, CHECK45 content-id shape law)
# stay green, and the restore must return exit 0 (falsifiability).
RED46_ROOT="$TEST_ROOT/red46"
mkdir -p "$RED46_ROOT"
cp -a "$TEST_ROOT/repo" "$RED46_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED46_ROOT/phlix-server"
python3 - "$RED46_ROOT/repo/components/PlayerScene.brs" "$RED46_ROOT/repo/components/SyncPlayTask.brs" "$RED46_ROOT/repo/source/lib/SyncPlayProtocol.brs" <<'PYEOF'
import sys
ps_path, task_path, proto_path = sys.argv[1], sys.argv[2], sys.argv[3]

ps_text = open(ps_path, encoding="utf-8").read()
needle = "    if SyncPlayWsRefusedForOrigin(serverUrl) then return invalid\n"
assert ps_text.count(needle) == 1, "CHECK46 plant: origin choke line missing (shape drift)"
ps_text = ps_text.replace(needle, "", 1)
assert "SyncPlayWsRefusedForOrigin(serverUrl)" not in ps_text, "CHECK46 plant: origin choke strip failed"
open(ps_path, "w", encoding="utf-8").write(ps_text)

task_text = open(task_path, encoding="utf-8").read()
needle = "    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then\n"
assert task_text.count(needle) == 1, "CHECK46 plant: accept-verification line missing (shape drift)"
task_text = task_text.replace(needle, "    if false then\n", 1)
assert "VerifyHandshakeAccept(headerText, keyB64)" not in task_text, "CHECK46 plant: accept-proof neutralise failed"
open(task_path, "w", encoding="utf-8").write(task_text)

proto_text = open(proto_path, encoding="utf-8").read()
needle = '                if cut = "" then exit for\n'
assert proto_text.count(needle) == 1, "CHECK46 plant: accept-parser blank-line stop missing (shape drift)"
proto_text = proto_text.replace(needle, "", 1)
assert 'if cut = "" then exit for' not in proto_text, "CHECK46 plant: blank-line stop strip failed"
open(proto_path, "w", encoding="utf-8").write(proto_text)
PYEOF
set +e
RED46_OUT=$(bash "$RED46_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED46_RC=$?
set -e
[ "$RED46_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the cleartext-JWT handshake class is re-planted (got 0 — the CHECK46 guard is toothless)"
sed -n '/=== Check 46:/,$p' <<<"$RED46_OUT" | grep -qF "CHECK46 R1" ||
	fail "CHECK46 red must fire the origin-choke R1 leg on the stripped refusal (got: $RED46_OUT)"
sed -n '/=== Check 46:/,$p' <<<"$RED46_OUT" | grep -qF "components/PlayerScene.brs" ||
	fail "CHECK46 red must name components/PlayerScene.brs"
sed -n '/=== Check 46:/,$p' <<<"$RED46_OUT" | grep -qF "CHECK46 R2" ||
	fail "CHECK46 red must fire the accept-proof R2 leg on the neutralised verification (got: $RED46_OUT)"
sed -n '/=== Check 46:/,$p' <<<"$RED46_OUT" | grep -qF "components/SyncPlayTask.brs" ||
	fail "CHECK46 red must name components/SyncPlayTask.brs"
sed -n '/=== Check 46:/,$p' <<<"$RED46_OUT" | grep -qF "source/lib/SyncPlayProtocol.brs - CHECK46 R2" ||
	fail "CHECK46 red must fire the accept-parser blank-line tooth on the stripped stop and name source/lib/SyncPlayProtocol.brs (got: $RED46_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED46_OUT" | grep -qF "CHECK44: relay mint + handshake map" ||
	fail "Check 44 must stay PASS while Check 46 is red (gate independence)"
sed -n '/=== Check 45:/,/=== Check 46:/p' <<<"$RED46_OUT" | grep -qF "CHECK45: content-id allowlist" ||
	fail "Check 45 must stay PASS while Check 46 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED46_ROOT/repo/components/PlayerScene.brs"
cp "$FAKE_REPO/components/SyncPlayTask.brs" "$RED46_ROOT/repo/components/SyncPlayTask.brs"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED46_ROOT/repo/source/lib/SyncPlayProtocol.brs"
set +e
GREEN46_OUT=$(bash "$RED46_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN46_RC=$?
set -e
[ "$GREEN46_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all three planted SyncPlay defects are removed (got $GREEN46_RC)"
assert_contains "CHECK46: https origins refuse the plaintext :8097 dial" "$GREEN46_OUT"
# --- CHECK46 R2-prose plant (M-ROKU-22 truth-rotation): re-grow the two
# platform-misclaim forms in a scratch README — the "`wss://` is impossible"
# heading and the "Roku can't do TLS" clause the review convicted as false
# (roSecureSocket is the platform's TLS socket; this channel does TLS for REST
# via roUrlTransfer + ca-bundle). Both new blacklist arms must fire naming
# README.md, CHECK44/CHECK45 stay green (independence), restore returns exit 0.
RED46B_ROOT="$TEST_ROOT/red46b"
mkdir -p "$RED46B_ROOT"
cp -a "$TEST_ROOT/repo" "$RED46B_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED46B_ROOT/phlix-server"
python3 - "$RED46B_ROOT/repo/README.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
needle_a = "**`ws://` only — this build ships no `wss://` path.**"
assert text.count(needle_a) == 1, "CHECK46 R2-prose plant: the M-ROKU-22 limitation heading drifted"
text = text.replace(needle_a, "**`ws://` only — `wss://` is impossible.**", 1)
needle_b = "rides the plaintext `roStreamSocket` (no wss path implemented"
assert text.count(needle_b) == 1, "CHECK46 R2-prose plant: the M-ROKU-22 wire-contract sentence drifted"
text = text.replace(needle_b, "since Roku can't do TLS, rides the plaintext", 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED46B_OUT=$(bash "$RED46B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED46B_RC=$?
set -e
[ "$RED46B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the wss platform-misclaims are re-grown (got 0 — the M-ROKU-22 prose blacklist is toothless)"
sed -n '/=== Check 46:/,$p' <<<"$RED46B_OUT" | grep -qF "README.md - CHECK46 R2: the M-ROKU-22 platform-misclaim (wss stated as impossible)" ||
	fail "CHECK46 R2-prose red must fire the impossibility arm naming README.md (got: $RED46B_OUT)"
sed -n '/=== Check 46:/,$p' <<<"$RED46B_OUT" | grep -qF "README.md - CHECK46 R2: the M-ROKU-22 platform-misclaim (Roku stated unable to do TLS)" ||
	fail "CHECK46 R2-prose red must fire the cannot-do-TLS arm naming README.md (got: $RED46B_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED46B_OUT" | grep -qF "CHECK44: relay mint + handshake map" ||
	fail "Check 44 must stay PASS while Check 46 prose is red (gate independence)"
sed -n '/=== Check 45:/,/=== Check 46:/p' <<<"$RED46B_OUT" | grep -qF "CHECK45: content-id allowlist" ||
	fail "Check 45 must stay PASS while Check 46 prose is red (gate independence)"
cp "$FAKE_REPO/README.md" "$RED46B_ROOT/repo/README.md"
set +e
GREEN46B_OUT=$(bash "$RED46B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN46B_RC=$?
set -e
[ "$GREEN46B_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted platform-misclaims are removed (got $GREEN46B_RC)"
assert_contains "CHECK46: https origins refuse the plaintext :8097 dial" "$GREEN46B_OUT"
# --- CHECK47 plant (M-ROKU-16): re-swallow Back in a scratch ConnectScene and
# return the boot chrome to the trap era (no SetFocus + per-error ObserveField
# in ShowBootError). Both classes must be named (R1/R2), the adjacent gates
# stay green (independence), and full restore returns exit 0.
RED47_ROOT="$TEST_ROOT/red47"
mkdir -p "$RED47_ROOT"
cp -a "$TEST_ROOT/repo" "$RED47_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED47_ROOT/phlix-server"
export RED47_REPO="$RED47_ROOT/repo"
python3 - <<'PYEOF'
import os
repo = os.environ["RED47_REPO"]
cs = os.path.join(repo, "components/ConnectScene.brs")
text = open(cs, encoding="utf-8").read()
needle = "pinned by CHECK47 R1.\n    return false\nend function"
assert text.count(needle) == 1, "CHECK47 plant: ConnectScene pass-through shape drifted"
trap = ("pinned by CHECK47 R1.\n"
        "    handled = false\n\n"
        "    if press then\n"
        "        if key = \"back\" then\n"
        "            handled = true\n"
        "        end if\n"
        "    end if\n\n"
        "    return handled\nend function")
open(cs, "w", encoding="utf-8").write(text.replace(needle, trap, 1))

pa = os.path.join(repo, "components/PhlixApp.brs")
text = open(pa, encoding="utf-8").read()
needle = ("    if m.bootRetryButton <> invalid then\n"
          "        m.bootRetryButton.SetFocus(true)\n"
          "    end if\nend sub")
assert text.count(needle) == 1, "CHECK47 plant: ShowBootError focus arm shape drifted"
plant = ("    if m.bootRetryButton <> invalid then\n"
         "        m.bootRetryButton.ObserveField(\"buttonSelected\", \"OnBootRetryButton\")\n"
         "    end if\nend sub")
open(pa, "w", encoding="utf-8").write(text.replace(needle, plant, 1))
PYEOF
set +e
RED47_OUT=$(bash "$RED47_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED47_RC=$?
set -e
[ "$RED47_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the bootstrap Back trap and the unfocusable retry chrome are re-planted (got 0 — the CHECK47 guard is toothless)"
sed -n '/=== Check 47:/,$p' <<<"$RED47_OUT" | grep -qF 'components/ConnectScene.brs - CHECK47 R1' ||
	fail "CHECK47 red must fire R1 and name components/ConnectScene.brs on the re-swallowed back (got: $RED47_OUT)"
sed -n '/=== Check 47:/,$p' <<<"$RED47_OUT" | grep -qF 'CHECK47 R2: ShowBootError no longer SetFocus' ||
	fail "CHECK47 red must fire R2 on the stripped focus (got: $RED47_OUT)"
sed -n '/=== Check 47:/,$p' <<<"$RED47_OUT" | grep -qF 'CHECK47 R2: ShowBootError observes fields again' ||
	fail "CHECK47 red must fire R2 on the re-planted per-error observer (got: $RED47_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED47_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 47 is red (gate independence)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED47_OUT" | grep -qF "CHECK44: relay mint + handshake map" ||
	fail "Check 44 must stay PASS while Check 47 is red (gate independence)"
cp "$FAKE_REPO/components/ConnectScene.brs" "$RED47_ROOT/repo/components/ConnectScene.brs"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED47_ROOT/repo/components/PhlixApp.brs"
set +e
GREEN47_OUT=$(bash "$RED47_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN47_RC=$?
set -e
[ "$GREEN47_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both planted bootstrap-Back defects are removed (got $GREEN47_RC)"
assert_contains "CHECK47: bootstrap scenes never consume Back" "$GREEN47_OUT"

# --- CHECK48 plant (M-ROKU-15, review roku__exploiter M4): the credential-
# custody class — firmware auto-follow walking a Bearer/password request to an
# attacker host, and a silent cleartext persist of a remote http origin. The
# plant re-grows THREE cured defect forms: the login send site's
# EnableRedirects(false) removed (R1), the ConnectScene consent gate neutralised
# (R2 — PersistAndGo would ride unchecked again), and the classifier's
# redirect_refused arm stripped (R3; CHECK34's triangle fires jointly BY DESIGN —
# the bucket and its message must arrive in one commit, and the leg asserts
# both diagnostics). Sibling gates (CHECK46 origin/accept, CHECK47 bootstrap
# Back) stay green, and the restore must return exit 0 (falsifiability).
RED48_ROOT="$TEST_ROOT/red48"
mkdir -p "$RED48_ROOT"
cp -a "$TEST_ROOT/repo" "$RED48_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED48_ROOT/phlix-server"
python3 - "$RED48_ROOT/repo" <<'PYEOF'
import sys, os
repo = sys.argv[1]

ac = os.path.join(repo, "source/lib/ApiClient.brs")
text = open(ac, encoding="utf-8").read()
needle = ("            ' never chose. Same manual-hop law as sendRaw (see there).\n"
          "            http.EnableRedirects(false)\n")
assert text.count(needle) == 1, "CHECK48 plant: sendRawWithDeviceId redirect-off shape drifted"
text = text.replace(needle, "            ' never chose. Same manual-hop law as sendRaw (see there).\n", 1)
open(ac, "w", encoding="utf-8").write(text)

sc = os.path.join(repo, "components/ConnectScene.brs")
text = open(sc, encoding="utf-8").read()
needle = "    if ServerUrlUsesCleartextToRemoteHost(url) then\n"
assert text.count(needle) == 1, "CHECK48 plant: Connect() consent-gate shape drifted"
text = text.replace(needle, "    if false then\n", 1)
open(sc, "w", encoding="utf-8").write(text)

ut = os.path.join(repo, "source/lib/Utilities.brs")
text = open(ut, encoding="utf-8").read()
needle = '    if Instr(1, lower, "redirect") > 0 then return "redirect_refused"\n'
assert text.count(needle) == 1, "CHECK48 plant: classifier arm shape drifted"
text = text.replace(needle, "", 1)
open(ut, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED48_OUT=$(bash "$RED48_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED48_RC=$?
set -e
[ "$RED48_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the credential-custody defects are re-planted (got 0 — the CHECK48 guard is toothless)"
sed -n '/=== Check 48:/,$p' <<<"$RED48_OUT" | grep -qF 'source/lib/ApiClient.brs - CHECK48 R1' ||
	fail "CHECK48 red must fire R1 and name source/lib/ApiClient.brs on the stripped redirect-off (got: $RED48_OUT)"
sed -n '/=== Check 48:/,$p' <<<"$RED48_OUT" | grep -qF 'components/ConnectScene.brs - CHECK48 R2' ||
	fail "CHECK48 red must fire R2 and name components/ConnectScene.brs on the neutralised consent gate (got: $RED48_OUT)"
sed -n '/=== Check 48:/,$p' <<<"$RED48_OUT" | grep -qF 'source/lib/Utilities.brs - CHECK48 R3' ||
	fail "CHECK48 red must fire R3 and name source/lib/Utilities.brs on the stripped classifier arm (got: $RED48_OUT)"
grep -qF "CHECK34 R1" <<<"$RED48_OUT" ||
	fail "stripping the redirect_refused classifier arm must ALSO redden CHECK34's triangle (the joint-pinning is by design)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED48_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 48 is red (gate independence)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED48_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back" ||
	fail "Check 47 must stay PASS while Check 48 is red (gate independence)"
cp "$FAKE_REPO/source/lib/ApiClient.brs" "$RED48_ROOT/repo/source/lib/ApiClient.brs"
cp "$FAKE_REPO/components/ConnectScene.brs" "$RED48_ROOT/repo/components/ConnectScene.brs"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED48_ROOT/repo/source/lib/Utilities.brs"
set +e
GREEN48_OUT=$(bash "$RED48_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN48_RC=$?
set -e
[ "$GREEN48_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all three planted credential-custody defects are removed (got $GREEN48_RC)"
assert_contains "CHECK48: credentialed sends decide redirects" "$GREEN48_OUT"

# --- CHECK49 plant (M-ROKU-17, review roku__gameux M2): the toast-display
# class — a show write aimed at a fabricated node, an overlay node that can
# never legally enter a dialog field, a re-grown phantom-mechanics script, a
# stripped drain observer, and the per-scope delivery wire left unwired
# again. Five plants in one run, each named by its own R-arm (R1 names the
# re-planted ComponentController write in components/PhlixApp.brs; R2 the
# Scene re-extension AND the re-grown phantom chrome literals; R3 the re-
# grown ToastScene.brs; R4 the vanishing display write + drain observer; R6
# the stripped PlayerScene wiring). Sibling gates CHECK47/CHECK48 stay green,
# and the restore must return exit 0 (falsifiability).
RED49_ROOT="$TEST_ROOT/red49"
mkdir -p "$RED49_ROOT"
cp -a "$TEST_ROOT/repo" "$RED49_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED49_ROOT/phlix-server"
python3 - "$RED49_ROOT/repo" <<'PYEOF'
import sys, os
repo = sys.argv[1]

xml = os.path.join(repo, "components/ToastScene.xml")
text = open(xml, encoding="utf-8").read()
needle = '<component name="ToastScene" extends="Dialog">'
assert text.count(needle) == 1, "CHECK49 plant: the Dialog re-base shape drifted"
text = text.replace(needle, '<component name="ToastScene" extends="Scene">', 1)
text = text.replace("</component>",
                    '  <children>\n    <Label id="toastLabel" text="Toast text here" />\n  </children>\n</component>', 1)
open(xml, "w", encoding="utf-8").write(text)

brs = os.path.join(repo, "components/ToastScene.brs")
open(brs, "w", encoding="utf-8").write("' CHECK49 plant: the phantom-mechanics script re-grown\nsub init()\nend sub\n")

app = os.path.join(repo, "components/PhlixApp.brs")
text = open(app, encoding="utf-8").read()
needle = "    target.dialog = toast\n"
assert text.count(needle) == 1, "CHECK49 plant: the dialog display write shape drifted"
text = text.replace(needle, "    m.top.ComponentController.Dialog = toast\n", 1)
needle = '    toast.ObserveField("wasClosed", "OnToastClosed")\n'
assert text.count(needle) == 1, "CHECK49 plant: the wasClosed drain observer shape drifted"
text = text.replace(needle, "", 1)
open(app, "w", encoding="utf-8").write(text)

pl = os.path.join(repo, "components/PlayerScene.brs")
text = open(pl, encoding="utf-8").read()
needle = "    toast.setScene(m.top)\n"
assert text.count(needle) == 1, "CHECK49 plant: the PlayerScene delivery wire shape drifted"
text = text.replace(needle, "", 1)
open(pl, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED49_OUT=$(bash "$RED49_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED49_RC=$?
set -e
[ "$RED49_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the toast-display defects are re-planted (got 0 — the CHECK49 guard is toothless)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'components/PhlixApp.brs - CHECK49 R1' ||
	fail "CHECK49 red must fire R1 and name components/PhlixApp.brs on the re-planted ComponentController write (got: $RED49_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'components/ToastScene.xml - CHECK49 R2' ||
	fail "CHECK49 red must fire R2 and name components/ToastScene.xml on the Scene re-extension / phantom chrome (got: $RED49_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'components/ToastScene.brs - CHECK49 R3' ||
	fail "CHECK49 red must fire R3 and name the re-grown components/ToastScene.brs (got: $RED49_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'CHECK49 R4: the dialog display write is gone' ||
	fail "CHECK49 red must fire R4 on the vanished dialog display write (got: $RED49_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'CHECK49 R4: the wasClosed drain observer is gone' ||
	fail "CHECK49 red must fire R4 on the stripped drain observer (got: $RED49_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49_OUT" | grep -qF 'components/PlayerScene.brs - CHECK49 R6' ||
	fail "CHECK49 red must fire R6 and name components/PlayerScene.brs on the unwired scope (got: $RED49_OUT)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED49_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back" ||
	fail "Check 47 must stay PASS while Check 49 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED49_OUT" | grep -qF "CHECK48: credentialed sends decide redirects" ||
	fail "Check 48 must stay PASS while Check 49 is red (gate independence)"
cp "$FAKE_REPO/components/ToastScene.xml" "$RED49_ROOT/repo/components/ToastScene.xml"
rm -f "$RED49_ROOT/repo/components/ToastScene.brs"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED49_ROOT/repo/components/PhlixApp.brs"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED49_ROOT/repo/components/PlayerScene.brs"
set +e
GREEN49_OUT=$(bash "$RED49_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN49_RC=$?
set -e
[ "$GREEN49_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all planted toast-display defects are removed (got $GREEN49_RC)"
assert_contains "CHECK49: the toast overlay is a built-in-Dialog node" "$GREEN49_OUT"

# --- CHECK49 R7 dispatch plant (M-ROKU-17 r2, review roku__gameux M17r1
# CRITICAL-1): the delivery-leg class. This plant re-grows BOTH dead doors at
# once — the retired node.PostMessage wire (bsc's vendored Roku types model
# PostMessage only on roRenderThreadQueue, whose receive path AddMessageHandler
# ships nowhere here; no onMessage special is modeled at any arity; the repo's
# seven Task components ride field observers, not onMessage) plus the silent
# pre-attach drop (r1 ask 3) — and strips the root observer wiring, renaming
# the receiver arm back to onMessage. The r1 display machinery (Dialog base,
# queue, timer, close/wasClosed) stays untouched: gate-class proof that R7
# alone convicts the dispatch path. CHECK49 R7 must name source/lib/
# ToastManager.brs (re-grown PostMessage; vanished guard/payload/trigger
# writes; silent-drop return re-grown; vanished Push + drain-assign) and
# components/PhlixApp.brs (re-grown onMessage; stripped ObserveField wiring;
# vanished dispatch arm), with CHECK49 R1/R6 territory held green and
# CHECK47/CHECK48/CHECK50/CHECK51 gate independence; restore returns exit 0
# (falsifiability).
RED49B_ROOT="$TEST_ROOT/red49b"
mkdir -p "$RED49B_ROOT"
cp -a "$TEST_ROOT/repo" "$RED49B_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED49B_ROOT/phlix-server"
python3 - "$RED49B_ROOT/repo" <<'PYEOF'
import sys, os
repo = sys.argv[1]

tm = os.path.join(repo, "source/lib/ToastManager.brs")
text = open(tm, encoding="utf-8").read()
needle = (
    '                if not target.DoesExist("toastSeq") then return\n'
    "                target.toastMessage = message\n"
    "                target.toastDuration = durationMs\n"
    "                target.toastSeq = target.toastSeq + 1\n"
)
assert text.count(needle) == 1, "CHECK49 r2 plant: the observed-field dispatch shape drifted"
dead = (
    '                content = CreateObject("roSGNode", "ContentNode")\n'
    "                content.title = message\n"
    '                target.PostMessage("showToast", content)\n'
)
text = text.replace(needle, dead, 1)
qneedle = """                if m._scene = invalid then
                    if m._pending.Count() >= m.MAX_PENDING then
                        dropped = m._pending.Shift()
                        print "Toast pre-attach queue overflow (cap " m.MAX_PENDING ") - dropped oldest notice:" dropped.text
                    end if
                    m._pending.Push({ text: message, duration: durationMs })
                    return
                end if"""
assert text.count(qneedle) == 1, "CHECK49 r2 plant: the pre-attach queue shape drifted"
text = text.replace(qneedle, "                if m._scene = invalid then return", 1)
open(tm, "w", encoding="utf-8").write(text)

app = os.path.join(repo, "components/PhlixApp.brs")
text = open(app, encoding="utf-8").read()
needle = '    m.top.ObserveField("toastSeq", "OnToastNotice")\n'
assert text.count(needle) == 1, "CHECK49 r2 plant: the root observer wiring shape drifted"
text = text.replace(needle, "", 1)
needle = "sub OnToastNotice(event as Object)\n"
assert text.count(needle) == 1, "CHECK49 r2 plant: the dispatch arm shape drifted"
text = text.replace(needle, "sub onMessage(msg as Object)\n", 1)
open(app, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED49B_OUT=$(bash "$RED49B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED49B_RC=$?
set -e
[ "$RED49B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the dead dispatch and silent-drop doors are re-planted (got 0 — the CHECK49 R7 guard is toothless)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF 'source/lib/ToastManager.brs - CHECK49 R7: node.PostMessage is re-grown' ||
	fail "CHECK49 R7 must name source/lib/ToastManager.brs on the re-grown PostMessage (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF "CHECK49 R7: the alwaysNotify trigger bump is gone" ||
	fail "CHECK49 R7 must convict the vanished toastSeq trigger bump in ToastManager (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF "CHECK49 R7: the silent pre-attach drop guard is back" ||
	fail "CHECK49 R7 must convict the re-grown silent pre-attach drop (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF "CHECK49 R7: pre-attach queue/drain needle 'm._pending.Push' is gone" ||
	fail "CHECK49 R7 must convict the vanished pre-attach queue push (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF 'components/PhlixApp.brs - CHECK49 R7: the root'\''s observer wiring is gone' ||
	fail "CHECK49 R7 must name components/PhlixApp.brs on the stripped ObserveField wiring (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF 'components/PhlixApp.brs - CHECK49 R7: the retired onMessage catch-all is re-grown' ||
	fail "CHECK49 R7 must name components/PhlixApp.brs on the re-grown onMessage receiver (got: $RED49B_OUT)"
sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF "CHECK49 R7: the dispatch arm sub vanished" ||
	fail "CHECK49 R7 must convict the vanished OnToastNotice dispatch arm (got: $RED49B_OUT)"
! grep -qF 'CHECK49 R1' <<<"$RED49B_OUT" ||
	fail "the r2 plants must not touch CHECK49 R1 territory - the ComponentController extinction pins (found: $RED49B_OUT)"
! sed -n '/=== Check 49:/,$p' <<<"$RED49B_OUT" | grep -qF 'CHECK49 R6' ||
	fail "the r2 plants must not touch CHECK49 R6 territory - the GetParent root walk pins (found: $RED49B_OUT)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED49B_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back" ||
	fail "Check 47 must stay PASS while the CHECK49 r2 dispatch plant is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED49B_OUT" | grep -qF "CHECK48: credentialed sends decide redirects" ||
	fail "Check 48 must stay PASS while the CHECK49 r2 dispatch plant is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED49B_OUT" | grep -qF "CHECK50: host pause/seek/resume, joins, host elections, errors and" ||
	fail "Check 50 must stay PASS while the CHECK49 r2 dispatch plant is red (gate independence - the r1 display machinery is untouched by this plant)"
sed -n '/=== Check 51:/,$p' <<<"$RED49B_OUT" | grep -qF "CHECK51: the error-overlay trio" ||
	fail "Check 51 must run and stay green while the CHECK49 r2 dispatch plant is red (gate independence)"
cp "$FAKE_REPO/source/lib/ToastManager.brs" "$RED49B_ROOT/repo/source/lib/ToastManager.brs"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED49B_ROOT/repo/components/PhlixApp.brs"
set +e
GREEN49B_OUT=$(bash "$RED49B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN49B_RC=$?
set -e
[ "$GREEN49B_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the r2 dispatch plants are restored (got $GREEN49B_RC)"
assert_contains "fiction stays extinct repo-wide and the pre-attach queue drain" "$GREEN49B_OUT"
# --- CHECK50 plant (M-ROKU-19, review roku__gameux M4): the watch-party
# attribution class. The plant re-grows TWO cured defect forms: the banner
# label node losing its id in the markup (R1 — ShowPartyNotice would write to
# an invalid node, i.e. the silent-event defect reborn), and one
# ApplyRemotePlayback arm losing its NotifyPartyEvent call (R3 — a host-driven
# transport change back to total silence mid-playback). Sibling gates (CHECK46
# origin/accept, CHECK48 credential custody) stay green, and the restore must
# return exit 0 (falsifiability).
RED50_ROOT="$TEST_ROOT/red50"
mkdir -p "$RED50_ROOT"
cp -a "$TEST_ROOT/repo" "$RED50_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED50_ROOT/phlix-server"
python3 - "$RED50_ROOT/repo" <<'PYEOF'
import sys, os
repo = sys.argv[1]

xmlp = os.path.join(repo, "components/PlayerScene.xml")
text = open(xmlp, encoding="utf-8").read()
needle = 'id="partyNoticeLabel" />'
assert text.count(needle) == 1, "CHECK50 plant: partyNoticeLabel markup shape drifted"
text = text.replace(needle, 'id="partyNoticeRenamed" />', 1)
open(xmlp, "w", encoding="utf-8").write(text)

brs = os.path.join(repo, "components/PlayerScene.brs")
text = open(brs, encoding="utf-8").read()
needle = '        NotifyPartyEvent(Translate("player_party_host_paused"), 2.5!)\n'
assert text.count(needle) == 1, "CHECK50 plant: pause-arm attribution call shape drifted"
text = text.replace(needle, "", 1)
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED50_OUT=$(bash "$RED50_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED50_RC=$?
set -e
[ "$RED50_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the party-attribution defects are re-planted (got 0 — the CHECK50 guard is toothless)"
sed -n '/=== Check 50:/,$p' <<<"$RED50_OUT" | grep -qF 'components/PlayerScene.xml - CHECK50 R1' ||
	fail "CHECK50 red must fire R1 and name components/PlayerScene.xml on the orphaned banner label (got: $RED50_OUT)"
sed -n '/=== Check 50:/,$p' <<<"$RED50_OUT" | grep -qF 'components/PlayerScene.brs - CHECK50 R3' ||
	fail "CHECK50 red must fire R3 and name components/PlayerScene.brs on the stripped pause-arm attribution (got: $RED50_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED50_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 50 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 50:/p' <<<"$RED50_OUT" | grep -qF "CHECK48: credentialed sends decide redirects" ||
	fail "Check 48 must stay PASS while Check 50 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.xml" "$RED50_ROOT/repo/components/PlayerScene.xml"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED50_ROOT/repo/components/PlayerScene.brs"
set +e
GREEN50_OUT=$(bash "$RED50_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN50_RC=$?
set -e
[ "$GREEN50_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both planted party-attribution defects are removed (got $GREEN50_RC)"
assert_contains "CHECK50: host pause/seek/resume" "$GREEN50_OUT"

# --- CHECK51 plant (M-ROKU-20, review roku__gameux M5): the live-error i18n
# law. Re-growing the raw-English session arm into a scratch PlayerScene.brs
# (Translate write replaced by the cured sentence) must fire BOTH arms of the
# pin — R1 (the overlay sub stopped writing Translate) and R2 (the sentence is
# back as a literal) — while CHECK50/CHECK20 stay green (gate independence);
# restoring returns exit 0 (falsifiability).
RED51_ROOT="$TEST_ROOT/red51"
mkdir -p "$RED51_ROOT"
cp -a "$TEST_ROOT/repo" "$RED51_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED51_ROOT/phlix-server"
python3 - "$RED51_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "components/PlayerScene.brs")
text = open(brs, encoding="utf-8").read()
needle = 'm.errorMessageLabel.text = Translate("player_err_session_expired")'
assert text.count(needle) == 1, "CHECK51 plant: session-arm Translate write shape drifted"
text = text.replace(
    needle,
    'm.errorMessageLabel.text = "Your session has expired. Please sign in again to continue saving progress."',
    1,
)
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED51_OUT=$(bash "$RED51_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED51_RC=$?
set -e
[ "$RED51_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the raw session-expired literal is re-planted (got 0 — the CHECK51 guard is toothless)"
sed -n '/=== Check 51:/,$p' <<<"$RED51_OUT" | grep -qF 'components/PlayerScene.brs - CHECK51 R1' ||
	fail "CHECK51 red must fire R1 and name components/PlayerScene.brs on the lost session-arm Translate write (got: $RED51_OUT)"
sed -n '/=== Check 51:/,$p' <<<"$RED51_OUT" | grep -qF 'CHECK51 R2: reintroduced English UI copy' ||
	fail "CHECK51 red must fire R2 on the re-grown raw English sentence (got: $RED51_OUT)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED51_OUT" | grep -qF "CHECK50: host pause/seek/resume" ||
	fail "Check 50 must stay PASS while Check 51 is red (gate independence)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED51_OUT" | grep -qF "Translate keys resolve under the flattened convention" ||
	fail "Check 20 must stay PASS while Check 51 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED51_ROOT/repo/components/PlayerScene.brs"
set +e
GREEN51_OUT=$(bash "$RED51_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN51_RC=$?
set -e
[ "$GREEN51_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted raw-English session arm is removed (got $GREEN51_RC)"
assert_contains "CHECK51: the error-overlay trio" "$GREEN51_OUT"

# --- CHECK52 plant (M-ROKU-21, review roku__gameux M6): the failure-vs-emptiness
# law. Reverting ONE failure branch — ExtractData's !ok arm back to the collapsed
# `return []` — in a scratch DashboardScene.brs must fire CHECK52 R1 twice, naming
# both the lost arm and the collapse detector, while CHECK48/CHECK51 stay green
# (gate independence); restoring returns exit 0 (falsifiability). This is the
# mutation the cure itself must never survive — a re-grown "confidently-empty
# app" cannot pass the battery.
RED52_ROOT="$TEST_ROOT/red52"
mkdir -p "$RED52_ROOT"
cp -a "$TEST_ROOT/repo" "$RED52_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED52_ROOT/phlix-server"
python3 - "$RED52_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "components/DashboardScene.brs")
text = open(brs, encoding="utf-8").read()
needle = 'if not resp.ok then return invalid'
assert text.count(needle) == 1, "CHECK52 plant: ExtractData !ok arm shape drifted"
text = text.replace(needle, 'if not resp.ok then return []', 1)
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED52_OUT=$(bash "$RED52_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED52_RC=$?
set -e
[ "$RED52_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the collapsed failure arm is re-planted (got 0 — the CHECK52 guard is toothless)"
sed -n '/=== Check 52:/,$p' <<<"$RED52_OUT" | grep -qF "CHECK52: 'if not resp.ok then return invalid' missing" ||
	fail "CHECK52 red must name the collapsed ExtractData !ok arm (got: $RED52_OUT)"
sed -n '/=== Check 52:/,$p' <<<"$RED52_OUT" | grep -qF 'CHECK52 R1: ExtractData still returns [] on some path' ||
	fail "CHECK52 red must fire the collapse detector on the reverted branch (got: $RED52_OUT)"
sed -n '/=== Check 51:/,/=== Check 52:/p' <<<"$RED52_OUT" | grep -qF "CHECK51: the error-overlay trio" ||
	fail "Check 51 must stay PASS while Check 52 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED52_OUT" | grep -qF "CHECK48: credentialed sends decide redirects themselves" ||
	fail "Check 48 must stay PASS while Check 52 is red (gate independence)"
cp "$FAKE_REPO/components/DashboardScene.brs" "$RED52_ROOT/repo/components/DashboardScene.brs"
set +e
GREEN52_OUT=$(bash "$RED52_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN52_RC=$?
set -e
[ "$GREEN52_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted collapsed arm is removed (got $GREEN52_RC)"
assert_contains "CHECK52: a failed read yields invalid" "$GREEN52_OUT"

# --- CHECK53 plant (M-ROKU-24, review roku__secnet M3): credential custody at
# the server_url persist choke. Re-grow the pre-cure persist — strip the
# conditional six-key wipe from PersistAndGo in a scratch ConnectScene.brs —
# and CHECK53 R1 must fire four convictions naming the lost capture, the lost
# conditional guard (same-URL prefill/retry law), the lost ResetCachedStorage
# primitive and the wipe-before-write order, while CHECK48 (whose R2 needles
# inspect the Connect() consent gate and the write-site census — untouched by
# this plant) and CHECK52 (dashboard/home rails) stay green (gate
# independence); restoring returns exit 0 (falsifiability). The leak itself —
# old-host access+refresh tokens riding GET {new}/auth/me and POST
# {new}/auth/refresh after OnConnected restores them — needs registry + network
# nodes, so this static leg is the gate (CHECK50/51/52 precedent, device
# honesty disclosed in the fixlog).
RED53_ROOT="$TEST_ROOT/red53"
mkdir -p "$RED53_ROOT"
cp -a "$TEST_ROOT/repo" "$RED53_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED53_ROOT/phlix-server"
python3 - "$RED53_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "components/ConnectScene.brs")
text = open(brs, encoding="utf-8").read()
needle = (
    '    previousUrl = GetServerUrl()\n'
    '    if previousUrl <> "" and previousUrl <> url then\n'
    '        ResetCachedStorage(true)\n'
    '    end if\n'
)
assert text.count(needle) == 1, "CHECK53 plant: PersistAndGo custody block shape drifted"
text = text.replace(needle, '', 1)
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED53_OUT=$(bash "$RED53_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED53_RC=$?
set -e
[ "$RED53_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the conditional wipe is re-planted away (got 0 — the CHECK53 guard is toothless)"
sed -n '/=== Check 53:/,$p' <<<"$RED53_OUT" | grep -qF "CHECK53: 'ResetCachedStorage(true)' missing" ||
	fail "CHECK53 red must name the missing six-key wipe primitive (got: $RED53_OUT)"
sed -n '/=== Check 53:/,$p' <<<"$RED53_OUT" | grep -qF 'CHECK53 R1: the wipe no longer PRECEDES the server_url write' ||
	fail "CHECK53 red must fire the wipe-before-write ordering conviction (got: $RED53_OUT)"
sed -n '/=== Check 53:/,$p' <<<"$RED53_OUT" | grep -qF 'if previousUrl <> "" and previousUrl <> url then' ||
	fail "CHECK53 red must name the lost conditional guard (same-URL retry law) (got: $RED53_OUT)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED53_OUT" | grep -qF "CHECK48: credentialed sends decide redirects themselves" ||
	fail "Check 48 must stay PASS while Check 53 is red (gate independence)"
sed -n '/=== Check 52:/,/=== Check 53:/p' <<<"$RED53_OUT" | grep -qF "CHECK52: a failed read yields invalid" ||
	fail "Check 52 must stay PASS while Check 53 is red (gate independence)"
cp "$FAKE_REPO/components/ConnectScene.brs" "$RED53_ROOT/repo/components/ConnectScene.brs"
set +e
GREEN53_OUT=$(bash "$RED53_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN53_RC=$?
set -e
[ "$GREEN53_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted pre-cure persist is removed (got $GREEN53_RC)"
assert_contains "CHECK53: the one server_url write-site wipes" "$GREEN53_OUT"
# --- CHECK55 plant (M-ROKU-23, review roku__secnet M2): hub relay origin law.
# Strip the scene choke, the task choke, rename the predicate and delete the
# README law paragraph in one scratch copy — CHECK55 R1/R2/R3/R4 must fire
# together naming the three files (a re-rolled subset would let one leg go
# soft); separately, PLANTING a roSecureSocket instantiation (the deferred arm
# shipping blind) must fire R3's no-fabricated-TLS arm. CHECK53 (credential
# custody at the persist choke — untouched by these plants) stays green both
# reds (gate independence); restoring returns exit 0 (falsifiability). The
# dial itself needs registry + live hub nodes, so these static legs are the
# gate (CHECK50-53 precedent; device honesty disclosed in the fixlog).
RED55_ROOT="$TEST_ROOT/red55"
mkdir -p "$RED55_ROOT"
cp -a "$TEST_ROOT/repo" "$RED55_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED55_ROOT/phlix-server"
python3 - "$RED55_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]

app = os.path.join(repo, "components/PhlixApp.brs")
text = open(app, encoding="utf-8").read()
needle = '    if HubRelayCleartextRefusedForOrigin(hubUrl) then return\n'
assert text.count(needle) == 1, "CHECK55 plant: scene choke shape drifted"
open(app, "w", encoding="utf-8").write(text.replace(needle, '', 1))

task = os.path.join(repo, "components/HubCommandTask.brs")
text = open(task, encoding="utf-8").read()
needle = ('    if HubRelayCleartextRefusedForOrigin(apiBase) then\n'
          '        SetState("closed")\n'
          '        return\n'
          '    end if\n\n')
assert text.count(needle) == 1, "CHECK55 plant: task choke shape drifted"
open(task, "w", encoding="utf-8").write(text.replace(needle, '', 1))

util = os.path.join(repo, "source/lib/Utilities.brs")
text = open(util, encoding="utf-8").read()
needle = 'function HubRelayCleartextRefusedForOrigin(hubUrl as String) as Boolean'
assert text.count(needle) == 1, "CHECK55 plant: predicate signature shape drifted"
open(util, "w", encoding="utf-8").write(
    text.replace(needle, 'function HubRelayLawRetired(hubUrl as String) as Boolean', 1))

rd = os.path.join(repo, "README.md")
lines = open(rd, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("5. **Command-consumer origin law"))
end = next(i for i, l in enumerate(lines) if l.startswith("#### Hub mode storage keys"))
assert start < end, "CHECK55 plant: README law paragraph window invalid"
del lines[start:end]
open(rd, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED55_OUT=$(bash "$RED55_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED55_RC=$?
set -e
[ "$RED55_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the hub-relay origin law is re-planted away (got 0 — the CHECK55 guard is toothless)"
sed -n '/=== Check 55:/,$p' <<<"$RED55_OUT" | grep -qF "CHECK55 R1: function HubRelayCleartextRefusedForOrigin() vanished" ||
	fail "CHECK55 red must name the vanished predicate (got: $RED55_OUT)"
sed -n '/=== Check 55:/,$p' <<<"$RED55_OUT" | grep -qF "CHECK55: 'HubRelayCleartextRefusedForOrigin(hubUrl)' missing" ||
	fail "CHECK55 red must name the stripped scene choke (got: $RED55_OUT)"
sed -n '/=== Check 55:/,$p' <<<"$RED55_OUT" | grep -qF "CHECK55: 'HubRelayCleartextRefusedForOrigin(apiBase)' missing" ||
	fail "CHECK55 red must name the stripped task choke (got: $RED55_OUT)"
sed -n '/=== Check 55:/,$p' <<<"$RED55_OUT" | grep -qF "CHECK55 R4: 'command-consumer origin law' missing" ||
	fail "CHECK55 red must name the deleted README law paragraph (got: $RED55_OUT)"
sed -n '/=== Check 53:/,/=== Check 55:/p' <<<"$RED55_OUT" | grep -qF "CHECK53: the one server_url write-site wipes" ||
	fail "Check 53 must stay PASS while Check 55 is red (gate independence)"

# (b) fabrication plant: the DEFERRED wss arm shipping blind.
RED55B_ROOT="$TEST_ROOT/red55b"
mkdir -p "$RED55B_ROOT"
cp -a "$TEST_ROOT/repo" "$RED55B_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED55B_ROOT/phlix-server"
python3 - "$RED55B_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
task = os.path.join(repo, "components/HubCommandTask.brs")
text = open(task, encoding="utf-8").read()
needle = "    m.proto = SyncPlayProtocol()\n"
assert text.count(needle) == 1, "CHECK55 plant B: proto-init shape drifted"
open(task, "w", encoding="utf-8").write(
    text.replace(needle, '    m.sock = CreateObject("roSecureSocket", 1)\n' + needle, 1))
PYEOF
set +e
RED55B_OUT=$(bash "$RED55B_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED55B_RC=$?
set -e
[ "$RED55B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a roSecureSocket instantiation is planted (got 0 — the deferred-arm no-fabrication pin is toothless)"
sed -n '/=== Check 55:/,$p' <<<"$RED55B_OUT" | grep -qF "roSecureSocket instantiation appeared" ||
	fail "CHECK55 red must convict the fabricated TLS dial (got: $RED55B_OUT)"
sed -n '/=== Check 53:/,/=== Check 55:/p' <<<"$RED55B_OUT" | grep -qF "CHECK53: the one server_url write-site wipes" ||
	fail "Check 53 must stay PASS while Check 55 is red (gate independence, fabrication plant)"

# (c) restore every plant -> green (falsifiability).
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED55_ROOT/repo/components/PhlixApp.brs"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$RED55_ROOT/repo/components/HubCommandTask.brs"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED55_ROOT/repo/source/lib/Utilities.brs"
cp "$FAKE_REPO/README.md" "$RED55_ROOT/repo/README.md"
set +e
GREEN55_OUT=$(bash "$RED55_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN55_RC=$?
set -e
[ "$GREEN55_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after every CHECK55 plant is restored (got $GREEN55_RC)"
assert_contains "CHECK55: the hub relay refuses" "$GREEN55_OUT"

# --- CHECK57 plant (M-ROKU-25): re-grow the five-name drift the one-name law
# cured — a watch-party banner label and a sync-server error value in the en_US
# catalog, the "'s Room" default name in PlayerScene, a room key MIRRORED into
# all seven catalogs (so Check 21's parity law cannot absorb the conviction —
# the R3 arm must be the one that grows red), and the README/docs pre-cure
# spellings — CHECK57 R1/R2/R3/R4 must each fire naming its plant, while
# CHECK20 (Translate resolution — every planted/consumed key still rides),
# CHECK21 (seven-family mirror — the new key is parity-grown), CHECK25 (XML
# chrome — untouched) and CHECK51 (live-copy law — no planted sentence returns
# to the comment-masked code view) stay green (gate independence); full restore
# returns exit 0 (falsifiability). R3's VANISH arm (a pinned identifier key
# removed) is ad-hoc-probed in the fixlog rather than here: deleting a party_*
# key from the catalogs would also fire CHECK20's consumer law and blur which
# gate convicted what.
RED57_ROOT="$TEST_ROOT/red57"
mkdir -p "$RED57_ROOT"
cp -a "$TEST_ROOT/repo" "$RED57_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED57_ROOT/phlix-server"
python3 - "$RED57_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]

def edit(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"CHECK57 plant: {path} needle drifted: {old!r}"
    open(path, "w", encoding="utf-8", newline="\n").write(text.replace(old, new, 1))

en = os.path.join(repo, "locale", "en_US", "strings.json")
edit(en, '"party_connected": "Connected to Watch Together",', '"party_connected": "Connected to watch party",')
edit(en, '"local_connect_failed": "Could not reach the server.",', '"local_connect_failed": "Could not reach the sync server.",')

# R3-new grown MIRROR-legally in every shipped catalog.
loc_root = os.path.join(repo, "locale")
for loc in sorted(os.listdir(loc_root)):
    p = os.path.join(loc_root, loc, "strings.json")
    text = open(p, encoding="utf-8").read()
    lines = text.split("\n")
    idx = [n for n, line in enumerate(lines) if '"create_room":' in line]
    assert len(idx) == 1, f"CHECK57 plant: create_room anchor drifted in {loc}"
    lines.insert(idx[0] + 1, '    "create_room2": "Create Room 2",')
    open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))

edit(os.path.join(repo, "components", "PlayerScene.brs"),
     'group_name: deviceName + "\'s Group"', 'group_name: deviceName + "\'s Room"')
edit(os.path.join(repo, "README.md"),
     'to start a new group (named `"<device>\'s Group"`', 'to start a new room (named `"<device>\'s Room"`')
edit(os.path.join(repo, "docs", "i18n.md"),
     "| Watch Together UI:", "| Watch-party room UI:")
PYEOF
set +e
RED57_OUT=$(bash "$RED57_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED57_RC=$?
set -e
[ "$RED57_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the five-name drift is re-planted (got 0 — the CHECK57 guard is toothless)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R1: player.party_connected' ||
	fail "CHECK57 red must re-convict the watch-party banner label (got: $RED57_OUT)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R1: errors.local_connect_failed' ||
	fail "CHECK57 red must re-convict the sync-server error value (got: $RED57_OUT)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R2: the renamed default came back' ||
	fail "CHECK57 red must convict the re-grown 's Room default in the shipped code (got: $RED57_OUT)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R3: new room/party key syncplay.create_room2' ||
	fail "CHECK57 red must convict the grown room key on its own R3 arm (got: $RED57_OUT)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R4: a ' ||
	fail "CHECK57 red must convict the re-grown watch-party docs spelling (got: $RED57_OUT)"
sed -n '/=== Check 57:/,$p' <<<"$RED57_OUT" | grep -qF 'CHECK57 R4: '"'"'to start a new room'"'"' is back' ||
	fail "CHECK57 red must convict the README button/thing drift coming back (got: $RED57_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED57_OUT" | grep -q "CHECK20: all" ||
	fail "Check 20 must stay PASS while Check 57 is red (gate independence)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED57_OUT" | grep -q "CHECK21: all" ||
	fail "Check 21 must stay PASS while Check 57 is red (gate independence — the R3 plant is parity-grown)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED57_OUT" | grep -q "CHECK25: all" ||
	fail "Check 25 must stay PASS while Check 57 is red (gate independence)"
sed -n '/=== Check 51:/,/=== Check 52:/p' <<<"$RED57_OUT" | grep -qF "CHECK51: the error-overlay trio" ||
	fail "Check 51 must stay PASS while Check 57 is red (gate independence)"
cp -a "$FAKE_REPO/locale"/. "$RED57_ROOT/repo/locale/"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED57_ROOT/repo/components/PlayerScene.brs"
cp "$FAKE_REPO/README.md" "$RED57_ROOT/repo/README.md"
cp "$FAKE_REPO/docs/i18n.md" "$RED57_ROOT/repo/docs/i18n.md"
set +e
GREEN57_OUT=$(bash "$RED57_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN57_RC=$?
set -e
[ "$GREEN57_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted vocabulary drift is removed (got $GREEN57_RC): $(grep -B1 -A6 '^  CHECK' <<<"$GREEN57_OUT" | tail -30)"
assert_contains "CHECK57: the co-watch feature speaks with one name" "$GREEN57_OUT"
# --- CHECK60 plant (M-ROKU-32): re-grow the structure-map lie the mirror law
# cured — one phantom landmark resurrected in the lib block (SessionManager.brs,
# deleted in R7.5) and one real landmark dropped from the map (AppContext.brs) —
# CHECK60 R1 must convict the phantom by name and R2 the miss by name, while
# CHECK56 (the README DEAD PATH markers the plant never touches) and CHECK58 stay
# green (gate independence: same README file, disjoint arms); restoring the map
# returns exit 0 (falsifiability).
RED60_ROOT="$TEST_ROOT/red60"
mkdir -p "$RED60_ROOT"
cp -a "$TEST_ROOT/repo" "$RED60_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED60_ROOT/phlix-server"
python3 - "$RED60_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]

def edit(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"CHECK60 plant: {path} needle drifted: {old!r}"
    open(path, "w", encoding="utf-8", newline="\n").write(text.replace(old, new, 1))

rm = os.path.join(repo, "README.md")
# R1 phantom: resurrect a file deleted in R7.5 inside the lib block.
edit(rm,
     "│   │   ├── Storage.brs           # Persistent storage (registry)",
     "│   │   ├── SessionManager.brs      # Session management\n│   │   ├── Storage.brs           # Persistent storage (registry)")
# R2 miss: drop a real landmark from the map.
edit(rm,
     "│   │   ├── AppContext.brs        # Hub/connection-state core (active server, relay routing, server_url custody)\n",
     "")
PYEOF
set +e
RED60_OUT=$(bash "$RED60_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED60_RC=$?
set -e
[ "$RED60_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the structure map lies again (got 0 — the CHECK60 guard is toothless)"
sed -n '/=== Check 60:/,$p' <<<"$RED60_OUT" | grep -qF 'CHECK60 R1: structure block lists SessionManager.brs' ||
	fail "CHECK60 red must re-convict the resurrected phantom landmark by name (got: $RED60_OUT)"
sed -n '/=== Check 60:/,$p' <<<"$RED60_OUT" | grep -qF 'CHECK60 R2: AppContext.brs ships in the tree' ||
	fail "CHECK60 red must convict the dropped landmark by name (got: $RED60_OUT)"
sed -n '/=== Check 56:/,/=== Check 57:/p' <<<"$RED60_OUT" | grep -q "CHECK56: the SyncPlay room scene has zero instantiation sites" ||
	fail "Check 56 must stay PASS while Check 60 is red (gate independence — same README, disjoint arms)"
sed -n '/=== Check 58:/,$p' <<<"$RED60_OUT" | grep -q "CHECK58: the stand-down guard restores the default strip" ||
	fail "Check 58 must stay PASS while Check 60 is red (gate independence)"
cp "$FAKE_REPO/README.md" "$RED60_ROOT/repo/README.md"
set +e
GREEN60_OUT=$(bash "$RED60_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN60_RC=$?
set -e
[ "$GREEN60_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the structure-map plants are removed (got $GREEN60_RC): $(grep -B1 -A6 '^  CHECK' <<<"$GREEN60_OUT" | tail -30)"
assert_contains "CHECK60: the Project Structure map lists exactly the 58 shipped .brs" "$GREEN60_OUT"
# --- CHECK61 plants (M-ROKU-37): the locale-family enumeration law on an
# independent scratch copy (CHECK58/59/60 scaffolding precedent), four arms each
# restored. P1 reverts README.md's locale/ block to the pre-M32 one-row era —
# CHECK61 R3 fires six times naming the omitted families and README.md; P2
# reverts the i18n.md Overview headline to the bare-sibling-count era the review
# lane read as "six families" — R1 convicts the missing family-total sentence;
# P3 strips one sibling row from the i18n.md Directory-Structure tree — R2
# convicts the omission; P4 rewrites one catalog's _metadata.locale onto a
# sibling tag — R4 convicts the folder that no longer names its own family.
# CHECK21 (directory-derived catalog parity), CHECK56 (disjoint doc surfaces)
# and CHECK60 (.brs landmarks — locale rows are none) stay PASS in every red —
# gate independence; full restore returns exit 0 with CHECK61 green. --
RED61_ROOT="$TEST_ROOT/red61"
mkdir -p "$RED61_ROOT"
cp -a "$TEST_ROOT/repo" "$RED61_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED61_ROOT/phlix-server"
python3 - "$RED61_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "README.md")
text = open(path, encoding="utf-8").read()
new_block = """├── locale/                       # Seven catalogs, same flattened key set (Check 21 parity; see docs/i18n.md)
│   ├── de_DE/strings.json
│   ├── en_US/strings.json        # Base locale — the fallback + comparison source
│   ├── es_ES/strings.json
│   ├── fr_FR/strings.json
│   ├── it_IT/strings.json
│   ├── ja_JP/strings.json
│   └── pt_BR/strings.json"""
old_block = """├── locale/
│   └── en_US/strings.json      # Base-locale user-facing strings (see docs/i18n.md)"""
assert text.count(new_block) == 1, "CHECK61 plant P1: the README locale/ tree shape drifted"
open(path, "w", encoding="utf-8").write(text.replace(new_block, old_block))
PYEOF
set +e
RED61A_OUT=$(bash "$RED61_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED61A_RC=$?
set -e
[ "$RED61A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the README tree under-enumerates the locale families (got 0 — the CHECK61 R3 arm is toothless)"
sed -n '/=== Check 61:/,$p' <<<"$RED61A_OUT" | grep -qF "README.md - CHECK61 R3: locale/de_DE/" ||
	fail "CHECK61 R3 red must name the omitted de_DE family and README.md (got: $RED61A_OUT)"
sed -n '/=== Check 61:/,$p' <<<"$RED61A_OUT" | grep -qF "CHECK61 R3: locale/pt_BR/" ||
	fail "CHECK61 R3 red must name the omitted pt_BR family (got: $RED61A_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED61A_OUT" | grep -qF "CHECK21: all 7 locale folders mirror en_US" ||
	fail "Check 21 must stay PASS while Check 61 is red (gate independence — it derives the directory, never the docs)"
sed -n '/=== Check 60:/,/=== Check 61:/p' <<<"$RED61A_OUT" | grep -qF "CHECK60: the Project Structure map lists exactly" ||
	fail "Check 60 must stay PASS while Check 61 R3 is red (gate independence — .brs landmarks, disjoint)"
cp "$FAKE_REPO/README.md" "$RED61_ROOT/repo/README.md"
python3 - "$RED61_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "docs", "i18n.md")
text = open(path, encoding="utf-8").read()
new_line = "- **Seven locale families** ship: a single base locale (`en_US`) plus six shipped sibling catalogs (`de_DE`, `es_ES`, `fr_FR`, `it_IT`, `ja_JP`, `pt_BR`) — Check 21 pins every catalog to the base key-for-key, Check 61 pins this total and every docs enumeration to the `locale/` directory itself"
old_line = "- Single base locale (`en_US`) plus six shipped sibling catalogs (`de_DE`, `es_ES`, `fr_FR`, `it_IT`, `ja_JP`, `pt_BR`)"
assert text.count(new_line) == 1, "CHECK61 plant P2: the i18n.md Overview headline shape drifted"
open(path, "w", encoding="utf-8").write(text.replace(new_line, old_line))
PYEOF
set +e
RED61B_OUT=$(bash "$RED61_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED61B_RC=$?
set -e
[ "$RED61B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the family-total sentence is reverted to the bare sibling count (got 0 — the CHECK61 R1 arm is toothless)"
sed -n '/=== Check 61:/,$p' <<<"$RED61B_OUT" | grep -qF "docs/i18n.md - CHECK61 R1" ||
	fail "CHECK61 R1 red must convict the bare-count headline naming docs/i18n.md (got: $RED61B_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED61B_OUT" | grep -qF "CHECK21: all 7 locale folders mirror en_US" ||
	fail "Check 21 must stay PASS while Check 61 R1 is red (gate independence)"
sed -n '/=== Check 60:/,/=== Check 61:/p' <<<"$RED61B_OUT" | grep -qF "CHECK60: the Project Structure map lists exactly" ||
	fail "Check 60 must stay PASS while Check 61 R1 is red (gate independence)"
cp "$FAKE_REPO/docs/i18n.md" "$RED61_ROOT/repo/docs/i18n.md"
python3 - "$RED61_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "docs", "i18n.md")
lines = open(path, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "pt_BR/strings.json" in l and "──" in l]
assert len(hit) == 1, "CHECK61 plant P3: the Directory-Structure pt_BR row shape drifted"
del lines[hit[0]]
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED61C_OUT=$(bash "$RED61_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED61C_RC=$?
set -e
[ "$RED61C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the i18n.md tree omits a shipped family (got 0 — the CHECK61 R2 arm is toothless)"
sed -n '/=== Check 61:/,$p' <<<"$RED61C_OUT" | grep -qF "CHECK61 R2: locale/pt_BR/ ships but the Directory-Structure tree omits it" ||
	fail "CHECK61 R2 red must name the omitted pt_BR family (got: $RED61C_OUT)"
cp "$FAKE_REPO/docs/i18n.md" "$RED61_ROOT/repo/docs/i18n.md"
python3 - "$RED61_ROOT/repo" <<'PYEOF'
import json, sys, os
path = os.path.join(sys.argv[1], "locale", "ja_JP", "strings.json")
catalog = json.load(open(path, encoding="utf-8"))
assert catalog["_metadata"]["locale"] == "ja_JP", "CHECK61 plant P4: the ja_JP folder identity drifted"
catalog["_metadata"]["locale"] = "de_DE"
with open(path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")
PYEOF
set +e
RED61D_OUT=$(bash "$RED61_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED61D_RC=$?
set -e
[ "$RED61D_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a catalog misnames its own family (got 0 — the CHECK61 R4 arm is toothless)"
sed -n '/=== Check 61:/,$p' <<<"$RED61D_OUT" | grep -qF "CHECK61 R4: _metadata.locale is 'de_DE' but the directory is" ||
	fail "CHECK61 R4 red must name the mislabeled folder (got: $RED61D_OUT)"
cp "$FAKE_REPO/locale/ja_JP/strings.json" "$RED61_ROOT/repo/locale/ja_JP/strings.json"
set +e
GREEN61_OUT=$(bash "$RED61_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN61_RC=$?
set -e
[ "$GREEN61_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all four CHECK61 plants are removed (got $GREEN61_RC)"
assert_contains "CHECK61: the family set is the directory" "$GREEN61_OUT"

# --- CHECK54 plant (M-ROKU-22 residual): three DELETION/NEUTRALIZATION shapes
# that no sibling conviction arm owns — the hub choke bypassed in
# ToggleSyncPanel, the scoped ws-only heading truncated away, and the
# vanished-history pointer re-grown in the PROTO §5 citation — must fire
# exactly CHECK54 R1/R2/R3 naming each plant, while CHECK46 (origin choke +
# accept proof + the misclaim regexes: none sees a bypassed hub arm, a
# SHORTER heading or a pointer sentence), CHECK48 (Connect() consent gate +
# write-site census) and CHECK53 (PersistAndGo custody) stay green (gate
# independence). Full restore returns exit 0 (falsifiability). The composition
# itself — a live dial offering the bearer subprotocol over roStreamSocket —
# needs device nodes, so this static leg is the gate (CHECK50/51/52/53
# precedent, device honesty disclosed in the fixlog).
RED54_ROOT="$TEST_ROOT/red54"
mkdir -p "$RED54_ROOT"
cp -a "$TEST_ROOT/repo" "$RED54_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED54_ROOT/phlix-server"
python3 - "$RED54_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
scene = os.path.join(repo, "components/PlayerScene.brs")
text = open(scene, encoding="utf-8").read()
needle = 'if GetConnectionKind() = "hub" then'
assert text.count(needle) == 1, "CHECK54 plant: the hub-choke needle drifted"
text = text.replace(needle, 'if false then', 1)
open(scene, "w", encoding="utf-8").write(text)
readme = os.path.join(repo, "README.md")
text = open(readme, encoding="utf-8").read()
needle = "**`ws://` only — this build ships no `wss://` path.**"
assert text.count(needle) == 1, "CHECK54 plant: the scoped heading drifted"
text = text.replace(needle, "**`ws://` only.**", 1)
open(readme, "w", encoding="utf-8").write(text)
proto = os.path.join(repo, "source/lib/SyncPlayProtocol.brs")
text = open(proto, encoding="utf-8").read()
needle = "Implements @phlix/syncplay SPEC §5 exactly."
assert text.count(needle) == 1, "CHECK54 plant: the SPEC citation drifted"
text = text.replace(needle, "Implements @phlix/syncplay SPEC §5 / worklog §1f exactly.", 1)
open(proto, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED54_OUT=$(bash "$RED54_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED54_RC=$?
set -e
[ "$RED54_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the three M22 residual defects are re-planted (got 0 — the CHECK54 guard is toothless)"
sed -n '/=== Check 54:/,$p' <<<"$RED54_OUT" | grep -qF $'\'GetConnectionKind() = "hub"\' missing' ||
	fail "CHECK54 red must name the bypassed hub choke in ToggleSyncPanel (got: $RED54_OUT)"
sed -n '/=== Check 54:/,$p' <<<"$RED54_OUT" | grep -qF 'README.md - CHECK54' ||
	fail "CHECK54 red must name the truncated scoped heading in README.md (got: $RED54_OUT)"
sed -n '/=== Check 54:/,$p' <<<"$RED54_OUT" | grep -qF 'source/lib/SyncPlayProtocol.brs - CHECK54 R3' ||
	fail "CHECK54 red must convict the re-grown vanished-history pointer in the PROTO citation (got: $RED54_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED54_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 54 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED54_OUT" | grep -qF "CHECK48: credentialed sends decide redirects themselves" ||
	fail "Check 48 must stay PASS while Check 54 is red (gate independence)"
sed -n '/=== Check 53:/,/=== Check 54:/p' <<<"$RED54_OUT" | grep -qF "CHECK53: the one server_url write-site wipes" ||
	fail "Check 53 must stay PASS while Check 54 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED54_ROOT/repo/components/PlayerScene.brs"
cp "$FAKE_REPO/README.md" "$RED54_ROOT/repo/README.md"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED54_ROOT/repo/source/lib/SyncPlayProtocol.brs"
set +e
GREEN54_OUT=$(bash "$RED54_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN54_RC=$?
set -e
[ "$GREEN54_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the three planted defects are removed (got $GREEN54_RC)"
assert_contains "CHECK54: the SyncPlayTask dial composes" "$GREEN54_OUT"

# --- Check 56 red proof + restore on an independent scratch copy: the dead
# SyncPlay room docs-truth law (M-ROKU-26). Two plants, one per direction of
# the pin: (a) re-growing the room wiring — a
# CreateObject("roSGNode", "SyncPlayScene") site in a scratch PlayerScene.brs —
# must fire CHECK56 R1 naming the file (the silent-wiring arm the review's
# day-waster reader-harm needs); (b) stripping the README manager tree row's
# DEAD PATH demotion must fire CHECK56 R2 naming README.md twice (the manager
# marker lost AND the same row naming components/SyncPlayScene unmarked) — the
# exact live-tense era-prose revert. CHECK46 and CHECK54 (the sibling SyncPlay
# gates) stay green (gate independence); full restore returns exit 0
# (falsifiability, house planted-red tradition). --
RED56_ROOT="$TEST_ROOT/red56"
mkdir -p "$RED56_ROOT"
cp -a "$TEST_ROOT/repo" "$RED56_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED56_ROOT/phlix-server"
python3 - "$RED56_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
scene = os.path.join(repo, "components/PlayerScene.brs")
text = open(scene, encoding="utf-8").read()
plant = (
    "\nsub M26PlantedRoomWiring()\n"
    '    m.room = CreateObject("roSGNode", "SyncPlayScene")\n'
    "end sub\n"
)
open(scene, "w", encoding="utf-8").write(text + plant)
readme = os.path.join(repo, "README.md")
text = open(readme, encoding="utf-8").read()
needle = "SyncPlay DEAD PATH — not wired into the shipped UI:"
assert text.count(needle) == 1, "CHECK56 plant: the README manager-row marker drifted"
text = text.replace(needle, "SyncPlay:", 1)
open(readme, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED56_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED56_RC=$?
set -e
[ "$RED56_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the room scene is re-wired and the README demotion stripped (got 0 — the CHECK56 guard is toothless)"
sed -n '/=== Check 56:/,$p' <<<"$RED56_OUT" | grep -qF 'components/PlayerScene.brs - CHECK56 R1' ||
	fail "CHECK56 red must name the planted room-scene instantiation site (got: $RED56_OUT)"
sed -n '/=== Check 56:/,$p' <<<"$RED56_OUT" | grep -qF "README.md - CHECK56 R2" ||
	fail "CHECK56 red must convict the stripped README manager-row demotion (got: $RED56_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED56_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 56 is red (gate independence)"
sed -n '/=== Check 54:/,/=== Check 56:/p' <<<"$RED56_OUT" | grep -qF "CHECK54: the SyncPlayTask dial composes" ||
	fail "Check 54 must stay PASS while Check 56 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED56_ROOT/repo/components/PlayerScene.brs"
cp "$FAKE_REPO/README.md" "$RED56_ROOT/repo/README.md"
set +e
GREEN55_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN55_RC=$?
set -e
[ "$GREEN55_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK56 plants are removed (got $GREEN55_RC)"
assert_contains "CHECK56: the SyncPlay room scene has zero instantiation sites" "$GREEN55_OUT"

# --- r2 cure (review M-ROKU-26 r1 MAJOR-1): the i18n.md surface gets REAL positive
# teeth and one plant-and-restore per convicted shape, on the same restored
# scratch tree. The r1 arm was conditional-shape only — BOTH r1-measured vacuous
# passes are now plants: (c) V1 deletes the `syncplay` consumer row outright (the
# positive survive-delete arm must convict a deletion, not just an annotation
# strip); (d) V2 rewrites the row live-tense with the components/ prefix and the
# `**not instantiated**` annotation stripped (the second measured exit-0 shape);
# (e) the r1 MINOR-1 survivor — stripping the `errors` row's new dead marker must
# fire the general consumer-table dead-marker law. Each plant exits non-zero
# naming docs/i18n.md under CHECK56 with the sibling SyncPlay gates (CHECK46/54)
# green, each restore returns exit 0 (falsifiability, house planted-red tradition). --
RED56B_OUT=""
RED56C_OUT=""
RED56D_OUT=""

python3 - "$RED56_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "docs/i18n.md")
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
idx = [i for i, l in enumerate(lines) if l.startswith("| `syncplay`")]
assert len(idx) == 1, "CHECK56 r2 plant V1: the syncplay consumer row drifted"
del lines[idx[0]]
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED56B_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED56B_RC=$?
set -e
[ "$RED56B_RC" -ne 0 ] || fail "CHECK56 must exit non-zero when the i18n.md syncplay consumer row is deleted (got 0 — the r1 V1 vacuous pass is back)"
sed -n '/=== Check 56:/,$p' <<<"$RED56B_OUT" | grep -qF 'docs/i18n.md - CHECK56 R2: the `syncplay` consumer-table row vanished entirely' ||
	fail "CHECK56 V1 red must convict the deleted syncplay row by name (got: $RED56B_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED56B_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 56 V1 is red (gate independence)"
sed -n '/=== Check 54:/,/=== Check 56:/p' <<<"$RED56B_OUT" | grep -qF "CHECK54: the SyncPlayTask dial composes" ||
	fail "Check 54 must stay PASS while Check 56 V1 is red (gate independence)"
cp "$FAKE_REPO/docs/i18n.md" "$RED56_ROOT/repo/docs/i18n.md"

python3 - "$RED56_ROOT/repo" <<'PYEOF'
import re, sys, os
path = os.path.join(sys.argv[1], "docs/i18n.md")
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
idx = [i for i, l in enumerate(lines) if l.startswith("| `syncplay`")]
assert len(idx) == 1, "CHECK56 r2 plant V2: the syncplay consumer row drifted"
new = re.sub(r"\(\*\*not instantiated\*\*[^)]*\)", "(live room UI)", lines[idx[0]])
assert new != lines[idx[0]], "CHECK56 r2 plant V2: the annotation shape drifted"
new = new.replace("components/SyncPlayScene.brs", "SyncPlayScene.brs")
assert "components/SyncPlayScene" not in new, "CHECK56 r2 plant V2: prefix strip failed"
lines[idx[0]] = new
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED56C_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED56C_RC=$?
set -e
[ "$RED56C_RC" -ne 0 ] || fail "CHECK56 must exit non-zero when the i18n.md syncplay row is rewritten live-tense without prefix or annotation (got 0 — the r1 V2 vacuous pass is back)"
sed -n '/=== Check 56:/,$p' <<<"$RED56C_OUT" | grep -qF "CHECK56: '**not instantiated**' missing" ||
	fail "CHECK56 V2 red must convict the rewritten row's lost annotation (got: $RED56C_OUT)"
sed -n '/=== Check 56:/,$p' <<<"$RED56C_OUT" | grep -qF "names SyncPlayScene.brs without a dead marker" ||
	fail "CHECK56 V2 red must also fire the consumer-table dead-marker law (got: $RED56C_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED56C_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 56 V2 is red (gate independence)"
sed -n '/=== Check 54:/,/=== Check 56:/p' <<<"$RED56C_OUT" | grep -qF "CHECK54: the SyncPlayTask dial composes" ||
	fail "Check 54 must stay PASS while Check 56 V2 is red (gate independence)"
cp "$FAKE_REPO/docs/i18n.md" "$RED56_ROOT/repo/docs/i18n.md"

python3 - "$RED56_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "docs/i18n.md")
text = open(path, encoding="utf-8").read()
lines = text.split("\n")
idx = [i for i, l in enumerate(lines) if l.startswith("| `errors`")]
assert len(idx) == 1, "CHECK56 r2 plant E: the errors consumer row drifted"
assert lines[idx[0]].count("**not instantiated**") == 1, "CHECK56 r2 plant E: the errors-row dead marker drifted"
assert "SyncPlayScene.brs" in lines[idx[0]], "CHECK56 r2 plant E: the errors row must name the scene to convict"
lines[idx[0]] = lines[idx[0]].replace("**not instantiated**", "LIVE")
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED56D_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED56D_RC=$?
set -e
[ "$RED56D_RC" -ne 0 ] || fail "CHECK56 must exit non-zero when the errors-row dead marker is stripped (got 0 — the r1 MINOR-1 survivor could decay silently again)"
sed -n '/=== Check 56:/,$p' <<<"$RED56D_OUT" | grep -qF "names SyncPlayScene.brs without a dead marker" ||
	fail "CHECK56 errors-row red must fire the consumer-table dead-marker law (got: $RED56D_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED56D_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial" ||
	fail "Check 46 must stay PASS while Check 56 errors-row plant is red (gate independence)"
sed -n '/=== Check 54:/,/=== Check 56:/p' <<<"$RED56D_OUT" | grep -qF "CHECK54: the SyncPlayTask dial composes" ||
	fail "Check 54 must stay PASS while Check 56 errors-row plant is red (gate independence)"
cp "$FAKE_REPO/docs/i18n.md" "$RED56_ROOT/repo/docs/i18n.md"
set +e
GREEN56_R2_OUT=$(bash "$RED56_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN56_R2_RC=$?
set -e
[ "$GREEN56_R2_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all three i18n.md plants are removed (got $GREEN56_R2_RC)"
assert_contains "CHECK56: the SyncPlay room scene has zero instantiation sites" "$GREEN56_R2_OUT"

# --- CHECK58 plant (M-ROKU-21f, review roku__gameux M21 r2 MINOR-1): the retry
# recovery-chrome law on an independent scratch copy (CHECK56 scaffolding
# precedent). P1 reverts the stand-down guard to recognizing ONLY the failure
# copy — the review-named defect re-grown; CHECK58 R1 fires naming
# components/HomeScene.brs. P2 (on the restored tree) re-grows a SECOND
# description-strip common_loading write-site in ShowHomeRailFailure — the
# sole-writer fact R1's safety rests on is falsified; CHECK58 R2's census
# convicts the 2x. CHECK52 (same M21 family, deliberately guard-agnostic) and
# CHECK56 stay PASS in both reds (gate independence); full restore returns
# exit 0 (falsifiability, house planted-red tradition). --
RED58_ROOT="$TEST_ROOT/red58"
mkdir -p "$RED58_ROOT"
cp -a "$TEST_ROOT/repo" "$RED58_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED58_ROOT/phlix-server"
python3 - "$RED58_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "components/HomeScene.brs")
text = open(path, encoding="utf-8").read()
needle = 'if strip = Translate("home_rail_failed") or strip = Translate("common_loading") then'
assert text.count(needle) == 1, "CHECK58 plant P1: the stand-down guard shape drifted"
text = text.replace(needle, 'if strip = Translate("home_rail_failed") then', 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED58A_OUT=$(bash "$RED58_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED58A_RC=$?
set -e
[ "$RED58A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the stand-down guard is reverted to failure-copy-only (got 0 — the CHECK58 guard is toothless)"
sed -n '/=== Check 58:/,$p' <<<"$RED58A_OUT" | grep -qF 'components/HomeScene.brs - CHECK58 R1' ||
	fail "CHECK58 red must convict the reverted guard naming components/HomeScene.brs (got: $RED58A_OUT)"
sed -n '/=== Check 58:/,$p' <<<"$RED58A_OUT" | grep -qF "review M21 r2 MINOR-1 re-grown" ||
	fail "CHECK58 red must name the stranded-loading defect it convicted (got: $RED58A_OUT)"
sed -n '/=== Check 52:/,/=== Check 53:/p' <<<"$RED58A_OUT" | grep -qF 'CHECK52: a failed read yields invalid' ||
	fail "Check 52 must stay PASS while Check 58 is red (gate independence — same M21 family, disjoint arms)"
sed -n '/=== Check 56:/,$p' <<<"$RED58A_OUT" | grep -qF "CHECK56: the SyncPlay room scene has zero instantiation sites" ||
	fail "Check 56 must stay PASS while Check 58 is red (gate independence)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED58_ROOT/repo/components/HomeScene.brs"
python3 - "$RED58_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "components/HomeScene.brs")
text = open(path, encoding="utf-8").read()
needle = 'if m.descriptionLabel <> invalid then m.descriptionLabel.text = Translate("home_rail_failed")'
assert text.count(needle) == 1, "CHECK58 plant P2: the ShowHomeRailFailure write-site shape drifted"
text = text.replace(needle, needle + '\n    m.descriptionLabel.text = Translate("common_loading")', 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED58B_OUT=$(bash "$RED58_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED58B_RC=$?
set -e
[ "$RED58B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a second description-strip loading writer is planted (got 0 — the CHECK58 R2 sole-writer arm is toothless)"
sed -n '/=== Check 58:/,$p' <<<"$RED58B_OUT" | grep -qF "CHECK58 R2: the description-strip loading copy is written 2x ['components/HomeScene.brs:" ||
	fail "CHECK58 red must convict the second writer naming the 2x census and its write-sites (got: $RED58B_OUT)"
sed -n '/=== Check 52:/,/=== Check 53:/p' <<<"$RED58B_OUT" | grep -qF 'CHECK52: a failed read yields invalid' ||
	fail "Check 52 must stay PASS while Check 58 R2 is red (gate independence)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED58_ROOT/repo/components/HomeScene.brs"
set +e
GREEN58_OUT=$(bash "$RED58_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN58_RC=$?
set -e
[ "$GREEN58_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK58 plants are removed (got $GREEN58_RC)"
assert_contains "CHECK58: the stand-down guard restores the default strip" "$GREEN58_OUT"

# --- CHECK59 plant (M-ROKU-33, review roku__writer): the CHANGELOG release-truth
# law on an independent scratch copy (CHECK58 scaffolding precedent). P1 reverts
# the rolling header to the pre-cure `## [Unreleased]` fiction — verbatim the base
# two-header state the queue convicted and the r1 review found live on master;
# CHECK59 R1 fires naming M-ROKU-33 and R2 convicts the anchorless model block.
# P2 (on the restored CHANGELOG) re-grows the phantom-r3 fabrication class itself:
# a versioned release header `## [v9.9.9] — 2026-12-31` behind zero tags; CHECK59
# R3 convicts the unbacked claim naming the token. CHECK40 (the package.yml +
# publishing.md half of the same vehicle law) and CHECK57 stay PASS in both reds
# (gate independence); full restore returns exit 0 (falsifiability, house
# planted-red tradition). --
RED59_ROOT="$TEST_ROOT/red59"
mkdir -p "$RED59_ROOT"
cp -a "$TEST_ROOT/repo" "$RED59_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED59_ROOT/phlix-server"
python3 - "$RED59_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "CHANGELOG.md")
lines = open(path, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if l.startswith("## [latest]")]
assert len(hit) == 1, "CHECK59 plant P1: the rolling-header shape drifted"
lines[hit[0]] = "## [Unreleased]"
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED59A_OUT=$(bash "$RED59_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED59A_RC=$?
set -e
[ "$RED59A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the [latest] header reverts to the Unreleased fiction (got 0 — the CHECK59 guard is toothless)"
sed -n '/=== Check 59:/,$p' <<<"$RED59A_OUT" | grep -qF 'CHANGELOG.md - CHECK59 R1' ||
	fail "CHECK59 red must convict the reverted header naming CHANGELOG.md (got: $RED59A_OUT)"
sed -n '/=== Check 59:/,$p' <<<"$RED59A_OUT" | grep -qF "CHECK59 R2:" ||
	fail "CHECK59 red must also convict the anchorless release-model block (got: $RED59A_OUT)"
sed -n '/=== Check 40:/,/=== Check 41:/p' <<<"$RED59A_OUT" | grep -qF "CHECK40: derive-version.sh fully reachable" ||
	fail "Check 40 must stay PASS while Check 59 is red (gate independence — same vehicle law, other side)"
sed -n '/=== Check 57:/,/=== Check 58:/p' <<<"$RED59A_OUT" | grep -qF "CHECK57: the co-watch feature speaks with one name" ||
	fail "Check 57 must stay PASS while Check 59 is red (gate independence)"
cp "$FAKE_REPO/CHANGELOG.md" "$RED59_ROOT/repo/CHANGELOG.md"
python3 - "$RED59_ROOT/repo" <<'PYEOF'
import sys, os
path = os.path.join(sys.argv[1], "CHANGELOG.md")
lines = open(path, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if l.startswith("## [R4.10]")]
assert len(hit) == 1, "CHECK59 plant P2: the R4.10 header shape drifted"
lines.insert(hit[0], "## [v9.9.9] — 2026-12-31")
lines.insert(hit[0] + 1, "")
open(path, "w", encoding="utf-8").write("\n".join(lines))
PYEOF
set +e
RED59B_OUT=$(bash "$RED59_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED59B_RC=$?
set -e
[ "$RED59B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a tag-less versioned release header is planted (got 0 — the CHECK59 R3 anti-fabrication arm is toothless)"
sed -n '/=== Check 59:/,$p' <<<"$RED59B_OUT" | grep -qF "CHECK59 R3" ||
	fail "CHECK59 red must convict the phantom versioned header (got: $RED59B_OUT)"
sed -n '/=== Check 59:/,$p' <<<"$RED59B_OUT" | grep -qF "v9.9.9" ||
	fail "CHECK59 R3 red must name the unbacked version token (got: $RED59B_OUT)"
sed -n '/=== Check 40:/,/=== Check 41:/p' <<<"$RED59B_OUT" | grep -qF "CHECK40: derive-version.sh fully reachable" ||
	fail "Check 40 must stay PASS while Check 59 R3 is red (gate independence)"
cp "$FAKE_REPO/CHANGELOG.md" "$RED59_ROOT/repo/CHANGELOG.md"
set +e
GREEN59_OUT=$(bash "$RED59_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN59_RC=$?
set -e
[ "$GREEN59_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK59 plants are removed (got $GREEN59_RC)"
assert_contains "CHECK59: the CHANGELOG names the vehicle that exists" "$GREEN59_OUT"
# --- CHECK62 plant (M-ROKU-31, review roku__writer M7): the README test-inventory +
# dependency-truth law on an independent scratch copy (CHECK56/58/59/60/61 scaffolding
# precedent). The plant re-grows the review-named README state in ONE pass: the era's
# 3-file Test Structure block PLUS a phantom name (SessionManager.test.brs — deleted
# in R7.5 per the M8 family, so R1 convicts it), the stale suite count literal, the
# convicted "No external dependencies required" sentence with the npm ci/devDependencies
# truth stripped, and the born-empty "configurable constants (in source files):"
# lead-in. CHECK62 fires R1 (phantom), R2 (26 shipped suites unlisted), R3 (count 3 !=
# census 29); the R2/R3 figures ride the tests/ census and rotate with every added
# suite (MJ-2 booked the 23→24 era at 21/24; w12L3-R3's DetailSceneYear made the 25th
# unit suite, rotating these to 22/25; w14L1's four routine suites - AdminScanRoutines,
# HomeSceneRoutines, LibrarySceneRoutines, SearchSceneRoutines - made the 26th-29th,
# rotating these to 26/29);
# CHECK52/CHECK56/CHECK58/CHECK60/CHECK61 stay
# PASS (gate independence — the plant touches none of their pinned surfaces: the
# Project-Structure map rows and locale-family rows are untouched); full restore
# returns exit 0 (falsifiability, house planted-red tradition). --
RED62_ROOT="$TEST_ROOT/red62"
mkdir -p "$RED62_ROOT"
cp -a "$TEST_ROOT/repo" "$RED62_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED62_ROOT/phlix-server"
python3 - "$RED62_ROOT/repo" <<'PYEOF'
import re, sys, os
path = os.path.join(sys.argv[1], "README.md")
text = open(path, encoding="utf-8").read()

# P1 the era's stale inventory returns, with one phantom name added
m = re.search(r"(?ms)^### Test Structure.*?```\n(.*?)```\n", text)
assert m, "CHECK62 plant: '### Test Structure' fenced block not found in the cured README"
era_block = """tests/
├── unit/
│   ├── ApiClient.test.brs      # API client unit tests
│   ├── SessionManager.test.brs  # session management unit tests
│   ├── Storage.test.brs         # Storage unit tests
│   └── Utilities.test.brs       # Utilities unit tests
├── integration/
│   └── ApiIntegration.test.brs  # API integration tests
├── fixtures/
│   └── server-route-manifest.json   # vendored phlix-server route manifest (S280)
└── scripts/
    ├── verify-route-manifest.mjs    # make validate-routes
    └── verify-runtime-portable.sh   # verify-runtime.sh portability regression
"""
text = text[: m.start(1)] + era_block + text[m.end(1):]

# P2 the stale count literal
assert "**29 rooibos unit suites**" in text, "CHECK62 plant: cured count literal shape drifted"
text = text.replace("**29 rooibos unit suites**", "**3 rooibos unit suites**", 1)

# P3 the dev-false dependency sentence returns; the npm ci truth leaves the section
dep = re.search(r"(?ms)^### 3\. Install Dependencies\s*\n(.*?)(?=\n#{2,3} )", text)
assert dep, "CHECK62 plant: Install Dependencies section not found"
text = text[: dep.start(1)] + "\nNo external dependencies required. BrightScript is natively supported by Roku devices.\n\n" + text[dep.end(1):]

# P4 the born-empty constants lead-in is re-grown above the Building heading
assert "\n## Building the App\n" in text, "CHECK62 plant: Building anchor shape drifted"
text = text.replace(
    "\n## Building the App\n",
    "\n### BrightScript Configuration\n\nThe app uses these configurable constants (in source files):\n\n\n\n## Building the App\n",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED62_OUT=$(bash "$RED62_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED62_RC=$?
set -e
[ "$RED62_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the review-era README inventories are re-planted (got 0 — the CHECK62 pin is toothless)"
sed -n '/=== Check 62:/,$p' <<<"$RED62_OUT" | grep -qF "CHECK62 R1: the Test Structure block names phantom suites ['SessionManager.test.brs']" ||
	fail "CHECK62 red must convict the phantom suite name naming it (got: $RED62_OUT)"
sed -n '/=== Check 62:/,$p' <<<"$RED62_OUT" | grep -qF "CHECK62 R2: 26 shipped suite(s) are absent" ||
	fail "CHECK62 red must convict the unlisted real suites (got: $RED62_OUT)"
sed -n '/=== Check 62:/,$p' <<<"$RED62_OUT" | grep -qF "CHECK62 R3: the Unit Tests section claims 3 rooibos unit suites" ||
	fail "CHECK62 red must convict the stale count literal against the census (got: $RED62_OUT)"
sed -n '/=== Check 62:/,$p' <<<"$RED62_OUT" | grep -qF 'CHECK62 R4: "No external dependencies required" is back' ||
	fail "CHECK62 red must convict the re-grown dev-false dependency sentence (got: $RED62_OUT)"
sed -n '/=== Check 62:/,$p' <<<"$RED62_OUT" | grep -qF 'CHECK62 R5: the "BrightScript Configuration" empty-section lead-in is re-grown' ||
	fail "CHECK62 red must convict the re-grown empty-section lead-in (got: $RED62_OUT)"
sed -n '/=== Check 52:/,/=== Check 53:/p' <<<"$RED62_OUT" | grep -qF 'CHECK52: a failed read yields invalid' ||
	fail "Check 52 must stay PASS while Check 62 is red (gate independence)"
sed -n '/=== Check 56:/,/=== Check 57:/p' <<<"$RED62_OUT" | grep -qF "CHECK56: the SyncPlay room scene has zero instantiation sites" ||
	fail "Check 56 must stay PASS while Check 62 is red (gate independence — README plant touches only CHECK62 surfaces)"
sed -n '/=== Check 58:/,/=== Check 59:/p' <<<"$RED62_OUT" | grep -qF "CHECK58: the stand-down guard restores the default strip" ||
	fail "Check 58 must stay PASS while Check 62 is red (gate independence)"
sed -n '/=== Check 60:/,/=== Check 61:/p' <<<"$RED62_OUT" | grep -qF 'CHECK60: the Project Structure map lists exactly the 58 shipped .brs' ||
	fail "Check 60 (M-ROKU-32 sibling) must stay PASS while Check 62 is red (gate independence — different README section)"
sed -n '/=== Check 61:/,/=== Check 62:/p' <<<"$RED62_OUT" | grep -qF "CHECK61: the family set is the directory" ||
	fail "Check 61 (M-ROKU-37 sibling) must stay PASS while Check 62 is red (gate independence — locale rows untouched)"
cp "$FAKE_REPO/README.md" "$RED62_ROOT/repo/README.md"
set +e
GREEN62_OUT=$(bash "$RED62_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN62_RC=$?
set -e
[ "$GREEN62_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the CHECK62 README plants are removed (got $GREEN62_RC)"
assert_contains "CHECK62: the Test Structure block and tests/ are set-equal" "$GREEN62_OUT"

# --- CHECK67 plant (R-ROKU-11, review fixlog/M-ROKU-20__r4.md observation N2): locale
# VALUE hygiene. The r4 reviewer re-planted the stripped copula into it_IT at the CURED
# anchor and the whole battery stayed green: "no CI leg guards locale VALUES — my
# re-strip plant sailed through 54 checks green". True, and structural: Check 21 pins
# the key SET and ORDER, Check 48 R3 pins _metadata.version, Check 51 pins player_*
# speakability — none of them reads how a value is SPOKEN. Here all three classes the
# ticket had to be reviewed into existence are re-grown in scratch catalogs (D1 the
# stripped copula it_IT, D2 the misplaced acute es_ES, D3 the pre-reform glyphs and the
# wrong-kanji word in BOTH its cured forms ja_JP — the exact bytes dc362df870 replaced).
# CHECK67 must convict every family by file and value key (measured 12), while
# CHECK21/CHECK48/CHECK51 — the legs that read these SAME files and slept through the
# r4 plant — must stay PASS (gate independence: Check 67 reads values, they read keys,
# versions and code), and restoring every catalog must return exit 0 with CHECK67 green
# (falsifiability).
RED67_ROOT="$TEST_ROOT/red67"
mkdir -p "$RED67_ROOT"
cp -a "$TEST_ROOT/repo" "$RED67_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED67_ROOT/phlix-server"
python3 - "$RED67_ROOT/repo" <<'PYEOF'
import os, sys

repo = sys.argv[1]
# (catalog, cured literal, pre-cure literal) taken byte-exact from
# `git show dc362df870^:locale/<family>/strings.json`. Literal text surgery, not JSON
# re-serialisation: the key set, key order and _metadata stay untouched on purpose, so
# the value-blind sibling legs cannot notice the plant and the red is Check 67's alone.
PLANT = (
    ("locale/it_IT/strings.json",
     '"err_session_expired": "La tua sessione è scaduta.',
     '"err_session_expired": "La tua sessione e scaduta.'),
    ("locale/es_ES/strings.json",
     "Inténtalo de nuevo durante las horas permitidas",
     "Intentélo de nuevo durante las horas permitidas"),
    ("locale/ja_JP/strings.json",
     "停止して視聴を続けてください",
     "停止して視聽を継けてください"),
    ("locale/ja_JP/strings.json",
     "進捗の保存を続けるには",
     "進捗の保存を継けるには"),
    ("locale/ja_JP/strings.json",
     "許可された時間帯にもう一度",
     "許可された時間帶にもう一度"),
)
for rel, cured, old in PLANT:
    path = os.path.join(repo, rel)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    assert text.count(cured) == 1, "CHECK67 plant: %s cured literal shape drifted (%r)" % (rel, cured)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text.replace(cured, old, 1))
PYEOF
set +e
RED67_OUT=$(bash "$RED67_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED67_RC=$?
set -e
[ "$RED67_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the three M-ROKU-20 value classes are re-planted into the catalogs (got 0 — the CHECK67 value gate is toothless)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/it_IT/strings.json - CHECK67 R1: the phrase [e scaduta. Accedi]' ||
	fail "CHECK67 red must convict D1 AUTOMATICALLY: a stripped copula has to surface as a phrase one catalog spells two ways, naming login.expired_message as the witness (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/it_IT/strings.json - CHECK67: [sessione e scaduta] is back' ||
	fail "CHECK67 red must convict D1 through the curated it row too — R1 needs a surviving witness, the row is what holds the law after a reword (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/es_ES/strings.json - CHECK67: [Intentélo] is back' ||
	fail "CHECK67 red must convict D2, the misplaced accent R1 structurally cannot see (moving the mark moves a letter of the skeleton) (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/ja_JP/strings.json - CHECK67: [帶] is back' ||
	fail "CHECK67 red must convict D3 on the pre-reform glyph 帶 (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/ja_JP/strings.json - CHECK67: [聽] is back' ||
	fail "CHECK67 red must convict D3 on the pre-reform glyph 聽 (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/ja_JP/strings.json - CHECK67: [継ける] is back' ||
	fail "CHECK67 red must convict D3 on the wrong-kanji 継ける (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'locale/ja_JP/strings.json - CHECK67: [継けて] is back' ||
	fail "CHECK67 red must convict the te-form 継けて independently — without that row a lone 続けて revert stays invisible while 続ける survives in another value (got: $RED67_OUT)"
sed -n '/=== Check 67:/,$p' <<<"$RED67_OUT" | grep -qF 'CHECK67: the canonical family form [時間帯] is gone' ||
	fail "CHECK67 red must convict a ban whose family has left the catalog (canonical-gone), so no row can rot into a vacuous ban (got: $RED67_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED67_OUT" | grep -qF "CHECK21: all 7 locale folders mirror en_US" ||
	fail "Check 21 (same locale files, key-set law) must stay PASS while Check 67 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED67_OUT" | grep -qF "CHECK48: credentialed sends decide redirects themselves" ||
	fail "Check 48 (same locale files, version and catalog-speech law) must stay PASS while Check 67 is red (gate independence)"
sed -n '/=== Check 51:/,/=== Check 52:/p' <<<"$RED67_OUT" | grep -qF "CHECK51: the error-overlay trio, every sync panel status, the party" ||
	fail "Check 51 (same player_* keys, live-copy law) must stay PASS while Check 67 is red (gate independence — the leg r4 slept on is a VALUE leg)"
for family in it_IT es_ES ja_JP; do
	cp "$FAKE_REPO/locale/$family/strings.json" "$RED67_ROOT/repo/locale/$family/strings.json"
done
set +e
GREEN67_OUT=$(bash "$RED67_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN67_RC=$?
set -e
[ "$GREEN67_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after every planted value regression is restored (got $GREEN67_RC)"
assert_contains "CHECK67: locale VALUES are guarded, not only keys" "$GREEN67_OUT"

# --- CHECK68 plant (R-ROKU-24, the named-candidate follow-up recorded by
# fixlog/M-ROKU-04__fix-r2.md Issue 2): credential retention on server_error.
# M-ROKU-04's r2 lane deliberately LIMITED the keep-allowance to transport arms
# ("A keep-on-server_error policy is a candidate follow-up, not silently folded
# in here"); this rider folds it in, so the plant re-grows BOTH regression
# directions in one scratch copy: (A) stripping the two `return false` keeps
# after the server_error assignments — the arms fall through to the wipe tail
# again, the exact pre-rider shape; (B) spreading the keep to the verdict arm —
# an early `return false` after `m.restoreReason = "session_invalid"` would
# strand credentials the server DID pronounce dead. CHECK68 must fire R1 twice
# (naming each fall-through by its successor statement) and R2 once, while
# CHECK36 (PhlixApp's boot ladder), CHECK44 (the restoreSession wire-lift chain
# — WireErrorText/IsTransportReason reads) and CHECK48 (the transport bucket
# set + redirect custody in Utilities/ApiClient send sites) stay green on the
# very file the plants edit (gate independence: they read disjoint arms and
# neighboring files; CHECK53's custody wipe in ConnectScene is untouched);
# restoring returns exit 0 (falsifiability). The runtime behavior itself is
# pinned device-side by tests/unit/ApiClient.test.brs's two new restoreSession
# subs (suite EXCLUDED under brs, hardware-gated rooibos — the CHECK50-53
# statement-presence precedent, disclosed in the fixlog).
RED68_ROOT="$TEST_ROOT/red68"
mkdir -p "$RED68_ROOT"
cp -a "$TEST_ROOT/repo" "$RED68_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED68_ROOT/phlix-server"
python3 - "$RED68_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "source/lib/ApiClient.brs")
text = open(brs, encoding="utf-8").read()
keep = (
    '                    m.restoreReason = "server_error"\n'
    '                    return false\n'
)
assert text.count(keep) == 2, "CHECK68 plant: the two server_error keep-return sites drifted (%d found)" % text.count(keep)
text = text.replace(keep, '                    m.restoreReason = "server_error"\n')
verdict = '                    m.restoreReason = "session_invalid"\n'
assert text.count(verdict) == 1, "CHECK68 plant: the session_invalid arm drifted"
text = text.replace(verdict, verdict + '                    return false\n')
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED68_OUT=$(bash "$RED68_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED68_RC=$?
set -e
[ "$RED68_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the server_error keep-returns are stripped and the verdict arm early-returns (got 0 — the CHECK68 guard is toothless)"
sed -n '/=== Check 68:/,$p' <<<"$RED68_OUT" | grep -qF 'CHECK68 R1: a "server_error" assignment is followed by [else if env <> invalid and env.ok = false and IsTransportReason(transportReason) then]' ||
	fail "CHECK68 red must convict the re-grown shape-arm fall-through naming its successor statement (got: $RED68_OUT)"
sed -n '/=== Check 68:/,$p' <<<"$RED68_OUT" | grep -qF 'CHECK68 R1: a "server_error" assignment is followed by [end if]' ||
	fail "CHECK68 red must convict the re-grown no-verdict-else fall-through at the ladder end (got: $RED68_OUT)"
sed -n '/=== Check 68:/,$p' <<<"$RED68_OUT" | grep -qF 'CHECK68 R2: m.restoreReason = "session_invalid" now early-returns' ||
	fail "CHECK68 red must convict the keep spread to the verdict arm (got: $RED68_OUT)"
sed -n '/=== Check 68:/,$p' <<<"$RED68_OUT" | grep -qF "CHECK68: 3 credential-retention pin(s) broken" ||
	fail "CHECK68 red must report exactly its 3 convictions (got: $RED68_OUT)"
sed -n '/=== Check 36:/,/=== Check 37:/p' <<<"$RED68_OUT" | grep -qF "CHECK36: honesty wired end-to-end" ||
	fail "Check 36 (same taxonomy, consumer side) must stay PASS while Check 68 is red (gate independence)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED68_OUT" | grep -qF "CHECK44: relay mint + handshake map and the SyncPlay dial carry" ||
	fail "Check 44 (same file, wire-lift arms) must stay PASS while Check 68 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED68_OUT" | grep -qF "CHECK48: credentialed sends decide redirects themselves" ||
	fail "Check 48 (same file, send-site custody) must stay PASS while Check 68 is red (gate independence)"
cp "$FAKE_REPO/source/lib/ApiClient.brs" "$RED68_ROOT/repo/source/lib/ApiClient.brs"
set +e
GREEN68_OUT=$(bash "$RED68_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN68_RC=$?
set -e
[ "$GREEN68_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted retention regressions are removed (got $GREEN68_RC)"
assert_contains "CHECK68: every restoreSession failure that carries NO verdict" "$GREEN68_OUT"

# --- CHECK35 R1 plant (R-ROKU-25, the evasion class named by note 3 of
# fixlog/M-ROKU-05__r1.md): the day-1 R1 capture r'\bCanDecodeVideo\(([^)]*)\)'
# stops at the FIRST ')', so a positional call whose first argument closes a
# nested call before the first comma hides every later comma from the test.
# Measured before the cure (log /tmp/opencode/rok25/oldleg-planted.log, and
# reproduced by the takeover lane at /tmp/opencode/rok25-take/tip-4plant.log):
# the first four plants ran the TIP leg with ONE conviction only — the plain
# positional pair — while the nested-close plant, its case-blind lowercase
# twin, and the unterminated list all sailed green. The cured leg is a
# string- and comment-aware balanced walk convicting a TOP-LEVEL comma, with
# EVERY occurrence of the name its own scan target — the walk resumes inside
# each argument list instead of past the whole call, because the takeover
# probe found that a skip-past walk amnesties a positional call BURIED inside
# an otherwise-sanctioned single-argument call's list (dev.CanDecodeVideo(
# Wrap(dev.CanDecodeVideo("x", "y"))) — the fifth plant, which the day-1
# capture convicted only by accident through its truncated outer match). So
# CHECK35 R1 must now fire five times naming file:line and each argument list
# (positional x4 — three top-level, one nested-buried — + unterminated
# fail-loud arm), while CHECK34 (the adjacent
# taxonomy leg) and CHECK42 — which reads this very wrapper file for the
# version single-source law — stay PASS on the plant run (gate independence:
# disjoint arms of the same file), and removing the plants returns exit 0
# (falsifiability). The tightening must also stay AMNESTIC to the legitimate
# shapes it now sees through: a second scratch copy planting ONLY an inline
# options-AA literal (commas inside braces) and a wrapped single argument
# must keep the whole battery green — the conviction is about top-level
# commas, not about parentheses existing.
RED35_ROOT="$TEST_ROOT/red35"
mkdir -p "$RED35_ROOT"
cp -a "$TEST_ROOT/repo" "$RED35_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED35_ROOT/phlix-server"
python3 - "$RED35_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "source/lib/AppContext.brs")
text = open(brs, encoding="utf-8").read()
assert text.rstrip().endswith("end function"), "CHECK35 plant: wrapper tail drifted"
assert "R25Plant" not in text, "CHECK35 plant: plants already present"
open(brs, "w", encoding="utf-8").write(text + '''
function R25PlantA(dev) as Boolean
    return dev.CanDecodeVideo(WrapFormat(dev), "container")
end function

function R25PlantB(dev) as Boolean
    return dev.candecodevideo(WrapFormat(dev), "profile")
end function

function R25PlantC(dev) as Boolean
    return dev.CanDecodeVideo("h264", "mp4")
end function

function R25PlantD(dev) as Boolean
    return dev.CanDecodeVideo("a", "b"
end function

function R25PlantE(dev) as Boolean
    return dev.CanDecodeVideo(Wrap(dev.CanDecodeVideo("x", "y")))
end function
''')
PYEOF
set +e
RED35_OUT=$(bash "$RED35_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED35_RC=$?
set -e
[ "$RED35_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the nested-close-before-comma evasions, the plain positional pair, a positional buried in a sanctioned call's list and an unterminated call are planted (got 0 — the CHECK35 R1 walk is toothless)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'source/lib/AppContext.brs:' ||
	fail "CHECK35 red must name the planted file with its line numbers (got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'CHECK35 R1: positional CanDecodeVideo(WrapFormat(dev), "container")' ||
	fail "CHECK35 red must convict the reviewer-named nested-close evasion by its full argument list (got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'CHECK35 R1: positional CanDecodeVideo(WrapFormat(dev), "profile")' ||
	fail "CHECK35 red must convict the case-blind lowercase twin of the same evasion (got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'CHECK35 R1: positional CanDecodeVideo("h264", "mp4")' ||
	fail "CHECK35 red must keep convicting the plain positional pair the day-1 regex already saw (regression fence, got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'CHECK35 R1: unterminated CanDecodeVideo(' ||
	fail "CHECK35 red must convict the unterminated argument list fail-loud (got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF 'CHECK35 R1: positional CanDecodeVideo("x", "y")' ||
	fail "CHECK35 red must convict the positional call buried inside an otherwise-sanctioned single-argument call's list (the takeover probe; got: $RED35_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED35_OUT" | grep -qF "CHECK35: 5 CanDecodeVideo-shape problem(s)" ||
	fail "CHECK35 red must report exactly its 5 convictions (got: $RED35_OUT)"
sed -n '/=== Check 34:/,/=== Check 35:/p' <<<"$RED35_OUT" | grep -qF "CHECK34: taxonomy triangle closed" ||
	fail "Check 34 (adjacent leg, disjoint files) must stay PASS while Check 35 is red (gate independence)"
sed -n '/=== Check 42:/,/=== Check 43:/p' <<<"$RED35_OUT" | grep -qF "CHECK42: all three ApiClient send sites" ||
	fail "Check 42 (same wrapper file, version single-source arms) must stay PASS while Check 35 is red (gate independence)"
cp "$FAKE_REPO/source/lib/AppContext.brs" "$RED35_ROOT/repo/source/lib/AppContext.brs"
set +e
GREEN35_OUT=$(bash "$RED35_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN35_RC=$?
set -e
[ "$GREEN35_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted positional calls are removed (got $GREEN35_RC)"
assert_contains "CHECK35: options-AA call shape, result-key parse, and three fail-open " "$GREEN35_OUT"

# Sanctioned-shape twin: the walk must NOT over-convict the legitimate forms.
LEGIT35_ROOT="$TEST_ROOT/legit35"
mkdir -p "$LEGIT35_ROOT"
cp -a "$TEST_ROOT/repo" "$LEGIT35_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$LEGIT35_ROOT/phlix-server"
python3 - "$LEGIT35_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "source/lib/AppContext.brs")
text = open(brs, encoding="utf-8").read()
assert "R25Legit" not in text, "CHECK35 sanctioned plant: shapes already present"
open(brs, "w", encoding="utf-8").write(text + '''
function R25LegitA(dev) as Boolean
    result = dev.CanDecodeVideo({"codec": "h264", "container": "mp4"})
    return type(result) = "roAssociativeArray"
end function

function R25LegitB(dev) as Boolean
    return dev.CanDecodeVideo(WrapFormat(dev))
end function
''')
PYEOF
set +e
LEGIT35_OUT=$(bash "$LEGIT35_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
LEGIT35_RC=$?
set -e
[ "$LEGIT35_RC" -eq 0 ] || fail "verify-runtime.sh must stay exit 0 when ONLY sanctioned options-AA shapes are planted — the tightening convicts top-level commas, not parentheses (got $LEGIT35_RC: $LEGIT35_OUT)"
assert_contains "CHECK35: options-AA call shape, result-key parse, and three fail-open " "$LEGIT35_OUT"

# --- CHECK69 plant (R-ROKU-26, the legacy Roku docs URL disclosed out of
# scope by the M-ROKU-05 lane and kept alive by fixlog/M-ROKU-05__r1.md note
# 4): the tree cited Roku's pre-reorg docs path (assembled below from
# adjacent literals — the contiguous prefix must never exist in this file's
# own bytes, SELF-BURN) and R-ROKU-26 rotated all 21 sites to the measured
# 301 targets on developer.roku.com/dev/docs. CHECK69 makes the rotation
# one-way, so the plant tests both directions of decay in ONE scratch copy:
# (A) re-growing the legacy URL at the first citation line of
# source/lib/AppContext.brs — the R1 family ban must convict file:line with
# the cited URL; (B) re-pointing BOTH canonical ifappmanager citations onto
# an unreachable mirror — the R2 carrier-presence arm must convict the lost
# citation (deleting a citation launders documentation). Exactly two
# convictions, no more: the R1 plant leaves eight canonical ifdeviceinfo
# siblings standing (R2 stays satisfied), and mirror URLs are not legacy
# paths (R1 stays silent on plant B). CHECK35 reads the very file plant-A
# edits and stays green (comment-only plants are inert to its code-shape
# walk); CHECK42/CHECK68 read ApiClient.brs and stay green (gate
# independence); restoring returns exit 0 (falsifiability).
RED69_ROOT="$TEST_ROOT/red69"
mkdir -p "$RED69_ROOT"
cp -a "$TEST_ROOT/repo" "$RED69_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED69_ROOT/phlix-server"
python3 - "$RED69_ROOT/repo" <<'PYEOF'
import os, sys
repo = sys.argv[1]
brs = os.path.join(repo, "source/lib/AppContext.brs")
text = open(brs, encoding="utf-8").read()
# Adjacent literals keep this plant's own bytes clean of the banned prefix.
legacy = "https://developer.roku.com/docs/refer" "ences/brightscript/interfaces/ifdeviceinfo.md"
assert legacy not in text, "CHECK69 plant: the legacy prefix is already on the surface it bans"
canon = "https://developer.roku.com/dev/docs/ifdeviceinfo"
assert text.count(canon) >= 2, "CHECK69 plant: the rotated ifdeviceinfo citations drifted"
i = text.index(canon)
text = text[:i] + legacy + text[i + len(canon):]
launched = "https://developer.roku.com/dev/docs/ifappmanager"
assert text.count(launched) == 2, "CHECK69 plant: the two ifappmanager citation sites drifted (%d found)" % text.count(launched)
text = text.replace(launched, "https://roku-docs-mirror.invalid/ifappmanager")
open(brs, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED69_OUT=$(bash "$RED69_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED69_RC=$?
set -e
[ "$RED69_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a legacy Roku doc URL is re-grown and a canonical citation is laundered (got 0 — the CHECK69 guard is toothless)"
sed -n '/=== Check 69:/,$p' <<<"$RED69_OUT" | grep -qE 'source/lib/AppContext\.brs:[0-9]+ - CHECK69 R1: legacy Roku doc URL cited:' ||
	fail "CHECK69 red must convict the re-grown legacy URL at file:line (got: $RED69_OUT)"
sed -n '/=== Check 69:/,$p' <<<"$RED69_OUT" | grep -qF 'CHECK69 R2: the canonical https://developer.roku.com/dev/docs/ifappmanager citation vanished' ||
	fail "CHECK69 red must convict the laundered canonical ifappmanager citation naming the page (got: $RED69_OUT)"
sed -n '/=== Check 69:/,$p' <<<"$RED69_OUT" | grep -qF "CHECK69: 2 Roku-doc-citation pin(s) broken" ||
	fail "CHECK69 red must report exactly its 2 convictions (got: $RED69_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED69_OUT" | grep -qF "CHECK35: options-AA call shape, result-key parse, and three fail-open " ||
	fail "Check 35 (same file, code-shape walk) must stay PASS while Check 69 is red (gate independence)"
sed -n '/=== Check 42:/,/=== Check 43:/p' <<<"$RED69_OUT" | grep -qF "CHECK42: all three ApiClient send sites" ||
	fail "Check 42 (neighboring send-custody legs) must stay PASS while Check 69 is red (gate independence)"
sed -n '/=== Check 68:/,$p' <<<"$RED69_OUT" | grep -qF "CHECK68: every restoreSession failure that carries NO verdict" ||
	fail "Check 68 (credential retention legs) must stay PASS while Check 69 is red (gate independence)"
cp "$FAKE_REPO/source/lib/AppContext.brs" "$RED69_ROOT/repo/source/lib/AppContext.brs"
set +e
GREEN69_OUT=$(bash "$RED69_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN69_RC=$?
set -e
[ "$GREEN69_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the planted citation regressions are removed (got $GREEN69_RC)"
assert_contains "CHECK69: every Roku docs citation on the shipped surface points at" "$GREEN69_OUT"

# --- CHECK70 plants (R-ROKU-05, fixlog/R-ROKU-05__fix.md): the hub-relay
# dial (:8804 command channel carrying the scoped relay token) accepted any
# "HTTP/1.1 101" status line — the M-ROKU-14 fail-closed accept-proof trio
# was wired at the :8097 sibling only and CHECK46 R2 pinned the ordering law
# there only. The cure calls VerifyHandshakeAccept on the relay 101, ordered
# AFTER the status gate and BEFORE the frame accumulator; CHECK70 makes that
# permanent. Three scratch reds, one named conviction each — a stripped
# guard, a shape drift and a trio bypass are different decay directions and
# the leg names which arm fires for which:
#   A  era posture re-grown: the guard line is stripped from the scratch
#      HubCommandTask WaitForConnect — R1 must convict "never verifies";
#   B  ordering drift: the guard swapped ABOVE the HandshakeAccepted status
#      gate — R1 must convict the ordering law and ONLY it (the key is still
#      captured first, the accumulator still fed last);
#   C  bespoke proof re-implanted: a roEVPDigest line inside WaitForConnect
#      — R2 must convict bypassing the unit-tested trio.
# CHECK44 (reads this very file's mint + handshake map) and CHECK46 (the
# sibling dial's own pins) stay green on all three reds — gate independence;
# restoring returns exit 0 with CHECK70 green (falsifiability — and the
# shipped single-line shape passing its own shape-tolerant regex is the
# amnesty measurement).
RED70_ROOT="$TEST_ROOT/red70"
mkdir -p "$RED70_ROOT"
cp -a "$TEST_ROOT/repo" "$RED70_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED70_ROOT/phlix-server"
HCT70="$RED70_ROOT/repo/components/HubCommandTask.brs"
python3 - "$HCT70" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
guard = "    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then return false"
assert text.count(guard) == 1, "CHECK70 plant-A: the relay-site guard anchor drifted (%d found)" % text.count(guard)
text = text.replace(guard + "\n", "", 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED70A_OUT=$(bash "$RED70_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED70A_RC=$?
set -e
[ "$RED70A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the relay-site accept proof is stripped (got 0 — the CHECK70 guard is toothless)"
sed -n '/=== Check 70:/,$p' <<<"$RED70A_OUT" | grep -qF 'CHECK70 R1: WaitForConnect never verifies Sec-WebSocket-Accept' ||
	fail "CHECK70 red-A must convict the re-grown era posture at the relay dial (got: $RED70A_OUT)"
sed -n '/=== Check 70:/,$p' <<<"$RED70A_OUT" | grep -qF "CHECK70: 1 hub-relay accept-proof pin(s) broken" ||
	fail "CHECK70 red-A must report exactly its 1 conviction (got: $RED70A_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED70A_OUT" | grep -qF "CHECK44: relay mint + handshake map and the SyncPlay dial carry" ||
	fail "Check 44 (reads this very file) must stay PASS while Check 70 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED70A_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial BEFORE the JWT is read" ||
	fail "Check 46 (the sibling dial's pins) must stay PASS while Check 70 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$HCT70"
python3 - "$HCT70" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
guard = "    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then return false"
gate = "    if not m.proto.HandshakeAccepted(headerText) then return false"
assert text.count(guard) == 1 and text.count(gate) == 1, "CHECK70 plant-B: anchors drifted"
assert text.index(guard) > text.index(gate), "CHECK70 plant-B: shipped ordering is proof-AFTER-status-gate"
text = text.replace(guard + "\n", "", 1)
text = text.replace(gate, guard + "\n" + gate, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED70B_OUT=$(bash "$RED70_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED70B_RC=$?
set -e
[ "$RED70B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the relay accept proof runs before the status gate (got 0 — the ordering law is toothless)"
sed -n '/=== Check 70:/,$p' <<<"$RED70B_OUT" | grep -qF 'CHECK70 R1: VerifyHandshakeAccept moved BEFORE the HandshakeAccepted status gate' ||
	fail "CHECK70 red-B must convict the ordering drift naming the status gate (got: $RED70B_OUT)"
sed -n '/=== Check 70:/,$p' <<<"$RED70B_OUT" | grep -qF "CHECK70: 1 hub-relay accept-proof pin(s) broken" ||
	fail "CHECK70 red-B must report exactly its 1 conviction (got: $RED70B_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED70B_OUT" | grep -qF "CHECK44: relay mint + handshake map and the SyncPlay dial carry" ||
	fail "Check 44 (reads this very file) must stay PASS while Check 70 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED70B_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial BEFORE the JWT is read" ||
	fail "Check 46 (the sibling dial's pins) must stay PASS while Check 70 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$HCT70"
python3 - "$HCT70" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
guard = "    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then return false"
assert text.count(guard) == 1, "CHECK70 plant-C: the relay-site guard anchor drifted (%d found)" % text.count(guard)
assert "evp = CreateObject(" not in text, "CHECK70 plant-C: the plant anchor is already on the surface"
text = text.replace(guard, "    evp = CreateObject(\"roEVPDigest\")\n" + guard, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED70C_OUT=$(bash "$RED70_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED70C_RC=$?
set -e
[ "$RED70C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the relay dial re-implements the accept proof outside the tested trio (got 0 — the R2 trio-custody arm is toothless)"
sed -n '/=== Check 70:/,$p' <<<"$RED70C_OUT" | grep -qF 'CHECK70 R2: the relay dial carries a bespoke accept computation' ||
	fail "CHECK70 red-C must convict the bespoke roEVPDigest reimplementation naming the trio law (got: $RED70C_OUT)"
sed -n '/=== Check 70:/,$p' <<<"$RED70C_OUT" | grep -qF "CHECK70: 1 hub-relay accept-proof pin(s) broken" ||
	fail "CHECK70 red-C must report exactly its 1 conviction (got: $RED70C_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED70C_OUT" | grep -qF "CHECK44: relay mint + handshake map and the SyncPlay dial carry" ||
	fail "Check 44 (reads this very file) must stay PASS while Check 70 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED70C_OUT" | grep -qF "CHECK46: https origins refuse the plaintext :8097 dial BEFORE the JWT is read" ||
	fail "Check 46 (the sibling dial's pins) must stay PASS while Check 70 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$HCT70"
set +e
GREEN70_OUT=$(bash "$RED70_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN70_RC=$?
set -e
[ "$GREEN70_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the three planted relay-handshake regressions are removed (got $GREEN70_RC)"
assert_contains "CHECK70: the hub-relay dial proves Sec-WebSocket-Accept before any" "$GREEN70_OUT"

# --- CHECK71 plants (R-ROKU-06, fixlog/R-ROKU-06__fix.md): the boot-auth path
# called fabricated Timer methods — an ms-based duration setter at the two
# Start* sites and a bare stop-method at four handlers — while the vendored
# bsc 0.72.5 model (this repo's own lock authority) knows only the fields
# control/duration/fire/repeat, zero methods. The cure rotated all six sites
# to the file's own field idiom; CHECK71 makes that permanent. Three scratch
# reds, differing conviction counts each:
#   A  era setter re-grown at the first start site — R1 names file:line AND
#      R2 convicts the lost shape (a field-name-only "fix" cannot launder
#      the method back without the dual conviction): exactly two;
#   B  bare stop-method re-grown inside OnAuthTimeout — R1 (method) + R3
#      (lost control-field stop): exactly two;
#   C  unit laundering — the ms value moved ONTO the correct field name
#      (duration = 20000) at the second start site: only the boundary-
#      checked R2 arm can see this decay, so R2 ALONE must convict and R1
#      stay silent: exactly one.
# CHECK47 (boot chrome, same file) and CHECK66 (Start*/handler bodies, same
# file) stay green on all three reds — gate independence; restoring returns
# exit 0 with CHECK71 green (falsifiability — and the shipped shapes passing
# their own boundary-checked regexes is the amnesty measurement). Banned
# needles are assembled from adjacent literals (CHECK69 SELF-BURN law) so no
# contiguous banned byte exists in this twin's own bytes either.
RED71_ROOT="$TEST_ROOT/red71"
mkdir -p "$RED71_ROOT"
cp -a "$TEST_ROOT/repo" "$RED71_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED71_ROOT/phlix-server"
APP71="$RED71_ROOT/repo/components/PhlixApp.brs"
python3 - "$APP71" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
dur = "    m.authTimer.duration = 20\n"
fab = "    m.authTimer.Set" + "Duration(20000)\n"
assert dur not in fab and fab not in text, "CHECK71 plant-A: the era setter is already on the surface"
assert text.count(dur) == 2, "CHECK71 plant-A: the two start-site duration anchors drifted (%d found)" % text.count(dur)
i = text.index(dur)
text = text[:i] + fab + text[i + len(dur):]
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED71A_OUT=$(bash "$RED71_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED71A_RC=$?
set -e
[ "$RED71A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the fabricated ms-setter is re-grown (got 0 — the CHECK71 guard is toothless)"
sed -n '/=== Check 71:/,$p' <<<"$RED71A_OUT" | grep -qF "CHECK71 R1: the Timer's fabricated ms-setter is back" ||
	fail "CHECK71 red-A must convict the re-grown setter naming file:line (got: $RED71A_OUT)"
sed -n '/=== Check 71:/,$p' <<<"$RED71A_OUT" | grep -qF "CHECK71 R2: StartAuthCheck carries 0/1 duration" ||
	fail "CHECK71 red-A must ALSO convict the lost start-site shape (method AND field decay together) (got: $RED71A_OUT)"
[ "$(sed -n '/=== Check 71:/,$p' <<<"$RED71A_OUT" | grep -c 'CHECK71 R')" -eq 2 ] ||
	fail "CHECK71 red-A must report exactly its 2 convictions (got: $RED71A_OUT)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED71A_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back (all four bubble to the CHECK31 exit" ||
	fail "Check 47 (same file, boot chrome) must stay PASS while Check 71 is red (gate independence)"
sed -n '/=== Check 66:/,/=== Check 67:/p' <<<"$RED71A_OUT" | grep -qF "CHECK66: both WS handshakes cap their header accumulator, both frame paths" ||
	fail "Check 66 (same file, auth-check attach/detach bodies) must stay PASS while Check 71 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$APP71"
python3 - "$APP71" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
stop = '        m.authTimer.control = "stop"'
era = "        m.authTimer." + "Stop()"
head = text.index("sub OnAuthTimeout()")
tail = text.index("end sub", head)
body = text[head:tail]
assert body.count(stop) == 1, "CHECK71 plant-B: the OnAuthTimeout stop anchor drifted (%d found)" % body.count(stop)
assert era not in text, "CHECK71 plant-B: the era stop-method is already on the surface"
text = text[:head] + body.replace(stop, era, 1) + text[tail:]
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED71B_OUT=$(bash "$RED71_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED71B_RC=$?
set -e
[ "$RED71B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the fabricated stop-method is re-grown at a handler (got 0 — the CHECK71 R1 stop arm is toothless)"
sed -n '/=== Check 71:/,$p' <<<"$RED71B_OUT" | grep -qF 'CHECK71 R1: the fabricated stop-method is back on' ||
	fail "CHECK71 red-B must convict the re-grown stop-method naming file:line (got: $RED71B_OUT)"
sed -n '/=== Check 71:/,$p' <<<"$RED71B_OUT" | grep -qF 'CHECK71 R3: OnAuthTimeout carries 0/1' ||
	fail "CHECK71 red-B must ALSO convict the lost control-field cancel (got: $RED71B_OUT)"
[ "$(sed -n '/=== Check 71:/,$p' <<<"$RED71B_OUT" | grep -c 'CHECK71 R')" -eq 2 ] ||
	fail "CHECK71 red-B must report exactly its 2 convictions (got: $RED71B_OUT)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED71B_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back (all four bubble to the CHECK31 exit" ||
	fail "Check 47 (same file, boot chrome) must stay PASS while Check 71 is red (gate independence)"
sed -n '/=== Check 66:/,/=== Check 67:/p' <<<"$RED71B_OUT" | grep -qF "CHECK66: both WS handshakes cap their header accumulator, both frame paths" ||
	fail "Check 66 (same file, auth-check bodies) must stay PASS while Check 71 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$APP71"
python3 - "$APP71" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
dur = "    m.authTimer.duration = 20\n"
laundered = "    m.authTimer.duration = 20000\n"
assert text.count(dur) == 2, "CHECK71 plant-C: the two start-site duration anchors drifted (%d found)" % text.count(dur)
i = text.rindex(dur)
text = text[:i] + laundered + text[i + len(dur):]
assert "Set" + "Duration" not in text, "CHECK71 plant-C: the plant must stay method-free (unit laundering only)"
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED71C_OUT=$(bash "$RED71_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED71C_RC=$?
set -e
[ "$RED71C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the ms value is laundered onto the correct field name (got 0 — the CHECK71 unit boundary is toothless)"
sed -n '/=== Check 71:/,$p' <<<"$RED71C_OUT" | grep -qF "CHECK71 R2: StartHubAuthCheck carries 0/1 duration" ||
	fail "CHECK71 red-C must convict the unit-laundered ms value at the second start site (got: $RED71C_OUT)"
sed -n '/=== Check 71:/,$p' <<<"$RED71C_OUT" | grep -qF "CHECK71: 1 boot-auth Timer idiom pin(s) broken" ||
	fail "CHECK71 red-C must report exactly its 1 conviction — R1 must stay silent when only the VALUE is wrong (got: $RED71C_OUT)"
sed -n '/=== Check 47:/,/=== Check 48:/p' <<<"$RED71C_OUT" | grep -qF "CHECK47: bootstrap scenes never consume Back (all four bubble to the CHECK31 exit" ||
	fail "Check 47 (same file, boot chrome) must stay PASS while Check 71 is red (gate independence)"
sed -n '/=== Check 66:/,/=== Check 67:/p' <<<"$RED71C_OUT" | grep -qF "CHECK66: both WS handshakes cap their header accumulator, both frame paths" ||
	fail "Check 66 (same file, auth-check bodies) must stay PASS while Check 71 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$APP71"
set +e
GREEN71_OUT=$(bash "$RED71_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN71_RC=$?
set -e
[ "$GREEN71_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the three planted Timer-idiom regressions are removed (got $GREEN71_RC)"
assert_contains "CHECK71: the boot-auth Timer arms through the seconds" "$GREEN71_OUT"

# --- CHECK72 plants (R-ROKU-27, fixlog/R-ROKU-27__report.md): the direct-play
# gate probed a quoted "h264" literal at the call site behind a fabricated
# phantom-conditional comment, asserting a codec no non-admin wire field
# supplies. The cure names the estate's canonical delivery codec through one
# documented accessor (DirectPlayProbeCodec); CHECK72 makes the shape
# one-way. Four scratch reds, differing conviction signatures each:
#   A  the era magic literal re-grown at the gate — the decay has three
#      faces and all three convict together: R1 magic-literal ban, R1
#      shipped-shape 0/1, R1 deviating call — exactly three;
#   B  the accessor value re-pointed (return "hevc") — a silent move of the
#      named bet: only the R2 value arm can see it, R1 stays silent (the
#      shape holds) — exactly one;
#   C  the phantom-conditional sentence re-grown above the gate — comment
#      surface only, inert to R1's code walk: R3 ALONE — exactly one;
#   D  the accessor docblock's Check 72 cure-marker stripped — the
#      rationale decaying toward a second magic constant: R2 marker ALONE
#      — exactly one.
# CHECK35 (the same wrapper file's options-AA law) and CHECK69 (the same two
# files' citation law) stay green on all four reds — gate independence;
# restoring returns exit 0 with CHECK72 green (falsifiability; the shipped
# shapes passing their own regexes is the amnesty measurement). Banned
# fragments are assembled from adjacent literals in the leg (CHECK69
# SELF-BURN law); the plants below build the era shapes from pieces so no
# contiguous banned byte exists in this twin's own bytes either.
RED72_ROOT="$TEST_ROOT/red72"
mkdir -p "$RED72_ROOT"
cp -a "$TEST_ROOT/repo" "$RED72_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED72_ROOT/phlix-server"
PS72="$RED72_ROOT/repo/components/PlayerScene.brs"
CTX72="$RED72_ROOT/repo/source/lib/AppContext.brs"
python3 - "$PS72" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
gate = "DeviceCanDecodeVideo(DirectPlayProbeCodec()" + ", streamFormat, \"\")"
era = "DeviceCanDecodeVideo(" + "\"h264\", streamFormat, \"\")"
assert text.count(gate) == 1, "CHECK72 plant-A: the accessor-shape gate anchor drifted (%d found)" % text.count(gate)
assert era not in text, "CHECK72 plant-A: the era magic-literal call is already on the surface"
text = text.replace(gate, era, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED72A_OUT=$(bash "$RED72_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED72A_RC=$?
set -e
[ "$RED72A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the magic codec literal is re-grown at the gate (got 0 — CHECK72 R1 is toothless)"
sed -n '/=== Check 72:/,$p' <<<"$RED72A_OUT" | grep -qF "CHECK72 R1: a quoted codec literal is back" ||
	fail "CHECK72 red-A must convict the re-grown magic literal naming file:line (got: $RED72A_OUT)"
sed -n '/=== Check 72:/,$p' <<<"$RED72A_OUT" | grep -qF "CHECK72 R1: 0/1 gate calls" ||
	fail "CHECK72 red-A must convict the lost shipped-shape pin (got: $RED72A_OUT)"
sed -n '/=== Check 72:/,$p' <<<"$RED72A_OUT" | grep -qF "CHECK72 R1: a DeviceCanDecodeVideo call" ||
	fail "CHECK72 red-A must convict the deviating call (got: $RED72A_OUT)"
[ "$(sed -n '/=== Check 72:/,$p' <<<"$RED72A_OUT" | grep -c 'CHECK72 R')" -eq 3 ] ||
	fail "CHECK72 red-A must report exactly its 3 convictions (got: $RED72A_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED72A_OUT" | grep -qF "CHECK35: options-AA call shape" ||
	fail "Check 35 (options-AA law, same wrapper) must stay PASS while Check 72 is red (gate independence)"
sed -n '/=== Check 69:/,/=== Check 70:/p' <<<"$RED72A_OUT" | grep -qF "CHECK69: every Roku docs citation on the shipped surface points at" ||
	fail "Check 69 (citation law, same files) must stay PASS while Check 72 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$PS72"
python3 - "$CTX72" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
canon = '    return "h264"'
drifted = '    return "he' + 'vc"'
assert text.count(canon) == 1, "CHECK72 plant-B: the canonical return anchor drifted (%d found)" % text.count(canon)
text = text.replace(canon, drifted, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED72B_OUT=$(bash "$RED72_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED72B_RC=$?
set -e
[ "$RED72B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the accessor value is silently moved (got 0 — CHECK72 R2's value arm is toothless)"
sed -n '/=== Check 72:/,$p' <<<"$RED72B_OUT" | grep -qF "CHECK72 R2: the accessor's body is" ||
	fail "CHECK72 red-B must convict the re-pointed canonical value (got: $RED72B_OUT)"
[ "$(sed -n '/=== Check 72:/,$p' <<<"$RED72B_OUT" | grep -c 'CHECK72 R')" -eq 1 ] ||
	fail "CHECK72 red-B must report exactly its 1 conviction — the shape holds, only the value moved (got: $RED72B_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED72B_OUT" | grep -qF "CHECK35: options-AA call shape" ||
	fail "Check 35 (same edited file) must stay PASS while Check 72 is red (gate independence)"
sed -n '/=== Check 69:/,/=== Check 70:/p' <<<"$RED72B_OUT" | grep -qF "CHECK69: every Roku docs citation on the shipped surface points at" ||
	fail "Check 69 (same edited file) must stay PASS while Check 72 is red (gate independence)"
cp "$FAKE_REPO/source/lib/AppContext.brs" "$CTX72"
python3 - "$PS72" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = "    ' The probe codec is the estate"
era = "    ' Def" + "ault codec to \"h264\" (most common) if not spe" + "cified; empty profile = \"any\".\n    ' named by DirectPlayProbeCodec (the rationale docblock owns it)\n"
assert text.count(anchor) == 1, "CHECK72 plant-C: the rationale-comment anchor drifted (%d found)" % text.count(anchor)
i = text.index(anchor)
j = text.index("\n", i) + 1  # consume the full anchor line; next line keeps the sentence readable
text = text[:i] + era + text[j:]
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED72C_OUT=$(bash "$RED72_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED72C_RC=$?
set -e
[ "$RED72C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the phantom-conditional comment is re-grown (got 0 — CHECK72 R3 is toothless)"
sed -n '/=== Check 72:/,$p' <<<"$RED72C_OUT" | grep -qF "CHECK72 R3: the fabricated phantom-conditional codec" ||
	fail "CHECK72 red-C must convict the re-grown phantom sentence naming file:line (got: $RED72C_OUT)"
[ "$(sed -n '/=== Check 72:/,$p' <<<"$RED72C_OUT" | grep -c 'CHECK72 R')" -eq 1 ] ||
	fail "CHECK72 red-C must report exactly its 1 conviction — a comment-only plant is inert to the code walk (got: $RED72C_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED72C_OUT" | grep -qF "CHECK35: options-AA call shape" ||
	fail "Check 35 must stay PASS while Check 72 is red (gate independence)"
sed -n '/=== Check 69:/,/=== Check 70:/p' <<<"$RED72C_OUT" | grep -qF "CHECK69: every Roku docs citation on the shipped surface points at" ||
	fail "Check 69 (the sibling comment law over the same file) must stay PASS while Check 72 is red — the plant is not a citation decay (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$PS72"
python3 - "$CTX72" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
marker = "one leg (" + "Check 72)"
assert text.count(marker) == 1, "CHECK72 plant-D: the docblock cure-marker anchor drifted (%d found)" % text.count(marker)
text = text.replace(marker, "one leg", 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED72D_OUT=$(bash "$RED72_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED72D_RC=$?
set -e
[ "$RED72D_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the accessor's cure marker is stripped (got 0 — CHECK72 R2's marker arm is toothless)"
sed -n '/=== Check 72:/,$p' <<<"$RED72D_OUT" | grep -qF 'lost its rationale marker "Check 72"' ||
	fail "CHECK72 red-D must convict the vanished Check 72 marker by name (got: $RED72D_OUT)"
[ "$(sed -n '/=== Check 72:/,$p' <<<"$RED72D_OUT" | grep -c 'CHECK72 R')" -eq 1 ] ||
	fail "CHECK72 red-D must report exactly its 1 conviction (got: $RED72D_OUT)"
sed -n '/=== Check 35:/,/=== Check 36:/p' <<<"$RED72D_OUT" | grep -qF "CHECK35: options-AA call shape" ||
	fail "Check 35 (same edited file) must stay PASS while Check 72 is red (gate independence)"
sed -n '/=== Check 69:/,/=== Check 70:/p' <<<"$RED72D_OUT" | grep -qF "CHECK69: every Roku docs citation on the shipped surface points at" ||
	fail "Check 69 (same edited file) must stay PASS while Check 72 is red (gate independence)"
cp "$FAKE_REPO/source/lib/AppContext.brs" "$CTX72"
set +e
GREEN72_OUT=$(bash "$RED72_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN72_RC=$?
set -e
[ "$GREEN72_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the four planted codec-probe regressions are removed (got $GREEN72_RC)"
assert_contains "CHECK72: the direct-play gate probes the named canonical delivery codec" "$GREEN72_OUT"

# --- CHECK73 plants (R-ROKU-29, fixlog/W-rW29roku__report.md): the twin's own
# PASS narration and the ledger's Regression-test sentence must state exactly
# the header-pin set the CI-layout positive run executes. CHECK73 DERIVES
# that set from this file's own assert inventory (the seq loop paired with
# its body pin + the individual literal header pins over $POSITIVE_OUT) and
# pins equality on both prose surfaces — the era drift the review named (a
# summary that quietly stopped matching the run, disclosed by
# fixlog/M-ROKU-04__fix-r2.md as pre-existing prose staleness predating the
# later legs) can neither re-grow nor newly arrive. Four scratch reds,
# differing conviction signatures each:
#   A  the era stale under-report re-grown in this file's PASS echo — the
#      narration lags the pins: R1 ALONE, exactly one;
#   B  an over-report claiming a pin the positive run never asserts — the
#      narration outruns the pins: R1 ALONE again, exactly one (equality is
#      bidirectional — the claim may neither lag the pins nor outrun them);
#   C  the ledger sentence reverted to the era range — the twin's own echo
#      holds the truth while docs/static-checks.md lags: R2 ALONE, exactly
#      one (the checks-doc pass rides the leg);
#   D  ledger row 73 deleted — the ledger may not under-claim the shipped
#      law (CHECK44 R5 / CHECK71 R4 / CHECK72 R4 precedent): R3 ALONE,
#      exactly one.
# CHECK71 and CHECK72 — the era-neighbor legs whose plant sections bound this
# block — stay green on all four reds: gate independence, this leg reads
# narration prose and ledger rows only, no shipped-code surface. Restoring
# returns exit 0 with CHECK73 green — the twin's prose matching the set
# derived from its own asserts is the amnesty measurement (and the derivation
# is self-pinning: a future header assert added without rotating BOTH prose
# surfaces reddens CI, exactly the drift class R-ROKU-29 names).
RED73_ROOT="$TEST_ROOT/red73"
mkdir -p "$RED73_ROOT"
cp -a "$TEST_ROOT/repo" "$RED73_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED73_ROOT/phlix-server"
TWIN73="$RED73_ROOT/repo/tests/scripts/verify-runtime-portable.sh"
DOC73="$RED73_ROOT/repo/docs/static-checks.md"
python3 - "$TWIN73" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
idx = [n for n, l in enumerate(lines) if l.startswith('echo "PASS: verify-runtime.sh is portable')]
assert len(idx) == 1, "CHECK73 plant-A: PASS-echo anchor count drifted (%d found)" % len(idx)
cured = "11-26 + 35 + 37-41 + 43-61"
era = "11-26 + 37-39"
line = lines[idx[0]]
assert line.count(cured) == 1, "CHECK73 plant-A: the cured-range anchor drifted in the echo (%d found)" % line.count(cured)
assert era not in line, "CHECK73 plant-A: the era under-report is already on the surface"
lines[idx[0]] = line.replace(cured, era, 1)
open(path, "w", encoding="utf-8").write("".join(lines))
PYEOF
set +e
RED73A_OUT=$(bash "$RED73_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED73A_RC=$?
set -e
[ "$RED73A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the twin's PASS narration lags its own header pins (got 0 — CHECK73 R1 is toothless)"
sed -n '/=== Check 73:/,$p' <<<"$RED73A_OUT" | grep -qF 'CHECK73 R1: the PASS narration claims "11-26 + 37-39"' ||
	fail "CHECK73 red-A must convict the re-grown era under-report quoting both sides of the drift (got: $RED73A_OUT)"
[ "$(sed -n '/=== Check 73:/,$p' <<<"$RED73A_OUT" | grep -c 'CHECK73 R')" -eq 1 ] ||
	fail "CHECK73 red-A must report exactly its 1 conviction — the pins and the ledger sentence still agree with each other (got: $RED73A_OUT)"
sed -n '/=== Check 71:/,/=== Check 72:/p' <<<"$RED73A_OUT" | grep -qF 'CHECK71: the boot-auth Timer arms through the seconds' ||
	fail "Check 71 (era-neighbor leg) must stay PASS while Check 73 is red (gate independence)"
sed -n '/=== Check 72:/,/=== Check 73:/p' <<<"$RED73A_OUT" | grep -qF "CHECK72: the direct-play gate probes the named canonical delivery codec" ||
	fail "Check 72 (era-neighbor leg) must stay PASS while Check 73 is red (gate independence)"
cp "$FAKE_REPO/tests/scripts/verify-runtime-portable.sh" "$TWIN73"
python3 - "$TWIN73" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
idx = [n for n, l in enumerate(lines) if l.startswith('echo "PASS: verify-runtime.sh is portable')]
assert len(idx) == 1, "CHECK73 plant-B: PASS-echo anchor count drifted (%d found)" % len(idx)
cured = "11-26 + 35 + 37-41 + 43-61"
over = "11-26 + 35 + 37-41 + 43-99"
line = lines[idx[0]]
assert line.count(cured) == 1, "CHECK73 plant-B: the cured-range anchor drifted in the echo (%d found)" % line.count(cured)
assert over not in line, "CHECK73 plant-B: the over-report is already on the surface"
lines[idx[0]] = line.replace(cured, over, 1)
open(path, "w", encoding="utf-8").write("".join(lines))
PYEOF
set +e
RED73B_OUT=$(bash "$RED73_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED73B_RC=$?
set -e
[ "$RED73B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the twin's PASS narration claims a pin the positive run never asserts (got 0 — CHECK73 R1's over-report arm is toothless)"
sed -n '/=== Check 73:/,$p' <<<"$RED73B_OUT" | grep -qF 'CHECK73 R1: the PASS narration claims "11-26 + 35 + 37-41 + 43-99"' ||
	fail "CHECK73 red-B must convict the over-report quoting both sides of the drift (got: $RED73B_OUT)"
[ "$(sed -n '/=== Check 73:/,$p' <<<"$RED73B_OUT" | grep -c 'CHECK73 R')" -eq 1 ] ||
	fail "CHECK73 red-B must report exactly its 1 conviction (got: $RED73B_OUT)"
sed -n '/=== Check 71:/,/=== Check 72:/p' <<<"$RED73B_OUT" | grep -qF 'CHECK71: the boot-auth Timer arms through the seconds' ||
	fail "Check 71 must stay PASS while Check 73 is red (gate independence)"
sed -n '/=== Check 72:/,/=== Check 73:/p' <<<"$RED73B_OUT" | grep -qF "CHECK72: the direct-play gate probes the named canonical delivery codec" ||
	fail "Check 72 must stay PASS while Check 73 is red (gate independence)"
cp "$FAKE_REPO/tests/scripts/verify-runtime-portable.sh" "$TWIN73"
python3 - "$DOC73" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
needle = "checks 11-26 + 35 + 37-41 + 43-61 all execute"
era = "checks 11-26 all execute"
assert text.count(needle) == 1, "CHECK73 plant-C: the ledger sentence anchor drifted (%d found)" % text.count(needle)
assert era not in text, "CHECK73 plant-C: the era sentence is already on the surface"
text = text.replace(needle, era, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED73C_OUT=$(bash "$RED73_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED73C_RC=$?
set -e
[ "$RED73C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the ledger's Regression-test sentence lags the twin's executed pins (got 0 — CHECK73 R2 is toothless)"
sed -n '/=== Check 73:/,$p' <<<"$RED73C_OUT" | grep -qF 'CHECK73 R2: the Regression-test sentence claims "asserts checks 11-26 all execute"' ||
	fail "CHECK73 red-C must convict the lagging ledger sentence quoting both sides of the drift (got: $RED73C_OUT)"
[ "$(sed -n '/=== Check 73:/,$p' <<<"$RED73C_OUT" | grep -c 'CHECK73 R')" -eq 1 ] ||
	fail "CHECK73 red-C must report exactly its 1 conviction — the twin echo itself still states the derived truth (got: $RED73C_OUT)"
sed -n '/=== Check 71:/,/=== Check 72:/p' <<<"$RED73C_OUT" | grep -qF 'CHECK71: the boot-auth Timer arms through the seconds' ||
	fail "Check 71 must stay PASS while Check 73 is red (gate independence)"
sed -n '/=== Check 72:/,/=== Check 73:/p' <<<"$RED73C_OUT" | grep -qF "CHECK72: the direct-play gate probes the named canonical delivery codec" ||
	fail "Check 72 must stay PASS while Check 73 is red (gate independence)"
cp "$FAKE_REPO/docs/static-checks.md" "$DOC73"
python3 - "$DOC73" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
kept = [l for l in lines if not l.startswith("| 73 |")]
assert len(lines) - len(kept) == 1, "CHECK73 plant-D: the row-73 anchor drifted (%d row lines found)" % (len(lines) - len(kept))
open(path, "w", encoding="utf-8").write("".join(kept))
PYEOF
set +e
RED73D_OUT=$(bash "$RED73_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED73D_RC=$?
set -e
[ "$RED73D_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when ledger row 73 is deleted (got 0 — CHECK73 R3 is toothless)"
sed -n '/=== Check 73:/,$p' <<<"$RED73D_OUT" | grep -qF "CHECK73 R3: row 73 vanished" ||
	fail "CHECK73 red-D must convict the vanished ledger row by name (got: $RED73D_OUT)"
[ "$(sed -n '/=== Check 73:/,$p' <<<"$RED73D_OUT" | grep -c 'CHECK73 R')" -eq 1 ] ||
	fail "CHECK73 red-D must report exactly its 1 conviction (got: $RED73D_OUT)"
sed -n '/=== Check 71:/,/=== Check 72:/p' <<<"$RED73D_OUT" | grep -qF 'CHECK71: the boot-auth Timer arms through the seconds' ||
	fail "Check 71 must stay PASS while Check 73 is red (gate independence)"
sed -n '/=== Check 72:/,/=== Check 73:/p' <<<"$RED73D_OUT" | grep -qF "CHECK72: the direct-play gate probes the named canonical delivery codec" ||
	fail "Check 72 must stay PASS while Check 73 is red (gate independence)"
cp "$FAKE_REPO/docs/static-checks.md" "$DOC73"
set +e
GREEN73_OUT=$(bash "$RED73_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN73_RC=$?
set -e
[ "$GREEN73_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the four planted narration-truth regressions are removed (got $GREEN73_RC)"
assert_contains "CHECK73: the twin's PASS narration and the ledger sentence both equal" "$GREEN73_OUT"

# --- CHECK74 plants (review roku__gameux CR-2 / M-ROKU-14 / M-ROKU-15): form
# input attribute truth (hint=/secure= extinct, hintText rides the translate
# net) and node-type existence (no XML tag outside curated built-ins ∪
# project components). Four scratch reds, differing conviction signatures each:
#   A  the era dead attribute re-grown — secureMode reverted to secure= in a
#      scratch LoginScene.xml fires R1 ALONE, exactly one (the word-boundary
#      regex cannot fire on the real field names; the hintText on the same
#      element stays a live, green translation subject);
#   B  an unlocalized hintText value planted in a scratch SyncPlayScene.xml
#      fires R2's not-a-catalog-value arm ALONE, exactly one — hintText is
#      chrome, and Check 25's net now covers it (Check 25 itself sleeps
#      through hint literals; that hole is what this leg closes);
#   C  the era phantom re-grown — the transport group's LayoutGroup renamed
#      back to <HStack> in a scratch PlayerScene.xml fires R4 ALONE, exactly
#      one (attributes and children ride unchanged; only the tag decays —
#      phantom instantiation renders NOTHING on device);
#   D  all five ParentalControls hintText attributes stripped in a scratch
#      copy fires R3's census ALONE, exactly one (9 minus 5 = 4 < floor 6) —
#      the scan may not go vacuous while its markup silently disappears.
# CHECK25 (the sibling XML-chrome law over the very files these plants edit),
# CHECK56/CHECK63/CHECK66 (SyncPlayScene.xml, PlayerScene.xml, LoginScene.xml
# readers), and CHECK73 (narration prose only) stay green on all four reds —
# gate independence; full restore returns exit 0 with CHECK74 green.
RED74_ROOT="$TEST_ROOT/red74"
mkdir -p "$RED74_ROOT"
cp -a "$TEST_ROOT/repo" "$RED74_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED74_ROOT/phlix-server"
LOGIN74="$RED74_ROOT/repo/components/LoginScene.xml"
SYNC74="$RED74_ROOT/repo/components/SyncPlayScene.xml"
PLAYER74="$RED74_ROOT/repo/components/PlayerScene.xml"
PARENT74="$RED74_ROOT/repo/components/ParentalControlsScene.xml"
python3 - "$LOGIN74" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = 'secureMode="true"'
era = 'secure="true"'
assert text.count(anchor) == 1, "CHECK74 plant-A: the secureMode anchor drifted (%d found)" % text.count(anchor)
assert era not in text, "CHECK74 plant-A: the era dead attribute is already on the surface"
text = text.replace(anchor, era, 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED74A_OUT=$(bash "$RED74_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED74A_RC=$?
set -e
[ "$RED74A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the dead secure= attribute is re-grown (got 0 — CHECK74 R1 is toothless)"
sed -n '/=== Check 74:/,$p' <<<"$RED74A_OUT" | grep -qF 'CHECK74 R1: dead markup attribute on the line' ||
	fail "CHECK74 red-A must convict the re-grown dead attribute naming file:line (got: $RED74A_OUT)"
[ "$(sed -n '/=== Check 74:/,$p' <<<"$RED74A_OUT" | grep -c 'CHECK74 R')" -eq 1 ] ||
	fail "CHECK74 red-A must report exactly its 1 conviction — the hintText on the same element stays live and green (got: $RED74A_OUT)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED74A_OUT" | grep -qF "CHECK25: all 192 XML chrome literals exempt or catalog-backed" ||
	fail "Check 25 (the sibling XML-chrome law over the same file) must stay PASS while Check 74 is red (gate independence)"
sed -n '/=== Check 66:/,/=== Check 67:/p' <<<"$RED74A_OUT" | grep -qF "CHECK66: both WS handshakes cap their header accumulator" ||
	fail "Check 66 (the same file's copy-pair law) must stay PASS while Check 74 is red (gate independence)"
cp "$FAKE_REPO/components/LoginScene.xml" "$LOGIN74"
python3 - "$SYNC74" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = 'hintText="Enter group name…"'
assert text.count(anchor) == 1, "CHECK74 plant-B: the hintText anchor drifted (%d found)" % text.count(anchor)
text = text.replace(anchor, 'hintText="Phantom unlocalized hint"', 1)
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED74B_OUT=$(bash "$RED74_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED74B_RC=$?
set -e
[ "$RED74B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an hintText escapes the locale catalog (got 0 — CHECK74 R2 is toothless)"
sed -n '/=== Check 74:/,$p' <<<"$RED74B_OUT" | grep -qF "CHECK74 R2: hintText literal 'Phantom unlocalized hint' is not a catalog value" ||
	fail "CHECK74 red-B must convict the unlocalized hint quoting the plant (got: $RED74B_OUT)"
[ "$(sed -n '/=== Check 74:/,$p' <<<"$RED74B_OUT" | grep -c 'CHECK74 R')" -eq 1 ] ||
	fail "CHECK74 red-B must report exactly its 1 conviction (got: $RED74B_OUT)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED74B_OUT" | grep -qF "CHECK25: all 192 XML chrome literals exempt or catalog-backed" ||
	fail "Check 25 must stay PASS while Check 74 is red — hint chrome is precisely the surface Check 25 never scanned (gate independence)"
sed -n '/=== Check 56:/,/=== Check 57:/p' <<<"$RED74B_OUT" | grep -qF "CHECK56: the SyncPlay room scene has zero instantiation sites" ||
	fail "Check 56 (the same scene's dead-path truth) must stay PASS while Check 74 is red (gate independence)"
cp "$FAKE_REPO/components/SyncPlayScene.xml" "$SYNC74"
python3 - "$PLAYER74" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = 'translation="[440,300]"'
assert text.count(anchor) == 1, "CHECK74 plant-C: the transport-group anchor drifted (%d found)" % text.count(anchor)
i = text.index(anchor)
s = text.rindex("<LayoutGroup ", 0, i)
e = text.index("</LayoutGroup>", i)
seg = text[s:e + len("</LayoutGroup>")]
assert "<HStack" not in seg and "</HStack>" not in seg, "CHECK74 plant-C: an HStack is already inside the group"
new = seg.replace("<LayoutGroup ", "<HStack ", 1).replace("</LayoutGroup>", "</HStack>", 1)
text = text[:s] + new + text[e + len("</LayoutGroup>"):]
open(path, "w", encoding="utf-8").write(text)
PYEOF
set +e
RED74C_OUT=$(bash "$RED74_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED74C_RC=$?
set -e
[ "$RED74C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the era phantom node is re-grown (got 0 — CHECK74 R4 is toothless)"
sed -n '/=== Check 74:/,$p' <<<"$RED74C_OUT" | grep -qF "CHECK74 R4: <HStack> is neither a curated Roku built-in nor a project component" ||
	fail "CHECK74 red-C must convict the phantom tag by name (got: $RED74C_OUT)"
[ "$(sed -n '/=== Check 74:/,$p' <<<"$RED74C_OUT" | grep -c 'CHECK74 R')" -eq 1 ] ||
	fail "CHECK74 red-C must report exactly its 1 conviction — attributes and children ride unchanged (got: $RED74C_OUT)"
sed -n '/=== Check 63:/,/=== Check 64:/p' <<<"$RED74C_OUT" | grep -qF "CHECK63: GetErrorMessage echoes no wire prose" ||
	fail "Check 63 (the same file's label-legibility law) must stay PASS while Check 74 is red (gate independence)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED74C_OUT" | grep -qF "CHECK25: all 192 XML chrome literals exempt or catalog-backed" ||
	fail "Check 25 must stay PASS while Check 74 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.xml" "$PLAYER74"
python3 - "$PARENT74" <<'PYEOF'
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
removed = 0
for n, line in enumerate(lines):
    if '<TextEditBox id=' in line and 'hintText="' in line:
        new = re.sub(r'\s*hintText="[^"]*"', '', line, count=1)
        assert new != line, "CHECK74 plant-D: the strip regex did not fire on line %d" % (n + 1)
        lines[n] = new
        removed += 1
assert removed == 5, "CHECK74 plant-D: hintText anchor drift (%d fields found, expected 5)" % removed
open(path, "w", encoding="utf-8").write("".join(lines))
PYEOF
set +e
RED74D_OUT=$(bash "$RED74_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
RED74D_RC=$?
set -e
[ "$RED74D_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the hintText markup silently disappears (got 0 — CHECK74 R3 is toothless)"
sed -n '/=== Check 74:/,$p' <<<"$RED74D_OUT" | grep -qF "CHECK74 R3: the hintText scan observed 5 occurrences" ||
	fail "CHECK74 red-D must convict the census naming the derived count (got: $RED74D_OUT)"
[ "$(sed -n '/=== Check 74:/,$p' <<<"$RED74D_OUT" | grep -c 'CHECK74 R')" -eq 1 ] ||
	fail "CHECK74 red-D must report exactly its 1 conviction — the surviving five hints stay catalog-clean (got: $RED74D_OUT)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED74D_OUT" | grep -qF "CHECK25: all 192 XML chrome literals exempt or catalog-backed" ||
	fail "Check 25 must stay PASS while Check 74 is red (gate independence)"
sed -n '/=== Check 73:/,/=== Check 74:/p' <<<"$RED74D_OUT" | grep -qF "CHECK73: the twin's PASS narration and the ledger sentence both equal" ||
	fail "Check 73 (narration prose only) must stay PASS while Check 74 is red (gate independence)"
cp "$FAKE_REPO/components/ParentalControlsScene.xml" "$PARENT74"
set +e
GREEN74_OUT=$(bash "$RED74_ROOT/repo/scripts/verify-runtime.sh" 2>&1)
GREEN74_RC=$?
set -e
[ "$GREEN74_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the four planted form-input/node-type regressions are removed (got $GREEN74_RC)"
assert_contains "CHECK74: hint=/secure= extinct, hintText rides the translate net" "$GREEN74_OUT"

# --- CHECK75 plants (R-ROKU-31: doc-fiction extinction gate): each era
# fiction string re-entering the shipped doc surface must convict exactly one
# CHECK75 R1 naming its file; the working recipe losing a marker must convict
# exactly one CHECK75 R2 alone; no sibling leg may absorb or leak the run;
# restore returns exit 0 with CHECK75 green. The plants write the banned
# strings CONTIGUOUS into scratch copies while this twin's own source carries
# only fragments (SELF-BURN law, CHECK69/71).
RED75_ROOT="$TEST_ROOT/red75"
mkdir -p "$RED75_ROOT"
cp -a "$TEST_ROOT/repo" "$RED75_ROOT/repo"
cp -a "$TEST_ROOT/phlix-server" "$RED75_ROOT/phlix-server"
export RED75_REPO="$RED75_ROOT/repo"

# red-A: the era install-endpoint fiction pasted back into README.md.
python3 - <<'PYEOF'
import os
p = os.path.join(os.environ["RED75_REPO"], "README.md")
era = "8060/" + "install"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert era not in text, "CHECK75 plant-A: the era fiction is already on the README surface"
with open(p, "a", encoding="utf-8") as f:
    f.write("\nEra prose plant: the old `:%s/app` recipe (CHECK75 red-A).\n" % era)
PYEOF
set +e
RED75A_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75A_RC=$?
set -e
[ "$RED75A_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the era install-endpoint fiction returns to README.md (got 0 — CHECK75 R1 is toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75A_OUT" | grep -qF 'CHECK75 R1: the install-endpoint fiction' ||
	fail "CHECK75 red-A must convict the README plant by fiction class (got: $RED75A_OUT)"
[ "$(sed -n '/=== Check 75:/,$p' <<<"$RED75A_OUT" | grep -c 'CHECK75 R')" -eq 1 ] ||
	fail "CHECK75 red-A must report exactly its 1 conviction (got: $RED75A_OUT)"
sed -n '/=== Check 41:/,/=== Check 42:/p' <<<"$RED75A_OUT" | grep -q "^  PASS\$" ||
	fail "Check 41 (docs-honesty sibling) must stay PASS while Check 75 is red (gate independence)"
sed -n '/=== Check 62:/,/=== Check 63:/p' <<<"$RED75A_OUT" | grep -q "^  PASS\$" ||
	fail "Check 62 (README census over the very file this plant edits) must stay PASS (gate independence)"
cp "$FAKE_REPO/README.md" "$RED75_REPO/README.md"

# red-B: a GROWN docs file carries the rokupkg install-flag string — the docs
# glob must be live, not frozen at today's file list.
python3 - <<'PYEOF'
import os
p = os.path.join(os.environ["RED75_REPO"], "docs", "fiction-proof.md")
era = "rokupkg --" + "install"
with open(p, "w", encoding="utf-8") as f:
    f.write("# Fiction probe\n\nThe era doc told users to run `%s` (CHECK75 red-B).\n" % era)
PYEOF
set +e
RED75B_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75B_RC=$?
set -e
[ "$RED75B_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a NEW docs file re-grows the install-flag fiction (got 0 — the docs glob is frozen/toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75B_OUT" | grep -qF 'docs/fiction-proof.md' ||
	fail "CHECK75 red-B must convict the grown file by path (got: $RED75B_OUT)"
[ "$(sed -n '/=== Check 75:/,$p' <<<"$RED75B_OUT" | grep -c 'CHECK75 R')" -eq 1 ] ||
	fail "CHECK75 red-B must report exactly its 1 conviction (got: $RED75B_OUT)"
sed -n '/=== Check 41:/,/=== Check 42:/p' <<<"$RED75B_OUT" | grep -q "^  PASS\$" ||
	fail "Check 41 must stay PASS while Check 75 is red (gate independence)"
sed -n '/=== Check 74:/,$p' <<<"$RED75B_OUT" | grep -qF 'CHECK74: hint=/secure= extinct' ||
	fail "Check 74 (latest-neighbor law) must stay PASS while Check 75 is red (gate independence)"
rm "$RED75_REPO/docs/fiction-proof.md"

# red-C: the npm-global rokupkg fiction pasted back into publishing.md.
python3 - <<'PYEOF'
import os
p = os.path.join(os.environ["RED75_REPO"], "docs", "publishing.md")
era = "npm install -g " + "rokupkg"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert era not in text, "CHECK75 plant-C: the era fiction is already on the publishing surface"
with open(p, "a", encoding="utf-8") as f:
    f.write("\nEra prose plant: `%s` before signing (CHECK75 red-C).\n" % era)
PYEOF
set +e
RED75C_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75C_RC=$?
set -e
[ "$RED75C_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the npm-global CLI fiction returns to publishing.md (got 0 — CHECK75 R1 is toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75C_OUT" | grep -qF 'CHECK75 R1: the npm-global CLI fiction' ||
	fail "CHECK75 red-C must convict the npm-global plant by class (got: $RED75C_OUT)"
[ "$(sed -n '/=== Check 75:/,$p' <<<"$RED75C_OUT" | grep -c 'CHECK75 R')" -eq 1 ] ||
	fail "CHECK75 red-C must report exactly its 1 conviction (got: $RED75C_OUT)"
sed -n '/=== Check 41:/,/=== Check 42:/p' <<<"$RED75C_OUT" | grep -q "^  PASS\$" ||
	fail "Check 41 (publishing.md is one of its six inputs) must stay PASS while Check 75 is red (gate independence)"
cp "$FAKE_REPO/docs/publishing.md" "$RED75_REPO/docs/publishing.md"

# red-D: the raw manifest form-field fiction re-enters as a workflow comment.
python3 - <<'PYEOF'
import os
p = os.path.join(os.environ["RED75_REPO"], ".github", "workflows", "test.yml")
era = "manifest=@" + "manifest"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert era not in text, "CHECK75 plant-D: the era fiction is already on the workflow surface"
with open(p, "a", encoding="utf-8") as f:
    f.write("# Era plant: the old form field sent %s (CHECK75 red-D).\n" % era)
PYEOF
set +e
RED75D_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75D_RC=$?
set -e
[ "$RED75D_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the raw-manifest-field fiction re-enters a workflow (got 0 — CHECK75 R1 is toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75D_OUT" | grep -qF '.github/workflows/test.yml' ||
	fail "CHECK75 red-D must convict the workflow by path (got: $RED75D_OUT)"
[ "$(sed -n '/=== Check 75:/,$p' <<<"$RED75D_OUT" | grep -c 'CHECK75 R')" -eq 1 ] ||
	fail "CHECK75 red-D must report exactly its 1 conviction (got: $RED75D_OUT)"
sed -n '/=== Check 65:/,/=== Check 66:/p' <<<"$RED75D_OUT" | grep -q "^  PASS\$" ||
	fail "Check 65 (test.yml reader) must stay PASS while Check 75 is red (gate independence)"
cp "$FAKE_REPO/.github/workflows/test.yml" "$RED75_REPO/.github/workflows/test.yml"

# red-E: the flip side — the WORKING recipe loses a marker while every fiction
# stays extinct. R2 must convict alone and R1 must stay silent.
python3 - <<'PYEOF'
import os
p = os.path.join(os.environ["RED75_REPO"], "Makefile")
anchor = "mysubmit=" + "Install"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK75 plant-E: the submit-marker anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "mysubmit=Deploy"))
PYEOF
set +e
RED75E_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75E_RC=$?
set -e
[ "$RED75E_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the real recipe loses its submit marker (got 0 — CHECK75 R2 is toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75E_OUT" | grep -qF "CHECK75 R2: the real install recipe's marker" ||
	fail "CHECK75 red-E must convict the missing marker naming the file (got: $RED75E_OUT)"
[ "$(sed -n '/=== Check 75:/,$p' <<<"$RED75E_OUT" | grep -c 'CHECK75 R')" -eq 1 ] ||
	fail "CHECK75 red-E must report exactly its 1 R2 conviction — with zero R1 hits (got: $RED75E_OUT)"
sed -n '/=== Check 41:/,/=== Check 42:/p' <<<"$RED75E_OUT" | grep -q "^  PASS\$" ||
	fail "Check 41 (Makefile reader) must stay PASS while Check 75 is red (gate independence)"
cp "$FAKE_REPO/Makefile" "$RED75_REPO/Makefile"

set +e
GREEN75_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN75_RC=$?
set -e
[ "$GREEN75_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all five doc-surface plants are removed (got $GREEN75_RC)"
assert_contains "CHECK75: the six era fictions are extinct across the" "$GREEN75_OUT"

# --- Check 76 red legs (MJ-1 detail-resume thread), same scratch repo ---
# red-F: the PlayItem Show call loses the resumeSeconds hand-off. R2 must
# convict ALONE — the fire and read sides stay wired, so their silence is
# itself the per-arm measurement.
python3 - <<'PYEOF76F'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/DetailScene.brs")
anchor = "        resumeSeconds: m.resumeSeconds\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK76 plant-F: the Show-arg anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF76F
set +e
RED76F_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED76F_RC=$?
set -e
[ "$RED76F_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the Show hand-off is stripped (got 0 — CHECK76 R2 is toothless)"
sed -n '/=== Check 76:/,$p' <<<"$RED76F_OUT" | grep -qF "CHECK76 R2: the Show argument block lost resumeSeconds" ||
	fail "CHECK76 red-F must convict the lost hand-off naming the file (got: $RED76F_OUT)"
[ "$(sed -n '/=== Check 76:/,$p' <<<"$RED76F_OUT" | grep -c 'CHECK76 R')" -eq 1 ] ||
	fail "CHECK76 red-F must report exactly its 1 R2 conviction — fire and read arms stay silent (got: $RED76F_OUT)"
sed -n '/=== Check 75:/,/=== Check 76:/p' <<<"$RED76F_OUT" | grep -q "^  PASS\$" ||
	fail "Check 75 (adjacent extinction leg) must stay PASS while Check 76 is red (gate independence)"
cp "$FAKE_REPO/components/DetailScene.brs" "$RED75_REPO/components/DetailScene.brs"

# red-G: the multiplexer response arm is re-pointed onto a never-matching op
# string. R1 must convict ALONE with exactly one named arm — the fire side,
# the hand-off and the PlayerScene consumer all stay wired.
python3 - <<'PYEOF76G'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/DetailScene.brs")
anchor = 'resp.op = "getContinueWatching"'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK76 plant-G: the response-arm anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, 'resp.op = "getContinueWatchingZ"'))
PYEOF76G
set +e
RED76G_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED76G_RC=$?
set -e
[ "$RED76G_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the response arm is un-armed (got 0 — CHECK76 R1 is toothless)"
sed -n '/=== Check 76:/,$p' <<<"$RED76G_OUT" | grep -qF 'CHECK76 R1: the resp.op = "getContinueWatching" arm is gone' ||
	fail "CHECK76 red-G must convict the vanished response arm naming it (got: $RED76G_OUT)"
[ "$(sed -n '/=== Check 76:/,$p' <<<"$RED76G_OUT" | grep -c 'CHECK76 R')" -eq 1 ] ||
	fail "CHECK76 red-G must report exactly its 1 R1 conviction — fire, hand-off and consumer pins stay silent (got: $RED76G_OUT)"
sed -n '/=== Check 43:/,/=== Check 44:/p' <<<"$RED76G_OUT" | grep -q "^  PASS\$" ||
	fail "Check 43 (same-file DetailScene reader) must stay PASS while Check 76 is red (gate independence)"
cp "$FAKE_REPO/components/DetailScene.brs" "$RED75_REPO/components/DetailScene.brs"

set +e
GREEN76_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN76_RC=$?
set -e
[ "$GREEN76_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK76 plants are removed (got $GREEN76_RC)"
assert_contains "CHECK76: the detail resume lookup fires, arms, hands off and is" "$GREEN76_OUT"

# --- Check 77 red legs (MJ-18 serverId custody), same scratch repo ---
# red-H: the picker's shape gate is stripped. R1 must convict ALONE — the
# read degrade and the dial refuse stay honest about their own pins.
python3 - <<'PYEOF77H'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/ServerPickerScene.brs")
anchor = "    if not IsSafeContentId(id) then return\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK77 plant-H: the picker-gate anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF77H
set +e
RED77H_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED77H_RC=$?
set -e
[ "$RED77H_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the pick gate is stripped (got 0 — CHECK77 R1 is toothless)"
sed -n '/=== Check 77:/,$p' <<<"$RED77H_OUT" | grep -qF "CHECK77 R1: the pick path no longer gates" ||
	fail "CHECK77 red-H must convict the lost pick gate naming the file (got: $RED77H_OUT)"
[ "$(sed -n '/=== Check 77:/,$p' <<<"$RED77H_OUT" | grep -c 'CHECK77 R')" -eq 1 ] ||
	fail "CHECK77 red-H must report exactly its 1 R1 conviction — read and dial gates stay silent (got: $RED77H_OUT)"
sed -n '/=== Check 76:/,/=== Check 77:/p' <<<"$RED77H_OUT" | grep -q "^  PASS\$" ||
	fail "Check 76 (adjacent MJ-era shape leg) must stay PASS while Check 77 is red (gate independence)"
cp "$FAKE_REPO/components/ServerPickerScene.brs" "$RED75_REPO/components/ServerPickerScene.brs"

# red-I: the task-side dial gate is stripped. R3 must convict ALONE.
python3 - <<'PYEOF77I'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/HubCommandTask.brs")
anchor = "    if not IsSafeContentId(serverId) then\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK77 plant-I: the dial-gate anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF77I
set +e
RED77I_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED77I_RC=$?
set -e
[ "$RED77I_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the dial gate is stripped (got 0 — CHECK77 R3 is toothless)"
sed -n '/=== Check 77:/,$p' <<<"$RED77I_OUT" | grep -qF "CHECK77 R3: the task-side path-law choke is gone" ||
	fail "CHECK77 red-I must convict the lost dial choke naming the file (got: $RED77I_OUT)"
[ "$(sed -n '/=== Check 77:/,$p' <<<"$RED77I_OUT" | grep -c 'CHECK77 R')" -eq 1 ] ||
	fail "CHECK77 red-I must report exactly its 1 R3 conviction — pick and read gates stay silent (got: $RED77I_OUT)"
sed -n '/=== Check 70:/,/=== Check 71:/p' <<<"$RED77I_OUT" | grep -q "^  PASS\$" ||
	fail "Check 70 (same-file relay accept-proof leg) must stay PASS while Check 77 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$RED75_REPO/components/HubCommandTask.brs"

set +e
GREEN77_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN77_RC=$?
set -e
[ "$GREEN77_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK77 plants are removed (got $GREEN77_RC)"
assert_contains "CHECK77: the serverId shape law holds at all three custody points" "$GREEN77_OUT"

# --- Check 78 red legs (MJ-20 settings-catalog custody), same scratch repo ---
# red-J: a raw header title is pasted back into the builder NEXT TO the
# translated entries. R1 must convict ALONE, exactly once — the census floor
# (27 surviving Translate calls) and the docs/ledger markers stay satisfied,
# so the raw-literal ban owns this conviction by itself.
python3 - <<'PYEOF78J'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/SettingsScene.brs")
anchor = '        { title: Translate("settings_section_account"), type: "header" },\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK78 plant-J: the builder first-row anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, anchor + '        { title: "Extra Section", type: "header" },\n'))
PYEOF78J
set +e
RED78J_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED78J_RC=$?
set -e
[ "$RED78J_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a raw builder literal is pasted back (got 0 — CHECK78 R1 is toothless)"
sed -n '/=== Check 78:/,$p' <<<"$RED78J_OUT" | grep -qF 'CHECK78 R1: a raw title: literal is back' ||
	fail "CHECK78 red-J must convict the pasted-back raw title naming the file:line (got: $RED78J_OUT)"
[ "$(sed -n '/=== Check 78:/,$p' <<<"$RED78J_OUT" | grep -c 'CHECK78 R')" -eq 1 ] ||
	fail "CHECK78 red-J must report exactly its 1 R1 conviction — census, docs marker and ledger row stay silent (got: $RED78J_OUT)"
sed -n '/=== Check 20:/,/=== Check 21:/p' <<<"$RED78J_OUT" | grep -q "^  PASS\$" ||
	fail "Check 20 (the catalog-resolution law over the very keys this leg protects) must stay PASS while Check 78 is red (gate independence)"
cp "$FAKE_REPO/components/SettingsScene.brs" "$RED75_REPO/components/SettingsScene.brs"

# red-K: a builder entry is deleted wholesale — no raw literal appears, the
# Translate census drops to 26. R2 must convict ALONE, R1 silent: the ban and
# the floor own separate conviction classes on purpose (a shrinking menu is
# not a paste-back and must not be reported as one).
python3 - <<'PYEOF78K'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/SettingsScene.brs")
anchor = '        { title: Translate("settings_section_about"), type: "header" },\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK78 plant-K: the builder about-row anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF78K
set +e
RED78K_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED78K_RC=$?
set -e
[ "$RED78K_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a builder entry is deleted (got 0 — CHECK78 R2 is toothless)"
sed -n '/=== Check 78:/,$p' <<<"$RED78K_OUT" | grep -qF "CHECK78 R2: the builder makes only" ||
	fail "CHECK78 red-K must convict the shrinking Translate census (got: $RED78K_OUT)"
[ "$(sed -n '/=== Check 78:/,$p' <<<"$RED78K_OUT" | grep -c 'CHECK78 R')" -eq 1 ] ||
	fail "CHECK78 red-K must report exactly its 1 R2 conviction — the raw-ban stays silent on a literal-free plant (got: $RED78K_OUT)"
[ "$(sed -n '/=== Check 78:/,$p' <<<"$RED78K_OUT" | grep -c 'CHECK78 R1')" -eq 0 ] ||
	fail "CHECK78 red-K must NOT fire R1 — no raw literal exists in this plant (got: $RED78K_OUT)"
sed -n '/=== Check 76:/,/=== Check 77:/p' <<<"$RED78K_OUT" | grep -q "^  PASS\$" ||
	fail "Check 76 (adjacent MJ-era shape leg) must stay PASS while Check 78 is red (gate independence)"
cp "$FAKE_REPO/components/SettingsScene.brs" "$RED75_REPO/components/SettingsScene.brs"

set +e
GREEN78_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN78_RC=$?
set -e
[ "$GREEN78_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK78 plants are removed (got $GREEN78_RC)"
assert_contains "CHECK78: the settings builder carries zero raw" "$GREEN78_OUT"

# --- Check 79 red legs (MJ-6/MJ-7 syncplay command funnel + stop custody), same scratch repo ---
# red-L: the catch-up push stripped from the attach window — the read still
# happens, the value is discarded; the MJ-6 first-tap swallow re-opens exactly
# at the worst instant, and no other R1 family may notice.
python3 - <<'PYEOF79L'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/SyncPlayTask.brs")
anchor = "    if catchUp <> invalid then m.pendingCommands.Push(catchUp)\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK79 plant-L: the catch-up push anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF79L
set +e
RED79L_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED79L_RC=$?
set -e
[ "$RED79L_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the catch-up push is gone (got 0 — CHECK79 R1 is toothless)"
sed -n '/=== Check 79:/,$p' <<<"$RED79L_OUT" | grep -qF "catchUp <> invalid then m.pendingCommands.Push(catchUp)" || fail "CHECK79 must convict the lost catch-up push (got: $RED79L_OUT)"
[ "$(sed -n '/=== Check 79:/,$p' <<<"$RED79L_OUT" | grep -c 'CHECK79 R')" -eq 1 ] || fail "CHECK79 must report exactly its 1 R1 conviction for the catch-up plant — the funnel families must not double-report (got: $RED79L_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED79L_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over these very files) must stay PASS while Check 79 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED79L_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes on the same scene) must stay PASS while Check 79 is red (gate independence)"
cp "$FAKE_REPO/components/SyncPlayTask.brs" "$RED75_REPO/components/SyncPlayTask.brs"

# red-M: the era immediate stop pair re-grown inside OnSyncLeavePressed — the
# exact MJ-7 defect (the queued leave frame dies with the thread; peers ghost
# the member). The shape-agnostic census owns the whole regrow class alone.
python3 - <<'PYEOF79M'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = "    m.syncUserStopped = true\n    ArmSyncLeaveStop()\nend sub"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK79 plant-M: the leave-body tail anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "    m.syncTask.control = \"stop\"\n    m.syncTask = invalid\n" + anchor))
PYEOF79M
set +e
RED79M_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED79M_RC=$?
set -e
[ "$RED79M_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an immediate leave stop is re-grown (got 0 — CHECK79 R2's census is toothless)"
sed -n '/=== Check 79:/,$p' <<<"$RED79M_OUT" | grep -qF "site(s) write m.syncTask.control" || fail "CHECK79 must convict the stop-custody census breach (got: $RED79M_OUT)"
[ "$(sed -n '/=== Check 79:/,$p' <<<"$RED79M_OUT" | grep -c 'CHECK79 R')" -eq 1 ] || fail "CHECK79 must report exactly its 1 R2 conviction for the regrow plant — the per-sub laws must not double-report through the census (got: $RED79M_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED79M_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over these very files) must stay PASS while Check 79 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED79M_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes on the same scene) must stay PASS while Check 79 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

GREEN79_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN79_RC=$?
[ "$GREEN79_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK79 plants are removed (got $GREEN79_RC — output: $GREEN79_OUT)"
assert_contains "CHECK79: the syncplay command funnel reads the field at attach" "$GREEN79_OUT"

# --- Check 80 red legs (MJ-9 join-anchor adoption), same scratch repo ---
# red-N: the syncAnchorApplied register stripped from the follower guard - the
# block still exists and parses the anchor, but adoption re-fires on every
# group_state frame and a promoted host would rubber-band itself: the exact
# MJ-9 custody half. Only R1's guard needle may notice (the census breaches it
# jointly inside the same conviction).
python3 - <<'PYEOF80N'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = "        if group <> invalid and not m.syncIsHost and not m.syncAnchorApplied then\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK80 plant-N: the adoption guard anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "        if group <> invalid and not m.syncIsHost then\n"))
PYEOF80N
set +e
RED80N_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED80N_RC=$?
set -e
[ "$RED80N_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the adoption register is stripped from the guard (got 0 — CHECK80 R1 is toothless)"
sed -n '/=== Check 80:/,$p' <<<"$RED80N_OUT" | grep -qF "the follower one-shot adoption guard" || fail "CHECK80 must convict the stripped adoption guard (got: $RED80N_OUT)"
[ "$(sed -n '/=== Check 80:/,$p' <<<"$RED80N_OUT" | grep -c 'CHECK80 R')" -eq 1 ] || fail "CHECK80 must report exactly its 1 R1 conviction for the guard plant - the register census reports jointly inside it (got: $RED80N_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED80N_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody on this very scene) must stay PASS while Check 80 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED80N_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over these very files) must stay PASS while Check 80 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED80N_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes on the same scene) must stay PASS while Check 80 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

# red-O: the duration clamp line deleted - positions beyond the cached length
# seek into phantom territory again (the positionOrDrop law this cure cites).
# Only R2's clamp needle may notice; R1 stays provably silent.
python3 - <<'PYEOF80O'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = "                            if dur# > 0 and anchorMs# > dur# then anchorMs# = dur#\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK80 plant-O: the duration clamp anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF80O
set +e
RED80O_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED80O_RC=$?
set -e
[ "$RED80O_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the duration clamp is deleted (got 0 — CHECK80 R2 is toothless)"
sed -n '/=== Check 80:/,$p' <<<"$RED80O_OUT" | grep -qF "anchorMs# > dur# then anchorMs# = dur#" || fail "CHECK80 must convict the deleted clamp (got: $RED80O_OUT)"
[ "$(sed -n '/=== Check 80:/,$p' <<<"$RED80O_OUT" | grep -c 'CHECK80 R')" -eq 1 ] || fail "CHECK80 must report exactly its 1 R2 conviction for the clamp plant - R1 must stay silent (got: $RED80O_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED80O_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody on this very scene) must stay PASS while Check 80 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED80O_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over these very files) must stay PASS while Check 80 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED80O_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes on the same scene) must stay PASS while Check 80 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

GREEN80_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN80_RC=$?
[ "$GREEN80_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK80 plants are removed (got $GREEN80_RC — output: $GREEN80_OUT)"
assert_contains "CHECK80: the joiner adopts SPEC" "$GREEN80_OUT"

# --- Check 81 red legs (MJ-17 per-dial entropy seeding), same scratch repo ---
# red-P: the seeding call dropped from NewWebSocketKey - the seeder stands but
# the key (and every mask behind it) rides the factory's seconds-granularity
# clock stream again: the exact boot-window guessability MJ-17 cures. Only
# R2's custody arm may notice (definition, mix and fold needles stay silent).
python3 - <<'PYEOF81P'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/SyncPlayProtocol.brs")
anchor = "            m.SeedWebSocketEntropy()\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK81 plant-P: the seeding-call anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF81P
set +e
RED81P_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED81P_RC=$?
set -e
[ "$RED81P_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the per-dial seeding call is dropped (got 0 — CHECK81 R2 is toothless)"
sed -n '/=== Check 81:/,$p' <<<"$RED81P_OUT" | grep -qF "lost its m.SeedWebSocketEntropy() call" || fail "CHECK81 must convict the dropped seeding call (got: $RED81P_OUT)"
[ "$(sed -n '/=== Check 81:/,$p' <<<"$RED81P_OUT" | grep -c 'CHECK81 R')" -eq 1 ] || fail "CHECK81 must report exactly its 1 R2 conviction for the call plant - R1 must stay silent (got: $RED81P_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED81P_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 80:/,$p' <<<"$RED81P_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED81P_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over the very handshake this seeder protects) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED81P_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes) must stay PASS while Check 81 is red (gate independence)"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED75_REPO/source/lib/SyncPlayProtocol.brs"

# red-Q: the per-install channel client id stripped from the digest source -
# the fold keeps running over model + clock only, so the seed family is again
# enumerable by anyone who knows the device model: the install-secret half of
# MJ-17. Only R1's mix needle may notice (fold, verb, order all stay honest).
python3 - <<'PYEOF81Q'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/SyncPlayProtocol.brs")
anchor = "                clientId = dev.GetChannelClientId()\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK81 plant-Q: the client-id anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, '                clientId = ""\n'))
PYEOF81Q
set +e
RED81Q_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED81Q_RC=$?
set -e
[ "$RED81Q_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the channel client id leaves the digest source (got 0 — CHECK81 R1 is toothless)"
sed -n '/=== Check 81:/,$p' <<<"$RED81Q_OUT" | grep -qF "GetChannelClientId" || fail "CHECK81 must convict the stripped client-id mix (got: $RED81Q_OUT)"
[ "$(sed -n '/=== Check 81:/,$p' <<<"$RED81Q_OUT" | grep -c 'CHECK81 R')" -eq 1 ] || fail "CHECK81 must report exactly its 1 R1 conviction for the client-id plant - R2 must stay silent (got: $RED81Q_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED81Q_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 80:/,$p' <<<"$RED81Q_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED81Q_OUT" | grep -q "^  PASS\$" || fail "Check 46 (SyncPlay origin/accept law over the very handshake this seeder protects) must stay PASS while Check 81 is red (gate independence)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED81Q_OUT" | grep -q "^  PASS\$" || fail "Check 50 (party-attribution shapes) must stay PASS while Check 81 is red (gate independence)"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED75_REPO/source/lib/SyncPlayProtocol.brs"

GREEN81_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN81_RC=$?
[ "$GREEN81_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK81 plants are removed (got $GREEN81_RC — output: $GREEN81_OUT)"
assert_contains "CHECK81: the WS key and every mask" "$GREEN81_OUT"

# --- Check 82 red legs (MJ-19 media-lane TLS boundary), same scratch repo ---
# red-R: the root-relative accept arm deleted - relative media paths (which can
# never cross the TLS boundary; they ride the origin's own scheme) get refused
# with the absolute shapes: the over-refusal half of the predicate. Only R1's
# relative-path needle may notice.
python3 - <<'PYEOF82R'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/Utilities.brs")
anchor = '    if Left(s, 1) = "/" then return true\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK82 plant-R: the relative-path arm anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF82R
set +e
RED82R_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED82R_RC=$?
set -e
[ "$RED82R_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the relative-path accept arm is deleted (got 0 — CHECK82 R1 is toothless)"
sed -n '/=== Check 82:/,$p' <<<"$RED82R_OUT" | grep -qF 'if Left(s, 1) = "/" then return true' || fail "CHECK82 must convict the deleted relative-path arm (got: $RED82R_OUT)"
[ "$(sed -n '/=== Check 82:/,$p' <<<"$RED82R_OUT" | grep -c 'CHECK82 R')" -eq 1 ] || fail "CHECK82 must report exactly its 1 R1 conviction for the relative-arm plant - R2 must stay silent (got: $RED82R_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED82R_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED82R_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED82R_OUT" | grep -q "^  PASS\$" || fail "Check 81 (entropy seeding) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 43:/,/=== Check 44:/p' <<<"$RED82R_OUT" | grep -q "^  PASS\$" || fail "Check 43 (wire-text type law over these very scenes) must stay PASS while Check 82 is red (gate independence)"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED75_REPO/source/lib/Utilities.brs"

# red-S: the PlayerScene gate block deleted wholesale - the direct-play lane
# re-opens: a hostile or misconfigured answer names http://anywhere and the TV
# obeys. Only R2's site custody may notice; the helper itself stays honest.
python3 - <<'PYEOF82S'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = (
    "    ' MJ-19: an https session never rides a signed media URL DOWN into\n"
    "    ' cleartext (media-lane TLS-boundary law, Utilities.brs). A refused URL\n"
    "    ' reuses the existing no-stream dialog - refusal-reason copy is\n"
    "    ' owner-gated; no new locale keys are minted this era.\n"
    "    if not IsStreamUrlAdmissible(GetServerUrl(), streamUrl) then\n"
    '        print "[MJ-19] refusing cleartext or malformed stream URL across the TLS origin boundary"\n'
    "        streamUrl = invalid\n"
    "    end if\n"
)
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK82 plant-S: the PlayerScene gate block anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF82S
set +e
RED82S_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED82S_RC=$?
set -e
[ "$RED82S_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the direct-play gate block is deleted (got 0 — CHECK82 R2 is toothless)"
sed -n '/=== Check 82:/,$p' <<<"$RED82S_OUT" | grep -qF "components/PlayerScene.brs: gate call lost or duplicated" || fail "CHECK82 must convict the deleted direct-play gate (got: $RED82S_OUT)"
[ "$(sed -n '/=== Check 82:/,$p' <<<"$RED82S_OUT" | grep -c 'CHECK82 R')" -eq 1 ] || fail "CHECK82 must report exactly its 1 R2 conviction for the gate plant - R1 must stay silent (got: $RED82S_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED82S_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED82S_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED82S_OUT" | grep -q "^  PASS\$" || fail "Check 81 (entropy seeding) must stay PASS while Check 82 is red (gate independence)"
sed -n '/=== Check 43:/,/=== Check 44:/p' <<<"$RED82S_OUT" | grep -q "^  PASS\$" || fail "Check 43 (wire-text type law over this very scene) must stay PASS while Check 82 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

GREEN82_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN82_RC=$?
[ "$GREEN82_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK82 plants are removed (got $GREEN82_RC — output: $GREEN82_OUT)"
assert_contains "CHECK82: every signed media URL" "$GREEN82_OUT"

# --- Check 83 red legs (MN-22 log custody / MN-24 Location custody), same scratch repo ---
# red-T: the content-bearing suppressed-detail echo re-grown in
# GetErrorMessage - the capped wire string rides the debug log verbatim
# again, exactly the MN-22 class M-ROKU-03 killed on the UI side. Only
# R1's convicted-shape arm may notice (predicate and task gate stay honest).
python3 - <<'PYEOF83T'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/Utilities.brs")
anchor = '        print "GetErrorMessage suppressed wire detail (" + Str(Len(safeError)).Trim() + " chars)"\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK83 plant-T: the count-only echo anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, '        print "GetErrorMessage suppressed wire detail: " safeError\n'))
PYEOF83T
set +e
RED83T_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED83T_RC=$?
set -e
[ "$RED83T_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the suppressed-detail echo carries wire content again (got 0 — CHECK83 R1 is toothless)"
sed -n '/=== Check 83:/,$p' <<<"$RED83T_OUT" | grep -qF "content-bearing suppressed-detail echo re-grown" || fail "CHECK83 must convict the re-grown content echo (got: $RED83T_OUT)"
[ "$(sed -n '/=== Check 83:/,$p' <<<"$RED83T_OUT" | grep -c 'CHECK83 R')" -eq 1 ] || fail "CHECK83 must report exactly its 1 R1 conviction for the echo plant (got: $RED83T_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED83T_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED83T_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED83T_OUT" | grep -q "^  PASS\$" || fail "Check 81 (entropy seeding) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 82:/,/=== Check 83:/p' <<<"$RED83T_OUT" | grep -q "^  PASS\$" || fail "Check 82 (media-lane TLS boundary — the sibling law in this very Utilities file) must stay PASS while Check 83 is red (gate independence)"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED75_REPO/source/lib/Utilities.brs"

# red-U: the absolutize call deleted from resolveLocation - a relative
# Location reaches the tuner lane again and live TV silently never plays
# (MN-24). Only R2's slice arm may notice; the three playback refusals and
# every other law stay honest, so R2's components conviction stays silent.
python3 - <<'PYEOF83U'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/ApiClient.brs")
anchor = '            if location <> "" then location = ResolveRedirectTarget(url, location)\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK83 plant-U: the absolutize anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF83U
set +e
RED83U_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED83U_RC=$?
set -e
[ "$RED83U_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when resolveLocation stops absolutizing (got 0 — CHECK83 R2 is toothless)"
sed -n '/=== Check 83:/,$p' <<<"$RED83U_OUT" | grep -qF "stopped absolutizing the 3xx Location" || fail "CHECK83 must convict the deleted absolutize call (got: $RED83U_OUT)"
[ "$(sed -n '/=== Check 83:/,$p' <<<"$RED83U_OUT" | grep -c 'CHECK83 R')" -eq 1 ] || fail "CHECK83 must report exactly its 1 R2 conviction for the absolutize plant - the components arm must stay silent (got: $RED83U_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED83U_OUT" | grep -q "^  PASS\$" || fail "Check 79 (funnel/stop-custody) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED83U_OUT" | grep -q "^  PASS\$" || fail "Check 81 (entropy seeding) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 82:/,/=== Check 83:/p' <<<"$RED83U_OUT" | grep -q "^  PASS\$" || fail "Check 82 (media-lane TLS boundary over this very resolveLocation chain) must stay PASS while Check 83 is red (gate independence)"
sed -n '/=== Check 77:/,/=== Check 78:/p' <<<"$RED83U_OUT" | grep -q "^  PASS\$" || fail "Check 77 (serverId custody on the same ApiClient dial lanes) must stay PASS while Check 83 is red (gate independence)"
cp "$FAKE_REPO/source/lib/ApiClient.brs" "$RED75_REPO/source/lib/ApiClient.brs"

GREEN83_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN83_RC=$?
[ "$GREEN83_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK83 plants are removed (got $GREEN83_RC — output: $GREEN83_OUT)"
assert_contains "CHECK83: the debug log never carries message-sized wire content" "$GREEN83_OUT"

# --- Check 84 red legs (MN-18 probe enumeration / MN-27 en_US copy law), same scratch repo ---
# red-V: the legacy six-name section list re-grown BESIDE the dynamic walk -
# inert at runtime (the walk overwrites it) but exactly the rot the ban
# exists to refuse: a future edit could delete the walk and leave the stale
# list standing. Only R1's ban arm may notice; Check 22's rotated (c) arm
# stays green because the walk survives - disclosed design of this plant.
python3 - <<'PYEOF84V'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/Utilities.brs")
anchor = "    sections = []\n    if raw <> invalid then sections = raw.Keys()\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK84 plant-V: the walk anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(
        anchor,
        '    sections = ["common", "utilities", "settings", "detail", "syncplay", "errors"]\n' + anchor))
PYEOF84V
set +e
RED84V_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED84V_RC=$?
set -e
[ "$RED84V_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the legacy six-name list is re-grown (got 0 — CHECK84 R1's ban is toothless)"
sed -n '/=== Check 84:/,$p' <<<"$RED84V_OUT" | grep -qF "legacy six-name section list is re-grown" || fail "CHECK84 must convict the re-grown legacy list (got: $RED84V_OUT)"
[ "$(sed -n '/=== Check 84:/,$p' <<<"$RED84V_OUT" | grep -c 'CHECK84 R')" -eq 1 ] || fail "CHECK84 must report exactly its 1 R1 conviction for the list plant (got: $RED84V_OUT)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED84V_OUT" | grep -q "^  PASS\$" || fail "Check 22 (rotated dynamic-walk arm — the walk survives this plant) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 83:/,$p' <<<"$RED84V_OUT" | grep -q "^  PASS\$" || fail "Check 83 (log/Location custody) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 82:/,/=== Check 83:/p' <<<"$RED84V_OUT" | grep -q "^  PASS\$" || fail "Check 82 (media-lane TLS boundary) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED84V_OUT" | grep -q "^  PASS\$" || fail "Check 81 (entropy seeding) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED84V_OUT" | grep -q "^  PASS\$" || fail "Check 80 (join-anchor custody) must stay PASS while Check 84 is red (gate independence)"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED75_REPO/source/lib/Utilities.brs"

# red-W: the err_bad_url closing period stripped - the en_US copy law was
# measured TOTAL at cure (every connect.err_* ends in terminal punctuation);
# one outlier re-opening is exactly the drift class R2 refuses. Only R2 may
# notice (select_track stays sentence-case inside the same conviction's
# sibling arm — which stays silent).
python3 - <<'PYEOF84W'
import os
p = os.path.join(os.environ["RED75_REPO"], "locale/en_US/strings.json")
anchor = '"err_bad_url": "That address isn\'t valid. Include the full URL, like http://192.168.1.100:8096.",'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK84 plant-W: the err_bad_url anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, '"err_bad_url": "That address isn\'t valid. Include the full URL, like http://192.168.1.100:8096",'))
PYEOF84W
set +e
RED84W_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED84W_RC=$?
set -e
[ "$RED84W_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when an err_* sentence loses its closing period (got 0 — CHECK84 R2 is toothless)"
sed -n '/=== Check 84:/,$p' <<<"$RED84W_OUT" | grep -qF "err_bad_url" || fail "CHECK84 must convict the stripped period by name (got: $RED84W_OUT)"
[ "$(sed -n '/=== Check 84:/,$p' <<<"$RED84W_OUT" | grep -c 'CHECK84 R')" -eq 1 ] || fail "CHECK84 must report exactly its 1 R2 conviction for the period plant (got: $RED84W_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED84W_OUT" | grep -q "^  PASS\$" || fail "Check 21 (cross-locale key mirror — values may differ) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 83:/,$p' <<<"$RED84W_OUT" | grep -q "^  PASS\$" || fail "Check 83 (log/Location custody) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 82:/,/=== Check 83:/p' <<<"$RED84W_OUT" | grep -q "^  PASS\$" || fail "Check 82 (media-lane TLS boundary) must stay PASS while Check 84 is red (gate independence)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED84W_OUT" | grep -q "^  PASS\$" || fail "Check 25 (XML chrome value mirror — this plant touches no mirrored value) must stay PASS while Check 84 is red (gate independence)"
cp "$FAKE_REPO/locale/en_US/strings.json" "$RED75_REPO/locale/en_US/strings.json"

GREEN84_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN84_RC=$?
[ "$GREEN84_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK84 plants are removed (got $GREEN84_RC — output: $GREEN84_OUT)"
assert_contains "CHECK84: the nested probe walks EVERY shipped section" "$GREEN84_OUT"

# --- Check 85 red legs (MN-7 chapters node / MN-9 retry overscan), same scratch repo ---
# red-X: the chapters pane swapped back to a plain <List> - the exact dead-pane
# shape MN-7 cured (renders no rows, never fires itemSelected). Only R1 may
# notice; the attr-keep law stays silent because the regex looks INSIDE the
# MarkupList tag that is now gone, and the observer never moved.
python3 - <<'PYEOF85X'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/AudiobookPlayerScene.xml")
anchor = '            <MarkupList height="200" width="840" translation="[10,240]"\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK85 plant-X: the chapter node anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, anchor.replace("<MarkupList", "<List", 1)))
PYEOF85X
set +e
RED85X_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED85X_RC=$?
set -e
[ "$RED85X_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the chapters pane regrows as a plain List (got 0 — CHECK85 R1 is toothless)"
sed -n '/=== Check 85:/,$p' <<<"$RED85X_OUT" | grep -qF "not MarkupList - a plain List draws no rows" || fail "CHECK85 must convict the regrown dead pane (got: $RED85X_OUT)"
[ "$(sed -n '/=== Check 85:/,$p' <<<"$RED85X_OUT" | grep -c 'CHECK85 R')" -eq 1 ] || fail "CHECK85 must report exactly its 1 R1 conviction for the chapter plant (got: $RED85X_OUT)"
sed -n '/=== Check 84:/,$p' <<<"$RED85X_OUT" | grep -q "^  PASS\$" || fail "Check 84 (probe enumeration + copy law) must stay PASS while Check 85 is red (gate independence)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED85X_OUT" | grep -q "^  PASS\$" || fail "Check 25 (XML chrome literals - the chapter node carries no text) must stay PASS while Check 85 is red (gate independence)"
sed -n '/=== Check 83:/,/=== Check 84:/p' <<<"$RED85X_OUT" | grep -q "^  PASS\$" || fail "Check 83 (log/Location custody) must stay PASS while Check 85 is red (gate independence)"
cp "$FAKE_REPO/components/AudiobookPlayerScene.xml" "$RED75_REPO/components/AudiobookPlayerScene.xml"

# red-Y: the retry button re-escapes to [1100,682] - bottom/right deep in the
# overscan band, the control a 4:3 set hides. Only the absence law may fire
# (the arithmetic law is deliberately suppressed for this exact revert so a
# single regression writes a single line - disclosed in the leg itself).
python3 - <<'PYEOF85Y'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/HomeScene.xml")
anchor = 'translation="[1056,644]"'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK85 plant-Y: the retry slot anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, 'translation="[1100,682]"'))
PYEOF85Y
set +e
RED85Y_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED85Y_RC=$?
set -e
[ "$RED85Y_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the retry button re-escapes into overscan (got 0 — CHECK85 R2 is toothless)"
sed -n '/=== Check 85:/,$p' <<<"$RED85Y_OUT" | grep -qF "retryButton escaped to" || fail "CHECK85 must convict the escaped retry slot (got: $RED85Y_OUT)"
[ "$(sed -n '/=== Check 85:/,$p' <<<"$RED85Y_OUT" | grep -c 'CHECK85 R')" -eq 1 ] || fail "CHECK85 must report exactly its 1 R2 conviction for the retry plant - the arithmetic-suppression guard failed (got: $RED85Y_OUT)"
sed -n '/=== Check 84:/,$p' <<<"$RED85Y_OUT" | grep -q "^  PASS\$" || fail "Check 84 (probe enumeration) must stay PASS while Check 85 is red (gate independence)"
sed -n '/=== Check 29:/,/=== Check 30:/p' <<<"$RED85Y_OUT" | grep -q "^  PASS\$" || fail "Check 29 (header keywalk walks .brs names, not XML slots) must stay PASS while Check 85 is red (gate independence)"
sed -n '/=== Check 32:/,/=== Check 33:/p' <<<"$RED85Y_OUT" | grep -q "^  PASS\$" || fail "Check 32 (rail-slot overlap ignores the retry tag) must stay PASS while Check 85 is red (gate independence)"
cp "$FAKE_REPO/components/HomeScene.xml" "$RED75_REPO/components/HomeScene.xml"

GREEN85_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN85_RC=$?
[ "$GREEN85_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK85 plants are removed (got $GREEN85_RC — output: $GREEN85_OUT)"
assert_contains "CHECK85: the chapters pane renders through the component its observer was" "$GREEN85_OUT"

# --- Check 86 red legs (MJ-13 spoken-label custody), same scratch repo ---
# red-Z: the continue-rail item mirror deleted (R1 alone).
python3 - <<'PYEOF86Z'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/HomeScene.brs")
anchor = "            accessibleLabel: nm\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK86 plant-Z: the continue-rail mirror anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF86Z
set +e
RED86Z_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED86Z_RC=$?
set -e
[ "$RED86Z_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the continue-rail accessibleLabel mirror is deleted (got 0 — CHECK86 R1 is toothless)"
sed -n '/=== Check 86:/,$p' <<<"$RED86Z_OUT" | grep -qF "CHECK86 R1:" || fail "CHECK86 must convict the lost builder mirror (got: $RED86Z_OUT)"
[ "$(sed -n '/=== Check 86:/,$p' <<<"$RED86Z_OUT" | grep -c 'CHECK86 R')" -eq 1 ] || fail "CHECK86 R1 plant must fire exactly its 1 conviction (got: $RED86Z_OUT)"
sed -n '/=== Check 85:/,/=== Check 86:/p' <<<"$RED86Z_OUT" | grep -q "^  PASS\$" || fail "Check 85 (browse chrome sibling) must stay PASS while Check 86 is red (gate independence)"
sed -n '/=== Check 84:/,/=== Check 85:/p' <<<"$RED86Z_OUT" | grep -q "^  PASS\$" || fail "Check 84 (copy-law sibling) must stay PASS while Check 86 is red (gate independence)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED75_REPO/components/HomeScene.brs"

# red-AA: one rail container label pair deleted (R2 alone).
python3 - <<'PYEOF86AA'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/HomeScene.brs")
anchor = '    n = m.top.findNode("upNextGrid")\n    if n <> invalid then n.accessibleLabel = Translate("common_up_next")\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK86 plant-AA: the rail-label anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, ""))
PYEOF86AA
set +e
RED86AA_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED86AA_RC=$?
set -e
[ "$RED86AA_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when a rail container label is deleted (got 0 — CHECK86 R2 is toothless)"
sed -n '/=== Check 86:/,$p' <<<"$RED86AA_OUT" | grep -qF "CHECK86 R2: expected 3 rail labels" || fail "CHECK86 must convict the rail-trio count (got: $RED86AA_OUT)"
[ "$(sed -n '/=== Check 86:/,$p' <<<"$RED86AA_OUT" | grep -c 'CHECK86 R')" -eq 1 ] || fail "CHECK86 R2 plant must fire exactly its 1 conviction (got: $RED86AA_OUT)"
sed -n '/=== Check 85:/,/=== Check 86:/p' <<<"$RED86AA_OUT" | grep -q "^  PASS\$" || fail "Check 85 must stay PASS while Check 86 is red (gate independence)"
sed -n '/=== Check 84:/,/=== Check 85:/p' <<<"$RED86AA_OUT" | grep -q "^  PASS\$" || fail "Check 84 must stay PASS while Check 86 is red (gate independence)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED75_REPO/components/HomeScene.brs"

set +e
GREEN86_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN86_RC=$?
set -e
[ "$GREEN86_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK86 plants are removed (got $GREEN86_RC — output: $GREEN86_OUT)"
assert_contains "CHECK86: every grid item and the home rails carry an explicit spoken label" "$GREEN86_OUT"

# --- Check 87 red legs (MN-26/MN-21/MN-6 hygiene trio), same scratch repo ---
# red-BB: the dead favorite-save key re-grown across ALL SEVEN catalogs
# (the set moves together; CHECK87 R1 alone - parity and custody siblings
# cannot convict a symmetric re-growth).
python3 - <<'PYEOF87BB'
import os
for loc in ("de_DE", "en_US", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR"):
    p = os.path.join(os.environ["RED75_REPO"], "locale", loc, "strings.json")
    with open(p, encoding="utf-8") as f:
        text = f.read()
    assert text.count('    "error_favorite_save_message"') == 1, \
        "CHECK87 plant-BB: the message-sibling anchor drifted in " + loc
    assert text.count('"error_favorite_save":') == 0, \
        "CHECK87 plant-BB: the dead key is not buried in " + loc
    text = text.replace(
        '    "error_favorite_save_message"',
        '    "error_favorite_save": "Error",\n    "error_favorite_save_message"',
        1,
    )
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
PYEOF87BB
set +e
RED87BB_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED87BB_RC=$?
set -e
[ "$RED87BB_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the dead favorite-save key is re-grown x7 (got 0 - CHECK87 R1 is toothless)"
sed -n '/=== Check 87:/,$p' <<<"$RED87BB_OUT" | grep -qF "CHECK87 R1:" || fail "CHECK87 must convict the re-grown dead key (got: $RED87BB_OUT)"
[ "$(sed -n '/=== Check 87:/,$p' <<<"$RED87BB_OUT" | grep -c 'CHECK87 R')" -eq 1 ] || fail "CHECK87 R1 plant must fire exactly its 1 conviction (got: $RED87BB_OUT)"
sed -n '/=== Check 21:/,/=== Check 22:/p' <<<"$RED87BB_OUT" | grep -q "^  PASS\$" || fail "Check 21 (locale parity) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED87BB_OUT" | grep -q "^  PASS\$" || fail "Check 48 (credential custody, same catalogs) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 86:/,$p' <<<"$RED87BB_OUT" | grep -q "^  PASS\$" || fail "Check 86 (spoken-label sibling) must stay PASS while Check 87 is red (gate independence)"
for L in de_DE en_US es_ES fr_FR it_IT ja_JP pt_BR; do
	cp "$FAKE_REPO/locale/$L/strings.json" "$RED75_REPO/locale/$L/strings.json"
done

# red-CC: splash_width re-shipped in the manifest (R2 alone).
python3 - <<'PYEOF87CC'
import os
p = os.path.join(os.environ["RED75_REPO"], "manifest")
anchor = "splash_color=#1a1a2e\nsplash_min_time=2000\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK87 plant-CC: the splash-block anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "splash_color=#1a1a2e\nsplash_width=1280\nsplash_min_time=2000\n", 1))
PYEOF87CC
set +e
RED87CC_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED87CC_RC=$?
set -e
[ "$RED87CC_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when splash_width re-ships (got 0 - CHECK87 R2 is toothless)"
sed -n '/=== Check 87:/,$p' <<<"$RED87CC_OUT" | grep -qF "CHECK87 R2:" || fail "CHECK87 must convict the re-shipped undocumented key (got: $RED87CC_OUT)"
[ "$(sed -n '/=== Check 87:/,$p' <<<"$RED87CC_OUT" | grep -c 'CHECK87 R')" -eq 1 ] || fail "CHECK87 R2 plant must fire exactly its 1 conviction (got: $RED87CC_OUT)"
sed -n '/=== Check 38:/,/=== Check 39:/p' <<<"$RED87CC_OUT" | grep -q "^  PASS\$" || fail "Check 38 (ui_resolutions plane law, same file) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 39:/,/=== Check 40:/p' <<<"$RED87CC_OUT" | grep -q "^  PASS\$" || fail "Check 39 (rsg_version law, same file) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 86:/,$p' <<<"$RED87CC_OUT" | grep -q "^  PASS\$" || fail "Check 86 (spoken-label sibling) must stay PASS while Check 87 is red (gate independence)"
cp "$FAKE_REPO/manifest" "$RED75_REPO/manifest"

# red-DD: the password field cap stripped (R3 alone, names passwordInput).
python3 - <<'PYEOF87DD'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/LoginScene.xml")
anchor = '                         hintText="Password"\n                         maxLength="255"\n'
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK87 plant-DD: the password-cap anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, '                         hintText="Password"\n', 1))
PYEOF87DD
set +e
RED87DD_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED87DD_RC=$?
set -e
[ "$RED87DD_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the password cap is stripped (got 0 - CHECK87 R3 is toothless)"
sed -n '/=== Check 87:/,$p' <<<"$RED87DD_OUT" | grep -qF "passwordInput has no maxLength" || fail "CHECK87 must name the naked password field (got: $RED87DD_OUT)"
[ "$(sed -n '/=== Check 87:/,$p' <<<"$RED87DD_OUT" | grep -c 'CHECK87 R')" -eq 1 ] || fail "CHECK87 R3 plant must fire exactly its 1 conviction (got: $RED87DD_OUT)"
sed -n '/=== Check 25:/,/=== Check 26:/p' <<<"$RED87DD_OUT" | grep -q "^  PASS\$" || fail "Check 25 (XML-literal net, same files) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 84:/,/=== Check 85:/p' <<<"$RED87DD_OUT" | grep -q "^  PASS\$" || fail "Check 84 (copy-law sibling) must stay PASS while Check 87 is red (gate independence)"
sed -n '/=== Check 86:/,$p' <<<"$RED87DD_OUT" | grep -q "^  PASS\$" || fail "Check 86 (spoken-label sibling) must stay PASS while Check 87 is red (gate independence)"
cp "$FAKE_REPO/components/LoginScene.xml" "$RED75_REPO/components/LoginScene.xml"

set +e
GREEN87_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN87_RC=$?
set -e
[ "$GREEN87_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after all three CHECK87 plants are removed (got $GREEN87_RC - output: $GREEN87_OUT)"
assert_contains "CHECK87: the buried catalog key stays buried" "$GREEN87_OUT"

# --- Check 88 red legs (MJ-8/MN-11 shared ladder + counted writes), same scratch repo ---
# red-EE: the OS keepalive call stripped from the party dial (R2 alone - the
# ladder, re-join and watchdog lines stay; only the keepalive needle goes dry).
python3 - <<'PYEOF88EE'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/SyncPlayTask.brs")
anchor = "    m.sock.SetKeepAlive(true)\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK88 plant-EE: the keepalive anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "", 1))
PYEOF88EE
set +e
RED88EE_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED88EE_RC=$?
set -e
[ "$RED88EE_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when SetKeepAlive is stripped (got 0 - CHECK88 R2 is toothless)"
sed -n '/=== Check 88:/,$p' <<<"$RED88EE_OUT" | grep -qF "CHECK88 R2:" || fail "CHECK88 must convict the keepalive strip (got: $RED88EE_OUT)"
[ "$(sed -n '/=== Check 88:/,$p' <<<"$RED88EE_OUT" | grep -c 'CHECK88 R')" -eq 1 ] || fail "CHECK88 R2 plant must fire exactly its 1 conviction (got: $RED88EE_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED88EE_OUT" | grep -q "^  PASS\$" || fail "Check 46 (accept-vs-timeout law, same dial) must stay PASS while Check 88 is red (gate independence)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED88EE_OUT" | grep -q "^  PASS\$" || fail "Check 79 (command funnel, same file) must stay PASS while Check 88 is red (gate independence)"
sed -n '/=== Check 87:/,$p' <<<"$RED88EE_OUT" | grep -q "^  PASS\$" || fail "Check 87 (hygiene sibling) must stay PASS while Check 88 is red (gate independence)"
cp "$FAKE_REPO/components/SyncPlayTask.brs" "$RED75_REPO/components/SyncPlayTask.brs"

# red-FF: the frame send re-un-bound from its count (R3 alone - the write is
# back to a silent best-effort and the custody census reads 1 bound of 3).
python3 - <<'PYEOF88FF'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/SyncPlayTask.brs")
anchor = "    sent = m.sock.Send(frame, 0, frame.Count())\n    return sent = frame.Count()\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK88 plant-FF: the SendMessage anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "    m.sock.Send(frame, 0, frame.Count())\n    return true\n", 1))
PYEOF88FF
set +e
RED88FF_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED88FF_RC=$?
set -e
[ "$RED88FF_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the frame send ignores its write count (got 0 - CHECK88 R3 is toothless)"
sed -n '/=== Check 88:/,$p' <<<"$RED88FF_OUT" | grep -qF "CHECK88 R3:" || fail "CHECK88 must convict the re-un-bound frame send (got: $RED88FF_OUT)"
[ "$(sed -n '/=== Check 88:/,$p' <<<"$RED88FF_OUT" | grep -c 'CHECK88 R')" -eq 1 ] || fail "CHECK88 R3 plant must fire exactly its 1 conviction (got: $RED88FF_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED88FF_OUT" | grep -q "^  PASS\$" || fail "Check 46 (accept-vs-timeout law) must stay PASS while Check 88 is red (gate independence)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED88FF_OUT" | grep -q "^  PASS\$" || fail "Check 79 (command funnel pairing) must stay PASS while Check 88 is red (gate independence)"
sed -n '/=== Check 87:/,$p' <<<"$RED88FF_OUT" | grep -q "^  PASS\$" || fail "Check 87 (hygiene sibling) must stay PASS while Check 88 is red (gate independence)"
cp "$FAKE_REPO/components/SyncPlayTask.brs" "$RED75_REPO/components/SyncPlayTask.brs"

set +e
GREEN88_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN88_RC=$?
set -e
[ "$GREEN88_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK88 plants are removed (got $GREEN88_RC - output: $GREEN88_OUT)"
assert_contains "CHECK88: the party leg rides the shared ladder" "$GREEN88_OUT"

# --- Check 89 red legs (MJ-10 coalesced burst + receiver deadband), same scratch repo ---
# red-GG: the per-key broadcast re-grown in SeekRelative (R1 alone - the
# coalescer def survives, only the tail law reverts to spam).
python3 - <<'PYEOF89GG'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = "    ScheduleSyncSeekBroadcast(position, newPosition)\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK89 plant-GG: the schedule-tail anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "    SyncBroadcastSeekMs(position, newPosition)\n", 1))
PYEOF89GG
set +e
RED89GG_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED89GG_RC=$?
set -e
[ "$RED89GG_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when SeekRelative re-spams per key (got 0 - CHECK89 R1 is toothless)"
sed -n '/=== Check 89:/,$p' <<<"$RED89GG_OUT" | grep -qF "CHECK89 R1:" || fail "CHECK89 must convict the re-grown per-key broadcast (got: $RED89GG_OUT)"
[ "$(sed -n '/=== Check 89:/,$p' <<<"$RED89GG_OUT" | grep -c 'CHECK89 R')" -eq 1 ] || fail "CHECK89 R1 plant must fire exactly its 1 conviction (got: $RED89GG_OUT)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED89GG_OUT" | grep -q "^  PASS\$" || fail "Check 50 (attribution banners in the same file) must stay PASS while Check 89 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED89GG_OUT" | grep -q "^  PASS\$" || fail "Check 80 (anchor adoption, same arm family) must stay PASS while Check 89 is red (gate independence)"
sed -n '/=== Check 88:/,$p' <<<"$RED89GG_OUT" | grep -q "^  PASS\$" || fail "Check 88 (shared-ladder sibling) must stay PASS while Check 89 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

# red-HH: the play-arm deadband stripped (R2 alone - dup gate survives).
python3 - <<'PYEOF89HH'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
anchor = ("        if seconds# <> m.lastRemoteSeekSec and Abs(seconds# - pos#) >= 0.75 then\n"
          "            m.videoPlayer.seek = seconds#\n"
          "            m.lastRemoteSeekSec = seconds#\n"
          "        end if\n        m.videoPlayer.control = \"play\"\n")
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK89 plant-HH: the play-arm deadband anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "        if seconds# <> m.lastRemoteSeekSec then\n            m.videoPlayer.seek = seconds#\n            m.lastRemoteSeekSec = seconds#\n        end if\n        m.videoPlayer.control = \"play\"\n", 1))
PYEOF89HH
set +e
RED89HH_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED89HH_RC=$?
set -e
[ "$RED89HH_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the play-arm deadband is stripped (got 0 - CHECK89 R2 is toothless)"
sed -n '/=== Check 89:/,$p' <<<"$RED89HH_OUT" | grep -qF "CHECK89 R2:" || fail "CHECK89 must convict the deadband-less play arm (got: $RED89HH_OUT)"
[ "$(sed -n '/=== Check 89:/,$p' <<<"$RED89HH_OUT" | grep -c 'CHECK89 R')" -eq 1 ] || fail "CHECK89 R2 plant must fire exactly its 1 conviction (got: $RED89HH_OUT)"
sed -n '/=== Check 50:/,/=== Check 51:/p' <<<"$RED89HH_OUT" | grep -q "^  PASS\$" || fail "Check 50 (attribution banners in the same file) must stay PASS while Check 89 is red (gate independence)"
sed -n '/=== Check 80:/,/=== Check 81:/p' <<<"$RED89HH_OUT" | grep -q "^  PASS\$" || fail "Check 80 (anchor adoption, same arm family) must stay PASS while Check 89 is red (gate independence)"
sed -n '/=== Check 88:/,$p' <<<"$RED89HH_OUT" | grep -q "^  PASS\$" || fail "Check 88 (shared-ladder sibling) must stay PASS while Check 89 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

set +e
GREEN89_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN89_RC=$?
set -e
[ "$GREEN89_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK89 plants are removed (got $GREEN89_RC - output: $GREEN89_OUT)"
assert_contains "CHECK89: the host seek storm lands as one trailing broadcast" "$GREEN89_OUT"

# --- Check 90 red legs (MN-12 reassembly + MN-13 window), same scratch repo ---
# red-KK: the fragment append stripped (R1 alone - the opener latches but the
# continuation never grows the frame, so the party message is still lost).
python3 - <<'PYEOF90KK'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/SyncPlayProtocol.brs")
anchor = "                                    m.fragBytes.Append(payBA)\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK90 plant-KK: the fragment-append anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "", 1))
PYEOF90KK
set +e
RED90KK_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED90KK_RC=$?
set -e
[ "$RED90KK_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the fragment append is stripped (got 0 - CHECK90 R1 is toothless)"
sed -n '/=== Check 90:/,$p' <<<"$RED90KK_OUT" | grep -qF "CHECK90 R1:" || fail "CHECK90 must convict the stripped append (got: $RED90KK_OUT)"
[ "$(sed -n '/=== Check 90:/,$p' <<<"$RED90KK_OUT" | grep -c 'CHECK90 R')" -eq 1 ] || fail "CHECK90 R1 plant must fire exactly its 1 conviction (got: $RED90KK_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED90KK_OUT" | grep -q "^  PASS\$" || fail "Check 79 (command funnel) must stay PASS while Check 90 is red (gate independence)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED90KK_OUT" | grep -q "^  PASS\$" || fail "Check 81 (protocol entropy, same file) must stay PASS while Check 90 is red (gate independence)"
sed -n '/=== Check 89:/,$p' <<<"$RED90KK_OUT" | grep -q "^  PASS\$" || fail "Check 89 (seek-storm sibling) must stay PASS while Check 90 is red (gate independence)"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED75_REPO/source/lib/SyncPlayProtocol.brs"

# red-LL: the RTT ceiling re-narrowed to the starvation value (R2 alone -
# the rotated headless pins stay honest, the protocol lies beside them).
python3 - <<'PYEOF90LL'
import os
p = os.path.join(os.environ["RED75_REPO"], "source/lib/SyncPlayProtocol.brs")
anchor = "        MAX_RTT: 5000\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK90 plant-LL: the MAX_RTT anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "        MAX_RTT: 1000\n", 1))
PYEOF90LL
set +e
RED90LL_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED90LL_RC=$?
set -e
[ "$RED90LL_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when MAX_RTT re-narrows (got 0 - CHECK90 R2 is toothless)"
sed -n '/=== Check 90:/,$p' <<<"$RED90LL_OUT" | grep -qF "CHECK90 R2:" || fail "CHECK90 must convict the re-narrowed ceiling (got: $RED90LL_OUT)"
[ "$(sed -n '/=== Check 90:/,$p' <<<"$RED90LL_OUT" | grep -c 'CHECK90 R')" -eq 1 ] || fail "CHECK90 R2 plant must fire exactly its 1 conviction (got: $RED90LL_OUT)"
sed -n '/=== Check 81:/,/=== Check 82:/p' <<<"$RED90LL_OUT" | grep -q "^  PASS\$" || fail "Check 81 (protocol entropy, same file) must stay PASS while Check 90 is red (gate independence)"
sed -n '/=== Check 88:/,/=== Check 89:/p' <<<"$RED90LL_OUT" | grep -q "^  PASS\$" || fail "Check 88 (shared ladder, same module) must stay PASS while Check 90 is red (gate independence)"
sed -n '/=== Check 89:/,$p' <<<"$RED90LL_OUT" | grep -q "^  PASS\$" || fail "Check 89 (seek-storm sibling) must stay PASS while Check 90 is red (gate independence)"
cp "$FAKE_REPO/source/lib/SyncPlayProtocol.brs" "$RED75_REPO/source/lib/SyncPlayProtocol.brs"

set +e
GREEN90_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN90_RC=$?
set -e
[ "$GREEN90_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK90 plants are removed (got $GREEN90_RC - output: $GREEN90_OUT)"
assert_contains "CHECK90: the frame stream reassembles and the sync clock is monotonic" "$GREEN90_OUT"

# --- Check 91 red legs (MN-14 per-pass envelope + app unwrap), same scratch repo ---
# red-MM: the direct per-frame write re-grown in the hub relay (R1 alone - the
# queue survives but the hot path bypasses it, and the BAN regex convicts).
python3 - <<'PYEOF91MM'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/HubCommandTask.brs")
anchor = "        m.pendingEvents.Push({\n            kind: \"pending_command\""
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK91 plant-MM: the queue-push anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "        EmitEvent({\n            kind: \"pending_command\"", 1))
PYEOF91MM
set +e
RED91MM_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED91MM_RC=$?
set -e
[ "$RED91MM_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the relay re-grows its per-frame write (got 0 - CHECK91 R1 is toothless)"
sed -n '/=== Check 91:/,$p' <<<"$RED91MM_OUT" | grep -qF "CHECK91 R1:" || fail "CHECK91 must convict the re-grown direct write (got: $RED91MM_OUT)"
[ "$(sed -n '/=== Check 91:/,$p' <<<"$RED91MM_OUT" | grep -c 'CHECK91 R')" -eq 1 ] || fail "CHECK91 R1 plant must fire exactly its 1 conviction (got: $RED91MM_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED91MM_OUT" | grep -q "^  PASS\$" || fail "Check 79 (command funnel) must stay PASS while Check 91 is red (gate independence)"
sed -n '/=== Check 88:/,/=== Check 89:/p' <<<"$RED91MM_OUT" | grep -q "^  PASS\$" || fail "Check 88 (shared ladder, same tasks) must stay PASS while Check 91 is red (gate independence)"
sed -n '/=== Check 90:/,$p' <<<"$RED91MM_OUT" | grep -q "^  PASS\$" || fail "Check 90 (stream/clock sibling) must stay PASS while Check 91 is red (gate independence)"
cp "$FAKE_REPO/components/HubCommandTask.brs" "$RED75_REPO/components/HubCommandTask.brs"

# red-NN: the batch branch token defused in the app-side unwrap (R2 alone -
# the envelope would ship but nothing unwraps it; dispatch call + guard law
# survive inside their subs, so ONLY the branch condition convicts).
python3 - <<'PYEOF91NN'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PhlixApp.brs")
anchor = "    if data.kind = \"batch\" then\n"
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK91 plant-NN: the unwrap anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "    if data.kind = \"batch_never_ships\" then\n", 1))
PYEOF91NN
set +e
RED91NN_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED91NN_RC=$?
set -e
[ "$RED91NN_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the unwrap branch is defused (got 0 - CHECK91 R2 is toothless)"
sed -n '/=== Check 91:/,$p' <<<"$RED91NN_OUT" | grep -qF "CHECK91 R2:" || fail "CHECK91 must convict the defused unwrap (got: $RED91NN_OUT)"
[ "$(sed -n '/=== Check 91:/,$p' <<<"$RED91NN_OUT" | grep -c 'CHECK91 R')" -eq 1 ] || fail "CHECK91 R2 plant must fire exactly its 1 conviction (got: $RED91NN_OUT)"
sed -n '/=== Check 45:/,/=== Check 46:/p' <<<"$RED91NN_OUT" | grep -q "^  PASS\$" || fail "Check 45 (guard law, extended arm) must stay PASS while Check 91 is red (gate independence)"
sed -n '/=== Check 89:/,/=== Check 90:/p' <<<"$RED91NN_OUT" | grep -q "^  PASS\$" || fail "Check 89 (seek-storm sibling) must stay PASS while Check 91 is red (gate independence)"
sed -n '/=== Check 90:/,$p' <<<"$RED91NN_OUT" | grep -q "^  PASS\$" || fail "Check 90 (stream/clock sibling) must stay PASS while Check 91 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED75_REPO/components/PhlixApp.brs"

set +e
GREEN91_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN91_RC=$?
set -e
[ "$GREEN91_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK91 plants are removed (got $GREEN91_RC - output: $GREEN91_OUT)"
assert_contains "CHECK91: the hub relay ships one envelope per recv pass" "$GREEN91_OUT"

# --- Check 92 red legs (MN-4 copy nudge + MN-23 boot re-gate), same scratch repo ---
# red-OO: the ShowLogin boot gate stripped (R2 alone - the predicate leaves the
# boot path; the docblock truth and catalogs stay honest, Check 48 sleeps on).
python3 - <<'PYEOF92OO'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PhlixApp.brs")
anchor = ("    if ServerUrlUsesCleartextToRemoteHost(GetServerUrl()) then\n"
          "        ShowConnect()\n        return\n    end if\n\n")
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(anchor) == 1, "CHECK92 plant-OO: the boot-gate anchor drifted (%d found)" % text.count(anchor)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(anchor, "", 1))
PYEOF92OO
set +e
RED92OO_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED92OO_RC=$?
set -e
[ "$RED92OO_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the boot re-gate is stripped (got 0 - CHECK92 R2 is toothless)"
sed -n '/=== Check 92:/,$p' <<<"$RED92OO_OUT" | grep -qF "CHECK92 R2:" || fail "CHECK92 must convict the stripped boot gate (got: $RED92OO_OUT)"
[ "$(sed -n '/=== Check 92:/,$p' <<<"$RED92OO_OUT" | grep -c 'CHECK92 R')" -eq 1 ] || fail "CHECK92 R2 plant must fire exactly its 1 conviction (got: $RED92OO_OUT)"
sed -n '/=== Check 44:/,/=== Check 45:/p' <<<"$RED92OO_OUT" | grep -q "^  PASS\$" || fail "Check 44 (boot-flow sibling) must stay PASS while Check 92 is red (gate independence)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED92OO_OUT" | grep -q "^  PASS\$" || fail "Check 48 (the consent gate itself) must stay PASS while Check 92 is red (gate independence)"
sed -n '/=== Check 91:/,/=== Check 92:/p' <<<"$RED92OO_OUT" | grep -q "^  PASS\$" || fail "Check 91 (liveness sibling) must stay PASS while Check 92 is red (gate independence)"
cp "$FAKE_REPO/components/PhlixApp.brs" "$RED75_REPO/components/PhlixApp.brs"

# red-PP: the stale 'never re-gated' residual re-grown over the MN-23 truth
# (R3 alone - and CHECK48 PROVABLY sleeps on the sentence: it pins the gate
# and its speakable keys, never prose. That silence is the disclosed design.)
python3 - <<'PYEOF92PP'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/ConnectScene.brs")
truth = ("' MN-23: boot rides THIS SAME law - PhlixApp ShowLogin() re-gates a\n"
         "' server_url persisted by a PRE-consent-law build: a cleartext REMOTE\n"
         "' origin is routed back to THIS screen instead of riding into a silent\n"
         "' credential POST. No ungated boot path remains (the stale 'pinned by\n"
         "' CHECK48's docblock leg' self-claim was corrected with this cure -\n"
         "' CHECK48 pins the gate and its SPEAKABLE keys, not this prose).")
residual = ("' Residual (honest, pinned by CHECK48's docblock leg): a URL persisted by a\n"
            "' PRE-consent-law build is never re-gated on boot (storage is read\n"
            "' directly); it fails closed into THIS screen on any transport error, and\n"
            "' re-connecting must pass the gate again.")
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count(truth) == 1, "CHECK92 plant-PP: the MN-23 truth anchor drifted (%d found)" % text.count(truth)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(truth, residual, 1))
PYEOF92PP
set +e
RED92PP_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED92PP_RC=$?
set -e
[ "$RED92PP_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the stale residual is re-grown (got 0 - CHECK92 R3 is toothless)"
sed -n '/=== Check 92:/,$p' <<<"$RED92PP_OUT" | grep -qF "CHECK92 R3:" || fail "CHECK92 must convict the re-grown residual (got: $RED92PP_OUT)"
[ "$(sed -n '/=== Check 92:/,$p' <<<"$RED92PP_OUT" | grep -c 'CHECK92 R')" -eq 1 ] || fail "CHECK92 R3 plant must fire exactly its 1 conviction (got: $RED92PP_OUT)"
sed -n '/=== Check 48:/,/=== Check 49:/p' <<<"$RED92PP_OUT" | grep -q "^  PASS\$" || fail "Check 48 MUST stay PASS under the prose plant - the disclosed proof it pins no sentence (got: $RED92PP_OUT)"
sed -n '/=== Check 91:/,/=== Check 92:/p' <<<"$RED92PP_OUT" | grep -q "^  PASS\$" || fail "Check 91 (liveness sibling) must stay PASS while Check 92 is red (gate independence)"
cp "$FAKE_REPO/components/ConnectScene.brs" "$RED75_REPO/components/ConnectScene.brs"

set +e
GREEN92_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN92_RC=$?
set -e
[ "$GREEN92_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK92 plants are removed (got $GREEN92_RC - output: $GREEN92_OUT)"
assert_contains "CHECK92: the empty hand gets a nudge and the pre-consent origin meets the gate at boot" "$GREEN92_OUT"

# --- Check 93 red legs (MN-2 resume percent + MN-3 admin Live TV hop), same scratch repo ---
# red-QQ: the builder's percent line stripped -> R1 alone (the fold survives but is
# orphaned - the card silently loses its line; the label/walk siblings sleep on).
python3 - <<'PYEOF93QQ'
import os
p = os.environ["RED75_REPO"] + "/components/HomeScene.brs"
with open(p, encoding="utf-8") as f:
    lines = f.readlines()
kept = [l for l in lines if "ShortDescriptionLine2: ContinueWatchPercent(item)" not in l]
assert len(lines) - len(kept) == 1, "CHECK93 plant-QQ: the builder line drifted (%d removed)" % (len(lines) - len(kept))
with open(p, "w", encoding="utf-8") as f:
    f.writelines(kept)
PYEOF93QQ
set +e
RED93QQ_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED93QQ_RC=$?
set -e
[ "$RED93QQ_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the builder percent line is stripped (got 0 - CHECK93 R1 is toothless)"
sed -n '/=== Check 93:/,$p' <<<"$RED93QQ_OUT" | grep -qF "CHECK93 R1:" || fail "CHECK93 must convict the orphaned fold (got: $RED93QQ_OUT)"
[ "$(sed -n '/=== Check 93:/,$p' <<<"$RED93QQ_OUT" | grep -c 'CHECK93 R')" -eq 1 ] || fail "CHECK93 QQ plant must fire exactly its 1 R1 conviction (got: $RED93QQ_OUT)"
sed -n '/=== Check 29:/,/=== Check 30:/p' <<<"$RED93QQ_OUT" | grep -q "^  PASS\$" || fail "Check 29 (header-walk sibling) must stay PASS under the QQ plant (got: $RED93QQ_OUT)"
sed -n '/=== Check 86:/,/=== Check 87:/p' <<<"$RED93QQ_OUT" | grep -q "^  PASS\$" || fail "Check 86 (spoken-label sibling) must stay PASS under the QQ plant (got: $RED93QQ_OUT)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED75_REPO/components/HomeScene.brs"

# red-RR: the settings->tv hop's admin gate stripped -> R2 alone. Check 29's walk
# law provably stays green under it (measured 2026-11-03): the gate is R2 turf,
# not the edge-existence law's - the twin keeps that separation honest.
python3 - <<'PYEOF93RR'
import os
p = os.environ["RED75_REPO"] + "/components/HomeScene.brs"
with open(p, encoding="utf-8") as f:
    text = f.read()
needle = 'else if m.headerCol = "settings" and m.isAdmin and m.tvButton <> invalid then'
assert text.count(needle) == 1, "CHECK93 plant-RR: the walk-edge needle drifted (%d found)" % text.count(needle)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(needle, needle.replace("m.isAdmin and ", ""), 1))
PYEOF93RR
set +e
RED93RR_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED93RR_RC=$?
set -e
[ "$RED93RR_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the hop's admin gate is stripped (got 0 - CHECK93 R2 is toothless)"
sed -n '/=== Check 93:/,$p' <<<"$RED93RR_OUT" | grep -qF "CHECK93 R2:" || fail "CHECK93 must convict the ungated hop (got: $RED93RR_OUT)"
[ "$(sed -n '/=== Check 93:/,$p' <<<"$RED93RR_OUT" | grep -c 'CHECK93 R')" -eq 1 ] || fail "CHECK93 RR plant must fire exactly its 1 R2 conviction (got: $RED93RR_OUT)"
sed -n '/=== Check 29:/,/=== Check 30:/p' <<<"$RED93RR_OUT" | grep -q "^  PASS\$" || fail "Check 29 (walk-shape law) MUST stay PASS under the RR plant - the gate is R2 turf (got: $RED93RR_OUT)"
sed -n '/=== Check 32:/,/=== Check 33:/p' <<<"$RED93RR_OUT" | grep -q "^  PASS\$" || fail "Check 32 (restore-arm sibling) must stay PASS under the RR plant (got: $RED93RR_OUT)"
cp "$FAKE_REPO/components/HomeScene.brs" "$RED75_REPO/components/HomeScene.brs"

set +e
GREEN93_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN93_RC=$?
set -e
[ "$GREEN93_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK93 plants are removed (got $GREEN93_RC - $GREEN93_OUT)"
assert_contains "CHECK93: the resume rail says where you left off and the admin meets Live TV" "$GREEN93_OUT"

# red-SS: the task join branch's canonical gate stripped -> CHECK94 R1 alone.
# Checks 46/79 read the very file and arm this plant touches (scheme/accept and
# funnel laws) and must sleep through it - the canonical-check is R1's turf.
python3 - <<'PYEOF94SS'
import os
p = os.environ["RED75_REPO"] + "/components/SyncPlayTask.brs"
with open(p, encoding="utf-8") as f:
    text = f.read()
needle = (
    '        if cmd.DoesExist("password_hash") and type(cmd.password_hash) = "roString" then\n'
    '            if IsCanonicalPasswordHash(cmd.password_hash) then\n'
    '                payload.password_hash = cmd.password_hash\n'
    '            end if\n'
    '        end if')
cured = (
    '        if cmd.DoesExist("password_hash") and type(cmd.password_hash) = "roString" then\n'
    '            payload.password_hash = cmd.password_hash\n'
    '        end if')
assert text.count(needle) == 1, "CHECK94 plant-SS: the join-arm gate drifted (%d found)" % text.count(needle)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(needle, cured, 1))
PYEOF94SS
set +e
RED94SS_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED94SS_RC=$?
set -e
[ "$RED94SS_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the join gate is stripped (got 0 - CHECK94 R1 is toothless)"
sed -n '/=== Check 94:/,$p' <<<"$RED94SS_OUT" | grep -qF "CHECK94 R1:" || fail "CHECK94 must convict the ungated digest carry (got: $RED94SS_OUT)"
[ "$(sed -n '/=== Check 94:/,$p' <<<"$RED94SS_OUT" | grep -c 'CHECK94 R')" -eq 1 ] || fail "CHECK94 SS plant must fire exactly its 1 R1 conviction (got: $RED94SS_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED94SS_OUT" | grep -q "^  PASS\$" || fail "Check 46 (origin/accept law over this very file) MUST stay PASS under the SS plant (got: $RED94SS_OUT)"
sed -n '/=== Check 79:/,/=== Check 80:/p' <<<"$RED94SS_OUT" | grep -q "^  PASS\$" || fail "Check 79 (command funnel, same arm) must stay PASS under the SS plant (got: $RED94SS_OUT)"
sed -n '/=== Check 93:/,/=== Check 94:/p' <<<"$RED94SS_OUT" | grep -q "^  PASS\$" || fail "Check 93 (percent/hop sibling) must stay PASS under the SS plant (got: $RED94SS_OUT)"
cp "$FAKE_REPO/components/SyncPlayTask.brs" "$RED75_REPO/components/SyncPlayTask.brs"

# red-TT: an Asc( scan re-grown inside the canonical gate -> CHECK94 R2 alone.
# R2's leaf law is SHAPE custody - the gate must keep the pinned IsHex40-
# family range-compare idiom its headless pins byte-assert. (The era comment
# here claimed "BrightScript HAS NO Asc()"; that generalization was FALSE -
# Asc is real, modeled by bsc, implemented by brs, live at four Utilities
# sites - and the MJ-2 lane's own in-lane headless crash belongs to the brs
# typed-formal class; see the 2026-11-04 CHANGELOG correction.) R2's leaf law
# owns the conviction, and the task carry,
# the panel, the mint and the docs (R1/R3/R4/R5) plus the Utilities-reading
# siblings (Checks 46/87) must all sleep through the comment-adjacent code swap.
python3 - <<'PYEOF94TT'
import os
p = os.environ["RED75_REPO"] + "/source/lib/Utilities.brs"
with open(p, encoding="utf-8") as f:
    text = f.read()
needle = '        if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")) then return false'
plant = ('        o = Asc(c)\n'
         '        if not ((o >= 48 and o <= 57) or (o >= 97 and o <= 102)) then return false')
assert text.count(needle) == 1, "CHECK94 plant-TT: the range-idiom line drifted (%d found)" % text.count(needle)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(needle, plant, 1))
PYEOF94TT
set +e
RED94TT_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED94TT_RC=$?
set -e
[ "$RED94TT_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the fabricated Asc( shape re-grows (got 0 - CHECK94 R2 is toothless)"
sed -n '/=== Check 94:/,$p' <<<"$RED94TT_OUT" | grep -qF "CHECK94 R2:" || fail "CHECK94 must convict the Asc( fabrication (got: $RED94TT_OUT)"
[ "$(sed -n '/=== Check 94:/,$p' <<<"$RED94TT_OUT" | grep -c 'CHECK94 R')" -eq 1 ] || fail "CHECK94 TT plant must fire exactly its 1 R2 conviction (got: $RED94TT_OUT)"
sed -n '/=== Check 46:/,/=== Check 47:/p' <<<"$RED94TT_OUT" | grep -q "^  PASS\$" || fail "Check 46 (roEVPDigest sibling law) MUST stay PASS under the TT plant (got: $RED94TT_OUT)"
sed -n '/=== Check 87:/,/=== Check 88:/p' <<<"$RED94TT_OUT" | grep -q "^  PASS\$" || fail "Check 87 (Utilities ENUM-comment hygiene) must stay PASS under the TT plant (got: $RED94TT_OUT)"
sed -n '/=== Check 93:/,/=== Check 94:/p' <<<"$RED94TT_OUT" | grep -q "^  PASS\$" || fail "Check 93 (percent/hop sibling) must stay PASS under the TT plant (got: $RED94TT_OUT)"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED75_REPO/source/lib/Utilities.brs"

set +e
GREEN94_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN94_RC=$?
set -e
[ "$GREEN94_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK94 plants are removed (got $GREEN94_RC - $GREEN94_OUT)"
assert_contains "join-by-code custody" "$GREEN94_OUT"

# --- CHECK99 (w14L1 era, LW-034): the vendored contracts registry pin is
# proven NON-SELF-REFERENTIAL right here in the twin. The fixture rides the
# fake repo via the whole-tests cp -a, so plant-UU corrupts ONE registry
# member in a scratch copy and the gate must fire exactly two lines — the R1
# md5 refusal and the R2 census-vs-registry drift naming both sides — while
# the checks that read the census itself (Check 22) and the immediately
# preceding era (Check 98) sleep through. Plant-VV reverts the RT-041 digest
# routing to the M-041A inline split — the regression the headless battery
# provably cannot convict (the roEVPDigest leg stops above the loop) — and
# must fire exactly its two R3 lines with the census legs and CHECK94's
# canonical-gate turf green. Restore between; final run exits 0 with the
# CHECK99 PASS phrase.
python3 - <<'PYEOF99UU'
import os
p = os.environ["RED75_REPO"] + "/tests/fixtures/error-codes.json"
with open(p, encoding="utf-8") as f:
    text = f.read()
needle = '"syncplay.queue_limit_exceeded"'
assert text.count(needle) == 1, "CHECK99 plant-UU: the registry needle drifted (%d found)" % text.count(needle)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(needle, '"syncplay.queue_limit_renamed_x9"', 1))
PYEOF99UU
set +e
RED99UU_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED99UU_RC=$?
set -e
[ "$RED99UU_RC" -ne 0 ] || fail "verify-runtime.sh must exit non-zero when a vendored registry member is renamed (got 0 - CHECK99 R1/R2 are toothless)"
sed -n '/=== Check 99:/,$p' <<<"$RED99UU_OUT" | grep -qF "CHECK99 R1:" || fail "CHECK99 must convict the md5 divergence (got: $RED99UU_OUT)"
sed -n '/=== Check 99:/,$p' <<<"$RED99UU_OUT" | grep -qF "CHECK99 R2:" || fail "CHECK99 must convict the census-vs-registry drift (got: $RED99UU_OUT)"
[ "$(sed -n '/=== Check 99:/,$p' <<<"$RED99UU_OUT" | grep -c 'CHECK99 R')" -eq 2 ] || fail "CHECK99 UU plant must fire exactly its 2 convictions R1+R2 (got: $RED99UU_OUT)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED99UU_OUT" | grep -q "^  PASS\$" || fail "Check 22 (census content pin — reads Utilities, not the fixture) MUST stay PASS under the UU plant (got: $RED99UU_OUT)"
sed -n '/=== Check 98:/,/=== Check 99:/p' <<<"$RED99UU_OUT" | grep -q "^  PASS\$" || fail "Check 98 (era sibling) must stay PASS under the UU plant (got: $RED99UU_OUT)"
cp "$FAKE_REPO/tests/fixtures/error-codes.json" "$RED75_REPO/tests/fixtures/error-codes.json"

python3 - <<'PYEOF99VV'
import os
p = os.environ["RED75_REPO"] + "/source/lib/Utilities.brs"
with open(p, encoding="utf-8") as f:
    text = f.read()
needle = (
    "    for each b in Utf8BytesFromString(plain)\n"
    "        src.Push(b)\n"
    "    end for")
plant = (
    "    for i = 1 to Len(plain)\n"
    "        for each b in Utf8BytesForCodePoint(Asc(Mid(plain, i, 1)))\n"
    "            src.Push(b)\n"
    "        end for\n"
    "    end for")
assert text.count(needle) == 1, "CHECK99 plant-VV: the digest routing line drifted (%d found)" % text.count(needle)
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(needle, plant, 1))
PYEOF99VV
set +e
RED99VV_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED99VV_RC=$?
set -e
[ "$RED99VV_RC" -ne 0 ] || fail "verify-runtime.sh must exit non-zero when the M-041A inline digest split regrows (got 0 - CHECK99 R3 is toothless)"
sed -n '/=== Check 99:/,$p' <<<"$RED99VV_OUT" | grep -qF "CHECK99 R3:" || fail "CHECK99 must convict the lost Utf8BytesFromString routing (got: $RED99VV_OUT)"
sed -n '/=== Check 99:/,$p' <<<"$RED99VV_OUT" | grep -qF "regrew inside SyncPlayPasswordHash" || fail "CHECK99 must name the re-grown inline split (got: $RED99VV_OUT)"
[ "$(sed -n '/=== Check 99:/,$p' <<<"$RED99VV_OUT" | grep -c 'CHECK99 R')" -eq 2 ] || fail "CHECK99 VV plant must fire exactly its 2 R3 convictions (got: $RED99VV_OUT)"
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED99VV_OUT" | grep -q "^  PASS\$" || fail "Check 22 (census law) MUST stay PASS under the VV plant (got: $RED99VV_OUT)"
sed -n '/=== Check 94:/,/=== Check 95:/p' <<<"$RED99VV_OUT" | grep -q "^  PASS\$" || fail "Check 94 (canonical-gate custody, same file - different turf) MUST stay PASS under the VV plant (got: $RED99VV_OUT)"
sed -n '/=== Check 98:/,/=== Check 99:/p' <<<"$RED99VV_OUT" | grep -q "^  PASS\$" || fail "Check 98 (era sibling) must stay PASS under the VV plant (got: $RED99VV_OUT)"
cp "$FAKE_REPO/source/lib/Utilities.brs" "$RED75_REPO/source/lib/Utilities.brs"

set +e
GREEN99_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN99_RC=$?
set -e
[ "$GREEN99_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after both CHECK99 plants are removed (got $GREEN99_RC - $GREEN99_OUT)"
assert_contains "CHECK99: the vendored registry is the contracts registry byte-for-byte" "$GREEN99_OUT"
assert_contains "=== Check 99:" "$GREEN99_OUT"

# --- Check 100 red legs (w15L9 R-A cohort custody), same scratch repo ---
# One plant per census limb: 19 single-line anchors run through a data-driven
# loop, the RT-105 routing window and its empty-branch line are dedicated
# multi-line plants, and the docs limb deletes ledger row 100. Each red run
# must fire EXACTLY the one named CHECK100 conviction with era siblings
# Check 98/99 green (gate independence), then restore. The two R105 plants
# are mutually independent: the window flip convicts the window arm only,
# the branch rewrite convicts the count arm only - each is asserted alone.
# Conviction counting: 'CHECK100 R' matches only conviction lines (the
# green-path summary and the broken-count roll-up carry no ' R' token).
for SPEC in \
"S1-detail-title|components/DetailScene.brs|TextOrEmpty(item.name)|item.name" \
"S2-detail-agg-score|components/DetailScene.brs|IsBoxedNumber(agg.score)|agg.score <> invalid" \
"S2-detail-agg-rating|components/DetailScene.brs|IsBoxedNumber(agg.rating)|agg.rating <> invalid" \
"S3a-player-title-lifts|components/PlayerScene.brs|TextOrEmpty(m.item.name)|m.item.name" \
"S3b-player-member-count|components/PlayerScene.brs|IsBoxedNumber(group.member_count)|group.member_count <> invalid" \
"S4-home-position-ticks|components/HomeScene.brs|IsBoxedNumber(cw.position_ticks)|cw.position_ticks <> invalid" \
"H-nm-item|components/HomeScene.brs|nm = TextOrEmpty(item.name)|nm = item.name" \
"H-nm-library|components/HomeScene.brs|nm = TextOrEmpty(library.name)|nm = library.name" \
"H-nm-cw-name|components/HomeScene.brs|nm = TextOrEmpty(cw.name)|nm = cw.name" \
"H-libName|components/HomeScene.brs|libName = TextOrEmpty(library.name)|libName = library.name" \
"S5b-grid-name|components/LibraryScene.brs|gridName = TextOrEmpty(item.name)|gridName = item.name" \
"S5b-grid-overview|components/LibraryScene.brs|gridOverview = TextOrEmpty(item.overview)|gridOverview = item.overview" \
"S6-chapter-window|components/AudiobookPlayerScene.brs|IsBoxedNumber(ch.start_seconds) and IsBoxedNumber(ch.end_seconds)|ch.start_seconds <> invalid and ch.end_seconds <> invalid" \
"S6-start-gate|components/AudiobookPlayerScene.brs|if ch <> invalid and IsBoxedNumber(ch.start_seconds) then|if ch <> invalid and ch.start_seconds <> invalid then" \
"AB-title|components/AudiobookPlayerScene.brs|TextOrEmpty(audiobook.title)|audiobook.title" \
"AB-author|components/AudiobookPlayerScene.brs|TextOrEmpty(audiobook.author)|audiobook.author" \
"AB-chapter-title|components/AudiobookPlayerScene.brs|TextOrEmpty(ch.title)|ch.title" \
"AB-saved-position|components/AudiobookPlayerScene.brs|IsBoxedNumber(resp.data.position_ms)|resp.data.position_ms <> invalid" \
"AB-saved-chapter|components/AudiobookPlayerScene.brs|IsBoxedNumber(resp.data.current_chapter_index)|resp.data.current_chapter_index <> invalid" \
; do
	IFS='|' read -r C100_LABEL C100_FILE C100_OLD C100_NEW <<<"$SPEC"
	C100_LABEL="$C100_LABEL" C100_FILE="$C100_FILE" C100_OLD="$C100_OLD" C100_NEW="$C100_NEW" python3 - <<'PYEOF100'
import os
p = os.path.join(os.environ["RED75_REPO"], os.environ["C100_FILE"])
with open(p, encoding="utf-8") as f:
    text = f.read()
old, new = os.environ["C100_OLD"], os.environ["C100_NEW"]
assert old in text, "CHECK100 plant-%s: anchor vanished" % os.environ["C100_LABEL"]
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(old, new, 1))
PYEOF100
	set +e
	RED100_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
	RED100_RC=$?
	set -e
	[ "$RED100_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after stripping the $C100_LABEL limb (CHECK100 R1 is toothless)"
	sed -n '/=== Check 100:/,$p' <<<"$RED100_OUT" | grep -qF "CHECK100 R1 [$C100_LABEL]:" || fail "CHECK100 must convict the $C100_LABEL limb by name (got: $RED100_OUT)"
	[ "$(sed -n '/=== Check 100:/,$p' <<<"$RED100_OUT" | grep -c 'CHECK100 R')" -eq 1 ] || fail "CHECK100 $C100_LABEL plant must fire exactly its 1 conviction (got: $RED100_OUT)"
	sed -n '/=== Check 98:/,/=== Check 99:/p' <<<"$RED100_OUT" | grep -q "^  PASS\$" || fail "Check 98 (era sibling) must stay PASS while Check 100 is red (gate independence)"
	sed -n '/=== Check 99:/,/=== Check 100:/p' <<<"$RED100_OUT" | grep -q "^  PASS\$" || fail "Check 99 (era sibling) must stay PASS while Check 100 is red (gate independence)"
	cp "$FAKE_REPO/$C100_FILE" "$RED75_REPO/$C100_FILE"
done

# R105 routing-window plant: canDirectPlay = false -> true. The window arm is
# the only limb whose shape contains that literal, so the count arms stay
# silent and exactly one named conviction may fire.
python3 - <<'PYEOF100W'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
with open(p, encoding="utf-8") as f:
    text = f.read()
assert text.count("canDirectPlay = false") == 1, "CHECK100 plant-R105W: the routing-limb anchor drifted"
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace("canDirectPlay = false", "canDirectPlay = true", 1))
PYEOF100W
set +e
RED100W_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED100W_RC=$?
set -e
[ "$RED100W_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after flipping the RT-105 routing limb (CHECK100 R1 is toothless)"
sed -n '/=== Check 100:/,$p' <<<"$RED100W_OUT" | grep -qF "CHECK100 R1 [R105-route-window]:" || fail "CHECK100 must convict the routing window by name (got: $RED100W_OUT)"
[ "$(sed -n '/=== Check 100:/,$p' <<<"$RED100W_OUT" | grep -c 'CHECK100 R')" -eq 1 ] || fail "CHECK100 R105-window plant must fire exactly its 1 conviction - the count arm stayed silent (got: $RED100W_OUT)"
sed -n '/=== Check 99:/,/=== Check 100:/p' <<<"$RED100W_OUT" | grep -q "^  PASS\$" || fail "Check 99 must stay PASS while Check 100 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

# R105 empty-branch plant: rewrite the SECOND `if streamFormat = "" then`
# (:452 leg). The window (:446) stays intact, so ONLY the count arm convicts.
python3 - <<'PYEOF100B'
import os
p = os.path.join(os.environ["RED75_REPO"], "components/PlayerScene.brs")
with open(p, encoding="utf-8") as f:
    lines = f.readlines()
hits = [i for i, l in enumerate(lines) if l.strip().startswith('if streamFormat = "" then')]
assert len(hits) == 2, "CHECK100 plant-R105B: the branch pair drifted (%s)" % hits
lines[hits[1]] = '        if streamFormat = "zz" then\n'
with open(p, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF100B
set +e
RED100B_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED100B_RC=$?
set -e
[ "$RED100B_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after rewriting the RT-105 second empty branch (CHECK100 R1 is toothless)"
sed -n '/=== Check 100:/,$p' <<<"$RED100B_OUT" | grep -qF "CHECK100 R1 [R105-empty-branches]:" || fail "CHECK100 must convict the empty-branch count by name (got: $RED100B_OUT)"
[ "$(sed -n '/=== Check 100:/,$p' <<<"$RED100B_OUT" | grep -c 'CHECK100 R')" -eq 1 ] || fail "CHECK100 R105-branch plant must fire exactly its 1 conviction - the window arm stayed silent (got: $RED100B_OUT)"
sed -n '/=== Check 99:/,/=== Check 100:/p' <<<"$RED100B_OUT" | grep -q "^  PASS\$" || fail "Check 99 must stay PASS while Check 100 is red (gate independence)"
cp "$FAKE_REPO/components/PlayerScene.brs" "$RED75_REPO/components/PlayerScene.brs"

# Docs limb plant: ledger row 100 deleted -> exactly the CHECK100 R2 line.
python3 - <<'PYEOF100D'
import os
p = os.path.join(os.environ["RED75_REPO"], "docs/static-checks.md")
with open(p, encoding="utf-8") as f:
    lines = f.readlines()
rows = [i for i, l in enumerate(lines) if l.startswith("| 100 |")]
assert len(rows) == 1, "CHECK100 plant-DOCS: ledger row 100 drifted (%s)" % rows
del lines[rows[0]]
with open(p, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF100D
set +e
RED100D_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED100D_RC=$?
set -e
[ "$RED100D_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after deleting ledger row 100 (CHECK100 R2 is toothless)"
sed -n '/=== Check 100:/,$p' <<<"$RED100D_OUT" | grep -qF "CHECK100 R2" || fail "CHECK100 must convict the missing docs row (got: $RED100D_OUT)"
sed -n '/=== Check 100:/,$p' <<<"$RED100D_OUT" | grep -qF "no row 100" || fail "CHECK100 R2 must name the vanished row (got: $RED100D_OUT)"
[ "$(sed -n '/=== Check 100:/,$p' <<<"$RED100D_OUT" | grep -c 'CHECK100 R')" -eq 1 ] || fail "CHECK100 docs plant must fire exactly its 1 R2 conviction (got: $RED100D_OUT)"
cp "$FAKE_REPO/docs/static-checks.md" "$RED75_REPO/docs/static-checks.md"

GREEN100_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN100_RC=$?
[ "$GREEN100_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after every CHECK100 plant is removed (got $GREEN100_RC — output: $GREEN100_OUT)"
assert_contains "CHECK100: every shipped limb of the RT-092 boxed-lift cohort and the" "$GREEN100_OUT"
assert_contains "=== Check 100:" "$GREEN100_OUT"

# --- Check 101 red legs (w15L9 R-B browse-failure custody), same scratch
# repo: 27 limbs, one single-token plant each (a data-driven loop), each
# firing EXACTLY one named CHECK101 R1 conviction with era siblings green.
# Plant tokens break exactly one regex arm (an X-suffix rename or a
# space-insert between Translate( and the quote — the census regexes are
# the only thing that sees them).
for SPEC in \
"fav-choke-call|components/FavoritesScene.brs|browseOutcome = FavoritesBrowseOutcome(|browseOutcome = FavoritesBrowseOutcomeX(" \
"fav-failure-write|components/FavoritesScene.brs|Translate(\"favorites_failed\")|Translate( \"favorites_failed\")" \
"fav-empty-sole-writer|components/FavoritesScene.brs|Translate(\"favorites_empty\")|Translate( \"favorites_empty\")" \
"fav-observe|components/FavoritesScene.brs|ObserveField(\"buttonSelected\", \"OnFavoritesRetryPressed\")|ObserveField(\"buttonSelected\", \"OnFavoritesRetryPressedX\")" \
"fav-unobserve|components/FavoritesScene.brs|m.retryButton.UnObserveField(\"buttonSelected\")|m.retryButton.UnObserveFieldX(\"buttonSelected\")" \
"fav-xml-retry-id|components/FavoritesScene.xml|id=\"retryButton\"|id=\"retryButtonX\"" \
"fav-xml-retry-chrome|components/FavoritesScene.xml|title=\"Retry\" focusable=\"true\"|title=\"Retry\" focusable=\"false\"" \
"sea-choke-call|components/SearchScene.brs|browseOutcome = SearchBrowseOutcome(|browseOutcome = SearchBrowseOutcomeX(" \
"sea-failure-write|components/SearchScene.brs|Translate(\"search_failed\")|Translate( \"search_failed\")" \
"sea-noresults-sole-writer|components/SearchScene.brs|Translate(\"search_no_results\")|Translate( \"search_no_results\")" \
"sea-observe|components/SearchScene.brs|ObserveField(\"buttonSelected\", \"OnSearchRetryPressed\")|ObserveField(\"buttonSelected\", \"OnSearchRetryPressedX\")" \
"sea-unobserve|components/SearchScene.brs|m.retryButton.UnObserveField(\"buttonSelected\")|m.retryButton.UnObserveFieldX(\"buttonSelected\")" \
"sea-xml-retry-id|components/SearchScene.xml|id=\"retryButton\"|id=\"retryButtonX\"" \
"sea-xml-retry-chrome|components/SearchScene.xml|title=\"Retry\" focusable=\"true\"|title=\"Retry\" focusable=\"false\"" \
"lib-choke-call|components/LibraryScene.brs|browseOutcome = LibraryBrowseOutcome(|browseOutcome = LibraryBrowseOutcomeX(" \
"lib-failed-limbs|components/LibraryScene.brs|Translate(\"library_failed\")|Translate( \"library_failed\")" \
"lib-observe|components/LibraryScene.brs|ObserveField(\"buttonSelected\", \"OnLibraryRetryPressed\")|ObserveField(\"buttonSelected\", \"OnLibraryRetryPressedX\")" \
"lib-unobserve|components/LibraryScene.brs|m.retryButton.UnObserveField(\"buttonSelected\")|m.retryButton.UnObserveFieldX(\"buttonSelected\")" \
"lib-xml-retry-id|components/LibraryScene.xml|id=\"retryButton\"|id=\"retryButtonX\"" \
"lib-xml-retry-chrome|components/LibraryScene.xml|title=\"Retry\" focusable=\"true\"|title=\"Retry\" focusable=\"false\"" \
"col-choke-call|components/CollectionScene.brs|browseOutcome = CollectionBrowseOutcome(|browseOutcome = CollectionBrowseOutcomeX(" \
"col-failed-limbs|components/CollectionScene.brs|Translate(\"collection_failed\")|Translate( \"collection_failed\")" \
"col-empty-sole-writer|components/CollectionScene.brs|Translate(\"collection_empty\")|Translate( \"collection_empty\")" \
"col-observe|components/CollectionScene.brs|ObserveField(\"buttonSelected\", \"OnCollectionRetryPressed\")|ObserveField(\"buttonSelected\", \"OnCollectionRetryPressedX\")" \
"col-unobserve|components/CollectionScene.brs|m.retryButton.UnObserveField(\"buttonSelected\")|m.retryButton.UnObserveFieldX(\"buttonSelected\")" \
"col-xml-retry-id|components/CollectionScene.xml|id=\"retryButton\"|id=\"retryButtonX\"" \
"col-xml-retry-chrome|components/CollectionScene.xml|title=\"Retry\" focusable=\"true\"|title=\"Retry\" focusable=\"false\"" \
; do
	IFS='|' read -r C101_LABEL C101_FILE C101_OLD C101_NEW <<<"$SPEC"
	C101_LABEL="$C101_LABEL" C101_FILE="$C101_FILE" C101_OLD="$C101_OLD" C101_NEW="$C101_NEW" python3 - <<'PYEOF101'
import os
p = os.path.join(os.environ["RED75_REPO"], os.environ["C101_FILE"])
with open(p, encoding="utf-8") as f:
    text = f.read()
old, new = os.environ["C101_OLD"], os.environ["C101_NEW"]
assert old in text, "CHECK101 plant-%s: anchor vanished" % os.environ["C101_LABEL"]
with open(p, "w", encoding="utf-8") as f:
    f.write(text.replace(old, new, 1))
PYEOF101
	set +e
	RED101_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
	RED101_RC=$?
	set -e
	[ "$RED101_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after breaking the $C101_LABEL limb (CHECK101 R1 is toothless)"
	sed -n '/=== Check 101:/,$p' <<<"$RED101_OUT" | grep -qF "CHECK101 R1 [$C101_LABEL]:" || fail "CHECK101 must convict the $C101_LABEL limb by name (got: $RED101_OUT)"
	[ "$(sed -n '/=== Check 101:/,$p' <<<"$RED101_OUT" | grep -c 'CHECK101 R')" -eq 1 ] || fail "CHECK101 $C101_LABEL plant must fire exactly its 1 conviction (got: $RED101_OUT)"
	sed -n '/=== Check 99:/,/=== Check 100:/p' <<<"$RED101_OUT" | grep -q "^  PASS\$" || fail "Check 99 (era sibling) must stay PASS while Check 101 is red (gate independence)"
	sed -n '/=== Check 100:/,/=== Check 101:/p' <<<"$RED101_OUT" | grep -q "^  PASS\$" || fail "Check 100 (wave sibling) must stay PASS while Check 101 is red (gate independence)"
	cp "$FAKE_REPO/$C101_FILE" "$RED75_REPO/$C101_FILE"
done

GREEN101_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN101_RC=$?
[ "$GREEN101_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after every CHECK101 plant is removed (got $GREEN101_RC — output: $GREEN101_OUT)"
assert_contains "CHECK101: every RT-094 browse scene routes failure through its" "$GREEN101_OUT"
assert_contains "=== Check 101:" "$GREEN101_OUT"

python3 - <<'PYEOF101D'
import os
p = os.path.join(os.environ["RED75_REPO"], "docs/static-checks.md")
lines = open(p, encoding="utf-8").readlines()
rows = [i for i, l in enumerate(lines) if l.startswith("| 101 |")]
assert len(rows) == 1, "CHECK101 plant-DOCS: ledger row 101 drifted (%s)" % rows
del lines[rows[0]]
open(p, "w", encoding="utf-8").writelines(lines)
PYEOF101D
set +e
RED101D_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED101D_RC=$?
set -e
[ "$RED101D_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after deleting ledger row 101 (CHECK101 R2 is toothless)"
[ "$(sed -n '/=== Check 101:/,$p' <<<"$RED101D_OUT" | grep -c 'CHECK101 R')" -eq 1 ] || fail "CHECK101 docs plant must fire exactly its 1 R2 conviction (got: $RED101D_OUT)"
cp "$FAKE_REPO/docs/static-checks.md" "$RED75_REPO/docs/static-checks.md"

# --- negative: audiobook dropped from the ENUM comment -> exit != 0 + CHECK14
export FAKE_REPO
python3 - <<'PYEOF'
import os
path = os.path.join(os.environ['FAKE_REPO'], 'source/lib/Utilities.brs')
with open(path) as f:
    lines = f.readlines()
# The ENUM comment line is the only line containing "book, photo" and
# "audiobook" together; preserve the exact "'   member, member, ..." shape so
# Check 14's regex still matches the 2-line block.
target = None
for i, line in enumerate(lines):
    if "book, photo" in line and "audiobook" in line:
        target = i
        break
assert target is not None, "ENUM comment line with audiobook not found in Utilities.brs"
assert lines[target].strip().startswith("'"), f"ENUM comment line does not start with ': {lines[target]!r}"
lines[target] = lines[target].replace(", audiobook", "")
with open(path, 'w') as f:
    f.writelines(lines)
PYEOF

set +e
NEG_OUT=$(bash "$FAKE_REPO/scripts/verify-runtime.sh" 2>&1)
NEG_RC=$?
set -e

[ "$NEG_RC" -ne 0 ] || fail "verify-runtime.sh should exit non-zero when the ENUM comment drops audiobook (got 0)"
assert_contains "CHECK14" "$NEG_OUT"

# --- (13) validate-xml zero-file-guard legs (estate CI-gate audit 2026-10-02)
# The pre-fix `make validate-xml` glob loop exited 0 on a ZERO-file discovery —
# a path-pattern regression silently greened the gate. scripts/validate-xml.sh
# counts what it finds and halts loud. W-min92/M-ROKU-19 extended the same
# fail-loud DNA to discovery SHAPE and PARSE DEPTH: recursive walk (nested
# directories no longer invisible) + a real xml.etree well-formedness parse
# (the two substring greps could never convict a malformed document whose
# markers merely exist). These legs run the REAL script directly
# (it derives its default scan root from its own location, so no cwd
# dependency): (a) real components/ green, (b) empty scratch root red + loud,
# (c) missing root red, (d) planted malformed XML red naming the plant, plant
# removed green (falsifiability + extraction fidelity), (e) NESTED malformed
# plant convicted by relative path (the flat-glob hole), (f) plant that passes
# both legacy greps yet is not well-formed convicted by the parser (the
# substring-era hole). FAKE_REPO untouched by this family. --
VALIDATE_XML="$REAL_REPO/scripts/validate-xml.sh"
[ -f "$VALIDATE_XML" ] || fail "validate-xml: scripts/validate-xml.sh missing from $REAL_REPO — the extracted gate must exist"

# (13a) positive: the real repo's components/ validates green through the script.
set +e
VX_OUT=$(bash "$VALIDATE_XML" 2>&1)
VX_RC=$?
set -e
[ "$VX_RC" -eq 0 ] || fail "validate-xml should exit 0 on the real components/ dir (got $VX_RC): $VX_OUT"
assert_contains "XML validation passed" "$VX_OUT"

# (13b) negative: an EMPTY scratch root must fire the zero-discovery guard.
EMPTY_XML_ROOT="$TEST_ROOT/empty-components"
mkdir -p "$EMPTY_XML_ROOT"
set +e
VX_EMPTY_OUT=$(bash "$VALIDATE_XML" "$EMPTY_XML_ROOT" 2>&1)
VX_EMPTY_RC=$?
set -e
[ "$VX_EMPTY_RC" -ne 0 ] || fail "validate-xml should exit non-zero when ZERO XML files are discovered (got 0) — the vacuous-pass hole is back"
assert_contains "discovered ZERO XML files" "$VX_EMPTY_OUT"

# (13c) negative: a MISSING scan root must be refused outright.
set +e
VX_MISSING_OUT=$(bash "$VALIDATE_XML" "$TEST_ROOT/no-such-components" 2>&1)
VX_MISSING_RC=$?
set -e
[ "$VX_MISSING_RC" -ne 0 ] || fail "validate-xml should exit non-zero when the components dir is missing (got 0)"
assert_contains "does not exist" "$VX_MISSING_OUT"

# (13d) negative+restore: a planted malformed XML in a scratch COPY of the real
# components must still fire the structure ERROR naming the plant (proves the
# extraction preserved the original per-file behavior), and removing the plant
# must return the run to exit 0.
VX_PLANT_ROOT="$TEST_ROOT/vx-plant-components"
mkdir -p "$VX_PLANT_ROOT"
cp -a "$REAL_REPO/components"/. "$VX_PLANT_ROOT/"
printf '<Component id="PlantedBroken">\n</Component>\n' >"$VX_PLANT_ROOT/PlantedBroken.xml"
set +e
VX_PLANT_OUT=$(bash "$VALIDATE_XML" "$VX_PLANT_ROOT" 2>&1)
VX_PLANT_RC=$?
set -e
[ "$VX_PLANT_RC" -ne 0 ] || fail "validate-xml should exit non-zero when a malformed XML is planted (got 0)"
assert_contains "PlantedBroken.xml - invalid structure" "$VX_PLANT_OUT"
rm "$VX_PLANT_ROOT/PlantedBroken.xml"
set +e
VX_RESTORE_OUT=$(bash "$VALIDATE_XML" "$VX_PLANT_ROOT" 2>&1)
VX_RESTORE_RC=$?
set -e
[ "$VX_RESTORE_RC" -eq 0 ] || fail "validate-xml must return to exit 0 after the malformed plant is removed (got $VX_RESTORE_RC): $VX_RESTORE_OUT"
assert_contains "XML validation passed" "$VX_RESTORE_OUT"

# (13e) negative: the FLAT-GLOB hole (M-ROKU-19, W-min92). A malformed XML in
# a NESTED directory must be convicted by its path relative to the scan root —
# the pre-cure script only globbed components/*.xml, so nested files had ZERO
# coverage while total_files stayed above the zero-guard.
VX_NEST_ROOT="$TEST_ROOT/vx-nested-components"
mkdir -p "$VX_NEST_ROOT"
cp -a "$REAL_REPO/components"/. "$VX_NEST_ROOT/"
mkdir -p "$VX_NEST_ROOT/panel/nested"
printf '<component>\n</component>\n' >"$VX_NEST_ROOT/panel/nested/NestedBroken.xml"
set +e
VX_NEST_OUT=$(bash "$VALIDATE_XML" "$VX_NEST_ROOT" 2>&1)
VX_NEST_RC=$?
set -e
[ "$VX_NEST_RC" -ne 0 ] || fail "validate-xml should exit non-zero when a MALFORMED XML hides in a nested directory (flat-glob silent-zero hole, got 0)"
assert_contains "panel/nested/NestedBroken.xml - invalid structure" "$VX_NEST_OUT"
rm "$VX_NEST_ROOT/panel/nested/NestedBroken.xml"
rmdir "$VX_NEST_ROOT/panel/nested" "$VX_NEST_ROOT/panel"
set +e
VX_NEST_RESTORE_OUT=$(bash "$VALIDATE_XML" "$VX_NEST_ROOT" 2>&1)
VX_NEST_RESTORE_RC=$?
set -e
[ "$VX_NEST_RESTORE_RC" -eq 0 ] || fail "validate-xml must return to exit 0 after the nested plant is removed (got $VX_NEST_RESTORE_RC): $VX_NEST_RESTORE_OUT"
assert_contains "XML validation passed" "$VX_NEST_RESTORE_OUT"

# (13f) negative: the SUBSTRING-ERA hole (M-ROKU-19, W-min92). A file whose
# first line carries '<?xml version' AND which contains a '</component>' text
# somewhere — so BOTH legacy greps pass — yet whose document is not
# well-formed (tag soup after the root close) must be convicted by the real
# parser. This is the leg the grep-era script could never pass: it proves the
# cure went deeper than discovery shape.
VX_SOUP_ROOT="$TEST_ROOT/vx-soup-components"
mkdir -p "$VX_SOUP_ROOT"
printf '<?xml version="1.0" encoding="UTF-8" ?>\n<component>\n</component>\n</component>\n' >"$VX_SOUP_ROOT/SubstringSurvivor.xml"
set +e
VX_SOUP_OUT=$(bash "$VALIDATE_XML" "$VX_SOUP_ROOT" 2>&1)
VX_SOUP_RC=$?
set -e
[ "$VX_SOUP_RC" -ne 0 ] || fail "validate-xml should exit non-zero on a file that passes both legacy substring greps but is NOT well-formed XML (got 0) — the parse depth is the cure"
assert_contains "SubstringSurvivor.xml - invalid structure" "$VX_SOUP_OUT"
assert_contains "not well-formed" "$VX_SOUP_OUT"

# --- Check 75 R5 red leg (RT-096 DEVELOPER.md custody), same scratch repo ---
python3 - <<'PYEOF75R5'
import os
p = os.path.join(os.environ["RED75_REPO"], "DEVELOPER.md")
with open(p, encoding="utf-8") as f:
    text = f.read()
assert "R5 escape probe" not in text, "CHECK75 R5 plant: the probe string pre-exists"
with open(p, "w", encoding="utf-8") as f:
    f.write(text + "\n`LibraryManager` owns library browsing on the device (R5 escape probe).\n")
PYEOF75R5
set +e
RED75R5_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
RED75R5_RC=$?
set -e
[ "$RED75R5_RC" -ne 0 ] || fail "verify-runtime.sh stayed green after pasting a live-tense fictional manager back into DEVELOPER.md (got 0 — CHECK75 R5 is toothless)"
sed -n '/=== Check 75:/,$p' <<<"$RED75R5_OUT" | grep -qF "CHECK75 R5: a fictional manager is named live-tense again" || fail "CHECK75 must convict the live-tense manager row by name (got: $RED75R5_OUT)"
[ "$(grep -c 'CHECK75 R5:' <<<"$RED75R5_OUT")" -eq 1 ] || fail "the R5 plant must fire exactly its 1 conviction (got: $RED75R5_OUT)"
sed -n '/=== Check 74:/,/=== Check 75:/p' <<<"$RED75R5_OUT" | grep -q "^  PASS\$" || fail "Check 74 (sibling doc law) must stay PASS while Check 75 R5 is red (gate independence)"
cp "$FAKE_REPO/DEVELOPER.md" "$RED75_REPO/DEVELOPER.md"
GREEN75R5_OUT=$(bash "$RED75_REPO/scripts/verify-runtime.sh" 2>&1)
GREEN75R5_RC=$?
[ "$GREEN75R5_RC" -eq 0 ] || fail "verify-runtime.sh must return to exit 0 after the R5 plant is removed (got $GREEN75R5_RC — output: $GREEN75R5_OUT)"

echo "PASS: verify-runtime.sh is portable — CI-layout positive run (exit 0, Check 14 PASS on 034_media_items_type_audiobook.sql, Check 11-26 + 35 + 37-41 + 43-61 headers present, CHECK21 + CHECK22 + CHECK23 + CHECK24 + CHECK25 + CHECK26 green) + ja_JP device-locale resolution leg (all literal Translate keys resolve with no en_US fallback) + Check 21 red leg (missing mirror key -> CHECK21 fired, Check 14/20/22/23/24 gates stayed green) + Check 22 content-pin red legs (rogue 21st census code -> CHECK22 fired naming it; rogue declaration in the post-flip EMPTY reserved ledger -> CHECK22 reserved-drift leg fired; removing SyncPlayReservedErrorCodes() entirely -> CHECK22 existence leg fired, the declaration gate stays armed; Check 21 stayed green all three runs) + Check 23 red legs (orphan errors key -> CHECK23 purity fired with CHECK22 green; raw EmitError literal -> CHECK23 fired, Check 21/22 gates stayed green) + Check 24 red leg (token key concatenated raw -> CHECK24 fired with file:line, Check 20/21/22/23 gates stayed green) + Check 19 exempt-anchoring red leg (prose ' for ' literal fired CHECK19 while a real for-header line stayed exempt, Check 20/21/22/23/24 gates stayed green; the RT-095 raw-argument escape leg (a ShowErrorDialog call hiding ONE raw literal beside a Translate sibling - the class the legacy >=3-literal arm waved through for two review eras - fired CHECK19 naming the literal exactly once on its own scratch, Check 20/25 green)) + Check 25 red leg (planted raw XML chrome label -> CHECK25 fired naming file:line, Check 20/21/22/23/24 gates stayed green) + Check 26 red leg (planted envelope-level resp.libraries read -> CHECK26 fired naming file and read, Check 20/24/25 gates stayed green) + Check 20 dotted-key red leg (planted Translate(\"player.playback_error\") -> CHECK20 fired naming file, dotted key and underscore suggestion with CHECKs 21-26 green; plant removed -> exit 0, falsifiability proven) + Check 39 rsg_version red leg+restore (planted rsg_version=7.0 + stripped rationale comment -> CHECK39 fired R2 naming the illegal value and R4, with the sibling manifest readers CHECK18/CHECK38 stayed green — gate independence; cured manifest restored -> exit 0, falsifiability proven) + M-ROKU-08 aggregation red leg+restore (planted CHECK1 violation in leg 1 -> exit non-zero with the violation printed and CHECK20/21/39 gates stayed green — single-sink accumulator, re-zeroing any cured-range leg reddens this leg; plant removed -> exit 0) + Check 40 dead-design red leg+restore (planted unreachable function + ghost documented flag -> CHECK40 fired R1 and R2 naming both plants, with CHECK18/CHECK39 gate independence; cured script restored -> exit 0 — designed-but-dead versioning machinery can no longer accumulate silently) + Check 41 signing-honesty red leg+restore (planted the phantom password-env claim, the rename-into-.pkg fallback, a hardcoded PKG_VERSION default and a self-signed-sideload echo into a scratch package-signed.sh plus an un-provisioned package-signed stub job into a scratch package.yml, a sagas.xml + sideload-testing pair into a scratch docs/publishing.md and a line-wrapped only-sideloads claim into a scratch README.md -> CHECK41 fired R1/R2/R3/R4/R5 naming each plant — the README plant proving the whitespace-join is wrap-tolerant — with CHECK18/CHECK40 gate independence; cured files restored -> exit 0 — a mislabeled 'signed' artifact, a phantom-secret claim or a fabricated package-contract file cannot return silently) + Check 42 channel-identity/diagnostics red leg+restore (stripping one send-site X-Phlix-Client-Version header, planting the \"1.0.1\" About literal and retargeting the multi-line block onto the non-wrapping statusLabel -> CHECK42 fired R1/R2/R6 naming each plant, with CHECK41/CHECK20 gate independence; cured files restored -> exit 0 — retail-user version visibility cannot silently regress) + Check 43 wire-text type-guard red leg+restore (planted SEVEN arms into a scratch DetailScene — raw resp.error lift, resp.data.message literal-compare, lcase(env.message), the \"Server error: \" + resp.error concat, the IsTransportReason(resp.error) typed-sink call, and the two R-ROKU-04 cover plants (a bare-Type(kind)=\"String\" line carrying a raw resp04cover.error compare, a resp04hole.message<>\"String\" compare — both ran GREEN under the former coarse token, measured at 349933e) -> CHECK43 fired all seven naming file, rule and read, with CHECK26/CHECK41 gate independence; plant removed -> exit 0; a sanctioned-gate run planting ONLY the wire-bound type(x.error)=\"String\" shapes (bare + compare-sharing) stayed exit 0 — hostile untyped wire text cannot re-enter a render-path String operation silently, no path stays exempt from the law, and the tightening cannot over-convict the idiom family it audits) + Check 44 dial-completion red leg+restore (stripping the hub-relay mint X-Phlix-Client-Version AddHeader in a scratch copy -> CHECK44 fired R1 naming components/HubCommandTask.brs, with CHECK42 gate independence; cured file restored -> exit 0 — the WebSocket/relay version disclosure cannot silently regress) + Check 45 content-id shape-gate red leg+restore (re-planting the era invalid/empty relay guard into a scratch PhlixApp and re-fattening the scratch main.brs launch validator into the printable loop fired CHECK45 R2/R4 naming files and rules, with CHECK43/CHECK44 gate independence; cured files restored -> exit 0 — a malformed content id can never silently re-enter the authenticated path-injection class) + Check 46 SyncPlay origin/accept red leg+restore (stripping the PlayerScene origin choke, neutralising the SyncPlayTask accept verification and stripping the accept parser's blank-line stop in a scratch copy fired CHECK46 R1/R2 naming all three files — including the r1 MAJOR-1 body-spoof tooth — with CHECK44/CHECK45 gate independence; cured files restored -> exit 0 — the main account JWT can never silently re-ride a cleartext handshake behind a TLS origin, a forged 101 without accept proof can never re-enter session scope, and a body line can never silently impersonate a header again) + Check 46 R2-prose platform-misclaim red leg+restore (M-ROKU-22: re-growing the wss-impossibility heading ('wss:// is impossible') and the 'Roku cannot do TLS' clause in a scratch README fired both rotated blacklist arms naming README.md, with CHECK44/CHECK45 gate independence; restore -> exit 0 — the transport limitation can never again ship as a false platform impossibility; wss is deferred, refusal is the law) + Check 47 bootstrap-Back/boot-retry red leg+restore (re-swallowing Back in a scratch ConnectScene and returning the boot chrome to the trap era — no SetFocus, per-error re-observe — fired CHECK47 R1 and R2 naming the scene and each defect, with CHECK46/CHECK44 gate independence; both plants restored -> exit 0 — a signed-out user can never again be trapped by a disabled Back on the first screens met, and a visible Retry can never again be unpressable) + Check 49 toast-display red leg+restore (re-extending the overlay onto Scene with phantom chrome, re-growing the ToastScene.brs mechanics script, re-planting the ComponentController display write + stripping the wasClosed drain observer, and unwiring the PlayerScene scope singleton fired CHECK49 R1/R2/R3/R4/R6 naming each plant, with CHECK47/CHECK48 gate independence; all plants restored -> exit 0 — the ambient-feedback layer can never again silently address a fabricated node, nor a scope's notices die at an unwired singleton) + Check 50 party-attribution red leg+restore (orphaning the banner label id in a scratch PlayerScene.xml and stripping the pause-arm NotifyPartyEvent call in a scratch PlayerScene.brs fired CHECK50 R1 and R3 naming each file, with CHECK46/CHECK48 gate independence; both plants restored -> exit 0 — host-driven transport changes and party events can never again run silent mid-playback, and the attribution banner can never be re-nested behind the panel) + Check 49 R7 dispatch plant red leg+restore (re-growing the retired node.PostMessage wire + the silent pre-attach drop and stripping the root observer wiring and receiver arm fired CHECK49 R7 naming source/lib/ToastManager.brs and components/PhlixApp.brs across ten convictions, with CHECK49 R1/R6 territory held green and CHECK47/CHECK48/CHECK50/CHECK51 gate independence; both plants removed -> exit 0 — an undocumented node-messaging door can never re-dispatch the queue, and a notice raised before setScene can never again vanish silently) + Check 51 live-copy red leg+restore (re-growing the raw session-expired sentence over the Translate write in a scratch PlayerScene.brs fired CHECK51 R1 and R2 naming the file and the sentence, with CHECK20/CHECK50 gate independence; restore -> exit 0 — the overlay trio, every sync panel status, the party banner family and the task-side fallback are catalog copy: reintroduced English is convicted file:line (Check 25 idiom) and raw-literal calls into the status/banner choke points are rejected; an ad-hoc second probe reverting the connected-banner and the SyncPlayTask fallback to raw literals fired three named CHECK51 pins jointly with CHECK50 R4) + Check 52 failure-vs-emptiness red leg+restore (reverting ONE failure branch — ExtractData's !ok arm to the collapsed return [] — in a scratch DashboardScene.brs fired CHECK52 R1 twice naming the lost arm and the collapse detector, with CHECK48/CHECK51 gate independence; restore -> exit 0 — a failed read can never again silently render as \"(none)\" on the admin dashboard or an empty grid on the home rails) + Check 53 credential-custody-at-the-choke red leg+restore (stripping the conditional six-key wipe from a scratch ConnectScene.brs's PersistAndGo fired four CHECK53 R1 convictions naming the capture, the conditional guard, the wipe primitive and the wipe-before-write order, with CHECK48/CHECK52 gate independence; cured file restored -> exit 0 — the old host's access and refresh tokens can never again ride a /auth/me or /auth/refresh request to a newly entered server, while same-URL reconnect keeps its session) + Check 54 dial-composition/truth-presence red leg+restore (M-ROKU-22 residual: bypassing the ToggleSyncPanel hub choke, truncating the scoped ws-only heading and re-growing the vanished-history pointer in the PROTO citation fired CHECK54 R1/R2/R3 naming each plant, with CHECK46/CHECK48/CHECK53 gate independence; all three restored -> exit 0 — no second ungated SyncPlay dial site can be composed silently, and the shipped transport truth can neither lie by omission nor decay by deletion) + Check 55 hub-relay origin-refuse red leg+restore (stripping the scene choke, the task choke, the predicate and the README law paragraph in one scratch copy fired CHECK55 R1/R2/R3/R4 naming all three files, and planting a roSecureSocket instantiation in a second copy fired the R3 no-fabricated-TLS arm, with CHECK53 gate independence both reds; all plants restored -> exit 0 — the hub-minted relay token can never again silently ride a cleartext socket behind an https hub origin, and the deferred wss arm can never ship as a blind platform call) + Check 56 dead-path docs-truth red leg+restore (M-ROKU-26: re-growing a CreateObject(\"roSGNode\", \"SyncPlayScene\") site in a scratch PlayerScene.brs AND stripping the README manager-row DEAD PATH demotion fired CHECK56 R1 naming the planted site and R2 convicting the stripped row twice, with CHECK46/CHECK54 gate independence; both plants restored -> exit 0 + the r2 i18n.md trio on the same scratch (V1 deleting the \`syncplay\` consumer row, V2 rewriting it live-tense with prefix AND annotation stripped, E stripping the \`errors\` row dead marker) each fired CHECK56 naming docs/i18n.md with CHECK46/CHECK54 gate independence, each restored -> exit 0 — the SyncPlay room scene can never be silently wired while the docs call it dead, the demotion truth can never silently decay back into live-tense prose, and the i18n.md consumer surface can no longer re-claim liveness by deletion or prefix-free rewrite (r2 cure of review M-ROKU-26 r1 MAJOR-1: the conditional-shape arm's measured vacuous passes are now plants); the seven catalogs' provenance listing of the shipped room file is pinned too (R3), and red-on-parent at dc362df87 measured exactly 10 R2 convictions while the r2 rotation re-measured at f39ce22 with exactly 1 new conviction — the errors-row survivor the r1 review named — the defect class was precisely documentation) + Check 57 co-watch-one-name red leg+restore (re-growing a watch-party banner label, a sync-server error value, the Group-vs-Room default name, a parity-grown create_room2 key in all seven catalogs and the README/docs pre-cure spellings fired CHECK57 R1/R2/R3/R4 naming each plant, with CHECK20/CHECK21/CHECK25/CHECK51 gate independence; all plants restored -> exit 0 — the co-watch feature can never again ship five names on screen: user-visible vocabulary is frozen to Watch Together + group, the dead-scene room chrome stays the pinned six-key owner-gated carve-out, and the identifier key census can neither silently grow nor shrink)+ Check 58 retry-recovery-chrome red leg+restore (M-ROKU-21f, review roku__gameux M21 r2 MINOR-1: reverting the stand-down guard to failure-copy-only in a scratch HomeScene.brs fired CHECK58 R1 naming the lost recognition of the retry-stranded loading copy, and re-growing a second description-strip common_loading writer fired CHECK58 R2's sole-writer census naming the 2x write-sites — each with CHECK52/CHECK56 gate independence (same M21 family, disjoint arms); both plants restored -> exit 0 — a successful Retry can never again leave the home strip reading \"Loading...\" over a healthy app, and no second writer may load the strip's transient copy while the recognition law stands) + Check 59 changelog-release-truth red leg+restore (M-ROKU-33, review roku__writer: reverting the [latest] rolling header to the base two-header Unreleased fiction fired CHECK59 R1 naming the item plus R2 convicting the anchorless model block, and planting a tag-less versioned release header ## [v9.9.9] — the retracted phantom-ladder class — fired CHECK59 R3 naming the unbacked token, with CHECK40/CHECK57 gate independence in both reds (Check 40 pins the same vehicle law from the package.yml + publishing.md side); both plants restored -> exit 0 — published rolling-era history can never again be filed as unreleased, and no versioned release claim can enter the CHANGELOG without git-tag or version-field proof) + Check 60 structure-map red leg+restore (M-ROKU-32, review roku__writer M8: re-growing the SessionManager.brs phantom landmark in the lib block and dropping AppContext.brs from the README Project Structure map fired CHECK60 R1 and R2 each naming its file, with CHECK56/CHECK58 gate independence (same README, disjoint arms); both plants restored -> exit 0 — the map can never again ship a phantom landmark nor omit a shipped .brs: the README structure block is self-pinning against find source components -name '*.brs' bidirectionally, 57 names both sides) + Check 61 locale-family-enumeration red legs+restore (M-ROKU-37: reverting the README locale/ block to its pre-M32 one-row era fired CHECK61 R3 six times naming the omitted shipped families and README.md; reverting the i18n.md Overview headline to the bare sibling count fired R1 naming the missing family-total sentence; stripping a tree sibling fired R2; rewriting one catalog _metadata.locale onto a sibling tag fired R4 — each red keeps CHECK21/CHECK56/CHECK60 PASS (gate independence: this leg reads docs text and folder names; they read catalog contents, disjoint doc surfaces and .brs landmarks); full restore -> exit 0 with CHECK61 green — no docs inventory may silently under-enumerate, ghost, or point at a catalog that misnames its own family) + Check 62 readme-inventory/dependency-truth red leg+restore (M-ROKU-31, review roku__writer M7: one README plant re-grew the era 3-file Test Structure block plus a phantom SessionManager.test.brs, the stale suite count, the dev-false \"No external dependencies required\" sentence with the npm ci/devDependencies truth stripped, and the born-empty \"configurable constants (in source files)\" lead-in, firing CHECK62 R1/R2/R3/R4/R5 naming each plant, with CHECK52/CHECK56/CHECK58/CHECK60/CHECK61 gate independence; restore -> exit 0 — the README test inventories and dependency truth can never again drift from the shipped tree silently. NUMBERING disclosed: composed as 59 against raw tip e1d04b8f by the stalled sibling lane; Checks 59/60/61 landed meanwhile, the collision probe at f56793f8 renumbered this leg to 62 per the CHECK54/55 rebasing precedent) + Check 67 locale-value-family red leg+restore (R-ROKU-11, review M-ROKU-20 r4 observation N2: re-growing all three cured value classes in scratch catalogs — the it_IT stripped copula, the es_ES misplaced acute and the ja_JP pre-reform glyphs plus the wrong-kanji word in BOTH its cured forms — fired CHECK67 twelve times naming each catalog and value key, including a canonical-gone conviction proving a ban whose family has left the catalog cannot rot into a vacuous pin, with CHECK21/CHECK48/CHECK51 gate independence (the three legs that read these very files and slept through the r4 plant); all five plants restored -> exit 0 — a locale VALUE can no longer decay in spelling while every leg asks only a structural question) + Check 68 restoreSession-keep-on-server_error red leg+restore (R-ROKU-24, the named-candidate follow-up of fixlog/M-ROKU-04__fix-r2.md Issue 2: re-growing the pre-rider fall-through (stripping BOTH server_error keep-returns so the arms wipe again) AND spreading the keep to the verdict arm (an early return after session_invalid) fired CHECK68 R1 twice — each conviction naming its successor statement — plus R2 once, with CHECK36/CHECK44/CHECK48 gate independence (the boot-ladder, wire-lift and send-custody legs read the very file these plants edit and stayed green); all plants restored -> exit 0 — an answered-but-broken /auth/me can never again silently wipe credentials the server never pronounced dead, and the 401/403 verdict arm's wipe can never be softened) + Check 35 R1 balanced-walk red leg+restore (R-ROKU-25, review M-ROKU-05__r1 note 3: re-growing the evasion the day-1 first-paren-stop regex waved through — a positional call closing a nested call before its first comma, its case-blind lowercase twin, the plain positional pair, an unterminated argument list, and a positional buried inside a sanctioned single-argument call's own list — fired CHECK35 R1 five times naming file:line and each argument list (measured on the tip leg beforehand: only the plain pair convicted; the buried plant's accidental day-1 conviction came from the truncated outer match, which is exactly why the shipped walk scans every occurrence, resuming inside each argument list), while a sanctioned-shape copy (inline options-AA literal with commas inside braces + a wrapped single argument) kept the whole battery exit 0 — the walk convicts top-level commas, never mere parentheses — with CHECK34/CHECK42 gate independence (Check 42 reads this very wrapper file); plants removed -> exit 0 — the options-AA signature law no longer has a parenthesis-shaped door) + Check 69 Roku-doc-citation red leg+restore (R-ROKU-26, the M-ROKU-05 lane's disclosed out-of-scope find kept alive by fixlog/M-ROKU-05__r1.md note 4: re-growing the banned legacy docs/refer-ences URL at AppContext's first citation line AND laundering BOTH canonical ifappmanager citations onto an unreachable mirror fired CHECK69 R1 naming file:line and R2 naming the vanished page — exactly two convictions, the eight standing ifdeviceinfo siblings and the non-legacy mirror URL keeping the other arms honest — with CHECK35 (same edited file; comment-only plants are inert to its code-shape walk), CHECK42 and CHECK68 gate independence; both plants restored -> exit 0 — every Roku docs citation on the shipped surface stays on its measured canonical /dev/docs target, and a citation can neither decay back to the redirect-only path nor be deleted to fake compliance) + Check 70 relay-accept-proof red legs+restore (R-ROKU-05: stripping the relay-site Sec-WebSocket-Accept guard (the era's status-line-only posture re-grown), swapping it ABOVE the HandshakeAccepted status gate, and re-implanting a bespoke roEVPDigest computation inside WaitForConnect in scratch copies of components/HubCommandTask.brs fired CHECK70 R1/R1/R2 — one named conviction per run, exactly — with CHECK44 (reads this very file's mint + handshake map) and CHECK46 (the sibling :8097 dial's own pins) green on all three reds (gate independence); all plants restored -> exit 0 with CHECK70 green (the shipped single-line shape passing its own shape-tolerant regex is the amnesty measurement) — the :8804 command channel can never again accept a status-line-only handshake, the scoped relay token can never again ride a socket nobody proved saw our key, and the proof can never migrate out of the unit-tested trio into a bespoke reimplementation) + Check 71 boot-auth-timer red legs+restore (R-ROKU-06: re-growing the fabricated ms-setter at the first start site fired R1 file:line + R2 shape-loss (exactly two convictions — a method cannot return without the dual conviction), re-growing the bare stop-method inside OnAuthTimeout fired R1 + R3 (exactly two), and laundering the ms VALUE onto the correct field name (duration = 20000) at the second start site fired the boundary-checked R2 ALONE (exactly one, R1 silent) — with CHECK47 and CHECK66, which read these very bodies, green on all three reds (gate independence); all plants restored -> exit 0 with CHECK71 green (the shipped shapes passing their own boundary-checked regexes is the amnesty measurement) — the boot-auth timeout can never again claim a unit or a cancel the Timer node does not have, the ms era can be neither re-grown as a method nor laundered as a value, and the row-49 law keeps its cure-attached marker) + Check 72 codec-probe-shape red legs+restore (R-ROKU-27: re-growing the era magic literal at the gate fired R1's three faces jointly — magic-literal ban, shipped-shape 0/1, deviating call, exactly three; silently re-pointing the accessor value to another codec fired the R2 value arm ALONE, exactly one (R1 silent — the shape held); re-growing the phantom-conditional comment sentence fired R3 ALONE, exactly one (a comment-only plant is inert to the code walk); stripping the accessor docblock's Check 72 cure-marker fired the R2 marker arm ALONE, exactly one) with CHECK35 (same wrapper, options-AA law) and CHECK69 (same files, citation law) green on all four reds (gate independence); all plants restored -> exit 0 with CHECK72 green (the shipped accessor-shape call and marker-complete docblock passing their own regexes is the amnesty measurement) — the direct-play gate can never again probe a codec it cannot know: the estate's canonical delivery codec is named in one documented accessor, inline magic literals are extinct at call sites, the fabricated defaulted-lookup sentence stays dead in the code view, and the named bet may move only where it is named) + Check 73 portable-narration-truth red legs+restore (R-ROKU-29, disclosed by fixlog/M-ROKU-04__fix-r2.md as pre-existing prose staleness predating the later legs, kept alive by RIDERS_QUEUE.md as the checks-doc candidate: re-growing the era stale under-report range in the twin PASS echo fired CHECK73 R1 ALONE, exactly one; planting an over-report that claims a pin the positive run never asserts fired R1 ALONE again (equality is bidirectional — the claim can neither lag the pins nor outrun them); reverting the ledger's Regression-test sentence to the era range fired R2 ALONE, exactly one (the twin's own echo holds the truth while the doc lags); deleting ledger row 73 fired R3 ALONE, exactly one) with CHECK71 and CHECK72 — the era-neighbor legs, whose plant sections this leg's own plants physically sit beside — green on all four reds (gate independence: this leg reads narration prose and ledger rows only, no shipped-code surface); all plants restored -> exit 0 with CHECK73 green (the twin's prose equaling the header-pin set derived from the twin's OWN assert inventory is the amnesty measurement — and the derivation self-pins: a future header assert added without rotating both prose surfaces reddens CI, exactly the drift class R-ROKU-29 names) — the portability summary can never again under-claim or over-claim what the positive run pins, and the checks-doc sentence rides the same derivation so no prose surface can rotate alone) + Check 74 form-input-attribute/node-type red legs+restore (CR-2/M-ROKU-14/15: re-growing the dead secure= attribute, planting an unlocalized hintText value, renaming the transport group back to the phantom <HStack>, and stripping all five ParentalControls hintText fields fired CHECK74 R1/R2/R4/R3 naming each plant — exactly one conviction per run, the census arm reporting the derived count alone — with CHECK25 (the sibling XML-chrome law that never scanned a single hint), CHECK56, CHECK63, CHECK66 and CHECK73 green across all four reds (gate independence); all plants restored -> exit 0 with CHECK74 green (the shipped hintText/secureMode markup and the curated tag set passing their own regexes is the amnesty measurement) — a TextEditBox can never again be markup-fiction, hint chrome can never escape the locale catalog, phantom node types can never re-instantiate as nothing on device, and the scan can never silently go vacuous) + Check 75 doc-fiction extinction red legs+restore (R-ROKU-31: appending the era install-endpoint prose to README.md, planting the install-flag fiction into a NEW docs/fiction-proof.md, the npm-global CLI claim into docs/publishing.md and the raw form-field fiction into a test.yml comment each fired exactly one CHECK75 R1 naming its file, and flipping the Makefile recipe's Install-submit marker to a foreign verb fired CHECK75 R2 ALONE with R1 silent — with CHECK41, CHECK62, CHECK65 and CHECK74 green across all five reds (gate independence: the sibling doc-scanning legs read disjoint surfaces of this very 76-file set); all plants restored -> exit 0 with CHECK75 green (the shipped 77-file surface passing its own six fragment-assembled needles, both recipe-marker pins and the RT-096 DEVELOPER.md live-tense-manager arm is the amnesty measurement) — the cured install/toolchain fictions can never silently re-enter the human-facing surface, the real recipe can never be deleted to fake compliance, and the scan can never go vacuously green) + Check 76 detail-resume-thread red legs+restore (MJ-1: stripping the resumeSeconds hand-off from PlayItem's Show call in a scratch DetailScene.brs fired CHECK76 R2 ALONE, exactly one, with the fire and read sides staying honest about their own pins; re-pointing the multiplexer response arm onto a never-matching op string fired CHECK76 R1 ALONE naming the vanished arm — with CHECK75 (adjacent extinction leg) and CHECK43 (the same file's render-path type law) green across both reds (gate independence); both plants restored -> exit 0 with CHECK76 green (the shipped four-surface thread passing its own fire/read/hand-off/consume pins is the amnesty measurement) — the detail-page resume can never silently regress to the restart-at-zero behavior the old Show docblock proudly documented) + Check 77 serverId-custody red legs+restore (MJ-18: stripping the picker's IsSafeContentId gate before the active_server_id persist fired CHECK77 R1 ALONE, exactly one; stripping the task-side dial gate fired CHECK77 R3 ALONE naming the lost choke — the read degrade and the sibling gates staying silent both times — with CHECK76 (adjacent MJ-era shape leg) and CHECK70 (the very file's relay accept-proof law) green across both reds (gate independence); both plants restored -> exit 0 with CHECK77 green (the shipped three-gate custody chain passing its own pick/read/dial pins is the amnesty measurement) — a hostile hub can never again ride an unvalidated serverId CRLF into the credential-bearing handshake through any of the three custody points) + Check 78 settings-catalog-custody red legs+restore (MJ-20: pasting a raw title back into the builder next to the translated rows fired CHECK78 R1 ALONE, exactly one file:line, the census floor/docs marker/ledger row staying silent (the ban owns paste-backs); deleting a builder entry wholesale fired CHECK78 R2 ALONE with R1 provably silent (the floor owns shrinkage - separate conviction classes by design) - with CHECK20 (the very keys resolution law) and CHECK76 (adjacent MJ-era shape leg) green across both reds (gate independence); both plants restored -> exit 0 with CHECK78 green (the shipped 27-call builder passing its own raw-ban and census-floor is the amnesty measurement) - the Settings menu can never again ship raw English beside its mirrored catalog keys) + Check 79 syncplay-command-funnel/deferred-leave-stop red legs+restore (MJ-6/MJ-7: stripping the catch-up push from the attach window fired CHECK79 R1 ALONE, exactly one — the drain-arm census, replay block and dedup laws stayed silent, the funnel reads its value and simply never queues it; re-growing the era immediate stop pair inside OnSyncLeavePressed fired CHECK79 R2 ALONE through the sole-custody census, exactly one — with CHECK46 (the sibling SyncPlay origin/accept law over these very two files) and CHECK50 (party-attribution shapes on the same scene file) green across both reds (gate independence); both plants restored -> exit 0 with CHECK79 green (the shipped funnel + deferred-stop shapes passing their own attach-window/drain/replay/census/fallback pins is the amnesty measurement) — a first-tap join can never again be swallowed before the handshake, and a leave can never again kill its own flush and ghost the member) + Check 80 join-anchor red legs+restore (MJ-9: stripping the syncAnchorApplied register from the adoption guard fired CHECK80 R1 ALONE, exactly one - the census breaches report jointly inside that one conviction; deleting the duration-clamp line fired CHECK80 R2 ALONE, exactly one, R1 provably silent - with CHECK79 (the funnel/stop-custody leg on this very scene), CHECK46 (the sibling SyncPlay origin/accept law over these very files) and CHECK50 (party-attribution shapes on the same file) green across both reds (gate independence); both plants restored -> exit 0 with CHECK80 green (the shipped adoption block passing its own register, guard, type-gate, drop, clamp, mismatch and application needles is the amnesty measurement) - a joiner can never again sit at zero while the party plays on, the host can never rubber-band its own anchor, and no adopted seek may land past the cached length or onto a title the group left behind) + Check 81 entropy-seeder red legs+restore (MJ-17: dropping the m.SeedWebSocketEntropy() call from NewWebSocketKey fired CHECK81 R2 ALONE, exactly one - the seeder definition, entropy mix and fold needles stayed silent, the key simply rode the factory clock stream again; stripping the per-install channel client id from the digest source fired CHECK81 R1 ALONE, exactly one, R2 provably silent - with CHECK79 (the funnel/stop-custody leg), CHECK80 (the join-anchor leg) and CHECK46 (the sibling origin/accept law over the very handshake this seeder protects) green across both reds (gate independence); both plants restored -> exit 0 with CHECK81 green (the shipped seeder and custody shapes passing their own mix, fold, verb and order pins is the amnesty measurement) - a blind LAN injector can never again enumerate the Sec-WebSocket-Key family from a boot-time window to forge the R-ROKU-05 accept proof) + Check 82 media-lane-custody red legs+restore (MJ-19: deleting the root-relative accept arm from the predicate fired CHECK82 R1 ALONE, exactly one - the origin-parse and downgrade needles stayed silent, relative media paths simply rode the refusal with the hostile shapes; deleting the PlayerScene gate block fired CHECK82 R2 ALONE, exactly one, R1 provably silent - with CHECK79 (the funnel/stop-custody leg), CHECK80 (the join-anchor leg), CHECK81 (the entropy-seeding leg) and CHECK43 (the wire-text type law over these very scenes) green across both reds (gate independence); both plants restored -> exit 0 with CHECK82 green (the shipped predicate and the three gated sites passing their own relative, parse, downgrade-refusal, wire-shape and custody pins is the amnesty measurement) - the TV can never again be told to fetch a signed stream in cleartext behind an https session, and no fabricated scheme or malformed host can re-enter the media node unchecked) + Check 83 log-and-Location custody red legs+restore (MN-22/MN-24: re-growing the content-bearing suppressed-detail echo in GetErrorMessage fired CHECK83 R1 ALONE, exactly one - the predicate and the task gate stayed honest, only the convicted legacy shape spoke; deleting the ResolveRedirectTarget absolutize call from resolveLocation fired CHECK83 R2 ALONE, exactly one - the three playback scheme refusals stayed silent - with CHECK79, CHECK80, CHECK81 and CHECK82 (the media-lane sibling over this very file and call chain) green across both reds (gate independence); both plants restored -> exit 0 with CHECK83 green (the shipped count-only echo, token gate and absolutization passing their own needles is the amnesty measurement) - the debug log can never again launder message-sized wire text, and a relative Location can never again reach a playback node unabsolutized) + Check 84 probe-enumeration and copy-law red legs+restore (MN-18/MN-27: re-growing the legacy six-name section list beside the dynamic walk fired CHECK84 R1 ALONE, exactly one - Check 22's rotated arm stayed green because the walk survives; the ban on the stale shape is the half that convicts, disclosed design; stripping one err_* closing period fired CHECK84 R2 ALONE, exactly one, naming the key - with CHECK21 (key mirror, values free), CHECK25 (chrome value mirror, disjoint key), CHECK82, CHECK83 green across both reds (gate independence); both plants restored -> exit 0 with CHECK84 green (the shipped walk and the measured-total copy law passing their own needles is the amnesty measurement) - the nested probe can never again lag the catalog it serves, and the en_US error family can never again reopen its punctuation drift) + Check 85 dead-pane and overscan red legs+restore (MN-7/MN-9: swapping the chapter node back to a plain List fired CHECK85 R1 ALONE, exactly one, with CHECK84 and CHECK25 (the pane owns no text literal) green; re-escaping the retry button to its old overscan slot fired CHECK85 R2 ALONE - the arithmetic law is guarded against double-writing that exact revert, disclosed in the leg - with CHECK29 (keywalk reads .brs names) and CHECK32 (rail overlap ignores the retry tag) green across both reds (gate independence); both plants restored -> exit 0 with CHECK85 green - the chapters pane can never again render through a component that draws no rows, and the one recovery control on the home screen can never again sit where a television hides it) + Check 86 spoken-label custody red legs+restore (MJ-13: deleting the continue-rail item mirror fired CHECK86 R1 ALONE, exactly one - the rail trio and the no-literal scan stayed honest; deleting one rail container pair fired CHECK86 R2 ALONE naming the count, exactly one - with CHECK85 and CHECK84 (the browse-chrome and copy-law siblings reading these very files) green across both reds (gate independence); both plants restored -> exit 0 with CHECK86 green (the shipped ten builder mirrors and rail trio passing their own census and no-literal pins is the amnesty measurement) - a grid item or a home rail can never again lose the explicit spoken label the review named) + Check 87 hygiene red legs+restore (MN-26/MN-21/MN-6: re-growing the dead favorite-save key across all seven catalogs fired CHECK87 R1 ALONE, exactly one - the set moves together, so Check 21 parity and Check 48 custody stay green; re-adding splash_width fired CHECK87 R2 ALONE with the two living manifest readers (Checks 38 and 39) green; stripping the password cap fired CHECK87 R3 ALONE naming passwordInput, with Checks 25 and 84 green; all plants restored -> exit 0 with CHECK87 green (the buried key, the documented manifest set and the capped fields pass their own census - the amnesty measurement) - a favorite dialog can never again quote an abandoned-draft headline, the channel can never again ship a key certification review bounces, and no text field can again swallow an unbounded paste) + Check 88 shared-ladder red legs+restore (MJ-8/MN-11: stripping SetKeepAlive from the party dial fired CHECK88 R2 ALONE with the accept-vs-timeout law (Check 46) and the command funnel (Check 79) green; re-un-binding the frame send from its count fired CHECK88 R3 ALONE - a silent partial write is a desynced stream and the custody census convicts it; both plants restored -> exit 0 with CHECK88 green (the shared ladder, the re-joined dial and the counted writes pass their own pins - the amnesty measurement) - the party leg can never again treat a transient drop as a funeral, and no task dial can ever again ignore a short socket write) + Check 89 seek-storm red legs+restore (MJ-10: re-growing the per-key broadcast in SeekRelative fired CHECK89 R1 ALONE with the attribution-banner law (Check 50) and the anchor adoption (Check 80) green; stripping the play-arm deadband fired CHECK89 R2 ALONE - a follower re-buffers for a position it already holds and the census convicts it; both plants restored -> exit 0 with CHECK89 green (the coalescer, the deadband and the bounded defer pass their own pins - the amnesty measurement) - a held transport key can never again flood the party with fifteen re-buffers and the local thumb never again fights the host frame-for-frame) + Check 90 stream-and-clock red legs+restore (MN-12/MN-13/MN-15: stripping the fragment append fired CHECK90 R1 ALONE - an unappended continuation is still a lost party message, and the command funnel, the protocol entropy and the seek-storm siblings stayed green; re-narrowing MAX_RTT to the starvation value fired CHECK90 R2 ALONE with its module siblings green; both plants restored -> exit 0 with CHECK90 green (the reassembly state, the breathing window and the monotonic base pass their own census - the amnesty measurement) - a split message can never again vanish in silence and an NTP step can never again forge an rtt or poison the offset buffer) + Check 91 liveness red legs+restore (MN-14/MN-20/MN-1: re-growing the relay's direct per-frame write fired CHECK91 R1 ALONE - the queue survived but the hot path bypassed it, and the command funnel, the shared ladder and the stream/clock siblings stayed green; defusing the app-side batch branch fired CHECK91 R2 ALONE with the extended guard law (Check 45) green - the envelope would ship into silence exactly like the era this check closes; both plants restored -> exit 0 with CHECK91 green (queue, unwrap, banner and play cue pass their own census - the amnesty measurement) - hub commands can never again collapse into each other on the field channel and the party can never again re-dial in silence) + Check 92 copy-and-boot red legs+restore (MN-4/MN-23: stripping the ShowLogin boot gate fired CHECK92 R2 ALONE - the predicate vanished from the boot path while the consent gate itself (Check 48) and the boot-flow siblings slept on undisturbed; re-growing the stale never-re-gated residual fired CHECK92 R3 ALONE with Check 48 PROVABLY green over the plant - the disclosed proof that leg pins the gate and its speakable keys, never prose; both plants restored -> exit 0 with CHECK92 green (the nudged catalogs, the boot re-gate and the cured docblock pass their own census - the amnesty measurement) - an exhausted search can never again dead-end without a nudge, and a pre-consent cleartext origin can never again ride boot into a silent credential POST) + Check 93 resume-rail and admin-hop red legs+restore (builder percent line stripped -> CHECK93 R1 alone with Check 29/86 siblings green; hop admin gate stripped -> CHECK93 R2 alone with Check 29/32 walk siblings provably green; both removed -> exit 0) + Check 94 join-by-code custody red legs+restore (MJ-2 deferred: the task join branch's IsCanonicalPasswordHash gate stripped -> CHECK94 R1 alone naming the malformed-carry risk, with Check 46/79 (the same file's origin/accept and funnel laws) and Check 93 green across the red; an Asc(-based scan re-grown inside IsCanonicalPasswordHash -> CHECK94 R2 alone (range-idiom loss + deviation from the pinned IsHex40-family shape, jointly convicted - shape custody, not a platform claim; the era's 'HAS NO Asc()' prose was false and is corrected in the CHANGELOG's 2026-11-04 entry), with Check 46/87 (the roEVPDigest sibling and Utilities hygiene) and Check 93 green across the red; both plants restored -> exit 0 with CHECK94 green (the shipped gate, digest leaves, panel form, seven-key mint v1.20.0 and honest docs passing their own pins is the amnesty measurement) - a malformed or plaintext digest can never again ride the join wire, and the canonical gate can never silently leave its pinned scan shape) + validate-xml zero-file-guard legs (real components/ green with count; empty scratch root -> \"discovered ZERO XML files\" red; missing root -> \"does not exist\" red; planted malformed XML -> named red, removed -> exit 0; M-ROKU-19 W-min92 extensions: nested-directory malformed plant convicted by relative path (flat-glob silent-zero hole), removed -> exit 0; and a plant passing BOTH legacy substring greps yet not well-formed convicted by the xml.etree parse (substring-era hole)) + audiobook-drift negative run (exit $NEG_RC, CHECK14 fired) + w14L1 CHECK99 legs (a vendored-registry member rename in the scratch copy fires exactly CHECK99 R1+R2 - md5 refusal + census-vs-registry drift - with Check 22 and Check 98 asleep; the M-041A inline digest revert fires exactly the two CHECK99 R3 routing lines with Checks 22/94/98 green - the headless-incapable regression convicted statically; restore -> exit 0 with the CHECK99 PASS phrase and header printed) + w15L9 CHECK101 browse-failure custody red legs+restore (each of the 27 limbs broken by a single-token plant fires exactly one named CHECK101 R1 conviction with Checks 99/100 green, and the ledger-row-101 deletion fires CHECK101 R2 alone; all restored -> exit 0 with the CHECK101 PASS phrase and header printed) + w15L9 CHECK100 cohort-custody red legs+restore (each of the 21 census limbs stripped in a scratch copy fires exactly one named CHECK100 conviction - the 19 single-line limbs through the data-driven loop, the RT-105 routing-window flip and the second empty-branch rewrite mutually independent so each fires its own arm alone, and the ledger-row deletion firing CHECK100 R2 alone - with era Checks 98/99 green on every red (gate independence); all plants restored -> exit 0 with the CHECK100 PASS phrase and header printed)"
