---
paths:
  - "Makefile"
  - "bin/git-strip-coauthored.sh"
  - "bin/check-bake-targets.sh"
  - "bin/check-image-versions.sh"
  - "bin/local-registry.sh"
  - "bin/tests/local-registry.test.sh"
  - "templates/shell/global-stack-make-exec.sh"
  - "bin/open-all-envs.sh"
  - "templates/tips/open-many-links.md"
  - ".claude/hooks/env-guard-on-write.sh"
  - "templates/shell/profile.sh"
  - "templates/shell/shell.shellrc"
  - "bin/tests/git-strip-coauthored.test.sh"
  - "bin/tests/makefile-posix.test.sh"
  - "bin/tests/check-bake-targets.test.sh"
  - "bin/tests/check-image-versions.test.sh"
  - "bin/tests/wait-healthy.test.sh"
  - "bin/tests/open-all-envs.test.sh"
  - "bin/tests/env-guard.test.sh"
  - "bin/tests/profile-shell.test.sh"
  - "bin/tests/claude-fullauto-shell.test.sh"
---

# Host-side tooling — small test suites and the scripts they cover

Split out of `CLAUDE.md` by `/rules-split` on 2026-10-09: the text below is unchanged except for cross-references and line citations, and each entry keeps a one-line index entry in `CLAUDE.md`. A new lesson about these files belongs HERE, not in `CLAUDE.md`.

## From CLAUDE.md § Testing & Verification

- **local registry lifecycle tests**: `bash bin/tests/local-registry.test.sh` (`docs/plans/local-registry-lifecycle.plan.md`). The incident on 2026-11-07 went like this:
  - `make soft-restart`'s host-wide `docker ps -q | xargs -r docker stop` stopped the registry. That line was borrowed from hard-restart, where it exists for the prune (664b215).
  - `--restart=always` does not revive an explicitly stopped container while the daemon stays up, so nothing started it again.
  - The stack came up on its local images, so the registry looked fine until the next `global-stack-start.sh` failed in buildkit with `connection refused`.
  - The wrapper's `--ignore-errors --keep-going` swallowed `make build`'s FATAL registry gate and exited 0.

  What the suite covers:
  - `bin/local-registry.sh ensure` for every container state. It never generates a cert: the buildx builder image COPYs it, so a rotation without `create-buildx-builder` breaks trust.
  - The `create` `docker run` contract.
  - The `container ls` query itself: the stub answers like real docker (no `--all` hides a stopped container; another `--format` gives Status text). Panel round 1 found a stub that ignored its arguments, where dropping `--all` stayed green.
  - curl's exit code: 6 (the alias does not resolve, i.e. no `/etc/hosts` entry) must yield an `/etc/hosts` hint, never a rotation, since a rotation restarts the daemon and fixes nothing.
  - The Makefile wiring. `up` has the ensure prerequisite; every down-n-* composite runs ensure FIRST (before `down`); soft-restart's order is guard on an empty tools path → ensure → `down` → scoped stop → `rm` → `up`; `start-local-registry` checks the alias resolves (`getent hosts`) before any cert, root or daemon step; both curl probes are bounded.
  - Panel round 3 added three executed cases: a failing `buildx bake --print` must not strand `down-n-up` (`up` has no `generate-buildx` prerequisite: its first line deletes the bake file); under `MAKEFLAGS=-j4` no `down` runs when ensure fails (the Makefile is `.NOTPARALLEL`, since prerequisite order holds only for serial make and `.WAIT` errors before GNU make 4.4); an EMPTY alias fails the `getent` check. That last case needs the stub `getent` to answer like glibc: no key enumerates the database and exits 0, while an empty key exits 2. An unquoted operand turns the empty alias into the no-key form.
  - Panel round 4 added further cases:
    - **An unparseable compose project** (stub `compose-fails`) must stop `make up`, the down-n-* composites and soft-restart BEFORE any `down`, with "does not parse". That is the job of `check-compose`, a strict `config -q` through make.
    - **The dead and silent-registry hints** must offer `docker rm -f <name> && make ensure-local-registry` before the rotation. The probe is `curl -k`, so trust cannot silence the registry, and only a cert/key mismatch needs a rotation.
    - **An empty alias** must name the missing `.env.local`, not tell you to add `127.0.0.1 ` to `/etc/hosts`.
  - The wrapper stopping on the first failure.
  - End to end, the wrapper drives a sandbox copy of the real Makefile against a stub `docker`: the incident replay, `down-n-up` healing a stopped registry, an EXECUTED `soft-restart` (the stub `sudo` allows exactly `rm -rf tools` inside the sandbox), the no-teardown guarantees (a dead registry: no `compose … down`, no stop, no `rm`), and `start-local-registry` with an unresolved alias (a stub `getent`): no openssl, root or `docker rm` call. Panel round 2 found that grep-only checks let a `-` recipe prefix or `-i` through; only the executed cases catch those.

  The stubs for `sudo`/`systemctl`/`openssl req` FAIL the case if called. Every run is under `env -i`, because an interactive `/stack` shell exports `.env.local`. The e2e `.env.local` keeps the registry ALIAS **nested**, so the case proves that make resolves it for the script.

- **git-strip-coauthored tests**: `bash bin/tests/git-strip-coauthored.test.sh` — 27 tests. Argument handling is a safety surface here: the script's only job is an irreversible `git filter-repo --force`, so every path reaching the rewrite must be one the caller asked for. Runs against a throwaway repo with a stub `git-filter-repo` on PATH — it can never touch real history
- **Makefile portability tests**: `bash bin/tests/makefile-posix.test.sh`. Recipes run under `/bin/sh` (dash) because the Makefile never sets `SHELL`, so `source` (exit 127, and the rest of an `&&` line never runs) and `&>` (backgrounds instead of silencing) are fatal in recipes. Also asserts every `make <target>` named in a recipe message actually exists, reading the target list from make's own database so `$(eval $(call ...))` targets count
- **bake-target gate tests**: `bash bin/tests/check-bake-targets.test.sh` — 12 tests for `bin/check-bake-targets.sh`, the fatal preflight that stops `make build` printing "Build complete" when the bake file yields zero targets. Unlike `check-image-versions.sh` it is NOT called with `|| true`
- **image-version preflight tests**: `bash bin/tests/check-image-versions.test.sh` — 30 tests. The script compares the ACTIVE env file (`.env.local` when present, else `.env` — `make up` builds from `.env.local`, so comparing canonical `.env` reports drift the build never sees) against each Dockerfile `ARG`. Its characteristic failure is vacuity: a service that cannot be compared is now named rather than skipped, and an aggregate fires when candidates existed and none could be compared. That aggregate is gated on *candidates*, not Dockerfile count — a tree of purely internal `FROM ${GLOBAL_STACK_VERSION}` services legitimately compares nothing. Case 14 asserts the committed mode is `100755`, which `core.fileMode=false` would otherwise let rot
- **wait-healthy tests**: `bash bin/tests/wait-healthy.test.sh` — 9 checks on the `wait-healthy` Makefile target, in a copy-to-tempdir sandbox with a stub `docker` (so `tools/errors/` resolves inside the sandbox, not the real tree). With the stack down the target used to print "Stack settled: 0 healthy, 0 failed" and exit 0; it now counts containers first. Three of the nine guard the other direction — one drives `starting` → `healthy` and asserts the ~10s settle cycle really happened, so the run takes ~15s
- **open-all-envs tests**: `bash bin/tests/open-all-envs.test.sh` — 22 checks (row 46). Its `android` stub rejects a `--sdk` placed after the subcommand, as the real CLI does, and an `androidsdk:` annotation must open no URL. Runs the script under `env -i` with a stub browser and a temp `HOME`, so no case can touch the real `~/.sdkman`. Covers `.env` resolution from a foreign cwd, the zero-link failure, byte-identical survival of `~/.sdkman/etc/config` (including after a Ctrl-C), and the byte-identical pairing with `templates/tips/open-many-links.md` (script line N → doc line N+7). The interrupt case must raise `kill -INT 0` under `setsid -w`: a SIGINT from inside a pipeline is swallowed
- **env-guard hook tests**: `bash bin/tests/env-guard.test.sh` — 12 checks on `.claude/hooks/env-guard-on-write.sh`. The port check is **consumer-keyed**: it warns only when some `docker/images/*/docker-compose.yaml` writes `${VAR:-}` immediately followed by a digit. Requires `jq` (the hook exits 0 without it and every case would be vacuous)
- **Host shell template tests**: `bash bin/tests/profile-shell.test.sh` — 13 checks that `templates/shell/profile.sh` keeps every chatty tool init wrapped in `_gs_quiet` (runs the extracted `# >>> gs-quiet` bytes) and carries no login-time `chown`/`chmod` of a `chrome-sandbox` (1b, audit 2026-10-06 F3); `bash bin/tests/claude-fullauto-shell.test.sh` — 20 checks that the `# >>> gs-claude-fullauto` block (interactive-only `claude()` wrapper adding `--allow-dangerously-skip-permissions`; `command claude` escape; non-interactive shells untouched) is present, byte-identical across `profile.sh` / `.shellrc` / `shell.shellrc`, and behaves, against a fake `claude` on PATH. Run with `< /dev/null` (they spawn `bash -i`).

## From CLAUDE.md § Makefile Patterns (moved by `/rules-split`, 2026-11-07)

- **DRY macros** for per-service targets — five families: `login-service-shell`, `login-service-sh`, `log-service`, `log-follow-service`, `restart-service`
  ```makefile
  $(eval $(call login-service-shell,03node24))
  ```
- **`docker-cli` target**: central dispatcher — assembles `${GLOBAL_STACK_DOCKER_CLI} ${FLAGS} ${EXEC} ${EXEC_FLAGS} ${SERVICE} ${CONTAINER_COMMAND}`
- `local.Makefile` extends via `-include local.Makefile`; uses `create-paths::` double-colon for additive extension
