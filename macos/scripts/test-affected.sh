#!/usr/bin/env bash
# Selective test runner for made (SwiftPM + XcodeSelectiveTesting).
# Determines affected SwiftPM unit test targets/suites and XCUITest targets against a merge-base
# (default: origin/main) with a fail-open full-suite bypass for build/CI/dependency changes.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"

BASE_BRANCH="${BASE_REF:-origin/main}"
MODE="unit"
CI_MODE=0
DRY_RUN=0
SKIP_BUILD="${SKIP_BUILD:-0}"
declare -a EXPLICIT_FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --base-branch)
            BASE_BRANCH="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --ci)
            CI_MODE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -c|--changed-files)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                EXPLICIT_FILES+=("$1")
                shift
            done
            ;;
        -h|--help)
            cat <<'EOF'
Usage: macos/scripts/test-affected.sh [options]

Options:
  --base-branch <ref>       Base branch for three-dot merge-base diff (default: origin/main)
  --mode <unit|ui|plan>     Execution mode: unit (swift test), ui (XCUITest), or plan (JSON output)
  --ci                      CI mode (diff merge-base...HEAD only; honor push/merge_group backstop)
  --skip-build              Pass --skip-build to swift test
  --dry-run                 Print resolved test commands without executing them
  -c, --changed-files ...   Explicit list of changed files (overrides git diff)
EOF
            exit 0
            ;;
        *)
            echo "test-affected: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

XST_VERSION="0.16.1"
XST_BIN="$repo_root/macos/.build/tools/xcode-selective-test"

ensure_xst() {
    if command -v xcode-selective-test >/dev/null 2>&1; then
        command -v xcode-selective-test
        return 0
    fi
    if [ -x "$XST_BIN" ]; then
        echo "$XST_BIN"
        return 0
    fi
    mkdir -p "$(dirname "$XST_BIN")"
    local archive_url="https://github.com/mikeger/XcodeSelectiveTesting/releases/download/${XST_VERSION}/xcode-selective-test.tar.gz"
    if curl -fsSL "$archive_url" | tar -xz -C "$(dirname "$XST_BIN")" 2>/dev/null && [ -x "$XST_BIN" ]; then
        echo "$XST_BIN"
        return 0
    fi
    return 1
}

FULL_SUITE=0
FULL_REASON=""
declare -a CHANGED_FILES=()

# 1. Push to main / merge_group / release tag backstop
if [ "${FORCE_FULL_TESTS:-0}" = "1" ]; then
    FULL_SUITE=1
    FULL_REASON="FORCE_FULL_TESTS=1"
elif [ "$CI_MODE" -eq 1 ] && [[ "${GITHUB_EVENT_NAME:-}" =~ ^(push|merge_group|workflow_dispatch|release)$ ]]; then
    FULL_SUITE=1
    FULL_REASON="CI backstop event (${GITHUB_EVENT_NAME})"
fi

# 2. Resolve changed files via three-dot merge-base diff
if [ "$FULL_SUITE" -eq 0 ]; then
    if [ "${#EXPLICIT_FILES[@]}" -gt 0 ]; then
        CHANGED_FILES=("${EXPLICIT_FILES[@]}")
    else
        resolved_base="$BASE_BRANCH"
        if ! git rev-parse --verify "${resolved_base}^{commit}" >/dev/null 2>&1; then
            if git rev-parse --verify "HEAD~1^{commit}" >/dev/null 2>&1; then
                resolved_base="HEAD~1"
            else
                resolved_base="HEAD"
            fi
        fi

        while IFS= read -r line; do
            [ -n "$line" ] && CHANGED_FILES+=("$line")
        done < <(
            {
                git diff --name-only "${resolved_base}...HEAD"
                if [ "$CI_MODE" -eq 0 ]; then
                    git diff --name-only HEAD
                    git diff --name-only --cached
                fi
            } | sort -u
        )
    fi
fi

# 3. Fail-open full-suite bypass check
if [ "$FULL_SUITE" -eq 0 ] && [ "${#CHANGED_FILES[@]}" -gt 0 ]; then
    for file in "${CHANGED_FILES[@]}"; do
        case "$file" in
            .github/workflows/*|.github/actions/*|Makefile|Dockerfile*|docker-compose*|\
            pnpm-lock.yaml|package-lock.json|uv.lock|poetry.lock|requirements*.txt|\
            go.mod|go.sum|Cargo.lock|*Package.resolved|*Package.swift|\
            tsconfig*.json|vitest.config.*|jest.config.*|playwright.config.*|\
            pyproject.toml|pytest.ini|conftest.py|build.rs|rust-toolchain*|\
            *.xcodeproj/project.pbxproj|*.xctestplan|*.xcscheme|\
            macos/scripts/bundle-app.sh|macos/scripts/test-affected.sh|macos/Support/*|.githooks/*)
                FULL_SUITE=1
                FULL_REASON="fail-open infrastructure/dependency file ($file)"
                break
                ;;
        esac
    done
fi

AFFECTED_UNIT="false"
UNIT_FILTER=""
AFFECTED_UI="false"
UI_ONLY_TESTING=""

if [ "$FULL_SUITE" -eq 1 ]; then
    AFFECTED_UNIT="true"
    UNIT_FILTER=""
    AFFECTED_UI="true"
    UI_ONLY_TESTING="-only-testing:MadeUITests"
elif [ "${#CHANGED_FILES[@]}" -gt 0 ]; then
    core_changed=0
    app_changed=0
    kernel_service_changed=0
    core_tests_changed=0
    app_tests_changed=0
    ui_tests_changed=0
    only_unit_test_suites=1
    declare -a touched_suites=()

    # Query XcodeSelectiveTesting if available alongside SwiftPM dump-package graph
    xst_targets=""
    if xst_cmd=$(ensure_xst); then
        declare -a xst_args=()
        for f in "${CHANGED_FILES[@]}"; do
            xst_args+=("-c" "$f")
        done
        xst_pkg_json=$("$xst_cmd" macos --json "${xst_args[@]}" 2>/dev/null | sed -n '/^\[/,$p' || true)
        xst_ui_json=$("$xst_cmd" macos/UITests/MadeUITests.xcodeproj --json "${xst_args[@]}" 2>/dev/null | sed -n '/^\[/,$p' || true)
        if [ -n "$xst_pkg_json" ]; then
            xst_targets=$(printf '%s\n' "$xst_pkg_json" | jq -r '.[].name' 2>/dev/null || true)
        fi
        if [ -n "$xst_ui_json" ] && printf '%s\n' "$xst_ui_json" | jq -e '.[] | select(.name == "MadeUITests")' >/dev/null 2>&1; then
            ui_tests_changed=1
        fi
    fi

    # Also evaluate reverse dependencies via swift package dump-package + jq
    pkg_dump=$(swift package --package-path macos dump-package 2>/dev/null || true)
    app_depends_on_core=1
    if [ -n "$pkg_dump" ]; then
        app_depends_on_core=$(printf '%s\n' "$pkg_dump" | jq -r '
            [.targets[] | select(.name == "MadeApp") | .dependencies[] | (.byName[0] // .product[0])] | index("MadeCore") | if . != null then 1 else 0 end
        ' 2>/dev/null || echo 1)
    fi

    if printf '%s\n' "$xst_targets" | grep -qx "MadeCore"; then
        core_changed=1
    fi
    if printf '%s\n' "$xst_targets" | grep -qx "MadeApp"; then
        app_changed=1
    fi
    if printf '%s\n' "$xst_targets" | grep -qx "MadeKernelService"; then
        kernel_service_changed=1
    fi

    for file in "${CHANGED_FILES[@]}"; do
        case "$file" in
            macos/Sources/MadeCore/*|macos/Tests/Goldens/*)
                core_changed=1
                only_unit_test_suites=0
                ;;
            macos/Sources/MadeApp/*)
                app_changed=1
                only_unit_test_suites=0
                ;;
            macos/Sources/MadeKernelService/*)
                kernel_service_changed=1
                only_unit_test_suites=0
                ;;
            macos/Tests/MadeCoreTests/*.swift)
                core_tests_changed=1
                suite_name=$(basename "$file" .swift)
                touched_suites+=("MadeCoreTests\\.${suite_name}")
                ;;
            macos/Tests/MadeCoreTests/*)
                core_tests_changed=1
                only_unit_test_suites=0
                ;;
            macos/Tests/MadeAppTests/*.swift)
                app_tests_changed=1
                suite_name=$(basename "$file" .swift)
                touched_suites+=("MadeAppTests\\.${suite_name}")
                ;;
            macos/Tests/MadeAppTests/*)
                app_tests_changed=1
                only_unit_test_suites=0
                ;;
            macos/UITests/*|img/made.icon/*)
                ui_tests_changed=1
                ;;
        esac
    done

    # Transitive closure: MadeCore -> MadeCoreTests, MadeAppTests, MadeUITests
    if [ "$core_changed" -eq 1 ]; then
        core_tests_changed=1
        if [ "$app_depends_on_core" -eq 1 ]; then
            app_tests_changed=1
        fi
        ui_tests_changed=1
    fi

    # Transitive closure: MadeApp -> MadeAppTests, MadeUITests
    if [ "$app_changed" -eq 1 ]; then
        app_tests_changed=1
        ui_tests_changed=1
    fi

    # Transitive closure: MadeKernelService -> MadeUITests (bundled XPC service)
    if [ "$kernel_service_changed" -eq 1 ]; then
        ui_tests_changed=1
    fi

    if [ "$core_tests_changed" -eq 1 ] || [ "$app_tests_changed" -eq 1 ]; then
        AFFECTED_UNIT="true"
        if [ "$only_unit_test_suites" -eq 1 ] && [ "${#touched_suites[@]}" -gt 0 ]; then
            joined=$(printf '%s\n' "${touched_suites[@]}" | sort -u | paste -sd '|' -)
            UNIT_FILTER="^(${joined})/"
        elif [ "$core_tests_changed" -eq 1 ] && [ "$app_tests_changed" -eq 0 ]; then
            UNIT_FILTER="^MadeCoreTests\\."
        elif [ "$app_tests_changed" -eq 1 ] && [ "$core_tests_changed" -eq 0 ]; then
            UNIT_FILTER="^MadeAppTests\\."
        else
            UNIT_FILTER=""
        fi
    fi

    if [ "$ui_tests_changed" -eq 1 ]; then
        AFFECTED_UI="true"
        UI_ONLY_TESTING="-only-testing:MadeUITests"
    fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "full_suite=$( [ "$FULL_SUITE" -eq 1 ] && echo true || echo false )"
        echo "affected_unit=${AFFECTED_UNIT}"
        echo "unit_filter=${UNIT_FILTER}"
        echo "affected_ui=${AFFECTED_UI}"
        echo "ui_only_testing=${UI_ONLY_TESTING}"
    } >> "$GITHUB_OUTPUT"
fi

case "$MODE" in
    plan)
        jq -n \
            --arg base "$BASE_BRANCH" \
            --argjson full_suite "$( [ "$FULL_SUITE" -eq 1 ] && echo true || echo false )" \
            --arg full_reason "$FULL_REASON" \
            --argjson affected_unit "$AFFECTED_UNIT" \
            --arg unit_filter "$UNIT_FILTER" \
            --argjson affected_ui "$AFFECTED_UI" \
            --arg ui_only_testing "$UI_ONLY_TESTING" \
            '{
                baseBranch: $base,
                fullSuite: $full_suite,
                fullReason: $full_reason,
                affectedUnit: $affected_unit,
                unitFilter: $unit_filter,
                affectedUI: $affected_ui,
                uiOnlyTesting: $ui_only_testing
            }'
        ;;
    unit)
        if [ "$FULL_SUITE" -eq 1 ]; then
            echo "test-affected: full unit test suite triggered (${FULL_REASON})"
        fi
        if [ "$AFFECTED_UNIT" != "true" ]; then
            echo "test-affected: no SwiftPM unit test targets affected relative to ${BASE_BRANCH}; skipping unit tests."
            exit 0
        fi
        declare -a swift_cmd=(swift test --package-path macos --build-system swiftbuild)
        if [ "$SKIP_BUILD" -eq 1 ]; then
            swift_cmd+=(--skip-build)
        fi
        if [ -n "$UNIT_FILTER" ]; then
            echo "test-affected: running selective unit tests with filter: ${UNIT_FILTER}"
            swift_cmd+=(--filter "$UNIT_FILTER")
        else
            echo "test-affected: running all unit test targets (MadeCoreTests + MadeAppTests)"
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            printf 'DRY_RUN: %q ' "${swift_cmd[@]}"
            printf '\n'
            exit 0
        fi
        "${swift_cmd[@]}"
        ;;
    ui)
        if [ "$FULL_SUITE" -eq 1 ]; then
            echo "test-affected: full UI test suite triggered (${FULL_REASON})"
        fi
        if [ "$AFFECTED_UI" != "true" ]; then
            echo "test-affected: no XCUITest targets affected relative to ${BASE_BRANCH}; skipping UI tests."
            exit 0
        fi
        echo "test-affected: running XCUITest target (${UI_ONLY_TESTING})"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "DRY_RUN: make test-ui"
            exit 0
        fi
        make test-ui
        ;;
    *)
        echo "test-affected: unsupported mode '$MODE' (expected unit, ui, or plan)" >&2
        exit 1
        ;;
esac
