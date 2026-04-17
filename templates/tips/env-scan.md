# env-scan — Environment File Sync Tool

`bin/env-scan.sh` synchronises `.env` (source) into `.env.local` (destination),
scans all Docker sources for `GLOBAL_STACK_*` variable references, detects missing
or conflicting variables, and optionally syncs differing values.

---

## Quick Start

```bash
bin/env-scan.sh                              # default: sync .env → .env.local
bin/env-scan.sh --sync-values=true           # also overwrite differing values in .env.local
bin/env-scan.sh --check-missing=false        # skip missing-variable checks
bin/env-scan.sh --quiet=true                 # suppress all informational output
bin/env-scan.sh --profile=true               # show per-phase timing and memory
bin/env-scan.sh --debug=true                 # verbose diagnostic output
```

---

## CLI Options

All options use `--key=value` form. Boolean options accept `true` or `false`.

### Core behaviour

| Option | Default | Description |
|---|---|---|
| `--source-files=VALUE` | `.env` | Space-separated list of source env files to read from |
| `--destination-files=VALUE` | `.env.local` | Space-separated list of destination files to merge into |
| `--dir=VALUE` | inferred from script path | Working directory; base for all relative paths |
| `--sync-values=true\|false` | `false` | When `true`, overwrite destination values that differ from source |

### Output formatting

| Option | Default | Description |
|---|---|---|
| `--strip-comments=true\|false` | `true` | Remove comment lines from merged destination file |
| `--remove-empty-lines=true\|false` | `true` | Remove empty lines from merged destination file |
| `--remove-trailing-spaces=true\|false` | `true` | Strip trailing whitespace from each line |

### Scanning

| Option | Default | Description |
|---|---|---|
| `--scan-sources=true\|false` | `true` | Scan Docker source files for variable references |
| `--scan-path=PATH` | `<dir>/docker` | Directory (or single file) to scan for variable usage |
| `--scan-var-prefix=PATTERN` | `(GLOBAL_STACK_)` | Regex prefix for variables to extract |
| `--scan-output-file=PATH` | `<dir>/.env.all.local` | Where to write all extracted variable definitions |
| `--scan-delete-output=true\|false` | `true` | Delete the scan output file after processing |
| `--scan-exclude-pattern=REGEX` | predefined | Variables to exclude from extraction |
| `--scan-ignore-pattern=LINES` | predefined paths | Newline-separated list of path regexes to skip during scan |
| `--include-docker-args=true\|false` | `true` | Include `ARG VAR=value` lines from Dockerfiles when scanning |
| `--debug-show-extracted-files=true\|false` | `false` | Print each file path as it is scanned (requires `--debug=true`) |

### Reporting

| Option | Default | Description |
|---|---|---|
| `--show-added-entries=true\|false` | `true` | Report variables added to destination that were not there before |
| `--show-different-entries=true\|false` | `true` | Report variables whose values differ between source and destination |
| `--check-missing=true\|false` | `true` | Report variables present in scan but absent from source or destination |
| `--quiet=true\|false` | `false` | Suppress all informational output; errors still print to stderr |

### Pattern overrides

| Option | Default | Description |
|---|---|---|
| `--exclude-different-pattern=REGEX` | predefined | Vars to skip in difference reporting (e.g. credentials, ports) |
| `--exclude-source-check-pattern=REGEX` | predefined | Vars to exclude from reverse missing check (dest → scan) |
| `--exclude-check-missing=REGEX` | predefined | Vars to exclude from the forward missing check (scan → dest) |
| `--exclude-multiple-values-pattern=REGEX` | predefined | Vars to exclude from conflicting-defaults detection |
| `--exclude-local-pattern=REGEX` | derived from prefix | Vars to exclude when checking for entries missing from dest |
| `--exclude-implicit-empty=true\|false` | `true` | Ignore `KEY=` (implicit empty) when detecting conflicting defaults |
| `--exclude-explicit-empty=true\|false` | `true` | Ignore `KEY=${KEY:-}` (explicit empty passthrough) when detecting conflicts |

### Temp file control

| Option | Default | Description |
|---|---|---|
| `--destination-file-tmp-suffix=VALUE` | `.tmp` | Suffix appended to destination filename for temp copy |
| `--destination-file-merged-suffix=VALUE` | `.merged` | Suffix appended for the merged intermediate file |
| `--source-merged-file=PATH` | `<dir>/.env.src.all.merged` | Path for the merged source index file |
| `--cleanup-tmp=true\|false` | `true` | Delete all temp files after processing |

### Diagnostics

| Option | Default | Description |
|---|---|---|
| `--debug=true\|false` | `false` | Enable verbose diagnostic messages |
| `--profile=true\|false` | `false` | Print per-phase execution time and memory usage after run |
| `--help` | — | Show usage and exit |

---

## What It Does — Phase by Phase

| Phase | What happens |
|---|---|
| 1. Parse args | CLI arguments applied; defaults filled in |
| 2. Build source index | All source files are merged into `.env.src.all.merged` (comments and empty lines stripped) |
| 3. Scan docker sources | Every file under `--scan-path` is parsed in parallel for `GLOBAL_STACK_*` references. Results written to `.env.all.local` |
| 4. Detect conflicting values | Flags any variable defined with more than one distinct non-empty value across source + scan output |
| 5. Sync env files | For each source→destination pair: merge source into destination (destination wins on key conflicts), show added/different entries, check missing, optionally sync differing values |
| 6. Cleanup | Remove temp files (unless `--cleanup-tmp=false`) |

---

## Variable Extraction

The scanner recognises these forms of `GLOBAL_STACK_*` usage in source files:

| Form | Example |
|---|---|
| Dockerfile `ARG` | `ARG GLOBAL_STACK_FOO=default` |
| Dockerfile `ENV` | `ENV GLOBAL_STACK_FOO=bar` |
| Plain assignment | `GLOBAL_STACK_FOO=bar` |
| Shell export | `export GLOBAL_STACK_FOO=bar` |
| Multi-line ENV continuation | `  GLOBAL_STACK_VERSION="${...}" \` |
| docker-compose list entry | `- GLOBAL_STACK_FOO=bar` |
| YAML map | `GLOBAL_STACK_FOO: bar` |
| Shell reference | `${GLOBAL_STACK_FOO:-default}` |
| Caddyfile | `{env.GLOBAL_STACK_FOO}` |
| PHP `getenv()` | `getenv('GLOBAL_STACK_FOO')` |
| PHP `$_ENV` | `$_ENV['GLOBAL_STACK_FOO']` |
| JS/TS | `process.env.GLOBAL_STACK_FOO` |
| Python | `os.environ.get('GLOBAL_STACK_FOO')` / `os.environ['GLOBAL_STACK_FOO']` |

---

## Merge Strategy

Destination file wins on key conflicts: if `.env.local` already has `FOO=myvalue`
and `.env` has `FOO=default`, the destination value is kept.

With `--sync-values=true`, destination values that differ from source are overwritten
to match source — useful for resetting `.env.local` to track `.env` defaults.

---

## Missing Variable Checks

Three checks run after each merge (unless `--check-missing=false`):

1. **Forward**: variables in scan output that are absent from source — suggests new
   `GLOBAL_STACK_*` usages in Docker files that aren't declared in `.env` yet.
2. **Forward**: variables in scan output that are absent from destination — suggests
   entries in `.env` that haven't been propagated to `.env.local`.
3. **Reverse**: variables in destination that don't appear anywhere in scan output —
   possibly stale entries in `.env.local` with no corresponding usage.

---

## Common Invocations

```bash
# Standard first-time setup: sync .env → .env.local, detect gaps
bin/env-scan.sh

# Reset .env.local to match .env exactly (overwrite all differing values)
bin/env-scan.sh --sync-values=true

# Sync two custom files without scanning Docker sources
bin/env-scan.sh \
  --source-files=".env .env.staging" \
  --destination-files=".env.local" \
  --scan-sources=false

# Only check differences, don't modify anything (keep tmp files for inspection)
bin/env-scan.sh --sync-values=false --cleanup-tmp=false

# Scan a specific subdirectory only
bin/env-scan.sh --scan-path=/stack/docker/images/03node24

# Profile a slow run
bin/env-scan.sh --profile=true

# Suppress all output except errors
bin/env-scan.sh --quiet=true
```

---

## Output Files

| File | Purpose |
|---|---|
| `.env.local` | Primary output: destination file updated with new entries from `.env` |
| `.env.all.local` | Temporary: all extracted `GLOBAL_STACK_*` definitions from Docker sources (deleted by default) |
| `.env.src.all.merged` | Temporary: merged source file used for conflict detection (deleted by default) |

Set `--scan-delete-output=false --cleanup-tmp=false` to keep intermediate files for
debugging.

---

## Profile Output

With `--profile=true`, a table like this is printed after the run:

```
  ┌─ Profile ─────────────────────────────────────────────────────┐
  │  Phase                             Duration     Memory         │
  ├───────────────────────────────────────────────────────────────┤
  │  Parse args                           3 ms    +0.0 MB         │
  │  Build source index                  12 ms    +0.1 MB         │
  │  Scan docker sources                340 ms    +1.2 MB         │
  │  Detect conflicting values           18 ms    +0.0 MB         │
  │  Sync env files                      45 ms    +0.2 MB         │
  │  Cleanup                              2 ms    −0.1 MB         │
  ├───────────────────────────────────────────────────────────────┤
  │  Total                              420 ms   Peak: 24.3 MB    │
  └───────────────────────────────────────────────────────────────┘
```

Duration is colour-coded: green < 200 ms, yellow 200 ms–1 s, red > 1 s.
Memory delta is per-phase RSS change; Peak shows the highest RSS seen.
