.PHONY: all help setup build build-tests test run run-mcp clean ci-local hooks

PKG_PATH := macos

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
	swift build --package-path $(PKG_PATH)

build-tests:
	swift build --package-path $(PKG_PATH) --build-tests

test:
ifdef FILTER
	swift test --package-path $(PKG_PATH) --filter $(FILTER)
else
	swift test --package-path $(PKG_PATH)
endif

run:
	swift run --package-path $(PKG_PATH) MadeApp

run-mcp:
	swift run --package-path $(PKG_PATH) MadeApp --mcp-stdio

clean:
	swift package --package-path $(PKG_PATH) clean
	rm -rf $(PKG_PATH)/.build

ci-local: build-tests test

hooks:
	git config core.hooksPath .githooks

setup: hooks
	xcodebuild -downloadComponent MetalToolchain
