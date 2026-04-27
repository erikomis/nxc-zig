#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "============================================"
echo "  nxc - Running all tests"
echo "============================================"
echo ""

# Build and run Zig unit tests
echo "--- Running Zig unit tests ---"
zig build test 2>&1 || {
    echo ""
    echo "ERROR: Some Zig unit tests failed."
    exit 1
}

echo ""
echo "--- Checking test file structure ---"
EXPECTED_TESTS=(
    "tests/fuzz/fuzz.zig"
    "tests/bench/bench.zig"
    "tests/diff/diff_test.zig"
    "tests/stress/stress_test.zig"
    "tests/memory/memory_test.zig"
    "tests/concurrency/concurrency_test.zig"
    "tests/test_root.zig"
    "tests/run_all_tests.sh"
)

all_ok=true
for f in "${EXPECTED_TESTS[@]}"; do
    if [ -f "$f" ]; then
        echo "  [OK] $f"
    else
        echo "  [MISSING] $f"
        all_ok=false
    fi
done

echo ""
if $all_ok; then
    echo "All test files present."
else
    echo "ERROR: Some test files are missing."
    exit 1
fi

echo ""
echo "============================================"
echo "  All tests completed successfully!"
echo "============================================"
