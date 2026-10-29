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
#                          (Checks 30-33's inputs - README + route-manifest
#                          truth, root-back exit law, surgical-wipe logout
#                          law),
#                          components/SettingsScene.brs + DetailScene.brs
#                          (Check 19's fixed target list) + SyncPlayTask.brs
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
#   (9) negative (twin-flip split, post-flip 2026-09-25): a rogue 20th code
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
#       (falsifiability, house planted-red tradition).
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
#       the positive run.
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
# Check 42 (M-ROKU-11) pins the three ApiClient send sites, the roAppInfo
# single source and the docs/debugging.md support story: both ride along.
cp "$REAL_REPO/source/lib/ApiClient.brs" "$FAKE_REPO/source/lib/ApiClient.brs"
cp "$REAL_REPO/docs/debugging.md" "$FAKE_REPO/docs/debugging.md"
# Check 47 (M-ROKU-16) R3 pins the bootstrap Back law docs truth —
# docs/navigation.md + docs/certification.md join the stage list.
cp "$REAL_REPO/docs/navigation.md" "$FAKE_REPO/docs/navigation.md"
cp "$REAL_REPO/docs/certification.md" "$FAKE_REPO/docs/certification.md"
# Check 44 (M-ROKU-11 completion) pins the task-thread version leaf in
# source/lib/SyncPlayProtocol.brs (the two task components ride via cp -a).
cp "$REAL_REPO/source/lib/SyncPlayProtocol.brs" "$FAKE_REPO/source/lib/SyncPlayProtocol.brs"
cp "$REAL_REPO/source/main.brs" "$FAKE_REPO/source/main.brs"
cp "$REAL_REPO/README.md" "$FAKE_REPO/README.md"
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
mkdir -p "$FAKE_REPO/tests/fixtures"
cp "$REAL_REPO/tests/fixtures/server-route-manifest.json" "$FAKE_REPO/tests/fixtures/server-route-manifest.json"
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
sed -n '/=== Check 22:/,$p' <<<"$RED21_OUT" | grep -q "CHECK22: all 19" ||
	fail "Check 22 must stay PASS while Check 21 is red (gate independence)"
sed -n '/=== Check 23:/,$p' <<<"$RED21_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 21 is red (gate independence)"
# CHECK24's token set is brace-driven; a non-token key (common.ok) removed
# from a mirror must not entangle the token law gate either.
sed -n '/=== Check 24:/,$p' <<<"$RED21_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 21 is red (gate independence)"

# --- Check 22 red proof (twin-flip split, leg 1): a rogue 20th code is pushed
# into the wire census without evidence or reservation. The content pin must
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
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED23B_OUT" | grep -q "CHECK22: all 19" ||
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
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED23_OUT" | grep -q "CHECK22: all 19" ||
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
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED24_OUT" | grep -q "CHECK22: all 19" ||
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
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED19_OUT" | grep -q "CHECK22: all 19" ||
	fail "Check 22 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 23:/,/=== Check 24:/p' <<<"$RED19_OUT" | grep -q "CHECK23: all" ||
	fail "Check 23 must stay PASS while Check 19 is red (gate independence)"
sed -n '/=== Check 24:/,$p' <<<"$RED19_OUT" | grep -q "CHECK24: all" ||
	fail "Check 24 must stay PASS while Check 19 is red (gate independence)"

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
sed -n '/=== Check 22:/,/=== Check 23:/p' <<<"$RED20_OUT" | grep -q "CHECK22: all 19" ||
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
)
with open(path, "w", encoding="utf-8") as f:
    f.write(text + plant)
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
sed -n '/=== Check 40:/,/=== Check 41:/p' <<<"$RED41_OUT" | grep -qF "CHECK40: derive-version.sh fully reachable" ||
	fail "Check 40 must stay PASS while Check 41 is red (gate independence)"
sed -n '/=== Check 18:/,/=== Check 19:/p' <<<"$RED41_OUT" | grep -qF 'PASS — package.json=' ||
	fail "Check 18 (the other version reader) must stay PASS while Check 41 is red (gate independence)"
cp "$FAKE_REPO/scripts/package-signed.sh" "$RED41_ROOT/repo/scripts/package-signed.sh"
cp "$FAKE_REPO/.github/workflows/package.yml" "$RED41_ROOT/repo/.github/workflows/package.yml"
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
# pre-r3 tip). Each must be named, sibling gates (CHECK26 envelope law,
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
# counts what it finds and halts loud. These legs run the REAL script directly
# (it derives its default scan root from its own location, so no cwd dependency):
# (a) real components/ green, (b) empty scratch root red + loud, (c) missing
# root red, (d) planted malformed XML red naming the plant, plant removed green
# (falsifiability + extraction fidelity). FAKE_REPO untouched by this family. --
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

echo "PASS: verify-runtime.sh is portable — CI-layout positive run (exit 0, Check 14 PASS on 034_media_items_type_audiobook.sql, Check 11-26 + 37-39 headers present, CHECK21 + CHECK22 + CHECK23 + CHECK24 + CHECK25 + CHECK26 green) + ja_JP device-locale resolution leg (all literal Translate keys resolve with no en_US fallback) + Check 21 red leg (missing mirror key -> CHECK21 fired, Check 14/20/22/23/24 gates stayed green) + Check 22 content-pin red legs (rogue 20th census code -> CHECK22 fired naming it; rogue declaration in the post-flip EMPTY reserved ledger -> CHECK22 reserved-drift leg fired; removing SyncPlayReservedErrorCodes() entirely -> CHECK22 existence leg fired, the declaration gate stays armed; Check 21 stayed green all three runs) + Check 23 red legs (orphan errors key -> CHECK23 purity fired with CHECK22 green; raw EmitError literal -> CHECK23 fired, Check 21/22 gates stayed green) + Check 24 red leg (token key concatenated raw -> CHECK24 fired with file:line, Check 20/21/22/23 gates stayed green) + Check 19 exempt-anchoring red leg (prose ' for ' literal fired CHECK19 while a real for-header line stayed exempt, Check 20/21/22/23/24 gates stayed green) + Check 25 red leg (planted raw XML chrome label -> CHECK25 fired naming file:line, Check 20/21/22/23/24 gates stayed green) + Check 26 red leg (planted envelope-level resp.libraries read -> CHECK26 fired naming file and read, Check 20/24/25 gates stayed green) + Check 20 dotted-key red leg (planted Translate(\"player.playback_error\") -> CHECK20 fired naming file, dotted key and underscore suggestion with CHECKs 21-26 green; plant removed -> exit 0, falsifiability proven) + Check 39 rsg_version red leg+restore (planted rsg_version=7.0 + stripped rationale comment -> CHECK39 fired R2 naming the illegal value and R4, with the sibling manifest readers CHECK18/CHECK38 stayed green — gate independence; cured manifest restored -> exit 0, falsifiability proven) + M-ROKU-08 aggregation red leg+restore (planted CHECK1 violation in leg 1 -> exit non-zero with the violation printed and CHECK20/21/39 gates stayed green — single-sink accumulator, re-zeroing any cured-range leg reddens this leg; plant removed -> exit 0) + Check 40 dead-design red leg+restore (planted unreachable function + ghost documented flag -> CHECK40 fired R1 and R2 naming both plants, with CHECK18/CHECK39 gate independence; cured script restored -> exit 0 — designed-but-dead versioning machinery can no longer accumulate silently) + Check 41 signing-honesty red leg+restore (planted the phantom password-env claim, the rename-into-.pkg fallback and a hardcoded PKG_VERSION default into a scratch package-signed.sh plus an un-provisioned package-signed stub job into a scratch package.yml -> CHECK41 fired R1/R2/R3/R4 naming each plant, with CHECK18/CHECK40 gate independence; cured files restored -> exit 0 — a mislabeled 'signed' artifact or a phantom-secret claim cannot return silently) + Check 42 channel-identity/diagnostics red leg+restore (stripping one send-site X-Phlix-Client-Version header, planting the \"1.0.1\" About literal and retargeting the multi-line block onto the non-wrapping statusLabel -> CHECK42 fired R1/R2/R6 naming each plant, with CHECK41/CHECK20 gate independence; cured files restored -> exit 0 — retail-user version visibility cannot silently regress) + Check 43 wire-text type-guard red leg+restore (planted all five arms into a scratch DetailScene — raw resp.error lift, resp.data.message literal-compare, lcase(env.message), the \"Server error: \" + resp.error concat and the IsTransportReason(resp.error) typed-sink call -> CHECK43 fired all five arms naming file, rule and read, with CHECK26/CHECK41 gate independence; plant removed -> exit 0 — hostile untyped wire text cannot re-enter a render-path String operation silently, and no path stays exempt from the law) + Check 44 dial-completion red leg+restore (stripping the hub-relay mint X-Phlix-Client-Version AddHeader in a scratch copy -> CHECK44 fired R1 naming components/HubCommandTask.brs, with CHECK42 gate independence; cured file restored -> exit 0 — the WebSocket/relay version disclosure cannot silently regress) + Check 45 content-id shape-gate red leg+restore (re-planting the era invalid/empty relay guard into a scratch PhlixApp and re-fattening the scratch main.brs launch validator into the printable loop fired CHECK45 R2/R4 naming files and rules, with CHECK43/CHECK44 gate independence; cured files restored -> exit 0 — a malformed content id can never silently re-enter the authenticated path-injection class) + Check 46 SyncPlay origin/accept red leg+restore (stripping the PlayerScene origin choke, neutralising the SyncPlayTask accept verification and stripping the accept parser's blank-line stop in a scratch copy fired CHECK46 R1/R2 naming all three files — including the r1 MAJOR-1 body-spoof tooth — with CHECK44/CHECK45 gate independence; cured files restored -> exit 0 — the main account JWT can never silently re-ride a cleartext handshake behind a TLS origin, a forged 101 without accept proof can never re-enter session scope, and a body line can never silently impersonate a header again) + Check 47 bootstrap-Back/boot-retry red leg+restore (re-swallowing Back in a scratch ConnectScene and returning the boot chrome to the trap era — no SetFocus, per-error re-observe — fired CHECK47 R1 and R2 naming the scene and each defect, with CHECK46/CHECK44 gate independence; both plants restored -> exit 0 — a signed-out user can never again be trapped by a disabled Back on the first screens met, and a visible Retry can never again be unpressable) + validate-xml zero-file-guard legs (real components/ green with count; empty scratch root -> \"discovered ZERO XML files\" red; missing root -> \"does not exist\" red; planted malformed XML -> named red, removed -> exit 0) + audiobook-drift negative run (exit $NEG_RC, CHECK14 fired)"
