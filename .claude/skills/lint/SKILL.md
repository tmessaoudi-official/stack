---
name: lint
spotlight: true
description: Use when shell scripts, Dockerfiles, or YAML files need quality validation. Use after editing any .sh, Dockerfile*, or .yaml/.yml file.
user-invocable: true
---

Find and validate all shell scripts and Dockerfiles in this project for quality issues.

## Shell Scripts
1. Find all `.sh` files under `bin/`, `docker/config/dist/bin/` (container startup scripts), `.claude/hooks/`, and `templates/shell/`: `find bin docker/config/dist/bin .claude/hooks templates/shell -name "*.sh" -type f`
2. Run `bash -n` syntax check on each file
3. Run `shellcheck -x -S warning` on each file
4. Report results grouped by file, with severity

## Dockerfiles
1. Find all Dockerfiles: `find docker/images -name "Dockerfile" -type f`
2. Run `hadolint` on each
3. Report results grouped by file

## YAML Files
1. Find all YAML files (excluding third-party and stateful data): `find . \( -name "*.yaml" -o -name "*.yml" \) | grep -v "^\./tools/" | grep -v "^\./var/" | grep -v "^\./projects/" | grep -v "^\./docker/data/" | grep -v "^\./docker/storage/" | grep -v "node_modules"`
2. Run `yamllint -d relaxed` on each file
3. Report results grouped by file, with line references

## Output
- Summary table: file → pass/fail → issue count
- List all warnings and errors with file:line references
- If everything passes, report "All clean"

**A missing tool is never a pass.** Check each linter with `command -v` first, and if one is
absent, say so explicitly — *"hadolint NOT INSTALLED — Dockerfiles were not linted"* — and never
fold that into "All clean". "All clean" must mean every linter ran, not that every linter that
happened to exist ran. `yamllint` in particular resolves to `/stack/tools/pyenv/shims/yamllint`,
inside the tools volume that `make soft-restart` wipes, so it can genuinely disappear between
runs. Report the tool inventory alongside the results:

    shellcheck ✓  hadolint ✓  yamllint ✓   ← all four ran
    shellcheck ✓  hadolint ✗  yamllint ✓   ← Dockerfiles UNCHECKED, say so in the summary

If arguments are provided, only lint files matching: $ARGUMENTS
