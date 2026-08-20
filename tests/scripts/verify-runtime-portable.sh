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
#                          (Check 19's fixed target list), images/, package.json,
#                          manifest; a git index so checks 1-13 (git grep /
#                          git ls-files) work
#     $tmp/phlix-server/migrations/034_media_items_type_audiobook.sql
#                          — the 13-member ENUM, the ONLY migration present
# then runs `bash $tmp/repo/scripts/verify-runtime.sh` from that OTHER location,
# WITHOUT PHLIX_SERVER_DIR set, so the sibling-default resolution is what is
# exercised. Asserts:
#   (1) exit code 0
#   (2) stdout contains "Check 14", "034_media_items_type_audiobook.sql", "PASS"
#   (3) stdout contains every "=== Check 11:" .. "=== Check 19:" header
#   (4) negative: audiobook removed from the Utilities.brs ENUM comment ->
#       exit code non-zero with a CHECK14 diagnostic
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
for i in $(seq 11 19); do
  assert_contains "=== Check $i:" "$POSITIVE_OUT"
done

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

echo "PASS: verify-runtime.sh is portable — CI-layout positive run (exit 0, Check 14 PASS on 034_media_items_type_audiobook.sql, Check 11-19 headers present) + audiobook-drift negative run (exit $NEG_RC, CHECK14 fired)"