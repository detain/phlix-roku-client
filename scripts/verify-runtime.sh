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
ALLOW_LIST="command content control currentTime duration endpoint errorMsg focusRing isFullscreen isPhoto loggingUrl manifestHDRType maxHeight maxWidth position rate retargetHeight retargetWidth secureChainingUrl securityKey stream streamFormat streamInfo subtitleStream textTrackTrack track transferType videoLocation videoNode wasPlaying wideAsync EnableCookies SetCertificatesFile ObserveField UnObserveField SetFocus globalCaptionMode seek audioTrack availableAudioTracks subtitleTracks currentSubtitleTrack errorCode width height translation volume isUnderlyingStreamPlaying notificationPeriod positionAsOfNow bifDisplay"
VIOLATIONS=0
while IFS=: read -r file line; do
	field=$(echo "$line" | sed 's/.*m\.videoPlayer\.\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/' | grep -oP '[a-zA-Z_][a-zA-Z0-9_]*' | head -1)
	if [[ -n "$field" ]] && ! echo "$ALLOW_LIST" | grep -qw "$field"; then
		echo "  $file — CHECK8: m.videoPlayer.$field is not a real Video node field"
		VIOLATIONS=1
	fi
done < <(git grep -n 'm\.videoPlayer\.' -- '*.brs' 2>/dev/null || true)
[[ $VIOLATIONS -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 9: OnKeyEvent invalid Roku remote keys (maps to §3.6) ==="
# Valid Roku remote keys per https://developer.roku.com/docs/references/scenegraph/remote-control-events.md
ALLOW_KEYS="back up down left right OK replay play rewind fastforward options info"
VIOLATIONS=0
for brs in $(git ls-files -- '*.brs'); do
	if [[ "$brs" == tests/* ]]; then continue; fi
	if grep -q 'sub OnKeyEvent' "$brs"; then
		keys=$(grep -oP 'key\s*[=!]=\s*"\K[^"]+' "$brs" 2>/dev/null || true)
		for key in $keys; do
			if ! echo "$ALLOW_KEYS" | grep -qw "$key"; then
				line_num=$(grep -n "[\"']$key[\"']" "$brs" | head -1 | cut -d: -f1)
				echo "  $brs:$line_num — CHECK9: OnKeyEvent compares key '$key' which is not a valid Roku remote key"
				VIOLATIONS=1
			fi
		done
	fi
done
[[ $VIOLATIONS -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 10: blocking network outside ApiTask (maps to §5.3) ==="
VIOLATIONS=0
while IFS=: read -r file line; do
	if [[ "$file" != components/ApiTask* ]]; then
		echo "  $file:$line — CHECK10: blocking network call (ApiClient.wait/sync) on render thread"
		VIOLATIONS=1
	fi
done < <(git grep -rn 'ApiClient\.\(wait\|sync\)' -- '*.brs' 2>/dev/null || true)
[[ $VIOLATIONS -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 11: unguarded Task control=run (R1.4: busy guard required) ==="
VIOLATIONS=0
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
TRANSLATE_RE = re.compile(r'Translate\(\s*"([A-Za-z0-9_]+)"')


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
# server-emitted at verification time. The syncplay twin flip adds
# syncplay.create_failed / join_failed / leave_failed (contracts-registered,
# reserved, NOT yet emitted) BEFORE the server starts sending them, so
# "known" is now a SUPERSET law: census ⊇ emitted, and the law is machine-
# enforced by CONTENT equality against an explicit split instead of a count:
#   EMITTED_VERIFIED (16): 12 legacy SCREAMING + 4 dotted twins, read off
#     phlix-server origin/master e0e010b07c7f4cc21baf10d9a945bac24edab45c
#     sendError literals (src/Session/SyncPlay/SyncPlayManager.php +
#     src/Server/WebSocket/MessageHandler.php; re-verify READ-ONLY at each
#     flip step - a code may only LEAVE this set when its server family
#     retires).
#   RESERVED (3): dotted twins in the phlix-contracts error registry
#     (dist/error-codes.json) awaiting the flip; promoted to emitted on flip,
#     census and catalogs unchanged.
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

# Wire truth - see the header above. Evidence: phlix-server origin/master
# e0e010b07c7f4cc21baf10d9a945bac24edab45c (2026-09-25, read-only grep of
# sendError / 'error_code' => literals; docblock-only GROUP_FULL /
# INVALID_PASSWORD examples in Messages.php are NOT wire codes).
EMITTED_VERIFIED = {
    "NOT_AUTHENTICATED", "NOT_IN_GROUP", "NOT_HOST", "UNKNOWN_MESSAGE",
    "HANDLER_ERROR", "PROTOCOL_VERSION_MISMATCH", "INVALID_NEW_HOST",
    "MEMBER_NOT_FOUND", "SAME_HOST", "CREATE_FAILED", "JOIN_FAILED",
    "LEAVE_FAILED",
    "syncplay.group_limit_reached", "syncplay.group_not_found",
    "syncplay.invalid_password", "syncplay.group_full",
}
RESERVED = {
    "syncplay.create_failed", "syncplay.join_failed", "syncplay.leave_failed",
}
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

print(f"  CHECK22: all 19 wire codes (16 emitted-verified + 3 declared "
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
#       wire codes (16 emitted-verified + 3 declared-reserved per Check 22's
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
            "wire-honest codes (16 emitted-verified + 3 declared-reserved), "
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

TP_KEY_RE = re.compile(r'TranslateWithParams\(\s*"([A-Za-z0-9_]+)"')
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

exit $((VIOLATIONS))
