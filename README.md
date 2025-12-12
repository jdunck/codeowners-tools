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
- Deduplicates matched rules in the summary
- Shows which files matched which patterns

## Usage

```bash
./check.sh <commit-sha> <codeowners-file>
```

### Arguments

- `commit-sha` (required): Git commit SHA to analyze. Can use any git ref like `HEAD`, `HEAD~1`, `main`, branch names, etc.
- `codeowners-file` (required): Path to CODEOWNERS file. Typically `.github/CODEOWNERS` or `CODEOWNERS` in repository root.

### Examples

```bash
# Analyze the most recent commit
./check.sh HEAD .github/CODEOWNERS

# Analyze a specific commit
./check.sh abc123 .github/CODEOWNERS

# Analyze the previous commit
./check.sh HEAD~1 .github/CODEOWNERS

# Use a CODEOWNERS file in repository root
./check.sh HEAD CODEOWNERS

# Analyze a specific commit with custom CODEOWNERS file
./check.sh abc123 path/to/CODEOWNERS
```

## Output

The script outputs only the matched CODEOWNERS rules (one per line, sorted and deduplicated):

```
/services/flat-file @Finch-API/team-data
```

If no rules match, the script outputs nothing and exits with code 0.

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
- `1` - CODEOWNERS file not found
- `2` - Invalid commit
- `3` - Not in a git repository
- `4` - Missing required argument: commit-sha
- `5` - Missing required argument: codeowners-file

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
