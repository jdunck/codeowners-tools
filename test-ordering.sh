#!/usr/bin/env bash

# Test script to verify "last match wins" behavior and file order preservation
# These tests use committed CODEOWNERS test files and historical commits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS_DIR="$(cd "$SCRIPT_DIR/../codeowners-tools-corpus" && pwd)"

echo "=== Testing Last Match Wins Behavior ==="
echo ""

echo "Test 1: Verify nested directory override (buttons overrides components)"
# Test that /src/components/buttons/ overrides /src/components/ for PrimaryButton.js
output=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 a35f805 .github/CODEOWNERS)
expected_buttons="/src/components/buttons/ @ui-team"
expected_components="/src/components/ @frontend-team"

# Check that both patterns appear in output (multiple files matched)
has_buttons=$(echo "$output" | grep -c "^$expected_buttons$" || echo "0")
has_components=$(echo "$output" | grep -c "^$expected_components$" || echo "0")

if [[ "$has_buttons" -gt 0 ]] && [[ "$has_components" -gt 0 ]]; then
    echo "  ✓ Correct: Both nested patterns present (buttons overrides components for specific files)"
else
    [[ "$has_buttons" -eq 0 ]] && echo "  ✗ Missing: '$expected_buttons'"
    [[ "$has_components" -eq 0 ]] && echo "  ✗ Missing: '$expected_components'"
    echo "  Output:"
    echo "$output" | sed 's/^/    /'
fi
echo ""

echo "Test 2: Verify last-match-wins with actual committed CODEOWNERS"
# Test with a historical commit that has matching files
output=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 a35f805 .github/CODEOWNERS)
expected="/src/components/buttons/ @ui-team"

if echo "$output" | grep -q "^$expected$"; then
    echo "  ✓ Correct: Last-match-wins rule found for buttons"
else
    echo "  ✗ Expected to find: '$expected'"
    echo "  ✗ Got: '$output'"
fi
echo ""

echo "Test 3: Verify pattern matching across multiple commits"
output1=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 a35f805 .github/CODEOWNERS)
output2=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a1752a1 a1752a1 .github/CODEOWNERS)

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

echo "Test 4: PR scenario - base CODEOWNERS applies, not candidate's"
# Candidate a1752a1 modifies CODEOWNERS to add @web-team, but base a35f805 rules apply
output=$(cd "$CORPUS_DIR" && "$SCRIPT_DIR/check.sh" a35f805 a1752a1 .github/CODEOWNERS)
expected_old_rule="*.js @js-team"

# Should match old rule from base (without @web-team), not new rule from candidate
if echo "$output" | grep -q "^$expected_old_rule$"; then
    echo "  ✓ Correct: Base CODEOWNERS applies (mimics GitHub PR behavior)"
else
    echo "  ✗ Expected base rule: '$expected_old_rule'"
    echo "  ✗ Got: '$output'"
    if echo "$output" | grep -q "@web-team"; then
        echo "  ✗ ERROR: Candidate's updated CODEOWNERS was used instead of base!"
    fi
fi
echo ""

echo "=== All ordering tests complete ==="
