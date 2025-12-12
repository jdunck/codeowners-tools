#!/usr/bin/env bash

# check.sh
# Analyzes a commit's changed files against CODEOWNERS rules from a base commit
# Mimics GitHub PR behavior: CODEOWNERS from base branch, files from candidate commit
# Outputs any effective (last-wins) rule, in the order of the CODEOWNERS file
#
# Usage: ./check.sh <base-commit> <candidate-commit> <codeowners-file>
#
# Arguments:
#   base-commit: Commit containing the CODEOWNERS file to use (required)
#   candidate-commit: Commit with changed files to analyze (required)
#   codeowners-file: Path to CODEOWNERS file in base-commit (required)
#
# Examples (using codeowners-tools-corpus repository):
#   cd ../codeowners-tools-corpus
#
#   # Example 1: Same commit for both (analyze commit against its own CODEOWNERS)
#   $ ../codeowners-tools/check.sh a35f805 a35f805 .github/CODEOWNERS
#   * @global-owner
#   *.js @js-team
#   /src/ @src-team
#   /src/components/ @frontend-team
#   /src/components/buttons/ @ui-team
#   /docs/**/*.md @docs-specialists
#   ... (more patterns)
#   # Shows how nested patterns override: buttons/ beats components/ for PrimaryButton.js
#
#   # Example 2: PR scenario - candidate updates CODEOWNERS, but base rules apply
#   $ ../codeowners-tools/check.sh a35f805 a1752a1 .github/CODEOWNERS
#   *.js @js-team
#   # Candidate a1752a1 added @web-team to *.js, but base a35f805 has only @js-team
#   # Shows GitHub PR behavior: base branch CODEOWNERS determines required reviewers
#
#   # Example 3: Single file rename - outputs just the winning pattern
#   $ ../codeowners-tools/check.sh 6b24f01 6b24f01 .github/CODEOWNERS
#   /src/ @src-team
#   # Demonstrates last-match-wins: /src/ overrides *.js for src/main.js

set -euo pipefail

# Exit codes:
# 0 - Success
# 1 - CODEOWNERS file not found
# 2 - Invalid commit
# 3 - Not in a git repository
# 4 - Missing required argument (base-commit)
# 5 - Missing required argument (candidate-commit)
# 6 - Missing required argument (codeowners-file)

# Check for required arguments
if [[ $# -lt 1 ]]; then
    echo "Error: Missing required argument: base-commit"
    exit 4
fi

if [[ $# -lt 2 ]]; then
    echo "Error: Missing required argument: candidate-commit"
    exit 5
fi

if [[ $# -lt 3 ]]; then
    echo "Error: Missing required argument: codeowners-file"
    exit 6
fi

BASE_COMMIT="$1"
CANDIDATE_COMMIT="$2"
CODEOWNERS_FILE="$3"

# Check if in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 3
fi

# Validate commits exist
if ! git cat-file -e "$CANDIDATE_COMMIT^{commit}" 2>/dev/null; then
    echo "Error: Invalid commit '$CANDIDATE_COMMIT'"
    exit 2
fi

if ! git cat-file -e "$BASE_COMMIT^{commit}" 2>/dev/null; then
    echo "Error: Invalid commit '$BASE_COMMIT'"
    exit 2
fi

# Check if CODEOWNERS file exists in the base commit
if ! git cat-file -e "$BASE_COMMIT:$CODEOWNERS_FILE" 2>/dev/null; then
    echo "Error: CODEOWNERS file not found at $CODEOWNERS_FILE in commit $BASE_COMMIT"
    exit 1
fi

# Get list of changed files in the candidate commit
mapfile -t CHANGED_FILES < <(git diff-tree --no-commit-id --name-only -r "$CANDIDATE_COMMIT" 2>/dev/null)

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    exit 0
fi

# Function to convert gitignore-style pattern to a format we can match
# This handles:
# - /path/to/file - matches from root
# - path/to/file - matches anywhere
# - path/** - matches path and all subdirectories
# - **/file - matches file in any directory
# - *.ext - matches extension anywhere in the path
match_pattern() {
    local pattern="$1"
    local filepath="$2"

    # Remove leading ./ from filepath if present
    filepath="${filepath#./}"

    # Handle negation patterns (patterns starting with !)
    if [[ "$pattern" == !* ]]; then
        return 1
    fi

    # If pattern starts with /, it's anchored to root
    if [[ "$pattern" == /* ]]; then
        pattern="${pattern#/}"

        # Exact match
        if [[ "$filepath" == "$pattern" ]]; then
            return 0
        fi

        # Directory match - pattern is a directory and file is under it
        if [[ "$pattern" == */ ]]; then
            # Remove trailing slash for matching
            local pattern_no_slash="${pattern%/}"
            if [[ "$filepath" == "$pattern_no_slash"/* ]]; then
                return 0
            fi
        elif [[ "$pattern" != *.* ]]; then
            # Pattern without extension, treat as directory
            if [[ "$filepath" == "$pattern"/* ]]; then
                return 0
            fi
        fi

        # Glob pattern with **
        if [[ "$pattern" == *"**"* ]]; then
            # Handle pattern/** (directory and all contents)
            if [[ "$pattern" == *"/**" ]]; then
                local prefix="${pattern%/**}"
                if [[ "$filepath" == "$prefix" ]] || [[ "$filepath" == "$prefix"/* ]]; then
                    return 0
                fi
            else
                # Handle **/pattern or pattern/**/something
                # Convert ** to .* for regex, but preserve the path structure
                local regex_pattern="$pattern"
                # First escape dots
                regex_pattern="${regex_pattern//./\\.}"
                # Convert ** to match any path depth
                regex_pattern="${regex_pattern//\*\*/.+}"
                # Convert single * to match within one path segment
                regex_pattern="${regex_pattern//\*/[^/]*}"

                if [[ "$filepath" =~ ^${regex_pattern}$ ]] || [[ "$filepath" =~ ^${regex_pattern}/ ]]; then
                    return 0
                fi
            fi
        fi

        # Glob pattern with *
        if [[ "$pattern" == *.* ]] && [[ "$pattern" == *\** ]]; then
            # Convert to regex-like matching
            local glob_pattern="${pattern//./\\.}"
            glob_pattern="${glob_pattern//\*/[^/]*}"
            if [[ "$filepath" =~ ^${glob_pattern}$ ]]; then
                return 0
            fi
        fi

        return 1
    fi

    # Pattern doesn't start with / - can match anywhere

    # Handle ** patterns
    if [[ "$pattern" == "**/"* ]]; then
        # **/something matches something in any directory
        local suffix="${pattern#**/}"

        # Check if filepath ends with the pattern or contains it as a path component
        if [[ "$filepath" == "$suffix" ]] || [[ "$filepath" == *"/$suffix" ]]; then
            return 0
        fi

        # Handle globs in the suffix
        if [[ "$suffix" == *"*"* ]]; then
            local glob_pattern="${suffix//./\\.}"
            glob_pattern="${glob_pattern//\*/[^/]*}"
            if [[ "$filepath" =~ (^|/)${glob_pattern}(/.*)?$ ]]; then
                return 0
            fi
        fi

        # Check if pattern with ** matches as subdirectory
        if [[ "$filepath" == *"/$suffix"/* ]] || [[ "$filepath" == "$suffix"/* ]]; then
            return 0
        fi

        return 1
    fi

    # Pattern with /** suffix means directory and all its contents
    if [[ "$pattern" == *"/**" ]]; then
        local prefix="${pattern%/**}"
        if [[ "$filepath" == "$prefix"/* ]] || [[ "$filepath" == *"/$prefix"/* ]]; then
            return 0
        fi
        return 1
    fi

    # Check if pattern matches anywhere in the path
    if [[ "$filepath" == "$pattern" ]] || [[ "$filepath" == *"/$pattern" ]]; then
        return 0
    fi

    # Check if it's a directory pattern and file is under it
    if [[ "$filepath" == "$pattern"/* ]] || [[ "$filepath" == *"/$pattern"/* ]]; then
        return 0
    fi

    # Handle glob patterns
    if [[ "$pattern" == *"*"* ]]; then
        local glob_pattern="${pattern//./\\.}"
        glob_pattern="${glob_pattern//\*/[^/]*}"

        # Try matching at any path level
        if [[ "$filepath" =~ (^|/)${glob_pattern}$ ]] || [[ "$filepath" =~ (^|/)${glob_pattern}/ ]]; then
            return 0
        fi
    fi

    return 1
}

# Parse CODEOWNERS file from the commit and store all rules with line numbers
declare -a all_rules_patterns
declare -a all_rules_owners
declare -a all_rules_line_numbers
line_num=0

while IFS= read -r line; do
    ((line_num++)) || true

    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Extract pattern (first field) and owners (remaining fields)
    read -r pattern owners <<< "$line"

    # Skip if no pattern
    [[ -z "$pattern" ]] && continue

    # Skip if pattern is a comment
    [[ "$pattern" =~ ^# ]] && continue

    # Store rule with line number
    all_rules_patterns+=("$pattern")
    all_rules_owners+=("$owners")
    all_rules_line_numbers+=("$line_num")
done < <(git show "$BASE_COMMIT:$CODEOWNERS_FILE" 2>/dev/null)

# For each changed file, find the last (winning) matching rule
declare -A file_to_rule_line  # Maps file -> line number of winning rule
declare -A rule_line_to_info   # Maps line number -> "pattern|owners"

for file in "${CHANGED_FILES[@]}"; do
    winning_line=-1
    winning_pattern=""
    winning_owners=""

    # Check rules in order (last match wins)
    for ((i=0; i<${#all_rules_patterns[@]}; i++)); do
        pattern="${all_rules_patterns[$i]}"
        owners="${all_rules_owners[$i]}"
        rule_line="${all_rules_line_numbers[$i]}"

        if match_pattern "$pattern" "$file"; then
            # This rule matches - it becomes the winner (overriding any previous match)
            winning_line="$rule_line"
            winning_pattern="$pattern"
            winning_owners="$owners"
        fi
    done

    # Store the winning rule if one was found
    if [[ $winning_line -ne -1 ]]; then
        file_to_rule_line["$file"]="$winning_line"
        rule_line_to_info["$winning_line"]="$winning_pattern|$winning_owners"
    fi
done

# Output matched rules in original file order (sorted by line number)
# Check if any rules matched by checking if array has any keys
if [[ -n "${!rule_line_to_info[*]}" ]]; then
    for line_num in $(printf '%s\n' "${!rule_line_to_info[@]}" | sort -n); do
        info="${rule_line_to_info[$line_num]}"
        IFS='|' read -r pattern owners <<< "$info"
        echo "$pattern $owners"
    done
fi

exit 0
