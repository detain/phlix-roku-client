#!/usr/bin/env bash
# scripts/verify-runtime.sh — Static runtime-defect checker for phlix-roku-client (R0.7)
# Each check exits non-zero and prints: FILE:LINE — CHECK_NAME: explanation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
cd "$REPO"
# Check 14 reads the phlix-server migrations dir; in CI it is checked out as a
# sibling repo (../phlix-server), same layout as the dev sandbox.
SERVER_DIR="${PHLIX_SERVER_DIR:-$(dirname "$REPO")/phlix-server}"
export REPO SERVER_DIR
FOUND=0
VIOLATIONS=0

echo "=== Check 1: Storage.factory misuse (R0.2 regression) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK1: Storage.factory used directly (use GetStorage())"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn 'Storage\.\(get\|set\|delete\|clear\)' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 2: m.top.Close() calls (R0.4 regression) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK2: m.top.Close() called (use m.top.requestClose = true)"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn 'm\.top\.Close()' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 3: ContentEmitter stub XML (R0.5 regression) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK3: ContentEmitter is not a real SceneGraph node"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn '<ContentEmitter' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 4: caption1Icon / handle:// invalid fields (R0.5 regression) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK4: caption1Icon/handle:// is not a real PosterGrid field or valid URI"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn -E 'caption1Icon|handle://' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 5: halign= XML attribute (R0.6 regression — should be horizAlign=) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK5: halign= is not a Label field (use horizAlign=)"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn 'halign=' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 6: ObserveField callback defined (maps to §5.5) ==="
for brs in $(git ls-files -- '*.brs'); do
	callbacks=$(grep -oP 'ObserveField\s*\(\s*"[^"]+"\s*,\s*"\K[^"]+' "$brs" 2>/dev/null || true)
	for cb in $callbacks; do
		# Check for regular sub/function OR colon-method syntax (OnCallback: sub() or OnCallback: function())
		if ! grep -qP "^(sub|function)\s+$cb\b" "$brs" 2>/dev/null &&
			! grep -qP "^\s+$cb:\s+(sub|function)\b" "$brs" 2>/dev/null; then
			line=$(grep -n "ObserveField.*\"$cb\"" "$brs" | head -1 | cut -d: -f1)
			echo "  $brs:$line — CHECK6: ObserveField target '$cb' has no matching sub/function"
			FOUND=1
			VIOLATIONS=1
		fi
	done
done
[[ $FOUND -eq 0 ]] && echo "  PASS"

FOUND=0
echo ""
echo "=== Check 7: FindNode target exists in XML (maps to §5.5) ==="
for brs in $(git ls-files -- '*.brs'); do
	if [[ "$brs" == tests/* ]]; then continue; fi
	base="${brs%.brs}"
	xml="${base}.xml"
	if [[ ! -f "$xml" ]]; then continue; fi
	# CHECK7 robustness (w15L9 round-3): read the <children> window ONCE per
	# (brs,xml) pair, not once per FindNode id. The per-id awk fork could
	# transiently fail under host load, and the old '2>/dev/null || true'
	# turned a fork failure into EMPTY children_content — a FALSE 'no id='
	# conviction on a random id that exists (the flake class that killed six
	# real full-twin runs: diag3 GREEN68 + diag4 GREEN76 'chapterLabel',
	# diag5b GREEN53 'skipButton' — every id verified present in the
	# committed xml). An unreadable carrier now convicts LOUD (CHECK75 R1
	# precedent) instead of silently poisoning the verdict.
	if ! children_content=$(awk '/^[[:space:]]*<\/children>/{found=0} found{print} /^[[:space:]]*<children>/{found=1; next} END{if(found)print}' "$xml" 2>&1); then
		echo "  $xml — CHECK7: the <children> extraction failed (carrier unreadable)"
		FOUND=1
		VIOLATIONS=1
		continue
	fi
	while IFS=: read -r line content; do
		ids=$(echo "$content" | grep -oP 'FindNode\s*\(\s*"\K[^"]+' 2>/dev/null || true)
		for id in $ids; do
			if [[ "$id" == *'$'* ]] || [[ "$id" == *'{'* ]]; then continue; fi
			if ! echo "$children_content" | grep -q "id=\"$id\"" 2>/dev/null; then
				echo "  $brs:$line — CHECK7: FindNode(\"$id\") but no id=\"$id\" in $xml <children>"
				FOUND=1
				VIOLATIONS=1
			fi
		done
	done < <(grep -n 'FindNode' "$brs" 2>/dev/null || true)
done
[[ $FOUND -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 8: m.videoPlayer invalid fields (maps to §5.6) ==="
# Allow-list of real Video node fields (Roku SceneGraph SDK)
# https://developer.roku.com/dev/docs/video
# M-ROKU-08 aggregation law: VIOLATIONS is the single end-to-end sink — legs
# may NEVER re-zero it. Checks 1-10 used to reset it at each header, so every
# violation before Check 11 printed but could not gate the exit. The PASS
# display now rides the same FOUND local checks 1-7 use.
ALLOW_LIST="command content control currentTime duration endpoint errorMsg focusRing isFullscreen isPhoto loggingUrl manifestHDRType maxHeight maxWidth position rate retargetHeight retargetWidth secureChainingUrl securityKey stream streamFormat streamInfo subtitleStream textTrackTrack track transferType videoLocation videoNode wasPlaying wideAsync EnableCookies SetCertificatesFile ObserveField UnObserveField SetFocus globalCaptionMode seek audioTrack availableAudioTracks subtitleTracks currentSubtitleTrack errorCode width height translation volume isUnderlyingStreamPlaying notificationPeriod positionAsOfNow bifDisplay"
FOUND=0
while IFS=: read -r file line; do
	field=$(echo "$line" | sed 's/.*m\.videoPlayer\.\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' | grep -oP '[a-zA-Z_][a-zA-Z0-9_]*' | head -1)
	if [[ -n "$field" ]] && ! echo "$ALLOW_LIST" | grep -qw "$field"; then
		echo "  $file — CHECK8: m.videoPlayer.$field is not a real Video node field"
		FOUND=1
		VIOLATIONS=1
	fi
done < <(git grep -n 'm\.videoPlayer\.' -- '*.brs' 2>/dev/null || true)
[[ $FOUND -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 9: OnKeyEvent invalid Roku remote keys (maps to §3.6) ==="
# Valid Roku remote keys per https://developer.roku.com/dev/docs/remote-control-events
ALLOW_KEYS="back up down left right OK replay play rewind fastforward options info"
FOUND=0
for brs in $(git ls-files -- '*.brs'); do
	if [[ "$brs" == tests/* ]]; then continue; fi
	if grep -q 'sub OnKeyEvent' "$brs"; then
		keys=$(grep -oP 'key\s*[=!]=\s*"\K[^"]+' "$brs" 2>/dev/null || true)
		for key in $keys; do
			if ! echo "$ALLOW_KEYS" | grep -qw "$key"; then
				line_num=$(grep -n "[\"']$key[\"']" "$brs" | head -1 | cut -d: -f1)
				echo "  $brs:$line_num — CHECK9: OnKeyEvent compares key '$key' which is not a valid Roku remote key"
				FOUND=1
				VIOLATIONS=1
			fi
		done
	fi
done
[[ $FOUND -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 10: blocking network outside ApiTask (maps to §5.3) ==="
FOUND=0
while IFS=: read -r file line; do
	if [[ "$file" != components/ApiTask* ]]; then
		echo "  $file:$line — CHECK10: blocking network call (ApiClient.wait/sync) on render thread"
		FOUND=1
		VIOLATIONS=1
	fi
done < <(git grep -rn 'ApiClient\.\(wait\|sync\)' -- '*.brs' 2>/dev/null || true)
[[ $FOUND -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 11: unguarded Task control=run (R1.4: busy guard required) ==="
# M-ROKU-08: the last re-zero site lives no more — this leg's gate display is
# driven by PYRET and its failure already accumulates via VIOLATIONS=1.
# For each control="run" in .brs files, verify a busy-guard (state check) appears
# within the preceding ~15 lines inside the same function.  Sites that are
# provably one-shot (guarded by if m.XTask=invalid or m.XTask.state<>"run" nearby),
# or that document the callback-chained "one op at a time" pattern (comments
# containing "two control" + "never" + "outstanding" or "un guarded"), are
# allowed.  All others are flagged.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import subprocess, re, sys, os

os.chdir(os.environ['REPO'])
result = subprocess.run(
    ['git', 'grep', '-n', r'control\s*=\s*"run"', '--', '*.brs'],
    capture_output=True, text=True
)
if result.returncode != 0 and not result.stdout.strip():
    sys.exit(0)

# Guards that satisfy the check:
guard_patterns = [
    re.compile(r'state\s*=\s*[\'"]run[\'"]'),
    re.compile(r'state\s*<>\s*[\'"]run[\'"]'),
    re.compile(r'if\s+m\.\w+\s*=\s*invalid\s+then'),
    re.compile(r'un guarded', re.IGNORECASE),
]
# Files using the callback-chained serialization pattern — single Task fires one op at a time
exempt_files = {
    'components/CollectionScene.brs',
    'components/CollectionsScene.brs',
    'components/ConnectScene.brs',
    'components/DetailScene.brs',
    'components/FavoritesScene.brs',
    'components/GuideScene.brs',
    'components/LibraryAdminScene.brs',
    'components/LibraryScene.brs',
    'components/LoginScene.brs',
    'components/MusicAlbumScene.brs',
    'components/ParentalControlsScene.brs',
    'components/PhotoAlbumScene.brs',
    'components/PhotosScene.brs',
    'components/ProfilesScene.brs',
    'components/RecommendationsScene.brs',
    'components/RecordingsScene.brs',
    'components/SeasonScene.brs',
    'components/SeriesRulesScene.brs',
    'components/SeriesScene.brs',
    'components/ServerPickerScene.brs',
    'components/UserAdminScene.brs',
    'components/PhlixApp.brs',
    'source/lib/TaskManager.brs',
}
# Exemption patterns: comments documenting the callback-chained serialization
# pattern ("one op at a time - never two control=run").
exempt_patterns = [
    # ' allow-listed: callback-chained — single Task fires one op at a time
    re.compile(r'two control[\s\S]{0,80}never|never[\s\S]{0,80}two control', re.IGNORECASE),
    re.compile(r'never outstanding', re.IGNORECASE),
    re.compile(r'one op at a time', re.IGNORECASE),
    re.compile(r"allow-listed: callback-chained", re.IGNORECASE),
]
found_violation = False
for gline in result.stdout.strip().split('\n'):
    if not gline.strip():
        continue
    parts = gline.split(':', 2)
    if len(parts) < 3:
        continue
    fname, lnum_s, line_content = parts
    # Skip .sh files and pre-existing exempt files
    if fname.endswith('.sh') or fname in exempt_files:
        continue
    try:
        lnum = int(lnum_s)
    except ValueError:
        continue
    # Skip comment-only lines (lines where the meaningful content starts with ')
    # because "control="run"" appearing in a comment is documentation, not code.
    stripped = line_content.strip()
    if stripped.startswith("'") or stripped.startswith('"') or stripped.startswith('}'):
        continue
    # Lookback for code-level guards (should be near the call site)
    guard_start = max(1, lnum - 15)
    # Lookback for exemption documentation (can be at function top, up to 50 lines)
    exempt_start = max(1, lnum - 50)
    try:
        with open(fname, 'r', errors='replace') as f:
            lines = f.readlines()
        # Guard context: lines strictly before the control="run" line
        guard_context = ''.join(lines[guard_start-1:lnum-1])
        # Exempt context: lines before AND including the control="run" line, because
        # the exemption comment often appears ON the same line (e.g. inline docs).
        exempt_context = ''.join(lines[exempt_start-1:lnum])
    except Exception:
        continue
    has_guard = any(p.search(guard_context) for p in guard_patterns)
    has_exempt = any(p.search(exempt_context) for p in exempt_patterns)
    if not has_guard and not has_exempt:
        print(f'  {fname}:{lnum} — CHECK11: control="run" without a busy/state guard in same function')
        found_violation = True
if found_violation:
    sys.exit(1)
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

FOUND=0
echo ""
echo "=== Check 12: syncplay/rooms instead of /groups (R4.1) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK12: syncplay uses /groups endpoint, not /rooms"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn 'syncplay/rooms' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 13: DELETE verb on syncplay endpoint (R4.1 — leave is POST) ==="
while IFS=: read -r file line; do
	echo "  $file:$line — CHECK13: syncplay leave uses POST, not DELETE"
	FOUND=1
	VIOLATIONS=1
done < <(git grep -rn 'syncplay' -- '*.brs' 2>/dev/null | grep 'DELETE' || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

echo ""
echo "=== Check 14: media_items.type ENUM drift vs server (S115) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, os, sys

# ── 1. Find the authoritative ENUM from server migrations ──────────────────────
migration_dir = os.path.join(os.environ['SERVER_DIR'], 'migrations')
if not os.path.isdir(migration_dir):
    print(f"  CHECK14: server migration dir not found at {migration_dir}")
    sys.exit(1)

# Collect every media_items.type ENUM definition found across all migration files.
# The final (most complete) one represents the current schema state.
enum_defs = {}  # name -> sorted list of members
for fname in sorted(os.listdir(migration_dir)):
    if not fname.endswith(".sql"):
        continue
    fpath = os.path.join(migration_dir, fname)
    with open(fpath, errors="replace") as f:
        content = f.read()
    # Match ALTER TABLE media_items MODIFY COLUMN type ENUM('a', 'b', ...) — captures
    # the ENUM value list up to the first closing paren (the list contains no embedded
    # parens). Scoped to the media_items.type column so a member-richer ENUM on another
    # table (e.g. content_rating in 083, stats media_type in 094) can never hijack the
    # authoritative source. \s+ spans the newline between `media_items` and `MODIFY`,
    # hence DOTALL is required.
    for m in re.finditer(
        r"ALTER\s+TABLE\s+media_items\s+MODIFY\s+COLUMN\s+`?type`?\s+ENUM\(([^)]+)\)",
        content,
        re.IGNORECASE | re.DOTALL,
    ):
        raw = m.group(1)
        members = [e.strip().strip("'") for e in raw.split(",")]
        enum_defs[fname] = members

if not enum_defs:
    print("  CHECK14: no media_items.type ENUM found in migrations")
    sys.exit(1)

# Use the migration with the most members as the authoritative current state.
# (034 has 13; earlier ones have fewer — the longest wins.)
server_enum = max(enum_defs.values(), key=len)
server_members = sorted(server_enum)
server_fname   = max(enum_defs, key=lambda k: len(enum_defs[k]))
if len(server_members) < 13:
    print(f"  CHECK14: server ENUM has only {len(server_members)} members, expected 13")
    sys.exit(1)

# ── 2. Extract the full type list from Utilities.brs ───────────────────────────
utilities_path = os.path.join(os.environ['REPO'], 'source/lib/Utilities.brs')
if not os.path.isfile(utilities_path):
    print(f"  CHECK14: Utilities.brs not found at {utilities_path}")
    sys.exit(1)

with open(utilities_path, errors="replace") as f:
    util_content = f.read()

# The full ENUM is documented in the comment block above PlayableTypes().
# The list spans exactly 2 lines (lines 853-855 in Utilities.brs: the
# "' The full ENUM is:" banner at 853 and the member list at 854-855) —
# capture them directly rather than using a greedy pattern that could spill
# into explanatory comment lines (which also start with ' but contain no
# commas).
# Note: \s* (zero-or-more) is used because lines start with ' directly, no leading WS.
enum_match = re.search(
    r"The full ENUM is:\s*\n((?:\s*'   [^\n]*\n){2})",
    util_content,
)
if not enum_match:
    print("  CHECK14: 'The full ENUM is:' comment block not found in Utilities.brs")
    sys.exit(1)

# Parse: strip leading ' and whitespace, then split on comma
client_members = []
for line in enum_match.group(1).splitlines():
    stripped = line.strip().lstrip("'").strip()
    if not stripped:
        continue
    for part in stripped.split(","):
        member = part.strip()
        if member:
            client_members.append(member)
client_members = sorted(client_members)

if len(client_members) != len(server_members):
    print(f"  CHECK14: member count mismatch — server={len(server_members)}, client={len(client_members)}")
    print(f"  CHECK14: server ENUM ({server_fname}): {server_members}")
    print(f"  CHECK14: client ENUM comment:          {client_members}")
    sys.exit(1)

# ── 3. Exact set equality check (both directions) ──────────────────────────────
server_set = set(server_members)
client_set = set(client_members)
missing_in_client = server_set - client_set
extra_in_client   = client_set - server_set

if missing_in_client:
    print(f"  CHECK14: server has members missing from client: {sorted(missing_in_client)}")
if extra_in_client:
    print(f"  CHECK14: client has extra members not in server: {sorted(extra_in_client)}")
if missing_in_client or extra_in_client:
    sys.exit(1)

# ── 4. PlayableTypes() is a strict subset — verify every member is in server ENUM
# Extract PlayableTypes() return value: ["movie", "episode", ...]
playable_match = re.search(
    r"function\s+PlayableTypes\s*\(\s*\)\s*as\s+Object\s*\n\s*return\s*\[(.*?)\]\s*end function",
    util_content,
    re.DOTALL,
)
if not playable_match:
    print("  CHECK14: PlayableTypes() function not found in Utilities.brs")
    sys.exit(1)

playable_members = [m.strip().strip('"').strip("'") for m in playable_match.group(1).split(",")]
not_in_server = [p for p in playable_members if p not in server_set]
if not_in_server:
    print(f"  CHECK14: PlayableTypes() members not in server ENUM: {not_in_server}")
    sys.exit(1)

# All checks passed
print(f"  PASS — server ENUM ({server_fname}): {server_members}")
print(f"         PlayableTypes() subset OK: {playable_members}")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 15: hardcoded localhost URL (R4.10) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, os, sys

os.chdir(os.environ['REPO'])

# Allow-list: files/patterns that legitimately contain localhost
exempt_files = {
    # tests/ — unit tests always use localhost for the mock server
    'tests/',
    # build/ — output tree, not source. Since M-ROKU-20 the deterministic
    # package recipe stages a byte-copy of source/ under build/pkg-stage/
    # (CI: package.yml only, and the Lint job's git-grep legs never see it;
    # a local `make package` followed by a full gate run WOULD). Contents
    # are already scanned at their real paths.
    'build/',
}
# Allow-list: specific line content patterns that are legitimate
exempt_line_patterns = [
    # ConnectScene.xml hint="https://my.phlix.server" placeholder
    re.compile(r'hint="https://my\.phlix\.server"'),
    # DEVELOPER.md ApiClient("http://localhost:8096") example
    re.compile(r'ApiClient\s*\(\s*"http://localhost'),
]
# Exempt absolute path:line — specific legitimate code uses
exempt_locs = {
    # Utilities.brs: localhost detection for the single-source host predicate
    # (IsPrivateHostAddress - scheme inference + the M-ROKU-15 cleartext gate
    # classify loopback through it). The pre-R4.7 pin at line 91 went stale
    # when the inline inference moved out of NormalizeServerUrl; M-ROKU-15
    # re-pinned it onto the predicate's own line. W-min91 re-pinned 121 -> 128:
    # the harness-convicted cure families (LCase/Left/Mid/Right global
    # conversions + Repl/UrlEncode evidence docblocks) shifted the file by
    # seven lines above this predicate.
    ('source/lib/Utilities.brs', 128): re.compile(r'if h = "localhost" then return true'),
}

found_violation = False
for ext in ('brs', 'xml'):
    for root, dirs, files in os.walk('.'):
        # Skip hidden dirs
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in files:
            if not fname.endswith(f'.{ext}'):
                continue
            fpath = os.path.join(root, fname)
            # Normalize path for exempt_files check
            normalized = fpath.lstrip('./')
            if any(normalized.startswith(e) for e in exempt_files):
                continue
            with open(fpath, errors='replace') as f:
                for lineno, line in enumerate(f, 1):
                    if 'localhost' not in line:
                        continue
                    # Skip comment-only lines (lines where meaningful content starts with ')
                    stripped = line.strip()
                    if stripped.startswith("'") or stripped.startswith('"'):
                        continue
                    # Skip exempt line patterns
                    if any(p.search(line) for p in exempt_line_patterns):
                        continue
                    # Skip exempt specific locations
                    is_exempt_loc = False
                    for (efile, eline), pattern in exempt_locs.items():
                        if normalized == efile and lineno == eline and pattern.search(line):
                            is_exempt_loc = True
                            break
                    if is_exempt_loc:
                        continue
                    print(f'  {normalized}:{lineno} — CHECK15: hardcoded localhost URL')
                    found_violation = True

if found_violation:
    sys.exit(1)
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 16: placeholder channel art file size (R6.2) ==="
# Each image in images/ must be large enough to plausibly contain real art at its
# declared dimensions.  A 166-byte PNG is not a 290x218 icon — no amount of
# compression makes a real photograph that small.
# Minimum bytes per pixel: 0.5 B/px (ultra-flat illustration still needs hundreds
# of bytes per pixel after DEFLATE; 1-bit placeholder palettes compress to nothing).
# Fail if: bytes < width * height * 0.5
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, sys, struct, zlib

repo = os.environ['REPO']
images_dir = os.path.join(repo, 'images')
if not os.path.isdir(images_dir):
    print(f"  CHECK16: images/ directory not found at {images_dir}")
    sys.exit(1)

MIN_BPP = 0.5  # bytes per pixel — ultra-flat art still needs this much
found_violation = False

for fname in sorted(os.listdir(images_dir)):
    fpath = os.path.join(images_dir, fname)
    if not fname.lower().endswith('.png'):
        continue
    fsize = os.path.getsize(fpath)
    # Read PNG header to get width/height
    try:
        with open(fpath, 'rb') as f:
            # PNG signature + IHDR chunk
            sig = f.read(8)
            if sig != b'\x89PNG\r\n\x1a\n':
                print(f"  images/{fname} — CHECK16: not a valid PNG file")
                found_violation = True
                continue
            f.read(4)  # chunk length
            chunk_type = f.read(4)
            if chunk_type != b'IHDR':
                print(f"  images/{fname} — CHECK16: IHDR chunk missing")
                found_violation = True
                continue
            width = struct.unpack('>I', f.read(4))[0]
            height = struct.unpack('>I', f.read(4))[0]
    except Exception as e:
        print(f"  images/{fname} — CHECK16: failed to read PNG dimensions: {e}")
        found_violation = True
        continue

    min_bytes = int(width * height * MIN_BPP)
    if fsize < min_bytes:
        print(f"  images/{fname} — CHECK16: {fsize} bytes is too small for {width}x{height} (min expected ~{min_bytes} bytes)")
        found_violation = True
    else:
        print(f"  images/{fname} ({width}x{height}, {fsize} bytes) — PASS")

if found_violation:
    sys.exit(1)
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 17: echo ERROR paired with exit/state (self-audit) ==="
# Every echo command with ERROR in its output should set FOUND=1, VIOLATIONS=1,
# or exit 1 to ensure the script properly fails when errors are detected.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

script_path = os.path.join(os.environ['REPO'], 'scripts/verify-runtime.sh')
# Exclude only the meta-check block itself (check 17) to avoid self-referential
# false positives: the audit range is [Check 17 marker, Check 18 marker), so
# checks 18-19 and the final exit block are included in the audit.
exclude_start = "=== Check 17:"
exclude_end = "=== Check 18:"

try:
    with open(script_path, 'r') as f:
        raw_lines = f.readlines()
except Exception as e:
    print(f"  CHECK17: failed to read script: {e}")
    sys.exit(1)

# Extract lines to audit (everything before the check 17 block)
lines_to_audit = []
in_meta_check = False
for line in raw_lines:
    if exclude_start in line:
        in_meta_check = True
    if exclude_end in line:
        in_meta_check = False
    if not in_meta_check:
        lines_to_audit.append(line)

violations = []
for i, line in enumerate(lines_to_audit):
    # Only check actual echo commands (not comments, not strings containing 'echo')
    # An echo command starts with optional whitespace, then 'echo' followed by whitespace
    if re.match(r'^\s*echo\s+', line) and 'ERROR' in line:
        linenum = i + 1
        violations.append(f"  {script_path}:{linenum} — CHECK17: echo command with ERROR should set FOUND=1, VIOLATIONS=1, or exit 1")

if violations:
    for v in violations:
        print(v)
    sys.exit(1)

print("  PASS — all echo ERROR commands properly paired with state/exit")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 18: version drift between package.json and manifest (R8.8) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, os, sys, json

repo = os.environ['REPO']

# Read package.json version
pkg_json = os.path.join(repo, 'package.json')
try:
    with open(pkg_json) as f:
        pkg_data = json.load(f)
    pkg_version = pkg_data.get('version', '')
except Exception as e:
    print(f"  CHECK18: failed to read package.json: {e}")
    sys.exit(1)

# Parse package.json version (major.minor.patch)
m = re.match(r'^(\d+)\.(\d+)\.(\d+)', pkg_version)
if not m:
    print(f"  CHECK18: package.json version '{pkg_version}' does not match semver format")
    sys.exit(1)
pkg_major, pkg_minor, pkg_patch = m.groups()

# Read manifest
manifest = os.path.join(repo, 'manifest')
try:
    with open(manifest) as f:
        manifest_content = f.read()
except Exception as e:
    print(f"  CHECK18: failed to read manifest: {e}")
    sys.exit(1)

# Parse manifest fields
def get_manifest_field(content, field):
    match = re.search(rf'^{field}=(\d+)', content, re.MULTILINE)
    return match.group(1) if match else None

man_major = get_manifest_field(manifest_content, 'major_version')
man_minor = get_manifest_field(manifest_content, 'minor_version')
man_build = get_manifest_field(manifest_content, 'build_version')

if man_major is None or man_minor is None or man_build is None:
    print(f"  CHECK18: manifest missing required version fields")
    sys.exit(1)

drift = []
if pkg_major != man_major:
    drift.append(f"major_version: package.json={pkg_major}, manifest={man_major}")
if pkg_minor != man_minor:
    drift.append(f"minor_version: package.json={pkg_minor}, manifest={man_minor}")

# Check if build_version in manifest is a valid build number
if not re.match(r'^\d+$', man_build):
    drift.append(f"build_version: manifest={man_build} is not a valid build number")

if drift:
    print(f"  CHECK18: version drift detected:")
    for d in drift:
        print(f"    {d}")
    sys.exit(1)

print(f"  PASS — package.json={pkg_version}, manifest major_version={man_major}, minor_version={man_minor}, build_version={man_build}")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 19: hardcoded i18n strings in target files (R7.12) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, os, sys

repo = os.environ['REPO']
os.chdir(repo)

TARGETS = [
    'components/SettingsScene.brs',
    'components/DetailScene.brs',
    'source/lib/Utilities.brs',
    # R-ROKU-08 (riders W8): PlayerScene joined once the M-ROKU-20 backlog
    # cleared — the overlay trio and the ShowErrorDialog error/retry/cancel
    # family ride Translate() at tip (measured 2026-10-30: zero convictions).
    'components/PlayerScene.brs',
]

# Allow-list: patterns that are NOT user-facing hardcoded i18n strings.
# TWO FAMILIES (the anchoring law — an exemption is a statement about CODE,
# never about prose inside a user-facing literal):
#   EXEMPT_CONTENT  — tested against the RAW line, because these patterns
#                     live INSIDE string literals by design (URLs, IPs,
#                     bare numbers, locale paths) or anchor a line's raw
#                     comment shape.
#   EXEMPT_STATEMENT — tested against code_view(line): trailing comment cut
#                     at the first ' outside a double-quoted string, then
#                     every double-quoted string's CONTENT blanked. A
#                     keyword like for/next/else/then/print/exit or a
#                     function name only exempts when it is actual code;
#                     'm.text = "Pay $5 for entry"' can no longer exempt
#                     itself with the word "for" inside the literal (the
#                     unanchored-substring defect class, review #91 LOW).
EXEMPT_CONTENT = [
    re.compile(r'^[\'"]HTTP/'),            # HTTP protocol strings
    re.compile(r'^[\'"]https?://'),         # URL scheme literals
    re.compile(r'^[\'"]ws[s]?://'),         # WebSocket scheme literals
    re.compile(r'^[\'"][a-z]+://'),         # any scheme://
    re.compile(r'localhost'),               # localhost hostnames
    # Private IPs, pinned to full dotted-quad shape: a bare '10.' substring
    # would exempt any line whose literal merely contains a decimal ('10.99').
    re.compile(r'192\.168\.\d{1,3}\.\d'),  # private IP patterns
    re.compile(r'\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),  # private IP patterns
    re.compile(r'172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d'),  # private IP patterns
    re.compile(r'\b127\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),  # loopback
    re.compile(r'^[\'"][0-9]+[\'"]$'),     # bare numeric strings
    re.compile(r'^[\'"][0-9]+\.[0-9]+[\'"]$'),  # version strings in quotes
    re.compile(r'locale/en_US'),           # references to locale path
    re.compile(r'^[\s]*\'\'\''),         # doc comment lines
    re.compile(r'^\s*\'\s@'),            # at-tag doc comment lines
]

def code_view(line):
    # Statement-view of a BrightScript line for the EXEMPT_STATEMENT tests:
    # cut the trailing comment (a ' outside a double-quoted string comments
    # to end-of-line; BrightScript strings are double-quoted only, same
    # masking contract as Checks 20/23/24), then blank every string's CONTENT
    # so only code shape — never literal prose — can satisfy an exemption.
    kept = []
    in_string = False
    for ch in line:
        if ch == '"':
            in_string = not in_string
            kept.append(ch)
        elif ch == "'" and not in_string:
            break
        else:
            kept.append(ch)
    return re.sub(r'"[^"]*"', '"STRING"', "".join(kept))

EXEMPT_STATEMENT = [
    re.compile(r'\bstr\s*\('),             # str() runtime formatting calls
    re.compile(r'\bFormatTime\b'),         # time formatting functions
    re.compile(r'\bFormatUnixTime\b'),
    re.compile(r'\bParseTime\b'),
    re.compile(r'\bUrlEncode\b'),          # URL encoding function
    re.compile(r'\bEscapeString\b'),       # string escape functions
    re.compile(r'\bUnescapeString\b'),
    re.compile(r'\.state\s*='),            # node state field assignments
    re.compile(r'control\s*='),            # node control field assignments
    re.compile(r'isFullscreen'),            # Video node boolean field
    re.compile(r'streamFormat'),            # Video node field name
    re.compile(r'\.uri\s*='),              # Poster.uri — data, not UI
    re.compile(r'\.id\s*='),               # node id field
    re.compile(r'\.content\s*='),          # ContentNode content field
    re.compile(r'GetApiClient\b'),         # function call
    re.compile(r'GetServerUrl\b'),         # function call
    re.compile(r'GetDeviceModel\b'),       # function call
    re.compile(r'GetStorage\b'),           # function call
    re.compile(r'm\.top\.\w+\s*='),        # m.top interface field writes
    re.compile(r'm\.item\.\w+\s*='),       # m.item data field writes
    re.compile(r'm\.\w+\s*=\s*invalid'),   # invalid assignments
    re.compile(r'\.ObserveField\('),       # observer registration
    re.compile(r'\.UnObserveField\('),     # observer unregistration
    re.compile(r'return\s+["\']'),         # return statements with string literals
    re.compile(r'print\s+'),               # print statements
    re.compile(r'exit\s+'),                # exit statements (exit for/while/function)
    re.compile(r'\.DoesExist\('),          # DoesExist method calls
    re.compile(r'\.Split\('),             # string split calls
    re.compile(r'\.Lower\(\)'),           # case conversion calls
    re.compile(r'\.Trim\(\)'),            # trim calls
    re.compile(r'if\s+.*\s*=\s*["\']'),   # if condition comparisons
    re.compile(r'\btrue\b|\bfalse\b'),     # boolean literals
    re.compile(r'\bthen\b'),              # if/then/end if keywords
    re.compile(r'\belse\b'),              # else keyword
    # for loop headers, anchored to the BrightScript grammar (dialect-verified
    # against this repo + the Roku spec): `for <var> = <start> to <limit>
    # [step <inc>]` and `for each <var> in <collection>`. A user literal
    # containing ' for ' cannot satisfy either branch.
    re.compile(r'\bfor\s+(?:each\s+\w+\s+in\s+|\w+\s*=)'),
    re.compile(r'\bnext\b'),              # next keyword (statement; 'to' needs
                                          # no own entry — it only survives
                                          # masking inside a for header, which
                                          # the grammar anchor above exempts)
    re.compile(r'^[\s]*function\s+\w+'),   # function declarations
    re.compile(r'^[\s]*sub\s+\w+'),       # sub declarations
    re.compile(r'chr\s*\(\s*10\s*\)'),   # Chr(10) line feeds — structural
    re.compile(r'chr\s*\(\s*13\s*\)'),   # Chr(13) — structural
    re.compile(r'chr\s*\(\s*9\s*\)'),    # Chr(9) — tab characters
    re.compile(r'Chr\s*\(\s*\d+\s*\)'),  # Any Chr() — structural, not i18n
    re.compile(r'JoinStrings\('),          # utility function call
    re.compile(r'SortKeyValue\('),        # utility function call
    re.compile(r'SortByEpisodeOrder\('),  # utility function call
    re.compile(r'NormalizeServerUrl\('),  # utility function call
    re.compile(r'NormalizeAlbumTrack\('), # utility function call
    re.compile(r'NormalizeCollectionItem\('), # utility function call
    re.compile(r'IsPlayableItem\('),      # utility function call
    re.compile(r'IsPlayableType\('),      # utility function call
    re.compile(r'IsAdminUser\('),         # utility function call
    re.compile(r'IsTruthyFlag\('),        # utility function call
    re.compile(r'RatingLabel\('),          # utility function call (returns label array)
    re.compile(r'\.Replace\('),            # string Replace calls
    re.compile(r'\.Lower\('),             # string Lower calls
    re.compile(r'\.Upper\('),             # string Upper calls
    re.compile(r'\.Trim\('),              # string Trim calls
    re.compile(r'\.Left\('),              # string Left calls
    re.compile(r'\.Right\('),             # string Right calls
    re.compile(r'\.Mid\('),               # string Mid calls
    re.compile(r'\.Instr\('),             # string Instr calls
    re.compile(r'\.Len\('),               # string Len calls
    re.compile(r'Repl\s*\('),             # string Repl calls
    re.compile(r'CreateObject\s*\('),     # CreateObject calls
    re.compile(r'type\s*\('),             # type() calls
    re.compile(r'Int\s*\('),              # Int() calls
    re.compile(r'Val\s*\('),              # Val() calls
    re.compile(r'Rnd\s*\('),              # Rnd() calls
    re.compile(r'Abs\s*\('),              # Abs() calls
    re.compile(r'Asc\s*\('),              # Asc() calls
    re.compile(r'now\s*\('),              # now() time function
    re.compile(r'nowMs\s*\('),            # nowMs() time function
    re.compile(r'SecondsToTicks\s*\('),   # time conversion
    re.compile(r'HealthOk\s*\('),         # health check function
    re.compile(r'IsValidUrl\s*\('),       # validation function
    re.compile(r'TruncateString\s*\('),   # string utility
    re.compile(r'ByteToHex\s*\('),       # hex utility
    re.compile(r'GenerateRandomId\s*\('), # ID generator
    re.compile(r'Translate\s*\('),       # i18n translation function (R7.12)
    re.compile(r'TranslateWithParams\s*\('),  # i18n token-substitution fn (CHECK 24 law)
]

def strip_line_comment(line):
    # A ' outside a double-quoted string comments to end-of-line (same
    # contract as code_view); returns the code-only view WITH contents.
    kept = []
    in_string = False
    for ch in line:
        if ch == '"':
            in_string = not in_string
            kept.append(ch)
        elif ch == "'" and not in_string:
            break
        else:
            kept.append(ch)
    return "".join(kept)

def show_error_dialog_raw_args(line):
    # RT-095 [w15L9 R-C, review roku__casualgamer #2]: the ShowErrorDialog
    # call-argument law runs BEFORE the global statement exemptions, because
    # the era's Translate mask sheltered the WHOLE line - a single raw
    # literal in any argument position slipped past whenever a sibling arg
    # was a catalog call (the exact escape PlayerScene's "No chapters
    # available for this content" pair shipped through; the old >=3
    # sibling-count arm could never even see a masked-sibling line). This
    # parses the balanced call, splits at top-level commas, exempts only the
    # ARGUMENT'S OWN shape (a masked call is the catalog route, not a
    # violation), and convicts every remaining literal. The short all-caps
    # button-label amnesty still owns bare ["OK"]-style captions.
    view = strip_line_comment(line)
    out = []
    for m in re.finditer(r'ShowErrorDialog\s*\(', view):
        if view[:m.start()].rstrip().endswith(("sub", "function")):
            continue  # the declaration itself, not a call
        i = m.end()
        depth = 1
        args = []
        cur = ""
        in_str = False
        closed = False
        while i < len(view):
            ch = view[i]
            if ch == '"':
                in_str = not in_str
            if not in_str:
                if ch in "([":
                    depth += 1
                elif ch in ")]":
                    depth -= 1
                    if depth == 0:
                        closed = True
                        break
                elif ch == ",":
                    args.append(cur)
                    cur = ""
            cur += ch
            i += 1
        if not closed:
            continue  # a wrapped call head is not parsed on partial shape
        args.append(cur)
        for arg in args:
            a = arg.strip()
            if not a:
                continue
            if any(pa.search(code_view(a)) for pa in EXEMPT_STATEMENT):
                continue
            for s in re.findall(r'"([^"]*)"', a):
                if s.isupper() and len(s) < 6:
                    continue
                out.append(s)
    return out

found_violation = False
for tpath in TARGETS:
    if not os.path.isfile(tpath):
        print(f"  {tpath} — CHECK19: file not found")
        found_violation = True
        continue
    with open(tpath, errors='replace') as f:
        lines = f.readlines()
    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        # Skip pure comment lines (content is a comment, not code)
        if stripped.startswith("'") and not stripped.startswith("''"):
            continue
        if stripped.startswith('"') and len(stripped) > 1 and stripped[1] == '"':
            continue

        # Find string literals on this line
        string_literals = re.findall(r'[\'"]([^\'"]+)[\'"]', line)
        if not string_literals:
            continue

        # Skip if line matches any exempt pattern (anchoring law at the top
        # of this check): content shapes see the raw line, statement shapes
        # only the code_view with string contents and comments blanked.
        if any(p.search(line) for p in EXEMPT_CONTENT):
            continue
        # RT-095: the ShowErrorDialog argument law is exempt from the global
        # statement amnesty - a masked sibling call must not shelter a raw
        # literal in another argument position. Convict first, then let the
        # legacy shape law below continue its work.
        for s in show_error_dialog_raw_args(line):
            print(f"  {tpath}:{lineno} — CHECK19: hardcoded user-facing string: {s[:60]}")
            found_violation = True
        if any(p.search(code_view(line)) for p in EXEMPT_STATEMENT):
            continue

        # This line has a string literal that is not exempt.
        # Check if it's in a UI context (dialog, label, button title, status).
        is_ui_context = False
        # Dialog field assignments
        if re.search(r'dialog\.(title|message|buttons)\s*=', line):
            is_ui_context = True
        # Label/text field assignments
        if re.search(r'\.text\s*=\s*[\'"]', line) and not re.search(r'\.uri\s*=\s*[\'"]', line):
            is_ui_context = True
        # Button/title field assignments on nodes
        if re.search(r'\.title\s*=\s*[\'"]', line):
            is_ui_context = True
        # statusLabel/detailLabel/loadingLabel assignments
        if re.search(r'm\.\w+(Status|Detail|Loading|Title|Info)\w*\.text\s*=', line):
            is_ui_context = True
        # Specific hardcoded strings in conditionals or assignments in Show*Dialog subs
        if re.search(r'(ShowAccount|ShowServer|ShowPlayback|ShowCaptions|ShowWatchHistory|ShowAbout|TogglePip)\(', line):
            is_ui_context = True
        # Error dialog strings are governed by the RT-095 pre-exemption
        # argument law above; the era's >=3-sibling arm is retired - it
        # could never see a line whose siblings carried a masked call, the
        # shelter that let the survivor pair ship (CHECK19 twin plant).

        if is_ui_context:
            # Skip short all-caps (standard button labels)
            for s in string_literals:
                if s.isupper() and len(s) < 6:
                    continue
                print(f"  {tpath}:{lineno} — CHECK19: hardcoded user-facing string: {s[:60]}")
                found_violation = True

if found_violation:
    sys.exit(1)
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 20: Translate() keys resolve against the locale catalog ==="
# The loader (source/lib/Utilities.brs LoadLocaleStrings) flattens every catalog
# section into "<section>_<bareKey>", and Translate() probes that table first.
# Every literal Translate("key") call in source/ + components/ must therefore
# have a matching flattened entry in locale/en_US/strings.json, or the UI
# silently renders the raw key. This check closes that gap for CI.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ['REPO']
os.chdir(repo)

CATALOG = 'locale/en_US/strings.json'

# Fail fast on a broken catalog with a one-line CHECK20 message (printed to
# stdout so it survives the PYOUT capture) instead of a raw traceback.
try:
    with open(CATALOG) as f:
        catalog = json.load(f)
except (OSError, ValueError) as err:
    print(f"  CHECK20: locale catalog unreadable: {err}")
    sys.exit(1)
if not isinstance(catalog, dict):
    print("  CHECK20: locale catalog unreadable: top level is not a JSON object")
    sys.exit(1)

# Mirror of FlattenLocaleCatalog(): section S + bare key K -> "S_K".
# Leaf policy mirrors the device loader: only strings enter the flattened
# table; a non-string leaf is a latent device type-crash (Translate() returns
# `as String`) and is rejected here so it can never ship.
flat = set()
bad_leaves = []
for section, data in catalog.items():
    if section == '_metadata' or not isinstance(data, dict):
        continue
    for bare_key, value in data.items():
        if not isinstance(value, str):
            bad_leaves.append(f"{section}.{bare_key}")
            continue
        flat.add(section + '_' + bare_key)

# Every literal Translate("...") call across the client. The \s* after the
# paren keeps this safe when the call opens on one line and the string literal
# sits on the next; matches are located in the comment-masked full text so
# line numbers stay exact. BrightScript strings are double-quoted only, so a
# single quote outside a string literal opens a comment that runs to the end
# of its line — whole-line AND trailing inline comments are both masked out.
# The key class INCLUDES '.' deliberately: a dotted literal ("section.key")
# can never resolve against the flat underscore table, so it must be VISIBLE
# here and reported red — the historical blind spot was the dotless class
# letting dotted literals slip through unchecked and render raw keys.
TRANSLATE_RE = re.compile(r'Translate\(\s*"([A-Za-z0-9_.]+)"')


def mask_brs_comments(text):
    # Replace each comment run with spaces of identical length, so offsets
    # (and therefore line attribution) of all remaining code stay exact.
    masked_lines = []
    for line in text.split('\n'):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        masked_lines.append(line[:cut].ljust(len(line)))
    return '\n'.join(masked_lines)

brs_files = []
for scan_dir in ('source', 'components'):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if name.endswith('.brs'):
                brs_files.append(os.path.join(root, name))

misses = []
checked_keys = set()
for path in brs_files:
    with open(path, errors='replace') as f:
        text = f.read()
    masked = mask_brs_comments(text)
    for mo in TRANSLATE_RE.finditer(masked):
        line_start = masked.rfind('\n', 0, mo.start()) + 1
        prefix = masked[line_start:mo.start()]
        # Lines that open with a double-quoted literal are doc-style noise,
        # never live calls (mirrors Check 19's own skip rule). Whole-line and
        # inline ' comments were already blanked by the masker.
        if prefix.lstrip().startswith('"'):
            continue
        key = mo.group(1)
        checked_keys.add(key)
        if key not in flat:
            lineno = text.count('\n', 0, mo.start()) + 1
            misses.append((path, lineno, key))

# The single dynamic call site — Translate(labels[n]) in RatingLabel — hides
# its keys from any literal-call scanner. Bind to the array inside its
# enclosing function so a future second `labels` variable cannot be scanned.
UTILITIES = 'source/lib/Utilities.brs'
with open(UTILITIES, errors='replace') as f:
    util_text = f.read()
rating_fn = re.search(r'function RatingLabel\(.*?\nend function', util_text, re.DOTALL)
if rating_fn is None:
    print("  CHECK20: RatingLabel function not found in " + UTILITIES)
    sys.exit(1)
labels_arr = re.search(r'labels\s*=\s*\[([^\]]*)\]', rating_fn.group(0))
if labels_arr is None:
    print("  CHECK20: literal labels array not found inside RatingLabel")
    sys.exit(1)
label_keys = re.findall(r'"([A-Za-z0-9_]+)"', labels_arr.group(1))
if not label_keys:
    print("  CHECK20: labels array in RatingLabel is empty — scanner assumption broken")
    sys.exit(1)
for key in label_keys:
    checked_keys.add(key)
    if key not in flat:
        misses.append((UTILITIES, 0, key))

# Deterministic reporting: sorted, deduplicated, per-key miss listing.
report = []
for path, lineno, key in misses:
    where = path if lineno == 0 else f"{path}:{lineno}"
    if '.' in key:
        report.append(f"  {where} — CHECK20: dotted Translate key '{key}' can never "
                      f"resolve — the flattened catalog uses the underscore form "
                      f"'{key.replace('.', '_')}' (see source/lib/Utilities.brs)")
    else:
        report.append(f"  {where} — CHECK20: Translate key '{key}' has no flattened entry in {CATALOG}")
for line in sorted(set(report)):
    print(line)
for leaf in sorted(set(bad_leaves)):
    print(f"  {CATALOG} — CHECK20: non-string leaf '{leaf}' — catalog values must be strings (Translate() returns as String)")
if misses or bad_leaves:
    if misses:
        print(f"  CHECK20: {len(set(report))} unresolved key(s) of {len(checked_keys)} checked")
    sys.exit(1)
print(f"  CHECK20: all {len(checked_keys)} Translate keys resolve under the flattened convention")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 21: every shipped locale catalog mirrors en_US ==="
# locale/ ships one folder per device locale tag (en_US is the base). The device
# loader (Utilities.brs LoadLocaleStrings) selects pkg:/locale/<tag>/strings.json
# from the normalized roAppInfo locale and FALLS BACK to pkg:/locale/en_US/-
# strings.json, and Translate() returns whatever the selected catalog holds —
# so a sibling catalog that is missing a key renders a raw key on that device,
# a stripped {placeholder} hands a format token to String.format-style callers
# as literal text, and a non-string leaf crashes the `as String` return. Check
# 20 only guards the en_US fallback; this check pins EVERY locale folder to it:
#   (a) flattened key set identical (missing AND extra both fail, listed per file)
#   (b) {placeholder} multisets identical per shared key
#   (c) newline-escape parity per shared key (the '\n\n' dialog bodies)
#   (d) non-string leaves rejected in ALL catalogs, and the runtime fallback in
#       Utilities.brs must still name pkg:/locale/en_US/strings.json verbatim
# en_US stays the sole Translate-literal source of truth — Check 20 above is
# intentionally untouched and keeps comparing against locale/en_US only.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ['REPO']
os.chdir(repo)

BASE = 'en_US'
LOCALE_ROOT = 'locale'
UTILITIES = 'source/lib/Utilities.brs'
FALLBACK_RE = re.compile(r'"pkg:/locale/en_US/strings\.json"')
PLACEHOLDER_RE = re.compile(r'\{[A-Za-z0-9_]+\}')

problems = []


def open_path(path):
    return open(path, encoding='utf-8')


def load(path):
    """Parse a catalog or record a friendly problem (never a raw traceback)."""
    try:
        with open_path(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as err:
        problems.append(f"  {path} — CHECK21: locale catalog unreadable: {err}")
        return None
    if not isinstance(data, dict):
        problems.append(f"  {path} — CHECK21: locale catalog unreadable: top level is not a JSON object")
        return None
    return data


def flat_strings(catalog, path):
    """Mirror of FlattenLocaleCatalog(): section S + bare key K -> "S_K",
    skipping _metadata. Non-string leaves are rejected (device Translate()
    returns `as String`)."""
    flat = {}
    for section, data in catalog.items():
        if section == '_metadata' or not isinstance(data, dict):
            continue
        for bare_key, value in data.items():
            if not isinstance(value, str):
                problems.append(
                    f"  {path} — CHECK21: non-string leaf '{section}.{bare_key}' — "
                    "catalog values must be strings (Translate() returns as String)")
                continue
            flat[section + '_' + bare_key] = value
    return flat


if not os.path.isdir(LOCALE_ROOT):
    print(f"  CHECK21: {LOCALE_ROOT}/ directory not found")
    sys.exit(1)

folders = sorted(d for d in os.listdir(LOCALE_ROOT)
                 if os.path.isdir(LOCALE_ROOT + '/' + d))

base_path = os.path.join(LOCALE_ROOT, BASE, 'strings.json')
if not os.path.isfile(base_path):
    print(f"  CHECK21: base catalog {base_path} missing — {BASE} is the sole fallback and source of truth")
    sys.exit(1)

base = load(base_path)
if base is None:
    for line in problems:
        print(line)
    sys.exit(1)
base_flat = flat_strings(base, base_path)
base_meta = base.get('_metadata')
if not isinstance(base_meta, dict):
    problems.append(f"  {base_path} — CHECK21: _metadata section missing or not an object")
    base_meta = {}

for folder in folders:
    path = os.path.join(LOCALE_ROOT, folder, 'strings.json')
    if not os.path.isfile(path):
        problems.append(f"  {path} — CHECK21: locale folder '{folder}' has no strings.json")
        continue
    catalog = load(path)
    if catalog is None:
        continue
    flat = flat_strings(catalog, path)

    meta = catalog.get('_metadata')
    if not isinstance(meta, dict):
        problems.append(f"  {path} — CHECK21: _metadata section missing or not an object")
        meta = {}
    if meta.get('locale') != folder:
        problems.append(
            f"  {path} — CHECK21: _metadata.locale is {meta.get('locale')!r} but folder is '{folder}'")
    if folder != BASE and isinstance(base_meta.get('source_files'), list) \
            and meta.get('source_files') != base_meta['source_files']:
        problems.append(f"  {path} — CHECK21: _metadata.source_files drifted from {base_path}")

    if folder == BASE:
        continue

    missing = sorted(set(base_flat) - set(flat))
    extra = sorted(set(flat) - set(base_flat))
    if missing:
        problems.append(
            f"  {path} — CHECK21: {len(missing)} key(s) missing vs {base_path}: {', '.join(missing)}")
    if extra:
        problems.append(
            f"  {path} — CHECK21: {len(extra)} key(s) not present in {base_path}: {', '.join(extra)}")

    for key in sorted(set(base_flat) & set(flat)):
        want = sorted(PLACEHOLDER_RE.findall(base_flat[key]))
        have = sorted(PLACEHOLDER_RE.findall(flat[key]))
        if want != have:
            problems.append(
                f"  {path} — CHECK21: placeholder mismatch on '{key}': en_US has "
                f"{', '.join(want) if want else '(none)'}, {folder} has "
                f"{', '.join(have) if have else '(none)'}")
        if base_flat[key].count('\n') != flat[key].count('\n'):
            problems.append(
                f"  {path} — CHECK21: newline-escape parity broken on '{key}' "
                f"(en_US has {base_flat[key].count(chr(10))} newline(s), {folder} has "
                f"{flat[key].count(chr(10))})")

# (d) The runtime fallback must stay pinned to en_US — LoadLocaleStrings' base
# constant is what every missing-device-locale path lands on.
try:
    with open_path(UTILITIES) as f:
        util_text = f.read()
except OSError as err:
    problems.append(f"  {UTILITIES} — CHECK21: unreadable: {err}")
else:
    if not FALLBACK_RE.search(util_text):
        problems.append(
            f"  {UTILITIES} — CHECK21: LoadLocaleStrings fallback target changed — "
            'the literal "pkg:/locale/en_US/strings.json" must remain the sole base locale')

# Deterministic reporting: problems were appended in sorted-folder order.
for line in problems:
    print(line)
if problems:
    print(f"  CHECK21: {len(problems)} locale-parity problem(s) across {len(folders)} locale folder(s)")
    sys.exit(1)

print(f"  CHECK21: all {len(folders)} locale folders mirror en_US — {len(base_flat)} "
      "flattened keys, placeholders, newline escapes and string leaves aligned")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 22: syncplay wire census is content-pinned and resolves in en_US ==="
# W5 guard law, wire-honesty split redesign (2026-09-25): the client localizes
# syncplay_error frames through the MAPPING LAW in Utilities.brs
# (SyncPlayErrorCodeToKey: trim, lowercase, "." and "-" -> "_", prefix
# "errors_"; empty/non-string -> errors_fallback). The census used to be a
# bare count pin ("exactly 16"), honest only while every member was
# server-emitted at verification time. The syncplay twin flip (landed
# 2026-09-25, PR #798 @ 9b2394ee) had added
# syncplay.create_failed / join_failed / leave_failed (contracts-registered,
# reserved at #90) BEFORE the server started sending them, so
# "known" is now a SUPERSET law: census ⊇ emitted, and the law is machine-
# enforced by CONTENT equality against an explicit split instead of a count:
#   EMITTED_VERIFIED (20 = 19 post-flip + syncplay.queue_limit_exceeded
#     promoted W-min92 on phlix-server 7baa398a evidence): read off origin/master
#     9b2394eea631739dff8f6e039d50f910c4304d97 (PR #798 twin flip) plus the
#     pre-flip record e0e010b07c7f4cc21baf10d9a945bac24edab45c, sendError
#     literals (src/Session/SyncPlay/SyncPlayManager.php +
#     src/Server/WebSocket/MessageHandler.php; re-verify READ-ONLY at each
#     flip step - a code may only LEAVE this set when its server family
#     retires). Split: 9 legacy SCREAMING current at 9b2394ee + 3 legacy
#     SCREAMING emitted ONLY by pre-flip servers (CREATE/JOIN/LEAVE_FAILED -
#     retired from current emits at 9b2394ee, kept until that server family
#     retires so old servers resolve) + 4 dotted twins live since before the
#     flip + 3 dotted twins PROMOTED by the flip (the ex-RESERVED trio).
#   RESERVED (0): EMPTY. The 2026-09-25 flip promoted the only reserved codes
#     (syncplay.create_failed/join_failed/leave_failed - phlix-contracts
#     error registry, dist/error-codes.json) to emitted-verified. The
#     function and leg (f) stay ARMED: the next flip-pending code must be
#     declared before census entry - declaration, not discovery.
# Legs:
#   (a) every literal in SyncPlayKnownErrorCodes() flattens to an existing
#       en_US errors_<key> entry, with no two codes colliding on one key
#   (b) errors_fallback exists (the generic localized last-resolve line)
#   (c) the normalizer keeps its shape (LCase + "."/"-" -> "_") and
#       Translate()'s nested probe walks every shipped section (MN-18 rotation
#       of the legacy six-name list - "errors" included) so bare-key callers
#       still localize
#   (d) SyncPlayTask.brs still routes syncplay_error text through
#       LocalizeSyncPlayError() (wire-in present)
#   (e) CENSUS CONTENT: set(census) == EMITTED_VERIFIED | RESERVED exactly -
#       a planted 21st code, a renamed member or a silently re-admitted
#       retired code all fire, which a count pin could not see
#   (f) DECLARED RESERVED: SyncPlayReservedErrorCodes() exists, names exactly
#       the RESERVED set, every member is in the census, and no reserved
#       member is SCREAMING or "local." shape
# Cross-locale parity of the errors section is covered by Check 21, which
# compares ALL sections of every locale folder against en_US.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ['REPO']
os.chdir(repo)
problems = []

UTILITIES = "source/lib/Utilities.brs"
TASK = "components/SyncPlayTask.brs"
BASE = "locale/en_US/strings.json"

# Wire truth - see the header above. Evidence (read-only greps of sendError /
# 'error_code' => literals; docblock-only GROUP_FULL / INVALID_PASSWORD
# examples in Messages.php are NOT wire codes):
#   9b2394eea631739dff8f6e039d50f910c4304d97 (2026-09-25, PR #798 twin flip):
#     9 SCREAMING still live (SyncPlayManager.php + MessageHandler.php
#     :156/:189/:213), the 4 inner-path dotted twins (:621/:702/:741/:745,
#     sent via the ?? wraps at :1588/:1627), and the PROMOTED trio
#     syncplay.create_failed/join_failed/leave_failed (sendError literals at
#     SyncPlayManager.php:1588/1627/1659). The SCREAMING trio appears ONLY in
#     flip comments there - retired from current emits.
#   e0e010b07c7f4cc21baf10d9a945bac24edab45c (pre-flip): the SCREAMING trio
#     CREATE_FAILED/JOIN_FAILED/LEAVE_FAILED were emitted; pre-flip servers
#     still speak them, so they stay resolved until that family retires.
EMITTED_VERIFIED = {
    # legacy SCREAMING - current at 9b2394ee
    "NOT_AUTHENTICATED", "NOT_IN_GROUP", "NOT_HOST", "UNKNOWN_MESSAGE",
    "HANDLER_ERROR", "PROTOCOL_VERSION_MISMATCH", "INVALID_NEW_HOST",
    "MEMBER_NOT_FOUND", "SAME_HOST",
    # dotted registry - inner-path twins (pre-flip twins, still live)
    "syncplay.group_limit_reached", "syncplay.group_not_found",
    "syncplay.invalid_password", "syncplay.group_full",
    # dotted registry - promoted by the 9b2394ee twin flip (ex-RESERVED)
    "syncplay.create_failed", "syncplay.join_failed",
    "syncplay.leave_failed",
    # dotted registry - promoted W-min92 on live emission: phlix-server
    # 7baa398a 'emit syncplay.queue_limit_exceeded on queue overflow'
    # (sendError literal SyncPlayManager.php:1254 on current master; ancestor
    # of server master verified at re-vendor time; contracts v0.5.3 row 8).
    "syncplay.queue_limit_exceeded",
    # legacy SCREAMING - emitted ONLY by pre-flip servers (e0e010b0
    # evidence; retired from current emits at 9b2394ee, kept for old-server
    # resolution - a family retires only when its servers do)
    "CREATE_FAILED", "JOIN_FAILED", "LEAVE_FAILED",
}
# EMPTY since the 2026-09-25 flip consumed the only reservation. Arm stays
# live: a future flip-pending code must be DECLARED here (and in the client's
# SyncPlayReservedErrorCodes()) before census entry - leg (f) proves it.
RESERVED = set()
EXPECTED_CENSUS = EMITTED_VERIFIED | RESERVED


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


util = None
try:
    util = read(UTILITIES)
except OSError as err:
    problems.append(f"  {UTILITIES} - CHECK22: unreadable: {err}")

codes = []
reserved = []
if util is not None:
    m = re.search(r"function SyncPlayKnownErrorCodes\(\).*?end function", util, re.S)
    if not m:
        problems.append(f"  {UTILITIES} - CHECK22: SyncPlayKnownErrorCodes() not found")
    else:
        codes = re.findall(r'"([^"]+)"', m.group(0))
    # (e) census content equality - the wire-honesty split
    census = set(codes)
    if len(codes) != len(census):
        dupes = sorted({c for c in codes if codes.count(c) > 1})
        problems.append(
            f"  {UTILITIES} - CHECK22: wire census contains duplicates {dupes}")
    missing = sorted(EXPECTED_CENSUS - census)
    extra = sorted(census - EXPECTED_CENSUS)
    if missing or extra:
        problems.append(
            f"  {UTILITIES} - CHECK22: wire census drifted from the pinned "
            f"emitted+reserved split (expected {len(EXPECTED_CENSUS)} codes: "
            f"{len(EMITTED_VERIFIED)} emitted-verified + {len(RESERVED)} "
            f"reserved)"
            + (f"; missing {missing}" if missing else "")
            + (f"; undeclared/unknown {extra}" if extra else "")
            + " - promote reserved codes only with server evidence, and mint "
            "client strings in SyncPlayLocalErrorCodes() instead")
    # (f) declared-reserved registry
    mr = re.search(r"function SyncPlayReservedErrorCodes\(\).*?end function", util, re.S)
    if not mr:
        problems.append(
            f"  {UTILITIES} - CHECK22: SyncPlayReservedErrorCodes() not found - "
            "flip-pending codes must be DECLARED, never silently census-pushed")
    else:
        reserved = re.findall(r'"([^"]+)"', mr.group(0))
        rset = set(reserved)
        if rset != RESERVED:
            problems.append(
                f"  {UTILITIES} - CHECK22: reserved census drifted from the "
                f"declared flip-pending set {sorted(RESERVED)}: found {sorted(rset)}")
        for code in sorted(rset):
            if code not in census:
                problems.append(
                    f"  {UTILITIES} - CHECK22: reserved code '{code}' is not a "
                    "wire census member")
            if not re.fullmatch(r"syncplay\.[a-z0-9_]+", code):
                problems.append(
                    f"  {UTILITIES} - CHECK22: reserved code '{code}' is not a "
                    'dotted registry name - SCREAMING members are emitted, not reserved')
    if not re.search(
            r'LCase\(raw\)\.Replace\("\.", "_"\)\.Replace\("-", "_"\)', util):
        problems.append(
            f"  {UTILITIES} - CHECK22: mapping law shape changed - normalizer no "
            'longer lowercases and maps "." and "-" to "_"')
    if ('function BuildBareLocaleIndex(' not in util
            or 'for each section in raw.Keys()' not in util
            or 'if section <> "_metadata"' not in util
            or 'LoadLocaleStrings._bare = BuildBareLocaleIndex(raw)' not in util):
        problems.append(
            f'  {UTILITIES} - CHECK22: Translate() nested probe no longer walks EVERY '
            'shipped section (MN-18 cure shape) - the errors family must stay resolvable '
            'for bare-key callers')

flat = set()
try:
    doc = json.loads(read(BASE))
    for section, section_data in doc.items():
        if section == "_metadata" or not isinstance(section_data, dict):
            continue
        for bare_key, leaf in section_data.items():
            if isinstance(leaf, str):
                flat.add(f"{section}_{bare_key}")
except (OSError, ValueError) as err:
    problems.append(f"  {BASE} - CHECK22: unreadable/unparsable: {err}")

if "errors_fallback" not in flat:
    problems.append(
        f"  {BASE} - CHECK22: errors_fallback missing - the generic localized "
        "last-resolve line is required")

seen = {}
for code in codes:
    key = "errors_" + code.strip().lower().replace(".", "_").replace("-", "_")
    if key in seen:
        problems.append(
            f"  {UTILITIES} - CHECK22: codes '{seen[key]}' and '{code}' collide "
            f"on key '{key}'")
    seen[key] = code
    if key not in flat:
        problems.append(
            f"  {BASE} - CHECK22: known code '{code}' maps to '{key}' which is "
            "missing from the en_US errors catalog")

try:
    task = read(TASK)
except OSError as err:
    task = ""
    problems.append(f"  {TASK} - CHECK22: unreadable: {err}")
if "LocalizeSyncPlayError(" not in task:
    problems.append(
        f"  {TASK} - CHECK22: syncplay_error text no longer routed through "
        "LocalizeSyncPlayError()")

for line in problems:
    print(line)
if problems:
    print(f"  CHECK22: {len(problems)} syncplay error-catalog problem(s)")
    sys.exit(1)

print(f"  CHECK22: all {len(EXPECTED_CENSUS)} wire codes "
      f"({len(EMITTED_VERIFIED)} emitted-verified + {len(RESERVED)} declared "
      "reserved) + errors_fallback resolve in en_US; census content-pinned; "
      "mapping law and task wire-in intact")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 23: client local.* error family stays separate from the wire census ==="
# The W5 wire census (Check 22) must remain an honest list of codes the SERVER
# can put on the wire. This build also MINTS local error codes - "local.*"
# strings produced on-device by SyncPlayTask setup failures and SyncPlayScene
# REST-path failures, which never ride a frame. They deliberately share the
# mapping law (SyncPlayErrorCodeToKey -> errors_local_* in the same errors
# section) but keep a SEPARATE census. Law (mirrored from the CLIENT-GENERATED
# ERROR FAMILY docblock in Utilities.brs):
#   (a) SyncPlayLocalErrorCodes() exists; every entry matches local.<snake>
#   (b) each local code flattens (via the Check 22 normalizer) to an existing
#       en_US errors_local_* entry, collision-free within the family
#   (c) WIRE-CENSUS HONESTY: SyncPlayKnownErrorCodes() still lists exactly 20
#       wire codes (20 emitted-verified — 19 since the flip + queue_limit_
#       exceeded promoted W-min92 on server 7baa398a evidence — + 0
#       declared-reserved post-flip per Check 22's
#       content pin), none starts with "local.", and no wire code
#       normalizes onto a local key (the families cannot impersonate each other)
#   (d) SECTION PURITY: every key in the en_US errors section belongs to
#       wire - {fallback} - local - nothing unaccounted may squat in the error
#       registry (this is what makes the census bidirectional, not just forward)
#   (e) CALL-SITE LAW: every EmitError("...") first argument in
#       components/SyncPlayTask.brs and every LocalizeSyncPlayLocalError("...")
#       literal across source/ + components/ names a census member - a task
#       error may never again carry a raw display literal - and the task still
#       resolves local text through LocalizeSyncPlayLocalError() (wire-in)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ["REPO"]
os.chdir(repo)
problems = []

UTILITIES = "source/lib/Utilities.brs"
TASK = "components/SyncPlayTask.brs"
BASE = "locale/en_US/strings.json"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def norm(code):
    # Mirror of SyncPlayErrorCodeToKey's normalizer (Check 22 pins its shape).
    return "errors_" + code.strip().lower().replace(".", "_").replace("-", "_")


def mask_brs_comments(text):
    # Same contract as Check 20's masker: comment runs become spaces of
    # identical length, so line attribution of the remaining code stays exact
    # and doc-style examples like LocalizeSyncPlayLocalError("local.*") in a
    # header comment can never be scanned as call sites.
    masked_lines = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        masked_lines.append(line[:cut].ljust(len(line)))
    return "\n".join(masked_lines)


local_codes = []
wire_codes = []

try:
    util = read(UTILITIES)
except OSError as err:
    util = ""
    problems.append(f"  {UTILITIES} - CHECK23: unreadable: {err}")
if util:
    ml = re.search(r"function SyncPlayLocalErrorCodes\(\).*?end function", util, re.S)
    if not ml:
        problems.append(
            f"  {UTILITIES} - CHECK23: SyncPlayLocalErrorCodes() not found - "
            "the client-generated local.* census is required")
    else:
        local_codes = re.findall(r'"([^"]+)"', ml.group(0))
        if not local_codes:
            problems.append(f"  {UTILITIES} - CHECK23: local census is empty")
        for code in local_codes:
            if not re.fullmatch(r"local\.[a-z0-9_]+", code):
                problems.append(
                    f"  {UTILITIES} - CHECK23: local code '{code}' violates the "
                    "shape local.<snake_name>")
    mw = re.search(r"function SyncPlayKnownErrorCodes\(\).*?end function", util, re.S)
    if not mw:
        problems.append(f"  {UTILITIES} - CHECK23: SyncPlayKnownErrorCodes() not found")
    else:
        wire_codes = re.findall(r'"([^"]+)"', mw.group(0))
    # (c) wire-census honesty (content authority is Check 22's pin (e); the
    # count here re-derives it independently so the two gates stay redundant)
    if len(wire_codes) != 20:
        problems.append(
            f"  {UTILITIES} - CHECK23: wire census must stay the 20 "
            "wire-honest codes (20 emitted-verified + 0 declared-reserved), "
            f"found {len(wire_codes)} - client-minted "
            "strings belong in SyncPlayLocalErrorCodes(), never here")
    for code in wire_codes:
        if code.strip().lower().startswith("local."):
            problems.append(
                f"  {UTILITIES} - CHECK23: wire census contains minted local "
                f"code '{code}' - wire-census honesty broken")

# (b) family-internal collisions + en_US resolution
seen = {}
for code in local_codes:
    key = norm(code)
    if key in seen:
        problems.append(
            f"  {UTILITIES} - CHECK23: local codes '{seen[key]}' and '{code}' "
            f"collide on key '{key}'")
    seen[key] = code

# (c) family disjointness on normalized keys
wire_keys = {norm(c) for c in wire_codes}
local_keys = {norm(c) for c in local_codes}
overlap = sorted(wire_keys & local_keys)
if overlap:
    problems.append(
        f"  {UTILITIES} - CHECK23: wire and local families collide on "
        f"key(s): {', '.join(overlap)}")

# Catalog side: (b) resolution + (d) section purity
try:
    doc = json.loads(read(BASE))
except (OSError, ValueError) as err:
    doc = None
    problems.append(f"  {BASE} - CHECK23: unreadable/unparsable: {err}")

if isinstance(doc, dict):
    es = doc.get("errors")
    if not isinstance(es, dict):
        problems.append(f"  {BASE} - CHECK23: errors section missing")
        es = {}
    for code in local_codes:
        key = norm(code)
        bare = key[len("errors_"):]
        if not isinstance(es.get(bare), str):
            problems.append(
                f"  {BASE} - CHECK23: local code '{code}' maps to '{key}' "
                "which is missing from the en_US errors catalog")
    accounted = set(wire_keys) | {"errors_fallback"} | set(local_keys)
    for bare in sorted(es):
        if not isinstance(es[bare], str):
            continue  # non-string leaves are CHECK20/21 territory
        if "errors_" + bare not in accounted:
            problems.append(
                f"  {BASE} - CHECK23: errors entry '{bare}' belongs to no "
                "accounted family (wire census, fallback, or local census) - "
                "the error registry must stay bidirectionally honest")

# (e) call-site law
local_set = set(local_codes)
try:
    task_masked = mask_brs_comments(read(TASK))
except OSError as err:
    task_masked = ""
    problems.append(f"  {TASK} - CHECK23: unreadable: {err}")
if task_masked:
    sites = 0
    for mo in re.finditer(r'EmitError\(\s*"([^"]*)"', task_masked):
        sites += 1
        arg = mo.group(1)
        if arg not in local_set:
            lineno = task_masked.count("\n", 0, mo.start()) + 1
            problems.append(
                f"  {TASK}:{lineno} - CHECK23: EmitError argument '{arg}' is "
                "not a SyncPlayLocalErrorCodes() member - task errors must "
                "name cataloged local.* codes, never raw display literals")
    if sites == 0:
        problems.append(
            f"  {TASK} - CHECK23: no EmitError(\"local.*\") call sites found - "
            "the client error family went unused or the scanner anchor moved")
    if "LocalizeSyncPlayLocalError(" not in task_masked:
        problems.append(
            f"  {TASK} - CHECK23: EmitError no longer resolves local text "
            "through LocalizeSyncPlayLocalError()")

for scan_dir in ("source", "components"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if not name.endswith(".brs"):
                continue
            path = os.path.join(root, name)
            try:
                text = mask_brs_comments(read(path))
            except OSError as err:
                problems.append(f"  {path} - CHECK23: unreadable: {err}")
                continue
            for mo in re.finditer(r'LocalizeSyncPlayLocalError\(\s*"([^"]*)"', text):
                arg = mo.group(1)
                if arg not in local_set:
                    lineno = text.count("\n", 0, mo.start()) + 1
                    problems.append(
                        f"  {path}:{lineno} - CHECK23: "
                        f"LocalizeSyncPlayLocalError argument '{arg}' is not "
                        "a member of SyncPlayLocalErrorCodes()")

for line in problems:
    print(line)
if problems:
    print(f"  CHECK23: {len(problems)} client-local error-family separation problem(s)")
    sys.exit(1)

print(f"  CHECK23: all {len(local_codes)} local.* codes + {len(wire_codes)} wire "
      "codes stay in separate censuses; errors section pure; call-site law intact")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 24: token-bearing catalog values flow through TranslateWithParams ==="
# TOKEN-DEFECT LAW (the i18n {placeholder} family). A catalog value that
# carries a {name} placeholder ("Logged in as: {email}") MUST be consumed
# through Utilities.brs TranslateWithParams, which substitutes each token BY
# NAME (position-free, the MembersCountText exemplar generalized in PR #86/#87).
# The historical defect class - `Translate("key") + value` - rendered the
# literal braces on the TV and froze the token's position in the English
# sentence; the double-colon shape additionally doubled the catalog's own
# label colon. Legs:
#   (a) token-bearing key set = union over ALL shipped locale catalogs (en_US
#       is SSOT; Check 21 pins parity - the union refuses to trust it blindly)
#   (b) every quoted reference to such a key in the runtime scan set must be
#       anchored in a TranslateWithParams( call; a bare Translate("key") or
#       any other occurrence is a violation with file:line
#   (c) DEAD-COPY DETECTION: a token-bearing key never consumed anywhere is
#       red too - unconsumed copy is how the raw-literal dialogs hid
#   (d) SHAPE PIN: TranslateWithParams must still exist, still delegate to
#       ApplyNamedTokens(Translate(key), params), and the pure core must still
#       substitute via Replace("{" + token + "}") - the law cannot vacate by
#       quietly gutting the helper
#   (e) PARAM COMPLETENESS: at each literal-AA call site the provided keys must
#       cover the catalog's token multiset - a missing param re-leaks braces.
#       A non-literal (dynamic) params argument is unverifiable statically and
#       is accepted, documented limitation.
#   (f) RESOLUTION MIRROR: every literal TranslateWithParams("key") must name a
#       flattened (section_key) entry in locale/en_US/strings.json - the
#       token-law conversion moved such keys out of Check 20's Translate()
#       regex field of view, so this leg keeps the anti-typo / raw-key-echo
#       guarantee TOTAL across both consumption functions.
# WHITELIST HONESTY: the scan set is source/ + components/ *.brs ONLY.
# docs/*.md quote catalog values verbatim and tests/unit/*.test.brs assert the
# law's raw-token inputs on purpose - they are excluded BY DESIGN, not by
# oversight; a token sample there must never be scanned as a consumption site.
# Comment runs are masked with the Check 20/23 masker, so doc-style examples
# inside .brs headers cannot register as call sites either.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob
import json
import os
import re
import sys

repo = os.environ["REPO"]
os.chdir(repo)
problems = []

TOKEN_RE = re.compile(r"\{([A-Za-z0-9_]+)\}")
QUOTED_KEY_TPL = '"{key}"'
AA_CALL_RE = re.compile(
    r'TranslateWithParams\(\s*"([A-Za-z0-9_]+)"\s*,\s*\{([^{}]*)\}')


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def mask_brs_comments(text):
    # Same contract as Check 20/23: comment runs become spaces of identical
    # length so line attribution of the remaining code stays exact.
    masked_lines = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        masked_lines.append(line[:cut].ljust(len(line)))
    return "\n".join(masked_lines)


# (a) token-bearing key set across every shipped locale catalog
tokens_by_key = {}
locale_files = sorted(glob.glob("locale/*/strings.json"))
if not locale_files:
    problems.append("  locale/*/strings.json - CHECK24: no locale catalogs found")
for path in locale_files:
    try:
        doc = json.loads(read(path))
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK24: unreadable/unparsable: {err}")
        continue
    if not isinstance(doc, dict):
        problems.append(f"  {path} - CHECK24: top level is not a JSON object")
        continue
    for section, data in doc.items():
        if section == "_metadata" or not isinstance(data, dict):
            continue
        for bare, leaf in data.items():
            if not isinstance(leaf, str):
                continue  # string-only leaves are CHECK20/21 territory
            found = TOKEN_RE.findall(leaf)
            if found:
                flat = f"{section}_{bare}"
                tokens_by_key.setdefault(flat, set()).update(found)

# (b)/(c) runtime scan set - see WHITELIST HONESTY in the header above
masked_files = {}
for scan_dir in ("source", "components"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if not name.endswith(".brs"):
                continue
            p = os.path.join(root, name)
            try:
                masked_files[p] = mask_brs_comments(read(p))
            except OSError as err:
                problems.append(f"  {p} - CHECK24: unreadable: {err}")

for key in sorted(tokens_by_key):
    occurrences = 0
    for path in sorted(masked_files):
        masked = masked_files[path]
        for mo in re.finditer(re.escape(QUOTED_KEY_TPL.format(key=key)), masked):
            occurrences += 1
            head = masked[:mo.start()]
            if re.search(r"TranslateWithParams\(\s*$", head):
                continue
            lineno = masked.count("\n", 0, mo.start()) + 1
            if re.search(r"Translate\(\s*$", head):
                problems.append(
                    f"  {path}:{lineno} - CHECK24: Translate(\"{key}\") is "
                    "concatenated raw - token-bearing values must flow through "
                    "TranslateWithParams (position-free substitution law)")
            else:
                problems.append(
                    f"  {path}:{lineno} - CHECK24: token-bearing key "
                    f"\"{key}\" referenced outside a TranslateWithParams call")
    if occurrences == 0:
        problems.append(
            f"  locale/*/strings.json - CHECK24: dead copy - token-bearing key "
            f"\"{key}\" (tokens: {', '.join(sorted(tokens_by_key[key]))}) is "
            "never consumed in source/ or components/ - unconsumed localized "
            "copy means the call site still renders its own raw string")

# (d) shape pin - the law's implementation must stay wired
UTILITIES = os.path.join("source", "lib", "Utilities.brs")
util = masked_files.get(UTILITIES, "")
if not re.search(r"function TranslateWithParams\(", util):
    problems.append(
        f"  {UTILITIES} - CHECK24: TranslateWithParams() not found - the law "
        "has no implementation to consume token-bearing values through")
elif not re.search(r"ApplyNamedTokens\(Translate\(key\),\s*params\)", util):
    problems.append(
        f"  {UTILITIES} - CHECK24: TranslateWithParams() no longer delegates "
        "to ApplyNamedTokens(Translate(key), params) - shape drift")
elif 'Replace("{" + token + "}"' not in util:
    problems.append(
        f"  {UTILITIES} - CHECK24: ApplyNamedTokens() no longer substitutes "
        'by name via Replace("{" + token + "}") - shape drift')

# (f) resolution mirror - TranslateWithParams literal keys must exist in the
# en_US flattened table: the conversion moved 12 catalog-bound keys out of
# CHECK 20's Translate("...") regex field of view, so this leg keeps the
# anti-typo guarantee total across BOTH consumption functions.
en_flat = set()
try:
    en_doc = json.loads(read(os.path.join("locale", "en_US", "strings.json")))
    for section, data in en_doc.items():
        if section == "_metadata" or not isinstance(data, dict):
            continue
        for bare, leaf in data.items():
            if isinstance(leaf, str):
                en_flat.add(f"{section}_{bare}")
except (OSError, ValueError) as err:
    problems.append(f"  locale/en_US/strings.json - CHECK24: unreadable: {err}")

TP_KEY_RE = re.compile(r'TranslateWithParams\(\s*"([A-Za-z0-9_.]+)"')
for path in sorted(masked_files):
    masked = masked_files[path]
    for mo in TP_KEY_RE.finditer(masked):
        key = mo.group(1)
        if key not in en_flat:
            lineno = masked.count("\n", 0, mo.start()) + 1
            problems.append(
                f"  {path}:{lineno} - CHECK24: TranslateWithParams key \"{key}\" "
                "has no flattened entry in locale/en_US/strings.json (raw-key "
                "rendering guard, mirrors CHECK 20 for this call form)")

# (e) param completeness at literal-AA call sites
for path in sorted(masked_files):
    masked = masked_files[path]
    for mo in AA_CALL_RE.finditer(masked):
        key, aa_body = mo.group(1), mo.group(2)
        if key not in tokens_by_key:
            continue
        provided = set(re.findall(r"([A-Za-z0-9_]+)\s*:", aa_body))
        missing = sorted(tokens_by_key[key] - provided)
        if missing:
            lineno = masked.count("\n", 0, mo.start()) + 1
            problems.append(
                f"  {path}:{lineno} - CHECK24: "
                f"TranslateWithParams(\"{key}\") omits param(s) {missing} - "
                "the literal braces would re-leak to the screen")

for line in problems:
    print(line)
if problems:
    print(f"  CHECK24: {len(problems)} token-substitution law problem(s)")
    sys.exit(1)

print(f"  CHECK24: all {len(tokens_by_key)} token-bearing catalog values "
      "consumed only via TranslateWithParams; params cover every token; zero "
      "raw-Translate concatenations, zero dead copies, helper shape intact; "
      "all TranslateWithParams keys resolve in en_US")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 25: components/*.xml chrome literals are inside the translate net ==="
# XML chrome gap law (i18n lane, 2026-09-25): user-facing strings shipped as
# SceneGraph markup (title=/text= attrs on visible nodes) were INVISIBLE to
# CHECKs 19-24, which only read .brs source. That invisibility was the last
# documented i18n gap (docs/i18n.md "XML chrome"). The estate pattern is
# pkg:/ catalog reads via Utilities.Translate() - locale:// mounting was
# deliberately avoided - so markup keeps English defaults and gets localized
# text programmatically at init (ApplyXmlChrome() precedent, mirroring the
# DetailScene action-button pattern).
# Law: every non-empty title=/text= literal in components/**/*.xml must be
#   (1) on the per-file EXEMPT list below (brand, glyphs, never-rendered
#       placeholders - stale exemptions are themselves a violation), or
#   (2) byte-match (after HTML-entity decoding) some en_US catalog value, on
#       a node carrying an id, and the paired .brs (components/<Name>.brs or
#       source/<Name>.brs) must both address that id via findNode(...)
#       (case-insensitive) AND call Translate() for a key whose value is that
#       literal - i.e. an actual programmatic override path exists.
# Element-content strings (<text>x</text>) have no attribute-override shape
# and are rejected outright. Unknown non-exempt literals fail loud file:line.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, html, json, os, re, sys
import xml.parsers.expat as expat

repo = os.environ["REPO"]
os.chdir(repo)
problems = []

SKIP_TAGS = {"interface", "field", "event", "component", "script", "function",
             "children", "annotation"}

# Per-file allow-list of EXEMPT literals, each with its reason. If the literal
# disappears but the entry stays, the check fails - exemptions cannot rot.
EXEMPT = {
    "components/HomeScene.xml": {
        "Phlix": "brand name - intentionally never localized"},
    "components/LoginScene.xml": {
        "Phlix": "brand name - intentionally never localized"},
    "components/PlayerScene.xml": {
        "PiP": "established industry acronym for picture-in-picture"},
    "components/RatingBadge.xml": {
        "\u2605": "decorative glyph, not text",
        "0.0/10": "numeric placeholder overwritten by data binding before "
                  "the badge ever renders"},
}

# en_US value -> set of flattened keys carrying it (entity-decoded compare)
en_values = {}
try:
    doc = json.loads(open(os.path.join("locale", "en_US", "strings.json"),
                          encoding="utf-8").read())
    for section, data in doc.items():
        if section == "_metadata" or not isinstance(data, dict):
            continue
        for bare, leaf in data.items():
            if isinstance(leaf, str):
                en_values.setdefault(leaf, set()).add(f"{section}_{bare}")
except (OSError, ValueError) as err:
    problems.append(f"  locale/en_US/strings.json - CHECK25: unreadable: {err}")


def parse(path):
    nodes, contents = [], []
    holder = {"in_text": False, "line": 0, "buf": []}
    parser = expat.ParserCreate()

    def start(tag, att):
        if tag in SKIP_TAGS:
            return
        title, text = att.get("title"), att.get("text")
        if title is not None and title.strip():
            nodes.append((parser.CurrentLineNumber, tag, att.get("id"),
                          "title", html.unescape(title)))
        elif text is not None and text.strip():
            nodes.append((parser.CurrentLineNumber, tag, att.get("id"),
                          "text", html.unescape(text)))
        if tag == "text":
            holder.update(in_text=True, line=parser.CurrentLineNumber, buf=[])

    def chardata(s):
        if holder["in_text"]:
            holder["buf"].append(s)

    def end(tag):
        if tag == "text" and holder["in_text"]:
            joined = "".join(holder["buf"])
            if joined.strip():
                contents.append((holder["line"], tag, joined.strip()))
            holder["in_text"] = False

    parser.StartElementHandler = start
    parser.CharacterDataHandler = chardata
    parser.EndElementHandler = end
    try:
        parser.Parse(open(path, "rb").read(), True)
    except Exception as err:
        problems.append(f"  {path} - CHECK25: unparsable XML: {err}")
        return [], []
    return nodes, contents


brs_cache = {}


def paired_brs(xml_path):
    name = os.path.splitext(os.path.basename(xml_path))[0]
    for cand in (os.path.join("components", name + ".brs"),
                 os.path.join("source", name + ".brs")):
        if cand in brs_cache:
            return brs_cache[cand]
        if os.path.exists(cand):
            brs_cache[cand] = (cand, open(cand, encoding="utf-8").read())
            return brs_cache[cand]
    brs_cache[name] = None
    return None, None


used_exempt, total = set(), 0
for xml_path in sorted(glob.glob(os.path.join("components", "**", "*.xml"),
                                 recursive=True)):
    xml_key = xml_path.replace(os.sep, "/")
    nodes, contents = parse(xml_path)
    total += len(nodes)
    exemption = EXEMPT.get(xml_key, {})
    for line, tag, nid, attr, value in nodes:
        if value in exemption:
            used_exempt.add((xml_key, value))
            continue
        keys = en_values.get(value)
        if keys is None:
            problems.append(
                f"  {xml_path}:{line} - CHECK25: XML chrome literal "
                f'"{value}" on <{tag}> has no en_US catalog entry - mint a '
                "key, add the ApplyXmlChrome() override in the paired .brs, "
                "and mirror all 7 locale files (docs/i18n.md)")
            continue
        if not nid:
            problems.append(
                f"  {xml_path}:{line} - CHECK25: <{tag}> literal \"{value}\" "
                "has no id, so no programmatic override can address it - add "
                "id= and set it from ApplyXmlChrome() in the paired .brs")
            continue
        brs_path, brs = paired_brs(xml_path)
        if brs is None:
            problems.append(
                f"  {xml_path}:{line} - CHECK25: \"{value}\" on id=\"{nid}\" "
                "has no paired .brs to carry the Translate() override")
            continue
        if not re.search(r'(?i)findnode\("' + re.escape(nid) + r'"\)', brs):
            problems.append(
                f"  {xml_path}:{line} - CHECK25: node id \"{nid}\" is never "
                f"addressed via findNode() in {brs_path} - add it to "
                "ApplyXmlChrome()")
            continue
        if not any(re.search(r'Translate\("' + re.escape(k) + r'"\)', brs)
                   for k in keys):
            problems.append(
                f"  {xml_path}:{line} - CHECK25: \"{value}\" maps to catalog "
                f"key(s) {sorted(keys)} but {brs_path} never calls "
                "Translate() for any of them - wire the override")
    for line, tag, content in contents:
        problems.append(
            f"  {xml_path}:{line} - CHECK25: element-content string in "
            f"<{tag}> ({content[:40]!r}) - XML text content has no attribute "
            "override shape; use a catalog-backed title/text attribute")

for xml_key, exemption in EXEMPT.items():
    for value, reason in exemption.items():
        if (xml_key, value) not in used_exempt:
            problems.append(
                f"  {xml_key} - CHECK25: stale exemption \"{value}\" "
                f"(\"{reason}\") no longer matches any XML literal - "
                "remove it")

for line in problems:
    print(line)
if problems:
    print(f"  CHECK25: {len(problems)} XML chrome problem(s)")
    sys.exit(1)

print(f"  CHECK25: all {total} XML chrome literals exempt or catalog-backed "
      "with a findNode+Translate override path in the paired .brs; zero "
      "element-content strings; zero stale exemptions")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 26: API-envelope reads stay behind the unwrap choke ==="
# Envelope law (2c119f9 follow-through, 2026-09-29): ApiClient.request() returns
# the TRANSPORT envelope {status,ok,data,error}; the server payload rides at
# .data. Commit 2c119f9 shipped that wrapper and updated ZERO consumers, so
# every reader of a former server field died silently (Home rails, hub detection,
# login, episodes, guide, syncplay groups - see docs/api-envelope.md). The law
# is one unwrap at one choke: UnwrapApiEnvelope() (source/lib/ApiClient.brs),
# applied by components/ApiTask.brs ApplyEnvelope() before any scene sees a
# response. This check fails loud on the fingerprints of the old bug class:
#   R1  code (not comments/strings) reading a server payload key directly off an
#       envelope-shaped variable name (env./resp./result./raw./data. + a known
#       server key) anywhere in source/ or components/ - chain reads like
#       resp.data.items stay legal because the dotted prefix rejects them.
#   R2  components/ApiTask.brs result.data assignments must come from an
#       unwrapped source: ApplyEnvelope/UnwrapApiEnvelope, the documented
#       payload-level exceptions (api.user, api2.probeHealth()), drills
#       (result.data.libraries/.item), or literals - never a bare api.X() call.
#   R3  the choke artifacts must exist: ApiTask defines ApplyEnvelope, and
#       ApiClient.brs (when present) carries the ENVELOPE LAW marker plus the
#       UnwrapApiEnvelope function (docs/ is not part of the channel zip, so
#       the docblock is the packaging-safe law citation).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ["REPO"]

VARS = r"env|envelope|resp|response|result|raw|data"
KEYS = (r"libraries|servers|groups|session_id|programs|recordings|channels|"
        r"audiobook|audiobooks|item|items|recommendations|artists|albums|tracks|"
        r"photos|collections|users|profiles|schedules|tags|chapters|letters|"
        r"genres|scan_status|new_password|access_token|refresh_token|read_url")
FORBIDDEN = re.compile(rf"(?<![.\w])(?:{VARS})\.(?:{KEYS})\b")
ASSIGN = re.compile(r"result\.data\s*=")
ASSIGN_ALLOWED = re.compile(
    r"UnwrapApiEnvelope\(|ApplyEnvelope\(|\bapi\.user\b|\bhubApi\.user\b|"
    r"api2\.probeHealth\(\)|result\.data\.(libraries|item)\b|=\s*\{|=\s*\[\]|=\s*invalid"
)

problems = []
scanned = 0

def code_only(line):
    """Strip double-quoted strings; drop full-line and inline ' comments."""
    code = re.sub(r'"[^"]*"', '""', line)
    if code.lstrip().startswith("'"):
        return ""
    cut = code.find("'")
    if cut >= 0:
        code = code[:cut]
    return code

# R1 - forbidden envelope-level server key reads across the shipped sources.
paths = sorted(
    glob.glob(os.path.join(repo, "source", "**", "*.brs"), recursive=True)
    + glob.glob(os.path.join(repo, "components", "**", "*.brs"), recursive=True)
)
for path in paths:
    rel = os.path.relpath(path, repo)
    scanned += 1
    with open(path, encoding="utf-8") as f:
        for num, line in enumerate(f, 1):
            for m in FORBIDDEN.finditer(code_only(line)):
                problems.append(
                    f"  {rel}:{num} - CHECK26: envelope-law leak: {m.group(0)} "
                    "reads a server payload key off an envelope-level variable; "
                    "unwrap with UnwrapApiEnvelope() behind an ok guard "
                    "(see docs/api-envelope.md)")

# R2/R3 - the ApiTask choke.
apitask = os.path.join(repo, "components", "ApiTask.brs")
if os.path.exists(apitask):
    with open(apitask, encoding="utf-8") as f:
        lines = f.readlines()
    if not any(re.match(r"\s*sub\s+ApplyEnvelope\b", l) for l in lines):
        problems.append("  components/ApiTask.brs - CHECK26: ApplyEnvelope() "
                        "choke helper is missing")
    for num, line in enumerate(lines, 1):
        code = code_only(line)
        if ASSIGN.search(code) and not ASSIGN_ALLOWED.search(code):
            problems.append(
                f"  components/ApiTask.brs:{num} - CHECK26: result.data assigned "
                f"from a raw helper result ({line.strip()[:80]}); route it through "
                "ApplyEnvelope()/UnwrapApiEnvelope() so scenes only ever see the "
                "server payload")

# R3 - ApiClient law markers (file is absent in the minimal scratch checkouts
# the portable regression test builds; the rule is conditional by design).
apiclient = os.path.join(repo, "source", "lib", "ApiClient.brs")
if os.path.exists(apiclient):
    with open(apiclient, encoding="utf-8") as f:
        client_src = f.read()
    if "ENVELOPE LAW" not in client_src:
        problems.append("  source/lib/ApiClient.brs - CHECK26: ENVELOPE LAW "
                        "docblock marker missing (the law citation travels in "
                        "the file because docs/ is not shipped in the zip)")
    if not re.search(r"function\s+UnwrapApiEnvelope\b", client_src):
        problems.append("  source/lib/ApiClient.brs - CHECK26: "
                        "UnwrapApiEnvelope() helper missing")

if problems:
    for p in problems:
        print(p)
    print(f"  CHECK26: {len(problems)} envelope-law problem(s)")
    sys.exit(1)

print(f"  CHECK26: all {scanned} shipped .brs files keep server payload reads "
      "behind the unwrap choke; ApiTask result.data assignments are all "
      "unwrap-derived or documented exceptions; law markers present")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 27: child-scene close is local removal, never a bubble-up ==="
# Back-navigation law (C03, 2026-10-28): the requestClose contract (docs/
# navigation.md) makes the OBSERVING parent remove the child scene that raised
# the signal - the parent-side mirror of PhlixApp.PopScreen. Before this fix
# every parent handler (22 files) re-bubbled m.top.requestClose = true instead;
# the bubble died at HomeScene (whose requestClose is not even declared in
# HomeScene.xml and is not observed by PhlixApp.ShowHome), so Back was a
# silent no-op on every screen opened from Home. This check fails loud if the
# bubble anti-pattern returns to any scene that owns a child-close handler:
#   R1  every components/*.brs defining 'sub OnChildRequestClose' (except
#       PhlixApp.brs, whose handler pops the screen stack) must take
#       '(event as Object)' and remove the requesting child via RemoveChild.
#   R2  no OnChildRequestClose body may set m.top.requestClose (that is the
#       dead bubble; self-close signals belong in OnKeyEvent/OnBackPressed).
#   R3  HomeScene.brs must never write m.top.requestClose - the field does
#       not exist on its interface and nothing above observes it.
#   R4  every ObserveField("requestClose", "NAME") must resolve NAME to a sub
#       defined by the OBSERVING component (its own .brs or a script its XML
#       attaches); an unresolvable handler name is a runtime-error vector on
#       the very signal the child removal depends on (C03-r2 issue 6a).
#   R5  every child scene that is observed for requestClose - by a literal
#       create+observe pair in a parent or via PhlixApp.PushScreen - must
#       write requestClose = true somewhere in its own .brs; a scene that
#       never fires the signal can never be closed by its observer (the
#       RecommendationsScene "For You" swallow, C03-r2 issue 1/b).
#   R6  no Teardown body may UnObserveField("requestClose") on m.top: the
#       variant-B self-observe arm routes a scene's OWN close signal through
#       Teardown INSIDE the dispatch, and unobserving the notifying field
#       there can prune the parent's pending RemoveChild arm (C03-r2 issue 2;
#       PopScreen is immune only because it pops outside field dispatch).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
problems = []

handler_re = re.compile(
    r"^sub\s+OnChildRequestClose\s*(\(event as Object\)|\(\))\s*\n(.*?)^end sub",
    re.MULTILINE | re.DOTALL)

scanned = 0
for path in sorted(glob.glob(os.path.join(repo, "components", "*.brs"))):
    rel = os.path.relpath(path, repo)
    src = open(path, encoding="utf-8").read()
    if rel == os.path.join("components", "PhlixApp.brs"):
        continue
    for m in handler_re.finditer(src):
        scanned += 1
        sig, body = m.group(1), m.group(2)
        if sig != "(event as Object)":
            problems.append(
                f"  {rel} - CHECK27: OnChildRequestClose lacks the event "
                "parameter; it cannot identify the requesting child to "
                "remove it")
        if "RemoveChild(" not in body:
            problems.append(
                f"  {rel} - CHECK27: OnChildRequestClose never calls "
                "RemoveChild; the requestClose contract requires the "
                "observing parent to remove the child scene locally")
        if re.search(r"m\.top\.requestClose\s*=\s*true", body):
            problems.append(
                f"  {rel} - CHECK27: OnChildRequestClose re-bubbles "
                "m.top.requestClose = true; the bubble died below HomeScene "
                "and made Back a no-op (C03 regression)")

home = os.path.join(repo, "components", "HomeScene.brs")
if os.path.exists(home):
    for num, line in enumerate(open(home, encoding="utf-8"), 1):
        if re.search(r"m\.top\.requestClose\s*=", line):
            problems.append(
                f"  components/HomeScene.brs:{num} - CHECK27: HomeScene "
                "writes its own requestClose - the field is undeclared in "
                "HomeScene.xml and unobserved above; the signal can only die")

# R4/R5/R6 - cross-check the two halves of the requestClose contract: the
# OBSERVER side (a parent's ObserveField must name a handler that actually
# exists in the observing component) and the SIGNAL side (a scene observed
# for requestClose must somewhere fire it), plus the mid-dispatch unobserve
# race the round-1 review caught in LibraryScene's Teardown.
OBSERVE_RE = re.compile(r'\.ObserveField\(\s*"requestClose"\s*,\s*"([^"]+)"')
CREATE_RE = re.compile(r'^\s*(\w+)\s*=\s*CreateObject\(\s*"roSGNode"\s*,\s*"(\w+)"')
PUSH_RE = re.compile(r'\w+\s*=\s*PushScreen\(\s*"(\w+)"')


def strip_comment_lines(text):
    """Drop full-line ' comments so contract prose cannot masquerade as code."""
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


observed_children = set()
for path in sorted(glob.glob(os.path.join(repo, "components", "*.brs"))):
    rel = os.path.relpath(path, repo)
    src = open(path, encoding="utf-8").read()
    code = strip_comment_lines(src)

    # R4: every requestClose observer must name a handler the observing
    # component defines (locally, or in a script its own XML attaches).
    for hm in OBSERVE_RE.finditer(code):
        handler = hm.group(1)
        local_def = re.search(r"^\s*(?:sub|function)\s+" + handler + r"\b",
                              code, re.MULTILINE)
        resolved = bool(local_def)
        xml = path[:-4] + ".xml"
        if not resolved and os.path.exists(xml):
            xml_src = open(xml, encoding="utf-8").read()
            for uri in re.findall(r'uri="pkg:/([^"]+\.brs)"', xml_src):
                cand = os.path.join(repo, uri)
                if os.path.exists(cand) and re.search(
                        r"^\s*(?:sub|function)\s+" + handler + r"\b",
                        strip_comment_lines(
                            open(cand, encoding="utf-8").read()),
                        re.MULTILINE):
                    resolved = True
                    break
        if not resolved:
            problems.append(
                f"  {rel} - CHECK27 R4: observes requestClose with handler "
                f"\"{handler}\" that the component never defines; the "
                "observer-half of the close contract cannot run")

    # R5 (collection half): literal create+observe trios and PushScreen
    # call sites mark the child type as contract-bound.
    lines = src.splitlines()
    for i, line in enumerate(lines):
        cm = CREATE_RE.match(line)
        if not cm:
            continue
        var, typ = cm.group(1), cm.group(2)
        window = "\n".join(lines[i + 1:i + 7])
        if re.search(re.escape(var) + r'\.ObserveField\(\s*"requestClose"',
                     window):
            observed_children.add(typ)
    for pm in PUSH_RE.finditer(code):
        observed_children.add(pm.group(1))

    # R6: a Teardown reached from a variant-B self-observe arm fires INSIDE
    # the requestClose dispatch; unobserving the field there can prune the
    # parent's pending removal before it runs.
    td = re.search(r"^sub\s+Teardown\b[^\n]*\n(.*?)^end sub", code,
                   re.MULTILINE | re.DOTALL)
    if td and re.search(r'\.UnObserveField\(\s*"requestClose"\s*\)', td.group(1)):
        problems.append(
            f"  {rel} - CHECK27 R6: Teardown unobserves m.top requestClose; "
            "the self-observe arm calls it mid-dispatch and the parent's "
            "pending RemoveChild can be pruned (C03-r2 race)")

for typ in sorted(observed_children):
    child = os.path.join(repo, "components", typ + ".brs")
    relc = os.path.relpath(child, repo)
    if not os.path.exists(child):
        problems.append(
            f"  {relc} - CHECK27 R5: observed child scene has no script file")
        continue
    if not re.search(r"requestClose\s*=\s*true",
                     strip_comment_lines(
                         open(child, encoding="utf-8").read())):
        problems.append(
            f"  {relc} - CHECK27 R5: an observer is registered for this "
            "scene's requestClose but the scene never writes requestClose = "
            "true; its Back can never be closed by the parent (For You "
            "soft-lock class, C03-r2)")

if problems:
    for p in problems:
        print(p)
    print(f"  CHECK27: {len(problems)} back-navigation contract problem(s)")
    sys.exit(1)

print(f"  CHECK27: all {scanned} parent OnChildRequestClose handlers remove "
      "the requesting child locally and never bubble; HomeScene never writes "
      "an undeclared requestClose; every requestClose observer resolves, "
      f"all {len(observed_children)} observed child scenes fire the signal, "
      "and no Teardown unobserves it mid-dispatch")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 28: player control surface is actually shown (C20) ==="
# Control-surface law (C20, 2026-10-29, review roku__gameux C1): the era
# PlayerScene declared the scrub/PiP/Chapters/Sleep overlay but its ONLY
# show-path was ExitPipMode - reachable only via a button inside the never-
# shown overlay (closed dead loop: overlay never visible -> buttons never
# focusable -> buttonSelected never fires). The fix binds OK to
# ShowControls(true), reveals on "paused", passively reveals at first
# "playing"/info/Preparing hints, dismisses Back before the scene exits,
# lets the open surface own the d-pad (bubble for spatial focus search), and
# wires the three centre transport buttons. This check fails loud if that
# wiring silently regresses back to an unreachable surface.
#   R1  the toggle drives the overlay id the XML declares hidden by default
#   R2  OnKeyEvent has a "OK" branch that shows the surface
#   R3  the "paused" state arm shows the surface
#   R4  the "back" branch dismisses the surface BEFORE OnBackPressed
#   R5  while the surface is visible the d-pad bubbles (return false) so
#       spatial focus search can move between its controls
#   R6  rewindButton/playPauseButton/forwardButton each have a defined
#       buttonSelected observer AND a paired ClosePlayer unobserve
#   R7  hiding restores Video focus (focus never parks on invisible buttons)
#   R8  ShowControls(true) has at least 3 call sites (era had exactly 1)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
brs_path = os.path.join(repo, "components", "PlayerScene.brs")
xml_path = os.path.join(repo, "components", "PlayerScene.xml")
problems = []


def line_of(src, idx):
    return src.count("\n", 0, idx) + 1


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def body(src, kind, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def slice_between(src, start_pat, stop_pat):
    m = re.search(start_pat, src)
    if not m:
        return None
    stop = re.search(stop_pat, src[m.end():])
    end = m.end() + (stop.start() if stop else len(src))
    return src[m.end():end]


brs = open(brs_path, encoding="utf-8").read()
code = strip_comment_lines(brs)
xml = open(xml_path, encoding="utf-8").read()

# R1: XML declares the overlay hidden; the toggle writes its .visible.
if 'id="controlsOverlay"' not in xml:
    problems.append("PlayerScene.xml: XML declares no controlsOverlay node")
elif 'visible="false"' not in xml.split('id="controlsOverlay"')[0].splitlines()[-1] + \
        xml.split('id="controlsOverlay"')[1].splitlines()[0]:
    problems.append("PlayerScene.xml: controlsOverlay must ship visible=\"false\" "
                    "(chrome before play)")
sc_body = body(brs, "sub", "ShowControls")
if sc_body is None:
    problems.append("PlayerScene.brs: ShowControls sub not found")
elif "m.controlsOverlay.visible = shouldShow" not in sc_body:
    problems.append("PlayerScene.brs:%d — CHECK28 R1: ShowControls no longer "
                    "toggles the overlay id wired in the XML"
                    % line_of(brs, brs.find("sub ShowControls")))

# R2: OK key shows the surface.
ok_branch = slice_between(code, r'if key = "OK" then', r'else if|end if')
if ok_branch is None or "ShowControls(true" not in ok_branch:
    problems.append("PlayerScene.brs:%d — CHECK28 R2: no \"OK\" key branch "
                    "showing the control surface (era dead-key regression)"
                    % line_of(code, code.find('if key = "OK" then')
                              if code.find('if key = "OK" then') >= 0 else 0))

# R3: paused state reveals the surface.
paused_arm = slice_between(code, r'else if state = "paused" then', r'else if|end if')
if paused_arm is None or "ShowControls(true" not in paused_arm:
    problems.append("PlayerScene.brs:%d — CHECK28 R3: the \"paused\" state arm "
                    "does not reveal the control surface (zero-feedback era bug)"
                    % line_of(code, code.find('state = "paused"')
                              if code.find('state = "paused"') >= 0 else 0))

# R4: back dismisses the surface before leaving the scene.
back_branch = slice_between(code, r'else if key = "back" then', r'else if|end if')
if (back_branch is None or "ShowControls(false" not in back_branch
        or "OnBackPressed" not in back_branch
        or back_branch.find("ShowControls(false") > back_branch.find("OnBackPressed")):
    problems.append("PlayerScene.brs: CHECK28 R4: the scene \"back\" branch must "
                    "dismiss the open control surface BEFORE OnBackPressed")

# R5: open surface owns the d-pad via bubble-to-spatial-search.
if not re.search(r'if key = "up" or key = "down" or key = "left" or key = "right" then\s*\n\s*return false',
                 code):
    problems.append("PlayerScene.brs: CHECK28 R5: no directional-key bubble while "
                    "the overlay is visible - its buttons are unreachable by focus "
                    "search (up/down would keep opening panels instead)")

# R6: centre transport buttons wired + unobserved (visible dead-button class).
for btn in ("rewindButton", "playPauseButton", "forwardButton"):
    om = re.search(r"m\." + btn + r'\.ObserveField\("buttonSelected", "(\w+)"\)', code)
    if om is None:
        problems.append("PlayerScene.brs: CHECK28 R6: %s has no buttonSelected "
                        "observer (overlay would show a dead focused button)" % btn)
        continue
    if body(brs, "sub", om.group(1)) is None:
        problems.append("PlayerScene.brs: CHECK28 R6: %s observer handler %s is not "
                        "defined" % (btn, om.group(1)))
    if not re.search(r"m\." + btn + r"\.UnObserveField\(\"buttonSelected\"\)", code):
        problems.append("PlayerScene.brs: CHECK28 R6: %s observer has no paired "
                        "ClosePlayer unobserve" % btn)

# R7: hiding hands focus back to the Video node.
if sc_body is not None and "m.videoPlayer.SetFocus(true)" not in sc_body:
    problems.append("PlayerScene.brs: CHECK28 R7: ShowControls(false) never "
                    "restores Video focus - focus parks on invisible buttons")

# R8: multiple live show call sites (era had exactly one, inside PiP).
call_sites = len(re.findall(r"ShowControls\(true", code))
if call_sites < 3:
    problems.append("PlayerScene.brs: CHECK28 R8: only %d ShowControls(true) call "
                    "site(s); the control surface is one PiP dead-loop away from "
                    "the era's never-shown state" % call_sites)

if problems:
    for p in problems:
        print("  " + p)
    print(f"  CHECK28: {len(problems)} player control-surface problem(s)")
    sys.exit(1)

print("  CHECK28: control surface shows on OK/pause/first-play, Back dismisses it "
      "before exiting, d-pad navigates its controls, transport buttons wired with "
      "paired unobserves, and Video focus is restored on hide")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 29: home header focus chain reaches Settings (C21) ==="
# Focus-chain law (C21, 2026-10-29, review roku__gameux C2): HomeScene's
# hand-rolled left/right header walk must visit EVERY header button declared
# in the XML header row (the Button nodes at y=36 since the MN-9 safe-area cure
# moved the row down from y=20; the law itself is coordinate-agnostic), in x-order so the
# Settings entry — and the SettingsScene behind it (logout, caption mode,
# server switch, playback prefs) — is reachable with the remote d-pad alone.
# The era chain skipped settingsButton entirely: Right stepped collections->
# admin (isAdmin) and Left stepped admin->collections; every header transition
# returned handled=true, so Roku's spatial-search fallback never fired and
# Settings was HARD unreachable for admins (and desynced m.headerCol for
# non-admins that fell through to it). Rules:
#   R1  header candidates parsed from HomeScene.xml y=36 Buttons, ordered by x;
#       settingsButton is one of them; adminButton ships visible="false"
#   R2  the Right walk's edges equal the consecutive x-order pairs
#   R3  the Left walk's edges are that chain's exact inverse
#   R4  every edge focuses the node its destination column names, and the
#       step into admin is gated on m.isAdmin (hidden-button law)
#   R5  FocusHeaderZone() can restore focus to every header column (incl.
#       settings) so a grid->header return never desyncs the chain
#   R6  settingsButton's buttonSelected observer is defined and opens
#       SettingsScene (reachability wired to a live destination)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
brs_path = os.path.join(repo, "components", "HomeScene.brs")
xml_path = os.path.join(repo, "components", "HomeScene.xml")
problems = []


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def slice_between(src, start_pat, stop_pat):
    m = re.search(start_pat, src)
    if not m:
        return None
    stop = re.search(stop_pat, src[m.end():])
    end = m.end() + (stop.start() if stop else len(src))
    return src[m.end():end]


brs = open(brs_path, encoding="utf-8").read()
code = strip_comment_lines(brs)
xml = open(xml_path, encoding="utf-8").read()

# R1: header candidates are the Button nodes riding the y=36 row (MN-9 era);
# the remote's
# natural horizontal order is their x order.
head = []
for m in re.finditer(r'<Button[^>]*?translation="\[(\d+),36\]"[^>]*?id="(\w+)"', xml):
    head.append((int(m.group(1)), m.group(2)))
head.sort()
cols = [nid[:-len("Button")] for _, nid in head]
if "settings" not in cols:
    problems.append('HomeScene.xml: CHECK29 R1: header row (y=36 Buttons) has no '
                    'settingsButton; candidates parsed: %s' % cols)
admin_tag = re.search(r'<Button[^>]*?id="adminButton"[^>]*/?>', xml)
if admin_tag is not None and 'visible="false"' not in admin_tag.group(0):
    problems.append('HomeScene.xml: CHECK29 R1: adminButton must ship '
                    'visible="false" (the isAdmin gate only hides the step)')

EDGE = re.compile(
    r'm\.headerCol = "(\w+)"[^\n]*\n\s*m\.(\w+)\.SetFocus\(true\)\s*\n\s*m\.headerCol = "(\w+)"')


def walk(s, label):
    out = []
    for src_col, btn, dst_col in EDGE.findall(s):
        if btn != dst_col + "Button":
            problems.append("HomeScene.brs: CHECK29 R4: %s edge %s->%s focuses %s "
                            "(destination column says %sButton)"
                            % (label, src_col, dst_col, btn, dst_col))
        out.append((src_col, dst_col))
    return out


RIGHT = slice_between(code, r'if key = "right" and m\.currentRail = "search" then',
                      r'else if key = "down"')
LEFT = slice_between(code, r'if key = "left" and m\.currentRail = "search" then',
                     r'else if key = "right"')
if RIGHT is None or LEFT is None:
    problems.append("HomeScene.brs: CHECK29: OnKeyEvent header branches not found "
                    "(structure drift; the walk can no longer be verified)")

expected_right = list(zip(cols, cols[1:]))
if RIGHT is not None:
    got = walk(RIGHT, "right")
    if got != expected_right:
        problems.append("HomeScene.brs: CHECK29 R2: Right header walk is %s; the "
                        "XML x-order demands %s - a skipped candidate is only "
                        "reachable by spatial fallback, which handled=true "
                        "disables" % (got, expected_right))
    # R4: the step into admin must be gated (button ships hidden).
    adm = re.search(r'm\.headerCol = "\w+"[^\n]*\n\s*m\.adminButton\.SetFocus\(true\)'
                    r'\s*\n\s*m\.headerCol = "admin"', RIGHT)
    if adm is not None and "m.isAdmin" not in adm.group(0):
        problems.append("HomeScene.brs: CHECK29 R4: the right step into admin is not "
                        "gated on m.isAdmin - focus can land on a hidden button")
if LEFT is not None:
    got = walk(LEFT, "left")
    expected_left = [(b, a) for a, b in reversed(expected_right)]
    if got != expected_left:
        problems.append("HomeScene.brs: CHECK29 R3: Left header walk is %s; expected "
                        "the exact inverse of the x-order, %s" % (got, expected_left))

# R5: FocusHeaderZone must be able to restore every column's focus.
fhz = body(brs, "FocusHeaderZone")
if fhz is None:
    problems.append("HomeScene.brs: CHECK29 R5: FocusHeaderZone() not found")
else:
    for col in cols:
        if col == "search":
            continue  # search is the default fallback arm of the restore chain
        # The hidden-by-default entries may additionally require their own
        # .visible (the post-demotion restore guard; the family is {admin, tv}
        # since MN-3 - CHECK32 R1 pins admin's gate exists, CHECK93 R2 pins
        # tv's does. A future hidden entry joins the family in the same commit
        # that adds its restore arm.)
        guard = (r'( and m\.' + col + r'Button\.visible)?'
                 if col in ("admin", "tv") else r'')
        pat = (r'm\.headerCol = "' + col + r'" and m\.' + col +
               r'Button <> invalid' + guard + r' then\s*\n\s*m\.' + col + r'Button\.SetFocus\(true\)')
        if re.search(pat, fhz) is None:
            problems.append("HomeScene.brs: CHECK29 R5: FocusHeaderZone cannot "
                            "restore focus to '%s' - a grid->header return would "
                            "desync m.headerCol from the visual focus" % col)

# R6: the Settings button's destination must be live, not a dead observer.
if 'm.settingsButton.ObserveField("buttonSelected", "OnSettingsPressed")' not in code:
    problems.append('HomeScene.brs: CHECK29 R6: settingsButton has no '
                    'buttonSelected observer (a focused dead button)')
osp = body(brs, "OnSettingsPressed")
if osp is None or 'CreateObject("roSGNode", "SettingsScene")' not in osp:
    problems.append("HomeScene.brs: CHECK29 R6: OnSettingsPressed does not open "
                    "SettingsScene (reachability wired to nothing)")

if problems:
    for p in problems:
        print("  " + p)
    print(f"  CHECK29: {len(problems)} header focus-chain problem(s)")
    sys.exit(1)

print("  CHECK29: header walk reaches every x-ordered button (Settings included) in "
      "both directions, the admin step is isAdmin-gated, FocusHeaderZone restores "
      "every column, and Settings opens SettingsScene")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 30: README/package.json endpoint + URL truth (C33) ==="
# Document-truth law (C33, 2026-10-29, review roku__writer C1+C2+C3): the
# README "API Endpoints" table is a contract claim. The Emby-era fiction rows
# that survived the F0b sweep (Auth/Login, Sessions, Library/VirtualFolders,
# Items, Sessions/Play, Playstate, Users/Me) document routes the product does
# not have — absent from the vendored server-route manifest AND from every
# client call site. The manual-deploy recipe zipped four trees and forgot
# locale/ (docs/i18n.md: a channel without catalogs renders raw keys), and
# the install/support/package.json URLs pointed at nonexistent homes
# (github.com/your-org/phlix-roku and phlix-media both 404).
#   R1  era-fiction ban: no backticked fabricated route reappears in README
#       (a prose mention outside backticks stays legal; a table row does not)
#   R2  table truth: every backticked /api/v1 path on an "API Endpoints"
#       table row resolves in tests/fixtures/server-route-manifest.json OR
#       in the pinned hub-mode allow set (phlix-hub registers exactly these
#       two; verified read-only against phlix-hub src/Application.php)
#   R3  repo identity: README + package.json know exactly one live home,
#       github.com/detain/phlix-roku-client
#   R4  manual recipe: the hand-run zip line ships ALL FIVE required trees
#       (manifest source components images locale — same set `make package`
#       zips and scripts/verify-package.sh asserts per tree)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
problems = []


def line_of(src, idx):
    return src.count("\n", 0, idx) + 1


with open(os.path.join(repo, "README.md"), encoding="utf-8") as fh:
    readme = fh.read()
with open(os.path.join(repo, "package.json"), encoding="utf-8") as fh:
    pkg = fh.read()
with open(
    os.path.join(repo, "tests/fixtures/server-route-manifest.json"), encoding="utf-8"
) as fh:
    manifest = json.load(fh)
server_paths = {t[1] for t in manifest["routes"]}

# R1: the exact fabricated Emby-era routes (review roku__writer C1).
FABRICATED = [
    "/api/v1/Auth/Login",
    "/api/v1/Sessions",
    "/api/v1/Sessions/{id}",
    "/api/v1/Library/VirtualFolders",
    "/api/v1/Items",
    "/api/v1/Sessions/Play",
    "/api/v1/Playstate",
    "/api/v1/Playstate/Progress",
    "/api/v1/Users/Me",
]
for fake in FABRICATED:
    needle = "`" + fake + "`"
    idx = readme.find(needle)
    if idx != -1:
        problems.append(
            "README.md:%d - CHECK30 R1: fabricated Emby-era route %s is back "
            "(the server registers no such route)" % (line_of(readme, idx), needle)
        )

# R2: hub-mode routes are registered by phlix-hub, deliberately absent from
# the SERVER manifest; every other documented path must be manifest-verified.
HUB_MODE = {"/api/v1/me/servers", "/api/v1/servers/{serverId}/proxy/{path:.*}"}
lines = readme.splitlines()
try:
    start = next(i for i, ln in enumerate(lines) if ln.strip() == "## API Endpoints")
except StopIteration:
    problems.append(
        "README.md: CHECK30 R2: '## API Endpoints' section vanished — a "
        "docs-truth gate with no table is vacuous; re-point this check deliberately"
    )
    start = None
if start is not None:
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")),
        len(lines),
    )
    for i in range(start, end):
        if not lines[i].lstrip().startswith("|"):
            continue
        for path in re.findall(r"`(/api/v1[^`]*)`", lines[i]):
            if path not in server_paths and path not in HUB_MODE:
                problems.append(
                    "README.md:%d - CHECK30 R2: documented endpoint `%s` "
                    "resolves in neither the vendored server-route manifest "
                    "nor the hub-mode allow set" % (i + 1, path)
                )

# R3: one canonical, live repo home (review roku__writer C3).
for name, src in (("README.md", readme), ("package.json", pkg)):
    for dead in ("your-org/phlix-roku", "phlix-media/phlix-roku-client"):
        idx = src.find(dead)
        if idx != -1:
            problems.append(
                "%s:%d - CHECK30 R3: dead repo URL '%s' — the live home is "
                "github.com/detain/phlix-roku-client" % (name, line_of(src, idx), dead)
            )
block = re.search(r'"repository"\s*:\s*\{[^}]*\}', pkg, re.S)
if block is None:
    problems.append(
        "package.json: CHECK30 R3: no repository block — npm/github identity "
        "metadata dropped (fix deliberately, not silently)"
    )
elif "detain/phlix-roku-client" not in block.group(0):
    problems.append(
        "package.json: CHECK30 R3: repository.url does not name "
        "detain/phlix-roku-client"
    )

# R4: the manual-deploy recipe must ship locale/ (review roku__writer C2).
recipe = [
    ln.strip()
    for ln in lines
    if ln.strip().startswith("zip -r phlix.zip")
]
if not recipe:
    problems.append(
        "README.md: CHECK30 R4: no manual 'zip -r phlix.zip' recipe found — "
        "the gate's subject vanished; re-point this leg deliberately"
    )
REQUIRED_TREES = {"manifest", "source", "components", "images", "locale"}
for ln in recipe:
    words = set(ln.split()) - {"zip", "-r", "phlix.zip"}
    if words != REQUIRED_TREES:
        problems.append(
            "README.md: CHECK30 R4: manual package recipe ships %s — must be "
            "exactly %s (dropping locale/ ships a raw-key-rendering channel)"
            % (sorted(words), sorted(REQUIRED_TREES))
        )

if problems:
    for p in problems:
        print("  " + p)
    print("  CHECK30: %d document-truth problem(s)" % len(problems))
    sys.exit(1)

print(
    "  CHECK30: every API-table route resolves in the server manifest or the "
    "hub-mode pair, zero Emby-era fictions, one live repo home in README + "
    "package.json, manual recipe ships all five trees"
)
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 31: Back at an empty stack exits the channel; never a black dead-screen ==="
# Root-back law (M-ROKU-01, 2026-10-29, review roku__casualgamer M2): when the
# screen stack is empty (user is on a bootstrap scene - Home/Connect/Login/
# ServerPicker are appended, never pushed) PhlixApp.OnKeyEvent used to return
# PopScreen()'s false verbatim. Unconsumed, RSG's native back handling closed
# only the FOCUSED child scene, exposing the root's black boot chrome - a dead
# screen that needed a second Back to actually exit. The cure honors PopScreen's
# documented contract ("false ... signals the caller should exit the channel"):
# PhlixApp raises the exitChannel field, main.brs observes it on the screen
# message port, the wait loop returns, main() ends, the channel exits cleanly.
# There is no creatable roApp.Exit() in SceneGraph (the official component
# library bsc bundles lists only roAppInfo/roAppManager/roAppMemoryMonitor), so
# exit-by-main-return is the platform primitive.
#   R1  components/PhlixApp.xml declares exitChannel as boolean alwaysNotify
#       (without alwaysNotify a second true-write never re-fires the event).
#   R2  PhlixApp.brs OnKeyEvent pairs `handled = PopScreen()` with a
#       `not handled` guard that writes m.top.exitChannel = true AND consumes
#       the key (handled = true). A back arm without the guard reintroduces
#       the black dead-screen (red on the 9ff4a6d parent era).
#   R3  source/main.brs observes exitChannel on a message port and its wait
#       loop exits on the roSGNodeEvent for that field - the signal must
#       actually end main(), not just exist.
#   R4  the loop also exits on roSGScreenEvent isScreenClosed (a main loop
#       that ignores root-screen closure is a zombie-loop vector).
#   R5  no .brs anywhere calls CreateObject("roApp") - the fiction primitive;
#       on-device it returns invalid and the exit silently does nothing.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
problems = []


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# R1: exitChannel declared on the root interface, boolean + alwaysNotify.
xml_path = os.path.join(repo, "components", "PhlixApp.xml")
if os.path.exists(xml_path):
    xml = read(xml_path)
    fld = re.search(
        r"<field\s[^>]*id=\"exitChannel\"[^>]*/?>", xml)
    if not fld:
        problems.append(
            "  components/PhlixApp.xml - CHECK31: exitChannel field is not "
            "declared; the root has no exit signal for Back-at-empty-stack")
    else:
        decl = fld.group(0)
        if 'type="boolean"' not in decl or 'alwaysNotify="true"' not in decl:
            problems.append(
                "  components/PhlixApp.xml - CHECK31: exitChannel must be "
                'type="boolean" alwaysNotify="true"; without alwaysNotify the '
                "exit event can be swallowed on repeat writes")
else:
    problems.append("  components/PhlixApp.xml missing - CHECK31")

# R2: OnKeyEvent consumes back at empty stack via the exitChannel guard.
app_path = os.path.join(repo, "components", "PhlixApp.brs")
if os.path.exists(app_path):
    src = read(app_path)
    fn = re.search(
        r"function\s+OnKeyEvent\b.*?^end function", src,
        re.MULTILINE | re.DOTALL)
    if not fn:
        problems.append(
            "  components/PhlixApp.brs - CHECK31: OnKeyEvent not found")
    else:
        body = fn.group(0)
        if not re.search(r"handled\s*=\s*PopScreen\(\)", body):
            problems.append(
                "  components/PhlixApp.brs - CHECK31: OnKeyEvent no longer "
                "routes back through PopScreen()")
        guard = re.search(
            r"if\s+not\s+handled\s+then(.*?)end\s+if", body,
            re.DOTALL)
        if not guard:
            problems.append(
                "  components/PhlixApp.brs - CHECK31: OnKeyEvent returns "
                "PopScreen()'s false unguarded; unconsumed back at the root "
                "closes only the focused child scene and exposes the black "
                "boot chrome (the M2 dead-screen regression)")
        else:
            g = guard.group(1)
            if not re.search(r"m\.top\.exitChannel\s*=\s*true", g):
                problems.append(
                    "  components/PhlixApp.brs - CHECK31: the not-handled "
                    "guard must raise m.top.exitChannel = true (main.brs "
                    "exits the channel on it)")
            if not re.search(r"handled\s*=\s*true", g):
                problems.append(
                    "  components/PhlixApp.brs - CHECK31: the not-handled "
                    "guard must consume the key (handled = true) so RSG "
                    "never applies native close at the root")
else:
    problems.append("  components/PhlixApp.brs missing - CHECK31")

# R3 + R4: main.brs wires exitChannel into the wait loop and exits on it;
# screen closure must also end main().
main_path = os.path.join(repo, "source", "main.brs")
if os.path.exists(main_path):
    src = read(main_path)
    if not re.search(r"ObserveField\(\s*\"exitChannel\"", src, re.IGNORECASE):
        problems.append(
            "  source/main.brs - CHECK31: exitChannel is not observed on a "
            "message port; raising the field would never end main()")
    if not re.search(
        r"\"roSGNodeEvent\"[\s\S]{0,200}?GetField\(\)\s*=\s*\"exitChannel\""
        r"[\s\S]{0,120}?exit while", src):
        problems.append(
            "  source/main.brs - CHECK31: the wait loop does not exit on the "
            "exitChannel roSGNodeEvent; the exit signal is wired to nothing")
    if not re.search(r"isScreenClosed\(\)[\s\S]{0,120}?exit while", src):
        problems.append(
            "  source/main.brs - CHECK31: the wait loop ignores "
            "roSGScreenEvent/isScreenClosed; a closed root screen must end "
            "main(), not spin the loop")
else:
    problems.append("  source/main.brs missing - CHECK31")

# R5: the roApp fiction primitive stays dead.
for path in sorted(
    glob.glob(os.path.join(repo, "**", "*.brs"), recursive=True)):
    rel = os.path.relpath(path, repo)
    if re.search(r"CreateObject\(\s*\"roApp\"\s*\)", read(path), re.IGNORECASE):
        problems.append(
            "  " + rel + " - CHECK31: CreateObject(\"roApp\") is not a "
            "creatable Roku SceneGraph component (absent from the official "
            "type library); it yields invalid and the exit silently fails - "
            "exit by ending main() via exitChannel instead")

if problems:
    for p in problems:
        print("  " + p)
    print("  CHECK31: %d root-back exit-law problem(s)" % len(problems))
    sys.exit(1)

print(
    "  CHECK31: exitChannel declared alwaysNotify on the root, OnKeyEvent "
    "consumes back-at-empty-stack by raising it, main.brs observes it and ends "
    "the loop (plus isScreenClosed hygiene), and the roApp fiction primitive "
    "appears nowhere - one Back from Home exits cleanly, no black dead-screen")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 32: home rail geometry, demotion-safe restore, and header-doc truth (M-ROKU-02) ==="
# Rail law (M-ROKU-02, 2026-10-29, review roku__casualgamer M3-recheck + M6):
# the Up Next rail shipped as a ghost - upNextLabel sat byte-identically on
# libraryLabel ([40,448]) and upNextGrid ([0,488]+300) stacked inside
# libraryGrid's footprint ([0,484]+200), while the hand-rolled vertical chain
# consumed every up/down with handled=true and had NO upnext arm - an
# unreachable row painted under Libraries (later-siblings-win z-order hid it,
# so users saw only clutter when a parallel load made it visible). Cure: the
# two rails SHARE the single Continue Watching slot (720p hosts exactly one
# row above Libraries), the exclusion is enforced by BOTH response handlers,
# and search/library gain upnext arms so the rail is enterable. Rules:
#   R1  FocusHeaderZone's admin restore is visibility-gated (post-demotion:
#       OnMeResponse hides adminButton on a failed/non-admin getMe; restoring
#       focus onto a hidden node strands the header zone in the void)
#   R2  rail geometry: upNextLabel/upNextGrid translations EQUAL the continue
#       pair's (shared slot by design) and neither rail's rect vertically
#       intersects the Libraries row's rect (the ghost bug, forbidden)
#   R3  both loaders enforce the exclusion: OnUpNextResponse bails while
#       ContinueRailVisible() (before any visible=true), and
#       OnContinueWatchingResponse retracts upNext before claiming the slot
#   R4  the vertical chain enters the upnext rail from search (down) and from
#       library (up) and leaves it (down->library, up->header) - reachability
#       both directions, mirroring the CHECK29 header-walk law
#   R5  README "Home Header Navigation" matches the XML header row: the
#       button count word and the x-order chain line are derived from the
#       Button titles the scene actually declares (the manual still described
#       the pre-For-You four-button header and omitted Settings)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
brs_path = os.path.join(repo, "components", "HomeScene.brs")
xml_path = os.path.join(repo, "components", "HomeScene.xml")
readme_path = os.path.join(repo, "README.md")
problems = []


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def slice_between(src, start_pat, stop_pat):
    m = re.search(start_pat, src)
    if not m:
        return None
    stop = re.search(stop_pat, src[m.end():])
    end = m.end() + (stop.start() if stop else len(src))
    return src[m.end():end]


def rect_of(nid):
    # Rail opening tags carry height/width/translation before id (house style);
    # scan the tag that names the id and pull the geometry out of it.
    for m in re.finditer(r'<(Label|PosterGrid)\b[^>]*>', xml):
        if ('id="%s"' % nid) in m.group(0):
            tr = re.search(r'translation="\[(-?\d+),(-?\d+)\]"', m.group(0))
            ht = re.search(r'height="(\d+)"', m.group(0))
            if tr is None or ht is None:
                return None
            return (int(tr.group(1)), int(tr.group(2)), int(ht.group(1)))
    return None


def voverlap(a, b):
    return a[1] < b[1] + b[2] and b[1] < a[1] + a[2]


brs = open(brs_path, encoding="utf-8").read()
code = strip_comment_lines(brs)
xml = open(xml_path, encoding="utf-8").read()
readme = open(readme_path, encoding="utf-8").read()

# R1: post-demotion restore guard.
fhz = body(code, "FocusHeaderZone")
if fhz is None:
    problems.append("HomeScene.brs: CHECK32 R1: FocusHeaderZone() not found")
elif re.search(r'm\.headerCol = "admin" and m\.adminButton <> invalid and m\.adminButton\.visible then', fhz) is None:
    problems.append("HomeScene.brs: CHECK32 R1: FocusHeaderZone restores focus to "
                    "adminButton without a .visible gate - after a demotion hides "
                    "the button, a grid->header return strands focus on a hidden node")

# R2: rail geometry.
want = {}
for nid in ("continueLabel", "continueGrid", "upNextLabel", "upNextGrid",
            "libraryLabel", "libraryGrid"):
    r = rect_of(nid)
    if r is None:
        problems.append("HomeScene.xml: CHECK32 R2: %s not found or missing "
                        "translation/height" % nid)
    want[nid] = r
if all(v is not None for v in want.values()):
    if want["upNextLabel"][:2] != want["continueLabel"][:2]:
        problems.append("HomeScene.xml: CHECK32 R2: upNextLabel at %s shares no "
                        "slot with continueLabel %s - the one-row budget above "
                        "Libraries is gone; re-plan, do not re-stack"
                        % (want["upNextLabel"][:2], want["continueLabel"][:2]))
    if want["upNextGrid"][:2] != want["continueGrid"][:2]:
        problems.append("HomeScene.xml: CHECK32 R2: upNextGrid at %s must ride "
                        "the continueGrid slot %s (shared top-rail slot)"
                        % (want["upNextGrid"][:2], want["continueGrid"][:2]))
    for g in ("upNextLabel", "upNextGrid"):
        for l in ("libraryLabel", "libraryGrid"):
            if voverlap(want[g], want[l]):
                problems.append("HomeScene.xml: CHECK32 R2: %s rect %s vertically "
                                "intersects %s rect %s - the Up Next ghost-rail "
                                "stack is back (invisible-label-under-Libraries / "
                                "grid-over-grid)" % (g, want[g], l, want[l]))

# R3: both loaders enforce the exclusion.
crv = body(code, "ContinueRailVisible")
if crv is None or "m.continueGrid.visible" not in crv:
    problems.append("HomeScene.brs: CHECK32 R3: ContinueRailVisible() missing or "
                    "not reading continueGrid.visible")
unr = body(code, "OnUpNextResponse")
if unr is None:
    problems.append("HomeScene.brs: CHECK32 R3: OnUpNextResponse not found")
else:
    bail = unr.find("if ContinueRailVisible() then return")
    show = unr.find("m.upNextGrid.visible = true")
    if bail == -1 or show == -1 or bail > show:
        problems.append("HomeScene.brs: CHECK32 R3: OnUpNextResponse renders the "
                        "rail without bailing while ContinueRailVisible() - a "
                        "second visible rail cannot fit above Libraries")
cwr = body(code, "OnContinueWatchingResponse")
if cwr is None:
    problems.append("HomeScene.brs: CHECK32 R3: OnContinueWatchingResponse not found")
else:
    retract = cwr.find("m.upNextGrid.visible = false")
    claim = cwr.find("m.continueGrid.visible = true")
    if retract == -1 or claim == -1 or retract > claim:
        problems.append("HomeScene.brs: CHECK32 R3: OnContinueWatchingResponse "
                        "claims the shared slot without retracting the upNext "
                        "rail (parallel loads race; both orders must end with "
                        "at most one visible)")

# R4: vertical chain reaches upnext both directions.
DOWN = slice_between(code, r'if key = "down" then', r'else if key = "up"')
UP = slice_between(code, r'if key = "up" then', r'return handled')
if DOWN is None or UP is None:
    problems.append("HomeScene.brs: CHECK32 R4: OnKeyEvent down/up branches not "
                    "found (structure drift; the rail chain can no longer be verified)")
ENTRY = re.compile(r'else if m\.upNextGrid <> invalid and m\.upNextGrid\.visible then\s*\n\s*m\.upNextGrid\.SetFocus\(true\)\s*\n\s*m\.currentRail = "upnext"')
if DOWN is not None:
    if ENTRY.search(DOWN) is None:
        problems.append("HomeScene.brs: CHECK32 R4: Down from the header never "
                        "enters the upnext rail (ghost row: visible, unfocusable)")
    if re.search(r'else if m\.currentRail = "upnext" then\s*\n\s*m\.libraryGrid\.SetFocus\(true\)\s*\n\s*m\.currentRail = "library"', DOWN) is None:
        problems.append("HomeScene.brs: CHECK32 R4: no Down exit from the upnext "
                        "rail to the library grid")
if UP is not None:
    if ENTRY.search(UP) is None:
        problems.append("HomeScene.brs: CHECK32 R4: Up from the library grid never "
                        "enters the upnext rail")
    if re.search(r'else if m\.currentRail = "upnext" then\s*\n\s*FocusHeaderZone\(\)', UP) is None:
        problems.append("HomeScene.brs: CHECK32 R4: no Up exit from the upnext "
                        "rail back to the header zone")

# R5: README header prose derives from the XML it documents.
head = []
for m in re.finditer(r'<Button[^>]*?translation="\[(\d+),20\]"[^>]*?text="([^"]*)"', xml):
    head.append((int(m.group(1)), m.group(2)))
head.sort()
titles = [t for _, t in head]
sec = re.search(r'### Home Header Navigation(.*?)(?=\n### |\Z)', readme, re.DOTALL)
if sec is None:
    problems.append("README.md: CHECK32 R5: 'Home Header Navigation' section not found")
elif titles:
    body_txt = sec.group(1)
    expected = "`" + " ↔ ".join(titles) + "`"
    if expected not in body_txt:
        problems.append("README.md: CHECK32 R5: header chain line is not %s - "
                        "the manual must walk the real x-ordered button titles "
                        "the XML declares" % expected)
    words = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven"}
    word = words.get(len(titles))
    if word is None:
        problems.append("CHECK32 R5: header now has %d buttons - extend the "
                        "count-word table (the prose claim cannot be verified)" % len(titles))
    elif ("up to %s buttons" % word) not in body_txt:
        problems.append("README.md: CHECK32 R5: the section claims a button "
                        "count other than 'up to %s buttons' while the XML "
                        "header row declares %d buttons" % (word, len(titles)))

if problems:
    for p in problems:
        print("  " + p)
    print("  CHECK32: %d rail-law problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK32: admin restore is visibility-gated, Up Next shares Continue's "
      "single slot (never Libraries), both loaders enforce the exclusion, the "
      "vertical chain walks the upnext rail both directions, and the README "
      "header prose equals the XML button walk")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 33: logout keeps its promise - surgical wipe, real login surface, credential-carrying teardown (M-ROKU-03) ==="
# Logout law (M-ROKU-03, 2026-10-29, review roku__casualgamer M4): the README
# promises logging out "keeps server_url, so you return to the login screen on
# the same hub/server". R1.6's ResetCachedStorage(true) called
# registry.DeleteAll() - wiping server_url too - so the next login POSTed to
# an empty base; the transport failure surfaced as "Cannot connect to server.
# Check your network" and logout dead-ended the app on a fake network error.
# Two collateral bugs on the same path: the logout ApiTask was appended AFTER
# ShowLogin (breaking the last-child=scene transition idiom the
# OnConnected/OnLoginSuccess/OnHubDetected handlers pop), and the server-side
# DELETE /sessions/{id} re-read session_id from the already-wiped registry,
# so teardown was a silent no-op since it shipped. Rules:
#   R1  ResetCachedStorage(fullReset) deletes EXACTLY the six auth/session
#       keys via registry.Delete - no DeleteAll, no server_url casualty
#   R2  OnLogout captures auth_token/session_id and resolves the MEDIA
#       teardown base (GetMediaBaseUrl) BEFORE the wipe — hub sessions are
#       SERVER rows reached through the relay, not hub rows — and carries
#       them on the logoutTask request
#   R3  OnLogout appends logoutTask BEFORE ShowLogin (scene stays last child)
#   R4  ShowLogin guards IsServerConnected and routes unconfigured states to
#       ConnectScene (AppContext law) instead of an empty-base login
#   R5  the ApiTask logout branch reads credentials from the REQUEST, never
#       from the wiped registry, and keeps result.ok = true
#   R6  the README promise sentence stays in place (if the law ever changes,
#       the manual must be re-derived in the same commit, not silently)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO", ".")
problems = []


def read(*parts):
    return open(os.path.join(repo, *parts), encoding="utf-8").read()


def body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


SIX_KEYS = {"auth_token", "refresh_token", "session_id",
            "connection_kind", "active_server_id", "active_server_name"}

# R1: surgical wipe in ResetCachedStorage.
rs = body(read("source", "lib", "Storage.brs"), "ResetCachedStorage")
if rs is None:
    problems.append("Storage.brs: CHECK33 R1: ResetCachedStorage() not found")
else:
    code = strip_comments(rs)
    if "DeleteAll" in code:
        problems.append("Storage.brs: CHECK33 R1: ResetCachedStorage still calls "
                        "registry.DeleteAll() - the nuke erases server_url and "
                        "turns logout into a dead-end login on an empty base")
    wiped = set(re.findall(r'registry\.Delete\("([^"]+)"\)', code))
    if wiped != SIX_KEYS:
        problems.append("Storage.brs: CHECK33 R1: fullReset wipe set is %s; "
                        "logout must delete exactly the six auth/session keys "
                        "%s (server_url and device convenience state survive)"
                        % (sorted(wiped), sorted(SIX_KEYS)))

# R2 + R3: OnLogout capture-before-wipe, task-before-scene.
app = body(read("components", "PhlixApp.brs"), "OnLogout")
if app is None:
    problems.append("PhlixApp.brs: CHECK33 R2: OnLogout() not found")
else:
    ol = strip_comments(app)
    i_wipe = ol.find("ResetCachedStorage(true)")
    if i_wipe == -1:
        problems.append("PhlixApp.brs: CHECK33 R2: OnLogout no longer calls "
                        "ResetCachedStorage(true)")
    for needle, what in (('GetStorage().get("auth_token")', "auth_token"),
                         ('GetStorage().get("session_id")', "session_id")):
        i = ol.find(needle)
        if i == -1 or (i_wipe != -1 and i > i_wipe):
            problems.append("PhlixApp.brs: CHECK33 R2: OnLogout must capture %s "
                            "BEFORE ResetCachedStorage(true); afterwards the "
                            "registry is wiped and teardown runs blind" % what)
    i_base = ol.find("GetMediaBaseUrl()")
    if i_base == -1 or (i_wipe != -1 and i_base > i_wipe):
        problems.append("PhlixApp.brs: CHECK33 R2: OnLogout must resolve the "
                        "teardown base via GetMediaBaseUrl() BEFORE "
                        "ResetCachedStorage(true) - the session is a SERVER "
                        "row reached through the media space (direct: the "
                        "byte-identical bare server url; hub: the per-server "
                        "relay, which the hub re-anchors at the server's "
                        "/api/v1/sessions - the hub itself has no such "
                        "route and issues no session_id at login). After the "
                        "wipe, connection_kind and active_server_id are gone "
                        "and the resolver degrades to the bare hub url")
    if "IsServerConnected()" not in ol:
        problems.append("PhlixApp.brs: CHECK33 R2: the teardown base must "
                        "stay guarded by IsServerConnected() (AppContext "
                        "law: never resolve a url unchecked)")
    req = re.search(r"logoutTask\.request = \{([^\n]*)\}", ol)
    if req is None or not all(k in req.group(1)
                              for k in ("base_url", "auth_token", "session_id")):
        problems.append("PhlixApp.brs: CHECK33 R2: logoutTask.request must carry "
                        "base_url + auth_token + session_id to the task")
    i_task = ol.find("m.top.Append(logoutTask)")
    i_login = ol.find("ShowLogin()")
    if i_task == -1 or i_login == -1 or i_task > i_login:
        problems.append("PhlixApp.brs: CHECK33 R3: logoutTask must be appended "
                        "BEFORE ShowLogin - the scene transitions pop the LAST "
                        "child, and a task appended after the scene hijacks "
                        "that removal")

# R4: ShowLogin routes unconfigured servers to Connect, never an empty base.
sl_raw = body(read("components", "PhlixApp.brs"), "ShowLogin")
if sl_raw is None:
    problems.append("PhlixApp.brs: CHECK33 R4: ShowLogin() not found")
else:
    sl = strip_comments(sl_raw)
    guard = sl.find("if not IsServerConnected() then")
    dial = sl.find('CreateObject("roSGNode", "LoginScene")')
    if guard == -1 or dial == -1 or guard > dial:
        problems.append("PhlixApp.brs: CHECK33 R4: ShowLogin builds LoginScene "
                        "without an IsServerConnected guard - a login on an "
                        "empty base misattributes as a fake network error")
    elif "ShowConnect()" not in sl[guard:dial]:
        problems.append("PhlixApp.brs: CHECK33 R4: ShowLogin's connectivity "
                        "guard does not route to ShowConnect()")

# R5: the ApiTask logout branch consumes the request, not the wiped registry.
task = read("components", "ApiTask.brs")
mb = re.search(r'else if req\.op = "logout" then(.*?)\n        end if', task, re.DOTALL)
if mb is None:
    problems.append("ApiTask.brs: CHECK33 R5: logout branch not found")
else:
    br = mb.group(1)
    if "GetStorage().get(" in br:
        problems.append("ApiTask.brs: CHECK33 R5: the logout branch reads the "
                        "registry - OnLogout has already wiped it, so the "
                        "teardown silently no-ops")
    if not all(k in br for k in ("req.base_url", "req.session_id", "req.auth_token")):
        problems.append("ApiTask.brs: CHECK33 R5: the logout branch must read "
                        "base_url, session_id and auth_token from the request")
    if "logoutApi.token =" not in br:
        problems.append("ApiTask.brs: CHECK33 R5: the teardown request must "
                        "ride the Bearer token (direct .token assignment, not "
                        "setToken which re-persists into the cleared registry)")
    if "result.ok = true" not in br:
        problems.append("ApiTask.brs: CHECK33 R5: logout must keep returning "
                        "ok regardless of server reachability (local logout "
                        "is already complete)")

# R6: the README promise stays pinned next to the law that keeps it true.
readme = read("README.md")
if "Logging out clears `connection_kind`" not in readme \
        or re.search(r"but keeps `server_url`, so you return to the\s+login screen on the same hub/server", readme) is None:
    problems.append("README.md: CHECK33 R6: the logout promise sentence "
                    "(clears the three hub keys, keeps server_url) was "
                    "reworded or dropped - re-derive it and CHECK33 together")

if problems:
    for p in problems:
        print("  " + p)
    print("  CHECK33: %d logout-contract problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK33: the logout wipe is surgical (six keys, no DeleteAll), the "
      "teardown captures its credentials and resolves the relay-capable "
      "media base before the wipe and rides the request, the task precedes "
      "the scene, ShowLogin never dangles on an empty base, "
      "and the README promise is pinned in place")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 34: transport-failure buckets keep the honest-taxonomy triangle (M-ROKU-04) ==="
# BUCKET LAW (M-ROKU-04, review roku__casualgamer M5): the day-1 connect path
# once collapsed every cause into a guessed "connect"/"timeout" label and
# PhlixApp misread "never logged in" as "Unable to reach server. Please check
# your network." The cure is a closed set of reason buckets with a triangle
# pin - one classifier, one literal Translate ladder, one catalog message per
# bucket - because an unclosed taxonomy silently re-opens the misattribution
# class (a new bucket with no message renders the raw key; a message with no
# bucket is dead copy; a bucket nobody translates dies to the generic label).
# Rules:
#   R1  ClassifyUrlFailure exists in Utilities.brs and returns EXACTLY the
#       pinned bucket set (drift in either direction is red - a new bucket
#       must arrive WITH its message, in the same commit)
#   R2  TranslateTransportReason is the single ladder; every bucket has a
#       literal Translate("connect_err_<bucket>") arm (no dynamic key
#       building - CHECK20's anti-typo guarantee stays total)
#   R3  IsTransportReason recognizes every bucket (the boot router's guard)
#   R4  locale/en_US/strings.json carries a non-empty connect.err_<bucket>
#       value for every bucket (CHECK21 mirrors it into every shipped
#       locale; CHECK24's token legs are untouched - none of these carry {})
#   R5  no dead taxonomy copy: every connect.err_* catalog key is referenced
#       by a literal Translate somewhere in the connect-path file set
#       (ConnectScene/PhlixApp/LoginScene/Utilities)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []
# M-ROKU-15 arrived WITH its triangle: classifier arm + literal ladder arm +
# catalog message (CHECK48 re-pins the same joint law at its own level).
EXPECTED = {"bad_url", "dns", "refused", "tls", "timeout", "unreachable", "redirect_refused"}

UTIL = "source/lib/Utilities.brs"


def read(*parts):
    return open(os.path.join(repo, *parts), encoding="utf-8").read()


def body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


util = read("source", "lib", "Utilities.brs")

# R1: classifier exists and returns exactly the pinned buckets.
cls = body(util, "ClassifyUrlFailure")
if cls is None:
    problems.append(f"  {UTIL} - CHECK34 R1: ClassifyUrlFailure() not found; the "
                    "connect path may not re-open to guessed labels (M-ROKU-04)")
    buckets = set()
else:
    buckets = set(re.findall(r'return\s+"([a-z_]+)"', strip_comments(cls)))
    missing = EXPECTED - buckets
    extra = buckets - EXPECTED
    if missing:
        problems.append(f"  {UTIL} - CHECK34 R1: classifier no longer returns "
                        f"{sorted(missing)} - deleting a bucket deletes a user's "
                        "ability to learn that cause")
    if extra:
        problems.append(f"  {UTIL} - CHECK34 R1: classifier invented buckets "
                        f"{sorted(extra)} without the triangle (message + ladder "
                        "arm must arrive in the same commit)")

# R2: the single Translate ladder covers every bucket literally.
lad = body(util, "TranslateTransportReason")
if lad is None:
    problems.append(f"  {UTIL} - CHECK34 R2: TranslateTransportReason() not found "
                    "- bucket->message must have exactly ONE ladder")
else:
    for b in sorted(EXPECTED):
        if f'Translate("connect_err_{b}")' not in strip_comments(lad):
            problems.append(f"  {UTIL} - CHECK34 R2: ladder lacks literal "
                            f'Translate("connect_err_{b}")')

# R3: the transport guard names every bucket.
isr = body(util, "IsTransportReason")
if isr is None:
    problems.append(f"  {UTIL} - CHECK34 R3: IsTransportReason() not found")
else:
    for b in sorted(EXPECTED):
        if f'"{b}"' not in strip_comments(isr):
            problems.append(f"  {UTIL} - CHECK34 R3: IsTransportReason does not "
                            f"recognize bucket {b}")

# R4: en_US carries a message per bucket.
try:
    en = json.loads(read("locale", "en_US", "strings.json"))
except Exception as e:  # noqa: BLE001 - fail loud, the parse IS the contract
    problems.append(f"  locale/en_US/strings.json - CHECK34: unreadable: {e}")
    en = {}
connect = en.get("connect") if isinstance(en.get("connect"), dict) else {}
if connect == {}:
    problems.append("  locale/en_US/strings.json - CHECK34 R4: connect section missing")
for b in sorted(EXPECTED):
    v = connect.get("err_" + b)
    if not isinstance(v, str) or not v.strip():
        problems.append(f"  locale/en_US/strings.json - CHECK34 R4: connect.err_{b} "
                        "missing or not a non-empty string")

# R5: anti-dead-copy across the connect-path file set.
consumers = ["components/ConnectScene.brs", "components/PhlixApp.brs",
             "components/LoginScene.brs", UTIL]
hay = "\n".join(read(*p.split("/")) for p in consumers)
for k in sorted(connect):
    if not k.startswith("err_"):
        continue
    if f'Translate("connect_{k}")' not in hay:
        problems.append(f"  locale/en_US/strings.json - CHECK34 R5: dead copy - "
                        f'connect.{k} is never consumed by a literal Translate("connect_{k}") '
                        "in the connect-path file set")

if problems:
    for p in problems:
        print(p)
    print("  CHECK34: %d transport-taxonomy problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK34: taxonomy triangle closed - %d buckets, one classifier, one "
      "literal ladder, one honest catalog message each" % len(EXPECTED))
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 35: CanDecodeVideo keeps the SDK options-AA call shape (M-ROKU-05) ==="
# SIGNATURE LAW (M-ROKU-05, review roku__crossfe M5): ifDeviceInfo.CanDecodeVideo
# is documented as CanDecodeVideo(video_format As Object) As Object - ONE
# associative array (keys codec/container/profile/level, lower-case quoted for
# pre-14.1 key case sensitivity) returning an AA whose "result" key holds the
# Boolean. The day-1 wrapper fabricated a positional (String, String, String)
# signature; that API never existed, so the R6.8 direct-play gate either threw
# a member/function arity error or coerced Invalid at every call site. The cure
# is DeviceCanDecodeVideo building the options AA, parsing "result", and
# failing OPEN (allow direct play) whenever the gate itself is broken - a
# wrongly-closed gate taxes every video with transcode, a wrongly-open one is
# recovered by PlayerScene's OnPlayerStateChange transcode fallback. Rules
# (scoped via \b - and for R1 via word-boundary guards in its scanner - so
# the wrapper's own name DeviceCanDecodeVideo, whose public String signature
# is deliberately preserved, never trips them):
#   R1  no .brs file contains a bare receiver-form CanDecodeVideo( call with
#       a TOP-LEVEL comma in its BALANCED argument list - the positional
#       shape stays dead. R-ROKU-25 (review M-ROKU-05__r1 note 3) replaced
#       the day-1 single regex, whose [^)]* capture stopped at the FIRST ')'
#       and let a nested close before the first comma hide every later comma
#       (measured green on a planted evasion), with a string- and
#       comment-aware balanced walk: case-insensitive like BrightScript
#       itself, whole-word guarded like the old \b, amnesty for nested-call,
#       bracket and inline-options-AA shapes whose commas never reach top
#       level, and a fail-loud conviction for an unterminated argument list.
#       Every occurrence of the name is its own scan target (the walk resumes
#       inside each argument list, not past the call), so a positional call
#       buried inside another call's list convicts too - a shape the day-1
#       capture caught only by accident
#   R2  the wrapper function body (comments stripped) builds a quoted
#       lower-case options AA ("codec"/"container"/"profile") and issues a
#       single-argument \bCanDecodeVideo(x) device call
#   R3  the wrapper parses the returned AA via Lookup("result")
#   R4  the gate stays fail-OPEN: a HasMethod("CanDecodeVideo") pre-7.10
#       firmware guard, exactly three logged fail-open arms ("failing open to
#       direct play"), and at least three "return true" fallbacks (missing
#       method / non-AA return / non-Boolean result)
#   R5  the fabricated positional signature comment never returns in any
#       comment line of the wrapper file
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    return open(path, encoding="utf-8").read()


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def keep_comments(text):
    return "\n".join(l for l in text.splitlines() if l.lstrip().startswith("'"))


brs_files = []
for root in ("source", "components"):
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".brs"):
                brs_files.append(os.path.join(dirpath, f))

# R1: the positional device-call shape is extinct in executable code.
# R-ROKU-25 (review M-ROKU-05__r1 note 3): the day-1 capture
# r'\bCanDecodeVideo\(([^)]*)\)' stopped at the FIRST ')', so a positional
# call that closes a nested call before its first comma -
# CanDecodeVideo(WrapFormat(dev), "container") matched as "WrapFormat(dev",
# comma-less - sailed through (measured green on the plant family below).
# The walk reads the BALANCED argument list instead: conviction requires a
# comma at TOP-LEVEL depth, so nested calls, bracket runs and inline
# options-AA literals (all their commas inside braces) stay the legitimate
# shapes they are for the CALL BEING WALKED, and an unterminated list is
# convicted fail-loud. Every occurrence of the name is still its own scan
# target (the walk resumes inside the argument list, never past the whole
# call): a positional CanDecodeVideo buried inside another call's list — the
# shape the day-1 capture convicted only by accident, and what a skip-past
# walk would amnesty through its own depth rule — is walked and convicted on
# its own top-level commas.
# BrightScript identifiers are case-blind, so the name matches
# case-insensitively; the whole-word guards on both sides keep the wrapper's
# own DeviceCanDecodeVideo (and any CanDecodeVideoX neighbour) out of the
# class exactly as \b did. Strings (closed by quote or newline, the
# BrightScript law) and ' line comments - same-line tails included, which
# strip_comments never cut - are skipped, so prose can neither fake a
# conviction nor hide one.
WORD_CHAR = re.compile(r'[A-Za-z0-9_]')


def skip_string(text, i):
    """text[i] is a quote: return the index just past the literal."""
    j = i + 1
    n = len(text)
    while j < n and text[j] not in '"\n':
        j += 1
    return j + 1


def walk_args(text, start):
    """text[start] is the '(' of a CanDecodeVideo call. Return the list of
    top-level argument texts (None if the list never closes). The caller
    deliberately does NOT skip past the whole call: it resumes INSIDE the
    argument list, because an occurrence nested in another call's list is
    itself an executable positional call - the day-1 first-paren-stop capture
    convicted that shape by accident, and the balanced walk must not lose it
    to its own depth amnesty."""
    depth = 0
    args = []
    cur = []
    i = start
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            after = skip_string(text, i)
            cur.append(text[i:after])
            i = after
            continue
        if ch == "'":
            j = text.find("\n", i)
            j = n if j == -1 else j
            cur.append(text[i:j])
            i = j
            continue
        if ch in "([{":
            depth += 1
            if depth > 1:
                cur.append(ch)
            i += 1
            continue
        if ch in ")]}":
            depth -= 1
            if depth < 0:
                return None
            if depth == 0 and ch == ")":
                args.append("".join(cur))
                return args
            cur.append(ch)
            i += 1
            continue
        if ch == "," and depth == 1:
            args.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    return None


def scan_positional_calls(path, text):
    n = len(text)
    i = 0
    while i < n:
        ch = text[i]
        if ch == '"':
            i = skip_string(text, i)
            continue
        if ch == "'":
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        if ch.isalpha() and (i == 0 or not WORD_CHAR.match(text[i - 1])):
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            if text[i:j].lower() == "candecodevideo":
                k = j
                while k < n and text[k] in " \t":
                    k += 1
                if k < n and text[k] == "(":
                    line = text.count("\n", 0, i) + 1
                    args = walk_args(text, k)
                    if args is None:
                        problems.append(f"  {path}:{line} - CHECK35 R1: "
                                        "unterminated CanDecodeVideo( — the "
                                        "argument list never closes; no "
                                        "options-AA call shape can be read "
                                        "from it (M-ROKU-05)")
                    elif len(args) > 1:
                        shown = ", ".join(" ".join(a.split()) for a in args)
                        problems.append(f"  {path}:{line} - CHECK35 R1: "
                                        f"positional CanDecodeVideo({shown}) "
                                        "call - the SDK takes ONE options "
                                        "associative array (M-ROKU-05)")
                    # Resume INSIDE the argument list (k+1), never past the
                    # whole call: every occurrence of the name gets its own
                    # verdict, so a positional CanDecodeVideo buried in an
                    # otherwise-sanctioned single-argument call's list (the
                    # shape the day-1 capture convicted by accident, and the
                    # shape a pure skip-past walk would amnesty) still convicts.
                    i = k + 1
                    continue
            i = j
            continue
        i += 1


for p in brs_files:
    scan_positional_calls(p, read(p))

WRAP = "source/lib/AppContext.brs"
if not os.path.exists(WRAP):
    problems.append(f"  {WRAP} - CHECK35: wrapper file gone; the cure lost its home")
    print("\n".join(problems))
    print("  CHECK35: %d CanDecodeVideo-shape problem(s)" % len(problems))
    sys.exit(1)

raw = read(WRAP)
fm = re.search(r"^function\s+DeviceCanDecodeVideo\b.*?\nend function",
               raw, re.MULTILINE | re.DOTALL)
if fm is None:
    problems.append(f"  {WRAP} - CHECK35 R2: DeviceCanDecodeVideo() not found")
    print("\n".join(problems))
    print("  CHECK35: %d CanDecodeVideo-shape problem(s)" % len(problems))
    sys.exit(1)
body = strip_comments(fm.group(0))

# R2: options AA with quoted lower-case keys + single-argument device call.
for k in ("codec", "container", "profile"):
    if f'"{k}"' not in body:
        problems.append(f'  {WRAP} - CHECK35 R2: options key "{k}" missing from '
                        f"the wrapper body; pre-14.1 firmware reads AA keys "
                        "case-sensitively, so keys must stay lower-case quoted")
if not re.search(r'\bCanDecodeVideo\(\s*[A-Za-z_][A-Za-z0-9_]*\s*\)', body):
    problems.append(f"  {WRAP} - CHECK35 R2: no single-options-AA "
                    "CanDecodeVideo(x) device call form in the wrapper body")

# R3: the result AA carries an honest boolean before it gates.
if 'Lookup("result")' not in body:
    problems.append(f'  {WRAP} - CHECK35 R3: no Lookup("result") on the return; '
                    "the SDK answers with an AA whose result key is the boolean")

# R4: broken gate fails OPEN - firmware guard + three fallback arms.
if 'HasMethod("CanDecodeVideo")' not in body:
    problems.append(f'  {WRAP} - CHECK35 R4: the HasMethod("CanDecodeVideo") '
                    "pre-7.10 firmware guard is gone")
if body.count("failing open to direct play") != 3:
    problems.append(f"  {WRAP} - CHECK35 R4: expected 3 fail-open arms bearing "
                    "'failing open to direct play', found "
                    f"{body.count('failing open to direct play')}")
if len(re.findall(r'^\s*return true\s*$', body, re.MULTILINE)) < 3:
    problems.append(f"  {WRAP} - CHECK35 R4: fewer than 3 'return true' "
                    "fallbacks - the broken gate must not fail closed")

# R5: the fabricated positional doc never returns.
if re.search(r'\bCanDecodeVideo\(codec as String', keep_comments(raw)):
    problems.append(f"  {WRAP} - CHECK35 R5: the fabricated positional "
                    "CanDecodeVideo(codec as String, ...) doc is back; the SDK "
                    "signature is CanDecodeVideo(video_format As Object) As Object")

if problems:
    for p in problems:
        print(p)
    print("  CHECK35: %d CanDecodeVideo-shape problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK35: options-AA call shape, result-key parse, and three fail-open "
      "arms all pinned; the positional fabrication stays dead")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1
echo ""
echo "=== Check 36: day-1 honesty triangle wired end-to-end (M-ROKU-04 closeout) ==="
# CONSUMER-SIDE LAW (M-ROKU-04, review roku__casualgamer M5): Check 34 pins the
# taxonomy PRODUCERS (classifier, ladder, catalog) but says nothing about the
# boot CONSUMERS - without this leg, PhlixApp could silently regress to the
# pre-fix "guess the cause" dialog (which misdiagnosed never-logged-in users as
# network failures), or the Settings server switch could revert to the dead
# "not implemented" copy, and the gate would stay green. Rules:
#   R1  both boot-auth handlers (OnAuthResponse/OnHubAuthResponse) delegate
#       failures to HandleBootAuthFailure(result), and the three pre-fix
#       misdiagnosis literals are dead text in PhlixApp.brs code
#   R2  HandleBootAuthFailure keeps all four honest arms: silent no_session ->
#       login, transport -> ShowConnect(reason), session_invalid -> the live
#       Session Expired dialog (Translate-sourced), else generic
#   R3  the reason survives the handoff: ShowConnect forwards bootReason and
#       ConnectScene renders it via TranslateTransportReason
#   R4  ApiTask forwards restoreReason in BOTH boot legs (checkAuth +
#       checkAuthHub) - producers feeding the consumer (2 forwardings pinned)
#   R5  the server switch is REAL: SettingsScene hands off to
#       OnSwitchServer(), which wipes credentials but keeps the address and
#       lands on ConnectScene
#   R6  the killed dead key settings.status_server_switch_not_implemented
#       stays out of every shipped locale catalog (dead-copy graveyard)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(*parts):
    return open(os.path.join(repo, *parts), encoding="utf-8").read()


def body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


APP = "components/PhlixApp.brs"
app_code = strip_comments(read(*APP.split("/")))

# R1: both boot handlers delegate to the ladder; lying literals stay dead.
for fn in ("OnAuthResponse", "OnHubAuthResponse"):
    b = body(app_code, fn)
    if b is None:
        problems.append(f"  {APP} - CHECK36 R1: {fn}() not found")
    elif "HandleBootAuthFailure(result)" not in b:
        problems.append(f"  {APP} - CHECK36 R1: {fn} no longer routes failures to "
                        "HandleBootAuthFailure(result) - the boot path may be "
                        "guessing causes again (M-ROKU-04)")
for lie in ("Unable to reach server", "Session Expired", "Connection Error"):
    if lie in app_code:
        problems.append(f"  {APP} - CHECK36 R1: reintroduced hardcoded misdiagnosis "
                        f'string "{lie}" - boot copy must come from the catalog ladder')

# R2: the ladder keeps every honest arm.
lad = body(app_code, "HandleBootAuthFailure")
if lad is None:
    problems.append(f"  {APP} - CHECK36 R2: HandleBootAuthFailure() not found - the "
                    "shared boot-failure ladder IS the M-ROKU-04 cure")
else:
    if '"no_session"' not in lad:
        problems.append(f'  {APP} - CHECK36 R2: ladder lost its "no_session" arm - '
                        "first-run users must reach login silently, never an error")
    if "IsTransportReason(" not in lad or "ShowConnect(" not in lad:
        problems.append(f"  {APP} - CHECK36 R2: ladder no longer routes transport "
                        "buckets to ShowConnect - a dead dialog over a login form "
                        "is the bug, not the cure")
    if '"session_invalid"' not in lad or 'Translate("login_expired_title")' not in lad:
        problems.append(f'  {APP} - CHECK36 R2: ladder lost its "session_invalid" arm - '
                        "the Session Expired dialog finally has a live trigger")

# R3: the reason survives the handoff into the retry screen.
sc = body(app_code, "ShowConnect")
if sc is None or "bootReason" not in sc:
    problems.append(f"  {APP} - CHECK36 R3: ShowConnect no longer forwards bootReason - "
                    "the per-cause message would be lost on the retry screen")
cs = strip_comments(read("components", "ConnectScene.brs"))
if "m.top.bootReason" not in cs or "TranslateTransportReason(" not in cs:
    problems.append("  components/ConnectScene.brs - CHECK36 R3: ConnectScene no longer "
                    "renders the transported boot reason (m.top.bootReason -> "
                    "TranslateTransportReason) - the retry screen went generic")

# R4: producers feed the consumer - both boot legs forward restoreReason.
fwd = re.findall(r"result\.error\s*=\s*(?:api|hubApi)\.restoreReason",
                 strip_comments(read("components", "ApiTask.brs")))
if len(fwd) != 2:
    problems.append(f"  components/ApiTask.brs - CHECK36 R4: expected 2 restoreReason "
                    f"forwardings (checkAuth + checkAuthHub), found {len(fwd)} - "
                    "without them the boot ladder receives no reason and Check 34's "
                    "taxonomy is orphaned at the consumer end")

# R5: the Settings server switch is real, not decorative.
ss = body(strip_comments(read("components", "SettingsScene.brs")), "OnSwitchServerConfirmed")
if ss is None:
    problems.append("  components/SettingsScene.brs - CHECK36 R5: "
                    "OnSwitchServerConfirmed() not found")
else:
    if "switch_not_implemented" in ss:
        problems.append("  components/SettingsScene.brs - CHECK36 R5: the server switch "
                        "is back to 'not implemented' - it must hand off to OnSwitchServer()")
    if "OnSwitchServer()" not in ss:
        problems.append("  components/SettingsScene.brs - CHECK36 R5: confirmed switch no "
                        "longer hands off to PhlixApp.OnSwitchServer() - dead button again")
sw = body(app_code, "OnSwitchServer")
if sw is None:
    problems.append(f"  {APP} - CHECK36 R5: OnSwitchServer() not found")
elif "ResetCachedStorage(true)" not in sw or "ShowConnect()" not in sw:
    problems.append(f"  {APP} - CHECK36 R5: OnSwitchServer no longer wipes-and-reconnects "
                    "(ResetCachedStorage(true) + ShowConnect()) - the switch is decorative")

# R6: dead-copy graveyard - the killed key stays dead in every shipped catalog.
for p in sorted(glob.glob(os.path.join(repo, "locale", "*", "strings.json"))):
    try:
        cat = json.loads(open(p, encoding="utf-8").read())
    except Exception as e:  # noqa: BLE001 - the parse IS the contract
        problems.append(f"  {p} - CHECK36: unreadable: {e}")
        continue
    settings = cat.get("settings") if isinstance(cat.get("settings"), dict) else {}
    if "status_server_switch_not_implemented" in settings:
        problems.append(f"  {p} - CHECK36 R6: settings.status_server_switch_not_implemented "
                        "resurrected - R5 pins the live path, so it is dead copy")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK36: %d day-1-honesty problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK36: honesty wired end-to-end - reason produced (ApiTask x2), routed "
      "(ladder x4 arms), rendered (ConnectScene), switch real, dead copy stays dead")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 37: discovery rides the documented socket surface and cannot latch (M-ROKU-04 r2) ==="
# SIGNATURE LAW (M-ROKU-04 r2, review M-ROKU-04__r1 issue 1 - the blocking one):
# r1's DiscoveryTask drove an roSocket via a "udp:" constructor string plus
# EnableBroadcast / JoinMulticastGroup / one-arg Receive - names that appear
# NOWHERE in this repo's own vendored Roku documentation mirror
# (node_modules/brighterscript/dist/roku-types/data.json, whose only UDP
# component is roDataGramSocket) - and hid the component name from bsc behind
# a const-fold-defeating function so the compiler could not flag any of it.
# Worse, a runtime error on that thread killed the task before `response` was
# written, and ConnectScene observed ONLY "response" - the screen latched on
# "Searching…" and dead-buttoned Find forever: the finding's own defect class
# re-introduced on the success path. Rules (files comment-stripped first):
#   R1  DiscoveryTask.brs contains the documented no-arg roDataGramSocket
#       constructor, roSocketAddress objects, and each documented verb of the
#       vendored worked example (SetAddress bind, SetMessagePort,
#       NotifyReadable, SetBroadcast, JoinGroup, SetSendToAddress, SendStr,
#       GetSocketID/GetID event ownership, IsReadable, ReceiveStr) - and the
#       the six r1 counter-doc/evasion patterns (four forms the r1 code
#       actually drove + two evasion artifacts) stay dead
#       ("udp:", EnableBroadcast, JoinMulticastGroup, SendToAddr,
#       DiscoverySocketName, one-arg .Receive()).
#   R2  ConnectScene's find flow observes BOTH "response" and "state" on the
#       DiscoveryTask node and un-observes both on teardown (pairing law).
#   R3  the state arm exists, keys on "finish", checks a missing response,
#       retires the task, and renders the honest connect_find_none floor -
#       an errored scan must degrade exactly like an empty scan.
#   R4  the pure SSDP parser ParseSsdpResponse lives in Utilities.brs (global
#       scope, unit-test reachable) and is NOT defined in the task file.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(*parts):
    return open(os.path.join(repo, *parts), encoding="utf-8").read()


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


task = strip_comments(read("components", "DiscoveryTask.brs"))
scene = strip_comments(read("components", "ConnectScene.brs"))
util = read("source", "lib", "Utilities.brs")

# R1a: the documented verbs of the vendored roDataGramSocket worked example.
REQUIRED = [
    (r'CreateObject\(\s*"roDataGramSocket"\s*\)',
     'the documented no-arg constructor CreateObject("roDataGramSocket")'),
    (r'CreateObject\(\s*"roSocketAddress"\s*\)',
     'roSocketAddress objects for bind/join/sendto'),
    (r'\.SetAddress\(', 'ifSocket.SetAddress(bind to a roSocketAddress)'),
    (r'\.SetMessagePort\(', 'ifSocketAsync.SetMessagePort'),
    (r'\.NotifyReadable\(', 'ifSocketAsync.NotifyReadable'),
    (r'\.SetBroadcast\(', 'ifSocketCastOption.SetBroadcast (docs name)'),
    (r'\.JoinGroup\(', 'ifSocketCastOption.JoinGroup (docs multicast join)'),
    (r'\.SetSendToAddress\(', 'ifSocket.SetSendToAddress (sendto half 1)'),
    (r'\.SendStr\(', 'ifSocket.SendStr (sendto half 2)'),
    (r'\.GetSocketID\(', 'roSocketEvent.GetSocketID event-ownership check'),
    (r'\.GetID\(', 'ifSocketAsync.GetID to compare it against'),
    (r'\.IsReadable\(', 'ifSocketAsync.IsReadable non-blocking drain probe'),
    (r'\.ReceiveStr\(', 'ifSocket.ReceiveStr documented read'),
]
for pat, why in REQUIRED:
    if not re.search(pat, task):
        problems.append(f"  components/DiscoveryTask.brs - CHECK37 R1: lost {why} "
                        "- the scan must drive ONLY the surface vendored in "
                        "brighterscript/dist/roku-types/data.json (M-ROKU-04 r2)")

# R1b: the r1 counter-doc surface stays dead.
FORBIDDEN = [
    (r'"udp:', 'the undocumented roSocket "udp:" constructor string'),
    (r'\bEnableBroadcast\b', 'EnableBroadcast (does not exist; SetBroadcast does)'),
    (r'\bJoinMulticastGroup\b', 'JoinMulticastGroup (does not exist; JoinGroup does)'),
    (r'\bSendToAddr\b', 'SendToAddr (not in this doc era; SetSendToAddress+SendStr)'),
    (r'\bDiscoverySocketName\b', 'the bsc name-obfuscation indirection'),
    (r'\.Receive\(\s*[^,()]*\)', 'one-arg Receive (documented arity is three)'),
]
for pat, why in FORBIDDEN:
    if re.search(pat, task):
        problems.append(f"  components/DiscoveryTask.brs - CHECK37 R1: reintroduced "
                        f"{why} - the counter-doc surface is what made r1 both "
                        "compiler-blind and crash-prone")

# R2: dual-field observation + paired teardown in the consumer.
if not re.search(r'ObserveField\(\s*"response"\s*,\s*"OnDiscoveryResponse"\s*\)', scene):
    problems.append('  components/ConnectScene.brs - CHECK37 R2: no longer observes '
                    'the find task\'s "response"')
if not re.search(r'ObserveField\(\s*"state"\s*,\s*"OnDiscoveryTaskState"\s*\)', scene):
    problems.append('  components/ConnectScene.brs - CHECK37 R2: the find task\'s '
                    '"state" observer is gone - a thread that dies before writing '
                    'response would latch "Searching..." and dead-button Find '
                    'forever (the exact r1 defect)')
for field in ("response", "state"):
    if f'UnObserveField("{field}")' not in scene:
        problems.append(f'  components/ConnectScene.brs - CHECK37 R2: teardown lost '
                        f'its UnObserveField("{field}") pairing')

# R3: the finish arm degrades an errored scan like an empty one.
m3 = re.search(r"^sub\s+OnDiscoveryTaskState\b[^\n]*\n(.*?)^end sub",
               scene, re.MULTILINE | re.DOTALL)
if m3 is None:
    problems.append("  components/ConnectScene.brs - CHECK37 R3: "
                    "OnDiscoveryTaskState() not found")
else:
    arm = m3.group(1)
    for token, why in (('"finish"', 'keys on the finish state'),
                       ('response', 'checks whether a response already arrived'),
                       ('RetireFindTask()', 'retires the task so Find stays pressable'),
                       ('connect_find_none', 'renders the honest empty floor')):
        if token not in arm:
            problems.append(f"  components/ConnectScene.brs - CHECK37 R3: the state arm "
                            f"no longer {why} ({token!r} missing) - an errored scan "
                            "must degrade exactly like an empty scan")

# R4: parser home = global scope (unit-test reachable).
if not re.search(r"^function\s+ParseSsdpResponse\b", util, re.MULTILINE):
    problems.append("  source/lib/Utilities.brs - CHECK37 R4: ParseSsdpResponse() "
                    "definition left the global scope - component-scoped pure logic "
                    "is unreachable from tests/unit")
if re.search(r"^function\s+ParseSsdpResponse\b", task, re.MULTILINE):
    problems.append("  components/DiscoveryTask.brs - CHECK37 R4: ParseSsdpResponse() "
                    "moved back into component scope, out of unit-test reach")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK37: %d documented-surface problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK37: discovery drives ONLY the vendored roDataGramSocket surface, the "
      "scan degrades to the honest floor on every path, and the parser stays testable")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 38: ui_resolutions agrees with the hardcoded 1280x720 design plane (M-ROKU-06) ==="
# DESIGN-PLANE LAW (M-ROKU-06, review roku__crossfe M6): with hd AND full both
# declared, RokuOS runs the app natively at the device design resolution — on a
# 1080p set the 1280x720 layout rendered unscaled in the top-left two-thirds,
# because NOTHING in this repo scales coordinates (census at cce1b34: zero
# resolutionRatio / viewBounds / GetVisibleRect / root Group scale; videoMode
# is read only for the About screen). The channel is a fixed 720p design
# space: 112 XML width/height/loadWidth/loadHeight attribute pins to 1280/720
# across 37 files (cce1b34), and PlayerScene.brs:1185/:3000 size the Video
# node 1280x720. Cure:
# declare 'hd' alone so the OS upscales the canvas on FHD devices.
# Rules (R1/R2 are scoped to the plane's existence — if a future resolution-
# aware rework removes the 1280/720 hardcodes, premise P goes false and
# declaring 'full' becomes a legitimate, conscious choice again):
#   P   premise: at least one XML node under components/ or source/ carries a
#       width|height|loadWidth|loadHeight of 1280 or 720 (the hardcoded plane)
#   R1  while P holds the manifest ui_resolutions token set is EXACTLY {hd} —
#       no 'full' (unscaled native FHD) and no 'sd' (a 1280-wide plane never
#       fits a 640x480 screen; the app is https-only modern)
#   R2  while P holds, FHD-plane-only literals are extinct in the markup: no
#       width="1920"/height="1080" attribute and no translation starting "[960"
#       (960 is the 1920-plane center x; the 720p house center convention is
#       640 — cf. DetailScene.xml's loadingLabel, a 1280-wide box at [0,340] "
#       since MN-10: centered by width, not by an x-anchor). XML comments are
#       blanked BEFORE scanning (line counts preserved) so explanatory prose
#       may quote the dead literals without tripping the gate
#   R3  the contiguous run of manifest comment lines ('-prefixed) sitting
#       directly above the ui_resolutions key must itself carry the words
#       "design" and "720", so the next editor sees the law at the key
#       instead of silently drifting back to hd,full
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    return open(path, encoding="utf-8").read()


xml_files = []
for root in ("components", "source"):
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".xml"):
                xml_files.append(os.path.join(dirpath, f))

# P: the hardcoded 720p design plane exists in the markup. XML comments are
# blanked line-preservingly first: prose that QUOTES a dead literal (like this
# gate's own history notes) is documentation, not a live coordinate.
def strip_xml_comments(text):
    return re.sub(r'<!--.*?-->',
                  lambda m: "\n" * m.group(0).count("\n"), text, flags=re.DOTALL)


xml_code = {p: strip_xml_comments(read(p)) for p in xml_files}

plane_nodes = 0
for p in xml_files:
    plane_nodes += len(re.findall(
        r'\b(?:width|height|loadWidth|loadHeight)="(?:1280|720)"', xml_code[p]))

if not os.path.exists("manifest"):
    problems.append("  manifest - CHECK38: manifest not found; the design-plane law is unreadable")
    print("\n".join(problems))
    print("  CHECK38: %d design-plane problem(s)" % len(problems))
    sys.exit(1)

manifest = read("manifest")
um = re.search(r'^\s*ui_resolutions\s*=\s*(.+?)\s*$', manifest, re.MULTILINE)
if um is None:
    problems.append("  manifest - CHECK38 R1: no ui_resolutions key — the RokuOS default is "
                    "'sd,hd', which contradicts the hardcoded 1280-wide plane just as loudly")
else:
    tokens = {t.strip().lower() for t in um.group(1).split(",") if t.strip()}
    if plane_nodes and tokens != {"hd"}:
        problems.append(f"  manifest - CHECK38 R1: the app hardcodes the 1280x720 plane in "
                        f"{plane_nodes} design-plane attribute pins yet ui_resolutions declares {sorted(tokens)} — "
                        "'full' runs 1080p devices natively UNSCALED (two-thirds dead screen) and "
                        "'sd' cannot show a 1280-wide layout; declare hd alone (M-ROKU-06)")

# R2: FHD-plane-only literals are extinct while the plane holds.
if plane_nodes:
    for p in xml_files:
        for i, line in enumerate(xml_code[p].splitlines(), 1):
            if re.search(r'\b(?:width|height)="(?:1920|1080)"', line):
                problems.append(f'  {p}:{i} - CHECK38 R2: FHD-plane-only size literal on a '
                                f"{plane_nodes}-pin 720p canvas (1280x720 design space, M-ROKU-06)")
            if re.search(r'translation="\[\s*960\b', line):
                problems.append(f'  {p}:{i} - CHECK38 R2: translation x=960 is the 1920-plane '
                                "center; the 720p design-plane center is x=640 (M-ROKU-06)")

# R3: the manifest keeps the rationale visible AT the key — walk the
# contiguous ' comment block directly above the ui_resolutions line.
lines = manifest.splitlines()
idx = next((i for i, l in enumerate(lines)
            if re.match(r'\s*ui_resolutions\s*=', l)), None)
if idx is not None:
    start = idx
    while start > 0 and lines[start - 1].lstrip().startswith("'"):
        start -= 1
    block = "\n".join(lines[start:idx])
    if not ("720" in block and "design" in block.lower()):
        problems.append("  manifest - CHECK38 R3: the ui_resolutions key lost its design-plane "
                        "comment — state the choice where the next editor sees it (M-ROKU-06)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK38: %d design-plane problem(s)" % len(problems))
    sys.exit(1)

print(f"  CHECK38: ui_resolutions=hd agrees with the {plane_nodes}-pin hardcoded "
      "1280x720 design plane; FHD-only literals extinct; rationale visible in the manifest")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 39: manifest rsg_version legal value space + cert posture (M-ROKU-07) ==="
# rsg_version is a real manifest key whose value space is the SceneGraph
# OBSERVER CALLBACK MODEL. The channel shipped rsg_version=7.0 (RSG's package
# version bled into the wrong key) for its whole life: devices silently ignore
# unknown values, and brighterscript's RokuConstants deliberately treats
# unknown-but-semver values as valid — so no vendored tool could ever flag it
# (review roku__crossfe M3). This leg is the gate that cannot be fooled.
# Law (developer.roku.com/dev/docs/channel-manifest, retrieved 2026-10-29):
#   rsg_version "Sets the SceneGraph observer callback model."
#   Documented values: 1.0 (deprecated as of Roku OS 8), 1.1, 1.2 ("defaults
#   to 1.2 as of Roku OS 9.3 if it's not specified"), 1.3.
#   "You must set this parameter to rsg_version=1.3 by October 1, 2026, to
#   continue passing certification testing."
# Rules:
#   R1  the rsg_version key exists — absent means the firmware default (1.2
#       on any modern OS), which fails the post-2026-10-01 cert law
#   R2  its value sits inside the documented set {1.0,1.1,1.2,1.3} — unknown
#       values are silently ignored by devices (false-comfort knob; the 7.0
#       fiction class), and no other gate in the estate sees them
#   R3  the shipped value is exactly 1.3 — legal 1.0/1.1/1.2 declarations fail
#       certification today; re-bless this pin ONLY when Roku moves the
#       goalpost, from a measured red, never pre-emptively
#   R4  the contiguous ' comment block directly above the key carries the
#       words "cert" and "observer" (case-insensitive) — the rationale stays
#       visible where the next editor decides (CHECK38 R3 idiom)
#   R5  Eval() is extinct in shipped .brs (case-insensitively — BrightScript
#       ids ignore case) — Roku's docs state Eval() "cannot
#       be used with rsg_version=1.2", so the declaration and the code may
#       never contradict each other (string-aware line-comment masking)
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

LEGAL_RSG_VERSIONS = ("1.0", "1.1", "1.2", "1.3")

if not os.path.exists("manifest"):
    print("  manifest - CHECK39: manifest not found; the rsg_version law is unreadable")
    print("  CHECK39: 1 rsg_version problem(s)")
    sys.exit(1)

manifest = open("manifest", encoding="utf-8").read()
rm = re.search(r'^\s*rsg_version\s*=\s*(.+?)\s*$', manifest, re.MULTILINE)
if rm is None:
    problems.append("  manifest - CHECK39 R1: no rsg_version key — devices would run the "
                    "firmware default (1.2 as of RokuOS 9.3) and fail the post-2026-10-01 "
                    "certification law requiring rsg_version=1.3 (M-ROKU-07)")
else:
    value = rm.group(1)
    if value not in LEGAL_RSG_VERSIONS:
        problems.append(f"  manifest - CHECK39 R2: rsg_version={value!r} is outside Roku's "
                        f"documented value space {LEGAL_RSG_VERSIONS} (the SceneGraph observer "
                        "callback model) — devices silently ignore unknown values, so the "
                        "declaration means nothing (the M-ROKU-07 7.0 fiction class)")
    elif value != "1.3":
        problems.append(f"  manifest - CHECK39 R3: rsg_version={value!r} is legal but fails "
                        "certification — Roku requires 1.3 to continue passing static-analysis "
                        "cert testing as of 2026-10-01 (channel-manifest docs, M-ROKU-07)")

# R4: the certification/observer rationale must live AT the key. Walk the
# contiguous ' comment block directly above the rsg_version line.
lines = manifest.splitlines()
idx = next((i for i, l in enumerate(lines)
            if re.match(r'\s*rsg_version\s*=', l)), None)
if idx is not None:
    start = idx
    while start > 0 and lines[start - 1].lstrip().startswith("'"):
        start -= 1
    block = "\n".join(lines[start:idx])
    if not ("cert" in block.lower() and "observer" in block.lower()):
        problems.append("  manifest - CHECK39 R4: the rsg_version key lost its certification/"
                        "observer-callback rationale comment — state the law where the next "
                        "editor sees it (M-ROKU-07)")

# R5: Eval() extinction keeps the >=1.2 declaration honest. Line-comment
# masking cuts at the first ' outside a double-quoted string (Check 19's
# code_view idiom, scoped to this leg). BrightScript identifiers are
# case-INsensitive (M-ROKU-07 review m1), so the scan is too — a future
# eval(/EVAL( must not slip past a case-sensitive leg while contradicting
# the rsg_version>=1.2 declaration.
def code_view(line):
    out, in_str = [], False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == "'" and not in_str:
            break
        out.append(ch)
    return "".join(out)

brs_files = []
for root in ("source", "components"):
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".brs"):
                brs_files.append(os.path.join(dirpath, f))

for p in brs_files:
    try:
        for i, line in enumerate(open(p, encoding="utf-8").read().splitlines(), 1):
            if re.search(r'\bEval\s*\(', code_view(line), re.IGNORECASE):
                problems.append(f"  {p}:{i} - CHECK39 R5: Eval() call contradicts the declared "
                                "rsg_version>=1.2 law (Roku: 'Eval() cannot be used with "
                                "rsg_version=1.2') — remove the call (M-ROKU-07)")
    except OSError as e:
        problems.append(f"  {p} - CHECK39: unreadable: {e}")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK39: %d rsg_version problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK39: rsg_version=1.3 inside Roku's documented value space "
      "(1.0/1.1/1.2/1.3 observer callback model); cert-posture rationale at the key; "
      "Eval() extinct in shipped code")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 40: version-discipline script is live code + publish vehicle matches its docs (M-ROKU-09) ==="
# scripts/derive-version.sh carried CI-build-number machinery (get_git_count /
# get_ci_build_version honoring CI_BUILD_NUMBER/GITHUB_RUN_NUMBER) that NO
# main() case dispatched and NO caller consumed — "designed but dead" release
# versioning (review roku__devops M2). Its header also advertised a no-arg
# "output all fields as manifest format" mode that crashed under `set -u`
# ("$1: unbound variable"), and its `*)` arm silently answered ANY unknown
# flag with the pkg version. The cure deleted the dead functions, made the
# header true, guarded the no-arg dispatch and made unknown flags fail loud.
# The publication vehicle (rolling `latest` GitHub prerelease, deleted and
# recreated every master push — package.yml release-latest) and its rollback
# fiction-or-truth documentation are owner-gated strategy (M-ROKU-09 rider B):
# this leg pins workflow reality to docs/publishing.md so they can never
# silently drift, whichever way the owner eventually decides.
# Rules:
#   R1  REACHABILITY: every function defined in scripts/derive-version.sh is
#       reachable from the script's top level (call graph over bare-word bash
#       invocations, comments masked) — a function only called by another dead
#       function is dead too; the dead design may never re-accumulate silently
#   R2  USAGE TRUTH: the header's Usage block and the main() dispatch arms are
#       a bijection on --flags; the no-arg case is guarded ("${1:-}") with an
#       explicit "" arm; the banned fiction phrase "manifest format" is absent
#   R3  BEHAVIOR PROBES (run the script): no-arg exits 0 printing the
#       package.json version; an unknown flag exits NON-ZERO (the silent
#       wrong-version arm is the trap that made the dead design dangerous)
#   R4  VEHICLE↔DOCS: package.yml still implements the rolling `latest`
#       vehicle exactly as docs/publishing.md describes it — the job deletes
#       (gh release delete latest --yes --cleanup-tag) and recreates tag
#       `latest` as a prerelease; publishing.md carries the rolling/rollback/
#       bump vocabulary; README's store-publishing section names the signed
#       .pkg (never "upload phlix.zip"). Change the vehicle and this leg
#       reddens: rotate workflow + docs + this pin in ONE change.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, subprocess, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

DV = "scripts/derive-version.sh"
try:
    dv_text = open(DV, encoding="utf-8").read()
except OSError as e:
    problems.append(f"  {DV} - CHECK40: unreadable: {e}")
    dv_text = None

if dv_text is not None:
    # --- R1: function reachability (bare-word call graph, comments masked) ---
    lines = dv_text.splitlines()
    funcs = {}          # name -> body line list
    order = []          # definition order
    cur = None
    depth = 0
    roots = set()
    for line in lines:
        s = line.strip()
        if s.startswith("#"):
            continue
        if cur is None:
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{', line)
            if m:
                cur = m.group(1)
                funcs[cur] = []
                order.append(cur)
                depth = line.count("{") - line.count("}")
                continue
            for name in funcs:
                if re.search(r'\b' + re.escape(name) + r'\b', line):
                    roots.add(name)
            continue
        body_callers = [n for n in funcs if n != cur and re.search(r'\b' + re.escape(n) + r'\b', line)]
        funcs[cur].extend(body_callers)
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            cur = None

    # root functions invoked at top level; if no call site parses at all, the
    # script cannot run anything — fail loud rather than pass vacuously.
    if not roots:
        problems.append(f"  {DV} - CHECK40 R1: no top-level function invocation found — the script dispatches nothing")
    reachable = set(roots)
    frontier = sorted(roots)
    while frontier:
        nxt = []
        for f in frontier:
            for callee in funcs.get(f, []):
                if callee not in reachable:
                    reachable.add(callee)
                    nxt.append(callee)
        frontier = nxt
    dead = [n for n in order if n not in reachable]
    for d in dead:
        problems.append(f"  {DV} - CHECK40 R1: function '{d}()' is defined but unreachable from the script's top level — designed-but-dead versioning machinery (the M-ROKU-09 class); delete it or wire it with its consumer in the same change")

    # --- R2: usage block <-> dispatch arms bijection + fiction ban ---
    documented = set(re.findall(r'--[A-Za-z0-9-]+',
                                "\n".join(l for l in lines
                                          if re.match(r'^\s*#\s+derive-version\.sh\s+--', l))))
    dispatched = set(re.findall(r'^\s*(--[A-Za-z0-9-]+)\s*[|)]', dv_text, re.MULTILINE))
    for flag in sorted(documented - dispatched):
        problems.append(f"  {DV} - CHECK40 R2: usage header documents '{flag}' but no main() arm dispatches it — a documented flag that answers nothing is the dead-design twin")
    for flag in sorted(dispatched - documented):
        problems.append(f"  {DV} - CHECK40 R2: main() dispatches '{flag}' that the usage header never documents — update the header with the flag")
    if 'case "${1:-}" in' not in dv_text:
        problems.append(f"  {DV} - CHECK40 R2: the no-arg dispatch is not guarded by case \"${{1:-}}\" — an unguarded \"$1\" crashes under set -u (the documented no-arg usage must work)")
    if not re.search(r'""\s*\)', dv_text):
        problems.append(f"  {DV} - CHECK40 R2: no explicit \"\" case arm — the documented no-arg behavior must be dispatched, not fallen through")
    if "manifest format" in dv_text:
        problems.append(f"  {DV} - CHECK40 R2: the header still claims a 'manifest format' output mode nothing emits (C33-era fiction); describe what ships or delete the claim")

    # --- R3: behavior probes (execute the script) ---
    try:
        pkg_version = json.load(open("package.json", encoding="utf-8"))["version"]
    except (OSError, KeyError, json.JSONDecodeError) as e:
        pkg_version = None
        problems.append(f"  package.json - CHECK40 R3: unreadable/versionless ({e}) — the probes cannot run")
    if pkg_version is not None:
        p = subprocess.run(["bash", DV], capture_output=True, text=True)
        if p.returncode != 0 or p.stdout.strip() != pkg_version:
            problems.append(f"  {DV} - CHECK40 R3: no-arg run must exit 0 and print package.json version {pkg_version!r} (got rc={p.returncode}, out={p.stdout.strip()!r}, err={p.stderr.strip()!r})")
        p = subprocess.run(["bash", DV, "--build-ci"], capture_output=True, text=True)
        if p.returncode == 0:
            problems.append(f"  {DV} - CHECK40 R3: unknown flag --build-ci exited 0 printing {p.stdout.strip()!r} — the silent *)-arm wrong-version trap is back; unknown flags must exit non-zero")

# --- R4: publish vehicle pinned by docs == workflow reality ---
WF = ".github/workflows/package.yml"
DOC = "docs/publishing.md"
RDME = "README.md"
try:
    wf_text = open(WF, encoding="utf-8").read()
except OSError as e:
    wf_text = None
    problems.append(f"  {WF} - CHECK40 R4: unreadable ({e}) — the publish-vehicle law is unreadable")
try:
    doc_text = open(DOC, encoding="utf-8").read()
except OSError as e:
    doc_text = None
    problems.append(f"  {DOC} - CHECK40 R4: unreadable ({e}) — publishing docs are part of the pinned contract")
try:
    readme_text = open(RDME, encoding="utf-8").read()
except OSError as e:
    readme_text = None
    problems.append(f"  {RDME} - CHECK40 R4: unreadable ({e})")

if wf_text is not None:
    for pin in ("gh release delete latest --yes --cleanup-tag", "tag_name: latest", "prerelease: true"):
        if pin not in wf_text:
            problems.append(f"  {WF} - CHECK40 R4: publish-vehicle pin '{pin}' is gone — the workflow changed its publication vehicle; rotate docs/publishing.md and this leg in the SAME change (rolling `latest` is the shipped design; versioned releases are an open owner decision, M-ROKU-09 rider B)")
if doc_text is not None:
    for word in ("rolling", "rollback", "bump"):
        if word not in doc_text.lower():
            problems.append(f"  {DOC} - CHECK40 R4: publishing docs lost the '{word}' truth (the vehicle is a rolling `latest` release that destroys the previous build; store submissions need a bumped strictly-increasing triple) — document the shipped reality (M-ROKU-09)")
if readme_text is not None:
    m = re.search(r'^### Publishing to Roku Channel Store\s*$(.*?)(?=^#{2,3} |\Z)',
                  readme_text, re.MULTILINE | re.DOTALL)
    if m is None:
        problems.append(f"  {RDME} - CHECK40 R4: the 'Publishing to Roku Channel Store' section vanished — keep the store-submission truth (signed .pkg via make package-signed, see docs/publishing.md)")
    else:
        section = m.group(1)
        if ".pkg" not in section:
            problems.append(f"  {RDME} - CHECK40 R4: the store-publishing section never names the signed .pkg — the store submission artifact is `make package-signed` output, not phlix.zip (docs/publishing.md; M-ROKU-09)")
        if "Upload your packaged app (phlix.zip)" in section:
            problems.append(f"  {RDME} - CHECK40 R4: the store-publishing section re-mints the 'Upload your packaged app (phlix.zip)' fiction — store submission takes the signed .pkg (docs/publishing.md; M-ROKU-09)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK40: %d version-discipline/publish-vehicle problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK40: derive-version.sh fully reachable + usage-true + fail-loud on unknown flags;")
print("           rolling `latest` vehicle == docs/publishing.md truth (rolling/rollback/bump present, README names the .pkg)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 41: signing wrapper claims only what it enforces; CI has no un-provisioned signer (M-ROKU-10) ==="
# scripts/package-signed.sh claimed a password environment variable no
# component ever read (docs/publishing.md even wired that secret into a CI
# snippet and promised a fail-loud the script could not perform), minted a
# faux-signed artifact by cp'ing the unsigned zip to a .pkg name when rokupkg
# failed while still printing "Signed package ready ... upload to the portal",
# stamped versions from a dead `:-1.0.1` default make never exported through
# to, and CI carried a package-signed stub job that installed no signer —
# green-skipped today, release-blocking the day its gate secret was armed
# (review roku__devops M3, all four bullets). The cure deleted the claims it
# cannot keep, named the artifact to the certificate's actual nature, killed
# the rename fallback fail-loud, threaded the real version, and deleted the
# stub. Rules keep claim<->behavior consistent in BOTH directions:
#   R1 PHANTOM-SECRET BAN: the dead credential token appears nowhere in the
#      signing chain (script, workflow, publishing docs) — a secret no
#      component reads may never again be advertised as required
#   R2 NO FALSE SIGNATURE: the unsigned-zip-renamed-to-.pkg pattern is banned;
#      the certificate-nature gate (openssl subject/issuer read) and the
#      honest *-dev-signed artifact name exist in the script AND are echoed
#      by docs/publishing.md; the dev-only "NOT accepted" banner exists
#   R3 VERSION TRUTH: the stale 1.0.1 default is gone, the script derives
#      PKG_VERSION via derive-version.sh and fails loud on an empty stamp,
#      and the Makefile recipe passes the derived PKG_VERSION explicitly
#   R4 CI SIGNER LAW: no workflow job runs `make package-signed` without
#      provisioning a signer (npm install + rokudev) in the same job — the
#      deleted stub may only return actually able to sign — and every
#      `needs:` entry names a job that exists (dangling-need from stub
#      removal or drift fails here)
#   R5 SMOKE-TRUTH RIDER (M-ROKU-29, review roku__writer M5): M-ROKU-10 made
#      the artifact NAME honest but left standing the claim that a
#      self-signed *-dev-signed.pkg is for "sideload testing" (five surfaces)
#      and a troubleshooting item blaming a missing `sagas.xml` — a file no
#      Roku package contract contains. The dev-mode installer accepts the
#      unsigned zip ONLY (the Makefile install target POSTs
#      -F archive=@phlix.zip; the script's own signer-failure branch already
#      names that route). Arms: R5a the false-smoke-claim needles
#      (whitespace-joined, wrap-tolerant) stay extinct in script, Makefile,
#      publishing doc and README; R5b the honest framing survives deletion —
#      "signing-chain smoke" and the `make install` device route are present
#      in doc AND script (positive-survive-delete, CHECK56 R2 idiom); R5c
#      the package-validation section states the REAL archive contract (root
#      manifest + source/ components/ images/ locale/) and the Makefile
#      still zips exactly that recipe — claim pinned to behavior.
# Static pins only: package-signed.sh executes `make package` and touches
# external CLIs/certs, so unlike CHECK40's pure derive-version.sh this leg
# never runs the wrapper — its guards are grepped, and the behavioral red
# proof rides the portable harness plant legs.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

PS = "scripts/package-signed.sh"
MK = "Makefile"
WF = ".github/workflows/package.yml"
DOC = "docs/publishing.md"
RDME = "README.md"

texts = {}
for path in (PS, MK, WF, DOC, RDME):
    try:
        texts[path] = open(path, encoding="utf-8").read()
    except OSError as e:
        problems.append(f"  {path} - CHECK41: unreadable: {e} — the claim/behavior pin cannot run vacuously")

if not problems:
    ps, mk, wf, doc = texts[PS], texts[MK], texts[WF], texts[DOC]

    # R1 phantom-secret ban
    for path in (PS, WF, DOC):
        if "ROKU_DEV_PASSWORD" in texts[path]:
            problems.append(
                f"  {path} - CHECK41 R1: claims ROKU_DEV_PASSWORD — no component in the signing chain "
                "reads it (auth is the rokudev CLI's interactive session token). A secret advertised as "
                "required but never consumed is the M-ROKU-10 false-assurance class: read it for real "
                "everywhere and rotate this leg, or delete the claim."
            )

    # R2 no false signature
    if re.search(r'cp\s+"?\$\{?PKG_NAME\}?\.zip', ps):
        problems.append(
            f"  {PS} - CHECK41 R2: an unsigned zip is being cp-renamed into the artifact name "
            "— minting a mislabeled 'signed' .pkg is the exact M-ROKU-10 store-cycle-wasting defect; "
            "signing failures must exit non-zero with no artifact"
        )
    if "-subject" not in ps or "-issuer" not in ps:
        problems.append(
            f"  {PS} - CHECK41 R2: the certificate-nature gate (openssl x509 -subject/-issuer compare) "
            "is gone — without it a self-signed cert can masquerade as store-submittable"
        )
    if "-dev-signed" not in ps:
        problems.append(
            f"  {PS} - CHECK41 R2: the honest *-dev-signed artifact name is gone — dev-signed output "
            "must be named to what its certificate can back (M-ROKU-10)"
        )
    if "NOT accepted by the Roku Channel Store" not in ps:
        problems.append(
            f"  {PS} - CHECK41 R2: the dev-only banner is gone — the summary must tell the operator "
            "a self-signed artifact is never uploadable"
        )
    if "-dev-signed" not in doc:
        problems.append(
            f"  {DOC} - CHECK41 R2: the docs lost the *-dev-signed artifact truth the script now names "
            "— behavior and docs rotate together (M-ROKU-10)"
        )

    # R3 version truth — the ban targets the ASSIGNMENT shape (a non-empty
    # literal default in parameter expansion), not prose that names the old
    # pattern historically; the derive law tolerates the quoted call path.
    if re.search(r'^\s*PKG_VERSION="\$\{PKG_VERSION:-[^}"]+\}"', ps, re.M):
        problems.append(
            f"  {PS} - CHECK41 R3: PKG_VERSION carries a hardcoded literal fallback default — make does "
            "not export ordinary variables, so `:-<version>}` silently mis-stamps direct invocations "
            "(the stale 1.0.1 defect, M-ROKU-10); derive it or fail loud"
        )
    if not re.search(r'derive-version\.sh"?\s+--pkg-version', ps):
        problems.append(
            f"  {PS} - CHECK41 R3: the PKG_VERSION fallback no longer derives from "
            "scripts/derive-version.sh --pkg-version — the single-source version law"
        )
    if not re.search(r'\[\s+-z\s+"\$PKG_VERSION"\s*\]', ps):
        problems.append(
            f"  {PS} - CHECK41 R3: the empty-version fail-loud guard is gone — an undeterminable "
            "version must halt BEFORE minting an artifact"
        )
    if not re.search(r'PKG_VERSION="\$\(PKG_VERSION\)"\s+bash\s+scripts/package-signed\.sh', mk):
        problems.append(
            f"  {MK} - CHECK41 R3: the package-signed recipe no longer passes PKG_VERSION=\"$(PKG_VERSION)\" "
            "into the script — make variables are not exported to recipes unless asked"
        )

    # R4 CI signer law + needs consistency
    job_starts = [(m.start(), m.group(1)) for m in re.finditer(r"(?m)^  ([A-Za-z0-9_-]+):\s*$", wf)]
    defined = set(name for _, name in job_starts)
    for idx, (pos, name) in enumerate(job_starts):
        end = job_starts[idx + 1][0] if idx + 1 < len(job_starts) else len(wf)
        block = wf[pos:end]
        if "make package-signed" in block:
            if not re.search(r"npm (ci|install)", block) or "rokudev" not in block:
                problems.append(
                    f"  {WF} - CHECK41 R4: job '{name}' runs `make package-signed` without provisioning a "
                    "signer (npm ci + rokudev) — the un-buildable green stub is the M-ROKU-10 class: it "
                    "skips silently today and blocks its `needs:` consumers the day its gate secret is armed"
                )
    needs_pat = re.compile(r"^\s*needs:\s*(?:\[([^\]]*)\]|([A-Za-z0-9_-]+))\s*$", re.M)
    for m in needs_pat.finditer(wf):
        for dep in re.split(r",", m.group(1) or m.group(2) or ""):
            dep = dep.strip().strip("'\"")
            if dep and dep not in defined:
                problems.append(
                    f"  {WF} - CHECK41 R4: `needs:` lists job '{dep}' which no longer exists "
                    "(deleted stub not un-referenced?) — release lanes would never start"
                )

    # ---- R5 smoke-truth rider (M-ROKU-29) --------------------------------
    SIDELOAD_FICTIONS = (
        "sideload testing only",
        "can be sideloaded",
        "sideload it for testing",
        "self-signed cert only sideloads",
    )
    for path in (PS, MK, DOC, RDME):
        joined = re.sub(r"\s+", " ", texts[path]).lower()
        for needle in SIDELOAD_FICTIONS:
            if needle in joined:
                problems.append(
                    f"  {path} - CHECK41 R5: revives the self-signed-sideload fiction "
                    f"({needle!r}) — no .pkg is device-installable; the dev-mode "
                    "installer takes the unsigned phlix.zip via 'make install' "
                    "(M-ROKU-29: the chain may only be described as it performs)"
                )
    for path in (DOC, PS):
        if "signing-chain smoke" not in texts[path]:
            problems.append(
                f"  {path} - CHECK41 R5: the 'signing-chain smoke' framing is gone — the "
                "dev-signed artifact's sole honest purpose must stay named; a cure that "
                "can be silently deleted is the same misinformation (positive-survive-"
                "delete, CHECK56 R2 idiom; M-ROKU-29)"
            )
        if "make install" not in texts[path]:
            problems.append(
                f"  {path} - CHECK41 R5: the device route ('make install', unsigned zip) "
                "is no longer named — steering testers to a path that actually installs "
                "is the load-bearing half of the cure (M-ROKU-29)"
            )
    if "sagas" in texts[DOC].lower():
        problems.append(
            f"  {DOC} - CHECK41 R5: a `sagas` artifact claim is back — no such file "
            "exists in the Roku package contract (root manifest + source/ components/ "
            "images/ locale/, the Makefile zip recipe); troubleshooting copy may name "
            "only shipped entries (M-ROKU-29, review roku__writer M5)"
        )
    _anchor = '"Package validation failed"'
    _i = texts[DOC].find(_anchor)
    if _i < 0:
        problems.append(
            f"  {DOC} - CHECK41 R5: the 'Package validation failed' anchor vanished — "
            "the package-contract pin cannot run vacuously; rotate this leg with the "
            "doc in the same commit (M-ROKU-29)"
        )
    else:
        _rest = texts[DOC][_i + len(_anchor):]
        _ends = [k for k in (_rest.find(t) for t in ("\n### ", "\n## ", "\n---\n")) if k >= 0]
        _sec = _rest[: min(_ends)] if _ends else _rest
        for token in ("manifest", "source/", "components/", "images/", "locale/"):
            if token not in _sec:
                problems.append(
                    f"  {DOC} - CHECK41 R5: the package-validation section no longer "
                    f"names `{token}` — the troubleshooting contract must state the "
                    "real archive shape (root manifest + source/ components/ images/ "
                    "locale/; M-ROKU-29)"
                )
    if not re.search(r"find source components images locale manifest -type f \| LC_ALL=C sort \| zip -X -q", mk):
        problems.append(
            f"  {MK} - CHECK41 R5: the package recipe no longer zip-pipes "
            "`source components images locale manifest` through the deterministic "
            "staged sorted-entry line (M-ROKU-20 rotated the era "
            "'zip -r $(PKG_NAME).zip source components images locale' literal onto "
            "this shape) — the doc's archive-contract claim is pinned to this exact "
            "line; rotate the doc, scripts/verify-package.sh and "
            "this leg together (M-ROKU-29)"
        )

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK41: %d signing-claim/behavior problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK41: no phantom password-secret claim in the signing chain; no rename-into-.pkg fallback;")
print("           certificate nature names the artifact (dev-signed honesty in script AND docs);")
print("           version derived + passed explicitly; no workflow signs without a provisioned signer, every needs: resolves")
print("           no self-signed-sideload fiction (smoke-only framing + device-zip route live;")
print("           package-validation contract pinned to the Makefile zip recipe, M-ROKU-29)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 42: channel version headers + the local diagnostics surface are wired, not claimed (M-ROKU-11) ==="
# A retail user could not tell anyone what was running or what went wrong: no
# version left the device, Settings -> About rendered a hardcoded "1.0.1", the
# only crash story was a dev-mode telnet, and docs/debugging.md described that
# telnet with claims the platform does not support (review roku__devops M4).
# The cure added X-Phlix-Client-Version to every ApiClient send site (value
# from roAppInfo.GetVersion(), never a literal), made the About screen read
# real firmware identity, gave it an OS-side crash record
# (ifappmanager.GetLastExitInfo, Roku OS 13.0+) plus a render-thread last-N
# error ring, and moved the multi-line block onto the Label that can actually
# wrap. Rules keep every one of those claims load-bearing IN BOTH DIRECTIONS:
#   R1 SEND-SITE LAW: all three ApiClient send sites (sendRaw,
#      sendRawWithDeviceId, resolveLocation) carry
#      AddHeader("X-Phlix-Client-Version", m.clientVersion) in CODE (comments
#      masked), and the factory stamps obj.clientVersion from the single
#      firmware source. A fourth send site added later must be listed here.
#   R2 NO VERSION LITERAL: no version-shaped string literal is assigned or
#      sent anywhere in source/ + components/, and the header value is never a
#      literal - the About lie (version = "1.0.1") may not return, in code or
#      in the wire header.
#   R3 SINGLE SOURCE: GetChannelVersion() -> ChannelInfo() ->
#      CreateObject("roAppInfo").GetVersion() is the one path, defined in
#      source/lib/AppContext.brs, and the About screen reads the version
#      through GetChannelVersion() so screen and wire cannot disagree.
#   R4 RING WIRED: the ring exists with its pinned capacities (12 kept, 5
#      shown), trims through DiagnosticsRingSize(), and is fed from BOTH legal
#      render-thread sites (PhlixApp.HandleBootAuthFailure,
#      SettingsScene.OnApiResponse failure arms) and read by the About screen.
#   R5 CRASH RECORD HONESTY: GetLastExitInfo() is firmware-gated with Val() on
#      the STRING GetOSVersion().major (>= 13, per
#      https://developer.roku.com/dev/docs/ifappmanager live 2026-10-29), and
#      the docs state the console_log limitation - that field only exists for
#      run_as_process=1 channels, which this manifest is NOT (pinned from both
#      sides: manifest has no run_as_process, docs say so).
#   R6 READABLE SURFACE: the multi-line block lands on detailLabel (which is
#      wrap="true" and 540 tall in SettingsScene.xml); the single-line status
#      bar keeps exactly the headline. Writing a Chr(10) block to statusLabel
#      is the theater this leg kills.
#   R7 CATALOG BINDING: every new About/diagnostics key exists in en_US and is
#      consumed in components/SettingsScene.brs (dead copy red).
#   R8 NOTHING LEAVES THE DEVICE: the diagnostics family opens no socket and
#      issues no request - there is no invented telemetry endpoint, so the
#      family files must contain no roUrlTransfer/AsyncPostFromString/SetUrl.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

AC = "source/lib/ApiClient.brs"
CTX = "source/lib/AppContext.brs"
SCENE = "components/SettingsScene.brs"
APP = "components/PhlixApp.brs"
XML = "components/SettingsScene.xml"
DOC = "docs/debugging.md"
CAT = "locale/en_US/strings.json"
MAN = "manifest"

HEADER = "X-Phlix-Client-Version"
NEW_KEYS = [
    "settings_about_channel_id",
    "settings_about_os_version",
    "settings_about_crash_heading",
    "settings_about_last_exit",
    "settings_about_last_exit_none",
    "settings_about_recent_errors",
    "settings_about_no_errors",
    "settings_about_error_entry",
]

problems = []


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def mask_comments(text):
    """Blank out BrightScript ' comments (string-aware) keeping offsets exact."""
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut].ljust(len(line)))
    return "\n".join(out)


def method_body(text, name):
    """Slice a factory-object method from its declaration to its end function."""
    m = re.search(r"(?m)^\s*%s:\s*function\(" % re.escape(name), text)
    if m is None:
        return None
    end = text.find("end function", m.end())
    return text[m.start():] if end == -1 else text[m.start():end]


texts = {}
for path in (AC, CTX, SCENE, APP, XML, DOC, CAT, MAN):
    try:
        texts[path] = read(path)
    except OSError as err:
        problems.append(f"  {path} - CHECK42: unreadable: {err} — the pin cannot run vacuously")

if not problems:
    ac = mask_comments(texts[AC])
    ctx = mask_comments(texts[CTX])
    scene = mask_comments(texts[SCENE])
    app = mask_comments(texts[APP])
    xml = texts[XML]
    doc = texts[DOC]
    man = texts[MAN]

    # ---- R1 send-site law ------------------------------------------------
    for name in ("sendRaw", "sendRawWithDeviceId", "resolveLocation"):
        body = method_body(ac, name)
        if body is None:
            problems.append(
                f"  {AC} - CHECK42 R1: send site `{name}` no longer exists — the three-site"
                " census of version-header carriers cannot be verified"
            )
            continue
        if not re.search(r'AddHeader\(\s*"%s"\s*,\s*m\.clientVersion\s*\)' % HEADER, body):
            problems.append(
                f"  {AC} - CHECK42 R1: `{name}` does not send AddHeader(\"{HEADER}\", "
                "m.clientVersion) in code — a request path with no channel identity is the "
                "M-ROKU-11 blind spot restated; every send site carries it"
            )
    if not re.search(r'obj\.clientVersion\s*=\s*GetChannelVersion\(\)', ac):
        problems.append(
            f"  {AC} - CHECK42 R1: the factory no longer stamps obj.clientVersion from "
            "GetChannelVersion() — the header would ride on the declared placeholder forever"
        )

    # ---- R2 no version literal anywhere in client code -------------------
    brs_files = []
    for scan_dir in ("source", "components"):
        for root, dirs, names in os.walk(scan_dir):
            dirs.sort()
            for name in sorted(names):
                if name.endswith(".brs"):
                    brs_files.append(os.path.join(root, name))
    for path in sorted(brs_files):
        try:
            code = mask_comments(read(path))
        except OSError as err:
            problems.append(f"  {path} - CHECK42 R2: unreadable: {err}")
            continue
        for mo in re.finditer(r'(version\s*=\s*|AddHeader\(\s*"%s"\s*,\s*)"(\d+\.\d+(?:\.\d+)?)"' % HEADER, code, re.I):
            lineno = code.count("\n", 0, mo.start()) + 1
            problems.append(
                f"  {path}:{lineno} - CHECK42 R2: a version literal in code — the About screen's "
                'hardcoded "1.0.1" reported a number unrelated to the installed build '
                "(M-ROKU-11); the value comes from roAppInfo.GetVersion()"
            )

    # ---- R3 single firmware source ----------------------------------------
    if not re.search(r"function GetChannelVersion\(\) as String\s*\n\s*return ChannelInfo\(\)\.version", ctx):
        problems.append(
            f"  {CTX} - CHECK42 R3: GetChannelVersion() no longer returns ChannelInfo().version "
            "— the About screen and the wire header would stop sharing one source"
        )
    if not re.search(r'CreateObject\("roAppInfo"\)', ctx) or ".GetVersion()" not in ctx:
        problems.append(
            f"  {CTX} - CHECK42 R3: ChannelInfo() no longer reads roAppInfo.GetVersion() — the "
            "firmware is the only version source (docs/debugging.md promises it)"
        )
    if "GetChannelVersion()" not in scene:
        problems.append(
            f"  {SCENE} - CHECK42 R3: the About screen no longer reads GetChannelVersion() — "
            "screen and wire must not be able to disagree"
        )

    # ---- R4 ring wired ---------------------------------------------------
    for fn in ("function DiagnosticsRingSize() as Integer", "function DiagnosticsShownCount() as Integer",
               "sub RecordDiagnosticsError(kind as String, detail as String)",
               "function GetDiagnosticsRing() as Object", "sub ClearDiagnosticsRing()",
               "function DiagnosticText(value as Object) as String",
               "function GetRunElapsedMs() as LongInteger"):
        if fn not in ctx:
            problems.append(
                f"  {CTX} - CHECK42 R4: `{fn}` is gone — the documented ring surface "
                "(docs/debugging.md) would be a claim without an implementation"
            )
    if "return 12" not in (re.search(r"DiagnosticsRingSize\(\) as Integer\s*\n\s*return \d+", ctx).group(0)
                           if re.search(r"DiagnosticsRingSize\(\) as Integer\s*\n\s*return \d+", ctx) else ""):
        problems.append(
            f"  {CTX} - CHECK42 R4: the ring capacity is no longer the pinned 12 — "
            "docs/debugging.md states 'last 12 failures' and rotates only with this leg"
        )
    if not re.search(r"while ring\.Count\(\) > DiagnosticsRingSize\(\)", ctx):
        problems.append(
            f"  {CTX} - CHECK42 R4: the ring no longer trims through DiagnosticsRingSize() — "
            "an unbounded 'last-N' list is not last-N"
        )
    if "RecordDiagnosticsError(" not in app or "RecordDiagnosticsError(" not in scene:
        problems.append(
            "  components - CHECK42 R4: a render-thread push site disappeared "
            "(PhlixApp.HandleBootAuthFailure / SettingsScene.OnApiResponse failure arms) — "
            "the ring would always read 'None this session'"
        )
    if len(re.findall(r"RecordDiagnosticsError\(\"settings", scene)) < 2:
        problems.append(
            f"  {SCENE} - CHECK42 R4: the two server-failure arms no longer both record — "
            "dropping the classified reason is the exact defect the ring cures"
        )

    # ---- R5 crash record honesty -----------------------------------------
    if not re.search(r"if GetOSMajorVersion\(\) < 13 then return invalid", ctx):
        problems.append(
            f"  {CTX} - CHECK42 R5: GetLastExitInfo() lost its Roku OS 13.0 gate — the call is "
            "undefined on older firmware (https://developer.roku.com/dev/docs/ifappmanager)"
        )
    if not re.search(r"return Val\(major\)", ctx):
        problems.append(
            f"  {CTX} - CHECK42 R5: the OS gate no longer goes through Val() — "
            "ifdeviceinfo.GetOSVersion() fields are STRINGS, so a numeric comparison is a "
            "type mismatch on real firmware"
        )
    if 'CreateObject("roAppManager").GetLastExitInfo()' not in ctx:
        problems.append(
            f"  {CTX} - CHECK42 R5: the exit record is no longer read from ifappmanager — "
            "Roku's own mechanism is the only crash surface this client may claim"
        )
    if re.search(r"^\s*run_as_process\s*=", man, re.M):
        problems.append(
            f"  {MAN} - CHECK42 R5: run_as_process is now set — docs/debugging.md states Phlix "
            "is NOT a run_as_process channel and therefore never receives the console_log field "
            "of GetLastExitInfo; if this is deliberate, rotate the doc in the same commit"
        )
    if "run_as_process=1" not in doc or "This manifest does not set it" not in doc:
        problems.append(
            f"  {DOC} - CHECK42 R5: the console_log caveat is gone — claiming the last-20 "
            "console lines without the run_as_process precondition is the fiction class this "
            "lane cured (M-ROKU-11)"
        )

    # ---- R6 readable surface --------------------------------------------
    if "m.detailLabel.text = info" not in scene:
        problems.append(
            f"  {SCENE} - CHECK42 R6: the multi-line About block no longer lands on "
            "detailLabel — statusLabel is a 40px single-line Label, so the block would be "
            "unreadable theater (the defect this lane found)"
        )
    detail = re.search(r'<Label[^>]*id="detailLabel"[^>]*>', xml, re.S)
    status = re.search(r'<Label[^>]*id="statusLabel"[^>]*>', xml, re.S)
    if detail is None or 'wrap="true"' not in detail.group(0):
        problems.append(
            f"  {XML} - CHECK42 R6: detailLabel lost wrap=\"true\" — the diagnostics block "
            "cannot render multi-line without it"
        )
    if status is not None and 'wrap="true"' in status.group(0):
        problems.append(
            f"  {XML} - CHECK42 R6: statusLabel is now a wrapping Label — the doc describes it "
            "as the single-line headline surface; rotate docs/debugging.md together with this"
        )

    # ---- R7 catalog binding ----------------------------------------------
    try:
        catalog = json.loads(texts[CAT])
    except ValueError as err:
        problems.append(f"  {CAT} - CHECK42 R7: unparseable: {err}")
        catalog = {}
    flat = {f"{section}_{bare}" for section, vals in catalog.items()
            if section != "_metadata" and isinstance(vals, dict)
            for bare, leaf in vals.items() if isinstance(leaf, str)}
    scene_keys = set(re.findall(r'Translate(?:WithParams)?\(\s*"([A-Za-z0-9_.]+)"', scene))
    for key in NEW_KEYS:
        if key not in flat:
            problems.append(
                f"  {CAT} - CHECK42 R7: {key} is missing from the flattened en_US table — "
                "the About screen would render the raw key (CHECK20/21 territory)"
            )
        if key not in scene_keys:
            problems.append(
                f"  {SCENE} - CHECK42 R7: dead copy — {key} exists in the catalog but the "
                "About screen never consumes it"
            )

    # ---- R8 nothing leaves the device ------------------------------------
    for path, code in ((CTX, ctx), (SCENE, scene)):
        for tok in ("roUrlTransfer", "AsyncPostFromString", "AsyncGetToString", "SetUrl("):
            if tok in code:
                problems.append(
                    f"  {path} - CHECK42 R8: the diagnostics surface now issues a request "
                    f"({tok}) — M-ROKU-11 ships LOCAL capture only; there is no telemetry "
                    "endpoint in this estate and none may be invented here"
                )

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK42: %d channel-identity/diagnostics problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK42: all three ApiClient send sites carry X-Phlix-Client-Version from the single roAppInfo")
print("           source; no version literal in any .brs; ring (12 kept / 5 shown) fed from both")
print("           render-thread sites and read by About; last-exit record Val()-gated to OS 13.0+ with")
print("           the run_as_process console_log caveat stated in the docs and true in the manifest;")
print("           multi-line block on the wrapping detailLabel; 8 new catalog keys live and consumed;")
print("           the diagnostics family opens no socket")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 43: wire error text is type-guarded before it meets string ops (M-ROKU-12) ==="
# Hostile-input law for wire text (review roku__exploiter M1, fix M-ROKU-12).
# A response body is attacker-influenced data: the contract says {error:
# string}, but a hostile server (or, on http://, any LAN injector) can answer
# {"error":123} / {"error":{"code":1}} instead. That non-String meeting a
# String operation - `<> ""` / `= ""` compares, lcase/instr/Left/Trim/Mid,
# concatenation, or an `as String` sink - is a BrightScript runtime type
# mismatch: on scenes it kills the render thread mid-login, on tasks it
# bricks the task. The cure SSOTs are SafeErrorMessage() + StripWireControl-
#Chars() + WireErrorMessageMax() (source/lib/Utilities.brs) and the task-
# thread choke DeriveResponseError()/WireErrorPresent() (components/
# ApiTask.brs). CHECK42 stays reserved to the M-ROKU-11 telemetry lane.
#   R1  five arms over the code-masked line (strings -> "", comments dropped):
#       a `.error`/`.message` wire member may NOT (a) be compared to a string
#       literal, (b) meet a string op (lcase/ucase/instr/left/right/len/
#       trim/mid), (c) meets a + on either side - concatenated into or out
#       of a string (the r2 blind class `"Server error: " + resp.error`,
#       both operand orders), (d) be passed as a direct call argument to a sink
#       whose first parameter is not proven `as Object` - the Object-sink set
#       is DERIVED from the tree's own function/sub signatures, so the guard
#       family self-exempts while `IsTransportReason(resp.error)`-style
#       String-sink calls convict, or (e) be lifted/returned raw into a
#       variable. Arms (a)-(d) run on a GUARD-SPAN-MASKED code view (R-ROKU-
#       03): a SafeErrorMessage/WireErrorPresent/WireErrorText call is
#       blanked together with its balanced argument span, so a guard token
#       on the line can no longer exempt a SECOND raw operand sitting
#       outside it (`WireErrorPresent(x.error) and x.error <> ""` - the
#       line-coarse slip r3 named). The "roString" type-gate literal keeps
#       the whole-line exemption, guarding the sanctioned PlayerScene
#       idiom; per-operand treatment of that family would convict
#       `type(ev.message) = "roString" and ev.message <> ""`, an accepted,
#       named residual. The bare "String" literal no longer exempts by
#       itself (R-ROKU-04, the r3 note's coarse-token ask): it counts ONLY
#       in the wire-bound gate shape - the line type-gating a wire member
#       itself, `Type(x.error) =/<> "String"` - the single-sided analogue
#       of the sanctioned roString idiom. An unrelated `"String"` (the
#       non-wire `Type(req.base_url) = "String"` gates at
#       components/ApiTask.brs:792/:794/:797 are the living shapes) buys
#       nothing, and the code mask closes with it: outside that gate the
#       literal renders `""`, so `x.error <> "String"` - a wire member
#       compared to string TEXT, the shape the verbatim keep hid from the
#       arm-(a) `<> ""` eyes - now convicts instead of sliding past.
#       Measured at tip before the tightening: zero convictions - every
#       `"String"` line pairs a roString/function guard or carries no wire
#       member (the three bare-token gates at ApiTask match no arm even
#       with the token removed). A comment naming a guard still buys
#       nothing (code-mask law, review r1 minor). (e) keeps the raw-line
#       token (the sanctioned choke-lift allowance). `.top`-prefixed reads
#       are RSG-typed and exempt.
#   R2  the cure artifacts are live: Utilities defines SafeErrorMessage
#       (value as Object) and WireErrorMessageMax() returning the pinned 300;
#       ApiTask defines WireErrorPresent and routes DeriveResponseError
#       through SafeErrorMessage.
#   NO path exemptions. The in-flight WARN set {components/PhlixApp.brs,
#   source/lib/ApiClient.brs} was DELETED here (review M-ROKU-12 r2, ask 2):
#   its premise - the M-ROKU-11 lane curing the ApiClient raw lifts - landed
#   typed at 587f85b (WireErrorText guards every wire lift in both files),
#   and a path hole over the two wire-choke files is exactly where this class
#   silently re-accumulated once (M-ROKU-11's own SettingsScene:214 raw
#   concat slipped CHECK43 while they were exempted). The whole tree is one
#   law.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ["REPO"]

# A line whose CODE carries a guard token has touched the value through a
# choke. WireErrorText (the ApiClient source-choke guard, M-ROKU-11
# completion) joins the set here because the exemption list above was
# deleted in the same commit: the cured lines must survive by the token,
# never by a path hole (review M-ROKU-12 r2, Ask-1 coupled detail). The
# "roString" type-gate literal survives the code mask below precisely so
# it stays visible to this check; the "String" literal survives ONLY as
# the right-hand side of a WIRE-BOUND gate (WIRE_GATE_HEAD) - R-ROKU-04,
# replacing the former bare-token alternative that let any line carrying
# the literal for unrelated reasons exempt arms (a)-(d).
WIRE_GATE_HEAD = r'\b[Tt]ype\s*\([^)]*\.(?:error|message)\b[^)]*\)\s*(?:<>|==|=)\s*'
GUARDED = re.compile(r'SafeErrorMessage\(|WireErrorPresent\(|WireErrorText\(|"roString"|' + WIRE_GATE_HEAD + r'"String"')
# R-ROKU-03: the guard-call spans, masked out of the code view so one guard
# token cannot exempt a second raw operand on the same line. One nesting
# level of balanced argument parens is consumed (real tree shapes include
# e.g. SafeErrorMessage(str(st).trim(), "")). Unbalanced/continued calls
# simply do not match and keep the pre-R-ROKU-03 whole-line exemption.
GUARD_CALL = re.compile(
    r'(?:SafeErrorMessage|WireErrorPresent|WireErrorText)\s*\('
    r'[^()]*(?:\([^()]*\)[^()]*)*\)'
)
# A wire-controlled member. `.top` reads (m.top.* RSG fields) are exempt:
# the node server coerces on write, so a read off them can never hand a
# non-String to a string op. (This lookbehind is placed BEFORE the dot -
# the pattern consumes it - where the old `(?<!m\.top\.)` window could
# never actually match and exempted nothing.)
WIRE = r'(?<!\.top)\.(?:error|message)\b'
# Wire member lifted/returned raw into a variable.
RAW_READ = re.compile(r'(?<![.\w])(?:return|=)\s+[\w.]*' + WIRE)
# Wire member compared against a String literal (code-only view renders any
# `<> "..."` as `<> ""` - a non-String wire value compared to text is the
# silent-true / crash-next-line class either way).
RAW_COMPARE = re.compile(WIRE + r'\s*(?:<>|==|=)\s*""')
# A String operation applied directly to a wire member.
RAW_STRINGOP = re.compile(
    r'\b(?:lcase|ucase|instr|left|right|len|trim|mid)\s*\([^)]*' + WIRE,
    re.I,
)
# A wire member meeting a + on either side - the r2 blind-spot plant
# `x = "Server error: " + resp.error` and its mirror.
RAW_CONCAT = re.compile(r'[+]\s*[\w.]*' + WIRE + r'|[\w.]*' + WIRE + r'\s*[+]')
# A wire member as the direct first argument of a call. Tolerated only when
# the callee's first parameter is proven `as Object` (the guard family and
# every other Object sink in the tree self-exempt via OBJECT_SINKS below);
# any other callee - String-typed, method, or unresolved builtin - is a
# typed sink and the crash class.
CALL_ARG = re.compile(r'[A-Za-z_]\w*\s*\(\s*[\w.]*' + WIRE)
FUNC_DEF = re.compile(r'^\s*(?:function|sub)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)', re.I | re.M)

paths = sorted(
    glob.glob(os.path.join(repo, "source", "**", "*.brs"), recursive=True)
    + glob.glob(os.path.join(repo, "components", "**", "*.brs"), recursive=True)
)

# Derive the tree's own Object-sink set: a name is safe only if every
# definition of it takes `as Object` (or no parameter) first.
object_sinks = set()
unsafe_sinks = set()
for path in paths:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for match in FUNC_DEF.finditer(fh.read()):
            name = match.group(1)
            params = match.group(2).strip()
            first = params.split(",")[0] if params else ""
            if not params or re.search(r'\bas\s+Object\b', first, re.I):
                object_sinks.add(name)
            else:
                unsafe_sinks.add(name)
object_sinks -= unsafe_sinks

def code_only(line):
    """Strip double-quoted strings; drop full-line and inline ' comments.

    The "roString" type-gate literal is KEPT verbatim: it is itself a
    GUARDED token and masking it away would make the r1 code-mask
    hardening blind the type-guard idiom it audits (PlayerScene's
    `type(ev.message) = "roString"` family). The "String" literal keeps
    that visibility ONLY in the wire-bound gate shape (WIRE_GATE_HEAD,
    R-ROKU-04): elsewhere it masks to "" like any other text, which both
    strips its whole-line exemption power and renders the formerly
    invisible `x.error <> "String"` compare to the arm-(a) `<> ""` eyes."""
    wire_gate_prefix = re.compile(WIRE_GATE_HEAD + r'$')
    def mask(match):
        literal = match.group(0)
        if literal == '"roString"':
            return literal
        if literal == '"String"' and wire_gate_prefix.search(match.string[:match.start()]):
            return literal
        return '""'
    code = re.sub(r'"[^"]*"', mask, line)
    if code.lstrip().startswith("'"):
        return ""
    cut = code.find("'")
    if cut >= 0:
        code = code[:cut]
    return code

problems = []
scanned = 0

for path in paths:
    rel = os.path.relpath(path, repo).replace(os.sep, "/")
    scanned += 1
    with open(path, encoding="utf-8", errors="replace") as fh:
        for num, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            code = code_only(line)
            if not code.strip():
                continue
            masked = GUARD_CALL.sub("", code)
            why = None
            if not GUARDED.search(masked):
                # Arms (a)-(d): the token must live in CODE, not in a comment
                # (review r1 minor - code-mask hardening), and NOT inside a
                # guard-call span (R-ROKU-03 - span mask; after blanking the
                # spans only the type-gate literals still exempt the line).
                if RAW_COMPARE.search(masked):
                    why = "compares wire .error/.message against a string literal"
                elif RAW_STRINGOP.search(masked):
                    why = "string operation on a raw wire .error/.message value"
                elif RAW_CONCAT.search(masked):
                    why = "concatenates a raw wire .error/.message value via + (into/out of a string)"
                else:
                    match = CALL_ARG.search(masked)
                    if match:
                        callee = re.search(r'([A-Za-z_]\w*)\s*\(\s*[\w.]*$', match.group(0)).group(1)
                        if callee not in object_sinks:
                            why = "passes a raw wire .error/.message value to a call sink not proven to take Object (%s)" % callee
            if why is None and not GUARDED.search(line):
                # Arm (e) keeps the raw-line exemption - the sanctioned
                # choke-lift allowance (review r1: "the choke-lift exemption
                # can keep raw-line").
                if RAW_READ.search(code):
                    why = "raw wire .error/.message read/return (unguarded lift into a variable)"
            if why is None:
                continue
            problems.append(f"  {rel}:{num} - CHECK43: {why}: {line.strip()[:80]}")

# R2 - the cure choke must be the shipped code, not a memory.
util_path = os.path.join(repo, "source", "lib", "Utilities.brs")
if os.path.exists(util_path):
    util = open(util_path, encoding="utf-8", errors="replace").read()
    if not re.search(r"function\s+SafeErrorMessage\(\s*value\s+as\s+Object", util):
        problems.append("  source/lib/Utilities.brs - CHECK43 R2: SafeErrorMessage(value as Object) is gone")
    if not re.search(r"function\s+WireErrorMessageMax\(\)\s*as\s*Integer[\s\S]{0,80}?\breturn\s+300\b", util):
        problems.append("  source/lib/Utilities.brs - CHECK43 R2: WireErrorMessageMax() cap pin (300) moved or gone")

at_path = os.path.join(repo, "components", "ApiTask.brs")
if os.path.exists(at_path):
    at = open(at_path, encoding="utf-8", errors="replace").read()
    if not re.search(r"function\s+WireErrorPresent\(", at):
        problems.append("  components/ApiTask.brs - CHECK43 R2: WireErrorPresent() is gone")
    body = re.search(r"function\s+DeriveResponseError\b[\s\S]*?\bend\s+function", at)
    if body is None or "SafeErrorMessage(" not in body.group(0):
        problems.append("  components/ApiTask.brs - CHECK43 R2: DeriveResponseError no longer routes through SafeErrorMessage")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK43: %d unguarded wire-text site(s) / broken choke pin(s)" % len(problems))
    sys.exit(1)

print("  CHECK43: all wire .error/.message reads across %d .brs files are type-guarded at the" % scanned)
print("           sink (SafeErrorMessage/WireErrorPresent/WireErrorText/roString-type-gate),")
print("           m.top-typed, or an `as Object` call sink derived from the tree itself;")
print("           no path exemptions; choke pins live")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 44: the version header and its guards complete to the WebSocket/relay dials (M-ROKU-11 completion) ==="
# CHECK42 (M-ROKU-11) wired the three ApiClient REST send sites. Two dial
# families were still version-blind: the SyncPlay :8097 WebSocket handshake
# (SyncPlayTask) and the hub relay (HubCommandTask's token-mint POST plus its
# handshake map). Task-thread components do not see AppContext (RSG component
# scopes), so the dials ride a zero-dependency leaf, ProtocolChannelVersion(),
# defined in source/lib/SyncPlayProtocol.brs — a file both task XMLs already
# include. The same landing left raw `X.error` wire lifts: the contract says
# {error: string} but a hostile body can answer {"error":{"code":1}}, and the
# raw member reaching a String compare/concat/sink is a BrightScript type
# mismatch. Those lifts now route through WireErrorText, a two-required-arg
# guard (optional params are not BrightScript — bsc BS1002). Rules keep every
# claim load-bearing in both directions:
#   R1 RELAY-MINT LAW: HubCommandTask sends AddHeader("X-Phlix-Client-Version",
#      ProtocolChannelVersion()) on the mint POST and its handshake map carries
#      the same value (comment-masked code).
#   R2 SYNCPLAY-DIAL LAW: SyncPlayTask's WaitForConnect builds extraHeaders
#      with the version unconditionally — the stamp line must precede the
#      Sec-WebSocket-Protocol AddReplace branch (an offer-conditional header
#      is the theater this rule kills).
#   R3 LEAF LAW (scope defect guard): ProtocolChannelVersion() is defined in
#      SyncPlayProtocol.brs over roAppInfo.GetVersion() with the invalid/empty
#      degradation to "unknown", and neither the leaf file nor either task
#      component may reference GetChannelVersion( or ChannelInfo( — an
#      AppContext call from a task compiles clean and dies at runtime.
#   R4 WIRE-LIFT GUARD: ApiClient defines WireErrorText(value as Object,
#      fallback as String) with BOTH args required; the cured raw lifts stay
#      cured (no `= data.error` / `= payload.error` / `= env.error` in code),
#      the restoreSession transport chain is guarded end-to-end, and PhlixApp's
#      boot-failure reason rides the guard.
#   R5 DOCS LAW: docs/debugging.md names the dial coverage — the header, both
#      task files and the leaf must appear; docs that under-claim shipped
#      behavior are the landing debt this rule pins.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

AC = "source/lib/ApiClient.brs"
MINT = "components/HubCommandTask.brs"
SYNC = "components/SyncPlayTask.brs"
PROTO = "source/lib/SyncPlayProtocol.brs"
PA = "components/PhlixApp.brs"
DOC = "docs/debugging.md"
HEADER = "X-Phlix-Client-Version"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK44: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(code):
    out = []
    for line in code.splitlines():
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        out.append(line)
    return "\n".join(out)


# ---- R1 relay mint POST + handshake map -------------------------------
mint = read(MINT)
if mint is not None:
    body = mask(mint)
    if f'AddHeader("{HEADER}", ProtocolChannelVersion())' not in body:
        problems.append(
            f"  {MINT} - CHECK44 R1: the relay-token mint no longer sends "
            f'AddHeader("{HEADER}", ProtocolChannelVersion()) — the hub relay went '
            "version-blind again"
        )
    maps = body.count(f'"{HEADER}": ProtocolChannelVersion()')
    if maps != 1:
        problems.append(
            f"  {MINT} - CHECK44 R1: expected exactly 1 handshake map carrying "
            f'"{HEADER}" via ProtocolChannelVersion(), found {maps}'
        )

# ---- R2 SyncPlay dial stamp is unconditional ---------------------------
sync = read(SYNC)
if sync is not None:
    body = mask(sync)
    stamp = body.find(f'extraHeaders = {{ "{HEADER}": ProtocolChannelVersion() }}')
    offer = body.find('extraHeaders.AddReplace("Sec-WebSocket-Protocol"')
    if stamp < 0:
        problems.append(
            f"  {SYNC} - CHECK44 R2: WaitForConnect no longer builds extraHeaders "
            f'unconditionally with "{HEADER}" — the SyncPlay dial went version-blind '
            "(or the stamp moved inside a branch: offer-conditional disclosure is "
            "the theater this rule kills)"
        )
    elif offer >= 0 and stamp > offer:
        problems.append(
            f"  {SYNC} - CHECK44 R2: the version stamp no longer precedes the "
            "Sec-WebSocket-Protocol branch — restore the always-on order"
        )

# ---- R3 leaf law + scope defect guard -----------------------------------
proto = read(PROTO)
if proto is not None:
    m = re.search(r"function ProtocolChannelVersion\(\) as String\n(.*?)\nend function", proto, re.S)
    if not m:
        problems.append(
            f"  {PROTO} - CHECK44 R3: ProtocolChannelVersion() definition missing — "
            "the task-thread dials have no AppContext-free source"
        )
    else:
        leaf = m.group(1)
        if 'CreateObject("roAppInfo")' not in leaf or "GetVersion()" not in leaf:
            problems.append(
                f"  {PROTO} - CHECK44 R3: ProtocolChannelVersion() no longer derives "
                "from roAppInfo.GetVersion() — the value must come from firmware, "
                "never a literal or a config hop"
            )
        if '"unknown"' not in leaf:
            problems.append(
                f"  {PROTO} - CHECK44 R3: ProtocolChannelVersion() lost its "
                'invalid/empty degradation to "unknown"'
            )
    for path, code in ((PROTO, proto), (MINT, mint), (SYNC, sync)):
        if code is None:
            continue
        body = mask(code)
        for bad in ("GetChannelVersion(", "ChannelInfo("):
            if bad in body:
                problems.append(
                    f"  {path} - CHECK44 R3: references AppContext symbol {bad} — "
                    "task scopes do not load AppContext; the call compiles clean "
                    "and dies at runtime (this exact defect was caught pre-landing)"
                )

# ---- R4 wire-lift guard -------------------------------------------------
ac = read(AC)
if ac is not None:
    body = mask(ac)
    if not re.search(r"function WireErrorText\(value as Object, fallback as String\) as String", body):
        problems.append(
            f"  {AC} - CHECK44 R4: the WireErrorText guard is missing or its "
            "signature drifted (two REQUIRED args are deliberate — BrightScript "
            "has no default parameters, bsc rejects them with BS1002)"
        )
    for raw in ("= data.error", "= payload.error", "= env.error"):
        if raw in body:
            problems.append(
                f"  {AC} - CHECK44 R4: raw wire lift `{raw}` is back — a hostile "
                "non-String error member reaching a String sink is a runtime type "
                "mismatch; route every lift through WireErrorText"
            )
    if "IsTransportReason(env.error)" in body:
        problems.append(
            f"  {AC} - CHECK44 R4: the transport chain lifted env.error straight "
            "into IsTransportReason (as String param) — use the guarded transportReason"
        )
    if "WireErrorText(env.error" not in body or "IsTransportReason(transportReason)" not in body:
        problems.append(
            f"  {AC} - CHECK44 R4: restoreSession's transport chain is no longer "
            "guarded end-to-end (guard once into transportReason, chain on it)"
        )
    if body.count("WireErrorText(data.error") + body.count("WireErrorText(payload.error") != 2:
        problems.append(
            f"  {AC} - CHECK44 R4: the two http_-bucket error arms no longer both "
            "ride WireErrorText (found "
            f"{body.count('WireErrorText(data.error')}+{body.count('WireErrorText(payload.error')})"
        )
pa = read(PA)
if pa is not None and "WireErrorText(result.error" not in mask(pa):
    problems.append(
        f"  {PA} - CHECK44 R4: the boot-failure reason lift stopped riding "
        "WireErrorText — every consumer below treats it as String"
    )

# ---- R5 docs tell the shipped truth ---------------------------------------
doc = read(DOC)
if doc is not None:
    for tok in (HEADER, "HubCommandTask", "SyncPlayTask", "ProtocolChannelVersion"):
        if tok not in doc:
            problems.append(
                f"  {DOC} - CHECK44 R5: the support story no longer names `{tok}` — "
                "the WebSocket/relay dials carry the header in code and docs/debugging.md "
                "is the only place an operator learns the coverage; under-claiming docs "
                "are landing debt"
            )

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK44: %d dial-completion/wire-lift problem(s)" % len(problems))
    sys.exit(1)

print("  CHECK44: relay mint + handshake map and the SyncPlay dial carry")
print("           X-Phlix-Client-Version from the AppContext-free roAppInfo leaf;")
print("           the leaf degrades to \"unknown\" and no task scope references")
print("           GetChannelVersion/ChannelInfo; WireErrorText guards every wire")
print("           error lift with two required args and the raw lifts stay extinct;")
print("           docs/debugging.md names the full dial coverage")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 45: untrusted mediaId is shape-gated before play (M-ROKU-13) ==="
# Hostile-input law for content ids (review roku__exploiter M2, fix M-ROKU-13).
# The hub-relay pending_command frames ride a PLAINTEXT socket (hostile hub or
# LAN injector) and ECP/launch deep-link args are attacker-settable; the era
# fed their mediaId into ApiClient's "/media/" + itemId raw concatenation with
# only an invalid/"" check (relay) or a printable-minus-"&" checker (launch),
# so "x?profile=1" / "x#frag" / "x/../../admin/users" turned the victim's TV
# into an arbitrary Bearer-authenticated GET engine. Cure: the canonical
# allowlist guard IsSafeContentId() + ContentIdMaxLen() (source/lib/
# Utilities.brs), applied at EVERY entry (source/main.brs
# ValidateDeepLinkContentId delegates; OnPendingHubCommand ignores hostile
# frames) and at the single play choke (ProcessDeepLink fails visible BEFORE
# any request is built). CHECK44 (M-ROKU-11 completion) took the previous
# number; CHECK45 keeps this wiring load-bearing in both directions:
#   R1  the guard family is live: IsSafeContentId(contentId as Dynamic) as
#       Boolean over the [A-Za-z0-9_-] allowlist (range + '-'/'_' code
#       literals — re-fattening to a printable-only sweep reddens), and
#       ContentIdMaxLen() returns the pinned 255 (cap BEFORE the per-byte
#       loop).
#   R2  OnPendingHubCommand (or, MN-14 era, its DispatchPendingHubCommand
#       single-command path behind the batch unwrap) guards data.mediaId
#       through IsSafeContentId BEFORE
#       it calls ProcessDeepLink, and the raw invalid/"" era form is extinct.
#   R3  ProcessDeepLink gates contentId BEFORE the getItem request is built
#       (ordering law) and rejects VISIBLE (ShowContentNotFoundDialog) — the
#       choke cannot be quietly gutted.
#   R4  ValidateDeepLinkContentId delegates to the canonical guard; the
#       printable-era loop may not return.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

UTIL = "source/lib/Utilities.brs"
PA = "components/PhlixApp.brs"
MAIN = "source/main.brs"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK45: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(code):
    out = []
    for line in code.splitlines():
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        out.append(line)
    return "\n".join(out)


# ---- R1 the canonical guard family is live, allowlist intact -----------
util = read(UTIL)
if util is not None:
    if not re.search(r"function\s+IsSafeContentId\(\s*contentId\s+as\s+Dynamic\s*\)\s*as\s+Boolean", util):
        problems.append(f"  {UTIL} - CHECK45 R1: IsSafeContentId(contentId as Dynamic) as Boolean is gone")
    body = re.search(r"function\s+IsSafeContentId\b[\s\S]*?\bend\s+function", util)
    if body is None:
        problems.append(f"  {UTIL} - CHECK45 R1: IsSafeContentId body is gone")
    else:
        text = body.group(0)
        if not re.search(r"ContentIdMaxLen\(\)", text):
            problems.append(f"  {UTIL} - CHECK45 R1: the guard no longer consults the ContentIdMaxLen() cap")
        for tok, why in (
            (r"c >= 48 and c <= 57", "lost the 0-9 range"),
            (r"c >= 65 and c <= 90", "lost the A-Z range"),
            (r"c >= 97 and c <= 122", "lost the a-z range"),
            (r"c = 45", "lost the '-' allow"),
            (r"c = 95", "lost the '_' allow"),
        ):
            if not re.search(tok, text):
                problems.append(f"  {UTIL} - CHECK45 R1: the [A-Za-z0-9_-] allowlist {why} — the guard was re-fattened")
        if re.search(r"c < 32 or c > 126", text):
            problems.append(f"  {UTIL} - CHECK45 R1: a printable-only sweep is back inside IsSafeContentId (path bytes / ? # . would re-enter)")
    if not re.search(r"function\s+ContentIdMaxLen\(\)\s*as\s*Integer[\s\S]{0,80}?\breturn\s+255\b", util):
        problems.append(f"  {UTIL} - CHECK45 R1: ContentIdMaxLen() cap pin (255) moved or gone")

# ---- R2+R3 relay entry guard + play choke (PhlixApp) --------------------
pa = read(PA)
if pa is not None:
    code = mask(pa)

    body = re.search(r"sub\s+OnPendingHubCommand\b[\s\S]*?\bend\s+sub", code)
    dispatch = re.search(r"sub\s+DispatchPendingHubCommand\b[\s\S]*?\bend\s+sub", code)
    if body is None and dispatch is None:
        problems.append(f"  {PA} - CHECK45 R2: OnPendingHubCommand is gone")
    else:
        text = body.group(0) if body is not None else dispatch.group(0)
        # MN-14 era (disclosed extension): the single-command path moved
        # behind the batch unwrap; follow it so the guard law keeps teeth.
        if "DispatchPendingHubCommand(" in text and dispatch is not None:
            text = dispatch.group(0)
        if re.search(r'data\.mediaId\s*=\s*invalid\b|data\.mediaId\s*=\s*""', text):
            problems.append(f"  {PA} - CHECK45 R2: the raw `data.mediaId = invalid or = \"\"` era form is back")
        gi = text.find("IsSafeContentId(data.mediaId)")
        pi = text.find("ProcessDeepLink()")
        if gi < 0:
            problems.append(f"  {PA} - CHECK45 R2: the pending_command path (OnPendingHubCommand / its MN-14 dispatcher) no longer gates data.mediaId through IsSafeContentId")
        elif pi >= 0 and gi > pi:
            problems.append(f"  {PA} - CHECK45 R2: the mediaId guard moved AFTER the ProcessDeepLink() call (ordering law)")

    body = re.search(r"sub\s+ProcessDeepLink\b[\s\S]*?\bend\s+sub", code)
    if body is None:
        problems.append(f"  {PA} - CHECK45 R3: ProcessDeepLink is gone")
    else:
        text = body.group(0)
        gi = text.find("IsSafeContentId(contentId)")
        ri = text.find('op: "getItem"')
        if gi < 0:
            problems.append(f"  {PA} - CHECK45 R3: ProcessDeepLink no longer gates contentId through IsSafeContentId (the play choke is gone)")
        elif ri >= 0 and gi > ri:
            problems.append(f"  {PA} - CHECK45 R3: the choke moved AFTER the getItem request is built — a rejected id would leave the TV")
        if "ShowContentNotFoundDialog(" not in text:
            problems.append(f"  {PA} - CHECK45 R3: the choke no longer fails VISIBLE (ShowContentNotFoundDialog)")

# ---- R4 the launch entry delegates (single canonical source) ------------
main = read(MAIN)
if main is not None:
    code = mask(main)
    body = re.search(r"function\s+ValidateDeepLinkContentId\b[\s\S]*?\bend\s+function", code)
    if body is None:
        problems.append(f"  {MAIN} - CHECK45 R4: ValidateDeepLinkContentId is gone")
    else:
        text = body.group(0)
        if "IsSafeContentId(" not in text:
            problems.append(f"  {MAIN} - CHECK45 R4: ValidateDeepLinkContentId no longer delegates to the canonical IsSafeContentId")
        if re.search(r"c < 32 or c > 126", text):
            problems.append(f"  {MAIN} - CHECK45 R4: the printable-era loop is back (path characters / ? # . would re-enter)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK45: %d content-id guard site(s) ungated or choke pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK45: content-id allowlist (IsSafeContentId / cap 255) live; the relay entry and")
print("           the play choke gate mediaId BEFORE any request leaves the TV (reject is")
print("           visible, ordering pinned); the launch entry delegates to the canonical guard")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 46: the SyncPlay dial refuses TLS origins and proves the handshake (M-ROKU-14) ==="
# Credential-custody law for the :8097 SyncPlay WebSocket (review
# roku__exploiter M3, fix M-ROKU-14). PlayerScene BuildSyncPlayWsParts used to
# read the MAIN ACCOUNT JWT and hand it to SyncPlayTask regardless of the
# connected server origin's scheme, and SyncPlayTask accepted ANY "101"
# status line without checking Sec-WebSocket-Accept — so on an https origin a
# passive LAN sniffer captured a TLS-established account credential (the hub
# relay path had already learned this lesson and mints scoped relay tokens;
# the direct dial had not). Cure, in two halves:
#   R1  origin refusal: SyncPlayWsRefusedForOrigin(serverUrl as String) as
#       Boolean (source/lib/Utilities.brs — pure, LCase+Trim, https:// → true)
#       is called INSIDE BuildSyncPlayWsParts BEFORE the credential is read
#       (ordering pin vs GetStorage().get("auth_token")) and its refusal
#       returns invalid (the choke); ConnectSyncTask renders the honest
#       refusal line via Translate("syncplay_status_tls_refused").
#   R2  handshake proof: the RFC6455 §1.3 magic GUID constant is live, the
#       fail-closed trio (SecWebSocketAcceptValue / ExpectedSecWebSocketAccept
#       / VerifyHandshakeAccept) exists in source/lib/SyncPlayProtocol.brs
#       with the accept parser's blank-line stop (the header scan must end at
#       the first Trim-empty line — the CRLF handshake terminator is invisible
#       to a nl+nl search, so without the stop a body impersonates a header:
#       review M-ROKU-14 r1 MAJOR-1),
#       SyncPlayTask calls VerifyHandshakeAccept AFTER the HandshakeAccepted
#       status gate (both required), tags the failure via m.wsAcceptFailed,
#       and RunSocket reports it as the census code local.ws_accept_invalid —
#       emitted only under that gate, never as a bare fallback. The era's
#       "accept the 101 unverified" claims are extinct in code AND prose.
#   R3  census + catalogs: local.ws_accept_invalid is a SyncPlayLocalErrorCodes()
#       member (Check 23 then enforces call-site/normalization law), and ALL
#       seven catalogs carry errors.local_ws_accept_invalid + syncplay.
#       status_tls_refused (Check 21 keeps the sides parity-pinned).
#   R4  harness teeth: tests/unit/SyncPlayWsTls.test.brs pins the truth table,
#       the header parser (incl. the body-spoof guard), the hex-shape gate,
#       the fail-closed arms, and the RFC6455 §1.3 vector on-device — the
#       leg below names all five Test subs.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

UTIL = "source/lib/Utilities.brs"
PROTO = "source/lib/SyncPlayProtocol.brs"
PS = "components/PlayerScene.brs"
TASK = "components/SyncPlayTask.brs"
README = "README.md"
TEST = "tests/unit/SyncPlayWsTls.test.brs"
LOCALES = ["en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR"]
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK46: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(code):
    out = []
    for line in code.splitlines():
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        out.append(line)
    return "\n".join(out)


def body(code, kind, name):
    m = re.search(rf"{kind}\s+{name}\b[\s\S]*?\bend\s+{kind}\b", code)
    return m.group(0) if m else None


# ---- R1 origin refusal (predicate live, choke ordered) -----------------
util = read(UTIL)
if util is not None:
    pred = body(util, "function", "SyncPlayWsRefusedForOrigin")
    if pred is None:
        problems.append(f"  {UTIL} - CHECK46 R1: SyncPlayWsRefusedForOrigin is gone")
    else:
        if not re.search(r"SyncPlayWsRefusedForOrigin\(\s*serverUrl\s+as\s+String\s*\)\s*as\s+Boolean", pred):
            problems.append(f"  {UTIL} - CHECK46 R1: the predicate signature moved off (serverUrl as String) as Boolean")
        if not (re.search(r"LCase\(", pred) and re.search(r"Trim\(", pred) and re.search(r'=\s*"https://"', pred)):
            problems.append(f"  {UTIL} - CHECK46 R1: the predicate no longer matches a case-insensitive https:// prefix")
ps = read(PS)
if ps is not None:
    code = mask(ps)
    b = body(code, "function", "BuildSyncPlayWsParts")
    if b is None:
        problems.append(f"  {PS} - CHECK46 R1: BuildSyncPlayWsParts is gone")
    else:
        gi = b.find("SyncPlayWsRefusedForOrigin(serverUrl)")
        ti = b.find('GetStorage().get("auth_token")')
        if gi < 0:
            problems.append(f"  {PS} - CHECK46 R1: BuildSyncPlayWsParts no longer consults SyncPlayWsRefusedForOrigin")
        if not re.search(r"SyncPlayWsRefusedForOrigin\(serverUrl\)\s*then\s+return\s+invalid", b):
            problems.append(f"  {PS} - CHECK46 R1: the refusal no longer returns invalid (the choke was softened)")
        if ti >= 0 and gi >= ti:
            problems.append(f"  {PS} - CHECK46 R1: the origin refusal moved AFTER the auth_token read (ordering law)")
    b = body(code, "sub", "ConnectSyncTask")
    if b is None or 'Translate("syncplay_status_tls_refused")' not in b:
        problems.append(f"  {PS} - CHECK46 R1: ConnectSyncTask no longer renders the honest TLS-refusal line")

# ---- R2 handshake proof (trio live, ordered, fail-closed; claims dead) --
proto = read(PROTO)
if proto is not None:
    pcode = mask(proto)
    if not re.search(rf"WS_ACCEPT_GUID:\s*\"{GUID}\"", proto):
        problems.append(f"  {PROTO} - CHECK46 R2: the RFC6455 magic GUID constant is gone or altered")

    def member(name):
        m = re.search(rf"{name}:\s*function\b[\s\S]*?end function", pcode)
        return m.group(0) if m else None

    trio = {
        "SecWebSocketAcceptValue": r"if responseText = invalid or responseText = \"\" then return \"\"",
        "ExpectedSecWebSocketAccept": r"if evp\.Setup\(\"sha1\"\) <> 0 then return \"\"",
        "VerifyHandshakeAccept": r"return got = expected",
    }
    for name, teeth in trio.items():
        b = member(name)
        if b is None:
            problems.append(f"  {PROTO} - CHECK46 R2: {name} is gone (the proof cannot be vacuous)")
        elif not re.search(teeth, b):
            problems.append(f"  {PROTO} - CHECK46 R2: {name} lost its fail-closed shape ({teeth})")
    b = member("SecWebSocketAcceptValue")
    if b is not None and 'if cut = "" then exit for' not in b:
        problems.append(f"  {PROTO} - CHECK46 R2: SecWebSocketAcceptValue no longer stops the header scan at the first blank line — a body line can impersonate a header again (the CRLF-blind nl+nl truncation era, review M-ROKU-14 r1 MAJOR-1)")
    b = member("VerifyHandshakeAccept")
    if b is not None:
        for guard in ('if offered = "" then return false', 'if got = "" then return false', 'if expected = "" then return false'):
            if guard not in b:
                problems.append(f"  {PROTO} - CHECK46 R2: VerifyHandshakeAccept missing fail-closed guard `{guard}`")
task = read(TASK)
if task is not None:
    tcode = mask(task)
    b = body(tcode, "function", "WaitForConnect")
    if b is None:
        problems.append(f"  {TASK} - CHECK46 R2: WaitForConnect is gone")
    else:
        hi = b.find("HandshakeAccepted(headerText)")
        vi = b.find("VerifyHandshakeAccept(headerText, keyB64)")
        if vi < 0:
            problems.append(f"  {TASK} - CHECK46 R2: WaitForConnect never verifies Sec-WebSocket-Accept")
        elif hi >= 0 and vi < hi:
            problems.append(f"  {TASK} - CHECK46 R2: VerifyHandshakeAccept moved BEFORE the HandshakeAccepted status gate (ordering law)")
        if "m.wsAcceptFailed = true" not in b:
            problems.append(f"  {TASK} - CHECK46 R2: the accept failure is no longer tagged (m.wsAcceptFailed)")
    b = body(tcode, "sub", "RunSocket")
    if b is None:
        problems.append(f"  {TASK} - CHECK46 R2: RunSocket is gone")
    else:
        m = re.search(r"if m\.wsAcceptFailed then[\s\S]*?EmitError\(\"local\.ws_accept_invalid\"\)", b)
        if m is None:
            problems.append(f"  {TASK} - CHECK46 R2: local.ws_accept_invalid is not emitted under the m.wsAcceptFailed gate")

# ---- R2-prose: the era's skip claims are extinct ------------------------
# M-ROKU-22 rotation: the same extinct-claims family also convicts the
# platform-misclaim assertions this item's review named ("`wss://` is
# impossible", "Roku can't do TLS"). They are FALSE as stated —
# roSecureSocket is the platform's TLS client socket and this very channel
# does TLS for REST on https origins — and the claim-shape mattered: it
# framed the M14 refusal law as the only conceivable posture. The shipped
# truth is: ws:// only because THIS BUILD rides roStreamSocket; wss is a
# deferred option; custody rests on refusal + consent + accept-proof.
for path in (PROTO, TASK, README):
    text = read(path)
    if text is None:
        continue
    if re.search(r"do NOT verify the[\s\S]{0,80}?Sec-WebSocket-Accept", text):
        problems.append(f"  {path} - CHECK46 R2: the era's \"do NOT verify the Sec-WebSocket-Accept\" claim is back")
    if "deferred - see worklog" in text and "Sec-WebSocket-Accept" in text.split("deferred - see worklog")[1][:120]:
        problems.append(f"  {path} - CHECK46 R2: accept verification is described as deferred again")
    if re.search(r"`wss://`\s+is\s+impossible", text):
        problems.append(f"  {path} - CHECK46 R2: the M-ROKU-22 platform-misclaim (wss stated as impossible) is back — wss is UNIMPLEMENTED (a deferred roSecureSocket arm), not impossible; scoped-true transport sentences (\"roStreamSocket has no TLS\") are unaffected")
    if re.search(r"Roku\s+can(?:'?t|not)\s+do\s+TLS", text):
        problems.append(f"  {path} - CHECK46 R2: the M-ROKU-22 platform-misclaim (Roku stated unable to do TLS) is back — this channel does TLS via roUrlTransfer + ca-bundle on every https origin")

# ---- R3 census membership + all seven catalogs -------------------------
if util is not None:
    b = body(util, "function", "SyncPlayLocalErrorCodes")
    if b is None or '"local.ws_accept_invalid"' not in b:
        problems.append(f"  {UTIL} - CHECK46 R3: local.ws_accept_invalid left the local.* census (Check 23 law starts here)")
for L in LOCALES:
    path = f"locale/{L}/strings.json"
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK46 R3: unreadable: {err}")
        continue
    if cat.get("errors", {}).get("local_ws_accept_invalid", "") == "":
        problems.append(f"  {path} - CHECK46 R3: errors.local_ws_accept_invalid missing (the refusal must be SPEAKABLE)")
    if cat.get("syncplay", {}).get("status_tls_refused", "") == "":
        problems.append(f"  {path} - CHECK46 R3: syncplay.status_tls_refused missing (the refusal status must exist)")

# ---- R4 the device harness pins the law ---------------------------------
test = read(TEST)
if test is None:
    problems.append(f"  {TEST} - CHECK46 R4: the M-ROKU-14 unit suite vanished")
else:
    for name in ("TestSyncPlayWsRefusedForOriginTruthTable", "TestSecWebSocketAcceptValueParsing", "TestIsHex40Shape", "TestVerifyHandshakeAcceptFailClosed", "TestRfc6455AcceptVector"):
        if f"sub {name}(" not in test:
            problems.append(f"  {TEST} - CHECK46 R4: {name} is gone")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK46: %d SyncPlay origin/accept pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK46: https origins refuse the plaintext :8097 dial BEFORE the JWT is read")
print("           (ordered choke + honest status line); the 101 is additionally proof-checked")
print("           against the RFC6455 Sec-WebSocket-Accept hash (fail-closed trio, ordering")
print("           pinned); local.ws_accept_invalid is census'd and speakable in all seven")
print("           catalogs; the era's unverified-accept claims AND the wss-impossibility")
print("           platform-misclaims (M-ROKU-22 rotation) are extinct in code and prose")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 47: bootstrap scenes never consume Back; the boot-retry button is focusable (M-ROKU-16) ==="
# Bootstrap Back law (review roku__gameux M1, fix M-ROKU-16). ConnectScene,
# LoginScene and ServerPickerScene each shipped a deliberate Back trap
# (OnKeyEvent consumed the press with handled = true — comments said "Don't
# allow backing out"). A signed-out user — whose FIRST screen is one of these
# three — could not leave the channel except via Home or power: certification
# requires Back to be never-disabled, and docs/navigation.md's own root-back
# law (M-ROKU-01/CHECK31) already promises "One Back from Home — or from any
# other bootstrap screen — exits cleanly". The traps made that claim false.
# Cure: the three scenes no longer consume anything (their OnKeyEvent bodies
# carry NO "back" branch; the press bubbles to PhlixApp.OnKeyEvent, whose
# stack-bottom arm raises exitChannel and ends main()). Compounding half of
# the finding: ShowBootError displayed the Retry button without ever
# SetFocus'ing it — buttonSelected needs focus + OK, so after a 20s boot
# timeout the visible control was unpressable — and it re-ObserveField'd the
# button on every error (m5: duplicate handlers). Cure: the observer is wired
# exactly once in Init; ShowBootError focuses the button.
#   R1  no bootstrap-scene OnKeyEvent body (comments masked) mentions "back"
#       at all — HomeScene included, since its back pass-through is the
#       precedent the cure mirrors; a re-grown trap on ANY of the four
#       dead-ends users the same way.
#   R2  PhlixApp boot chrome: ShowBootError focuses bootRetryButton and
#       performs no ObserveField (the re-observe era is extinct); Init owns
#       the single buttonSelected wiring.
#   R3  docs truth: navigation.md names the bootstrap no-consume law by
#       CHECK47, and certification.md's 3.3 row carries M-ROKU-16 (the
#       shipped scope now covers the bootstrap screens, not just the root).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

SCENES = [
    "components/ConnectScene.brs",
    "components/LoginScene.brs",
    "components/ServerPickerScene.brs",
    "components/HomeScene.brs",
]
APP = "components/PhlixApp.brs"
NAV = "docs/navigation.md"
CERT = "docs/certification.md"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK47: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(code):
    out = []
    for line in code.splitlines():
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        out.append(line)
    return "\n".join(out)


def body(code, kind, name):
    m = re.search(rf"{kind}\s+{name}\b[\s\S]*?\bend\s+{kind}\b", code)
    return m.group(0) if m else None


# ---- R1 no bootstrap scene consumes Back -------------------------------
for path in SCENES:
    src = read(path)
    if src is None:
        continue
    b = body(mask(src), "function", "OnKeyEvent")
    if b is None:
        # The handler may also be deleted entirely (also a pass-through).
        if body(mask(src), "sub", "OnKeyEvent") is not None:
            problems.append(f"  {path} - CHECK47 R1: sub-form OnKeyEvent found — the pin parses the function form")
        continue
    if re.search(r'key\s*=\s*"back"', b) or re.search(r'"back"\s*=\s*key', b):
        problems.append(
            f'  {path} - CHECK47 R1: OnKeyEvent branches on "back" again — bootstrap Back must bubble '
            "to PhlixApp.OnKeyEvent (the CHECK31 exit arm); a scene-level back branch is the trap era "
            "(review roku__gameux M1)"
        )

# ---- R2 boot-retry chrome: focused, wired once --------------------------
app = read(APP)
if app is not None:
    acode = mask(app)
    b = body(acode, "sub", "ShowBootError")
    if b is None:
        problems.append(f"  {APP} - CHECK47 R2: ShowBootError is gone")
    else:
        if "m.bootRetryButton.SetFocus(true)" not in b:
            problems.append(
                "  components/PhlixApp.brs - CHECK47 R2: ShowBootError no longer SetFocus'es the retry "
                "button — an unfocused Button cannot raise buttonSelected (visible-but-unpressable era)"
            )
        if "ObserveField(" in b:
            problems.append(
                "  components/PhlixApp.brs - CHECK47 R2: ShowBootError observes fields again — the "
                "per-error re-observe accumulated duplicate buttonSelected handlers (m5); Init owns the wiring"
            )
    b = body(acode, "sub", "Init")
    if b is None:
        problems.append(f"  {APP} - CHECK47 R2: Init is gone")
    else:
        if 'm.bootRetryButton.ObserveField("buttonSelected", "OnBootRetryButton")' not in b:
            problems.append(
                "  components/PhlixApp.brs - CHECK47 R2: Init no longer wires bootRetryButton "
                "buttonSelected exactly once"
            )

# ---- R3 docs truth ------------------------------------------------------
nav = read(NAV)
if nav is not None:
    if "CHECK47" not in nav:
        problems.append(f"  {NAV} - CHECK47 R3: navigation.md does not name the bootstrap no-consume law (CHECK47)")
cert = read(CERT)
if cert is not None:
    row = None
    for line in cert.splitlines():
        if line.startswith("| 3.3 "):
            row = line
            break
    if row is None:
        problems.append(f"  {CERT} - CHECK47 R3: certification.md lost its 3.3 Back row")
    elif "M-ROKU-16" not in row:
        problems.append(f"  {CERT} - CHECK47 R3: certification.md 3.3 still claims the root alone (M-ROKU-16 scope missing)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK47: %d bootstrap-Back/boot-retry pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK47: bootstrap scenes never consume Back (all four bubble to the CHECK31 exit")
print("           arm); the boot-retry button is focused on display and its buttonSelected")
print("           observer is wired once in Init; navigation.md and certification.md carry")
print("           the shipped scope")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 48: connect/pair credential custody - redirect law + cleartext consent (M-ROKU-15) ==="
# CREDENTIAL CUSTODY LAW (M-ROKU-15, review roku__exploiter M4): the Connect/
# pair flow let the USER choose the server origin (a typed URL was kept as-is
# even when explicitly http://, and "Connect anyway" persisted whatever
# survived normalization after a FAILED probe), while the credentialed
# ApiClient send sites left redirect policy to the firmware's auto-follow - so
# a login password posted in plaintext JSON, or a Bearer token, could be
# 3xx-walked to a host the user never chose. Cure in three legs, pinned
# statically below, with every pure leaf pinned by
# tests/unit/RedirectCustody.test.brs on-device:
#   R1  redirect custody: sendRaw and sendRawWithDeviceId (the login POST)
#       disable the firmware auto-follow, adjudicate every 3xx through the
#       pure-leaf trio (ResolveRedirectTarget / IsCredentialSafeRedirectHop /
#       RedirectHopLimit) and abort with a fail text naming "redirect" (the
#       redirect_refused bucket) unless the hop is same-origin or the
#       same-host http->https upgrade; resolveLocation (Bearer-carrying,
#       Location-hungry) disables following so its documented "WITHOUT
#       following" contract is a guarantee, not best-effort; probeHealth
#       stays redirect-FOLLOWING by design (zero credentials ride it, and an
#       http->https /health 301 must still probe green) — but its response
#       stays size-gated like the credentialed sites (RT-034). Body-size
#       custody rides the same per-site arm: every parse site consults
#       ResponseBodyExceedsCap before materializing the ParseJSON input, so
#       an oversized hostile body (the hub-proxy path is the live threat)
#       never becomes an unbounded string-to-object explosion.
#   R2  cleartext consent: Connect() is the persist choke - when
#       ServerUrlUsesCleartextToRemoteHost says so, the shipped two-button
#       ShowErrorDialog idiom demands a LOUD OK before anything is written;
#       the server_url write-site census stays exactly one (inside
#       PersistAndGo, which the default-deny callback alone reaches);
#       LAN/loopback http stays silent - the documented home-server normal.
#   R3  single source + triangle: the scheme inference, the consent gate and
#       the hop law all read hosts through HostOfUrl/IsPrivateHostAddress
#       (NormalizeServerUrl delegates - re-rolled octet logic is how
#       "10th-street.example.com" was once misclassified); the
#       redirect_refused bucket carries its classifier arm, transport guard,
#       ladder line and catalog message x7; catalogs bump as a set (1.16.0 —
#       rotated by the review CR-2/Check74 batch: ten form-chrome keys entered
#       the set — the ParentalControls label/hint keys x9 plus the group-name
#       hint x7 — Check 74 R2's translate net cannot be satisfied without
#       them; previously 1.15.0, rotated by R-ROKU-10 (riders W10): one
#       generic-notice catalog key entered the set — the hub-mode dialog title
#       plus the chapter-picker pair now ride common_notice x7; disclosed per
#       this arm's own law).
#   R4  the device harness pins the law: tests/unit/RedirectCustody.test.brs
#       and all seven Test subs.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

UTIL = "source/lib/Utilities.brs"
AC = "source/lib/ApiClient.brs"
SCENE = "components/ConnectScene.brs"
TEST = "tests/unit/RedirectCustody.test.brs"
LOCALES = ["en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR"]

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK48: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def method_body(text, name):
    m = re.search(r"(?m)^\s*%s:\s*function\(" % re.escape(name), text)
    if m is None:
        return None
    end = text.find("\n        end function", m.end())
    return text[m.start():] if end == -1 else text[m.start():end]


def sub_body(text, name):
    m = re.search(r"(?m)^(?:sub|function)\s+%s\b[^\n]*\n(.*?)^end (?:sub|function)" % re.escape(name),
                  text, re.DOTALL)
    return m.group(0) if m else None


util = read(UTIL)
ac = read(AC)
scene = read(SCENE)

# ---- R1 send-site redirect custody ---------------------------------------
if ac is not None:
    acm = mask(ac)
    for name in ("sendRaw", "sendRawWithDeviceId"):
        b = method_body(acm, name)
        if b is None:
            problems.append(f"  {AC} - CHECK48 R1: send site `{name}` is gone — the redirect-custody census cannot run")
            continue
        if "http.EnableRedirects(false)" not in b:
            problems.append(f"  {AC} - CHECK48 R1: `{name}` no longer disables the firmware auto-follow — a Bearer/password-carrying request could be 3xx-walked to a host the user never chose (M-ROKU-15)")
        for leaf, why in (("ResolveRedirectTarget(", "a Location must be absolutized before ANY verdict"),
                          ("IsCredentialSafeRedirectHop(", "only same-origin / same-host http-then-https hops may re-send credentials"),
                          ("RedirectHopLimit()", "the manual chain must be bounded"),
                          ("ResponseBodyExceedsCap(", "every 2xx body must meet the parse cap before ParseJSON materializes it (RT-034, review roku__exploiter #8)")):
            if leaf not in b:
                problems.append(f"  {AC} - CHECK48 R1: `{name}` stopped consulting {leaf[:-1]} — {why} (M-ROKU-15)")
        if 'result.fail = "redirect refused' not in b:
            problems.append(f"  {AC} - CHECK48 R1: `{name}` no longer fails refusals through the redirect_refused text — an un-followable 3xx would surface as the old silent empty error")
    rl = method_body(acm, "resolveLocation")
    if rl is None or "http.EnableRedirects(false)" not in (rl or ""):
        problems.append(f"  {AC} - CHECK48 R1: resolveLocation (Bearer-carrying) no longer disables following — its docblock GUARANTEES the 3xx is not followed")
    ph = method_body(acm, "probeHealth")
    if ph is None:
        problems.append(f"  {AC} - CHECK48 R1: probeHealth vanished — the uncredentialed probe's follow-by-design note has no body to inspect")
    elif "EnableRedirects" in ph:
        problems.append(f"  {AC} - CHECK48 R1: probeHealth gained redirect-off mode — it carries ZERO credentials, and an http-then-https /health 301 must still probe green (M-ROKU-04 r1 issue 5 law)")
    elif "ResponseBodyExceedsCap(" not in ph:
        problems.append(f"  {AC} - CHECK48 R1: probeHealth stopped consulting ResponseBodyExceedsCap — the uncredentialed probe may follow redirects by design, but an oversized hostile /health body must still meet the parse cap before ParseJSON (RT-034)")

# ---- R1b ROK-13 credentialed-transfer census -----------------------------
# EVERY AddHeader("Authorization", ...) site under components/ + source/ must
# be in the allow-list below AND its enclosing function must disable the
# firmware auto-follow. A NEW credentialed transfer fails loud until it is
# consciously custodied and added here.
AUTH_ALLOW = {
    ("source/lib/ApiClient.brs", "sendRaw"),
    ("source/lib/ApiClient.brs", "resolveLocation"),
    ("components/HubCommandTask.brs", "MintRelayToken"),
}
FUNC_RE = re.compile(r"(?m)^\s*(?:(\w+):\s*function\(|(?:sub|function)\s+(\w+)\b)")
auth_sites = 0
for root in ("components", "source"):
    for dp, _dn, fns in os.walk(root):
        for fn in sorted(fns):
            if not fn.endswith(".brs"):
                continue
            path = os.path.join(dp, fn).replace(os.sep, "/")
            raw = read(path)
            if raw is None:
                continue
            masked = mask(raw)
            starts = [(masked.count("\n", 0, m.start()), m.group(1) or m.group(2)) for m in FUNC_RE.finditer(masked)]
            mlines = masked.split("\n")
            for site in re.finditer(r'\.AddHeader\(\s*"Authorization"', raw):
                line_start = raw.rfind("\n", 0, site.start()) + 1
                if "'" in raw[line_start:site.start()] and '"' not in raw[line_start:raw.find("'", line_start)]:
                    continue  # commented-out line
                auth_sites += 1
                site_line = raw.count("\n", 0, site.start())
                idx = -1
                for i, (pos, _nm) in enumerate(starts):
                    if pos <= site_line:
                        idx = i
                if idx < 0:
                    problems.append(f"  {path} - CHECK48 R1b: Authorization AddHeader outside any function")
                    continue
                fname = starts[idx][1]
                end = starts[idx + 1][0] if idx + 1 < len(starts) else len(mlines)
                if (path, fname) not in AUTH_ALLOW:
                    problems.append(f"  {path} - CHECK48 R1b: credentialed transfer in `{fname}` is outside the allow-list - a new Authorization-carrying send must be custodied (EnableRedirects(false) + 3xx refusal) and added to AUTH_ALLOW (ROK-13)")
                elif "EnableRedirects(false)" not in "\n".join(mlines[starts[idx][0]:end]):
                    problems.append(f"  {path} - CHECK48 R1b: `{fname}` carries Authorization but no longer disables the firmware auto-follow (ROK-13)")
if auth_sites < len(AUTH_ALLOW):
    problems.append(f"  CHECK48 R1b: census saw {auth_sites} Authorization sites, expected >= {len(AUTH_ALLOW)} - the census cannot run vacuously")
mrt = read("components/HubCommandTask.brs")
if mrt is not None:
    mb = sub_body(mask(mrt), "MintRelayToken")
    if mb is None or "ResponseBodyExceedsCap(" not in mb or "SetCertificatesFile(" not in mb:
        problems.append("  components/HubCommandTask.brs - CHECK48 R1b: MintRelayToken must meet ResponseBodyExceedsCap before ParseJSON and pin SetCertificatesFile (ROK-13)")

# ---- R2 the consent choke over the single persist site -------------------
if scene is not None:
    sc = mask(scene)
    conn = sub_body(sc, "Connect")
    if conn is None:
        problems.append(f"  {SCENE} - CHECK48 R2: the Connect() persist choke is gone")
    else:
        gate = conn.find("ServerUrlUsesCleartextToRemoteHost(")
        persist = conn.find("PersistAndGo(")
        if gate == -1:
            problems.append(f"  {SCENE} - CHECK48 R2: Connect() no longer consults ServerUrlUsesCleartextToRemoteHost — a typed http remote origin could persist silently again (the M15 cleartext class)")
        elif persist != -1 and gate > persist:
            problems.append(f"  {SCENE} - CHECK48 R2: the consent gate must be consulted BEFORE PersistAndGo — after-the-fact dialogs custody nothing")
        if 'GetStorage().set(' in conn:
            problems.append(f"  {SCENE} - CHECK48 R2: Connect() itself writes storage again — the write must live behind the gate, in PersistAndGo")
        if "ShowErrorDialog(" not in conn:
            problems.append(f"  {SCENE} - CHECK48 R2: the consent dialog call vanished — the gate would drop the user's request with no say at all")
        for key in ("connect_cleartext_title", "connect_cleartext_message", "connect_cleartext_continue", "common_cancel"):
            if f'Translate("{key}")' not in conn:
                problems.append(f'  {SCENE} - CHECK48 R2: the dialog lost literal Translate("{key}") — CHECK20/21 keep the labels cataloged, never inline')
    cb = sub_body(sc, "OnCleartextConsentChoice")
    if cb is None or "if index <> 0 then return" not in cb:
        problems.append(f"  {SCENE} - CHECK48 R2: the consent callback or its default-deny (index <> 0) guard is gone — only the explicit continue may persist")
    if "PersistAndGo(" not in (cb or ""):
        problems.append(f"  {SCENE} - CHECK48 R2: the confirmed arm no longer reaches PersistAndGo — the dialog would promise a connect it never performs")

# server_url write-site census: exactly one across the shipped .brs corpus.
writes = 0
for scan_dir in ("source", "components"):
    for root, dirs, names in os.walk(scan_dir):
        for name in sorted(names):
            if name.endswith(".brs"):
                path = os.path.join(root, name)
                code = mask(read(path) or "")
                n = code.count('GetStorage().set("server_url"')
                if n:
                    if path != SCENE:
                        problems.append(f"  {path} - CHECK48 R2: a second server_url write-site appeared outside the consent choke ({n}x) — every persist must ride Connect()/PersistAndGo()")
                    writes += n
if writes != 1:
    problems.append(f"  {SCENE} - CHECK48 R2: server_url write-site census is {writes}, expected exactly 1 (PersistAndGo under the consent gate)")

# ---- R3 single-source predicate + redirect_refused triangle --------------
if util is not None:
    u = mask(util)
    for name in ("HostOfUrl", "IsPrivateHostAddress", "ServerUrlUsesCleartextToRemoteHost",
                 "RedirectHopLimit", "OriginOfUrl", "IsCredentialSafeRedirectHop",
                 "ResolveRedirectTarget", "ResponseBodyByteCap", "ResponseBodyExceedsCap"):
        if not re.search(r"(?m)^function %s\b" % name, u):
            problems.append(f"  {UTIL} - CHECK48 R3: the custody leaf {name}() is gone — the unit suite and the send/scene call sites reference it by name")
    norm = sub_body(u, "NormalizeServerUrl")
    if norm is None or "IsPrivateHostAddress(HostOfUrl(" not in norm:
        problems.append(f'  {UTIL} - CHECK48 R3: NormalizeServerUrl no longer delegates inference to the single-source predicate — re-rolled octet logic is how "10th-street.example.com" was once misclassified')
    gatefn = sub_body(u, "ServerUrlUsesCleartextToRemoteHost")
    if gatefn is None or "not IsPrivateHostAddress(HostOfUrl(" not in gatefn:
        problems.append(f"  {UTIL} - CHECK48 R3: ServerUrlUsesCleartextToRemoteHost no longer rides HostOfUrl + IsPrivateHostAddress — consent and inference must agree on ONE host class")
    cls = sub_body(u, "ClassifyUrlFailure")
    if cls is None or 'return "redirect_refused"' not in cls:
        problems.append(f"  {UTIL} - CHECK48 R3: the classifier lost the redirect_refused arm — refused hops would fall to the generic unreachable lie")
    if "redirect_refused" not in (sub_body(u, "IsTransportReason") or ""):
        problems.append(f"  {UTIL} - CHECK48 R3: IsTransportReason no longer admits redirect_refused — restoreSession would wipe credentials the server never disproved")
    if 'Translate("connect_err_redirect_refused")' not in (sub_body(u, "TranslateTransportReason") or ""):
        problems.append(f"  {UTIL} - CHECK48 R3: the bucket ladder lost its connect_err_redirect_refused arm (CHECK34 R2 keeps the triangle total)")
    if scene is not None and '"192"' in mask(scene):
        problems.append(f"  {SCENE} - CHECK48 R3: octet literals reappeared in ConnectScene — the gate must ask the predicate, never re-derive it")

for L in LOCALES:
    path = f"locale/{L}/strings.json"
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK48 R3: unreadable: {err}")
        continue
    for key in ("err_redirect_refused", "cleartext_title", "cleartext_message", "cleartext_continue"):
        if cat.get("connect", {}).get(key, "") == "":
            problems.append(f"  {path} - CHECK48 R3: connect.{key} missing — the refusal and the consent dialog must be SPEAKABLE in every shipped locale")
    if cat.get("_metadata", {}).get("version") != "1.23.0":
        problems.append(f"  {path} - CHECK48 R3: _metadata.version is not 1.23.0 — the catalogs bump as a set with this law (rotated by R-ROKU-10 with the common_notice mint, then by the review CR-2/Check74 batch with the ten form-chrome keys, then by the MJ-4 batch with home_start_failed, then by the MJ-20 pass (no mint), then by the MJ-11 batch with the four transport-label keys, then by the MN-26 batch retiring the dead detail.error_favorite_save key (removal, no mint), then by the MJ-2 deferred-lane batch with the seven syncplay join-code keys (v1.20.0, 391 leaves), then by the RT-032 batch with the concurrent-stream singular key (v1.21.0, 392 leaves), then by the RT-094 batch with the four browse-failure keys (v1.22.0, 396 leaves), then by the RT-095 batch with the thirteen dialog/error-copy keys (v1.23.0, 409 leaves), disclosed)")

# ---- R4 the device harness pins the law -----------------------------------
test = read(TEST)
if test is None:
    problems.append(f"  {TEST} - CHECK48 R4: the M-ROKU-15 custody unit suite vanished")
else:
    for name in ("TestHostOfUrlVectors", "TestIsPrivateHostAddressTruthTable",
                 "TestCleartextRemoteGateTruthTable", "TestOriginOfUrlNormalization",
                 "TestCredentialSafeRedirectHopLaw", "TestResolveRedirectTargetShapes",
                 "TestRedirectBucketClassification", "TestResponseBodyCapLaw"):
        if f"sub {name}(" not in test:
            problems.append(f"  {TEST} - CHECK48 R4: {name} is gone")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK48: %d credential-custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK48: credentialed sends decide redirects themselves (auto-follow off,")
print("           same-origin/upgrade hop law, bounded chain, honest redirect_refused")
print("           refusal); the one server_url persist site sits behind a loud")
print("           cleartext-consent dialog for remote http origins; inference, consent")
print("           and hops share one host predicate; the seven catalogs speak both the")
print("           refusal and the dialog; the unit suite pins every pure leaf; every")
print("           parse site meets the RT-034 body-size cap before ParseJSON")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo "=== Check 49: the toast pipeline displays via the built-in Dialog (M-ROKU-17) ==="
# TOAST DISPLAY LAW (M-ROKU-17, review roku__gameux M2; adjudicated against
# the M-ROKU-17 r1 REWORK phantom). The R3.4 ambient-feedback layer was a
# three-layer phantom: the show write targeted m.top.ComponentController.Dialog
# (SGDEX vocabulary — no ComponentController ever existed in the component
# set, so the assignment landed on invalid and every notice vanished); the
# overlay extended Scene, which is not a legal Scene.dialog payload (Roku's
# Scene reference expects "a node extended from a Dialog node"); and the
# overlay script faked its mechanics (a Timer that was created but never
# attached — timers only tick in the render tree — an invisible label, and
# m.top.close writes, which is the built-in Dialog's dismiss control, not a
# Scene field). Delivery was dead too: BrightScript m is per component-script-
# scope, so ToastManager's "singleton" is one instance per including scope,
# and the only non-root consumer never called setScene. Cure, riding the
# estate's shipped dialog idiom (SettingsScene m.top.dialog = dialog;
# Utilities ShowErrorDialog): ToastScene re-based onto the built-in Dialog,
# displayed by the root coordinator through the CURRENT SURFACE's dialog
# field (topmost Scene-derived last-appended child — the OnConnected idiom),
# FIFO queue (cap 5, drop-oldest WITH print) that never tramples a scene-
# owned modal (bounded 2s x 15 retry, expired queue dropped WITH print),
# dismissal via the documented close/wasClosed pair on a ROOT-attached
# timer, and per-scope delivery restored (PlayerScene wires its singleton;
# show() walks GetParent to the root coordinator). Statically pinned below;
# the pure-leaf-free joints are node-tree behavior, so the device harness
# pins nothing new (venue: no ROKU_HOST in this lane — disclosed).
# M-ROKU-17 r2 (review roku__gameux M17r1 CRITICAL-1): the r1 round proved
# the DISPLAY half reviewed-clean but convicted the DELIVERY half a third
# phantom layer — target.PostMessage("showToast") into a node message handler
# is no articulable RokuOS contract: bsc's vendored Roku types (the
# component-library authority this channel lints against;
# brighterscript/dist/roku-types/data.json) model PostMessage exactly once,
# on roRenderThreadQueue, whose documented receive path is AddMessageHandler
# — used nowhere here — roSGNode models no onMessage special at any arity,
# and none of this repo's seven Task components rides one. The 689b475
# two-arg re-arm inherits that unmodeled door; this round replaces the wire
# outright. Cure: delivery rides the root scene's OBSERVED INTERFACE FIELDS
# — toastMessage/toastDuration payload + the alwaysNotify toastSeq trigger —
# wired in Init via ObserveField("toastSeq", "OnToastNotice"), the repo's
# proven render-thread channel (every requestClose arm; ShowErrorDialog's
# named-sub observers). R7 below pins the mechanism itself inside the
# pinning surface — dead wire extinct repo-wide, live channel wired at BOTH
# ends payload-before-trigger on declared interface fields — and keeps the
# r2 round's adopted pre-attach queue/drain pins (r1 ask 3, shipped by
# 689b475, mechanism-independent). Measured THIS round: reverting only the
# three dispatch files fires 12 named R7 pins at the 689b475 door and 18 at the
# r1 7942e66 fiction, R1..R6 and every other leg green in both probes — the
# leg convicts the dispatch path specifically. Device
# honesty: delivery rests on documented render-thread field-observer
# semantics the shipped requestClose arms exercise live, but no ROKU_HOST
# venue ran ToastManager end-to-end on-device this lane (statically pinned
# only, per the CHECK47/48/49 family precedent — disclosed). The r2 plants
# live in the portable harness RED49B family.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

APP = "components/PhlixApp.brs"
SCENE_XML = "components/ToastScene.xml"
SCENE_BRS = "components/ToastScene.brs"
PLAYER = "components/PlayerScene.brs"
TMGR = "source/lib/ToastManager.brs"
APP_XML = "components/PhlixApp.xml"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK49: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask_brs(text):
    # BrightScript line comments (' to end of line) stripped — the pins match
    # CODE, never era prose that legitimately names the dead defect (the
    # CHECK47 masking precedent).
    return re.sub(r"'[^\n]*", "", text)


def mask_xml(text):
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


# ---- R1 the fabricated ComponentController write stays extinct -------------
hits = sorted(
    p for p in glob.glob("source/**/*.brs", recursive=True)
    + glob.glob("components/**/*.xml", recursive=True)
    + glob.glob("components/**/*.brs", recursive=True)
    if "ComponentController" in mask_xml(mask_brs(open(p, encoding="utf-8", errors="replace").read()))
)
for h in hits:
    problems.append(
        f"  {h} - CHECK49 R1: ComponentController is back — no such node exists in this "
        "component set; the toast display must ride the real Scene dialog field"
    )

# ---- R2 the overlay extends the built-in Dialog, phantom chrome extinct ----
xml = read(SCENE_XML)
if xml is None:
    problems.append(f"  {SCENE_XML} - CHECK49 R2: the toast overlay component vanished")
else:
    xml = mask_xml(xml)
    m = re.search(r'<component\s+name="ToastScene"\s+extends="([^"]+)"', xml)
    if m is None or m.group(1) != "Dialog":
        problems.append(
            f"  {SCENE_XML} - CHECK49 R2: ToastScene extends "
            f"{'?missing?' if m is None else m.group(1)!r} — only a node extended from the "
            "built-in Dialog is a legal Scene.dialog payload; the Scene base was the defect"
        )
    for ghost in ("toastLabel", "Toast text here"):
        if ghost in xml:
            problems.append(
                f"  {SCENE_XML} - CHECK49 R2: the pre-fix chrome ({ghost}) is back — the "
                "notice text rides the inherited Dialog title field; this markup ships no literals"
            )

# ---- R3 the phantom-mechanics script stays deleted --------------------------
if os.path.exists(SCENE_BRS):
    problems.append(
        f"  {SCENE_BRS} - CHECK49 R3: the fabricated overlay script is re-grown — its Timer "
        "was never attached, its label never visible, and m.top.close is not a Scene field; "
        "dismissal now rides the Dialog close/wasClosed pair owned by the root coordinator"
    )

# ---- R4 the display + dismiss arms ride real fields -------------------------
app = read(APP)
if app is not None:
    app = mask_brs(app)
    if "target.dialog = toast" not in app:
        problems.append(
            f"  {APP} - CHECK49 R4: the dialog display write is gone — the coordinator must "
            "assign the toast to the current surface's dialog field (the estate idiom)"
        )
    if 'toast.ObserveField("wasClosed", "OnToastClosed")' not in app:
        problems.append(
            f"  {APP} - CHECK49 R4: the wasClosed drain observer is gone — without it a "
            "dismissed or Back-closed toast never hands the surface to the next queued notice"
        )
    if "m.activeToast.close = true" not in app:
        problems.append(
            f"  {APP} - CHECK49 R4: the documented Dialog close control write is gone — "
            "auto-dismiss regressed to a phantom"
        )

    # ---- R5 the queue coordinator keeps its bounded, loud shape -------------
    for needle, why in (
        ("m.toastQueue = []", "queue state initialized in Init"),
        ("sub EnqueueToast(", "enqueue arm"),
        ("if m.toastQueue.Count() > 5 then", "FIFO cap 5 with drop-oldest"),
        ("sub TryShowToast(", "drain arm"),
        ("sub ArmToastRetry(", "bounded blocked-surface retry"),
        ("m.toastRetryTicks >= 15", "30 s retry window (15 x 2 s)"),
        ("m.top.AppendChild(m.toastTimer)",
         "dismiss/retry timer attached to the ROOT scene (a Timer only ticks in the render tree)"),
    ):
        if needle not in app:
            problems.append(f"  {APP} - CHECK49 R5: {why} is gone ({needle!r})")

# ---- R6 per-scope delivery restored ------------------------------------------
pl = read(PLAYER)
if pl is not None and "toast.setScene(m.top)" not in mask_brs(pl):
    problems.append(
        f"  {PLAYER} - CHECK49 R6: the progress-warning scope unwired its ToastManager "
        "singleton again — per-script-scope m means show() dies at the invalid guard without it"
    )
tm = read(TMGR)
if tm is not None:
    tm = mask_brs(tm)
    if "while parent <> invalid" not in tm or "target.GetParent()" not in tm:
        problems.append(
            f"  {TMGR} - CHECK49 R6: the GetParent root walk is gone — the notice must reach "
            "the root coordinator, not the scope-stored (possibly nested) scene"
        )

# ---- R7 dispatch mechanism + pre-attach drain (M-ROKU-17 r2) -----------------
# The r1 review convicted the PostMessage/onMessage wire outright (no
# articulable RokuOS node contract; bsc models PostMessage only on
# roRenderThreadQueue, receive via AddMessageHandler, shipped nowhere here).
# R7 pins the LIVE mechanism — declared observed fields, payload-before-
# trigger writes, root observer wiring, receiver arm — convicts the dead
# pair extinct repo-wide, and keeps the adopted pre-attach queue/drain pins
# (r1 ask 3: zero permanent drops on the normal path, capped loud
# drop-oldest on overflow).
for p in sorted(
    glob.glob("source/**/*.brs", recursive=True)
    + glob.glob("components/**/*.brs", recursive=True)
):
    code = mask_brs(open(p, encoding="utf-8", errors="replace").read())
    if re.search(r"(?i)\.PostMessage\s*\(", code):
        problems.append(
            f"  {p} - CHECK49 R7: node.PostMessage is re-grown — roSGNode has no "
            "documented message-receive contract (bsc's vendored Roku types model "
            "PostMessage only on roRenderThreadQueue, whose receive path is "
            "AddMessageHandler, shipped nowhere here; no onMessage special is modeled "
            "at any arity); delivery rides the observed toastSeq channel"
        )
    if re.search(r"(?i)sub\s+onMessage\s*\(", code):
        problems.append(
            f"  {p} - CHECK49 R7: the retired onMessage catch-all is re-grown — no "
            "documented node dispatch calls it at any arity; the dispatch arm is "
            "OnToastNotice, fed by ObserveField(\"toastSeq\")"
        )

if tm is not None:
    for needle, why in (
        ('target.DoesExist("toastSeq")', "the foreign-root guard on the dispatch channel"),
        ("target.toastMessage = message", "the String payload write"),
        ("target.toastDuration = durationMs", "the Integer duration payload write"),
        ("target.toastSeq = target.toastSeq + 1", "the alwaysNotify trigger bump"),
    ):
        if needle not in tm:
            problems.append(f"  {TMGR} - CHECK49 R7: {why} is gone ({needle!r})")
    i_msg = tm.find("target.toastMessage")
    i_dur = tm.find("target.toastDuration")
    i_seq = tm.find("target.toastSeq = target.toastSeq + 1")
    if i_msg >= 0 and i_dur >= 0 and i_seq >= 0 and not (i_msg < i_seq and i_dur < i_seq):
        problems.append(
            f"  {TMGR} - CHECK49 R7: the trigger must be bumped AFTER both payload writes — "
            "the coordinator must never observe a half-written notice"
        )
    if "if m._scene = invalid then return" in tm:
        problems.append(
            f"  {TMGR} - CHECK49 R7: the silent pre-attach drop guard is back — a notice "
            "raised before setScene must queue (capped, drop-oldest WITH print), not vanish"
        )
    for needle in ("_pending", "MAX_PENDING", "m._pending.Push", "queued = m._pending", "m.deliver("):
        if needle not in tm:
            problems.append(f"  {TMGR} - CHECK49 R7: pre-attach queue/drain needle {needle!r} is gone")

if app is not None:
    if 'm.top.ObserveField("toastSeq", "OnToastNotice")' not in app:
        problems.append(
            f"  {APP} - CHECK49 R7: the root's observer wiring is gone — without "
            "ObserveField(\"toastSeq\", \"OnToastNotice\") the bump delivers to nobody"
        )
    if "sub OnToastNotice(" not in app:
        problems.append(
            f"  {APP} - CHECK49 R7: the dispatch arm sub vanished — OnToastNotice is the "
            "channel's receiver"
        )
    if "m.top.toastMessage" not in app or "m.top.toastDuration" not in app:
        problems.append(
            f"  {APP} - CHECK49 R7: the receiver stopped reading the payload fields — the "
            "notice text/duration ride toastMessage/toastDuration"
        )

app_xml = read(APP_XML)
if app_xml is not None:
    app_xml = mask_xml(app_xml)
    for rx, why in (
        (r'<field\s+id="toastMessage"\s+type="string"', "the String payload field declaration"),
        (r'<field\s+id="toastDuration"\s+type="integer"', "the Integer payload field declaration"),
        (r'<field\s+id="toastSeq"\s+type="integer"[^>]*alwaysNotify="true"',
         "the alwaysNotify trigger field declaration"),
    ):
        if re.search(rx, app_xml) is None:
            problems.append(
                f"  {APP_XML} - CHECK49 R7: {why} is gone — the dispatch channel is declared "
                "interface fields (interface-undeclared fields are not the cross-component "
                "channel this repo's requestClose arms prove out)"
            )

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK49: %d toast-display pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK49: the toast overlay is a built-in-Dialog node displayed through the")
print("           current surface's dialog field; the root coordinator queues FIFO (cap 5,")
print("           drop-oldest with print), never tramples a scene modal (bounded 2s x 15")
print("           retry), dismisses via the documented close/wasClosed pair on a root-")
print("           attached timer; every scope's ToastManager reaches it by the GetParent")
print("           walk plus the declared, observed toastSeq dispatch channel (R7), the")
print("           PostMessage/onMessage fiction stays extinct repo-wide and the pre-attach queue drain")
print("           stands (M-ROKU-17 r2)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 50: watch-party attribution banner - scene-level, panel-independent (M-ROKU-19) ==="
# PARTY ATTRIBUTION LAW (M-ROKU-19, review roku__gameux M4): every SyncPlay event
# used to surface ONLY on the syncStatusLabel, which lives INSIDE syncPanel - and
# closing the panel stops the socket, so while actually watching (panel closed)
# host pause/seek/resume changed the picture in total silence and join/host/error/
# drop events were invisible. Cure: a scene-level partyNotice strip with a
# one-shot Timer auto-hide (R2.1 idiom), driven through ShowPartyNotice /
# NotifyPartyEvent choke points; user-initiated socket stops (panel close, Leave)
# set m.syncUserStopped so the terminal "closed" event banners only on real
# drops. Pinned statically:
#   R1  markup: components/PlayerScene.xml carries a visible=false
#       partyNotice Rectangle DIRECT under <children> (scene-level sibling,
#       never re-nested in syncPanel) with a partyNoticeLabel child that has no
#       design-time text (CHECK25 chrome law).
#   R2  mechanics: the five subs exist; ShowPartyNotice's body runs the R2.1
#       timer trio (duration/ObserveField("fire")/Append/control="start") and
#       flips visible; neither Show nor Hide may reference syncPanel (the
#       panel-independence law this whole item is about); NotifyPartyEvent
#       rides SetSyncStatus + ShowPartyNotice.
#   R3  the silent class: ApplyRemotePlayback banners all three arms ("Host
#       resumed"/"Host paused"/"Host changed position").
#   R4  event coverage: HandleSyncEvent banners open/info/host_elect(x2)/error/
#       closed (the closed arm gated on m.syncUserStopped) and the suppression
#       flag is wired at >=5 sites across the file.
# M-ROKU-20 (Check 51) localized the party copy: the R3/R4 needles below anchor
# the banner call at its Translate() call shape. The attribution semantics are
# unchanged (one banner per arm, panel-independent); Check 51 owns the law that
# the strings themselves ride the catalog.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys
import xml.etree.ElementTree as ET

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

XMLP = "components/PlayerScene.xml"
BRS = "components/PlayerScene.brs"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK50: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def sub_body(text, name):
    m = re.search(r"(?ms)^sub %s\(.*?^end sub" % re.escape(name), text)
    return m.group(0) if m else None


# ---- R1 markup: scene-level, hidden-by-default, literal-free --------------
tree = None
try:
    tree = ET.parse(XMLP)
except (OSError, ET.ParseError) as err:
    problems.append(f"  {XMLP} - CHECK50 R1: unparseable: {err}")

if tree is not None:
    root = tree.getroot()
    children = root.find("children")
    notice = None
    if children is not None:
        notice = children.find("Rectangle[@id='partyNotice']")
    if notice is None:
        problems.append(f"  {XMLP} - CHECK50 R1: no scene-level partyNotice Rectangle directly under <children> — the banner vanished or was re-nested inside a panel (the exact defect class this item fixed)")
    else:
        if notice.get("visible") != "false":
            problems.append(f'  {XMLP} - CHECK50 R1: partyNotice must ship visible="false" — an always-on strip would scar the default playback path')
        label = notice.find("Label[@id='partyNoticeLabel']")
        if label is None:
            problems.append(f"  {XMLP} - CHECK50 R1: partyNotice has no partyNoticeLabel child — ShowPartyNotice would write to an invalid node")
        elif label.get("text") is not None:
            problems.append(f"  {XMLP} - CHECK50 R1: partyNoticeLabel carries design-time text= — CHECK25 chrome law, the string is set only at runtime")

# ---- R2 mechanics: timer idiom + panel-independence ------------------------
brs = read(BRS)
if brs is not None:
    code = mask(brs)
    for name in ("ShowPartyNotice", "HidePartyNotice", "StopPartyNoticeTimer",
                 "OnPartyNoticeTimerFire", "NotifyPartyEvent"):
        if not re.search(r"(?m)^sub %s\(" % name, code):
            problems.append(f"  {BRS} - CHECK50 R2: sub {name}() is gone — the banner pipeline is its only driver")

    show = sub_body(code, "ShowPartyNotice")
    if show is not None:
        for needle in ('CreateObject("roSGNode", "Timer")', "duration = hold",
                       'ObserveField("fire", "OnPartyNoticeTimerFire")',
                       "m.top.Append(m.partyNoticeTimer)",
                       'control = "start"', "m.partyNotice.visible = true"):
            if needle not in show:
                problems.append(f"  {BRS} - CHECK50 R2: ShowPartyNotice lost the R2.1 idiom needle [{needle}] — a banner that never auto-hides (or never arms a timer) is the old silence with extra steps")
        if "syncPanel" in show:
            problems.append("  " + BRS + " - CHECK50 R2: ShowPartyNotice references syncPanel — the banner MUST be panel-independent; the panel is only open while the user is not watching")
    hide = sub_body(code, "HidePartyNotice")
    if hide is not None:
        if "StopPartyNoticeTimer()" not in hide or "visible = false" not in hide:
            problems.append(f"  {BRS} - CHECK50 R2: HidePartyNotice must stop its timer AND clear visibility — an orphaned timer would hide a fresh notice mid-hold")
        if "syncPanel" in hide:
            problems.append("  " + BRS + " - CHECK50 R2: HidePartyNotice references syncPanel — panel-independence law")
    notify = sub_body(code, "NotifyPartyEvent")
    if notify is not None:
        if "SetSyncStatus(text)" not in notify or "ShowPartyNotice(text, hold)" not in notify:
            problems.append(f"  {BRS} - CHECK50 R2: NotifyPartyEvent must drive BOTH the panel label and the banner — either half alone re-creates the invisible-event defect for one of the two viewing states")

    # ---- R3 the silent class: host-driven transport changes ----------------
    arp = sub_body(code, "ApplyRemotePlayback")
    if arp is None:
        problems.append(f"  {BRS} - CHECK50 R3: ApplyRemotePlayback vanished — the host-follow path has no home")
    else:
        for needle in ('NotifyPartyEvent(Translate("player_party_host_resumed")',
                       'NotifyPartyEvent(Translate("player_party_host_paused")',
                       'NotifyPartyEvent(Translate("player_party_host_position")'):
            if needle not in arp:
                problems.append(f"  {BRS} - CHECK50 R3: {needle} is gone — a mid-playback transport change with no on-screen attribution is precisely the invisible-event defect (gameux M4)")

    # ---- R4 event coverage + drop-vs-close suppression ---------------------
    hse = sub_body(code, "HandleSyncEvent")
    if hse is None:
        problems.append(f"  {BRS} - CHECK50 R4: HandleSyncEvent vanished")
    else:
        for needle in ('ShowPartyNotice(Translate("player_party_connected")',
                       'NotifyPartyEvent(msg, 4.0!)',
                       'NotifyPartyEvent(Translate("player_party_you_are_host")',
                       'NotifyPartyEvent(Translate("player_party_host_changed")',
                       'ShowPartyNotice(Translate("player_party_disconnected")',
                       "if not m.syncUserStopped"):
            if needle not in hse:
                problems.append(f"  {BRS} - CHECK50 R4: HandleSyncEvent lost the banner arm [{needle}] — party events would fall back to panel-only visibility")
    nflag = code.count("m.syncUserStopped")
    if nflag < 5:
        problems.append(f"  {BRS} - CHECK50 R4: m.syncUserStopped appears {nflag}x, expected >=5 (Init, ConnectSyncTask reset, CloseSyncPanel, OnSyncLeavePressed, closed arm) — without every site the drop-vs-teardown distinction rots")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK50: %d party-attribution pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK50: host pause/seek/resume, joins, host elections, errors and")
print("           unexpected drops all surface on a scene-level, panel-")
print("           independent auto-hiding banner (R2.1 timer idiom); user-")
print("           initiated socket stops (panel close / Leave) are suppressed")
print("           via m.syncUserStopped; the markup ships hidden and literal-free")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 51: live playback & party copy rides the locale catalog (M-ROKU-20) ==="
# LIVE-COPY LAW (M-ROKU-20 r2; review roku__gameux M5 + the M-ROKU-19 disclosed
# residual): every player-surface string that renders on the TV is catalog copy —
# the three P5-S5 error-overlay messages, every SetSyncStatus panel label, the
# whole ShowPartyNotice/NotifyPartyEvent banner family, the hub-mode notice, the
# playback dialogs and the SyncPlayTask unknown-code fallback. The pin follows
# the Check 25 zero-literals idiom: it CONVICTS reintroduced English file:line,
# never merely asserts key presence. Legs:
#   R1  the three Show*Error subs write Translate("player_err_*") into
#       m.errorMessageLabel.text.
#   R2  zero-literals: each swept English sentence, quote-anchored, is a
#       violation in the comment-masked code view of every *.brs under
#       components/ and source/ — plus the call-shape law: SetSyncStatus(" /
#       ShowPartyNotice(" / NotifyPartyEvent(" may never open a raw string
#       literal (a Translate()/TranslateWithParams() call or a variable is the
#       legal shape; the pre-existing syncplay_status_tls_refused arm already
#       rides Translate() and passes by shape).
#   R3  SPEAKABLE: the 29 new player_* keys are non-empty strings in ALL SEVEN
#       shipped catalogs (Check 21 owns full parity; this leg names the family).
#   R0  unreadable inputs fail loud — the pin cannot run vacuously.
# CHECK50's R3/R4 needles rotated with this sweep (they anchor the banner call
# at its localized call shape; the M19 attribution semantics are unchanged).
# CROSSING DISCLOSURE (r2): the sibling landing ab050d5 grew a narrower
# Check 51 (overlay trio only) from an older brief WHILE this sweep was in
# flight; this block supersedes it — same number, same law family, strictly
# stronger legs (the trio's ab050d5 catalog keys and call sites are kept
# untouched; R1's needles are compatible). Their portable CHECK51 plant leg
# stays armed against this block (assert strings retargeted to these prints).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

BRS = "components/PlayerScene.brs"

ERR_TRIO = {
    "ShowProgressAuthError": 'm.errorMessageLabel.text = Translate("player_err_session_expired")',
    "ShowAccessError": 'm.errorMessageLabel.text = Translate("player_err_access_schedule")',
    "ShowStreamLimitError": 'm.errorMessageLabel.text = Translate("player_err_stream_limit")',
}

# The swept sentences (en_US catalog values / former literals), quote-anchored.
# "Host changed" also covers the "Host changed position" prefix by design: both
# sentences were swept. Ambiguous single words ride the exact-quote form, which
# is the form a reintroduced render assignment would take.
SENTENCES = [
    '"Your session has expired. Please sign in again to continue saving progress."',
    '"Playback blocked by access schedule. Try again during allowed hours."',
    '"Stream limit reached. Stop another stream to continue watching."',
    '"Playback failed. Please try again."',
    '"Transcode produced no stream URL."',
    '"Transcode timed out."',
    '"Watch Together isn\'t available in hub mode yet"',
    '"Connected to watch party"',
    '"Watch party disconnected"',
    '"You are now host"',
    '"Host changed position"',
    '"Host changed"',
    '"Host resumed"',
    '"Host paused"',
    '"No groups - create one to start"',
    '"Select a group to join, or Create"',
    '"SyncPlay unavailable"',
    '"SyncPlay error"',
    '"Left the group"',
    '" in group"',
    '" joined"',
    '"Loading groups…"',
    '"Creating group…"',
    '"Connecting…"',
    '"Joining…"',
    '"In sync"',
    '"Connected"',
    '"Disconnected"',
]

CALL_SHAPE = re.compile(r'(SetSyncStatus|ShowPartyNotice|NotifyPartyEvent)\(\s*"')

PLAYER_KEYS = [
    "err_access_schedule", "err_playback_failed", "err_session_expired",
    "err_stream_limit", "err_transcode_no_stream", "err_transcode_timeout",
    "party_connected", "party_disconnected", "party_error_fallback",
    "party_host_changed", "party_host_paused", "party_host_position",
    "party_host_resumed", "party_member_joined", "party_you_are_host",
    "sync_hub_unavailable", "sync_members_in_group", "sync_status_connected",
    "sync_status_connecting", "sync_status_creating", "sync_status_disconnected",
    "sync_status_group", "sync_status_in_sync", "sync_status_joining",
    "sync_status_left", "sync_status_loading", "sync_status_no_groups",
    "sync_status_select_group", "sync_status_unavailable",
]

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK51: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    # Check 20/23/24/50 masker: code view with comment runs cut.
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def sub_body(text, name):
    m = re.search(r"(?ms)^sub %s\(.*?^end sub" % re.escape(name), text)
    return m.group(0) if m else None


# ---- R1 the P5-S5 overlay trio is catalog copy ---------------------------
brs = read(BRS)
if brs is not None:
    code = mask(brs)
    for name, needle in ERR_TRIO.items():
        body = sub_body(code, name)
        if body is None:
            problems.append(f"  {BRS} - CHECK51 R1: sub {name}() is gone — the error-overlay family lost its home")
        elif needle not in body:
            problems.append(f"  {BRS} - CHECK51 R1: {name} no longer writes [{needle}] — the overlay would render a raw string again")

# ---- R2 zero-literals + call-shape law over the whole runtime ------------
for scan_dir in ("components", "source"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if not name.endswith(".brs"):
                continue
            p = os.path.join(root, name)
            text = read(p)
            if text is None:
                continue
            for lineno, line in enumerate(mask(text).split("\n"), 1):
                for frag in SENTENCES:
                    if frag in line:
                        problems.append(f'  {p}:{lineno} - CHECK51 R2: reintroduced English UI copy {frag} — live player/party copy rides the locale catalog (M-ROKU-20 law, Check 25 idiom)')
                mo = CALL_SHAPE.search(line)
                if mo:
                    problems.append(f'  {p}:{lineno} - CHECK51 R2: {mo.group(1)}( opens a raw string literal — status/banner copy must flow through Translate()/TranslateWithParams() (M-ROKU-20)')

# ---- R3 the 29-key family is SPEAKABLE in every shipped catalog ----------
locale_files = sorted(glob.glob("locale/*/strings.json"))
if len(locale_files) < 7:
    problems.append(f"  locale/*/strings.json - CHECK51 R3: found {len(locale_files)} catalogs, expected 7 — the pin cannot run vacuously")
for path in locale_files:
    raw = read(path)
    if raw is None:
        continue
    try:
        doc = json.loads(raw)
    except ValueError as err:
        problems.append(f"  {path} - CHECK51 R3: unparsable: {err}")
        continue
    player = doc.get("player") if isinstance(doc, dict) else None
    if not isinstance(player, dict):
        problems.append(f"  {path} - CHECK51 R3: no player section — the live-copy family has no home")
        continue
    for bare in PLAYER_KEYS:
        v = player.get(bare)
        if not isinstance(v, str) or v == "":
            problems.append(f"  {path} - CHECK51 R3: player.{bare} missing/empty — live copy must be SPEAKABLE in every shipped locale")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK51: %d live-copy pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK51: the error-overlay trio, every sync panel status, the party")
print("           banner family (both choke points + the task-side fallback) and")
print("           the playback dialogs are catalog copy — 29 player_* keys ride")
print("           all seven locales, reintroduced English is convicted file:line")
print("           and raw-literal calls into the status/banner choke points are rejected")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 52: a failed read never renders as emptiness (M-ROKU-21) ==="
# FAILURE-VS-EMPTY LAW (M-ROKU-21, review roku__gameux M6): DashboardScene's
# ExtractData collapsed !ok / 401 / 403 / malformed into [] and RenderDashboard
# drew those failures as "(none)" rows; HomeScene's OnLibrariesResponse had no
# failure branch at all (empty grid, description still "Select a library") and
# OnContinueWatchingResponse silently returned on !ok. A user with a wiped token
# or an unreachable server saw a confidently-empty app with no recovery path.
# Cure: ExtractData yields invalid (never []) on failure; each scene keeps a
# per-read failure flag, renders localized failure copy instead of "(none)",
# and reveals a focusable Retry button (the M16 boot-retry idiom, Check 47).
# Pinned statically:
#   R1  DashboardScene: ExtractData's failure arms return invalid (the four
#       exact lines — re-growing a collapsed `return []` branch breaks the
#       matching arm), OnApiResponse records the classification
#       (m.nowPlayingFailed/m.storageFailed/m.activityFailed), RenderDashboard
#       writes Translate("dashboard_failed_row") per failed section x3 and
#       Translate("dashboard_failed_status") into the status label, and the
#       retry wiring exists (buttonSelected observer + StartLoadChain defined
#       and called from both Init and the retry handler);
#   R2  HomeScene: OnLibrariesResponse and OnContinueWatchingResponse each own
#       a failure branch that sets its flag and calls ShowHomeRailFailure, the
#       success paths call HideHomeRailFailureIfHealthy, the retry handler
#       re-fires exactly the failed loads, and ApplyXmlChrome localizes both
#       retryButton titles (CHECK25's override-path law);
#   R3  both XMLs carry id="retryButton" focusable="true" — the recovery path
#       is a pressable control, not prose (Check 47's lesson);
#   R4  the three cured English sentences appear as raw literals in NO .brs
#       file under components/ or source/ (comment-masked whole-tree scan —
#       CHECK51 R2's idiom);
#   R5  the three keys (home.rail_failed, dashboard.failed_row,
#       dashboard.failed_status) exist, non-empty and string-typed, in ALL
#       SEVEN shipped catalogs (CHECK48 R3 keeps the set-bump honest).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

DASH = "components/DashboardScene.brs"
HOME = "components/HomeScene.brs"
DASH_XML = "components/DashboardScene.xml"
HOME_XML = "components/HomeScene.xml"
LOCALES = ["de_DE", "en_US", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR"]

# (section, bare key) pairs the cure rides (CHECK51 R3's idiom)
CAT_KEYS = [("home", "rail_failed"), ("dashboard", "failed_row"), ("dashboard", "failed_status")]
# fragments unique to each cured English sentence (CHECK51 R2's idiom)
FRAGMENTS = ["Couldn't load", "press OK to retry", "reads failed"]

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK52: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def func_body(text, name):
    m = re.search(r"(?ms)^(function|sub) %s\(.*?^(end function|end sub)" % re.escape(name), text)
    return m.group(0) if m else None


def require(haystack, where, needle, why):
    if haystack is None:
        return
    if needle not in haystack:
        problems.append(f"  {where} - CHECK52: {needle!r} missing — {why}")


dash = read(DASH)
home = read(HOME)

# ---- R1 the dashboard classifies failure instead of collapsing to [] -------
if dash is not None:
    dcode = mask(dash)
    body = func_body(dcode, "ExtractData")
    if body is None:
        problems.append(f"  {DASH} - CHECK52 R1: function ExtractData() vanished — the classification has no home")
    else:
        for arm in (
            "if resp = invalid then return invalid",
            "if not resp.ok then return invalid",
            "if resp.data = invalid then return invalid",
            "if resp.data.data = invalid then return invalid",
            'if type(resp.data.data) <> "roArray" then return invalid',
        ):
            require(body, DASH, arm, "ExtractData's failure arm back to collapsing into [] — a failed read rendering as '(none)' is the M-ROKU-21 defect re-grown")
        if "return []" in body:
            problems.append(f"  {DASH} - CHECK52 R1: ExtractData still returns [] on some path — failure must be invalid, [] must mean honest-empty")
    for flag in ("m.nowPlayingFailed", "m.storageFailed", "m.activityFailed"):
        oabody = func_body(dcode, "OnApiResponse")
        require(oabody, DASH, flag + " = (", "OnApiResponse does not classify this read — the section's failure state is unsaid")
    rbody = func_body(dcode, "RenderDashboard")
    if rbody is None:
        problems.append(f"  {DASH} - CHECK52 R1: sub RenderDashboard() vanished")
    else:
        n = rbody.count('Translate("dashboard_failed_row")')
        if n != 3:
            problems.append(f'  {DASH} - CHECK52 R1: RenderDashboard writes Translate("dashboard_failed_row") {n}x, expected 3x — every failed section must render failure copy, not "(none)"')
        require(rbody, DASH, 'SetStatus(Translate("dashboard_failed_status"))', "the status label never reports the failed reads")
    require(dcode, DASH, 'ObserveField("buttonSelected", "OnRetryPressed")', "the dashboard retry button has no handler — recovery path unwired")
    require(dcode, DASH, "sub StartLoadChain()", "the dashboard cannot restart its read chain")
    if func_body(dcode, "Init") is not None and "StartLoadChain()" not in func_body(dcode, "Init"):
        problems.append(f"  {DASH} - CHECK52 R1: Init no longer routes through StartLoadChain — the retry restart shape is drifting from the boot shape")
    if func_body(dcode, "OnRetryPressed") is not None and "StartLoadChain()" not in func_body(dcode, "OnRetryPressed"):
        problems.append(f"  {DASH} - CHECK52 R1: OnRetryPressed does not call StartLoadChain — the OK press would be theater")

# ---- R2 the home screen owns its failure branches ---------------------------
if home is not None:
    hcode = mask(home)
    lb = func_body(hcode, "OnLibrariesResponse")
    if lb is None:
        problems.append(f"  {HOME} - CHECK52 R2: sub OnLibrariesResponse() vanished")
    else:
        require(lb, HOME, "m.librariesFailed = true", "the libraries handler is back to swallowing failure into an empty grid")
        require(lb, HOME, "ShowHomeRailFailure()", "a failed libraries read never reaches the user — the confidently-empty app re-grown")
        require(lb, HOME, "m.librariesFailed = false", "the success path never clears the failure flag — a recovered load would keep retry copy")
    cb = func_body(hcode, "OnContinueWatchingResponse")
    if cb is None:
        problems.append(f"  {HOME} - CHECK52 R2: sub OnContinueWatchingResponse() vanished")
    else:
        require(cb, HOME, "m.continueFailed = true", "the continue-watching handler is back to silently returning on !ok")
        require(cb, HOME, "ShowHomeRailFailure()", "a failed continue-watching read never reaches the user")
        require(cb, HOME, "m.continueFailed = false", "the success path never clears the failure flag")
    require(hcode, HOME, "sub HideHomeRailFailureIfHealthy()", "nothing ever retracts the failure state once both reads are healthy")
    rb = func_body(hcode, "OnRetryPressed")
    if rb is None:
        problems.append(f"  {HOME} - CHECK52 R2: sub OnRetryPressed() vanished — the Retry control would be theater")
    else:
        require(rb, HOME, "if m.librariesFailed then LoadLibrariesAsync()", "retry never re-fires the failed libraries load")
        require(rb, HOME, "if m.continueFailed then LoadContinueWatchingAsync()", "retry never re-fires the failed continue-watching load")
    ac = func_body(hcode, "ApplyXmlChrome")
    require(ac, HOME, 'Translate("common_retry")', "the home retryButton title never gets its programmatic chrome override (CHECK25's law)")
    if dash is not None:
        dac = func_body(mask(dash), "ApplyXmlChrome")
        require(dac, DASH, 'Translate("common_retry")', "the dashboard retryButton title never gets its programmatic chrome override (CHECK25's law)")

# ---- R3 the recovery path is a pressable control ----------------------------
for x, label in ((DASH_XML, "DashboardScene.xml"), (HOME_XML, "HomeScene.xml")):
    xt = read(x)
    if xt is not None:
        m = re.search(r'(?s)<Button[^>]*id="retryButton"[^>]*>', xt)
        if m is None:
            problems.append(f'  {x} - CHECK52 R3: no <Button id="retryButton"> — prose without a control is not a recovery path (Check 47\'s lesson)')
        elif 'focusable="true"' not in m.group(0):
            problems.append(f"  {x} - CHECK52 R3: retryButton is not focusable — the retry cannot be reached with the remote")

# ---- R4 the cured sentences live only in the catalog ------------------------
scan_files = []
for scan_dir in ("components", "source"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".brs"):
                scan_files.append(os.path.join(root, name))
for path in scan_files:
    text = read(path)
    if text is None:
        continue
    for lineno, line in enumerate(mask(text).split("\n"), 1):
        for frag in FRAGMENTS:
            if frag in line:
                problems.append(f'  {path}:{lineno} - CHECK52 R4: raw English fragment "{frag}" re-grown as a literal outside the catalog — this copy must ride Translate (Checks 20/21 keep it speakable)')

# ---- R5 every shipped locale speaks the three keys --------------------------
for L in LOCALES:
    path = f"locale/{L}/strings.json"
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK52: unreadable: {err}")
        continue
    for section, bare in CAT_KEYS:
        value = cat.get(section, {}).get(bare)
        if not isinstance(value, str) or value.strip() == "":
            problems.append(f"  {path} - CHECK52 R5: {section}.{bare} missing — failure copy must be SPEAKABLE in every shipped locale")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK52: %d failure-vs-emptiness pin(s) broken" % len(problems))
    sys.exit(1)

print('  CHECK52: a failed read yields invalid (never "(none)"), both home rails own their')
print('           failure branches, the recovery path is a focusable Retry button, the')
print('           three English sentences exist nowhere as raw literals in .brs code, and')
print('           all seven catalogs speak home.rail_failed + the dashboard failed pair')
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 53: the server_url persist choke wipes credentials on URL change (M-ROKU-24) ==="
# CREDENTIAL-CUSTODY-AT-THE-CHOKE LAW (M-ROKU-24, review roku__secnet M3):
# PersistAndGo — the single server_url write-site CHECK48 R2 censuses to
# exactly one — used to write the newly entered address over the old one with
# the PREVIOUS host's auth_token/refresh_token/session_id still persisted.
# OnConnected then rebuilt the client (GetApiClient restores those keys),
# restoreSession() fired GET {new}/auth/me with the OLD Bearer, and the 401
# refresh arm POSTed the old refresh token to {new}/auth/refresh. Reachable at
# tip via the boot transport-failure retry (ShowConnect(reason), M-ROKU-04
# prefill): edit the saved address to another host and connect. The cure runs
# the R1.6 six-key ResetCachedStorage(true) wipe at the choke BEFORE the new
# url is written and before the connected signal, CONDITIONAL on the url
# actually changing (same-URL reconnect keeps its session; first connect has
# no prior url). Pinned statically (the logic needs registry + network nodes —
# CHECK50/51/52 precedent: statement-presence legs, device honesty disclosed):
#   R1  ConnectScene.PersistAndGo owns the custody sequence: previousUrl
#       capture, the exact conditional guard (a surviving unconditional wipe or
#       a dropped equality arm breaks the prefill/retry law), the
#       ResetCachedStorage(true) call, and the order wipe -> set("server_url")
#       -> m.top.connected = true (no request surface can observe the new host
#       before the old credentials are gone);
#   R2  the wipe rides the named primitive, not a re-rolled delete list (the
#       six-key census is Storage.brs's law — a hand-rolled subset here drifts
#       silently), and the write-site stays unique inside the choke;
#   R3  PhlixApp.OnConnected stays a pure rebuild + StartAuthCheck: no storage
#       write may re-appear there (custody scattered to callers is the exact
#       invariant the review convicted) and the auth check must stay wired.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

SCENE = "components/ConnectScene.brs"
APP = "components/PhlixApp.brs"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK53: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def func_body(text, name):
    m = re.search(r"(?ms)^(function|sub) %s\(.*?^(end function|end sub)" % re.escape(name), text)
    return m.group(0) if m else None


def require(haystack, where, needle, why):
    if haystack is None:
        return
    if needle not in haystack:
        problems.append(f"  {where} - CHECK53: {needle!r} missing — {why}")


scene = read(SCENE)
app = read(APP)

# ---- R1 the choke owns the custody sequence ---------------------------------
if scene is not None:
    scode = mask(scene)
    pg = func_body(scode, "PersistAndGo")
    if pg is None:
        problems.append(f"  {SCENE} - CHECK53 R1: sub PersistAndGo() vanished — the credential-custody choke has no home")
    else:
        require(pg, SCENE, "previousUrl = GetServerUrl()",
                "the choke must capture the PERSISTED url before overwriting it (CHECK48 R2 keeps this the only write-site)")
        require(pg, SCENE, 'if previousUrl <> "" and previousUrl <> url then',
                "the wipe must stay conditional on a genuine URL change — same-URL reconnect keeps its session (M-ROKU-04 prefill/retry law), first connect wipes nothing")
        require(pg, SCENE, "ResetCachedStorage(true)",
                "the change arm must run the R1.6 six-key wipe, not a silent partial clear")
        wipe = pg.find("ResetCachedStorage(true)")
        write = pg.find('GetStorage().set("server_url"')
        signal = pg.find("m.top.connected = true")
        if write == -1:
            problems.append(f"  {SCENE} - CHECK53 R1: PersistAndGo lost its server_url write — the choke stopped being the persist site")
        elif wipe == -1 or wipe > write:
            problems.append(f"  {SCENE} - CHECK53 R1: the wipe no longer PRECEDES the server_url write — the new host's address could persist while the old host's tokens still ride storage")
        if signal != -1 and wipe != -1 and wipe > signal:
            problems.append(f"  {SCENE} - CHECK53 R1: the wipe no longer precedes the connected signal — OnConnected could restore old credentials before they are gone")

    # ---- R2 single-source wipe primitive, unique write inside the choke ----
    if pg is not None:
        if "registry.Delete(" in pg or ".deleteKey(" in pg:
            problems.append(f"  {SCENE} - CHECK53 R2: a hand-rolled registry delete appeared inside PersistAndGo — the six-key census is ResetCachedStorage's law; a re-rolled subset drifts silently")
        if pg.count('GetStorage().set("server_url"') != 1:
            n = pg.count('GetStorage().set("server_url"')
            problems.append(f"  {SCENE} - CHECK53 R2: PersistAndGo's own server_url write count is {n}, expected exactly 1 — CHECK48 R2's repo-wide census starts here")

# ---- R3 OnConnected stays a pure rebuild + auth check -----------------------
if app is not None:
    acode = mask(app)
    oc = func_body(acode, "OnConnected")
    if oc is None:
        problems.append(f"  {APP} - CHECK53 R3: sub OnConnected() vanished — nothing rebuilds the client after connect")
    else:
        if "GetStorage().set(" in oc:
            problems.append(f"  {APP} - CHECK53 R3: OnConnected writes storage again — custody scattered to callers is the exact invariant review roku__secnet M3 convicted; it lives at PersistAndGo")
        require(oc, APP, "StartAuthCheck()",
                "the boot auth check must stay wired — custody wipes must not silence the session validation")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK53: %d credential-custody-at-the-choke pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK53: the one server_url write-site wipes the six auth/session keys")
print("           before persisting a CHANGED address and before the connected")
print("           signal, so no old-host access or refresh token can ride a")
print("           request to a host the user has not authenticated against;")
print("           same-URL reconnect keeps its session, first connect keeps its")
print("           nothing, and the wipe rides the single R1.6 primitive")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 54: SyncPlay dial composes through the refusal choke; transport prose stays true (M-ROKU-22) ==="
# SYNCPLAY DIAL-COMPOSITION + TRUTH-PRESENCE LAW (M-ROKU-22, review roku__secnet M1):
# The credential class this item guards is ALREADY closed upstream — by CHECK46
# (origin-refusal + RFC6455 accept-proof, M-ROKU-14), CHECK48 R2 (the single
# server_url write-site and its cleartext consent dialog, M-ROKU-15) and
# CHECK53 (custody wipe at the persist choke, M-ROKU-24). None of them,
# however, pinned HOW the dial is COMPOSED: the review's exfil scenario needs
# the bearer JWT to reach a non-LAN/off-origin host, and that stays impossible
# only while (a) the SyncPlayTask node is instantiated from exactly one site,
# (b) that site builds its parts through BuildSyncPlayWsParts AFTER the
# refusal guard and the honest-reason probe, (c) the parts builder forces
# port 8097 (host comes from GetServerUrl, the user-authenticated authority —
# never a wire-provided address) and refuses https origins in-code, and (d)
# the panel entry chokes hub mode (no relay path, so the token can never ride
# the unimplemented side). This leg pins that composition, so a future edit
# cannot open a second, ungated dial site while still passing CHECK46/48/53.
# The platform-misclaim conviction arms are CHECK46 R2's (the sibling M22
# prose lane edbbd8a shipped them first — disclosed double-lane landing);
# THIS leg adds what that lane could not: the composition census above, the
# truth-PRESENCE arms (the scoped ws://-only heading, the roSecureSocket
# deferred-option sentences — a cure only needs to survive being DELETED, the
# conviction arms do not catch that), and the dead-pointer arm for the era's
# "worklog §" citations (no SyncPlay worklog exists in-repo; the sibling lane
# re-anchored README/TASK but left source/lib/SyncPlayProtocol.brs' §5 note).
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

PLAYER = "components/PlayerScene.brs"
TASK = "components/SyncPlayTask.brs"
PROTO = "source/lib/SyncPlayProtocol.brs"
README = "README.md"
UTILS = "source/lib/Utilities.brs"
DOCS = "docs/static-checks.md"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK54: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def func_body(text, name):
    m = re.search(r"(?ms)^(function|sub) %s\(.*?^(end function|end sub)" % re.escape(name), text)
    return m.group(0) if m else None


def require(haystack, where, needle, why):
    if haystack is None:
        return
    if needle not in haystack:
        problems.append(f"  {where} - CHECK54: {needle!r} missing — {why}")


# ---- R1 the dial composition: one node home, refusal-ordered, port-forced ----
raw = read(PLAYER)
pcode = mask(raw) if raw is not None else None

homes = []
for base in ("components", "source"):
    for root, _dirs, files in os.walk(base):
        for fn in sorted(files):
            if not fn.endswith(".brs"):
                continue
            path = os.path.join(root, fn)
            text = read(path)
            if text is None:
                continue
            if re.search(r'CreateObject\("roSGNode",\s*"SyncPlayTask"\)', mask(text)):
                homes.append(path)
if len(homes) != 1:
    problems.append(f"  CHECK54 R1: the SyncPlayTask node must be instantiated from exactly one site — found {len(homes)} {homes}. Every extra instantiator is a credentialed dial this gate does not see")

ct = func_body(pcode, "ConnectSyncTask")
if ct is None:
    problems.append(f"  {PLAYER} - CHECK54 R1: sub ConnectSyncTask() vanished — the dial's only home has no shape to pin")
else:
    i_parts = ct.find("BuildSyncPlayWsParts()")
    i_guard = ct.find("if parts = invalid")
    i_probe = ct.find("SyncPlayWsRefusedForOrigin(GetServerUrl())")
    i_node = ct.find('CreateObject("roSGNode", "SyncPlayTask")')
    for idx, what in ((i_parts, "the parts-builder call"), (i_guard, "the invalid-parts guard"),
                      (i_probe, "the honest-reason refusal probe"), (i_node, "the node instantiation")):
        if idx < 0:
            problems.append(f"  {PLAYER} - CHECK54 R1: ConnectSyncTask lost {what} — the choke that keeps the bearer JWT off an unrefused socket is gone")
    if -1 not in (i_parts, i_guard, i_probe, i_node) and not (i_parts < i_guard < i_probe < i_node):
        problems.append(f"  {PLAYER} - CHECK54 R1: ConnectSyncTask order broke (builder->guard->refusal-probe->instantiation) — a task that can be created before the refusal decides is a task that can dial refused origins")

b = func_body(pcode, "BuildSyncPlayWsParts")
if b is None:
    problems.append(f"  {PLAYER} - CHECK54 R1: function BuildSyncPlayWsParts() vanished — no parts builder to census")
else:
    require(b, PLAYER, "SyncPlayWsRefusedForOrigin(serverUrl) then return invalid",
            "the builder must refuse TLS origins in-code, not hope the caller checked (M-ROKU-14 choke)")
    require(b, PLAYER, "port: 8097",
            "the dial port is FORCED to the SyncPlay worker, never inherited from the stored origin's port")

tp = func_body(pcode, "ToggleSyncPanel")
require(tp, PLAYER, 'GetConnectionKind() = "hub"',
        "hub mode must stay choked at the panel entry — no relay path is implemented, so the JWT has nowhere honest to ride")

# ---- R2 truth present: the scoped transport law must SURVIVE, not just not-lie ----
r = read(README)
require(r, README, "**`ws://` only — this build ships no `wss://` path.**",
        "the M22 rotation scoped the heading to the BUILD, and the heading is the user-facing law — silent deletion is the same misinformation as the old false claim")
require(r, README, "roSecureSocket` exists",
        "README must keep naming the platform's TLS client socket as a deferred arm (the misclaim cure this item filed)")
require(r, README, "stays a deferred",
        "README must keep the wss migration documented as deferred, not as impossibility")
t = read(TASK)
require(t, TASK, "BUILD limitation",
        "the task header must keep scoping ws-only-ness to the build")
require(t, TASK, "roSecureSocket exists",
        "the task header must keep naming roSecureSocket — the header is what a maintainer reads before touching the transport")
p = read(PROTO)
require(p, PROTO, "SPEC §5",
        "the client clock sync loop must keep its wire-contract citation")

# ---- R3 extinct: the era's dead worklog pointers (scoped to M22's files) ------
dead = re.compile(r"worklog\s*§|See the worklog")
for path in (README, TASK, PROTO, PLAYER, UTILS, DOCS):
    text = read(path)
    if text is None:
        continue
    hits = [n + 1 for n, line in enumerate(text.split("\n")) if dead.search(line)]
    if hits:
        problems.append(f"  {path} - CHECK54 R3: dead worklog pointer back at line(s) {hits} — no SyncPlay worklog exists in-repo; prose must cite README/static-checks rows, not vanished history (LiveTV/LivePlayer 'See the worklog.' lines are a different feature's prose debt, out of this scope)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK54: %d SyncPlay dial-composition/truth pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK54: the SyncPlayTask dial composes through the single refusal-ordered")
print("           site (builder -> invalid guard -> refusal probe -> node), the")
print("           parts force port 8097 from the authenticated origin, hub mode is")
print("           choked at the panel, the scoped ws-only law and the roSecureSocket")
print("           deferred-arm prose are present, and no dead worklog pointer")
print("           survives in the M22 file set")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1
echo "=== Check 55: the hub relay refuses the plaintext :8804 dial behind https origins (M-ROKU-23) ==="
# HUB RELAY PLAINTEXT-ORIGIN LAW (M-ROKU-23, review roku__secnet M2):
# StartHubCommandConsumer stripped the hub URL's scheme and dialled the FIXED
# plaintext :8804 relay listener regardless of the hub origin — a raw
# roStreamSocket handshake carrying the hub MINTED relay token
# (Authorization: Bearer; the holder can push "Alexa, play X" commands into
# the user's session) across cleartext while the hub's own identity was TLS.
# A passive path sniffer could capture a live credential AND inject playback
# behind the advertised TLS. The cure applies the M-ROKU-14 doctrine
# (4240ad2, :8097 leg) to the relay leg: the pure predicate
# HubRelayCleartextRefusedForOrigin refuses the cleartext dial for https
# origins at the scene choke BEFORE the credential is read and again at the
# task before any mint (defense in depth); http/legacy origins keep
# byte-identical behavior (their REST lane is already cleartext — no NEW
# exposure class). The wss arm via roSecureSocket is DEFERRED with disclosure
# (the hub's TLS front-end already routes GET /syncplay/ to the worker —
# phlix-hub docs/websockets.md), NOT declared platform-impossible (the
# edbbd8a doctrine on the sibling leg). The dial needs registry + live hub
# nodes, so these statement-presence legs are the gate (CHECK50-53
# precedent; device honesty disclosed in the fixlog). They also pin the
# device-safety lesson this lane learned the hard way: the law predicate body
# uses ONLY the 1-based global string surface — member .Mid (0-based on the
# platform) and member .Lower (NOT a Roku string member at all) are convicted
# in this family's law code.
#   R1 Utilities: the predicate exists with its Boolean signature and the
#      exact `return Left(s, 8) = "https://"` shape, and its body contains no
#      `.Mid(` and no `.Lower(` (device-safe globals only);
#   R2 PhlixApp: StartHubCommandConsumer refuses hubUrl via the predicate
#      BEFORE `token = GetStorage().get("auth_token")` (refuse-before-
#      credential order, M-ROKU-14 doctrine) and the stale
#      "(http://host[:port])" comment that papered over the scheme-strip is
#      extinct;
#   R3 HubCommandTask: RunConsumer refuses apiBase via the predicate before
#      `MintAndConnect(`; the plaintext arm stays wired for http hubs
#      (CreateObject("roStreamSocket") present); NO roSecureSocket
#      instantiation ships (the deferred arm stays unbuilt — zero unverified
#      platform calls); the task XML must script-include Utilities.brs — a
#      component scope does NOT auto-include pkg:/source, so without the
#      include the predicate call is an unresolved symbol (bsc BS1140; the
#      SyncPlayTask.xml Storage+Utilities+Protocol closure is the twin);
#   R4 docs law: the README names the fixed :8804, the refusal and the
#      deferred arm; the task header keeps REFUSES + DEFERRED and never
#      re-grows the plaintext-by-assertion phrase;
#   R5 CHANGELOG names M-ROKU-23 (measured forward-only law).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

UTIL = "source/lib/Utilities.brs"
APP = "components/PhlixApp.brs"
TASK = "components/HubCommandTask.brs"
README = "README.md"
CHANGE = "CHANGELOG.md"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK55: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def func_body(text, name):
    m = re.search(r"(?ms)^(function|sub) %s\(.*?^(end function|end sub)" % re.escape(name), text)
    return m.group(0) if m else None


def require(haystack, where, needle, why):
    if haystack is None:
        return
    if needle not in haystack:
        problems.append(f"  {where} - CHECK55: {needle!r} missing — {why}")


util = read(UTIL)
app = read(APP)
task = read(TASK)
readme = read(README)
change = read(CHANGE)

# ---- R1 the predicate: exact shape, device-safe globals only ----------------
if util is not None:
    ucode = mask(util)
    pred = func_body(ucode, "HubRelayCleartextRefusedForOrigin")
    if pred is None:
        problems.append(f"  {UTIL} - CHECK55 R1: function HubRelayCleartextRefusedForOrigin() vanished — the hub-relay origin law has no home")
    else:
        require(pred, UTIL, "as Boolean", "the predicate must return a Boolean")
        require(pred, UTIL, 'return Left(s, 8) = "https://"', "the refusal must be exactly the documented https:// shape (global Left, 1-based)")
        if ".Mid(" in pred:
            problems.append(f"  {UTIL} - CHECK55 R1: the predicate body calls the member .Mid — ifStringOps indices are 0-based while the globals are 1-based; law code uses the global Mid only (M-ROKU-23 device-safety law)")
        if ".Lower(" in pred:
            problems.append(f"  {UTIL} - CHECK55 R1: the predicate body calls the member .Lower — Roku strings have NO Lower member (ifStringOps lists none); the call is a device runtime error; use the global LCase (M-ROKU-23 device-safety law)")

# ---- R2 scene choke: refuse BEFORE the credential is read -------------------
if app is not None:
    acode = mask(app)
    shc = func_body(acode, "StartHubCommandConsumer")
    if shc is None:
        problems.append(f"  {APP} - CHECK55 R2: sub StartHubCommandConsumer() vanished — nothing gates the relay dial at the scene")
    else:
        require(shc, APP, "HubRelayCleartextRefusedForOrigin(hubUrl)", "the scene must refuse the cleartext relay dial for https hub origins")
        gate = shc.find("HubRelayCleartextRefusedForOrigin(hubUrl)")
        cred = shc.find('GetStorage().get("auth_token")')
        if gate != -1 and cred != -1 and not gate < cred:
            problems.append(f"  {APP} - CHECK55 R2: the refusal no longer PRECEDES the auth_token read — the credential must stay unreached on an origin whose dial is doomed to be refused (M-ROKU-14 order doctrine)")
    if app is not None and "(http://host[:port])" in app:
        problems.append(f"  {APP} - CHECK55 R2: the stale '(http://host[:port])' parse comment is back — it papered over the scheme-strip this cure convicted (docs-truth law)")

# ---- R3 task choke + plaintext arm present + no fabricated TLS --------------
if task is not None:
    tcode = mask(task)
    rc = func_body(tcode, "RunConsumer")
    if rc is None:
        problems.append(f"  {TASK} - CHECK55 R3: sub RunConsumer() vanished — the task-side defense in depth is gone")
    else:
        require(rc, TASK, "HubRelayCleartextRefusedForOrigin(apiBase)", "the task must refuse an https-origin config before anything mints or dials")
        gate = rc.find("HubRelayCleartextRefusedForOrigin(apiBase)")
        mint = rc.find("MintAndConnect(")
        if gate != -1 and mint != -1 and not gate < mint:
            problems.append(f"  {TASK} - CHECK55 R3: the task-side refusal no longer PRECEDES MintAndConnect — a cleartext socket could re-mint a token before refusal")
    require(tcode, TASK, 'CreateObject("roStreamSocket")', "the http/legacy plaintext arm must stay wired — the refusal narrows its origins, it does not retire the arm")
    if 'CreateObject("roSecureSocket"' in tcode:
        problems.append(f"  {TASK} - CHECK55 R3: a roSecureSocket instantiation appeared — the wss relay arm is DEFERRED pending on-device API verification; zero unverified platform calls ship (M-ROKU-23 floor, edbbd8a doctrine)")
    xml = read("components/HubCommandTask.xml")
    if xml is None:
        problems.append("  components/HubCommandTask.xml - CHECK55 R3: unreadable/missing — the task scope pin cannot run vacuously")
    elif "pkg:/source/lib/Utilities.brs" not in xml:
        problems.append(f"  components/HubCommandTask.xml - CHECK55 R3: the Utilities.brs script-include is gone — the task scope cannot resolve HubRelayCleartextRefusedForOrigin; component scopes do NOT auto-include pkg:/source (SyncPlayTask.xml is the twin)")

# ---- R4 docs law -------------------------------------------------------------
if readme is not None:
    rl = readme.lower()
    for needle, why in [
        ("command-consumer origin law", "the README hub section must carry the named M-ROKU-23 command-consumer origin law paragraph (the fixed plaintext :8804 dial, its refusal and the deferred wss arm)"),
        ("refus", "the README must state the https-origin refusal (M-ROKU-23 law)"),
        ("deferred", "the README must disclose the wss roSecureSocket arm as DEFERRED, not impossible (edbbd8a doctrine)"),
    ]:
        if needle not in rl:
            problems.append(f"  {README} - CHECK55 R4: {needle!r} missing — {why}")
if task is not None:
    if "NO TLS and NO WebSocket" in task:
        problems.append(f"  {TASK} - CHECK55 R4: the plaintext-by-assertion header is back ('NO TLS and NO WebSocket') — transport reality ships WITH the refusal law and the deferred wss arm, never as a bare limitation (M-ROKU-22 doctrine applies to this leg too)")
    for needle, why in [("REFUSES", "the task header must name the https-origin refusal law (M-ROKU-23)"), ("DEFERRED", "the task header must disclose the wss arm as deferred")]:
        if needle not in task:
            problems.append(f"  {TASK} - CHECK55 R4: {needle!r} missing — {why}")

# ---- R5 CHANGELOG names the item --------------------------------------------
if change is not None:
    require(change, CHANGE, "M-ROKU-23", "the measured CHANGELOG law: the landing names its item")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK55: %d hub-relay origin-law pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK55: the hub relay refuses the plaintext :8804 dial behind https")
print("           origins — the scene choke precedes the auth_token read, the")
print("           task choke precedes the mint, http/legacy hubs keep their")
print("           exact pre-cure behavior, and the wss arm is DEFERRED-")
print("           DISCLOSED (never fabricated, never declared impossible)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 56: the dead SyncPlay room files stay truthfully dead — docs-claim-vs-instantiation-site law (M-ROKU-26) ==="
# DEAD-PATH DOCUMENTATION-TRUTH LAW (M-ROKU-26, review roku__writer M2):
# components/SyncPlayScene.{brs,xml} is instantiated nowhere (no CreateObject, no XML
# child, no route) and source/lib/SyncPlayManager.brs has exactly ONE caller — dead
# SyncPlayScene.brs. The LIVE watch-together flow is PlayerScene's overlay driving
# components/SyncPlayTask directly (PlayerScene.brs:1800). The writer review caught
# docs describing this dead pair as live machinery; the i18n.md consumer row was
# annotated @ab050d5, but the README tree, CHECK 23's prose, the api-envelope row,
# Utilities' local-family comments and the shipped files themselves still read live.
# This leg pins BOTH directions of that contract:
#   R1 (code truth): the room scene stays uninstantiated and the manager stays called
#      only by the dead pair. If a lane ever wires the room, this arm goes RED on
#      purpose — the docs' dead-path claims must be re-cut in the same commit.
#   R2 (docs truth): the demotion markers ("DEAD PATH — not wired into the shipped
#      UI", the README retention note, the per-file banners, the CHECK 23 /
#      api-envelope annotations, the i18n.md consumer rows — positive survive-
#      delete on the `syncplay` row plus a dead-marker law over EVERY table row
#      naming the scene, r2 cure of review M-ROKU-26 r1 MAJOR-1 — , the Utilities
#      law note) must be PRESENT — a cure that can be silently deleted is the same
#      misinformation as the old false claim (CHECK 54 R2's survival idiom).
#   R3 (provenance truth): every locale's _metadata.source_files keeps listing
#      components/SyncPlayScene.brs. The field means "source files that OWN the
#      strings" (docs/i18n.md), the scene ships, and its keys are physically extracted
#      from it (Check 24 stages SyncPlayScene.brs as the sole consumer of
#      syncplay_members_count). Deleting the entry would falsify provenance; retiring
#      the files/key-sets must rotate this arm in the same commit (disclosed rotation).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

SCENE_BRS = "components/SyncPlayScene.brs"
SCENE_XML = "components/SyncPlayScene.xml"
MANAGER = "source/lib/SyncPlayManager.brs"
README = "README.md"
DOCS = "docs/static-checks.md"
ENVELOPE = "docs/api-envelope.md"
I18N = "docs/i18n.md"
UTILS = "source/lib/Utilities.brs"

DEAD_MARKER = "DEAD PATH — not wired into the shipped UI"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK56: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def require(haystack, where, needle, why):
    if haystack is None:
        return
    if needle not in haystack:
        problems.append(f"  {where} - CHECK56: {needle!r} missing — {why}")


# ---- R1 instantiation census: the room stays unwired, by code -------------
scene_re = re.compile(r'CreateObject\(\s*"SyncPlayScene"|CreateObject\(\s*"roSGNode",\s*"SyncPlayScene"\s*\)')
manager_call_re = re.compile(r'(?<!function )\bSyncPlayManager\(')

for base in ("components", "source"):
    for root, _dirs, files in os.walk(base):
        for fn in sorted(files):
            if not fn.endswith(".brs"):
                continue
            path = os.path.join(root, fn)
            text = read(path)
            if text is None:
                continue
            coded = mask(text)
            for m26 in scene_re.finditer(coded):
                problems.append(f"  {path} - CHECK56 R1: the SyncPlayScene node is instantiated ({coded[m26.start():m26.start()+60]!r}) — the room scene is NOT wired into the shipped UI per README/§6, every doc naming it DEAD PATH is now a lie, and the wire-vs-retire owner decision was bypassed silently; re-cut the R2 doc set and rotate this pin in the same commit")
            if path != MANAGER:
                for line in coded.split("\n"):
                    if manager_call_re.search(line) and path != SCENE_BRS:
                        problems.append(f"  {path} - CHECK56 R1: SyncPlayManager is constructed here — its only lawful caller is the dead {SCENE_BRS}; a live caller makes the 'dead pair' docs false: {line.strip()!r}")

for root, _dirs, files in os.walk("components"):
    for fn in sorted(files):
        if not fn.endswith(".xml"):
            continue
        path = os.path.join(root, fn)
        if path == SCENE_XML:
            continue
        text = read(path)
        if text is None:
            continue
        for needle, why in (
            ("<SyncPlayScene", "a live XML graph embeds the room scene — that IS instantiation; docs must be re-cut with the wiring"),
            ('uri="pkg:/components/SyncPlayScene.brs"', "a live XML graph loads the dead scene's script — the pair is being wired"),
            ('uri="pkg:/source/lib/SyncPlayManager.brs"', "a live XML graph loads the dead manager's script — the manager is being wired"),
        ):
            if needle in text:
                problems.append(f"  {path} - CHECK56 R1: {needle!r} — {why}")

# ---- R2 truth present: every demotion marker survives ---------------------
r = read(README)
if r is not None:
    for line in r.split("\n"):
        if "SyncPlayManager.brs" in line and "#" in line and DEAD_MARKER not in line:
            problems.append(f"  {README} - CHECK56 R2: the SyncPlayManager.brs tree row lost its {DEAD_MARKER!r} demotion — the row described dead machinery in live-tense for a whole era (review roku__writer M2) and must not silently revert: {line.strip()!r}")
        if "components/SyncPlayScene" in line and "DEAD PATH" not in line:
            problems.append(f"  {README} - CHECK56 R2: a README row names components/SyncPlayScene without a DEAD PATH marker — the shipped-UI-architecture law is 'no separate SyncPlay scene'; name the retention explicitly: {line.strip()!r}")
    require(r, README, "**Room-scene retention (dead path).**",
            "the §6 retention note is the user-visible truth that the room files are unreachable from the shipped UI (owner wire-vs-retire stays open; the docs may not claim live)")
    require(r, README, "Check 56",
            "README must cite the gate that keeps these claims honest")

for path in (SCENE_BRS, SCENE_XML, MANAGER):
    t = read(path)
    if t is not None:
        require(t, path, DEAD_MARKER,
                "the reader who opens a dead file must learn it is dead THERE — this is the file a contributor reads before 'fixing a bug in the SyncPlay scene' (the day-waster the review named)")

d = read(DOCS)
if d is not None:
    row23 = [line for line in d.split("\n") if line.startswith("| 23 |")]
    if not row23:
        problems.append(f"  {DOCS} - CHECK56 R2: the Check 23 table row vanished — its prose names the dead pair's error sites and must carry the not-instantiated annotation")
    else:
        require(row23[0], f"{DOCS} row 23", "not-instantiated",
                "CHECK 23's example prose cited 'SyncPlayScene REST-path failures' as if they occur live; the annotation is the cure")
    if not [line for line in d.split("\n") if line.startswith("| 56 |")]:
        problems.append(f"  {DOCS} - CHECK56 R2: no row 56 in the checks table — the ledger must enumerate this gate (this leg self-pins its ledger row, the house truth-presence idiom)")

e = read(ENVELOPE)
if e is not None:
    for line in e.split("\n"):
        if "SyncPlayManager" in line and "dead path" not in line:
            problems.append(f"  {ENVELOPE} - CHECK56 R2: the SyncPlayManager mention lost its 'dead path' annotation — the envelope story must not imply the manager runs: {line.strip()!r}")

i18 = read(I18N)
if i18 is not None:
    # POSITIVE survive-delete presence (r2 cure, review M-ROKU-26 r1 MAJOR-1):
    # the r1 arm was conditional-shape only — deleting the syncplay row outright
    # (plant V1) or rewriting it live-tense without the components/ prefix
    # (plant V2) passed VACUOUSLY at fa67902 (both measured exit 0), while the
    # row's own contract text advertised a survive-delete tooth. The row must
    # now EXIST and carry the demotion. And every consumer-table row naming the
    # scene file — bare or prefixed — must carry a dead marker: that general
    # law arms the r1 MINOR-1 survivor (the `errors` row presenting the dead
    # scene as a live law-driven consumer), so the annotation shipped for :71
    # cannot silently decay one line away from the row the review cured @ab050d5.
    sync_rows = [line for line in i18.split("\n") if line.startswith("| `syncplay`")]
    if not sync_rows:
        problems.append(f"  {I18N} - CHECK56 R2: the `syncplay` consumer-table row vanished entirely — the row carries the scene's '**not instantiated**' demotion (shipped @ab050d5); deleting it re-claims the dead room as live by omission (r1 plant V1, survive-delete)")
    else:
        require(sync_rows[0], f"{I18N} `syncplay` row", "**not instantiated**",
                "the syncplay consumer-table row lost its demotion annotation — the room scene is dead machinery and this row is where a reader of the consumer table learns it (r1 plant V2, survive-delete)")
    for line in i18.split("\n"):
        if not line.startswith("| `"):
            continue
        if "SyncPlayScene.brs" in line and "**not instantiated**" not in line and "DEAD PATH" not in line:
            problems.append(f"  {I18N} - CHECK56 R2: a consumer-table row names SyncPlayScene.brs without a dead marker (bare or prefixed) — the `errors` row presented the dead scene as a live law-driven errors consumer for an era (r1 MINOR-1); name the dead path explicitly: {line.strip()[:80]!r}")

# ROK-12 mirror carriers: contributor-facing docs that name SyncPlayManager must
# carry the dead marker on the same line (and must keep naming it, so a delete is loud).
for mirror in ("DEVELOPER.md", "CLAUDE.md"):
    mt = read(mirror)
    if mt is None:
        continue
    mlines = [ln for ln in mt.split("\n") if "SyncPlayManager" in ln]
    if not mlines:
        problems.append(f"  {mirror} - CHECK56 R2: no SyncPlayManager mention — the mirror carrier vanished; the dead-marker law needs its line")
    for ln in mlines:
        if DEAD_MARKER not in ln:
            problems.append(f"  {mirror} - CHECK56 R2: a SyncPlayManager line lost its {DEAD_MARKER!r} marker (ROK-12): {ln.strip()[:100]!r}")

u = read(UTILS)
require(u, UTILS, "DEAD-PATH NOTE (M-ROKU-26, Check 56)",
        "the local-error family docblock says these codes are 'produced ON THIS DEVICE' — half of them (the room REST path) are produced by code that never runs; the law note keeps that honest")

# ---- R3 provenance kept: catalogs still list the dead scene as owner ------
locale_root = "locale"
try:
    locales = sorted(d for d in os.listdir(locale_root) if os.path.isdir(os.path.join(locale_root, d)))
except OSError as err:
    locales = []
    problems.append(f"  {locale_root} - CHECK56 R3: unreadable: {err} — the pin cannot run vacuously")
if len(locales) != 7:
    problems.append(f"  CHECK56 R3: expected SEVEN locale dirs, found {len(locales)} {locales} — the provenance pin must not run against a truncated set")
for loc in locales:
    path = os.path.join(locale_root, loc, "strings.json")
    text = read(path)
    if text is None:
        continue
    try:
        meta = json.loads(text).get("_metadata", {})
    except (ValueError, AttributeError) as err:
        problems.append(f"  {path} - CHECK56 R3: unparsable or shape-broken catalog: {err}")
        continue
    src = meta.get("source_files")
    if not isinstance(src, list) or SCENE_BRS not in src:
        problems.append(f"  {path} - CHECK56 R3: _metadata.source_files no longer lists {SCENE_BRS} — the field means 'source files that own the strings' and the scene ships and owns the syncplay/*_room keys (Check 24 proves the consumer); retiring the files/key-sets must rotate this arm and the i18n.md row in the SAME commit")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK56: %d dead-SyncPlay-path doc/instantiation pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK56: the SyncPlay room scene has zero instantiation sites and its manager")
print("           is called only by the dead pair; the README tree/retention note, the")
print("           three per-file DEAD PATH banners, the CHECK 23 row, the api-envelope")
print("           row, the i18n.md consumer rows (positive survive-delete on the")
print("           `syncplay` row plus the table dead-marker law) and the Utilities law")
print("           note all carry the demotion truth, and all seven catalogs keep the scene as a")
print("           provenance owner — the dead path can neither be silently wired nor")
print("           silently re-claimed as live")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 57: the co-watch feature speaks with one name (M-ROKU-25) ==="
# ONE-NAME LAW (M-ROKU-25, review roku__writer M1): the co-watch feature had
# five names, three of them live on TV (Watch Together / group / Room /
# watch parties / watch room + sync server, plus user-visible "SyncPlay").
# The ruling: user-visible concept = GROUP, feature name = WATCH TOGETHER;
# room/party/session/"sync server"/user-visible SyncPlay are dead vocabulary
# in en_US values, and the created group defaults to "<device>'s Group".
# The README carried the whole drift in one sentence ("press Create Group to
# start a new room") — cured here; docs/i18n.md's "Watch-party room UI" —
# cured here. Carve-outs are ruling-anchored, not drift: CON-07 — catalog KEY
# names are code identifiers (they mirror wire/client codes through Check 23)
# and never rename; the six syncplay.*_room chrome keys+values belong to the
# DEAD SyncPlayScene ("keep the *_room keys only if the dead scene survives";
# wire-vs-retire is an owner call, docs/i18n.md). Non-en_US locales are the
# sibling i18n lane's domain (key parity is Check 19/20/24/25's law, all
# unchanged here); auth-context "session" (player.err_session_expired etc.)
# is a different concept — the law kills the word as a co-watch NAME. The
# review's own example 'Couldn't reach the watch session.' contradicted its
# kill-session clause; the same review's rubric ("server (direct)") governs,
# so the sync-server family became "the server" (disclosed in
# .reviews/fixlog/M-ROKU-25__fix.md).
# Pinned statically:
#   R1  vocabulary conviction over the co-watch key scope (all errors.*, all
#       syncplay.* except the pinned carve-out, player.party_*/sync_*/
#       create_group/leave): no value carries a convicted name;
#   R2  the create command defaults deviceName + "'s Group" and the old "'s
#       Room" spelling is extinct across components/ + source/;
#   R3  the room/party KEY census is frozen at exactly the 6 carve-out + 13
#       identifier mirrors — silent growth or rename reddens;
#   R4  README + docs/i18n.md never spell "watch party", and the Create Group
#       step says you start a new group.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

CAT = "locale/en_US/strings.json"
README = "README.md"
I18N = "docs/i18n.md"
PLAYER = "components/PlayerScene.brs"

# Dead-scene carve-out (SyncPlayScene chrome; keys AND values stay per the
# M1 ruling + owner-gated wire-vs-retire. R3 freezes this exact set.)
DEAD_ROOM = {
    "syncplay.default_room_name", "syncplay.label_room_name",
    "syncplay.label_public_room", "syncplay.create_room",
    "syncplay.public_rooms", "syncplay.leave_room",
}
# Key names mirroring wire/client codes or the banner function family
# (CON-07: identifiers ride forever; values above already speak group/Watch
# Together).
IDENTIFIER_KEYS = {
    "errors.local_room_create_failed", "errors.local_room_join_failed",
    "errors.local_room_leave_failed", "errors.local_invalid_room",
    "player.party_connected", "player.party_disconnected",
    "player.party_error_fallback", "player.party_host_changed",
    "player.party_host_paused", "player.party_host_position",
    "player.party_host_resumed", "player.party_member_joined",
    "player.party_you_are_host",
}
CONVICTED = re.compile(r"(?i)\broom\b|\bpart(y|ies)\b|\bsession\b|sync server|\bSyncPlay\b")
DOC_PARTY = re.compile(r"(?i)watch[- ]part")

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK57: unreadable: {err} — the pin cannot run vacuously")
        return None


# ---- R1 vocabulary conviction over the co-watch key scope -------------------
data = None
raw = read(CAT)
if raw is not None:
    try:
        data = json.loads(raw)
    except ValueError as err:
        problems.append(f"  {CAT} - CHECK57 R1: unreadable: {err} — the pin cannot run vacuously")

if isinstance(data, dict):
    scope = {}
    for sec in ("errors", "syncplay"):
        for k, v in (data.get(sec) or {}).items():
            if f"{sec}.{k}" in DEAD_ROOM:
                continue
            scope[f"{sec}.{k}"] = v
    for k, v in (data.get("player") or {}).items():
        if k.startswith(("party_", "sync_")) or k in ("create_group", "leave"):
            scope[f"player.{k}"] = v
    for key in sorted(scope):
        v = scope[key]
        if not isinstance(v, str):
            continue
        m = CONVICTED.search(v)
        if m:
            problems.append(f"  {CAT} - CHECK57 R1: {key} = {v!r} carries the convicted name {m.group(0)!r} — the concept is 'group', the feature is 'Watch Together'")

# ---- R2 the default group name is its concept -------------------------------
player = read(PLAYER)
if player is not None and "group_name: deviceName + \"'s Group\"" not in player:
    problems.append("  components/PlayerScene.brs - CHECK57 R2: the create command must default the group name to deviceName + \"'s Group\" (the M1 ruling renamed the \"Room\" default)")
for base in ("components", "source"):
    for root, _dirs, files in os.walk(base):
        for fn in sorted(files):
            if not fn.endswith((".brs", ".xml")):
                continue
            path = os.path.join(root, fn)
            text = read(path)
            if text is None:
                continue
            hits = [n + 1 for n, line in enumerate(text.split("\n")) if "'s Room" in line]
            if hits:
                problems.append(f"  {path}:{hits} - CHECK57 R2: the renamed default came back ('s Room) — the concept is 'group'")

# ---- R3 the room/party key-name census is a closed set ----------------------
if isinstance(data, dict):
    found = set()
    for sec, vals in data.items():
        if isinstance(vals, dict):
            for k in vals:
                if re.search(r"(?i)room|party", k):
                    found.add(f"{sec}.{k}")
    pinned = DEAD_ROOM | IDENTIFIER_KEYS
    for key in sorted(found - pinned):
        problems.append(f"  {CAT} - CHECK57 R3: new room/party key {key} — the co-watch identifier set is closed; grow it (with 7-family parity) or not at all")
    for key in sorted(pinned - found):
        problems.append(f"  {CAT} - CHECK57 R3: pinned identifier key {key} vanished — key renames break the Check 23 code-mirror law; retire only with the owner's SyncPlayScene wire-vs-retire call")

# ---- R4 the docs speak the one name -------------------------------------------
for doc in (README, I18N):
    text = read(doc)
    if text is None:
        continue
    hits = [n + 1 for n, line in enumerate(text.split("\n")) if DOC_PARTY.search(line)]
    if hits:
        problems.append(f"  {doc}:{hits} - CHECK57 R4: a 'watch party' spelling survived in the docs — searchable drift the census convicted")
readme = read(README)
if readme is not None:
    if 'to start a new group (named `"<device>\'s Group"`' not in readme:
        problems.append('  README.md - CHECK57 R4: the Create Group step must say you start a new GROUP named "<device>\'s Group" — the button/thing drift was the item in one sentence')
    if "to start a new room" in readme:
        problems.append("  README.md - CHECK57 R4: 'to start a new room' is back")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK57: %d co-watch vocabulary pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK57: the co-watch feature speaks with one name — no convicted room/party/")
print("           session/'sync server'/SyncPlay spelling survives in the scoped en_US")
print("           values, the created group defaults to \"<device>'s Group\", the")
print("           room/party key census is frozen at the 6 dead-scene carve-outs + 13")
print("           Check-23 identifier mirrors, and README + docs/i18n.md name the")
print("           feature Watch Together only")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 58: the Retry recovery path hands the strip back (M-ROKU-21f) ==="
# RETRY RECOVERY-CHROME LAW (M-ROKU-21f, review roku__gameux M21 r2 MINOR-1):
# The M21 failure-vs-emptiness cure gave HomeScene a Retry control whose press
# writes the transient loading copy (Translate("common_loading")) into the
# description strip while the failed rails re-load. Its stand-down guard,
# HideHomeRailFailureIfHealthy, recognized ONLY the failure copy — after a
# SUCCESSFUL retry both flags clear, the guard's equality fails, and the strip
# stays "Loading..." over a healthy app until the user happens to focus an
# item (the focused handlers' self-heal). Cosmetic chrome, but the same
# state-legibility class in miniature: a completed load must not look like an
# in-flight one. Cure: the guard restores the default chrome from EITHER copy
# it owns — failure OR retry-stranded loading — behind the healthy-gate. The
# recognition is safe because OnRetryPressed is the SOLE writer of
# common_loading to the description strip (boot loading rides the separate
# loadingLabel; ApplyXmlChrome's default is home_select_library) — R2 proves
# that sole-writer fact repo-wide, so the extended guard can never overwrite a
# legitimate live loading state or an item caption the user focused meanwhile.
# R1 keeps the healthy-gate early return pinned: a partial recovery must still
# let the other rail's failure copy stand (Check 32 shared-slot law intact).
# CHECK52 owns the failure-branch topology and is deliberately guard-agnostic;
# this leg owns the recovery half of the same 4-state model.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

HOME = "components/HomeScene.brs"
TRANSIENT = 'm.descriptionLabel.text = Translate("common_loading")'

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK58: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def func_body(text, name):
    m = re.search(r"(?ms)^(function|sub) %s\(.*?^(end function|end sub)" % re.escape(name), text)
    return m.group(0) if m else None


home = read(HOME)
if home is not None:
    hcode = mask(home)

    # ---- R1 the stand-down guard owns BOTH transient copies ----------------
    hb = func_body(hcode, "HideHomeRailFailureIfHealthy")
    if hb is None:
        problems.append(f"  {HOME} - CHECK58 R1: sub HideHomeRailFailureIfHealthy() vanished — nothing ever hands the strip back")
    else:
        for needle, why in (
            ("if m.librariesFailed or m.continueFailed then return",
             "the healthy-gate early return is gone — a partial recovery would strip the still-failed rail's copy"),
            ("strip = m.descriptionLabel.text",
             "the guard no longer snapshots the strip text it decides on — the shape this leg pins drifted"),
            ('if strip = Translate("home_rail_failed") or strip = Translate("common_loading") then',
             "the restore guard is back to recognizing only the failure copy — a successful Retry strands the strip on the loading copy (review M21 r2 MINOR-1 re-grown)"),
            ('m.descriptionLabel.text = Translate("home_select_library")',
             "the stand-down never hands the strip back to its default chrome"),
        ):
            if needle not in hb:
                problems.append(f"  {HOME} - CHECK58 R1: {needle!r} missing — {why}")

    # ---- R2 the loading copy is OnRetryPressed's SOLE write-site -----------
    rb = func_body(hcode, "OnRetryPressed")
    if rb is None:
        problems.append(f"  {HOME} - CHECK58 R2: sub OnRetryPressed() vanished — the Retry control would be theater")
    elif TRANSIENT not in rb:
        problems.append(f'  {HOME} - CHECK58 R2: OnRetryPressed no longer writes {TRANSIENT!r} — the transient copy R1 recognizes must be the one Retry itself writes')

writers = []
for scan_dir in ("components", "source"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".brs"):
                path = os.path.join(root, name)
                text = read(path)
                if text is None:
                    continue
                for lineno, line in enumerate(mask(text).split("\n"), 1):
                    if TRANSIENT in line:
                        writers.append(f"{path}:{lineno}")
if len(writers) != 1:
    problems.append(
        f"  {HOME} - CHECK58 R2: the description-strip loading copy is written {len(writers)}x {writers} — "
        f"OnRetryPressed must be the SOLE writer, or R1's recognition of common_loading can overwrite a "
        f"legitimate live loading state (the sole-writer fact the recovery-chrome law rests on)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK58: %d recovery-chrome pin(s) broken" % len(problems))
    sys.exit(1)

print('  CHECK58: the stand-down guard restores the default strip from the failure copy')
print('           AND the retry-stranded loading copy behind the healthy-gate, and')
print('           OnRetryPressed is the proven sole writer of that transient copy across')
print('           components/ + source/ — a completed retry can no longer read as a live')
print('           load, and no legitimate loading state can be stripped mid-flight')
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 59: the CHANGELOG describes the real release vehicle (M-ROKU-33) ==="
# CHANGELOG RELEASE-TRUTH LAW (M-ROKU-33, review roku__writer): the file carried
# exactly two '##' headers (## [Unreleased] + ## [R4.10] — 2026-08-05), so no
# shipped release was EVER listed — while the Package workflow had been publishing
# a rolling `latest` GitHub prerelease on every master push since 2026-06-28
# (`3b36606`). A prior fix report for this item proved wholly phantom (unreachable
# anchor sha, five fabricated "tag-verified" v1.0.0–v1.4.0 releases against a
# one-tag origin, three 404-ing CI run IDs — r1 review findings F1–F5). The cure
# names the vehicle that exists; this leg keeps it honest:
#   R1  ROLLING HEADER: a line starting '## [latest]' must exist — published
#       rolling-era history can never again be filed under an "unreleased" fiction
#   R2  MODEL-BLOCK TRUTH: the prose between the '## [latest]' header and the next
#       header must carry (whitespace-collapsed for wrapping) docs/publishing.md's
#       literal "exactly one tag (`latest`)", the "docs/publishing.md"
#       cross-reference, and the LIVE package.json version — a store-triple bump
#       without a CHANGELOG rotation reddens this arm
#   R3  ANTI-FABRICATION: every '## [token]' release header whose token is
#       version-shaped must be backed by a real git tag or the package.json
#       version — the phantom v1.x ladder class can never re-enter this file
# CHECK40 R4 pins the same vehicle from the package.yml + publishing.md side; this
# leg pins the CHANGELOG side, gate-independent of it.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, subprocess, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

CHANGE = "CHANGELOG.md"
HEADER = "## [latest]"
problems = []

pkg_version = None
try:
    pkg_version = json.load(open("package.json", encoding="utf-8")).get("version")
except (OSError, ValueError) as err:
    problems.append(f"  package.json - CHECK59: unreadable: {err} — the version-truth arm cannot run vacuously")

text = None
try:
    text = open(CHANGE, encoding="utf-8").read()
except OSError as err:
    problems.append(f"  {CHANGE} - CHECK59: unreadable: {err} — the pin cannot run vacuously")

if text is not None:
    lines = text.split("\n")
    header_at = [i for i, l in enumerate(lines) if l.startswith(HEADER)]

    # ---- R1 the rolling line is named what it is ----------------------------
    if not header_at:
        problems.append(
            f"  {CHANGE} - CHECK59 R1: no '## [latest]' header — the rolling sideload"
            " prerelease is the release vehicle (package.yml release-latest, every master"
            " push); shipped history is back under an [Unreleased] fiction (M-ROKU-33)")

    # ---- R2 the model block states the verified vehicle ---------------------
    collapsed = ""
    if header_at:
        start = header_at[0] + 1
        end = len(lines)
        for i in range(start, len(lines)):
            if lines[i].startswith("## ") or lines[i].startswith("### "):
                end = i
                break
        collapsed = re.sub(r"\s+", " ", "\n".join(lines[start:end]))
    for needle, why in (
        ("exactly one tag (`latest`)",
         "the CHANGELOG stopped sharing docs/publishing.md's literal tag-layer truth —"
         " the cross-truth between the two documents IS the M-ROKU-33 cure"),
        ("docs/publishing.md",
         "the release-model block lost its cross-reference to docs/publishing.md"),
    ):
        if not header_at or needle not in collapsed:
            problems.append(f"  {CHANGE} - CHECK59 R2: {needle!r} missing from the [latest] release-model block — {why}")
    if pkg_version and (not header_at or str(pkg_version) not in collapsed):
        problems.append(
            f"  {CHANGE} - CHECK59 R2: the live package.json version {pkg_version!r} is not stated"
            " in the [latest] release-model block — rotate this entry with any store-triple bump")

    # ---- R3 version-shaped headers need tag or version backing --------------
    def tag_backed(name):
        try:
            out = subprocess.run(["git", "tag", "-l", name], capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            return False
        return out.returncode == 0 and bool(out.stdout.strip())

    for lineno, line in enumerate(lines, 1):
        m = re.match(r"^## \[([^\]]+)\]", line)
        if not m:
            continue
        token = m.group(1).strip()
        if not re.fullmatch(r"v?\d+(?:\.\d+)+", token):
            continue
        bare = token[1:] if token.startswith("v") else token
        if token == pkg_version or bare == pkg_version or tag_backed(token) or tag_backed("v" + bare):
            continue
        problems.append(
            f"  {CHANGE}:{lineno} - CHECK59 R3: versioned release header {token!r} has NO"
            f" backing — not a git tag on this checkout and not the package.json version"
            f" {pkg_version!r} — the fabricated v1.0.0–v1.4.0 ladder the r1 review"
            " convicted (F3) can never re-enter this file")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK59: %d CHANGELOG release-truth pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK59: the CHANGELOG names the vehicle that exists — the [latest]")
print("           rolling line heads a model block carrying publishing.md's")
print("           exactly-one-tag literal, the publishing.md cross-reference and")
print("           the live store triple, and every version-shaped release header")
print("           stands on git-tag or version-field proof")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 60: README Project Structure mirrors the shipped .brs tree (M-ROKU-32) ==="
# STRUCTURE-MAP TRUTH LAW (M-ROKU-32, review roku__writer M8): the Project
# Structure block is the map a new developer navigates the codebase by, and it
# shipped four phantom landmarks (SessionManager/LibraryManager/TaskManager.brs —
# deleted in R7.5 per PhlixApp.xml's removal note — plus a source/data/Theme.brs
# that never existed here) while missing a real one (AppContext.brs) and the
# entire music/photos/favorites/search/settings/ApiTask component cohort. Every
# prior cure patched prose rows by hand; this leg makes the map SELF-PINNING:
# the set of *.brs names listed inside the block must equal, BIDIRECTIONALLY,
# the set of *.brs basenames on disk under source/ + components/ (the writer's
# own regeneration law: find source components -name '*.brs'). R1 kills phantoms
# (a listed name with no file); R2 kills misses (a shipped file the map omits).
# Basename equality is deliberate: the block is a tree, not a manifest, and the
# one legit collision (SkipButton.brs in source/player + components/) exists on
# both sides. Comment-only docblocks inside .brs files are irrelevant here —
# this scans the README, so the fenced block moving/closing unbalanced is itself
# a red (the map vanished). Re-add a deleted file under a stale name, ship a new
# .brs without listing it, or rename one without editing the map, and CI stops.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

text = open("README.md", encoding="utf-8").read()
m = re.search(r"^## Project Structure\s*\n\n```\n(.*?)\n```", text, re.S | re.M)
if m is None:
    print("  README.md - CHECK60: the '## Project Structure' fenced block vanished — the map itself is gone")
    sys.exit(1)
block = m.group(1)

listed = set(re.findall(r"[A-Za-z0-9_-]+\.brs", block))
if not listed:
    print("  README.md - CHECK60: the structure block lists zero .brs files — it cannot be a map")
    sys.exit(1)

actual = set()
for scan_dir in ("source", "components"):
    for root, dirs, names in os.walk(scan_dir):
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".brs"):
                actual.add(name)

for phantom in sorted(listed - actual):
    problems.append(f"  README.md - CHECK60 R1: structure block lists {phantom} — no such .brs exists under source/ or components/ (phantom landmark: deleted, renamed, or never shipped)")
for miss in sorted(actual - listed):
    problems.append(f"  README.md - CHECK60 R2: {miss} ships in the tree but the structure block omits it (missing landmark: the map is no longer complete)")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK60: %d structure-map entr(s) broken" % len(problems))
    sys.exit(1)

print(f"  CHECK60: the Project Structure map lists exactly the {len(listed)} shipped .brs")
print("           landmarks of source/ + components/ — no phantoms, no misses")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
echo ""
echo "=== Check 61: the docs' locale-family inventories enumerate locale/ (M-ROKU-37) ==="
# LOCALE-FAMILY ENUMERATION LAW (M-ROKU-37, review roku__docmaint-class): the
# locale/ directory is the family set — docs only describe it. The review lane
# recorded readers taking "plus six shipped sibling catalogs" as a SIX-family
# claim while seven families ship, and the README Project Structure tree
# under-enumerated the locale/ families (the tree's own exhaustive convention;
# the M-ROKU-32 regen already lists all seven rows — the R3 arm pins them).
# CHECK21 derives directories dynamically and never reads the docs; CHECK48
# carries its own hardcoded seven-list; CHECK60 (M-ROKU-32) mirrors the .brs
# landmarks. Nothing pinned docs locale claims to the directory until this leg
# (numbering note: 60 was claimed by the M32 lane mid-flight — renumbered per
# the collision law):
#   R1  i18n.md OVERVIEW states the total in words ("Seven locale families"),
#       the base-excluded sibling count in words, and enumerates every
#       directory tag on disk
#   R2  i18n.md Directory-Structure tree enumerates every locale directory
#       exactly once, no ghosts, no duplicates (survive-delete conviction)
#   R3  README Project-Structure tree enumerates every locale directory
#       exactly once, no ghost folder (M-ROKU-32's regen made this arm
#       green-at-base; its teeth are proven by plant P1)
#   R4  every folder's _metadata.locale equals the folder name — an inventory
#       line cannot point at a catalog that identifies itself as another family
# Fail-loud throughout: an unreadable locale/ or missing base convicts; the
# arms cannot run vacuously on an empty tree. CHECK60's .brs-mirror and
# CHECK21's content parity stay its gate-independent siblings.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

I18N = "docs/i18n.md"
README = "README.md"
problems = []

WORDS = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six",
         7: "seven", 8: "eight", 9: "nine", 10: "ten", 11: "eleven", 12: "twelve"}

# ---- fail-loud ground truth -------------------------------------------------
try:
    folders = sorted(d for d in os.listdir("locale")
                     if os.path.isdir(os.path.join("locale", d)))
except OSError as err:
    print(f"  locale/ - CHECK61: unreadable: {err} — the family-enumeration arms cannot run vacuously")
    sys.exit(1)
if not folders:
    print("  locale/ - CHECK61: zero locale directories — every docs family claim is false against an empty directory")
    sys.exit(1)
if "en_US" not in folders:
    problems.append("  locale/ - CHECK61 R0: no en_US directory — the docs' base-locale/fallback law cannot be true of this tree")
if len(folders) not in WORDS:
    print(f"  locale/ - CHECK61: {len(folders)} families on disk — outside the word-map; rotate WORDS deliberately with the set")
    sys.exit(1)
total_word, sib_word = WORDS[len(folders)], WORDS[len(folders) - 1]


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as err:
        problems.append(f"  {path} - CHECK61: unreadable: {err} — the pin cannot run vacuously")
        return None


def fenced_blocks(text):
    return re.findall(r"```[^\n]*\n.*?```", text, flags=re.S)


def tree_tags(block):
    """locale tags enumerated in a tree block — one-line (tag/strings.json) and
    split-glyph (tag/ + a child strings.json line) forms both carry 'tag/'"""
    return re.findall(r"\b([a-z]{2}_[A-Z]{2})/", block)


i18n_text = read(I18N)
readme_text = read(README)
want = set(folders)

# ---- R1 the Overview headline counts in words and enumerates the set --------
if i18n_text is not None:
    head = [l for l in i18n_text.split("\n") if "locale famil" in l.lower() and "ship" in l.lower()]
    if not head:
        problems.append(
            f"  {I18N} - CHECK61 R1: no Overview line states the total number of locale "
            f"families — a bare sibling count reads as the family total (the review M37 "
            f"misread class: '{total_word.capitalize()} locale families ship' must be on the record)")
    else:
        line = head[0]
        collapsed = re.sub(r"\s+", " ", line)
        m = re.search(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+locale\s+famil",
                      collapsed, flags=re.I)
        if not m or m.group(1).lower() != total_word:
            problems.append(
                f"  {I18N} - CHECK61 R1: the Overview total does not read '{total_word} locale "
                f"families' against {len(folders)} directories on disk: {line!r}")
        m = re.search(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+shipped\s+sibling\s+catalog",
                      collapsed, flags=re.I)
        if not m or m.group(1).lower() != sib_word:
            problems.append(
                f"  {I18N} - CHECK61 R1: the Overview sibling count does not read "
                f"'{sib_word} shipped sibling catalogs' (base excluded) against {folders}: {line!r}")
        enumerated = set(re.findall(r"`([a-z]{2}_[A-Z]{2})`", line))
        if enumerated != want:
            missing, ghost = sorted(want - enumerated), sorted(enumerated - want)
            problems.append(
                f"  {I18N} - CHECK61 R1: the Overview enumeration drifts from locale/ — "
                f"missing {missing}, not-a-directory {ghost}")

    # ---- R2 the Directory-Structure tree enumerates the set -------------------
    tree_block = next((b for b in fenced_blocks(i18n_text) if "└── locale/" in b), None)
    if tree_block is None:
        problems.append(
            f"  {I18N} - CHECK61 R2: no fenced Directory-Structure tree naming 'locale/' — "
            "the enumeration this document ships with was deleted (CHECK56 survive-delete precedent)")
    else:
        tags = tree_tags(tree_block)
        for ghost in sorted(set(t for t in tags if t not in want)):
            problems.append(f"  {I18N} - CHECK61 R2: tree lists locale/{ghost}/strings.json — no such directory")
        for miss in sorted(want - set(tags)):
            problems.append(f"  {I18N} - CHECK61 R2: locale/{miss}/ ships but the Directory-Structure tree omits it")
        dupes = sorted(t for t in set(tags) if tags.count(t) > 1)
        if dupes:
            problems.append(f"  {I18N} - CHECK61 R2: tree enumerates {dupes} more than once")

# ---- R3 the README inventory enumerates the set ------------------------------
if readme_text is not None:
    tree_block = next((b for b in fenced_blocks(readme_text) if "├── locale/" in b), None)
    if tree_block is None:
        problems.append(
            f"  {README} - CHECK61 R3: no fenced Project-Structure tree naming 'locale/' — "
            "the shipped channel packages locale/, the inventory may not go silent about it")
    else:
        tags = tree_tags(tree_block)
        for ghost in sorted(set(t for t in tags if t not in want)):
            problems.append(f"  {README} - CHECK61 R3: tree lists locale/{ghost}/strings.json — no such directory")
        for miss in sorted(want - set(tags)):
            problems.append(
                f"  {README} - CHECK61 R3: locale/{miss}/ ships (packaged by the Makefile, "
                f"parity-guarded by Check 21) but the Project-Structure tree omits it — "
                f"the one-row locale/ block under-enumerated {len(folders)} families as one (M37 class)")
        dupes = sorted(t for t in set(tags) if tags.count(t) > 1)
        if dupes:
            problems.append(f"  {README} - CHECK61 R3: tree enumerates {dupes} more than once")

# ---- R4 folder identity: _metadata.locale names its own family ----------------
for folder in folders:
    path = os.path.join("locale", folder, "strings.json")
    try:
        meta = json.load(open(path, encoding="utf-8")).get("_metadata", {})
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK61 R4: unreadable: {err} — folder identity cannot be verified")
        continue
    claimed = meta.get("locale") if isinstance(meta, dict) else None
    if claimed != folder:
        problems.append(
            f"  {path} - CHECK61 R4: _metadata.locale is {claimed!r} but the directory is "
            f"{folder!r} — a docs inventory line pointing here mislabels the family")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK61: %d locale-family pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK61: the family set is the directory — %d locale families on disk," % len(folders))
print("           stated in words and enumerated by tag in the i18n.md Overview,")
print("           in the i18n.md Directory-Structure tree and in the README")
print("           Project-Structure tree (no ghosts, no omissions, no duplicates),")
print("           and every catalog's _metadata.locale names its own folder")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# CHECK 62 (M-ROKU-31, review roku__writer M7): the README's test inventories and its
# dependency truth mirror the SHIPPED tree, in both directions.
# NUMBERING (disclosed, CHECK54/55 rebasing precedent): this leg was composed as "59"
# against raw origin tip e1d04b8f (highest header Check 58); the collision probe then
# the sibling fixlanes then LANDED Checks 59 (M-ROKU-33), 60 (M-ROKU-32) and 61
# (M-ROKU-37) atop it, so the collision probe at f56793f8 (grep -n '=== Check',
# highest header 61) renumbers this leg to 62 — the header census stays globally
# unique however the lanes interleave.
# THE HOLE THE REVIEW NAMED: the README listed THREE unit files while tests/unit/
# held sixteen (twenty-two today); the make test-unit sample echo was hand-typed
# rather than the target's real output; §3 "Install Dependencies — No external
# dependencies required" was device-true but dev-false (make lint runs npx bsc,
# every CI workflow runs npm ci against package.json devDependencies); and
# "### BrightScript Configuration" promised "these configurable constants"
# followed by nothing — a heading born empty in 367c48a's restructure, with no
# named configurable constants anywhere in source/ (tunables are inline call-site
# literals), so the section was deleted per the review's own "(or delete the
# heading)" arm. Every inventory claim in the cured block is RE-DERIVED from the
# tree; this leg keeps the cure from decaying back into fiction — the exact drift
# class CHECK56 (docs-vs-instantiation) and CHECK57 (spelling census) pin, on the
# tests/ axis.
#   R1  every *.test.brs basename named in the "### Test Structure" fenced block
#       exists somewhere under tests/ (phantom-landmark catcher);
#   R2  every *.test.brs on disk under tests/ is named in that block (silent-
#       addition catcher) — the block and the tree are set-equal by basename;
#   R3  the Unit Tests section's "**N rooibos unit suites**" literal exists and
#       N equals the tests/unit/ census (the prose count cannot rot);
#   R4  the "### 3. Install Dependencies" section carries `npm ci` and names the
#       devDependencies truth, and the convicted phrase "No external dependencies
#       required" stays extinct (a lie returning is convicted, CHECK54 R2 idiom);
#   R5  the empty-section lead-in "configurable constants (in source files)" stays
#       extinct (survive-by-deletion arm, CHECK56 R2 precedent);
#   R0  unreadable inputs fail loud — the pin cannot run vacuously.
# No unit suite: pure docs-vs-tree presence legs (CHECK50/52/56/57/58 precedent).
echo "=== Check 62: README test inventories + dependency truth mirror the shipped tree (M-ROKU-31) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

README = "README.md"
problems = []

try:
    text = open(README, encoding="utf-8").read()
except OSError as err:
    print(f"  {README} - CHECK62 R0: unreadable: {err} — the pin cannot run vacuously")
    sys.exit(1)

# ---- disk truth --------------------------------------------------------------
unit_disk = sorted(os.path.basename(p) for p in glob.glob("tests/unit/*.test.brs"))
all_disk = sorted(os.path.basename(p) for p in glob.glob("tests/**/*.test.brs", recursive=True))
if not unit_disk or not all_disk:
    problems.append(f"  tests/ - CHECK62 R0: the suite census is empty (unit={len(unit_disk)} all={len(all_disk)}) — the pin cannot run vacuously")

# ---- the Test Structure fenced block ------------------------------------------
idx = text.find("### Test Structure")
if idx == -1:
    problems.append("  README.md - CHECK62 R1: the '### Test Structure' heading vanished — the pinned inventory has no home")
    block = ""
else:
    fence = re.search(r"```[^\n]*\n(.*?)```", text[idx:], re.S)
    if fence is None:
        problems.append("  README.md - CHECK62 R1: no fenced code block under '### Test Structure' — nothing to compare the tree against")
        block = ""
    else:
        block = fence.group(1)
listed = sorted(set(re.findall(r"([A-Za-z0-9_]+\.test\.brs)", block)))

phantoms = [n for n in listed if n not in all_disk]
if phantoms:
    problems.append(f"  README.md - CHECK62 R1: the Test Structure block names phantom suites {phantoms} — no such *.test.brs exists under tests/ (review M7: a map whose landmarks are gone makes readers distrust every list)")
missing = [n for n in all_disk if n not in listed]
if missing:
    problems.append(f"  README.md - CHECK62 R2: {len(missing)} shipped suite(s) are absent from the Test Structure block {missing} — the inventory decays silently again (review M7 listed 3 of 16; the drift class this pin owns)")

# ---- R3 the prose count ------------------------------------------------------
count = re.search(r"\*\*(\d+) rooibos unit suites\*\*", text)
if count is None:
    problems.append("  README.md - CHECK62 R3: the '**N rooibos unit suites**' census literal vanished from the Unit Tests section — the count the review re-derived is no longer stated")
elif len(unit_disk) and int(count.group(1)) != len(unit_disk):
    problems.append(f"  README.md - CHECK62 R3: the Unit Tests section claims {count.group(1)} rooibos unit suites but tests/unit/ holds {len(unit_disk)} — stale inventory re-grown")

# ---- R4 install-dependency truth ---------------------------------------------
dep = re.search(r"### 3\. Install Dependencies\s*\n(.*?)(?=\n#{2,3} )", text, re.S)
if dep is None:
    problems.append("  README.md - CHECK62 R4: the '### 3. Install Dependencies' section vanished — the dependency truth it carries has no home")
else:
    body = dep.group(1)
    if "No external dependencies required" in body:
        problems.append('  README.md - CHECK62 R4: "No external dependencies required" is back — dev-false: make lint runs npx bsc and lint.yml/test.yml/package.yml all run npm ci against package.json devDependencies (review M7)')
    for needle, why in (
        ("npm ci", "the section no longer tells fresh checkouts to run it"),
        ("devDependencies", "the section no longer names where the toolchain lives"),
        ("brighterscript", "the devDependency census (brighterscript) left the section"),
        ("rooibos-roku", "the devDependency census (rooibos-roku) left the section"),
    ):
        if needle not in body:
            problems.append(f"  README.md - CHECK62 R4: Install Dependencies lost {needle!r} — {why}")

# ---- R5 the born-empty section stays deleted -----------------------------------
if "configurable constants (in source files)" in text:
    problems.append('  README.md - CHECK62 R5: the "BrightScript Configuration" empty-section lead-in is re-grown — a promise with nothing behind it (born empty in 367c48a, deleted by M-ROKU-31; there are no configurable constants in source/)')

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK62: %d README-truth pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK62: the Test Structure block and tests/ are set-equal by basename")
print(f"           ({len(all_disk)} shipped suites, {len(unit_disk)} unit), the stated suite count")
print("           matches the census, Install Dependencies carries the npm ci +")
print("           devDependencies truth with the convicted phrase extinct, and the")
print("           born-empty constants lead-in stays deleted — the README test")
print("           inventories can no longer drift from the shipped tree silently")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# CHECK 63 (W-min89: M-ROKU-03, -29, -34, -57): one leg owns four prose/legibility
# convictions cured by this batch.
# NUMBERING (disclosed, CHECK54/55/62 rebase-precedent): composed against tip
# b30b7f2, whose highest header is Check 62 (collision probe: grep -n '=== Check'
# at own tip); this leg takes 63.
#   R1 (M-ROKU-03) GetErrorMessage's convicted raw-wire echo "if len(safeError) > 0
#       then return safeError" stays extinct (comment-masked view), and the
#       transport-translation arm (IsTransportReason -> TranslateTransportReason
#       on safeError) is PRESENT: internal reason codes land on catalog copy and
#       any other wire detail is printed for diagnostics, replaced in speech by
#       the generic caption.
#   R2 (M-ROKU-03) ServerPickerScene's convicted preference of the raw wire error
#       ("errorMsg = SafeErrorMessage(resp.error") stays extinct — the load
#       failure dialog shows the friendly caption; the detail rides the print
#       channel only.
#   R3 (M-ROKU-29) ToastManager splices no bracket severity tags into the spoken
#       toast text (convicted concatenations "[ERROR] " and "[WARNING] ",
#       comment-masked view) and showInfo's dwell sits at the 4000ms legibility
#       floor (the parsed literal must be >= 4000).
#   R4 (M-ROKU-34) the word-bearing PlayerScene labels never regress to
#       SmallSystemFont on a 10-foot TV: sleepTimerLabel, syncStatusLabel,
#       qualityStatusLabel, settingsStatusLabel, trackListStatusLabel,
#       sleepTimerStatusLabel and upNextCardCountdown are enumerated (a vanished
#       label is itself a red — the law loses its subjects); MJ-2's syncCodeLabel
#       and syncCodePasswordLabel joined the enumeration in their minting commit;
#       timeLabel keeps the Small face by the review's own digits-only carve-out
#       and is deliberately NOT pinned either way.
#   R5 (M-ROKU-57) the README internal-alias extinction holds: server-A7, F12a,
#       F7a, F13, F9, F10, S280, "server SP5", "mobile E5 slice" and the
#       "unscouted" typo stay gone, the demoted top-level "## SyncPlay (Watch
#       Together)" home exists, and the fake Installation "### 6." step shape
#       stays extinct (a section heading masquerading as a numbered step).
#   R0  unreadable inputs fail loud — the pin cannot run vacuously.
# No unit suite: pure presence legs over shipped files (CHECK50/52/56/57/62 precedent).
echo "=== Check 63: spoken-error floor, tag-free toasts, legible player labels, alias-free README (W-min89) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

UTILITIES = "source/lib/Utilities.brs"
PICKER = "components/ServerPickerScene.brs"
TOASTS = "source/lib/ToastManager.brs"
PLAYER_XML = "components/PlayerScene.xml"
README = "README.md"
problems = []


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as err:
        problems.append(f"  {path} - CHECK63 R0: unreadable: {err} - the pin cannot run vacuously")
        return None


def mask_brs_comments(text):
    # Same contract as Check 20's masker: a single quote outside a double-quoted
    # string opens a comment that runs to end of line; comment runs become spaces
    # of identical length. Prose that QUOTES a convicted shape can never convict.
    out = []
    for line in text.splitlines(keepends=True):
        in_str = False
        chars = list(line)
        i = 0
        while i < len(chars):
            c = chars[i]
            if c == '"':
                in_str = not in_str
            elif c == "'" and not in_str:
                for j in range(i, len(chars)):
                    if chars[j] not in ("\n", "\r"):
                        chars[j] = " "
                break
            i += 1
        out.append("".join(chars))
    return "".join(out)


util = read(UTILITIES)
if util is not None:
    masked = mask_brs_comments(util)
    if re.search(r"len\(safeError\)\s*>\s*0\s+then\s+return\s+safeError", masked):
        problems.append('  source/lib/Utilities.brs - CHECK63 R1: the raw-wire echo arm "if len(safeError) > 0 then return safeError" is re-grown in GetErrorMessage - server prose is not user copy (review roku__webux M-ROKU-03)')
    if "IsTransportReason(safeError)" not in masked or "TranslateTransportReason(safeError)" not in masked:
        problems.append("  source/lib/Utilities.brs - CHECK63 R1: the transport-translation arm vanished from GetErrorMessage - reason codes must land on the TranslateTransportReason ladder, not on printed wire prose")

picker = read(PICKER)
if picker is not None:
    pmask = mask_brs_comments(picker)
    if re.search(r"errorMsg\s*=\s*SafeErrorMessage\(\s*resp\.error", pmask):
        problems.append('  components/ServerPickerScene.brs - CHECK63 R2: the load-failure dialog is fed SafeErrorMessage(resp.error, ...) again - the raw wire value regains the spoken seat (review roku__webux M-ROKU-03)')

toast = read(TOASTS)
if toast is not None:
    tmask = mask_brs_comments(toast)
    for tag in ('"[ERROR] " +', '"[WARNING] " +'):
        if tag in tmask:
            problems.append(f'  source/lib/ToastManager.brs - CHECK63 R3: the bracket severity concatenation {tag[:-2]} + "..." is re-grown - severity belongs to the channel (color/duration), not to the SPOKEN text (review roku__writer M-ROKU-29)')
    dwell = re.search(r"showInfo:\s*function.*?m\.show\(\s*message\s*,\s*(\d+)\s*\)", tmask, re.S)
    if dwell is None:
        problems.append("  source/lib/ToastManager.brs - CHECK63 R3: the showInfo dwell literal is unparseable - the 4000ms legibility floor lost its subject")
    elif int(dwell.group(1)) < 4000:
        problems.append(f"  source/lib/ToastManager.brs - CHECK63 R3: showInfo dwell regressed to {dwell.group(1)}ms - below the 4000ms floor this batch set (info notices must be readable, review roku__writer M-ROKU-29)")

xmltext = read(PLAYER_XML)
if xmltext is not None:
    xclean = re.sub(r"<!--.*?-->", " ", xmltext, flags=re.S)
    labels = {}
    for tag_m in re.finditer(r"<Label\b[^>]*>", xclean, re.S):
        tag = tag_m.group(0)
        id_m = re.search(r'id="([^"]+)"', tag)
        if id_m is None:
            continue
        labels.setdefault(id_m.group(1), []).append(tag)
    WORD_BEARING = (
        "sleepTimerLabel", "syncStatusLabel", "qualityStatusLabel",
        "settingsStatusLabel", "trackListStatusLabel", "sleepTimerStatusLabel",
        "upNextCardCountdown",
        # MJ-2 (join-by-code panel): the two new word-bearing labels join the
        # enumerated set in their minting commit - the CHECK63 R4 docblock and
        # the static-checks row moved with them, disclosed.
        "syncCodeLabel", "syncCodePasswordLabel",
    )
    for label_id in WORD_BEARING:
        hits = labels.get(label_id)
        if not hits:
            problems.append(f"  components/PlayerScene.xml - CHECK63 R4: word-bearing label id={label_id} vanished - the legibility law lost its subject (M-ROKU-34)")
            continue
        for tag in hits:
            font_m = re.search(r'font="font:([A-Za-z]+)"', tag)
            if font_m is not None and font_m.group(1) == "SmallSystemFont":
                problems.append(f"  components/PlayerScene.xml - CHECK63 R4: id={label_id} carries SmallSystemFont again - word-bearing TV labels ride Medium-or-larger (review roku__crossfe M-ROKU-34)")

readme = read(README)
if readme is not None:
    for pat, why in (
        (r"server-A7", "internal work-item alias"),
        (r"\bF12a\b", "internal epic alias"),
        (r"\bF7a\b", "internal epic alias"),
        (r"\bF13\b", "internal epic alias"),
        (r"\bF9\b", "internal epic alias"),
        (r"\bF10\b", "internal epic alias"),
        (r"\bS280\b", "internal ticket alias"),
        (r"server SP5", "internal ticket alias"),
        (r"mobile E5 slice", "internal epic alias"),
        (r"unscouted", "typo the review named"),
    ):
        if re.search(pat, readme):
            problems.append(f"  README.md - CHECK63 R5: {pat!r} ({why}) is re-grown in the README - users met these codes nowhere (review roku__writer M-ROKU-57)")
    if not re.search(r"^## SyncPlay \(Watch Together\)$", readme, re.M):
        problems.append('  README.md - CHECK63 R5: the top-level "## SyncPlay (Watch Together)" heading is not the section\'s home anymore')
    if re.search(r"^### 6\. SyncPlay", readme, re.M):
        problems.append('  README.md - CHECK63 R5: the fake Installation "### 6." step heading is back - a feature section does not continue the numbered install list (M-ROKU-57)')

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK63: %d W-min89 conviction(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK63: GetErrorMessage echoes no wire prose (transport codes translated,")
print("           picker detail print-only), toasts carry no spoken severity tags with")
print("           info at the 4000ms floor, every word-bearing PlayerScene label rides")
print("           Medium-or-larger, and the README alias census is clean with the")
print("           SyncPlay section on its top-level home")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# CHECK 64 (W-min90: M-ROKU-01/02/04/11/30/42/47/50 batch): catalog discipline,
# spoken-copy extinction, header containment and the account-label mechanism.
# NUMBERING (disclosed, CHECK54/55/62 rebase-precedent): composed against tip
# e7d6b97, whose highest header is Check 63 (this campaign's own W-min89 leg);
# collision probe re-run at write time, this leg takes 64.
#   R1 (M-ROKU-04/-02) the swept hardcoded dialog/status sentences stay extinct as
#       RAW STRING LITERALS in every components/ + source/ .brs (comment-masked
#       view, CHECK51/52 idiom): "No servers", "No collections", "No collections
#       available.", "Collection has no ID", "No stream URL available", "Playback
#       failed", "Content Not Available", "Unable to load servers" and the
#       subscription-fiction message the ask convicted. They now ride catalog
#       keys, so seven shipped locales finally speak these states.
#   R2 (M-ROKU-02/-04/-11) SPEAKABLE roster: the eight keys this batch introduced
#       or adopted exist non-empty string-typed in ALL SEVEN catalogs (CHECK21
#       owns set-parity; this arm owns the named roster - a deleted member reddens
#       here by name).
#   R3 (M-ROKU-02) errors.unknown_message carries its next step: the old bare
#       one-sentence copy "The server rejected an unrecognized request." is
#       convicted (the review's dead-end prose), and every locale's value stays
#       non-empty.
#   R4 (M-ROKU-30) header containment: every HomeScene.xml y=36 header Button
#       (row rode y=20 until the MN-9 safe-area cure; rotation disclosed in Check 85 era)
#       (CHECK29's own parse shape) satisfies x + width <= 1280 - the admin step
#       ran off the 1280 canvas before this batch; a row that re-grows past the
#       edge reddens. Fail-loud: fewer than six parsed header buttons is itself
#       red (the law may not run vacuously).
#   R5 (M-ROKU-11) the account label never returns to the bare-client read: the
#       convicted expression "GetApiClient().user.email" is extinct in every
#       .brs (comment-masked), and SettingsScene carries the getMe dispatch
#       that replaced it (anti-vacuity pair).
#   R6 (M-ROKU-47) no value in any of the seven catalogs contains a three-dot
#       "..." ellipsis - the house glyph is U+2026 (common.loading already
#       shipped it); keys are exempt, string VALUES are not.
#   R7 (M-ROKU-42/-50) README extinct phrases: the misattributed editor credit
#       "by彩虹", the stale quote "Couldn't reach that server", and any lingering
#       "check your subscription" fiction.
#   R0  unreadable inputs and empty rosters fail loud - the pin cannot run
#       vacuously.
# No unit suite: pure presence legs over shipped statics (CHECK50/52/62/63 precedent).
echo "=== Check 64: catalog discipline, spoken-copy extinction, header containment, account label (W-min90) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob
import json
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

FAMILIES = ("en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR")
README = "README.md"
problems = []


def mask_brs_comments(text):
    # Same contract as Check 20's masker: a single quote outside a double-quoted
    # string opens a comment that runs to end of line; comment runs become spaces.
    out = []
    for line in text.splitlines(keepends=True):
        in_str = False
        chars = list(line)
        i = 0
        while i < len(chars):
            c = chars[i]
            if c == '"':
                in_str = not in_str
            elif c == "'" and not in_str:
                for j in range(i, len(chars)):
                    if chars[j] not in ("\n", "\r"):
                        chars[j] = " "
                break
            i += 1
        out.append("".join(chars))
    return "".join(out)


def load_catalog(fam):
    path = f"locale/{fam}/strings.json"
    try:
        with io_open(path) as f:
            return json.load(f)
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK64 R0: unreadable: {err} - the pin cannot run vacuously")
        return None


def io_open(path):
    return open(path, encoding="utf-8")


# ---- R1 raw spoken-copy extinction across the client .brs graph --------------
CONVICTED = (
    '"No servers"',
    '"No collections"',
    '"No collections available."',
    '"Collection has no ID"',
    '"No stream URL available"',
    '"Playback failed"',
    '"Content Not Available"',
    '"Unable to load servers"',
    '"This content is not available in your library. Please check your subscription or try again later."',
)
brs_files = sorted(glob.glob("components/*.brs") + glob.glob("source/**/*.brs", recursive=True))
if not brs_files:
    problems.append("  components/ + source/ - CHECK64 R0: no .brs files discovered - the extinction scan cannot run vacuously")
for path in brs_files:
    try:
        masked = mask_brs_comments(io_open(path).read())
    except OSError as err:
        problems.append(f"  {path} - CHECK64 R0: unreadable: {err}")
        continue
    for lit in CONVICTED:
        if lit in masked:
            problems.append(f"  {path} - CHECK64 R1: raw dialog copy {lit} is back outside the catalog - these states are SPEAKABLE in seven locales (review roku__casualgamer m4/M-ROKU-04, m2/M-ROKU-02)")

# ---- R2 the SPEAKABLE roster x7 -----------------------------------------------
ROSTER = (
    ("serverpicker", "load_failed"),
    ("serverpicker", "no_servers"),
    ("collections", "empty"),
    ("detail", "no_collections_available"),
    ("detail", "collection_no_id"),
    ("player", "err_no_stream"),
    ("app", "content_unavailable_title"),
    ("app", "content_unavailable_message"),
)
cats = {}
for fam in FAMILIES:
    cat = load_catalog(fam)
    if cat is not None:
        cats[fam] = cat
    for section, key in ROSTER:
        val = (cat or {}).get(section, {}).get(key) if cat else None
        if not isinstance(val, str) or val.strip() == "":
            where = f"locale/{fam}/strings.json"
            problems.append(f"  {where} - CHECK64 R2: {section}.{key} is missing or empty - the W-min90 roster must be speakable in all seven shipped locales")

# ---- R3 unknown_message carries its next step ----------------------------------
OLD_UNKNOWN = "The server rejected an unrecognized request."
for fam, cat in cats.items():
    val = cat.get("errors", {}).get("unknown_message")
    where = f"locale/{fam}/strings.json"
    if not isinstance(val, str) or val.strip() == "":
        problems.append(f"  {where} - CHECK64 R3: errors.unknown_message vanished or is empty")
    elif val == OLD_UNKNOWN:
        problems.append(f"  {where} - CHECK64 R3: errors.unknown_message is back to the dead-end one-sentence copy - the review convicted telling the user what failed without ever saying what to do (M-ROKU-02)")

# ---- R4 header containment -----------------------------------------------------
try:
    xml = io_open("components/HomeScene.xml").read()
except OSError as err:
    xml = None
    problems.append(f"  components/HomeScene.xml - CHECK64 R0: unreadable: {err}")
if xml is not None:
    xclean = re.sub(r"<!--.*?-->", " ", xml, flags=re.S)
    row = []
    for m in re.finditer(r'<Button[^>]*?translation="\[(\d+),36\]"[^>]*?id="(\w+)"', xclean):
        tag_full = re.search(r'<Button[^>]*?id="' + m.group(2) + r'"[^>]*/?>', xclean, re.S)
        w = re.search(r'width="(\d+)"', tag_full.group(0)) if tag_full else None
        if w is None:
            problems.append(f"  components/HomeScene.xml - CHECK64 R4: header Button id={m.group(2)} has no parsable width - containment cannot be proven")
            continue
        row.append((int(m.group(1)), int(w.group(1)), m.group(2)))
    if len(row) < 6:
        problems.append(f"  components/HomeScene.xml - CHECK64 R4: only {len(row)} header-row (y=36) Buttons parsed - the containment law lost its subjects (six ship)")
    for x, w, nid in row:
        if x + w > 1280:
            problems.append(f"  components/HomeScene.xml - CHECK64 R4: {nid} spans x={x}..{x + w} - past the 1280 design plane (M-ROKU-30: the admin step ran off-canvas; the plane is fixed, the OS upscales)")

# ---- R5 the account-label mechanism ---------------------------------------------
for path in brs_files:
    try:
        masked = mask_brs_comments(io_open(path).read())
    except OSError:
        continue
    if "GetApiClient().user.email" in masked:
        problems.append(f"  {path} - CHECK64 R5: the bare-client email read is back - GetApiClient is rebuilt without a user object on every boot, so the account line would strand blank again (M-ROKU-11: the answer comes from the getMe op)")
try:
    settings = io_open("components/SettingsScene.brs").read()
except OSError as err:
    settings = None
    problems.append(f"  components/SettingsScene.brs - CHECK64 R0: unreadable: {err}")
if settings is not None and 'op: "getMe"' not in settings:
    problems.append('  components/SettingsScene.brs - CHECK64 R5: the getMe dispatch vanished - SettingsScene no longer fetches the account label it renders (anti-vacuity pair of the extinction arm)')

# ---- R6 no three-dot ellipsis in catalog values -----------------------------------
def walk_values(obj, path):
    for k, v in obj.items():
        if isinstance(v, dict):
            walk_values(v, f"{path}.{k}")
        elif isinstance(v, str) and "..." in v:
            problems.append(f"  {path}.{k} - CHECK64 R6: value carries a three-dot ellipsis - the shipped house glyph is U+2026 (review roku__writer M-ROKU-47)")
for fam, cat in cats.items():
    walk_values({k: v for k, v in cat.items() if isinstance(v, dict) and k != "_metadata"}, f"locale/{fam}/strings.json")

# ---- R7 README extinct phrases ----------------------------------------------------
try:
    readme = io_open(README).read()
except OSError as err:
    readme = None
    problems.append(f"  {README} - CHECK64 R0: unreadable: {err}")
if readme is not None:
    for phrase, why in (
        ("by\u5f69\u8679", "the editor credit named a look-alike marketplace entry; the canonical Roku extension is *BrightScript Language* by RokuDeveloper (M-ROKU-42)"),
        ("Couldn't reach that server", "the README quoted copy the client stopped shipping at d252b17; the /health probe now surfaces the cataloged connect.err_unreachable sentence (M-ROKU-50)"),
        ("check your subscription", "Phlix has no subscription concept a TV dialog should blame - the content-unavailable copy now says server (M-ROKU-02)"),
    ):
        if phrase in readme:
            problems.append(f"  README.md - CHECK64 R7: {phrase!r} is re-grown - {why}")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK64: %d W-min90 conviction(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK64: the swept dialog sentences live only in the catalogs (all eight")
print("           roster keys speakable x7, unknown_message says what to do next),")
print("           the header row stands inside the 1280 plane, the account label")
print("           rides getMe with the bare-client read extinct, no value in any")
print("           catalog types '...', and the README prose convictions hold")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 65: forbidden string-member family extinct; headless unit gate wired (M-ROKU-15/17) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def mask_brs_comments(text):
    # Same contract as Check 20/64's masker: a single quote outside a
    # double-quoted string opens a comment running to end of line.
    out = []
    for line in text.splitlines(keepends=True):
        in_str = False
        chars = list(line)
        i = 0
        while i < len(chars):
            c = chars[i]
            if c == '"':
                in_str = not in_str
            elif c == "'" and not in_str:
                for j in range(i, len(chars)):
                    if chars[j] not in ("\n", "\r"):
                        chars[j] = " "
                break
            i += 1
        out.append("".join(chars))
    return "".join(out)


# The W-min91 harness campaign proved these string MEMBERS are fatal on the
# device (.Lower/.UCase do not exist at all; .Left/.Mid/.Right phantom-serve
# in some runtimes with 0-BASED indices while the device exposes them only as
# globals; .Repl/.padz misuse were found in-tree). The globals LCase/UCase/
# Left/Mid/Right/Repl are the legal shapes. Pin: no receiver-dot member of the
# family survives anywhere the client executes.
MEMBER = re.compile(r"(?:[A-Za-z0-9_\]\)\"])\.(Lower|Upper|UCase|Left|Mid|Right|padz|Repl)\s*\(")
SORTBY3 = re.compile(r"\.SortBy\s*\([^()]*,[^()]*,[^()]*\)")

scan_exts = (".brs", ".xml", ".bs")
files = []
# tests/ is included on purpose: the suites execute on the DEVICE (rooibos)
# too, and the harness does NOT catch member forms — brs phantom-serves
# .Left/.Mid (0-based) where the device has no member at all. A forbidden
# member in a test file is a device-side crash that hides green here.
for base in ("source", "components", "tests"):
    for root, _dirs, names in os.walk(base):
        for n in sorted(names):
            if n.endswith(scan_exts):
                files.append(os.path.join(root, n))

lcase_uses = 0
for path in sorted(files):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    code = mask_brs_comments(raw)
    for m in MEMBER.finditer(code):
        line = code[: m.start()].count("\n") + 1
        problems.append(
            f"  {path}:{line} - CHECK65 R1: forbidden string member '.{m.group(1)}(' — "
            "device law: use the global {Lower/Upper->LCase/UCase, Left/Mid/Right, Repl}"
        )
    if SORTBY3.search(code):
        for m in SORTBY3.finditer(code):
            line = code[: m.start()].count("\n") + 1
            problems.append(
                f"  {path}:{line} - CHECK65 R2: 3-argument .SortBy( — the device (and brs) "
                "accept at most (fieldName, sortFlag)"
            )
    lcase_uses += len(re.findall(r"\bLCase\s*\(", code))

# R3 positive control: the sweep must not be vacuous — LCase (the family's
# canonical cure) actually appears in shipped code.
if lcase_uses < 10:
    problems.append(
        f"  CHECK65 R3: only {lcase_uses} LCase( call sites across source/+components/ — "
        "the pin is going vacuous (expect dozens; a rename storm or scanner break happened)"
    )

# R4 detector self-probe: the regex must convict planted shapes (red-leg proof
# inside the leg, estate style) AND the comment masker must keep a member call
# that lives INSIDE a comment out of the conviction set (negative control).
probe = mask_brs_comments('x = "a".Mid(1)\n\' foo.Left(2) planted\n')
if len(MEMBER.findall(probe)) != 1:  # the in-comment arm must NOT count
    problems.append("  CHECK65 R4: detector self-probe failed — planted member calls not convicted")
probe2 = 'z = q.Repl(" ", 2)\nw = LCase(m.Upper())'
if len(MEMBER.findall(probe2)) != 2:
    problems.append("  CHECK65 R4: detector self-probe failed — Repl/.Upper members not convicted")
if not SORTBY3.search('arr.SortBy("k", "desc", false)'):
    problems.append("  CHECK65 R4: detector self-probe failed — 3-arg SortBy not convicted")

# R5 wiring law (M-ROKU-17): the headless gate must stay executed by a real,
# unconditional CI step AND by the Makefile test-unit device-free arm. A future
# edit re-deadening either is exactly the defect class this item was filed for.
with open(".github/workflows/test.yml", encoding="utf-8") as f:
    tify = f.read()
if "run-headless-unit.mjs" not in tify:
    problems.append("  CHECK65 R5: test.yml no longer executes tests/scripts/run-headless-unit.mjs")
if re.search(r"if:\s*env\.ROKU_HOST\s*!=\s*''", tify):
    problems.append(
        "  CHECK65 R5: test.yml re-grows an 'if: env.ROKU_HOST != \"\"' step — job env never "
        "defines ROKU_HOST, so such a step is permanently dead (the M-ROKU-17 defect)"
    )
with open("Makefile", encoding="utf-8") as f:
    mk = f.read()
if "run-headless-unit.mjs" not in mk:
    problems.append("  CHECK65 R5: Makefile no longer references the headless unit gate")
with open("package.json", encoding="utf-8") as f:
    pkg = f.read()
if '"brs"' not in pkg:
    problems.append("  CHECK65 R5: package.json lost the brs devDependency the headless gate runs on")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK65: %d conviction(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK65: no forbidden string member (.Lower/.Upper/.UCase/.Left/.Mid/.Right/")
print("           .padz/.Repl) survives in source/, components/ or tests/, no 3-arg")
print("           SortBy, the detector self-probes convict, LCase presence keeps the")
print("           sweep honest, and the headless brs gate is wired into CI + Makefile")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 66: WS accumulator caps, destructive-op consent, en_US copy pair (minors W-min95) ==="
# NUMBERING (disclosed, CHECK62 renumbering-precedent style): collision probe at
# composition time — grep -c '^=== Check' over this script listed 65 legs, highest
# header Check 65; the one-fixer law leaves no sibling rok FIXER mid-flight, so 66
# is claimed clean.
# WHAT THIS LEG PINS (three shapes the W-min95 minors review named, none of which
# any earlier leg could see):
#   R1  both WS handshakes cap the pre-\r\n\r\n accumulator at the canonical
#       MaxHandshakeHeaderBytes and refuse the dial beyond it (M-ROKU-24, review
#       roku__exploiter m3 — the tries loop alone bounded it at ~400KB of junk).
#   R2  both frame paths cap the POST-consumption buffer residual at frame-max +
#       one chunk + headroom (M-ROKU-39, review roku__secnet m3 — ParseFrames
#       bounds declared lengths, not arrival volume; a never-completing extended
#       header used to grow m.buffer forever).
#   R3  the hub-command socket HONOURS ParseFrames' rejectedOversize flag —
#       W-min93 shipped the flag + SyncPlayTask consumption, and this file's
#       silence was the surviving half of the same hostile-desync class.
#   R4  the protocol owns both ceilings as named constants and ParseFrames
#       compares through them (no re-inlined magic bytes; two bound sites).
#   R5  setUserAdmin and clearProfilePin each ride the ConnectScene consent
#       idiom: stash-re-armed-at-press, default-deny callback (index 0 first),
#       and the OLD ungated send shapes are convicted ABSENT (negative guards).
#   R6  the en_US copy pair is sentence-case (M-ROKU-48/49): caption label
#       matches its own wire casing, login button reads "Log In" in catalog and
#       XML together (the CHECK25 pairing survives only because both moved).
#   R7  the consent key family is speakable in all seven locales and each
#       named message carries exactly one {name} token.
#   R8  the W-min94 batch shapes, completing that lane's rider (a) ("CHECK66
#       pin-leg covers BOTH batches"): auth-check ATTACH+DETACH (both Start*
#       sites RemoveChild the replaced task AND timer, and re-attach the boot
#       Timer — the attach half of the W-min94 cure was the unpinned seam,
#       forward-fixed here per the W-min94-roku__r1:31 same-lane candidate),
#       the screenStack depth cap +
#       named-reference bootstrap removals (the "whatever is last child"
#       positional invariant stays extinct), and SearchScene's keyboard-to-
#       results down-binding.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK66: unreadable: {err}")
        return None


SYNC = read("components/SyncPlayTask.brs")
HUB = read("components/HubCommandTask.brs")
PROTO = read("source/lib/SyncPlayProtocol.brs")
UAA = read("components/UserAdminActionsScene.brs")
PAS = read("components/ProfileActionsScene.brs")
LXML = read("components/LoginScene.xml")

HEADER_CAP = re.compile(r"headerBytes\.Count\(\) > m\.proto\.MaxHandshakeHeaderBytes then return false")
RESIDUAL_CAP = re.compile(r"m\.buffer\.Count\(\) > m\.proto\.MaxFrameBytes \+ 4096 \+ 64")

# ---- R1 handshake header cap, both dialers ---------------------------------
for name, src in (("components/SyncPlayTask.brs", SYNC), ("components/HubCommandTask.brs", HUB)):
    if src is None:
        continue
    if not HEADER_CAP.search(src):
        problems.append(f"  {name} - CHECK66 R1: handshake loop no longer caps headerBytes at m.proto.MaxHandshakeHeaderBytes (M-ROKU-24)")

# ---- R2 post-consumption residual cap, both frame paths -------------------
for name, src in (("components/SyncPlayTask.brs", SYNC), ("components/HubCommandTask.brs", HUB)):
    if src is None:
        continue
    m = RESIDUAL_CAP.search(src)
    if not m:
        problems.append(f"  {name} - CHECK66 R2: frame path no longer caps the post-consumption m.buffer residual (M-ROKU-39)")
    elif name == "components/SyncPlayTask.brs" and "rejectedOversize" not in src[max(0, m.start() - 2500):m.start()]:
        # honesty: the syncplay residual cap must live in HandleSocketEvent,
        # i.e. in the same body that consumes rejectedOversize.
        problems.append("  components/SyncPlayTask.brs - CHECK66 R2: residual cap drifted out of HandleSocketEvent")

# ---- R3 hub honours the parse rejection flag ------------------------------
if HUB is not None and "rejectedOversize" not in HUB:
    problems.append("  components/HubCommandTask.brs - CHECK66 R3: parsed.rejectedOversize is ignored again — a rejected head-of-line frame would wedge the buffer forever (M-ROKU-24/39 parity)")

# ---- R4 constants owned once, comparisons rewired -------------------------
if PROTO is not None:
    if not re.search(r"MaxHandshakeHeaderBytes: 65536", PROTO):
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK66 R4: MaxHandshakeHeaderBytes constant vanished")
    if not re.search(r"MaxFrameBytes: 1048576", PROTO):
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK66 R4: MaxFrameBytes constant vanished")
    if len(re.findall(r"payLen > m\.MaxFrameBytes", PROTO)) != 2:
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK66 R4: ParseFrames must compare BOTH extended-length arms against m.MaxFrameBytes (a re-inlined magic byte splits the source of truth)")
    if re.search(r"payLen > 1048576", PROTO):
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK66 R4: raw 1048576 literal re-appeared beside the constant")

# ---- R5 consent gates ------------------------------------------------------
if UAA is not None:
    if "OnToggleAdmin" not in UAA or "OnSetAdminChoice" not in UAA:
        problems.append("  components/UserAdminActionsScene.brs - CHECK66 R5: the admin-toggle consent callback vanished (M-ROKU-27)")
    else:
        if not re.search(r'ShowErrorDialog\(m\.top, Translate\("useradminactions_confirm_title"\)', UAA):
            problems.append("  components/UserAdminActionsScene.brs - CHECK66 R5: OnToggleAdmin no longer renders the named confirm dialog")
        if not re.search(r"sub OnSetAdminChoice\(index as Integer\)\s*\n\s*if index <> 0 then return", UAA):
            problems.append("  components/UserAdminActionsScene.brs - CHECK66 R5: OnSetAdminChoice lost its default-deny first arm (M-ROKU-27)")
        cbbody = UAA[UAA.find("sub OnSetAdminChoice"):UAA.find("end sub", UAA.find("sub OnSetAdminChoice"))] if "sub OnSetAdminChoice" in UAA else ""
        if "isAdmin: granting" not in cbbody:
            problems.append("  components/UserAdminActionsScene.brs - CHECK66 R5: the confirmed send must use the STASHED intent (isAdmin: granting), not a recompute (the review's stale-local-state half)")
    if re.search(r"isAdmin: \(not m\.currentIsAdmin\)", UAA):
        problems.append("  components/UserAdminActionsScene.brs - CHECK66 R5: ungated one-press admin toggle reappeared (M-ROKU-27)")
if PAS is not None:
    if not re.search(r"sub OnClearPinChoice\(index as Integer\)\s*\n\s*if index <> 0 then return", PAS):
        problems.append("  components/ProfileActionsScene.brs - CHECK66 R5: OnClearPinChoice lost its default-deny consent arm (M-ROKU-27)")
    # The pre-fix defect: OnClearPin itself fired the DELETE. Body-window
    # conviction — a loose send-shape regex would re-match the identical,
    # now-consent-gated send inside OnClearPinChoice and false-convict.
    pin_body = re.search(r"sub OnClearPin\(event as Object\)(.*?)end sub", PAS, re.DOTALL)
    if pin_body is None:
        problems.append("  components/ProfileActionsScene.brs - CHECK66 R5: OnClearPin vanished")
    elif 'control = "run"' in pin_body.group(1):
        problems.append("  components/ProfileActionsScene.brs - CHECK66 R5: Clear PIN is one-press-gated again — the DELETE must only fire from the consent callback (M-ROKU-27)")
    elif "ShowErrorDialog" not in pin_body.group(1):
        problems.append("  components/ProfileActionsScene.brs - CHECK66 R5: OnClearPin no longer routes through the consent dialog (M-ROKU-27)")

# ---- R6 en_US copy pair ----------------------------------------------------
try:
    en = json.load(open("locale/en_US/strings.json", encoding="utf-8"))
except (OSError, ValueError) as err:
    problems.append(f"  locale/en_US/strings.json - CHECK66 R6: unreadable: {err}")
    en = None
if en is not None:
    if en.get("settings", {}).get("button_caption_instant_replay") != "Instant replay":
        problems.append("  locale/en_US/strings.json - CHECK66 R6: caption label drifted from sentence case again (M-ROKU-48 — the split with the OS wire value's own casing is the defect)")
    if en.get("login", {}).get("button") != "Log In":
        problems.append("  locale/en_US/strings.json - CHECK66 R6: login.button is not the verb pair 'Log In' (M-ROKU-49)")
    if LXML is not None and 'text="Log In"' not in LXML:
        problems.append("  components/LoginScene.xml - CHECK66 R6: XML fallback literal no longer byte-matches the catalog (CHECK25 pairing; both must move together)")
    if LXML is not None and re.search(r'text="Login"\s*\n\s*id="loginButton"', LXML):
        problems.append("  components/LoginScene.xml - CHECK66 R6: the noun-as-verb 'Login' literal was reintroduced")

# ---- R7 cross-locale presence of the consent key family -------------------
for loc in ("en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR"):
    path = f"locale/{loc}/strings.json"
    try:
        cat = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError) as err:
        problems.append(f"  {path} - CHECK66 R7: unreadable: {err}")
        continue
    for section, key in (("common", "confirm"),
                         ("useradminactions", "confirm_title"),
                         ("useradminactions", "confirm_make_message"),
                         ("useradminactions", "confirm_remove_message"),
                         ("profileactions", "confirm_title"),
                         ("profileactions", "confirm_message")):
        if cat.get(section, {}).get(key, "") == "":
            problems.append(f"  {path} - CHECK66 R7: {section}.{key} missing — the consent dialog must be SPEAKABLE in every shipped locale")
    for section, key in (("useradminactions", "confirm_make_message"),
                         ("useradminactions", "confirm_remove_message"),
                         ("profileactions", "confirm_message")):
        if cat.get(section, {}).get(key, "").count("{name}") != 1:
            problems.append(f"  {path} - CHECK66 R7: {section}.{key} must carry exactly one {{name}} token (the review's person-with-the-remote cure)")

# ---- R8 W-min94 batch shapes (rider (a) completion) ----------------------
APP = read("components/PhlixApp.brs")
Srch = read("components/SearchScene.brs")
if APP is not None:
    for fn in ("StartAuthCheck", "StartHubAuthCheck"):
        body = re.search(r"(?:function |sub )" + fn + r"\(.*?\)(.*?)end (?:function|sub)", APP, re.DOTALL)
        if body is None:
            problems.append(f"  components/PhlixApp.brs - CHECK66 R8: {fn} vanished (M-ROKU-25)")
            continue
        if "RemoveChild(m.authTask)" not in body.group(1) or "RemoveChild(m.authTimer)" not in body.group(1):
            problems.append(f"  components/PhlixApp.brs - CHECK66 R8: {fn} re-grows orphaned auth tasks — retry-mashing must DETACH the replaced task AND timer (M-ROKU-25)")
        if "AppendChild(m.authTimer)" not in body.group(1):
            problems.append(f"  components/PhlixApp.brs - CHECK66 R8: {fn} no longer attaches its boot Timer — a detached Timer never ticks, so the timeout chrome re-becomes fiction (W-min94-roku__r1:31 forward-fix, R-ROKU-06 lane: the detach half was pinned, the attach cure was not)")
    if "m.screenStack.Count() >= 12" not in APP:
        problems.append("  components/PhlixApp.brs - CHECK66 R8: the screenStack depth cap vanished — deep-link floods must stay bounded (M-ROKU-28)")
    named = len(re.findall(r"m\.top\.RemoveChild\(m\.(connectScene|loginScene|pickerScene)\)", APP))
    if named < 4:
        problems.append(f"  components/PhlixApp.brs - CHECK66 R8: only {named}/4 named-reference bootstrap removals survive — the last-child positional invariant must not return (M-ROKU-28)")
    if re.search(r"RemoveChild\(m\.top\.GetChild\(m\.screenStack\.Count\(\)\s*-\s*1", APP):
        problems.append("  components/PhlixApp.brs - CHECK66 R8: positional last-child removal reappeared in a bootstrap transition (M-ROKU-28)")
if Srch is not None:
    if 'key = "down" and m.zone = "keyboard" and m.results.Count() > 0' not in Srch:
        problems.append("  components/SearchScene.brs - CHECK66 R8: the keyboard-to-results down binding vanished — the results rail must be reachable from the keyboard (M-ROKU-32)")

# ---- self-probe: the regexes must convict the OLD shapes ------------------
if not HEADER_CAP.search("if headerBytes.Count() > m.proto.MaxHandshakeHeaderBytes then return false"):
    problems.append("  CHECK66 self-probe: R1 regex failed to convict its planted positive")
if RESIDUAL_CAP.search("n = m.sock.Receive(chunk, 0, 4096)"):
    problems.append("  CHECK66 self-probe: R2 regex matches non-cap text (vacuous detector)")
if re.search(r"isAdmin: \(not m\.currentIsAdmin\)", 'm.apiTask.request = { op: "setUserAdmin", userId: m.userId, isAdmin: (not m.currentIsAdmin) }') is None:
    problems.append("  CHECK66 self-probe: R5 negative guard cannot convict the planted ungated send")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK66: %d conviction(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK66: both WS handshakes cap their header accumulator, both frame paths")
print("           cap the post-consumption residual, the hub socket honours the parse")
print("           rejection, the protocol owns both ceilings once, admin+PIN changes")
print("           require a default-deny named consent, the en_US copy pair sits")
print("           in sentence case in catalog AND markup together, the consent family")
print("           is speakable x7 with its {name} tokens, and the W-min94 batch")
print("           shapes (auth detach, screenStack cap, named removals, search")
print("           down-binding) hold the rider (a) cross-batch duty")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 67: locale VALUES keep one canonical family form (R-ROKU-11) ==="
# NUMBERING (disclosed, CHECK62/CHECK66 collision-probe precedent): at composition
# time the highest header in this script is Check 66, and neither 'Check 67' nor
# 'CHECK67' appears anywhere in scripts/, tests/, docs/ or README.md — 67 is clean.
#
# WHY THE LEG EXISTS (R-ROKU-11, filed from fixlog/M-ROKU-20__r4.md observation N2).
# The r4 reviewer re-planted the stripped copula into it_IT at the CURED anchor and
# ran the whole battery: "no CI leg guards locale VALUES — my re-strip plant sailed
# through 54 checks green". That was true, and it is the reason M-ROKU-20 needed
# four review rounds to get five sentences right: Check 21 pins the key SET and
# ORDER, Check 48 R3 pins _metadata.version, Check 51 R3 pins player-family
# speakability, Checks 23/24/57 ask structural questions. Not one leg asks HOW a
# value is spelled, so all three defect classes the ticket had to be reviewed into
# existence (r3/r4 ask D1 the stripped copula, D2 the misplaced acute, D3 the
# pre-reform glyphs) were invisible at authoring. The leg is the review's own
# remedy, quoted: "a future value-family consistency leg (e.g. accent-strip/
# misplaced-accent/pre-reform-glyph scan of it/es/ja against each file's own
# canonical family forms)".
#
# WHAT IT PINS — locale VALUES only. It reads no keys, no version field, no code
# surface, so it is gate-independent of Checks 21/22/23/48/51 and this commit
# rotates none of them.
#   R0  ANTI-VACUITY. Exactly the seven shipped catalogs (the family law Check 61
#       enumerates), each parsable, each carrying MIN_VALUES string values. A value
#       gate scanning a stub catalog proves nothing, so a thin catalog reddens here
#       instead of passing quietly.
#   R1  ACCENT-STRIP — the automated, general arm. Inside ONE catalog, a phrase the
#       catalog repeats keeps ONE diacritic family. Key = three token skeletons with
#       combining marks dropped after NFD; two distinct surfaces on one key therefore
#       differ only in their marks. The 3-token window is MEASURED, not taste: at
#       n=2 the rule convicts pt_BR ('não','pode') against ('não','pôde') — cannot
#       versus could-not, both correct Portuguese — while n=3 leaves all seven shipped
#       catalogs clean (measured zero). It convicts this ticket's real D1 defect at
#       its pre-cure bytes (dc362df870^), naming both value keys:
#       player.err_session_expired [e scaduta] against login.expired_message
#       [è scaduta]. Disclosed limit: R1 needs a second witness, which is exactly why
#       the it row stands in the curated table too.
#   R2  MISPLACED ACCENT — curated, because R1 structurally cannot see it: moving an
#       acute moves a LETTER of the skeleton (Intentelo versus Intentalo), so there is
#       no collision to find. 'Intentélo' is banned and its family form 'Inténtalo' is
#       required.
#   R3  PRE-REFORM / WRONG-KANJI GLYPHS — curated, for the ja family the review named:
#       帶 U+5E36 (Kyūjitai of 帯 U+5E2C), 聽 U+807D (Kyūjitai; the modern word 視聴
#       writes 聞 U+805E), 継ける AND 継けて (継 U+7D99 'inherit' standing in for 続
#       U+7D9A 'continue' — the ticket cured both forms, so the leg bans both; a lone
#       te-form revert otherwise stays invisible while 続ける survives in another value),
#       plus the old forms 繼 U+7E7C and 續 U+7E8C. Disclosed shape:
#       Japanese is not space-tokenized (ja_JP yields ~452 whitespace tokens against
#       ~1,200 for the Latin families), so glyph substitution is out of R1's reach by
#       construction and ja's value hygiene rides these rows.
#   R4  TEETH. Every family row is pinned on BOTH sides — ban absent AND canonical
#       present — so a row cannot rot into a vacuous ban the day its copy is reworded;
#       rewording the family is legal work that rotates the table in the same commit
#       (Check 48 R3 / Check 66 R6 rotation precedent). And the detectors self-probe
#       in-script (CHECK65 R4 / CHECK66 precedent, no file writes): R1 must convict a
#       planted è/e pair and must NOT convict identical copy; each family row must
#       convict its own plant and must not trip on its own canonical form. A detector
#       that has gone blind reddens the battery instead of guarding nothing.
#
# MEASURED AT COMPOSITION. Against the seven cured catalogs: zero convictions, exit
# 0 (370 values per locale, 8,572 tokens). Against the three pre-cure catalogs at
# dc362df870^, and against an equivalent five-value targeted plant of the same three
# classes: twelve convictions each, covering every row r4 cured — 3 R1 phrase
# divergences + the it ban row (D1), the es ban row (D2), and for D3 the 帶, 聽,
# 継ける and 継けて bans plus three canonical-gone convictions where the parent file
# carried the old forms in place of the family forms (時間帶, no 続ける, no 続けて).
# The same plant through the FULL battery (scripts/verify-runtime.sh, scratch clone)
# reddens Check 67 ALONE at 67 legs — Checks 21, 48 and 51 read these very files and
# stay green exactly as they did on the r4 reviewer's plant, which is the gate
# independence this leg was missing from.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import collections
import glob
import json
import os
import sys
import unicodedata

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

LOCALES = ("de_DE", "en_US", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR")
MIN_VALUES = 300      # 370 per locale at the composition anchor
MIN_TOKENS = 4000     # 8,572 across the seven at the composition anchor

# Curated family rows: (locale, forbidden form, required canonical form, why).
# R1's phrase-context arm is the general detector; these rows are the classes it
# structurally cannot see — a moved accent changes the skeleton, so there is no
# collision to find — and they name this ticket's exact five cured values.
FAMILY = (
    ("es_ES", "Intentélo", "Inténtalo",
     "misplaced accent: the acute sits on another vowel of the same verb, so the "
     "de-accented skeleton itself moves and R1 has no witness pair (r4 ask D2)"),
    ("it_IT", "sessione e scaduta", "sessione è scaduta",
     "stripped copula. R1 convicts it today only while a second witness survives "
     "(login.expired_message); this row holds the law after a reword (r4 ask D1)"),
    ("ja_JP", "帶", "時間帯",
     "pre-reform glyph: Kyūjitai 帶 U+5E36 for post-reform 帯 U+5E2C (r4 ask D3)"),
    ("ja_JP", "聽", "視聴",
     "pre-reform glyph: Kyūjitai 聽 U+807D; the modern word 視聴 writes 聞 U+805E (r4 ask D3)"),
    ("ja_JP", "継ける", "続ける",
     "wrong-kanji sibling of that family: 継 U+7D99 (継承, 'inherit') standing in "
     "for 続 U+7D9A (連続, 'continue') (r4 ask D3)"),
    ("ja_JP", "継けて", "続けて",
     "the same wrong kanji in the te-form the ticket actually cured (r4 ask D3): "
     "without this row a lone 続けて -> 継けて revert stays invisible, because 続ける "
     "still survives in another value and R1 sees no Latin-style accent witness"),
    ("ja_JP", "繼", "続",
     "pre-reform glyph: Kyūjitai 繼 U+7E7C for 継 U+7D99"),
    ("ja_JP", "續", "続",
     "pre-reform glyph: Kyūjitai 續 U+7E8C for 続 U+7D9A"),
)


def skeleton(word):
    """Base letters: NFD-decompose, then drop the combining marks."""
    return "".join(c for c in unicodedata.normalize("NFD", word)
                   if unicodedata.category(c) != "Mn")


def flat_values(doc):
    """Flat 'section.key' -> value map. _metadata is Check 21/48 territory."""
    out = {}

    def walk(node, prefix):
        for key, val in node.items():
            if key == "_metadata":
                continue
            if isinstance(val, dict):
                walk(val, prefix + key + ".")
            elif isinstance(val, str):
                out[prefix + key] = val

    if not isinstance(doc, dict):
        raise ValueError("top level is not an object")
    walk(doc, "")
    return out


def read_catalog(path):
    try:
        with open(path, encoding="utf-8") as handle:
            doc = json.load(handle)
    except (OSError, ValueError) as err:
        problems.append("  %s - CHECK67 R0: unreadable: %s — a value gate cannot run "
                        "vacuously on a catalog it cannot read" % (path, err))
        return None
    try:
        vals = flat_values(doc)
    except ValueError as err:
        problems.append("  %s - CHECK67 R0: %s" % (path, err))
        return None
    if len(vals) < MIN_VALUES:
        problems.append("  %s - CHECK67 R0: only %d string values, the floor is %d — "
                        "scanning a stub catalog proves nothing" % (path, len(vals), MIN_VALUES))
        return None
    return vals


def trigram_divergences(vals):
    """R1: a phrase one catalog repeats must be spelled one way.

    Key = three de-accented token skeletons. Two surfaces for one key therefore
    differ ONLY in diacritics: that is the accent-strip family this ticket had
    to be reviewed into. Three (not two) tokens is measured, not taste: at n=2
    the rule convicts pt_BR ('não','pode') against ('não','pôde') — cannot vs
    could not, both correct Portuguese — while n=3 leaves the seven shipped
    catalogs clean. Genuine homographs need a matching two-token neighbourhood
    to collide, and that is a copy question a human should see anyway.
    """
    seen = collections.defaultdict(lambda: collections.defaultdict(list))
    for vkey in sorted(vals):
        tokens = vals[vkey].split()
        for i in range(len(tokens) - 2):
            window = tuple(tokens[i:i + 3])
            seen[tuple(skeleton(t) for t in window)][window].append(vkey)
    out = []
    for key in sorted(seen):
        if len(seen[key]) > 1:
            out.append((key, sorted(seen[key].items())))
    return out


def family_convictions(loc, text):
    """R2/R3 on ONE locale's copy: its ban absent, its canonical present.

    Both sides are load-bearing. A ban with no canonical anchor rots the day the
    family copy is reworded — the row would then guard nothing while reporting
    green — so a vanished canonical form reddens the leg and the table rotates
    deliberately in the same commit (Check 48 R3 / Check 66 R6 precedent).
    """
    out = []
    for row_loc, forbidden, canonical, why in FAMILY:
        if row_loc != loc:
            continue
        if forbidden in text:
            out.append(("ban", row_loc, forbidden, why))
        if canonical not in text:
            out.append(("canonical", row_loc, canonical, why))
    return out


# ---- R0 the seven catalogs are present, parse and carry real volume -------
paths = sorted(glob.glob("locale/*/strings.json"))
if len(paths) != len(LOCALES):
    problems.append("  locale/*/strings.json - CHECK67 R0: found %d catalogs, expected "
                    "%d — the value scan cannot cover a partial locale tree"
                    % (len(paths), len(LOCALES)))

parsed = {}
for path in paths:
    vals = read_catalog(path)
    if vals is not None:
        parsed[path] = vals

# ---- R1 the automated accent-strip arm ------------------------------------
token_volume = 0
for path in sorted(parsed):
    vals = parsed[path]
    token_volume += sum(len(text.split()) for text in vals.values())
    for key, surfaces in trigram_divergences(vals):
        who = "; ".join("%s = [%s]" % (vkeys[0], " ".join(surface))
                        for surface, vkeys in surfaces)
        problems.append("  %s - CHECK67 R1: the phrase [%s] is spelled %d different ways in "
                        "one catalog (%s) — a repeated phrase keeps ONE diacritic family; "
                        "this is the M-ROKU-20 accent-strip class the value-blind battery "
                        "let through (r4 N2)" % (path, " ".join(key), len(surfaces), who))
if token_volume < MIN_TOKENS:
    problems.append("  locale/*/strings.json - CHECK67 R1: only %d tokens in the witness "
                    "pool, the floor is %d — the phrase-consistency arm would run vacuously"
                    % (token_volume, MIN_TOKENS))

# ---- R2/R3 the curated family arms ----------------------------------------
for path in sorted(parsed):
    loc = path.split(os.sep)[1]
    text = "\n".join(parsed[path].values())
    for kind, _row_loc, form, why in family_convictions(loc, text):
        if kind == "ban":
            problems.append("  %s - CHECK67: [%s] is back in the copy — %s" % (path, form, why))
        else:
            problems.append("  %s - CHECK67: the canonical family form [%s] is gone — %s; a "
                            "ban whose family has left the catalog guards nothing, so rotate "
                            "this row with the reword in the same commit" % (path, form, why))

# ---- R4 self-probe: every arm must convict its plant and spare its cure ---
PLANT_IT = {"a": "La tua sessione e scaduta. Accedi di nuovo.",
            "b": "Login scaduto: la tua sessione è scaduta. Accedi ora."}
CURE_IT = {"a": "La tua sessione è scaduta. Accedi di nuovo.",
           "b": "Login scaduto: la tua sessione è scaduta. Accedi ora."}
if not trigram_divergences(PLANT_IT):
    problems.append("  CHECK67 R4 self-probe: the accent-strip arm did not convict its "
                    "planted è/e pair — R1 is a toothless gate")
if trigram_divergences(CURE_IT):
    problems.append("  CHECK67 R4 self-probe: the accent-strip arm convicted identical "
                    "copy — R1 over-convicts and would redden legitimate work")
for loc, forbidden, canonical, _why in FAMILY:
    if ("ban", loc, forbidden, _why) not in family_convictions(loc, forbidden):
        problems.append("  CHECK67 R4 self-probe: planting [%s] into %s did not name its own "
                        "ban row — the family row cannot fire" % (forbidden, loc))
    if any(kind == "ban" for kind, _row, form, _w in family_convictions(loc, canonical)
           if form == forbidden):
        problems.append("  CHECK67 R4 self-probe: the canonical form [%s] still trips the ban "
                        "on [%s] — the table would redden the copy it defends"
                        % (canonical, forbidden))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK67: %d locale-value pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK67: locale VALUES are guarded, not only keys — any phrase a catalog")
print("           repeats keeps one diacritic family (the arm that could not see")
print("           M-ROKU-20 r4's re-strip plant now convicts by file and value key),")
print("           the misplaced-accent and pre-reform-glyph families are pinned on")
print("           BOTH sides so no row can rot into a vacuous ban, the volume floors")
print("           stop a stub catalog passing the leg, and every detector self-probes")
print("           against its own plant, so the battery cannot silently go blind")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 68: restoreSession keeps credentials on server_error; only verdict arms wipe (R-ROKU-24) ==="
# NUMBERING (disclosed, CHECK62/CHECK66/CHECK67 collision-probe precedent): at
# composition time the highest header in this script is Check 67, and neither
# 'Check 68' nor 'CHECK68' appears anywhere in scripts/, tests/, docs/ or
# README.md (grep rc=1, measured this lane) — 68 is clean.
#
# WHY THE LEG EXISTS (R-ROKU-24, the named-candidate follow-up from
# fixlog/M-ROKU-04__fix-r2.md Issue 2). M-ROKU-04 r1 review issue 2 disclosed
# that the "server_error" bucket — a 2xx /auth/me with no user payload, or a
# non-401/403 answered failure — fell through to the credential wipe, and the
# r2 lane deliberately LIMITED the keep-allowance to transport arms: "A
# keep-on-server_error policy is a candidate follow-up, not silently folded in
# here." This rider IS that follow-up, folded openly: a shape failure or a 5xx
# answers "the server is broken", never "this token is dead", so the arm now
# preserves the stored credentials exactly like the transport arm it sits
# beside. The only wipe-authorized arms are the two VERDICT arms: 401/403
# ("session_invalid" — the server pronounced on THIS token) and the
# empty-state "no_session" (partial leftovers, as always). Cross-host safety
# is not this function's burden: CHECK53 pins PersistAndGo's write-site
# custody wipe, which clears the trio whenever the user points the client at a
# different server, so kept credentials can never ride to an unauthenticated
# host. The behavior's device tests are authored in tests/unit/ApiClient.test.brs
# (the suite is function-object-state EXCLUDED under brs and hardware-gated in
# CI — M-ROKU-04 Discovery.test.brs precedent), so THIS leg is the gate today
# (CHECK50-53 precedent: statement-presence legs, device honesty disclosed).
#
# WHAT IT PINS — over the comment-stripped restoreSession body only:
#   R1  ANTI-VACUITY + keep-shape: the function is found, exactly the TWO
#       server_error assignments the law names stand, and EACH is immediately
#       followed by `return false` — an arm that falls through to the wipe
#       tail regrows the M-ROKU-04 candidate policy.
#   R2  verdict arms stay fall-through: "session_invalid" and "no_session"
#       assignments are NOT followed by `return false` (an early return there
#       would spread the keep to arms the server DID pronounce on).
#   R3  the wipe tail stands and sits downstream: setToken/setRefreshToken/
#       setSession each exactly once in the body, after the session_invalid
#       arm, with the tail `return false` as the body's last statement.
#   R4  the neighbors are untouched: the 401/403 gate literal and the
#       transport arm's `return false` keep (M-ROKU-04's original law) are
#       still present — this rider extends the keep family, it does not
#       relocate it.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(*parts):
    return open(os.path.join(repo, *parts), encoding="utf-8").read()


def strip_comments(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


AC = "source/lib/ApiClient.brs"
code = strip_comments(read(AC))
m = re.search(r"restoreSession: function\(\) as Boolean\n(.*?)\n        end function",
              code, re.DOTALL)
if m is None:
    # R0 (anti-vacuity): the leg's whole subject is this function's shape.
    problems.append(f"  {AC} - CHECK68: restoreSession() not found (or its "
                    "signature drifted) — the credential-retention law has "
                    "no host and this leg must not pass quietly")
else:
    lines = [l.strip() for l in m.group(1).splitlines() if l.strip()]

    def next_line(i):
        return lines[i + 1] if i + 1 < len(lines) else "<end-of-body>"

    # R1: exactly the two server_error sites, each followed by its keep-return.
    se = [i for i, l in enumerate(lines) if l == 'm.restoreReason = "server_error"']
    if len(se) != 2:
        problems.append(f'  {AC} - CHECK68 R1: expected exactly 2 '
                        f'"server_error" assignments (the 2xx-no-user shape '
                        "arm + the no-verdict else arm), found "
                        f"{len(se)} — the bucket's producers must stay the "
                        "two arms R-ROKU-24 rules on")
    for i in se:
        if next_line(i) != "return false":
            problems.append('  ' + AC + ' - CHECK68 R1: a "server_error" '
                            "assignment is followed by [" + next_line(i) +
                            "] instead of `return false` — that arm falls "
                            "through to the wipe tail, which regrows the "
                            "M-ROKU-04 candidate policy R-ROKU-24 closed "
                            '(the "kept" allowance was deliberately limited '
                            "in fixlog/M-ROKU-04__fix-r2.md and folded here)")

    # R2: the verdict arms keep reaching the wipe tail (no early return).
    for verdict in ('m.restoreReason = "session_invalid"',
                    'm.restoreReason = "no_session"'):
        vs = [i for i, l in enumerate(lines) if l == verdict]
        if not vs:
            problems.append(f"  {AC} - CHECK68 R2: {verdict} is gone — the "
                            "boot taxonomy lost a verdict arm")
            continue
        for i in vs:
            if next_line(i).startswith("return"):
                problems.append(f"  {AC} - CHECK68 R2: {verdict} now "
                                "early-returns — the server PRONOUNCED on "
                                "this token (or storage is empty); the wipe "
                                "tail is that arm's law and keeping would "
                                "strand dead credentials")

    # R3: the wipe tail stands, downstream, single-valued, tail-terminated.
    for stmt in ('m.setToken("")', 'm.setRefreshToken("")', 'm.setSession("")'):
        if lines.count(stmt) != 1:
            problems.append(f"  {AC} - CHECK68 R3: the wipe tail must carry "
                            f"{stmt} exactly once (found "
                            f"{lines.count(stmt)}) — credential deletion "
                            "lives in ONE place downstream of the verdict arms")
    if lines:
        wipe_i = lines.index('m.setToken("")')
        si = [i for i, l in enumerate(lines) if l == 'm.restoreReason = "session_invalid"']
        if si and not (wipe_i > si[0]):
            problems.append(f"  {AC} - CHECK68 R3: the wipe no longer sits "
                            "downstream of the session_invalid verdict arm")
        if lines[-1] != "return false":
            problems.append(f"  {AC} - CHECK68 R3: restoreSession's body no "
                            "longer ends in the tail `return false` — the "
                            "false-path contract every boot consumer reads")

    # R4: neighbors untouched — the verdict gate and the transport keep.
    if "env.status = 401 or env.status = 403" not in code:
        problems.append(f"  {AC} - CHECK68 R4: the 401/403 gate literal "
                        "drifted — the ONLY answered responses that may "
                        "pronounce a token dead")
    tr = [i for i, l in enumerate(lines) if l == 'm.restoreReason = transportReason']
    if not tr:
        problems.append(f"  {AC} - CHECK68 R4: the transport keep arm is "
                        "gone — M-ROKU-04's original preservation law")
    else:
        for i in tr:
            if next_line(i) != "return false":
                problems.append(f"  {AC} - CHECK68 R4: the transport arm no "
                                "longer returns before the wipe — a router "
                                "blip would wipe credentials again")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK68: %d credential-retention pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK68: every restoreSession failure that carries NO verdict on this")
print("           token (2xx-no-user shape, non-401/403 answer, unclassifiable")
print("           envelope, transport bucket) PRESERVES the stored credentials;")
print("           only 401/403 and the empty-state arm reach the single wipe")
print("           tail — the keep family extends M-ROKU-04's transport law to")
print("           the answer R-ROKU-24 names, and CHECK53's write-site custody")
print("           wipe keeps cross-host safety independent of this choice")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 69: Roku doc citations are canonical /dev/docs URLs; both legacy redirect families stay extinct (R-ROKU-26 + RT-030) ==="
# NUMBERING (probed, CHECK62/CHECK66 precedent): at composition time the
# highest header in this script is Check 68, and neither 'Check 69' nor
# 'CHECK69' appears anywhere in scripts/, tests/, docs/, README.md or
# CHANGELOG.md (grep rc=1, measured this lane) — 69 is next-FREE.
#
# WHY THE LEG EXISTS (R-ROKU-26, the M-ROKU-05 lane's disclosed out-of-scope
# find, kept alive by fixlog/M-ROKU-05__r1.md note 4). The tree cited Roku's
# pre-reorg docs path — the `docs/refer-ences/...` family (the banned prefix
# below is assembled from fragments; the hyphen here is deliberate, see
# SELF-BURN) — at 21 comment/README/doc sites (AppContext.brs x10,
# PlayerScene.brs x5, ApiClient.brs x1, this script's Check-8/Check-9 header
# comments x2, README.md x2, docs/bif_thumbs.md x1). The October measurement
# called them 404; re-measured at cure time every one answers 301 onto its
# canonical https://developer.roku.com/dev/docs/<page> target (browser UA —
# the whole site answers 403 to bare curl, which is itself why the family
# must not be trusted to keep answering at all). A comment should name the
# live page, not a path that survives only as Roku's redirect grace. The cure
# rotated all 21 sites to their MEASURED Location targets; this leg makes the
# rotation one-way.
#
# RT-030 (w11L1, writer #13, 2026-11-09) swept the SECOND legacy family the
# R-ROKU-26 scan does not cover: the pre-reorg `docs/developer-program/...`
# path (plus one /en-us/ locale-pinned variant) still lived at 11 sites —
# source/main.brs x4, manifest x1, docs/publishing.md x2, docs/bif_thumbs.md
# x1, docs/device-verification.md x2, components/PhlixApp.brs x1 (a URL split
# across two comment lines whose FIRST line carried the contiguous prefix).
# Each rotated to the browser-UA-measured canonical target: deep-linking,
# closed-caption, getting-started, store-certification, mjpeg-bif, and the
# dead focus-management.md split (its legacy target 404s through the current
# redirect) folded onto the live core-concepts page. This leg now bans both
# families and R2 pins the new citations the same one-way law.
#
# SELF-BURN (disclosed): this script and tests/scripts/verify-runtime-portable.sh
# live INSIDE the scanned surface; both build every banned prefix from
# ADJACENT string literals so the ban never matches its own gate. CHANGELOG.md is
# deliberately OUT of the scan set — the verbatim-history law forbids rewriting
# historical entries that quote the retired paths.
#
# WHAT IT PINS:
#   R1  Family ban, read directly off the shipped surface: no scanned line
#       carries either contiguous legacy prefix (the references family and
#       the developer-program family); convictions name file:line and
#       the cited URL. A whitelisted-extension file that is not valid UTF-8
#       fails LOUD (the scan certifies what it reads; silence is not a pass).
#       Scan set: source/ components/ scripts/ tests/ docs/ locale/ images/ +
#       README.md manifest package.json; dot-dirs, build/ and node_modules/
#       pruned; citation extensions .brs .xml .md .json .sh .txt.
#   R2  Migrated citations LIVE ON: each rotated carrier file must still cite
#       the canonical dev/docs page its rotation landed on. Deleting a
#       citation launders documentation instead of curing it — the arm
#       convicts file, page and the loss. (This script's own two rotated
#       comments are NOT pinned: a gate self-citing its subject is circular.)
#       Carrier list: TEN carrier files pinning SEVENTEEN pages — R-ROKU-26's
#       five files (AppContext.brs, ApiClient.brs, PlayerScene.brs, README.md,
#       bif_thumbs.md) plus the five new files RT-030 rotated (main.brs,
#       manifest, PhlixApp.brs, publishing.md, device-verification.md);
#       bif_thumbs.md joins the rotation with a SECOND pinned page
#       (mjpeg-bif), so it counts once as a carrier — the r1 wave's "eleven
#       carriers" prose double-counted it (CHANGELOG carries the forward
#       correction; verbatim history keeps its entry). Each era stages the
#       files its own pins read, and the twin's CI-layout stage list carries
#       all of them (measured: twin :195/:210/:225/:235/:248/:261/:266/:267 +
#       the manifest cp and the components cp -a).
#   R3  LEDGER SELF-CENSUS (w11L1 r2): docs/static-checks.md row 69 must
#       carry a "CARRIERS (n carriers, p pins)" census block whose segments
#       equal THIS dict — names and per-carrier page sets, derived, not
#       paraphrased. The r1 review convicted a booked-but-never-landed row
#       amendment (prose ahead of disk — this wave's own quarry); R3 makes
#       that decay shape convict in the gate, naming the drift either way.
#       A missing row 69 or missing ledger convicts LOUD (the arm certifies
#       what it reads). No new Check number; the twin's CHECK69 plants do
#       not touch the ledger, so its exactly-two-convictions assertion
#       stands; R3's own falsification is measured red-first in the lane's
#       scratch clone (register .reviews/2026-11-09/FIX-roku-w11L1-round2.md).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []

# Assembled from adjacent literals (SELF-BURN law, header above): the
# contiguous banned prefixes must never exist in this file's own bytes.
LEGACIES = (
    "developer.roku.com/docs/refer" "ences/",
    "developer.roku.com/docs/developer-" "program/",
)

SCAN_DIRS = ("source", "components", "scripts", "tests", "docs", "locale", "images")
SCAN_FILES = ("README.md", "manifest", "package.json")
CITATION_EXTS = {".brs", ".xml", ".md", ".json", ".sh", ".txt"}
PRUNE = {"build", "node_modules"}


def scanned():
    for top in SCAN_DIRS:
        if not os.path.isdir(top):
            continue
        for root, dirs, files in os.walk(top):
            dirs[:] = [d for d in sorted(dirs)
                       if not d.startswith(".") and d not in PRUNE]
            for name in sorted(files):
                if os.path.splitext(name)[1] in CITATION_EXTS:
                    yield os.path.join(root, name).replace(os.sep, "/")
    for name in SCAN_FILES:
        if os.path.isfile(name):
            yield name


texts = {}
for path in scanned():
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        problems.append(f"  {path} - CHECK69 R1: whitelisted citation file is "
                        "not readable UTF-8 text — this scan certifies what it "
                        "reads; it may not silently skip a member")
        continue
    texts[path] = text
    for lineno, line in enumerate(text.splitlines(), 1):
        for legacy in LEGACIES:
            if legacy in line:
                m = re.search(r"https?://\S*" + re.escape(legacy) + r"\S*", line)
                cited = m.group(0).rstrip(").,;:'\"") if m else legacy
                problems.append(
                    f"  {path}:{lineno} - CHECK69 R1: legacy Roku doc URL cited: "
                    f"{cited} \u2014 cite the canonical "
                    "https://developer.roku.com/dev/docs/<page> target; the "
                    "legacy path is redirect-only indirection, not documentation")

CANON = "https://developer.roku.com/dev/docs/"
CARRIERS = {
    "source/lib/AppContext.brs": ("ifdeviceinfo", "ifappinfo", "ifappmanager",
                                  "iftimespan"),
    "source/lib/ApiClient.brs": ("ifdeviceinfo",),
    "components/PlayerScene.brs": ("ifdeviceinfo", "remote-control-events"),
    "README.md": ("remote-control-events",),
    "docs/bif_thumbs.md": ("media-playback-nodes", "mjpeg-bif"),
    # RT-030 (w11L1): the developer-program-family rotations, same one-way law.
    "manifest": ("deep-linking",),
    "source/main.brs": ("deep-linking",),
    "components/PhlixApp.brs": ("core-concepts",),
    "docs/publishing.md": ("getting-started", "store-certification"),
    "docs/device-verification.md": ("deep-linking", "closed-caption"),
}
for carrier in sorted(CARRIERS):
    text = texts.get(carrier)
    if text is None:
        problems.append(f"  {carrier} - CHECK69 R2: the citation carrier is "
                        "gone from the layout — R-ROKU-26's rotated citations "
                        "it hosted cannot be verified")
        continue
    for page in CARRIERS[carrier]:
        if CANON + page not in text:
            problems.append(
                f"  {carrier} - CHECK69 R2: the canonical "
                f"{CANON + page} citation vanished — the rotated law-comment "
                "must name the live page; deleting a citation launders "
                "documentation, it is not a cure")

# R3 (w11L1 r2): the checks ledger must AGREE with the dict above — derived
# equality, not paraphrase. Row 69 carries a "CARRIERS (n carriers, p pins)"
# census block whose segments are one 'path: page, page' per carrier, closed
# by the next em-dash. Marker absent = the counts drifted (dict grew or the
# amendment never landed — the r1 booking-lag class this arm exists to
# catch); a missing/added carrier or a page-set drift convicts, named either
# way. A row-less or ledger-less layout convicts LOUD: the self-census
# certifies what it reads; it may not silently skip its subject.
LEDGER = "docs/static-checks.md"
LEDGER_MARK = "CARRIERS (%d carriers, %d pins)" % (
    len(CARRIERS), sum(len(pages) for pages in CARRIERS.values()))
row69 = None
for line in texts.get(LEDGER, "").splitlines():
    if line.startswith("| 69 "):
        row69 = line
        break
if row69 is None:
    problems.append("  " + LEDGER + " - CHECK69 R3: no row 69 in the checks "
                    "ledger — the self-census certifies what it reads; it "
                    "may not silently skip its subject")
else:
    at = row69.find(LEDGER_MARK)
    if at == -1:
        problems.append("  " + LEDGER + " - CHECK69 R3: row 69 carries no "
                        "'" + LEDGER_MARK + "' census — the ledger and the "
                        "gate dict disagree on the counts (rotate the row's "
                        "CARRIERS block with the dict in the same commit)")
    else:
        block = row69[at + len(LEDGER_MARK):]
        sep = " \u2014 "
        if block.startswith(sep):
            block = block[len(sep):]
        cut = block.find(sep)
        if cut != -1:
            block = block[:cut]
        parsed = {}
        for seg in block.split(";"):
            seg = seg.strip()
            if not seg:
                continue
            name, colon, pages = seg.partition(":")
            if not colon or not pages.strip():
                problems.append("  " + LEDGER + " - CHECK69 R3: census "
                                "segment '" + seg + "' is not a "
                                "'path: page, page' shape")
                continue
            parsed[name.strip()] = frozenset(
                p.strip() for p in pages.split(",") if p.strip())
        expected = dict((k, frozenset(v)) for k, v in CARRIERS.items())
        for carrier in sorted(set(expected) - set(parsed)):
            problems.append("  " + LEDGER + " - CHECK69 R3: the gate dict "
                            "pins carrier '" + carrier + "' but row 69 does "
                            "not name it — the docs census lags the gate")
        for carrier in sorted(set(parsed) - set(expected)):
            problems.append("  " + LEDGER + " - CHECK69 R3: row 69 names "
                            "carrier '" + carrier + "' the gate dict does "
                            "not pin — the ledger claims teeth the gate "
                            "does not have")
        for carrier in sorted(set(parsed) & set(expected)):
            if parsed[carrier] != expected[carrier]:
                problems.append(
                    "  " + LEDGER + " - CHECK69 R3: row 69's page set for '"
                    + carrier + "' (" + ", ".join(sorted(parsed[carrier]))
                    + ") drifts from the dict pin ("
                    + ", ".join(sorted(expected[carrier]))
                    + ") — rotate the row with the dict")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK69: %d Roku-doc-citation pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK69: every Roku docs citation on the shipped surface points at")
print("           the canonical /dev/docs page - both legacy redirect families")
print("           (references, developer-program) are extinct here and stay")
print("           extinct, and every carrier keeps its migrated citations")
print("           (21 sites rotated by R-ROKU-26; 11 more by RT-030)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 70: the hub-relay dial proves Sec-WebSocket-Accept before any session traffic (R-ROKU-05) ==="
# NUMBERING (probed, CHECK62/CHECK69 precedent): at composition time the
# highest header in this script is Check 69, and neither 'Check 70' nor
# 'CHECK70' appears anywhere in scripts/, tests/, docs/, README.md or
# CHANGELOG.md (grep rc=1, measured this lane) — 70 is next-FREE.
#
# WHY THE LEG EXISTS (R-ROKU-05, triage .reviews/ledger-exec/E-rok0507-triage.md).
# The hub relay consumer (components/HubCommandTask.brs, ws://hub:8804/
# syncplay/{server_id}) accepted ANY "HTTP/1.1 101" status line: a blind LAN
# injector that forges the status line — without ever having seen this dial's
# random key — was handed a live command channel carrying the scoped relay
# token on the socket it chose. The M-ROKU-14 cure shipped the fail-closed
# RFC6455 accept-proof trio (SyncPlayProtocol.VerifyHandshakeAccept et al.)
# and wired it at exactly ONE caller (SyncPlayTask.brs, the :8097 dial),
# while CHECK46 R2 pinned the ordering law at THAT site only — the relay
# sibling stayed a status-line-only acceptor by asymmetry, not by decision.
# The cure: the ordered twin guard at the relay site (HubCommandTask
# WaitForConnect), refusing into this file's own backoff-ladder idiom
# (return false — no wsAcceptFailed tag: the SyncPlayTask emit path has no
# consumer here, and R2 keeps that divergence sanctioned). Precondition
# proven by cross-repo read before wiring (fixlog/R-ROKU-05__fix.md): the
# hub :8804 101 is emitted by Workerman's Websocket protocol, which echoes
# base64(SHA1(offered key + GUID)) unconditionally on every upgrade
# (phlix-hub vendor/workerman/workerman/src/Protocols/Websocket.php —
# coordinates re-verified against hub master 81be1692 on 2026-11-09 by the
# w08L3 fold: key read + 400 branch :509-514, digest computed :516, the 101
# built :518-522 and sent :557) — proof never bricks a live relay.
#
# WHAT IT PINS (arms follow the CHECK46 R2 precedent: shape-identity needles,
# fail-loud on unreadable inputs, mask() before any code-shape scan):
#   R1  relay-site proof, ordered and bound: inside HubCommandTask
#       WaitForConnect the offered key is captured (NewWebSocketKey →
#       keyB64), THAT key is the one BuildHandshakeRequest sends, the
#       HandshakeAccepted status gate stands, the fail-closed
#       `if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then
#       return false` runs AFTER the status gate (both single-line and
#       block forms pass — shape tolerance, never over-convict the law),
#       and BEFORE AppendRemainderBytes feeds the frame accumulator — a
#       refused handshake may not leave parsed-frame machinery armed.
#   R2  scope precision (the amnesty side of the law): the proof rides the
#       TESTED trio — no bespoke roEVPDigest/SHA1/GUID reimplementation in
#       the file's CODE (the :35 docblock's truthful wss-DEFERRED transport
#       prose is untouched by this arm, comments are masked); the
#       `local.ws_accept_invalid` census code stays SyncPlayTask-owned
#       (Check 46 R3's emit gate — a second emitter here would repurpose a
#       room-session code for the command channel without a law); and the
#       era's status-line-only posture may not re-grow as prose
#       ("do NOT verify ... Sec-WebSocket-Accept").
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

HCT = "components/HubCommandTask.brs"
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK70: unreadable: {err} — the pin cannot run vacuously")
        return None


def mask(code):
    out = []
    for line in code.splitlines():
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        out.append(line)
    return "\n".join(out)


def body(code, kind, name):
    m = re.search(rf"{kind}\s+{name}\b[\s\S]*?\bend\s+{kind}\b", code)
    return m.group(0) if m else None


# ---- R1 the relay dial carries the ordered, key-bound, fail-closed proof --
hct = read(HCT)
if hct is not None:
    code = mask(hct)
    b = body(code, "function", "WaitForConnect")
    if b is None:
        problems.append(
            f"  {HCT} - CHECK70 R1: WaitForConnect is gone — the relay handshake lost "
            "the home that carries its accept proof (R-ROKU-05)")
    else:
        ki = re.search(r"keyB64\s*=\s*m\.proto\.NewWebSocketKey\(\)", b)
        bi = re.search(r"BuildHandshakeRequest\(\s*host\s*,\s*port\s*,\s*path\s*,\s*keyB64\s*,", b)
        hi = b.find("HandshakeAccepted(headerText)")
        vm = re.search(
            r"if\s+not\s+m\.proto\.VerifyHandshakeAccept\(\s*headerText\s*,\s*keyB64\s*\)"
            r"\s+then\s+return\s+false", b)
        ai = b.find("AppendRemainderBytes(headerBytes, termIdx + 4)")
        if ki is None:
            problems.append(
                f"  {HCT} - CHECK70 R1: the offered key is no longer captured as keyB64 "
                "(NewWebSocketKey) — the proof has nothing bound to THIS handshake")
        if bi is None:
            problems.append(
                f"  {HCT} - CHECK70 R1: BuildHandshakeRequest no longer receives keyB64 in "
                "its positional shape — the verified key must be the key this dial offered")
        if hi < 0:
            problems.append(
                f"  {HCT} - CHECK70 R1: the HandshakeAccepted status gate vanished from the "
                "relay dial")
        if vm is None:
            problems.append(
                f"  {HCT} - CHECK70 R1: WaitForConnect never verifies Sec-WebSocket-Accept — "
                "the era's status-line-only posture is back: a forged 101 re-opens the "
                "command channel behind the scoped relay token (R-ROKU-05)")
        else:
            if hi >= 0 and vm.start() < hi:
                problems.append(
                    f"  {HCT} - CHECK70 R1: VerifyHandshakeAccept moved BEFORE the "
                    "HandshakeAccepted status gate (ordering law, SyncPlayTask twin)")
            if ki is not None and vm.start() < ki.start():
                problems.append(
                    f"  {HCT} - CHECK70 R1: the accept proof runs before the key is "
                    "offered — it verifies nothing this handshake sent")
        if ai >= 0 and vm is not None and ai < vm.start():
            problems.append(
                f"  {HCT} - CHECK70 R1: AppendRemainderBytes feeds the frame accumulator "
                "BEFORE the accept proof — a refused handshake would leave parsed-frame "
                "machinery armed with the injector's bytes")

# ---- R2 scope precision: shared trio, SyncPlayTask-only emit, prose ------
if hct is not None:
    code = mask(hct)
    low = code.lower()
    for needle, name in (("roevpdigest", "roEVPDigest"), ("\"sha1\"", "a \"sha1\" digest name"),
                         (GUID.lower(), "the RFC6455 GUID literal")):
        if needle in low:
            problems.append(
                f"  {HCT} - CHECK70 R2: the relay dial carries a bespoke accept computation "
                f"({name}) — the proof must ride the unit-tested SyncPlayProtocol trio "
                "(SecWebSocketAcceptValue / ExpectedSecWebSocketAccept / VerifyHandshakeAccept), "
                "not a second unaudited implementation")
    if "local.ws_accept_invalid" in hct:
        problems.append(
            f"  {HCT} - CHECK70 R2: the SyncPlayTask-owned census code local.ws_accept_invalid "
            "appears at the relay site — its emit gate lives under m.wsAcceptFailed on the "
            ":8097 dial (Check 46 R3); the command channel refuses into the backoff ladder "
            "and Check 70's sanctioned divergence keeps it that way")
    if re.search(r"do NOT verify[\s\S]{0,80}?Sec-WebSocket-Accept", hct):
        problems.append(
            f"  {HCT} - CHECK70 R2: the era's \"do NOT verify the Sec-WebSocket-Accept\" "
            "claim is back at the relay site")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK70: %d hub-relay accept-proof pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK70: the hub-relay dial proves Sec-WebSocket-Accept before any")
print("           frame byte reaches the session accumulator — fail-closed,")
print("           ordered, bound to the key THIS handshake offered, proof")
print("           riding the tested trio, and the SyncPlayTask emit idiom")
print("           staying SyncPlayTask-only (the :8804 command channel can")
print("           never again accept a status-line-only handshake)")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 71: the boot-auth Timer rides the documented field idiom; the fabricated ms-method and stop-method stay extinct (R-ROKU-06) ==="
# NUMBERING (CHECK62/66/69/70 collision-probe precedent): at composition time the
# highest header in this script is Check 70, and neither 'Check 71' nor
# 'CHECK71' appears anywhere in scripts/, tests/, docs/, README.md or
# CHANGELOG.md of the anchor tree (git grep rc=1 at c7bfebd8, measured this
# lane; the single working-tree hit is this family's own row-49 forward
# reference) — 71 is next-FREE.
#
# WHY THE LEG EXISTS (R-ROKU-06, triage .reviews/ledger-exec/E-rok0507-triage.md;
# ask RIDERS_QUEUE.md R-ROKU-06). The boot-auth path carried fabricated
# METHOD calls on an roSGNode "Timer": a ms-based duration setter at the two
# Start* sites and a bare stop-method call at the four timeout/response
# handlers. The vendored authority this repo's own lock pins (bsc 0.72.5
# roku-types/data.json) models Timer with the fields control/duration/fire/
# repeat, ZERO interfaces, and the setter name occurs ZERO times in that
# file — the calls are runtime no-ops (at best), so the armed 20 s boot
# timeout never actually held the unit or the cancel its source claimed.
# W-min94 (a1ec49a) made the timer REAL (attach half); docs row 49 already
# legislated "the fabricated setter method stays dead" — aspirational beyond
# the toast coordinator until this lane rotated all six sites to the file's
# own field idiom (ArmToastDismiss: control stop, duration SECONDS, control
# start) and this leg made the ban one-way.
#
# WHAT IT PINS (fail-loud on unreadable inputs; comment-masked scans; the
# two banned needles are assembled from adjacent literals — CHECK69
# SELF-BURN law — so no contiguous banned byte exists in this script):
#   R1  fabricated-method extinction over the shipped CODE surface: every
#       .brs under components/ + source/ (true file:line named). Scope is
#       the code view on purpose — the no-op class lives there; docs and
#       CHANGELOG name the dead method verbatim as law/history (the
#       verbatim-history precedent, CHECK59 row).
#   R2  start-site shape (two arms): StartAuthCheck and StartHubAuthCheck
#       each carry EXACTLY ONE duration assignment on the seconds literal —
#       unit-boundary checked, so the ms era cannot be laundered back under
#       the correct field name (20 passes, 20000 does not) — and the
#       duration write precedes the control start write (a field set after
#       start cannot re-time the run in flight).
#   R3  stop-site shape (four arms): OnAuthTimeout, OnBootRetryButton,
#       OnAuthResponse and OnHubAuthResponse each cancel through exactly
#       one control-field stop — the same file's replace-block idiom.
#   R4  docs truth: the row-49 law sentence carries its cure-attached
#       markers (R-ROKU-06 + Check 71), so "stays dead" cannot silently
#       drift back to aspiration — docs may not under-claim shipped
#       behavior (CHECK44 R5 precedent).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK71: unreadable: {err} — the pin cannot run vacuously")
        return None


# Banned needles assembled from adjacent literals (SELF-BURN law): the
# contiguous forms never exist in this script's own bytes.
SD = "Set" + "Dura" + "tion("
AS = "authTimer." + "Sto" + "p("


def code_lines(code):
    """(line_number, line) for non-comment lines — TRUE file line numbers."""
    for i, line in enumerate(code.splitlines(), 1):
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        yield i, line


# ---- R1 fabricated-method extinction over the shipped code surface -------
targets = []
for root in ("components", "source"):
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".brs"):
                targets.append(os.path.join(dirpath, name))
if not targets:
    problems.append(
        "  CHECK71 R1: no shipped .brs found under components/ + source/ — the "
        "extinction walk cannot run vacuously")
for path in sorted(targets):
    code = read(path)
    if code is None:
        continue
    for i, line in code_lines(code):
        if SD in line:
            problems.append(
                f"  {path}:{i} - CHECK71 R1: the Timer's fabricated ms-setter is back — the "
                "vendored bsc 0.72.5 model is fields control/duration/fire/repeat with NO "
                "methods; the call is a runtime no-op. Arm the timeout through the "
                "duration field in SECONDS (R-ROKU-06)")
        if AS in line:
            problems.append(
                f"  {path}:{i} - CHECK71 R1: the fabricated stop-method is back on the "
                "boot-auth Timer — the node model has no methods; cancel through "
                "control = \"stop\" (R-ROKU-06)")

# ---- R2/R3 boot-auth Timer shapes in components/PhlixApp.brs -------------
APP = read("components/PhlixApp.brs")
if APP is not None:
    code = "\n".join(line for _i, line in code_lines(APP))

    def body(name):
        m = re.search(r"(?:function |sub )" + name + r"\(.*?\)(.*?)end (?:function|sub)",
                      code, re.DOTALL)
        return m.group(1) if m else None

    for fn in ("StartAuthCheck", "StartHubAuthCheck"):
        b = body(fn)
        if b is None:
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R2: {fn} vanished — the boot-auth timer "
                "lost the home that arms its 20 s timeout (R-ROKU-06)")
            continue
        durs = list(re.finditer(r"m\.authTimer\.duration\s*=\s*20(?![0-9])", b))
        starts = list(re.finditer(r"m\.authTimer\.control\s*=\s*\"start\"", b))
        if len(durs) != 1:
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R2: {fn} carries {len(durs)}/1 duration "
                "assignments on the seconds literal 20 — the Timer arms through the "
                "duration field in SECONDS; the ms era cannot return, under the field "
                "name or any other (unit boundary pinned) (R-ROKU-06)")
        if len(starts) != 1:
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R2: {fn} carries {len(starts)}/1 "
                "control start writes — exactly one Timer arm is the shipped shape "
                "(R-ROKU-06)")
        if len(durs) == 1 and starts and durs[0].start() > starts[-1].start():
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R2: {fn} writes duration AFTER "
                "control = \"start\" — a field set after start cannot re-time the run "
                "in flight; order duration-then-start (R-ROKU-06)")

    for fn in ("OnAuthTimeout", "OnBootRetryButton", "OnAuthResponse", "OnHubAuthResponse"):
        b = body(fn)
        if b is None:
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R3: {fn} vanished — a boot-auth "
                "timer-cancel home is gone (R-ROKU-06)")
            continue
        stops = len(re.findall(r"m\.authTimer\.control\s*=\s*\"stop\"", b))
        if stops != 1:
            problems.append(
                f"  components/PhlixApp.brs - CHECK71 R3: {fn} carries {stops}/1 "
                "control-field stops — the Timer cancels through control = \"stop\", "
                "the same file's replace-block idiom (R-ROKU-06)")

# ---- R4 docs row-49 law sentence carries its cure markers -----------------
DOC = read("docs/static-checks.md")
if DOC is not None:
    rows = [l for l in DOC.splitlines()
            if "Timer model is control/duration/fire/repeat" in l]
    if not rows:
        problems.append(
            "  docs/static-checks.md - CHECK71 R4: the row-49 Timer-model law sentence "
            "vanished — the repo-wide ban must stay written down (R-ROKU-06)")
    for l in rows:
        for marker in ("R-ROKU-06", "Check 71"):
            if marker not in l:
                problems.append(
                    "  docs/static-checks.md - CHECK71 R4: the row-49 \"stays dead\" claim "
                    f"drifted back toward aspiration — the cure marker {marker} vanished "
                    "from the law sentence; docs may not under-claim shipped behavior")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK71: %d boot-auth Timer idiom pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK71: the boot-auth Timer arms through the seconds `duration` field")
print("           and cancels through `control` at all six sites — the fabricated")
print("           ms-setter and stop-method are extinct in every shipped code")
print("           view, the ms era cannot be laundered back under the field name")
print("           (unit boundary pinned), duration-before-start ordering holds,")
print("           and the row-49 law keeps its cure-attached marker")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 72: the direct-play gate probes the named canonical codec; the call-site magic literal and the phantom-conditional comment stay extinct (R-ROKU-27) ==="
# NUMBERING (CHECK62/66/69/70/71 collision-probe precedent): at composition time
# the highest header in this script is Check 71, and neither 'Check 72' nor
# 'CHECK72' appears anywhere in scripts/, tests/, docs/, README.md or
# CHANGELOG.md of the anchor tree (git grep rc=1 at 5423b75d, measured this
# lane) — 72 is next-FREE.
#
# WHY THE LEG EXISTS (R-ROKU-27, ask RIDERS_QUEUE.md R-ROKU-27; disclosed
# out-of-scope by fixlog/M-ROKU-05__fix.md and kept alive by
# fixlog/M-ROKU-05__r1.md note 4). The direct-play capability gate probed a
# quoted "h264" literal AT THE CALL SITE while its comment claimed a
# default-when-unspecified branch that no caller, wire field, or device
# surface ever supplied: the server exposes per-file codec only in the
# admin-gated files block (MediaItemShaper::buildFilesBlock) and
# playback-info carries no video-track codec a non-admin client could
# consume, so the call asserted knowledge the client structurally cannot
# have. The estate truth the magic string stood for: h264 IS the canonical
# delivery codec — every server device profile transcodes to h264
# (QualitySelector::loadDefaultProfiles) and the quality ladder's
# stream-copy branch admits only h264 sources (AbrLadder::buildOriginal).
# The cure moves the bet into the file's own accessor idiom
# (DirectPlayProbeCodec in source/lib/AppContext.brs, beside
# DeviceCanDecodeVideo) with its honest rationale in ONE docblock, and this
# leg makes the shape one-way: probes name the codec, they do not guess it
# inline, and the phantom-conditional sentence cannot re-grow.
#
# WHAT IT PINS (fail-loud on unreadable inputs; comment-masked code walks;
# banned comment fragments assembled from adjacent literals — CHECK69
# SELF-BURN law):
#   R1  call-site law over every shipped .brs under components/ + source/:
#       no DeviceCanDecodeVideo CALL may take a quoted-string first argument
#       (the definition line carries no quote and is structurally exempt;
#       file:line named) — and PlayerScene.brs's code view carries EXACTLY
#       ONE gate call, in the shipped accessor shape
#       DeviceCanDecodeVideo(DirectPlayProbeCodec(), streamFormat, ""), so
#       the sole consumer cannot vanish or multiply silently.
#   R2  the single named source in source/lib/AppContext.brs: exactly one
#       DirectPlayProbeCodec() definition, typed 'as String', whose body is
#       exactly one return of the canonical "h264" literal (value drift is
#       conviction, not re-derivation), whose rationale docblock sits
#       directly above it and carries the cure markers R-ROKU-27 + Check 72
#       plus the rationale phrases (canonical delivery codec / transcode /
#       non-admin) — the bet may move only where it is named.
#   R3  phantom-conditional extinction over the shipped code view's COMMENT
#       surface: no single comment line may again join the fabricated
#       "…ault codec to…" claim with its "if not spe…cified" escape hatch —
#       the sentence that dressed a static guess as a defaulted lookup.
#       Docs and CHANGELOG may narrate the era verbatim (CHECK71 R1
#       precedent: history lives outside the code view on purpose).
#   R4  docs truth: docs/static-checks.md row 72 exists and carries its
#       cure markers (R-ROKU-27 + Check 72) — the ledger cannot under-claim
#       the shipped law (CHECK44 R5 / CHECK71 R4 precedent).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK72: unreadable: {err} — the pin cannot run vacuously")
        return None


def code_lines(code):
    """(line_number, line) for non-comment lines — TRUE file line numbers."""
    for i, line in enumerate(code.splitlines(), 1):
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            continue
        yield i, line


def comment_lines(code):
    """(line_number, line) for comment lines only — R3's banned sentence era."""
    for i, line in enumerate(code.splitlines(), 1):
        t = line.strip()
        if t.startswith("'") or t.startswith("Rem") or t.startswith("rem "):
            yield i, line


# Fragments of the fabricated sentence, assembled from adjacent literals
# (SELF-BURN law): the contiguous forms never exist in this script's bytes.
PH1 = "ault codec " + "to"
PH2 = "if not spe" + "cified"

MAGIC = re.compile(r"(?i)(?<![A-Za-z0-9_])DeviceCanDecodeVideo\s*\(\s*\"")
GATE = re.compile(r"(?i)(?<![A-Za-z0-9_])DeviceCanDecodeVideo\s*\(")
SHIPPED = re.compile(
    r"(?i)DeviceCanDecodeVideo\s*\(\s*DirectPlayProbeCodec\s*\(\s*\)\s*,\s*"
    r"streamFormat\s*,\s*\"\"\s*\)")

# ---- R1 call-site law over the shipped code view --------------------------
targets = []
for root in ("components", "source"):
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".brs"):
                targets.append(os.path.join(dirpath, name))
if not targets:
    problems.append(
        "  CHECK72 R1: no shipped .brs found under components/ + source/ — the "
        "call-site walk cannot run vacuously")
scene = read("components/PlayerScene.brs")
for path in sorted(targets):
    code = scene if path == os.path.join("components", "PlayerScene.brs") else None
    if code is None:
        code = read(path)
    if code is None:
        continue
    for i, line in code_lines(code):
        if MAGIC.search(line):
            problems.append(
                f"  {path}:{i} - CHECK72 R1: a quoted codec literal is back at a "
                "DeviceCanDecodeVideo call site — the direct-play probe may only "
                "name the codec through DirectPlayProbeCodec(); no wire field gives "
                "this client the source's true codec, and an inline literal launders "
                "the estate bet into an unsourced guess (R-ROKU-27)")

if scene is not None:
    gates = [(i, l) for i, l in code_lines(scene) if GATE.search(l) and not SHIPPED.search(l)]
    shipped = [(i, l) for i, l in code_lines(scene) if SHIPPED.search(l)]
    if len(shipped) != 1:
        problems.append(
            f"  components/PlayerScene.brs - CHECK72 R1: {len(shipped)}/1 gate calls in "
            "the shipped accessor shape DeviceCanDecodeVideo(DirectPlayProbeCodec(), "
            "streamFormat, \"\") — the sole direct-play consumer must probe through "
            "the named codec (R-ROKU-27)")
    for i, _l in gates:
        problems.append(
            f"  components/PlayerScene.brs:{i} - CHECK72 R1: a DeviceCanDecodeVideo call "
            "in this file deviates from the shipped accessor shape — the probe codec "
            "is named by DirectPlayProbeCodec(), not improvised per call site "
            "(R-ROKU-27)")

# ---- R2 the single named source in source/lib/AppContext.brs --------------
CTX = read("source/lib/AppContext.brs")
if CTX is not None:
    lines = CTX.splitlines()
    defs = [i for i, l in enumerate(lines, 1)
            if re.search(r"(?i)^\s*function\s+DirectPlayProbeCodec\s*\(\s*\)", l)]
    if len(defs) != 1:
        problems.append(
            f"  source/lib/AppContext.brs - CHECK72 R2: {len(defs)}/1 "
            "DirectPlayProbeCodec definitions — the probe codec has exactly one "
            "named home beside its consumer's gate (R-ROKU-27)")
    else:
        d = defs[0]
        if not re.search(r"(?i)^\s*function\s+DirectPlayProbeCodec\s*\(\s*\)\s*as\s+String\s*$",
                         lines[d - 1]):
            problems.append(
                f"  source/lib/AppContext.brs:{d} - CHECK72 R2: the accessor's return "
                "contract moved off 'as String' — callers feed the literal straight "
                "into the CanDecodeVideo options AA (R-ROKU-27)")
        end = None
        for j in range(d, len(lines)):
            if re.search(r"(?i)^\s*end\s+function", lines[j]):
                end = j
                break
        if end is None:
            problems.append(
                "  source/lib/AppContext.brs - CHECK72 R2: DirectPlayProbeCodec never "
                "closes — the accessor body is unreadable as a shape (R-ROKU-27)")
        else:
            body = "\n".join(lines[d:end])
            rets = re.findall(r"(?i)^\s*return\s+(.*)$", body, re.M)
            if len(rets) != 1 or rets[0].strip() != '"h264"':
                problems.append(
                    "  source/lib/AppContext.brs - CHECK72 R2: the accessor's body is "
                    f"not exactly one 'return \"h264\"' (found {len(rets)} return arm(s)) "
                    "— h264 is the estate's canonical delivery codec (every server "
                    "profile transcodes to it); the value moves ONLY by rotating this "
                    "pin from a measured red, with the docblock rationale rewritten to "
                    "match (R-ROKU-27)")
        doc = []
        k = d - 2
        while k >= 0:
            t = lines[k].strip()
            if t.startswith("'"):
                doc.append(t)
                k -= 1
            else:
                break
        joined = "\n".join(doc)
        for marker in ("R-ROKU-27", "Check 72", "canonical delivery codec", "transcode",
                       "non-admin"):
            if marker not in joined:
                problems.append(
                    f"  source/lib/AppContext.brs - CHECK72 R2: the accessor docblock "
                    f"lost its rationale marker \"{marker}\" — the named bet must keep "
                    "the reasoning that makes it honest, not decay into a second magic "
                    "constant (R-ROKU-27)")

# ---- R3 phantom-conditional extinction over the comment surface -----------
for path in sorted(targets):
    code = read(path)
    if code is None:
        continue
    for i, line in comment_lines(code):
        if PH1 in line and PH2 in line:
            problems.append(
                f"  {path}:{i} - CHECK72 R3: the fabricated phantom-conditional codec "
                "comment is back — the gate has no defaulted lookup to describe: no "
                "caller, wire field, or device surface ever supplies a codec here. "
                "The rationale lives in DirectPlayProbeCodec's docblock (R-ROKU-27)")

# ---- R4 docs row 72 carries its cure markers -------------------------------
DOC = read("docs/static-checks.md")
if DOC is not None:
    rows = [l for l in DOC.splitlines() if re.match(r"^\|\s*72\s*\|", l)]
    if not rows:
        problems.append(
            "  docs/static-checks.md - CHECK72 R4: row 72 vanished — the checks ledger "
            "must enumerate this shipped leg (CHECK66-era landing law) (R-ROKU-27)")
    for l in rows:
        for marker in ("R-ROKU-27", "Check 72"):
            if marker not in l:
                problems.append(
                    "  docs/static-checks.md - CHECK72 R4: row 72 lost its cure marker "
                    f"\"{marker}\" — the ledger may not under-claim the shipped law")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK72: %d direct-play codec-probe pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK72: the direct-play gate probes the named canonical delivery codec")
print("           through exactly one accessor-shaped call; the accessor is the")
print("           single 'h264' home with its rationale markers intact, no quoted")
print("           codec literal survives at any DeviceCanDecodeVideo call site, the")
print("           phantom-conditional comment family stays extinct in the shipped")
print("           code view, and ledger row 72 keeps its cure markers")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 73: the portable twin's PASS narration and the ledger sentence state exactly the header pins the positive run executes (R-ROKU-29) ==="
# NUMBERING (CHECK62/66/69/70/71/72 collision-probe precedent): at composition
# time the highest header in this script is Check 72, and neither 'Check 73'
# nor 'CHECK73' appears anywhere in scripts/, tests/, docs/, README.md or
# CHANGELOG.md of the anchor tree (git grep rc=1 at 1c3ce2d, measured this
# lane) — 73 is next-FREE.
#
# WHY THE LEG EXISTS (R-ROKU-29, ask RIDERS_QUEUE.md R-ROKU-29; disclosed by
# fixlog/M-ROKU-04__fix-r2.md as "pre-existing prose staleness predating
# checks 35-37 ... candidate for a future checks-doc pass"). The twin's final
# PASS echo narrated the CI-layout positive run with an era range of header
# pins while the run's own assert inventory had long grown past it — every
# leg added since silently escaped the summary a human reads to learn what
# the portability proof covers. Re-typing the range is exactly the class
# that re-rotts on the next leg added, so the cure is self-derivation: this
# leg recomputes the pinned-header set FROM the twin's own asserts, compacts
# it to canonical range form, and demands equality from BOTH prose surfaces —
# the twin's PASS echo and the ledger's Regression-test sentence. Prose can
# no longer lag the pins, in either direction, on either surface.
#
# WHAT IT PINS (fail-loud on unreadable inputs and on ambiguous anchors;
# the claim needle is assembled from adjacent literals — CHECK69 SELF-BURN
# law — so this script's bytes never carry the phrase the twin is parsed on):
#   R1  twin PASS-echo equality — the phrase the single PASS echo carries
#       between its last 'Check ' lead-in and the header-pin claim needle
#       must equal the derived canonical range (under-report AND over-report
#       convict: the claim may neither lag the pins nor claim pins the run
#       never executes). Derivation: every `for VAR in $(seq A B)` loop whose
#       body pins "=== Check $VAR:" on $POSITIVE_OUT contributes A-B; every
#       individual literal header pin over $POSITIVE_OUT contributes itself.
#       Zero pins, or a second PASS echo carrying the claim, convicts loudly.
#   R2  ledger equality — docs/static-checks.md's Regression-test sentence
#       must carry the SAME derived range (the checks-doc pass rides the
#       leg: the two prose surfaces cannot rotate independently of the
#       harness they describe).
#   R3  docs truth — docs/static-checks.md row 73 exists and carries its
#       cure markers (R-ROKU-29 + Check 73) — the ledger cannot under-claim
#       the shipped law (CHECK44 R5 / CHECK71 R4 / CHECK72 R4 precedent).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        problems.append(f"  {path} - CHECK73: unreadable: {err} — the pin cannot run vacuously")
        return None


def compact(pins):
    """Sorted int set -> canonical '11-26 + 35 + 37-41 + 43-61' range form."""
    runs = []
    start = prev = None
    for n in sorted(pins):
        if start is None:
            start = prev = n
            continue
        if n == prev + 1:
            prev = n
            continue
        runs.append((start, prev))
        start = prev = n
    if start is not None:
        runs.append((start, prev))
    return " + ".join(("%d-%d" % (a, b)) if b > a else "%d" % a for a, b in runs)


# The claim needle the twin's PASS echo rides, assembled from adjacent
# literals (SELF-BURN law): contiguous, it would collide with the very
# surface this leg parses.
CLAIM = "headers " + "present"

INDIV = re.compile(r'assert_contains "=== Check (\d+):" "\$POSITIVE_OUT"')
LOOP = re.compile(r'for\s+(\w+)\s+in\s+\$\(\s*seq\s+(\d+)\s+(\d+)\s*\)')

derived = None
TWIN = read("tests/scripts/verify-runtime-portable.sh")
if TWIN is not None:
    lines = TWIN.splitlines()
    pins = set()
    for i, line in enumerate(lines):
        m = INDIV.search(line)
        if m:
            pins.add(int(m.group(1)))
            continue
        ml = LOOP.search(line)
        if ml:
            var, a, b = ml.group(1), int(ml.group(2)), int(ml.group(3))
            body = "\n".join(lines[i + 1:])
            cut = body.find("\ndone")
            if cut != -1:
                body = body[:cut]
            if ('assert_contains "=== Check $%s:" "$POSITIVE_OUT"' % var) in body:
                pins.update(range(a, b + 1))
    if not pins:
        problems.append(
            "  tests/scripts/verify-runtime-portable.sh - CHECK73: zero CI-layout header "
            "pins derived — the twin's positive block changed shape; update this leg's "
            "derivation in lockstep, never let it go vacuous (R-ROKU-29)")
    else:
        derived = compact(pins)
        echoes = [l for l in lines
                  if l.startswith('echo "PASS: verify-runtime.sh is portable')
                  and CLAIM in l]
        if len(echoes) != 1:
            problems.append(
                f"  tests/scripts/verify-runtime-portable.sh - CHECK73 R1: {len(echoes)}/1 "
                "PASS-echo lines carry the header-pin claim — the narration anchor must be "
                "unique (R-ROKU-29)")
        else:
            pre = echoes[0][:echoes[0].find(CLAIM)]
            j = pre.rfind("Check ")
            if j == -1:
                problems.append(
                    "  tests/scripts/verify-runtime-portable.sh - CHECK73 R1: the PASS echo "
                    "holds the header-pin claim without a 'Check ' lead-in — rotate the "
                    "narration shape in lockstep with this leg (R-ROKU-29)")
            else:
                narrated = pre[j + len("Check "):].strip().rstrip(",")
                if narrated != derived:
                    problems.append(
                        f"  tests/scripts/verify-runtime-portable.sh - CHECK73 R1: the PASS "
                        f"narration claims \"{narrated}\" but the twin's own CI-layout header "
                        f"pins derive \"{derived}\" — narration must equal the executed pins; "
                        "rotate the phrase in the same commit that adds or removes a header "
                        "assert, never after (R-ROKU-29)")

DOC = read("docs/static-checks.md")
if DOC is not None:
    sent = re.findall(r"asserts checks (.+?) all execute", DOC)
    if len(sent) != 1:
        problems.append(
            f"  docs/static-checks.md - CHECK73 R2: {len(sent)}/1 Regression-test header-pin "
            "sentences found — the ledger anchor must be unique for this pin (R-ROKU-29)")
    elif derived is not None and sent[0] != derived:
        problems.append(
            f"  docs/static-checks.md - CHECK73 R2: the Regression-test sentence claims "
            f"\"asserts checks {sent[0]} all execute\" while the twin's executed header pins "
            f"derive \"{derived}\" — the checks-doc may not lag (or outrun) the harness it "
            "describes; rotate both prose surfaces in the same commit (R-ROKU-29)")
    rows = [l for l in DOC.splitlines() if re.match(r"^\|\s*73\s*\|", l)]
    if not rows:
        problems.append(
            "  docs/static-checks.md - CHECK73 R3: row 73 vanished — the checks ledger must "
            "enumerate this shipped leg (CHECK66-era landing law) (R-ROKU-29)")
    for l in rows:
        for marker in ("R-ROKU-29", "Check 73"):
            if marker not in l:
                problems.append(
                    "  docs/static-checks.md - CHECK73 R3: row 73 lost its cure marker "
                    f"\"{marker}\" — the ledger may not under-claim the shipped law")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK73: %d portable-narration-truth pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK73: the twin's PASS narration and the ledger sentence both equal")
print("           the header-pin set derived from the twin's own assert")
print(f"           inventory ({derived}); ledger row 73 keeps its cure markers")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ============================================================================
# CHECK74 — form-input attribute truth + node-type existence (review
#           roku__gameux CR-2 / M-ROKU-14 / M-ROKU-15, R-ROKU-30 class).
# NUMBERING (CHECK62/66/69/70/71/72/73 collision-probe precedent): at
#           composition time the highest header in this script is Check 73,
#           and neither 'Check 74' nor 'CHECK74' appears anywhere in
#           scripts/, tests/, docs/, README.md or CHANGELOG.md of the anchor
#           tree (git grep rc=1 at 4316872, measured this lane) — 74 is
#           next-FREE.
#
# WHY THE LEG EXISTS. Three node types used by shipped XML (TextFormDialog,
# ToggleButton, HStack) are neither Roku built-ins nor project components —
# they instantiate as nothing, and every `.text`/`.checked` contract riding
# them silently reads invalid: the ParentalControls form could not be typed
# into on device. Separately, `hint=` and `secure=` are not TextEditBox
# fields either (the real fields are hintText/secureMode), so the login
# placeholders and the password masking were markup fiction — and invisible
# to Check 25, which scans title=/text= only. This leg closes the whole
# class from three directions: dead attributes are extinct (R1), hintText is
# pulled INTO the Check 25 translate net with the same teeth (R2), the scan
# itself is pinned non-vacuous (R3), and no XML tag may exist outside
# curated built-ins ∪ project-defined names (R4 — phantom instantiation
# itself goes extinct, not just these three).
echo "=== Check 74: form-input attribute truth and node-type existence (CR-2/M-ROKU-14/15) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, html, json, os, re, sys
import xml.parsers.expat as expat

repo = os.environ["REPO"]
os.chdir(repo)
problems = []

XMLS = sorted(glob.glob("components/**/*.xml", recursive=True))


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# ---- R1: dead TextEditBox attribute names are extinct ---------------------
# `hint="` / `secure="` are NOT TextEditBox fields (the real fields are
# hintText / secureMode). A word-boundary regex cannot fire on the real
# names, because there `hint`/`secure` is followed by letters, not `="`.
DEAD = re.compile(r'(?<![A-Za-z])(hint|secure)="')
for path in XMLS:
    src = read(path)
    if src is None:
        problems.append(f"  {path} - CHECK74: unreadable")
        continue
    for i, line in enumerate(src.splitlines(), 1):
        if DEAD.search(line):
            problems.append(
                f"  {path}:{i} - CHECK74 R1: dead markup attribute on the "
                "line — TextEditBox speaks hintText= / secureMode=; the bare "
                "hint=/secure= names silently never render [CR-2/M-ROKU-14/15]")

# ---- R2: every hintText= literal rides the Check 25 translate net ---------
en = json.loads(read("locale/en_US/strings.json"))
en_values = {}
for section, data in en.items():
    if section == "_metadata" or not isinstance(data, dict):
        continue
    for bare, leaf in data.items():
        if isinstance(leaf, str):
            en_values.setdefault(leaf, set()).add(f"{section}_{bare}")

# Per-file exemptions for hintText literals that are never localized
# (example URLs are brand-shaped content, not prose). Stale exemptions are
# themselves violations, mirroring Check 25's no-rot law.
HINT_EXEMPT = {
    "components/ConnectScene.xml": {
        "https://my.phlix.server": "example URL placeholder — identical in "
                                   "every locale, not translatable prose"},
}

SKIP_TAGS = {"interface", "field", "event", "component", "script", "function",
             "children", "annotation"}

hint_count = 0
seen_hints = {}
BUILTIN_TAGS = {
    # Curated Roku built-ins (SceneGraph component reference) covering every
    # tag this repo uses plus its immediate neighbours; growth requires an
    # act of review, which is exactly the point [CR-2].
    "ArrayGrid", "Audio", "Button", "ContentNode", "Dialog", "Group",
    "Keyboard", "Label", "LabelList", "LayoutGroup", "List", "MarkupGrid",
    "MarkupList", "MaskGroup", "Panel", "Poster", "PosterGrid", "Rectangle",
    "Row", "RowList", "Scene", "ScrollStrategy", "SimpleLabel",
    "SimpleKeyboard", "Spinner", "StatefulRow", "StyledKeyboard", "Task",
    "TextEditBox", "Timer", "Video", "VideoGroup",
}

project_tags = set()
for path in XMLS:
    src = read(path) or ""
    for m in re.finditer(r'<component\s+name="([^"]+)"', src):
        project_tags.add(m.group(1))

for path in XMLS:
    src = read(path)
    if src is None:
        continue
    tags, hints = [], []
    parser = expat.ParserCreate()

    def start(tag, att, _tags=tags, _hints=hints):
        if tag in SKIP_TAGS:
            return
        _tags.append(tag)
        if tag == "Button" and "title" in att:
            problems.append(
                f"  {path}:{parser.CurrentLineNumber} - CHECK74 R5: "
                "<Button> carries title= — the Roku Button label field is "
                "text=; title= is not a Button field and renders an "
                "unlabeled button [ROK-1]")
        h = att.get("hintText")
        if h is not None and h.strip():
            _hints.append((parser.CurrentLineNumber, tag, att.get("id"),
                           html.unescape(h)))

    parser.StartElementHandler = start
    try:
        parser.Parse(src, True)
    except expat.ExpatError as err:
        problems.append(f"  {path} - CHECK74: unparseable: {err}")
        continue

    # R4: node-type existence — every element tag must be a curated built-in
    # or a project-defined component. Phantom tags (TextFormDialog et al.)
    # instantiate as nothing on device; CI could not see the class before.
    for tag in set(tags):
        if tag not in BUILTIN_TAGS and tag not in project_tags:
            problems.append(
                f"  {path} - CHECK74 R4: <{tag}> is neither a curated Roku "
                "built-in nor a project component — it renders NOTHING on "
                "device (the CR-2 phantom class)")

    # R2/R3: hintText net + non-vacuity census
    hint_count += len(hints)
    for lineno, tag, nid, value in hints:
        if value in HINT_EXEMPT.get(path, set()) or \
           HINT_EXEMPT.get(path, {}).get(value) is not None:
            continue
        if not nid:
            problems.append(
                f"  {path}:{lineno} - CHECK74 R2: hintText on an id-less node "
                "— the translate net addresses chrome by id (Check 25 idiom)")
            continue
        keys = en_values.get(value)
        if not keys:
            problems.append(
                f"  {path}:{lineno} - CHECK74 R2: hintText literal {value!r} "
                "is not a catalog value — XML chrome literals ride the "
                "locale catalog (Check 25 law extended to hints)")
            continue
        base = os.path.basename(path)[:-4]
        paired = f"components/{base}.brs"
        if not os.path.exists(paired):
            paired = f"source/{base}.brs"
        brs = read(paired)
        if brs is None:
            problems.append(f"  {paired} - CHECK74 R2: unreadable pair for {path}")
            continue
        if re.search(r'(?i)findNode\("%s"\)' % re.escape(nid), brs) is None:
            problems.append(
                f"  {path}:{lineno} - CHECK74 R2: id '{nid}' is never "
                f"addressed in {paired} — no override path exists")
            continue
        if not any(f'Translate("{k}")' in brs for k in keys):
            problems.append(
                f"  {path}:{lineno} - CHECK74 R2: no Translate() call for any "
                f"catalog key carrying {value!r} in {paired} — the hint "
                "escapes the translate net")
    seen_hints[path] = {v for (_, _, _, v) in hints}

for path, exempt in HINT_EXEMPT.items():
    for value, reason in exempt.items():
        if value not in seen_hints.get(path, set()):
            problems.append(
                f"  {path} - CHECK74 R2: exemption for {value!r} ({reason}) "
                "is stale — the literal no longer rides hintText= on this "
                "file; carve-outs must rot with their markup")

# R5 (brs half): no `.title =` write on a Button ref (label field is text).
BTN_TITLE_WRITE = re.compile(
    r'(?<![A-Za-z0-9_])(?:n|[A-Za-z0-9_]*Button|publicToggle)\.title\s*=(?!=)')
for bpath in sorted(glob.glob("components/**/*.brs", recursive=True)):
    bsrc = read(bpath) or ""
    for i, line in enumerate(bsrc.splitlines(), 1):
        if BTN_TITLE_WRITE.search(line.split("'")[0]):
            problems.append(
                f"  {bpath}:{i} - CHECK74 R5: .title write on a Button ref — "
                "the Button label field is text [ROK-1]")

if hint_count < 6:
    problems.append(
        f"  CHECK74 R3: the hintText scan observed {hint_count} occurrences "
        "(floor 6, set by measurement at ship time) — the scan or the markup "
        "changed shape; rotate the floor in lockstep with disclosure, never "
        "let this leg go vacuous")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK74: %d form-input/node-type pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK74: hint=/secure= extinct, hintText rides the translate net")
print(f"           ({hint_count} occurrences scanned, floor 6), and every")
print("           XML tag is a curated built-in or a project component —")
print("           the CR-2 phantom-node class cannot regrow silently")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 75: the shipped doc surface stays free of the era install/toolchain fictions, and the real recipe keeps its markers (CR-3 / CR-4 / MN-30 era) ==="
# WHY: 53b478b cured the fabricated install/toolchain prose out of the shipped
# docs — an install endpoint hung off the ECP port, two npm-global installs of
# CLIs that 404 on the public registry (live-probed), a Makefile dev-target
# that never existed, and a raw form field that re-created the dual-source
# shape the C1 law forbids. Every cure was one-time prose surgery: each banned
# string can be pasted back by a helpful future lane, and the CR-3/CR-4 era
# proved fiction survives review rounds. This leg makes the class extinct by
# construction over the surfaces that ship to humans, and R2 ensures the gate
# can never be satisfied by deleting the working recipe it protects.
# NUMBERING: 75 collision-probed at 53b478b (grep 'Check 75' scripts tests
# Makefile docs -> rc=1; highest prior header = Check 74).
# SELF-BURN (CHECK69/71 law): the banned strings are assembled from adjacent
# fragments so neither this script nor the twin carries a contiguous needle;
# the verbatim forms live only in docs/static-checks.md row 75, which R1
# deliberately excludes (the ledger is the quote-carrier). CHANGELOG.md is
# outside the scan too: verbatim history must keep naming what it retracted.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

repo = os.environ["REPO"]
os.chdir(repo)
problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# ---- R1: the era fictions stay extinct on the shipped doc surface ----------
# fragment + fragment = the banned contiguous string (SELF-BURN); the label
# names the fiction class so even the diagnostics never reprint it whole.
NEEDLES = [
    ("8060/" + "install", "install-endpoint fiction (install is not an "
                          "ECP route) [CR-3]"),
    ("npm install -g " + "rokudev", "npm-global CLI fiction (the registry "
                                    "404s the name) [CR-4]"),
    ("npm install -g " + "rokupkg", "npm-global CLI fiction (the registry "
                                    "404s the name) [CR-4]"),
    ("rokupkg --" + "install", "install-flag fiction (no such CLI) [CR-4]"),
    ("dev-" + "install", "Makefile dev-target fiction (the target never "
                         "existed) [CR-4 era]"),
    ("manifest=@" + "manifest", "raw form-field fiction (re-creates the "
                                "dual-source shape the C1 law forbids)"),
]

# The surfaces that ship to a human or a device tool: the three root docs,
# every doc except this gate's own ledger (R4 reads that file), every
# workflow YAML, and every shipped .brs.
ANCHORS = ("Makefile", "README.md", "CLAUDE.md")
FILES = list(ANCHORS) + ["DEVELOPER.md"]  # w15L9 R-D RT-096: the guide joins the guarded surface
FILES += sorted(f for f in glob.glob("docs/*.md")
                if f != "docs/static-checks.md")
FILES += sorted(glob.glob(".github/workflows/*.yml"))
FILES += sorted(glob.glob("source/**/*.brs", recursive=True))
FILES += sorted(glob.glob("components/**/*.brs", recursive=True))

for path in FILES:
    src = read(path)
    if src is None:
        problems.append(f"  {path} - CHECK75 R1: scan member unreadable")
        continue
    for i, line in enumerate(src.splitlines(), 1):
        for needle, label in NEEDLES:
            if needle in line:
                problems.append(
                    f"  {path}:{i} - CHECK75 R1: the {label} is back on "
                    "the shipped doc surface — a cured fiction cannot be "
                    "re-pasted")

# ---- R2: the real recipe keeps its identifying markers ----------------------
# The flip side of R1: all three markers ride BOTH the Makefile install leg
# and the README manual recipe (review CR-3's shipped cure).
MARKERS = ("/plugin_install", "mysubmit=Install", "digest")
for path in ("Makefile", "README.md"):
    src = read(path)
    if src is None:
        continue  # R1 already convicted the unreadable anchor
    for marker in MARKERS:
        if marker not in src:
            problems.append(
                f"  {path} - CHECK75 R2: the real install recipe's marker "
                f"{marker!r} vanished — the extinction gate cannot be fed "
                "by deleting the recipe it protects [CR-3]")

# ---- R3: the scan cannot go vacuous ------------------------------------------
# Anchors are mandatory members; the file-count floor was measured at ship
# time (76 in the repo AND the twin layout; the RT-096 DEVELOPER.md pass
# grew it to 77 there too — the twin stages the complete scan set for
# exactly this reason).
for path in ANCHORS:
    if not os.path.isfile(path):
        problems.append(
            f"  CHECK75 R3: required scan anchor {path} vanished — the doc "
            "surface changed shape; rotate this leg in lockstep, never let "
            "it shrink silently")
if len(FILES) < 70:
    problems.append(
        f"  CHECK75 R3: the scan observed {len(FILES)} files (floor 70, set "
        "by measurement at ship time: 76 files, 77 since the RT-096 "
        "DEVELOPER.md pass, in repo and twin layouts alike) — the "
        "glob or the tree changed shape; rotate with disclosure, never let "
        "this leg go vacuous")

# ---- R6: the Makefile device legs stay fail-loud (ROK-6) ---------------------
# install/launch/stop must capture the response (-o + -w status) and grep the
# body for the device's failure phrases; the README recipe must carry the same.
MK = read("Makefile")
if MK is not None:
    for tgt in ("install", "launch", "stop"):
        mt = re.search(r"^%s:.*?(?=^\S)" % tgt, MK, re.S | re.M)
        body = mt.group(0) if mt else ""
        for marker in ("%{http_code}", "Install Failure|Error Message", "exit $$rc"):
            if marker not in body:
                problems.append(
                    f"  Makefile - CHECK75 R6: target {tgt!r} lost its "
                    f"response-guard marker {marker!r} - a failed device "
                    "response would exit 0 again [ROK-6]")
RD = read("README.md")
if RD is not None:
    for marker in ("%{http_code}", "Install Failure|Error Message"):
        if marker not in RD:
            problems.append(
                f"  README.md - CHECK75 R6: the sideload recipe lost its "
                f"response-guard marker {marker!r} [ROK-6]")

# ---- R4: the ledger row keeps its cure markers ------------------------------
LEDGER = read("docs/static-checks.md")
if LEDGER is None:
    problems.append("  docs/static-checks.md - CHECK75 R4: unreadable")
else:
    rows = [l for l in LEDGER.splitlines() if re.match(r"^\|\s*75\s*\|", l)]
    if not rows:
        problems.append(
            "  docs/static-checks.md - CHECK75 R4: row 75 vanished — the "
            "checks ledger must enumerate this shipped leg (CHECK71/72/73 "
            "R4 precedent)")
    else:
        for l in rows:
            for marker in ("CR-3", "CR-4"):
                if marker not in l:
                    problems.append(
                        f"  docs/static-checks.md - CHECK75 R4: row 75 lost "
                        f"its cure marker {marker!r} — ledger and leg "
                        "rotate in the same commit")

# ---- R5: DEVELOPER.md cannot re-grow live-tense fictional managers ----------
# RT-096 (w15L9 R-D): the guide's Key Components table shipped SessionManager,
# LibraryManager and TaskManager for a client that never had them (the real
# surface is AuthManager/ToastManager/SyncPlayManager + Storage, with
# AppContext owning the connection). One-time prose surgery cannot stop a
# paste-back — CHECK75 R1 DNA — so any DEVELOPER.md line naming a fictional
# manager must carry its dead marker (the R7.5 cull sentence). Blanket naming
# is impossible repo-wide on purpose: CLAUDE.md and PhlixApp.brs mention the
# trio HONESTLY in dead tense; this arm is scoped to the guide alone.
DEV = read("DEVELOPER.md")
if DEV is None:
    problems.append("  DEVELOPER.md - CHECK75 R5: unreadable scan member")
else:
    for i, line in enumerate(DEV.splitlines(), 1):
        if re.search(r"SessionManager|LibraryManager|TaskManager", line) and not re.search(
                r"deleted|removed|gone|retired|dead|no longer", line, re.I):
            problems.append(
                f"  DEVELOPER.md:{i} - CHECK75 R5: a fictional manager is named "
                "live-tense again — the R7.5 cull row keeps its dead marker")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK75: %d doc-fiction gate pin(s) broken" % len(problems))
    sys.exit(1)

print(f"  CHECK75: the six era fictions are extinct across the {len(FILES)}-file")
print("           shipped doc surface, the real port-80 recipe keeps its")
print("           three markers in Makefile and README, and ledger row 75")
print("           carries its CR-3/CR-4 cure refs — the fiction class cannot")
print("           re-enter the docs silently")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 76: the detail screen threads its resume position to the player — the MJ-1 wiring cannot rot back to restart-at-zero ==="
# WHY: PlayerScene.Show has consumed an optional args.resumeSeconds since the
# continue-watching rail shipped (F3), but DetailScene.PlayItem only ever
# passed {item, playbackInfo} — every Search/Favorites/Season -> detail ->
# Play press restarted a half-watched item at 0:00 while the docs table
# promised "resume from bookmark if available". MJ-1 cured it by riding the
# already-wired getContinueWatching op (ApiTask.brs) at item-load time and
# handing the matching row's position_ticks to Show. Each of the three
# surfaces of that thread (request fire, response arm, Show argument) is a
# one-line delete away from silently becoming the old fiction again, and the
# PlayerScene consumer side is what makes the first two more than decoration.
# NUMBERING: 76 collision-probed at 4ff1ea3 (grep 'Check 76' scripts tests
# Makefile docs -> rc=1; highest prior header = Check 75).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK76 R0: cannot read {path}: {exc}")
        return None

ds_text = read("components/DetailScene.brs")
ps_text = read("components/PlayerScene.brs")
ledger = read("docs/static-checks.md")

if ds_text is not None:
    # R1 fire side: the lookup must be requested on the item-load path.
    if not re.search(r'\{\s*op:\s*"getContinueWatching"\s*\}', ds_text):
        problems.append('  components/DetailScene.brs - CHECK76 R1: the { op: "getContinueWatching" } resume lookup is no longer fired on the detail load path — the resume data has no source')
    # R1 read side: the response must be armed in the op-multiplexed handler.
    if not re.search(r'resp\.op\s*=\s*"getContinueWatching"', ds_text):
        problems.append('  components/DetailScene.brs - CHECK76 R1: the resp.op = "getContinueWatching" arm is gone — the lookup response would fall through the multiplexer unhandled')
    # R2 hand-off: PlayItem's Show call must carry the resume field.
    show_block = re.search(r'playerScene\.Show\([\s\S]*?\)\s*$', ds_text, re.MULTILINE)
    if show_block is None:
        problems.append('  components/DetailScene.brs - CHECK76 R2: PlayItem no longer calls playerScene.Show(...) — the detail play path shape changed under this leg; re-derive it')
    elif "resumeSeconds" not in show_block.group(0):
        problems.append('  components/DetailScene.brs - CHECK76 R2: the Show argument block lost resumeSeconds — detail-page playback silently returns to restart-at-zero (the MJ-1 defect)')

if ps_text is not None and not re.search(r'args\.resumeSeconds', ps_text):
    # R3 consume side: the sink must still read what the wire passes.
    problems.append('  components/PlayerScene.brs - CHECK76 R3: args.resumeSeconds is no longer consumed by Show — every producer of the resume offset (HomeScene rails, DetailScene) is now writing into a field the player ignores')

if ledger is not None:
    row = re.search(r'^\|\s*76\s*\|.*$', ledger, re.MULTILINE)
    if row is None or "MJ-1" not in row.group(0):
        problems.append('  docs/static-checks.md - CHECK76 R4: ledger row 76 is missing or no longer names its MJ-1 cure ref (CHECK71/72/73/75 R4 precedent)')

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK76: %d detail-resume wiring pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK76: the detail resume lookup fires, arms, hands off and is")
print("           consumed on all four surfaces (fire / read / Show arg /")
print("           PlayerScene sink), and ledger row 76 carries its cure ref")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 77: the hub-supplied serverId is path-law-gated at pick, at read and at dial (MJ-18; the M-ROKU-13 shape law extended to the credential-bearing relay composition) ==="
# WHY: the hub's /me/servers response is untrusted input the same way any
# wire field is: serverId rides into the mint URL (HubCommandTask), the raw
# WS upgrade request line (BuildHandshakeRequest writes it VERBATIM - there
# is no CR/LF filter there, unlike ResolveRedirectTarget's deliberate one)
# and the media-proxy prefix (AppContext). ParseJSON restores \r and \n
# escapes as real CRLF, so one ungated pass lets a hostile hub smuggle
# attacker-chosen headers or paths carrying the minted bearer token. The
# cure mirrors the mediaId choke exactly: IsSafeContentId at the pick, a
# degrade-at-read on GetActiveServerId, and a task-side refusal before any
# socket exists. This leg pins all three gates plus the ledger row: a
# one-line delete at any gate silently re-opens the whole class.
# NUMBERING: 77 collision-probed at the MJ-1 tree (grep 'Check 77' scripts
# tests Makefile docs -> empty; highest prior header = Check 76).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK77 R0: cannot read {path}: {exc}")
        return None

# R1 pick gate: the stringified hub id must pass the shape law BEFORE it
# persists — the storage write is the choke every downstream reader shares.
sp = read("components/ServerPickerScene.brs")
if sp is not None:
    m = re.search(r'sub OnRowSelected', sp)
    block = ""
    if m:
        stop = sp.find('GetStorage().set("active_server_id"', m.start())
        block = sp[m.start():stop if stop > 0 else m.start() + 4000]
    if not re.search(r'IsSafeContentId\(\s*id\s*\)', block):
        problems.append("  components/ServerPickerScene.brs - CHECK77 R1: the pick path no longer gates the stringified serverId with IsSafeContentId before persisting it — hostile hub ids re-enter storage (the MJ-18 entry point)")

# R2 read gate: GetActiveServerId must degrade an unsafe stored id to "".
ac = read("source/lib/AppContext.brs")
if ac is not None:
    m = re.search(r'function GetActiveServerId\(\)[\s\S]*?end function', ac)
    if m is None:
        problems.append("  source/lib/AppContext.brs - CHECK77 R2: GetActiveServerId vanished — re-derive this leg against the new resolver shape")
    elif not re.search(r'IsSafeContentId', m.group(0)):
        problems.append("  source/lib/AppContext.brs - CHECK77 R2: the read-path gate is gone — ids persisted before the pick gate shipped (or by any future writer) would compose mint/proxy/relay paths unchecked")

# R3 dial gate: HubCommandTask must refuse an unsafe cfg.serverId before any
# mint/socket, mirroring the M-ROKU-23 origin choke placement.
hc = read("components/HubCommandTask.brs")
if hc is not None:
    m = re.search(r'sub RunConsumer', hc)
    if m is None:
        problems.append("  components/HubCommandTask.brs - CHECK77 R3: the RunConsumer task body vanished — re-derive this leg")
    else:
        entry = hc[m.start():m.start() + 4000]
        g = re.search(r'IsSafeContentId\(\s*serverId\s*\)', entry)
        if g is None:
            problems.append("  components/HubCommandTask.brs - CHECK77 R3: the task-side path-law choke is gone — the mint URL and the relay request line are the last credential-bearing composition and they would run ungated (the MJ-18 defect)")
        elif "closed" not in entry[g.end():g.end() + 200]:
            problems.append("  components/HubCommandTask.brs - CHECK77 R3: the dial gate no longer refuses with SetState(\"closed\") — a rejected relay must be an honest terminal state, not a swallowed return")

# R4 ledger truth (CHECK71/72/73/75/76 R4 precedent).
led = read("docs/static-checks.md")
if led is not None:
    row = re.search(r'^\|\s*77\s*\|.*$', led, re.MULTILINE)
    if row is None or "MJ-18" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK77 R4: ledger row 77 is missing or no longer names its MJ-18 cure ref")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK77: %d serverId-custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK77: the serverId shape law holds at all three custody points")
print("           (pick persist, read degrade, dial refuse) and ledger row 77")
print("           carries its cure ref")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 78: the Settings menu builder keeps riding its catalog — the MJ-20 rewire cannot paste back to raw English or silently shrink (era of the dead-mirrored keys) ==="
# WHY: from the R7.12 baseline until the MJ-20 cure, docs/i18n.md advertised
# SettingsScene catalog coverage while the builder shipped 17 raw title
# literals and 10 raw description literals — and the 27 matching
# settings.section_*/item_*/desc_* keys sat mirrored (and consumer-less) in
# all seven locale files. The cure is a pure rewire: every entry rides
# Translate() on the flattened underscore form the device loader resolves.
# A paste-back of literals, a re-point to bare unprefixed keys, or a builder
# that quietly loses entries would re-fictionalise that doc surface; this
# leg pins the rewired shape itself. The raw-literal ban is region-scoped
# (the array literal only): every other `{ title: ... }` shape in the repo
# (runtime-built content rows) is legitimate.
# NUMBERING: 78 collision-probed at 4c7ae09 (grep 'Check 78'/'CHECK78' over
# scripts tests Makefile docs -> rc=1; the only mentions are this era's own
# forward refs in the MJ-20 commit's docs). Highest prior header = Check 77.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK78 R0: cannot read {path}: {exc}")
        return None

# R1 raw-literal ban inside the builder region + R2 Translate-census floor.
ss = read("components/SettingsScene.brs")
if ss is not None:
    m = re.search(r'm\.settingsItems = \[(.*?)\n    \]', ss, re.S)
    if m is None:
        problems.append("  components/SettingsScene.brs - CHECK78 R0: the m.settingsItems builder array literal vanished — re-derive this leg against the new shape (the raw-ban and census floor both read the region it delimits)")
    else:
        region = m.group(1)
        for hit in re.finditer(r'(title|description): "', region):
            lineno = ss[:m.start(1) + hit.start()].count("\n") + 1
            problems.append(
                f'  components/SettingsScene.brs:{lineno} - CHECK78 R1: a raw {hit.group(1)}: literal is back in the '
                "m.settingsItems builder — the 27 settings_section_*/item_*/desc_* keys are mirrored in all seven "
                "locales precisely so this menu localises (MJ-20 regression: the pasted-back literal makes the "
                "docs/i18n.md coverage claim fiction again)"
            )
        census = region.count("Translate(")
        if census < 27:
            problems.append(f"  components/SettingsScene.brs - CHECK78 R2: the builder makes only {census} Translate calls (floor 27 — 17 titles + 10 descriptions at ship-time measurement) — a catalog-backed entry was deleted or re-rawed; the menu can not go partially English again without reddening this floor")

# R3 docs cure marker: the i18n.md bullet that turns the coverage claim true.
doc = read("docs/i18n.md")
if doc is not None:
    if not re.search(r"\(MJ-20[^\n]*SettingsScene", doc):
        problems.append("  docs/i18n.md - CHECK78 R3: the MJ-20 SettingsScene catalog-cure bullet is gone — the sentence that makes this repo's i18n truth for the Settings menu live is this leg's premise (and Check 78's own doc ref lives in it)")

# R4 ledger truth (CHECK71/72/73/75/76/77 R4 precedent).
led = read("docs/static-checks.md")
if led is not None:
    row = re.search(r'^\|\s*78\s*\|.*$', led, re.MULTILINE)
    if row is None or "MJ-20" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK78 R4: ledger row 78 is missing or no longer names its MJ-20 cure ref")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK78: %d settings-catalog pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK78: the settings builder carries zero raw title:/description: literals,")
print("           its Translate census stands at the 27-call floor, the docs/i18n.md")
print("           cure marker and ledger row 78 hold the MJ-20 truth — the dead-mirrored")
print("           keys cannot re-orphan silently")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 79: the SyncPlay join cannot be swallowed before the handshake, and the leave cannot kill its own flush (MJ-6/MJ-7 era of the discarded command window and the ghost member) ==="
# WHY: two live-syncplay defects cured together; each half is pinned by its own
# rule family. MJ-6: the scene wrote m.syncTask.command the moment control="run"
# landed, so the first write sat in the FIELD before the task thread ever called
# ObserveField("command", m.port) — the attach synthesises no event, and the
# WaitForConnect poll plus the handshake-header read silently DISCARDED every
# roSGNodeEvent of the window. A tap on an existing watch party could vanish:
# socket open, yourId never set, zero syncplay commands, the group silently
# memberless (and the empty-yourId branch then suppressed time_pings forever).
# Cure = a command funnel: catch-up read at attach (the field value IS the lost
# write), drain arms in both pre-loop windows, replay at the main-loop gate,
# reference-identity dedup (m.lastCommand) so no write is dropped or dispatched
# twice. MJ-7: the leave path set control="stop" synchronously — Task's exit
# never drains its queue, so the queued group_leave + close frames died in the
# socket while peers carried a ghost member until heartbeat expiry. Cure =
# deferred stop: the leave/close write stands, the task emits "closed" after
# flushing, the closed arm runs StopSyncTaskNow, with a bounded 2s Timer
# fallback guarded on the syncUserStopped register. The census is shape-agnostic
# on purpose: a regrown immediate stop reddens it exactly once whatever wording
# the leg later faces.
# NUMBERING: 79 collision-probed at 8021fa6 (grep 'Check 79'/'CHECK79' over
# scripts tests Makefile docs -> rc=1; zero mentions). Highest prior header = 78.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK79 R0: cannot read {path}: {exc}")
        return None

# R1 - the MJ-6 command-funnel law (components/SyncPlayTask.brs). The four
# mechanisms (catch-up read at attach, drain arms in both pre-loop windows,
# replay at the main-loop gate, identity dedup) are ONE cure; the plant class
# strips single lines to prove each family carries teeth.
tsk = read("components/SyncPlayTask.brs")
if tsk is not None:
    missing = []
    attach = tsk.find('m.top.ObserveField("command", m.port)')
    if attach < 0:
        missing.append('observer attach m.top.ObserveField("command", m.port)')
    else:
        gate = tsk.find('running = true', attach)
        if gate < 0:
            missing.append('main-loop gate "running = true"')
        else:
            for needle in ('m.pendingCommands = []',
                           'catchUp = m.top.command',
                           'if catchUp <> invalid then m.pendingCommands.Push(catchUp)'):
                if needle not in tsk[attach:gate]:
                    missing.append(needle + " [attach window]")
    if len(re.findall(r'type\(ev\) = "roSGNodeEvent" and ev\.GetField\(\) = "command"', tsk)) != 2:
        missing.append("the two pre-loop drain arms (poll + handshake-header guard)")
    for needle in ('if dc <> invalid then m.pendingCommands.Push(dc)',
                   'if hc <> invalid then m.pendingCommands.Push(hc)',
                   'while m.pendingCommands.Count() > 0 and running',
                   'rc = m.pendingCommands.Shift()',
                   'if rc <> m.lastCommand then',
                   'm.lastCommand = rc',
                   'if not HandleCommand(rc) then running = false',
                   'if cd <> m.lastCommand then',
                   'm.lastCommand = cd'):
        if needle not in tsk:
            missing.append(needle)
    if missing:
        problems.append("  components/SyncPlayTask.brs - CHECK79 R1: " + str(len(missing)) +
            " funnel-law line(s) lost - " + "; ".join(missing) +
            " (the join written before the thread observes the field is silently discarded again: catch-up read, both drain arms, replay and the identity dedup are one mechanism - MJ-6)")

# R2 - the MJ-7 stop-custody law (components/PlayerScene.brs). stop is legal
# ONLY inside StopSyncTaskNow (census == 1); the leave/close paths write their
# frame, arm the bounded fallback and let the task's own "closed" event run the
# stop. Multi-needle laws aggregate to one conviction so a single-line plant
# can never double-report.
sc = read("components/PlayerScene.brs")
if sc is not None:
    stops = len(re.findall(r'm\.syncTask\.control = "stop"', sc))
    if stops != 1:
        problems.append('  components/PlayerScene.brs - CHECK79 R2: ' + str(stops) +
            ' site(s) write m.syncTask.control = "stop" (law: exactly 1 - inside StopSyncTaskNow, the sole custody sink; a second immediate stop kills the queued group_leave/close frame before it reaches the wire and ghosts the member until heartbeat expiry - MJ-7)')
    missing2 = []

    def sub_body(name):
        m = re.search(r'\nsub ' + re.escape(name) + r'\n(.*?)\nend sub', sc, re.S)
        return m.group(1) if m else None

    for sig, needles in (
        ('OnSyncLeavePressed()', [
            'm.syncTask.command = { kind: "leave", group_id: m.syncGroupId }',
            'm.syncUserStopped = true',
            'ArmSyncLeaveStop()']),
        ('StopSyncTaskNow()', [
            'm.syncTask.UnObserveField("event")',
            'm.syncTask.control = "stop"',
            'm.syncTask = invalid']),
        ('ArmSyncLeaveStop()', [
            'CreateObject("roSGNode", "Timer")',
            'ObserveField("fire", "OnSyncStopTimerFired")',
            'm.syncStopTimer.duration = 2',
            'm.syncStopTimer.repeat = false',
            'm.syncStopTimer.control = "start"']),
        ('OnSyncStopTimerFired(event as Object)', [
            'if m.syncUserStopped and m.syncTask <> invalid then StopSyncTaskNow()']),
        ('CloseSyncPanel()', [
            'm.syncTask.command = { kind: "leave", group_id: m.syncGroupId }',
            'ArmSyncLeaveStop()']),
    ):
        body = sub_body(sig)
        if body is None:
            missing2.append('sub ' + sig + ' vanished')
            continue
        for needle in needles:
            if needle not in body:
                missing2.append('sub ' + sig + ': ' + needle)
    if 'if m.syncUserStopped then StopSyncTaskNow()' not in sc:
        missing2.append('the closed-arm terminal stop')
    if missing2:
        problems.append("  components/PlayerScene.brs - CHECK79 R2: " + str(len(missing2)) +
            " stop-custody law(s) lost - " + "; ".join(missing2) +
            " (the leave/close write must reach the wire before the thread dies: closed-event stop, bounded guarded fallback, single sink - MJ-7)")

# R3 docs cure marker: certification 7.4 only became TRUE with the deferred
# stop — the row must keep naming the cure it now describes (CHECK78 R3 idiom).
cert = read("docs/certification.md")
if cert is not None:
    row74 = re.search(r'^\|\s*7\.4\s*\|.*$', cert, re.MULTILINE)
    if row74 is None or "MJ-7" not in row74.group(0) or "StopSyncTaskNow" not in row74.group(0):
        problems.append("  docs/certification.md - CHECK79 R3: the 7.4 lifecycle row no longer names its MJ-7 custody cure (cure ref + sole-sink name) - the PASS claim is only honest while stop custody sits in StopSyncTaskNow behind the leave/close flush")

# R4 ledger truth (CHECK71/72/73/75/76/77/78 R4 precedent).
led = read("docs/static-checks.md")
if led is not None:
    row = re.search(r'^\|\s*79\s*\|.*$', led, re.MULTILINE)
    if row is None or "MJ-6" not in row.group(0) or "MJ-7" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK79 R4: ledger row 79 is missing or no longer names its MJ-6/MJ-7 cure refs")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK79: %d syncplay-funnel/stop-custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK79: the syncplay command funnel reads the field at attach, drains both")
print("           pre-loop windows, replays at the main-loop gate and dedups by identity;")
print("           stop custody sits in the single StopSyncTaskNow sink behind the closed")
print("           event with the bounded guarded fallback - a swallowed first tap and a")
print("           self-killed leave flush are now shape-impossible")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 80: the joiner adopts the group anchor exactly once - the at-zero joiner and the rubber-banding host are the MJ-9 era (SPEC §4 playback_position) ==="
# WHY: group_state carried playback_position + playback_state from day one and
# PlayerScene rendered chrome from them without ever ADOPTING them: a member who
# joined mid-film (or re-opened after a drop) sat at position 0 while the party
# played on, and the first host-driven playback frame yanked it - SPEC §4 names
# the field "what a joiner adopts as its starting point". Cure = an adoption
# block in HandleSyncEvent's group_state arm, one-shot per (re)join through the
# syncAnchorApplied register (init + open-arm reset), follower-only (host self-
# application is the rubber-band class), type-gated reads on both spellings,
# negatives dropped, the cached duration as clamp (positionOrDrop law), a
# definite different-title match suppressing adoption in silence (notice copy is
# owner-gated), and the m.applyingRemote wrap so the local seek never
# re-broadcasts. The anchor is adopted UNSTAMPED on purpose: SPEC §10.2 leaves
# the as-of reference an OPEN decision and the reference law forbids inventing
# a drift adjustment.
# NUMBERING: 80 collision-probed at 245ea95 (grep 'Check 80'/'CHECK80' over
# scripts tests Makefile docs -> zero hits). Highest prior header = 79.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK80 R0: cannot read {path}: {exc}")
        return None

sc = read("components/PlayerScene.brs")
if sc is not None:
    hm = re.search(r'\nsub HandleSyncEvent\(ev as Object\)\n(.*?)\nend sub', sc, re.S)
    if hm is None:
        problems.append("  components/PlayerScene.brs - CHECK80 R1: sub HandleSyncEvent(ev as Object) vanished - the sync dispatcher is the only place the join anchor may lawfully be adopted")
        region = ""
    else:
        region = hm.group(1)

    # R1 - the adoption custody law: the register exists, resets on (re)join,
    # and the follower one-shot guard stands. Multi-needle family aggregates to
    # ONE conviction so a single-line plant can never double-report.
    missing = []
    if sc.count('m.syncAnchorApplied = false') != 2:
        missing.append('register reset sites (init + open arm) - expected 2')
    if sc.count('m.syncAnchorApplied') != 5:
        missing.append('register census - expected 5 sites')
    if 'if group <> invalid and not m.syncIsHost and not m.syncAnchorApplied then' not in region:
        missing.append('the follower one-shot adoption guard')
    if region.count('m.syncAnchorApplied = true') != 2:
        missing.append('register set sites (mismatch suppress + apply) - expected 2')
    if region.count('m.applyingRemote') != 2:
        missing.append('the echo-suppression wrap (applyingRemote true+false around the adoption seek)')
    if missing:
        problems.append("  components/PlayerScene.brs - CHECK80 R1: " + str(len(missing)) +
            " adoption-custody law(s) lost - " + "; ".join(missing) +
            " (a joiner that never reads group.playback_position sits at zero while the party plays on - SPEC §4 makes the anchor the joiner's starting point; MJ-9)")

    # R2 - the anchor parsing law: type-gated unboxed-safe reads, negative drop,
    # definite-state application, duration clamp, mismatch suppression, ms->s
    # seek and the existing-copy attribution notice.
    missing2 = []
    for needle in ('tp = type(group.playback_position)',
                   'havePos = anchorMs# >= 0',
                   'else if havePos and (st = "playing" or st = "paused") then',
                   'if gmedia <> "" and lmedia <> "" and gmedia <> lmedia then',
                   'if dur# > 0 and anchorMs# > dur# then anchorMs# = dur#',
                   'm.videoPlayer.seek = anchorMs# / 1000.0',
                   'NotifyPartyEvent(Translate("player_party_host_position"), 2.5!)'):
        if needle not in region:
            missing2.append(needle)
    if missing2:
        problems.append("  components/PlayerScene.brs - CHECK80 R2: " + str(len(missing2)) +
            " anchor-parsing law(s) lost - " + "; ".join(missing2) +
            " (unboxed wire reads, undropped negatives, unclamped positions, buffering/stopped frames applied as verdicts, or a seek onto a title the group left behind are each a live defect class - the clamp follows the positionOrDrop law; MJ-9)")

# R3 docs cure marker: certification only gained row 7.5 because the scene now
# adopts the anchor - the row must keep naming its cure (CHECK78 R3/CHECK79 R3
# idiom).
cert = read("docs/certification.md")
if cert is not None:
    row75 = re.search(r'^\|\s*7\.5\s*\|.*$', cert, re.MULTILINE)
    if row75 is None or "MJ-9" not in row75.group(0) or "playback_position" not in row75.group(0):
        problems.append("  docs/certification.md - CHECK80 R3: the 7.5 join-anchor row is missing or no longer names its MJ-9 cure ref and the playback_position field - the PASS claim is only honest while the adoption block stands")

# R4 ledger truth (CHECK71/.../78/79 R4 precedent).
led = read("docs/static-checks.md")
if led is not None:
    row = re.search(r'^\|\s*80\s*\|.*$', led, re.MULTILINE)
    if row is None or "MJ-9" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK80 R4: ledger row 80 is missing or no longer names its MJ-9 cure ref")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK80: %d join-anchor pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK80: the joiner adopts SPEC §4's group anchor once per (re)join - follower-")
print("           only, type-gated, negatives dropped, duration-clamped, definite")
print("           mismatches suppressed in silence, echoes wrapped; the rubber-")
print("           banding host and the at-zero joiner are both shape-impossible now")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 81: the syncplay key stream is seeded per dial - boot-window LCG guesses are the MJ-17 era (Sec-WebSocket-Key + frame masks) ==="
# WHY: RandomByte was Rnd(256)-1 over the platform LCG, and the factory's only
# seeding was Rnd(0) - a RESEED-FROM-CLOCK call at seconds granularity. An
# attacker who could not sniff the wire could still enumerate the LCG family
# from a coarse boot-time window, predict our 16-byte Sec-WebSocket-Key, and
# answer the handshake with a correctly-hashed accept: exactly the blind LAN
# injection the R-ROKU-05 accept-hash defense-in-depth exists to refuse. Cure =
# SeedWebSocketEntropy folded from SHA-1 over per-install channel client id +
# device model + millisecond wall clock, invoked at the head of NewWebSocketKey
# so every dial - and every frame mask drawn after it - runs on a stream no
# off-device observer can enumerate. The brighterscript callable corpus declares
# Rnd(x <= 0) as the seeding verb (its RandomSeed is NOT modelled by the
# vendored bsc), so the seed lands through Rnd(-n); roEVPDigest absence
# degrades to the time-only seed - still per-dial, never constant.
# NUMBERING: 81 collision-probed at ded15c3 (grep 'Check 81'/'CHECK81' over
# scripts tests Makefile docs -> zero hits). Highest prior header = 80.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK81 R0: cannot read {path}: {exc}")
        return None

proto = read("source/lib/SyncPlayProtocol.brs")
if proto is not None:
    # R1 - the seeder law: the entropy mix, the fold, the seeding verb and the
    # untouched draw shapes. Multi-needle family aggregates to ONE conviction
    # so a single-line plant can never double-report.
    missing = []
    for needle in ('        SeedWebSocketEntropy: function() as Void',
                   '            seedVal = CInt(NowMs() and 2147483647)',
                   '                clientId = dev.GetChannelClientId()',
                   '                    seedVal = ((hexba[16] and 127) * 16777216) + (hexba[17] * 65536) + (hexba[18] * 256) + hexba[19]',
                   '            Rnd(-seedVal)',
                   "        ' MJ-17: the stream is re-seeded per dial by SeedWebSocketEntropy."):
        if needle not in proto:
            missing.append(needle.strip())
    if proto.count('evp.Setup("sha1") = 0') != 1:
        missing.append('exactly one positive Setup("sha1") = 0 arm (the accept side keeps <> 0) - expected 1')
    if proto.count('            return Rnd(256) - 1') != 1:
        missing.append('the RandomByte draw shape (Rnd(256) - 1, exactly 1 site)')
    if missing:
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK81 R1: " + str(len(missing)) +
            " entropy-seeder law(s) lost - " + "; ".join(missing) +
            " (an unseeded or clock-only LCG lets a blind LAN injector enumerate the Sec-WebSocket-Key family from a boot-time window and forge the R-ROKU-05 accept proof - MJ-17)")

    # R2 - the per-dial custody law: the key draw is preceded by the seeding
    # call INSIDE NewWebSocketKey, and the 16-byte draw loop itself stands.
    km = re.search(r'\n        NewWebSocketKey: function\(\) as String\n(.*?)\n        end function', proto, re.S)
    if km is None:
        problems.append("  source/lib/SyncPlayProtocol.brs - CHECK81 R2: function NewWebSocketKey vanished - the key builder is the sole dial-side seeding custody point")
    else:
        body = km.group(1)
        if body.count('m.SeedWebSocketEntropy()') != 1:
            problems.append("  source/lib/SyncPlayProtocol.brs - CHECK81 R2: NewWebSocketKey lost its m.SeedWebSocketEntropy() call (count " +
                str(body.count('m.SeedWebSocketEntropy()')) + " - expected 1) - a key drawn from the unseeded factory stream is family-guessable (MJ-17)")
        elif body.find('m.SeedWebSocketEntropy()') > body.find('ba.Push(m.RandomByte())'):
            problems.append("  source/lib/SyncPlayProtocol.brs - CHECK81 R2: the seeding call must precede the first RandomByte draw in NewWebSocketKey - seed-after-draw hands the key to the old stream")
        if body.count('ba.Push(m.RandomByte())') != 1:
            problems.append("  source/lib/SyncPlayProtocol.brs - CHECK81 R2: the 16-byte key draw loop (ba.Push(m.RandomByte())) lost its single call site")

# R3 docs cure marker: certification gained row 7.6 because the stream is now
# seeded per dial - the row must keep naming its cure (CHECK79/80 R3 idiom).
cert = read("docs/certification.md")
if cert is not None:
    row76 = re.search(r'^\|\s*7\.6\s*\|.*$', cert, re.MULTILINE)
    if row76 is None or "MJ-17" not in row76.group(0) or "Rnd(-" not in row76.group(0):
        problems.append("  docs/certification.md - CHECK81 R3: the 7.6 entropy-custody row is missing or no longer names its MJ-17 cure ref and the Rnd(- seeding verb - the PASS claim is only honest while the per-dial seed stands")

# R4 ledger truth (CHECK78/79/80 R4 precedent).
led = read("docs/static-checks.md")
if led is not None:
    row = re.search(r'^\|\s*81\s*\|.*$', led, re.MULTILINE)
    if row is None or "MJ-17" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK81 R4: ledger row 81 is missing or no longer names its MJ-17 cure ref")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK81: %d entropy pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK81: the WS key and every mask drawn behind it ride an LCG re-seeded")
print("           per dial from per-install client id + model + millisecond clock")
print("           folded through SHA-1; a boot-window guess can no longer forge")
print("           the R-ROKU-05 accept proof")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 82: the media lane never rides a signed URL DOWN across the TLS boundary - cleartext stream targets are the MJ-19 era ==="
# WHY: three consumption sites lifted a server-supplied stream URL straight
# onto a Video/Audio content node with no scheme custody: PlayerScene's direct
# play lane, the audiobook lane, and the LiveTV tuner lane whose URL is the raw
# 302 Location from resolveLocation. On an https origin the REST answer can
# still name http://anywhere - the TV then issues the signed-URL-bearing media
# GET in cleartext, leaking the media token and viewing intent across the TLS
# boundary the session was built to keep. The repo's own plaintext-origin
# doctrine (SyncPlayWsRefusedForOrigin, M-ROKU-14) names the scheme mismatch
# itself as the exploitable class; browsers enforce the same mixed-content
# rule. Cure = IsStreamUrlAdmissible(origin, url): root-relative paths ride the
# origin scheme (admissible), any absolute shape must parse to an http(s)
# origin (OriginOfUrl refuses file://, data://, userinfo games, malformed
# hosts), and an https origin refuses an http:// target; an http origin keeps
# http media because the REST lane is already cleartext there - no NEW class.
# The predicate self-guards non-String wire shapes (CHECK43 law) and every
# refusal degrades into the site's EXISTING no-stream chrome - refusal-reason
# copy is owner-gated, no locale keys are minted by this era.
# NUMBERING: 82 collision-probed at the Batch-10 tip (grep 'Check 82'/'CHECK82'
# over scripts tests Makefile docs -> zero hits). Highest prior header = 81.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import re, sys, os

os.chdir(os.environ['REPO'])
problems = []

def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as exc:
        problems.append(f"  CHECK82 R0: cannot read {path}: {exc}")
        return None

# --- R1: the media-lane predicate keeps its full shape in Utilities.brs ---
u = read("source/lib/Utilities.brs")
if u is not None:
    laws = []
    needles = [
        "function IsStreamUrlAdmissible(originUrl as String, streamUrl as String) as Boolean",
        '    if Left(s, 1) = "/" then return true',
        '    if OriginOfUrl(s) = "" then return false',
        '        if Left(LCase(originUrl.Trim()), 8) = "https://" and Left(s, 7) = "http://" then',
    ]
    for n in needles:
        if u.count(n) != 1:
            laws.append(n.strip()[:60])
    if "if type(streamUrl) <> \"String\" then return false" not in u:
        laws.append("non-String wire guard")
    if "MEDIA LANE TLS-BOUNDARY LAW (MJ-19" not in u:
        laws.append("MJ-19 section marker")
    if laws:
        problems.append(
            "  source/lib/Utilities.brs - CHECK82 R1: admissibility law(s) lost - "
            + "; ".join(laws)
            + " (a server-answered cleartext or fabricated-scheme media URL can leak "
            "signed tokens across the TLS boundary again - MJ-19)")

# --- R2: all three consumption sites gate through the predicate ---
site_laws = []
for path, marker in (
    ("components/PlayerScene.brs", "[MJ-19] refusing"),
    ("components/AudiobookPlayerScene.brs", "[MJ-19] audiobook: refusing"),
    ("components/LivePlayerScene.brs", "[MJ-19] live: refusing"),
):
    t = read(path)
    if t is None:
        continue
    if t.count("if not IsStreamUrlAdmissible(GetServerUrl(), streamUrl) then") != 1:
        site_laws.append(path + ": gate call lost or duplicated")
    if path == "components/PlayerScene.brs":
        # RT-002 w01 wave (2026-11-06) rotation, from measured red in that
        # commit: the single HLS choke PlayHlsUrlRefused re-uses the era's
        # unified refusal print, so the file legitimately carries the marker
        # TWICE now (direct lane + shared gate). Presence is the law; the
        # gate itself is pinned by CHECK95 R4. The other two files stayed
        # single-site lanes and keep the exact-count law.
        if t.count(marker) < 1:
            site_laws.append(path + ": refusal marker lost")
    elif t.count(marker) != 1:
        site_laws.append(path + ": refusal marker lost")
if site_laws:
    problems.append(
        "  CHECK82 R2: media-lane gate custody broken - " + "; ".join(site_laws)
        + " (an ungated site re-opens the cleartext signed-URL leak the era closed - MJ-19)")

# --- R3: the certification row names the cure ---
c = read("docs/certification.md")
if c is not None:
    m = re.search(r"^\|\s*7\.7\s*\|.*$", c, re.M)
    if not m or "MJ-19" not in m.group(0) or "mixed-content" not in m.group(0):
        problems.append("  docs/certification.md - CHECK82 R3: the 7.7 media-lane custody row is missing or no longer names its MJ-19 cure")

# --- R4: the static-checks ledger row exists and names the cure ref ---
s = read("docs/static-checks.md")
if s is not None:
    m = re.search(r"^\|\s*82\s*\|.*$", s, re.M)
    if not m or "MJ-19" not in m.group(0):
        problems.append("  docs/static-checks.md - CHECK82 R4: ledger row 82 is missing or no longer names its MJ-19 cure ref")

if problems:
    print(f"  CHECK82: {len(problems)} media-lane custody pin(s) broken")
    for p in problems:
        print(p)
    sys.exit(1)

print("  CHECK82: every signed media URL is admitted or refused at the TLS boundary -")
print("           Utilities' predicate keeps its relative-path, origin-parse,")
print("           downgrade-refusal and wire-shape arms, all three consumption")
print("           sites (direct play, audiobook, tuner Location) gate through it,")
print("           and refusals degrade into existing localized no-stream chrome.")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 83: logs keep wire content out, relative Locations absolutize, the dead room stays documented dead - the MN-16/MN-22/MN-24/MN-25/MN-29 era ==="
# WHY: MN-22 (review roku__secnet): the UI-side raw-wire echo was convicted by
# M-ROKU-03 but two DEBUG-LOG echoes of wire content lingered - SyncPlayTask's
# error arm printed msg.error_code raw (message-sized payload reaches the log
# whenever a server misuses the code field) and GetErrorMessage's suppressed
# detail arm printed the entire (already length-capped) safeError. MN-24
# (review roku__qa): resolveLocation returned the 3xx Location verbatim, so a
# relative "/streams/x.m3u8" reached getChannelStreamUrl and the Video node
# silently never played; and the MJ-19 gate ADMITS root-relative paths by
# doctrine, so a scheme-less survivor still reached playback nodes. MN-16
# (review roku__srphp): the dead SyncPlayManager path carries blocking
# wait(35000) REST calls a revival would inherit - the header must state the
# revival law. MN-25/MN-29: README claimed 6 settings sections (7 ship) and
# i18n.md claimed Check 19 scans three files (four since R-ROKU-08).
#   R1: log custody - IsErrorCodeToken stands and the SyncPlayTask echo is gated
#       by it; GetErrorMessage's diagnostic carries a COUNT, never content (the
#       old echo shape is convicted by name, plant-safe).
#   R2: Location custody - resolveLocation absolutizes via ResolveRedirectTarget
#       before returning, and all three playback surfaces refuse scheme-less
#       stream urls at the node boundary.
#   R3: the dead manager's header carries the REVIVAL LAW (MN-16 marker + the
#       background-task clause).
#   R4: docs truth - README's settings row names 7 sections incl Notifications,
#       the nav walk lists notifications, i18n.md names four scoped files, and
#       the certification media-lane row 7.8 names the MN-24 custody.
# NUMBERING: 83 collision-probed at 4d143c9, highest prior 82.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

problems = []

# --- R1: log custody (MN-22) ---
task = read("components/SyncPlayTask.brs")
utils = read("source/lib/Utilities.brs")
laws = []
if task is None or utils is None:
    problems.append("  CHECK83 R0: cannot read the syncplay task or utilities - the pin cannot run vacuously")
else:
    if "function IsErrorCodeToken(value as String) as Boolean" not in utils:
        laws.append("IsErrorCodeToken predicate lost")
    if "        if IsErrorCodeToken(codeStr) then" not in task:
        laws.append("SyncPlayTask error echo no longer gated by the token shape")
    if 'print "SyncPlay error_code: " + codeStr' in task and "if IsErrorCodeToken(codeStr) then\n            print \"SyncPlay error_code: \" + codeStr" not in task:
        laws.append("ungated raw error_code echo re-grown")
    if "suppressed wire detail (\" + Str(Len(safeError)).Trim() + \" chars)\"" not in utils:
        laws.append("GetErrorMessage detail no longer count-only")
    if 'print "GetErrorMessage suppressed wire detail: " safeError' in utils:
        laws.append("content-bearing suppressed-detail echo re-grown")
    if laws:
        problems.append(
            "  components/SyncPlayTask.brs - CHECK83 R1: " + "; ".join(laws)
            + " (wire message content must never ride the debug log - only bounded "
            "code tokens or a char count - MN-22)")

# --- R2: Location custody (MN-24) ---
api = read("source/lib/ApiClient.brs")
laws = []
if api is None:
    problems.append("  CHECK83 R0: cannot read ApiClient - the pin cannot run vacuously")
else:
    m = re.search(r"\n        resolveLocation: function\(path as String\) as String\n(.*?)\n        end function", api, re.S)
    if m is None:
        problems.append("  source/lib/ApiClient.brs - CHECK83 R2: resolveLocation vanished - the 302 custody pin cannot run vacuously")
    else:
        if "if location <> \"\" then location = ResolveRedirectTarget(url, location)" not in m.group(1):
            laws.append("resolveLocation stopped absolutizing the 3xx Location")
if laws:
    problems.append(
        "  source/lib/ApiClient.brs - CHECK83 R2: " + "; ".join(laws)
        + " (a relative Location hands the Video node a scheme-less url and live "
        "TV silently never plays - MN-24)")
laws = []
for path in (
    "components/PlayerScene.brs",
    "components/AudiobookPlayerScene.brs",
    "components/LivePlayerScene.brs",
):
    t = read(path)
    if t is None:
        continue
    if t.count('Left(LCase(streamUrl), 6) <> "https:"') != 1:
        laws.append(path + ": scheme custody lost or duplicated")
if laws:
    problems.append(
        "  components - CHECK83 R2: " + "; ".join(laws)
        + " (a root-relative survivor of the MJ-19 gate cannot be fetched by a "
        "playback node - refuse at the boundary, never silence - MN-24)")

# --- R3: revival law (MN-16) ---
mgr = read("source/lib/SyncPlayManager.brs")
if mgr is None:
    problems.append("  CHECK83 R0: cannot read SyncPlayManager - the pin cannot run vacuously")
else:
    laws = []
    if "REVIVAL LAW (MN-16" not in mgr:
        laws.append("revival-law marker missing")
    if "background task" not in mgr:
        laws.append("blocking-REST clause missing")
    if laws:
        problems.append(
            "  source/lib/SyncPlayManager.brs - CHECK83 R3: " + "; ".join(laws)
            + " (the dead room's blocking wait(35000) calls must be named before "
            "any revival - MN-16)")

# --- R4: docs truth (MN-25/MN-29 + certification 7.8) ---
readme = read("README.md")
if readme is None or "# Settings, 7 sections (Account / Server / Playback / Captions / Watch History / Notifications /" not in readme:
    problems.append("  README.md - CHECK83 R4: the settings row lost its 7-section/Notifications truth (MN-25)")
if readme is not None and "captions mode, notifications, clear watch history, and PiP" not in readme:
    problems.append("  README.md - CHECK83 R4: the nav walk lost notifications (MN-25)")
i18n = read("docs/i18n.md")
if i18n is None or "The four scoped files" not in i18n:
    problems.append("  docs/i18n.md - CHECK83 R4: Check 19's scope lost its four-file truth (MN-29)")
cert = read("docs/certification.md")
row = ""
if cert is not None:
    mm = re.search(r"^\|\s*7\.8\s*\|.*$", cert, re.M)
    if mm:
        row = mm.group(0)
if "MN-24" not in row or "ResolveRedirectTarget" not in row:
    problems.append("  docs/certification.md - CHECK83 R4: the 7.8 row is missing or no longer names its MN-24 custody (ResolveRedirectTarget)")

if problems:
    for p in problems:
        print(p)
    print("  CHECK83: %d log-custody/Location/revival/docs pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK83: the debug log never carries message-sized wire content; a 302 Location")
print("           absolutizes before it reaches a playback node; the dead room's revival")
print("           law and the docs counts stand.")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 84: the locale probe walks every section, the en_US copy law holds, the synopsis reads at distance (MN-18/MN-27/MN-8 era) ==="
# WHY: MN-18 (review roku__scribe lineage): Translate()'s legacy nested probe
# walked SIX hardcoded section names while the catalog ships 32 — a bare-key
# caller into any other section silently returned the raw key. Cure: enumerate
# the PARSED catalog's own keys (raw.Keys(), "_metadata" skipped) — the probe
# can no longer lag the catalog; CHECK 22's (c) arm rotated to the same shape
# (the legacy six-name list was the convicted shape there too — disclosed
# rotation, intent 'errors family resolvable' preserved and strengthened).
# MN-27 (review roku__writer): en_US 'Select Track' violated the uniform
# sentence-case family, and connect.err_bad_url lacked the closing period the
# sibling error lines carry — measured truth: 8 of 10 siblings had it; the cure
# closed the WHOLE family (err_empty/err_invalid joined, disclosed) so the law
# is now total, not aspirational. MN-8 (review roku__a11y): the synopsis label
# was font:SmallSystemFont — unreadable from couch distance; it joins the
# MediumSystemFont body family (58 prior sites). MN-28 (review roku__writer):
# the README dev-mode flow never named the accept-EULA → SET DEVICE PASSWORD →
# reboot step the install story authenticates against (ROKU_PASSWORD) — the
# on-device truth lives in docs/device-verification.md §1; the README now says
# it. Twin plants V (re-grow the legacy six-name list — R1 ban alone) and W
# (strip one err_* closing period — R2 alone), gate independence pinned.
# NUMBERING: 84 collision-probed at 24b5148, highest prior 83.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

repo = os.environ['REPO']
os.chdir(repo)
problems = []

UTILITIES = "source/lib/Utilities.brs"
EN = "locale/en_US/strings.json"
DETAIL = "components/DetailScene.xml"
README = "README.md"
LEDGER = "docs/static-checks.md"


def read(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError as e:
        problems.append(f'  {path} - CHECK84: unreadable: {e}')
        return None


# --- R1: MN-18 dynamic probe (walk present; legacy list extinct) ---
util = read(UTILITIES)
if util is not None:
    r1 = []
    if ('function BuildBareLocaleIndex(' not in util
            or 'for each section in raw.Keys()' not in util
            or 'LoadLocaleStrings._bare = BuildBareLocaleIndex(raw)' not in util
            or 'bare = LoadLocaleStrings._bare' not in util):
        r1.append('probe stopped enumerating the parsed catalog (raw.Keys() walk lost; ROK-27 precomputed bare index must walk every section at load and Translate must read it)')
    if 'if section <> "_metadata"' not in util:
        r1.append('_metadata-skip guard lost')
    if util.count('sections = ["common"') != 0:
        r1.append('the legacy six-name section list is re-grown')
    if r1:
        problems.append(
            f'  {UTILITIES} - CHECK84 R1: ' + '; '.join(r1)
            + ' (a bare-key caller into an unlisted section silently renders raw keys - MN-18)')

# --- R2: MN-27 en_US copy law ---
en = read(EN)
if en is not None:
    try:
        doc = json.loads(en)
        r2 = []
        st = (doc.get('player') or {}).get('select_track')
        if st != 'Select track':
            r2.append(f"player.select_track drifted from the sentence-case family (got {st!r})")
        conn = doc.get('connect') or {}
        bad = sorted(k for k, v in conn.items()
                     if k.startswith('err') and isinstance(v, str)
                     and not v.rstrip().endswith(('.', '!', '?')))
        if bad:
            r2.append('connect.err_* without the closing period: ' + ', '.join(bad))
        if r2:
            problems.append(
                f'  {EN} - CHECK84 R2: ' + '; '.join(r2)
                + ' (the en_US copy law is total now - the family reads uniform from couch to couch - MN-27)')
    except ValueError as e:
        problems.append(f'  {EN} - CHECK84 R2: unparsable JSON: {e}')

# --- R3: MN-8 synopsis font ---
det = read(DETAIL)
if det is not None:
    if det.count('font="font:SmallSystemFont"') != 0:
        problems.append(
            f'  {DETAIL} - CHECK84 R3: a SmallSystemFont label is back in the detail view - '
            'synopsis body must ride the MediumSystemFont family (unreadable at couch distance - MN-8)')

# --- R4: MN-28 README device-password step ---
rd = read(README)
if rd is not None:
    r4 = []
    if 'set a device password' not in rd:
        r4.append('the accept-EULA -> set-device-password -> reboot step vanished from the README')
    if 'rokipassword' not in rd:
        r4.append('the ROKU_PASSWORD example binding vanished')
    if r4:
        problems.append(
            f'  {README} - CHECK84 R4: ' + '; '.join(r4)
            + ' (the install story authenticates against a password the setup text never named - MN-28)')

# --- R5: ledger row 84 names the era ---
led = read(LEDGER)
if led is not None:
    m = re.search(r'^\|\s*84\s*\|.*$', led, re.M)
    if not m or 'MN-18' not in m.group(0):
        problems.append(
            f'  {LEDGER} - CHECK84 R5: ledger row 84 is missing or no longer names its MN-18 cure ref')

if problems:
    print('\n'.join(problems))
    print(f'  CHECK84: {len(problems)} locale-probe/copy/font/docs pin(s) broken')
    sys.exit(1)

print('  CHECK84: the nested probe walks EVERY shipped section; the en_US copy law is')
print('           total; the synopsis reads at couch distance; the README names the')
print('           password the installer authenticates with.')
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 85: dead-pane node swap, safe-area chrome, honest fetch cues (MN-7/MN-9/MN-10 era) ==="
# WHY: three review findings, one era. MN-7: the audiobook chapters pane was
# a plain <List> - it renders no rows and never fires itemSelected, while the
# .brs observer and ContentNode feed were always MarkupList-shaped (the dead
# pane the [review roku__qa] walk flagged). MN-9: HomeScene's header chrome
# sat at y=20 inside the top overscan band, the description strip at y=680
# clipped 8px OFF a 720 plane, and the M-ROKU-21 retry button bottom-right
# was the one recovery control a television could hide - cert reviewers and
# 4:3 sets both lose it. MN-10: three "Loading…" labels were auto-width at
# x=640 (horizAlign="center" centers INSIDE the box - the box began at the
# center), Detail/Series shipped them default-visible (boot flicker), no
# scene had motion, and Detail's getItem failure early-returned BEFORE the
# hide - the cue stranded on "Loading" forever once default-visible dropped.
# Cures: MarkupList node swap (attrs kept, zero .brs change); coordinates
# moved inside [64,36,1152,648] with grid height abutting the strip; labels
# full-plane + initially hidden + a Spinner the PlayerScene visible-drive
# idiom already ships, toggled beside every label write, failure retract
# included. Each arm below is one law; convictions stay one-line each so the
# twin plants (X chapter-node re-regrow / Y retry overscan re-escape) each
# fire exactly one.
# NUMBERING: 81/82/83/84 taken by prior eras; 85 collision-probed at the
# batch-13 tip (grep -c 'Check 85' == 0), highest prior 84.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

problems = []


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


# ---- R1: MN-7 chapters pane is the component its observer was written for
ax = read("components/AudiobookPlayerScene.xml")
ab = read("components/AudiobookPlayerScene.brs")
tags = re.findall(r"<(\w+)\b[^>]*id=\"chapterList\"[^>]*/?>", ax)
if tags != ["MarkupList"]:
    problems.append("  components/AudiobookPlayerScene.xml - CHECK85 R1: chapterList "
                    "renders through %s, not MarkupList - a plain List draws no rows "
                    "and never fires itemSelected (MN-7 dead pane)" % (tags or "nothing"))
ml = re.search(r"<MarkupList\b[^>]*id=\"chapterList\"[^>]*/?>", ax)
if ml and ('numRows="5"' not in ml.group(0) or 'itemSize="[840, 40]"' not in ml.group(0)):
    problems.append("  components/AudiobookPlayerScene.xml - CHECK85 R1: the chapter "
                    "MarkupList lost the numRows/itemSize the pane is sized by (MN-7 cure "
                    "keeps every attribute - the feed below still builds .Title rows)")
if 'ObserveField("itemSelected"' not in ab:
    problems.append("  components/AudiobookPlayerScene.brs - CHECK85 R1: the itemSelected "
                    "observer vanished - the MarkupList swap presumes it (MN-7)")

# ---- R2: MN-9 home chrome lives inside the overscan bands
hx = read("components/HomeScene.xml")
if 'translation="[40,20]"' in hx:
    problems.append("  components/HomeScene.xml - CHECK85 R2: brand label back at "
                    "[40,20] - inside the top overscan band; MN-9 moves header chrome "
                    "to the [64,36] safe origin")
if 'translation="[0,680]"' in hx or 'translation="[0,636]"' not in hx:
    problems.append("  components/HomeScene.xml - CHECK85 R2: description strip is no "
                    "longer safe-area-flush at [0,636] (h40 -> 676; it used to sit at "
                    "680 with 8px off a 720 plane)")
if 'translation="[1100,682]"' in hx:
    problems.append("  components/HomeScene.xml - CHECK85 R2: retryButton escaped to "
                    "[1100,682] again - bottom 718/right 1260 is overscan territory; "
                    "the recovery control must live where a set can show it (MN-9)")


def box(tag_pat, kind, path="components/HomeScene.xml", src=None):
    m = re.search(tag_pat, src if src is not None else read(path), re.S)
    if not m:
        problems.append("  %s - CHECK85 R2: %s tag vanished (MN-9 chrome)" % (path, kind))
        return None
    tr = re.search(r'translation="\[(-?\d+),\s?(-?\d+)\]"', m.group(0))
    wh = re.search(r'width="(\d+)"', m.group(0))
    ht = re.search(r'height="(\d+)"', m.group(0))
    if not (tr and wh and ht):
        problems.append("  %s - CHECK85 R2: %s lost translation/width/height - the "
                        "safe-area arithmetic needs all three (MN-9)" % (path, kind))
        return None
    return tuple(int(g.group(1)) for g in (tr, wh, ht))


# Safe area on the 720 plane: [64,36,1152,648] -> x in [64,1216], y in [36,684].
rt = box(r'<Button\b[^>]*id="retryButton"[^>]*>', "retryButton", src=hx)
if rt:
    x, w, h = rt
    m = re.search(r'<Button\b[^>]*id="retryButton"[^>]*>', hx, re.S)
    y = int(re.search(r'translation="\[\d+,\s?(\d+)\]"', m.group(0)).group(1))
    # the escape-absence law above owns the [1100,682] revert; arithmetic
    # convicts only NEW offenders so one revert fires one line (twin law)
    if not (x + w <= 1216 and y + h <= 684) and 'translation="[1100,682]"' not in hx:
        problems.append("  components/HomeScene.xml - CHECK85 R2: retryButton box "
                        "(%d..%d, %d..%d) leaves the safe area (right 1216/bottom 684) "
                        "- the M-ROKU-21 recovery control is lost to overscan (MN-9)"
                        % (x, x + w, y, y + h))
st = box(r'<Rectangle\b[^>]*translation="\[\d+,\s?\d+\]"[^>]*color="#0d0d1a"', "description strip", src=hx)
if st:
    x, w, h = st
    m = re.search(r'<Rectangle\b[^>]*translation="\[\d+,\s?(\d+)\]"[^>]*color="#0d0d1a"', hx, re.S)
    ty = int(m.group(1))
    if not (ty >= 36 and ty + h <= 684) and 'translation="[0,636]"' in hx:
        problems.append("  components/HomeScene.xml - CHECK85 R2: description strip at "
                        "y=%d (h%d) no longer ends inside the safe bottom 684 (MN-9)"
                        % (ty, h))
# Grid must abut the strip: [0,484] + height <= strip top 636.
gm = re.search(r'<PosterGrid\b[^>]*id="libraryGrid"[^>]*>|<PosterGrid\b[^>]*translation="\[0,484\]"[^>]*>', hx, re.S)
if gm is None:
    gm = re.search(r'<PosterGrid height="(\d+)" width="1280" translation="\[0,484\]"', hx)
    ght = int(gm.group(1)) if gm else None
else:
    ght = int(re.search(r'height="(\d+)"', gm.group(0)).group(1)) if gm else None
if ght is None:
    problems.append("  components/HomeScene.xml - CHECK85 R2: libraryGrid tag "
                    "unfindable - its height law cannot run (MN-9)")
elif ght + 484 > 636:
    problems.append("  components/HomeScene.xml - CHECK85 R2: libraryGrid height=%d "
                    "reaches y=%d past the description strip top 636 - the pre-MN-9 "
                    "overlap is back (claimed window was already fiction; now it is "
                    "arithmetic)" % (ght, 484 + ght))
for nid in ("Search", "ForYou", "Favorites", "Collections", "Settings"):
    pass  # header buttons are pinned by the next arithmetic law:

hb = re.findall(r'<Button\b[^>]*?height="60"[^>]*?translation="\[\d+,\s?(\d+)\]"[^>]*?>', hx, re.S)
hb += re.findall(r'<Button\b[^>]*?translation="\[\d+,\s?(\d+)\]"[^>]*?height="60"[^>]*?>', hx, re.S)
if len(hb) < 6:
    problems.append("  components/HomeScene.xml - CHECK85 R2: only %d header buttons "
                    "parse (six are shipped) - the y>=36 top-band law cannot run" % len(hb))
elif any(int(y) < 36 for y in hb):
    problems.append("  components/HomeScene.xml - CHECK85 R2: a header button sits at "
                    "y<36 - back inside the top overscan band MN-9 pulled chrome out of "
                    "(got %s)" % sorted(set(hb)))

# ---- R3: MN-10 fetch cues center, start hidden, spin, and retract
cues = (
    ("components/HomeScene.xml", "components/HomeScene.brs", 2),
    ("components/DetailScene.xml", "components/DetailScene.brs", 2),
    ("components/SeriesScene.xml", "components/SeriesScene.brs", 1),
)
for xmlp, brsp, false_min in cues:
    xs = read(xmlp)
    tag = re.search(r'<Label id="loadingLabel"[^>]*>', xs, re.S)
    if tag is None:
        problems.append("  %s - CHECK85 R3: loadingLabel vanished (MN-10 cue family)" % xmlp)
    else:
        t = tag.group(0)
        if 'width="1280"' not in t or 'translation="[0, 340]"' not in t or 'visible="false"' not in t:
            problems.append("  %s - CHECK85 R3: loadingLabel lost its full-plane "
                            "centering or the hidden default - an auto-width label at "
                            "x=640 renders right-of-center, and a default-visible cue "
                            "flickers at boot (MN-10)" % xmlp)
    if xs.count('<Spinner id="fetchSpinner"') != 1:
        problems.append("  %s - CHECK85 R3: the fetchSpinner sibling is missing or "
                        "duplicated - motion is the repo's PlayerScene visible-drive "
                        "idiom (MN-10)" % xmlp)
    bs = read(brsp)
    if bs.count('FindNode("fetchSpinner")') != 1:
        problems.append("  %s - CHECK85 R3: no single fetchSpinner wiring line "
                        "(MN-10)" % brsp)
    if bs.count("fetchSpinner.visible = true") < 1:
        problems.append("  %s - CHECK85 R3: nothing ever starts the spinner - the label "
                        "spins its partner law (MN-10)" % brsp)
    if bs.count("fetchSpinner.visible = false") < false_min:
        problems.append("  %s - CHECK85 R3: fewer than %d spinner retract sites - every "
                        "loadingLabel hide must retract the cue with it, and Detail's "
                        "failure arm counts (MN-10)" % (brsp, false_min))

db = read("components/DetailScene.brs")
failarm = re.search(
    r"if not resp\.ok or resp\.data = invalid then\n(.*?)return\n\s*end if", db, re.S)
if failarm is None:
    problems.append("  components/DetailScene.brs - CHECK85 R3: the getItem failure "
                    "early-return is gone or reshaped - with it the cue-strand fix "
                    "(hide label + spinner before returning, MN-10) has no home")
elif "fetchSpinner.visible = false" not in failarm.group(1) or "loadingLabel.visible = false" not in failarm.group(1):
    problems.append("  components/DetailScene.brs - CHECK85 R3: a failed getItem no "
                    "longer retracts BOTH cue halves before returning - a default-hidden "
                    "cue that shows on request and never hides on failure is the same "
                    "perpetual Loading with new steps (MN-10)")

# ---- R4: the era's docs carry the era
sx = read("docs/static-checks.md")
row = re.search(r"^\|\s*85\s*\|[^\n]*$", sx, re.M)
if not row or not all(k in row.group(0) for k in ("MN-7", "MN-9", "MN-10")):
    problems.append("  docs/static-checks.md - CHECK85 R4: row 85 missing or not "
                    "naming MN-7/MN-9/MN-10 - Check 85 has no ledger entry")
ch = read("CHANGELOG.md")
if "MN-7" not in ch or "fetchSpinner" not in ch:
    problems.append("  CHANGELOG.md - CHECK85 R4: no changelog entry names the "
                    "MN-7 chapters pane or the fetchSpinner cue (era record)")

if problems:
    print("\n".join(problems))
    print("  CHECK85: %d pin(s) broken" % len(problems))
    sys.exit(1)
print("  CHECK85: the chapters pane renders through the component its observer was")
print("           written for; the home chrome (brand, six header buttons, strip,")
print("           retry, grid) lives inside the [64,36,1152,648] safe area with the")
print("           grid abutting the strip; every fetch cue is full-plane centered,")
print("           starts hidden, spins beside its label, and retracts on failure.")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# --- Check 86: MJ-13 accessibleLabel custody (the browse path is speakable) ---
echo "=== Check 86: spoken-label custody on the grid family and the home rails (MJ-13 era) ==="
# WHY: the gameux review found accessibleLabel appearing ZERO times channel-wide —
# no accessible browse -> detail -> play path. The cure mirrors the readable name
# every media-grid builder already sets (Title:) into the explicit Roku
# screen-reader field accessibleLabel, and labels the three HomeScene rails with
# the SAME catalog keys their heading Labels render. Attribute-only by law: the
# values are data expressions or Translate() calls — a design-time English literal
# in an accessibleLabel (XML or .brs assignment) is a CHECK25-mirror breach the
# runtime never needs. This leg pins the builder family, the rail trio, and the
# no-literal law.
# NUMBERING: 86 collision-probed at d87d253, highest prior 85.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import glob, os, re, sys

problems = []

# R1: per-file builder-mirror census (colon AA-key sites; DetailScene writes the
# guarded '=' form once — named by shape). Builder sites and rail containers are
# disjoint token forms so each twin plant fires exactly one arm.
BUILDER_CENSUS = {
    "components/AudiobookScene.brs": ("accessibleLabel:", 1),
    "components/CollectionScene.brs": ("accessibleLabel:", 1),
    "components/DetailScene.brs": ("node.accessibleLabel = sim.title", 1),
    "components/EpisodeListTask.brs": ("accessibleLabel:", 1),
    "components/FavoritesScene.brs": ("accessibleLabel:", 1),
    "components/HomeScene.brs": ("accessibleLabel:", 3),
    "components/LibraryScene.brs": ("accessibleLabel:", 1),
    "components/PhotoAlbumScene.brs": ("accessibleLabel:", 1),
    "components/PhotosScene.brs": ("accessibleLabel:", 1),
    "components/SearchScene.brs": ("accessibleLabel:", 1),
}
for rel, (token, want) in BUILDER_CENSUS.items():
    if not os.path.exists(rel):
        problems.append("  %s - CHECK86 R1: the grid builder file vanished" % rel)
        continue
    with open(rel, encoding="utf-8") as f:
        src = f.read()
    got = src.count(token)
    if got < want:
        problems.append("  %s - CHECK86 R1: %d accessibleLabel builder mirror(s), expected %d (MJ-13 cure lost)" % (rel, got, want))

# R2: the HomeScene rail trio carries container labels from the catalog.
with open("components/HomeScene.brs", encoding="utf-8") as f:
    home = f.read()
n = home.count("n.accessibleLabel = Translate(")
if n != 3:
    problems.append("  components/HomeScene.brs - CHECK86 R2: expected 3 rail labels (continueGrid/upNextGrid/libraryGrid), found %d (MJ-13)" % n)

# R3: no-literal law — accessibleLabel values are data or Translate, never raw English.
for path in glob.glob("components/*.xml"):
    with open(path, encoding="utf-8") as f:
        if 'accessibleLabel="' in f.read():
            problems.append("  %s - CHECK86 R3: design-time accessibleLabel literal bypasses the catalog mirror law" % path)
for path in glob.glob("components/*.brs") + glob.glob("source/**/*.brs", recursive=True):
    with open(path, encoding="utf-8") as f:
        if re.search(r"accessibleLabel\s*=\s*\"", f.read()):
            problems.append("  %s - CHECK86 R3: raw English literal assigned to accessibleLabel" % path)

# R4: docs custody — the static-checks row and CHANGELOG entry name the era.
with open("docs/static-checks.md", encoding="utf-8") as f:
    rows = f.read()
row = re.search(r"^\|\s*86\s*\|.*$", rows, re.M)
if not row or "MJ-13" not in row.group(0):
    problems.append("  docs/static-checks.md - CHECK86 R4: row 86 missing or not naming MJ-13")
with open("CHANGELOG.md", encoding="utf-8") as f:
    chg = f.read()
if "MJ-13" not in chg or "accessibleLabel" not in chg:
    problems.append("  CHANGELOG.md - CHECK86 R4: no entry naming MJ-13/accessibleLabel")

if problems:
    print("  CHECK86: %d accessibility custody law(s) broken:" % len(problems))
    for p in problems:
        print(p)
    sys.exit(1)

print("  CHECK86: every grid item and the home rails carry an explicit spoken label -")
print("           MJ-13 mirror custody holds (data/Translate values only, zero literals).")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 87: catalog, manifest and input-field hygiene - retired keys stay buried, undocumented keys stay out, naked fields stay capped (MN-21/MN-26/MN-6 era) ==="
# THE HYGIENE TRIO (MN-26, MN-21, MN-6 length-cap half; reviews roku__writer,
# roku__crossfe, roku__exploiter+secnet - 2026-11-03 fix lane):
#   R1  `detail.error_favorite_save` ("Error", an abandoned-draft duplicate of
#       common.error) is REMOVED from all seven catalogs - the live
#       `detail_error_favorite_save_message` consumer path is pinned present -
#       and the set has ridden every bump since - v1.19.0 at this commit
#       (CHECK48 R3's literal rotated with it, per the M-ROKU-20/R-ROKU-10
#       set-bump precedent: removal, no mint), v1.20.0 with the MJ-2
#       join-code mint (deferred lane, 2026-11-03), then v1.21.0 with the
#       RT-032 concurrent-stream singular mint (w11L1, 2026-11-09), then
#       v1.22.0 with the RT-094 four browse-failure mint (w15L9 R-B,
#       2026-11-10), then v1.23.0 with the RT-095 thirteen-key mint (w15L9
#       R-C, 2026-11-10); R1's
#       own version literal below is the CURRENT ride, not a historical
#       claim.
#   R2  the manifest ships only documented, hd-relevant keys: splash_width,
#       splash_height, screensaver_private (all ignored by firmware, all
#       cert-review bounce risks) and mm_icon_focus_sd (dead weight beside the
#       absent side_sd under ui_resolutions=hd) are extinct; the documented
#       set that must survive is positively pinned too - absence laws alone
#       cannot tell a cure from an accident.
#   R3  every TextEditBox/Keyboard input field in components/ carries
#       maxLength: the registry-crypto half of MN-6 stays deferred (platform
#       custody), but "unbounded text flows into server columns and the fixed
#       720 layout" is pure client hygiene and is closed here (serverInput/
#       usernameInput/passwordInput 255 - the column class; roomNameInput 100;
#       search Keyboard 128 - layout distance).
#   R4  this era's rows: docs/static-checks.md row 87 and the CHANGELOG entry.
# NUMBERING: 87 collision-probed at d87d253 (highest prior 86); twin plant
# letters BB/CC/DD continue the static-checks.md series (Z/AA = Check 86).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import json, os, re, sys

LOCALES = ("de_DE", "en_US", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR")
problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# ---- R1 the retired favorite-save key stays buried; set rides the current v1.23.0 ----
r1 = []
for loc in LOCALES:
    path = f"locale/{loc}/strings.json"
    raw = read(path)
    if raw is None:
        r1.append(f"{path} unreadable")
        continue
    try:
        cat = json.loads(raw)
    except ValueError as err:
        r1.append(f"{path} unparseable ({err})")
        continue
    detail = cat.get("detail", {})
    if "error_favorite_save" in detail:
        r1.append(f"{path} dead detail.error_favorite_save re-grown")
    if "error_favorite_save_message" not in detail:
        r1.append(f"{path} live detail.error_favorite_save_message vanished")
    if cat.get("_metadata", {}).get("version") != "1.23.0":
        r1.append(f"{path} _metadata.version is not 1.23.0")
if r1:
    problems.append("  locale/* - CHECK87 R1: catalog hygiene broken: " + "; ".join(r1))

# ---- R2 the manifest ships only documented, hd-relevant keys ----
BANNED = ("splash_width=", "splash_height=", "screensaver_private=", "mm_icon_focus_sd=")
REQUIRED = ("mm_icon_focus_hd=", "mm_icon_side_hd=", "splash_color=",
            "splash_min_time=", "screensaver_title=", "ui_resolutions=hd")
r2 = []
mani = read("manifest")
if mani is None:
    r2.append("manifest unreadable")
else:
    lines = [ln.strip() for ln in mani.splitlines()]
    for key in BANNED:
        if any(ln.startswith(key) for ln in lines):
            r2.append(f"undocumented/dead key {key[:-1]} re-shipped")
    for key in REQUIRED:
        if not any(ln.startswith(key) for ln in lines):
            r2.append(f"documented key {key} went missing")
if r2:
    problems.append("  manifest - CHECK87 R2: " + "; ".join(r2))

# ---- R3 no input field takes unbounded text ----
TAG_RE = re.compile(r'<(TextEditBox|Keyboard)\b(((?!>).)*)>', re.S)
r3 = []
for name in sorted(os.listdir("components")):
    if not name.endswith(".xml"):
        continue
    xml = read(f"components/{name}")
    if xml is None:
        continue
    for mm in TAG_RE.finditer(xml):
        body = mm.group(2)
        if "maxLength" not in body:
            idm = re.search(r'id="([^"]+)"', body)
            r3.append(f"{name} {idm.group(1) if idm else 'unnamed'} has no maxLength")
if r3:
    problems.append("  components/*.xml - CHECK87 R3: " + "; ".join(r3))

# ---- R4 the era's docs rows ----
sc = read("docs/static-checks.md") or ""
cl = read("CHANGELOG.md") or ""
row = None
for ln in sc.splitlines():
    if re.match(r"^\|\s*87\s*\|", ln):
        row = ln
        break
if row is None or not all(tok in row for tok in ("MN-21", "MN-26", "MN-6")):
    problems.append("  docs/static-checks.md - CHECK87 R4: row 87 is missing or does not name MN-21/MN-26/MN-6")
if "MN-26" not in cl or "maxLength" not in cl:
    problems.append("  CHANGELOG.md - CHECK87 R4: the entry must name MN-26 and the maxLength caps")

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK87: %d hygiene pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK87: the buried catalog key stays buried, the manifest ships only its")
print("           documented set, and no input field takes unbounded text - the")
print("           MN-21/MN-26/MN-6 trio (catalog set rides v1.23.0 - the current ride,")
print("           rotated again by the MJ-2 join-code mint, the RT-032")
print("           singular-key mint, the RT-094 four browse-failure mint and the")
print("           RT-095 thirteen dialog/error-copy mint;")
print("           see R1's provenance note).")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 88: the party leg rides the shared ladder - transient drops re-dial, deaths stop lying, sends report shortfalls (MJ-8/MN-11 era) ==="
# WHY: the MJ-8 review found the asymmetry: HubCommandTask shipped a 5-rung
# reconnect ladder while SyncPlayTask single-shot it - one Wi-Fi hiccup ended
# the party permanently, the scene just banners on closed/error. The cure:
#   - the rung table moved SHARED into source/lib/SyncPlayProtocol.brs
#     (SyncPlayBackoffMs / SyncPlayMaxAttempts); no task may own it again;
#   - SyncPlayTask dials inside the ladder (DialAndConsume), re-joins the
#     learned group behind every fresh handshake (m.replayCmd/m.needsRejoin),
#     arms OS keepalive (SetKeepAlive(true)) and a 3-tick pong watchdog
#     (m.missedPings), and defers "closed" to true exhaustion;
#   - MN-11: every socket write binds its count - a SHORT write is a desynced
#     stream and is treated as death (ladder), never ignored. Only
#     SendCloseAndDie keeps a best-effort bare send (intentional death).
# NUMBERING: 88 collision-probed at 897376f, highest prior 87.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

problems = []

PROTO = read("source/lib/SyncPlayProtocol.brs")
SYNC = read("components/SyncPlayTask.brs")
HCT = read("components/HubCommandTask.brs")
SXML = read("components/SyncPlayTask.xml")
for name, src in (("source/lib/SyncPlayProtocol.brs", PROTO), ("components/SyncPlayTask.brs", SYNC), ("components/HubCommandTask.brs", HCT), ("components/SyncPlayTask.xml", SXML)):
    if src is None:
        problems.append(f"  {name} - CHECK88: unreadable")

# ---- R1 rungs shared law ----------------------------------------------------
missing1 = []
if PROTO is not None:
    if "    delays = [1000, 2000, 4000, 8000, 16000]" not in PROTO:
        missing1.append("the rung table is not owned by SyncPlayProtocol.brs")
    if "function SyncPlayBackoffMs(attempt as Integer) as Integer" not in PROTO:
        missing1.append("SyncPlayBackoffMs definition lost")
    if "function SyncPlayMaxAttempts() as Integer" not in PROTO:
        missing1.append("SyncPlayMaxAttempts definition lost")
for name, src in (("components/SyncPlayTask.brs", SYNC), ("components/HubCommandTask.brs", HCT)):
    if src is None:
        continue
    if "SyncPlayBackoffMs(" not in src:
        missing1.append(f"{name} no longer waits on the SHARED rung")
    if "SyncPlayMaxAttempts()" not in src:
        missing1.append(f"{name} no longer consults the SHARED cap")
    if "delays = [" in src:
        missing1.append(f"{name} re-inlines its own delays table (the split-rungs asymmetry class)")
if missing1:
    problems.append("  source/lib/SyncPlayProtocol.brs + both tasks - CHECK88 R1: " + "; ".join(missing1) + " (MJ-8: one ladder law for both sockets, owned once)")

# ---- R2 syncplay ladder family ----------------------------------------------
missing2 = []
if SYNC is not None:
    for needle in (
        "m.sock.SetKeepAlive(true)",
        'if m.attempt > 0 then SetState("reconnecting")',
        "outcome = DialAndConsume(host, port, path, bearerToken)",
        "if m.replayCmd <> invalid and m.needsRejoin then",
        "if m.missedPings >= 3 then",
        'else if outcome = "connected" or m.wasEverOpen then',
    ):
        if needle not in SYNC:
            missing2.append(needle)
    if SYNC.count("m.missedPings = 0") != 3:
        missing2.append(f"watchdog reset family is {SYNC.count('m.missedPings = 0')} lines, expected 3 (latch init / per-dial / time_pong)")
    if SYNC.count("m.stopped = true") != 2:
        missing2.append(f"stop latches are {SYNC.count('m.stopped = true')}, expected 2 (leave + close) - an unlatched stop re-dials a left party")
    if 'if m.wsAcceptFailed then' not in SYNC or 'EmitError("local.ws_accept_invalid")' not in SYNC:
        missing2.append("the exhaustion report lost the M-ROKU-14 accept-vs-timeout split (Check 46 law)")
if missing2:
    problems.append("  components/SyncPlayTask.brs - CHECK88 R2: " + "; ".join(missing2) + " (the ladder, keepalive, re-join and watchdog are one cure - MJ-8)")

# ---- R3 send-return custody --------------------------------------------------
missing3 = []
if SYNC is not None:
    for needle in (
        "function SendMessage(typeStr as String, payload as Object) as Boolean",
        "return sent = frame.Count()",
        "function SendTimePing() as Boolean",
        "if sent < 0 or sent < req.Len() then return false",
    ):
        if needle not in SYNC:
            missing3.append(f"SyncPlayTask: {needle}")
    total = SYNC.count("m.sock.Send(")
    bound = SYNC.count("sent = m.sock.Send(")
    if total != 3 or bound != 2:
        missing3.append(f"SyncPlayTask socket-write custody is {bound} bound / {total} total, expected 2/3 (pong + SendMessage bound, SendCloseAndDie best-effort)")
    if 'if not HandleCommand(rc) then running = false' not in SYNC:
        missing3.append("SyncPlayTask: the funnel replay no longer routes a command death to the loop exit (Check 79 pairing)")
if HCT is not None:
    for needle in (
        "if sent < 0 or sent < req.Len() then return false",
        "sent = m.sock.Send(pong, 0, pong.Count())",
    ):
        if needle not in HCT:
            missing3.append(f"HubCommandTask: {needle}")
    if HCT.count("            if m.sock = invalid then") != 1:  # MN-14: body grew the flush; the law (mid-pass death stops feeding) is unchanged
        missing3.append("HubCommandTask: the mid-pass socket-invalid check is gone (a dead pong must stop feeding frames)")
if missing3:
    problems.append("  both task dials - CHECK88 R3: " + "; ".join(missing3) + " (a short write IS death - MN-11)")

# ---- R4 docs -----------------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*88\s*\|.*MJ-8.*MN-11", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK88 R4: row 88 is missing or does not name MJ-8 + MN-11")
chg = read("CHANGELOG.md")
if chg is None or "MN-11" not in chg or "SetKeepAlive" not in chg:
    problems.append("  CHANGELOG.md - CHECK88 R4: the entry must name MN-11 and the keepalive law")
cert = read("docs/certification.md")
if cert is None or not re.search(r"^\|\s*7\.9\s*\|.*MJ-8", cert, re.M):
    problems.append("  docs/certification.md - CHECK88 R4: row 7.9 is missing or does not name MJ-8")

if problems:
    print("  CHECK88: %d pin group(s) broken:" % len(problems))
    for p in problems:
        print(p)
    sys.exit(1)

print('  CHECK88: the party leg rides the shared ladder - rungs owned once, deaths re-dial')
print('           behind the replayed join, keepalive armed, a 3-tick pong watchdog stands in,')
print('           and every socket write reports its own shortfall (MJ-8/MN-11 era).')
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 89: the host seek storm lands as one trailing broadcast - bursts coalesce, the receiver keeps its deadband (MJ-10 era) ==="
# WHY: MJ-10 found every transport-key press seeking AND broadcasting on the
# host while the follower seeked UNCONDITIONALLY per message - holding rewind
# flooded the party with re-buffer storms. The cure is one mechanism:
#   - send side: SeekRelative schedules a 250 ms TRAILING broadcast (latched
#     leading edge m.syncSeekPendingFromMs + re-armed m.syncSeekTimer); play/
#     pause FLUSH the pending burst first; SyncBroadcastSeekMs refuses no-ops;
#   - receive side: a 0.75 s deadband + duplicate-target memory
#     (m.lastRemoteSeekSec) absorb echoes and jitter, and a remote seek that
#     arrives while the LOCAL thumb is mid-burst (m.userSeekInteractMs,
#     NowMs-based) is deferred with ONE bounded retry (ArmSyncSeekRetry), never
#     fought frame-for-frame;
#   - stop custody: StopSyncTaskNow buries both timers and both pendings.
# NUMBERING: 89 collision-probed at a86483c, highest prior 88.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

def sub_body(src, name):
    m = re.search(r"\nsub " + name + r"\(.*?\nend sub\n", src, re.S)
    return m.group(0) if m else None

problems = []

SCENE = read("components/PlayerScene.brs")
if SCENE is None:
    print("  components/PlayerScene.brs - CHECK89: unreadable")
    sys.exit(1)

# ---- R1 send-side coalescing custody --------------------------------------
missing1 = []
sr = sub_body(SCENE, "SeekRelative")
if sr is None or "ScheduleSyncSeekBroadcast(position, newPosition)" not in sr:
    missing1.append("SeekRelative no longer SCHEDULES its broadcast (per-key spam is back)")
if sr is None or "m.userSeekInteractMs = NowMs()" not in sr:
    missing1.append("SeekRelative lost the local-interaction stamp (defer-while-interacting is blind)")
for needle in (
    "sub ScheduleSyncSeekBroadcast(fromSeconds as Float, toSeconds as Float)",
    "    if m.syncSeekPendingFromMs = invalid then\n        m.syncSeekPendingFromMs = Int(fromSeconds * 1000.0)",
    "m.syncSeekTimer.duration = 0.25",
    "SyncBroadcastSeekMs(fromMs, SyncPositionMs())",
    "if fromMs = toMs then return",
):
    if needle not in SCENE:
        missing1.append(needle if len(needle) < 60 else needle[:57] + "...")
if SCENE.count("FlushSyncSeekBroadcast()") != 3:
    missing1.append(f"flush custody is {SCENE.count('FlushSyncSeekBroadcast()')} sites, expected 3 (def + play + pause)")
if "SyncBroadcastSeek(position" in SCENE:
    missing1.append("the direct per-key SyncBroadcastSeek call survived")
if missing1:
    problems.append("  components/PlayerScene.brs - CHECK89 R1: " + "; ".join(missing1) + " (the burst coalescer is the whole cure - MJ-10)")

# ---- R2 receive-side deadband + dup laws -----------------------------------
missing2 = []
arp = sub_body(SCENE, "ApplyRemotePlayback")
if arp is None:
    missing2.append("ApplyRemotePlayback vanished")
else:
    if "pos# = m.videoPlayer.position" not in arp:
        missing2.append("the deadband lost its live-position read")
    if arp.count("seconds# <> m.lastRemoteSeekSec and Abs(seconds# - pos#) >= 0.75 then") != 3:
        missing2.append(f"the dup+deadband gate is {arp.count('seconds# <> m.lastRemoteSeekSec and Abs(seconds# - pos#) >= 0.75 then')} arms, expected 3 (play/pause/seek)")
    if "if NowMs() - m.userSeekInteractMs < 1500& then" not in arp:
        missing2.append("defer-while-interacting is gone - remote seeks fight the local thumb again")
    if "m.pendingRemoteSeekSec = seconds#" not in arp or "ArmSyncSeekRetry()" not in arp:
        missing2.append("the deferred seek lost its retry latch")
if missing2:
    problems.append("  components/PlayerScene.brs - CHECK89 R2: " + "; ".join(missing2) + " (a follower seek is worth 0.75 s of distance - MJ-10 era law)")

# ---- R3 retry + stop custody ------------------------------------------------
missing3 = []
rt = sub_body(SCENE, "OnSyncSeekRetryFired")
if rt is None or "if target# <> m.lastRemoteSeekSec and Abs(target# - m.videoPlayer.position) >= 0.75 then" not in rt:
    missing3.append("the retry skipped re-checking the deadband laws (it would storm on its own)")
if "m.syncSeekRetryTimer.duration = 1" not in SCENE:
    missing3.append("ArmSyncSeekRetry lost its 1 s bound")
sp = sub_body(SCENE, "StopSyncTaskNow")
if sp is None:
    missing3.append("StopSyncTaskNow vanished")
else:
    for needle in (
        "m.syncSeekTimer.control = \"stop\"",
        "    m.syncSeekPendingFromMs = invalid\n",
        "m.syncSeekRetryTimer.control = \"stop\"",
        "    m.pendingRemoteSeekSec = invalid\n",
    ):
        if needle not in sp:
            missing3.append("the leave/close path no longer buries " + needle.strip()[:40])
if SCENE.count("    m.syncSeekPendingFromMs = invalid\n") != 2:
    missing3.append(f"pending-burst wipes are {SCENE.count('    m.syncSeekPendingFromMs = invalid')} statements, expected 2 (flush + stop)")
if missing3:
    problems.append("  components/PlayerScene.brs - CHECK89 R3: " + "; ".join(missing3) + " (a left party must not outlive its timers - MJ-10)")

# ---- R4 docs -----------------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*89\s*\|.*MJ-10", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK89 R4: row 89 is missing or does not name MJ-10")
cl = read("CHANGELOG.md")
if cl is None or "MJ-10" not in cl or "coalesc" not in cl.lower():
    problems.append("  CHANGELOG.md - CHECK89 R4: the entry must name MJ-10 and the coalesced burst")

if problems:
    print("  CHECK89: %d pin group(s) broken:" % len(problems))
    for line in problems:
        print(line)
    sys.exit(1)

print('  CHECK89: the host seek storm lands as one trailing broadcast -')
print('  250 ms coalescing on the sender, deadband + dup memory + bounded defer on the follower')
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 90: the frame stream reassembles and the sync clock is monotonic - FIN custody, the widened RTT window, the NTP-proof base (MN-12/MN-13/MN-15 era) ==="
# WHY: three same-family defects on the WS byte stream and its clock:
#   - MN-12: ParseFrames ignored the FIN bit entirely - a fragmented message
#     (opcode 0 continuation, or any FIN=0 data frame) silently vanished. The
#     cure assembles fragments across calls (m.fragOpcode/m.fragBytes on the
#     protocol object), refuses fragment floods at MaxFrameBytes, drops orphans,
#     and the task resets the state PER DIAL (a fresh handshake cannot inherit
#     a half-frame - Check 88's DialAndConsume owns that reset).
#   - MN-13: MAX_RTT 1000 ms starved the offset estimator on congested links
#     (every sample > 1 s dropped, IsStable never true). Widened to 5000 ms;
#     the two headless pins rotated WITH the law (measured red first).
#   - MN-15: the TimeSync base was wall-clock NowMs() - an NTP step mid-flight
#     forged rtts and poisoned the rolling buffer. NowMonoMs() (roTimespan,
#     with the era's brs-headless invalid-component fallback) is the single
#     base for ping stamps, pong stamps, drift samples and adjusted position;
#     client_time is an opaque echo server-side, so the base swap touches no
#     wire law (phlix-server TimeSync::processPing casts it verbatim).
# NUMBERING: 90 collision-probed at cd0dc0a, highest prior 89.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

problems = []

PROTO = read("source/lib/SyncPlayProtocol.brs")
SYNC = read("components/SyncPlayTask.brs")
TEST = read("tests/unit/SyncPlayProtocol.test.brs")
for name, src in (("source/lib/SyncPlayProtocol.brs", PROTO),
                  ("components/SyncPlayTask.brs", SYNC),
                  ("tests/unit/SyncPlayProtocol.test.brs", TEST)):
    if src is None:
        print(f"  {name} - CHECK90: unreadable")
        sys.exit(1)

# ---- R1 MN-12 FIN custody ----------------------------------------------------
missing1 = []
for needle in (
    "isFIN = (byte0 and 128) = 128",
    "m.fragBytes.Append(payBA)",
    "if m.fragBytes.Count() > m.MaxFrameBytes then",
    "frame = { opcode: m.fragOpcode, payloadBytes: m.fragBytes }",
    "        fragOpcode: invalid",
    "        fragBytes: invalid",
):
    if needle not in PROTO:
        missing1.append(f"protocol: {needle[:56]}")
if PROTO.count("if opcode = 0 then") < 1:
    missing1.append("protocol: the continuation opcode lost its branch")
if "m.proto.fragOpcode = invalid" not in SYNC:
    missing1.append("task: DialAndConsume no longer resets fragment state per dial")
if missing1:
    problems.append("  WS byte stream - CHECK90 R1: " + "; ".join(missing1) + " (a fragmented party message must arrive WHOLE - MN-12)")

# ---- R2 MN-13 RTT window ------------------------------------------------------
missing2 = []
if "MAX_RTT: 5000" not in PROTO:
    missing2.append("protocol lost the widened MAX_RTT (1000 ms starved the estimator)")
if "MAX_RTT: 1000" in PROTO:
    missing2.append("the 1000 ms ceiling re-appeared in the protocol")
if "assertEqual(proto.MAX_RTT, 5000)" not in TEST:
    missing2.append("the headless constant pin was not rotated to 5000")
if "proto.AddPong(0, 0, 6000)" not in TEST:
    missing2.append("the headless rejection probe was not rotated past the widened window")
if missing2:
    problems.append("  rtt custody - CHECK90 R2: " + "; ".join(missing2) + " (the filter must admit honest congestion, refuse junk - MN-13)")

# ---- R3 MN-15 monotonic base ---------------------------------------------------
missing3 = []
for needle in (
    "NowMonoMs: function() as LongInteger",
    'CreateObject("roTimespan")',
    "synchronizedNow# = m.NowMonoMs() + m.currentOffset",
    "nowSec# = m.NowMonoMs() / 1000.0",
):
    if needle not in PROTO:
        missing3.append(f"protocol: {needle[:52]}")
for needle in (
    "t1 = m.proto.NowMonoMs()",
    "m.proto.AddPong(t1, t2, m.proto.NowMonoMs())",
):
    if needle not in SYNC:
        missing3.append(f"task: {needle}")
if "synchronizedNow# = NowMs() + m.currentOffset" in PROTO:
    missing3.append("the adjusted-position math is back on the wall clock")
if "m.proto.AddPong(t1, t2, NowMs())" in SYNC:
    missing3.append("the pong stamp is back on the wall clock")
if missing3:
    problems.append("  sync clock - CHECK90 R3: " + "; ".join(missing3) + " (an NTP step must not forge an rtt or poison the offset buffer - MN-15)")

# ---- R4 docs --------------------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*90\s*\|.*MN-12.*MN-13.*MN-15", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK90 R4: row 90 is missing or does not name MN-12 + MN-13 + MN-15")
cl = read("CHANGELOG.md")
if cl is None or "MN-12" not in cl or "reassembl" not in cl.lower():
    problems.append("  CHANGELOG.md - CHECK90 R4: the entry must name MN-12 and the reassembly law")

if problems:
    print("  CHECK90: %d pin group(s) broken:" % len(problems))
    for line in problems:
        print(line)
    sys.exit(1)

print("  CHECK90: the frame stream reassembles and the sync clock is monotonic -")
print("  FIN custody per dial, the RTT window admits honest congestion, and no")
print("  NTP step can forge an rtt or poison the offset buffer")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 91: the hub relay ships one envelope per recv pass and the party says so out loud - queue/unwrap custody, the reconnecting banner, the play cue (MN-1/MN-14/MN-20 era) ==="
# WHY: three liveness-legibility defects, one era:
#   - MN-14: HubCommandTask field-wrote EVERY decoded pending_command
#     directly; rapid same-field writes collapse under SceneGraph, so a pass
#     carrying several commands delivered (at most) the last. The cure queues
#     per pass (m.pendingEvents) and flushes ONE write - direct when single,
#     {kind:"batch", items:[...]} when many (the SyncPlayTask idiom) - before
#     EVERY loop exit including the MN-11 mid-pass death; PhlixApp unwraps the
#     envelope and dispatches each item through the unchanged M-ROKU-13 guard
#     path (Check 45 R2 follows the unwrap - disclosed rotation, law intact).
#   - MN-20: the scene learned connection liveness ONLY from task events;
#     Check 88's "reconnecting" ladder state had no scene observer. The cure
#     pairs ObserveField("connectionState") with the event observer, banners
#     the ONE transition the event channel cannot announce (reusing the
#     player_sync_status_connecting copy - zero new strings), and un-observes
#     BOTH on the stop path (F13 pairing law).
#   - MN-1: the Detail Play button was a silent no-op for its whole network
#     round-trip; the pending swap to the shipped loading copy (and its
#     retraction on the response) makes the wait visible. CHECK58's
#     sole-writer law covers the DESCRIPTION strip only - untouched.
# NUMBERING: 91 collision-probed at ad2c5e5, highest prior 90.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

problems = []

HCT = read("components/HubCommandTask.brs")
APP = read("components/PhlixApp.brs")
PSC = read("components/PlayerScene.brs")
DSC = read("components/DetailScene.brs")
for name, src in (("components/HubCommandTask.brs", HCT), ("components/PhlixApp.brs", APP),
                  ("components/PlayerScene.brs", PSC), ("components/DetailScene.brs", DSC)):
    if src is None:
        print(f"  {name} - CHECK91: unreadable")
        sys.exit(1)

# ---- R1 HCT queue custody -----------------------------------------------------
missing1 = []
if HCT.count("m.pendingEvents = []") != 2:
    missing1.append(f"queue resets are {HCT.count('m.pendingEvents = []')} sites, expected 2 (per-dial init + post-flush)")
for needle in (
    "m.pendingEvents.Push({",
    "sub FlushPendingEvents()",
    "EmitEvent(m.pendingEvents[0])",
    'EmitEvent({ kind: "batch", items: m.pendingEvents })',
):
    if needle not in HCT:
        missing1.append(needle if len(needle) < 52 else needle[:49] + "...")
loop = re.search(r"for each frame in parsed\.frames[\s\S]*?end for", HCT)
if loop is None or "FlushPendingEvents()" not in loop.group(0):
    missing1.append("the recv loop no longer flushes before its exits (decoded commands die with the pass)")
if re.search(r'EmitEvent\(\{\s*\n\s+kind: "pending_command"', HCT):
    missing1.append("the direct per-frame pending_command field-write is re-grown (coalescing is back)")
if missing1:
    problems.append("  components/HubCommandTask.brs - CHECK91 R1: " + "; ".join(missing1) + " (one pass, one write - MN-14)")

# ---- R2 PhlixApp unwrap --------------------------------------------------------
missing2 = []
for needle in (
    'if data.kind = "batch" then',
    "DispatchPendingHubCommand(item)",
    "DispatchPendingHubCommand(data)",
    "sub DispatchPendingHubCommand(data as Object)",
):
    if needle not in APP:
        missing2.append(needle if len(needle) < 48 else needle[:45] + "...")
if missing2:
    problems.append("  components/PhlixApp.brs - CHECK91 R2: " + "; ".join(missing2) + " (an envelope nobody unwraps is a dropped command - MN-14)")

# ---- R3 PlayerScene state custody -----------------------------------------------
missing3 = []
for needle in (
    'm.syncTask.ObserveField("connectionState", "OnSyncConnectionState")',
    'm.syncTask.UnObserveField("connectionState")',
    "sub OnSyncConnectionState(event as Object)",
    'if s = "reconnecting" then',
    'NotifyPartyEvent(Translate("player_sync_status_connecting"), 4.0!)',
):
    if needle not in PSC:
        missing3.append(needle if len(needle) < 52 else needle[:49] + "...")
if missing3:
    problems.append("  components/PlayerScene.brs - CHECK91 R3: " + "; ".join(missing3) + " (the ladder's reconnecting state must reach the viewer - MN-20)")

# ---- R4 DetailScene play cue ----------------------------------------------------
missing4 = []
for needle in (
    'm.playButton.text = Translate("common_loading")',
    'm.playButton.text = PlayButtonLabel()',  # ROK-S22: restore routes through the resume-aware label (Play / Resume)
):
    if DSC.count(needle) != 1:
        missing4.append(f"{needle} x{DSC.count(needle)}, expected 1")
if missing4:
    problems.append("  components/DetailScene.brs - CHECK91 R4: " + "; ".join(missing4) + " (a pressed button must answer - MN-1)")

# ---- R5 docs ---------------------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*91\s*\|.*MN-14.*MN-20.*MN-1\b", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK91 R5: row 91 is missing or does not name MN-14 + MN-20 + MN-1")
cl = read("CHANGELOG.md")
if cl is None or "MN-14" not in cl or "silent no-op" not in cl:
    problems.append("  CHANGELOG.md - CHECK91 R5: the entry must name MN-14 and the silent no-op it kills")

if problems:
    print("  CHECK91: %d pin group(s) broken:" % len(problems))
    for line in problems:
        print(line)
    sys.exit(1)

print("  CHECK91: the hub relay ships one envelope per recv pass and the party says so out loud -")
print("  queue/unwrap custody, the reconnecting banner, and the play button that answers")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 92: the empty hand gets a nudge and the pre-consent origin meets the gate at boot - copy law, boot re-gate, docblock truth (MN-4/MN-23 era) ==="
# WHY: two last actionable review findings, one shipped copy law and one
# credential-exposure class:
#   - MN-4: the search empty state said only 'No results' - no direction.
#     Every locale's search.no_results now KEEPS its translated sentence as
#     the prefix and adds the nudge (value-only edit x7; the key-set is held
#     so v1.19.0 stands - the MN-27 value-precedent, NOT the MN-26 set move);
#   - MN-23 (secnet): a server_url persisted BEFORE the cleartext-consent law
#     rode boot straight into a credential POST - PhlixApp ShowLogin checked
#     IsServerConnected and dialled past any gate. The boot path now applies
#     the SAME ServerUrlUsesCleartextToRemoteHost predicate the connect form
#     enforces, routing a cleartext-remote origin back to ConnectScene. The
#     ConnectScene docblock that called this a permanent residual is rewritten
#     to truth (its 'pinned by CHECK48' self-claim was stale prose - CHECK48
#     pins the gate and the speakable keys, not the sentence).
# NUMBERING: 92 collision-probed at 6dadd81, highest prior 91.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys, json

def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None

def sub_body(src, name):
    m = re.search(r"\nsub " + name + r"\(.*?\nend sub\n", src, re.S)
    return m.group(0) if m else None

problems = []

OLD_VALS = {
    "en_US": "No results",
    "de_DE": "Keine Ergebnisse",
    "es_ES": "Sin resultados",
    "fr_FR": "Aucun résultat",
    "it_IT": "Nessun risultato",
    "ja_JP": "結果がありません",
    "pt_BR": "Nenhum resultado",
}

# ---- R1 MN-4: every locale kept its sentence and grew the nudge ----------
missing1 = []
for loc, old_v in OLD_VALS.items():
    path = f"locale/{loc}/strings.json"
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, ValueError):
        missing1.append(f"{loc} unreadable")
        continue
    v = cat.get("search", {}).get("no_results", "")
    if v == old_v:
        missing1.append(f"{loc} back to the bare sentence")
    elif not v.startswith(old_v) or len(v) <= len(old_v) + 3:
        missing1.append(f"{loc} lost the keep-the-sentence + nudge law")
if missing1:
    problems.append("  locale catalogs - CHECK92 R1: " + "; ".join(missing1) + " (an empty hand must be told what to try - MN-4 era copy law)")

# ---- R2 MN-23: the boot re-gate inside ShowLogin ---------------------------
APP = read("components/PhlixApp.brs")
if APP is None:
    problems.append("  components/PhlixApp.brs - CHECK92 R2: unreadable")
else:
    sl = sub_body(APP, "ShowLogin")
    if sl is None:
        problems.append("  components/PhlixApp.brs - CHECK92 R2: ShowLogin vanished")
    else:
        missing2 = []
        if "ServerUrlUsesCleartextToRemoteHost(GetServerUrl())" not in sl:
            missing2.append("the cleartext-remote predicate left the boot path")
        else:
            if not sl.find("ServerUrlUsesCleartextToRemoteHost(GetServerUrl())") < sl.find("loginScene = CreateObject"):
                missing2.append("the re-gate no longer precedes LoginScene creation")
        if missing2:
            problems.append("  components/PhlixApp.brs - CHECK92 R2: " + "; ".join(missing2) + " (a pre-consent origin must meet the gate BEFORE credentials ride - MN-23)")

# ---- R3 ConnectScene docblock truth -----------------------------------------
CS = read("components/ConnectScene.brs")
missing3 = []
if CS is None:
    missing3.append("ConnectScene unreadable")
else:
    if "never re-gated on boot" in CS:
        missing3.append("the stale 'never re-gated' residual claim survived")
    if "MN-23" not in CS:
        missing3.append("the docblock no longer names the boot re-gate it shipped")
if missing3:
    problems.append("  components/ConnectScene.brs - CHECK92 R3: " + "; ".join(missing3) + " (docs must tell TODAY's truth - era law)")

# ---- R4 docs trio ----------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*92\s*\|.*MN-4.*MN-23", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK92 R4: row 92 is missing or does not name MN-4 + MN-23")
cl = read("CHANGELOG.md")
if cl is None or "MN-23" not in cl or "re-gate" not in cl:
    problems.append("  CHANGELOG.md - CHECK92 R4: the entry must name MN-23 and the boot re-gate")
cert = read("docs/certification.md")
if cert is None or not re.search(r"^\|\s*7\.10\s*\|.*MN-23", cert, re.M):
    problems.append("  docs/certification.md - CHECK92 R4: row 7.10 is missing or does not name MN-23")

if problems:
    print("  CHECK92: %d pin group(s) broken:" % len(problems))
    for line in problems:
        print(line)
    sys.exit(1)

print("  CHECK92: the empty hand gets a nudge and the pre-consent origin meets the gate at boot -")
print("  keep-the-sentence copy law x7, the ShowLogin predicate re-application, and a docblock")
print("  that finally tells today's truth")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 93: the resume rail says where you left off and the admin meets Live TV without the menu hop (MN-2 + MN-3) ==="
# NUMBERING: 93 is the next-FREE leg (92 taken by the batch-21 era, measured
# on this lane at 562e8a8; 'Check 93'/'CHECK93' appeared nowhere in scripts/,
# tests/ or docs/ before this commit).
#
# WHY THE LEG EXISTS (review roku__casualgamer m2/MN-2 + m3/MN-3, batch 22):
# the "Continue Watching" tiles carried no progress cue at all - the rail
# that promises "where you left off" rendered tiles indistinguishable from
# fresh posters, while the wire rows it builds from DO carry position_ticks
# AND duration_ticks (the server re-attaches both per row; probed this lane).
# And the Live TV family hid behind exactly one door - the AdminScene menu -
# so an admin walked Home -> Admin -> menu row 4 -> channels for the surface
# they reach every day. The cure is chrome the repo already owns: the same
# ShortDescriptionLine2 the Library/Photos/Collection/Audiobook grids render,
# and the same admin-gated header reveal + scene-launch idioms adminButton
# ships. Zero new catalog strings: the percent is numeric chrome and the
# button title rides the shipped common.live_tv key x7.
#
# WHAT IT PINS (fail-loud on unreadable inputs):
#   R1 percent custody - the builder hands every continue tile its second
#      description line from ONE function, and that function keeps every
#      decision the cure made: boxed-type numeric lift on BOTH ticks, the
#      degenerate-pair refusals, the exact ratio, the 1..100 clamps, the
#      Str().trim() era idiom and the "%" suffix.
#   R2 admin-route custody - tvButton ships hidden on the y=36 row in x-order
#      position six; init wires the observer; OnMeResponse reveals it on the
#      SAME isAdmin proof as adminButton and hides it in the fail-closed else
#      branch; OnTvPressed launches LiveTvScene through the four-shape scene
#      launch with requestClose custody; both walks step settings <-> tv <->
#      admin with every edge INTO a hidden-by-default entry gated on m.isAdmin
#      (both sides - a mid-session demotion cannot strand focus by walking it
#      onto a hidden node); FocusHeaderZone restores tv through its .visible
#      gate (the CHECK29 R5 guard family is {admin, tv} since this commit);
#      ApplyXmlChrome speaks the shipped key; README walks the real chain.
#   R3 keyset-held absence law - the cure minted NOTHING, but the census
#      literal is the CURRENT state and rotates with every later set move:
#      en_US rides v1.23.0 and all seven ships hold exactly 409 leaf keys
#      (measured: 387 at batch-21, 384 after the MN-26 removal, 391 after the
#      MJ-2 join-code mint, 392 after the RT-032 concurrent-stream singular
#      mint (w11L1), 396 after the RT-094 four browse-failure mint (w15L9
#      R-B, v1.22.0), 409 after the RT-095 thirteen-key mint (w15L9 R-C,
#      v1.23.0) - this era-pass retires the pre-rotation 387 that
#      the docblock and the PASS narration recited while the pin enforced 384;
#      the audit's OBS-1 drift, fixed at its true home), common.live_tv is
#      present and non-empty in all seven, and no percent-flavored key may
#      squat in any catalog (ban arm - the absence is the point).
#   R4 docs pair - static-checks row 93 names MN-2 + MN-3; the CHANGELOG
#      entry names both, the percent function and the button.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import io, json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def sub_body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


problems = []
LOCALES = ("en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR")

# ---- R1 percent custody (MN-2) -------------------------------------------------
HOME = read("components/HomeScene.brs")
if HOME is None:
    problems.append("  components/HomeScene.brs - CHECK93: unreadable")
    HOME = ""
hc = strip_comment_lines(HOME)
missing1 = []
builder = sub_body(hc, "OnContinueWatchingResponse")
if builder is None or "ShortDescriptionLine2: ContinueWatchPercent(item)" not in builder:
    missing1.append("the continue builder no longer feeds the tile its second description line")
cw = sub_body(hc, "ContinueWatchPercent")
if cw is None:
    missing1.append("ContinueWatchPercent vanished")
else:
    if 'item.DoesExist("position_ticks")' not in cw or 'item.DoesExist("duration_ticks")' not in cw:
        missing1.append("the missing-field refusal left")
    if 'positionType <> "roLongInteger"' not in cw or 'durationType <> "roLongInteger"' not in cw:
        missing1.append("the boxed-type numeric lift (or one of its two arms) left - JSON ticks are not trusted blind")
    if "if duration <= 0 or position <= 0 then return" not in cw:
        missing1.append("the degenerate-pair refusal (zero/negative denominator or position) left")
    if "Int(position / duration * 100.0)" not in cw:
        missing1.append("the percent ratio drifted from the single honest formula")
    if "if percent < 1 then percent = 1" not in cw or "if percent > 100 then percent = 100" not in cw:
        missing1.append("a 1..100 clamp left - a started row shows at least 1, a corrupt ratio never shows 400")
    if 'Str(percent).trim() + "%"' not in cw:
        missing1.append("the Str().trim() era stringing or its % suffix drifted")
if missing1:
    problems.append("  components/HomeScene.brs - CHECK93 R1: " + "; ".join(missing1) + " (the rail may not lie about where you left off - MN-2)")

# ---- R2 admin-route custody (MN-3) ----------------------------------------------
missing2 = []
XMLS = read("components/HomeScene.xml")
if XMLS is None:
    missing2.append("HomeScene.xml unreadable")
else:
    row = [(int(m.group(1)), m.group(2)) for m in
           re.finditer(r'<Button[^>]*?translation="\[(\d+),36\]"[^>]*?id="(\w+)"', XMLS)]
    cols = [nid[:-len("Button")] for _, nid in sorted(row)]
    if cols != ["search", "forYou", "favorites", "collections", "settings", "tv", "admin"]:
        missing2.append("the header x-order is %s, not search/forYou/favorites/collections/settings/tv/admin" % cols)
    tag = re.search(r'<Button[^>]*?id="tvButton"[^>]*/?>', XMLS)
    if tag is None:
        missing2.append("tvButton vanished from the header")
    else:
        if 'visible="false"' not in tag.group(0):
            missing2.append("tvButton no longer ships visible=\"false\" (the isAdmin gate only hides the step)")
        if 'text="Live TV"' not in tag.group(0):
            missing2.append("tvButton lost its en-fallback title")
if HOME:
    if 'm.tvButton.ObserveField("buttonSelected", "OnTvPressed")' not in hc:
        missing2.append("the tvButton buttonSelected observer is unwired (a focused dead button)")
    om = sub_body(hc, "OnMeResponse")
    if om is None:
        missing2.append("OnMeResponse vanished")
    else:
        if "if m.isAdmin and m.tvButton <> invalid then m.tvButton.visible = true" not in om:
            missing2.append("the isAdmin reveal arm for tvButton left - the hop may only ride the SAME proof as the Admin entry")
        hide = om.find("SetIsAdmin(false)")
        tvhide = om.find("m.tvButton.visible = false")
        if hide == -1 or tvhide == -1 or tvhide < hide:
            missing2.append("the fail-closed else branch no longer hides tvButton after SetIsAdmin(false)")
    otv = sub_body(hc, "OnTvPressed")
    if otv is None:
        missing2.append("OnTvPressed vanished")
    else:
        for needle, why in (
            ('CreateObject("roSGNode", "LiveTvScene")', "the direct Live TV scene launch is no longer the destination"),
            ("m.top.Append(scene)", "the launch bypasses the append custody"),
            ('scene.ObserveField("requestClose", "OnChildRequestClose")', "the child close signal is unwired (a Back that dies on the floor)"),
            ("scene.SetFocus(true)", "the launched scene never takes focus"),
        ):
            if needle not in otv:
                missing2.append(why)
    RIGHT = None
    m = re.search(r'if key = "right" and m\.currentRail = "search" then(.*?)else if key = "down"', hc, re.S)
    LEFT = None
    m2 = re.search(r'if key = "left" and m\.currentRail = "search" then(.*?)else if key = "right"', hc, re.S)
    if m is None or m2 is None:
        missing2.append("the header walk branches drifted (the tv steps can no longer be verified)")
    else:
        RIGHT, LEFT = m.group(1), m2.group(1)
        for src, dst, text, label in (
            ("settings", "tv", RIGHT, "right"),
            ("tv", "admin", RIGHT, "right"),
            ("admin", "tv", LEFT, "left"),
            ("tv", "settings", LEFT, "left"),
        ):
            edge = re.search(r'm\.headerCol = "' + src + r'"([^\n]*)\n\s*m\.' + dst + r'Button\.SetFocus\(true\)\s*\n\s*m\.headerCol = "' + dst + '"', text)
            if edge is None:
                missing2.append("the %s step %s->%s vanished from the header walk" % (label, src, dst))
            elif dst in ("tv", "admin") and "m.isAdmin" not in edge.group(1):
                missing2.append("the %s step into %s is not gated on m.isAdmin - focus can land on a hidden button" % (label, dst))
    fhz = sub_body(HOME, "FocusHeaderZone")
    if fhz is None or not re.search(r'm\.headerCol = "tv" and m\.tvButton <> invalid and m\.tvButton\.visible then\s*\n\s*m\.tvButton\.SetFocus\(true\)', fhz, re.S):
        missing2.append("FocusHeaderZone cannot restore tv through its .visible gate - a grid->header return after a demotion would strand focus on a hidden node")
    if not re.search(r'findNode\("tvButton"\)[\s\S]{0,80}n\.text = Translate\("common_live_tv"\)', HOME):
        missing2.append("ApplyXmlChrome no longer speaks the shipped key - a chrome literal the mirror law convicts")
README = read("README.md")
if README is None:
    missing2.append("README.md unreadable")
else:
    if "`Search ↔ For You ↔ Favorites ↔ Collections ↔ Settings ↔ Live TV ↔ Admin`" not in README:
        missing2.append("the README header chain line does not walk the real seven-title x-order")
    if "up to seven buttons" not in README:
        missing2.append("the README header section still counts the row wrong")
if missing2:
    problems.append("  components/HomeScene + README - CHECK93 R2: " + "; ".join(missing2) + " (the admin hop must exist, speak, and stay gated - MN-3)")

# ---- R3 keyset-held absence law -------------------------------------------------
missing3 = []
for loc in LOCALES:
    path = f"locale/{loc}/strings.json"
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, ValueError):
        missing3.append(f"{loc} unreadable")
        continue
    leaves = {s + "_" + k: v for s, sub in cat.items()
              if s != "_metadata" and isinstance(sub, dict)
              for k, v in sub.items() if isinstance(v, str)}
    if len(leaves) != 432:
        missing3.append(f"{loc} carries {len(leaves)} leaf keys, not the measured 432 (ROK-50 +2 transcode_preparing keys, ROK-S2 +1 err_track_unavailable key, ROK-S21 +18 player-island/season keys, ROK-S22 +2 common.resume/player.resuming_from keys) - the keyset moved")
    if not leaves.get("common_live_tv", "").strip():
        missing3.append(f"{loc} lost the shipped common_live_tv value")
    percent_keys = [k for k in leaves if "percent" in k.lower() or "progress_" in k.lower()]
    if percent_keys:
        missing3.append(f"{loc} re-minted progress copy {percent_keys} - the percent is NUMERIC chrome, no key may exist")
en = None
try:
    with open("locale/en_US/strings.json", encoding="utf-8") as f:
        en = json.load(f)
except (OSError, ValueError):
    missing3.append("en_US unreadable for the version pin")
if en is not None and en.get("_metadata", {}).get("version") != "1.23.0":
    missing3.append("en_US _metadata.version is not 1.23.0 - the census rides the CURRENT set (the literal rotates with every mint: MJ-2 at v1.20.0, RT-032 at v1.21.0, RT-094 at v1.22.0, RT-095 at v1.23.0; batch-22 itself minted NOTHING and its absence law is what the census proves)")
if missing3:
    problems.append("  locale catalogs - CHECK93 R3: " + "; ".join(missing3) + " (batch 22 ships ZERO new strings; the census proves the absence)")

# ---- R4 docs pair ----------------------------------------------------------------
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*93\s*\|.*MN-2\b.*MN-3\b", docs, re.M):
    problems.append("  docs/static-checks.md - CHECK93 R4: row 93 is missing or does not name MN-2 + MN-3")
cl = read("CHANGELOG.md")
if cl is None or not re.search(r"MN-2\b", cl) or not re.search(r"MN-3\b", cl) or "ContinueWatchPercent" not in cl or "tvButton" not in cl:
    problems.append("  CHANGELOG.md - CHECK93 R4: the entry must name MN-2 + MN-3, the percent function and the button")

if problems:
    print("  CHECK93: %d pin group(s) broken:" % len(problems))
    for line in problems:
        print(line)
    sys.exit(1)

print("  CHECK93: the resume rail says where you left off and the admin meets Live TV")
print("  in one hop - percent custody, the gated tv walk with hidden-entry law on both")
print("  sides, the 409-key v1.23.0 absence census, and the docs pair")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# =============================================================================
# CHECK 94 (MJ-2, deferred lane): JOIN-BY-CODE CUSTODY - digest-only gate on
# the WebSocket, a panel-owned code form, and the seven-key set move.
#
# Review roku__casualgamer deferred MJ-2 because the Live Watch Together panel
# could only join what the picker LISTED, and a password-protected room was a
# dead end (the join command carried no gate at all). The cure rides FROZEN
# wire: syncplay_group_join already carries password_hash (SPEC section 4 -
# unsalted SHA-256, lowercase 64-hex, compared VERBATIM; the plaintext arm is
# DEPRECATED and "new clients MUST NOT send password on the WebSocket"), and
# group ids ARE the shareable sp_* codes the other devices display. What had
# to be built was CLIENT CUSTODY, not a contract:
#   R1 join-arm wire law - the SyncPlayTask join branch forwards the digest
#      ONLY through the canonical client gate (IsCanonicalPasswordHash) and
#      the quoted plaintext key "password" stays extinct in that branch (the
#      masked-code view: comments reciting the class buy nothing). In
#      PlayerScene the join-by-code sub computes the digest via
#      SyncPlayPasswordHash, lands a digest-less firmware on the cataloged
#      refusal copy (syncplay_status_hash_unavailable), and NEVER lifts the
#      raw password into the command dict (cmd.password= and a "password"
#      dict key both convict).
#   R2 digest-leaf custody - Utilities' SyncPlayPasswordHash is the
#      roEVPDigest(Setup("sha256")) + LCase + canonical-recheck ladder,
#      fail-closed "" on every inability path (no component, Setup refusal,
#      junk shape) and never sha1/md5/roEncryptor; IsCanonicalPasswordHash
#      scans exactly 64 chars with the protocol's range-compare idiom - the
#      Asc( call is pinned EXTINCT here as SHAPE custody - this gate keeps
#      the one IsHex40-family range-compare idiom its headless pins byte-
#      assert (Asc is real: bsc models it, brs implements it; the era 'HAS
#      NO Asc()' generalization is FALSE and retracted by the 2026-11-04
#      CHANGELOG correction - the ban stands). The
#      truth table ships in tests/unit/SyncPlayJoinCode.test.brs.
#   R3 panel ownership - the code form is a VISIBILITY SWAP inside syncPanel
#      (no new overlay, no focus stack): all eight nodes ship; both inputs
#      ride maxLength (CHECK87 R3's census); the password arm carries the
#      REAL secureMode="true" field (MJ-14 truth - secure= convicts); the
#      trio's buttonSelected observers are Init-paired with the teardown
#      unobserve; ToggleSyncPanel and CloseSyncPanel both fold to list mode
#      (the form is per-open state); ShowSyncListMode wipes both fields
#      (typed custody); the panel key branch unwinds code mode BEFORE
#      closing the whole panel; and ApplyXmlChrome speaks every literal
#      (CHECK25's net).
#   R4 the seven-key set move - syncplay's code_hint/code_label/code_missing/
#      join/join_with_code/password_label/status_hash_unavailable are present
#      and non-empty in all seven ships and the en copy is pinned verbatim;
#      the set rode v1.20.0 when this leg minted it - CHECK48 R3, CHECK87 R1
#      and CHECK93 R3's literals rotated to it in this SAME commit (a bump
#      that skips a pin site is not a bump, it is a drift) and the 391-leaf
#      census moved with them (387 batch-21, 384 MN-26, 391 MJ-2 - the OBS-1
#      recital-drift the audit named died in that rotation, disclosed). The
#      ride is v1.23.0 since the RT-095 thirteen dialog/error-copy mint
#      (w15L9 R-C, 2026-11-10, 409 leaves; v1.22.0 rode the RT-094
#      browse-failure mint, w15L9 R-B; v1.21.0 rode the RT-032 singular mint,
#      w11L1 2026-11-09); all four current-ride legs - CHECK48
#      R3, CHECK87 R1, CHECK93 R3 and this R4 - rotate together on every set
#      move, which is exactly what this leg's own law demands.
#   R5 docs pair + README truth - row 94 exists naming MJ-2; the CHANGELOG
#      names MJ-2, the digest function and the button; the README's SyncPlay
#      block no longer LIES: the convicted "simply fail to join" clause and
#      the stale "no group-id typing on the TV" claim are extinct, "Join With
#      Code" is walked, and the pre-existing MJ-8-era "no auto re-join"
#      drift (this lane's audit find, unrelated to MJ-2 but retired here,
#      disclosed) stays retired.
# =============================================================================
echo "=== Check 94: join-by-code custody - digest-only gate, panel-owned form, seven-key mint (MJ-2 deferred) ==="
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import io
import json
import os
import re
import sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

LOCALES = ("en_US", "de_DE", "es_ES", "fr_FR", "it_IT", "ja_JP", "pt_BR")
MINTED = {
    "code_hint": "Starts with sp_\u2026",
    "code_label": "Group Code",
    "code_missing": "Enter the group code first",
    "join": "Join",
    "join_with_code": "Join With Code",
    "password_label": "Password (optional)",
    "status_hash_unavailable": "This device cannot unlock a password-protected group.",
}

problems = []


def read(path):
    try:
        return io.open(path, encoding="utf-8").read()
    except OSError as err:
        problems.append(f"  {path} - CHECK94 R0: unreadable: {err} - the pin cannot run vacuously")
        return None


def mask_brs_comments(text):
    # Same contract as Check 20/63's masker: a single quote outside a double-
    # quoted string opens a comment that runs to end of line; comment runs
    # become spaces of identical length. Prose that QUOTES a convicted shape
    # can never convict.
    out = []
    for line in text.splitlines(keepends=True):
        in_str = False
        chars = list(line)
        i = 0
        while i < len(chars):
            c = chars[i]
            if c == '"':
                in_str = not in_str
            elif c == "'" and not in_str:
                for j in range(i, len(chars)):
                    if chars[j] not in ("\n", "\r"):
                        chars[j] = " "
                break
            i += 1
        out.append("".join(chars))
    return "".join(out)


def sub_body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.M | re.S)
    return m.group(1) if m else None


# ---- R1 join-arm wire law ------------------------------------------------------
r1 = []
task = read("components/SyncPlayTask.brs")
if task is not None:
    tmask = mask_brs_comments(task)
    jm = re.search(r'else if kind = "join" then(.*?)\n    else if', tmask, re.S)
    if jm is None:
        r1.append("the join branch vanished from HandleCommand - the wire law lost its subject")
    else:
        body = jm.group(1)
        if "password_hash" not in body:
            r1.append("the join branch no longer forwards password_hash - protected joins are dead ends again (MJ-2 regression)")
        if "IsCanonicalPasswordHash(" not in body:
            r1.append("the join branch forwards a digest the client never canonical-checked - the server refuses non-canonical shapes, so the malformed carry would silently eat the gate")
        if re.search(r'"password"', body):
            r1.append('the quoted plaintext key "password" re-appeared in the join branch - SPEC section 4: new clients MUST NOT send password on the WebSocket')
        if re.search(r"\bpayload\.password\b", body):
            r1.append("payload.password re-grown in the join branch - the plaintext gate never rides the socket")
scene = read("components/PlayerScene.brs")
if scene is not None:
    smask = mask_brs_comments(scene)
    cbody = sub_body(smask, "OnSyncCodeJoinPressed")
    if cbody is None:
        r1.append("OnSyncCodeJoinPressed is gone - the join-by-code arm lost its owner")
    else:
        if "SyncPlayPasswordHash(" not in cbody:
            r1.append("the code form no longer digests the password through SyncPlayPasswordHash")
        if "password_hash" not in cbody:
            r1.append('cmd.password_hash vanished - the join command carries no gate')
        if 'syncplay_status_hash_unavailable' not in cbody:
            r1.append("the digest-less fail-closed arm (syncplay_status_hash_unavailable) vanished - a device that cannot compute the gate must REFUSE the join, not attempt it ungated")
        if re.search(r"\bcmd\.password\b(?!_)", cbody):
            r1.append("the raw password was lifted into the command dict - plaintext custody defect (MJ-2's whole point)")
        if re.search(r'\bpassword\s*:', cbody):
            r1.append('a "password:" dict literal re-grew in the code-join arm')
if r1:
    problems.append("  join-arm wire - CHECK94 R1: " + "; ".join(r1))

# ---- R2 digest-leaf custody ----------------------------------------------------
r2 = []
util = read("source/lib/Utilities.brs")
if util is not None:
    umask = mask_brs_comments(util)
    hbody = sub_body(umask, "SyncPlayPasswordHash")
    gbody = sub_body(umask, "IsCanonicalPasswordHash")
    if hbody is None:
        r2.append("SyncPlayPasswordHash vanished - the digest leaf lost its body")
    else:
        for tok, why in (
            ('CreateObject("roEVPDigest")', "the platform digest component (the VerifyHandshakeAccept sibling)"),
            ('Setup("sha256")', 'Setup("sha256") - the SPEC digest, not any other'),
            ("LCase(", "lowercase normalization to the canonical form the server byte-compares"),
            ("IsCanonicalPasswordHash(", "the canonical recheck before anything returns"),
        ):
            if tok not in hbody:
                r2.append(f"SyncPlayPasswordHash lost {tok} ({why})")
        for banned in ('Setup("sha1")', '"md5"', "roEncryptor"):
            if banned in hbody:
                r2.append(f"SyncPlayPasswordHash computes with {banned} - wrong digest family")
    if gbody is None:
        r2.append("IsCanonicalPasswordHash vanished - the client-side canonical gate is gone")
    else:
        if "<> 64" not in gbody or 'c >= "a" and c <= "f"' not in gbody:
            r2.append("IsCanonicalPasswordHash no longer scans exactly 64 lowercase hex chars (range-idiom shape)")
        if "Asc(" in gbody:
            r2.append("Asc( re-grew in the canonical gate - the leaf must keep its pinned IsHex40-family range-compare shape; this ban is SHAPE custody, not a platform claim (Asc is real: bsc models it, brs implements it, four live Utilities sites call it) - the MJ-2 lane's own in-lane headless crash belonged to the brs typed-formal class its EXCLUDED_TESTS comments document; the era prose generalized that event into 'HAS NO Asc()' and the 2026-11-04 CHANGELOG correction retracts the generalization, not the ban")
if r2:
    problems.append("  digest leaves - CHECK94 R2: " + "; ".join(r2))

# ---- R3 panel ownership ---------------------------------------------------------
r3 = []
xml = read("components/PlayerScene.xml")
if xml is not None:
    xclean = re.sub(r"<!--.*?-->", " ", xml, flags=re.S)
    for node_id in ("syncJoinCodeButton", "syncCodeGroup", "syncCodeLabel", "syncCodeInput",
                    "syncCodePasswordLabel", "syncCodePasswordInput", "syncCodeJoinButton",
                    "syncCodeCancelButton"):
        if f'id="{node_id}"' not in xclean:
            r3.append(f"{node_id} vanished from syncPanel")
    def tag_of(nid):
        for tm in re.finditer(r"<[A-Za-z]+\b[^>]*>", xclean, re.S):
            if f'id="{nid}"' in tm.group(0):
                return tm.group(0)
        return ""
    tin = tag_of("syncCodeInput")
    tpin = tag_of("syncCodePasswordInput")
    if "maxLength" not in tin:
        r3.append("syncCodeInput lost maxLength (the CHECK87 R3 census law)")
    if "maxLength" not in tpin or 'secureMode="true"' not in tpin:
        r3.append('syncCodePasswordInput lost maxLength or the REAL secureMode="true" field (MJ-14 truth)')
    if re.search(r"\bsecure=", tin + tpin):
        r3.append("the dead secure= attribute re-grew (Check 74 R1 family)")
if scene is not None:
    sinit = re.search(r"sub Init\(\)(.*?)^end sub", scene, re.S | re.M)
    sinit = sinit.group(1) if sinit else ""
    for nid in ("syncJoinCodeButton", "syncCodeGroup", "syncCodeInput", "syncCodePasswordInput",
                "syncCodeJoinButton", "syncCodeCancelButton"):
        if f'FindNode("{nid}")' not in sinit:
            r3.append(f"Init no longer wires {nid}")
    for cb, nid in (("OnSyncJoinCodePressed", "syncJoinCodeButton"),
                    ("OnSyncCodeJoinPressed", "syncCodeJoinButton"),
                    ("OnSyncCodeCancelPressed", "syncCodeCancelButton")):
        if f'{nid}.ObserveField("buttonSelected", "{cb}")' not in scene:
            r3.append(f"the {cb} observer pair is broken ({nid})")
        if f'{nid}.UnObserveField("buttonSelected")' not in scene:
            r3.append(f"{nid} is observed but never un-observed - the teardown pairing law (F13 block) is broken")
    for tok, why in (
        ("sub ShowSyncCodeMode", "the code-mode visibility swap"),
        ("sub ShowSyncListMode", "the list-mode visibility swap"),
    ):
        if tok not in scene:
            r3.append(f"{tok} is gone ({why})")
    tp = sub_body(scene, "ToggleSyncPanel")
    cs = sub_body(scene, "CloseSyncPanel")
    if tp is None or "ShowSyncListMode()" not in tp:
        r3.append("ToggleSyncPanel no longer folds to list mode on open")
    if cs is None or "ShowSyncListMode()" not in cs:
        r3.append("CloseSyncPanel no longer folds to list mode - a stale mid-form visibility leaks into the next open")
    sl = sub_body(scene, "ShowSyncListMode")
    if sl is None or 'syncCodePasswordInput.text = ""' not in sl:
        r3.append("ShowSyncListMode no longer wipes the password field (typed custody)")
    ok = sub_body(scene, "OnKeyEvent")
    if ok is None or "if m.syncCodeMode then" not in ok:
        r3.append("the panel key branch no longer unwinds code mode BEFORE closing the whole panel")
    chrome = sub_body(scene, "ApplyXmlChrome")
    if chrome is None:
        r3.append("ApplyXmlChrome vanished - CHECK25's override path died with it")
    else:
        for tok in ('Translate("syncplay_join_with_code")', 'Translate("syncplay_code_label")',
                    'Translate("syncplay_code_hint")', 'Translate("syncplay_password_label")',
                    'Translate("syncplay_join")', 'Translate("common_cancel")'):
            if tok not in chrome:
                r3.append(f"ApplyXmlChrome no longer speaks {tok}")
if r3:
    problems.append("  syncPanel form - CHECK94 R3: " + "; ".join(r3))

# ---- R4 the seven-key set move ---------------------------------------------------
r4 = []
for loc in LOCALES:
    path = f"locale/{loc}/strings.json"
    try:
        cat = json.load(io.open(path, encoding="utf-8"))
    except (OSError, ValueError) as err:
        r4.append(f"{path} unreadable: {err}")
        continue
    sec = cat.get("syncplay", {})
    for key in sorted(MINTED):
        v = sec.get(key)
        if not isinstance(v, str) or v.strip() == "":
            r4.append(f"{path}: syncplay.{key} missing or empty")
    if cat.get("_metadata", {}).get("version") != "1.23.0":
        r4.append(f"{path}: _metadata.version is not 1.23.0 - the MJ-2 mint rode v1.20.0, the RT-032 singular-key mint rode v1.21.0 and the RT-094 browse-failure mint rode v1.22.0; the RT-095 thirteen-key dialog/error-copy mint rides it")
en = None
try:
    en = json.load(io.open("locale/en_US/strings.json", encoding="utf-8"))
except (OSError, ValueError):
    r4.append("en_US unreadable for the copy pin")
if en is not None:
    for key, val in MINTED.items():
        if en.get("syncplay", {}).get(key) != val:
            r4.append(f"en_US syncplay.{key} drifted off the ratified copy")
    keys = list(en.get("syncplay", {}).keys())
    if keys != sorted(keys):
        r4.append("en_US syncplay section is no longer alphabetical (the set-sort law)")
if r4:
    problems.append("  locale mint - CHECK94 R4: " + "; ".join(r4))

# ---- R5 docs pair + README truth ---------------------------------------------------
r5 = []
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*94\s*\|.*MJ-2\b", docs, re.M):
    r5.append("docs/static-checks.md row 94 is missing or does not name MJ-2")
cl = read("CHANGELOG.md")
if cl is None or "MJ-2" not in cl or "SyncPlayPasswordHash" not in cl or "Join With Code" not in cl:
    r5.append("CHANGELOG.md must name MJ-2, the digest function and the button")
readme = read("README.md")
if readme is not None:
    for banned, why in (
        ("simply fail to join", "the retired MJ-2 dead-end claim"),
        ("no group-id typing on the TV", "the pre-code-entry Usage claim MJ-2 made false"),
        ("no auto re-join", "the MJ-8-era drift this lane's audit caught (ladder law ships)"),
    ):
        if banned in readme:
            r5.append(f'README re-grew "{banned}" - {why}')
    if "Join With Code" not in readme:
        r5.append("README no longer walks the Join With Code surface")
if r5:
    problems.append("  docs/README - CHECK94 R5: " + "; ".join(r5))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK94: %d conviction(s) - the deferred MJ-2 laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK94: a code from any device opens the room - digest-only custody,")
print("  the panel-owned form, the seven-key mint (born v1.20.0, riding v1.23.0),")
print("  and the honest README")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 95: end-of-playback truth - real-end completion, the up-next wrapper, mode-aware boot retry, the single HLS gate, parsed skip markers, windowed lazy loading (RT-089 RT-090 RT-001 RT-002 RT-003 RT-004) ==="
# NUMBERING: 95 is the next-FREE leg (94 taken by the MJ-2 era, measured on
# this lane at 53f11ac; 'Check 95'/'CHECK95' appear nowhere in scripts/,
# tests/ or docs/ before this commit).
#
# WHY THE LEG EXISTS (review lineage roku__crossfe C1 + roku__gameux C1 +
# roku__casualgamer M1 + roku__exploiter M3/M4 + roku__crossfe m3, wave w01):
# six shipped defects shared one shape - the client trusted a shape it never
# verified. The R4.4 completion fallback fired at 95% of the runtime (cutting
# the last five minutes off every film, skipping the completeSession POST
# because it pre-set the very flag CompleteSession owns, tearing the scene
# down under the Up Next card, and re-tripping instantly on resume - an
# unwatchable loop); the up-next handlers read the WRAPPER envelope
# {items: [...]} that GET /users/me/next-up answers as if it were the bare
# item (phantom rail tile, dead select key, title-less card that stranded
# the post-playback screen when Play-Now dismissed itself without launching);
# the boot retry button always ran the direct-mode auth check, wiping valid
# hub sessions to a false "Session Expired" (Init's mode branch did not
# survive into the retry path); the HLS lane took server playlist URLs
# straight into the Video node while only the direct lane enforced the
# MJ-19/MN-24 gates; skip markers rode raw from the wire into typed float
# comparisons and the skipRequested field (render-thread Type Mismatch class);
# and ActivateVisibleRange walked the ENTIRE content tree on every scroll
# event. Every cure below is shape custody, and this leg pins the shapes.
#
# WHAT IT PINS (fail-loud on unreadable inputs):
#   R1 real-end completion - the OnPositionUpdate fallback gates on
#      duration-position < 1 (never the retired 0.95 fraction), latches once
#      through m.endOfPlaybackFallbackFired, and routes EXACTLY like the
#      firmware "finished" branch: isPlaying=false, StopPlayback(),
#      ShowUpNextCard() - and neither sessionCompleteReported=true nor
#      ClosePlayer() may appear in that body again (CompleteSession owns the
#      flag; the card owns the scene).
#   R2 wrapper custody - both OnUpNextResponse handlers (HomeScene rail,
#      PlayerScene card) read resp.data.items and keep the envelope out of
#      the item slot; the ApiTask getNextUp docblock tells the wrapper truth
#      and the retired "direct item object" claim may not regrow.
#   R3 boot-retry mode law - OnBootRetryButton mirrors Init: hub mode retried
#      through StartHubAuthCheck (bare hub url), direct through StartAuthCheck.
#   R4 single HLS choke - PlayHls admits a URL only through PlayHlsUrlRefused,
#      which carries the MJ-19 IsStreamUrlAdmissible call AND the MN-24
#      scheme refusal, and the gate must precede the ContentNode creation.
#   R5 marker parse custody - both SkipButton implementations (live component
#      + headless factory) lift every skip_* value through a boxed-numeric
#      reader (ReadLong idiom, components/SyncPlayTask.brs) storing invalid
#      for everything non-numeric, and PlayerScene writes the typed markers
#      field only from a roAssociativeArray check.
#   R6 windowed walk - ActivateVisibleRange iterates the visible column
#      window with a GetChildCount-bounded for-loop; the full 0..invalid
#      while-walk may not regrow.
#   R7 docs pair - static-checks row 95 names the era; the CHANGELOG entry
#      names RT-089 and RT-090 and the two new gate functions.
# Zero new catalog keys: every user-visible copy here rides keys the ship
# already has (the CHECK93 R3 census stays untouched BY CONSTRUCTION).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as err:
        return None


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def sub_body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


problems = []

# ---- R1 real-end completion (RT-089) --------------------------------------------
PSRC = read("components/PlayerScene.brs")
if PSRC is None:
    problems.append("  components/PlayerScene.brs - CHECK95: unreadable")
    PSRC = ""
psc = strip_comment_lines(PSRC)
r1 = []
opp = sub_body(psc, "OnPositionUpdate")
if opp is None:
    r1.append("OnPositionUpdate vanished")
else:
    if "0.95" in opp:
        r1.append("the retired 95%-fraction gate is back")
    if "duration - position < 1" not in opp:
        r1.append("the real-end gate (duration - position < 1) left")
    if "m.endOfPlaybackFallbackFired" not in opp:
        r1.append("the once-only end-fallback latch left")
    if "m.sessionCompleteReported = true" in opp:
        r1.append("the fallback pre-sets sessionCompleteReported again - CompleteSession owns that flag")
    if "ClosePlayer()" in opp:
        r1.append("the fallback tears the scene down with ClosePlayer again - route it through ShowUpNextCard")
    if "StopPlayback()" not in opp or "ShowUpNextCard()" not in opp:
        r1.append("the fallback no longer routes through the finished-state path (StopPlayback + ShowUpNextCard)")
    if "m.isPlaying = false" not in opp:
        r1.append("the fallback no longer mirrors the finished branch's isPlaying reset")
if r1:
    problems.append("  end-of-playback fallback - CHECK95 R1: " + "; ".join(r1))

# ---- R2 wrapper custody (RT-090) ------------------------------------------------
r2 = []
HSRC = read("components/HomeScene.brs")
if HSRC is None:
    problems.append("  components/HomeScene.brs - CHECK95: unreadable")
    HSRC = ""
hb = sub_body(strip_comment_lines(HSRC), "OnUpNextResponse")
if hb is None:
    r2.append("HomeScene OnUpNextResponse vanished")
elif "resp.data.items" not in hb:
    r2.append("the HomeScene rail stopped reading the {items: [...]} wrapper")
pb = sub_body(psc, "OnUpNextResponse")
if pb is None:
    r2.append("PlayerScene OnUpNextResponse vanished")
else:
    if "resp.data.items" not in pb:
        r2.append("the PlayerScene card stopped reading the {items: [...]} wrapper")
    if "m.upNextItem = resp.data" in pb:
        r2.append("the envelope is being stored as the item again")
AT = read("components/ApiTask.brs")
if AT is None:
    problems.append("  components/ApiTask.brs - CHECK95: unreadable")
    AT = ""
arm = AT[AT.find('req.op = "getNextUp"'):] if 'req.op = "getNextUp"' in AT else ""
arm = arm[:arm.find('else if req.op')] if 'else if req.op' in arm else arm
if "{items:" not in arm:
    r2.append("the getNextUp docblock does not name the wrapper shape")
if "direct item object" in arm:
    r2.append("the retired 'direct item object' contract claim regrew in ApiTask")
if r2:
    problems.append("  up-next wrapper custody - CHECK95 R2: " + "; ".join(r2))

# ---- R3 boot-retry mode law (RT-001) ----------------------------------------------
APP = read("components/PhlixApp.brs")
if APP is None:
    problems.append("  components/PhlixApp.brs - CHECK95: unreadable")
    APP = ""
rb = sub_body(strip_comment_lines(APP), "OnBootRetryButton")
r3 = []
if rb is None:
    r3.append("OnBootRetryButton vanished")
else:
    if 'GetConnectionKind() = "hub"' not in rb:
        r3.append("the retry no longer mirrors Init's mode branch")
    if "StartHubAuthCheck()" not in rb:
        r3.append("hub mode retries still ride the relay-base StartAuthCheck - the false Session Expired class")
if r3:
    problems.append("  boot-retry mode law - CHECK95 R3: " + "; ".join(r3))

# ---- R4 single HLS choke (RT-002) -------------------------------------------------
r4 = []
ph = sub_body(psc, "PlayHls")
gate = sub_body(psc, "PlayHlsUrlRefused")
if ph is None:
    r4.append("PlayHls vanished")
else:
    if "PlayHlsUrlRefused(" not in ph:
        r4.append("PlayHls no longer admits URLs through the shared refusal gate")
    if gate is not None:
        if ph.find("CreateObject(\"roSGNode\", \"ContentNode\")") < 0 or \
           ph.find("PlayHlsUrlRefused(") > ph.find("CreateObject(\"roSGNode\", \"ContentNode\")"):
            r4.append("the refusal gate no longer PRECEDES the ContentNode creation")
if gate is None:
    r4.append("PlayHlsUrlRefused vanished")
else:
    if "IsStreamUrlAdmissible(" not in gate:
        r4.append("the MJ-19 TLS-boundary gate left the HLS lane")
    if '<> "https:"' not in gate:
        r4.append("the MN-24 scheme refusal left the HLS lane")
    if "player_err_transcode_no_stream" not in ph:
        r4.append("refusals no longer reuse the existing no-stream dialog")
if r4:
    problems.append("  HLS single choke - CHECK95 R4: " + "; ".join(r4))

# ---- R5 marker parse custody (RT-003) ----------------------------------------------
r5 = []
CSB = read("components/SkipButton.brs")
if CSB is None:
    problems.append("  components/SkipButton.brs - CHECK95: unreadable")
    CSB = ""
FSB = read("source/player/SkipButton.brs")
if FSB is None:
    problems.append("  source/player/SkipButton.brs - CHECK95: unreadable")
    FSB = ""

def dict_method_body(src, name):
    m = re.search(r"^(\s*)" + name + r": function[^\n]*\n(.*?)^\1end function",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(2) if m else None

# The law, in both files: a Boolean admissibility probe decides, and the
# stored value is ALWAYS the raw wire member (never a helper return) - an
# as-Object round-trip re-boxes numerics, which the headless brs harness
# silently mis-compares. Per-key shape pinned for all four skip_* markers.
MARKER_KEYS = ("skip_intro_start", "skip_intro_end", "skip_outro_start", "skip_outro_end")
for label, src, helper, probe in (
        ("component", CSB, "SkipMarkerIsNumeric", "SkipMarkerIsNumeric(markerData."),
        ("factory", FSB, "isNumericMarker", "m.isNumericMarker(markerData.")):
    h = sub_body(src, helper) or dict_method_body(src, helper)
    if h is None:
        r5.append(f"the {label} Boolean marker probe ({helper}) is missing")
        continue
    sig_ok = re.search(r"(?:^function\s+" + helper + r"[^\n]*as Boolean$|^\s*" + helper + r": function[^\n]*as Boolean$)",
                       src, re.MULTILINE)
    if sig_ok is None:
        r5.append(f"the {label} marker probe does not return Boolean - value round-trips re-box numerics")
    for tp in ("roInt", "roLongInteger", "roFloat", "roDouble"):
        if tp not in h:
            r5.append(f"the {label} probe dropped the {tp} arm")
    sm = sub_body(src, "setMarkers") or dict_method_body(src, "setMarkers")
    if sm is None:
        r5.append(f"the {label} setMarkers vanished")
        continue
    for key in MARKER_KEYS:
        if probe + key + ")" not in sm:
            r5.append(f"the {label} setMarkers no longer probes {key}")
        if f"m.markers.{key} = markerData.{key}" not in sm:
            r5.append(f"the {label} setMarkers stores {key} through an as-Object round-trip instead of the raw wire member")
oc = sub_body(CSB, "OnMarkersChange")
if oc is None or "setMarkers(markerData)" not in strip_comment_lines(oc):
    r5.append("the component's markers-field callback no longer delegates to the guarded setMarkers")
if 'type(skipSpec) = "roAssociativeArray"' not in psc:
    r5.append("PlayerScene writes the typed markers field without the roAssociativeArray check")
if r5:
    problems.append("  marker parse custody - CHECK95 R5: " + "; ".join(r5))

# ---- R6 windowed walk (RT-004) ------------------------------------------------------
r6 = []
USRC_R6 = read("source/lib/Utilities.brs") or ""
av = sub_body(strip_comment_lines(USRC_R6), "ActivateVisibleRange")
if av is None:
    r6.append("ActivateVisibleRange vanished")
else:
    if "while child <> invalid" in av:
        r6.append("the full 0..invalid walk regrew - the window clamp is the law")
    if "GetChildCount" not in av:
        r6.append("the window is no longer bounded by GetChildCount")
    if "for i = first to last" not in av:
        r6.append("the bounded for-loop shape left")
# ROK-3/ROK-4: the grid family shares the leaf; no scene keeps a private full walk.
for scn in ("HomeScene", "LibraryScene", "CollectionScene", "FavoritesScene", "AudiobookScene", "SearchScene"):
    ssrc = read("components/" + scn + ".brs") or ""
    if "sub ActivateVisibleRange" in ssrc:
        r6.append(scn + " re-declares the activator instead of using the Utilities leaf")
    if "ActivateVisibleRange(" not in ssrc:
        r6.append(scn + " visibleRect handler no longer calls the shared activator")
    if "ClearLazyPosterUrl(" in ssrc:
        r6.append(scn + " regrew the unload arm")
    if "while child <> invalid" in ssrc:
        r6.append(scn + " regrew a full 0..invalid walk")
if r6:
    problems.append("  windowed lazy walk - CHECK95 R6: " + "; ".join(r6))

# ---- R7 docs pair -------------------------------------------------------------------
r7 = []
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*95\s*\|.*RT-089\b", docs, re.M):
    r7.append("docs/static-checks.md row 95 is missing or does not name RT-089")
cl = read("CHANGELOG.md")
if cl is None or "RT-089" not in cl or "RT-090" not in cl or "PlayHlsUrlRefused" not in cl:
    r7.append("CHANGELOG.md must name RT-089, RT-090 and the new gate function")
if r7:
    problems.append("  docs pair - CHECK95 R7: " + "; ".join(r7))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK95: %d conviction(s) - the w01 end-of-playback laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK95: the film ends at the end, the envelope stays an envelope,")
print("  the retry knows its mode, one gate owns every HLS lane, markers are")
print("  parsed before they speak, and the rail walks its window")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 96: search debounce self-heal, dead-seam extinction, numeric version custody, honest clean/gitignore, fail-loud release reset (RT-005 RT-006 RT-007 RT-008 RT-009 RT-010) ==="
# NUMBERING: 96 is the next-FREE leg (95 taken by the w01 end-of-playback era,
# measured on this lane at 5d12356; 'Check 96'/'CHECK96' appear nowhere in
# scripts/, tests/ or docs/ before this commit).
#
# WHY THE LEG EXISTS (review lineage roku__crossfe + roku__devops, wave w07):
# six small hygiene defects shared one shape - the tree trusted a mechanism
# that quietly no-ops on its bad day. The search debounce timer DROPPED a
# fired query whenever a request was still in flight (the one-shot timer is
# consumed when its handler runs, so the newest keystrokes could sit
# unsearched forever unless another key happened); AppContext advertised a
# tiered poster-decode seam (GetPosterDecodeSize) with zero call sites
# anywhere - the repo's fail-loud-or-delete doctrine says dead code dies
# (M-ROKU-09 precedent in derive-version.sh); the Makefile's PKG_VERSION
# rides $(shell ...) which collapses to EMPTY when derive-version.sh fails
# (make does not propagate that exit), and verify-package.sh leg 6 only
# grepped key EXISTENCE, so a packaged manifest with blank version stamps
# sailed through; make clean left the sha256 sibling and the whole build/
# tree behind; the .gitignore comment cited a 'make dev-package' target that
# never existed; and package.yml reset the rolling 'latest' release with
# '|| true', so a transient gh failure left tomorrow's assets bolted onto
# yesterday's stale tag.
#
# WHAT IT PINS (fail-loud on unreadable inputs):
#   R1 SearchScene OnSearchTimerFire may not drop a fired query on a busy
#      apiTask with a bare one-line return; the busy path must RE-ARM the
#      debounce (control stop+start pair inside the handler).
#   R2 GetPosterDecodeSize stays extinct across source/ (name AND the
#      'poster decode size' docblock claim).
#   R3 the package recipe fails loud on an empty PKG_VERSION, _update-manifest
#      asserts all three stamps are NUMERIC in build/manifest, and
#      verify-package.sh leg 6 requires anchored numeric version stamps
#      while title= stays a presence check.
#   R4 make clean removes phlix.zip, its .sha256 sibling AND build/.
#   R5 .gitignore names no phantom target - and keeps naming the real one.
#   R6 package.yml probes the 'latest' release before deleting it, the
#      delete carries no '|| true', and the CHECK40 R4 vehicle literal
#      ('gh release delete latest --yes --cleanup-tag') stays intact.
#   R7 docs pair - static-checks row 96 names RT-005; the CHANGELOG era
#      entry names all six items.
# Zero new catalog keys: nothing user-visible changes in this era (the
# CHECK93 R3 census stays untouched BY CONSTRUCTION).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def strip_comment_lines(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


def sub_body(src, name):
    m = re.search(r"^(?:sub|function)\s+" + name + r"\b[^\n]*\n(.*?)^end (?:sub|function)",
                  src, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else None


problems = []

# ---- R1 search debounce self-heal (RT-005) --------------------------------------
SS = read("components/SearchScene.brs")
if SS is None:
    problems.append("  components/SearchScene.brs - CHECK96: unreadable")
    SS = ""
tf = sub_body(strip_comment_lines(SS), "OnSearchTimerFire")
r1 = []
if tf is None:
    r1.append("OnSearchTimerFire vanished")
else:
    if re.search(r'apiTask\.state\s*=\s*"run" then[ \t]+return', tf):
        r1.append('the busy-guard drops the fired query again - a consumed one-shot timer means the newest text may never be searched')
    if 'm.apiTask.state = "run"' not in tf:
        r1.append('the in-flight guard left the timer handler entirely')
    if 'm.searchTimer.control = "stop"' not in tf or 'm.searchTimer.control = "start"' not in tf:
        r1.append('the busy path no longer re-arms the debounce (stop+start) - the re-arm IS the cure')
if r1:
    problems.append("  search debounce self-heal - CHECK96 R1: " + "; ".join(r1))

# ---- R2 dead-seam extinction (RT-006) --------------------------------------------
r2 = []
AC = read("source/lib/AppContext.brs")
if AC is None:
    problems.append("  source/lib/AppContext.brs - CHECK96: unreadable")
    AC = ""
if "poster decode size" in AC.lower():
    r2.append("the tiered 'poster decode size' docblock claim survived - a promise may not outlive its seam")
for dirpath, dirnames, filenames in os.walk("source"):
    dirnames[:] = [d for d in dirnames if d != "node_modules"]
    for fn in sorted(filenames):
        if not fn.endswith((".brs", ".xml")):
            continue
        path = os.path.join(dirpath, fn)
        body = read(path)
        if body is not None and re.search(r"\bGetPosterDecodeSize\b", body):
            r2.append(path + " still names the dead GetPosterDecodeSize seam")
if r2:
    problems.append("  dead-seam extinction - CHECK96 R2: " + "; ".join(r2))

# ---- R3 numeric version custody (RT-007) ------------------------------------------
MK = read("Makefile")
if MK is None:
    problems.append("  Makefile - CHECK96: unreadable")
    MK = ""
r3 = []
if not re.search(r'\[\s*-z\s*"\$\(strip \$\(PKG_VERSION\)\)"\s*\]', MK):
    r3.append('the package recipe accepts an empty PKG_VERSION (make swallows derive-version.sh\'s exit, so blank versions would ship)')
mrec = re.search(r"^_update-manifest:[^\n]*\n((?:\t[^\n]*\n?)+)", MK, re.MULTILINE)
mrecipe = mrec.group(1) if mrec else ""
if "for k in major minor build; do" not in mrecipe:
    r3.append("_update-manifest does not assert the derived stamps after substitution")
if "_version=[0-9]+" not in mrecipe:
    r3.append("_update-manifest's stamp assertion is not numeric-anchored")
VP = read("scripts/verify-package.sh")
if VP is None:
    problems.append("  scripts/verify-package.sh - CHECK96: unreadable")
    VP = ""
if 'grep -qE "^${key}=[0-9]+$"' not in VP:
    r3.append("verify-package.sh leg 6 accepts empty version stamps (existence-only grep)")
if 'grep -q "^title="' not in VP:
    r3.append("verify-package.sh leg 6 no longer checks title= presence")
if r3:
    problems.append("  numeric version custody - CHECK96 R3: " + "; ".join(r3))

# ---- R4 honest clean (RT-008) ------------------------------------------------------
cleanrec = re.search(r"^clean:[^\n]*\n((?:\t[^\n]*\n?)+)", MK, re.MULTILINE)
crecipe = cleanrec.group(1) if cleanrec else ""
r4 = []
if "rm -f $(PKG_NAME).zip $(PKG_NAME).zip.sha256" not in crecipe:
    r4.append("clean leaves the .sha256 sibling behind")
if "rm -rf $(BUILD_DIR)" not in crecipe:
    r4.append("clean leaves $(BUILD_DIR)/ (and its pkg-stage) behind")
if r4:
    problems.append("  honest clean - CHECK96 R4: " + "; ".join(r4))

# ---- R5 gitignore prose truth (RT-009) ----------------------------------------------
GI = read(".gitignore")
r5 = []
if GI is None:
    problems.append("  .gitignore - CHECK96: unreadable")
else:
    if "dev-package" in GI:
        r5.append("the ignore comment names the phantom 'make dev-package' target again (that target never existed)")
    if "make package" not in GI:
        r5.append("the ignore comment no longer names the real 'make package' producer")
if r5:
    problems.append("  gitignore prose truth - CHECK96 R5: " + "; ".join(r5))

# ---- R6 fail-loud release reset (RT-010) ---------------------------------------------
WF = read(".github/workflows/package.yml")
r6 = []
if WF is None:
    problems.append("  .github/workflows/package.yml - CHECK96: unreadable")
else:
    if "gh release delete latest --yes --cleanup-tag" not in WF:
        r6.append("the release-reset vehicle left package.yml - CHECK40 R4 and docs/publishing.md ride it")
    if re.search(r"gh release delete latest --yes --cleanup-tag\s*\|\|\s*true", WF):
        r6.append("the reset shrugs at gh failures again - a transient error leaves the NEW assets attached to the stale tag")
    if "gh release view latest" not in WF:
        r6.append("the reset does not probe for the release before deleting it")
if r6:
    problems.append("  fail-loud release reset - CHECK96 R6: " + "; ".join(r6))

# ---- R7 docs pair ---------------------------------------------------------------------
r7 = []
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*96\s*\|.*RT-005\b", docs, re.M):
    r7.append("docs/static-checks.md row 96 is missing or does not name RT-005")
cl = read("CHANGELOG.md")
missing = [rid for rid in ("RT-005", "RT-006", "RT-007", "RT-008", "RT-009", "RT-010")
           if cl is None or rid not in cl]
if missing:
    r7.append("CHANGELOG.md does not name this era's items: " + " ".join(missing))
if r7:
    problems.append("  docs pair - CHECK96 R7: " + "; ".join(r7))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK96: %d conviction(s) - the w07 debounce/packaging laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK96: the search re-arms instead of dropping, dead seams stay dead,")
print("  an empty version stamp cannot ship, clean really cleans, and the")
print("  release reset fails loud instead of shrugging")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 97: Makefile recipe-comment dollar-escape law, .PHONY completeness, fold doc-pair (RT-011, REVIEW-w07L5roku-r2 Minor) ==="
# NUMBERING: 97 is the next-FREE leg (96 taken by the w07 hygiene era, measured
# on this lane at b6c20b2: highest header in this file is Check 96; 'Check 97'/
# 'CHECK97' appear nowhere in scripts/, tests/, docs/, README.md, CLAUDE.md or
# CHANGELOG.md — git grep rc=1, measured before this block was written).
#
# WHY THE LEG EXISTS (the w08L3 card fold):
#  (a) REVIEW-w07L5roku-r2.md Minor — the $$(shell ...) escape that keeps the
#      Makefile's RT-007 recipe comments inert is itself unpinned. GNU make
#      expands $(...) across a whole recipe line BEFORE the shell ever sees
#      it, and the shell's '#' never hides a make-time expansion: a future
#      edit dropping one '$' turns a comment into a command make executes
#      while reading the file. Every gate would stay green through that edit
#      (verify-runtime never executes make), which is exactly how the
#      w07L5-era phantom probe could have written /tmp from a 'comment'.
#  (b) RT-011 (review roku__devops #6) — .PHONY was incomplete (14 of the 25
#      declared targets at dispatch tip; the review counted 8 unlisted at its
#      own era — drift disclosed): make treats a target whose name collides
#      with a root file/dir as up to date when its prerequisites do not
#      change, so the recipe silently never runs while make exits 0. Six of
#      the eight the review named are CI-gate invocations (make bslint,
#      validate-xml, verify-runtime, check) — the fail-open class this repo
#      already legislated against in validate-xml.sh (zero-file guard) and
#      CHECK40. No such root names exist today; the pin keeps that latent
#      state from rotting into an active one.
#  The era additionally repairs the CHECK70 docblock's hub-vendor line cites
#  (:511-523/:558 era values drifted; re-verified at hub master 81be1692:
#  101 built :518-522, sent :557) — prose truth only, no pin (cross-repo
#  line numbers move with every hub edit; pinning them would import hub
#  churn into this battery).
#
# WHAT IT PINS (fail-loud on unreadable inputs):
#   R1 recipe-comment dollar-escape law — every tab-line whose text (after an
#      optional '@' and whitespace) starts with '#' may contain '$(' only in
#      the '$$(' escaped form; convictions name Makefile:line. Scope is
#      comment-led lines on purpose: code-led recipes legitimately use
#      $(MAKE)/$(PKG_NAME), and '#' mid-command is shell text make passes
#      through, not something this leg can classify without over-convicting.
#   R2 .PHONY completeness — every target the Makefile defines must appear on
#      the .PHONY line, unless a root-level file/dir actually bears its name
#      (then up-to-date semantics are the real contract). The exemption set
#      is empty today (measured); a genuine future file-producing target
#      rotates this pin from a measured red, with the reason in its row.
#   R3 anti-vacuity — the two RT-007 escape-comment sites (the empty-
#      $$(shell) guard block and the PKG_VERSION-collapses block) still exist
#      with their escapes, so R1 can never be satisfied by deleting them.
#   R4 docs pair — this row (97) exists naming RT-011 and the w07L5-r2
#      lineage, and the CHANGELOG era entry names RT-011..RT-016 + Check 97.
# Zero new catalog keys, zero wire codes: nothing user-visible changes.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


problems = []

MK = read("Makefile")
if MK is None:
    print("  Makefile - CHECK97: unreadable")
    sys.exit(1)
lines = MK.splitlines()

# ---- R1 recipe-comment dollar-escape law ------------------------------------
r1 = []
for n, line in enumerate(lines, 1):
    if not line.startswith("\t"):
        continue
    rest = line[1:]
    if rest.startswith("@"):
        rest = rest[1:]
    rest = rest.lstrip()
    if not rest.startswith("#"):
        continue
    for m in re.finditer(r"\$\(", line):
        if m.start() == 0 or line[m.start() - 1] != "$":
            r1.append(f"Makefile:{n} - a recipe comment carries an un-escaped "
                      f"'$(' — make expands it while READING the recipe, so the "
                      f"comment executes; spell it '$$('")
if r1:
    problems.append("  recipe-comment dollar-escape law - CHECK97 R1:\n    "
                    + "\n    ".join(r1))

# ---- R2 .PHONY completeness --------------------------------------------------
phony = []
targets = []
for line in lines:
    if line.startswith(".PHONY:"):
        phony = line.split(":", 1)[1].split()
    m = re.match(r"^([A-Za-z_][A-Za-z0-9._-]*)\s*:(?!=)", line)
    if m:
        targets.append(m.group(1))
declared = set(phony)
r2 = []
for t in targets:
    if t in declared:
        continue
    if os.path.exists(t):
        continue  # a real file bearing the name: up-to-date semantics apply
    r2.append(f"target '{t}' is not declared .PHONY (a root file/dir of that "
              f"name would make 'make {t}' exit 0 without running its recipe)")
if r2:
    for item in r2:
        problems.append("  .PHONY completeness - CHECK97 R2: " + item)

# ---- R3 anti-vacuity: the escape sites themselves ----------------------------
r3 = []
if "an empty $$(shell ...) result" not in MK:
    r3.append("the _update-manifest empty-stamp escape-comment block left the "
              "Makefile - R1 would walk an empty field and pass vacuously")
if "PKG_VERSION rides a $$(shell ...) assignment" not in MK:
    r3.append("the package empty-PKG_VERSION escape-comment block left the "
              "Makefile - R1 would walk an empty field and pass vacuously")
if r3:
    problems.append("  escape-site anti-vacuity - CHECK97 R3: " + "; ".join(r3))

# ---- R4 docs pair -------------------------------------------------------------
r4 = []
docs = read("docs/static-checks.md")
if docs is None or not re.search(r"^\|\s*97\s*\|.*RT-011\b.*w07L5", docs, re.M):
    r4.append("docs/static-checks.md row 97 is missing or does not name RT-011 "
              "and the w07L5-r2 lineage")
cl = read("CHANGELOG.md")
missing = [rid for rid in ("RT-011", "RT-012", "RT-013", "RT-014", "RT-015", "RT-016")
           if cl is None or rid not in cl]
if missing:
    r4.append("CHANGELOG.md does not name this era's items: " + " ".join(missing))
if cl is not None and "Check 97" not in cl:
    r4.append("CHANGELOG.md does not name Check 97")
if r4:
    problems.append("  docs pair - CHECK97 R4: " + "; ".join(r4))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK97: %d conviction(s) - the Makefile comment-escape and .PHONY laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK97: recipe comments stay inert to make, every target declares itself")
print("  .PHONY, the escape sites hold their ground, and the docs pair is complete")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 98: w12L3 era - guarded final-position read, canonical host parser on both dial legs, boxed-family year gate, docblock/doc truth pins (RT-035 RT-036 RT-037 RT-038 RT-039 RT-040) ==="
# NUMBERING: 98 is the next-FREE leg (97 taken by the w08L3 fold, measured on
# this lane at d34aa7b1: highest header in this file is Check 97; 'Check 98'/
# 'CHECK98' appear nowhere in scripts/, tests/, docs/, README.md, CLAUDE.md or
# CHANGELOG.md — git grep rc=1, measured before this block was written).
#
# WHY THE LEG EXISTS (card w12 L3, reviews 2026-11-04):
#  (a) RT-035 (review roku__exploiter #9, Info) — StopPlayback guarded the
#      stop-control write against a nil player but read m.videoPlayer.position
#      OUTSIDE that guard; the pin keeps the read folded back in, so a future
#      re-flatten reddens.
#  (b) RT-036 (review roku__exploiter #7, Minor) — DisplaySimilar gated the
#      year render on type(sim.year) = "Int", a name the firmware never
#      emits (headless brs probe: a JSON member answers "Integer"/"roInt",
#      never "Int"), so the arm was dead. The pin forbids the dead spelling
#      and requires the repo's boxed-family signature.
#  (c) RT-037 (review roku__secnet #1, Minor) — the two syncplay/hub dial
#      legs carried hand-rolled scheme/path/colon splits that were broken
#      on IPv6 literals and accepted userinfo authorities. Cure: both parse
#      through the canonical HostOfUrl (the delegation law CHECK48 R3
#      already pins for the connect-class predicates). The pin requires
#      HostOfUrl( on both bodies and forbids the retired split shapes from
#      returning.
#  (d) RT-038 (review roku__secnet #2, Info) — the entropy docblock claimed
#      a stream "no off-device observer can enumerate"; truth: there is no
#      CSPRNG on the platform and the re-roll is predictable-by-design
#      hygiene over non-secret draws. RT-040 (review roku__secnet #4, Info)
#      — the probeHealth docblock filed its redirect-following as a loose
#      "Info"; truth: it is a deliberate CHECK48-pinned exemption. R4 pins
#      the exact truth phrases so neither claim can quietly rot back.
#  (e) RT-039 (review roku__secnet #3, Info) — plaintext device-registry
#      token storage was undocumented. R4 pins the publishing.md section +
#      the README pointer.
#  (f) R5 docs pair — this table row + the CHANGELOG era entry, the same
#      closure law CHECK97 R4 carries.
# Zero new catalog keys, zero wire codes, zero user-visible strings.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def sub_body(text, name):
    m = re.search(r"(?m)^(?:sub|function)\s+%s\b[^\n]*\n(.*?)^end (?:sub|function)" % re.escape(name),
                  text, re.DOTALL)
    return m.group(0) if m else None


problems = []

PS = read("components/PlayerScene.brs")
PA = read("components/PhlixApp.brs")
DS = read("components/DetailScene.brs")
AC = read("source/lib/ApiClient.brs")
SP = read("source/lib/SyncPlayProtocol.brs")
PUB = read("docs/publishing.md")
RDME = read("README.md")
DOCS = read("docs/static-checks.md")
CHANGE = read("CHANGELOG.md")

unreadable = [name for name, src in
              (("PlayerScene", PS), ("PhlixApp", PA), ("DetailScene", DS),
               ("ApiClient", AC), ("SyncPlayProtocol", SP), ("publishing", PUB),
               ("README", RDME), ("static-checks", DOCS), ("CHANGELOG", CHANGE))
              if src is None]
if unreadable:
    print("  CHECK98 R0: unreadable input(s): " + ", ".join(unreadable) +
          " - the era pins cannot run vacuously")
    sys.exit(1)

# ---- R1 StopPlayback: the final-position read lives inside the guard -------
r1 = []
body = sub_body(mask(PS), "StopPlayback")
if body is None:
    r1.append("sub StopPlayback vanished from PlayerScene.brs - the guard law has no body to inspect")
else:
    guard = body.find('if m.videoPlayer <> invalid then')
    control = body.find('m.videoPlayer.control = "stop"')
    posread = body.find('position = m.videoPlayer.position')
    if guard < 0 or control < 0:
        r1.append("the m.videoPlayer guard / control-stop landmarks left the masked body")
    elif posread < 0:
        r1.append("the final-position read (position = m.videoPlayer.position) left StopPlayback")
    else:
        # The guard's closing 'end if' is the FIRST one after the control
        # write; the read must live strictly before it (and after the write).
        guard_close = body.find("end if", control + len('m.videoPlayer.control = "stop"'))
        if guard_close < 0:
            r1.append("StopPlayback lost the end if closing its m.videoPlayer guard")
        elif not (guard < control < posread < guard_close):
            r1.append("m.videoPlayer.position is read OUTSIDE the m.videoPlayer <> invalid guard - on a nil player the unguarded member access faults the sub right after the stop write (RT-035)")
if r1:
    problems.append("  StopPlayback guard - CHECK98 R1:\n    " + "\n    ".join(r1))

# ---- R2 both dial legs parse through HostOfUrl, hand-rolled splits stay gone
r2 = []
b = sub_body(mask(PS), "BuildSyncPlayWsParts")
if b is None:
    r2.append("function BuildSyncPlayWsParts vanished from PlayerScene.brs")
else:
    if "HostOfUrl(" not in b:
        r2.append("BuildSyncPlayWsParts stopped parsing through the canonical HostOfUrl (RT-037)")
    for shape in ('Instr(1, rest, "://")', 'Instr(1, rest, "/")', 'Instr(1, rest, ":")'):
        if shape in b:
            r2.append("the retired hand-rolled split " + shape + " is back in BuildSyncPlayWsParts - it blanks IPv6 literals at the first colon (RT-037)")
b = sub_body(mask(PA), "StartHubCommandConsumer")
if b is None:
    r2.append("sub StartHubCommandConsumer vanished from PhlixApp.brs")
else:
    if "HostOfUrl(" not in b:
        r2.append("StartHubCommandConsumer stopped parsing through the canonical HostOfUrl (RT-037)")
    for shape in ('Instr(1, host, "://")', 'Instr(1, host, "/")'):
        if shape in b:
            r2.append("the retired hand-rolled split " + shape + " is back in StartHubCommandConsumer - same IPv6/userinfo defect class (RT-037)")
if r2:
    problems.append("  dial-leg host parsing - CHECK98 R2:\n    " + "\n    ".join(r2))

# ---- R3 DisplaySimilar year gate: dead 'Int' spelling banned, family present
r3 = []
b = sub_body(mask(DS), "DisplaySimilar")
if b is None:
    r3.append("sub DisplaySimilar vanished from DetailScene.brs")
else:
    if re.search(r'=\s*"Int"', b):
        r3.append('a type() gate against "Int" is back - the firmware never emits that name (a JSON member answers "Integer"/"roInt"; measured headless brs probe), the arm is dead and the year never renders (RT-036)')
    if '"roLongInteger"' not in b or '"Integer"' not in b:
        r3.append('the boxed-numeric family signature ("Integer".."roDouble") is missing from the year gate - the repo idiom is ApplyResumeFromContinueWatching/Utilities, not a bare arm (RT-036)')
    if "sim.year <> invalid" not in b:
        r3.append("the sim.year <> invalid presence check left the gate")
if r3:
    problems.append("  DisplaySimilar year gate - CHECK98 R3:\n    " + "\n    ".join(r3))

# ---- R4 docblock/doc truth pins (RAW text - these ARE comments) -------------
r4 = []
for src, needle, why in (
        (AC, "the firmware auto-follow is left",
         "probeHealth's deliberate-exemption docblock is gone - the redirect-follow must be named as a CHECK48-pinned design decision (RT-040)"),
        (AC, "CHECK48 R1 enforces the exemption",
         "probeHealth's docblock no longer names the enforcing leg - the exemption and its pin must cite each other (RT-040)"),
        (SP, "predictable-by-design",
         "the entropy docblock lost its honest limits wording - no CSPRNG exists on this platform and the docblock must say so (RT-038)"),
        (PUB, "## Security Notes \u2014 Device Token Storage",
         "docs/publishing.md lost the device-token-storage section (RT-039)"),
        (PUB, "no keystore",
         "the device-token-storage section no longer states the platform limit (RT-039)"),
        (RDME, "Security Notes \u2014 Device Token Storage",
         "README.md lost its pointer to the device-token-storage section (RT-039)")):
    if needle not in src:
        r4.append(why)
if r4:
    problems.append("  docblock/doc truth - CHECK98 R4:\n    " + "\n    ".join(r4))

# ---- R5 docs pair -----------------------------------------------------------
r5 = []
if not re.search(r"^\|\s*98\s*\|.*RT-035.*RT-040", DOCS, re.M):
    r5.append("docs/static-checks.md row 98 is missing or does not name RT-035..RT-040")
missing = [rid for rid in ("RT-035", "RT-036", "RT-037", "RT-038", "RT-039", "RT-040") if rid not in CHANGE]
if missing:
    r5.append("CHANGELOG.md does not name this era's items: " + " ".join(missing))
if "Check 98" not in CHANGE:
    r5.append("CHANGELOG.md does not name Check 98")
if r5:
    problems.append("  docs pair - CHECK98 R5: " + "; ".join(r5))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK98: %d conviction(s) - the w12L3 era laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK98: the final-position read stays guarded, both dial legs parse through")
print("  HostOfUrl, the year gate is alive, and the era's doc truth stands")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

# ---------------------------------------------------------------------------
echo "=== Check 99: w14L1 era - the vendored contracts registry is byte-pinned, the syncplay census meets it through equality and containment, and the RT-041/042/047/048/049/091 laws hold in their carriers (LW-034 RT-041 RT-042 RT-047 RT-048 RT-049 RT-091) ==="
# NUMBERING: 99 is the next-FREE leg (98 taken by w12L3, measured on this lane
# at 131df6b289: highest header in this file is Check 98; 'Check 99'/'CHECK99'
# appeared nowhere in scripts/ or docs/ before this block was written - the
# only hits are this era's own forward-references in tests and the register).
#
# WHY THE LEG EXISTS (card w14 L1, reviews 2026-11-09):
#  (a) LW-034 (review roku__devops) - the estate's error-code census had NO
#      cross-repo pin on roku: the console family learned this lesson the hard
#      way (38b068cb ContractsErrorCodesGateTest) - fixture-vs-fixture twins
#      are the vacuity class, so R1 pins the vendored bytes by md5 against the
#      contracts registry ITSELF (dist/error-codes.json at the FROZEN trio md5
#      5d1783a71a3c4e128b2021327cad3717, 205 codes) and R2 meets the Bright-
#      Script census with real EQUALITY (the 8 dotted syncplay.* members) and
#      honest CONTAINMENT (the 12 SCREAMING members live inside the 76 bare
#      registry members of mixed domains - the same law 3 the console gate
#      carries). Drift in EITHER direction reddens: a census member the
#      registry lacks, or a family rename registry-side the census never
#      followed.
#  (b) RT-041 fold-in (REVIEW-w13L3roku Minor 1) - the join-password digest
#      R2 ships a cure whose headless conviction was a gap: M-041A (revert to
#      the FromAsciiString spelling) sailed green because the roEVPDigest leg
#      stops headless. R3 pins the ROUTING statically: SyncPlayPasswordHash
#      must feed through the pure Utf8BytesFromString, must not regrow the
#      inline Asc(Mid(plain split, and the helper must keep delegating to the
#      truth-table'd Utf8BytesForCodePoint.
#  (c) RT-042 fold-in (REVIEW-w13L3roku Minor 2) - the push-cap refusal rides
#      zero automated render conviction headless (brs mocks unknown
#      roSGNode types as Invalid, so ShowErrorDialog cannot execute); R4
#      statically pins both deep-link arms routing their refusal through
#      ShowDeepLinkError (never a silent ShowHome) and the cap's disclose-
#      invalid order inside PushScreen. The headless cap-refusal test
#      (PhlixApp.test.brs) convicts the return-invalid leg.
#  (d) R4 also carries the era's ORDER laws - RT-049 (busy check precedes the
#      loadingPage stick), RT-091 (busy check precedes the pendingUpNext arm),
#      RT-047 (poll decision sits above the device-only label rendering; the
#      timer is created, observed, silenced through RefreshStatus(silent) and
#      released in Teardown), RT-048 (the order marker rides the label, the
#      cycle steps through NextSortStep, and the dead " *" construction stays
#      extinct in ShowSortOptions).
#  (e) R5 docs pair - this row + the CHANGELOG era entry naming every id and
#      Check 99 + scripts/audit-gate.mjs (RT-088), the CHECK97/98 closure law.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import hashlib, json, os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

FIXTURE = "tests/fixtures/error-codes.json"
FIXTURE_MD5 = "5d1783a71a3c4e128b2021327cad3717"
REGISTRY_COUNT = 205
SYNCPLAY_FAMILY = 8
BARE_MEMBERS = 76
CENSUS_TOTAL = 20
CENSUS_DOTTED = 8
CENSUS_SCREAMING = 12


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def mask(text):
    out = []
    for line in text.split("\n"):
        in_string = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif ch == "'" and not in_string:
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def sub_body(text, name):
    m = re.search(r"(?m)^(?:sub|function)\s+%s\b[^\n]*\n(.*?)^end (?:sub|function)" % re.escape(name),
                  text, re.DOTALL)
    return m.group(0) if m else None


def before(body, first, second, leg, label, problems):
    a, b = body.find(first), body.find(second)
    if a < 0:
        problems.append("  %s - CHECK99 %s: literal %s vanished" % (label, leg, repr(first)))
    elif b < 0:
        problems.append("  %s - CHECK99 %s: literal %s vanished" % (label, leg, repr(second)))
    elif a > b:
        problems.append("  %s - CHECK99 %s: %s must precede %s" % (label, leg, repr(first), repr(second)))


problems = []

RAW_FIX = read(FIXTURE)
UTIL = read("source/lib/Utilities.brs")
LAA = read("components/LibraryAdminActionsScene.brs")
LIB = read("components/LibraryScene.brs")
SRCH = read("components/SearchScene.brs")
HOME = read("components/HomeScene.brs")
APP = read("components/PhlixApp.brs")
DOCS = read("docs/static-checks.md")
CHLOG = read("CHANGELOG.md")
for path, blob in ((FIXTURE, RAW_FIX), ("source/lib/Utilities.brs", UTIL),
                   ("components/LibraryAdminActionsScene.brs", LAA),
                   ("components/LibraryScene.brs", LIB),
                   ("components/SearchScene.brs", SRCH),
                   ("components/HomeScene.brs", HOME),
                   ("components/PhlixApp.brs", APP),
                   ("docs/static-checks.md", DOCS), ("CHANGELOG.md", CHLOG)):
    if blob is None:
        problems.append("  %s - CHECK99 R0: unreadable" % path)

# ---- R1: the vendored registry is the contracts registry, byte for byte ----
codes = []
if RAW_FIX is not None:
    digest = hashlib.md5(RAW_FIX.encode("utf-8")).hexdigest()
    if digest != FIXTURE_MD5:
        problems.append("  %s - CHECK99 R1: md5 %s is not the FROZEN contracts trio md5 %s "
                        "(re-vendor from phlix-contracts dist/error-codes.json, do not hand-edit)"
                        % (FIXTURE, digest, FIXTURE_MD5))
    try:
        data = json.loads(RAW_FIX)
    except ValueError as err:
        data = None
        problems.append("  %s - CHECK99 R1: unparseable JSON: %s" % (FIXTURE, err))
    if data is not None:
        comment = data.get("$comment", "")
        if "emit-error-codes.mjs" not in comment:
            problems.append("  %s - CHECK99 R1: $comment does not name the generator "
                            "scripts/emit-error-codes.mjs" % FIXTURE)
        raw_codes = data.get("codes")
        if not isinstance(raw_codes, list) or not all(isinstance(c, str) for c in raw_codes):
            problems.append("  %s - CHECK99 R1: codes is not a list of strings" % FIXTURE)
            raw_codes = []
        codes = raw_codes
        if len(raw_codes) != REGISTRY_COUNT:
            problems.append("  %s - CHECK99 R1: registry carries %d codes, expected %d"
                            % (FIXTURE, len(raw_codes), REGISTRY_COUNT))
        if len(set(raw_codes)) != len(raw_codes):
            problems.append("  %s - CHECK99 R1: registry carries duplicates" % FIXTURE)

registry_syncplay = sorted(c for c in codes if c.startswith("syncplay."))
registry_bare = [c for c in codes if "." not in c]

# ---- R2: the census MEETS the registry (equality + honest containment) ----
census = []
reserved_members = None
if UTIL is not None:
    m = re.search(r"function SyncPlayKnownErrorCodes\(\).*?end function", UTIL, re.S)
    if not m:
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: SyncPlayKnownErrorCodes() not found")
    else:
        census = re.findall(r'"([^"]+)"', m.group(0))
    r = re.search(r"function SyncPlayReservedErrorCodes\(\).*?end function", UTIL, re.S)
    if not r:
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: SyncPlayReservedErrorCodes() not found")
    else:
        reserved_members = re.findall(r'"([^"]+)"', r.group(0))
if census:
    if len(census) != len(set(census)):
        dupes = sorted({c for c in census if census.count(c) > 1})
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: census contains duplicates %s" % dupes)
    if len(census) != CENSUS_TOTAL:
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: census carries %d codes, expected %d"
                        % (len(census), CENSUS_TOTAL))
    dotted = sorted(c for c in census if "." in c)
    screaming = sorted(c for c in census if "." not in c)
    if len(dotted) != CENSUS_DOTTED or len(screaming) != CENSUS_SCREAMING:
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: census split is %d dotted/%d bare, "
                        "expected %d/%d" % (len(dotted), len(screaming), CENSUS_DOTTED, CENSUS_SCREAMING))
    if registry_syncplay and dotted != registry_syncplay:
        missing = sorted(set(dotted) - set(registry_syncplay))
        extra = sorted(set(registry_syncplay) - set(dotted))
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: syncplay family drift "
                        "(census-only %s | registry-only %s) - the census and the vendored "
                        "contracts registry must move together" % (missing, extra))
    lost = sorted(set(screaming) - set(registry_bare))
    if lost:
        problems.append("  source/lib/Utilities.brs - CHECK99 R2: SCREAMING members not in the "
                        "registry bare set: %s" % lost)
if reserved_members is not None and reserved_members:
    problems.append("  source/lib/Utilities.brs - CHECK99 R2: SyncPlayReservedErrorCodes() is no longer "
                    "the empty list (%s) - promote deliberately and move the census, do not silently arm"
                    % reserved_members)

# ---- R3: RT-041 - the digest routes through the pure UTF-8 helper ----
if UTIL is not None:
    hash_body = mask(sub_body(UTIL, "SyncPlayPasswordHash") or "")
    helper_body = mask(sub_body(UTIL, "Utf8BytesFromString") or "")
    if not hash_body:
        problems.append("  source/lib/Utilities.brs - CHECK99 R3: SyncPlayPasswordHash not found")
    else:
        if "Utf8BytesFromString(plain)" not in hash_body:
            problems.append("  source/lib/Utilities.brs - CHECK99 R3: SyncPlayPasswordHash no longer "
                            "feeds the digest through Utf8BytesFromString(plain)")
        if "Asc(Mid(plain" in hash_body:
            problems.append("  source/lib/Utilities.brs - CHECK99 R3: the inline Asc(Mid(plain byte "
                            "split regrew inside SyncPlayPasswordHash (M-041A class - headless cannot "
                            "convict it, this leg is the only automated pin)")
    if not helper_body:
        problems.append("  source/lib/Utilities.brs - CHECK99 R3: Utf8BytesFromString not found")
    elif "Utf8BytesForCodePoint(Asc(Mid(text" not in helper_body:
        problems.append("  source/lib/Utilities.brs - CHECK99 R3: Utf8BytesFromString no longer "
                        "delegates to the truth-table'd Utf8BytesForCodePoint(Asc(Mid(text")

# ---- R4: era render/order laws in their carriers ----
if LAA is not None:
    init_body = mask(sub_body(LAA, "Init") or "")
    resp_body = mask(sub_body(LAA, "OnApiResponse") or "")
    tear_body = mask(sub_body(LAA, "Teardown") or "")
    inflight = mask(sub_body(LAA, "IsScanJobInFlight") or "")
    refresh_sig = sub_body(LAA, "RefreshStatus")
    for needle, where, carrier in (("CreateChild(\"Timer\")", init_body, "Init"),
                                   ("ObserveField(\"fire\", \"OnScanPollFire\")", init_body, "Init"),
                                   ("SetScanPolling(IsScanJobInFlight(", resp_body, "OnApiResponse"),
                                   ("m.scanTimer = invalid", tear_body, "Teardown")):
        if needle not in where:
            problems.append("  components/LibraryAdminActionsScene.brs - CHECK99 R4 (RT-047): "
                            "%s missing from the %s carrier" % (repr(needle), carrier))
    if resp_body and "scanStatusLabel" in resp_body:
        before(resp_body, "SetScanPolling(IsScanJobInFlight(", "scanStatusLabel",
               "R4 (RT-047)", "LibraryAdminActionsScene.OnApiResponse", problems)
    elif resp_body:
        problems.append("  components/LibraryAdminActionsScene.brs - CHECK99 R4 (RT-047): "
                        "the scanStatusLabel carrier vanished from OnApiResponse")
    for needle in ("\"queued\"", "\"running\""):
        if needle not in inflight:
            problems.append("  components/LibraryAdminActionsScene.brs - CHECK99 R4 (RT-047): "
                            "IsScanJobInFlight no longer treats %s as in-flight" % needle)
    if refresh_sig is None or "RefreshStatus(silent = false as Boolean)" not in refresh_sig:
        problems.append("  components/LibraryAdminActionsScene.brs - CHECK99 R4 (RT-047): "
                        "RefreshStatus lost its silent-parameter signature")
if LIB is not None:
    labels_body = mask(sub_body(LIB, "UpdateSortFilterLabels") or "")
    sort_body = mask(sub_body(LIB, "ShowSortOptions") or "")
    step_body = mask(sub_body(LIB, "NextSortStep") or "")
    marker_body = mask(sub_body(LIB, "SortOrderMarker") or "")
    if "+ SortOrderMarker(m.sortOrder)" not in labels_body:
        problems.append("  components/LibraryScene.brs - CHECK99 R4 (RT-048): the sort label no "
                        "longer carries + SortOrderMarker(m.sortOrder)")
    for needle in ("NextSortStep(m.sortField, m.sortOrder)", "ApplySort(nxt.field, nxt.order)"):
        if needle not in sort_body:
            problems.append("  components/LibraryScene.brs - CHECK99 R4 (RT-048): ShowSortOptions "
                            "no longer steps through %s" % needle)
    if '" *"' in sort_body:
        problems.append("  components/LibraryScene.brs - CHECK99 R4 (RT-048): the dead \" *\" "
                        "selection-marker construction regrew in ShowSortOptions")
    if "ToggleSortOrder(" not in step_body:
        problems.append("  components/LibraryScene.brs - CHECK99 R4 (RT-048): NextSortStep no "
                        "longer flips the order at the wrap")
    if '"desc"' not in marker_body:
        problems.append("  components/LibraryScene.brs - CHECK99 R4 (RT-048): SortOrderMarker "
                        "lost its desc spelling")
if SRCH is not None:
    more_body = mask(sub_body(SRCH, "LoadMoreItems") or "")
    if not more_body:
        problems.append("  components/SearchScene.brs - CHECK99 R4 (RT-049): LoadMoreItems not found")
    else:
        before(more_body, "m.apiTask.state = \"run\"", "m.loadingPage = true",
               "R4 (RT-049)", "SearchScene.LoadMoreItems", problems)
if HOME is not None:
    upnext_body = mask(sub_body(HOME, "OnUpNextItemSelected") or "")
    if not upnext_body:
        problems.append("  components/HomeScene.brs - CHECK99 R4 (RT-091): OnUpNextItemSelected not found")
    else:
        before(upnext_body, "m.apiTask.state = \"run\"", "m.pendingUpNext = {",
               "R4 (RT-091)", "HomeScene.OnUpNextItemSelected", problems)
if APP is not None:
    dl_body = mask(sub_body(APP, "OnDeepLinkItemResponse") or "")
    push_body = mask(sub_body(APP, "PushScreen") or "")
    if not dl_body:
        problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): OnDeepLinkItemResponse not found")
    else:
        for needle in ("if detailScene = invalid", "if seasonScene <> invalid"):
            if needle not in dl_body:
                problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): the %s arm "
                                "vanished - a refused push must never ride on silently" % needle)
        if dl_body.count("ShowDeepLinkError()") < 3:
            problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): the deep-link error "
                            "surface appears %d time(s), expected at least 3 (failure + both "
                            "refusal arms)" % dl_body.count("ShowDeepLinkError()"))
    if not push_body:
        problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): PushScreen not found")
    else:
        cap = push_body.find("Count() >= 12")
        create = push_body.find("CreateObject(")
        if cap < 0 or create < 0:
            problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): PushScreen lost its "
                            "cap probe or its node construction")
        elif cap > create:
            problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): the >= 12 cap check "
                            "must refuse BEFORE any node is built")
        if "return invalid" not in push_body:
            problems.append("  components/PhlixApp.brs - CHECK99 R4 (RT-042): the cap refusal no "
                            "longer discloses invalid to its callers")

# ---- R5: docs pair ----
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*99\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK99 R5: no row 99 in the checks table")
    else:
        for idiom in ("LW-034", "RT-041", "RT-042", "RT-047", "RT-048", "RT-049", "RT-091"):
            if idiom not in row.group(0):
                problems.append("  docs/static-checks.md - CHECK99 R5: row 99 does not name %s" % idiom)
if CHLOG is not None:
    for idiom in ("LW-034", "RT-041", "RT-042", "RT-047", "RT-048", "RT-049", "RT-091",
                  "Check 99", "scripts/audit-gate.mjs"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK99 R5: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK99: %d conviction(s) - the w14L1 era laws are broken" % len(problems))
    sys.exit(1)

print("  CHECK99: the vendored registry is the contracts registry byte-for-byte, the census")
print("  meets it through syncplay-family equality and bare-set containment, and the era's")
print("  digest routing, deep-link refusal and sort-order laws stand in their carriers")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 100: the RT-092 boxed-lift cohort and the RT-105 routing arm keep every shipped limb (w15L9 era custody) ==="
# NUMBERING: next-FREE probe at this lane's base 3d26ee7f - max Check in this
# script was 99 (grep "^=== Check" tail), so 100 is free.
# WHY (REVIEW-w15L9roku.md MAJOR, executed strip table): an adversarial review
# stripped one coercion limb per site at 7b76043b and found 8 of the 9 shipped
# RT-092 inline arms plus the RT-105 unknown-container routing arm stayed GREEN
# across BOTH the headless battery and this gate - the pure-function mapper arms
# are convicted by tests/unit tables, but the inline scene legs had no pin
# anywhere, so a future re-boxing or limb-deletion could silently delete the
# cure. This is the static custody the cohort needed: per-limb exact-equality
# census (a limb that vanishes OR multiplies without rotating this dict
# reddens), the routing window pinned as one indivisible shape, and the docs
# pair that keeps the era named where it was adjudicated. Every arm has a
# red-leg plant in the portable twin (strip -> CHECK100 convicts BY NAME ->
# restore), so no pin here can rot into a vacuous count.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

# (path, label, kind, needle, want) - kind "re" = regex findall over raw text,
# "str" = literal substring count. Counts were MEASURED from disk at base
# 3d26ee7f (line cites era-verified there); equality, not floor: a limb
# stripped convicts, a limb pasted twice convicts, and the census itself must
# rotate in the commit that moves the cohort.
ARMS = [
    ("components/DetailScene.brs", "S1-detail-title", "re",
     r'TextOrEmpty\(item\.name\)', 1),
    ("components/DetailScene.brs", "S2-detail-agg-score", "re",
     r'IsBoxedNumber\(agg\.score\)', 1),
    ("components/DetailScene.brs", "S2-detail-agg-rating", "re",
     r'IsBoxedNumber\(agg\.rating\)', 1),
    ("components/PlayerScene.brs", "S3a-player-title-lifts", "re",
     r'TextOrEmpty\(m\.item\.name\)', 7),
    ("components/PlayerScene.brs", "S3b-player-member-count", "re",
     r'IsBoxedNumber\(group\.member_count\)', 1),
    ("components/PlayerScene.brs", "R105-route-window", "str",
     '    if streamFormat = "" then\n'
     "        canDirectPlay = false\n"
     "    else\n"
     '        canDirectPlay = DeviceCanDecodeVideo(DirectPlayProbeCodec(), streamFormat, "")\n'
     "    end if", 1),
    ("components/PlayerScene.brs", "R105-empty-branches", "re",
     r'if streamFormat = "" then', 2),
    ("components/HomeScene.brs", "S4-home-position-ticks", "re",
     r'IsBoxedNumber\(cw\.position_ticks\)', 1),
    ("components/HomeScene.brs", "H-nm-item", "re",
     r'nm = TextOrEmpty\(item\.name\)', 3),
    ("components/HomeScene.brs", "H-nm-library", "re",
     r'nm = TextOrEmpty\(library\.name\)', 1),
    ("components/HomeScene.brs", "H-nm-cw-name", "re",
     r'nm = TextOrEmpty\(cw\.name\)', 1),
    ("components/HomeScene.brs", "H-libName", "re",
     r'libName = TextOrEmpty\(library\.name\)', 1),
    ("components/LibraryScene.brs", "S5b-grid-name", "re",
     r'gridName = TextOrEmpty\(item\.name\)', 1),
    ("components/LibraryScene.brs", "S5b-grid-overview", "re",
     r'gridOverview = TextOrEmpty\(item\.overview\)', 1),
    ("components/AudiobookPlayerScene.brs", "S6-chapter-window", "re",
     r'IsBoxedNumber\(ch\.start_seconds\) and IsBoxedNumber\(ch\.end_seconds\)', 1),
    ("components/AudiobookPlayerScene.brs", "S6-start-gate", "re",
     r'if ch <> invalid and IsBoxedNumber\(ch\.start_seconds\) then', 1),
    ("components/AudiobookPlayerScene.brs", "AB-title", "re",
     r'TextOrEmpty\(audiobook\.title\)', 2),
    ("components/AudiobookPlayerScene.brs", "AB-author", "re",
     r'TextOrEmpty\(audiobook\.author\)', 1),
    ("components/AudiobookPlayerScene.brs", "AB-chapter-title", "re",
     r'TextOrEmpty\(ch\.title\)', 2),
    ("components/AudiobookPlayerScene.brs", "AB-saved-position", "re",
     r'IsBoxedNumber\(resp\.data\.position_ms\)', 1),
    ("components/AudiobookPlayerScene.brs", "AB-saved-chapter", "re",
     r'IsBoxedNumber\(resp\.data\.current_chapter_index\)', 1),
]

problems = []
for path, label, kind, needle, want in ARMS:
    if not os.path.exists(path):
        problems.append(f"  {path} - CHECK100 R1 [{label}]: the cohort carrier file vanished")
        continue
    with open(path, encoding="utf-8") as f:
        src = f.read()
    got = src.count(needle) if kind == "str" else len(re.findall(needle, src))
    if got != want:
        problems.append(
            f"  {path} - CHECK100 R1 [{label}]: expected exactly {want}, "
            f"found {got} - the RT-092/RT-105 limb was stripped, re-boxed or "
            f"multiplied without rotating this census in the same commit")

# R2: docs pair custody - the ledger row and the CHANGELOG entry name the era.
def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None

DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*100\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK100 R2: no row 100 in the checks table")
    else:
        for idiom in ("RT-092", "RT-105"):
            if idiom not in row.group(0):
                problems.append("  docs/static-checks.md - CHECK100 R2: row 100 does not name %s" % idiom)
if CHLOG is not None:
    for idiom in ("RT-092", "RT-105", "Check 100"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK100 R2: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK100: %d cohort-custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK100: every shipped limb of the RT-092 boxed-lift cohort and the")
print("  RT-105 unknown-container routing window stands where it landed, and")
print("  the era keeps its custody in the checks ledger and the CHANGELOG")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 101: the RT-094 browse-failure routing keeps every shipped limb (w15L9 R-B custody) ==="
# NUMBERING: next-FREE probe at this lane's tree - Check 100 is this wave's own
# R-A landing (the highest at dispatch base was 99), so 101 is free.
# WHY (REVIEW-w15L9roku.md R-B / RT-094): four browse scenes used to render
# emptiness - or nothing at all - over a dead server. The cure routes every
# failure decision through a pure per-scene choke (headless-pinned by the
# four BrowseOutcome suites) and discloses it with literal Translate keys
# plus a focusable retry (HomeScene exemplar). The INLINE routing limbs -
# the choke call, the failure write, the sole-writer empty copy, the
# observer pairing and the XML retry chrome - are device-side lines no
# headless battery can reach, so this static census is their honest home
# (the CHECK100 precedent). Exact-equality arms: a limb stripped, doubled
# or collapsed back to the empty era reddens by arm name; every arm has a
# red-leg plant in the portable twin.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

# (path, label, regex, want) - counts MEASURED from disk at this commit.
ARMS = [
    ("components/FavoritesScene.brs", "fav-choke-call",
     r'browseOutcome = FavoritesBrowseOutcome\(', 1),
    ("components/FavoritesScene.brs", "fav-failure-write",
     r'Translate\("favorites_failed"\)', 1),
    ("components/FavoritesScene.brs", "fav-empty-sole-writer",
     r'Translate\("favorites_empty"\)', 1),
    ("components/FavoritesScene.brs", "fav-observe",
     r'ObserveField\("buttonSelected", "OnFavoritesRetryPressed"\)', 1),
    ("components/FavoritesScene.brs", "fav-unobserve",
     r'm\.retryButton\.UnObserveField\("buttonSelected"\)', 1),
    ("components/FavoritesScene.xml", "fav-xml-retry-id",
     r'id="retryButton"', 1),
    ("components/FavoritesScene.xml", "fav-xml-retry-chrome",
     r'text="Retry" focusable="true" visible="false"', 1),
    ("components/SearchScene.brs", "sea-choke-call",
     r'browseOutcome = SearchBrowseOutcome\(', 1),
    ("components/SearchScene.brs", "sea-failure-write",
     r'Translate\("search_failed"\)', 1),
    ("components/SearchScene.brs", "sea-noresults-sole-writer",
     r'Translate\("search_no_results"\)', 1),
    ("components/SearchScene.brs", "sea-observe",
     r'ObserveField\("buttonSelected", "OnSearchRetryPressed"\)', 1),
    ("components/SearchScene.brs", "sea-unobserve",
     r'm\.retryButton\.UnObserveField\("buttonSelected"\)', 1),
    ("components/SearchScene.xml", "sea-xml-retry-id",
     r'id="retryButton"', 1),
    ("components/SearchScene.xml", "sea-xml-retry-chrome",
     r'text="Retry" focusable="true" visible="false"', 1),
    ("components/LibraryScene.brs", "lib-choke-call",
     r'browseOutcome = LibraryBrowseOutcome\(', 1),
    ("components/LibraryScene.brs", "lib-failed-limbs",
     r'Translate\("library_failed"\)', 2),
    ("components/LibraryScene.brs", "lib-observe",
     r'ObserveField\("buttonSelected", "OnLibraryRetryPressed"\)', 1),
    ("components/LibraryScene.brs", "lib-unobserve",
     r'm\.retryButton\.UnObserveField\("buttonSelected"\)', 1),
    ("components/LibraryScene.xml", "lib-xml-retry-id",
     r'id="retryButton"', 1),
    ("components/LibraryScene.xml", "lib-xml-retry-chrome",
     r'text="Retry" focusable="true" visible="false"', 1),
    ("components/CollectionScene.brs", "col-choke-call",
     r'browseOutcome = CollectionBrowseOutcome\(', 1),
    ("components/CollectionScene.brs", "col-failed-limbs",
     r'Translate\("collection_failed"\)', 2),
    ("components/CollectionScene.brs", "col-empty-sole-writer",
     r'Translate\("collection_empty"\)', 1),
    ("components/CollectionScene.brs", "col-observe",
     r'ObserveField\("buttonSelected", "OnCollectionRetryPressed"\)', 1),
    ("components/CollectionScene.brs", "col-unobserve",
     r'm\.retryButton\.UnObserveField\("buttonSelected"\)', 1),
    ("components/CollectionScene.xml", "col-xml-retry-id",
     r'id="retryButton"', 1),
    ("components/CollectionScene.xml", "col-xml-retry-chrome",
     r'text="Retry" focusable="true" visible="false"', 1),
]

problems = []
for path, label, rx, want in ARMS:
    if not os.path.exists(path):
        problems.append(f"  {path} - CHECK101 R1 [{label}]: the RT-094 carrier vanished")
        continue
    with open(path, encoding="utf-8") as f:
        src = f.read()
    got = len(re.findall(rx, src))
    if got != want:
        problems.append(
            f"  {path} - CHECK101 R1 [{label}]: expected exactly {want}, "
            f"found {got} - the RT-094 failure-vs-empty routing limb was "
            f"stripped, doubled or collapsed back to the empty era without "
            f"rotating this census in the same commit")

# R2: docs pair custody - the ledger row and the CHANGELOG entry name the era.
def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None

DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*101\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK101 R2: no row 101 in the checks table")
    elif "RT-094" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK101 R2: row 101 does not name RT-094")
if CHLOG is not None:
    for idiom in ("RT-094", "Check 101"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK101 R2: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK101: %d browse-failure custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK101: every RT-094 browse scene routes failure through its")
print("  choke to the failure copy with a focusable retry, the empty verdicts")
print("  keep their sole writers, and the era keeps its custody in the")
print("  checks ledger and the CHANGELOG")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 102: the RT-093 server-id shape custody keeps every shipped limb (w16L5) ==="
# NUMBERING: next-FREE probe at this lane's tree - 101 is the highest header
# (w15L9 era) and grep found zero 102 mentions anywhere in scripts/ docs/
# tests/ Makefile, so 102 is free. CHECK73's derivation self-pins this era:
# every plant below is scratch-local (asserts ride GREEN102/RED102 vars, not
# $POSITIVE_OUT), so the header-pin set does NOT rotate - the rotation this
# commit carries instead is the twin PASS-echo + ledger-row era narration
# (the CHECK73 R-ROKU-29 precedent, w15L9 CHECK100/101 form) and the docs
# pair (R2 arms below).
# WHY (review roku__exploiter #2, card w16 L5): server-RETURNED ids - the
# values a federated box chooses - were the one id family the launch-arg and
# server-id gates never judged. They ride API payloads into typed scene
# parameters (LoadItem/LoadSeason/LoadCollection - invalid or numeric values
# raise a render-thread Type Mismatch), into grid routing, into custody
# slots (pendingUpNext/pendingResume armed before judgment under RT-091's
# law), into the cache-custody keys, and at transport into raw
# "/media/" + itemId concatenation (the review's x/../../admin/users,
# x?profile=1, x#frag, x&extra=1 each reshape the Bearer-authenticated GET;
# the numeric class crashes the task thread BEFORE m.top.response lands,
# latching caller-side mutation/play guards forever). The cure is layered:
# producer gates at every named routing/arming site (component scope - no
# headless battery can reach them: the CHECK100/101 static-census doctrine
# is their honest home), a transport choke in components/ApiTask.brs (its
# pure legs ARE executed by tests/unit/ContentIdGuard.test.brs through the
# EXTRA_SOURCES door - that suite is this leg's dynamic twin), and UrlEncode
# at every id-path interpolation in source/lib/ApiClient.brs (identity on
# the admitted alphabet, zero wire change). Exact-equality arms: a limb
# stripped, doubled or reverted reddens BY ARM NAME without rotating this
# census in the same commit.
# R3 ERA NOTE (w16L5-R2): the HH review proved the positive-only arms can
# never convict a FUTURE raw id-path site (inserting one fired nothing). The
# negative-census leg re-derives the raw set every run and demands equality
# with a frozen provenance baseline - empty, because the full-set sweep now
# guards every id segment in the file (incl. the sessions sites whose
# "client-minted uuid" premise was falsified: session_id is a server payload
# value; GetSecureUuid exists nowhere in the repo).
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

# (path, label, regex, want) - counts MEASURED from disk at this commit.
ARMS = [
    ("components/PhlixApp.brs", "dl-response-gate",
     r'IsSafeContentId\(item\.id\)', 1),
    ("components/DetailScene.brs", "detail-entry-choke",
     r'IsSafeContentId\(itemId\)', 1),
    ("components/DetailScene.brs", "detail-similar-gate",
     r'IsSafeContentId\(mediaId\)', 1),
    ("components/DetailScene.brs", "detail-collection-mutation-gates",
     r'IsSafeContentId\(collectionId\)', 2),
    ("components/DetailScene.brs", "detail-item-rejudge",
     r'IsSafeContentId\(m\.itemId\)', 2),
    ("components/CollectionScene.brs", "col-route-gate",
     r'IsSafeContentId\(item\.id\)', 1),
    ("components/CollectionScene.brs", "col-entry-choke",
     r'IsSafeContentId\(collectionId\)', 1),
    ("components/FavoritesScene.brs", "fav-route-gate",
     r'IsSafeContentId\(item\.id\)', 1),
    ("components/SearchScene.brs", "sea-route-gate",
     r'IsSafeContentId\(item\.id\)', 1),
    ("components/LibraryScene.brs", "lib-route-gate",
     r'IsSafeContentId\(item\.id\)', 1),
    ("components/HomeScene.brs", "home-rail-gates",
     r'IsSafeContentId\(mediaItemId\)', 2),
    ("components/PlayerScene.brs", "player-upnext-gate",
     r'IsSafeContentId\(mediaItemId\)', 1),
    ("components/ApiTask.brs", "task-op-set-def",
     r'function OpCarriesContentId\(op as Dynamic\) as Boolean', 1),
    ("components/ApiTask.brs", "task-choke-def",
     r'function ContentIdRequestRefused\(req as Object\) as Boolean', 1),
    ("components/ApiTask.brs", "task-reason-def",
     r'function InvalidContentIdReason\(\) as String', 1),
    ("components/ApiTask.brs", "task-dispatch-arm",
     r'if ContentIdRequestRefused\(req\) then', 1),
    ("components/ApiTask.brs", "task-token-write",
     r'result\.error = InvalidContentIdReason\(\)', 1),
    ("components/ApiTask.brs", "task-cache-getkey",
     r'"/media/" \+ UrlEncode\(req\.itemId\)', 1),
    ("components/ApiTask.brs", "task-cache-inval-keys",
     r'"GET:/media/" \+ UrlEncode\(itemId\)', 2),
    ("source/lib/ApiClient.brs", "media-paths-encoded",
     r'"/media/" \+ UrlEncode\(', 10),
    ("source/lib/ApiClient.brs", "history-path-encoded",
     r'"/users/me/history/" \+ UrlEncode\(', 1),
    ("source/lib/ApiClient.brs", "collection-paths-encoded",
     r'"/collections/" \+ UrlEncode\(', 3),
    ("source/lib/ApiClient.brs", "transcode-status-encoded",
     r'"/transcode/" \+ UrlEncode\(', 1),
]

problems = []
for path, label, rx, want in ARMS:
    if not os.path.exists(path):
        problems.append(f"  {path} - CHECK102 R1 [{label}]: the RT-093 carrier vanished")
        continue
    with open(path, encoding="utf-8") as f:
        src = f.read()
    got = len(re.findall(rx, src))
    if got != want:
        problems.append(
            f"  {path} - CHECK102 R1 [{label}]: expected exactly {want}, "
            f"found {got} - the RT-093 server-id custody limb was stripped, "
            f"doubled or reverted without rotating this census in the same "
            f"commit")

# R2: docs pair custody - the ledger row and the CHANGELOG entry name the era.
def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None

DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*102\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK102 R2: no row 102 in the checks table")
    elif "RT-093" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK102 R2: row 102 does not name RT-093")
if CHLOG is not None:
    for idiom in ("RT-093", "Check 102"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK102 R2: does not name %s" % idiom)

# R3 (w16L5-R2): NEGATIVE census. The R1 arms count only ENCODED sites, so a
# future RAW id-path concat anywhere in source/lib/ApiClient.brs was gate-
# invisible - the exact asymmetry the HH review convicted (verdict item 4).
# This arm re-derives the raw set every run and demands equality with the
# frozen BASELINE below, whose entries carry their server-derived provenance
# note, so the gate encodes the truth and not just a number.
#
# BASELINE is EMPTY by construction of w16L5-R2: every id segment in the file
# now rides UrlEncode (the full-set sweep closed the 34-site residual census
# the register miscounted, incl. the sessions sites whose "client-minted"
# premise was falsified - session_id is a SERVER payload value). A site may
# enter the baseline only with a provenance note (id source + why lawful raw);
# a NEW raw site convicts by family and file:line, and silently encoding a
# baseline site convicts too - rotate the census in the same commit.
BASELINE = {}
# (path, path-literal, id-expr) -> (allowed count, provenance note)

from collections import Counter
RAW_FILES = ("source/lib/ApiClient.brs", "components/ApiTask.brs")
RAW = re.compile(r'("(?:/[A-Za-z0-9._-]+)+/")( \+ )(?!UrlEncode[A-Za-z0-9_]*\()([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)')
derived = Counter()
first_line = {}
for API in RAW_FILES:
    if not os.path.exists(API):
        problems.append("  %s - CHECK102 R3: the RT-093 carrier vanished" % API)
        continue
    with open(API, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            probe = line.lstrip()
            if probe.startswith("'") or probe[:4].lower() in ("rem ", "rem\t"):
                continue
            for mt in RAW.finditer(line):
                key = (API, mt.group(1), mt.group(3))
                derived[key] += 1
                first_line.setdefault(key, i)
for key in sorted(derived):
    want, _note = BASELINE.get(key, (0, ""))
    if derived[key] > want:
        fam = key[1].strip('"')
        problems.append(
            '  %s:%d - CHECK102 R3 [%s]: raw id-path concat "%s + %s" is '
            'outside the frozen negative baseline (%d found, %d allowed) - '
            'wrap the id segment in UrlEncode or enter the site with a '
            'server-derived provenance note' % (key[0], first_line[key], fam, key[1], key[2], derived[key], want))
for key in sorted(BASELINE):
    if derived.get(key, 0) < BASELINE[key][0]:
        fam = key[1].strip('"')
        problems.append(
            '  %s - CHECK102 R3 [%s]: baseline raw site vanished (%d expected, '
            '%d found) - rotate the negative census in the same commit as the '
            'code' % (key[0], fam, BASELINE[key][0], derived.get(key, 0)))

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK102: %d server-id custody pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK102: every RT-093 gate - deep-link response routing, detail/browse/")
print("  rail/up-next producers, the transport choke and the encoded path and")
print("  cache-custody sites - stands where the review landed it; the R3")
print("  negative census holds source/lib/ApiClient.brs raw-free against its")
print("  provenance-bearing baseline; and the era")
print("  keeps its custody in the checks ledger and the CHANGELOG")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 103: the chapter-label fade keeps one Timer child, stop/start re-arm, change-only showing and hide-once firing (ROK-5) ==="
# NUMBERING: next-FREE probe at this lane's tree - 102 is the highest header
# (w16L5 era) and `git grep -i 'check 103\|CHECK103'` returned rc=1 over the
# whole tree at b65c591, so 103 is free. CHECK73's derivation self-pins this
# era: every plant below is scratch-local (asserts ride GREEN103/RED103 vars,
# not $POSITIVE_OUT), so the header-pin set does NOT rotate (the CHECK102
# form).
# WHY (ROK-5, round-2026-11-11 roku plan step ROK-S5): UpdateChapterLabel ran
# on EVERY Video position tick (~2/s) and, inside a chapter, called
# ShowChapterLabel every time - which stopped, unobserved and REMOVED the
# running Timer child and minted a brand-new one. The 2s countdown restarted
# on every tick, so the fade NEVER fired: the label sat over the picture for
# the whole chapter, and the scene churned a Timer node create/append/remove
# twice a second. The cure is three laws plus the fire's own contract:
#   single child  - ArmChapterLabelTimer lazily mints ONE Timer (guarded by
#                   `if m.chapterLabelTimer = invalid`), observes it once, and
#                   ClosePlayer is the ONE release site; Show() stops the live
#                   countdown instead of invalidating (orphaning) the child.
#   stop/start    - the re-arm is control "stop" then "start" on that same
#                   node; no other site starts it.
#   change-only   - UpdateChapterLabel re-shows only when the chapter INDEX
#                   changes; a user seek records the index it lands on so the
#                   next tick does not re-arm a second time.
#   hide-once     - OnChapterLabelTimerFire ONLY hides: it never re-arms,
#                   restarts, re-shows, releases or re-mints, so each chapter
#                   entry yields exactly one 2s window and one fade.
# These are device-side Timer/render writes - brs mocks unknown roSGNode
# types as Invalid, so no headless battery reaches them (the CHECK100/101
# static-census doctrine is their honest home). Exact-equality arms over
# comment-masked bodies: a limb stripped, doubled or reverted reddens BY ARM
# NAME without rotating this census in the same commit.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)

PS = "components/PlayerScene.brs"
problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def mask(text):
    # full-line comments only (no carrier line here carries a trailing one)
    out = []
    for line in text.splitlines():
        probe = line.lstrip()
        if probe.startswith("'") or probe[:4].lower() in ("rem ", "rem\t"):
            continue
        out.append(line)
    return "\n".join(out)


SRC = read(PS)
if SRC is None:
    problems.append("  %s - CHECK103 R0: the ROK-5 carrier vanished" % PS)
    SRC = ""
SRC = mask(SRC)

BODY_RX = r"(?ms)^(?:sub|function) %s\(.*?^end (?:sub|function)"
NAMES = ("Show", "OnPositionUpdate", "UpdateChapterLabel", "ShowChapterLabelAt",
         "ShowChapterLabel", "ArmChapterLabelTimer", "OnChapterLabelTimerFire",
         "ClosePlayer", "SeekRelative")
BODIES = {}
for name in NAMES:
    found = re.findall(BODY_RX % re.escape(name), SRC)
    if SRC and len(found) != 1:
        problems.append("  %s - CHECK103 R0: %d/1 bodies named %s - the ROK-5 "
                        "carrier shape drifted; rotate this leg in lockstep, never "
                        "let it go vacuous" % (PS, len(found), name))
    BODIES[name] = found[0] if len(found) == 1 else ""


def scope_text(scope):
    kind, _, name = scope.partition(":")
    if kind == "file":
        return SRC
    if kind == "body":
        return BODIES.get(name, "")
    if kind == "outside":
        body = BODIES.get(name, "")
        return SRC.replace(body, "", 1) if body else SRC
    raise SystemExit("CHECK103: unknown scope %s" % scope)


# (law, label, scope, regex, want) - counts MEASURED from disk at this commit.
ARMS = [
    # single child
    ("R1", "timer-mint-single", "file",
     r'm\.chapterLabelTimer = CreateObject\("roSGNode", "Timer"\)', 1),
    ("R1", "timer-mint-lazy", "body:ArmChapterLabelTimer",
     r'if m\.chapterLabelTimer = invalid then\s*\n\s*m\.chapterLabelTimer = CreateObject\(', 1),
    ("R1", "timer-observe-once", "body:ArmChapterLabelTimer",
     r'm\.chapterLabelTimer\.ObserveField\("fire", "OnChapterLabelTimerFire"\)', 1),
    ("R1", "timer-one-shot", "body:ArmChapterLabelTimer",
     r'm\.chapterLabelTimer\.repeat = false', 1),
    ("R1", "timer-two-seconds", "body:ArmChapterLabelTimer",
     r'(?m)m\.chapterLabelTimer\.duration = 2\s*$', 1),
    ("R1", "release-in-teardown", "body:ClosePlayer",
     r'm\.top\.RemoveChild\(m\.chapterLabelTimer\)', 1),
    ("R1", "release-outside-teardown", "outside:ClosePlayer",
     r'RemoveChild\(m\.chapterLabelTimer\)', 0),
    ("R1", "never-orphaned-live", "outside:ClosePlayer",
     r'(?m)^\s*m\.chapterLabelTimer = invalid\s*$', 0),
    # stop/start
    ("R2", "arm-stop-start", "body:ArmChapterLabelTimer",
     r'm\.chapterLabelTimer\.control = "stop"\s*\n\s*m\.chapterLabelTimer\.control = "start"', 1),
    ("R2", "start-outside-arm", "outside:ArmChapterLabelTimer",
     r'm\.chapterLabelTimer\.control = "start"', 0),
    ("R2", "arm-sole-route", "body:ShowChapterLabel",
     r'(?m)^\s*ArmChapterLabelTimer\(\)\s*$', 1),
    # change-only
    ("R3", "tick-routes-update", "body:OnPositionUpdate",
     r'UpdateChapterLabel\(position, duration\)', 1),
    ("R3", "change-only-gate", "body:UpdateChapterLabel",
     r'if idx = m\.chapterLabelIndex then return\s*\n\s*m\.chapterLabelIndex = idx\s*\n\s*ShowChapterLabelAt\(idx\)', 1),
    ("R3", "seek-records-index", "body:SeekRelative",
     r'm\.chapterLabelIndex = GetChapterIndexAtPosition\(newPosition, duration\)\s*\n\s*ShowChapterLabelAt\(m\.chapterLabelIndex\)', 1),
    ("R3", "label-sole-route", "outside:ShowChapterLabelAt",
     r'(?<!sub )\bShowChapterLabel\(', 0),
    # hide-once
    ("R4", "fire-hides", "body:OnChapterLabelTimerFire",
     r'm\.chapterLabel\.visible = false', 1),
    ("R4", "fire-never-rearms", "body:OnChapterLabelTimerFire",
     r'\.control\b|ArmChapterLabelTimer|ShowChapterLabel|RemoveChild|Append|CreateObject|chapterLabelTimer = ', 0),
]

if SRC:
    for law, label, scope, rx, want in ARMS:
        got = len(re.findall(rx, scope_text(scope)))
        if got != want:
            problems.append(
                "  %s - CHECK103 %s [%s]: expected exactly %d, found %d - the "
                "ROK-5 chapter-label fade limb was stripped, doubled or "
                "reverted without rotating this census in the same commit"
                % (PS, law, label, want, got))

# R5: docs pair custody - the ledger row and the CHANGELOG entry name the era.
DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*103\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK103 R5: no row 103 in the checks table")
    elif "ROK-5" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK103 R5: row 103 does not name ROK-5")
if CHLOG is not None:
    for idiom in ("ROK-5", "Check 103"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK103 R5: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK103: %d chapter-label fade pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK103: the chapter-label fade keeps its ROK-5 limbs - one lazily")
print("  minted Timer child released only at teardown, a stop/start re-arm with")
print("  no second starter, change-only showing on the position tick and the")
print("  seek, a fire that only hides - and the era keeps its custody in the")
print("  checks ledger and the CHANGELOG")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 104: image-lane URLs route through the admissibility leaf and degrade to the placeholder (ROK-14 / ROK-36) ==="
# NUMBERING: next-free after 103. Scratch-local, no header-pin rotation (the
# CHECK103 form). WHY: server-supplied poster/thumbnail/photo urls were
# assigned to Poster/Image uri raw, so an http:// image off an https origin
# (or a file/data/userinfo shape) loaded unchecked. The cure is the pure
# IsImageUrlAdmissible leaf + SafeImageUrl degrade arm; this census holds
# every carrier on it.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)
problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def mask(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


UT = read("source/lib/Utilities.brs")
if UT is None:
    problems.append("  source/lib/Utilities.brs - CHECK104 R0: carrier vanished")
    UT = ""
UT = mask(UT)
for name, want in (("IsImageUrlAdmissible", 1), ("SafeImageUrl", 1)):
    got = len(re.findall(r"(?m)^function %s\(" % name, UT))
    if got != want:
        problems.append("  source/lib/Utilities.brs - CHECK104 R1 [%s-def]: expected %d, found %d" % (name, want, got))
m = re.search(r"(?ms)^function IsImageUrlAdmissible\(.*?^end function", UT)
body = m.group(0) if m else ""
for label, rx in (("pkg-arm", r'Left\(s, 5\) = "pkg:/"'),
                  ("delegates", r"IsStreamUrlAdmissible\(")):
    if len(re.findall(rx, body)) != 1:
        problems.append("  source/lib/Utilities.brs - CHECK104 R1 [%s]: expected exactly 1" % label)

# (path, label, regex, want)
SITES = [
    ("components/PhotoAlbumScene.brs", "album-thumb", r"SafeImageUrl\(GetServerUrl\(\), photo\.thumbnail_url\)", 1),
    ("components/PhotoAlbumScene.brs", "album-thumb-raw", r"= photo\.thumbnail_url\s*$", 0),
    ("components/PhotosScene.brs", "cover-thumb", r"SafeImageUrl\(GetServerUrl\(\), cover\.thumbnail_url\)", 1),
    ("components/PhotosScene.brs", "cover-thumb-raw", r"= cover\.thumbnail_url\s*$", 0),
    ("components/PhotoViewerScene.brs", "full-url", r"SafeImageUrl\(GetServerUrl\(\), photo\.full_url\)", 1),
    ("components/PhotoViewerScene.brs", "full-url-raw", r"= photo\.full_url\s*$", 0),
    ("components/DetailScene.brs", "poster", r"m\.posterImage\.uri = SafeImageUrl\(GetServerUrl\(\), posterUrl\)", 1),
    ("components/DetailScene.brs", "poster-raw", r"m\.posterImage\.uri = posterUrl\s*$", 0),
    ("components/DetailScene.brs", "similar", r"HDPosterUrl = SafeImageUrl\(GetServerUrl\(\), sim\.posterUrl\)", 1),
    ("components/DetailScene.brs", "similar-raw", r"HDPosterUrl = sim\.posterUrl\s*$", 0),
    ("components/HomeScene.brs", "upnext", r"return SafeImageUrl\(GetServerUrl\(\), (?:meta|item)\.poster(?:_url)?\)", 6),
    ("components/HomeScene.brs", "upnext-raw", r"return (?:meta|item)\.poster(?:_url)?\s*$", 0),
]
for path, label, rx, want in SITES:
    t = read(path)
    if t is None:
        problems.append("  %s - CHECK104 R2 [%s]: carrier vanished" % (path, label))
        continue
    got = len(re.findall(r"(?m)" + rx, mask(t)))
    if got != want:
        problems.append("  %s - CHECK104 R2 [%s]: expected exactly %d, found %d - an image-lane carrier was un-gated or reshaped without rotating this census" % (path, label, want, got))

DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*104\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK104 R3: no row 104 in the checks table")
    elif "ROK-14" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK104 R3: row 104 does not name ROK-14")
if CHLOG is not None:
    for idiom in ("ROK-14", "Check 104"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK104 R3: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK104: %d image-lane admissibility pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK104: every image-lane carrier routes through SafeImageUrl over the")
print("  IsImageUrlAdmissible leaf, no raw assignment survives, and the era keeps")
print("  its custody in the checks ledger and the CHANGELOG")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo "=== Check 105: the memory-tier page size reaches every paged scene and cache-defaulting task site (ROK-25) ==="
# NUMBERING: next-free after 104. GetPageSize() (AppContext) was defined with
# zero callers, so the documented R6.8 tier promise never reached a request.
PYRET=0
PYOUT=$(
	python3 - <<'PYEOF'
import os, re, sys

repo = os.environ.get("PHLIX_ROKU_REPO") or os.environ.get("REPO") or "."
os.chdir(repo)
problems = []


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def mask(text):
    return "\n".join(l for l in text.splitlines()
                     if not l.lstrip().startswith("'"))


AC = read("source/lib/AppContext.brs")
if AC is None:
    problems.append("  source/lib/AppContext.brs - CHECK105 R0: carrier vanished")
    AC = ""
AC = mask(AC)
if len(re.findall(r"(?m)^function GetPageSize\(\) as Integer", AC)) != 1:
    problems.append("  source/lib/AppContext.brs - CHECK105 R1 [def]: GetPageSize expected exactly 1 definition")

# (path, label, regex, want)
SITES = [
    ("components/SeasonScene.brs", "season", r"^\s*m\.limit = GetPageSize\(\)", 1),
    ("components/SeriesScene.brs", "series", r"^\s*m\.limit = GetPageSize\(\)", 1),
    ("components/FavoritesScene.brs", "favorites", r"^\s*m\.limit = GetPageSize\(\)", 1),
    ("components/AudiobookScene.brs", "audiobook", r"^\s*m\.limit = GetPageSize\(\)", 1),
    ("components/ApiTask.brs", "task-defaults", r"^\s*limit = GetPageSize\(\)", 3),
    ("components/SeasonScene.brs", "season-raw", r"^\s*m\.limit = \d+\s*$", 0),
    ("components/SeriesScene.brs", "series-raw", r"^\s*m\.limit = \d+\s*$", 0),
    ("components/FavoritesScene.brs", "favorites-raw", r"^\s*m\.limit = \d+\s*$", 0),
    ("components/AudiobookScene.brs", "audiobook-raw", r"^\s*m\.limit = \d+\s*$", 0),
]
for path, label, rx, want in SITES:
    t = read(path)
    if t is None:
        problems.append("  %s - CHECK105 R2 [%s]: carrier vanished" % (path, label))
        continue
    got = len(re.findall(r"(?m)" + rx, mask(t)))
    if got != want:
        problems.append("  %s - CHECK105 R2 [%s]: expected exactly %d, found %d - a page-size caller was stripped or reshaped without rotating this census" % (path, label, want, got))

DOCS = read(os.path.join("docs", "static-checks.md"))
CHLOG = read("CHANGELOG.md")
if DOCS is not None:
    row = re.search(r"(?m)^\|\s*105\s*\|.*$", DOCS)
    if not row:
        problems.append("  docs/static-checks.md - CHECK105 R3: no row 105 in the checks table")
    elif "ROK-25" not in row.group(0):
        problems.append("  docs/static-checks.md - CHECK105 R3: row 105 does not name ROK-25")
if CHLOG is not None:
    for idiom in ("ROK-25", "Check 105"):
        if idiom not in CHLOG:
            problems.append("  CHANGELOG.md - CHECK105 R3: does not name %s" % idiom)

if problems:
    for prob in problems:
        print(prob)
    print("  CHECK105: %d page-size wiring pin(s) broken" % len(problems))
    sys.exit(1)

print("  CHECK105: GetPageSize is defined once and called by every paged scene and")
print("  the three ApiTask limit defaults; no literal m.limit survives")
PYEOF
) || PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

exit $((VIOLATIONS))
