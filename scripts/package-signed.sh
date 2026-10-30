#!/bin/bash
# =============================================================================
# package-signed.sh — Build a code-signed .pkg from the sideload zip
# =============================================================================
#
# Honesty pass (M-ROKU-10, review roku__devops M3). The old header claimed a
# dedicated Roku-dev PASSWORD environment variable had to be set and that the
# script would fail without it — NO component in this repo ever read any
# such variable. Authentication lives entirely in the external rokudev CLI's
# stored session token (`rokudev auth`, where credentials are typed at its
# own prompt); this script reads no password env var. The claim is deleted,
# and every precondition listed below is actually enforced here.
# verify-runtime Check 41 pins claim<->behavior so the false assurance
# cannot return.
#
# Prerequisites (enforced in the steps below or by the invoked CLI):
#   - Roku developer account (https://developer.roku.com). For STORE
#     submission the certificate must be Roku-issued — see docs/publishing.md,
#     "Certificate Details".
#   - `rokudev auth` previously run (one-time, interactive) if you use rokudev.
#   - openssl — used both to generate a development certificate and to
#     determine the certificate's nature before naming the artifact.
#   - a code signing certificate at ~/.phlix/phlix-signing.pem — the
#     Roku-issued one, or one this script generates on demand for dev/CI.
#
# What this script does:
#   1. Runs `make package` to produce the sideload phlix.zip
#   2. Ensures a signing certificate exists, generating a self-signed
#      development certificate when none is present (dev/CI use only)
#   3. Signs with rokudev/rokupkg. The certificate's NATURE decides the
#      artifact name and the printed next steps: a self-signed certificate
#      can never produce a store-submittable package, so that artifact is
#      named *-dev-signed.pkg and is explicitly marked NOT uploadable — its
#      purpose is the signing-chain smoke test only. Nothing installs a
#      .pkg on a device anyway: the dev-mode installer takes the unsigned
#      zip ('make install'), never a package of any provenance.
#      There is deliberately NO fallback that renames the unsigned zip into
#      a .pkg — a "signed" label the chain cannot back is exactly the
#      mislabeled artifact that wastes a store review cycle (M-ROKU-10).
# =============================================================================

set -e

PKG_NAME="phlix"
CERT_PATH="${HOME}/.phlix/phlix-signing.pem"
CERT_DIR="$(dirname "$CERT_PATH")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Version stamp law (M-ROKU-10): the Makefile passes PKG_VERSION explicitly
# because make does NOT export ordinary variables into recipes — the old
# `${PKG_VERSION:-1.0.1}` default therefore silently mis-stamped every
# direct invocation `1.0.1` forever. Never guess a version: take the
# environment, else derive it from package.json via the single-source
# script, else fail loud BEFORE minting any artifact.
PKG_VERSION="${PKG_VERSION:-}"
if [ -z "$PKG_VERSION" ]; then
	PKG_VERSION="$(bash "$SCRIPT_DIR/derive-version.sh" --pkg-version 2>/dev/null || true)"
fi
if [ -z "$PKG_VERSION" ]; then
	echo "ERROR: cannot determine the package version (PKG_VERSION unset and scripts/derive-version.sh failed)." >&2
	echo "       Run through 'make package-signed' from the repo root." >&2
	exit 1
fi

echo "=== Building signed package for $PKG_NAME v$PKG_VERSION ==="

# Step 1: Produce sideload zip via make package
echo "--- Step 1: Packaging sideload zip ---"
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
		# Interactive terminal — prompt before creating
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
		echo "  For store submission, obtain a real certificate from the Roku developer portal" >&2
		echo "  and place it at $CERT_PATH (see docs/publishing.md)." >&2
		exit 1
	fi
else
	echo "  ✓ Reusing existing certificate at $CERT_PATH"
fi

# Step 2b: Determine the certificate's nature. A self-signed certificate is
# one whose subject equals its issuer. This decides whether the output may
# honestly carry a store-submission label at all; an unreadable certificate
# fails loud rather than minting a "signed" artifact of unknown provenance.
echo "--- Step 2b: Inspecting certificate nature ---"
CERT_SUBJECT="$(openssl x509 -in "$CERT_PATH" -noout -subject 2>/dev/null)" || {
	echo "ERROR: $CERT_PATH is not a readable X.509 certificate (or openssl is missing)." >&2
	echo "       Refusing to mint a 'signed' artifact from an unverifiable certificate." >&2
	exit 1
}
CERT_ISSUER="$(openssl x509 -in "$CERT_PATH" -noout -issuer 2>/dev/null)" || {
	echo "ERROR: cannot read the issuer of $CERT_PATH (openssl failure)." >&2
	exit 1
}
if [ "${CERT_SUBJECT#subject=}" = "${CERT_ISSUER#issuer=}" ]; then
	SELF_SIGNED=1
else
	SELF_SIGNED=0
fi

# The artifact name states the truth the certificate can back.
if [ "$SELF_SIGNED" -eq 1 ]; then
	SIGNED_PKG="${PKG_NAME}-${PKG_VERSION}-dev-signed.pkg"
else
	SIGNED_PKG="${PKG_NAME}-${PKG_VERSION}.pkg"
fi

# Step 3: Create the signed .pkg
echo "--- Step 3: Creating signed package ($SIGNED_PKG) ---"
if command -v rokudev >/dev/null 2>&1; then
	echo "Using rokudev to sign package..."
	if ! rokudev sign \
		--input "${PKG_NAME}.zip" \
		--output "$SIGNED_PKG" \
		--cert "$CERT_PATH" \
		2>&1; then
		echo "ERROR: rokudev sign failed." >&2
		echo "NOTE: store-ready signing requires the Roku-issued code signing" >&2
		echo "      certificate (see docs/publishing.md, 'Certificate Details')." >&2
		echo "      For development testing, the sideload zip can be installed" >&2
		echo "      directly with 'make install'." >&2
		exit 1
	fi
elif command -v rokupkg >/dev/null 2>&1; then
	echo "Using rokupkg to sign package..."
	# Fail loud on signing errors: the old branch cp'd the unsigned zip to the
	# .pkg name and still claimed success — the mislabeled-artifact defect.
	rokupkg \
		--sign "$CERT_PATH" \
		--input "${PKG_NAME}.zip" \
		--output "$SIGNED_PKG" \
		2>&1 || {
		echo "ERROR: rokupkg signing failed." >&2
		echo "       Refusing to rename the unsigned zip into '$SIGNED_PKG' —" >&2
		echo "       a '.pkg' the chain cannot actually sign must not be minted (M-ROKU-10)." >&2
		echo "       The sideload zip (${PKG_NAME}.zip) is still available for 'make install'." >&2
		exit 1
	}
else
	echo "ERROR: Neither rokudev nor rokupkg is available." >&2
	echo "Install rokudev CLI: npm install -g rokudev" >&2
	echo "The unsigned zip (${PKG_NAME}.zip) is still available for sideloading." >&2
	exit 1
fi

if [ ! -f "$SIGNED_PKG" ]; then
	echo "ERROR: signing produced no artifact ($SIGNED_PKG)." >&2
	exit 1
fi

# Summary — next steps match what the certificate actually supports.
echo ""
echo "=== Summary ==="
echo "  Sideload zip: ${PKG_NAME}.zip"
if [ "$SELF_SIGNED" -eq 1 ]; then
	echo "  Dev-signed pkg: $SIGNED_PKG"
	echo ""
	echo "  DEV-SIGNED ONLY — this artifact is NOT accepted by the Roku Channel Store."
	echo "  (It was signed with a self-signed certificate at $CERT_PATH.)"
	echo "  Nothing installs a .pkg on a device — the dev-mode installer takes the"
	echo "  unsigned zip: for device testing use '${PKG_NAME}.zip' via 'make install'."
	echo "  This artifact is a signing-chain smoke test; NEVER upload it to the portal."
	echo "  For store submission, replace the certificate with the Roku-issued one"
	echo "  and rebuild — see docs/publishing.md, 'Certificate Details'."
else
	echo "  Signed pkg:  $SIGNED_PKG"
	echo ""
	echo "Next steps (store submission, Roku-issued certificate):"
	echo "  1. Upload $SIGNED_PKG to the Roku developer portal"
	echo "  2. Submit for review via https://developer.roku.com"
	echo "  3. See docs/publishing.md for the full submission workflow"
fi
