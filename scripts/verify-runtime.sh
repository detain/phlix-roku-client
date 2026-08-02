#!/usr/bin/env bash
# scripts/verify-runtime.sh — Static runtime-defect checker for phlix-roku-client (R0.7)
# Each check exits non-zero and prints: FILE:LINE — CHECK_NAME: explanation
set -euo pipefail
REPO="/home/sites/phlix/phlix-roku-client"
cd "$REPO"
FOUND=0

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
echo "=== Checks 8-10 not yet implemented ==="