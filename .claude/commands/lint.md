Find and validate all shell scripts and Dockerfiles in this project for quality issues.

## Shell Scripts
1. Find all `.sh` files under `bin/`: `find bin -name "*.sh" -type f`
2. Run `bash -n` syntax check on each file
3. Run `shell-check -x -S warning` on each file
4. Report results grouped by file, with severity

## Dockerfiles
1. Find all Dockerfiles: `find docker/images -name "Dockerfile" -type f`
2. Run `hadolint` on each (if available)
3. Report results grouped by file

## Output
- Summary table: file → pass/fail → issue count
- List all warnings and errors with file:line references
- If everything passes, report "All clean"

If arguments are provided, only lint files matching: $ARGUMENTS
