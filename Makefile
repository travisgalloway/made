.PHONY: all help setup build build-tests test run run-mcp clean ci-local hooks

PKG_PATH := macos
# Swift Build compiles Shaders.metal; the native build system (the Swift 6.3 default) only copies it.
SWIFT_FLAGS := --package-path $(PKG_PATH) --build-system swiftbuild

all: build

help:
	@echo "Available make targets for made:"
	@echo "  make setup          Install the Metal Toolchain and the git hooks"
	@echo "  make build          Build MadeApp and MadeCore library"
	@echo "  make build-tests    Build application targets and unit test suite"
	@echo "  make test           Run all unit tests (or 'make test FILTER=<name>')"
	@echo "  make run            Launch MadeApp GUI application"
	@echo "  make run-mcp        Run MadeApp with embedded MCP server on stdio"
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

run:
	swift run $(SWIFT_FLAGS) MadeApp

run-mcp:
	swift run $(SWIFT_FLAGS) MadeApp --mcp-stdio

clean:
	swift package --package-path $(PKG_PATH) clean
	rm -rf $(PKG_PATH)/.build

ci-local: build-tests test

hooks:
	git config core.hooksPath .githooks

setup: hooks
	xcodebuild -downloadComponent MetalToolchain
