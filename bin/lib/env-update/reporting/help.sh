#!/bin/bash
# help.sh — usage text

[[ -n "${_GS_EU2_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_HELP_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_gs_eu2_show_help() {
  cat << EOF
bin/env-update.sh v${_GS_EU2_VERSION} — annotation parser + version checker (12 fetcher types)

Usage: env-update.sh [OPTIONS]

Options:
  --version               Print version and exit
  --help                  Show this help and exit
  --env-file=<path>       Source .env file (default: /stack/.env)
  --filter=<regex>        Only parse records whose env_var matches regex
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
  --with-tags             Force tags-API merge for ALL github: and pecl-git: repos in
                          one run. Equivalent to adding (check-tags) to every annotation.
  --unstable / --unstable=full
                          Force channel=unstable on all stable/default records.
                          Fetchers return the highest prerelease. The prerelease
                          guard in decide.sh is bypassed: stable→prerelease
                          classifies as AUTO. (manual) and (hold) still apply.
  --unstable=info         Informational only — after each fetch, shows the latest
                          prerelease as a "↳ [INFO] unstable: <version>" sub-line.
                          Does not change AUTO/HOLD/SKIP logic.
  --stable                Force channel=stable on all records with a non-stable
                          channel (rc, beta, alpha, nightly, unstable). Records
                          already on stable/default are unchanged. Mutually
                          exclusive with --unstable.

Default (no flags): print a parser summary with per-type breakdown and hints.

Fetcher types: dockerhub, github, npm, pecl, pecl-git, pypi, quay, rubygems,
sdkman, sdkmanager, url, codeberg.

Examples:
  bin/env-update.sh                                # parser summary (no network)
  bin/env-update.sh --check                        # fetch all, stream report
  bin/env-update.sh --check --filter=POSTGRES      # fetch only POSTGRES* vars
  bin/env-update.sh --check --no-cache             # bypass cache
  bin/env-update.sh --dump --format=json | jq .    # structured record dump
  bin/env-update.sh --check --apply                # fetch + apply all AUTO updates
  bin/env-update.sh --check --apply --scan         # apply + propagate to .env.local + Dockerfiles
  bin/env-update.sh --check --apply --dry-run      # preview what would be applied
  bin/env-update.sh --check --with-tags            # audit all github/pecl-git repos including tag-only releases
  bin/env-update.sh --unstable --check             # force unstable: propose prereleases globally as AUTO
  bin/env-update.sh --unstable=info --check        # info mode: show unstable sub-line without changing decisions
  bin/env-update.sh --stable --check               # force stable: see stable versions for all rc/beta/nightly vars
  bin/env-update.sh --stable --check --dry-run     # preview stable-forced output without writing
EOF
}
