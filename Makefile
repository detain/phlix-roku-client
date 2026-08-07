.PHONY: all package install dev clean test lint lint-fix validate-manifest _run_rooibos _run_rooibos_unit _run_rooibos_integration

# Roku IP address (set via environment or edit here)
ROKU_IP ?= 192.168.1.100
ROKU_DEV ?= rokudev
ROKU_PASSWORD ?= rokipassword

# Package name
PKG_NAME = phlix
PKG_VERSION = 1.0.1

# Source directories
SOURCE_DIR = source
TESTS_DIR = tests
LIB_DIR = $(SOURCE_DIR)/lib
COMPONENTS_DIR = components

all: package

# Create zip package for sideloading
package:
	@echo "Creating $(PKG_NAME).zip..."
	zip -r $(PKG_NAME).zip manifest source components images

# Build a signed package for store submission
# Requires: ROKU_DEV_PASSWORD set, rokudev auth via `rokudev auth`
package-signed:
	@echo "Building signed package..."
	@bash scripts/package-signed.sh
	@echo "Signed package ready. See docs/publishing.md for submission steps."

# Install to Roku device
install: package
	@echo "Installing to Roku at $(ROKU_IP)..."
	curl -v -u $(ROKU_DEV):$(ROKU_PASSWORD) -X POST \
		http://$(ROKU_IP):8060/install/app \
		-F "archive=@$(PKG_NAME).zip" \
		-F "manifest=@manifest"

# Launch the app (after install)
launch:
	@echo "Launching $(PKG_NAME)..."
	curl -u $(ROKU_DEV):$(ROKU_PASSWORD) -X POST \
		http://$(ROKU_IP):8060/launch/dev \
		--data-urlencode "channel=dev"

# Stop the app
stop:
	@echo "Stopping $(PKG_NAME)..."
	curl -u $(ROKU_DEV):$(ROKU_PASSWORD) -X POST \
		http://$(ROKU_IP):8060/keypress/home

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
	@# rooibos requires a Roku device/emulator (set ROKU_HOST env var)
	@# If ROKU_HOST is not set and no local runner available, fail with clear message
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run tests..."; \
		$(MAKE) _run_rooibos; \
	elif command -v rokuunit >/dev/null 2>&1; then \
		echo "Running tests with rokuunit..."; \
		rokuunit; \
	elif command -v rooibos >/dev/null 2>&1; then \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "rooibos requires a Roku device/emulator. Set ROKU_HOST environment variable."; \
		echo "Falling back to lint check..."; \
		$(MAKE) lint; \
		exit 1; \
	elif command -v npx >/dev/null 2>&1 && npx --yes rooibos-roku --help >/dev/null 2>&1; then \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "rooibos-roku requires a Roku device/emulator. Set ROKU_HOST environment variable."; \
		echo "Falling back to lint check..."; \
		$(MAKE) lint; \
		exit 1; \
	else \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "No BrightScript test runner (rokuunit/rooibos/rooibos-roku) is available."; \
		echo "Falling back to lint check..."; \
		$(MAKE) lint; \
		exit 1; \
	fi

# Internal target to run rooibos with host
_run_rooibos:
	@if command -v rooibos >/dev/null 2>&1; then \
		rooibos; \
	else \
		npx --yes rooibos-roku; \
	fi

# Run unit tests only.
# BrightScript unit tests can ONLY execute on a real Roku device/emulator (rooibos).
# When no device is configured (e.g. CI) this SKIPS with success rather than failing —
# the brighterscript zero-error gate (`make lint`) is the real automated check. Set
# ROKU_HOST to actually run the suite against a device.
test-unit:
	@echo "Running unit tests..."
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run unit tests..."; \
		$(MAKE) _run_rooibos_unit; \
	else \
		echo "Tests require hardware — skipping"; \
		echo "Unit test files present:"; \
		if [ -d $(TESTS_DIR)/unit ]; then find $(TESTS_DIR)/unit -name "*.test.brs" -exec basename {} \; | head -10; else echo "  (none)"; fi; \
		exit 2; \
	fi

_run_rooibos_unit:
	@if command -v rooibos >/dev/null 2>&1; then \
		rooibos --group unit; \
	else \
		npx --yes rooibos-roku --group unit; \
	fi

# Run integration tests only
test-integration:
	@echo "Running integration tests..."
	@if [ -n "$$ROKU_HOST" ] || [ -n "$$ROKU_TEST_HOST" ]; then \
		echo "Roku host detected ($$ROKU_HOST$$ROKU_TEST_HOST), attempting to run integration tests..."; \
		$(MAKE) _run_rooibos_integration; \
	elif command -v rokuunit >/dev/null 2>&1; then \
		echo "Running integration tests with rokuunit..."; \
		rokuunit --group integration; \
		exit 1; \
	elif command -v rooibos >/dev/null 2>&1; then \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "rooibos requires a Roku device/emulator. Set ROKU_HOST environment variable."; \
		echo "Integration test files:"; \
		if [ -d $(TESTS_DIR)/integration ]; then find $(TESTS_DIR)/integration -name "*.test.brs" -exec basename {} \; | head -5; else echo "  No integration tests found"; fi; \
		exit 1; \
	elif command -v npx >/dev/null 2>&1 && npx --yes rooibos-roku --help >/dev/null 2>&1; then \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "rooibos-roku requires a Roku device/emulator. Set ROKU_HOST environment variable."; \
		echo "Integration test files:"; \
		if [ -d $(TESTS_DIR)/integration ]; then find $(TESTS_DIR)/integration -name "*.test.brs" -exec basename {} \; | head -5; else echo "  No integration tests found"; fi; \
		exit 1; \
	else \
		echo "ERROR: Tests cannot run in this environment."; \
		echo "No BrightScript test runner (rokuunit/rooibos/rooibos-roku) is available."; \
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

# Validate XML files
validate-xml:
	@echo "Validating XML files..."
	@FOUND=0; \
	for xml in $(COMPONENTS_DIR)/*.xml; do \
		if [ -f "$$xml" ]; then \
			if grep -q '<?xml version' "$$xml" && grep -q '</component>' "$$xml"; then \
				echo "  ✓ $$(basename $$xml)"; \
			else \
				echo "  ERROR: $$(basename $$xml) - invalid structure"; \
				FOUND=1; \
			fi; \
		fi; \
	done; \
	if [[ $$FOUND -eq 1 ]]; then exit 1; fi

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

# Full validation suite
validate: validate-manifest validate-xml test
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
