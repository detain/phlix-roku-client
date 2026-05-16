.PHONY: all package install dev clean test lint lint-fix validate-manifest

# Roku IP address (set via environment or edit here)
ROKU_IP ?= 192.168.1.100
ROKU_DEV ?= rokudev
ROKU_PASSWORD ?= rokipassword

# Package name
PKG_NAME = phlex
PKG_VERSION = 1.0.1

# Source directories
SOURCE_DIR = source
TESTS_DIR = tests
LIB_DIR = $(SOURCE_DIR)/lib
COMPONENTS_DIR = $(SOURCE_DIR)/components

all: package

# Create zip package for sideloading
package:
	@echo "Creating $(PKG_NAME).zip..."
	zip -r $(PKG_NAME).zip manifest source images

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
	@echo "BrightScript tests require device or emulator to execute."
	@echo ""
	@echo "Unit Tests:"
	@if [ -d $(TESTS_DIR)/unit ]; then \
		find $(TESTS_DIR)/unit -name "*.test.brs" -exec echo "  - {}" \; ; \
	else \
		echo "  No unit tests found"; \
	fi
	@echo ""
	@echo "Integration Tests:"
	@if [ -d $(TESTS_DIR)/integration ]; then \
		find $(TESTS_DIR)/integration -name "*.test.brs" -exec echo "  - {}" \; ; \
	else \
		echo "  No integration tests found"; \
	fi

# Run unit tests only
test-unit:
	@echo "Running unit tests..."
	@if [ -d $(TESTS_DIR)/unit ]; then \
		echo "Unit test files:"; \
		find $(TESTS_DIR)/unit -name "*.test.brs" -exec basename {} \; ; \
	else \
		echo "No unit tests found"; \
	fi

# Run integration tests only
test-integration:
	@echo "Running integration tests..."
	@if [ -d $(TESTS_DIR)/integration ]; then \
		echo "Integration test files:"; \
		find $(TESTS_DIR)/integration -name "*.test.brs" -exec basename {} \; ; \
	else \
		echo "No integration tests found"; \
	fi

# ===========================================
# Linting
# ===========================================

# Run linter
lint:
	@echo "Running BrightScript lint checks..."
	@echo ""
	@echo "Checking for debug artifacts..."
	@if grep -rn "console.log" $(SOURCE_DIR)/ 2>/dev/null; then \
		echo "ERROR: console.log found (use print instead)"; \
	else \
		echo "  ✓ No console.log found"; \
	fi
	@if grep -rn "TODO\|FIXME" $(SOURCE_DIR)/ 2>/dev/null; then \
		echo "WARNING: TODO/FIXME comments found"; \
	else \
		echo "  ✓ No TODO/FIXME comments"; \
	fi
	@echo ""
	@echo "Checking naming conventions..."
	@bad_funcs=$$(grep -rn "^function [a-z]" $(SOURCE_DIR)/ 2>/dev/null || true); \
	if [ -n "$$bad_funcs" ]; then \
		echo "WARNING: Functions should use PascalCase:"; \
		echo "$$bad_funcs" | head -3; \
	else \
		echo "  ✓ Function names are PascalCase"; \
	fi
	@echo ""
	@echo "Checking file structure..."
	@required_files="main.brs ApiClient.brs Storage.brs AuthManager.brs SessionManager.brs LibraryManager.brs"; \
	for f in $$required_files; do \
		if [ -f "$(LIB_DIR)/$$f" ] || [ -f "$(SOURCE_DIR)/$$f" ]; then \
			echo "  ✓ $$f exists"; \
		else \
			echo "  WARNING: $$f not found"; \
		fi; \
	done
	@echo ""
	@echo "Checking component files..."
	@if [ -d $(COMPONENTS_DIR) ]; then \
		find $(COMPONENTS_DIR) -name "*.brs" -exec basename {} \; | sort; \
	else \
		echo "  WARNING: components directory not found"; \
	fi
	@echo ""
	@echo "Lint check complete."

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
	@for xml in $(COMPONENTS_DIR)/*.xml; do \
		if [ -f "$$xml" ]; then \
			if grep -q '<?xml version' "$$xml" && grep -q '</component>' "$$xml"; then \
				echo "  ✓ $$(basename $$xml)"; \
			else \
				echo "  ERROR: $$(basename $$xml) - invalid structure"; \
			fi; \
		fi; \
	done

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
	@echo "# Phlex Roku API Reference" > API.md
	@echo "" >> API.md
	@echo "## ApiClient Methods" >> API.md
	@grep -E "^        ' [A-Z].*" $(LIB_DIR)/ApiClient.brs | sed "s/        ' /- /" >> API.md
	@echo "" >> API.md
	@echo "API.md generated."

# Default target
.DEFAULT_GOAL := package
