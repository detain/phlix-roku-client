#!/usr/bin/env bash
# scripts/derive-version.sh — Single source of truth for version information
# Reads version from package.json and derives all other version fields.
# Usage:
#   derive-version.sh                  — output all fields as manifest format
#   derive-version.sh --major           — output major_version only
#   derive-version.sh --minor           — output minor_version only
#   derive-version.sh --build           — output build_version (patch number from package.json)
#   derive-version.sh --pkg-version     — output full version from package.json
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

# Get git commit count (or 0 if not a git repo) - for CI purposes
get_git_count() {
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get CI build number if available, otherwise fall back to git count
get_ci_build_version() {
    local build="${CI_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
    if [[ -n "$build" ]]; then
        echo "$build"
    else
        get_git_count
    fi
}

main() {
    case "$1" in
        --major)
            get_major_version
            ;;
        --minor)
            get_minor_version
            ;;
        --build)
            get_build_version
            ;;
        --pkg-version|*)
            get_pkg_version
            ;;
    esac
}

main "$@"
