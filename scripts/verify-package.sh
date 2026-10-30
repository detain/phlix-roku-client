#!/usr/bin/env bash
# scripts/verify-package.sh — Sideload artifact layout gate (C08; review
# evidence roku__crossfe C1 + roku__devops C1).
#
# The law: `make package` must produce an archive Roku's Development
# Application Installer can actually install. Roku requires the channel
# manifest at the ARCHIVE ROOT ("The root level of all Roku apps must contain
# a `manifest` file" — developer.roku.com/dev/docs/channel-manifest; the
# failure symptom is documented across forum threads 198/3225/9582/10222:
# "Install Failure: No manifest. Invalid package.").
#
# WHY THIS EXISTS: since 88f5865 (R8.8 version-single-sourcing) the recipe
# zipped `$(MANIFEST_OUT)` = build/manifest with `zip -r`, storing the
# manifest NESTED under build/ with no root entry — every packaged channel
# was structurally uninstallable, and no gate ever opened the zip: the CI
# packaging job asserted only file EXISTENCE (if-no-files-found), never
# layout. Local devs never noticed because `make install` posts a separate
# raw `-F manifest=@manifest` field that papers over the broken archive.
#
# What this script asserts (each leg is the counter-leg of a real past defect;
# zero-inspection vacuous pass is forbidden — validate-xml 1678b40 doctrine):
#   1. the zip exists and opens at all;
#   2. its member listing is NON-EMPTY (a structurally empty archive proves
#      nothing yet would "pass" a naive grep);
#   3. EXACTLY ONE root-level `manifest` entry (positive law — and ambiguity
#      is also red);
#   4. ZERO `build/` entries (the negative leg — the exact OLD defect shape;
#      build output must never ship);
#   5. every required source tree — source/ components/ images/ locale/ —
#      carries at least one FILE entry at root position (dropping a tree,
#      e.g. locale/, ships a channel with no catalogs: same structural
#      class as the missing manifest);
#   6. the shipped root manifest parses as a manifest: title= plus the three
#      R8.8 version keys major_version= minor_version= build_version= are
#      present (guards against a stray empty/garbage file at root).
#
# Usage: bash scripts/verify-package.sh [PKG_ZIP]
#   PKG_ZIP defaults to <repo>/phlix.zip resolved from this script's own
#   location — layout-independent, the same idiom as validate-xml.sh.
# Exit: 0 green; 1 red with every failed leg named.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
PKG="${1:-$REPO/phlix.zip}"

fail() {
	echo "ERROR: verify-package: $1" >&2
	exit 1
}

command -v unzip >/dev/null 2>&1 || fail "'unzip' is required to open the artifact — refusing to verify nothing."
[ -f "$PKG" ] || fail "artifact '$PKG' does not exist — refusing to verify nothing (build it with 'make package')."

# One member name per line (zinfo listing). Directory entries appear as "dir/".
if ! listing="$(unzip -Z1 "$PKG" 2>/dev/null)"; then
	fail "artifact '$PKG' is not a readable zip — refusing to verify nothing."
fi

problems=0
note() {
	echo "  FAIL: $1" >&2
	problems=$((problems + 1))
}

total_entries="$(printf '%s\n' "$listing" | awk 'NF{c++} END{print c+0}')"
if [ "$total_entries" -eq 0 ]; then
	fail "artifact '$PKG' contains ZERO entries — an empty archive is a vacuous pass, not a package."
fi

# (3) root manifest — exactly one.
root_manifest="$(printf '%s\n' "$listing" | awk '$0=="manifest"{c++} END{print c+0}')"
if [ "$root_manifest" -eq 0 ]; then
	note "no root-level 'manifest' entry in $PKG — Roku rejects packages without one (\"Install Failure: No manifest. Invalid package\")."
elif [ "$root_manifest" -gt 1 ]; then
	note "$root_manifest root-level 'manifest' entries in $PKG — exactly one is required."
fi

# (4) negative leg: the OLD defect shape must never return.
build_entries="$(printf '%s\n' "$listing" | awk '$0 ~ /^build\//{c++} END{print c+0}')"
if [ "$build_entries" -ne 0 ]; then
	note "$build_entries 'build/' entries in $PKG — build output must never ship (this is the exact layout class that made every R8.8-era package uninstallable)."
fi

# (5) required trees, each with at least one file.
for tree in source components images locale; do
	tree_files="$(printf '%s\n' "$listing" | awk -v t="$tree/" 'index($0, t) == 1 && $0 !~ /\/$/{c++} END{print c+0}')"
	if [ "$tree_files" -eq 0 ]; then
		note "required tree '$tree/' carries zero files in $PKG — the channel would ship without it."
	fi
done

# (6) shipped root manifest parses as a manifest.
if [ "$root_manifest" -eq 1 ]; then
	tmp="$(mktemp)"
	trap 'rm -f "$tmp"' EXIT
	if ! unzip -p "$PKG" manifest >"$tmp" 2>/dev/null; then
		note "root 'manifest' exists in $PKG but cannot be extracted."
	else
		for key in title major_version minor_version build_version; do
			if ! grep -q "^${key}=" "$tmp"; then
				note "shipped root manifest lacks required key '${key}=' (R8.8 derivation must ride the artifact)."
			fi
		done
		# (7) [W-min93 M-ROKU-14, review roku__crossfe m6] the rsg_version
		# callback-model pin must ride the ARTIFACT (CHECK39 pins the source
		# manifest; this closes it at the shipped-bytes surface), and every
		# images/ path the shipped manifest references must EXIST as a member
		# — a package whose declared icon/splash is missing installs into a
		# broken chrome (same uninstallable-adjacent class as legs 3-5).
		if ! grep -q '^rsg_version=' "$tmp"; then
			note "shipped root manifest lacks rsg_version= (SceneGraph callback-model pin must ride the artifact)."
		fi
		while IFS= read -r ref; do
			[ -n "$ref" ] || continue
			if ! printf '%s\n' "$listing" | grep -qxF "$ref"; then
				note "shipped manifest references '$ref' but the archive carries no such member."
			fi
		done < <(grep -oE 'images/[A-Za-z0-9._/-]+' "$tmp" | sort -u)
	fi
fi

if [ "$problems" -ne 0 ]; then
	echo "ERROR: verify-package: $problems layout problem(s) in $PKG — the sideload artifact is NOT installable as shipped." >&2
	exit 1
fi

echo "verify-package: $PKG layout OK — root manifest present (title/version keys intact), zero build/ entries, source/components/images/locale all ship files ($total_entries members)."
