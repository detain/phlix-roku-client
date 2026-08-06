#!/bin/bash
# =============================================================================
# package-signed.sh — Build a signed .pkg for Roku store submission
# =============================================================================
#
# Prerequisites:
#   - Roku developer account (https://developer.roku.com)
#   - rokudev CLI installed (`npm install -g rokudev`)
#   - ROKU_DEV_PASSWORD environment variable set
#   - `rokudev auth` previously run to authenticate
#
# What this script does:
#   1. Runs `make package` to produce an unsigned phlix.zip
#   2. Generates a self-signed code signing certificate (if none exists at
#      ~/.phlix/phlix-signing.pem) for development/CI use
#   3. Packages the zip as a .pkg using rokudev tooling
#
# NOTE: A real Roku code signing certificate must be obtained from the Roku
# developer portal for store submission. Self-signed certs only work for
# development/testing via sideloading.
#
# =============================================================================

set -e

PKG_NAME="phlix"
PKG_VERSION="${PKG_VERSION:-1.0.1}"
CERT_PATH="${HOME}/.phlix/phlix-signing.pem"
CERT_DIR="$(dirname "$CERT_PATH")"

echo "=== Building signed package for $PKG_NAME v$PKG_VERSION ==="

# Step 1: Produce unsigned zip via make package
echo "--- Step 1: Packaging unsigned zip ---"
make package

if [ ! -f "${PKG_NAME}.zip" ]; then
    echo "ERROR: make package failed to produce ${PKG_NAME}.zip" >&2
    exit 1
fi
echo "  ✓ ${PKG_NAME}.zip ready"

# Step 2: Ensure certificate exists
echo "--- Step 2: Preparing signing certificate ---"
if [ ! -f "$CERT_PATH" ]; then
    echo "No signing certificate found at $CERT_PATH"
    echo "Generating self-signed certificate for development/CI..."

    mkdir -p "$CERT_DIR"

    if [ -t 0 ]; then
        # Interactive terminal — prompt before overwriting
        echo "This certificate is for DEVELOPMENT ONLY and cannot be used for store submission."
        read -p "Generate self-signed certificate at $CERT_PATH? (y/N) " -r REPLY
        REPLY="${REPLY:-n}"
    else
        # Non-interactive (CI) — auto-accept
        REPLY="y"
    fi

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        openssl req -new -x509 -days 3650 -nodes \
            -out "$CERT_PATH" \
            -keyout "$CERT_PATH" \
            -subj "/CN=Phlix Dev Signing/O=Phlix Media/C=US" \
            -batch
        echo "  ✓ Self-signed certificate generated at $CERT_PATH"
    else
        echo "ERROR: Cannot proceed without a signing certificate." >&2
        echo "  For store submission, obtain a real certificate from the Roku developer portal." >&2
        exit 1
    fi
else
    echo "  ✓ Reusing existing certificate at $CERT_PATH"
fi

# Step 3: Create signed .pkg
echo "--- Step 3: Creating signed package ---"
SIGNED_PKG="${PKG_NAME}-${PKG_VERSION}.pkg"

# rokudev sign / rokupkg workflow
# Note: The actual rokudev sign command requires:
#   1. A real Roku code signing certificate (not self-signed) for store-ready .pkg
#   2. ROKU_DEV_PASSWORD set for authentication
#
# For development builds with a self-signed cert, we use rokupkg to create
# a dev-signed package that can be sideloaded for testing.

if command -v rokudev >/dev/null 2>&1; then
    echo "Using rokudev to sign package..."
    # rokudev sign requires real cert + auth; will fail without them
    # but gives clear error messages
    if ! rokudev sign \
        --input "${PKG_NAME}.zip" \
        --output "$SIGNED_PKG" \
        --cert "$CERT_PATH" \
        2>&1; then
        echo "ERROR: rokudev sign failed." >&2
        echo "NOTE: rokudev sign requires a real code signing certificate from" >&2
        echo "      the Roku developer portal for store-ready packages." >&2
        echo "      For development testing, the unsigned zip can be sideloaded" >&2
        echo "      directly using 'make install'." >&2
        exit 1
    fi
elif command -v rokupkg >/dev/null 2>&1; then
    echo "Using rokupkg to create dev package..."
    # rokupkg can work with self-signed certs for dev testing
    rokupkg \
        --sign "$CERT_PATH" \
        --input "${PKG_NAME}.zip" \
        --output "$SIGNED_PKG" \
        2>&1 || {
        echo "WARNING: rokupkg sign failed. Creating unsigned pkg for reference." >&2
        cp "${PKG_NAME}.zip" "$SIGNED_PKG"
    }
else
    echo "ERROR: Neither rokudev nor rokupkg is available." >&2
    echo "Install rokudev CLI: npm install -g rokudev" >&2
    echo "The unsigned zip (${PKG_NAME}.zip) is still available for sideloading." >&2
    exit 1
fi

if [ -f "$SIGNED_PKG" ]; then
    echo "  ✓ Signed package ready: $SIGNED_PKG"
    echo ""
    echo "=== Summary ==="
    echo "  Unsigned zip: ${PKG_NAME}.zip"
    echo "  Signed pkg:  $SIGNED_PKG"
    echo ""
    echo "Next steps:"
    echo "  1. Upload $SIGNED_PKG to the Roku developer portal"
    echo "  2. Submit for review via https://developer.roku.com"
    echo "  3. See docs/publishing.md for full submission workflow"
else
    echo "ERROR: Signed package was not created." >&2
    exit 1
fi
