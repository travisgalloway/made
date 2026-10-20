.PHONY: all help setup build build-tests test test-ui test-viewport bundle run run-mcp clean ci-local hooks

PKG_PATH := macos
# Swift Build compiles Shaders.metal; the native build system (the Swift 6.3 default) only copies it.
SWIFT_FLAGS := --package-path $(PKG_PATH) --build-system swiftbuild
APP_BINARY := $(PKG_PATH)/.build/Made.app/Contents/MacOS/MadeApp

all: build

help:
	@echo "Available make targets for made:"
	@echo "  make setup          Install the Metal Toolchain and the git hooks"
	@echo "  make build          Build MadeApp and MadeCore library"
	@echo "  make build-tests    Build application targets and unit test suite"
	@echo "  make test           Run all unit tests (or 'make test FILTER=<name>')"
	@echo "  make test-ui        Run XCUITest UI tests (or 'make test-ui FILTER=<name>')"
	@echo "  make test-viewport  Run Metal 4 XCUITest viewport tests (or 'make test-viewport FILTER=<name>')"
	@echo "  make bundle         Assemble macos/.build/Made.app with the kernel XPC service"
	@echo "  make run            Launch the bundled MadeApp GUI application"
	@echo "  make run-mcp        Run the bundled MadeApp with embedded MCP server on stdio"
	@echo "  make clean          Clean SwiftPM build artifacts and caches"
	@echo "  make ci-local       Run full build-tests and test suite locally"
	@echo "  make hooks          Install the pre-commit and pre-push hooks that run the Metal test suites"

build:
	swift build $(SWIFT_FLAGS)

build-tests:
	swift build $(SWIFT_FLAGS) --build-tests

test:
ifdef FILTER
	swift test $(SWIFT_FLAGS) --filter $(FILTER)
else
	swift test $(SWIFT_FLAGS)
endif

bundle: build
	$(PKG_PATH)/scripts/bundle-app.sh

test-ui: bundle
ifdef FILTER
	xcodebuild test -project $(PKG_PATH)/UITests/MadeUITests.xcodeproj -scheme MadeUITests -destination "platform=macOS" -derivedDataPath $(PKG_PATH)/.build/UITests $(if $(findstring MadeUITests/,$(FILTER)),-only-testing:$(FILTER),-only-testing:MadeUITests/$(FILTER))
else
	xcodebuild test -project $(PKG_PATH)/UITests/MadeUITests.xcodeproj -scheme MadeUITests -destination "platform=macOS" -derivedDataPath $(PKG_PATH)/.build/UITests
endif

test-viewport: bundle
ifdef FILTER
	MADE_UI_REQUIRE_METAL4=1 xcodebuild test -project $(PKG_PATH)/UITests/MadeUITests.xcodeproj -scheme MadeUITests -destination "platform=macOS" -derivedDataPath $(PKG_PATH)/.build/UITests $(if $(findstring MadeUITests/,$(FILTER)),-only-testing:$(FILTER),-only-testing:MadeUITests/$(FILTER))
else
	MADE_UI_REQUIRE_METAL4=1 xcodebuild test -project $(PKG_PATH)/UITests/MadeUITests.xcodeproj -scheme MadeUITests -destination "platform=macOS" -derivedDataPath $(PKG_PATH)/.build/UITests -only-testing:MadeUITests/ViewportSelectionUITests
endif
	mkdir -p $(PKG_PATH)/.build/viewport-pass
	touch $(PKG_PATH)/.build/viewport-pass/$$(git rev-parse HEAD^{tree})

# Runs the bundle's executable directly, so stdout and logs stay in this terminal.
run: bundle
	$(APP_BINARY)

run-mcp: bundle
	$(APP_BINARY) --mcp-stdio

clean:
	swift package --package-path $(PKG_PATH) clean
	rm -rf $(PKG_PATH)/.build

ci-local: build-tests test

hooks:
	git config core.hooksPath .githooks

setup: hooks
	xcodebuild -downloadComponent MetalToolchain
