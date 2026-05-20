#!/bin/bash
# help.sh — usage text

[[ -n "${_GS_EU2_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_HELP_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_gs_eu2_show_help() {
  cat << EOF
bin/env-update.sh v${_GS_EU2_VERSION} — annotation parser + version checker (11 fetcher types)

Usage: env-update.sh [OPTIONS]

Options:
  --version               Print version and exit
  --help                  Show this help and exit
  --annotations           Print a structured reference of all supported annotation
                          flags, fetcher types, and inline syntax, then exit.
  --env-file=<path>       Source .env file (default: /stack/.env)
  --filter=<regex>        Only parse records whose env_var matches regex
  --exclude=<regex>       Skip records whose env_var matches regex. Composable
                          with --filter: --filter=NODE --exclude=NODEEDGE means
                          all Node vars except NODEEDGE. Empty value is a no-op.
  --dump                  Emit parsed records to stdout
  --format=<text|json>    Dump format (default: text)
  --check                 Fetch latest versions and stream [AUTO|HOLD|SKIP|ERROR] report
  --apply                 Apply all AUTO decisions to the env file; implies --check.
                          Creates a timestamped .env backup before writing.
                          Use with --dry-run to preview without writing.
  --scan                  After --apply, run bin/env-scan.sh to propagate changes to
                          .env.local and Dockerfiles. Off by default.
  --no-cache              Bypass the fetch cache
  --cache-ttl=<seconds>   Cache TTL in seconds (default: 3600)
  --dry-run               No writes (gates cache, .env, and Dockerfile propagation).
  --with-tags             Force tags-API merge for ALL github: repos in one run.
                          Equivalent to adding (check-tags) to every annotation.
  --unstable / --unstable=full
                          Force channel=unstable on all stable/default records.
                          Fetchers return the highest prerelease; if stable has
                          surpassed the highest prerelease, stable is returned
                          instead (promotion guard). The prerelease guard in
                          decide.sh is bypassed: stable→prerelease classifies
                          as AUTO. (manual) and (hold) still apply.
  --unstable=info         Informational only — after each fetch, shows the latest
                          prerelease as a "↳ [UNSTABLE] unstable: <version>" sub-line.
                          Does not change AUTO/HOLD/SKIP logic.
  --stable / --stable=full        Force channel=stable on all records with a non-stable
                                  channel (rc, beta, alpha, nightly, unstable → stable).
                                  Records already on stable/default are unchanged.
                                  Mutually exclusive with --unstable=full only.
  --stable=info                   Informational only — after each fetch, shows the stable
                                  version as a "↳ [STABLE] stable: <version>" sub-line for
                                  records on non-stable channels. Does not change decisions.
                                  Compatible with --unstable=full (shown below main line).
  --no-notes                      Suppress annotation (note: TEXT) sub-lines — for minimal
                                  output. Does NOT suppress SHA, [UNSTABLE], [STABLE],
                                  [DRIFT], or [PIN-MISS] sub-lines.
  --no-drift                      Suppress [DRIFT] sub-lines — emitted when the VAR= value
                                  in the env file differs from what the annotation claims as
                                  current. Does NOT affect (note:TEXT) or other sub-lines.
  --changes-only                  Hide purely up-to-date records (SKIP + no signals) from
                                  output. A record is hidden only when: decision=SKIP
                                  (genuine up-to-date), no [DRIFT], no [WATCH], no
                                  [FALLBACK], no [UNSTABLE]/[STABLE] info sub-lines.
                                  (note:TEXT) records are still hidden — notes are metadata,
                                  not signals. (skip:REASON) and (lock:REASON) records are
                                  always visible. Summary counts all checked records; adds
                                  "(N hidden)" when any records are suppressed.
  --no-fail                       Always exit 0, even when ERROR decisions are present.
                                  Useful in pipeline scripts where you want the output
                                  without letting fetch failures abort the pipeline.
                                  Scope: only ERROR fetch decisions are suppressed. Usage
                                  errors (bad flags, bad env file), backup failures during
                                  --apply, and env-file-not-found remain fatal. When errors
                                  are suppressed a stderr notice is printed:
                                  "[NO-FAIL] fetch errors present — exit code forced to 0"
                                  Note: with --apply --no-fail, AUTO decisions are still
                                  applied even when some records have ERROR.
                                  Note: with --scan --no-fail, the --no-fail flag is passed
                                  through to env-scan.sh (suppresses its propagation errors too).
  Backup (--apply only — ignored with --dry-run):
  --backup=<true|false>           Create a timestamped backup before applying changes.
                                  (default: true). Pass --backup=false to skip.
  --backup-keep=<N>               Keep the N newest backup files; delete older ones.
                                  0 = keep all (no pruning). (default: 10)
  --backup-purge=<true|false>     Delete ALL existing backups matching the backup pattern
                                  BEFORE creating the new backup. (default: false)
  --backup-suffix=<str>           Suffix anchor for backup filenames; full name is
                                  <file><suffix>.<YYYYMMDD-HHMMSS-PID>. (default: .bak)

  --force-auto                    Override (manual) and (override) annotation flags and HOLD
                                  decisions — treats them as AUTO-eligible. Useful for
                                  scripted environments where human gates are not appropriate.
                                  NOTE: (lock:REASON) and (skip:REASON) annotation flags are
                                  immune to --force-auto — they cannot be overridden. The
                                  (manual) flag CAN be overridden; the annotation text is NOT
                                  rewritten. (lock:REASON) cannot be overridden at all;
                                  annotation-only updates via --apply still work for locked
                                  records (version bump without --force-auto).
                                  When used with --apply, requires --confirm="Confirm override"
                                  to proceed (safety gate — prevents accidental use).
  --confirm=TEXT                  Confirmation string required by --force-auto --apply.
                                  Must be exactly: Confirm override
  --profile                       Show phase timing and memory usage table after run
                                  (default: false). Phases: Parse args, Parse env file,
                                  Fetch + classify, Apply (when --apply), env-scan
                                  (when --apply --scan).

Default (no flags): print a parser summary with per-type breakdown and hints.

Summary line format (shown after --check):
  Summary: N AUTO, N SHA, N HOLD, N MANUAL, N LOCK, N SKIP, N FROZEN, N FALLBACK, N ERROR  (N checked)
    ↳ N WATCH · N DRIFT (N fixable) · N DOWNGRADE · N +sha

  FALLBACK   — records that fell back to LOW major (range annotation, HIGH not yet in registry).
               Overlay counter: the record is also counted as AUTO or SKIP; not added to total.
  The secondary ↳ line is omitted when all four signals are zero.
  WATCH      — new runtime generation detected (watch-major annotation).
  DRIFT      — VAR= in the env file differs from the annotation's current version.
               (N fixable): how many DRIFT records are on AUTO, HOLD, MANUAL, or SHA decisions
               (--apply or --force-auto --apply can resolve them).
  DOWNGRADE  — subset of DRIFT: VAR= is ahead of annotation (downgrade risk). Not fixable.
  +sha       — AUTO or MANUAL decisions that also carry a sha annotation update (↳ sha: sub-line).
               Pure SHA decisions are excluded (already counted in the primary SHA counter).
  --no-drift suppresses DRIFT and DOWNGRADE from the secondary line; WATCH and +sha are unaffected.

Fetcher types: dockerhub, github, npm, pecl, pypi, quay, rubygems,
sdkman, sdkmanager, url, codeberg.
pecl supports an optional (git:owner/repo) flag for HEAD SHA tracking.
pecl and sdkmanager do not support major_hint filtering; range syntax is
unsupported for those types.

Major range annotation: TYPE:IDENTIFIER:LOW-HIGH (e.g. npm:@types/node:25-26)
  LOW  = fallback major — used when HIGH has no versions yet.
  HIGH = desired major — used as soon as any version in that major ships.
  LOW must be < HIGH (parse-time validation; dotted ranges not supported).
  When running on LOW because HIGH is unavailable, a [FALLBACK] sub-line is
  emitted (not suppressed by --no-notes). Once HIGH versions appear, the
  fetcher automatically promotes to them and [FALLBACK] disappears.

Examples:
  bin/env-update.sh                                # parser summary (no network)
  bin/env-update.sh --check                        # fetch all, stream report
  bin/env-update.sh --check --filter=POSTGRES      # fetch only POSTGRES* vars
  bin/env-update.sh --check --filter=NODE --exclude=NODEEDGE  # Node vars except NODEEDGE
  bin/env-update.sh --check --no-cache             # bypass cache
  bin/env-update.sh --dump --format=json | jq .    # structured record dump
  bin/env-update.sh --check --apply                # fetch + apply all AUTO updates
  bin/env-update.sh --check --apply --scan         # apply + propagate to .env.local + Dockerfiles
  bin/env-update.sh --check --apply --dry-run      # preview what would be applied
  bin/env-update.sh --check --with-tags            # audit all github repos including tag-only releases
  bin/env-update.sh --unstable --check             # force unstable: propose prereleases globally as AUTO
  bin/env-update.sh --unstable=info --check        # info mode: show unstable sub-line without changing decisions
  bin/env-update.sh --stable --check               # force stable: see stable versions for all rc/beta/nightly vars
  bin/env-update.sh --stable --check --dry-run     # preview stable-forced output without writing
  bin/env-update.sh --stable=info --check          # info mode: show stable sub-line for non-stable-channel records
  bin/env-update.sh --stable=info --unstable=full --check  # unstable decisions + stable sub-line for each
  bin/env-update.sh --check --no-notes                    # suppress (note: ...) sub-lines
  bin/env-update.sh --check --no-drift                    # suppress [DRIFT] sub-lines
  bin/env-update.sh --check --changes-only                # hide up-to-date records; show only actionable/informational
  bin/env-update.sh --check --no-fail                     # always exit 0 even if some fetchers error
  bin/env-update.sh --check --force-auto                  # preview: (manual)/(hold) treated as AUTO
  bin/env-update.sh --apply --force-auto --confirm="Confirm override"  # apply with force-auto
  bin/env-update.sh --apply --backup=false                            # apply without backup
  bin/env-update.sh --apply --backup-keep=3                           # keep only 3 newest backups
  bin/env-update.sh --apply --backup-purge=true                       # purge old backups then create new
  bin/env-update.sh --apply --backup-suffix=.snap                     # custom backup suffix

  bin/env-update.sh --annotations                                     # print annotation syntax reference

Tip: run --annotations to see all supported annotation flags, fetcher types, and inline syntax.
EOF
}
