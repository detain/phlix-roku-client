#!/usr/bin/env bash
# scripts/validate-xml.sh — SceneGraph XML structure validation (behind `make validate-xml`).
#
# The law: EVERY XML file under components/ — discovered RECURSIVELY, nested
# directories included — must (1) carry an <?xml version ...?> prologue,
# (2) parse as well-formed XML, and (3) have a closed lowercase <component>
# root element.
#
# WHY A SCRIPT AND NOT THE OLD INLINE MAKEFILE LOOP (estate CI-gate audit
# 2026-10-02): the pre-fix check was a glob loop in the Makefile that exited 0
# whenever it discovered ZERO files — a renamed components dir, a drifted path
# pattern, or an empty checkout validated nothing yet still greened the gate
# (vacuous pass). This script counts what it discovers and fails loudly on an
# empty discovery, so "nothing checked" can never again read as "everything
# passed".
#
# WHY RECURSIVE + A REAL PARSER (review roku devops M3, W-min92/M-ROKU-19):
# the post-audit era still scanned only the flat glob components/*.xml and
# "validated" by two greps for the substrings '<?xml version' and
# '</component>'. That had two holes: (a) an XML file in a NESTED directory
# was invisible — total_files stayed > 0 so the zero-discovery guard could not
# fire, yet the nested file had ZERO coverage; (b) two substring greps are not
# a parse — a file whose prologue and closing tag merely EXIST somewhere, in an
# otherwise malformed document (unbalanced children, wrong-case root, junk
# tail), sailed through. Discovery is now os.walk-based and every file passes
# through a real XML parser (stdlib xml.etree); the substring law is kept as
# the prologue/root check so the original convictions still read the same.
#
# Falsifiability: tests/scripts/verify-runtime-portable.sh leg (13):
#   13a real components/ green · 13b empty root red · 13c missing root red ·
#   13d planted grep-hostile file red naming it, restore green ·
#   13e planted NESTED malformed file red naming its relative path (the flat
#       glob era silently skipped this) ·
#   13f planted file that passes BOTH legacy greps yet is NOT well-formed red
#       (the substring-era hole; only a parser can convict it).
#
# Usage: bash scripts/validate-xml.sh [COMPONENTS_DIR]
#   COMPONENTS_DIR defaults to <repo>/components resolved from this script's
#   own location — layout-independent, the same idiom as verify-runtime.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
COMPONENTS_DIR="${1:-$REPO/components}"

if [ ! -d "$COMPONENTS_DIR" ]; then
	echo "ERROR: validate-xml: components directory '$COMPONENTS_DIR' does not exist — refusing to validate nothing." >&2
	exit 1
fi

echo "Validating XML files in $COMPONENTS_DIR ..."

python3 - "$COMPONENTS_DIR" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

root = os.path.abspath(sys.argv[1])

# Recursive, deterministic-order discovery. The flat components/*.xml glob era
# gave nested files zero coverage while total_files stayed loud-green; os.walk
# closes that hole, and sort keeps per-file output stable for the leg greps.
paths = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for name in sorted(filenames):
        if name.endswith(".xml"):
            paths.append(os.path.relpath(os.path.join(dirpath, name), root))
paths.sort()

if not paths:
    print(
        "ERROR: validate-xml: discovered ZERO XML files in '%s' — an empty file set "
        "is a path-pattern regression, NOT a pass. Failing loudly." % root,
        file=sys.stderr,
    )
    sys.exit(1)

invalid = 0
for rel in paths:
    full = os.path.join(root, rel)
    try:
        with open(full, "rb") as handle:
            raw = handle.read()
    except OSError as error:
        print("  ERROR: %s - invalid structure (unreadable: %s)" % (rel, error))
        invalid += 1
        continue

    reason = ""
    text = raw.decode("utf-8", errors="replace")
    if "<?xml version" not in text.split("\n", 1)[0]:
        reason = "missing <?xml version ...?> prologue on the first line"
    else:
        try:
            tree_root = ET.fromstring(raw)
        except ET.ParseError as error:
            reason = "not well-formed XML (%s)" % error
        else:
            if tree_root.tag != "component":
                reason = "root element is <%s>, the law requires lowercase <component>" % tree_root.tag

    if reason:
        print("  ERROR: %s - invalid structure (%s)" % (rel, reason))
        invalid += 1
    else:
        print("  ✓ %s" % rel)

if invalid:
    print(
        "ERROR: validate-xml: %d of %d XML files have invalid structure." % (invalid, len(paths)),
        file=sys.stderr,
    )
    sys.exit(1)

print("XML validation passed (%d files validated)." % len(paths))
PY
