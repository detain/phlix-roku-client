.PHONY: all package package-signed install dev clean test lint lint-fix validate-manifest validate-routes verify-package _run_rooibos _run_rooibos_unit _run_rooibos_integration

# Roku IP address (set via environment or edit here)
ROKU_IP ?= 192.168.1.100
ROKU_DEV ?= rokudev
ROKU_PASSWORD ?= rokipassword

# Package name
PKG_NAME = phlix
PKG_VERSION = $(shell bash $(CURDIR)/scripts/derive-version.sh --pkg-version)

# Source directories
SOURCE_DIR = source
TESTS_DIR = tests
LIB_DIR = $(SOURCE_DIR)/lib
COMPONENTS_DIR = components

# R8.8: Inject version from package.json into manifest at build time
BUILD_DIR = build
MANIFEST_SRC = manifest
MANIFEST_OUT = $(BUILD_DIR)/manifest

_update-manifest: $(MANIFEST_SRC)
	@mkdir -p $(BUILD_DIR)
	@sed -e 's/^major_version=.*/major_version=$(shell $(CURDIR)/scripts/derive-version.sh --major)/' \
	      -e 's/^minor_version=.*/minor_version=$(shell $(CURDIR)/scripts/derive-version.sh --minor)/' \
	      -e 's/^build_version=.*/build_version=$(shell $(CURDIR)/scripts/derive-version.sh --build)/' \
	      $(MANIFEST_SRC) > $(MANIFEST_OUT)

all: package

# Create zip package for sideloading.
# C08 (review roku__crossfe C1 + roku__devops C1): Roku's Dev Application
# Installer requires the manifest at the ARCHIVE ROOT; the pre-fix recipe
# zipped $(MANIFEST_OUT) = build/manifest with `zip -r`, which stored it
# NESTED under build/ and made every packaged channel uninstallable (and
# package.yml published exactly that zip as the rolling "latest"). Cure:
# the directory trees keep their structure via `zip -r`; the version-derived
# manifest rides as a bare root member via `zip -j` (junk paths). `rm -f`
# first because zip UPDATES an existing archive — without it a stale zip
# could keep old-layout entries after the recipe itself was fixed. The
# target ends by opening its own output: scripts/verify-package.sh fails
# loudly on any layout regression, so `make package` (and with it `make
# install`, `make dev-install`, CI's package job, and package-signed.sh's
# phlix.zip input) can no longer produce a structurally invalid artifact
# silently.
# M-ROKU-20 (determinism): the same tree now rebuilds BYTE-IDENTICAL zips.
# The recipe stages a copy of the four payload trees plus the version-derived
# manifest, stamps every staged entry to a fixed timestamp, and feeds zip a
# C-locale-sorted file list ('zip -X -@', extra fields off) from inside the
# stage dir — so checkout mtimes and filesystem traversal order can no longer
# change the bytes. The digest is recorded next to the archive (phlix.zip.
# sha256) and CI (package.yml) uploads/publishes it beside the package.
package: _update-manifest
	@echo "Packaging version $(PKG_VERSION)..."
	@rm -f $(PKG_NAME).zip $(PKG_NAME).zip.sha256
	@rm -rf $(BUILD_DIR)/pkg-stage
	@mkdir -p $(BUILD_DIR)/pkg-stage
	@cp -R source components images locale $(BUILD_DIR)/pkg-stage/
	@cp $(MANIFEST_OUT) $(BUILD_DIR)/pkg-stage/manifest
	@find $(BUILD_DIR)/pkg-stage -exec touch -t 200001010000.00 {} +
	@cd $(BUILD_DIR)/pkg-stage && find source components images locale manifest -type f | LC_ALL=C sort | zip -X -q "$(CURDIR)/$(PKG_NAME).zip" -@
	@bash "$(CURDIR)/scripts/verify-package.sh" "$(CURDIR)/$(PKG_NAME).zip"
	@cd "$(CURDIR)" && sha256sum "$(PKG_NAME).zip" > "$(PKG_NAME).zip.sha256"
	@cat "$(PKG_NAME).zip.sha256"

# Build a code-signed package. The artifact is named to the certificate's
# nature: the Roku-issued cert yields phlix-X.X.X.pkg (store submission); a
# self-signed cert yields phlix-X.X.X-dev-signed.pkg — a signing-chain smoke
# artifact only (never uploadable, and nothing installs a .pkg on a device:
# device testing runs 'make install' with phlix.zip) — scripts/package-signed.sh
# decides and states it.
# Truth pass (M-ROKU-10): the old comment demanded a "ROKU_DEV_PASSWORD"
# env var that no component ever read; credentials belong to the rokudev
# CLI's interactive `rokudev auth` step. PKG_VERSION is passed explicitly
# because make does not export ordinary variables into recipes — without
# this the script could never stamp the real version.
package-signed:
	@echo "Building signed package..."
	@PKG_VERSION="$(PKG_VERSION)" bash scripts/package-signed.sh
	@echo "Done — see docs/publishing.md for artifact truth and submission steps."

# Install to Roku device.
# M-ROKU-21: credentials no longer ride curl argv (-u user:pass is visible in
# ps to every local user); the whole request is described on stdin via
# 'curl --config -'. The raw-manifest form field was DROPPED too: since the
# C08 cure the version-injected manifest rides at the zip's root and is the
# single source the installer should see — feeding a second, un-injected
# 'manifest' field re-created the dual-source shape the C1 law forbids.
install: package
	@echo "Installing to Roku at $(ROKU_IP)..."
	@printf 'user = "%s:%s"\nurl = "http://%s:8060/install/app"\nrequest = "POST"\nform = "archive=@%s.zip"\n' \
		"$(ROKU_DEV)" "$(ROKU_PASSWORD)" "$(ROKU_IP)" "$(PKG_NAME)" \
		| curl -v --config -

# Launch the app (after install)
launch:
	@echo "Launching $(PKG_NAME)..."
	@printf 'user = "%s:%s"\nurl = "http://%s:8060/launch/dev?channel=dev"\nrequest = "POST"\n' \
		"$(ROKU_DEV)" "$(ROKU_PASSWORD)" "$(ROKU_IP)" | curl -sS --config -

# Stop the app
stop:
	@echo "Stopping $(PKG_NAME)..."
	@printf 'user = "%s:%s"\nurl = "http://%s:8060/keypress/home"\nrequest = "POST"\n' \
		"$(ROKU_DEV)" "$(ROKU_PASSWORD)" "$(ROKU_IP)" | curl -sS --config -

# Development server (requires rokupkg)
dev-install: package
	@echo "Installing to dev mode..."
	rokupkg --install $(PKG_NAME).zip

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -f $(PKG_NAME).zip

# ===========================================
# Testing
# ===========================================

# Run tests
test:
	@echo "Running tests..."
	@echo ""
	@# With a device configured (ROKU_HOST/ROKU_TEST_HOST) rooibos drives the
	@# full suite on hardware. Without one, the headless BrightScript
	@# interpreter gate (brs) executes the pure-logic suites — it is a real
	@# test runner (red exits red), not a lint-substitute; see M-ROKU-18.
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run tests..."; \
		$(MAKE) _run_rooibos; \
	elif command -v rokuunit >/dev/null 2>&1; then \
		echo "Running tests with rokuunit..."; \
		rokuunit; \
	else \
		echo "No Roku host configured — running the headless (brs) interpreter gate."; \
		node tests/scripts/run-headless-unit.mjs; \
	fi

# Internal target to run rooibos with host
_run_rooibos:
	@if command -v rooibos >/dev/null 2>&1; then \
		rooibos; \
	else \
		npx --yes rooibos-roku; \
	fi

# Run unit tests.
# BrightScript suites have two execution venues (M-ROKU-15/M-ROKU-18 truth):
#  - On a real Roku device/emulator (ROKU_HOST/ROKU_TEST_HOST set): rooibos
#    drives every suite on hardware.
#  - Device-free (CI, workstations): the headless interpreter gate runs the
#    pure-logic suites in the brs BrightScript interpreter — a REAL gate:
#    failures exit non-zero. Suites that depend on device-only idioms are
#    excluded there with per-item reasons recorded in that script's EXCLUDED
#    maps and the W-min91 fixlog.
test-unit:
	@echo "Running unit tests..."
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run unit tests..."; \
		$(MAKE) _run_rooibos_unit; \
	else \
		echo "No Roku host configured — running the headless (brs) unit gate."; \
		node tests/scripts/run-headless-unit.mjs; \
	fi

_run_rooibos_unit:
	@if command -v rooibos >/dev/null 2>&1; then \
		rooibos --group unit; \
	else \
		npx --yes rooibos-roku --group unit; \
	fi

# Run integration tests (device-only).
# These suites open real sockets from the Roku to a live Phlix server, so they
# require ROKU_HOST/ROKU_TEST_HOST (or the rokuunit CLI) — there is no
# device-free arm here and the recipe says so loudly instead of pretending.
test-integration:
	@echo "Running integration tests..."
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run integration tests..."; \
		$(MAKE) _run_rooibos_integration; \
	elif command -v rokuunit >/dev/null 2>&1; then \
		echo "Running integration tests with rokuunit..."; \
		rokuunit --group integration; \
	else \
		echo "ERROR: integration tests need a Roku device/emulator."; \
		echo "Set ROKU_HOST (or install rokuunit) — the headless brs gate covers unit suites only."; \
		echo "Integration test files:"; \
		if [ -d $(TESTS_DIR)/integration ]; then find $(TESTS_DIR)/integration -name "*.test.brs" -exec basename {} \; | head -5; else echo "  No integration tests found"; fi; \
		exit 1; \
	fi

_run_rooibos_integration:
	@if command -v rooibos >/dev/null 2>&1; then \
		rooibos --group integration; \
	else \
		npx --yes rooibos-roku --group integration; \
	fi

# ===========================================
# Linting
# ===========================================

# Run linter (brighterscript = the real zero-error gate)
lint:
	@echo "Running brighterscript (bsc)..."
	npx bsc --project bsconfig.json

# Run bslint (BrightScript linter) - hard gate (fails on any issue)
bslint:
	@echo "Running bslint..."
	@output=$$(npx bslint --project bsconfig.json 2>&1); \
	ec=$$?; \
	if [ $$ec -ne 0 ]; then \
		echo "$$output"; \
		echo ""; \
		echo "bslint failed with exit code $$ec - failing build"; \
		exit 1; \
	fi; \
	if echo "$$output" | grep -qE "^\s*\[([0-9]+:[0-9]+:[0-9]+.[0-9]+)\].*- (error|warning)"; then \
		echo "$$output"; \
		echo ""; \
		echo "bslint found issues - failing build"; \
		exit 1; \
	fi
	@echo "  ✓ bslint passed"

# Fix common lint issues
lint-fix:
	@echo "Running lint fixes..."
	@echo "Removing trailing whitespace..."
	@find $(SOURCE_DIR) -name "*.brs" -exec sed -i 's/[[:space:]]*$//' {} \;
	@echo "  ✓ Trailing whitespace removed"
	@echo ""
	@echo "Lint fix complete. Review changes before committing."

# ===========================================
# Validation
# ===========================================

# Validate manifest
validate-manifest:
	@echo "Validating manifest..."
	@if grep -q "^title=" manifest; then \
		echo "  ✓ title field present"; \
	else \
		echo "ERROR: manifest missing title field"; \
		exit 1; \
	fi
	@if grep -q "^major_version=" manifest; then \
		echo "  ✓ major_version field present"; \
	else \
		echo "ERROR: manifest missing major_version field"; \
		exit 1; \
	fi
	@if grep -q "^minor_version=" manifest; then \
		echo "  ✓ minor_version field present"; \
	else \
		echo "ERROR: manifest missing minor_version field"; \
		exit 1; \
	fi
	@if grep -q "^build_version=" manifest; then \
		echo "  ✓ build_version field present"; \
	else \
		echo "ERROR: manifest missing build_version field"; \
		exit 1; \
	fi
	@echo "Manifest validation passed."

# Validate XML files — delegated to scripts/validate-xml.sh (estate CI-gate
# audit 2026-10-02). The old inline glob loop exited 0 VACUOUSLY whenever it
# discovered zero files (renamed dir / drifted path pattern validated nothing
# yet greened the gate). The script counts its discovery and fails loudly on a
# zero-file run; red-leg: tests/scripts/verify-runtime-portable.sh leg (13).
validate-xml:
	@bash "$(CURDIR)/scripts/validate-xml.sh" "$(abspath $(COMPONENTS_DIR))"

# ===========================================
# CI/CD helpers
# ===========================================

# Check all prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v zip >/dev/null 2>&1 && echo "  ✓ zip available" || echo "  WARNING: zip not found"
	@command -v curl >/dev/null 2>&1 && echo "  ✓ curl available" || echo "  WARNING: curl not found"
	@if [ -d .github/workflows ]; then \
		echo "  ✓ GitHub Actions configured"; \
	else \
		echo "  WARNING: .github/workflows not found"; \
	fi
	@if [ -f README.md ]; then \
		echo "  ✓ README.md exists"; \
	else \
		echo "  WARNING: README.md not found"; \
	fi
	@if [ -f DEVELOPER.md ]; then \
		echo "  ✓ DEVELOPER.md exists"; \
	else \
		echo "  WARNING: DEVELOPER.md not found"; \
	fi

verify-runtime:
	@bash "$(CURDIR)/scripts/verify-runtime.sh"

# C08 artifact gate: assert the sideload zip's on-disk layout (root manifest,
# no build/ entries, required trees). `make package` runs this on its own
# output; this standalone target lets a CI job open the exact artifact it is
# about to upload/release without rebuilding it.
verify-package:
	@bash "$(CURDIR)/scripts/verify-package.sh" "$(CURDIR)/$(PKG_NAME).zip"

# S280: client route gate — every URL this client issues must be tuple-exact
# against the vendored phlix-server manifest (tests/fixtures/server-route-manifest.json).
# Device-free by design: static scan + exact compare, runs anywhere Node runs.
validate-routes:
	@echo "Validating issued routes against the vendored server manifest (S280)..."
	@node tests/scripts/verify-route-manifest.mjs
	@echo "  ✓ route gate green"
	@echo "  ✓ route gate falsifiability:" && node tests/scripts/verify-route-manifest.mjs --self-test

# Full validation suite
validate: validate-manifest validate-xml validate-routes test
	@echo ""
	@echo "All validations passed."

# ===========================================
# Documentation
# ===========================================

# Generate API documentation
docs-api:
	@echo "Generating API documentation..."
	@echo "# Phlix Roku API Reference" > API.md
	@echo "" >> API.md
	@echo "## ApiClient Methods" >> API.md
	@grep -E "^        ' [A-Z].*" $(LIB_DIR)/ApiClient.brs | sed "s/        ' /- /" >> API.md
	@echo "" >> API.md
	@echo "API.md generated."

# Default target
.DEFAULT_GOAL := package
