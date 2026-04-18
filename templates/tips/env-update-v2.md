# env-update-v2 v0.2.0 — Phase 2: dockerhub fetcher + channel selection

`bin/env-update-v2.sh` is the greenfield replacement for `bin/env-update.sh`.
Phase 2 adds the first fetcher (dockerhub), channel selection, tag-flag pipeline,
a flat-file cache, and useful default output. No writes to `.env` yet.

---

## Quick Start

```bash
bin/env-update-v2.sh --version                         # print 0.2.0 and exit
bin/env-update-v2.sh                                   # parser summary (no network)
bin/env-update-v2.sh --check                           # fetch all, stream report
bin/env-update-v2.sh --check --filter=POSTGRES         # only POSTGRES* vars
bin/env-update-v2.sh --check --no-cache                # bypass cache
bin/env-update-v2.sh --dump                            # parse /stack/.env, print all records
bin/env-update-v2.sh --dump --format=json | jq .       # JSON output
bin/env-update-v2.sh --dump --env-file=path/to/.env    # custom source file
```

---

## CLI Options

| Option                | Description                                                    |
| --------------------- | -------------------------------------------------------------- |
| `--version`           | Print `0.2.0` and exit 0                                      |
| `--help`              | Show usage text                                                |
| `--check`             | Fetch latest versions and stream `[AUTO\|HOLD\|SKIP\|ERROR]` report |
| `--no-cache`          | Bypass the fetch cache                                         |
| `--cache-ttl=<N>`     | Cache TTL in seconds (default: 3600)                          |
| `--dump`              | Emit parsed records (text or JSON)                             |
| `--format=text\|json` | Dump format (default: `text`)                                  |
| `--filter=<regex>`    | Only parse records whose `env_var` matches bash regex          |
| `--env-file=<path>`   | Source file to parse (default: `/stack/.env`)                 |
| `--dry-run`           | No-op placeholder; gates cache writes. Reserved for future `.env` write phases. |

---

## Default output (no flags)

```
env-update-v2 v0.2.0 — parsed /stack/.env

  73 annotated variables across 8 fetcher types:
    dockerhub     21   github        34   npm            8
    pecl           4   pecl-git       2   sdkman         2
    pypi           1   url            1

  Hint: run --check to fetch latest versions (network required)
        run --dump  to emit structured records
        run --help  for all options
```

## --check output format

```
[AUTO  ]  GLOBAL_STACK_POSTGRES18_VERSION               18.3-alpine3.23 → 18.4-alpine3.23
[HOLD  ]  GLOBAL_STACK_MYSQL9_VERSION                   9.5.0 → 9.6.0 (major pin: 9)
[SKIP  ]  GLOBAL_STACK_GITHUB_CLI_VERSION               fetcher 'github' not yet implemented
──────────────────────────────────────────────────────────────────────────────
  Summary: 1 AUTO, 1 HOLD, 0 MANUAL, 1 SKIP, 0 ERROR  (3 checked)
```

Decision tags:
- `[AUTO  ]` — safe to apply; stays within major pin if set
- `[HOLD  ]` — major version jump detected; review required
- `[MANUAL]` — `(override)` or `(manual)` flag in annotation
- `[SKIP  ]` — up-to-date, or fetcher not yet implemented, or no matching tags
- `[ERROR ]` — fetch failed (network, HTTP error, parse error)

---

## Phase 2 fetcher scope

**Implemented**: `dockerhub` — full tag-flag pipeline, channel selection, major-pin, flat-file cache.

**Not yet implemented** (show `[SKIP]` with note): `github`, `npm`, `pecl`, `pecl-git`,
`pypi`, `quay`, `rubygems`, `sdkman`, `sdkmanager`, `url`, `codeberg`. These are Phase 3+.

---

## Cache

Flat-file cache at `_GS_EU2_CACHE_DIR` (default: `/tmp/global-stack-env-update-v2-cache`).
One `.cache` file per key. TTL: `_GS_EU2_CACHE_TTL` seconds (default 3600).

```bash
--no-cache              # bypass cache this run
--cache-ttl=0           # treat all cache entries as expired
```

For testing: `export _GS_EU2_HTTP_FIXTURE_DIR=/path/to/fixtures` — all HTTP GETs are
served from files in that directory (query string stripped, URL sanitized to filename).

---

## Annotation Format

```bash
# @todo env-update [FLAGS] TYPE:IDENTIFIER[:MAJOR] [VERSION] [(hint)]
# @todo could be a repo url https://... SHA
VAR_NAME=current_value
```

### Inline flags (balanced `(...)` tokens before TYPE:IDENTIFIER)

| Flag | Stored as | Description |
| ---- | --------- | ----------- |
| `(override)` | `override: true` | Always MANUAL, never AUTO |
| `(manual)` | `manual: true` | Require human review |
| `(propagate)` | `propagate: true` | Update all occurrences |
| `(channel:VALUE)` | `channel` | Release channel (e.g. `unstable`, `rc`) |
| `(skip:REASON)` | `skip_reason` | Skip with reason string |
| `(version-prefix:STR)` | `version_prefix` | Prefix to prepend to version |
| `(tag-filter:REGEX)` | `tag_filter` | Keep only tags matching regex |
| `(tag-exclude:REGEX)` | `tag_exclude` | Exclude tags matching regex |
| `(tag-strip-prefix:STR)` | `tag_strip_prefix` | Strip prefix from tag before comparing |
| `(tag-strip-suffix:STR)` | `tag_strip_suffix` | Strip suffix from tag before comparing |
| `(tag-extract:REGEX)` | `tag_extract` | Extract version from tag via capture group |
| `(tag-replace:FROM:TO)` | `tag_replace_from` / `tag_replace_to` | Replace substring in tag |
| `(tag-suffix:STR)` | `tag_suffix` | Match only tags ending with suffix |
| `(fetch-extract:REGEX)` | `fetch_extract` | Extract version from fetched content |
| `(fetch-json:JQ_PATH)` | `fetch_json` | Extract via jq path from JSON response |
| `(url-probe:PATTERN)` | `url_probe` | URL probe pattern (for `url` type) |
| `(url-probe-depth:N)` | `url_probe_depth` | Max redirect depth for URL probe |

### Structured inline tokens (anywhere after TYPE:IDENTIFIER)

| Token | Stored as | Example |
| ----- | --------- | ------- |
| `(pecl-ref:NAME)` | `pecl_ref` | `(pecl-ref:event)` |
| `(depends-on:VAR:constraint)` | `depends_on` | `(depends-on:GLOBAL_STACK_SONARQUBE_VERSION:major)` |
| `urls: URL1 URL2 ...` | `urls` | `urls: https://example.com/` |

### Multi-line git fallback (line before VAR=)

```bash
# @todo could be a repo url https://github.com/owner/repo.git SHA
```

Stored as `git_fallback_url` + `git_fallback_sha`.

---

## Record Fields (31 total — 28 parser fields + 3 fetch fields)

| Field | Source |
| ----- | ------ |
| `env_var` | Variable name from `VAR=VALUE` line |
| `current_version` | Version from annotation, or `VAR=VALUE` if omitted |
| `type` | Fetcher type (e.g. `dockerhub`, `github`, `npm`) |
| `identifier` | Registry path / repo slug |
| `major_hint` | Numeric suffix from `TYPE:ID:MAJOR` |
| `override` / `manual` / `propagate` | Boolean markers (`true` or empty) |
| `channel` / `skip_reason` / `version_prefix` | String flags |
| `tag_filter` … `tag_suffix` | Tag manipulation flags |
| `fetch_extract` / `fetch_json` | Fetch result extraction |
| `url_probe` / `url_probe_depth` | URL probe settings |
| `pecl_ref` / `depends_on` / `urls` | Structured tokens |
| `git_fallback_url` / `git_fallback_sha` | Multi-line fallback |
| `hint` | Trailing `(free text)` on annotation line |
| `line_number` / `raw_annotation` | Metadata |
| `proposed_version` | Set by fetcher after `--check` |
| `decision` | `AUTO` / `HOLD` / `MANUAL` / `SKIP` / `ERROR` — set by fetcher + classifier |
| `error_message` | Human-readable error when `decision=ERROR` or `decision=SKIP` |

---

## Error Policy

Parser exits non-zero immediately with a message on:

```
env-update-v2: <path>:<line>: <specific reason>
```

Triggered by: unknown flag name, empty required value, malformed `depends-on`
(no `VAR:constraint` format), missing `TYPE:IDENTIFIER`, or duplicate
`@todo env-update` before the same variable.

Fetch errors (network, parse) set `decision=ERROR` and continue — they do not abort.

---

## Architecture

```
bin/env-update-v2.sh                → entry point (sources main.sh)
bin/lib/env-update-v2/
├── config/
│   ├── defaults.sh                 → _GS_EU2_CFG + VERSION + env-var overrides
│   └── prerelease_markers.sh       → pre-release detection regex fragments
├── core/
│   ├── args.sh                     → CLI flag parsing
│   ├── records.sh                  → record data model + accessor API
│   ├── parse.sh                    → annotation parser (state machine)
│   ├── semver.sh                   → semver compare + pre-release detection
│   ├── channel.sh                  → stable/rc/beta/unstable tag selection
│   ├── tag_flags.sh                → apply tag-filter/exclude/strip/extract/replace
│   ├── cache.sh                    → flat-file TTL cache (read/write/invalidate)
│   └── decide.sh                   → classify fetch result → AUTO/HOLD/MANUAL/SKIP
├── fetchers/
│   └── dockerhub.sh                → Docker Hub fetcher (record-index contract)
├── http/
│   └── curl.sh                     → HTTP GET wrapper + fixture injection seam
├── reporting/
│   ├── help.sh                     → usage text
│   ├── dump.sh                     → text + JSON record printer
│   ├── summary.sh                  → default no-flags parser summary
│   └── stream.sh                   → streaming [TAG] per-record output + summary
└── main.sh                         → orchestration
bin/tests/env-update-v2.test.sh     → 74 tests (17 sections)
bin/tests/fixtures/env-update-v2/   → synthetic .env fixtures + HTTP fixtures
  http/                             → fixture JSON files for fetcher tests
```

### Record accessor API

```bash
_gs_eu2_record_new              # allocate next index → stored in _GS_EU2_LAST_IDX
_gs_eu2_record_set IDX FLD VAL  # set one field (printf -v)
_gs_eu2_record_get IDX FLD      # read one field (${!varname:-})
_gs_eu2_record_count            # number of records allocated
_gs_eu2_record_fields           # canonical field list (single source of truth)
```

### Adding a new fetcher

1. Create `bin/lib/env-update-v2/fetchers/<type>.sh`
2. Implement `_gs_eu2_fetch_<type>() { local _idx="${1}"; ... }` — reads from record, writes `proposed_version` + `decision` + `error_message` back
3. Add a `case` arm in `_gs_eu2_run_check()` in `main.sh`
4. Write tests (mock HTTP via `_GS_EU2_HTTP_FIXTURE_DIR`)

### Adding a new record field

1. Add the name to `_gs_eu2_record_fields()` in `records.sh`
2. Handle in parser or fetcher as appropriate
3. Write a test

No call-site refactor needed — the record model is fully data-driven.
