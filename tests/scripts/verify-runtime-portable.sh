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
#                          components/SettingsScene.brs + DetailScene.brs
#                          (Check 19's fixed target list), locale/<all shipped
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
#   (3) stdout contains every "=== Check 11:" .. "=== Check 21:" header
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
#
# RUN:  bash tests/scripts/verify-runtime-portable.sh
# There is no Makefile slot: `make check` is a prerequisites probe, not a script
# runner, so this test is intentionally standalone. Wire it into a CI job or a
# future tests/ runner if one appears.

set -euo pipefail

for tool in bash git python3 cp rm mktemp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: required tool '$tool' not found" >&2; exit 1; }
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
cp "$REAL_REPO/source/lib/Utilities.brs"  "$FAKE_REPO/source/lib/Utilities.brs"
cp "$REAL_REPO/components/SettingsScene.brs" "$FAKE_REPO/components/SettingsScene.brs"
cp "$REAL_REPO/components/DetailScene.brs"   "$FAKE_REPO/components/DetailScene.brs"
cp -a "$REAL_REPO/images"/. "$FAKE_REPO/images/"
cp "$REAL_REPO/package.json" "$FAKE_REPO/package.json"
cp "$REAL_REPO/manifest"     "$FAKE_REPO/manifest"
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
for i in $(seq 11 21); do
  assert_contains "=== Check $i:" "$POSITIVE_OUT"
done
assert_contains "CHECK21: all" "$POSITIVE_OUT"

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

echo "PASS: verify-runtime.sh is portable — CI-layout positive run (exit 0, Check 14 PASS on 034_media_items_type_audiobook.sql, Check 11-21 headers present, CHECK21 green) + ja_JP device-locale resolution leg (all literal Translate keys resolve with no en_US fallback) + Check 21 red leg (missing mirror key -> CHECK21 fired, Check 14/20 gates stayed green) + audiobook-drift negative run (exit $NEG_RC, CHECK14 fired)"