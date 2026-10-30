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
	while IFS=: read -r line content; do
		ids=$(echo "$content" | grep -oP 'FindNode\s*\(\s*"\K[^"]+' 2>/dev/null || true)
		for id in $ids; do
			if [[ "$id" == *'$'* ]] || [[ "$id" == *'{'* ]]; then continue; fi
			# Extract all content between <children> and </children> and search for id=
			children_content=$(awk '/^[[:space:]]*<\/children>/{found=0} found{print} /^[[:space:]]*<children>/{found=1; next} END{if(found)print}' "$xml" 2>/dev/null || true)
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
# https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md
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
# Valid Roku remote keys per https://developer.roku.com/docs/references/scenegraph/remote-control-events.md
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
    # re-pinned it onto the predicate's own line.
    ('source/lib/Utilities.brs', 121): re.compile(r'if h = "localhost" then return true'),
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
        # Error dialog strings — these ARE user-facing and should be in locale
        if 'ShowErrorDialog' in line:
            # The string after ShowErrorDialog — check if it's in the call
            if string_literals and len(string_literals) >= 3:
                is_ui_context = True

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
#   EMITTED_VERIFIED (19, post-flip): read off phlix-server origin/master
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
#       Translate()'s nested-probe sections list still includes "errors"
#   (d) SyncPlayTask.brs still routes syncplay_error text through
#       LocalizeSyncPlayError() (wire-in present)
#   (e) CENSUS CONTENT: set(census) == EMITTED_VERIFIED | RESERVED exactly -
#       a planted 20th code, a renamed member or a silently re-admitted
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
    if not re.search(r'sections = \[[^\]]*"errors"[^\]]*\]', util):
        problems.append(
            f'  {UTILITIES} - CHECK22: Translate() nested-probe sections list no '
            'longer includes "errors"')

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
#   (c) WIRE-CENSUS HONESTY: SyncPlayKnownErrorCodes() still lists exactly 19
#       wire codes (19 emitted-verified + 0 declared-reserved post-flip per Check 22's
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
    if len(wire_codes) != 19:
        problems.append(
            f"  {UTILITIES} - CHECK23: wire census must stay the 19 "
            "wire-honest codes (19 emitted-verified + 0 declared-reserved), "
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
# in the XML header row (the Button nodes at y=20), in visual x-order, so the
# Settings entry — and the SettingsScene behind it (logout, caption mode,
# server switch, playback prefs) — is reachable with the remote d-pad alone.
# The era chain skipped settingsButton entirely: Right stepped collections->
# admin (isAdmin) and Left stepped admin->collections; every header transition
# returned handled=true, so Roku's spatial-search fallback never fired and
# Settings was HARD unreachable for admins (and desynced m.headerCol for
# non-admins that fell through to it). Rules:
#   R1  header candidates parsed from HomeScene.xml y=20 Buttons, ordered by x;
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

# R1: header candidates are the Button nodes riding the y=20 row; the remote's
# natural horizontal order is their x order.
head = []
for m in re.finditer(r'<Button[^>]*?translation="\[(\d+),20\]"[^>]*?id="(\w+)"', xml):
    head.append((int(m.group(1)), m.group(2)))
head.sort()
cols = [nid[:-len("Button")] for _, nid in head]
if "settings" not in cols:
    problems.append('HomeScene.xml: CHECK29 R1: header row (y=20 Buttons) has no '
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
        # The admin arm may additionally require adminButton.visible (the
        # post-demotion restore guard; CHECK32 R1 pins that it DOES).
        guard = r'( and m\.adminButton\.visible)?' if col == "admin" else r''
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
for m in re.finditer(r'<Button[^>]*?translation="\[(\d+),20\]"[^>]*?title="([^"]*)"', xml):
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
# (all scoped via \b so the wrapper's own name DeviceCanDecodeVideo - whose
# public String signature is deliberately preserved - never trips them):
#   R1  no .brs file (comments stripped) contains a bare receiver-form
#       CanDecodeVideo( call with a comma inside its argument list - the
#       positional shape stays dead
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
for p in brs_files:
    code = strip_comments(read(p))
    for m in re.finditer(r'\bCanDecodeVideo\s*\(([^)]*)\)', code):
        if "," in m.group(1):
            problems.append(f"  {p} - CHECK35 R1: positional CanDecodeVideo({m.group(1).strip()}) "
                            "call - the SDK takes ONE options associative array (M-ROKU-05)")

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
#       640 — cf. DetailScene.xml's loadingLabel [640,340]). XML comments are
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
#   R5  Eval() is extinct in shipped .brs — Roku's docs state Eval() "cannot
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
# code_view idiom, scoped to this leg).
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
            if re.search(r'\bEval\s*\(', code_view(line)):
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
    if not re.search(r"zip -r \$\(PKG_NAME\)\.zip source components images locale", mk):
        problems.append(
            f"  {MK} - CHECK41 R5: the package recipe no longer zips "
            "`source components images locale` — the doc's archive-contract claim is "
            "pinned to this exact line; rotate the doc, scripts/verify-package.sh and "
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
#       variable. Guard-token lines (SafeErrorMessage/WireErrorPresent/
#       WireErrorText/the "roString"/"String" type-gate literals) are exempt
#       - arms (a)-(d) test the token on the CODE-MASKED text (a comment
#       naming a guard cannot buy exemption, review r1 minor), (e) keeps the
#       raw-line token (the sanctioned choke-lift allowance). `.top`-
#       prefixed reads are RSG-typed and exempt.
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
# type-gate literals survive the code mask below precisely so they stay
# visible to this check.
GUARDED = re.compile(r'SafeErrorMessage\(|WireErrorPresent\(|WireErrorText\(|"roString"|"String"')
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

    The type-gate guard literals ("roString"/"String") are KEPT verbatim:
    they are themselves GUARDED tokens and masking them away would make
    the r1 code-mask hardening blind the type-guard idiom it audits
    (PlayerScene's `type(ev.message) = "roString"` family)."""
    def mask(match):
        literal = match.group(0)
        return literal if literal in ('"roString"', '"String"') else '""'
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
            why = None
            if not GUARDED.search(code):
                # Arms (a)-(d): the guard token must live in CODE, not in a
                # comment on the line (review r1 minor - code-mask hardening).
                if RAW_COMPARE.search(code):
                    why = "compares wire .error/.message against a string literal"
                elif RAW_STRINGOP.search(code):
                    why = "string operation on a raw wire .error/.message value"
                elif RAW_CONCAT.search(code):
                    why = "concatenates a raw wire .error/.message value via + (into/out of a string)"
                else:
                    match = CALL_ARG.search(code)
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
#   R2  OnPendingHubCommand guards data.mediaId through IsSafeContentId BEFORE
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
    if body is None:
        problems.append(f"  {PA} - CHECK45 R2: OnPendingHubCommand is gone")
    else:
        text = body.group(0)
        if re.search(r'data\.mediaId\s*=\s*invalid\b|data\.mediaId\s*=\s*""', text):
            problems.append(f"  {PA} - CHECK45 R2: the raw `data.mediaId = invalid or = \"\"` era form is back")
        gi = text.find("IsSafeContentId(data.mediaId)")
        pi = text.find("ProcessDeepLink()")
        if gi < 0:
            problems.append(f"  {PA} - CHECK45 R2: OnPendingHubCommand no longer gates data.mediaId through IsSafeContentId")
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
#       http->https /health 301 must still probe green).
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
#       ladder line and catalog message x7; catalogs bump as a set (1.10.0).
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
                          ("RedirectHopLimit()", "the manual chain must be bounded")):
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
                 "ResolveRedirectTarget"):
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
    if cat.get("_metadata", {}).get("version") != "1.10.0":
        problems.append(f"  {path} - CHECK48 R3: _metadata.version is not 1.10.0 — the catalogs bump as a set with this law")

# ---- R4 the device harness pins the law -----------------------------------
test = read(TEST)
if test is None:
    problems.append(f"  {TEST} - CHECK48 R4: the M-ROKU-15 custody unit suite vanished")
else:
    for name in ("TestHostOfUrlVectors", "TestIsPrivateHostAddressTruthTable",
                 "TestCleartextRemoteGateTruthTable", "TestOriginOfUrlNormalization",
                 "TestCredentialSafeRedirectHopLaw", "TestResolveRedirectTargetShapes",
                 "TestRedirectBucketClassification"):
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
print("           refusal and the dialog; the unit suite pins every pure leaf")
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

exit $((VIOLATIONS))
