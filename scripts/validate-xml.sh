#!/usr/bin/env bash
# scripts/validate-xml.sh — SceneGraph XML structure validation (behind `make validate-xml`).
#
# The law: every components/*.xml must carry an <?xml version ...?> prologue and
# a closed lowercase </component> element.
#
# WHY A SCRIPT AND NOT THE OLD INLINE MAKEFILE LOOP (estate CI-gate audit
# 2026-10-02): the pre-fix check was a glob loop in the Makefile that exited 0
# whenever it discovered ZERO files — a renamed components dir, a drifted path
# pattern, or an empty checkout validated nothing yet still greened the gate
# (vacuous pass). This script counts what it discovers and fails loudly on an
# empty discovery, so "nothing checked" can never again read as "everything
# passed". Falsifiability: tests/scripts/verify-runtime-portable.sh leg (13).
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

total_files=0
invalid_files=0
for xml in "$COMPONENTS_DIR"/*.xml; do
	[ -f "$xml" ] || continue
	total_files=$((total_files + 1))
	if grep -q '<?xml version' "$xml" && grep -q '</component>' "$xml"; then
		echo "  ✓ $(basename "$xml")"
	else
		echo "  ERROR: $(basename "$xml") - invalid structure"
		invalid_files=$((invalid_files + 1))
	fi
done

if [ "$total_files" -eq 0 ]; then
	echo "ERROR: validate-xml: discovered ZERO XML files in '$COMPONENTS_DIR' — an empty file set is a path-pattern regression, NOT a pass. Failing loudly." >&2
	exit 1
fi

if [ "$invalid_files" -ne 0 ]; then
	echo "ERROR: validate-xml: $invalid_files of $total_files XML files have invalid structure." >&2
	exit 1
fi

echo "XML validation passed ($total_files files validated)."
