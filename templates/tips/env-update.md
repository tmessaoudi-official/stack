# env-update v2.0.0 — Complete Reference

`bin/env-update.sh` is the automated version checker for Global Stack. It parses
`@todo env-update` annotations in `.env`, fetches the latest versions from 12 upstream
source types, classifies each update decision, and can apply AUTO decisions back to `.env`.

---

## Table of Contents

1. [Quick Reference — Fetcher Summary Table](#1-quick-reference--fetcher-summary-table)
2. [Annotation Syntax — Complete Reference](#2-annotation-syntax--complete-reference)
3. [Annotation Flag Reference](#3-annotation-flag-reference)
4. [CLI Flag Reference](#4-cli-flag-reference)
5. [Output Format — Every Detail](#5-output-format--every-detail)
6. [Decision Engine](#6-decision-engine)
7. [Fetcher Deep-Dives](#7-fetcher-deep-dives)
   - [dockerhub](#71-dockerhub)
   - [github](#72-github)
   - [npm](#73-npm)
   - [pecl-git](#74-pecl-git)
   - [pypi](#75-pypi)
   - [quay](#76-quay)
   - [rubygems](#77-rubygems)
   - [sdkman](#78-sdkman)
   - [sdkmanager](#79-sdkmanager)
   - [url](#710-url)
   - [codeberg](#711-codeberg)
   - [pecl (internal helper)](#712-pecl-internal-helper)
8. [Caching System](#8-caching-system)
9. [The Apply Cycle](#9-the-apply-cycle)
10. [PECL-Git Fetcher — Extended](#10-pecl-git-fetcher--extended)
11. [Multi-Variable Patterns](#11-multi-variable-patterns)
12. [Error Reference](#12-error-reference)
13. [Testing and Development](#13-testing-and-development)

---

## 1. Quick Reference — Fetcher Summary Table

| Type | Identifier Format | Major Hint | Tag Flags | Auth Required | Notes |
|------|-------------------|:---:|:---:|---|---|
| `dockerhub` | `_/image` or `org/image` | Yes | Yes | No | `_/` = Docker Library; paginates all tags |
| `github` | `owner/repo` | Yes | Yes | GITHUB_TOKEN (optional but recommended) | 3-strategy: releases → tags → git ls-remote |
| `npm` | `package-name` or `@scope/name` | Yes | Yes | No | CLI fast path via `npm view` when available |
| `pecl-git` | `owner/repo` | Yes | Partial | GITHUB_TOKEN (optional) | Dual-source: GitHub tags + PECL promotion check |
| `pypi` | `package-name` | Yes | Yes | No | CLI fast path via `pip index versions` when available |
| `quay` | `org/image` | Yes | Yes | No | 50-tag limit per call; no pagination |
| `rubygems` | `gem-name` | Yes | Yes | No | CLI fast path via `gem search` when available; two-endpoint strategy |
| `sdkman` | `candidate-name` | Yes | No | No | Java: distribution-aware selection; HTTP-first (no CLI) |
| `sdkmanager` | `component-name` | No | No | No | Always MANUAL; requires `sdkmanager` binary |
| `url` | URL string | No | Yes (some tiers) | Varies | 5-tier strategy; most flexible fetcher |
| `codeberg` | `owner/repo` | Yes | Yes | No | Gitea API; releases → tags fallback |
| `pecl` | `extension-name` | No | No | No | PECL REST XML API; use `(git:owner/repo)` flag to also fetch SHA from GitHub tag |

---

## 2. Annotation Syntax — Complete Reference

Every version variable in `.env` that should be checked has a `@todo env-update`
annotation on the line immediately before the assignment (with any number of blank lines
and comment lines tolerated in between — the C2 rule).

### Full annotation grammar

```
# @todo env-update [FLAGS...] TYPE:IDENTIFIER[:MAJOR_HINT] [CURRENT_VERSION] [(hint text)] [urls: URL...]
[# optional comment lines — ignored]
[blank lines — ignored]
VAR_NAME=current_value
```

### Token-by-token breakdown

**`TYPE:IDENTIFIER[:MAJOR_HINT]`** — required; must appear exactly once.

- `TYPE` — lowercase fetcher name: `dockerhub`, `github`, `npm`, `pecl-git`, `pypi`,
  `quay`, `rubygems`, `sdkman`, `sdkmanager`, `url`, `codeberg`.
- `IDENTIFIER` — the resource to fetch. Format varies by fetcher type (see Section 7).
- `:MAJOR_HINT` — optional numeric suffix. Accepts dotted values like `8.2` (the D1 fix).
  The parser checks that the last colon-separated segment matches `^[0-9]+(\.[0-9]+)*$`.
  When present, the fetcher restricts its output and the decision engine enforces the pin.

**`FLAGS`** — zero or more parenthesized tokens `(flag)` or `(flag:value)`. Flags are
**position-agnostic**: they can appear before the TYPE:IDENTIFIER, after it, or after the
version string. The parser uses a two-pass hoist: Pass 1 extracts all recognized flag
parens from anywhere in the annotation; Pass 2 parses the TYPE:IDENTIFIER from what
remains. Non-recognized parenthetical groups are kept as-is (treated as the hint text).

**`CURRENT_VERSION`** — optional. When omitted, the parser reads the version from the
`VAR_NAME=current_value` assignment line. When present in the annotation, that value takes
precedence. The current version is the baseline for semver comparison and for what `--apply`
will replace.

**`(hint text)`** — optional trailing parenthetical with free text. Detected as the last
`(non-flag-text)` group remaining after flags are hoisted. Stored in the `hint` record
field. Never interpreted — purely informational for humans.

**`urls: URL1 URL2 ...`** — optional. A space-separated list of reference URLs following
the literal keyword `urls:`. These are stored in the `urls` record field and used by the
`url` fetcher's Tier 3 (GitHub redirect). They are otherwise informational.

**`sha: HEXSTRING`** — optional. An annotated commit SHA stored in `annotation_sha`. Used
when `(use-sha)` is active — `--apply` replaces both the version token in the annotation
and the SHA. Not common in standard annotations.

### Git fallback line

An optional extra comment line immediately before the annotation (or the variable) can
capture a legacy git reference:

```bash
# @todo could be a repo url https://github.com/owner/repo.git abc123def456
# @todo env-update ...
VAR=value
```

The regex `^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url` triggers this. Stored as `git_fallback_url` and `git_fallback_sha`. Not used by any active fetcher — purely informational metadata.

### Whitespace and blank-line rules (C2)

Once the parser enters `AWAITING_VARIABLE` state (after seeing a `@todo env-update` line),
it will skip any number of:
- Blank lines
- Comment-only lines (`#...`)

The variable assignment (`VAR=value`) must eventually follow. If a second `@todo env-update`
appears before an assignment, the parser exits with a "duplicate @todo" error. If a
non-blank, non-comment, non-assignment line is encountered, the parser logs a warning and
resets state (the annotation is lost).

### Real-world example annotations

```bash
# Simple: Docker Hub image with major pin and tag suffix
# @todo env-update (tag-suffix:-oraclelinux9) dockerhub:_/mysql:9 9.1.0
GLOBAL_STACK_MYSQL9_VERSION=9.1.0

# GitHub release with tag filter and major pin
# @todo env-update (tag-filter:^[0-9\.]) github:flutter/flutter:3 3.29.3
GLOBAL_STACK_FLUTTER3_VERSION=3.29.3

# npm package stable
# @todo env-update npm:serverless 3.38.0
GLOBAL_STACK_SERVERLESS_VERSION=3.38.0

# Multiple flags, any order
# @todo env-update (channel:rc) (tag-strip-prefix:v) (version-prefix:v) github:owner/repo:1 1.5.0-rc2
MY_VERSION=v1.5.0-rc2

# URL fetcher with json extraction
# @todo env-update (fetch-json:.version) url:https://example.com/api/version 2.3.0
SOME_VERSION=2.3.0
```

---

## 3. Annotation Flag Reference

All flags use balanced parentheses: `(flag)` for boolean flags, `(flag:value)` for valued
flags. Flags are **position-agnostic** — they can appear anywhere in the annotation line.

### Note flag

| Flag | Record field | Description |
|------|-------------|-------------|
| `(note:TEXT)` | `note` | Free-text annotation displayed as a `↳ TEXT` line below the version line in `--check` output. Use when bumping the variable in `.env` is not sufficient on its own — another file must also be updated. Example: `(note:also add new version to compat list in setup.sh)`. Has no effect on the decision classification. |

### Boolean (presence-only) flags

| Flag | Record field | Description |
|------|-------------|-------------|
| `(override)` | `override: true` | Force MANUAL decision regardless of version comparison. Use when a variable should never be auto-applied. |
| `(manual)` | `manual: true` | Same effect as `override` — forces MANUAL. Semantic distinction: `manual` means "needs human judgment"; `override` means "auto is wrong here." |
| `(propagate)` | `propagate: true` | Stored but not acted on by the core fetcher. Reserved for tools that need to track which variables should be propagated to derived files. |
| `(use-sha)` | `use_sha: true` | For `pecl-git`: when `--apply` writes the variable, it writes `proposed_sha` instead of `proposed_version`. Use for variables tracking a git commit SHA rather than a version string. |
| `(prefer-specific)` | `prefer_specific: true` | **dockerhub only.** After all tag filters run, drop any tag whose numeric prefix has fewer than two dots (i.e. `X` or `X.Y` "floating" tags). A tag like `9.1-alpine3.23` has numeric prefix `9.1` (1 dot) and is floating — Docker Hub silently updates it when `9.1.1` ships, making the tag string unchanging and therefore invisible to env-update. A tag like `9.0.4-alpine3.23` has prefix `9.0.4` (2 dots) and is pinnable. Use this flag when you want true version pinning. **Do NOT use for images where `X.Y` is the real specific version** (e.g. `postgres:18.3-alpine3.23` — Postgres has no `X.Y.Z` Docker tags). If all remaining tags are floating after this filter, the record is set to SKIP. |
| `(check-tags)` | `check_tags: true` | **github and pecl-git only.** Always fetch both the Releases API and the Tags API for this repo, then merge the two candidate pools before applying filters. Use for repos that publish new versions as git tags before (or instead of) creating a GitHub Release — the canonical example is Zig, which had `0.15.2` in tags while the Releases API still returned `0.15.1`. Without this flag, the fetcher uses Releases as primary and only falls back to Tags when Releases returns nothing. See also the automatic [version-gap fix](#version-gap-fix) (fires for every repo; this flag is for repos where the gap is chronic). |

### Valued flags — channel

| Flag | Record field | Description |
|------|-------------|---|
| `(channel:VALUE)` | `channel` | Select versions from a specific release channel. Values: `stable` (default), `unstable` (any pre-release), `rc`, `beta`, `alpha`, `nightly`, or any comma-separated combination like `rc,beta`. |

**Channel behavior details:**
- `stable` (empty or explicit): picks the highest non-prerelease version. Never falls back to pre-releases.
- `unstable`: picks the highest pre-release version. Falls back to stable if no pre-release exists.
- `rc`, `beta`, `alpha`: picks the highest version matching that channel keyword. Falls back to the highest pre-release if no exact match, then stable if the stable has surpassed the channel version.
- `nightly`: for the `url` fetcher's Tier 4, treats the identifier as a directory listing of nightly build directories.
- `(skip:REASON)` — forces a SKIP decision with the provided reason string stored in `skip_reason`. The fetcher still runs, but the decision is overridden. Useful for temporarily pausing a variable.

### Valued flags — tag manipulation pipeline

These flags are applied in the following order to the raw tag/version list fetched from the registry. The pipeline runs left-to-right:

1. `tag-filter` — keep only tags matching regex
2. `tag-exclude` — drop tags matching regex
3. `tag-extract` — Perl capture-group extraction (replaces the whole tag with group 1)
4. `tag-strip-prefix` — strip literal prefix
5. `tag-strip-suffix` — strip literal suffix
6. `tag-replace` — replace literal substring globally

After the pipeline, channel selection picks the best remaining version.

| Flag | Record field | Applies to | Description |
|------|-------------|------|---|
| `(tag-filter:REGEX)` | `tag_filter` | All except `sdkman`, `sdkmanager`, `url`(tiers 1-2) | Keep only tags matching ERE regex. Applied to the raw tag name. |
| `(tag-exclude:REGEX)` | `tag_exclude` | Same | Drop tags matching ERE regex. Runs after `tag-filter`. |
| `(tag-strip-prefix:STR)` | `tag_strip_prefix` | All tag-based fetchers | Strip a literal string prefix from each tag. For example, strip `v` from `v3.2.1` → `3.2.1`. See also `version-prefix` to restore it after comparison. |
| `(tag-strip-suffix:STR)` | `tag_strip_suffix` | All tag-based fetchers | Strip a literal string suffix from each tag. For example, strip `-alpine3.23` from `18.3-alpine3.23` → `18.3`. |
| `(tag-extract:PERL_REGEX)` | `tag_extract` | All tag-based fetchers | Apply a Perl regex to each tag; tags not matching are discarded; matching tags are replaced by capture group 1. Uses `perl -ne`. |
| `(tag-replace:FROM:TO)` | `tag_replace_from` / `tag_replace_to` | All tag-based fetchers | Replace all occurrences of the literal string FROM with TO in each tag. For example, Ruby tags use underscores (`3_4_9`) — `(tag-replace:_:.)` converts them to dots for semver comparison. The FROM:TO format is mandatory; FROM and TO may be empty on either side of the colon. |
| `(tag-suffix:STR)` | `tag_suffix` | `dockerhub` | **Applies only to dockerhub.** Filters the raw tag list to only tags ending with the suffix, before the rest of the pipeline runs. The suffix string is treated as a literal (not a regex). Example: `(tag-suffix:-oraclelinux9)` keeps only tags like `9.1.0-oraclelinux9`. |

> **NOTE:** `tag-suffix` is special — it is a pre-pipeline filter specific to the `dockerhub` fetcher and is applied before the `tag-filter` / `tag-exclude` pipeline. Other fetchers ignore it.

### Valued flags — version prefix restoration

| Flag | Record field | Description |
|------|-------------|---|
| `(version-prefix:STR)` | `version_prefix` | After tag processing and channel selection, re-prepend this string to the proposed version. Used together with `tag-strip-prefix` to strip `v` for comparison, then restore it for the stored value. Example: strip `v` for sorting, then `(version-prefix:v)` puts `v` back so the variable holds `v0.32.1` not `0.32.1`. |

### Valued flags — extraction strategies (for `url` fetcher)

| Flag | Record field | Tier | Description |
|------|-------------|------|---|
| `(fetch-extract:PERL_REGEX)` | `fetch_extract` | Tier 1 | Fetch the URL body (the identifier is the URL), apply the Perl regex, collect all capture group 1 matches, sort `-V`, take highest. If the regex matches nothing, returns an error (not a fallback). |
| `(fetch-json:JQ_PATH)` | `fetch_json` | Tier 2 | Fetch the URL as JSON, extract the value at the jq path. Example: `(fetch-json:.info.version)`. |
| `(url-probe:PATHS)` | `url_probe` | Tier 5 | Comma-separated path templates to probe. Templates support `{codename}` (Ubuntu codename like `noble`) and `{codename-version}` (Ubuntu version like `24.04`). The fetcher probes from newest Ubuntu codename to oldest, stopping at the first 2xx/3xx response. |
| `(url-probe-depth:N)` | `url_probe_depth` | Tier 5 | Maximum number of codenames to probe backward. Default: 6. |

### Valued flags — dependency tracking

| Flag | Record field | Description |
|------|-------------|---|
| `(depends-on:VAR:constraint)` | `depends_on` | Declare a dependency relationship. Both VAR and constraint are required; the format `VAR:constraint` is mandatory. Stored as metadata only — the core fetcher does not enforce it. Intended for tools that post-process records to check dependency ordering. |

---

## 4. CLI Flag Reference

```
bin/env-update.sh [OPTIONS]
```

| Flag | Default | Description |
|------|---------|---|
| `--version` | — | Print `2.0.0` and exit 0. |
| `--help` | — | Show usage text and exit 0. |
| `--env-file=PATH` | `/stack/.env` | Path to the `.env` file to parse. |
| `--filter=REGEX` | (none) | Only process records whose `env_var` matches this bash ERE regex. Also supports `type:TYPENAME` prefix (e.g. `--filter=type:dockerhub`) to filter by fetcher type rather than variable name. |
| `--dump` | off | After parsing, emit all records to stdout in text or JSON format. No network calls. Mutually exclusive with `--check` and `--apply`. |
| `--format=text\|json` | `text` | Output format for `--dump`. `text` emits one field per line with `field: value` pairs, grouped by record index. `json` emits a JSON array of objects, one per record, with all fields as string values. |
| `--check` | off | Fetch latest versions for all parsed records and stream the `[AUTO\|HOLD\|SKIP\|ERROR\|MANUAL]` report. Requires network. |
| `--apply` | off | Apply all `AUTO` decisions back to the `.env` file. Implies `--check`. Creates a timestamped backup of `.env` before any writes. Requires a recent `--dry-run` within the past 30 minutes (safety gate). Mutually exclusive with `--dry-run`. |
| `--scan` | off | After `--apply` completes, automatically run `bin/env-scan.sh` to propagate changes to `.env.local` and Dockerfiles. Pass-through: if `env-scan.sh` fails, a warning is printed but the exit code is non-fatal. |
| `--dry-run` | off | No writes of any kind: cache writes are suppressed, `.env` is never modified, Dockerfile propagation is skipped. Prints a `[DRY-RUN]` prefix line for each update that would be applied. Mutually exclusive with `--apply`. After a successful `--dry-run --check`, writes a timestamp marker (`last-dry-run-ts`) so a subsequent `--apply` can confirm the preview was recent. |
| `--no-cache` | off | Bypass the flat-file cache entirely. Every fetch goes to the network. Cache reads return miss; cache writes are skipped. |
| `--cache-ttl=N` | `3600` | Override the cache TTL in seconds. Must be a positive integer or zero (`0` = all cache entries treated as expired). |
| `--with-tags` | off | For every `github:` and `pecl-git:` record in the run, always fetch both the Releases API and the Tags API and merge the candidate pools. Same effect as adding `(check-tags)` to every annotation, but applies globally for one run. Use when you suspect any repo in the batch may have released via tags only. Complements the automatic [version-gap fix](#version-gap-fix); this flag ensures the merged pool is used for all repos without waiting for a gap to be detected. |
| `--unstable` / `--unstable=full` | off | **Full unstable mode.** Forces `channel=unstable` on every record that does not already have an explicit non-stable channel in its annotation. Fetchers return the highest prerelease as the proposed candidate. The prerelease guard in `decide.sh` is bypassed: `stable current + prerelease proposed` classifies as `AUTO` (not `SKIP`). `(manual)` and `(hold)` flags are still respected. Use when you want to track prerelease versions globally for a run. Accepts both `--unstable` (bare) and `--unstable=full`. Mutually exclusive with `--stable`. |
| `--unstable=info` | off | **Informational unstable mode.** Does NOT change `AUTO`/`HOLD`/`SKIP` decision logic and does NOT bypass the prerelease guard. After each fetch, performs a second pass (cache hit — no extra HTTP) with `channel=unstable` to discover what the latest prerelease would be. When a prerelease version is found that differs from the stable proposed version, it is shown as a `↳ [INFO] unstable: <version>` sub-line under the main decision line. Use when you want a heads-up about available prereleases without committing to tracking them. Mutually exclusive with `--stable`. |
| `--stable` | off | **Force stable channel.** Forces `channel=stable` on every record whose annotation has an explicit non-stable channel (`rc`, `beta`, `alpha`, `nightly`, `unstable`, or any other non-empty, non-stable value). Records already on the default stable channel (empty or `stable`) are untouched. Prints a `[STABLE MODE] channel forced stable for N record(s)` header line when at least one override occurs. Use when you want to see what the stable versions would be for a set of vars that are normally tracked at prerelease. Mutually exclusive with `--unstable` (any form). |

### Flag combinations and mutual exclusivity

- `--dry-run` and `--apply` are mutually exclusive — exit 1 if both are given.
- `--dump` and `--check` are mutually exclusive — exit 1 if both are given.
- `--dump` and `--apply` are mutually exclusive — exit 1 if both are given.
- `--apply` implies `--check` — no need to specify both; `--apply` alone triggers a check first.
- `--scan` is a no-op unless `--apply` is also specified and not `--dry-run`.
- `--stable` and `--unstable` (any form: bare, `=full`, `=info`) are mutually exclusive — exit 1 if both are given.

### Typical usage patterns

```bash
# Safe preview cycle (recommended)
bin/env-update.sh --check --dry-run                # preview all
bin/env-update.sh --check --dry-run --filter=NODE  # preview one service
bin/env-update.sh --apply                          # apply after preview (guard checks timestamp)
bin/env-update.sh --apply --scan                   # apply + propagate to .env.local + Dockerfiles

# Inspection
bin/env-update.sh                                  # parse summary, no network
bin/env-update.sh --dump                           # dump parsed records (no network)
bin/env-update.sh --dump --format=json | jq .      # machine-readable records

# Targeted runs
bin/env-update.sh --check --filter=POSTGRES        # only GLOBAL_STACK_POSTGRES* vars
bin/env-update.sh --check --filter=type:github     # only github-type fetchers
bin/env-update.sh --check --no-cache               # force fresh fetch

# Unstable / prerelease tracking
bin/env-update.sh --unstable --check               # full unstable: propose prereleases as AUTO
bin/env-update.sh --unstable --check --filter=NODE # unstable only for NODE vars
bin/env-update.sh --unstable=info --check          # info mode: show unstable as sub-line only

# Stable channel override (see what stable versions would be for prerelease-tracked vars)
bin/env-update.sh --stable --check                 # force stable: stable versions for all rc/beta/nightly vars
bin/env-update.sh --stable --check --dry-run       # preview stable-forced output without writing

# Tag-ahead audit
bin/env-update.sh --check --with-tags              # merge releases+tags for all github/pecl-git repos
bin/env-update.sh --check --filter=ZIG             # (check-tags already annotated on Zig — no flag needed)

# Debug
bin/env-update.sh --version                        # print 2.0.0
bin/env-update.sh --help                           # show all flags
```

---

## 5. Output Format — Every Detail

### Default output (no action flags)

When no `--check`, `--apply`, or `--dump` flag is given, the tool prints a parser summary
to stdout. No network calls are made.

```
env-update v2.0.0 — parsed /stack/.env

  73 annotated variables across 8 fetcher types:
    codeberg        1   dockerhub      21   github         34
    npm             8   pecl           4   pecl-git        2
    sdkman          2   url            1

  Hint: run --check to fetch latest versions (network required)
        run --dump  to emit structured records
        run --help  for all options
```

The per-type breakdown is printed in columns of three, left-aligned, sorted alphabetically
by type name. Column widths: type name at 12 chars, count at 4 chars.

### --check output format

The `--check` output streams one line per record as each fetch completes. A progress
indicator (overwritten with `\r`) shows the current variable being fetched on stderr while
the fetch is in progress.

```
[AUTO  ]  GLOBAL_STACK_POSTGRES18_VERSION              18.3-alpine3.23 → 18.4-alpine3.23
[HOLD  ]  GLOBAL_STACK_MYSQL9_VERSION                  9.1.0 → 9.6.0  ← major bump (9→9)
[HOLD  ]  GLOBAL_STACK_JAVA_VERSION                    17.5 → 21.0.3  ← major pin (21.x available)
[SKIP  ]  GLOBAL_STACK_NGINX_VERSION                   (up to date)
[SKIP  ]  GLOBAL_STACK_OLD_VERSION                     (would downgrade)
[MANUAL]  GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION     18.3 → 19.0  ← manual flag
[ERROR ]  GLOBAL_STACK_SOME_VERSION                    (fetch failed for github:owner/repo)
──────────────────────────────────────────────────────────────────────────────
  Summary: 1 AUTO, 2 HOLD, 1 MANUAL, 2 SKIP, 1 ERROR  (7 checked)
```

### Column layout and spacing

Each output line follows this `printf` template:

```bash
printf "%s  %-${_max_var_len}s%s\n" "${_tag}" "${_env_var}" "${_change}"
```

- `_tag` — 8 characters wide (e.g. `[AUTO  ]`, `[HOLD  ]`, `[SKIP  ]`, `[ERROR ]`, `[MANUAL]`). Note the **two trailing spaces** after the bracket content for all 4-letter decisions (`AUTO`, `HOLD`, `SKIP`) to align with the 6-char `[MANUAL]`. The actual tag strings are `[AUTO  ]`, `[HOLD  ]`, `[SKIP  ]`, `[ERROR ]`, `[MANUAL]`.
- Two spaces between tag and variable name.
- `_env_var` — left-padded to `_max_var_len` characters (dynamic — see below).
- `_change` — appended directly after, starting with two spaces.

**Dynamic column width**: before the fetch loop, `main.sh` pre-scans all `env_var` names
in the current run and sets `_max_var_len` to the length of the longest name. Minimum
width is 40 characters. This ensures the `→` arrow (or reason label) appears at the same
column across all lines in the output, regardless of variable name length.

**Why are there multiple spaces between `[MANUAL]` and the variable name?**
The tag itself is always exactly 8 characters: `[` + 6-char content + `]`. Content is padded to 6 chars, so `AUTO` becomes `AUTO  ` (2 trailing spaces), `HOLD` becomes `HOLD  `, `SKIP` becomes `SKIP  `, `ERROR` becomes `ERROR ` (1 trailing space), and `MANUAL` is exactly 6 chars with no padding. After the tag come **2 fixed spaces** (the `  ` in the format string), then the variable name in a dynamic-width field. The visual appearance of "extra spaces" between `[AUTO  ]` and the variable name comes from the 2 trailing spaces inside the tag brackets plus the 2 fixed spaces = 4 spaces before the variable.

### The `_change` field

The `_change` suffix is built from the decision and record state:

| Condition | `_change` value |
|-----------|----------------|
| `SKIP` with `error_message` | `  (error_message text)` |
| `SKIP` prerelease proposed, current stable | `  (proposed is prerelease — pin manually when stable ships)` |
| `SKIP` downgrade detected | `  (would downgrade)` |
| `SKIP` without error (up to date) | `  (up to date)` |
| `HOLD` / `AUTO` / `MANUAL` with `proposed != current` | `  current_version → proposed_version[reason]` |
| Any decision with `error_message` (no proposed) | `  (error_message text)` |
| Otherwise | `` (empty) |

### Reason labels

Non-AUTO decisions append a short reason label to the version arrow so the user knows
immediately why the decision was made, without needing to understand annotation flags or
inspect the record.

| Decision | Trigger | Reason label appended |
|----------|---------|----------------------|
| `[HOLD  ]` | Major bump, no `major_hint` pin | `  ← major bump (X→Y)` where X=current major, Y=proposed major |
| `[HOLD  ]` | Proposed version escapes `major_hint` pin | `  ← major pin (Y.x available)` where Y=proposed major |
| `[MANUAL]` | `(override)` or `(manual)` annotation flag | `  ← manual flag` |
| `[SKIP  ]` | Proposed is a prerelease, current is stable | `  (proposed is prerelease — pin manually when stable ships)` |
| `[SKIP  ]` | Proposed is older than current (downgrade) | `  (would downgrade)` in place of arrow |
| `[SKIP  ]` | Up to date | `  (up to date)` — no label needed |
| `[ERROR ]` | Fetch failure | error message is the reason — no additional label |

Reason labels use the same color as surrounding text — no new colors are introduced.
If a reason cannot be determined (unknown HOLD sub-case), the label is omitted rather
than showing a placeholder.

### Decision tags

| Tag | When it fires |
|-----|--------------|
| `[AUTO  ]` | The fetcher found a newer version within the same major (or within the major_hint pin), and no `override` or `manual` flag is set. Safe to apply automatically. |
| `[HOLD  ]` | A newer version exists but it crosses a major version boundary, or the proposed version escapes the major_hint pin. Requires human review before upgrading. Reason label explains which case triggered. |
| `[MANUAL]` | The annotation has `(override)` or `(manual)` flag, OR the fetcher (e.g. `sdkmanager`) explicitly sets `manual=true`. The proposed version is shown but will never be auto-applied. |
| `[SKIP  ]` | The variable is already at the latest version (`current == proposed`), or the fetcher returned no viable candidates, or the current version is a floating reference (`latest`, `nightly`, etc.), or the proposed would downgrade the current version, or the proposed is a prerelease while the current is stable. Also used when a fetcher sets `error_message` but no `decision`. |
| `[ERROR ]` | Network failure, HTTP error (4xx/5xx), rate limiting after 3 retries, or a parse failure in the API response. The fetch was attempted and definitively failed. |

### alt_version line

When the `github` fetcher selects a stable version but a newer pre-release also exists in
the tag list, it populates `alt_version`. The `url` fetcher also populates it in some
cases. The `pecl-git` fetcher uses it to signal PECL promotion availability.

The `alt_version` field is visible in `--dump` output. In the streaming `--check` output,
`alt_version` is not currently printed inline (it is stored in the record and accessible
via `--dump --format=json`).

### --format=json structure

`--dump --format=json` emits a JSON array. Each element is an object with all 31 record
fields as string keys. Empty fields are present as empty strings (`""`), not `null`.

```json
[
  {
    "env_var": "GLOBAL_STACK_POSTGRES18_VERSION",
    "current_version": "18.3-alpine3.23",
    "type": "dockerhub",
    "identifier": "_/postgres",
    "major_hint": "18",
    "override": "",
    "manual": "",
    "propagate": "",
    "channel": "",
    "skip_reason": "",
    "version_prefix": "",
    "tag_filter": "",
    "tag_exclude": "",
    "tag_strip_prefix": "",
    "tag_strip_suffix": "",
    "tag_extract": "",
    "tag_replace_from": "",
    "tag_replace_to": "",
    "tag_suffix": "-alpine3.23",
    "fetch_extract": "",
    "fetch_json": "",
    "url_probe": "",
    "url_probe_depth": "",
    "pecl_ref": "",
    "depends_on": "",
    "urls": "",
    "git_fallback_url": "",
    "git_fallback_sha": "",
    "hint": "",
    "line_number": "42",
    "raw_annotation": "# @todo env-update (tag-suffix:-alpine3.23) dockerhub:_/postgres:18 18.3-alpine3.23",
    "proposed_version": "",
    "decision": "",
    "error_message": "",
    "alt_version": "",
    "annotation_sha": "",
    "proposed_sha": "",
    "use_sha": "",
    "commit_date": ""
  }
]
```

### --dump text format

The text format prints one record block per parsed annotation:

```
=== record 0 ===
env_var: GLOBAL_STACK_POSTGRES18_VERSION
current_version: 18.3-alpine3.23
type: dockerhub
identifier: _/postgres
major_hint: 18
...
```

Fields are printed in canonical order as defined in `records.sh::_gs_eu2_record_fields()`.
Empty fields are printed as `field: ` (empty value).

### Color output

Color is not currently implemented in the `--check` streaming output. The `NO_COLOR`
environment variable is respected by the test harness colors but is not applied to the main
tool output. All output is plain text.

### --apply output

When `--apply` is active:

```
Backup: /stack/.env.bak.1716123456
[APPLIED]  GLOBAL_STACK_POSTGRES18_VERSION              18.3-alpine3.23 → 18.4-alpine3.23
[APPLIED]  GLOBAL_STACK_NODE22_VERSION                  22.13.0 → 22.14.0
  2 update(s) applied to /stack/.env
```

When `--dry-run --apply`:

```
Apply preview (--dry-run):
  [DRY-RUN]  GLOBAL_STACK_POSTGRES18_VERSION              18.3-alpine3.23 → 18.4-alpine3.23
  1 update(s) would be applied (--dry-run — no writes)
```

---

## 6. Decision Engine

The decision engine (`core/decide.sh`) runs after every fetcher completes. It classifies
the fetcher's `proposed_version` against `current_version` and writes the final `decision`
field. Fetchers may pre-set `decision` to `ERROR` or `SKIP` themselves (to short-circuit),
but if `decision` is `AUTO` or empty, `decide.sh` makes the final call.

### Full decision path

```
proposed_version empty?        → SKIP
current is unversioned?        → SKIP  (floating ref: nightly/latest/edge/master/next/head/main)
override=true OR manual=true?  → MANUAL
current == proposed?           → SKIP  (up to date)
proposed is prerelease AND
  current is stable?           → SKIP  (prerelease guard — "proposed is prerelease")
proposed sorts before current? → SKIP  (downgrade protection, via sort -V)
semver_delta = major?
  major_hint empty?            → HOLD  (major jump, no pin — requires review)
  major_hint set but proposed
  does not start with hint?    → HOLD  (escapes the pin — C3 rule)
                               → AUTO  (within major, safe to apply)
```

The **prerelease guard** protects stable variables from being auto-proposed RC/alpha/beta
versions. It uses `_gs_eu2_is_prerelease` which matches the full marker set (both dash and
no-dash formats: `6.3.0-rc1` and `6.3.0RC1` are both detected). When it fires, the SKIP
annotation reads `(proposed is prerelease — pin manually when stable ships)`.

### Downgrade protection

Before the semver delta check, the engine uses `sort -V` to compare `current` and
`proposed` (stripping any leading `v`). If `proposed` sorts before `current`, the decision
is `SKIP`. This prevents accidentally "downgrading" a variable when the registry returns an
older tag that passes the filter.

### Major hint enforcement (C3 rule)

The major hint pin uses the regex `^${major_hint}([.^_-]|$)` to test whether the proposed
version starts with the hint. The trailing anchor `([.^_-]|$)` prevents a hint of `18`
from matching `180.0`. The `_` in the anchor accommodates Ruby-style tags (`3_4_9`).

Examples:
- `major_hint=18`, proposed=`18.4` → matches `^18([.^_-]|$)` → AUTO
- `major_hint=18`, proposed=`19.0` → does not match → HOLD
- `major_hint=8.2`, proposed=`8.2.28` → matches `^8.2([.^_-]|$)` → AUTO (D1 rule: dotted hints work)
- `major_hint=8.2`, proposed=`8.3.0` → does not match → HOLD

### Semver comparison details (`core/semver.sh`)

**`_gs_eu2_semver_compare`** — strips `v` prefix, checks for pre-release suffix (`-alpha`,
`-rc1`, etc.). If both have the same base version but one has a pre-release suffix, the
pre-release is "older" (`1.0.0-rc1 < 1.0.0`). Falls back to `sort -V` for the final call.

**`_gs_eu2_semver_delta`** — returns `major`, `minor`, `patch`, or `unknown`:
- Strips `v` prefix, normalizes `_` to `.`.
- **Path-prefix stripping**: git-refs-style prefixes like `tags/2.4.66` are stripped to
  `2.4.66` before comparison, so `tags/2.4.66 → tags/2.4.67` is correctly classified as
  `patch` (not `major`). Pattern matched: `^<word>/<digit-led-version>`.
- **Codename-date style** (e.g. ubuntu `resolute-20260108`): if both operands start with
  a non-digit (after path stripping), compares the prefix before the first hyphen. Same
  prefix = `patch`, different prefix = `major`.
- **Date-SHA style** (e.g. `20241231-abc12345` or 40-char hex): always returns `patch` so
  `decide.sh` emits AUTO instead of HOLD for commit-tracking variables.
- Numeric: compares first component for major, second for minor, falls back to patch.

The HOLD reason label (e.g. `← major bump (2→3)`) also strips any path prefix so `tags/2`
displays as just `2`.

### Prerelease detection (`_GS_EU2_PRERELEASE_MARKERS`)

The following patterns are recognized as pre-release markers (case-insensitive):

```
alpha[0-9.]*    beta[0-9.]*     rc[0-9.]*       preview         pre
nightly         edge            canary          snapshot        experimental
insiders        .dev            -dev            [0-9]a[0-9]     [0-9]b[0-9]
milestone       [.-]m[0-9]      -cr[0-9]        -ea             -next.
next
```

The `D5` fix ensures `[0-9.]*` is used after `rc`/`alpha`/`beta` so that both `rc1` and
`rc.1` are detected. Note that distribution suffixes used by SDKMAN Java (like `-zulu`,
`-tem`) are explicitly **not** in this list and are handled separately in `sdkman.sh`.

---

## 7. Fetcher Deep-Dives

### 7.1 dockerhub

**Identifier format:** `NAMESPACE/IMAGE` where namespace is either a Docker Hub user/org or
the special alias `_/` for Docker Official Library images.

- `_/postgres` → fetches `library/postgres` (Docker Official Library)
- `dpage/pgadmin4` → fetches `dpage/pgadmin4`
- `_/mysql` → fetches `library/mysql`

**API endpoint:** `https://registry.hub.docker.com/v2/repositories/{namespace}/tags?page_size=100&ordering=last_updated`

**Pagination:** Follows the `next` field in each page response until `null`. Accumulates all tags from all pages (C1 rule). There is no page limit — it fetches everything.

**What field is used:** `.results[].name` — the tag name string.

**Major hint:** Yes. After the tag pipeline, filters with `grep -E "^${major_hint}([.^-]|$)"` then falls back to awk for exact first-segment matching.

**Tag flags:** All tag flags apply. The `tag-suffix` flag is special — it pre-filters tags before the rest of the pipeline runs. The `prefer-specific` flag (see Section 3) demotes floating tags after all filters, before channel selection.

**Floating vs specific tags — why it matters:** Docker Hub serves both "floating" tags (`X.Y`, `X`) that are continuously updated to point to the latest patch, and "specific" tags (`X.Y.Z`) that are permanently pinned to an exact image. A floating tag like `9.1-alpine3.23` silently re-points when Docker Hub publishes `9.1.1-alpine3.23`. Since the tag string never changes, env-update will never detect the update and your container will silently pull a different image on next `docker pull`. Use `(prefer-specific)` to enforce pinnable `X.Y.Z` tags.

**Version prefix:** After pipeline and channel selection, if `version_prefix` is set, it is prepended to the proposed version (B3 rule).

**Channel support:** Yes — via `_gs_eu2_channel_select_best`.

**No auth required.**

**Pitfalls:**
- Images with only `latest` tag (no versioned tags) → SKIP with "no versioned tags available".
- The `_/` prefix shorthand: using the raw image name without `_/` will attempt to fetch `imagename` as a user namespace (likely fails).
- `tag-suffix` must match the exact literal suffix (not a regex) — the code escapes it before using it in grep.
- **Do NOT use `(prefer-specific)` with Postgres**: `postgres:18.3-alpine3.23` is the real specific tag — no `18.3.x` Docker tags exist. The filter would drop all tags and produce SKIP.

**Cache key:** `dockerhub:namespace/image:tag_suffix:major_hint:channel`

**Example annotations:**
```bash
# Standard with oraclelinux suffix
# @todo env-update (tag-suffix:-oraclelinux9) (tag-strip-suffix:-oraclelinux9) dockerhub:_/mysql:9 9.1.0
GLOBAL_STACK_MYSQL9_VERSION=9.1.0-oraclelinux9

# Pinning to specific X.Y.Z tags (floating X.Y tags are rejected)
# @todo env-update (tag-filter:alpine) (prefer-specific) dockerhub:valkey/valkey 9.0.3-alpine3.23
GLOBAL_STACK_VALKEY_VERSION=9.0.3-alpine3.23
```

---

### 7.2 github

**Identifier format:** `owner/repo` (e.g. `flutter/flutter`, `docker/buildx`)

**Three-strategy fetch (tried in order):**

1. **Releases API** — `GET /repos/{owner}/{repo}/releases?per_page=100`. Filters out drafts (`draft == false`). Pre-releases and stable releases are both included at this stage; channel selection decides later.
   - **Pre-release-only fallthrough:** If the Releases API returns only pre-releases and the channel is stable (empty or `"stable"`), the fetcher automatically falls through to Strategy 2. This handles repos like Flutter that publish GitHub Releases exclusively for pre-releases while stable tags are tag-only.
2. **Tags API** — `GET /repos/{owner}/{repo}/tags?per_page=100&page=N`. Paginated up to 10 pages. Stops early when a page returns fewer than 100 items.
3. **git ls-remote** — last resort, triggered when `major_hint` is set and both the Releases and Tags APIs returned nothing that matched the pin after applying all tag filters. Calls `git ls-remote` on `https://github.com/{owner}/{repo}.git`. Testable via the `_GS_EU2_GIT_LS_REMOTE_FIXTURE` env var.

**Authentication:** Reads `GITHUB_TOKEN` or `GLOBAL_STACK_GITHUB_TOKEN` from the environment. Without a token, the unauthenticated API rate limit (60 req/hr) applies. The error message includes a hint to set the token when auth is absent and a fetch fails.

**Token in git ls-remote:** Uses `GIT_ASKPASS` to supply the token out-of-band (avoids the token appearing in process listings or shell history).

**Major hint:** Yes. Applied after the tag pipeline with `grep -E "^v?${major_hint}([.^_-]|$)"`.

**Tag flags:** Full pipeline applies to both the releases and tags strategy outputs.

**`alt_version`:** When the channel is stable (empty or `stable`) and a newer pre-release exists beyond the stable pick, `alt_version` is set to `"pre-release also available: VERSION"`.

**Version prefix:** Applied after channel selection if `version_prefix` is set.

**Cache key:** `github:owner/repo:major_hint:channel` (normal mode); `github:owner/repo:major_hint:channel:tags` (check-tags / --with-tags mode — separate key to prevent cache contamination).

**Merge mode (`(check-tags)` / `--with-tags`):**

When either the per-annotation `(check-tags)` flag or the `--with-tags` CLI flag is active, the fetcher **always runs both** the Releases API and the Tags API, then **merges the two candidate pools** before applying tag flags and channel selection. This guarantees the best version across both sources:

```
Releases → [v0.14.0]
Tags     → [v0.15.2, v0.15.0, v0.14.0, v0.13.5]
Merged   → [v0.14.0, v0.15.2, v0.15.0, v0.14.0, v0.13.5]
Filtered → channel_select → v0.15.2
```

Use `(check-tags)` for repos where the Releases API chronically lags the Tags API (e.g. `ziglang/zig`). Use `--with-tags` for one-off audits of the entire batch.

**Version-gap fix (automatic):** <a name="version-gap-fix"></a>

Even without `(check-tags)`, the fetcher detects when the normal strategy proposes a version **older than the current version** (`proposed < current`). When this gap is detected, the fetcher automatically fetches the Tags API, merges it with the original releases pool, re-runs the filter+channel pipeline, and takes the best result. If the merged pool produces a newer version, it replaces the original proposed value.

This fires silently and automatically on every run — no annotation change needed. It catches the "I updated to a tag-only release, but env-update is now stuck proposing the older Release" case.

```
Normal run:   releases → v0.14.0   vs current v0.15.2 → gap detected!
Gap fix:      tags → v0.15.2, merged → v0.15.2 (same as current → SKIP, up to date)
```

Difference vs `(check-tags)`: The gap fix fires only **after** a gap is detected (reactive). `(check-tags)` fires on **every** run for that repo (proactive — use for chronic divergers).

**Known quirks:**
- Some repos publish via Releases API only; others only via Tags API. The fetcher handles both transparently. Repos with thousands of tags may need git ls-remote for deep major version searches.
- **Repos that publish GitHub Releases only for pre-releases** (e.g., Flutter): the fetcher detects this and falls through to the Tags API and git ls-remote automatically — no special annotation needed beyond the normal `tag-filter` flag.
- **SKIP→ERROR escalation:** When all fetch strategies exhaust without finding stable tags, and the current version is itself stable, the fetcher sets `ERROR` instead of `SKIP`. The reasoning: a stable current version proves stable releases have existed for this project — failing to find any indicates a fetcher failure rather than a legitimate "no stable releases" scenario.

**Example annotations:**
```bash
# @todo env-update (tag-filter:^[0-9\.]) github:flutter/flutter:3 3.29.3
GLOBAL_STACK_FLUTTER3_VERSION=3.29.3

# With v-prefix stripping and restoration
# @todo env-update (tag-strip-prefix:v) (version-prefix:v) github:docker/buildx v0.22.0
GLOBAL_STACK_BUILDX_VERSION=v0.22.0

# Repos that release via tags only (Zig releases tags before GitHub Releases)
# @todo env-update (check-tags) github:ziglang/zig 0.15.2 urls: https://ziglang.org/download/
GLOBAL_STACK_ZIG_VERSION=0.15.2

# Tracking an underscore-repo (GitHub repo name with underscores)
# HTTP fixture: bin/tests/fixtures/env-update/http/api.github.com_repos_testowner_underscore-repo_releases
# @todo env-update github:testowner/underscore-repo 1.0.0
```

---

### 7.3 npm

**Identifier format:** Package name, including scoped packages with `@` prefix.

- `serverless` → `https://registry.npmjs.org/serverless`
- `@angular/cli` → `https://registry.npmjs.org/%40angular%2Fcli` (URL-encoded)

**CLI fast path:** When `npm` is available on PATH and fixture mode is not active and the channel is stable, uses `npm view PACKAGE dist-tags.latest` directly. Skips the API call.

**API:** `https://registry.npmjs.org/{encoded-package}`

**Stable fast path:** Reads `.["dist-tags"].latest` from the full registry JSON when no special channel is requested.

**Full channel path:** Reads `.versions | to_entries[]` filtering out deprecated entries (where `.value.deprecated != ""`). Then applies the tag flags pipeline, major-pin filter, and channel selection.

**Major hint:** Yes. After tag flags, applies `grep -E "^v?${major_hint}([.^-]|$)"` with awk fallback.

**Tag flags:** Full pipeline applies to the version list.

**Version prefix:** Applied after channel selection.

**No auth required.**

**Pitfalls:**
- Deprecated package versions are excluded from the full version list path.
- The stable fast path (`dist-tags.latest`) does not apply tag flags — it returns the registry's declared "latest" directly.

**Cache key:** `npm:package-name:major_hint:channel`

**Example annotation:**
```bash
# @todo env-update npm:serverless:3 3.38.0
GLOBAL_STACK_SERVERLESS_VERSION=3.38.0
```

---

### 7.4 pecl-git

See also [Section 10 (Extended)](#10-pecl-git-fetcher--extended) for full details.

**Identifier format:** `owner/repo` (GitHub repository hosting a PHP extension).

**Strategy:** Fetches release tags from GitHub (releases API → tags API fallback, max 3 pages). Strips `v`-prefix and any `tag_strip_prefix`. Filters stable candidates when current is stable (prerelease guard). Filters by major_hint. Sorts descending, takes best. Fetches the commit SHA for the version tag. Fetches the commit date. Checks for PECL promotion.

**Merge mode and version-gap fix:** Supports `(check-tags)` and `--with-tags` exactly as the `github` fetcher does. When active, always fetches both the Releases API and Tags API and merges the candidate pools. The automatic version-gap fix (proposed < current → auto-check tags) also applies.

**PECL extension name derivation:** Strips `php-`, `php_`, or `ext-` prefix from the repo name (lowercase). If auto-derivation is wrong, migrate to `pecl:NAME (git:owner/repo)` instead (see [§7.12](#712-pecl)).

**`proposed_version`:** The semver release tag (v-prefix stripped, e.g. `6.3.0`).
**`proposed_sha`:** Full commit SHA for HEAD (always HEAD, not the tagged SHA — supports PHP master workflows). May be empty if the GitHub API is unreachable.
**`proposed_sha_date`:** YYYY-MM-DD date of the HEAD commit (stored in record; written to annotation as `sha:HASH (YYYY-MM-DD)` by `--apply`).
**`commit_date`:** Same as `proposed_sha_date` — YYYY-MM-DD date of HEAD (used for PECL promotion check).
**`alt_version`:** If a newer stable PECL release exists (i.e., `pecl_release_date > commit_date`), set to `"PECL stable available: VERSION — consider switching to pecl:EXTNAME"`.

**`use_sha` flag:** When `(use-sha)` is present, `--apply` writes `proposed_sha` to the variable instead of `proposed_version`.

**Cache key:** `pecl-git4:owner/repo` (the `4` suffix was bumped to switch from tag SHA to HEAD SHA).

**Auth:** Reads `GITHUB_TOKEN` or `GLOBAL_STACK_GITHUB_TOKEN`.

**Example annotation:**
```bash
# @todo env-update pecl-git:krakjoe/parallel 1.2.2
GLOBAL_STACK_PHP_PARALLEL_VERSION=1.2.2
```

---

### 7.5 pypi

**Identifier format:** Package name (e.g. `ansible`, `awscli`).

**CLI fast path:** When `pip` is available on PATH and fixture mode is not active and the channel is stable, uses `pip index versions PACKAGE` to extract the latest stable version directly.

**API:** `https://pypi.org/pypi/{package}/json`

**Stable fast path:** Reads `.info.version`.

**Full channel path:** Reads `.releases | to_entries[]` filtering out releases where all files are yanked (`all(.yanked == true)`). Applies tag flags pipeline, major-pin, and channel selection.

**Major hint:** Yes.

**Tag flags:** Full pipeline applies.

**No auth required.**

**Pitfalls:**
- A release is considered yanked only if ALL its files are yanked. Partially yanked releases (some files yanked) are still included.
- The `pip index versions` output format varies across pip versions — the extraction uses `grep -oE '\([^)]+\)'` to find the versions list in parentheses.

**Cache key:** `pypi:package-name:major_hint:channel`

**Example annotation:**
```bash
# @todo env-update pypi:ansible 10.7.0
GLOBAL_STACK_ANSIBLE_VERSION=10.7.0
```

---

### 7.6 quay

**Identifier format:** `org/image` (e.g. `keycloak/keycloak`).

**API:** `https://quay.io/api/v1/repository/{org}/{image}/tag/?limit=50&onlyActiveTags=true`

**No pagination** — fetches at most 50 tags per call. If a project has more than 50 active tags, only the most recently updated 50 are considered.

**What field is used:** `.tags[].name`

**Major hint:** Yes.

**Tag flags:** Full pipeline applies.

**No auth required.**

**Version prefix:** Applied after channel selection.

**Pitfalls:**
- The 50-tag limit may miss older major versions if the project has many active tags. Use `major_hint` to ensure the right version range is targeted.

**Cache key:** `quay:org/image:major_hint:channel`

**Example annotation:**
```bash
# @todo env-update quay:keycloak/keycloak:26 26.1.4
GLOBAL_STACK_KEYCLOAK_VERSION=26.1.4
```

---

### 7.7 rubygems

**Identifier format:** Gem name (e.g. `rails`, `bundler`).

**CLI fast path:** When `gem` is available on PATH and fixture mode is not active and the channel is stable, uses `gem search "^NAME$" --versions --all --no-color` to extract the latest version.

**Two-endpoint strategy:**
1. `https://rubygems.org/api/v1/gems/{name}.json` → `.version` (stable fast path)
2. `https://rubygems.org/api/v1/versions/{name}.json` → `.[] | select(.yanked == false) | .number` (full list)

**Resilience:** If the versions endpoint fails, falls back to the single stable version from the gems endpoint.

**Major hint:** Yes.

**Tag flags:** Full pipeline applies to the version list.

**No auth required.**

**Pitfalls:**
- Yanked versions are excluded from the full list.
- The gems endpoint only returns the single current stable version — for channel-aware selection, the versions endpoint is needed.

**Cache key:** `rubygems:gem-name:major_hint:channel`

**Example annotation:**
```bash
# @todo env-update rubygems:bundler:2 2.6.3
GLOBAL_STACK_BUNDLER_VERSION=2.6.3
```

---

### 7.8 sdkman

**Identifier format:** SDKMAN candidate name (e.g. `java`, `gradle`, `maven`, `scala`).

**Strategy (HTTP-first, CLI not used in v2):**
1. `GET /2/candidates/{candidate}/linux/versions/list?current={current}&pageSize=40` — text table. Skipped for `java` (API returns 400).
2. `GET /2/candidates/{candidate}/linux/versions/all` — comma-separated list. Always used for Java; fallback for others.

**Java special handling:**
- Java versions include distribution suffixes: `11.0.31-zulu`, `11.0.31-tem`, `17.0.14-graalce`.
- The fetcher extracts the preferred distribution from `current_version` (e.g. `11.0.21-zulu` → preferred `zulu`).
- Selection preference: preferred distribution > `-tem` (Temurin) > others.
- Pre-releases in the base version (`rc`, `beta`, `alpha`, `ea`) are excluded in stable mode.

**Major hint:** Yes.

**No tag flags** — the version list is extracted via regex from the raw text response, not as structured tags.

**Channel support:** Yes — `_gs_eu2_channel_select_best` is called on the extracted version list.

**When not installed:** If both HTTP endpoints fail and the fixture dir is not set and `SDKMAN_DIR` (`/stack/tools/sdkman` default) is absent, sets `error_message` to "sdkman not installed" and returns without a proposed version. This results in SKIP (not ERROR).

**Cache key:** `sdkman:candidate:major_hint:channel`

**Example annotations:**
```bash
# @todo env-update sdkman:java:17 17.0.10-tem
GLOBAL_STACK_JAVA17_VERSION=17.0.10-tem

# @todo env-update sdkman:gradle:8 8.12.1
GLOBAL_STACK_GRADLE_VERSION=8.12.1
```

---

### 7.9 sdkmanager

**Identifier format:** Android SDK component name (e.g. `platform-tools`, `build-tools`, `ndk`).

**Strategy:**
1. Checks `_GS_EU2_SDKMANAGER_CMD_FIXTURE` env var (test seam — cats that file).
2. Locates `sdkmanager` binary: PATH → `${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager` → `${ANDROID_HOME}/cmdline-tools/bin/sdkmanager` → `${ANDROID_HOME}/tools/bin/sdkmanager`.
3. Runs `sdkmanager --sdk_root=... --list` and parses output.

**Always MANUAL.** The fetcher sets `manual=true` unconditionally. No `--apply` will ever write an sdkmanager variable. Reason: sdkmanager versions are platform/tool-dependent and require explicit human decision.

**Output parsing:** Handles two formats from `sdkmanager --list`:
- `COMPONENT | VERSION | ...` (bare name, single version)
- `COMPONENT;VERSION | VERSION | ...` (component;version pairs for tools like `build-tools` and `ndk`)

**No major hint, no tag flags, no channel.**

**When not found:** Sets `error_message` and returns (no proposed version) → SKIP decision. Not ERROR — the binary may simply not be installed on this machine.

**Cache key:** `sdkmanager:component:channel`

**Example annotation:**
```bash
# @todo env-update sdkmanager:platform-tools 35.0.2
GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION=35.0.2
```

---

### 7.10 url

**Identifier format:** A full URL (the resource to fetch). The identifier IS the URL.

**Five-tier strategy (tried in order, stop at first match):**

**Tier 1 — `fetch-extract` (Perl regex):**
Triggered when `(fetch-extract:REGEX)` is set. Fetches the URL body, applies the Perl regex
with `perl -ne "if (/REGEX/) { print \"$1\n\" }"`, collects all capture group 1 matches,
sorts with `sort -V`, takes the highest. If the regex matches nothing, returns an error
(not a fallback to the next tier — `fetch-extract` is the declared strategy).

**Tier 2 — `fetch-json` (jq path):**
Triggered when `(fetch-json:JQ_PATH)` is set. Fetches the URL as JSON, extracts the value
at the jq path. If the result is empty or null, returns an error (same non-fallback behavior).

**Tier 3 — GitHub redirect via `urls:` field:**
Triggered when the `urls:` field contains at least one `github.com` URL. Extracts
`owner/repo` from the URL, calls the GitHub Releases API then Tags API (3 pages max),
applies the tag flags pipeline, runs channel selection. Respects `GITHUB_TOKEN`. If this
strategy finds a result, it returns immediately. If not, it tries the next urls: entry and
eventually falls through.

**Tier 4 — Directory listing:**
Two sub-modes:

- **`channel:nightly`** — fetches the identifier URL, parses `href="..."` attributes
  looking for versioned directory entries (containing at least one digit), sorts them with
  `sort -V`, takes the highest. If nothing found, returns an error.

- **Apache/SVN/GNU detection** — triggered when the URL contains `svn.apache.org/repos/asf/`,
  `/pub/gnu/`, or `apache.org.*tags/`. Fetches the HTML directory listing, extracts `href`
  values containing version numbers (`[0-9]+\.[0-9]`), applies `version_prefix` filtering,
  runs channel selection. If `version_prefix` is set, keeps only hrefs starting with the
  prefix and strips it for comparison, then re-prepends for the result.

**Tier 5 — `url-probe` (Ubuntu codename paths):**
Triggered when `(url-probe:PATHS)` is set. Probes each path template from newest Ubuntu
codename backward (up to `url_probe_depth` codenames, default 6). Template variables:
`{codename}` and `{codename-version}`. Uses HTTP HEAD (with GET fallback for 405 Method
Not Allowed). Returns the first path that responds 2xx or 3xx. The result is the raw path
form (e.g. `stable/xUbuntu_24.04`), allowing `decide.sh` to compare it directly against
`current_version`.

**Ubuntu codenames (ordered oldest to newest):**
xenial (16.04), bionic (18.04), focal (20.04), jammy (22.04), kinetic (22.10), lunar (23.04),
mantic (23.10), noble (24.04), oracular (24.10), plucky (25.04), questing (25.10), resolute (26.04).

**No tier matched:** Sets `error_message = "url: no extraction strategy matched for URL"` and
returns 0 with empty proposed_version. `decide.sh` will classify as SKIP.

**No major hint** (the identifier is a URL, not a versioned registry).

**Tag flags:** Apply in Tiers 3 and 4 (directory listing). Not applied in Tiers 1 and 2.

**Version prefix:** Applied in Tiers 1, 2, 3, and 4 to the selected version.

**Cache key:** `url:URL:fe_flag:fj_flag:up_flag:channel`

**Example annotations:**
```bash
# Tier 1: Perl regex extraction from a changelog/download page
# @todo env-update (fetch-extract:cmdline-tools-([0-9]+)\.) url:https://dl.google.com/android/repository/repository2-3.xml 16
GLOBAL_STACK_ANDROID_CMD_LINE_TOOLS_VERSION=16

# Tier 2: JSON API extraction
# @todo env-update (fetch-json:.latestVersion) url:https://api.example.com/version 3.2.1
MY_TOOL_VERSION=3.2.1

# Tier 3: GitHub redirect
# @todo env-update url:https://example.com/info urls: https://github.com/owner/repo/releases 1.5.0
SOME_TOOL_VERSION=1.5.0

# Tier 5: Ubuntu codename probe
# @todo env-update (url-probe:stable/xUbuntu_{codename-version}) url:https://repo.example.com stable/xUbuntu_24.04
PKG_REPO_PATH=stable/xUbuntu_24.04
```

---

### 7.11 codeberg

**Identifier format:** `owner/repo` (Codeberg repository, Gitea platform).

**API endpoints:**
1. Releases: `https://codeberg.org/api/v1/repos/{owner}/{repo}/releases?limit=50&page=1`
2. Tags (fallback): `https://codeberg.org/api/v1/repos/{owner}/{repo}/tags?limit=50`

**Strategy:** Fetches releases (up to 50). If the releases array is empty or the request fails, falls back to the tags endpoint. Filters out drafts from releases. Pre-releases (based on the `prerelease` field in the JSON) are included in the raw list — channel selection handles filtering.

**Major hint:** Yes.

**Tag flags:** Full pipeline applies.

**No auth required.**

**Version prefix:** Applied after channel selection.

**Cache key:** `codeberg:owner/repo:major_hint:channel`

**Example annotation:**
```bash
# @todo env-update codeberg:gotosocial/gotosocial:0 0.17.3
GLOBAL_STACK_GOTOSOCIAL_VERSION=0.17.3
```

---

### 7.12 pecl

The `pecl` type uses PECL as the authoritative version source. It replaces the old
`pecl-git:owner/repo` pattern for PHP extensions that have stable PECL releases and
optionally a GitHub repo for HEAD SHA tracking.

**Annotation pattern:**
```bash
# @todo env-update (manual) pecl:zmq (git:zeromq/php-zmq) 1.1.3 sha:616b6c64...
GLOBAL_STACK_PHP_DEFAULT_ZMQ_VERSION=

# @todo env-update pecl:imagick 3.8.0
GLOBAL_STACK_PHP_DEFAULT_IMAGICK_VERSION=3.8.0
```

**`(git:owner/repo)` flag (optional):** when set, fetches the HEAD commit SHA from GitHub
after PECL returns the version. HEAD is always used (not the tagged SHA) so the annotation
stays current for PHP master workflows. If the GitHub API is unreachable, the SHA is empty
but the version update is not blocked (soft-fail).

**Decision matrix:**
- PECL has stable release, HEAD SHA fetched → `proposed_version` + `proposed_sha` + `proposed_sha_date`
- PECL has stable release, HEAD unreachable → `proposed_version` only (no SHA)
- No PECL stable release → `decision=ERROR`

**When to use which pattern:**
- `pecl:ext` — extension is on PECL with stable releases, no SHA tracking needed
- `pecl:ext (git:owner/repo)` — extension is on PECL with stable releases + want SHA
- `pecl-git:owner/repo` — no PECL stable releases; git tags are the only source

**API endpoints:**
- `https://pecl.php.net/rest/r/{ext}/allreleases.xml` — all releases XML
- `https://pecl.php.net/rest/r/{ext}/{version}.xml` — per-version details (release date)
- `https://api.github.com/repos/{owner}/{repo}/commits?sha={ref}&per_page=1` — SHA lookup

**XML parsing:** Uses `grep/sed` without `xmllint`. Extracts `<v>VERSION</v><s>STABILITY</s>` pairs.

**Helper functions (also used by `pecl-git`):**
- `_gs_eu2_pecl_get_latest_stable EXT` — returns latest stable PECL version (empty on failure)
- `_gs_eu2_pecl_get_release_date EXT VERSION` — returns YYYY-MM-DD release date
- `_gs_eu2_pecl_check_promotion EXT COMMIT_DATE` — returns the PECL version if its release
  date is strictly newer than `COMMIT_DATE`, otherwise returns empty

**Cache keys:** `pecl2:stable:{ext}` and `pecl2:date:{ext}:{version}` (version cache only; SHA is not cached)

---

## 8. Caching System

### Cache location

Default: `/tmp/global-stack-env-update-cache/`

Override: Set `_GS_EU2_CACHE_DIR` environment variable before sourcing the library, or use
`--cache-ttl` to adjust TTL. The CLI `--cache-ttl` flag populates `_GS_EU2_CFG[cache_ttl]`
which propagates to the `_GS_EU2_CACHE_TTL` env var used by `cache.sh`.

### Cache key to filename

The key-to-file mapping:

```
key = "dockerhub:library/postgres:-alpine3.23:18:stable"
safe = key with [:\/@ ] replaced by _
file = /tmp/global-stack-env-update-cache/dockerhub_library_postgres_-alpine3.23_18_stable.cache
```

Characters replaced: `:`, `/`, `@`, and space → `_`. The result is a flat filename with
`.cache` extension.

### Cache key structure by fetcher

| Fetcher | Cache key format |
|---------|-----------------|
| dockerhub | `dockerhub:namespace:tag_suffix:major_hint:channel` |
| github | `github:owner/repo:major_hint:channel` |
| npm | `npm:package:major_hint:channel` |
| pypi | `pypi:package:major_hint:channel` |
| rubygems | `rubygems:gem:major_hint:channel` |
| quay | `quay:org/image:major_hint:channel` |
| codeberg | `codeberg:owner/repo:major_hint:channel` |
| sdkman | `sdkman:candidate:major_hint:channel` |
| sdkmanager | `sdkmanager:component:channel` |
| pecl-git | `pecl-git3:owner/repo` |
| url | `url:URL:fe_flag:fj_flag:up_flag:channel` |
| pecl (stable) | `pecl2:stable:ext_name` |
| pecl (date) | `pecl2:date:ext_name:version` |

### TTL and expiry

Default TTL: **3600 seconds** (1 hour). The cache uses `stat -c %Y` (Linux) or
`stat -f %m` (macOS) to get the file modification time. If `(now - mtime) > TTL`, the
entry is considered stale and returns a miss. A missing file is also a miss.

Override TTL: `--cache-ttl=N` (seconds). `--cache-ttl=0` treats all entries as expired.

### What is cached

The fetcher's final `proposed_version` string (after pipeline and channel selection). The
cache does NOT store the full decision or error message — only the proposed version.

For `pecl-git`, the cache format is `proposed_version|proposed_sha` (pipe-separated).

### Cache writes in dry-run mode (C4 rule)

When `--dry-run` is active, **no cache writes occur**. This prevents a dry-run from
"priming" the cache with a stale or incorrect result that would then be used by a real run.

### `--no-cache`

When `--no-cache` is active, all cache reads return miss and all cache writes are skipped
for that run. The cache directory is not cleared — existing entries remain valid for future
non-`--no-cache` runs.

### Fixture injection (`_GS_EU2_HTTP_FIXTURE_DIR`)

When `_GS_EU2_HTTP_FIXTURE_DIR` is set, all HTTP GET requests (including authenticated ones)
are served from files in that directory instead of making real network calls. The filename
is derived from the URL using the same sanitization as the cache key:

1. Strip query string from URL
2. Strip leading `https___` protocol prefix
3. Replace all non-alphanumeric characters (except `.`, `-`, `_`) with `_`
4. If the original URL had `page=N` in the query string, append `_page_N` to the filename

This is the single test seam that makes all 12 fetchers deterministically testable.

### Dry-run timestamp marker

After a successful `--dry-run --check` run, a timestamp file is written to
`${_GS_EU2_CACHE_DIR}/last-dry-run-ts`. The `--apply` command checks this file and rejects
the apply if the timestamp is older than 30 minutes (1800 seconds). This prevents the
class of incident where `--apply` is run "cold" without a prior preview.

---

## 9. The Apply Cycle

### Safety rule: always dry-run before apply

```bash
# Step 1: Preview
bin/env-update.sh --check --dry-run

# Step 2: Apply (within 30 minutes of the dry-run)
bin/env-update.sh --apply
```

The `--apply` flag checks for a `last-dry-run-ts` marker in the cache directory. If the
marker is absent or older than 30 minutes, `--apply` exits with:

```
[WARN] --apply requires a recent --dry-run (within 30 min). Run with --dry-run first.
```

This is a hard guard — there is no flag to bypass it. If you need to force an apply (e.g.
after CI cleared the cache dir), run `--dry-run` first.

### What --apply writes

Only `AUTO` decisions are applied. `HOLD`, `MANUAL`, `SKIP`, and `ERROR` decisions are
skipped silently.

For each AUTO record, `_gs_eu2_apply_single` performs an atomic rewrite of the `.env` file
using `awk` + a tempfile + `mv`. It updates two things in one pass:

1. **The variable assignment line** (`VAR=current_value` → `VAR=proposed_version`). Matched
   by `index($0, var "=") == 1` — the variable name must start at column 1.
   - When `use_sha=true` and `proposed_sha` is non-empty, writes `proposed_sha` instead of
     `proposed_version`.

2. **The annotation comment line** (the `@todo env-update` line). Matched by exact string
   equality against `raw_annotation`. The rewrite updates two sub-tokens:
   - The version token: finds `" current_version"` (with a leading space as word boundary)
     and replaces it with `" proposed_version"`.
   - The `sha:` keyword: finds `"sha:current_sha"` and replaces it with `"sha:new_sha"`.

### Backup behavior

Before the first write, a timestamped backup is created:

```bash
cp -a /stack/.env /stack/.env.bak.$(date +%s)
```

If the backup fails (disk full, permissions, etc.), the apply aborts. The backup path is
printed to stderr.

### After apply: propagation

After `--apply` completes, run `bin/env-scan.sh` to propagate the new versions to:
- `.env.local` (sync new values)
- `Dockerfile` `ARG` lines (rewrite `ARG VAR=value` where value differs from `.env`)

Pass `--scan` to do this automatically:
```bash
bin/env-update.sh --apply --scan
```

If `env-scan.sh` fails, a warning is printed but the apply exit code is still 0 (the `.env`
was already updated successfully).

---

## 10. PECL-Git Fetcher — Extended

The `pecl-git` fetcher is the most complex in the system because it tracks PHP extensions
that exist on GitHub but also (potentially) on PECL. It must reason about two independent
version streams and decide which is authoritative.

### Use case

Some PHP extensions are not (yet) officially released on PECL, or their GitHub releases are
ahead of what PECL has published. `pecl-git` tracks the GitHub release tags as the primary
source, but warns when PECL has caught up (suggesting a switch to the simpler `pecl` type).

### Identifier format

`owner/repo` — the GitHub repository (e.g. `krakjoe/parallel`, `arnaud-lb/php-rdkafka`).

Legacy full-URL form (`https://github.com/owner/repo`) is also accepted for backward
compatibility with cached/old annotations.

### PECL extension name derivation

The fetcher automatically derives the PECL extension name from the repo name:
1. Lowercase the repo name
2. Strip `php-` prefix → result is the extension name
3. If no match: strip `php_` prefix
4. If no match: strip `ext-` prefix
5. If no match: use the repo name as-is

If auto-derivation is wrong, migrate the annotation to `pecl:EXT_NAME (git:owner/repo)` where `EXT_NAME` is the correct PECL extension name.

Examples:
- `php-event` → `event`
- `php_rdkafka` → `rdkafka`
- `ext-swoole` → `swoole`
- `parallel` → `parallel` (no prefix to strip)

### GitHub fetch strategy

1. **Releases API** (up to 100 results per call, no pagination for pecl-git).
2. **Tags API fallback** (3 pages max, 100 per page).
3. **ERROR** if both return nothing — includes a hint to use `(use-sha)` for manual pinning.

### Tag processing

1. Strip `v`-prefix from each tag.
2. Apply `tag_strip_prefix` from the record (if set).
3. **Stable filter** (when current version is stable): discard any candidate that
   `_gs_eu2_is_prerelease` identifies as a prerelease (e.g. `6.3.0RC1`, `6.3.0-beta2`).
   This prevents `sort -V` from picking a release-candidate over a stable release.
   If all candidates are prerelease (unusual), the filter is bypassed to avoid empty result.
   Skipped when current version is itself a prerelease.
4. Filter by `major_hint` (exact first-segment match: `${tag%%.*} == major_hint`).
5. Sort with `sort -V`, take the highest.

### SHA lookup

After selecting the best version tag, the fetcher calls:
```
GET https://api.github.com/repos/{owner}/{repo}/commits?sha=v{version}&per_page=1
```
(tries `v`-prefixed first, then bare version tag).

The returned full SHA is stored in `proposed_sha`.

### Commit date

After SHA lookup, fetches:
```
GET https://api.github.com/repos/{owner}/{repo}/commits/{sha}
```
Extracts `.commit.author.date` (ISO8601), trims to `YYYY-MM-DD`. Stored in `commit_date`
(hint only — never written to `.env` by `--apply`).

### PECL promotion check

After getting the commit date, calls `_gs_eu2_pecl_check_promotion`:
- Fetches latest stable PECL version for the extension.
- Fetches the PECL release date for that version.
- If PECL release date > commit date (lexicographic YYYY-MM-DD comparison): the PECL
  release is newer than the git commit → sets `alt_version` to:
  `"PECL stable available: VERSION — consider switching to pecl:EXTNAME"`

This signals that the extension has caught up on PECL and the annotation could be simplified
from `pecl-git:owner/repo` to `pecl:extension-name`.

### Cache format

`pecl-git3:owner/repo` → `proposed_version|proposed_sha`

The `3` in the key prefix was bumped to invalidate stale values from prior versions that
stored a `YYYYMMDD-sha8` compound format.

### `use-sha` mode

When `(use-sha)` is set:
- `proposed_version` is still computed and displayed in `--check` output.
- But `--apply` writes `proposed_sha` to `VAR=` instead of `proposed_version`.
- Both the annotation version token and the `sha:` keyword in the annotation are updated.

Use this for variables that track a commit SHA (e.g. when a Docker image is pinned to a
specific commit rather than a semver tag).

### Example annotations

```bash
# Standard semver tracking
# @todo env-update pecl-git:krakjoe/parallel 1.2.2
GLOBAL_STACK_PHP_PARALLEL_VERSION=1.2.2

# For extensions where name auto-derivation works: use pecl: type instead
# @todo env-update pecl:event (git:mkoppanen/php-event) 3.1.4
GLOBAL_STACK_PHP_EVENT_VERSION=3.1.4

# SHA tracking (variable stores a commit SHA)
# @todo env-update (use-sha) pecl-git:owner/ext sha:abc123... 1.0.0
GLOBAL_STACK_EXT_SHA=abc123def456...
```

---

## 11. Multi-Variable Patterns

Some services require multiple related variables that must be updated together.

### Docker images with tag suffixes (Alpine, OracleLinux, etc.)

The stored version includes the suffix, but the comparison must work without it:

```bash
# @todo env-update (tag-suffix:-alpine3.23) (tag-strip-suffix:-alpine3.23) dockerhub:_/postgres:18 18.3
GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23
```

Wait — `current_version` in the annotation is `18.3` (without suffix), but `VAR=18.3-alpine3.23`
(with suffix). When the annotation version differs from the VAR value, the annotation version
takes precedence. So `current_version=18.3` and `proposed` will also be without the suffix.
The `tag-suffix` flag ensures only `-alpine3.23` tagged versions are fetched.

Alternatively, with `version-prefix` / `tag-strip-suffix` approach:

```bash
# @todo env-update (tag-suffix:-alpine3.23) dockerhub:_/postgres:18 18.3-alpine3.23
GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23
```

Here `current_version=18.3-alpine3.23` (from the annotation), and the proposed version
will also include the suffix (since `tag-strip-suffix` is not applied — the suffix is kept
in the raw tag name, filtered only to tags ending with that suffix).

### PHP companion variables

PHP uses three variables per version series:

```bash
# @todo env-update github:php/php-src:8.2 8.2.28
GLOBAL_STACK_PHP82_VERSION=8.2.28

# These companions must be updated manually after updating PHP82_VERSION:
GLOBAL_STACK_PHP82_VERSION_NAME=php-8.2.28      # For configure --with-php-config
GLOBAL_STACK_PHP82_VERSION_AS=8.2               # For phpbrew install
```

The companion variables (`VERSION_NAME`, `VERSION_AS`) have no `@todo env-update`
annotation — they are derived and must be updated manually (or via a post-apply hook).

### Ruby underscore-format tags

Ruby releases use underscore separators in GitHub tags (`v3_4_9`). The tag-replace flag
converts them to dots for semver comparison:

```bash
# @todo env-update (tag-strip-prefix:v) (tag-replace:_:.) (version-prefix:v) github:ruby/ruby:3 3.4.9
GLOBAL_STACK_RUBY3_VERSION=v3.4.9
```

Pipeline:
1. Raw tag from GitHub: `v3_4_9`
2. `tag-strip-prefix:v` → `3_4_9`
3. `tag-replace:_:.` → `3.4.9`
4. Channel select: `3.4.9`
5. `version-prefix:v` → `v3.4.9`

The `semver_delta` function also normalizes `_` to `.` for comparison purposes (independent
of the tag pipeline).

### Maven dotted major hints (D1 fix)

Maven releases use a 3-component version but may be pinned to a minor series:

```bash
# @todo env-update sdkman:maven:3.9 3.9.9
GLOBAL_STACK_MAVEN_VERSION=3.9.9
```

The `major_hint=3.9` is a dotted hint. The parser accepts it (matches `^[0-9]+(\.[0-9]+)*$`).
The decision engine checks `^3.9([.^_-]|$)` — so `3.9.10` matches and `3.10.0` does not.

### BuildKit v-prefixed versions

```bash
# @todo env-update (tag-strip-prefix:v) (version-prefix:v) dockerhub:moby/buildkit v0.20.2
GLOBAL_STACK_BUILDX_VERSION=v0.20.2
```

Strip `v` for clean semver comparison, restore it so the variable keeps `v0.20.2`.

---

## 12. Error Reference

### Parser errors (exit 1 immediately)

These errors abort the tool on the first bad annotation. The format is:
```
env-update: FILE:LINE: MESSAGE
```

| Error message | Cause | Fix |
|--------------|-------|-----|
| `unknown flag "NAME" in annotation` | A `(flagname)` or `(flagname:val)` token whose name is not in the recognized flag set. | Check spelling of the flag name. |
| `flag "NAME" requires a non-empty value` | A valued flag like `(channel:)` with empty value after the colon. | Add a value: `(channel:stable)`. |
| `flag tag-replace requires FROM:TO format` | `(tag-replace:ONETHING)` — no second colon separator. | Use `(tag-replace:FROM:TO)`. |
| `malformed depends-on — expected VAR:constraint, got "..."` | `(depends-on:JUST_A_VAR)` — no constraint after colon. | Use `(depends-on:VAR:major)`. |
| `annotation has no TYPE:IDENTIFIER (got: "...")` | The annotation line has no recognizable `type:identifier` token. | Add the type and identifier: `dockerhub:_/image`. |
| `duplicate @todo env-update before assignment (previous at line N)` | Two `@todo env-update` annotations in a row without a variable assignment between them. | Remove the duplicate or add the missing `VAR=value` line. |
| `annotation not followed by variable assignment (got: LINE)` | A non-blank, non-comment, non-assignment line appeared after the annotation. | Ensure the next non-comment line is `VAR=value`. |

### Fetch errors (set decision=ERROR, continue)

These do not abort the tool — they set `decision=ERROR` and move to the next record.

| Error message | Cause | Fix |
|--------------|-------|-----|
| `fetch failed for TYPE:IDENTIFIER` | HTTP error (4xx/5xx) or curl failure. | Check network, rate limits, auth token. |
| `fetch failed for github:REPO (set GITHUB_TOKEN...)` | GitHub API rate limit without token (HTTP 403/429). | Set `GITHUB_TOKEN` or `GLOBAL_STACK_GITHUB_TOKEN` in the environment. |
| `no tags or releases found for github:REPO` | GitHub API returned empty releases and empty tags. | Check that the repo exists and has releases/tags. |
| `no tags returned for TYPE:IDENTIFIER` | API returned HTTP 200 but empty tag list. | Verify the identifier is correct. |
| `rate-limited by URL after 3 attempts — try again later` | HTTP 429 persisted through 3 retry attempts with exponential backoff. | Wait and retry; set `GITHUB_TOKEN` for GitHub. |
| `pecl-git: cannot extract owner/repo from 'IDENTIFIER'` | The identifier is neither `owner/repo` nor a full `github.com/owner/repo` URL. | Use the `owner/repo` format. |
| `pecl-git: no release tags found for 'REPO'; pin manually with (use-sha)` | The GitHub repo has no releases and no tags, or all failed auth. | Use `(use-sha)` and pin to a commit SHA manually. |

### SKIP conditions (not errors — no message or informational)

| Condition | Message |
|-----------|---------|
| Current version is a floating reference | `floating reference (nightly) — pin manually to adopt proposed version` |
| All tags filtered out (major-pin, tag-filter, etc.) and current version is pre-release | `no tags matched filters for TYPE:IDENTIFIER` |
| Channel selection returned nothing and current version is pre-release | `channel selection returned nothing for TYPE:IDENTIFIER` |
| sdkman not installed | `sdkman not installed (SDKMAN_DIR=PATH)` |
| sdkmanager not found | `sdkmanager not found` |

> **Note:** When the `github` fetcher hits a "no tags matched" or "channel selection returned nothing" condition and the current version is **stable** (not pre-release), it escalates to `ERROR` instead of `SKIP`. The reasoning: a stable current version proves stable releases exist — failing to find any is a fetcher failure, not a legitimate no-stable-releases scenario.
| url: no tier matched | `url: no extraction strategy matched for URL` |
| url: fetch-extract matched nothing | `url: fetch-extract pattern 'REGEX' matched nothing from URL` |
| url: fetch-json returned empty | `url: fetch-json jq path 'PATH' returned empty from URL` |
| No versioned tags available | `no versioned tags available for TYPE:IDENTIFIER` |
| Proposed == current | *(no message — displayed as "(up to date)")* |

### CLI flag errors (exit 1 immediately, no FILE:LINE prefix)

| Error | Cause |
|-------|-------|
| `env-update: --dry-run and --apply are mutually exclusive` | Both flags given simultaneously. |
| `env-update: --dump is mutually exclusive with --check and --apply` | `--dump` combined with action flags. |
| `env-update: --cache-ttl requires a positive integer, got: VALUE` | Non-numeric value after `--cache-ttl=`. |
| `env-update: unknown option: --OPTION` | Unrecognized CLI flag. |
| `env-update: env file not found: PATH` | The `--env-file` path does not exist. |
| `env-update: unknown --format value: VALUE (valid: text, json)` | Invalid value for `--format`. |
| `[WARN] --apply requires a recent --dry-run (within 30 min). Run with --dry-run first.` | `--apply` attempted without a recent `--dry-run`. |

---

## 13. Testing and Development

### Running the test suite

```bash
bash bin/tests/env-update.test.sh
```

The test suite runs 216+ tests across 38 sections covering: lexer, parsing, flag dispatch,
HTTP seam, all 12 fetchers, cache, channel selection, tag flags, semver, decision classifier,
apply logic, and error paths.

Output format: sections with pass/fail counts per section, and a final summary. Color output
when running in a terminal.

### Fixture-based testing

All fetcher tests use the HTTP fixture seam (`_GS_EU2_HTTP_FIXTURE_DIR`). When set, no real
network calls are made — all `_gs_eu2_http_get` calls read from files in that directory
instead.

**Fixture directory:** `bin/tests/fixtures/env-update/http/`

**Fixture filename derivation** (same logic as `_gs_eu2_fixture_path` in `curl.sh`):
1. Strip the query string from the URL.
2. Strip the leading `https___` protocol prefix.
3. Replace all characters that are not `a-zA-Z0-9._-` with `_`.
4. If the original URL had `page=N` in the query string, append `_page_N`.

Examples:
- `https://registry.hub.docker.com/v2/repositories/library/postgres/tags?page_size=100&ordering=last_updated`
  → strip query → `https://registry.hub.docker.com/v2/repositories/library/postgres/tags`
  → strip protocol → `registry.hub.docker.com_v2_repositories_library_postgres_tags`

- `https://api.github.com/repos/testowner/underscore-repo/releases`
  → `api.github.com_repos_testowner_underscore-repo_releases`

The paginated fixture disambiguation: for `page=2`, the filename gets `_page_2` appended:
- `https://api.github.com/repos/owner/repo/tags?per_page=100&page=2`
  → `api.github.com_repos_owner_repo_tags_page_2`

### Fixture file format

Fixture files must contain the exact response body that the real API would return. For JSON
APIs, this is the full JSON object/array. For Docker Hub, it is the paginated response
including `next` and `results[].name`. For SDKMAN text responses, it is the raw text table.
For PECL XML, it is the raw XML document.

### Writing a new test

Tests use the `t "label" bash -c "..."` pattern with a `PASS` or `FAIL` sentinel on the
last line:

```bash
t "my test — describes what it tests" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/my_test_cache
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    source '/stack/bin/lib/env-update/core/cache.sh'
    source '/stack/bin/lib/env-update/http/curl.sh'
    source '/stack/bin/lib/env-update/fetchers/myfetcher.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'myfetcher'
    _gs_eu2_record_set \$idx identifier 'owner/repo'
    _gs_eu2_record_set \$idx env_var    'MY_VAR'
    _gs_eu2_fetch_myfetcher \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.2.3' ]] || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"
```

Always use a fresh `_GS_EU2_CACHE_DIR` (a subdirectory of `${TMP_DIR}`) per test to
prevent cache pollution between tests.

### Adding a new fetcher

All 12 fetcher types are implemented. To add a hypothetical 13th:

1. Create `bin/lib/env-update/fetchers/{type}.sh` with an include guard and a main function
   `_gs_eu2_fetch_{type}() { local _idx="${1}"; ... }`.

2. The function contract:
   - Read all needed record fields via `_gs_eu2_record_get "${_idx}" FIELD`.
   - On success: call `_gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"`. Leave `decision` empty — `decide.sh` will classify.
   - On hard failure: call `_gs_eu2_record_set "${_idx}" decision "ERROR"` and `_gs_eu2_record_set "${_idx}" error_message "..."`.
   - On soft failure (no match): set `error_message` and return (decide.sh will SKIP since proposed_version is empty).
   - Implement cache: read at start, write at end, respect `_GS_EU2_CFG[no_cache]`.

3. Add a `source` line in `main.sh`.

4. Add a `case` arm in `_gs_eu2_run_check()` in `main.sh`:
   ```bash
   newtype) _gs_eu2_fetch_newtype "${_i}" ;;
   ```

5. Create HTTP fixtures for the test suite.

6. Add a test section to `bin/tests/env-update.test.sh`.

### Adding a new record field

1. Add the field name to `_gs_eu2_record_fields()` in `core/records.sh`.
2. Handle it in `core/parse.sh` (dispatch in `_gs_eu2_dispatch_flag` or handle as a
   non-paren keyword like `urls:` or `sha:`).
3. Add `_gs_eu2_record_set "${_idx}" newfield "..."` calls wherever the field is populated.
4. Write a test that checks the field appears correctly in `--dump` output.

No accessor refactor needed — the record model is flat and fully data-driven via `printf -v`
and indirect variable references.

### Offline testing with cached responses

For manual debugging without network access:

```bash
# Run once with network to populate cache
bin/env-update.sh --check --filter=POSTGRES

# Subsequently: use cache (TTL 3600s)
bin/env-update.sh --check --filter=POSTGRES

# Force cache-only (simulate --offline behavior by setting TTL high)
export _GS_EU2_CACHE_TTL=86400
bin/env-update.sh --check --filter=POSTGRES
```

> **NOTE:** `--offline` is listed in some early documentation but is **not implemented** in
> v2.0.0. There is no `--offline` flag. Use the fixture seam for deterministic offline
> testing in CI.
