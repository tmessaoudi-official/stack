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

- [2026-09-02] AGREED (Track 1b shape): the fix is a branch, not a format change.
  `_gs_eu2_shown_value` in `core/parse.sh` prints the bare marker for an absent value and
  keeps `%q` for a real one — both halves matter, so `t121d` asserts a real malformed value
  (`(depends-on:a b)` → `a\ b`) is STILL escaped. It is green before the fix and red only if
  the fix over-reaches; sabotage S5 (drop `%q` outright — the lazy fix) reds exactly it, and
  S4 (re-escape the marker) reds the other three. Neither mutation is caught by the other's
  test, which is why both exist.
- [2026-09-02] NOTED (Track 1b test-construction trap): a bare `# @todo env-update` with
  nothing after it is not treated as an annotation at all, so it never reaches the
  no-TYPE:IDENTIFIER branch. `t121c` reaches it with a flags-only annotation
  (`(channel:rc)`), where the value is emptied by hoisting rather than by omission. The first
  draft used the bare form and went green against the UNFIXED parser — a passing test over a
  path that never ran.
- [2026-09-02] NOTED (suite runtime): the env-update suite exceeds 15 minutes wall-clock and
  cannot complete in one foreground tool call; a background run is stopped at turn end. It is
  run as four disjoint `--section` chunks (1-30 / 31-60 / 61-95 / 96-121, ~2 / 3.5 / 6 / 1
  min), each reporting its own authoritative `ALL PASSED ✓ N / N`. The close-out battery must
  budget for this. Post-Track-1 total: **844** (195 + 246 + 242 + 161) = baseline 836 + 4
  (§120) + 4 (§121).

- [2026-09-02] REVISED (Track 3c — `set -euo pipefail` is NOT applied to
  `bin/open-all-envs.sh`, and the plan's instruction to add it is withdrawn): two
  independent grounds, either sufficient. (1) **Paste safety.** The script is
  byte-identical-paired with `templates/tips/open-many-links.md`, whose block is meant to be
  pasted into a live shell — the repo already carries a rule for exactly this file requiring
  the `(cd X && cmd)` form over `cd || exit`. `set -e`, `set -u` and a bare `exit` all
  terminate the developer's interactive shell, so strict mode would turn a documented tip into
  a terminal-killer. (2) **The script legitimately runs commands that fail.**
  `npm --global outdated` returns non-zero whenever anything IS outdated
  [Verified: `npm --global outdated; echo $?` → **1** on this host today], so `set -e` would
  abort at `:183` and the python and sdkman sections would never run — strict mode would make
  the script *less* correct, not safer. What replaces it: the two real defects are fixed at
  the root (absolute repo-root `.env`; capture-and-restore of the sdkman config), and the
  zero-link failure exits only when not interactive (`[[ "$-" == *i* ]]`), which is the same
  dual-surface contract the `(cd X && cmd)` rule already encodes.
- [2026-09-02] AGREED (Track 3c trap design): the restore is trapped on **EXIT only**, and the
  handler deliberately never clears the trap. Trapping INT/TERM as well is the trap that looks
  like the safe choice and is not — a handler that RETURNS hands control back to the script,
  so the remaining lines would rewrite the config again with nothing armed to undo them. Not
  needed either: a non-interactive bash killed by INT or TERM runs its EXIT trap and stops
  [Verified: exit 130 / 143, the line after the kill never executed]. The handler is idempotent
  (`[[ -f "${bak}" ]] || return 0`) because it genuinely runs twice — once explicitly, once
  from the trap, and a group signal can even run it in a subshell as well. The trap is not
  armed in an interactive shell, where it would displace the developer's own EXIT trap.
- [2026-09-02] NOTED (Track 3c test-construction trap — the second "green over a path that
  never ran" of this plan): the interrupt case first used `sdk() { kill -INT $$; }`. A SIGINT
  raised from **inside a pipeline** is swallowed — the script calls `sdk list … | grep ""`, the
  loop ran to completion and exited 0 [Verified: minimal repro prints `REACHED-END`, rc=0;
  the identical kill outside a pipeline exits 130]. The faithful vector is `kill -INT 0` (a
  terminal signals the whole process group), which requires the case to run under `setsid -w`
  or it takes the suite down with it. It also exercises the handler's idempotence for free:
  the subshell runs the EXIT trap too.
- [2026-09-02] AGREED (Track 3c — the doc pairing is now EXECUTABLE, not a convention): the
  `open-many-links.md` block was regenerated mechanically from `tail -n +2` of the script
  rather than hand-synced, and `open-all-envs.test.sh` case 6 asserts the pairing
  (`diff` of script lines 2-N against doc lines 9-(N+7), plus a guard that the doc's two extra
  trailing lines still exist so the +7 offset stays true). Sabotage S6 — one digit changed in
  the doc alone — reds exactly that one case and nothing else. The script also gained the
  trailing newline it was missing, without which the diff can never be byte-exact.
- [2026-09-02] CONFIRMED-AT-EXECUTION (Track 3c F12 is destructive on the SUCCESS path, as the
  earlier correction predicted): the red baseline shows a fully successful run leaving the
  developer's config as the single line `sdkman_healthcheck_enable=false`, with a seeded
  `sdkman_debug_mode=false` **gone**. Interrupted mid-run it is worse — the file is left
  `<deleted>`, because `rm -rf` has already run by then (sabotage S1). Red baseline 10/12 →
  12/12 after the fix; six sabotages, all red for their stated reason, all restores
  `cmp`-verified. Live end-to-end run against the real 380-annotation `.env` with a temp HOME:
  **171 URLs enumerated, rc=0**, real `~/.sdkman/etc/config` md5 unchanged, and the temp home
  left with no config file behind.

- [2026-09-02] CORRECTION (Track 3b — the existing suite PINNED the F8 defect): case 4 of
  `bin/tests/check-image-versions.test.sh` asserted `[[ -z "$out" ]] && ok "missing-env-var:
  skipped silently"`. The silent skip at `:83` was not merely untested, it was **encoded as
  expected behaviour**, so fixing F8 required flipping an existing green assertion rather than
  only adding new ones. Worth generalising: an extend-not-create evidence step must read the
  existing assertions for the defect before adding cases beside them, or the fix and the suite
  contradict each other.
- [2026-09-02] REVISED (Track 3b F8 — the plan's guard condition would have cried wolf): the
  plan specifies "zero comparisons with >0 Dockerfiles → WARN". That fires on a tree whose
  services all chain `FROM ${GLOBAL_STACK_VERSION}`, where zero comparisons is the CORRECT
  answer and nothing is wrong [Verified: sabotage T3 removes the extra gate and case 3
  immediately reds with `WARN: 0 image service(s) … the version check did NOT run`]. The guard
  implemented is therefore gated on **candidates** — services whose `FROM` actually references
  a `GLOBAL_STACK_IMAGE_*_VERSION` — and fires only when candidates > 0 and comparisons == 0.
  The root fix is one level lower and is what the plan's own diagnosis pointed at: `:83` no
  longer skips in silence at all, it names the service and which side is unreadable. The
  aggregate is the backstop, not the mechanism; it also catches the case the plan's version
  misses entirely — 10 of 11 compared and one silently dropped.
- [2026-09-02] CONFIRMED-AT-EXECUTION (Track 3b F9 + the non-vacuity re-check it demands): the
  default env file is now `.env.local` when present, `.env` otherwise, and every WARN names the
  file it read. Because the compared values change, Track 0's "silent AND non-vacuous" baseline
  had to be re-established rather than assumed: under the new default the real repo yields
  **11 candidates, 11 comparisons, 0 dropped**, reading `/stack/.env.local` [Verified: `bash -x`
  trace — 12 `_gs_civ_candidates=` and 12 `_gs_civ_checked=` lines = init + 11 each], output
  silent, `make check-image-versions` rc=0. Silence still means clean; it no longer means
  "examined nothing". F14 done in the same commit: `git update-index --chmod=+x` →
  `git ls-files -s` reports `100755`, and case 14 asserts it so `core.fileMode=false` cannot
  quietly lose it again. Suite 17 → **30/30**; five sabotages, all red for their stated reason,
  all restores `cmp`-verified.

- [2026-09-02] CONFIRMED-AT-EXECUTION (Track 3a/3d — both Makefile findings reproduce, and the
  sandbox that proves them is cheaper than expected): `wait-healthy` is testable in a
  copy-to-tempdir tree holding nothing but the `Makefile` and a two-line `.env.local`, with a
  stub `docker` answering the two shapes the recipe uses (`ps -q` and `ps --format
  "{{.Health}}"`). The whole repo is not needed, and `tools/errors/` then resolves inside the
  sandbox instead of the real tree — which matters, because the target's failure branch reads
  that directory. F6 red baseline: `Stack settled: 0 healthy, 0 failed`, **rc=0**, with the
  stack down. F7 red baseline: `sed: can't read .env.local` on the first `make` of a clone.
  New suite `bin/tests/wait-healthy.test.sh` **9/9**; `makefile-posix` 5 → **7/7**.
- [2026-09-02] AGREED (Track 3a — the F6 suite guards BOTH directions): three of its nine cases
  exist to stop the fix over-reaching, not to prove it. A count guard that returned too eagerly
  would make `wait-healthy` stop waiting, which is the same class of silent wrong answer in the
  other direction — so case 4 drives the stub `starting` → `healthy` and asserts the target
  really spent a ~10 s settle cycle. Sabotage M3 is the one that matters most: it leaves the
  new message intact and changes only `exit 1` → `exit 0`, and the suite still reds, so the
  exit code is pinned independently of the wording.
- [2026-09-02] AGREED (Track 3d — the guard goes on the shell call, not on stderr): the fix is
  `$(shell test -f <file> && sed …)`, never `2>/dev/null`. Redirecting would silence the
  fresh-clone case and an `.env.local` that exists but is genuinely unreadable, which is a real
  failure this repo would then never report. Non-vacuity kept on both sides: the suite asserts
  `make help` still produces output on the fresh clone (so a silent stderr is not a make that
  died early), and the real repo still resolves **885** `GLOBAL_STACK_*` variables through the
  guarded export.

- [2026-09-02] CONFIRMED-AT-EXECUTION (Track 4a — F13 reproduces on BOTH halves, on real data):
  red baseline 6/12 — the hook emitted **5** false port warnings on `.env.local` and 1 on
  `.env`, and did not match the range-style var at all. The consumer forms are now pinned:
  `local.05…/docker-compose.yaml:161` is `${VAR:-}:${VAR:-}` and `Makefile:170` is
  `--publish ${VAR}:5000` (both supply the colon), against `01localstack-localstack:36`
  `${VAR:-}4510-4559` (concatenating). After the fix the hook is silent on both real files;
  strip the colon from that one real variable, against the REAL compose tree (temp dir with a
  symlinked `docker/`), and it fires naming exactly that variable — so the silence is
  certified non-vacuous rather than assumed. Four sabotages red for their stated reason;
  E4 (drop the already-terminated skip) produces **53** false warnings on the real
  `.env.local`, which is the scale of noise the consumer key removes.
- [2026-09-02] AGREED (Track 4a — the vacuity guard is part of the fix, not decoration): a
  consumer-keyed check with no consumer files to read has examined nothing, and reporting that
  as clean is how a guard quietly stops guarding. When port candidates exist and the glob
  matches zero compose files, the hook now says the port check could not run. Same shape as the
  Track 3b aggregate; both come from the same lesson — silence must mean "checked and clean",
  never "did not look".
- [2026-09-02] NOTED (CLAUDE.md § Gotchas corrected in the same commit): the standing entry
  "Port vars must end with `:` when set" was **wrong for five of this repo's port vars** and is
  the belief that produced the buggy hook. Rewritten to state the consumer rule, with both
  consumer forms and the line numbers.

- [2026-09-02] CORRECTION (Track 3c follow-up — the F12 SAFETY NET had destructive failure
  paths of its own, and none of S1-S6 touched them): a backup that silently did not happen is
  worse than no backup, because the restore then "restores" by deleting. Three shapes, all
  real: (1) `mktemp` fails while the config exists → the backup variable is empty, restore
  takes the never-existed branch and `rm -f`s the developer's file [Verified: standalone probe
  printed *"would rm -f the developer's config"*]; (2) the capture `cp` fails into the file
  `mktemp` already created → a 0-byte "backup" restores cleanly over the original AND passes
  `cmp`, both sides being empty; (3) the restore's own WARN said *"your original is kept at
  <bak>"* while the caller deleted that backup on the very next line. Fixes: the capture is
  verified with `cmp` and, when it fails, the ENTIRE sdkman block is skipped — never write to a
  file you could not back up; the backup is deleted inside the restore and only after a
  verified copy; the caller's trailing `rm -f` is gone. Two new cases (`TMPDIR` pointed at a
  missing directory; a stub `cp` that fails only when the config is the DESTINATION, so the
  capture succeeds and the restore does not). Sabotages S8/S9 red them.
- [2026-09-02] NOTED (UNCERTIFIED-BY-EXECUTION, named rather than hidden): the separate
  `_GS_EU_MD_SDK_CFG_EXISTED` flag is **defence in depth, not a certified guarantee** —
  sabotage S7 reverts it to the old `[[ -n "${BAK}" ]]` inference and NOTHING behavioural reds,
  because the `_SAFE` guard means restore is never reached in the state that distinguishes
  them. It is kept so `_gs_eu_md_sdk_cfg_restore` is correct on its own terms if the block is
  ever moved or reused. Two further dimensions of this track are also uncertified: the
  `[[ $- == *i* ]]` interactive-paste path has never executed (every case runs
  non-interactively), and `make wait-healthy` has never been run against a REAL running stack —
  the suite proves the recipe's logic against a stub `docker`, not that a live compose
  deployment emits the states the stub emits.
- [2026-09-02] NOTED (a FLAKY test was nearly committed — the interrupt vector): the first
  green 12/12 was luck. `kill -INT 0` reaches the process group the way Ctrl-C does, but races
  the pipeline's own completion: measured **11/12 runs exit 130, 1/12 exits 0**, and the suite
  reproduced that as 2 passes and 1 failure in three consecutive runs. The race is the missing
  dwell after the kill — the stub returned immediately, so bash could reap the pipeline before
  acting on its pending signal. Replaced with `kill -TERM $$`, **12/12 deterministic**, which
  also removes the `setsid -w` isolation the group signal required. The guarantee is unchanged
  (the shell dies mid-block, only the EXIT trap can restore) and that trap fires for INT and
  TERM alike. Suite re-run four times: 16/16 each. The lesson generalises past this repo: a
  signal-based test needs its determinism MEASURED over repeats, not observed once.

- [2026-09-02 15:40] CORRECTION (Track 2a): the stale-error-clearing literal
  `rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"` exists at
  **19** sites, not the 10 this plan states — `git grep -n 'PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN'
  -- docker/config/dist/bin | grep 'rm -f'`. The convention is byte-matched at all three new
  sites. Measured hazard, recorded not fixed: with an unset token the literal expands to
  `rm -f "<errors>/"`, which is *Is a directory*, rc 1, and under `set -eE` + the ERR trap aborts
  the script (probe: `bash -c 'set -eEuo pipefail; trap ...; rm -f "$1/"'` → TRAP-FIRED rc=1).
  All 19 existing sites already carry that shape; adopting it adds no new class of failure.
- [2026-09-02 15:40] AGREED (Track 2a): the token invariant gains its FIRST documented exception.
  The three web servers keep the shared `successes/web-server` write and gain per-service error
  tokens. Three claim surfaces had to move with the code or they would have made the change look
  like a defect: `CLAUDE.md` § Gotchas (the invariant itself), `.claude/skills/validate/SKILL.md`
  step 8 (whose loop would emit a **P0 that is not one** — the three have no success literal in
  their HTTP healthcheck at all, so `err_token != ok_token` fires unconditionally), and
  `.claude/skills/stack-lenses/SKILL.md` in both places it states the invariant. Found by the
  blast-radius lens; none was in the plan.
- [2026-09-02 15:40] AGREED (Track 2a): `base-wait-for.sh` writes the three tokens as full
  `errors/<name>` literals rather than composing them from a variable, purely so §21c can grep
  them. The guard reads the tokens from the three compose files and asserts wait-for names each
  one — three literals in one file coupled to three literals in three other files is exactly the
  shape that drifts silently. Sabotage W1 (rename in compose only) reds it.
- [2026-09-02 15:40] NOTED (Track 2a) → register: a **disabled** alternative cannot clear its own
  stale token. caddy fails → `errors/caddy`; the developer switches `COMPOSE_FILE` to nginx and
  runs `up` **without** `make down`; consumers now fail-fast on a token whose producer is no
  longer in the stack. The plan's third safety clause ("`make down` clears `errors/*`") is what
  covers this, and it is a real precondition, not a proof. Carried, not fixed.
- [2026-09-02 15:40] REVISED (Track 2c): the plan scopes F8 to pyenv. `rbenv:55` and `nvm:57`
  have the **identical** raw-vs-resolved shape and all three carry the same comment claiming the
  marker "== the raw value for fully-qualified pins". It is latent only because every pin in
  `.env` is fully qualified today (`3.14.7`, `3.4.10`, `v24.19.0`); a partial pin — the entire
  reason `find-latest` and the `_AS` label scheme exist — reinstalls on EVERY boot. Full-set
  coverage puts rbenv in scope. **nvm is carried**: `nvm version` needs nvm sourced, which happens
  ~130 lines after the gate, so resolving early there is a restructure, not a fix.

- [2026-09-02 16:20] AGREED (Track 2b): the plan's "enumerate readers and map each to its service
  compose file" is **one line**, not thirty-three. The extends chain resolves to a single shared
  environment fragment: every tier-02/03/04/05 service reaches
  `docker/config/compose-fragments/base-env.compose.yaml` through `base`, `base-6vol` or one of the
  five `<lang>-packages` fragments (which themselves extend base/base-6vol), and `01caddy`,
  `03flutter3`, `01selenium-*` and `02sonarqube` extend it directly. Declaring the var there covered
  **32 services** in one edit — the count is not asserted from a list kept in the test, it is read
  out of the resolved config. `00base` needed a second line: it *is* the image the fragment's
  consumers are built FROM, so it cannot extend it and repeats the list inline.
- [2026-09-02 16:20] NOTED (Track 2b): `02sdkman` receives the value and **ignores it**. Its
  `USE_LOCKS` guards are commented out (`TODO.md:197`) so `flock` runs unconditionally, because the
  script leaks fd 200 when locks are disabled. The plumbing lands for all six readers; toggling
  works for five. Not fixed here — it is a restructure of the acquire/release blocks, and TODO.md
  already tracks it.
- [2026-09-02 16:20] NOTED (Track 2b): evidence step (3) could not run —
  `docker compose ps -q | wc -l` = **0**, the stack is down. Per the plan's own instruction the
  run stops after step (2), and BOTH halves are `UNCERTIFIED-BY-EXECUTION`: value visibility inside
  a running container, and lock-serialized tier-03 parallel install.

- [2026-09-02 17:05] CORRECTION (Track 2c): §9 of `startup-prologue.test.sh` was **green on the
  defect** — it asserted `gs_version_gate .*${PYTHON_VERSION}` / `${RUBY_VERSION}` as the required
  compare target, which is exactly the raw pin F8 is about. Same shape as Session B's
  `check-image-versions` case 4. Updated, not routed around: §9 now asserts the resolved value, and
  asserts the raw pin where it belongs — as the argument handed to `find-latest` — plus the original
  never-`${PYENV_VERSION}` contract it was written for.
- [2026-09-02 17:05] NOTED (Track 2c): behaviour change beyond "stop the spurious reinstall", stated
  because it is not obvious from the diff. A partial pin now **re-resolves on every boot**, so a
  pyenv/rbenv upgrade shipping newer definitions triggers a genuine reinstall-with-WARN. That is the
  gate's purpose (a version bump must reinstall), and it is why prefix-tolerant string matching was
  rejected as the alternative fix: it would silently pin a partial pin to whatever it first resolved
  to. Recorded in the code comments and in `CLAUDE.md` § Gotchas.
- [2026-09-02 17:05] NOTED (Track 2c): the resolved value is REUSED at each install site
  (`pyenv:137`, `rbenv:127`) rather than recomputed, so "gate on the value the marker gets" holds by
  construction. Sabotage P2 restores the second call and reds §22e — with a second call the two can
  disagree and the mismatch returns silently. This also removed one SC2155 finding from each script
  (`export X=$(...)` → `export X="${...}"`), so both files' shellcheck sets shrank by one.

- [2026-09-04 09:38] AGREED (Track 5a): Inventory A is **412** vars, not the ~380 estimated at
  planning time, and splits 38 / 160 / 138 / 73 / 1 / 2 across classes 1 / 2 / 2↑ / 3 / 3U / 4.
  The **2↑** class is new and was not anticipated by the plan: 138 `_DEFAULT_*` vars are
  upstream of a gated class-2 slot through `.env`'s own `${}` expansion, so they are already
  covered *through their referrer*. Recording them as dead — which an audit keyed only on
  file references would have done — would have put ~138 live vars into the plan as dead.
- [2026-09-04 09:38] AGREED (Track 5a): the **manager `warn-gated` shape is an accepted
  pattern, not a gap**. Seven managers (nvm, phpbrew, pyenv, rbenv, sdkman, rust, fvm) call
  `gs_version_gate … >/dev/null || true` for the WARN and decide with an adjacent inline
  compare. `CLAUDE.md` § Gotchas documents this deliberately, and `nvm` gates on the raw pin
  by necessity (its resolver needs nvm sourced later in the file), pinned by
  `startup-prologue.test.sh` §22f. 5b must not converge these.
- [2026-09-04 09:38] AGREED (Track 5a): the seed table was **incomplete in three groups** and
  **wrong in one**. Added: `phpmyadmin` (write-only marker, same defect as deployer), the five
  00base tools installed at runtime from `base-start.sh:29-38` (go/zig/hurl/mise/awscli), and
  the five rust tools from `rust-start.sh:51-55` whose image-ENV delivery makes them look
  build-time. Removed: `wkhtmltopdf` and `sonar-scanner-cli` are class 1 (image build), so
  they are already covered and leave row 21. Every `*_LATEST` variable in
  `phpbrew-install-tools.sh` / `rust-iou.sh` / `sdkman-start.sh` is assigned from the `.env`
  pin with its curl line commented out, so those compares are against the pin and the
  sdkman/rust gates cannot WARN spuriously.

- [2026-09-04 12:18] AGREED (developer ruling, Track 5b): **the scope guard at `:793` is
  amended.** Install-logic changes are permitted *where a `.env` pin cannot otherwise hold*.
  First and so far only instance: `phpbrew-install-tools.sh:32` installs `laravel/installer`
  unpinned and `:34` then runs `composer global update --ignore-platform-reqs
  --with-all-dependencies`, which would move any tool row 17 gates back off its pin — so a
  gate alone cannot work there. Everywhere else the guard stands unchanged: no tool
  additions or removals, no version bumps, no install-logic rewrites beyond gate + marker
  discipline. The mechanism at `:34` (delete versus constrain) is NOT ruled here — deleting
  stops every global composer package updating, not only gated ones, so whichever row 17
  chooses gets its own dated entry.
- [2026-09-04 12:18] AGREED (developer ruling): **the five defect groups found by the
  2026-09-04 five-lens sweep are absorbed into this plan as rows 25–29**, rather than
  recorded and left. They are: the three web-server `*-iou.sh` exit-1 exemptions plus the
  hardcoded `WEB_SERVER_SCRIPTS` array that hid them (25); the 14 Dockerfiles carrying
  `# @todo fix pin versions` (26); the `CLAUDE.md` corrections (27); the
  `.claude/settings.json` `ask`-tier contradiction (28); and the `TODO.md` prune (29).
  This **supersedes the 2026-09-03 decline** of the first, the test-array and the
  settings.json items — they were declined then and are in scope now. Rows 27 and 28 are
  `blocked`, not `todo`: both touch classifier-blocked files, so their terminal state is a
  handover script, never a commit by Claude. Row 28's *direction* is still unruled and sits
  in `### Needs input`.

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
- **Web-server shared SUCCESS marker, unlocked** (carried from Track 2a as the plan directed):
  `caddy`/`nginx`/`httpd` each `sudo rm -rf` the shared `successes/web-server` with no lock. A real
  race only when 2+ alternatives are enabled at once. Not fixed in Track 2a.
- **A DISABLED web-server alternative cannot clear its own stale error token** (found in Track 2a,
  not anticipated by the plan). caddy fails → `errors/caddy`; the developer edits `COMPOSE_FILE` to
  nginx and runs `up` **without** `make down`; consumers now fail-fast on a token whose producer is
  no longer in the stack. The clause that covers it — "`make down` clears `errors/*`" — is a real
  precondition, not a proof. The alternative (COMPOSE_FILE introspection in the consumer) is
  REJECTED by ruling, so this stays carried.
- **nvm still gates on the raw pin** (hunt F8, fixed for pyenv/rbenv in Track 2c). Its resolver is
  `nvm version`, which needs nvm sourced ~130 lines below the gate. Latent while every node pin is
  fully qualified; a partial pin (`v24`) would recompile every boot. Pinned by §22f so it cannot be
  "fixed" by copying the pyenv shape into a script where the resolver is not yet available.
- **`02sdkman` receives `GLOBAL_STACK_USE_LOCKS` and ignores it** (Track 2b). Its guards are
  commented out (`TODO.md:197`) because the script leaks fd 200 when locks are disabled. Plumbing
  reaches all six readers; toggling works for five. The fix is a restructure of the acquire/release
  blocks, already tracked in `TODO.md`.
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

---

## Appendix — Track 5a bidirectional audit (2026-09-04)

Required location per Track 5a. Both inventories were enumerated **independently**;
neither was derived from the other, and neither started from the seed-list table.
Everything below is reproducible from the commands quoted — no script was added to
`bin/` (scope guard).

### Method, and the four defects it had to survive

Classification is by **consuming mechanism**, computed from four indexes joined against
the var list rather than 380+ per-var greps. Four defects were found and fixed *during*
the audit; each one had changed the class-3 count, so they are recorded here rather than
silently corrected:

1. **Compose fragments were not globbed.** `docker/config/compose-fragments/*.compose.yaml`
   carries every `*_INSTALL_PACKAGE_*` mapping (151 lines). Without it all 160 class-2
   vars fell through to "dead".
2. **The image-ENV delivery path was missed.** A var can reach a container via
   `environment:` **or** via the Dockerfile `ARG`→`ENV` flow (`00base/Dockerfile:75` ARG,
   `:150` ENV). Classifying on the compose channel alone under-counted class 3 by eleven
   runtime-installed tools (rust `cargo-*`, jujutsu, mergiraf, go, zig, hurl, mise…).
3. **Alias direction was inverted.** For `- KEY=${VALUE}` the `.env` var is the `${}`
   right-hand side, not the first match on the line. Only bites where both sides are
   `GLOBAL_STACK_*_VERSION` names — `03php8-4/docker-compose.yaml:24`
   (`- GLOBAL_STACK_FRANKENPHP_VERSION=${GLOBAL_STACK_FRANKENPHP_8_4_VERSION}`), which
   misfiled the three per-version frankenphp source vars.
4. **`.env`-internal `${}` expansion was ignored.** 138 `_INSTALL_PACKAGE_*` vars are
   defined as `${GLOBAL_STACK_*_DEFAULT_*_VERSION}` (`grep -c '_INSTALL_PACKAGE_.*=\${GLOBAL_STACK_[A-Z0-9_]*_DEFAULT_' .env` → 138).
   The `_DEFAULT_*` family is therefore **upstream of a gated class-2 slot**, not dead.
   Recording ~138 live vars as dead would have been the worst outcome this audit could
   produce, since 5b and every later session would build on it.

Two traps worth carrying: `docker/images/local.*/` is **gitignored**, so `git grep` cannot
see it — those two dirs on disk were read directly and contribute **0** `_VERSION` hits;
and `docker/buildkit/Dockerfile` lives outside `docker/images/`, so its ARGs need an
explicit index entry. Per RTK-local.md, presence/absence was never concluded from
rtk-rewritten `git grep` output — the last four vars were re-checked through `rtk proxy`
after a filtered run returned a false empty.

### Inventory A — every `GLOBAL_STACK_*_VERSION` in `.env`

```
grep -oE '^GLOBAL_STACK_[A-Z0-9_]+_VERSION' .env | sort -u | wc -l   →  412
```

**412**, not the ~380 the Track 5 text estimated. The count is the figure Done-when #1
checks; re-run the command rather than trusting this number if `.env` has moved on.

| Class | N | Meaning | Disposition |
|---|---|---|---|
| 1 | 38 | image tag / Dockerfile `ARG` at build | ALREADY covered (env-scan ARG propagation + `check-image-versions` + rebuild) — record, don't touch |
| 2 | 160 | `setup-packages.sh` pkg slot | ALREADY gated (`gs_version_gate` at `base-setup-packages.sh:97`) — record |
| 2↑ | 138 | `_DEFAULT_*`, upstream of a class-2 slot by `.env` expansion | ALREADY gated *through its referrer* — record; a bump propagates at compose resolution. **No compose entry is needed** for these: env-scan carries the upstream var, so the expansion resolves before any container sees it [Verified: `grep -c '_DEFAULT_.*_VERSION=' .env.local` → 138]. The new-var cascade rule (above) therefore does not apply to a `_DEFAULT_` var |
| 3 | 73 | runtime install script | **THE TARGET SET** — see the worklist below |
| 3U | 1 | delivered to a container, no in-repo reader | record |
| 4 | 2 | dead | record as such |
| | **412** | | |

**Class 1 (38)** — `GLOBAL_STACK_` prefix and `_VERSION` suffix elided; braces enumerate
the family in full:
`BAT_{-}, CLAUDE_{CODE}, CORENTINTH_{IT_TOOLS}, DIFFTASTIC_{-}, DOCKER_{BUILDX, COMPOSE, TOOLS_PATH}, FRANKENPHP_{WATCHER}, GITLEAKS_{-}, HADOLINT_{-}, IMAGE_{AXLLENT_MAILPIT, DPAGE_PGADMIN4, EPICLABS_DOCKER_ORACLE_XE_11G, KEYCLOAK_KEYCLOAK, MARIADB13, MONGO7, MONGOCLIENT_MONGOCLIENT, MYSQL9, POSTGRES18, SELENIUM_STANDALONE_CHROME, SELENIUM_STANDALONE_FIREFOX, UBUNTU}, LOCALSTACK_{LOCALSTACK}, MOBY_{BUILDKIT}, PODMAN_{COMPOSE}, REDIS_{-}, RTK_{-}, SHELLCHECK_{-}, SHFMT_{-}, SONARQUBE_{-}, SONAR_{SCANNER_CLI}, SOPS_{-}, TASK_{-}, VALKEY_{-}, WKHTMLTOPDF_{-}, YAMLFMT_{-}, YQ_{-}`
plus `DOCKER_LOCAL_REGISTRY_VERSION` — classified by hand, its only consumer is
`Makefile:174` (`registry:${…}`), which no compose/Dockerfile index covers.

**Class 2 (160)** — `JAVA26_{SDKMAN_INSTALL_PACKAGE_GRADLE_VX2, …_GROOVY_VX2, …_SPARK_VX1, …_SPARK_VX2} (4)`,
`JAVA_INSTALL_PACKAGE_{ANT, GRADLE_VX1, GRADLE_VX2, GROOVY_VX1, GROOVY_VX2, JBANG, KOTLIN, MAVEN_VX1, MAVEN_VX2, MAVEN_VX3, MICRONAUT, POMCHECKER, QUARKUS, SCALA, SPARK_VX1, SPARK_VX2, SPRINGBOOT, TOMCAT} (18)`,
`NODE24_INSTALL_PACKAGE_{TYPES_NODE} (1)`, `NODE26_INSTALL_PACKAGE_{TYPES_NODE} (1)`,
`NODEEDGE_INSTALL_PACKAGE_{CORDOVA_RES, TYPES_NODE} (2)`,
`NODE_INSTALL_PACKAGE_{…60 slots…} (60)`, `PHP8_{5_INSTALL_PACKAGE_OPCACHE} (1)`,
`PHPEDGE_INSTALL_PACKAGE_{AMQP, APCU, GD, IMAGICK, MEMCACHED, OPCACHE, PECL_HTTP, PHALCON, RAPHF, REDIS, SSH2, XDEBUG, YAML} (13)`,
`PHP_INSTALL_PACKAGE_{…34 slots…} (34)`, `PYTHON_INSTALL_PACKAGE_{…24 slots…} (24)`,
`RUBY_INSTALL_PACKAGE_{FASTLANE, GOOGLE_API_CLIENT} (2)`.
The 60/34/24 slot names are exactly the `_DEFAULT_` names listed next — the two families
are one-to-one by construction.

**Class 2↑ (138)** — `JAVA_DEFAULT_{…18}`, `NODE_DEFAULT_{ANGULAR_CLI, ANGULAR_DEVKIT_ARCHITECT, ANGULAR_DEVKIT_SCHEMATICS_CLI, BIOMEJS_BIOME, CAPACITOR_CLI, COLORS, COMMITIZEN, COMMITLINT_CLI, COMMITLINT_CONFIG_CONVENTIONAL, CONCURRENTLY, CORDOVA_RES, CORDOVA, DEGIT, EMBER_CLI, ESLINT, EXPRESS_GENERATOR, GATSBY_CLI, GIGET, GITLAB_CI_LOCAL, HONO, HUSKY, HYGEN, IONIC_CLI, KNEX, LINT_STAGED, LOOPBACK_CLI, NATIVE_RUN, NESTJS_CLI, NEWMAN, NRWL_CLI, NRWL_TAO, NX, PLAYWRIGHT, PNPM, PRETTIER_ESLINT, PRETTIER, PURESCRIPT, QUASAR_CLI, REACT_SCRIPTS, REACT, RESTIFY, SAILS, SASS, SEQUELIZE, SERVERLESS, SPAGO, TS_NODE, TSX, TYPESCRIPT, TYPES_FILESYSTEM, VITEST, VITE, VSCODE_VSCE, VUE_CLI_PLUGIN_BABEL, VUE_CLI_PLUGIN_ESLINT, VUE_CLI_SERVICE, VUE_CLI, YARN, YO, ZOD} (60)`,
`PHP_DEFAULT_{AMQP, APCU, EXIF, FFI, FTP, GD, GETTEXT, GMP, ICONV, IMAGICK, INOTIFY, INTL, LDAP, MEMCACHED, MEMCACHE, MONGODB, OPCACHE, PECL_HTTP, PHALCON, PROPRO, PSR, RAPHF, REDIS, SOAP, SSH2, SWOOLE, TIMECOP, UUID, XDEBUG, XML, YAML, ZEPHIR_PARSER, ZIP, ZMQ} (34)`,
`PYTHON_DEFAULT_{ATTRDICT3, ATTRDICT, AWSCLI_LOCAL, BLINKER, DJANGO, FASTAPI, FLASK, MYSQLCLIENT, NATSORT, PIPENV, PIP, PSYCOPG2, PYLINT, PYTHON_DOTENV, PYYAML, SETUPTOOLS, SIMPLEJSON, SQLFLUFF, UV, VIRTUALENV, WATCHDOG, WHEEL, WXPYTHON, YAMLLINT} (24)`,
`RUBY_DEFAULT_{FASTLANE, GOOGLE_API_CLIENT} (2)`. `JAVA_DEFAULT_` expands the same 18
slots as `JAVA_INSTALL_PACKAGE_` above.

**Class 3U (1)** — `GLOBAL_STACK_CORENTINTH_IT_TOOLS_NJS_VERSION`, delivered as
`NJS_VERSION` by `00corentinth-it-tools/docker-compose.yaml:18` to a third-party image;
no startup script in this repo reads it. Not a 5b row.

**Class 4 (2, dead)** — `GLOBAL_STACK_MCP_SOOPERSET_MCP_ATLASSIAN_VERSION`,
`GLOBAL_STACK_MCP_ZEREIGHT_MCP_GITLAB_VERSION`. Zero references in the tracked tree
outside `.env`. Also class 4 by the Track 5 ruling, and deliberately excluded from the
count above because they carry no `.env` var of their own: the commented-out deno
`aleph`/`mandarinets` installs — `GLOBAL_STACK_DENO_ALEPH_VERSION` and
`GLOBAL_STACK_DENO_MANDARINETS_VERSION` do exist and reach `02nvm`, but their only
consumer is commented out in `nvm-install-tools.sh`; they stay out.

### Inventory B — every gate call site and marker read/write

```
git grep -n 'gs_version_gate\|VERSIONS}/' docker/config/dist/bin/   →  169 lines, 21 files
git grep -n 'gs_version_gate()' docker/config/dist/bin/             →  1 definition
```

`gs_version_gate` is defined once, at `base-bin/global-stack-base-prologue.sh:264`, and
called from **8 files**: `base-setup-packages.sh:97` (pkg slots), `fvm-start.sh:53,79`,
`nvm-start.sh:67,97`, `phpbrew-start.sh:57,87,123`, `pyenv-start.sh:67,96`,
`rbenv-start.sh:64,93`, `rust-start.sh:32`, `sdkman-start.sh:66,89`. Every other
`tools/versions/` touch in the remaining 13 files is a raw read or write with no
content comparison driven by the helper.

### A ∩ B — the class-3 worklist, with a terminal state for every var

Five statuses. Only **exist-only** and **hand-rolled** are 5b work.

| Status | N | Meaning |
|---|---|---|
| `gated` | 13 | the helper drives the decision |
| `warn-gated` | 7 | helper called for the WARN only (`>/dev/null \|\| true`), decision by an adjacent inline compare — **the documented manager shape, an accepted pattern, NOT a gap** |
| `hand-rolled` | 9 | real content-compare against the pin, but silent and duplicated — converge |
| `exist-only` | 41 | **the gaps**: a version bump does nothing |
| `ref-only` | 1 | read for PATH construction, not an install site |
| `commented` | 2 | the deno `aleph`/`mandarinets` vars — consumer commented out, stay out |
| | **73** | sums to class 3 exactly: every var has one status, none has two |

**`gated` (13)** — via the compose alias, so the `GLOBAL_STACK_` name never appears in the
script: `NODE24`, `NODE26`, `NODEEDGE` (`node.<label>`, `nvm-start.sh:67`); `PHP8_4`,
`PHP8_5`, `PHPEDGE` (`php.<AS>`, `phpbrew-start.sh:57`, plus the edge SHA sidecar `:87`);
`PYTHON3` (`pyenv-start.sh:67`); `RUBY3`, `RUBY4` (`rbenv-start.sh:64`); `JAVA17`,
`JAVA21`, `JAVA26` (`sdkman-start.sh:66`); `FLUTTER3` (`fvm-start.sh:53`).

**`warn-gated` (7)** — the manager pattern: `NVM`, `PHPBREW`, `PYENV`, `RBENV`, `SDKMAN`,
`RUST`, `FVM`. **Do not "converge" these in 5b.** `CLAUDE.md` § Gotchas documents the
shape deliberately (managers WARN on a manager-version bump but reinstall the manager
only, with no cascade to runtimes), and `nvm` additionally gates on the *raw* pin because
its resolver needs nvm sourced ~130 lines further down — pinned by
`startup-prologue.test.sh` §22f precisely so nobody copies the pyenv shape into it.

Two write-placement worries were checked and are **not** findings: `rust-iou.sh:35` writes
the `rust` marker only from inside `rust-start.sh`'s reinstall branch (`:42-45` calls it),
and `sdkman-start.sh:95` writes the `sdkman` marker inside its own
`SDK_LATEST != SDK_CURRENT` branch. Neither rewrites its marker every boot, so neither
gate is blinded.

**`hand-rolled` (9)** — `COMPOSER`, `ZEPHIR_LANG`, `PHALCON_DEVTOOLS`, `PICKLE`, `PIE`,
`MAGO`, `CASTOR`, `FABPOT_LOCAL_PHP_SECURITY_CHECKER` in
`phpbrew-install-tools.sh` (`[[ -f phar && $X_LATEST = $(cat marker) ]]`), plus `MKCERT`
at `base-start.sh:20` (compares `mkcert --version`, no marker at all). **The `*_LATEST`
variables are not network fetches** — every one is assigned from the `.env` pin with the
curl line commented out (`phpbrew-install-tools.sh:9-10`, `rust-iou.sh:12-13`,
`sdkman-start.sh:82`), so these really are compares against the pin. The same fact
retires a worry worth recording: the `sdkman`/`rust` markers are written with the pin, so
their `:89`/`:32` gates cannot WARN spuriously.

**`exist-only` (41) — the 5b worklist.** Three of these groups are **absent from the Track
5 seed table**, which is exactly what 5a existed to find:

| Group | Vars | Site | Defect |
|---|---|---|---|
| nvm tools | `DENO`, `BUN` | `nvm-install-tools.sh` | `[ -f … ]`, no marker (seed list) |
| phpbrew tools | `DEPLOYER`, `SYMFONY_CLI` | `phpbrew-install-tools.sh:65,89` | marker written, guard checks only `-f` (seed list) |
| **phpmyadmin** | `PHPMYADMIN`, `PHPMYADMIN_TYPE` | `phpmyadmin-start.sh:43,49,57` + write-only `:76` | **NOT in the seed list** — identical write-only-marker defect to deployer |
| android | `ANDROID_BUILD_TOOLS`, `ANDROID_CMDLINE_TOOLS`, `ANDROID_NDK`, `ANDROID_NDK_BUNDLE`, `ANDROID_PLATFORM_TOOLS` | `android-start.sh:73,79` / `android-setup.sh:37` | exist-only `android.sdkmanager`; the 5 vars never compared (seed list) |
| **00base tools** | `GO`, `ZIG`, `HURL`, `MISE` (+ awscli, which has no `.env` var — `[[ ! -d … ]]`) | `base-install-*.sh`, all called from `base-start.sh:29-38` | **NOT in the seed list** — `command -v X` empty; no marker |
| **rust tools** | `CARGO_NEXTEST`, `CARGO_OUTDATED`, `CARGO_ZIGBUILD`, `JUJUTSU`, `MERGIRAF` | `rust-install-*.sh`, called from `rust-start.sh:51-55` | seed list said "audit gating"; the answer is **none** — `command -v X` empty, no marker. Delivered by image ENV, so they look build-time and are not |
| web servers | `CADDY`, `HTTPD`, `HTTPD_APR`, `HTTPD_APR_UTIL`, `HTTPD_MOD_AUTH_OPENIDC`, `HTTPD_MODSECURITY_MOD`, `HTTP_CORERULESET`, `HTTP_MODSECURITY_LIB`, `NGINX`, `NGINX_CJOSE`, `NGINX_LIBOAUTH2`, `NGINX_MOD_AUTH_OPENIDC`, `NGINX_MODSECURITY_MOD` | `{caddy,httpd,nginx}-iou*.sh` | `*_VERSION_PATH` markers declared in `*-start.sh`; **no `gs_version_gate` in any of the three** — per-site compare shape still to be read in row 20 |
| frankenphp | `FRANKENPHP`, `FRANKENPHP_8_4`, `FRANKENPHP_8_5`, `FRANKENPHP_EDGE` | `php8.4-bin/…-setup-version.sh` | no marker |
| rbenv extras | `RBENV_GEMSET`, `RBENV_RUBY_BUILD` | `rbenv-iou.sh:13-19` | **not exist-only** — guarded only by `-n VERSION` and re-cloned unconditionally *inside the manager's reinstall branch*, so a plugin-only bump does nothing while an rbenv bump re-clones both. Still a gap; different 5b shape |
| serverless | `SERVERLESS_FRAMEWORK_ELASTICMQ` | `serverless-framework-start.sh` | no marker |
| rustup | `RUSTUP_INIT` | `rust-iou.sh:9,27` | writes `rust-init` from the pin, but only ever from inside `rust-start.sh`'s reinstall branch (`:42-45`), so it never self-clears on a `RUSTUP_INIT` bump |

**`ref-only` (1)** — `NGINX_AUTOMAKE_VERSION`, used only to build `PATH`
(`nginx-start.sh:8,15`). Not an install site; not a 5b row.

**The line Track 5a asked for:** `A(class 3) − B(gated ∪ warn-gated)` = **53 vars**, of which
**50 are actionable 5b rows** (41 exist-only + 9 hand-rolled) across **11 sites**; the other
three are non-rows (1 ref-only + 2 commented-out). The five statuses sum to 73, which is
class 3 exactly — every class-3 var has one terminal state and none has two [Verified: the
status sets are bijective with the class-3 list, `comm` empty in both directions]. No
class-3 var is absent from this accounting, and no gate site in B lacks a class-3 var in A.

### What this changes for rows 15–21

- **Row 18 (rust) grows and changes shape**: the five cargo/jj/mergiraf tools are runtime
  installs delivered by image ENV, so the `.env` → compose `environment:` cascade does
  **not** currently carry them; gating them means deciding whether to add the compose
  entry or read the image ENV. That is the F3-shape hazard the plan warns about.
- **Row 21 grows**: `wkhtmltopdf` and `sonar-scanner-cli` are **class 1**, not runtime
  installs — they leave the worklist. The 00base tools (go/zig/hurl/mise/awscli) and
  phpmyadmin join it.
- **Row 20 keeps its audit step**: none of the three web-server scripts calls the helper,
  and they are the prologue-exempt ones, so row 15's helper extraction is a hard
  prerequisite for row 20 specifically.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Stage 1 — unify plans into MASTER, archive the 5 superseded | S | done | 0cc4c4d | docs/plans/*.md docs/archive/plans/*.md |
| 2 | Track 0 — baseline battery certification of HEAD | M | done | 29eaaa6 | docs/plans/MASTER.plan.md bin/tests/*.test.sh |
| 3 | Track 1a — F2 tag-flag fingerprint in all 9 fetcher cache keys | M | done | b43d74d | bin/lib/env-update/*.sh templates/tips/env-update.md |
| 4 | Track 1b — F3 `<empty>` placeholder escaping in parse errors | S | done | 2483ff6 | bin/lib/env-update/core/parse.sh bin/tests/env-update.test.sh |
| 5 | Track 2a — F4 per-service web-server error tokens | M | done | 7176367 | docker/images/01caddy/* docker/images/01nginx/* docker/images/01httpd/* docker/config/dist/bin/base-bin/*.sh |
| 6 | Track 2b — F3 GLOBAL_STACK_USE_LOCKS reaches containers at runtime | M | done | 26b9d7a | docker/images/*/docker-compose.yaml bin/tests/compose-env-plumbing.test.sh |
| 7 | Track 2c — F8 pyenv/rbenv gate on the resolved version, not the raw pin | M | done | bef24bd | docker/config/dist/bin/pyenv-bin/*.sh docker/config/dist/bin/rbenv-bin/*.sh |
| 8 | Track 3a+3d — F6 wait-healthy false-OK; F7 fresh-clone sed noise | M | done | d39dc48 | Makefile bin/tests/wait-healthy.test.sh |
| 9 | Track 3b — F8/F9/F14 check-image-versions (vacuity, .env.local, mode) | M | done | 59a6f82 | bin/check-image-versions.sh bin/tests/check-image-versions.test.sh |
| 10 | Track 3c — F11/F12 open-all-envs .env resolution + host ~/.sdkman destruction | M | done | 7d70a82 | bin/open-all-envs.sh templates/tips/open-many-links.md |
| 11 | Track 3c follow-up — sdkman backup must not destroy the file when it fails | S | done | d5adf56 | bin/open-all-envs.sh |
| 12 | Track 4a — F13 env-guard port check keyed on the consumer | M | done | f7db75b | .claude/hooks/env-guard-on-write.sh bin/tests/env-guard.test.sh |
| 13 | Track 2a docs — stop /new-service resurrecting F4; carry the four residuals | S | done | 53aff52 | .claude/skills/new-service/SKILL.md docs/plans/MASTER.plan.md |
| 14 | Track 5a — bidirectional audit (all _VERSION vars x all gate sites) into a plan appendix | L | done | 7782701 | .env docs/plans/MASTER.plan.md docker/config/dist/bin/*/*.sh |
| 15 | Track 5b — extract gs_version_gate into its own sourceable helper (prologue-exempt safe) | M | done | b27aca7 | docker/config/dist/bin/base-bin/*.sh bin/tests/startup-prologue.test.sh |
| 16 | Track 5b — gate nvm-install-tools (deno, bun) | M | done | b08ce58 | docker/config/dist/bin/nvm-bin/*.sh bin/tests/startup-prologue.test.sh |
| 17 | Track 5b — gate phpbrew-install-tools (deployer, symfony-cli, laravel/installer, ...) | L | todo | - | docker/config/dist/bin/phpbrew-bin/*.sh .env |
| 18 | Track 5b — gate rust tools (cargo-nextest/outdated/zigbuild, jujutsu, mergiraf, rustup-init); all 5 arrive by image ENV, not compose env — decide the cascade | M | todo | - | docker/config/dist/bin/rust-bin/*.sh .env docker/images/00base/* |
| 19 | Track 5b — gate android (sdkmanager + 5 uncompared vars) | M | todo | - | docker/config/dist/bin/android-bin/*.sh |
| 20 | Track 5b — gate web-server sub-components (mod_security, coreruleset, cjose, liboauth2, apr) | L | todo | - | docker/config/dist/bin/nginx-bin/*.sh docker/config/dist/bin/httpd-bin/*.sh |
| 21 | Track 5b — remainder named by 5a: phpmyadmin, 00base runtime installs (go/zig/hurl/mise/awscli), frankenphp, rbenv gemset+ruby-build, elasticmq. NOT wkhtmltopdf/sonar-scanner-cli — 5a proved those class 1 | M | todo | - | docker/config/dist/bin/*/*.sh |
| 22 | Track 5 docs — CLAUDE.md Gotchas + two-phase note once the gate is universal | S | todo | - | CLAUDE.md |
| 23 | Close-out — terminal states + SHAs in plan, full battery re-run, advisor, push | M | todo | - | docs/plans/MASTER.plan.md CLAUDE.md |
| 24 | Developer input — supervised rebuild/bring-up closing the 4 UNCERTIFIED labels | M | blocked | - | - |
| 25 | Sweep — web-server iou handlers write an error token on exit 1; de-hardcode WEB_SERVER_SCRIPTS | M | todo | - | docker/config/dist/bin/caddy-bin/*.sh docker/config/dist/bin/httpd-bin/*.sh docker/config/dist/bin/nginx-bin/*.sh bin/tests/startup-prologue.test.sh |
| 26 | Sweep — pin the 14 Dockerfiles carrying `# @todo fix pin versions` | L | todo | - | docker/images/*/Dockerfile* templates/ghost-blog/Dockerfile |
| 27 | Sweep — CLAUDE.md corrections (141/1 claim, stale suite counts, LOCAL slot, exclusion list) | S | blocked | - | CLAUDE.md |
| 28 | Sweep — settings.json ask-tier vs CLAUDE.md:49/:369; direction unruled | S | blocked | - | .claude/settings.json CLAUDE.md |
| 29 | Sweep — prune TODO.md (item 189 + zig drift done; consolidate its 5 container-test items with row 24) | S | todo | - | TODO.md |
<!-- /progress-block -->
### Blocked
- Row 24 — the supervised rebuild/bring-up. Also the SAME blocker as TODO.md's
  entire "Requires container testing" section (TODO.md:11,25,31,38,48): one
  blocker recorded in two files.

### Needs input
- Row 17, laravel/installer: unpinned AND followed by `composer global update
  --with-all-dependencies` (phpbrew-install-tools.sh:31-34), which defeats any
  gate row 17 adds. Closing it needs an install-logic change the Track 5 scope
  guard (:793) forbids — a developer ruling, not executor work.

### Needs research
- Row 20: the per-site compare shape in {caddy,httpd,nginx}-iou*.sh is unread;
  none of the three calls gs_version_gate.
- Whether to split row 21 into 21a (prologue-sourcing: phpmyadmin, serverless,
  rbenv-iou, frankenphp) and 21b (exempt: 00base installs), which have
  different dependencies on row 15.

### Fragile
- Full 12-entry register lives at MASTER.plan.md:848 — this heading is the
  collector-visible pointer to it.
- caddy-iou.sh:21, httpd-iou.sh:26, nginx-iou.sh:33 still exempt exit 1 and
  lack _STACK_CAUGHT: a failed web-server INSTALL writes no error token.
- DO NOT "simplify": `((_elapsed++)) || true` (base-wait-for.sh:44) and
  `((COMMAND_COUNTER++)) || true` (base-setup-packages.sh:52) — post-increment
  from 0 returns status 1 under set -e. Verified by repro.
- sdkman-start.sh's three `set +E` blocks are inert (shopt -s extdebug at :4
  re-enables errtrace), while :145 and base-setup-packages.sh:38 both describe
  them as providing tolerance.
- caddy-start.sh:8 is the only one of 18 PATH= assignments missing its colon;
  works only because the scripts it calls live in /usr/local/bin.
- startup-prologue.test.sh §15's harness ABORTS the whole suite (exit 127, no
  tally line) when gs_version_gate is undefined, instead of redding — observed
  under row 15's sabotage 1. §22's harness guards this with `|| true`; §15's does
  not. A broken helper source line therefore kills the run rather than reporting
  it. Not fixed in row 15 (out of its scope); a candidate for row 21 or 23.
- SABOTAGE HYGIENE: back up with `cp -a` before mutating, never restore with
  `git checkout` — on uncommitted work it restores HEAD and silently destroys the
  edits under test. Cost a re-do in row 15; the md5 check is what caught it.
  Always `md5sum -c` the restore.

### Known issues
- MASTER.plan.md:484 claims F2 startup-health-signalling "fully executed" —
  it is 8 of 11 handlers (see Fragile).
- Rows 13/14 Files columns do not match what their shas touched.
- Stale counts in CLAUDE.md: makefile-posix 5→7 (:323), open-all-envs 12→16
  (:327), env-update "117 sections"→125 declared (:321); "next free LOCAL slot
  41719" (:404) is taken → 41720.
- `# @todo fix pin versions` across 14 Dockerfiles — unplanned, unrowed.
- TODO.md:189 (WAIT_FOR_TIMEOUT from .env) is already done (.env:46).
- DECLINED by the developer 2026-09-03, recorded so they are not re-surfaced
  as new: CLAUDE.md:337 "141/1 exemption is gone"; the hardcoded
  WEB_SERVER_SCRIPTS array at startup-prologue.test.sh:1081; the live 3-entry
  `ask` tier in .claude/settings.json vs CLAUDE.md:49/:369.

## Goal
<!-- goal-block -->
**Goal.** Bring `MASTER.plan.md` to a terminal state: every runtime-installed tool in
`/stack` reinstalls-with-WARN on a `.env` version bump through the single
`gs_version_gate` pattern, the five defect groups the 2026-09-04 sweep found outside the
plan are closed, and the whole is pushed to `master` with every finding carrying a
terminal state and every unproven dimension named `UNCERTIFIED-BY-EXECUTION`.

### In scope

- **Rows 15–23** as written: extract `gs_version_gate` into
  `base-bin/global-stack-base-version-gate.sh` (row 15 — it gates rows 18, 19, 20 and the
  exempt half of 21, four of six migration rows), migrate the 50 actionable class-3 sites
  the 5a appendix names, then docs and close-out.
- **Row 17 additionally pins `laravel/installer`** (`phpbrew-install-tools.sh:32`) and
  stops `:34`'s `composer global update --ignore-platform-reqs --with-all-dependencies`
  from moving a gated tool off its pin.
- **Rows 25–29, absorbed by developer ruling 2026-09-04:**
  - 25 — the exit-1 exemption and missing `_STACK_CAUGHT` in `caddy-iou.sh:21`,
    `httpd-iou.sh:26`, `nginx-iou.sh:33`, so a failed web-server *install* writes an error
    token; plus replacing `startup-prologue.test.sh:1081`'s hardcoded 8-entry
    `WEB_SERVER_SCRIPTS` array with discovery, since that array is why §19 never went red
    for those three.
  - 26 — pin the 14 Dockerfiles carrying `# @todo fix pin versions`
    [Verified: `git grep -l` over `docker/**Dockerfile*` and `templates/**Dockerfile*` → 14].
  - 27 — `CLAUDE.md` corrections: the false "141/1 exemption is gone" (`:337`), stale suite
    counts (`:321` env-update, `:323` makefile-posix 5→7, `:327` open-all-envs 12→16), the
    taken LOCAL slot (`:404`, 41719 → 41720), and the incomplete prologue-exclusion list.
  - 28 — resolve the contradiction between `.claude/settings.json`'s live 3-entry `ask`
    tier and `CLAUDE.md:49`/`:369` ("no deny and no ask tier at all").
  - 29 — prune `TODO.md`: item 189 (`WAIT_FOR_TIMEOUT` from `.env`) and the 00base zig
    drift are already done, and its 5-item "Requires container testing" section is the
    same blocker as row 24.

### Out of scope

- `/stack/projects/*`, anything under `~/.claude`, new services, reviewer panels, named
  subagents.
- **Version bumps for their own sake.** Row 26 is not an exception: pinning a floating
  install records the version already being installed, it does not move it.
- Anything destructive — no `make hard-restart` / `soft-restart` / `save`, no
  `docker volume rm`. The only container operations permitted are a single-service
  recreate plus login, and only if the stack is already up.
- Row 24's supervised bring-up: an external dependency, not executor work.

### Done when

1. Status-block rows exist for 25–29, and `bash ~/.claude/bin/project-state.sh` reports
   `steps_done + steps_blocked == steps_total` with `staleness == []`.
2. `git grep -n 'gs_version_gate()' docker/config/dist/bin/` returns exactly 1 hit, and
   `git grep -l 'base-prologue.sh' docker/config/dist/bin/{caddy,nginx,httpd,android}-bin/`
   returns nothing — the helper exists and the exempt scripts source only it.
3. Every class-3 var in the 5a appendix carries a terminal state: `gated`,
   `already-gated`, `reclassified`, or `REFUTED-AT-EXECUTION` with evidence.
4. **Row 17's observable**, mechanism-agnostic: after a `.env` bump and a phpbrew
   reinstall, `composer global show laravel/installer` reports the pinned version and no
   other gated tool's marker has changed.
5. `git grep -c '@todo fix pin versions' -- 'docker/**Dockerfile*' 'templates/**Dockerfile*'`
   returns 0.
6. `bash bin/tests/startup-prologue.test.sh` green, with a section proving the three
   web-server handlers now write an error token on exit 1 — red-first, and sabotage-checked
   by restoring one exemption.
7. Every suite in `bin/tests/*.test.sh` green, each suite's own final tally line pasted.
8. All 13 original findings plus the 5 absorbed groups carry a terminal state — FIXED
   (sha) / REFUTED-AT-EXECUTION (evidence) / CARRIED (register entry). None silently
   dropped.
9. Pushed to `master` with plain `git push`; `git.ahead == 0`; the completion report names
   each unproven dimension in the words `UNCERTIFIED-BY-EXECUTION`.

### Constraints

- **The Track 5 scope guard (`:793`) is amended, not ignored** (ruling 2026-09-04):
  install-logic changes are permitted *where a `.env` pin cannot otherwise hold* — first
  and so far only instance, `phpbrew-install-tools.sh:32-34`. Everywhere else the guard
  stands: no tool additions or removals, no version bumps, no install-logic rewrites
  beyond gate + marker discipline.
- **Row 17's mechanism is row 17's call** — delete `:34` or constrain it — bounded by "no
  tool additions/removals". Deleting stops *every* global composer package updating, not
  only gated ones, so whichever is chosen gets its own dated `AGREED`.
- **Rows 27 and 28 cannot reach `done` by Claude's hand.** `CLAUDE.md` and
  `.claude/settings.json` are classifier-blocked, so their terminal state is a
  `/tmp/<verb>-<topic>-20260904.sh` handed over for `! bash` execution. They are therefore
  `blocked`, like row 24, and the stop condition's
  `steps_done + steps_blocked == steps_total` absorbs them.
- Order: 15 before 18/19/20/21b; 16, 17 and 21a are parallel-safe with 15. Row 20 is the
  tail of the critical path and its per-site compare shape is still unread.
- `GS_STARTUP_DRY_RUN` exits at prologue `:319`, *after* the gate at `:264`, so a script
  sourcing only the helper has no dry-run seam — rows 18/19/20/21b must stub `curl`/`git`
  on PATH instead, which is why they cost more than their size suggests.
- `master` only, plain `git push` (never `-u`), fixed identity, **no `Co-Authored-By` and
  no `Claude-Session` trailer**, conventional prefixes, one self-contained green commit per
  finding.
- Write/Edit tools for every file change (Bash-written files bypass all lint hooks);
  `git --no-pager -c core.pager=cat diff --no-ext-diff`; `git grep`, never `grep -rn`;
  `docker compose config` always `-q` — plain `config` prints every secret.
- `advisor()`-only certification; the 5-round escalation cap is the sole permitted
  question. Per-project autonomous sentinel is present, so the certification-tier question
  is suppressed.

### Ambiguities resolved

| Question | Ruling | Who |
|---|---|---|
| Re-prove the landed rows? | No — taken as given | Developer, 2026-09-04 |
| End before or after the supervised rebuild? | Before — push with labels named | Developer, 2026-09-04 |
| Is the goal met with row 17 partly done? | No — widen the scope guard and fix `laravel/installer` | Developer, 2026-09-04 |
| Do the sweep's out-of-plan defects join the goal? | Yes — all five groups, rows 25–29 | Developer, 2026-09-04 |
| Which way does row 28 go? | **Unruled.** Recommended: correct `CLAUDE.md`, because `95ccbb7` added the `ask` entries to gate a real `.env` write and `ask` prompts rather than dead-ends, so it does not violate the "no denies" ruling. Alternative: remove the three entries. Routed to `### Needs input` | — |
| Does 5a's seed table define 5b's worklist? | No — the appendix does | Plan `:737-739` |
| Are working-but-hand-rolled compares in scope? | Yes — silent and duplicated, converge | Plan `:773` |
| Class-1/class-2 vars: migrate? | No — classify and record | Plan `:70-75` |
| Split row 21 into 21a/21b? | Does not change the outcome; recorded in `### Needs research`, not asked | — |
<!-- /goal-block -->
