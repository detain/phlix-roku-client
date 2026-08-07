#!/usr/bin/env bash
# scripts/derive-version.sh — Single source of truth for version information
# Reads version from package.json and derives all other version fields.
# Usage:
#   derive-version.sh                  — output all fields as manifest format
#   derive-version.sh --major          — output major_version only
#   derive-version.sh --minor          — output minor_version only
#   derive-version.sh --patch           — output patch version (from package.json)
#   derive-version.sh --build           — output build_version (git commit count or CI build number)
#   derive-version.sh --pkg-version    — output full version from package.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"

# Read version from package.json
get_pkg_version() {
    python3 -c "import json; print(json.load(open('$REPO/package.json'))['version'])"
}

# Get git commit count (or 0 if not a git repo)
get_git_count() {
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get CI build number if available, otherwise fall back to git count
get_build_version() {
    local build="${CI_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
    if [[ -n "$build" ]]; then
        echo "$build"
    else
        get_git_count
    fi
}

# Parse version components
parse_version() {
    local version=$(get_pkg_version)
    local major minor patch
    # Handle versions like "1.0.1" or "1.0.1-beta"
    if [[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
    else
        echo "ERROR: Cannot parse version from package.json: $version" >&2
        exit 1
    fi
    echo "$major $minor $patch"
}

main() {
    if [[ $# -eq 0 ]]; then
        # Output all fields in manifest format
        read -r major minor patch <<< "$(parse_version)"
        local build=$(get_build_version)
        echo "major_version=$major"
        echo "minor_version=$minor"
        echo "build_version=$build"
    else
        case "$1" in
            --major)
                parse_version | cut -d' ' -f1
                ;;
            --minor)
                parse_version | cut -d' ' -f2
                ;;
            --patch)
                parse_version | cut -d' ' -f3
                ;;
            --build)
                get_build_version
                ;;
            --pkg-version)
                get_pkg_version
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: $0 [--major|--minor|--patch|--build|--pkg-version]" >&2
                exit 1
                ;;
        esac
    fi
}

main "$@"
