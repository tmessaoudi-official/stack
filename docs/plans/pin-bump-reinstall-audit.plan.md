# pin-bump-reinstall-audit Plan

Developer request 2026-09-24, verbatim: *"I want you to verify all pinned version in .env and their
installation scripts ! all of them for reinstalling on a pin bump without hard restart or remving
version or anything ! is it handled cleanly everywhere ? i want 100 % evidence on every variable
version and its usage ! no implementation yet !"* — AUDIT ONLY; nothing below is implemented.

## Decisions Log
- [2026-09-24 10:45] AGREED: fan-out + verify — mechanical inventories both ways, ≤5 read-only agents trace consumer groups, every "handled" verdict re-verified in the main conversation; report in var/claude/ + summary.
- [2026-09-24 10:45] AGREED: image-level pins PASS when a bump reaches the container via a normal rebuild target (make rebuild / down-n-rebuild*) — no hard-restart, no volume wipe, no manual marker delete.
- [2026-09-24 10:45] AGREED: evidence = static trace + behavioural probes of the SHIPPED gate logic against a tmpdir marker (GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS pinned to a tmpdir, never live tools/); no container touched.
- [2026-09-24 10:45] AGREED: certification tier for this audit's 3C and 6C = advisor() only.
- [2026-09-24 12:40] AGREED: second pass (audit only) = every NON-apt install site in the repo — discover anything unpinned (hardcoded / floating) AND prove each .env-pinned installer actually installs the pinned version; apt installs of any kind are out of scope.
- [2026-09-24 12:55] AGREED: pass-2 certification tier for 3C and 6C = advisor() only.
- [2026-09-24 14:35] AGREED (developer, verbatim intent: "versions could be bumped or move back … that should be the logic everywhere"): every reinstall path must install EXACTLY the pinned version in BOTH directions (upgrade and downgrade) — marker != pin ⇒ install pin, never an upgrade-only comparison; applies to every var, and any fix or verdict that assumed upgrade-only must be reconsidered.
- [2026-09-24 14:10] AGREED: next = a fix PLAN (no code until approved) for pass-1 A1 (pyenv/rbenv managers + ruby-build/gemset reachability), pass-1 A2 (phpbrew tools + phpbrew), and rustup-init (pin-ignored sed + unreachable gate).

## Formal Plan
<!-- written at Phase 4 — tranche 1, PROPOSED 2026-09-24, NOT yet approved -->

### Invariant (ruling 14:35)
`marker != pin` ⇒ install EXACTLY the pin, whether the pin moved up or down. A failed install never deletes
the working version and never writes a satisfied marker. Every step below is tested in BOTH directions.

### Step 5 — A2 phpbrew tools (S) · `phpbrew-bin/global-stack-phpbrew-start.sh:124-131`
- Hoist `global-stack-phpbrew-install-tools.sh` out of the phpbrew-mismatch block: it runs on every
  install-mode boot, still BEFORE `iou.sh` (iou's `composer update` needs composer). Its 12 per-tool gates
  are equality-based and skip without network (`-f` phar floors; laravel's floor is a local
  `composer global show`) [Verified: read `install-tools.sh:15-187`]. Per-boot cost: 11 `stat`s + one
  `composer global show`.
- `iou.sh` stays gated: `PHPBREW_VERSION` is locked to 2.2.0 by the vendored overlay (`iou.sh:16-19`, `.env:899`
  `lock`), so it stays NOT-HANDLED by design. Deliverable: 11 of 12 A2 pins.
- Downgrade: each tool's install replaces the file (`rm -rf` for composer, `curl -O`/`-o` overwrite for phars,
  `composer global require pkg:<ver>` for laravel) [Inferred for laravel downgrade — test it].
- Test §55 (red today — the pass-1 probe): extract the shipped install-mode block by anchor, tmpdir markers,
  stub callees; COMPOSER up, COMPOSER down, unchanged → `install-tools` invoked each time; non-vacuity guard.
  Sabotage: re-wrap the call in the mismatch condition → red.

### Step 6 — A1 pyenv / rbenv (M)
- 6a `pyenv-iou.sh:9-11`, `rbenv-iou.sh:11-13`: keep the fresh clone; add the missing branch — `.git` present
  AND installed `--version` != pin (`#v`) → `git -C ROOT fetch --tags --force --prune origin` +
  `git -C ROOT checkout --force "refs/tags/${PIN}"`. Works up and down; a missing tag dies under `set -e`
  (error token, no marker write). Marker shape at `pyenv-start.sh:127` / rbenv twin unchanged
  (`--version`, `#v`-stripped) → equals the pin after checkout.
- 6b call `rbenv-iou.sh` (and `pyenv-iou.sh`, for symmetry) on EVERY install-mode boot; the checkout guard
  inside makes the steady state network-free, and the ruby-build/gemset gates (`rbenv-iou.sh:20-38`) become
  reachable — fixes RBENV_RUBY_BUILD / RBENV_GEMSET.
- 6c fail fast BEFORE any delete: in `pyenv-start.sh:68-76` / `rbenv-start.sh:64-73`, if `_resolved` is not in
  `pyenv install --list` / `rbenv install --list-all` → error token, exit 1, message naming the manager pin
  to bump; the working interpreter stays.
- 6d delete AFTER install: move `rm -rf versions/${_old}` to after the successful install + marker write
  (`pyenv-start.sh:~156`, `rbenv-start.sh:~182`), so a failed build (network, compiler) also leaves the old
  interpreter. Old may be newer or older — same code.
- Ordering is already safe: 03python3/03ruby* wait for `successes/pyenv|rbenv`, which 02 clears at boot and
  writes after iou [Verified: `pyenv-start.sh:23,41-43,141`].
- Tests §56 (red today): stub `git` on PATH, `.git` present; pin above / below / equal to installed →
  fetch+checkout of `refs/tags/<pin>` / same / no git call; rbenv: bump RUBY_BUILD alone → plugin re-clone.
  §57 (red today): extracted runtime block; unknown definition → exit 1 + token + old dir present; failing
  install stub → old dir present; success → old dir removed afterwards. Existing anchors §22 (resolve-before-
  gate) and §29 (rbenv plugin gates) must still match AND extract non-empty after the edit.
- Certification by execution during implementation: tmp `PYENV_ROOT` really cloned at v2.8.5, shipped iou
  run with pin v2.8.6 then back to v2.8.5 → `pyenv --version` follows both ways (network; tmp dir only).

### Step 7 — rustup-init (M) · `rust-bin/global-stack-rust-iou.sh`, `global-stack-rust-start.sh:42-46`
- 7a delete the `sed` (`:25`, verified no-op); run the installer with `RUSTUP_VERSION` exported to the pin
  (the installer's own knob, `rustup-init-1.29.1.sh:98-104`).
- 7b rust-init marker != pin alone → re-run the installer over the existing install
  (`-y --no-modify-path --default-toolchain none`, toolchains kept) to replace rustup, up or down
  [Unverified — certify below].
- 7c `rustup set auto-self-update disable` after install, so no later rustup command moves it.
- 7d write the `rust-init` marker AFTER install, from `rustup --version`; != pin → error token, exit 1
  (today it is written at `:27`, before anything installs).
- 7e reachability: call `rust-iou.sh` on every boot (both of its sections already self-compare), instead of
  only on a RUST_VERSION mismatch.
- Test §58 (red today): static — no `sed -i` on `rustup.installer.sh`; behavioural — stub installer records
  env/args; rust-init up / down / equal → invoked with `RUSTUP_VERSION=<pin>` / same / not invoked.
- Certification by execution during implementation: tmp `CARGO_HOME`/`RUSTUP_HOME`, real installer, install
  1.29.1 → re-run with 1.28.2 → `rustup --version` = 1.28.2 → back to 1.29.1 (network; tmp dirs only).

### Step 8 — both-directions sweep (S) — per ruling 14:35
- Repo-wide grep: exactly ONE ordered (upgrade-only) comparison exists in any install path — host claude,
  `templates/shell/global-unu.sh:503-517` (`_gs_semver_lt`). Change it to `!=` (install the pin either way).
- go / zig / hurl extract over the previous tree (`install-go.sh:19`, `install-zig.sh:13`,
  `install-hurl.sh:17`): wipe the target before extract (GOPATH lives inside GOROOT, `.env:350-351` — move
  or preserve it first), so a downgrade cannot leave newer files behind.
- Every other gate is equality-based (`gs_version_gate`, `!=`) → already bidirectional [Verified: grep].
- Tests: static guard — no ordered comparison in install paths (discovered, `>= N` floor); behavioural
  wipe-before-extract probe for go with a tmpdir root.

### Step 9 — docs (S)
- CLAUDE.md "Managers … reinstall the manager only" and the `rbenv-iou.sh:15-19` row-21 comment. CLAUDE.md
  is classifier-blocked → handed over as a `! bash /tmp/…sh` script. Other refuted claims stay listed below
  as follow-ups (not this tranche).

### Rollback
One commit per step; `git revert <sha>`. Marker formats are unchanged, so no `tools/` migration. By
construction (6c/6d/7d) a failing boot leaves the previous version installed and writes an error token.

### Separately gated — NOT authorised by approving this plan
Live verification on the running stack: bump `PYENV_VERSION` one tag up then back on 02pyenv alone; bump
`COMPOSER_VERSION` alone; bump `RUSTUP_INIT_VERSION` down then up. Each is asked for individually.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Inventory A (254 annotated pins + aliases) and B (every consumer) | M | done | - | .env |
| 2 | Per-pin reinstall-on-bump trace + gate probes | L | done | - | docker/config/dist/bin/** |
| 3 | Findings report, graded per var | M | done | - | var/claude/** |
| 4 | Pass 2: every non-apt install site honours its pin; anything unpinned; host surface | L | done | - | var/claude/** |
| 5 | A2 phpbrew tools reachable every boot (11/12 pins) | S | todo | - | docker/config/dist/bin/phpbrew-bin/** |
| 6 | A1 pyenv/rbenv upgrade+downgrade, plugin reachability, fail-fast + delete-after-install | M | todo | - | docker/config/dist/bin/pyenv-bin/**, docker/config/dist/bin/rbenv-bin/** |
| 7 | rustup-init honours pin both ways, reachable, marker from installed binary | M | todo | - | docker/config/dist/bin/rust-bin/** |
| 8 | Both-directions sweep: host claude gate, go/zig/hurl wipe-before-extract | S | todo | - | templates/shell/global-unu.sh, docker/config/dist/bin/base-bin/** |
| 9 | Docs: manager-reinstall claim + row-21 comment | S | todo | - | CLAUDE.md, docker/config/dist/bin/rbenv-bin/** |
<!-- /progress-block -->
### Blocked
### Needs input
- Which of A1–A7 / B / C to fix, in what order (no implementation authorised yet).
- Approval of the tranche-1 Formal Plan (steps 5–9).
- env-update proposal policy: `decide.sh` rule 5 makes any DOWNWARD correction a `SKIP` (a downgrade is a
  hand-edit today). Delivery (steps 5–8) handles downgrades either way; whether env-update should also
  PROPOSE them is a separate policy call.
### Needs research
### Fragile
### Known issues
Full report (gitignored): `var/claude/pin-audit/REPORT.md`; per-pin file:line evidence in `var/claude/pin-audit/raw/G*.md`.
Result at HEAD 7b45087 — 254 pins: 168 clean (125 runtime-gated, 39 via `make down-n-rebuild*`, 4 via pull),
33 NOT-HANDLED, 26 PARTIAL, 20 EMPTY, 5 dead, 2 info-only.
- A1 pyenv/rbenv managers never upgrade (`*-iou.sh` clone only when `.git` absent) → PYENV, RBENV, RUBY_BUILD,
  GEMSET bumps are no-ops and PYTHON3/RUBY3/RUBY4 bumps past the frozen definitions delete the old interpreter
  then fail (resolver fallback verified by execution; install failure inferred).
- A2 `phpbrew-install-tools.sh` runs only on a PHPBREW mismatch → 11 tool pins + PHPBREW never applied
  (verified by execution of the shipped block).
- A3 FRANKENPHP bump: build only runs when `php.<AS>` marker absent; launch silently skipped.
- A4 4 caddy plugin pins not in the caddy gate input (live service).
- A5 5 nginx/httpd module pins ungated + MODSECURITY_LIB modules not rebuilt (UNCERTIFIED-BY-EXECUTION).
- A6 `make rebuild` does not push → 00base changes do not cascade; `make down-n-rebuild*` does (tier order verified).
- A7 SDKMAN (installer hardcodes 5.23.0), RUSTUP_INIT (gate behind RUST mismatch), registry/buildkit (manual targets);
  PARTIAL: PHP8_x gate on VERSION_NAME, FVM gate reads an unplumbed var, node raw-pin gate (latent), yarn patch,
  groovy/spark VX2 consumers lack depends_on.
- B install-quality: `Dockerfile:304-308` `|| echo` masks failures; `curl -L` without `-f` in 00base installs;
  go/zig overlay extract; phpbrew ext exit-0 (inferred).
- C escape hatches: `RELOAD_NODE24` / deleted node marker keeps pkg markers → no npm globals (verified by
  execution); `RELOAD_PHP8_x` keeps ext markers.
- PASS 2 (`var/claude/pin-audit/pass2/REPORT.md`) — install-site honours-pin + unpinned discovery:
  rustup-init PIN-IGNORED (`rust-iou.sh:25` sed matches nothing in the 1.29.1 installer — verified by
  execution; fix = export `RUSTUP_VERSION`); android launcher pinned but the real CLI floats to Google's
  latest; host claude 2.1.281 vs pin 2.1.276 (upgrade-only gate + autoUpdates); serverless `^` ranges with no
  tracked lockfile; `phpbrew-iou.sh:24` `composer update` discards phpbrew's lockfile; phpbrew pin locked to
  2.2.0 by the vendored overlay guard (`:16-19`, exit 1); `SDKMAN_NATIVE_VERSION` 0.7.34 has no pin;
  phpMyAdmin pinned to `master` = frozen at first install; awscli/rootAVD/docker-reclaim/mise `usage` float.
  Host surface `templates/shell/global-unu.sh` (~16 tools from the same pins) is delivered only by a manual
  run or `make hard-restart`; the host copy `~/.local/bin/global-unu.sh` is hand-copied, no deploy step.
  Disk→code sweep: every `tools/*` tree and `tools/bin/*` binary maps to a known site — no orphan.
- D doc claims refuted: CLAUDE.md android launcher "yields 1.0.15985488"; CLAUDE.md frankenphp gotcha, RELOAD "full unconditional reinstall", "manager-only
  reinstall"; `rbenv-iou.sh:15-19` comment; MASTER.plan.md:1487 MCP "dead"; `.env:277` MODSECURITY_LIB note.
