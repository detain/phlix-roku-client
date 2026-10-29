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
    # Utilities.brs: localhost detection for scheme inference
    ('source/lib/Utilities.brs', 91): re.compile(r'if lower\.Left\(9\) = "localhost"'),
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
    "components/ToastScene.xml": {
        "Toast text here": "never rendered - visible=false and init replaces "
                           "the text with m.top.message"},
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
EXPECTED = {"bad_url", "dns", "refused", "tls", "timeout", "unreachable"}

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

exit $((VIOLATIONS))
