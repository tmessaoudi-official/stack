---
name: lint
description: Use when shell scripts, Dockerfiles, or YAML files need quality validation. Use after editing any .sh, Dockerfile*, or .yaml/.yml file.
user-invocable: true
---

Find and validate all shell scripts and Dockerfiles in this project for quality issues.

## Shell Scripts
1. Find all `.sh` files under `bin/`: `find bin -name "*.sh" -type f`
2. Run `bash -n` syntax check on each file
3. Run `shellcheck -x -S warning` on each file
4. Report results grouped by file, with severity

## Dockerfiles
1. Find all Dockerfiles: `find docker/images -name "Dockerfile" -type f`
2. Run `hadolint` on each (if available)
3. Report results grouped by file

## YAML Files
1. Find all YAML files: `find . -name "*.yaml" -o -name "*.yml" | grep -v "^\./tools/" | grep -v "^\./var/"`
2. Run `yamllint -d relaxed` on each file
3. Report results grouped by file, with line references

## Output
- Summary table: file → pass/fail → issue count
- List all warnings and errors with file:line references
- If everything passes, report "All clean"

If arguments are provided, only lint files matching: $ARGUMENTS
