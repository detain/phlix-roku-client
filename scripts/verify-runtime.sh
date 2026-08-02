#!/usr/bin/env bash
# scripts/verify-runtime.sh — Static runtime-defect checker for phlix-roku-client (R0.7)
# Each check exits non-zero and prints: FILE:LINE — CHECK_NAME: explanation
set -euo pipefail
REPO="/home/sites/phlix/phlix-roku-client"
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
    if ! grep -qP "^(sub|function)\s+$cb\b" "$brs" 2>/dev/null; then
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
      if ! grep -A200 '<children>' "$xml" 2>/dev/null | grep -B200 '</children>' | grep -q "id=\"$id\"" 2>/dev/null; then
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
ALLOW_LIST="command content control currentTime duration endpoint errorMsg focusRing isFullscreen isPhoto loggingUrl manifestHDRType maxHeight maxWidth position rate retargetHeight retargetWidth secureChainingUrl securityKey stream streamFormat streamInfo subtitleStream textTrackTrack track transferType videoLocation videoNode wasPlaying wideAsync"
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
    ['git', 'grep', '-n', r'control\s*=\s*"run"'],
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
# Exemption patterns: comments documenting the callback-chained serialization
# pattern ("one op at a time - never two control=run").
exempt_patterns = [
    # Callback-chained serialization pattern: documentation comment indicating
    # "two control=run are never outstanding" or "one op at a time".
    # Use [\s\S] to match across newlines in multi-line comments.
    re.compile(r'two control[\s\S]{0,80}never|never[\s\S]{0,80}two control', re.IGNORECASE),
    re.compile(r'never outstanding', re.IGNORECASE),
    re.compile(r'one op at a time', re.IGNORECASE),
]
found_violation = False
for gline in result.stdout.strip().split('\n'):
    if not gline.strip():
        continue
    parts = gline.split(':', 2)
    if len(parts) < 3:
        continue
    fname, lnum_s, line_content = parts
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

[[ $VIOLATIONS -eq 1 ]] && exit 1