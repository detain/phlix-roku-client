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

[[ $VIOLATIONS -eq 1 ]] && exit 1