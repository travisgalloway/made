.PHONY: all help build build-tests test run run-mcp clean ci-local

PKG_PATH := macos

all: build

help:
	@echo "Available make targets for made:"
	@echo "  make build          Build MadeApp and MadeCore library"
	@echo "  make build-tests    Build application targets and unit test suite"
	@echo "  make test           Run all unit tests (or 'make test FILTER=<name>')"
	@echo "  make run            Launch MadeApp GUI application"
	@echo "  make run-mcp        Run MadeApp with embedded MCP server on stdio"
	@echo "  make clean          Clean SwiftPM build artifacts and caches"
	@echo "  make ci-local       Run full build-tests and test suite locally"

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
