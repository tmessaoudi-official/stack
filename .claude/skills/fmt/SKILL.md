---
name: fmt
description: Use when shell scripts or YAML files need formatting, or to preview formatting changes before committing. Supports --check, --sh, --yaml flags.
user-invocable: true
---

Format shell scripts and YAML files using shfmt and yamlfmt.

## Default behavior (no arguments):
1. **Shell scripts**: find all `.sh` files under `bin/` and format with `shfmt -w -i 2 -ci -bn`
2. **YAML files**: find all `.yaml`/`.yml` files under `docker/images/` and format with `yamlfmt`
3. Report which files were modified

## With arguments ($ARGUMENTS):
- If a specific file path is given, format only that file
- If `--check` is given, run in check-only mode (no modifications):
  - `shfmt -d -i 2 -ci -bn` for shell scripts (shows diff)
  - `yamlfmt -dry` for YAML files
- If `--sh` is given, only format shell scripts
- If `--yaml` is given, only format YAML files

## Output:
- List of files formatted (or "already formatted" if no changes needed)
- For `--check` mode: list files needing formatting with diff preview
- Summary: X shell files formatted, Y YAML files formatted

## Formatting standards:
- **shfmt**: indent=2, case indent (`-ci`), binary ops at start of next line (`-bn`)
- **yamlfmt**: default settings
