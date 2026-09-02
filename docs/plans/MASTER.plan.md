# /stack — MASTER PLAN (single source of truth)

> **What this file is.** The one live plan for this repo. It absorbs the five previous plan
> files (now in `docs/archive/plans/` after this plan's Stage-1 commit) and the ranked open
> backlog from the 2026-08-28/29 bug hunt (`var/claude/hunt/MASTER-TRIAGE.md`, gitignored,
> superseded by this file). It is self-sufficient: written to be executed by a fresh model in
> a fresh session with no access to the planning conversation.
>
> **Executor: read `## Executor session constraints` before your first tool call.**
> On any conflict, THIS FILE beats conversation memory, session summaries, and any plan-mode
> scratch file. Repo `CLAUDE.md` still applies in full.

## TL;DR

| Stage | What |
|---|---|
| Stage 1 | Unification commit: archive the 5 old plans to `docs/archive/plans/`, track this file, push |
| Track 0 | Certify HEAD: run the full test battery before any new work |
| Track 1 | env-update: cache-key poisoning (tag flags) + 1 cosmetic message fix |
| Track 2 | Startup/health: per-service web-server error tokens; `USE_LOCKS` dead at runtime; pyenv false-reinstall |
| Track 3 | Makefile/bin: `wait-healthy` false-OK; `check-image-versions.sh` ×3; `open-all-envs.sh` ×2 (incl. host `~/.sdkman` destruction); fresh-clone `sed` noise |
| Track 4 | Hooks: `env-guard-on-write.sh` port check rewrite (5/5 false positives + 1 real miss) |
| Track 5 | Reload coverage: EVERY runtime-installed tool converges on the `gs_version_gate` pattern (deno, bun, deployer, symfony-cli, laravel/installer, android, … confirmed ungated) |
| Close-out | Re-run battery, update this file with terminal states, push |

Method, enforced: reproduce → failing test → fix → sabotage-check → one green commit each;
advisor-only certification; zero questions to the developer; nothing destructive.

Developer still owes: one supervised rebuild/bring-up (closes the `UNCERTIFIED-BY-EXECUTION`
labels) and post-push commit signing.

## Decisions Log (seeded from the 2026-08-31/09-01 planning session)

- [2026-08-31] AGREED: scope of unification = the `/stack` repo itself. `/stack/projects/*`
  subprojects (scout, twes, invoiceninja, …) are OUT — each has its own plan.
- [2026-08-31] AGREED: superseded plan files are **archived unchanged** (developer chose
  archive over delete/tombstone); path refined 2026-09-01 to `docs/archive/plans/`.
- [2026-08-31] AGREED (F4): **per-service error tokens** for caddy/nginx/httpd — not a shared
  `web-server` error token, not deferral. Mechanism spec in Track 2; consumer side polls all
  three per-service error paths (COMPOSE_FILE introspection rejected — see Track 2).
- [2026-08-31] AGREED (F3): **fix + verify-then-classify**. Implement the compose change;
  first-line evidence is a cheap single-container recreate + `printenv` (compose
  `environment:` applies at container create — a full rebuild may be unnecessary for
  value-visibility). Only what genuinely needs rebuild-scale proof is labeled
  `UNCERTIFIED-BY-EXECUTION`, in those words. The developer runs any supervised full rebuild
  later, at a moment of their choosing.
- [2026-08-31] AGREED: Docker Hub anonymous page-cap silent-hit stays an **accepted risk**
  (2026-08-21 ruling stands: document, don't redesign). Register entry only; no work item.
- [2026-08-31] AGREED: certification is **advisor-only throughout** — `advisor()` at every
  3C/6C gate and at every milestone; **no reviewer panels are ever spawned** by the executor.
  The one carve-out that still asks: the 5-round advisor escalation cap (global framework).
- [2026-08-31] CARRIED (record-only, cross-repo, NOT executor work): decontainerization **D2**
  (sibling permission tiers vs rent-watch's empty-deny invariant, options unchanged) and
  bundle-audit **open ruling #2** (whether siblings adopt `claude-setup/<bundle>.tar.gz`).
  Provenance: `docs/archive/plans/decontainerization.plan.md` § status table,
  `docs/archive/plans/claude-bundle-cross-repo-audit.plan.md` § "Open — needs a ruling".
- [2026-08-31] AGREED (env-update F2 fix design): append a **hash of the 7 applied tag flags
  to the cache key** at every fetcher cache site (9 files) — matches the `bf36367`
  md5-in-filename precedent. Do NOT switch to caching the pre-flag raw list.
- [2026-09-01] AGREED (developer, verbatim intent): archive location is
  **`docs/archive/plans/`** (pattern `docs/archive/{plans|specs}` — specs subdir created when
  a spec is first archived).
- [2026-09-01] AGREED (developer, verbatim intent): **reload/version-change coverage for
  EVERYTHING installable** — "all tools/installable things must follow the same pattern",
  explicitly including tools installed inside runtimes (composer under phpbrew, deno/bun under
  node, …). This is Track 5.
- [2026-09-01] AGREED (design, follows from the directive): the ONE pattern is
  **`gs_version_gate` content-compare** (base-prologue helper). Every runtime-installed tool
  gets (a) a pinned `GLOBAL_STACK_*_VERSION` var in `.env` with a `@todo env-update`
  annotation and (b) a gate site keyed on a `tools/versions/<runtime>.<tool>` marker written
  only after a successful install. Hand-rolled compares converge on the helper; exist-only
  checks are replaced; unpinned installs get pinned. Image-build-time tools (Dockerfile
  `ARG`s in `00base` etc.) are ALREADY correctly covered by the ARG-drift mechanism
  (`env-scan` propagation + `check-image-versions` + rebuild) — classify, don't migrate.

### Executor entries

- [2026-09-01] DONE: Stage 1 landed as `0cc4c4d` — 5 plans moved to `docs/archive/plans/` as
  pure renames (`git diff --cached -M --stat`: 5 files, 0 lines changed), `MASTER.plan.md`
  tracked (529 insertions), `var/claude/hunt/MASTER-TRIAGE.md` banner applied, pushed
  (`8486f62..0cc4c4d`, `git rev-list --count origin/master..master` = 0).
- [2026-09-01] TRACK 0 BASELINE (at `0cc4c4d`, tallies read from each suite's own final line):
  env-update **836/836**; env-scan **186/186**; startup-prologue **182/182**; makefile-posix
  **5/5**; check-bake-targets **12/12**; git-strip-coauthored **27/27**;
  check-image-versions **17/17**; profile-shell **12/12**; claude-fullauto-shell **20/20
  after the fix below** (was 3/20). `docker compose --env-file .env.local config -q` exit 0.
  `make check-image-versions` silent + exit 0, and that silence is **certified non-vacuous**:
  43 Dockerfiles, 11 matching `^FROM …${GLOBAL_STACK_IMAGE_*_VERSION}`, 11 comparisons
  actually executed (`bash -x` trace counts 12 `_gs_civ_checked=` lines = init + 11) — a real
  "no drift", not the F8 vacuity signature.
- [2026-09-01] AGREED (Track 0 red, fixed as `7e79d39`): `claude-fullauto-shell.test.sh` was
  red at baseline because `8486f62` added `--permission-mode plan` to the `claude()` wrapper
  in all three templates without updating the suite. The **template is right, the assertions
  were stale** — cases 3 and 7 now pin the whole flag prefix in order. Case 7 (zsh) was
  *latently* red: skipped on this host for lack of zsh, so it would have surfaced only on a
  host that has it. Case 0 keeps its bare-substring form on purpose (vacuity guard).
  Sabotage-checked; restore `cmp`-verified. **Certified-by-execution boundary**: cases 0–6
  (bash, all three templates) ran green; the case-7 (zsh) assertion is fixed **by inspection
  only** — zsh is not installed on this host, so that string has never been executed. Its
  correctness is [Inferred] from the identical bash cases.
- [2026-09-01] CARRIED (P3, developer's own call — NOT executor work): `8486f62` added
  `--permission-mode plan` to the wrapper but three prose surfaces still describe it as
  adding a single flag — the template block's own comment ("every session still starts in its
  normal mode", now inaccurate: sessions open in plan mode), the test header comment at
  `bin/tests/claude-fullauto-shell.test.sh:8`, and the global `~/.claude/CLAUDE.md`
  § full-auto paragraph. The templates would need a triple-identical edit (out of Track 0's
  scope), and `~/.claude` is out of this plan's scope entirely. Recorded so the drift is not
  invisible.
- [2026-09-01] CORRECTION (Track 1a scope — the plan's 9-file list is wrong in BOTH
  directions; use this set instead): the fetchers that apply tag flags between a cache read
  and a cache write are **codeberg, dockerhub, ghcr, github, npm, pypi, quay, rubygems,
  url** [Verified: `git grep -l apply_tag_flags bin/lib/env-update/fetchers/`]. `sdkman.sh`
  is a **false member** of the plan's list — it uses no tag flags at all [Verified: `git grep
  -n 'tag_filter\|tag_strip\|tag_extract\|tag_exclude\|tag_replace' fetchers/sdkman.sh`
  returns nothing]. `url.sh` is **missing** from it and has the identical defect: key built
  at `:101`, read at `:104`, tag flags applied at `:219`, cache written at `:226` with that
  same key. Implementing the plan's list verbatim would have left `url.sh` poisoned — the
  exact "a 10th fetcher forgets it" hazard the plan warns against.
- [2026-09-01] AGREED (Track 1a design, refines the cache-key ruling): the hash must be
  folded in at the **`local _cache_key=` construction line**, never inside
  `_gs_eu2_cache_try_load` — `_gs_eu2_cache_write` takes only `(_key, _value)` and receives
  no record index [Verified: `core/cache.sh:77`], so hashing on the read side alone would
  make the read key differ from the write key. For `url.sh` fold it at `:101` only: all five
  `cache_write` sites (`:126, :163, :226, :275, :340`) reuse that one key, and a superset key
  is harmless for the tiers that apply no flags. `url.sh:413` (`url-probe`) is a separate key
  — confirm no tag-flag application sits between its read and its write before excluding it.
  The structural guard is a **paired-set assertion**, not "helper present in every fetcher"
  (pecl/sdkman/sdkmanager legitimately apply no flags): the set of files matching
  `apply_tag_flags_from_record` must be a SUBSET of the set matching the key helper.
- [2026-09-01] REFUTED-AT-EXECUTION (no work item): the 4th bug from the 2026-08-28/29 hunt —
  `awk -v` escape-processing corrupting version strings — is **already fixed** at `9e61c05`
  ("pass values into awk via ENVIRON so a backslash is not interpreted"). The only surviving
  `awk -v` occurrence in `bin/lib/env-update/` is the explanatory comment at `apply.sh:90`
  [Verified: `git grep -n 'awk -v' bin/lib/env-update/`]. Recorded so it is not silently
  dropped; it was absorbed by neither the plan body nor the register.
- [2026-09-01] CORRECTION (Track 3b): `bin/tests/check-image-versions.test.sh` **already
  exists** (17/17 green) since `9398486`, which also fixed a `$PWD`-resolution vacuity in the
  script. Track 3b's evidence step is therefore **extend, not create**, and the suite is
  added to the Track 0 battery above. F8 is **half-fixed**: the 0-Dockerfiles guard is
  present (`:63-69`), the 0-*comparisons* guard is still absent (`:84` still skips silently
  when either side is unreadable). F9 (`:36` defaults to `.env`, not `.env.local`) and F14
  (mode `100644` [Verified: `git ls-files -s`]) remain fully live.
- [2026-09-01] CORRECTION (Track 3c F12 ordering — the fix must capture EARLIER than the plan
  implies): `bin/open-all-envs.sh` overwrites the host's `~/.sdkman/etc/config` with an
  unconditional `echo … > "${HOME}/.sdkman/etc/config"` at `:191`, i.e. **before** the
  `rm -rf` at `:195`. Content capture must happen before that first `>`, not merely before
  the `rm -rf`. Worse than stated: the script's final act (`:205`) leaves the developer's
  config replaced by the single line `sdkman_healthcheck_enable=false`, so a completed run is
  destructive even when nothing errors. F11 also confirmed live: no `set -euo pipefail`, and
  `.env` is read as a bare relative path at `:180` and `:203`.
- [2026-09-01] CONFIRMED-AT-EXECUTION (Track 2a): the defect reproduces exactly as specced —
  `caddy:22`, `httpd:23`, `nginx:23` all write the same `${…_SUCCESSES}/web-server`, three
  consumers wait on it (`alltogether:20`, `localstack:11`, `serverless:19`), and none of
  `01caddy` / `01nginx` / `01httpd` defines `GLOBAL_STACK_ERROR_TOKEN` in its compose file
  [Verified: `git grep -n GLOBAL_STACK_ERROR_TOKEN` over the three files returns nothing].

- [2026-09-02] AGREED (Track 1a design): the fingerprint is `_gs_eu2_tag_flags_fingerprint`
  in `core/tag_flags.sh` — an 8-hex `md5sum | cut -c1-8` (the tool `cache.sh:38` already uses;
  no new dependency) over the same 7 fields `_gs_eu2_apply_tag_flags_from_record` reads,
  **NUL-separated**. NUL because a bash string cannot contain one: a printable separator
  reintroduces the very collision the fix exists to prevent, one layer down. Appended
  **unconditionally**, including for flag-less records — a "skip the suffix when no flags are
  set" branch is one that can be half-applied, and the cost of not having it is one cache
  generation, in `/tmp`, under a 3600 s TTL.
- [2026-09-02] AGREED (Track 1a guard rests on a set coincidence, now pinned): the fetchers
  that apply tag flags, those that `source core/tag_flags.sh`, and those needing the
  fingerprint are the SAME 9 — `pecl` / `sdkman` / `sdkmanager` are in none of the three
  [Verified: per-file `grep -c` — `tagflags=0` for exactly those three]. `t120b` asserts both
  the membership and the coincidence, so a 10th fetcher cannot quietly join two of the sets.
  Independently corroborated by the documentation written before this work:
  `templates/tips/env-update.md:243` scopes `(tag-filter)` to *"All except `sdkman`,
  `sdkmanager`, `url`(tiers 1-2)"* — naming the two excluded fetchers the code analysis found,
  and confirming `url` is IN for its later tiers. The plan's original nine (which dropped
  `url` and kept `sdkman`) contradicted the repo's own reference on both counts.
- [2026-09-02] CORRECTION (`url.sh:413` is IN, and for a better reason than "no flags
  between"): the second cache site is `_gs_eu2_url_probe_check`, whose value **is** the
  proposed version for url-probe records, and it is handed the same `_cache_key` from `:371`.
  Fixing `:101` therefore fixes `:413` — no second edit, and none was made.
- [2026-09-02] CARRIED (not fixed, out of Track 1a's stated scope — the 7 tag flags):
  `version_prefix` is applied to `_proposed` **before** the cache write in both `url.sh`
  (`:124` → `:126`) and `github.sh` (`:589` → `:595`) while appearing in neither key — the
  same poisoning shape for a different field. Note-only; no evidence it is live in `.env`.
- [2026-09-02] REFUTED (`tag_channel_prefix` — a finding I raised and then disproved before
  acting on it): it looked like `version_prefix`'s twin, because it is absent from the
  `local _cache_key=` construction line. It is **not** — `github.sh:257` appends
  `:tcp_${_tcp}` to the key afterwards, and `:258` appends `:tags` for merge mode. So
  `templates/tips/env-update.md:250` ("Cache key is segregated from non-flag runs") is TRUE
  and nothing is owed here. Recorded because the near-miss generalises: a
  `grep 'local _cache_key='` sweep sees construction and misses **post-construction
  appends**, and only `grep '_cache_key="\${_cache_key}'` finds those — two sites, both in
  `github.sh`, none anywhere else [Verified: that grep across all 12 fetchers].
- [2026-09-02] NOTED (pre-existing, untouched): `templates/tips/env-update.md` documents
  per-fetcher cache keys at `:940`, `:979`, `:1068`, `:1154`, `:1184`, `:1216`, and every one
  of them was **already** stale before this change — none lists `major_hint_min`,
  `prefer_specific` or `watch_major_depth`, all of which have been in the keys for some time.

The executor APPENDS its own dated `AGREED:` entries here (e.g. the F3 classification
outcome, Track 5 audit rulings) as it goes — this file is where rulings land. Never backdate;
never write an entry for a ruling that was not actually taken (forged-AGREED hazard, global
Rule 17).

## Planning-time verified state (2026-08-31/09-01)

- Tree clean at `8486f62` [Verified: `git status --porcelain` empty].
- Full autonomy armed for `/stack`: all six guard-family bypass sentinels at project scope
  (`~/.claude/projects/-stack/state/*-bypass`) + permission-swap project-armed (8 allow rules
  in `.claude/settings.local.json`, epoch 1788189357). Consequence: the executing session
  runs gate-free and MUST NOT need to ask the developer anything — every ruling is
  pre-settled in this file.
- Of the five archived plans, three were fully executed
  (`session-protocol-and-agent-removal`, `startup-health-signalling` F1/F2/F5/F6/F7,
  `fetcher-error-signalling` F1); their open residuals are absorbed below.

---

## Stage 1 — the unification commit (executor's FIRST action, before Track 0)

1. **Identity check first**: `git -C /stack config user.name` / `user.email` must be
   `Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>`. Never any
   `Co-Authored-By` or `Claude-Session` trailer, on this or any later commit.
2. `mkdir -p /stack/docs/archive/plans`
3. `git mv` each of the five files into `docs/archive/plans/` (content untouched):
   `decontainerization.plan.md`, `claude-bundle-cross-repo-audit.plan.md`,
   `session-protocol-and-agent-removal.plan.md`, `startup-health-signalling.plan.md`,
   `fetcher-error-signalling.plan.md`.
4. `git add docs/plans/MASTER.plan.md` (this file — untracked until this commit).
5. Append a superseded banner to `var/claude/hunt/MASTER-TRIAGE.md` (top of file):
   `> SUPERSEDED 2026-09-01 by docs/plans/MASTER.plan.md — open items absorbed there.`
   (gitignored file; local bookkeeping, not part of the commit).
6. One commit: `docs(plans): unify all plans into MASTER.plan.md; archive superseded plans` —
   then `git push` (plain — never `-u`). Then Track 0.

---

## Track 0 — baseline certification of HEAD (before any new work)

Certify current HEAD by executing the full battery. The suite's own final
`ALL PASSED ✓ N / N` line is the ONLY authoritative tally — never count `✓` marks, never sum
per-section `└─` lines, never assert an expected count from this file:

```bash
bash bin/tests/env-update.test.sh          # large; last observed 836/836 — re-read, don't trust this hint
bash bin/tests/env-scan.test.sh
bash bin/tests/startup-prologue.test.sh    # 182 at planning time
bash bin/tests/makefile-posix.test.sh
bash bin/tests/check-bake-targets.test.sh
bash bin/tests/check-image-versions.test.sh   # ADDED 2026-09-01: exists since 9398486; the
                                              #   plan's original 8-suite list omitted it
bash bin/tests/git-strip-coauthored.test.sh
bash bin/tests/profile-shell.test.sh        < /dev/null   # spawns bash -i
bash bin/tests/claude-fullauto-shell.test.sh < /dev/null  # spawns bash -i
docker compose --env-file .env.local config -q            # ALWAYS -q (secrets!)
make check-image-versions
```

Any red here is a STOP-and-fix-first (its own commit) before the tracks below. Record the
tallies in this file's Decisions Log as the Track 0 baseline entry.

---

## Open work — 13 findings + reload-coverage convergence (verify-before-build is MANDATORY per item)

Triage evidence dates from 2026-08-28/29; no commit since touched these surfaces [Inferred:
commit subjects `9aad609..8486f62` are shell-templates/bundle/docs]. The executor MUST
re-reproduce each defect against live HEAD before writing the failing test; if a defect no
longer reproduces, record `REFUTED-AT-EXECUTION` in the Decisions Log with evidence and skip
its fix. TDD per repo Rule 7: failing test first, confirmed red **for the stated reason**;
sabotage/mutation check per repo § Certification; restore verified byte-for-byte (`cmp`).

### Track 1 — env-update (surface: `bin/lib/env-update/`, STRONG executable evidence)

**1a. [P1] F2 — cache key omits all 7 tag flags → cross-record poisoning; a version its OWN
`tag-filter` rejects gets WRITTEN.**
- Where: `core/tag_flags.sh:118` (`_gs_eu2_apply_tag_flags_from_record`) applies
  `tag_filter, tag_exclude, tag_strip_prefix, tag_strip_suffix, tag_extract,
  tag_replace_from, tag_replace_to` BETWEEN cache read and cache write; NO fetcher includes
  them in its key: `github.sh:255-257`, `dockerhub.sh:166`, `codeberg.sh:96`, `ghcr.sh:168`,
  `npm.sh:88`, `pypi.sh:70`, `quay.sh:95`, `rubygems.sh:65`, `sdkman.sh:221`.
- Repro (verified 2026-08-29; both records collapse to one key
  `github_testowner_mixed-tags-repo_____b703b6ed.cache`):
  ```bash
  S=/tmp/p4; mkdir -p $S/c; FX=/stack/bin/tests/fixtures/env-update/http
  printf '# @todo env-update (tag-filter:^PHP_ZIP-) (tag-strip-prefix:PHP_ZIP-) github:testowner/mixed-tags-repo 1.0.0\nGLOBAL_STACK_A_VERSION=1.0.0\n' > $S/a.env
  printf '# @todo env-update github:testowner/mixed-tags-repo 1.0.0\nGLOBAL_STACK_B_VERSION=1.0.0\n' > $S/b.env
  _GS_EU2_CACHE_DIR=$S/c _GS_EU2_HTTP_FIXTURE_DIR=$FX bash bin/env-update.sh --env-file=$S/b.env --check
  _GS_EU2_CACHE_DIR=$S/c _GS_EU2_HTTP_FIXTURE_DIR=$FX bash bin/env-update.sh --env-file=$S/a.env --apply --yes
  # BROKEN: A written 1.22.8 (its own tag-filter rejects it). With --no-cache: correct 1.12.1.
  ```
- Fix (ruled): compute one hash over the record's 7 tag-flag values (empty flags hash too —
  stable for flag-less records) and append it to the cache key at all 9 sites. Prefer ONE
  shared helper (in `core/tag_flags.sh` or the `3dd5cda` cache-try-load helper) so a 10th
  fetcher can't forget it; wire every site through it.
- Evidence: new `env-update.test.sh` section — two records same source different flags must
  yield different cached results (the repro above as fixture-driven test); sabotage = drop
  the hash from one fetcher's key → red.

**1b. [P3] F3 — `printf %q` renders the `<empty>` placeholder as `got \<empty\>` in three
parse-error messages.** Find the three sites (`git grep -n '%q' bin/lib/env-update/`); print
the placeholder literally (`%s` for the placeholder arm) while keeping `%q` for genuinely
user-supplied values. Evidence: assert exact message text in the args/parse test section.

Commit boundary: one commit per finding (`fix(cache): include tag flags in fetcher cache
keys`, `fix: render <empty> placeholder literally in parse errors`). Milestone close: full
`env-update.test.sh` green + `advisor()`.

### Track 2 — startup / health signalling (surface: `docker/config/dist/bin/`, compose YAML)

**2a. [P1] startup F4 — `successes/web-server` has no error producer and no `depends_on`; a
failed web server hangs 3 consumers for the full 3600s, which then blame themselves.**
- Where: producers `caddy-bin/global-stack-caddy-start.sh:22,44,103`,
  `nginx-bin/global-stack-nginx-start.sh:23,59,195`,
  `httpd-bin/global-stack-httpd-start.sh:23,53,162` — all three write/delete the SAME
  `${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server`. Consumers:
  `serverless-bin/…-start.sh:11`, `alltogether/global-stack-alltogether-start.sh:14`,
  `localstack-bin/global-stack-localstack-start.sh:11`. Fail-fast:
  `base-bin/global-stack-base-wait-for.sh:10-19` derives the error path from the success path
  (`_error_path="${dependency/\/successes\//\/errors\/}"` → polls `errors/web-server`, which
  nothing writes because `01caddy`/`01nginx`/`01httpd` define no `GLOBAL_STACK_ERROR_TOKEN`).
- Fix (ruled — per-service tokens):
  1. Give each of `01caddy`, `01nginx`, `01httpd` its own `GLOBAL_STACK_ERROR_TOKEN` in its
     compose YAML: `caddy`, `nginx`, `httpd`. **Token invariant applies**: their own
     healthchecks/success writes keep using their existing markers; do not touch the shared
     `web-server` SUCCESS marker semantics.
  2. Each producer clears its own stale `errors/<token>` at startup (byte-match the existing
     10-site literal
     `rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"`
     — the convention audit greps for exactly that string; no new helper).
  3. Consumer side: extend `base-wait-for.sh` so that when the dependency is
     `successes/web-server`, it fail-fasts if **any of `errors/caddy`, `errors/nginx`,
     `errors/httpd`** exists (in addition to the derived path). Poll-all-three is safe: a
     non-running alternative writes nothing, producers clear their own stale token (step 2),
     and `make down` clears `errors/*`. **COMPOSE_FILE introspection is REJECTED** as primary
     design: it is unverified that `COMPOSE_FILE` reaches consumer container env, and
     poll-all-three needs no such precondition. Do not build it.
- **Explicitly carried OPEN (not in scope)**: the three producers `sudo rm -rf` the shared
  SUCCESS marker with no lock — a real race only when 2+ alternatives are enabled at once.
  Register entry; do not fix here.
- Evidence: `startup-prologue.test.sh` new sections — each producer writes its own token on
  failure (mirror existing §17-20 shapes); wait-for unit test with a fake tools tree proving
  fail-fast on each of the three error files and NO fail-fast when only a stale-then-cleared
  token existed. Sabotage: point one producer's token at a different literal → red (the
  repo's canonical sabotage shape). The live bring-up behavior is
  `UNCERTIFIED-BY-EXECUTION: consumer fail-fast under a real failed web-server container is
  unproven without a stack bring-up` — state exactly that in the completion report.

**2b. [P1] startup F3 — `GLOBAL_STACK_USE_LOCKS` is build-time only; flipping it in
`.env.local` changes nothing; the tier-03 install race can never be serialized.**
- Where: `docker/images/00base/docker-compose.yaml:63` passes it as `build.args`;
  `00base/Dockerfile:80` (`ARG`) and `:156` (baked `ENV`). Runtime readers:
  `nvm-bin/global-stack-nvm-start.sh:68,192`, `pyenv-bin/…:68,174`, `rbenv-bin/…:66,166`,
  `phpbrew-bin/…:106,231`, `fvm-bin/…:63,138` — value expected to track `.env.local`, but no
  service puts it in `environment:`.
- Fix (ruled — verify-then-classify): add `GLOBAL_STACK_USE_LOCKS: ${GLOBAL_STACK_USE_LOCKS}`
  to the `environment:` of every tier-02/03 service whose startup script reads it (enumerate
  readers by `git grep -l 'GLOBAL_STACK_USE_LOCKS' docker/config/dist/bin/` and map each to
  its service compose file — full-set coverage rule; check the `04b64ae` extends fragments
  first: one fragment edit may cover many services). Keep the Dockerfile ARG/ENV as harmless
  default; compose `environment:` overrides image ENV at runtime.
- Evidence ladder: (1) `docker compose --env-file .env.local config -q` green;
  (2) `docker compose --env-file .env.local config --format json | jq
  '.services["03node24"].environment.GLOBAL_STACK_USE_LOCKS'` — prints only that key, never
  the full expanded config (secrets); (3) IF the stack is running: flip the value in
  `.env.local`, recreate ONE tier-03 container (`docker compose up -d --force-recreate
  03node24` — plain restart does NOT re-read env; recreate does), `make login-03node24` →
  `printenv GLOBAL_STACK_USE_LOCKS`; restore the value after. If (3) proves visibility, the
  value-plumbing is CERTIFIED and say so; only the actual install-race serialization remains
  `UNCERTIFIED-BY-EXECUTION: lock-serialized tier-03 parallel install is unproven without a
  full reinstall cycle`. If the stack is down, stop after (2) and label both halves
  UNCERTIFIED in those words.

**2c. [P2] startup F8 — pyenv `gs_version_gate` compares the RAW pin against a marker holding
the RESOLVED version → spurious reinstall WARN on every start for partial pins.**
- Where: `pyenv-bin/global-stack-pyenv-start.sh:56-57` gates on raw `${PYTHON_VERSION}`;
  `:137,144` write the resolved `$(global-stack-pyenv-find-latest.sh "${PYTHON_VERSION}")`.
  nvm documents the invariant it violates (`nvm-bin/…-start.sh:52-55`); rbenv already has the
  partial-pin resolver pattern (test §20 precedent).
- Fix: resolve BEFORE gating — gate on the same resolved value that gets written (mirror the
  rbenv resolver shape). Evidence: `startup-prologue.test.sh` section mirroring §20's rbenv
  test, red-first with a marker holding a resolved version vs a raw pin.

Milestone close: `startup-prologue.test.sh` green, compose `config -q` green, `advisor()`,
completion report naming every UNCERTIFIED dimension in those words.

### Track 3 — Makefile / bin scripts (surface: `Makefile`, `bin/`)

**3a. [P1] F6 — `make wait-healthy` exits 0 with the stack down.**
- Where: `Makefile:245-252` — the `while … grep -q starting` loop over
  `docker compose ps --format "{{.Health}}"` sees empty output when nothing runs, the loop
  never enters, and the errors-dir check passes on an empty dir.
- Fix: before the settle loop, count services (`docker compose … ps -q | wc -l` shape);
  zero → print `stack is not running` and exit 1. Recipe runs under `/bin/sh` (dash) — no
  bashisms outside the existing `bash -c` wrapper; extend inside the wrapper.
- Evidence: new `bin/tests/wait-healthy.test.sh` using a stub `docker` on PATH (the
  `git-strip-coauthored` stub pattern + the copy-to-tempdir isolation pattern): stub returns
  empty ps → target must exit non-zero; stub returns healthy set → exit 0. Also extend
  `makefile-posix.test.sh` if a recipe line changed shape.

**3b. [P1+P2] F8/F9/F14 — `bin/check-image-versions.sh` (one item, three defects).**
- F8 [P1]: `:83` skips silently when either side is unreadable; `:61-69` guards 0 Dockerfiles
  but nothing guards "0 comparisons possible" — a renamed env side is silently vacuous. Fix:
  count comparisons actually made; zero (with >0 Dockerfiles) → same WARN-shape as the
  0-Dockerfiles guard (non-fatal, matching its `|| true` preflight role, but LOUD).
- F9 [P2]: `:36` compares `.env` while `make up` builds from `.env.local`
  (`Makefile:213-215`). Fix: default `_GS_CIV_ENV_FILE` to `.env.local` when present, else
  `.env`; report which file was used.
- F14 [P2]: committed `100644` while allow-listed as directly runnable. Fix:
  `git update-index --chmod=+x bin/check-image-versions.sh` (works despite
  `core.fileMode=false`; note it in the commit message — local `git diff` won't show the
  mode bit).
- Evidence: new `bin/tests/check-image-versions.test.sh` (pattern:
  `check-bake-targets.test.sh`) — fixture env files + fixture Dockerfiles: drift detected;
  renamed env side → loud WARN not silence; `.env.local` preferred over `.env`. Sabotage:
  re-blind the comparison counter → red.

**3c. [P1] F11/F12 — `bin/open-all-envs.sh` (one item, two defects).**
- F11 [P1]: reads the literal relative `.env` (`:180`, `:203`) — from any cwd but `/stack` it
  opens ZERO links and exits 0; also the only `bin/` script without `set -euo pipefail`. Fix:
  resolve repo root from `BASH_SOURCE[0]` and use absolute paths; add strict mode per
  `templates/tips/bash-strict-mode.md`; opening zero links → exit non-zero with a message.
- F12 [P1]: `:188-195,:205` overwrite → source → `rm -rf` → re-create the HOST's
  `~/.sdkman/etc/config`, destroying the developer's real file. Fix: preserve-and-restore —
  if the file exists, copy its exact content aside first and restore it byte-identical
  (`cmp`-verified) at the end AND on any early exit (trap); if it did not exist, remove only
  what the script created. No unconditional `rm -rf` of a host path survives this fix.
- CONSTRAINT: `bin/open-all-envs.sh` is byte-identical-paired with
  `templates/tips/open-many-links.md` — verify whether the pairing covers these lines and
  update BOTH surfaces in the same commit if so; doc block must use `(cd X && cmd)`
  paste-safe form, never `cd || exit`.
- Evidence: new `bin/tests/open-all-envs.test.sh` — fake `HOME`, stub link-opener on PATH,
  run from a foreign cwd (must still enumerate links), pre-seeded `~/.sdkman/etc/config`
  must survive byte-identical (`cmp`). Red-first for both defects.

**3d. [P3] F7 — every `make` on a fresh clone prints `sed: can't read .env.local`.**
- Where: `Makefile:12` — `export $(shell sed 's/=.*//' ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV})`
  runs unconditionally while `:11` uses tolerant `-include`. Fix the root cause (no stderr
  suppression — anti-bandaid rule):
  `$(shell test -f ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV} && sed 's/=.*//'
  ${GLOBAL_STACK_DOCKER_CLI_DOT_ENV})`. Evidence: `makefile-posix.test.sh` check —
  `make help` in a temp clone-shape dir (no `.env.local`) emits no `can't read` on stderr.

Milestone close: all `bin/tests/*.test.sh` green + `advisor()`.

### Track 4 — hooks (surface: `.claude/hooks/`)

**4a. [P1] F13 — `env-guard-on-write.sh` port check: 5/5 false positives on the repo's own
env files AND misses the one range var that really concatenates.**
- Where: `:35-37` — regex `^GLOBAL_STACK[A-Z0-9_]*_PORT_[0-9]+=.*[^:]$`.
  Half A: all 5 current warnings name vars whose consumers supply the `:` themselves (must
  NOT end with `:`). Half B: the name pattern requires `=` right after digits, so range-style
  `GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559=` (consumer
  `01localstack-localstack/docker-compose.yaml:36`: `${VAR:-}4510-4559`; `.env.local:137` =
  `42731-42780:`) never matches — the ONLY `_PORT` var of 50 the hook misses, and exactly
  the concatenating form it exists to protect.
- Fix (consumer-keyed, zero annotations): warn iff (value non-empty) AND (value does not end
  `:`) AND (some `docker/images/*/docker-compose.yaml` contains `${VAR:-}` immediately
  followed by a digit — the concatenating consumer form). Extend the name regex to allow
  `_PORT_[0-9]+(_[0-9]+)*=`. This fixes both halves at once.
- Evidence: new `bin/tests/env-guard.test.sh` (no test exists today — create it;
  copy-to-tempdir isolation with fixture env + fixture compose tree). Red baseline: current
  hook = 5 false warnings + 1 miss. Green: 0 warnings on canonical files; dropped-`:` on the
  range var → warning. Sabotage: remove the consumer-form check → red.

Milestone close: hook test green; run the hook once against the real `.env`/`.env.local` and
paste the (empty) output; `advisor()`.

### Track 5 — reload coverage: version-gate EVERY runtime-installed tool (developer directive 2026-09-01)

**Goal.** A version bump in `.env` must trigger reinstall-with-WARN for EVERY runtime-installed
tool, exactly as `gs_version_gate` (in `base-bin/global-stack-base-prologue.sh`) already does
for managers, tier-03 runtimes, and `setup-packages.sh` pkg slots. Today three idioms coexist;
after this track there is ONE.

**5a. The bidirectional audit (do this FIRST — it defines 5b's full worklist).**
- Inventory A: every `GLOBAL_STACK_*_VERSION` var in `.env` (~380;
  `grep -oE '^GLOBAL_STACK_[A-Z0-9_]+_VERSION' .env | sort -u`), each classified by install
  mechanism: (1) compose image tag / Dockerfile `ARG` at image build (ALREADY covered by
  env-scan ARG propagation + `check-image-versions` + rebuild — record, don't touch);
  (2) `setup-packages.sh` pkg slot (ALREADY gated — record); (3) runtime install script
  (THE TARGET SET); (4) dead/commented (record as such).
- Inventory B: every `gs_version_gate` call site + every `tools/versions/` marker read/write
  (`git grep -n 'gs_version_gate\|VERSIONS}/' docker/config/dist/bin/`).
- Both inventories are STATED IN FULL in a dedicated **appendix section of this file**
  (required location — not the Decisions Log) before any migration — any class-3 var absent
  from B is a finding. Do not start from the seed list below and "check the rest"; enumerate
  both sides independently.

**5b. Migration pattern (one shape, applied per tool).** For each ungated/hand-rolled site:
```bash
_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/<runtime>.<tool>" \
         "${GLOBAL_STACK_<TOOL>_VERSION}" "<runtime>.<tool>")"
# reinstall branch: remove the tool's artifacts + marker, install pinned version,
# write the marker ONLY after verified success (existing convention)
```
- Marker naming follows the existing `phpbrew.composer` convention: `<runtime>.<tool>`.
- Existing `GLOBAL_STACK_RELOAD_*` flags keep forcing unconditional reinstall (unchanged).
- Every tool keeps/gains a pinned `.env` var WITH a `@todo env-update` annotation using an
  **EXISTING fetcher type only** (the 12 in `templates/tips/env-update.md`; e.g.
  laravel/installer → `github:laravel/installer` — never invent a new fetcher type).
- **New-var cascade wiring (mandatory, F3-shape hazard)**: any NEW `GLOBAL_STACK_*_VERSION`
  var must land in the FULL cascade — `.env` (+annotation) → env-scan → the consuming
  service's compose `environment:` block — or the container reads empty and the gate either
  reinstalls every start or never fires. Verify in-container visibility the Track 2b way:
  `docker compose --env-file .env.local config --format json | jq
  '.services["<svc>"].environment.<VAR>'`.
- **Prologue-exemption collision rule**: `gs_version_gate` lives in the prologue, but the
  caddy/nginx/httpd scripts and `android-setup` are DELIBERATELY prologue-exempt (they keep
  their own `stackCatch`; the 141-exempt variant). Never source the full prologue into an
  exempt script (it would swap their ERR-trap handling), and never re-implement the gate
  inline. Instead: extract `gs_version_gate` into its own sourceable helper
  (`base-bin/global-stack-base-version-gate.sh`), have the PROLOGUE source it (all existing
  call sites unchanged), and have exempt scripts source ONLY the helper. First check per
  seed-list script whether it sources the prologue (`android-start` may — the exemption list
  names `android-setup`; verify, don't assume).
- Respect the `set -xeE`/prologue conventions and the ERR-trap-in-`if` gotcha (memory:
  nvm cache self-heal — suppression propagates into sourced functions).

**Confirmed gaps (seed list — verified 2026-09-01 against HEAD `8486f62`; re-verify then
fix):**

| Site | Defect |
|---|---|
| `nvm-bin/global-stack-nvm-install-tools.sh` deno block | `[ -f "${DENO_JS}" ]` exist-only; `GLOBAL_STACK_DENO_VERSION` bump does NOTHING; no marker |
| same file, bun block | `[ -f "${BUN_JS}" ]` exist-only; `GLOBAL_STACK_BUN_VERSION` bump does NOTHING; no marker |
| `phpbrew-bin/global-stack-phpbrew-install-tools.sh:65` deployer | writes `phpbrew.deployer` marker but the guard checks only `-f` — marker write-only, version bump does nothing |
| same file `:89` symfony-cli | identical write-only-marker defect (`phpbrew.symfony-cli`) |
| same file `:31-34` laravel/installer | `composer global require` UNPINNED + a `composer global update --with-all-dependencies` that mutates versions outside any pin — pin + gate; investigate whether the update runs every start |
| same file, composer/zephir/phalcon/pickle/pie blocks | hand-rolled `[[ -f x && want = $(cat marker) ]]` — works but silent (no WARN) and duplicated; converge on `gs_version_gate` |
| `android-bin/global-stack-android-start.sh:73-79` | exist-only `android.sdkmanager` marker; the 5 `GLOBAL_STACK_ANDROID_*_VERSION` vars are NEVER compared — any SDK/NDK/build-tools bump does nothing without `RELOAD_ANDROID` |
| `rust-bin/global-stack-rust-install-cargo-nextest.sh` (+ outdated/zigbuild) | audit gating of `CARGO_NEXTEST/OUTDATED/ZIGBUILD_VERSION` |
| caddy/nginx/httpd sub-components (`http.mod_security`, `http.coreruleset`, `nginx.cjose`, `nginx.liboauth2`, apr, mod_auth_openidc, …) | markers exist (`*_VERSION_PATH` vars) — audit whether each is content-compared against its `.env` var or exist-only; converge |
| the rest of class 3 from 5a | whatever the audit finds (wkhtmltopdf, sonar-scanner-cli, elasticmq, rbenv gemset/ruby-build, fvm extras, …) |

- **Do NOT resurrect commented-out installs** (deno aleph/mandarinets are commented out in
  the script — they stay out; their vars are class 4).
- **Scope guard**: behavior change is strictly "version bump now reinstalls, with WARN". No
  tool additions/removals, no version bumps themselves, no install-logic rewrites beyond the
  gate + marker discipline.

**Evidence.** Extend `bin/tests/startup-prologue.test.sh`: for each converted script, a
fixture-tools-tree test proving (red-first) marker-mismatch → reinstall path entered +
WARN emitted, marker-match → skip, and marker written only on the success path. Test seam:
the reinstall branches run real `curl`/`git` — stub those binaries on PATH (the
`git-strip-coauthored` stub precedent + copy-to-tempdir isolation), or where the script's
structure allows, assert via the gate's own WARN output under `GS_STARTUP_DRY_RUN=1`.
Sabotage: revert one site to its old exist-only guard → red. `bash -n` + shellcheck +
`GS_STARTUP_DRY_RUN=1` across all touched scripts. Live in-container reinstall proof is
`UNCERTIFIED-BY-EXECUTION: real reinstall-on-bump inside a running container is unproven
without a bring-up` — named in the completion report; closed by the developer's supervised
bring-up (Inputs owed §).

**Docs (same commits).** Update `CLAUDE.md` § Gotchas `tools/versions/` entry (coverage is
now universal for runtime installs) + the two-phase model note; update
`templates/tips/env-update.md` only if new annotation entries need documenting.

Milestone close: startup-prologue suite green; both 5a inventories recorded in the appendix;
every class-3 var has a terminal state (gated / already-gated / class-2 / class-4);
`advisor()`.

---

## Close-out (after all tracks)

1. Update this file: mark each finding FIXED/REFUTED/CARRIED with its commit SHA; final
   Decisions Log entries; keep the register current.
2. Update `CLAUDE.md` **only where behavior changed** (e.g. new test suites in § Testing;
   wait-healthy semantics; env-guard behavior; version-gate universality). No new docs.
3. Full battery re-run (Track 0 list) — paste tallies. Final `advisor()` (6C).
4. Completion report: per repo rules, state plainly what was certified by execution and name
   every `UNCERTIFIED-BY-EXECUTION` dimension in those words (expected: F4 live fail-fast;
   F3 race-serialization; Track 5 live reinstall-on-bump; possibly F3 value-plumbing if the
   stack was down).
5. `git push` (plain). Note for the developer: SHAs get rewritten when they sign; afterwards
   `git fetch && git reset --hard origin/master` (verify the tree hash matches first).

## Fragile-implementations register (carried honestly — no work items unless listed above)

- Docker Hub anonymous page cap: a cap-hit is now SILENT where it used to be a loud ERROR
  (accepted risk, ruling 2026-08-21, re-affirmed 2026-08-31).
- sdkman fetcher: on a machine without sdkman, a dead broker is indistinguishable from
  "not installed" → SKIP (recorded residual).
- url fetcher tier 3: transport failures invisible when no tier 4 applies → falls to
  "no extraction strategy matched" SKIP (recorded residual).
- url tier 5 (`url-probe`): cannot distinguish "all absent" from "network down" → SKIP.
- Web-server producers `sudo rm -rf` the shared SUCCESS marker without a lock (real only with
  2+ alternatives enabled; carried open per the F4 ruling).
- `make soft-restart` / `make save` destructive-surprise semantics (see `CLAUDE.md` Gotchas +
  `docs/BLAST-RADIUS.md`) — unchanged, listed for the executor's awareness.
- The armed autonomy itself: permission-swap project arm is cwd-keyed and invisible from
  other directories; a drifted Bash cwd silently voids ALL project-scope gate bypasses (see
  constraints below).

## Explicitly NOT in this plan (negative space — protects the executor)

- `/stack/projects/*` subprojects (own plans; scout + twes unified 2026-08-31).
- `~/.claude` anything: the autonomy toolchain (gates-bypass, permission-swap, full-auto) is
  SHIPPED and out of scope; the developer's global framework files are never written from
  here.
- `~/.claude/plans/*` plan-mode scratch files: leave them.
- D2 + bundle-adoption ruling: cross-repo developer rulings, record-only.
- No new services, no version bumps (`/bump-versions` is its own workflow), no
  `make hard-restart`/`soft-restart`/`save`, no `docker volume rm` — nothing destructive; the
  ONLY container operations permitted are Track 2b's single-service recreate + login, and
  only if the stack is already up.
- No reviewer panels, no named subagents, no teams (advisor-only ruling).
- Commented-out installs (deno aleph/mandarinets) stay out.

## Inputs still owed BY THE DEVELOPER (the only ones — nothing else blocks)

1. A supervised moment to run the full rebuild/bring-up that closes F3's race-serialization,
   F4's live fail-fast, and Track 5's live reinstall-on-bump `UNCERTIFIED` labels
   (`make down-n-rebuild-force-recreate`, 10+ min, heavy-build SIGKILL history on this box —
   their call when).
2. Post-push signing (rewrites SHAs; the close-out note covers the reset dance).

## Executor session constraints (the delta that bites THIS work — repo CLAUDE.md still applies in full)

- **Autonomy**: gates are bypassed and certification is advisor-only (ruling above). The
  5-round advisor escalation cap still asks via AskUserQuestion — that is the ONLY permitted
  question.
- **Never `cd` away and stay**: a drifted Bash cwd re-arms every gate silently (project-slug
  sentinels are LIVE-cwd-keyed) and can target the wrong git repo (`~/.claude` is a repo).
  Absolute paths + `git -C /stack` always; if a command must `cd`, return in the same
  command.
- **Write/Edit tools only** for file changes — bash-written files bypass ALL lint/format
  hooks.
- **`git diff` is difftastic here**: for any programmatic diff inspection use
  `git --no-pager -c core.pager=cat diff --no-ext-diff`; use `git grep`, never `grep -rn`,
  for completeness sweeps.
- **compose config always `-q`** (or `--format json | jq` one key) — plain `config` prints
  all secrets.
- **Test-suite tallies**: only the suite's own final line counts; `--section` lists are
  COMMA-separated; never edit a test file while a background run executes it.
- **Commits**: master only, plain `git push`, fixed identity, no trailers, conventional
  prefixes, one self-contained green commit per finding/boundary as specced.
- **Plan file discipline**: append rulings/outcomes to THIS file in the same change as the
  work; this file is the record.

## Verification (whole plan)

1. `docs/plans/` contains exactly `MASTER.plan.md`; `docs/archive/plans/` holds the 5 moved
   files, contents `git diff`-identical to their pre-move blobs.
2. Track 0 battery green at baseline AND at close-out; every new test suite red-first-proven
   and sabotage-checked in its own commit history (commit messages say so).
3. Each of the 13 findings has a terminal state in this file: FIXED (SHA) /
   REFUTED-AT-EXECUTION (evidence) / CARRIED (register entry) — none silently dropped.
4. Track 5: both inventories recorded in the appendix; every class-3 (runtime-installed)
   `GLOBAL_STACK_*_VERSION` var is gated via `gs_version_gate` or explicitly classified
   otherwise; the seed-list gaps (deno, bun, deployer, symfony-cli, laravel/installer,
   android, …) all closed or REFUTED with evidence.
5. `git grep -l 'MASTER-TRIAGE'` in tracked files returns only historical/archive
   references; the gitignored triage file carries the superseded banner.
6. Completion report names every UNCERTIFIED-BY-EXECUTION dimension in those words.
