#!/usr/bin/env bash

# Test script for check.sh

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check.sh"
CORPUS_DIR="$(cd "$(dirname "$0")/../codeowners-tools-corpus" && pwd)"
PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local expected_exit="$2"
    shift 2
    local output
    local exit_code

    echo "Test: $name"
    set +e
    output=$(cd "$CORPUS_DIR" && "$@" 2>&1)
    exit_code=$?
    set -e

    if [[ $exit_code -eq $expected_exit ]]; then
        echo "  ✓ Exit code $exit_code (expected)"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ Exit code $exit_code (expected $expected_exit)"
        FAILED=$((FAILED + 1))
    fi

    if [[ -n "$output" ]]; then
        echo "  Output: $output"
    else
        echo "  Output: (none)"
    fi
    echo ""
}

echo "=== Testing check.sh ==="
echo ""

# Test success cases
test_case "Success with matches" 0 "$SCRIPT" a35f805 a35f805 .github/CODEOWNERS
test_case "Success with multiple files" 0 "$SCRIPT" 7f35e64 7f35e64 .github/CODEOWNERS
test_case "Single file - last match wins" 0 "$SCRIPT" 6b24f01 6b24f01 .github/CODEOWNERS
test_case "Complex pattern (**/ pattern)" 0 "$SCRIPT" a35f805 a35f805 .github/CODEOWNERS
test_case "Wildcard pattern" 0 "$SCRIPT" a35f805 a35f805 .github/CODEOWNERS
test_case "PR scenario - base CODEOWNERS applies" 0 "$SCRIPT" a35f805 a1752a1 .github/CODEOWNERS

# Test error cases
test_case "Missing base-commit argument" 4 "$SCRIPT"
test_case "Missing candidate-commit argument" 5 "$SCRIPT" HEAD
test_case "Missing codeowners-file argument" 6 "$SCRIPT" HEAD HEAD
test_case "CODEOWNERS not found" 1 "$SCRIPT" HEAD HEAD /nonexistent/file
test_case "Invalid commit" 2 "$SCRIPT" invalidcommit123 a35f805 .github/CODEOWNERS

# Test git repo check (run in /tmp)
echo "Test: Not in git repository"
CODEOWNERS_FULL_PATH="$CORPUS_DIR/.github/CODEOWNERS"
set +e
output=$(cd /tmp && "$SCRIPT" HEAD HEAD "$CODEOWNERS_FULL_PATH" 2>&1)
exit_code=$?
set -e

if [[ $exit_code -eq 3 ]]; then
    echo "  ✓ Exit code 3 (expected)"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ Exit code $exit_code (expected 3)"
    FAILED=$((FAILED + 1))
fi
echo "  Output: $output"
echo ""

# Summary
echo "=== Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed! ✓"
    exit 0
else
    echo "Some tests failed! ✗"
    exit 1
fi
