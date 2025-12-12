#!/usr/bin/env bash

# check.sh
# Analyzes a git commit's changed files against CODEOWNERS rules
# Usage: ./check.sh <commit-sha> <codeowners-file>
#
# Arguments:
#   commit-sha: Git commit SHA to analyze (required)
#   codeowners-file: Path to CODEOWNERS file (required)
#
# Examples:
#   ./check.sh HEAD .github/CODEOWNERS
#   ./check.sh abc123 .github/CODEOWNERS
#   ./check.sh HEAD~1 .github/CODEOWNERS
#   ./check.sh main CODEOWNERS

set -euo pipefail

# Exit codes:
# 0 - Success
# 1 - CODEOWNERS file not found
# 2 - Invalid commit
# 3 - Not in a git repository
# 4 - Missing required argument (commit-sha)
# 5 - Missing required argument (codeowners-file)

# Check for required arguments
if [[ $# -lt 1 ]]; then
    echo "Error: Missing required argument: commit-sha"
    exit 4
fi

if [[ $# -lt 2 ]]; then
    echo "Error: Missing required argument: codeowners-file"
    exit 5
fi

COMMIT="$1"
CODEOWNERS_FILE="$2"

# Check if in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 3
fi

# Validate commit exists
if ! git cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
    echo "Error: Invalid commit '$COMMIT'"
    exit 2
fi

# Check if CODEOWNERS file exists in the specified commit
if ! git cat-file -e "$COMMIT:$CODEOWNERS_FILE" 2>/dev/null; then
    echo "Error: CODEOWNERS file not found at $CODEOWNERS_FILE in commit $COMMIT"
    exit 1
fi

# Get list of changed files in the commit
mapfile -t CHANGED_FILES < <(git diff-tree --no-commit-id --name-only -r "$COMMIT" 2>/dev/null)

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
        if [[ "$pattern" == */ ]] || [[ "$pattern" != *.* ]]; then
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
done < <(git show "$COMMIT:$CODEOWNERS_FILE" 2>/dev/null)

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
