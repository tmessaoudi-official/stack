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

- [2026-09-04 14:18] AGREED (row 17, mechanism ruling owed by the 12:18 entry): the blanket
  `composer global update --ignore-platform-reqs --with-all-dependencies` is **DELETED**, not
  constrained. Evidence for the choice: `laravel/installer` is the ONLY `composer global
  require` in the repo [`git grep 'composer global'` → 2 hits, both in this one file], and the
  `rsync`ed seed at `conf/phpbrew-composer/source/` contains only `src/` with no
  `composer.json`, so the update maintained no other global package. With the require pinned,
  the line's sole remaining effect would be to move that pin. `laravel/installer` is pinned to
  `v5.32.0` — the value `bin/env-update.sh --check` resolved, not a guess; since the tool was
  previously unpinned it was already floating at latest, so this records the installed version
  rather than bumping it.
- [2026-09-04 14:18] AGREED (row 17, defect found during execution): the ten marker-based
  phpbrew tools wrote their marker **BEFORE** installing, so a failed install recorded success
  and every later boot skipped it. That is worse than the "works but silent" the Track 5 seed
  table describes, and it is the reason the migration is a fix rather than a refactor. All ten
  now write the marker as the last statement of the install branch; `startup-prologue.test.sh`
  §25d pins that ordering structurally for every block.

- [2026-09-04 14:27] AGREED (row 18, second instance of the widened scope guard): `cargo
  install` gains `--force` **on the reinstall path only**. `cargo install` is not guaranteed to
  replace an already-installed binary without it, so a bump could no-op while the marker write
  that follows recorded the new version — the marker-first defect in a new guise. This is an
  install-logic change and qualifies under the 2026-09-04 guard amendment ("where a `.env` pin
  cannot otherwise hold"). `cargo` 1.98.0 is present on the dev host but the replace-vs-skip
  behaviour was NOT verified empirically; `--force` was chosen precisely so the outcome does
  not depend on that unverified detail.
- [2026-09-04 14:27] AGREED (row 18, cascade decision the plan left open): the five rust tool
  vars are added to `02rust`'s compose `environment:`. They previously reached the container
  ONLY via the `00base` Dockerfile `ARG`→`ENV` flow, which bakes at build time — so a `.env`
  bump was invisible to a runtime gate until the image was rebuilt, and the gate would have
  compared against a stale baked value forever. Same shape as `GLOBAL_STACK_USE_LOCKS` in
  Track 2b. Verified resolving in-container the Track 2b way.
- [2026-09-04 14:27] CORRECTION (5a appendix): `RUSTUP_INIT` was listed under `exist-only`.
  That is wrong — `rust-iou.sh:19,31` content-compares both `rust-init` and `rust` against
  their pins (`!=`), so both are `hand-rolled`, not exist-only. They work; converging them onto
  the helper for the WARN is left to row 21. The exist-only count of 41 is unchanged in kind
  but this one var moves category.

- [2026-09-04 14:34] CORRECTION (5a appendix, row 19): the appendix says "the 5
  `GLOBAL_STACK_ANDROID_*_VERSION` vars are NEVER compared". True, but incomplete — only
  THREE are live. `NDK_BUNDLE` and `PLATFORM_TOOLS` appear solely in the commented-out
  `@todo fix version not found` line of `android-setup.sh`; the live `sdkmanager` call passes
  bare `"ndk-bundle"` and `"platform-tools"`. They are therefore comment-only (class 4 in
  substance) and were deliberately EXCLUDED from the composite marker: including them would
  force a reinstall on a bump that changes nothing installed.
- [2026-09-04 14:34] AGREED (row 19): the android gate uses a COMPOSITE marker
  (`android.sdk`, holding `cmdline-tools=…;build-tools=…;ndk=…`) rather than one marker per
  component, because the three pins are consumed by a single `sdkmanager` invocation that
  installs them together — per-component markers would imply an independence the install does
  not have. It is composed once in `android-start.sh` and exported to `android-setup.sh`
  rather than recomputed there: two copies of the string would drift, and every boot would
  then read as a version change.

- [2026-09-04 14:46] AGREED (row 21): **frankenphp is deliberately NOT gated.** Its artifact
  path embeds the version (`frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}.tar.gz`, and the
  extract dir likewise), so a bump already downloads a different file and rebuilds — it is
  version-sensitive by construction. A marker would add redundant state that could only drift
  out of agreement with the path. Pinned by `startup-prologue.test.sh` §29c so nobody "fixes"
  it later. Same reasoning retires `awscli`: it has no `.env` version var at all, so there is
  nothing to compare.
- [2026-09-04 14:46] NOTED (row 21): the 5a appendix's SHAPE classification has now been
  corrected four times — `RUSTUP_INIT` (hand-rolled, not exist-only), the two comment-only
  android vars, the 13 web-server vars (hand-rolled, not exist-only), and frankenphp
  (path-keyed, needs no gate). The appendix was reliable about WHICH vars exist and which are
  ungated, and unreliable about the shape of each site, because shapes were inferred from grep
  output rather than by reading each block. **Row 20 and any later audit should read the site
  before trusting the appendix's shape column.** The var inventory itself stands.

- [2026-09-04 14:55] NOTED (row 20): the row is **17 sites, not 14**. The 5a appendix's count
  used a pattern matching only the singular `*_VERSION_PATH` spelling and so missed each
  server's OWN version compare (`NGINX_VERSIONS_PATH`, `HTTPD_VERSIONS_PATH`,
  `CADDY_VERSIONS_PATH`). Fifth correction to the appendix's shape/count column. Row 20 is
  also the only Track 5b row that is NOT a defect fix: every site already compared correctly,
  so what it buys is the WARN and one idiom. `startup-prologue.test.sh` §30b makes the
  convergence checkable — zero hand-rolled marker compares may remain in the three trees.
- [2026-09-04 14:55] NOTED (row 20): no duplicate WARN arises from `*-iou-common.sh` gating
  the same markers as its caller. The caller's cleanup block deletes the marker on a mismatch
  before invoking the IOU script, so the inner gate sees an absent marker and returns
  `install`, which is silent by design. Do not "fix" this by suppressing the inner gate's
  stderr — the silence is structural, not incidental.

- [2026-09-04 15:35] AGREED (developer ruling, row 26): the 14 `# @todo fix pin versions`
  comments are **retired, not acted on**. They mark ~144 `apt-get` packages across four
  different base distros — not `.env` version vars, which is what the sweep's description
  implied and what the absorb-everything ruling was given on. `.hadolint.yaml` already ignores
  DL3008 with the comment *"acceptable in development environments where we intentionally
  track latest packages"*, and zero apt packages are pinned anywhere in the repo: the lint
  config was the standing decision and the TODOs contradicted it. Exact apt pins would also
  break the build whenever the archive rotates a superseded version off the mirror. Each
  comment is REPLACED by the ruling rather than deleted, so the absence of a pin is explained
  where it would otherwise look like an oversight.
- [2026-09-04 15:35] NOTED: this is the second time a sweep-lens description proved wrong
  about the SHAPE of the work (after the 5a appendix's five shape corrections). Both lenses
  were accurate about WHERE the issue was and wrong about WHAT it was, because both classified
  from grep output. Treat any lens finding's "what to do" as a hypothesis to verify, not a
  worklist item — the location is the reliable part.
- [2026-09-04 23:53] AGREED: row 28 — KEEP the three `ask` entries in `.claude/settings.json`
  (all `bin/env-update.sh --apply*`, added `95ccbb7`) and CORRECT the docs that say the file is
  allow-list only. Rationale accepted: an `ask` prompts and is answered in-session, a `deny`
  dead-ends, and the no-denies ruling is about unrecoverable blocks. Eight claim sites across
  `CLAUDE.md` (:26/:45/:49/:143/:369), both reviewer agent defs and `docs/BLAST-RADIUS.md:10`
  ship in ONE handover script, `var/claude/fix-ask-tier-docs-20260904.sh`, because none of the
  three files is Claude-writable without either the classifier or Rule 5 in the way.
- [2026-09-05 06:25] AGREED: row 24 (the certifying bring-up) is POSTPONED — developer's
  choice from *make up + wait-healthy* / *down-n-rebuild-force-recreate* / *postpone*. Finding
  recorded for whenever it runs: the stack is DOWN (0 stack containers, 338 `tools/versions`
  markers persisting), every compose file reaches the bind-mounted `docker/config/dist/bin`
  (21 mount it directly, the rest extend/anchor 00base), and the only Dockerfile delta since
  the last bring-up (`fc10204`) is comment-only — so `make up` + `make wait-healthy` certifies
  the eight dimensions WITHOUT a rebuild, which this box's heavy-build SIGKILL history argues
  against. `config -q` and `check-image-versions` both pass at `b3c5995`. Image age checked
  too: the 40 stack images date from 2026-08-25, and since then ZERO non-comment Dockerfile
  or `conf/` lines changed (baseline `c9b4576`); the six `.env` pin bumps in that window
  (mailpit image, mise, claude-code, mcp-gitlab, biome, pnpm) are compose `image:` pulls or
  runtime installs the gate handles — none is a Dockerfile `ARG`.
- [2026-09-11 12:10] AGREED (row 30): fix E7 at the **normalize-the-3-android-handlers** scope —
  drop the `!= "1"` arm, add `_STACK_CAUGHT`, give `android-start.sh` the 141 exemption, write
  `errors/${GLOBAL_STACK_ERROR_TOKEN}` BEFORE the deliberate `sleep infinity`, and align the elapsed
  line to `command:`. The 11 web-server handlers are NOT unified — working code, outside this fix.
  Sourcing the prologue into android was REJECTED: it contradicts the prologue-exemption collision
  rule at line 915-918 and would drop the documented stay-alive-on-error behaviour.
  Certification tier for this row: `advisor()` only.

- [2026-09-11 10:12] AGREED (row 31): fix the `--sdk` P0 at the **full** scope the developer asked
  for — the flag position at all three call sites, the `2>/dev/null || true` swallow, one array as
  the source of truth for install AND verify, `.env`'s stale line-number anchors replaced by names,
  the config.ini rewrite decoupled from the `_google_apis` reverse-parse, `${ANDROID_HOME}` quoted,
  and `GLOBAL_STACK_ANDROID_SDK_URL` renamed to `..._SDK_BUILD` (it holds a build number).
  Three things were offered and DECLINED, each for a stated reason: **renaming the AVDs** —
  `setup-dist.sh` runs on every start and `avdmanager create --force` with a new name would create
  three NEW AVDs beside the three that exist; **removing the dead `..._NDK_BUNDLE_VERSION`
  plumbing** — working code, read by no script but outside this fix; **pinning rootAVD to a sha** —
  the clone is consumed by nothing executable and gitlab is not one of the 12 fetcher types, so a
  pin would never auto-update; quoting alone was chosen.
  Two measured findings moved the fix away from the obvious one: a naive `;`→`/` single-array
  transform FATALs on `platform-tools` (single-instance upstream, listed bare with its version in
  column 2), and the existing `grep -qF` detects removal for 17 of 17 probed ids, so it is NOT
  replaced with field matching. Certification tier for this row: `advisor()` only.
- [2026-09-11 11:05] 6C FINDING (row 31, not a developer ruling — deliberately NOT labelled
  `AGREED`, because no question was put and none was answered): the pre-completion check found two things the
  evidence pass had missed, both now closed. **(1)** The `..._SDK_URL`→`..._SDK_BUILD` sweep was
  run with `git grep`, which cannot see gitignored files — `docker/images/local.05php8-4-…-android-
  n-flutter3-41-9/docker-compose.yaml:144` still plumbed the old name, so on this machine the
  all-in-one image would have received `GLOBAL_STACK_ANDROID_SDK_URL=` blank and no `..._SDK_BUILD`,
  killing `setup.sh:39` under `set -u`. `docker compose config -q` had NOT caught it twice over: it
  warns and exits 0 on an unset variable, and a stale `GLOBAL_STACK_ANDROID_SDK_URL=15859902` export
  in the session's own shell was masking the warning, because compose interpolation prefers the
  shell over `--env-file`. Fixed in the gitignored file (backup kept, never staged) and re-validated
  under `env -i` — zero warnings, all four android services resolve `BUILD=15859902`. The lesson
  graduated to `CLAUDE.md` § Gotchas as a rider on the `git grep, not grep -rn` bullet, which until
  now pointed only one way: `git grep` is the sweep for TRACKED files and is blind to exactly the
  gitignored compose files that consume a plumbed var. **(2)** `setup-dist.sh`'s rewritten AVD loop had only
  static grep coverage; §43u-43y now execute it. They are **regression guards, not red-first
  proofs** — HEAD's glob-and-reverse-parse loop passes all five under a faithful stub, which is the
  correct result: the rewrite removed a fragile dependency, it did not fix a live break. Three
  sabotages red them. Also recorded-not-fixed as A10: `setup.sh`'s final `[[ -n "${GS_ANDROID_SDK_
  WANT:-}" ]] && printf …` makes a STANDALONE run exit 1 (production always exports the var).

- [2026-09-11 12:12] AGREED (row 32): fix A10 at the **whole-class** scope, not the one file it was
  filed under. Two corrections came out of the pre-work investigation and both are recorded here
  rather than quietly folded in. **(1)** A10's own evidence was wrong: a standalone
  `global-stack-android-setup.sh` does exit 1, but from **line 32** -- `git clone` of rootAVD fails
  with "destination path already exists and is not an empty directory" -- and execution never
  reaches the final line at all. The exit code was right, the attributed cause was not. The
  mechanism is nonetheless real, proven in isolation: a trailing `[[ cond ]] && cmd` returns the
  FALSE test as the script's own status (var unset -> 1, var set -> 0). **(2)** The blast-radius
  sweep found the same shape as the last executable line of three more scripts --
  `node24/node26/nodeedge-setup.sh`, all ending `[ -s "${NVM_DIR}/bash_completion" ] && \. ...` --
  and THOSE are the reachable half: `nvm-start.sh:143` calls them as a bare statement under
  `set -xeEu` with the prologue ERR trap, so a false guard aborts the node install and writes an
  error token. A10's android instance is by contrast unreachable today, because `start.sh:115`
  exports `GS_ANDROID_SDK_WANT` before its only call site. Both halves are LATENT, neither is a
  live break, and the developer chose to fix the class rather than the filed instance. Scope: the
  `if` conversion in all four scripts (behaviour identical, only the exit status changes; the
  comment at `setup.sh:143-148` deliberately wants the marker ABSENT standalone and the `if` keeps
  that), the missing trailing newline on `setup.sh`, and a DISCOVERY-based assertion so the class
  cannot return -- a hardcoded list of four would be the same can-never-fire defect §19 had.
  Certification tier for both gates: `advisor()` only.

- [2026-09-11 14:34] AGREED (row 33 + a hygiene sweep): after row 32 closed, the remaining backlog
  was counted rather than drip-fed -- **16 open, 1 live defect**. Ruling: fix the live one as its
  own row, then BATCH items 2-6 into a single hygiene change, then re-verify items 8-16 in one pass
  and report them as a list to rule on once. **Nothing is to be committed**: the developer reviews
  the whole working tree first (verbatim: "wait don't commit ! let me review everything !").
  The live defect turned out MUCH wider than filed as A8. Filed as "platform-tools is pinned but
  absent from the gate's composite marker"; measured, **9 of the 12** `GLOBAL_STACK_ANDROID_*` vars
  that `global-stack-android-setup.sh` consumes are absent from `GS_ANDROID_SDK_WANT` -- only
  `cmdline-tools`, `build-tools` and `ndk` are in it. Missing: `API_LEVEL_1/2/3`,
  `SYSTEM_IMAGE_TAG`, `SYSTEM_IMAGE_PLAYSTORE_TAG`, `SYSTEM_IMAGE_ABI`, `PLATFORM_TOOLS_VERSION`,
  `INSTALL_SYSTEM_IMAGES`, `SDK_BUILD`. Each is a `.env` bump that changes what is installed while
  leaving the marker byte-identical, so `gs_version_gate` answers `skip` and the bump never lands --
  the exact silent class Track 5 exists to close, one level up from row 31. Two bite now: flipping
  `INSTALL_SYSTEM_IMAGES` to true installs an emulator + 6 images and would do nothing, and the
  pending `API_LEVEL_3` bump off `37.2-beta1` onto the shipped stable would read as applied and
  would not be. The fence comment at `android-start.sh:110-113` asserting both `_NDK_BUNDLE_VERSION`
  and `_PLATFORM_TOOLS_VERSION` are "deliberately absent... the live call passes bare" is now HALF
  FALSE: row 31 made platform-tools a pinned id at `setup.sh:80`. Known cost, stated up front:
  widening the marker changes its content once, and `android-start.sh:119` answers a mismatch with
  `sudo rm -rf "${ANDROID_HOME}"` -- so the next `make up` does one full SDK reinstall. That
  reinstall is also the first time row 31's `--sdk` fix would ever execute, which is a row-24
  UNCERTIFIED dimension, so the cost is not pure loss.
- [2026-09-11 15:50] BUILT (row 33, uncommitted by instruction): the widening landed in the working
  tree. Red-first was measured BEFORE `android-start.sh` was touched and matched the prediction
  exactly -- 27f redded on precisely the nine missing inputs and stayed green on the three that were
  already covered, 47b named the same nine, 12 failures / 594 total. After the fix: 594/594.
  The red-first run IS the sabotage table for this row: one case per key, each changing exactly one
  field, so every one of the twelve has an individually demonstrated red path. Two self-inflicted
  lint regressions were caught by a before/after parity measurement against `HEAD` and fixed:
  SC2043 (the `for _v in NDK_BUNDLE` loop became one-element once `PLATFORM_TOOLS` moved to the
  include loop) and two `|`-continuations that shfmt's `-bn` style wants as `\` + leading `|`.
  Final parity: shellcheck identical but for one added SC2016 (a deliberately single-quoted
  `printf` of generated code, matching the 77 already there), shfmt zero new objections on both
  files. The live `tools/versions/android.sdk` was verified byte-unchanged (56 B, Sep 10 14:19)
  after every probe run -- §46's tmpdir pin plus §27's own `GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS`
  override are what keep a probe from overwriting it and triggering the `sudo rm -rf`.
  UNCERTIFIED-BY-EXECUTION: no bring-up. That the widened marker actually drives a successful
  reinstall is exactly the row-24 dimension, and it stays unproven until a `make up`.
- [2026-09-11 16:20] FINDING (row 34 — the hygiene batch, NOT a developer ruling): the batch was
  authorised as five items. Verified against the tree, **four of the five are wrong as filed**, and
  the re-verification is worth more than the changes. Every one was caught by reading the fence
  before touching it, which is the whole point of the rule.
  **(2) dead `_NDK_BUNDLE_VERSION` plumbing — HALF real.** `.env:1338` carries a `lock:` annotation
  and a six-line fence: the var "RECORDS the revision the bare install yields; it cannot drive it.
  Do not 'fix' it into a versioned id." So the VAR is a deliberate record and STAYS. What was
  genuinely dead is the `environment:` plumbing injecting it into four containers where no script
  reads it — removed from `04android`, `05edge`, `05stable` and the gitignored `local.05` (edited,
  backup kept, never staged), each leaving a comment saying why, plus a cross-reference in `.env`.
  Verified: resolved config carries 0 occurrences of NDK_BUNDLE and still 48 of the 12 real android
  inputs (12 x 4 services).
  **(3) rootAVD pin — ALREADY DECLINED on the merits**, 2026-09-11 10:12, and the reason still
  holds: "the clone is consumed by nothing executable and gitlab is not one of the 12 fetcher
  types, so a pin would never auto-update". Not re-litigated. Its idempotence half is real but
  narrow — `git clone` into an existing dir exits 128, reachable ONLY on a standalone debugging run,
  because the production path wipes `ANDROID_HOME` at `start.sh:144` before calling setup at :150.
  **(4) `conf/sdkman/sdk-init/` orphan removal — FALSIFIED.** It is not an orphan: 5.1K of live
  code, rsynced into `${SDKMAN_DIR}/bin` at `sdkman-start.sh:127`, pinned by four §32 assertions and
  recorded in `.env:437`. Removing it would break the SDKMAN init patch and red the suite.
  **(5) `API_LEVEL_3` off `37.2-beta1` onto stable — FALSIFIED.** `.env:1352` reads
  `(lock:API level ...; android-37.2 STABLE exists upstream, this is deliberately the beta)`. The
  stable being available is the documented PREMISE of the lock, not evidence against it. Changing
  it needs a developer ruling, not a hygiene sweep. Note row 33 now makes that bump WORK when it is
  taken: API_LEVEL_3 is in the composite, so it will force the reinstall it never used to.
  **(6) trailing newlines — REAL and done.** 49 of the 103 dist/bin scripts then present lacked one; all 103 now
  (102 since row 35 deleted the callerless `base-set-bash-strict.sh`)
  carry one. Verified mechanically: every one of the 49 is exactly `1/1` in `--numstat`, so the
  final byte moved and nothing else.
- [2026-09-11 17:10] 6C FINDING (rows 33/34, not a developer ruling — no question was put): the
  pre-completion check demanded a red path for §47a and §47c, which the red-first run had not
  produced (it proved 47b only). Measuring them found a REAL defect in §47 itself. `_a47_consumed`
  had no `|| true`, so pointing `AND_SETUP` at a nonexistent file did not RED 47a — it killed the
  whole run at that line with no tally, which reads as a crash rather than as the guard firing.
  This is the harness trap already recorded in ### Fragile and already guarded three times in this
  file; §47 reproduced it. Fixed, and both directions now measured: with the guard, the broken root
  reds `47a ... (found 0)` and the run still tallies — and 47b goes GREEN on that empty set
  (`uncovered: none`), which is precisely the vacuity 47a exists to catch, demonstrated live rather
  than argued. 47c was proven separately by adding `;fake=${GLOBAL_STACK_ANDROID_FAKE}` to the
  composite: it reds naming the dead key. Both mutations restored and the restores verified by
  sha256 — `start.sh` back to `9f94fa375fb880c4`, numstat `31/6`.
  Also closed here: `env-update.test.sh` 844/844 run because `.env` was edited (that suite owns
  `.env` parsing); the `.env` note reworded from "the four android compose files" to name the three
  TRACKED ones plus "any `local.*` variant", since a clean clone would read "four" and find three;
  and the three node `*-setup.sh` confirmed byte-identical at last (`865e2047d297113e`) — row 32
  left node26 differing by its trailing newline, and the row-34 sweep closed it.
- [2026-09-11 16:45] RE-VERIFICATION of backlog items 8-16, measured today, one pass, nothing
  changed by it — this is the list the developer rules on once:
  **A3(ii) AVD naming** — STILL TRUE, still cosmetic. `setup-dist.sh:68` hardcodes
  `..._android_${ver}_google_apis` while the image tag is `google_apis_ps16k`. The triage itself
  downgraded it to "a labelling lie, not a functional break", and row 31 DECLINED the rename with a
  reason that still holds: `setup-dist.sh` runs every start, so `avdmanager create --force` under a
  new name would create three NEW AVDs beside the three that exist. Leave it.
  **The mis-rooted DOCTYPE x81 / "corrupted package.xml" x246 scan** — remains what it was filed as:
  root cause NOT found, the original hypothesis FALSIFIED, the scan itself mis-rooted. No new
  evidence today; it needs a bring-up to re-observe, so it is a row-24 dependant.
  **Dockerfiles unparseable by hadolint** — REAL, and the numbers drifted: filed 33 of 43, measured
  **32 of 41** today. Root cause now identified and it is NOT ours: hadolint's parser cannot read a
  registry `host:port` in a `FROM` when the port comes from an `ARG` —
  `FROM ${ALIAS}:${PORT}/image:${VERSION}` gives `unexpected ':' expecting ... the image tag`. The
  only "fix" would be restructuring every FROM line and breaking the local-registry build chain.
  Document as an upstream limitation; do not touch the Dockerfiles.
  **`MODE=setup` java-marker gate** — already widened: `sdkman-start.sh:70-71` gates on
  `java.${_java_label}` via `gs_version_gate`, and :181 passes `--marker-prefix`. Closed.
  **`cmdline-tools` PATH order** — the ordering is deliberate, but the investigation turned up
  something NOT filed: `android-start.sh:48` and :55 both contain a **double colon**
  (`...${FLUTTER_VERSION:-}/bin::${ANDROID_HOME}/cmdline-tools/bin`). An empty PATH element means
  "the current directory" to POSIX, so every container running this start script has `.` on its
  PATH. Small, real, and one character to fix — NOT fixed here because it is outside both
  authorised rows and the developer asked to review before anything else lands.
  **rust yanked crates** — no yank handling exists for the rust fetcher (the only `yank` logic in
  the tree is `fetchers/pypi.sh`, which excludes yanked releases properly). Still open as filed.
  **E3** — informational root-cause note, not a defect. No action.
  **E7-f** — CLOSED row 35. `base-bin/global-stack-base-set-bash-strict.sh` deleted. Zero callers
  re-confirmed under BOTH sweeps (`git grep` and plain `grep` over `docker/`, `bin/`, the Makefile
  and the gitignored compose files); the only hits were the file itself, this plan and the triage
  report. It is the pre-prologue ERR/EXIT handler and writes strictly LESS than `stackCatch` (no
  line number, no command, no `_STACK_CAUGHT` re-entry guard). dist/bin drops 103 -> 102; §46a's
  floor is `>= 90`, so it stays green.
  **E7-g** — CLOSED row 35, and it was NOT merely latent: measured argless, all three exited 1 with
  ZERO files in `tools/errors/`. The fix had to move the reads below the `stackCatch` DEFINITION,
  not below the `trap` line as filed — the trap body calls `stackCatch`, so a read in between dies
  with `stackCatch: command not found` and still writes nothing. After: each writes its token
  naming the offending command (`line: 1 command: CADDY_PATH="${1}"`). All three callers do pass it. (`android-setup.sh`'s `${1}` is a
  stackCatch function parameter — different thing, not a member of this class.)

- [2026-09-11 18:05] AGREED: row 35 — finish the remaining six backlog items in one batch, commit
  nothing, present the whole tree for review at the end (developer ruling, verbatim: *"You know what
  finish everything but don't commit ! let me review zt the end !"*). Three of the six were filed
  wrongly and were corrected against the code before implementation, not after: the `::` defect is at
  FOUR sites (`alltogether-start.sh` carries the same copy-pasted PATH as `android-start.sh`), not
  two; `caddy-start.sh:8` is a glued re-include that loses the first inherited PATH element, not just
  a missing separator; and the §15 abort is not §15's at all but `assert_output_contains`'s, shared by
  31 call sites. E8 (rust yanked crates) was RETRACTED in the triage itself — `/stack` owns no crate
  or lockfile — so the batch is six, not seven. The `set +E`-is-inert Fragile entry was falsified by
  measurement and corrected in place with a tombstone rather than deleted.

- [2026-09-11 18:40] AGREED: row 36 — the developer restarted the stack and reported errors; the
  investigation found a P0 regression that was NOT in the triage backlog and NOT caused by rows
  33/34/35 (`git log 5ef6b67~1..HEAD -- rbenv-start.sh` is empty). Root cause is a comment inside a
  line continuation, introduced by `7e8c0b2`. Two lessons recorded rather than just the fix. FIRST:
  this is the FOURTH distinct "a comment silently breaks a construct" defect in this repo (the
  ShellCheck comment-as-directive trap, §19's comment-stripping requirement, §47's prose naming vars
  it does not install, and now this) — comments here are load-bearing often enough that any construct
  they sit inside needs a guard. SECOND: a green suite plus a healthy `docker ps` proved nothing,
  because the running containers PREDATED the commit under test. Uptime is not evidence that the
  current code runs; only a restart is.

The executor APPENDS its own dated `AGREED:` entries here (e.g. the F3 classification
outcome, Track 5 audit rulings) as it goes — this file is where rulings land. Never backdate;
never write an entry for a ruling that was not actually taken (forged-AGREED hazard, global
Rule 17).

- [2026-09-11 20:05] AGREED: rows 38 and 39 are TWO commits, not one, and neither is pushed —
  the developer reviews the tree first. Row 38 (platform-tools single-instance install id) and
  row 39 (`$HOME` permissions subtract, never assign) touch different files and are different
  defect classes; one message for both would re-create exactly the narrative tangle row 38 spent
  effort untangling. Developer ruling on the certification question: build the chown fix now and
  commit nothing yet, so both changes are reviewed together as one tree.
- [2026-09-11 20:05] AGREED: row 39's fix is `chmod ug-s,go-rwx`, and the `.docker/cli-plugins`
  `a+x` arm is DELETED rather than joined by a second special case for `~/.android`. Rationale,
  measured not assumed: the arm never fired (no container has that directory; docker's plugins
  live in `/usr/libexec/docker/cli-plugins`), and under the subtract-only rule an executable
  arriving at 0755 keeps owner-execute with no exception needed. A per-directory exception is
  what let this class hide in one place — growing it would be the same mistake a third time.
- [2026-09-11 21:10] AGREED (row 24): the supervised bring-up runs with
  `GLOBAL_STACK_RELOAD_ANDROID=true` so it exercises rows 38 AND 39 in one pass, not row 39 alone.
  The developer chose this over a plain cold `make up`. Reason it is not optional: row 39 rides
  the entrypoint and any restart proves it, but row 38's install block sits behind
  `gs_version_gate`, and `tools/versions/android.sdk` is present and current — so the gate returns
  `skip` and the block never executes. A bring-up without the flag would report green while
  leaving the row-38 fix entirely unexercised, which is the can-never-fire class this plan has now
  hit seven times, arrived at from the testing side instead of the code side. Cost, stated up
  front: `android-start.sh:119` `sudo rm -rf`s `ANDROID_HOME` first, so this is a full SDK
  re-download. `.env.local` was backed up to `/tmp/env.local.bak.1789152647` before the flip, the
  master `.env` stays `false`, and the flag is reset once the run is read.

- [2026-09-11 21:25] RAN (row 24) — the supervised bring-up, with `RELOAD_ANDROID=true` per the
  21:10 ruling, against `cd591f8` + `5fe9435`. Result: `make down-n-up` → **44/44 healthy, 0 error
  tokens**; `04android` gate → `reinstall`, `sudo rm -rf /stack/tools/android`, full SDK rebuilt.
  Row 38 live: `_ptv_got=37.0.1`, `adb` = `37.0.1-15733141`, no `WARN: platform-tools`, no
  `these packages are absent`, and the command actually issued was
  `android --sdk=/stack/tools/android sdk install emulator …` — `--sdk` GLOBAL (row 31) and the
  single-instance id BARE (row 38), read off the live log rather than inferred.
  **A METHOD FINDING that nearly produced a false green.** The bring-up ALONE does not exercise
  row 39, and the green would have read as though it did. `/home/developer` is CONTAINER-LOCAL —
  `docker inspect` shows only `.bash_history`, `.zsh_history` and the dist source as mounts — so
  `down-n-up` RECREATES the container and hands `chown-home` an EMPTY `$HOME` with no cached
  executable to strip; the launcher then re-downloaded at 0755 twenty-five seconds AFTER container
  start (mtime 20:57:40 vs StartedAt 20:57:15). The tell was the mtime, not the mode: a 0755 file
  whose mtime PREDATES the boot would have meant the permission pass had missed it, and a 0755
  file whose mtime POSTDATES it means there was nothing there when the pass ran. Checking that is
  what stopped "44 healthy" being reported as row-39 certification.
  The real proof needed a RESTART (not a recreate), so a cache existed at the moment of the pass:
  **755 before → 700 after**, then `android --version` → `1.0.16261425`, and **zero**
  `Failed to exec android binary` / `Permission denied (os error 13)` across the whole boot, with
  the ensuing multi-GB reinstall driven BY that 0700 launcher. Under `chmod 600` that middle value
  is 600 and the next exec is the EACCES this row exists to fix. Container healthy in ~270-360 s.
  Generalises beyond android: **a cache-stripping defect cannot be tested by recreating the
  container that holds the cache** — the recreate destroys the fixture. Same family as the
  warm-volume `skip` that hid row 31, met from the testing side instead of the code side.
  Residuals named, not folded in: `USE_LOCKS=false` so lock-serialized tier-03 install stayed
  untestable, and the two web-server failure dimensions need deliberate failure injection against a
  live stack — not an executor's call. `.env.local` restored to `RELOAD_ANDROID=false` and diffed
  against `/tmp/env.local.bak.1789152647`: that one line, no other drift.

- [2026-09-12 10:05] AGREED (row 41): the android platforms and build-tools pins become a ROLLING
  WINDOW of the three latest STABLE releases via a new env-update `(offset:N)` annotation flag,
  fully AUTO, no `(manual)` — the developer's words: "no need for manual ! the logic is that i want
  always to cover the three latest versions in android platform and build tools". Slot 3 therefore
  loses its deliberate beta (37.2-beta1 → 37.2). Accepted costs, stated in the question: every
  window shift reinstalls the SDK on the next boot; the system-image tag stays fixed while the
  levels roll and the verify loop is what catches a rename. Not ruled (surfaced after the fact,
  seen live): a major crossing is `HOLD` under decide.sh rule 7 like every other record —
  `--force-hold` applies it. Naming: the unsuffixed `..._BUILD_TOOLS_VERSION` stays the latest
  (PATH and the start scripts point at it), `_PREV_1` / `_PREV_2` are the compat slots.
- [2026-09-12 11:40] AGREED (row 41, major-crossing HOLD): keep decide.sh rule 7 unchanged and apply
  the six android window records with `--force-hold --confirm="Confirm override"` when a new major
  ships. Stated in the question: a plain `--apply` on platforms 38.0 / build-tools 38.0.0 leaves
  slot 3 HOLD while slots 1-2 AUTO, i.e. `37.1 / 37.2 / 37.2` and a duplicate `platforms;android-37.2`
  in `_pkgs` — the window only stays intact under `--force-hold`. The opt-in exemption flag and the
  bring-up were offered and declined.
- [2026-09-12 16:50] AGREED (row 42, certification tier): `advisor()` only for this fix — an ordinary
  per-task gate, not a milestone boundary. Reviewer panel and both were offered and declined.
- [2026-09-12 16:50] AGREED (row 42, fix scope): roll the nodeedge pin back AND fix the class with an
  `env-update` artifact-existence gate. Stated in the question: a rollback alone is a Rule 14 bandaid
  because the next `--apply` re-picks the same broken nightly. Rollback-only and diagnose-only were
  offered and declined.
- [2026-09-12 17:45] AGREED (row 43, scope): fix ALL THREE failing services in this effort —
  `03nodeedge` (done), `04android` and `02rust`. "Finish nodeedge then android only" and
  "nodeedge only, report the rest" were offered and declined.
- [2026-09-12 17:45] AGREED (row 43, android approach): gate the rolling window on SYSTEM-IMAGE
  availability — the window must refuse an API level whose system images are not on the stable
  channel, so it lands on the newest fully-usable level today and advances on its own once Google
  promotes the images. Stated in the question: this fixes the class so no future roll can
  reintroduce it, at the cost of a new check plus tests. WARN-and-skip in the startup script, and
  installing system images from the dev channel, were offered and declined (the latter with my
  recommendation against it, since it opts every image into dev builds).
- [2026-09-24 10:19] AGREED (milestone certification tier): `advisor()` only at the plan's closing
  boundary — "Use only advisor for now". The three-lens milestone panel was offered as the
  recommendation and declined; the plan closes advisor-certified, not panel-certified.
- [2026-09-24 10:19] AGREED (plan disposition): KEEP this file, marked closed — it remains the only
  home of the fragile register and the open `UNCERTIFIED-BY-EXECUTION` dimensions under `### Blocked`.
  Graduate-then-delete and delete-now were offered and declined.
- [2026-09-24 10:19] AGREED (`.claude/settings.json`): leave the working-tree change that empties the
  three `env-update --apply*` `ask` entries UNCOMMITTED — it is permission-swap-project's armed state
  (sentinel `~/.claude/projects/-stack/state/permission-profile-project-added.json` present), not a
  reversal of the row 28 ruling. Restoring now and a new drop-the-trio ruling were offered and declined.
- [2026-09-24 10:19] CLOSED: 48/48 rows done, re-verified at `75d0112`. All 13 `bin/tests/*.test.sh`
  suites `ALL PASSED` (startup-prologue 637, env-update 910 as five `--section` batches
  162+174+210+177+187, env-scan 186, check-image-versions 30, git-strip-coauthored 27, open-all-envs
  22, claude-fullauto-shell 20, compose-env-plumbing 15, check-bake-targets 12, env-guard 12,
  profile-shell 12, makefile-posix 10, wait-healthy 9); Done-when 2 (`gs_version_gate()` ×1, no
  exempt script sources the prologue), 5 (0 `@todo fix pin versions`) and 9 (ahead 0) re-run. Done-when
  4 PARTLY observed: `tools/composer/vendor/composer/installed.json` holds `laravel/installer`
  v5.32.0 = the `.env` pin, marker written by a live boot 2026-09-18 — but the pin has never been
  bumped since `0e71e5b`, so "after a bump, no other marker changes" is `UNCERTIFIED-BY-EXECUTION`.
  Done-when 3 and 8 rest on this file's own records and were not re-audited today. Row 41's SDK
  reinstall and row 46's marker migration both ran on the 2026-09-18 boot [Inferred: `android.sdk`
  and `android.cli` mtimes, `android.sdkmanager` absent; boot log not read]. Still
  `UNCERTIFIED-BY-EXECUTION`: lock-serialized tier-03 install, a web-server handler writing its
  error token, consumer fail-fast behind a failed web server (see `### Blocked`).

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
bash bin/tests/env-update.test.sh          # large; last observed 844/844 on 2026-09-05 (426 s) — re-read, don't trust this hint
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
| `hand-rolled` | 9 → **22** | real content-compare against the pin, but silent and duplicated — converge. Corrected 2026-09-04: the 13 web-server vars were mis-filed as exist-only (see the row-20 note below); they compare correctly, they are just silent |
| `exist-only` | 41 → **28** | **the gaps**: a version bump does nothing |
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
| web servers | `CADDY`, `HTTPD`, `HTTPD_APR`, `HTTPD_APR_UTIL`, `HTTPD_MOD_AUTH_OPENIDC`, `HTTPD_MODSECURITY_MOD`, `HTTP_CORERULESET`, `HTTP_MODSECURITY_LIB`, `NGINX`, `NGINX_CJOSE`, `NGINX_LIBOAUTH2`, `NGINX_MOD_AUTH_OPENIDC`, `NGINX_MODSECURITY_MOD` | `{caddy,httpd,nginx}-iou*.sh` + `*-start.sh` | **CORRECTED 2026-09-04 (row 20 read): these are `hand-rolled`, NOT `exist-only`.** Every site is `{ [[ ! -e P ]] \|\| [[ "$(cat P)" != "$V" ]]; }` — a real content-compare, semantically identical to `gs_version_gate != "skip"`, but silent and duplicated across **14 sites in 5 files** (httpd-start 4, nginx-start 5, httpd-iou-common 2, nginx-iou-common 2, nginx-iou 1). Converging them buys the WARN and one shape, not new detection |
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
| 13 | Track 2a docs — stop /new-service resurrecting F4; carry the four residuals | S | done | 53aff52 | .claude/skills/new-service/SKILL.md bin/tests/startup-prologue.test.sh docker/config/dist/bin/*/*-start.sh docs/plans/MASTER.plan.md |
| 14 | Track 5a — bidirectional audit (all _VERSION vars x all gate sites) into a plan appendix | L | done | 7782701 | docs/plans/MASTER.plan.md |
| 15 | Track 5b — extract gs_version_gate into its own sourceable helper (prologue-exempt safe) | M | done | b27aca7 | docker/config/dist/bin/base-bin/*.sh bin/tests/startup-prologue.test.sh |
| 16 | Track 5b — gate nvm-install-tools (deno, bun) | M | done | b08ce58 | docker/config/dist/bin/nvm-bin/*.sh bin/tests/startup-prologue.test.sh |
| 17 | Track 5b — gate phpbrew-install-tools (11 tools incl. laravel/installer pin) | L | done | 0e71e5b | docker/config/dist/bin/phpbrew-bin/*.sh .env docker/images/02phpbrew/docker-compose.yaml bin/tests/startup-prologue.test.sh |
| 18 | Track 5b — gate the 5 rust tools + deliver their pins at runtime (cascade: added to 02rust compose) | M | done | 0b5593a | docker/config/dist/bin/rust-bin/*.sh docker/images/02rust/docker-compose.yaml bin/tests/startup-prologue.test.sh |
| 19 | Track 5b — gate android SDK components (composite marker on the 3 LIVE pins) | M | done | 0415ca3 | docker/config/dist/bin/android-bin/*.sh bin/tests/startup-prologue.test.sh |
| 20 | Track 5b — converge all 17 web-server compares on gs_version_gate (WARN + one idiom) | L | done | e9fd01e | docker/config/dist/bin/nginx-bin/*.sh docker/config/dist/bin/httpd-bin/*.sh docker/config/dist/bin/caddy-bin/*.sh bin/tests/startup-prologue.test.sh |
| 21 | Track 5b — remainder named by 5a: phpmyadmin, 00base runtime installs, elasticmq, rbenv plugins. frankenphp NOT gated (path-keyed); awscli has no pin | M | done | ae4f4df 53c0859 | docker/config/dist/bin/base-bin/*.sh docker/config/dist/bin/phpmyadmin-bin/*.sh docker/config/dist/bin/serverless-bin/*.sh docker/config/dist/bin/rbenv-bin/*.sh bin/tests/startup-prologue.test.sh |
| 22 | Track 5 docs — CLAUDE.md Gotchas + two-phase note once the gate is universal | S | done | 3f94de3 | CLAUDE.md |
| 23 | Close-out — terminal states + SHAs in plan, full battery re-run, advisor, push | M | done | 4eb16c6 | docs/plans/MASTER.plan.md |
| 24 | Developer input — supervised rebuild/bring-up closing 8 of the 9 UNCERTIFIED-BY-EXECUTION dimensions. RAN 2026-09-11 21:1x against `cd591f8`/`5fe9435` with `RELOAD_ANDROID=true`. Closed: whole stack up from cold (44/44 healthy, 0 error tokens), value visibility in a running container, marker-driven real reinstall, and both row-38 and row-39 live. NOT closed, and still `UNCERTIFIED-BY-EXECUTION` in those words: lock-serialized tier-03 parallel install (`USE_LOCKS=false`, untestable this run), a web-server handler actually writing `tools/errors/<token>`, and consumer fail-fast behind a failed web server — the last two need deliberate failure injection, which was not authorised. State is `done` with NO sha on purpose: a bring-up is not a commit, so the collector reads it as *claimed*, not *verified*. | M | done | - | - |
| 25 | Sweep — web-server iou handlers write an error token on exit 1; de-hardcode WEB_SERVER_SCRIPTS | M | done | a1ba6f1 | docker/config/dist/bin/caddy-bin/*.sh docker/config/dist/bin/httpd-bin/*.sh docker/config/dist/bin/nginx-bin/*.sh bin/tests/startup-prologue.test.sh |
| 26 | Sweep — retire the stale `# @todo fix pin versions` TODOs (NOT pin: .hadolint.yaml already rules against it) | L | done | fc10204 | docker/images/*/Dockerfile* templates/ghost-blog/Dockerfile |
| 27 | Sweep — CLAUDE.md corrections (141/1 claim, stale suite counts, LOCAL slot, exclusion list) | S | done | 3f94de3 | CLAUDE.md |
| 28 | Sweep — settings.json ask-tier vs CLAUDE.md; RULED 2026-09-04 keep the `ask` trio, correct 8 doc claims (handover script run by the developer 2026-09-05) | S | done | 10ab7f6 | CLAUDE.md .claude/agents/reproducibility-reviewer.md .claude/agents/stack-infra-reviewer.md docs/BLAST-RADIUS.md |
| 29 | Sweep — prune TODO.md (item 189 + zig drift done; consolidate its 5 container-test items with row 24) | S | done | cec239d | TODO.md |
| 30 | E7 — normalize the 3 android stackCatch handlers to the post-row-25 shape (exit 1 reported, `_STACK_CAUGHT`, 141 exemption on start, error token written before `sleep infinity`, `message:`→`command:`); extend §19 discovery to the whole exempt family, shape-agnostic; fix the new-service scaffold | M | done | 36e03cd | docker/config/dist/bin/android-bin/*.sh bin/tests/startup-prologue.test.sh .claude/skills/new-service/SKILL.md |
| 31 | P0 — `--sdk` is a GLOBAL option, not a subcommand option: `b2ae4d1` wrote `android sdk install --sdk=…` at all 3 call sites, which the CLI rejects with exit 2. Move it to `android --sdk=… sdk …`, drop the `2>/dev/null` OR-TRUE swallow that turned that exit 2 into a FATAL blaming the package ids, make one array the source of truth for install AND verify (11 of 24 ids were verified while the comment claimed all), replace `.env`'s stale line-number anchors with names, decouple the config.ini rewrite from the `_google_apis` reverse-parse, quote `${ANDROID_HOME}`, rename `..._SDK_URL`→`..._SDK_BUILD` | M | done | 76dadb1 | docker/config/dist/bin/android-bin/global-stack-android-setup*.sh .env docker/images/0{4android,5edge,5stable}/docker-compose.yaml bin/tests/startup-prologue.test.sh bin/tests/env-update.test.sh templates/tips/env-update.md |
| 32 | A10 at whole-class scope — a trailing test-led `[[ cond ]] && cmd` returns the FALSE test as the SCRIPT's exit status. 4 sites: `android-setup.sh` (unreachable today — `start.sh:115` exports the var before its only call site) and `node24/node26/nodeedge-setup.sh` (reachable — `nvm-start.sh:143` calls them as bare statements under `set -xeEu` with the prologue ERR trap). Convert to `if`, behaviour identical; add §46, a DISCOVERY-based guard (a hardcoded list of 4 would be §19's can-never-fire defect again) narrowed to TEST-led `&&` so the legitimate OR-TRUE and `cmd &&` last lines stay green | M | done | 75a8291 | docker/config/dist/bin/android-bin/global-stack-android-setup.sh docker/config/dist/bin/node*-bin/global-stack-nvm-node*-setup.sh bin/tests/startup-prologue.test.sh |
| 33 | A8a at its real width — the android SDK gate's composite marker carried 3 of the 12 `GLOBAL_STACK_ANDROID_*` inputs `setup.sh` actually consumes, so a bump of any of the other NINE was silently never applied (`gs_version_gate` answered `skip`). Widen `GS_ANDROID_SDK_WANT` to all 12 in a fixed order on ONE line (§27 extracts it with `grep -m1`), rewrite the half-false fence comment that called `_PLATFORM_TOOLS_VERSION` comment-only when row 31 made it a pinned id, and add §47 — a DISCOVERY-based bidirectional check (consumed ⊆ composite AND composite ⊆ consumed) with a `>= 12` floor. §27's probe now pins all 12 explicitly (it was inheriting 9 from the developer's shell) and bumps them one at a time. Cost stated up front: one forced full SDK reinstall on the next `make up` | M | done | 7a8974c | docker/config/dist/bin/android-bin/global-stack-android-start.sh bin/tests/startup-prologue.test.sh CLAUDE.md |
| 34 | Hygiene batch, authorised as 5 items — 4 falsified or already settled on re-verification (see the 16:20 FINDING). DONE: the dead `_NDK_BUNDLE_VERSION` compose plumbing removed from 4 files (the `.env` var itself is a documented deliberate RECORD and stays), and trailing newlines added to the 49 of the 103 dist/bin scripts then present that lacked one (102 since row 35), each exactly `1/1` in numstat. NOT DONE with evidence: rootAVD pin (declined on the merits 2026-09-11 10:12, reason still valid), `sdk-init` removal (not an orphan — live rsync at `sdkman-start.sh:127`, 4 assertions pin it), `API_LEVEL_3` bump (a documented `lock:` on the beta) | S | done | 5ef6b67 | docker/images/0{4android,5edge,5stable}/docker-compose.yaml .env docker/config/dist/bin/**/*.sh |
| 35 | Remainder of the hygiene backlog, six items after E8's retraction. **PATH well-formedness**: a literal `::` (POSIX empty element = the CURRENT DIRECTORY on PATH) at FOUR sites, not the 2 filed — `android-start.sh` and `alltogether-start.sh`, twice each; and `caddy-start.sh:8` glued `${PATH}` with no colon, so `caddy/bin` was never on PATH AND the first inherited element was eaten (line 15 wrote the correct form, proving a typo; it expands the corrupted value, so one fix repairs both). New §48 discovers both classes over the 38 PATH-writing lines with a `>= 30` floor, ANCHORED — a bare `PATH=` also matches every `*_PATH=` var here, inflating the corpus to 138 and making the floor unfalsifiable. **E7-g at CLASS scope — filed as 3, the sweep found 8**: the three `*-setup.sh` plus `caddy-iou.sh`, `httpd-iou{,-common}.sh` and `nginx-iou{,-common}.sh`, the same family row 25's Files cell scoped away. All read `${1}` under `set -u` above their handler; measured argless all eight exit 1 writing ZERO error tokens — the same unattributable death row 30 fixed in `android-start.sh`. Reads moved below whichever of the `trap` line and the `stackCatch` DEFINITION comes LAST — half the family traps first, half defines first, and getting only one right still writes nothing. New §49 ENUMERATES the class (`set -u` + a column-0 positional read) rather than listing it, with `base-dump-pg-project.sh` a named exemption; its S3 sabotage proves the half-fix reds. **E7-f**: `base-set-bash-strict.sh` deleted, zero callers under both sweeps, superseded by the prologue. **Harness abort**: fixed at the root — not §15 but `assert_output_contains`'s unguarded `out=$("$@" 2>&1)`, shared by all 31 call sites. **Fragile register**: the `set +E`-is-inert entry was wrong on all three claims (measured: `set +E` works under extdebug) | M | done | 7a8974c | docker/config/dist/bin/**/*.sh bin/tests/startup-prologue.test.sh docs/plans/MASTER.plan.md CLAUDE.md |
| 36 | P0 REGRESSION found by the developer's own restart, not by the backlog. `7e8c0b2` (2026-09-10 19:22, "drop `gem --debug`") parked its explanatory comment BETWEEN the continued arguments of `rbenv-start.sh`'s `global_stack_base_setup_packages` call. A `\` splices the next line on, so the command ended at that `#`: the call silently took FOUR arguments instead of five — `gem install` never passed, so no ruby gem could ever install — and the orphaned `--command='gem …'` line ran as its own command, exit **127**. It stayed hidden for a day because 03ruby3/03ruby4 had started at 12:21, seven hours BEFORE the commit; the first restart surfaced it and took SEVEN containers down via `depends_on` (03ruby3, 03ruby4, 02rbenv, 04android, 04serverless-framework, 05stable, 05edge). Comment moved above the call; new §50 DISCOVERS the class, narrowed to a comment continuing a LIVE line so the six genuine commented-out blocks stay green | S | done | 0bd182d | docker/config/dist/bin/rbenv-bin/global-stack-rbenv-start.sh bin/tests/startup-prologue.test.sh |
| 37 | P0 STARTUP RACE, found by the same restart. `down` deletes `tools/elapsed`; on the next `up` every service appends to it, and several run as ROOT (01postgres18, 01mysql9, 01mariadb13, 01mongo7, 02dpage-pgadmin4) via their healthcheck's `healthcheck-elapsed.sh`. The first root appender CREATES the file `root:root 0644`. 00base runs as `developer` and is the ONLY service opening it with `>` (base-start.sh:54 -> print-success.sh:23, the "create" arm), so it is denied, dies, and EVERY service depends on 00base. `print-success.sh`'s `chmod o+w` cannot save it: it is line 24, one line AFTER the write that fails. Observed: 00base Exited(1), `/stack/tools/elapsed: Permission denied`, 7 containers blocked. Fix: `create-paths` pre-creates it as the HOST user at 0666 before any container starts, so root appenders find an existing file and ownership is never taken. 0666 not 0644 because seluser/sonarqube containers append too -- what the `chmod o+w` always intended. No or-true guard on the chmod: a failure there means the file is already root-owned and 00base will die anyway, so failing `up` loudly is the better failure. 3 checks added to makefile-posix (7 -> 10), all three sabotaged | S | done | 321de07 | Makefile bin/tests/makefile-posix.test.sh |
| 38 | P0 found by the same restart, and the FIRST failure row 33's forced SDK reinstall actually executed. `platform-tools` is SINGLE-INSTANCE upstream and takes NO version, so `_pkgs`' `"platform-tools;${…_VERSION}"` answered `Package platform-tools/37.0.1 not found.` and EXITED 0 — nothing installed. Row 31 fixed only the LISTING half, adding a `"platform-tools;"*) _id="platform-tools"` exception — correct in itself, but existing only because the install id carried a version. **The shipped verify CAUGHT the defect and the SUITE did not**: on the first boot that ever ran this block it printed `FATAL: … these packages are absent: platform-tools` and exited 1 (2026-09-11 18:36), which is how this was found; meanwhile the §43 stub recorded whatever it was handed and re-applied that same mapping, so 43q–43t were green on a package that could never install — a stub mirroring the code's assumption tests nothing but the mirror. `adb` absence window = that one failed reinstall (18:36 → fix); before it the block had never run (warm-volume `skip`) and the pre-row-31 install was still on disk. Measured: all three single-instance ids (`platform-tools`, `ndk-bundle`, `emulator`) reject a version this way while multi-instance `build-tools;37.0.0` is accepted. Install id bare, exception deleted, stub made faithful, and the `.env` pin reinterpreted as an EXPECTED version (it is not requestable) asserted against the installed build with a WARN — which §47a/47c independently REQUIRE, since dropping the var from `setup.sh` reds both. New §43z/43z2 static class guard (an `ndk-bundle;<ver>` regression reds too) and §43aa–43ac on the assertion; 601 → 606 | S | done | cd591f8 | docker/config/dist/bin/android-bin/global-stack-android-{setup,start}.sh bin/tests/startup-prologue.test.sh CLAUDE.md |
| 39 | P0 found while verifying row 38, and the reason row 38 needed a hand-deleted cache to go green. `base-bin/global-stack-base-chown-home.sh:50` ran `find "$HOME/" -type f -exec sudo chmod 600` from the ENTRYPOINT of every container, and a numeric `600` also strips the OWNER's execute bit -- so any tool caching an executable under `$HOME` is disarmed on the NEXT boot. Measured: `~/.android/bin/android-cli` (the launcher's 87 MB self-download, 0755) becomes `-rw-------` and the SDK reinstall dies `Failed to exec android binary: Permission denied (os error 13)`; second instance same day, serverless v4 caches `sf-core.js`, a bundled `esbuild` and `invoke.py` under `~/.serverless/releases/<ver>/` at 0755. The first draft of this row blamed `binary.js`'s `existsSync(binaryPath)` gate and was WRONG -- `binaryPath` is `<serverless>/node_modules/.bin/serverless-linux-amd64-<v>`, under `tools/`, which chown-home never touches. Measured instead: with all three release files at 0600 `serverless --version` still returns 4.42.0 (the Go launcher runs sf-core.js via `node`; read suffices), while the bundled `esbuild` is a native ELF that answers `Permission denied` at 0600 and prints `0.28.2` at 0755 -- so the break is real but confined to a bundling/deploy path, and is [Inferred], not exercised. ARMED, not always-firing: a normal boot never invokes `android` (`gs_version_gate` -> skip; `avdmanager` is a 5760-byte shell script calling `java` directly), so only a reinstall boot meets a stripped cache -- the same hiding pattern as row 31. Fixed with `chmod ug-s,go-rwx` (every group/other bit gone, setuid/setgid gone, owner untouched; can only PRESERVE an x, never add one), ssh verified satisfied against a real sshd (600/700 accepted, 640/660/604 rejected), and the `.docker/cli-plugins` `a+x` arm DELETED rather than joined by a second exception (it never fired; docker's plugins live in /usr/libexec). New §51, 606 -> 614. Certified by execution: `04android` restarted with the fixture in place, synced script line 89 shows `ug-s,go-rwx`, `android-cli` survived at `-rwx------`, `android --version` = 1.0.16261425, container healthy in 57s, 0 error tokens. | S | done | 5fe9435 | docker/config/dist/bin/base-bin/global-stack-base-chown-home.sh bin/tests/startup-prologue.test.sh CLAUDE.md |
| 40 | Build BROKEN by `1aa924f`, reported by the developer: `apt-get update --allow-releaseinfo-change` fails `E: Command line option --allow-releaseinfo-change is not understood in combination with the other options`, exit 100. That commit copied the `00base` apt idiom into the only TWO images that do not descend from `00base`, and they are far older than the option (apt 1.5, 2017 -- measured against apt's own `debian/changelog`, NOT the 1.9.3 this row first claimed from recall): `01epiclabs-docker-oracle-xe-11g` = Ubuntu 16.04 xenial / apt 1.2.32, `02mongoclient-mongoclient` = Debian 8 jessie / apt 1.0.9.8.6 (read out of each image's layer 0; reproduced byte-identically in a clean `ubuntu:16.04` AND on both real base images). DECISION: they are NOT one class and get different cures. epiclabs -- xenial is still served (archive.ubuntu.com 200, old-releases 404), so dropping the flag IS the fix; the tzdata install then genuinely works. mongoclient -- apt cannot be used at all: jessie is archived so `deb.debian.org` 404s and `apt-get update` exits 100 even WITHOUT the flag, and the image was slimmed by deleting `/usr/share/zoneinfo` without telling dpkg, which still reports `tzdata 2019c` `install ok installed` owning 1902 files, making `apt-get install tzdata` a SILENT no-op and `--reinstall` undownloadable. Re-pointing at archive.debian.org was REJECTED (needs Check-Valid-Until=false plus an expired-key auth bypass, and still cannot reinstall); zone files instead come from a pinned `ubuntu:${GLOBAL_STACK_IMAGE_UBUNTU_VERSION}` stage via `COPY --from`, the var wired through the compose build args. An earlier plan to simply DELETE mongoclient's RUN (on the layer-0 reading that tzdata was already present) was FALSIFIED by checking the FINAL image -- it would have shipped the bug looking fixed. Certified by execution: targeted `docker compose build` of both = rc 0, and both containers now report `date +%Z` CEST / winter CET where they printed the literal `Europe` before. Sabotage both ways: re-adding the flag reds the build with the original error; removing the `COPY` leaves the build GREEN (rc 0) while `date +%Z` returns to `Europe` -- so the build alone certifies nothing here and the runtime check is the guard. Be precise about what IS and is NOT automated: the new §35c/§35e are TEXT guards pinning the mechanism (the `COPY`, the pinned `FROM`, the absence of the flag), no suite runs either container, and the `date +%Z` certification was manual -- run as each image's OWN default user (root for epiclabs, node for mongoclient) after an earlier pass used `--user root` and so would not have proven mongoclient's real user can read the copied tree. The probe needs `-e TZ=Europe/Paris` to reproduce: neither Dockerfile sets `ENV TZ` (compose supplies it), so run verbatim without it both images print `UTC CET`, which reads as a regression that is not there. UNCERTIFIED: every runtime probe used `--entrypoint sh`, so neither service was ever started through its own entrypoint -- for Oracle that gap matters most, and the honest form of it is that `/usr/sbin/startup.sh` IS the entrypoint and contains no TZ reference at all (grep rc 1), so the Oracle processes inherit TZ from the container environment and were never observed resolving the zone the way glibc-in-sh did. Restore verified byte-for-byte by sha256. | S | done | ffa84cb | docker/images/01epiclabs-docker-oracle-xe-11g/Dockerfile docker/images/02mongoclient-mongoclient/Dockerfile docker/images/02mongoclient-mongoclient/docker-compose.yaml bin/tests/startup-prologue.test.sh CLAUDE.md |
| 41 | Developer request 2026-09-12: tag a `.env` pin so env-update resolves latest / latest-1 / latest-2, for the android `platforms;android-` API levels and `build-tools`, so both families always cover the three latest releases. Ruling: stable window, fully AUTO, no `(manual)` (slot 3 loses its deliberate beta). SHIPPED as two pieces. (a) env-update: a generic `(offset:N)` annotation flag (parse.sh recognises/validates it, `offset` record field, refused at parse time with any non-stable `(channel:)`), applied in `_gs_eu2_channel_select_best` through a new third argument via `_gs_eu2_channel_nth_newest` (N-th newest DISTINCT version, `1.2.0`/`v1.2.0` one step; past the end → nothing, never the oldest); and the `sdkmanager` fetcher REWRITTEN to read Google's `repository2-3.xml` over HTTP instead of shelling out to a local `sdkmanager` on `tools/` — which resolved nothing with the stack down (`/stack/tools` held only `caroot/` at the time) and could not parse `platforms;android-<LEVEL>` at all (regex wanted `platforms;<digit>`), the real reason the API levels carried a year-old `(lock:)` claiming the fetcher "returns the revision". The parser takes the version from the `path=` attribute (NOT `<api-level>`, which the 37.2 betas mislabel as 37.1), strips `android-` for platforms, drops `-extN` extension SDKs, codenames and `obsolete="true"` packages, reads bare-id versions from `<revision>` (with `-rcN` from `<preview>`), and suffixes a non-stable `channelRef` (`36.6.11-dev`) so the stable pick cannot land on it; `build-tools;37.0.0-rc2` sits in channel-0, so selection keys on the version STRING. The offset is IN the cache key (`sdkmanager:ID:CHANNEL:offN`) — without it the three platforms slots resolved to one value, silently (t33l). (b) android: the two hardcoded compat `build-tools;36.0.0`/`36.1.0` became `GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_2/_PREV_1` — `.env` (offsets 2/1/0 on both families, `(channel:unstable)` dropped, API_LEVEL_3 37.2-beta1 → 37.2), four compose files incl. the gitignored `local.05`, `_pkgs`, `GS_ANDROID_SDK_WANT` 12 → 14 inputs, §27/§47 pins 14. Certified by execution: env-update suite 862/862 (new §33 rewritten on an XML fixture, 16 cases; new §122, 10 cases incl. a six-record end-to-end `--check`); startup-prologue 620 total with only the four §31 failures, which fail identically at HEAD (verified against a copy of the HEAD suite) and are unrelated; `env-scan` synced the two vars into `.env.local`; `env -i … docker compose config -q` rc 0, empty stderr; LIVE against Google: all 14 android records resolve (`up to date`), and a stale copy of `.env` proposed `36.0.0 / 37.0 / 37.1 / 37.2` for the four slots one step behind. Sabotage, all red then restored byte-for-byte: cache key without offset (t33l), cross-check removed (t122d), nth off-by-one (8 red), `-ext` filter dropped, obsolete filter dropped (needed a fixture entry — the first attempt passed because nothing obsolete was in the fixture), channel suffix dropped, composite key dropped (27b2/27f/47b), `_pkgs` slot dropped (47a/47c), doc cache-key line gutted (45b2). Harness lesson, measured: §45b anchored on the old doc text `sdkmanager --sdk_root`, and after the §7.9 rewrite its unguarded `$(grep …)` killed the run at line 667 with NO tally — two android sabotages read as "not caught" until the log was opened (§47 had never run); now or-true-guarded and anchored on the new facts. Two facts the developer must know: a shift that crosses a major (37.2 → 38.0) is `HOLD` under decide.sh rule 7 like every record (`--force-hold` applies it — seen live: `35.0.1 → 36.0.0` and `36.1 → 37.0` came back HOLD); and every window shift reinstalls the SDK on the next boot. UNCERTIFIED-BY-EXECUTION: no container was started — that the `04android` boot installs `build-tools;36.0.0`/`36.1.0` from the two new vars is proven by the §43 probe against a stub `android`, not by a bring-up; the next `make up` reinstalls the SDK (API_LEVEL_3 changed) and is the runtime proof. 6C follow-up (advisor finding, same day): `(offset:N>0)` was accepted on all 12 types but honoured by `sdkmanager` alone — the other fetchers call the selector without it, so `(offset:1) dockerhub:…` resolved to latest silently; parse.sh now refuses it naming both types (`_GS_EU2_OFFSET_TYPES`), t122k/t122l, docs corrected (the tips row had claimed the other fetchers "accept the flag through the shared selector"). Suite 864/864. | M | done | 9eced59 | bin/lib/env-update/** bin/tests/env-update.test.sh bin/tests/fixtures/env-update/http/dl.google.com_android_repository_repository2-3.xml bin/tests/startup-prologue.test.sh .env docker/images/04android/docker-compose.yaml docker/images/05stable/docker-compose.yaml docker/images/05edge/docker-compose.yaml docker/config/dist/bin/android-bin/global-stack-android-setup.sh docker/config/dist/bin/android-bin/global-stack-android-start.sh templates/tips/env-update.md CLAUDE.md docs/plans/MASTER.plan.md |
| 42 | Developer reported `make hard-restart` producing errors that were not there before. Diagnosed: `03nodeedge` is the ONLY failing service -- `exited (4)`, restart budget `on-failure:5` EXHAUSTED so it cannot self-heal, 6 error blocks in `tools/elapsed`, `tools/errors/node.edge` the only token; `05edge` is its only dependent and is blocked in `created`. Everything else is healthy or inside its 24h start period (`02keycloak` flapped unhealthy then recovered; `02mongoclient` restarted 3x racing `01mongo7` then connected, no token; `03python3` waits on `02rust`, not on nodeedge; two `Created` strays are `twes-node-ci:22` from another project). ROOT CAUSE, and it is upstream, not the android work: `de72e51` (env-update `--apply`, 10:18) bumped `GLOBAL_STACK_NODEEDGE_VERSION` `…20260911 0de4fcceb9` -> `…20260912 565f69f986` because `(fetch-json:max_by(.date).version)` takes the newest `index.json` entry -- but nodejs.org ANNOUNCES a nightly before all its platform artifacts land. That build's `SHASUMS256.txt` holds SIX entries (darwin-arm64, linux-ppc64le, linux-s390x) and NEITHER `node-<v>-linux-x64.tar.xz` NOR the source `node-<v>.tar.xz` exists -- both 404, re-probed 10 minutes apart with SHASUMS unchanged, while the previous nightly returns 200 for both. nvm finds no binary, falls back to source, 404s again, returns exit 4; `gs_install_retry_purge` retries once and the second failure fires the ERR trap. `(stale-after:14d)` does not cover this: it guards a FROZEN index, not an INCOMPLETE one. FIX (developer chose rollback + class fix over rollback-only, which is a Rule 14 bandaid since the next `--apply` re-picks it): pin rolled back to `…20260911 0de4fcceb9`, and a new `(verify-asset:<url with {version}>)` flag makes the url fetcher PROVE the artifact exists before proposing. `(fetch-json:)` emits a newest-first candidate list, the fetcher walks it (capped by `_GS_EU2_VERIFY_ASSET_MAX`, default 10) and takes the first candidate whose asset returns 200, WARNing each rejection to stderr with the version and the 404 URL; none verify -> NO proposal (SKIP), never a broken pin. Refused at parse time when it lacks `{version}` (a fixed URL cannot discriminate), when `(fetch-json:)` is absent, or on a non-`url` type -- the `b2290dc` shape, since only Tier 2 reads it. Ungated single-value records are untouched, and the flag is in the cache key so gated/ungated cannot share an entry. Certified by execution: new §123, 11 cases, RED FIRST for the stated reason (`vAvBvC` -- the pre-existing newline-strip concatenating multi-line jq output) then 11/11; fixture index deliberately lists the three nightlies OUT of date order so a pass proves `sort_by(.date)` then `reverse` ordered them. LIVE against the real nodejs.org: `WARN: verify-asset skipping v27.0.0-nightly20260912565f69f986 -- artifact not published (HTTP 404)` then `[SKIP] (up to date)` -- i.e. had this existed at 10:18 the bump would never have happened. shellcheck clean; shfmt drift identical to HEAD (zero introduced). | M | done | 0ee59d3 | bin/lib/env-update/fetchers/url.sh bin/lib/env-update/core/parse.sh bin/lib/env-update/core/records.sh bin/tests/env-update.test.sh .env templates/tips/env-update.md bin/lib/env-update/reporting/reference.sh CLAUDE.md docs/plans/MASTER.plan.md |
| 43 | Developer reported errors after `make hard-restart`; `04android` was the second of three failures (see rows 42, 44). FATAL: `android sdk install reported success but these packages are absent: system-images/android-37.2/google_apis_ps16k/x86_64 system-images/android-37.2/google_apis_playstore_ps16k/x86_64`. ROOT CAUSE, measured against Google's live XMLs: row 41's rolling window rolled `API_LEVEL_3` to 37.2 because `platforms;android-37.2` IS channel-0 (stable) -- while BOTH of its system images sit on channel-2 (dev). `android sdk install` is stable-only and EXITS 0 on `Package not found`, so both were silently skipped and only the shipped verify loop caught it. Row 41 had anticipated a TAG RENAME; the class that bit is CHANNEL SKEW between a platform and its companions -- and note the 37.2-BETA images ARE channel-0, which is exactly why the previous `37.2-beta1` pin worked and the promotion broke it. FIX: `(require-sibling:URL` + pipe + `ID_TEMPLATE,...)` on the sdkmanager fetcher -- a candidate survives only when EVERY listed companion is present, channel-0 and not `obsolete="true"` in its named XML. Four load-bearing properties: each pair carries its own URL (the tag -> document mapping is data Google publishes, not a rule derivable from the id -- deriving it would encode a guess); the filter runs BEFORE `_gs_eu2_channel_select_best` so `(offset:N)` counts qualifying levels only; it FAILS CLOSED (unreachable companion XML -> ERROR, pin unchanged, never an empty set a filter reads as "nothing to exclude"); and a repeated flag is REFUSED at parse, because the store is last-wins and the first pair would vanish while the gate read as checking both tags. Each XML is fetched once per run. The spec joins the cache key but is appended ONLY WHEN SET -- an unconditional segment leaves a trailing colon that invalidates every cached sdkmanager entry, which the pre-existing t33g caught on the full-suite run (the section-only run had not). Window hand-rolled to 36.1 / 37.0 / 37.1: the correction direction is DOWNWARD, so decide.sh rule 5 makes each a SKIP and `--apply` can never walk the window back -- the gate's job is to stop the next `--apply` re-picking 37.2. Certified by execution: §124, 14 cases, RED FIRST for their stated reasons -- four refusal tests were first GREEN VACUOUSLY on the generic `unknown flag require-sibling` message and were tightened to demand the specific cause before being accepted. Five sabotages, each restored byte-identically by sha256: cache-key segment dropped -> t124l; fail-open on an unreachable XML -> t124j; stop after the first pair -> t124h; obsolete filter dropped -> t124i; channel check dropped -> t124f. env-update 889/889, startup-prologue 622/622. §45b2's fixed `-A40` window was re-bounded on the next heading: row 43's prose pushed the cache-key line out of view and redded a guard whose subject had not changed -- a window ordinary growth can invalidate is the mirror of a can-never-fire check. LIVE: the three gated records return `up to date`; the same record with the flag stripped returns AUTO `37.1 -> 37.2`. RUNTIME: 04android recreated, `ANDROID_HOME` wiped and the SDK reinstalled, all six system images downloaded, verify loop passed, success token written, container HEALTHY, and all three AVDs created and templated. Known non-blocking noise: 18 `Could not load devices from .../devices.xml` lines, one per image per pass -- NO system image ships that file (`find` count 0), so avdmanager falls back to its bundled device definitions; zero non-devices.xml Error lines in the log. | M | done | 825444a | bin/lib/env-update/fetchers/sdkmanager.sh bin/lib/env-update/core/parse.sh bin/lib/env-update/core/records.sh bin/lib/env-update/reporting/reference.sh bin/tests/env-update.test.sh bin/tests/startup-prologue.test.sh .env templates/tips/env-update.md CLAUDE.md docs/plans/MASTER.plan.md |
| 44 | Third of the three post-`hard-restart` failures (rows 42, 43). `02rust` exited 101: `cargo install cargo-outdated` failed compiling `jiff 0.2.36` -- `couldn't read .../jiff-0.2.36/src/../../../../CHANGELOG.md` (also COMPARE/DESIGN/PLATFORM.md). Restart budget `on-failure:5` exhausted, and `03python3` + `05edge` sat in `created` behind it. Two hypotheses were discriminated rather than assumed: a corrupt extraction in the shared `tools/cargo` registry was FALSIFIED -- the `.crate` archive itself holds 104 entries and not one `.md`, so the extraction is faithful and the PUBLISHED CRATE is broken. jiff 0.2.36's `Cargo.toml` include list packages `/*.md`, which is PACKAGE-root relative, while `src/lib.rs`'s UNGATED `pub mod _documentation` does `include_str!("../../../../CHANGELOG.md")` -- three levels ABOVE the package root. Upstream agreed: 0.2.36 was published 2026-09-12 15:13, YANKED, and superseded by 0.2.37 at 15:39; our build landed inside that 26-minute window. ROOT CAUSE ON OUR SIDE, which is the part worth fixing: `cargo install` IGNORES the committed `Cargo.lock` by default and re-resolves to the newest semver-compatible release, so `--tag v0.19.0` pinned only OUR source and not the dependency set that tag was tested against. v0.19.0's own lockfile pins `jiff 0.2.23`; `cargo fetch --locked` at that tag exits 0, so the lockfile is consistent. FIX: `--locked`, an outlier restored to the local convention -- the other four install sites in the same directory (nextest, zigbuild, jujutsu, mergiraf) already carried it and `git log -S'--locked'` shows it was never removed, only never added. TDD: startup-prologue §52 DISCOVERS the class (comment lines stripped first -- cargo-nextest.sh explains `--force` in a comment containing the literal `cargo install`, which would seat a permanently un-fixable offender in the corpus), red first naming cargo-outdated, then 622/622. Sabotage: stripping `--locked` from jujutsu reds 52b naming jujutsu; breaking the find root reds the 52a floor WHILE 52b passes green on the empty set -- the non-vacuity guard demonstrated live rather than asserted. Both restored byte-identically. Certified by execution, and note WHY the success token alone would not have been evidence: 0.2.36 is yanked, so an UNLOCKED install today resolves 0.2.37 and succeeds too. The build log is the proof -- `Compiling jiff v0.2.23` (the tag's lockfile) and `Installed package cargo-outdated v0.19.0`; 02rust HEALTHY after `--force-recreate`. | S | done | 6e3f6c9 | docker/config/dist/bin/rust-bin/global-stack-rust-install-cargo-outdated.sh bin/tests/startup-prologue.test.sh docs/plans/MASTER.plan.md |
| 45 | Developer request 2026-09-13: drift check of `templates/shell/*` against their live copies (`/etc/profile.d/stack.sh`, end of `~/.bashrc`, end of `/etc/bash.bashrc`, end of `~/.profile`, `~/.local/bin/`), then sync. Direction ruled PER CHANGE after dating each one, never blanket. `b3d6c64`: 11 live `/etc/profile.d/stack.sh` lines ported into `profile.sh` (live untouched). `ad61673`: `.shellrc` gains live's phpbrew `source` line and Angular `ng completion` (template GUARDED with `command -v ng`, live is not -- deliberate); templates indent with 4 spaces as live does (`profile.sh` only on the fullauto `claude()` line, so the block stays byte-identical for fullauto Case 6, confirmed red then green); the dangling `claude-mem` alias is NOT ported, ruled removed from live `~/.bashrc` by the developer. Expected residual drift: the ng guard, and whitespace-only hunks in `profile.sh`. No suite pins the phpbrew line or the ng guard -- evidence is `bash -n` on the extracted block plus the live-vs-template diff. | S | done | ad61673 | templates/shell/.shellrc templates/shell/shell.shellrc templates/shell/profile.sh |
| 46 | Developer request 2026-09-14: `sdkmanager` is deprecated upstream (a shim over `android sdk`) and 04android already uses `android sdk`, so every remaining usage moves. Rulings (AskUserQuestion, 2026-09-14): type token `androidsdk:`; a leftover `sdkmanager:` is a HARD parse refusal (dispatch is dynamic -- an unknown type SKIPs silently); marker `android.sdkmanager` -> `android.cli` WITH an in-script `mv` migration before the gate (an absent marker = `sudo rm -rf ANDROID_HOME` + 15-min reinstall). `6672f05`: fetcher `git mv` sdkmanager.sh -> androidsdk.sh (functions, `_GS_EU2_ANDROIDSDK_REPO_URL`, cache-key prefix), both flag allow-lists, 13 `.env` annotations; open-all-envs `sdkmanager --sdk_root --list` -> `android --sdk="${ANDROID_HOME}" sdk list --all` (host-measured: rc 0, 645 lines, all 85 build-tools versions) and the androidsdk type skipped so its require-sibling XML URL is never opened. Tests red-first: env-update §125 (5), open-all-envs cases 7-8 (6, `android` stub rejects `--sdk` after the subcommand like the real CLI), startup-prologue §53 (7, runs the shipped migration block against a tmpdir). Green: env-update 894/894 (two whole-suite runs were killed for low memory by other processes on the box, so it ran as five `--section` batches 1-25/26-50/51-75/76-100/101-125, each ending `ALL PASSED`: 162+174+210+177+171), open-all-envs 22/22, startup-prologue 629/629. Six sabotages red, restores byte-identical. UNCERTIFIED-BY-EXECUTION: the migration inside a real 04android boot (the live 13-byte `tools/versions/android.sdkmanager` moves on next start) | M | done | 6672f05 | bin/lib/env-update/** bin/open-all-envs.sh templates/tips/** bin/tests/env-update.test.sh bin/tests/open-all-envs.test.sh bin/tests/startup-prologue.test.sh docker/config/dist/bin/android-bin/** .env CLAUDE.md .claude/skills/check-versions/SKILL.md |
| 47 | Developer request 2026-09-14: fix the 04android boot warnings/deprecations (~380 avdmanager package.xml/devices.xml lines from the unversioned cmdline-tools on PATH, the sdkmanager --licenses deprecation, dead legacy PATH entries, emulator/telemetry notices). Implemented S1-S3 (versioned avdmanager by path, PATH reorder + dead entries dropped at 5 sites, licence call guarded); S4-S6 ruled out of scope — see docs/plans/android-boot-warnings.plan.md. Live 04android restart verification owed by the developer. | M | done | a689c68 | docker/config/dist/bin/android-bin/** docker/config/dist/bin/alltogether/** templates/shell/profile.sh bin/tests/startup-prologue.test.sh docs/** |
| 48 | Developer report 2026-09-14: `GLOBAL_STACK_JAVA_DEFAULT_GROOVY_VX1_VERSION` `(channel:unstable)` never proposed `6.0.0-RC-2` over `6.0.0-beta-3`. ROOT CAUSE, reproduced on both `/bin/sort` (uutils 0.8.0) and GNU `gnusort` 9.7: `sort -V` is byte-wise, `R` (0x52) < `b` (0x62), so RC-2 ranked below beta-3 at every `sort -V` site (and lowercasing alone is no fix: it ranks `snapshot` > `rc`). Rulings (AskUserQuestion): ordered tiers (0 dev/snapshot/nightly/canary/edge/experimental/insiders/next, 1 alpha, 2 beta/preview/pre/ea, 3 milestone, 4 rc/cr, stable above all; lowest tier wins on several markers); an unknown suffix is ranked by the marker found inside it; convert ALL sites; fix the use-sha SHA misclassification in the same change. FIX: `_gs_eu2_version_keys` / `_gs_eu2_version_sort [-u]` / `_gs_eu2_version_older` in `core/semver.sh` build a `base~<tier><lowercased suffix>` key (one perl pass, config via `%ENV`, mawk has no intervals) and keep `sort -V` over it — both sorts order `~` before end-of-string. A non-pre-release keeps key == v-stripped input, so its order is unchanged (t126a); the tier map `_GS_EU2_PRERELEASE_RANKS` is index-parallel to the 23 markers. 18 sites converted (channel, decide, drift, main, github, pecl, sdkman, url); two raw sorts kept deliberately (sdkman java numeric field key, androidsdk `sort -uV` whose order is unused). `_gs_eu2_is_prerelease` now returns false for `^[0-9a-f]{7,40}$` (bare or after an `@`) — 5 of 6 use-sha pins had classified PRE via `[0-9]a[0-9]` inside the hex. Certified by execution: env-update 910 (batches 1-25/26-50/51-75/76-100 = 162+174+210+177 run at f20cdfe and NOT re-run after 50e264a, whose lib edits are `#` comment lines only, `bash -n` clean; batch 101-126 = 187 re-run at 50e264a; t126o/t126p and O1–O3 landed in 50e264a); §126 16 cases, 14 red first for the stated reason plus t126o/t126p (per-marker tier table keyed by marker, and one sample per marker through the real key builder — added at 6C because t126n checked only count and range, so a wrong digit at any index passed); t12d tightened to exactly `18.5-rc1`. Sabotage S1–S9 + O1–O3 all red, restores byte-identical. Full-`.env` before/after diff: only GROOVY_VX1 changed (SKIP → AUTO `6.0.0-beta-3 → 6.0.0-RC-2`); a KEYCLOAK ERROR was upstream (HEAD code reproduces it, quay.io 504). Semantics worth knowing: equal KEYS are one version, so `1.3.0-RC1`/`1.3.0-rc1` are neither older than the other and `semver_compare` prints `newer` both ways. t126l certifies GNU order only where `gnusort` exists (visible SKIP otherwise). No `--apply` run. | M | done | f20cdfe | bin/lib/env-update/** bin/tests/env-update.test.sh templates/tips/env-update.md templates/tips/env-laws.md CLAUDE.md docs/plans/** |
<!-- /progress-block -->
### Blocked
- (CLEARED 2026-09-11 21:1x.) Row 24 — the supervised bring-up RAN. Kept for the trail: it was
  POSTPONED by the developer 2026-09-05 (06:25 ruling: a `make up` from cold, no rebuild needed),
  and was the SAME blocker as TODO.md's entire "Requires container testing" section
  (TODO.md:11,25,31,38,48) — one blocker recorded in two files.
- THREE dimensions survive the bring-up and are still `UNCERTIFIED-BY-EXECUTION`, named rather
  than folded into a green: (1) lock-serialized tier-03 parallel install — `GLOBAL_STACK_USE_LOCKS`
  is `false`, so the run could not exercise it and a green here would be vacuous; (2) a web-server
  handler writing `tools/errors/<token>` on a failed install — `01caddy` came up healthy, and this
  is the heaviest of the nine (row 25's fix is certified by handler SHAPE only, never by a run);
  (3) consumer fail-fast behind a failed web server. (2) and (3) need a DELIBERATELY failed web
  server, which is failure injection against a live stack and was not authorised — it is a
  developer call, not an executor one.

### Needs input
- (none open.)
- (RULED 2026-09-04 23:53) Row 28: the developer chose *"Correct CLAUDE.md"* — the three
  `ask` entries stay (all `bin/env-update.sh --apply*`, the one command that rewrites `.env`;
  added `95ccbb7`) and the docs are corrected. The sweep found EIGHT claim sites, not two:
  `CLAUDE.md:26/:45/:49/:143/:369`, `.claude/agents/reproducibility-reviewer.md:28`,
  `.claude/agents/stack-infra-reviewer.md:122`, `docs/BLAST-RADIUS.md:10`. All eight ship in
  `var/claude/fix-ask-tier-docs-20260904.sh` (dry-run proven on a scratch copy: 8 replacements,
  0 stale claims left in any file, a second run aborts on every anchor). The developer ran it
  2026-09-05; landed at `10ab7f6` (8/8 applied, 0 stale claims, repo-wide `git grep` clean). The
  archived 2026-08-06 ruling at `docs/archive/plans/claude-bundle-cross-repo-audit.plan.md:19`
  is left as written — archived plans are archived unchanged (2026-08-31).
- (CLOSED 2026-09-04) Row 17, laravel/installer: the developer ruled *"widen the
  guard — fix it too"*. `composer global update --with-all-dependencies` was
  DELETED and the tool pinned to `GLOBAL_STACK_LARAVEL_INSTALLER_VERSION`;
  landed at `0e71e5b`.

### Needs research
- (none open.) Both questions were answered by work that landed:
  row 20 read all 17 web-server compare sites and converged them on
  `gs_version_gate` (`e9fd01e`); the 21a/21b split WAS taken and both halves
  landed (`ae4f4df`, `53c0859`), with `frankenphp` ruled out of scope (its
  artifact path embeds the version) and `awscli` excluded (no `.env` pin).

### Fragile
- Full 12-entry register lives at MASTER.plan.md:848 — this heading is the
  collector-visible pointer to it.
- (FIXED in row 25, `a1ba6f1` — kept for the lesson.) caddy-iou.sh, httpd-iou.sh
  and nginx-iou.sh exempted exit 1 and lacked `_STACK_CAUGHT`, so a failed
  web-server INSTALL wrote no error token at all. It survived the 2026-08-29
  migration because TWO checks were each structurally incapable of firing:
  `startup-prologue.test.sh` §19 iterated a hardcoded 8-entry array that omitted
  exactly these three, and CLAUDE.md described the exemption as already gone. Two
  can't-fire checks read as two passing checks. §19 now DISCOVERS handlers (11),
  which is what makes it able to fail. NOTE: the fix is certified by handler SHAPE
  only — no run has yet observed one of these writing `tools/errors/<token>`; that
  is the heaviest of the nine UNCERTIFIED dimensions and closes with row 24.
- DO NOT "simplify": `((_elapsed++)) || true` (base-wait-for.sh:44) and
  `((COMMAND_COUNTER++)) || true` (base-setup-packages.sh:52) — post-increment
  from 0 returns status 1 under set -e. Verified by repro.
- ~~sdkman-start.sh's three `set +E` blocks are inert~~ — **this entry was WRONG
  on all three of its claims; corrected row 35, 2026-09-11.** (1) The premise is
  false: `set +E` WORKS under extdebug. Measured — `bash -c 'shopt -s extdebug;
  set -E; set +E; shopt -o errtrace'` reports `errtrace off`, and `SHELLOPTS`
  drops `errtrace` with it. `extdebug` turns errtrace ON when it is set; it does
  not pin it on against a later `set +E`. The blocks provide the tolerance they
  claim and the comments describing them are accurate. (2) The line numbers were
  stale: the blocks are at 161/163, 178/187 and 192/199, not `:145`. (3)
  `base-setup-packages.sh:38` is not about tolerance at all — the real reference
  is **:125** ("Tolerant callers run under set +E; capture a failed command so
  …"). Note also the `set +E` family is wider than sdkman: serverless-framework
  -start.sh:97,106, alltogether-start.sh:82,88 and android-start.sh:86,92.
  Kept rather than deleted: a register entry that was acted on as true for four
  rows should leave a tombstone, not vanish.
- ~~caddy-start.sh:8 is the only one of 18 PATH= assignments missing its colon~~
  — FIXED row 35. Two corrections to the entry as filed: the corpus is **38**
  PATH-writing lines across dist/bin, not 18 (an unanchored `PATH=` grep says 138 by sweeping
  in every `*_PATH=` variable — the mistake §48 was written with and corrected in the same row); and "works only because the scripts
  it calls live in /usr/local/bin" understated it — the missing colon meant
  `${TOOLS}/caddy/bin` was never on PATH *and* the first inherited element was
  consumed by the concatenation. Line 15 wrote the correct form into the shellrc
  from the already-corrupted value, so the one fix repaired both. Pinned by §48c.
- ~~startup-prologue.test.sh §15's harness ABORTS the whole suite~~ — FIXED row
  35, at the root rather than at §15. The abort was not §15's: it is
  `assert_output_contains`'s unguarded `out=$("$@" 2>&1)` (line 63) under the
  suite's `set -euo pipefail`, shared by all **31** of its call sites; §15 was
  merely the first to exercise it. Re-measured before the fix — renaming
  `gs_version_gate` aborted at Section 15 with exit 127 and ZERO tally lines;
  after, the same sabotage exits 1 with a full tally and 26 red assertions, each
  carrying the child's exit code so a 127 is distinguishable from an output
  mismatch.
- SABOTAGE HYGIENE: back up with `cp -a` before mutating, never restore with
  `git checkout` — on uncommitted work it restores HEAD and silently destroys the
  edits under test. Cost a re-do in row 15; the md5 check is what caught it.
  Always `md5sum -c` the restore.

### Known issues
- (CLOSED 2026-09-23 — no longer reproduces: `bash bin/tests/startup-prologue.test.sh` at `9644ac0` → `ALL PASSED ✓ 637 / 637`, exit 0; all four §31a/31b/31c assertions listed ✓ in that run; no commit in `986cfea..9644ac0` touching the suite or `serverless-bin/` targets §31, so the original failure was possibly environment-dependent rather than fixed.) (2026-09-12, row 41) `startup-prologue.test.sh` §31a/31b/31c (4 assertions, the serverless nested-grep probes) FAIL on this machine at HEAD `986cfea` as well as after row 41 — verified by running a copy of the HEAD suite; not touched by row 41. Cause not investigated; the suite's tally is 616/620 until it is.
- (CLOSED 2026-09-05.) `bin/tests/env-update.test.sh` ran to completion on an idle box:
  `ALL PASSED ✓ 844 / 844`, exit 0, 426 s, 118 distinct sections (highest number 121). The
  ninth UNCERTIFIED-BY-EXECUTION dimension is closed; row 24's bring-up covers the other
  eight. History of the 2026-09-04 entry, kept for the lesson: two
  background runs were SIGKILLed by the box, not failed: the first reached section 121 of ~125
  with 0 failures, the second died at section 18. Neither produced the authoritative
  `ALL PASSED` tally line, so neither counts as green. This matches CLAUDE.md's "heavy parallel
  builds get killed on this box" — the suite runs 8 parallel fetch workers. It is the ONE suite
  of 13 not certified in the close-out battery. It matters because row 17 added
  `GLOBAL_STACK_LARAVEL_INSTALLER_VERSION` + its `@todo env-update` annotation to `.env`, which
  this suite's parser reads; the annotation itself WAS exercised directly
  (`bin/env-update.sh --check --filter=LARAVEL_INSTALLER` → resolved `v5.32.0`), but that is one
  fetcher path, not the suite. Re-run it alone on an unloaded machine before trusting the
  milestone as fully certified.
- MASTER.plan.md:484 claims F2 startup-health-signalling "fully executed". That claim was
  **FALSE when written** — it was 8 of 11 handlers, and the sweep caught it. Row 25
  (2026-09-04) closed the gap in the code, which does not retroactively make a past-tense
  statement about 2026-09-01 true; it makes it moot. The wording stands as a historical record
  of what was believed then. What needed correcting was `CLAUDE.md`'s *present-tense* claim,
  and that is in the row 22/27 handover script.
- (CLOSED 2026-09-04) Rows 13/14 Files columns did not match what their shas
  touched — row 13 under-listed (its sha also touched the three `*-start.sh`
  scripts and the test suite), row 14 over-listed `.env` and the startup scripts
  when `7782701` was a plan-only audit commit. Both cells now match `git show
  --stat`. The collector never flagged either, because it only requires OVERLAP
  between the sha and the Files cell, not equality — an over-listed cell passes.
- (MOSTLY CLOSED 2026-09-04, `3f94de3`.) Applied: makefile-posix 5→7,
  open-all-envs 12→16, startup-prologue 220→392, LOCAL slot 41719→41720.
  DELIBERATELY NOT APPLIED: the env-update tally at `CLAUDE.md:321`. That suite
  was SIGKILLed twice today without producing its authoritative `ALL PASSED`
  line, so there is no MEASURED number to write — and writing an unmeasured one
  is precisely how the four stale counts above came to exist. The line already
  instructs the reader to re-run rather than trust it. Correct it only from a
  tally line produced by a completed run. (CLOSED 2026-09-05: measured — 844 tests from the
  suite's own `ALL PASSED` line, 118 distinct section numbers counted in its output; landed
  at `CLAUDE.md:321` in `bc892ac` via a one-line `sed` run by the developer.)
- (CLOSED 2026-09-04, `fc10204`.) `# @todo fix pin versions` across 14
  Dockerfiles became row 26, and the ruling INVERTED the finding: `.hadolint.yaml`
  already ignores DL3008 for this repo, so the TODOs contradicted a standing
  decision, and acting on them would have broken builds on the next Debian/Ubuntu
  archive rotation. They were removed, not actioned.
- TODO.md:189 (WAIT_FOR_TIMEOUT from .env) is already done (.env:46).
- SUPERSEDED: three items were declined by the developer on 2026-09-03, then
  the 2026-09-04 ruling *"absorb everything the sweep found"* reversed two of
  them. `CLAUDE.md:337`'s "141/1 exemption is gone" claim and the hardcoded
  `WEB_SERVER_SCRIPTS` array both became row 25 and are FIXED (`a1ba6f1`,
  `3f94de3`). Only the third — the live 3-entry `ask` tier in
  `.claude/settings.json` vs `CLAUDE.md:49`/`:369` — is still open; it is row 28
  and now sits in ### Needs input with a recommendation. A decline is not
  permanent: re-surface a declined item when the surrounding work changes what
  it costs.

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

- [2026-09-11 19:05] BUILT (row 38) + TOMBSTONE on two earlier entries in this log.
  The live bring-up ran row 33's forced SDK reinstall -- the first time `global-stack-android-setup.sh`'s
  install block had EVER executed -- and it failed: `FATAL: ... these packages are absent: platform-tools`.
  Measured against the real CLI in the running container, all four probes:
  `sdk install 'platform-tools;37.0.1'` -> `Package platform-tools/37.0.1 not found.` **exit 0**;
  `sdk install platform-tools` -> downloads `platform-tools_r37.0.1-linux.zip`, installs;
  `sdk list` -> `platform-tools  37.0.1  Android SDK Platform-Tools`; and the same version-suffix
  rejection for `ndk-bundle` and `emulator`, while `build-tools;37.0.0` is accepted. So the class is
  THREE single-instance packages, bare on BOTH sides, not one exception on the listing side.
  TOMBSTONE 1 -- the 2026-09-11 11:05 row-31 entry above (`:626`) says "a naive `;`->`/` single-array
  transform FATALs on `platform-tools` (single-instance upstream, listed bare...)". True but half the
  rule: it named the LISTING convention and inferred a listing-side exception, when the same property
  governs the INSTALL side. The exception it produced hid nothing -- it mapped the dead id to bare,
  grepped, found nothing and FATALed, which is how this was found. What hid the defect was the §43
  STUB, which re-applied that same mapping and so stayed green. Correct the record in one line: the
  shipped verify worked; the test suite is what was blind.
  TOMBSTONE 2 -- the 2026-09-11 14:34 row-33 entry above (`:687`) says "row 31 made platform-tools a
  pinned id at `setup.sh:80`". It made it a pinned id that installs nothing. The var stays in the
  composite marker either way, so row 33's widening is unaffected and needs no rework -- only its
  REASON changes, from "it is a live install id" to "it is an expected version the verify asserts".
  Red-first, in the advisor's order and measured at each step: the stub fix ALONE redded 43q with
  `1| platform-tools|none` -- that id named and no other -- then the install-id fix greened 43q/43r/43s/43t,
  then 43ab/43ac redded `0||none` with no WARN in existence, and 47a/47c redded exactly as predicted
  (`found 11`, `dead: GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION`) because the var had gone dead in
  `setup.sh`. The version assertion closed all four. 606/606.
  The WARN is deliberate and is NOT a swallowed error: there is no failure to absorb (the install
  succeeded), the pin is UNREQUESTABLE for a single-instance package, the only remedy is a human
  `.env` bump, and a FATAL would strand 04android plus 05stable/05edge/local.05 on documentation drift.
- [2026-09-11 20:05] BUILT (row 39) + a CORRECTION to my own row-38 blast-radius claim.
  Earlier in this session I reported the android CLI as the "sole confirmed casualty" of the
  chown-home defect, on the strength of a sweep that looked only at `.serverless/binaries/`
  (JSON, harmless). A full sweep of every container for owner-executable files under `$HOME`
  found FOUR more in 04serverless-framework -- `sf-core.js`, a bundled `esbuild`, `invoke.py`
  and `metadata.json`, all 0755. The first sweep ran before serverless had downloaded its
  `releases/<ver>/` tree; the tree appeared at 18:36 and the sweep was never repeated. Lesson,
  and it is the third time this session: a blast-radius sweep is a measurement of a moment, and
  a container that installs on first use has a different $HOME an hour later.
  The probe extracts ONE LINE, not the block, on the advisor's amendment, and that is the whole
  difference between a real test and a green one: the block runs `sudo chown -R` first, the
  kernel drops setuid on `chown(2)` of a regular file, so a 4755 fixture would have reached the
  chmod already at 0755 and 51e (`ug-s`) could never have redded. Whole-block extraction would
  have shipped a check that cannot fire -- the class this repo has now hit seven times.
  Seven sabotages, all `cp -a` backups, all restores md5-verified byte-identical:
  S1 revert to `chmod 600` -> 51b/51c/51e/51f red; S2 drop `ug-s` -> 51e ALONE red (the clause
  that whole-block extraction would have made untestable); S3 drop `go-rwx` -> 51b/51c/51d/51e/51f
  red; S4 re-add the cli-plugins arm -> 51a (`found 2`) + 51h (`found 3`) red, so the non-vacuity
  guard doubles as the no-second-file-chmod guard; S5 duplicate the anchor line -> 51a red;
  S6 restore the EXACT shipped pre-fix file from HEAD -> SIX failures / 614, which is the finding
  in one line and the red-first proof this test would have caught the defect before it shipped;
  S7 break the extraction anchor -> 5 red, so the probe cannot pass vacuously on an empty script.
  shellcheck code set identical to HEAD (`SC2086`, pre-existing on the rsync line), shfmt hunk
  count identical (1/1) -- zero new findings, zero formatting drift, the file's pre-existing
  4-space indentation deliberately untouched.
- [2026-09-11 20:40] CORRECTION (row 39), caught by the 6C advisor round, and it is the SAME class
  I blocked row 38 on: I wrote the serverless half of the blast radius as [Verified] in four
  durable places -- CLAUDE.md, this row, this log and the commit message -- claiming `binary.js`
  gates re-download on `existsSync(binaryPath)` so a stripped cache "would neither re-download nor
  run". I had marked `binaryPath` [Inferred] in my own reasoning and then shipped it as Verified
  without resolving it. Resolved now, and the claim was WRONG: `binary.js:172-182` puts
  `binaryPath` at `<installDirectory>/<name>-<version>` with `installDirectory` defaulting to
  `join(__dirname,'node_modules','.bin')` -- i.e. `tools/serverless-framework/node_modules/
  serverless/node_modules/.bin/serverless-linux-amd64-0.0.2`, under `tools/`, which chown-home
  never touches (confirmed on disk at 0755). The falsifier then ran in the container: with
  `sf-core.js`, `esbuild` and `invoke.py` all chmod'ed to 0600, `serverless --version` still
  printed `4.42.0` -- the Go launcher runs sf-core.js through `node`, and a shebang script loaded
  by an interpreter needs READ, not execute. What DOES break is narrower and real: the bundled
  `esbuild` is a native ELF (`\177ELF`), which answers `Permission denied` at 0600 and prints
  `0.28.2` at 0755, so only a bundling/deploy path that shells out to it fails -- and that end-to-
  end break is [Inferred], because no deploy was run. All three files were restored to 0755 and
  re-stat'ed. The lesson is not about serverless: reading a gate's CONDITION is not the same as
  resolving its OPERAND, and a mechanism narrated from source is [Inferred] until the path is
  resolved on disk. The fix itself is untouched by this -- the files are under `$HOME`, they were
  being stripped, and `ug-s,go-rwx` stops it.

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
