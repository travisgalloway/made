#!/bin/sh
# Shared by pre-commit and pre-push. Runs the Metal-backed suites, because CI runners may lack a GPU and skip them.
# Usage: run-metal-tests.sh <hook name> <bypass command>. A failure, a skip, or a missing result exits 1.

hook=$1
bypass="Fix the tests, or bypass deliberately with: $2"

repo_root=$(git rev-parse --show-toplevel) || exit 1
cd "$repo_root" || exit 1

# A suite is Metal-backed when it asks for a device, so new suites join without editing this script.
suites=$(grep -l 'MTLCreateSystemDefaultDevice' macos/Tests/MadeCoreTests/*.swift | xargs -n1 basename | sed 's/\.swift$//' | paste -sd '|' -)
if [ -z "$suites" ]; then
    echo "$hook: found no Metal-backed test suites, so nothing was verified" >&2
    exit 1
fi

log=$(mktemp -t "made-$hook") || exit 1
echo "$hook: running Metal suites ($suites)"
swift test --package-path macos --filter "^MadeCoreTests\.($suites)/" >"$log" 2>&1
status=$?

if [ "$status" -ne 0 ]; then
    grep -E 'error:|failed \(' "$log" >&2
    echo "$hook: Metal suites failed (exit $status). Full log: $log" >&2
    echo "$bypass" >&2
    exit 1
fi

skipped=$(grep -c ' skipped (' "$log")
if [ "$skipped" -gt 0 ]; then
    grep ' skipped (' "$log" >&2
    echo "$hook: $skipped Metal tests skipped, so the suites did not run. Full log: $log" >&2
    echo "$bypass" >&2
    exit 1
fi

executed=$(grep -E 'Executed [0-9]+ tests?' "$log" | tail -1)
if [ -z "$executed" ]; then
    echo "$hook: the test log has no result line, so the outcome is unknown. Full log: $log" >&2
    echo "$bypass" >&2
    exit 1
fi

echo "$hook:$executed" | sed 's/[[:space:]]\{2,\}/ /g'
rm -f "$log"
