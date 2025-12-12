# check.sh

A shell script that analyzes a git commit's changed files against CODEOWNERS rules and reports which code ownership rules match.

## Features

- Supports all gitignore-style pattern syntax used in CODEOWNERS files:
  - `/path/to/file` - Matches from repository root
  - `path/to/file` - Matches anywhere in the repository
  - `path/**` - Matches directory and all its contents
  - `**/file` - Matches file or directory in any location
  - `*.ext` - Matches files with extension anywhere
  - `/adapters/**/auth/*.ts` - Complex patterns with wildcards
- Proper handling of path anchoring (leading `/`)
- Shows each matched only once, in codeowner-file order.

## Usage

```bash
./check.sh <base-commit> <candidate-commit> <codeowners-file>
```

### Arguments

- `base-commit` (required): Commit containing the CODEOWNERS file to use. Mimics GitHub PR behavior where base branch rules apply.
- `candidate-commit` (required): Commit with changed files to analyze. Can use any git ref like `HEAD`, `HEAD~1`, `main`, branch names, etc.
- `codeowners-file` (required): Path to CODEOWNERS file in base-commit. Typically `.github/CODEOWNERS` or `CODEOWNERS` in repository root.

### Examples

Using the [codeowners-tools-corpus](https://github.com/jdunck/codeowners-tools-corpus) repository:

```bash
cd ../codeowners-tools-corpus

# Analyze a commit against its own CODEOWNERS
../codeowners-tools/check.sh a35f805 a35f805 .github/CODEOWNERS

# Single file change - demonstrates last-match-wins
../codeowners-tools/check.sh 6b24f01 6b24f01 .github/CODEOWNERS
# Output: /src/ @src-team

# PR scenario: candidate updates CODEOWNERS, but base rules apply
../codeowners-tools/check.sh a35f805 a1752a1 .github/CODEOWNERS
# Output: *.js @js-team
# (NOT *.js @js-team @web-team - base CODEOWNERS determines reviewers)
```

## Output

The script outputs matched CODEOWNERS rules from the base commit (one per line, in CODEOWNERS file order):

```
/services/flat-file @Finch-API/team-data
```

If no rules match, the script outputs nothing and exits with code 0.

### Why Two Commits?

This mimics GitHub's actual PR review behavior:
- **Base commit** provides the CODEOWNERS file (what rules apply)
- **Candidate commit** provides the changed files (what's being reviewed)

This prevents bypassing code review by modifying CODEOWNERS in the same PR where you're making changes.

## Pattern Matching Details

The script correctly handles these CODEOWNERS pattern types:

1. **Root-anchored paths** (`/path`): Only matches from repository root
2. **Unanchored paths** (`path`): Matches anywhere in the repository
3. **Directory patterns** (`/path/` or `/path`): Matches the directory and all contents
4. **Recursive glob** (`path/**`): Matches directory and all subdirectories
5. **Any-depth match** (`**/filename`): Matches filename at any directory level
6. **Wildcards** (`*.ext`, `file-*`): Standard glob wildcards
7. **Complex patterns** (`/adapters/**/auth/*.ts`): Combines multiple pattern types

## Exit Codes

- `0` - Success (with or without matches)
- `1` - CODEOWNERS file not found in base commit
- `2` - Invalid commit (base or candidate), or candidate is not a descendant of base
- `3` - Not in a git repository
- `4` - Missing required argument: base-commit
- `5` - Missing required argument: candidate-commit
- `6` - Missing required argument: codeowners-file

## Notes

- **Last match wins**: When multiple rules match the same file, only the last matching rule is reported (GitHub CODEOWNERS behavior)
- **File order preserved**: Output rules appear in the same order they appear in the CODEOWNERS file (sorted by line number)
- The script uses `set -euo pipefail` for strict error handling
- Requires bash 4.0+ for associative arrays
- All output goes to stdout (not stderr), including errors

### Example: Last Match Wins

Given this CODEOWNERS file:

```
/services/** @team-general
/services/flat-file @team-specific
```

For a file `services/flat-file/foo.ts`, only the second rule will be output because it appears last and overrides the first rule.
