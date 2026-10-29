#!/usr/bin/env bash
# scripts/derive-version.sh — Single source of truth for version information
# Reads version from package.json and derives all other version fields.
#
# Usage:
#   derive-version.sh                  — full version from package.json (alias of --pkg-version)
#   derive-version.sh --major          — major_version only (first component)
#   derive-version.sh --minor          — minor_version only (second component)
#   derive-version.sh --build          — build_version only (third component; see
#                                        docs/publishing.md "Version discipline")
#   derive-version.sh --pkg-version    — full version from package.json
#
# Unknown flags fail loud (exit 2): the pre-fix `*)` arm silently answered ANY
# flag with the pkg version, so a caller reaching for the CI-build machinery
# deleted under M-ROKU-09 (below) would have baked a WRONG build_version with
# no error. verify-runtime.sh CHECK40 pins this usage block, the dispatch arms
# and the fail-loud behavior against drift.
#
# M-ROKU-09 (review roku__devops M2): this script once carried a designed but
# dead CI-build-number machinery — get_git_count() and get_ci_build_version()
# honoring CI_BUILD_NUMBER/GITHUB_RUN_NUMBER. No main() case dispatched it, no
# caller in the repo referenced it, and no CI step consumed a CI-derived
# build_version. The dead design is DELETED (fail-loud-or-delete doctrine,
# precedent windows WIN-05). Re-admitting CI-derived versions must arrive in
# the same change as its consumer AND the docs rotation it implies — the
# publication-vehicle question (versioned releases + rollback) is an open owner
# decision tracked in docs/publishing.md "Release Vehicles and Rollback".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"

# Read version from package.json
get_pkg_version() {
	python3 -c "import json; print(json.load(open('$REPO/package.json'))['version'])"
}

# Get major version (first part)
get_major_version() {
	python3 -c "import json; print(json.load(open('$REPO/package.json'))['version'].split('.')[0])"
}

# Get minor version (second part)
get_minor_version() {
	python3 -c "import json; print(json.load(open('$REPO/package.json'))['version'].split('.')[1])"
}

# Get build version (third part - patch number)
get_build_version() {
	python3 -c "import json; print(json.load(open('$REPO/package.json'))['version'].split('.')[2])"
}

main() {
	# "${1:-}" (not "$1"): the pre-fix bare "$1" died under `set -u` when the
	# documented no-arg usage was run (CHECK40 R3 probes exactly this).
	case "${1:-}" in
	--major)
		get_major_version
		;;
	--minor)
		get_minor_version
		;;
	--build)
		get_build_version
		;;
	--pkg-version | "")
		get_pkg_version
		;;
	*)
		echo "derive-version.sh: unknown option '$1' (supported: --major, --minor, --build, --pkg-version)" >&2
		exit 2
		;;
	esac
}

main "$@"
