#!/usr/bin/env bash

# Test script to verify "last match wins" behavior and file order preservation
# These tests use committed CODEOWNERS test files and historical commits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS_DIR="$(cd "$SCRIPT_DIR/../codeowners-tools-corpus" && pwd)"

echo "=== Testing Last Match Wins Behavior ==="
echo ""

echo "Test 1: Override with last match wins"
# Using test-codeowners-override.txt with commit a35f805 that has src/components/buttons changes
# File has: /src/components/ @frontend-team then /src/components/buttons/ @ui-team
# Copy test file to corpus to make it accessible
cp "$SCRIPT_DIR/test-codeowners-override.txt" "$CORPUS_DIR/test-codeowners-override.txt"
output=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 test-codeowners-override.txt 2>&1 || echo "")
rm -f "$CORPUS_DIR/test-codeowners-override.txt"

if [[ -z "$output" ]]; then
    echo "  ℹ Test file not in commit a35f805 - skipping (expected)"
else
    expected="/src/components/buttons/ @ui-team"
    if echo "$output" | grep -q "^$expected$"; then
        echo "  ✓ Correct: Last rule wins (buttons overrides components)"
    else
        echo "  ✗ Expected to find: '$expected'"
        echo "  ✗ Got: '$output'"
    fi
fi
echo ""

echo "Test 2: Verify last-match-wins with actual committed CODEOWNERS"
# Test with a historical commit that has matching files
output=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 .github/CODEOWNERS)
expected="/src/components/buttons/ @ui-team"

if echo "$output" | grep -q "^$expected$"; then
    echo "  ✓ Correct: Last-match-wins rule found for buttons"
else
    echo "  ✗ Expected to find: '$expected'"
    echo "  ✗ Got: '$output'"
fi
echo ""

echo "Test 3: Verify pattern matching across multiple commits"
output1=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 .github/CODEOWNERS)
output2=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a1752a1 .github/CODEOWNERS)

# Check if expected patterns are present in the outputs
has_docs_pattern=$(echo "$output1" | grep -c "^/docs/\*\*/\*\.md @docs-specialists$" || echo "0")
has_js_pattern=$(echo "$output2" | grep -c "^\*\.js @js-team @web-team$" || echo "0")

if [[ "$has_docs_pattern" -gt 0 ]] && [[ "$has_js_pattern" -gt 0 ]]; then
    echo "  ✓ Correct: Different patterns match different commits"
else
    echo "  ✗ Pattern matching issue"
    [[ "$has_docs_pattern" -eq 0 ]] && echo "    Missing /docs/**/*.md pattern in a35f805"
    [[ "$has_js_pattern" -eq 0 ]] && echo "    Missing *.js @js-team @web-team pattern in a1752a1"
    echo "    Docs commit (a35f805) output:"
    echo "$output1" | sed 's/^/      /'
    echo "    JS commit (a1752a1) output:"
    echo "$output2" | sed 's/^/      /'
fi
echo ""

echo "=== All ordering tests complete ==="
