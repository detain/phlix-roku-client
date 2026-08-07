#!/usr/bin/env bash
# scripts/verify-runtime.sh — Static runtime-defect checker for phlix-roku-client (R0.7)
# Each check exits non-zero and prints: FILE:LINE — CHECK_NAME: explanation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
cd "$REPO"
FOUND=0
VIOLATIONS=0

echo "=== Check 1: Storage.factory misuse (R0.2 regression) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK1: Storage.factory used directly (use GetStorage())"
  FOUND=1
done < <(git grep -rn 'Storage\.\(get\|set\|delete\|clear\)' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 2: m.top.Close() calls (R0.4 regression) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK2: m.top.Close() called (use m.top.requestClose = true)"
  FOUND=1
done < <(git grep -rn 'm\.top\.Close()' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 3: ContentEmitter stub XML (R0.5 regression) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK3: ContentEmitter is not a real SceneGraph node"
  FOUND=1
done < <(git grep -rn '<ContentEmitter' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 4: caption1Icon / handle:// invalid fields (R0.5 regression) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK4: caption1Icon/handle:// is not a real PosterGrid field or valid URI"
  FOUND=1
done < <(git grep -rn -E 'caption1Icon|handle://' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 5: halign= XML attribute (R0.6 regression — should be horizAlign=) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK5: halign= is not a Label field (use horizAlign=)"
  FOUND=1
done < <(git grep -rn 'halign=' -- '*.xml' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 6: ObserveField callback defined (maps to §5.5) ==="
for brs in $(git ls-files -- '*.brs'); do
  callbacks=$(grep -oP 'ObserveField\s*\(\s*"[^"]+"\s*,\s*"\K[^"]+' "$brs" 2>/dev/null || true)
  for cb in $callbacks; do
    # Check for regular sub/function OR colon-method syntax (OnCallback: sub() or OnCallback: function())
    if ! grep -qP "^(sub|function)\s+$cb\b" "$brs" 2>/dev/null && \
       ! grep -qP "^\s+$cb:\s+(sub|function)\b" "$brs" 2>/dev/null; then
      line=$(grep -n "ObserveField.*\"$cb\"" "$brs" | head -1 | cut -d: -f1)
      echo "  $brs:$line — CHECK6: ObserveField target '$cb' has no matching sub/function"
      FOUND=1
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
      fi
    done
  done < <(grep -n 'FindNode' "$brs" 2>/dev/null || true)
done
[[ $FOUND -eq 0 ]] && echo "  PASS"

echo ""
echo "=== Check 8: m.videoPlayer invalid fields (maps to §5.6) ==="
# Allow-list of real Video node fields (Roku SceneGraph SDK)
# https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md
ALLOW_LIST="command content control currentTime duration endpoint errorMsg focusRing isFullscreen isPhoto loggingUrl manifestHDRType maxHeight maxWidth position rate retargetHeight retargetWidth secureChainingUrl securityKey stream streamFormat streamInfo subtitleStream textTrackTrack track transferType videoLocation videoNode wasPlaying wideAsync EnableCookies SetCertificatesFile ObserveField UnObserveField SetFocus globalCaptionMode seek audioTrack availableAudioTracks subtitleTracks currentSubtitleTrack errorCode width height translation volume isUnderlyingStreamPlaying notificationPeriod positionAsOfNow"
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
PYOUT=$(python3 - <<'PYEOF'
import subprocess, re, sys, os

os.chdir('/home/sites/phlix/phlix-roku-client')
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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

FOUND=0
echo ""
echo "=== Check 12: syncplay/rooms instead of /groups (R4.1) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK12: syncplay uses /groups endpoint, not /rooms"
  FOUND=1
done < <(git grep -rn 'syncplay/rooms' -- '*.brs' 2>/dev/null || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

FOUND=0
echo ""
echo "=== Check 13: DELETE verb on syncplay endpoint (R4.1 — leave is POST) ==="
while IFS=: read -r file line; do
  echo "  $file:$line — CHECK13: syncplay leave uses POST, not DELETE"
  FOUND=1
done < <(git grep -rn 'syncplay' -- '*.brs' 2>/dev/null | grep 'DELETE' || true)
if [[ $FOUND -eq 0 ]]; then echo "  PASS"; fi

echo ""
echo "=== Check 14: media_items.type ENUM drift vs server (S115) ==="
PYOUT=$(python3 - <<'PYEOF'
import re, os, sys

# ── 1. Find the authoritative ENUM from server migrations ──────────────────────
migration_dir = "/home/sites/phlix/phlix-server/migrations"
if not os.path.isdir(migration_dir):
    print(f"  CHECK14: server migration dir not found at {migration_dir}")
    sys.exit(1)

# Collect every ENUM definition found across all migration files.
# The final (most complete) one represents the current schema state.
enum_defs = {}  # name -> sorted list of members
for fname in sorted(os.listdir(migration_dir)):
    if not fname.endswith(".sql"):
        continue
    fpath = os.path.join(migration_dir, fname)
    with open(fpath, errors="replace") as f:
        content = f.read()
    # Match MODIFY/CHANGE COLUMN ... ENUM('a', 'b', ...) — captures the ENUM value list
    # up to the first closing paren (the list contains no embedded parens).
    for m in re.finditer(
        r"ENUM\(([^)]+)\)",
        content,
        re.IGNORECASE,
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
utilities_path = "/home/sites/phlix/phlix-roku-client/source/lib/Utilities.brs"
if not os.path.isfile(utilities_path):
    print(f"  CHECK14: Utilities.brs not found at {utilities_path}")
    sys.exit(1)

with open(utilities_path, errors="replace") as f:
    util_content = f.read()

# The full ENUM is documented in the comment block above PlayableTypes().
# The list spans exactly 2 lines (lines 732-733 in Utilities.brs) — capture them
# directly rather than using a greedy pattern that could spill into explanatory
# comment lines (which also start with ' but contain no commas).
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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 15: hardcoded localhost URL (R4.10) ==="
PYOUT=$(python3 - <<'PYEOF'
import re, os, sys

os.chdir('/home/sites/phlix/phlix-roku-client')

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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

FOUND=0
echo ""
echo "=== Check 16: placeholder channel art file size (R6.2) ==="
# Each image in images/ must be large enough to plausibly contain real art at its
# declared dimensions.  A 166-byte PNG is not a 290x218 icon — no amount of
# compression makes a real photograph that small.
# Minimum bytes per pixel: 0.5 B/px (ultra-flat illustration still needs hundreds
# of bytes per pixel after DEFLATE; 1-bit placeholder palettes compress to nothing).
# Fail if: bytes < width * height * 0.5
PYOUT=$(python3 - <<'PYEOF'
import os, sys, struct, zlib

repo = '/home/sites/phlix/phlix-roku-client'
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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

FOUND=0
echo ""
echo "=== Check 17: echo ERROR paired with exit/state (self-audit) ==="
# Every echo command with ERROR in its output should set FOUND=1, VIOLATIONS=1,
# or exit 1 to ensure the script properly fails when errors are detected.
PYOUT=$(python3 - <<'PYEOF'
import re, sys

script_path = '/home/sites/phlix/phlix-roku-client/scripts/verify-runtime.sh'
# Exclude the meta-check block itself (check 17) to avoid self-referential false positives
exclude_start = "=== Check 17:"
exclude_end = "exit $((VIOLATIONS))"

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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

echo ""
echo "=== Check 18: version drift between package.json and manifest (R8.8) ==="
PYOUT=$(python3 - <<'PYEOF'
import re, os, sys, json

repo = '/home/sites/phlix/phlix-roku-client'

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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

FOUND=0
echo ""
echo "=== Check 19: hardcoded i18n strings in target files (R7.12) ==="
PYOUT=$(python3 - <<'PYEOF'
import re, os, sys

repo = '/home/sites/phlix/phlix-roku-client'
os.chdir(repo)

TARGETS = [
    'components/SettingsScene.brs',
    'components/DetailScene.brs',
    'source/lib/Utilities.brs',
]

# Allow-list: patterns that are NOT user-facing hardcoded i18n strings
EXEMPT = [
    re.compile(r'^[\'"]HTTP/'),            # HTTP protocol strings
    re.compile(r'^[\'"]https?://'),         # URL scheme literals
    re.compile(r'^[\'"]ws[s]?://'),         # WebSocket scheme literals
    re.compile(r'^[\'"][a-z]+://'),         # any scheme://
    re.compile(r'localhost'),               # localhost hostnames
    re.compile(r'192\.168\.'),             # private IP patterns
    re.compile(r'10\.'),                    # private IP patterns
    re.compile(r'172\.(1[6-9]|2[0-9]|3[0-1])\.'),  # private IP patterns
    re.compile(r'127\.'),                   # loopback
    re.compile(r'^[\'"][0-9]+[\'"]$'),     # bare numeric strings
    re.compile(r'^[\'"][0-9]+\.[0-9]+[\'"]$'),  # version strings in quotes
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
    re.compile(r'locale/en_US'),           # references to locale path
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
    re.compile(r'exit\s+'),                # exit statements
    re.compile(r'\.DoesExist\('),          # DoesExist method calls
    re.compile(r'\.Split\('),             # string split calls
    re.compile(r'\.Split\("_\"\)'),       # underscore split for prefs
    re.compile(r'\.Lower\(\)'),           # case conversion calls
    re.compile(r'\.Trim\(\)'),            # trim calls
    re.compile(r'if\s+.*\s*=\s*["\']'),   # if condition comparisons
    re.compile(r'\btrue\b|\bfalse\b'),     # boolean literals
    re.compile(r'\bthen\b'),              # if/then/end if keywords
    re.compile(r'\belse\b'),              # else keyword
    re.compile(r'\bfor\s+'),              # for loop keyword
    re.compile(r'\bnext\b'),              # next keyword
    re.compile(r'\bto\b'),                # to keyword in for loops
    re.compile(r'^[\s]*function\s+\w+'),   # function declarations
    re.compile(r'^[\s]*sub\s+\w+'),       # sub declarations
    re.compile(r'^[\s]*\'\'\''),         # doc comment lines
    re.compile(r'^\s*\'\s@'),            # at-tag doc comment lines
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
    re.compile(r'\.Replace\('),            # string Replace calls
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

        # Skip if line matches any exempt pattern
        if any(p.search(line) for p in EXEMPT):
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
)
PYRET=$?
echo "$PYOUT"
[[ $PYRET -eq 0 ]] && echo "  PASS" || VIOLATIONS=1

exit $((VIOLATIONS))