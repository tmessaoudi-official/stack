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
- [2026-09-24 15:05] AGREED: tranche-1 Formal Plan steps 5–9 approved (code + temp-dir tests; live bumps still asked separately).
- [2026-09-24 15:05] AGREED: host Claude Code keeps auto-update → `GLOBAL_STACK_CLAUDE_CODE_VERSION` is a CONTAINER-only pin; step 8 becomes: document that, keep the host gate upgrade-only as the single named exemption of the no-ordered-comparison guard.
- [2026-09-24 15:05] AGREED (developer: "if we need to reinstall it needs to be clean with a wipe ! no dirty reinstall !"): a reinstall must never overlay a new version on the old tree — go/zig/hurl (tranche 2) get wipe-then-install.
- [2026-09-24 14:10] AGREED: next = a fix PLAN (no code until approved) for pass-1 A1 (pyenv/rbenv managers + ruby-build/gemset reachability), pass-1 A2 (phpbrew tools + phpbrew), and rustup-init (pin-ignored sed + unreachable gate).
- [2026-09-24 23:40] AGREED: tranche 2 scope = ALL items (delete-before-install at nvm/phpbrew/sdkman/fvm/android + rbenv plugins, the floating composer bootstrap, package-slot downgrades); investigate, plan, hard stop for approval before implementing.
- [2026-09-24 23:40] AGREED: env-update decide.sh rule 5 stays — a downward upstream move is SKIP; rollbacks are a deliberate hand edit of .env, which the install side honours both ways.
- [2026-09-24 23:55] AGREED: tranche 2 approved as steps 11–17, step by step, test-first, tier asked at every gate.
- [2026-09-24 23:55] AGREED: step 14 — a go bump's staged swap moves `go/home` (GOPATH) into the new tree; GOPATH is preserved, not wiped.
- [2026-09-24 23:55] AGREED: step 16 — option (a) only: keep the clean full SDK wipe, stop wiping `GRADLE_USER_HOME`.
- [2026-09-25 09:37] SUPERSEDED (see 2026-09-25 09:58): mise's delete-before-install (`install-mise.sh:18-21`, data dirs removed before `curl https://mise.run | sh`) is logged as a known issue and fixed later, outside step 14; step 14 stays go/zig/hurl.
- [2026-09-25 09:58] AGREED: no tool is ever unpacked next to its old tree in tools/. go/zig reinstall = download to container /tmp, check the upstream-published SHA-256 and that the archive holds the binary, THEN wipe the tool dir (go's `home` GOPATH set aside and restored), unpack fresh, run the version check, marker last.
- [2026-09-25 09:58] AGREED: hurl is fixed now — a pinned 00base build stage compiles hurl ${GLOBAL_STACK_HURL_VERSION} from source (cargo --locked, pinned Rust) against Ubuntu 26.04's libxml2.so.16; install-hurl.sh copies the binary into tools/hurl (the mkcert pattern). Reason: the only upstream Linux build links libxml2.so.2, absent on 26.04, so hurl has been unrunnable in 00base.
- [2026-09-25 09:58] AGREED: mise's delete-before-install is fixed IN step 14 (supersedes 09:37): pinned mise binary from its GitHub release with its checksum (no remote script piped to sh), `mise --version` checked against the pin, then data dirs wiped, marker last.
- [2026-09-25 10:07] AGREED: go's GOPATH (`go/home`) is renamed to the sibling `tools/go.gopath-aside` for the duration of a go reinstall — the one named exception to "nothing next to the old tree"; restored on any failure, restored at the next start when GOPATH is absent, FATAL when both exist, never deleted.
- [2026-09-25 10:18] AGREED: hurl stays at `/stack/tools/hurl/bin` (host PATH unchanged) — the image only COMPILES it; boot copies it into tools/ like mkcert (confirms 09:58 after the developer asked).
- [2026-09-25 11:47] AGREED: an 00base image with NO compiled hurl (any image built before step 14c) makes install-hurl.sh WARN (naming `rebuild 00base`) and leave tools/hurl untouched instead of FATAL — the boot must not fail over an unused tool during the transition; the rebuild then repairs hurl on its own. An image whose compiled hurl does not match the pin stays FATAL.
- [2026-09-25 12:08] AGREED: step 15 covers ALL 11 tools in `phpbrew-install-tools.sh`, not only the composer bootstrap: temp-dir download with `curl -f`, upstream checksum where published, the tool's own version check against the pin, THEN replace, marker last; pinned release assets replace the piped mago/castor installers; composer builds in a temp dir with a pinned, SHA-384-checked bootstrap before the old one is wiped.
- [2026-09-26 11:17] AGREED: tranche 3 — fix ALL reinstall sites the tranche-2 milestone panel found outside the ruled list (fvm's /stack/projects extract+delete, deno and bun incl. bun's piped installer, caddy, httpd, nginx, phpmyadmin, rust, php.edge) now, same shape as tranche 2; one milestone panel over tranches 2+3.
- [2026-09-26 11:43] AGREED: tranche 3 plan (steps 18-27) approved as drafted; every enabled web server rebuilds on its first boot after the commit.
- [2026-09-26 11:43] AGREED: prefix-baked sites (httpd, nginx, php.edge, rust, shared ModSecurity) use policy B — every input fetched and checked before the wipe, build at the final path, check the build, FATAL + error token on a build failure.
- [2026-09-26 11:43] AGREED: caddy is built locally with xcaddy (new pin GLOBAL_STACK_XCADDY_VERSION, checksum-verified); add-package is dropped.
- [2026-09-26 11:43] AGREED: phpMyAdmin and the ModSecurity-apache connector are SHA-tracked (use-sha annotations, the php.edge shape; phpMyAdmin TYPE=commit).
- [2026-09-26 15:52] AGREED: the shared ModSecurity build drops `--with-lua` (no image installs a Lua dev package, no config uses Lua; configure then auto-detects and builds without it) — step 23a; it also needs `submodule update --init --recursive` (Mbed TLS's nested submodules), both measured in the 01caddy image.

## Formal Plan
<!-- written at Phase 4 — tranche 1, APPROVED 2026-09-24 15:05 (steps 5-9; step 8 revised) -->

### Invariant (ruling 14:35) — target, and what this tranche delivers
Target, everywhere: `marker != pin` ⇒ install EXACTLY the pin, up or down; a failed install never deletes
the working version and never writes a satisfied marker. **This tranche brings pyenv, rbenv, the phpbrew tools,
rustup and the host claude gate into compliance.** The same delete-before-install shape still exists at
`nvm-start.sh:72`, `phpbrew-start.sh:62`, `sdkman-start.sh:78`, `fvm-start.sh:28,43`, `android-start.sh:169`
(the row-42 nvm nightly-404 incident is this class) — tranche 2, listed under Known issues. Every step below
is tested in BOTH directions.

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
- 6c fail fast at the resolver: `find-latest.sh` (pyenv `:14-16`, rbenv twin) falls back to the RAW pin when
  the version is neither installed nor listed — that fallback is the defect. Make it print nothing and exit 1;
  the caller (`pyenv-start.sh:66` / `rbenv-start.sh:63`) dies under `set -e` → error token, message naming the
  manager pin to bump, nothing touched. §22 stubs find-latest and does not assert the fallback [Verified:
  read §22] → unaffected.
- 6d on `reinstall`, touch NOTHING until the install succeeds: today `pyenv-start.sh:69-75` / `rbenv-start.sh:65-72`
  delete the old dir, the `pkg.*` markers and the runtime marker before building. New order: decide → install
  the pin → then delete old dir, wipe `pkg.*`, write the marker (`pyenv-start.sh:~156`, `rbenv-start.sh:~182`).
  A failed build leaves old interpreter + old marker + old pkg markers, so the next boot retries `reinstall`
  (not `install` — which would be the C1 no-packages shape). Old may be newer or older — same code.
- Ordering is already safe: 03python3/03ruby* wait for `successes/pyenv|rbenv`, which 02 clears at boot and
  writes after iou [Verified: `pyenv-start.sh:23,41-43,141`].
- Tests §56 (red today): stub `git` on PATH, `.git` present; pin above / below / equal to installed →
  fetch+checkout of `refs/tags/<pin>` / same / no git call; rbenv: bump RUBY_BUILD alone → plugin re-clone.
  §57 (red today): extracted runtime block; unknown definition → exit 1 + token + old dir present; failing
  install stub → old dir present; success → old dir removed afterwards. Existing anchors §22 (resolve-before-
  gate) and §29 (rbenv plugin gates) must still match AND extract non-empty after the edit.
- Certification by execution during implementation: tmp `PYENV_ROOT` really cloned at v2.8.5, shipped iou
  run with pin v2.8.6 then back to v2.8.5 → `pyenv --version` follows both ways (network; tmp dir only).
- AS BUILT (2026-09-24): three deviations, each for a measured reason.
  (1) 6a decides by commit, not `--version`: `rev-parse -q --verify refs/tags/<pin>^{commit}` vs `HEAD` — local,
  exact, direction-free; fetch only when they differ or the tag is unknown locally.
  (2) §56 uses a REAL local upstream repo (two annotated tags), not a `git` stub — a stub would model the
  script's belief about git. The iou gets a real `.git`, and 56h points `origin` at a nonexistent path to prove
  the steady state does not fetch.
  (3) 6d's cleanup also refuses (`exit 1`, EXIT trap writes the token) when `versions/<resolved>` is absent:
  `source <shellrc> && <install>` does not trip `set -e` when `source` fails (non-final `&&` member), so
  install success is PROVEN on disk, not inferred from reaching the line (§57h, red first).
  §22's extraction now ends on the gate's own `  fi` (its old anchor, the in-block `rm -f marker`, moved).
  Certified by execution against github.com (scratch dirs only): pyenv v2.8.5→v2.8.6→v2.8.5 and rbenv
  v1.3.1→v1.3.2→v1.3.1 through the shipped iou; `--version` equals the pin each time; ignored `versions/` +
  `plugins/` survive (`git status` clean with both present); pin current with origin unreachable → rc 0, no fetch.
  NOT certified by execution: a real python/ruby compile on reinstall (the install + cleanup order is
  asserted statically and the cleanup behaviourally, never with a real `pyenv install`).

### Step 7 — rustup-init (M) · `rust-bin/global-stack-rust-iou.sh`, `global-stack-rust-start.sh:42-46`
- 7a delete the `sed` (`:25`, verified no-op); run the installer with `RUSTUP_VERSION` exported to the pin
  (the installer's own knob, `rustup-init-1.29.1.sh:98-104`).
- 7b rust-init marker != pin (alone or with RUST) → run the installer ONCE over the existing install
  (`-y --no-modify-path --default-toolchain none`, toolchains kept) to replace rustup, up or down
  [Unverified — the one unobserved assumption of this plan; certify below]. The RUST section (`:30-36`)
  then uses `rustup toolchain install ${RUST} && rustup default ${RUST}` instead of re-running the installer,
  so a first boot runs the installer exactly once (the test asserts one invocation).
- 7c `rustup set auto-self-update disable` after install, so no later rustup command moves it.
- 7d write the `rust-init` marker AFTER install, from `rustup --version | awk '{print $2}'` (output shape
  `rustup 1.29.1 (d95a37b6a 2026-08-13)` [Verified: ran it]); != pin → error token, exit 1 (today it is written
  at `:27`, before anything installs).
- 7e reachability: call `rust-iou.sh` on every boot (both of its sections already self-compare), instead of
  only on a RUST_VERSION mismatch.
- Test §58 (red today): static — no `sed -i` on `rustup.installer.sh`; behavioural — stub installer records
  env/args; rust-init up / down / equal → invoked with `RUSTUP_VERSION=<pin>` / same / not invoked.
- Certification by execution during implementation: tmp `CARGO_HOME`/`RUSTUP_HOME`, real installer, install
  1.29.1 → re-run with 1.28.2 → `rustup --version` = 1.28.2 → back to 1.29.1 (network; tmp dirs only).
- AS BUILT (2026-09-24). The 7b assumption was probed BEFORE §58 was written and is now [Verified]: both the
  1.28.2 and 1.29.1 `rustup-init.sh` honour `RUSTUP_VERSION`; re-running replaces rustup 1.29.1 → 1.28.2 →
  1.29.1; an installed toolchain (rustc 1.98.1) survives; `settings.toml` (auto-self-update) survives.
  NEW measured fact that makes 7c load-bearing: with auto-self-update at its default, `rustup toolchain
  install` self-updated rustup 1.28.2 → 1.29.1 ("info: downloading self-update") — past the pin with no
  `.env` change. So the disable runs on EVERY boot before any toolchain command (also fixes live installs
  made before this change, whose setting is still `enable`), and §58's stub rustup models that self-update.
  Deviations: `--profile default` kept and `--no-modify-path` NOT added (the old call modified the path;
  unchanged behaviour); the gate is `gs_version_gate` on `rust-init` plus a `-x ${CARGO_HOME}/bin/rustup`
  floor. A RUST change still wipes both homes first (clean reinstall, per the 14:35 ruling).
  Certified by execution (scratch homes, real installers, SHIPPED rust-iou.sh, auto-self-update pre-set to
  `enable` to model a live install): pin 1.29.1 → 1.28.2 → 1.28.2 → 1.29.1 gives rustup 1.29.1 / 1.28.2 /
  1.28.2 / 1.29.1, marker equal each time, setting `disable`, rustc 1.98.1 kept, the unchanged boot made no
  download, no error token. NOT certified by execution: a real `rustup toolchain install` of a NEW RUST pin
  through the shipped script (the toolchain was pre-installed; the path is covered by §58g's stub only).
- 6C follow-up (advisor, folded into step 8's commit): the gate read only the marker, which the OLD code wrote
  from the PIN before installing — intent, not the binary. It now also compares `rustup --version` (none when
  `${CARGO_HOME}/bin/rustup` is not executable): marker current + binary stale → reinstall (§58k, red first).
  Live read-only check 2026-09-24: `tools/cargo/bin/rustup` = 1.29.1 = marker (latent, not live);
  `tools/rustup/settings.toml` has no auto_self_update key (= default enable) — the every-boot disable fixes it.
  `tools/bin/rustup.installer.sh` on the live tree is the OLD sed-patched download; harmless (re-fetched
  before every use) — it is not what ships.

### Step 8 — host claude: container-only pin (S) — REVISED by ruling 15:05 (keep auto-update)
- AS BUILT (2026-09-24): `.env` note above the claude `@todo` annotation (annotation still adjacent; env-update
  `--check --dry-run --filter` still parses the record) and a comment at `global-unu.sh` `_gs_semver_lt`.
  §59 = the no-ordered-comparison guard over `dist/bin`, `docker/images`, `templates/shell` (`*.sh`,
  `Dockerfile*`, comment lines stripped). Inventory taken first: exactly TWO ordered sites exist — the host
  claude gate and 00base sonar-scanner `-ge 6`, which picks the archive NAME by major (6+ has an arch suffix),
  not whether to install — so both are exempt by name, and they are the non-vacuity floor (59a).
  Step 9 widened the pattern to a string `<`/`>` inside `[[ ]]` (the inventory's fourth shape; zero hits,
  sabotage `[[ "${NODE_VERSION:-}" < "v1" ]]` in nvm-start reds 59b naming `nvm-start.sh:7`).
  Row 8's sha: a commit cannot carry its own sha (an amend changes it — `9157a89` was recorded and is
  dangling); row N's sha lands in step N+1's commit.
- Keep the host gate upgrade-only; comment it and `.env`'s annotation as "container pin; host follows
  Claude Code auto-update". The no-ordered-comparison guard exempts exactly this one site by name.
- (original text below, superseded)
- Repo-wide grep: exactly ONE ordered (upgrade-only) comparison exists in any install path — host claude,
  `templates/shell/global-unu.sh:503-517` (`_gs_semver_lt`). Change it to `!=` (install the pin either way).
  Every other gate is equality-based (`gs_version_gate`, `!=`) → already bidirectional [Verified: grep].
- Holding the pin on the host ALSO needs Claude Code's own `autoUpdates` off (`~/.claude/settings.json` —
  classifier-blocked → handed to you as a command); otherwise the gate installs the pin and the app moves it
  again afterwards. Your call (Needs input).
- Test: static guard — no ordered comparison in install paths (discovered, non-vacuity floor).
- go / zig / hurl overlay extract is NOT in this tranche — it carries a design fork (Needs input).

### Step 9 — docs (S)
- CLAUDE.md "Managers … reinstall the manager only", AND the startup-prologue suite's "~19 s" run time
  (measured 161 s at load 22-24 on 2026-09-24 — the number is load-dependent, yet CLAUDE.md uses it as the
  tell that `--section` did not filter). (The `rbenv-iou.sh` row-21 comment was corrected in step
  6, 3af3d55.) CLAUDE.md is classifier-blocked → handed over as a `! bash /tmp/…sh` script. Other refuted claims stay listed below
  as follow-ups (not this tranche).

### Rollback
One commit per step; `git revert <sha>`. Marker formats are unchanged, so no `tools/` migration. By
construction (6c/6d/7d) a failing boot leaves the previous version installed and writes an error token.

### Separately gated — NOT authorised by approving this plan
Live verification on the running stack: bump `PYENV_VERSION` one tag up then back on 02pyenv alone; bump
`COMPOSER_VERSION` alone; bump `RUSTUP_INIT_VERSION` down then up. Each is asked for individually.

## Formal Plan — tranche 2 (APPROVED 2026-09-24 23:55)
Principle, from rulings 14:35 + 15:05: a reinstall installs exactly the pin in either direction, never
overlays the old tree, and never deletes the working version until the new one is PROVEN on disk.
Tranche 1's §57 shape is the template: the gate only decides; the install trigger also fires on
`reinstall`; after the install, prove the new version exists (else FATAL — the EXIT trap writes the token),
then drop the old dir and wipe `pkg.*`; the marker is written where it is today (last).

### Step 11 — runtimes: nvm node, phpbrew php, sdkman java, fvm flutter (M)
- Gates today delete first: `nvm-start.sh:68-76`, `phpbrew-start.sh:58-66`, `sdkman-start.sh:72-80`,
  `fvm-start.sh:54-61` [Verified: read]. Install sites: nvm `:121` (`gs_install_retry_purge … nvm install`),
  php `:144`, java `:162`, flutter `:95`; triggers `! -f marker` at nvm `:116,140`, php `:142,164,171`,
  flutter `:93`, java (to read) [Verified: grep]. All four keep versions SIDE BY SIDE (`versions/node/<v>`,
  `php/<name>`, `candidates/java/<v>`, `fvm versions/<v>`), so install-new-then-drop-old is possible.
- `php.edge` is the one EXCEPTION and stays wipe-then-build: it always installs to `php-master`, and phpbrew
  bakes that prefix into the built binaries (`php-config --prefix`), so it cannot be built beside itself
  [Inferred from how phpbrew configures `--prefix`; not probed]. Documented at the site.
- `RELOAD_*=true` paths are untouched. Correction (advisor 3C, step 11): only php `:43` and fvm `:28`
  (`RELOAD_FVM`) actually wipe a runtime dir; `RELOAD_NODE` (nvm `:46`), `RELOAD_JAVA` (`:60`) and
  `RELOAD_FLUTTER` (fvm `:43`) remove markers only, so the gate returns `install`, not `reinstall`, and
  `nvm install` / `sdk install` / `fvm install` no-op on the existing dir — see Known issues. `sdkman-start.sh:162` is `source <rc> && sdk install java …` (the `source && cmd` class) —
  the on-disk proof before cleanup covers it; named at the site. `gs_install_retry_purge` returns the second
  attempt's status, so a double failure aborts under `set -e` before the cleanup [Verified: read
  `base-prologue.sh`]. nvm's raw-pin gate (§22f) is left as it is — only its delete lines move.
- Marker CONTENT readers: alltogether/phpmyadmin/serverless/android build PATH from `php.<AS>`/node markers
  [Verified: grep]; they wait for the runtime's success marker, written after the final marker write, so they
  read the NEW value. Within each start script, any read of the marker between gate and final write is
  checked during implementation (pyenv `:159` had that shape).
- Test §60 (red first), per runtime: gate on a reinstall leaves old dir + pkg markers + marker; the cleanup
  block drops old / keeps new when the new dir exists and refuses (non-zero, old kept) when it does not;
  install < cleanup < package loop (static order); every `! -f marker` trigger also fires on reinstall.

- AS BUILT (step 11): the four gates decide only (`_<rt>_old=""`, set on reinstall). nvm `:116,:140`,
  php `:143,:182,:189` and fvm `:93` triggers gained `|| gate == reinstall`. A cleanup block after each
  install proves the new binary with `-x` (`versions/node/$(nvm version)/bin/node`, `php/<name>/bin/php`,
  `candidates/java/<v>/bin/java`, `fvm/cache/versions/<v>/bin/flutter`), then drops the old dir unless
  `gs_version_in_use` (new, in `base-version-gate.sh`, stdout `shared|free`, always returns 0) finds
  another label recording it, then wipes pkg.* (not fvm: no package loop). php also drops the old php's
  `build/` dir and every `frankenphp-*-<old name>` binary (clean-wipe ruling; the glob covers a frankenphp pin
  bumped in the same boot — 60i). A boot that fails AFTER the cleanup (e.g. in `nvm use`) keeps the old marker, so
  the next boot re-enters `reinstall`, the installer no-ops, `-x` passes, the old-dir `rm` is a no-op and pkg.*
  re-wipes: the retry converges [Inferred from the code path; not executed].
  Proof paths `bin/node`, `bin/php`, `bin/java`, `bin/flutter` exist and are executable on the live tree
  [Verified: `[ -x ]` builtin, not rtk `ls`]. Certifying run: 719/719 at `902f08f`, sabotage S1–S8. §60: 34 checks; sabotage
  S1–S7 each caught, each restored byte-identical. 6C sweep: the only marker-CONTENT readers in dist/bin are
  the four consumers above (`git grep` for `cat`/`<` of a runtime marker: 11 hits, 4 files) — none inside a runtime
  script or its sub-scripts, so keeping the old marker until the final write changes no read. 60j (nvm resolves via `nvm version`) is a STATIC check —
  no behavioural test of a partial node pin.

### Step 12 — package slots: cleanup of the OLD version only after the NEW installed (S)
- `base-setup-packages.sh:112-117` evals `--cleanup-command` (gem uninstall / sdk uninstall of the old
  version) BEFORE the install commands `:122-133` [Verified: read]. Move it into the success branch
  (`:139-144`): non-tolerant callers after the commands; tolerant callers only when `_cmd_ok=1` and the
  `--success-check` passes — then the marker. A failed install keeps the old gem/candidate.
- Test §61 (red first): stub commands; success → order `install` then `cleanup:<old>` then marker = new;
  failed install (non-tolerant aborts / tolerant `_cmd_ok=0`) → no cleanup, marker still old; a pin moved
  DOWN (marker 2.0, pin 1.0) → install 1.0 then cleanup 2.0.
- sdkman does NOT refuse: the vendored `sdk uninstall` deselects (unlinks the per-home `current`) and removes
  (`conf/sdkman/src/sdkman-uninstall.sh:33-45`), and `sdk install` under `sdkman_auto_answer=true` has already
  linked the new version as current (`sdkman-install.sh:39-47`, link written at `sdkman-path-helpers.sh:88`)
  [Verified: read]. No `sdk default` step needed.
- Certification: real `pip install pkg==<lower>` and `npm add -g pkg@<lower>` downgrades in scratch dirs
  (the two slot commands with no cleanup) [Unverified until run]; `sdk uninstall` of the version that was
  the default before the new install — probed with a real sdkman in a scratch `SDKMAN_DIR` if the download
  is reasonable, otherwise named UNCERTIFIED.

- AS BUILT (step 12): `PACKAGE_OLD_VERSION` is captured on reinstall before the commands and reset per slot;
  the cleanup eval moved into the success branch (`_pkg_ok`: non-tolerant = reached; tolerant = `_cmd_ok` and
  `--success-check`), right before the marker write. rubygems keeps an executable another installed version
  provides (`Uninstaller#remove_executables`, both ruby 3.4.10 and 4.0.7 on the volume) [Verified: read], so
  `gem uninstall -x` after the install cannot drop the new version's stub. §61: 8 checks (61g green before and
  after — it pins first-install; 61h red before only on order, it pins the per-slot reset). Sabotage T1–T4
  each caught, restored byte-identical. Suite 727/727. Real downgrades in scratch: `pip install six==1.16.0`
  over 1.17.0 → 1.16.0, one dist-info; `npm add -g --force is-number@6.0.0` over 7.0.0 → 6.0.0 [Verified].
  gem, in the shipped order: `rake` 13.2.1, then install 13.1.0, then `gem uninstall rake -v 13.2.1 -x -I` →
  stub kept, `rake --version` 13.1.0, only 13.1.0 listed [Verified: ran `gem` directly, not through the
  engine or `rbenv init`; the kept stub means `rbenv rehash` keeps its shim — Inferred]. sdkman's
  deselect-not-refuse is [Verified: read] only; no `sdk uninstall` ran. Step 11's "S1–S8" means S1–S7 plus the frankenphp glob revert.

### Step 13 — rbenv plugins: reuse step 6's in-place move (S)
- `rbenv-iou.sh` ruby-build/gemset arms `rm -rf plugins/<p>` then `git clone` [Verified: read]. The plugins
  are git clones at tags — the same object as rbenv itself — so they get step 6's certified block: `.git`
  absent → clone; present → `rev-parse HEAD` vs `refs/tags/<pin>^{commit}`, fetch + `checkout --force` only
  when they differ. No `.new` state, no second shape. (advisor 3C round 1)
- Test §62 on §56's real-git fixture, plugin arms: pin up / down → at the tag; current → no fetch; unknown
  tag → fails, plugin dir intact.

- AS BUILT (step 13): one helper, `_rbenv_plugin_follow_pin`, serves both arms; rbenv's own block (step 6)
  is untouched, so §29b's structural anchor still reads it. The gate lines are byte-identical (§29f
  extracts them) and still print the WARN; the trigger is now `gate != skip || ! -d plugins/<p>/.git`, and
  the marker is written after the move. Deviation from the plan text (advisor 3C): a plugin dir that is not
  a clone is never removed — `git clone` fills an empty one and fails loud on a non-empty one, files kept
  [Verified: probe, rc 128]. §62 (18 checks) drives the whole iou with github.com redirected by
  `GIT_CONFIG_COUNT` insteadOf to a mirror of §56's fixture or to a dead path; red first on d/e/f/h/i/j for
  the stated reason (the old arm printed `128 nogit`: deleted, then the clone failed). Sabotage S1
  delete-then-reclone (10 red), S2 marker before the move (62h/62i ruby-build), S3 always fetch (62f ×2),
  each restored byte-identical. Suite 745/745. Live `tools/` plugins are clones at their pins with markers
  equal to `.env.local`, so the next boot is `skip` [Verified: read].

### Step 14 — go / zig / mise / hurl: check first, then wipe and install fresh (L) — REVISED by rulings 2026-09-25 09:58
- Today go/zig/hurl extract OVER their tree (`install-go.sh:19`, `install-zig.sh:13`, `install-hurl.sh:17`) and mise
  wipes its data dirs BEFORE `curl https://mise.run | sh` (`install-mise.sh:18-21`) [Verified: read]. Nothing is
  ever unpacked next to its old tree (ruling 09:58). Three commits:
- **14a go/zig.** Download into a container `mktemp -d`; check the SHA-256 against upstream (go:
  `dl.google.com/go/<archive>.sha256`; zig: `index.json` `.<v>."x86_64-linux".shasum`), building the
  `<hash>  <file>` line ourselves; check the archive lists `go/bin/go` / `zig-x86_64-linux-<v>/zig`. Any failure →
  FATAL, old tool and marker untouched. Then wipe the tool dir, unpack fresh, chmod/chown the fresh tree, and
  check the version as the developer user (go: `^go version go<pin> ` WITH the trailing space; zig: exact).
  Marker last. **The one named exception to "nothing next to the old tree": go's GOPATH (`go/home`, 1.9 GB) is
  renamed to the sibling `${GOROOT}.gopath-aside` before the wipe and renamed back after the chown** — a
  same-filesystem rename is the only instant move, and it is user data, not an unpacked version. An EXIT trap
  restores it on any failure; at the next start a leftover aside is restored when GOPATH is absent, is FATAL
  when both exist, and is never deleted.
- **14b mise.** The pinned release binary `mise-<v>-linux-x64` + the release's `SHASUMS256.txt` replace the piped
  installer; `--version` (printed WITHOUT the leading `v` — probe the real output first) checked against the
  pin before anything is touched; then the data dirs are wiped, the binary placed at `MISE_INSTALL_PATH`,
  `mise use -g usage` run, marker last. (`usage` itself stays unpinned — pass-2 float, unchanged.)
- **14c hurl.** hurl's only Linux build links `libxml2.so.2`, absent on Ubuntu 26.04 (`.so.16`), so hurl has
  been unrunnable in 00base [Verified: ldd]. A `hurl-build` stage on the same pinned Ubuntu tag installs hurl's
  documented build deps (apt, build stage only), `rustup-init` at `GLOBAL_STACK_RUSTUP_INIT_VERSION` after its
  checksum, toolchain `GLOBAL_STACK_RUST_VERSION` (hurl MSRV 1.95.0), then `cargo install --locked hurl --version
  <pin> --root /opt/hurl`; the main stage copies `/opt/hurl/bin`. `install-hurl.sh` checks the image's
  `hurl --version` names the pin (else the image is stale → FATAL), wipes `tools/hurl`, copies hurl + hurlfmt,
  checks again, marker last. Man pages/completions are dropped (cargo does not ship them). Compose build args
  gain the two Rust pins; `make check-image-versions` must stay clean.
- Tests: §63 go/zig, §64 mise, §65 hurl — stub `curl`/`sudo`, red first with the old code's failure named;
  sabotage per section. Execution: real go/zig/mise downloads up then down in a throwaway 00base container
  with a scratch `tools/`; a real build of the hurl stage plus `ldd` + `hurl --version` in the result. The live
  `tools/` and running stack are never touched. Composer's test moves to §66.
- AS BUILT (14a): go/zig download into `mktemp -d`, check the upstream SHA-256 (`<hash>  <file>` built by the
  script) and the archive listing (`grep -x … >/dev/null`, never `-q`: an early exit SIGPIPEs tar under
  pipefail), then wipe + unpack fresh; chmod/chown BEFORE GOPATH returns (the old `chmod -R a+rwx` rewrote
  every GOPATH file to 0777); version check (go `go version go<pin> ` with the space, zig exact), marker last.
  go's EXIT trap restores the aside. §63: 22 checks, 13 red first for the stated reason (old tree left
  behind, bad checksum installed, `1.4.00` accepted, aside ignored, GOPATH 600 → 777). Sabotage S1–S9 each
  caught and restored byte-identical — S6 (drop the both-exist FATAL) first SURVIVED, because on a reinstall
  pin `mv -T` refuses the non-empty aside anyway; 63j2 (current pin, where nothing moves) now catches it.
  §62b2 cold start rides along. Suite 768/768. Real downloads in a throwaway 00base container with a scratch
  `tools/`: go 1.27.0 → 1.27.1 → 1.27.0 and zig 0.15.2 → 0.16.0 → 0.15.2, stale file gone every time,
  GOPATH file kept at 600, no aside or temp dir left [Verified: ran].
- AS BUILT (14a follow-up): a killed reinstall's next boot meets the aside AND an EMPTY GOPATH, because
  `base-start.sh:13` runs `create-directories.sh` (which mkdirs GOPATH) before `:31` install-go. An empty GOPATH
  is now dropped (emptiness tested first — a bare `rmdir` would abort under `set -e` before the FATAL could say
  why) and the aside restored; FATAL only when GOPATH has content. 63j3 red first; SA1 (no drop) caught, SA2
  (drop without the emptiness test) first SURVIVED — rc and dirs are identical, only the message is lost — so
  63j2 now also requires the FATAL text. Commit `84cd38f`.
- AS BUILT (14b): the pinned `mise-<v>-linux-x64` + `SHASUMS256.txt` (assets named `./<asset>`, so the check
  runs inside the temp dir) replace `curl https://mise.run | sh`; the checksum and `--version` (printed WITHOUT
  the `v`, matched as `<v> ` with the space) are checked BEFORE the wipe, and that pre-wipe `--version` runs
  with every `MISE_*_DIR` in the temp dir — `--version` migrates whatever data dir it is given [Verified: the
  `migrate` WARN in the probe]. Then wipe, `install -m 0755` (removes and copies in one step, nothing next to
  the old binary), installed copy re-checked, `mise use -g usage`, marker last. `usage` is the one step still
  reaching the network after the wipe; its failure stays FATAL because a mise without `usage` is broken and a
  marker would lie — the next boot retries (64h). §64: 11 checks, 9 red first (the old code wiped the data and
  then failed on the piped installer: `data=none` on every pin, even a bad one). Sabotage M1–M5 each caught,
  restored byte-identical. Suite 780/780. Real downloads in a throwaway 00base container: v2026.9.10 →
  v2026.9.11 → v2026.9.10, stale data gone each time, real `usage` installed, current pin untouched, no temp
  dir left [Verified: ran].
- AS BUILT (14c): 00base gains a `hurl-build` stage (same pinned Ubuntu; hurl's documented apt build deps;
  archived `rustup-init` at `GLOBAL_STACK_RUSTUP_INIT_VERSION` checked against its `*./rustup-init` SHA-256;
  toolchain `GLOBAL_STACK_RUST_VERSION`; `cargo install --locked --root /opt/hurl hurl@<pin> hurlfmt@<pin>` —
  two crates, checked on crates.io; the stage re-checks `hurl --version`). `COPY --from` and
  `ENV GLOBAL_STACK_HURL_BUILD_PATH` sit AFTER the big RUN so neither invalidates the base layer; compose
  build args gain the two Rust pins. install-hurl.sh downloads nothing: it checks the image's hurl names the
  pin (else FATAL), wipes `tools/hurl`, installs hurl + hurlfmt, re-checks, marker last. An installed hurl
  that cannot run is a reinstall trigger (the live copy is exactly that, marker == pin). An image with NO
  compiled hurl (built before 14c) WARNs and leaves tools/ alone (ruling 11:47) — sync-bin ships this script
  on the next boot while the image changes only on a rebuild. `templates/shell/.profile` now puts
  `HURLPATH/bin`, not `HURLPATH`, on PATH (65m). §65: 13 checks, red first; 65h/65i were first red for a
  test-side reason (PATH lacked tools/hurl/bin; the no-download check sat after a no-op) and were fixed
  before the red set was counted. Sabotage H1–H6 each caught, restored byte-identical. Suite 793/793;
  `compose config -q` clean; `check-image-versions` clean; hadolint +1 DL3026 (the new FROM, same notice as
  the existing one). REAL: the stage compiled (386 s); in the real 00base image the binary has 0 missing
  libs, repaired a copy of the live broken tools/hurl (completions/ and man/ gone), ran a request file,
  hurlfmt works, the second boot is a no-op; the pre-14c image path WARNs with rc 0; the same binary runs on
  the host (Ubuntu 26.04) [Verified: ran]. Step 14 commits: 14a `5360b17`, follow-up `84cd38f`, 14b
  `008b841`, 14c `8bae406`.

### Step 15 — all 11 phpbrew tools: check first, then replace (L) — REVISED by ruling 2026-09-25 (scope)
- `phpbrew-install-tools.sh` [Verified: read]: composer `rm -rf`s its source + phar BEFORE cloning and bootstraps
  with an UNPINNED `composer-setup.php`; fabpot `curl -LsS -o <installed binary>` without `-f` (a 404 overwrites
  the working binary with HTML, marker written); deployer/symfony `curl -LO` without `-f`; mago/castor pipe a
  remote installer into `bash`; zephir/phalcon/pickle/pie download with `-f` then `mv` (safe, unchecked).
- Measured facts [Verified 2026-09-25]: checksums published for composer (`getcomposer.org/download/<v>/
  composer.phar.sha256sum`), symfony-cli and fabpot (`checksums.txt`, `<sha>  <name>`); none for the rest.
  Version lines: `Composer version <v> `, `Laravel Installer <v>`, `Deployer <v>`, `Symfony CLI version <v> `,
  `(PIE) <v>`, `mago <v>`, `castor v<v>`, `Local PHP Security Checker <v>,`. zephir/phalcon/pickle CANNOT run
  under the 02phpbrew system php 8.5.4 (no mbstring etc.; the phpbrew-built php does not exist yet on a first
  install), so their check is PHP's own Phar open (signature-verified; rejects a truncated file and an HTML 404
  page — both measured). mago: tarball `mago-<v>-x86_64-unknown-linux-gnu/mago`; castor: static
  `castor.linux-amd64`. The prologue owns EXIT/ERR/SIGPIPE traps: no own EXIT trap, no `grep -q` in pipes.
- Shape (every tool): download into one `mktemp -d` with `curl -f`; checksum where published; version check
  where runnable (the version must be followed by a non-[0-9.] char), else the Phar open; THEN replace
  (`install -m 0755`), marker last. composer: pinned `composer.phar` + its sha256 replaces composer-setup.php;
  the source clone, overlay rsync and `composer install` happen in the temp dir and are version-checked
  BEFORE the old source/phar are removed. laravel: unchanged install, version-checked before the marker.
- Commits: 15a composer + laravel (§66), 15b the five phars (§67), 15c symfony/mago/castor/fabpot (§68).
  Each red first, sabotage, real downloads in a throwaway 02phpbrew container with a scratch tools/.
- AS BUILT (15a): one `mktemp -d` for the whole script (`_pt_dl`, removed on the last line; a FATAL leaves it
  in container /tmp, since the prologue owns EXIT) and two helpers: `_pt_names <output> <prefix> <version>`
  (the version must not continue with a digit or a dot) and `_pt_fatal`. composer: the pinned `composer.phar`
  and its `.sha256sum` downloaded, checksum and `--version` checked; the tag cloned into the temp dir, the
  overlay rsynced, `composer install`ed with the checked phar, the built source's `--version` checked; only
  THEN `rm -rf` the old source + phar, `mv -T` the source in, `install -m 0755` the phar. `COMPOSER_HOME/vendor`
  (laravel) and the cache are never touched. Every fallible step (both downloads, the clone, the install, the
  two version checks) sits inside an `if` with a named FATAL: a bare failure reaches the prologue's generic
  handler first (measured: the unwrapped download exited 22 with no reason given). laravel: the exact
  require line is unchanged; `vendor/bin/laravel --version` must name the pin before the marker. The stray
  tab on the old clone line is gone. §66: 15 checks after `5ee3cee` (14 at `a40d2e7`; a fixture repo with six tags via `insteadOf`, stub
  curl/php/sudo), 10 red first with the old code's reasons (`composer-setup.php` reached, source wiped before
  a clone that then failed, `1.4.00` accepted for laravel). 66i first went red on the new code's own COMMENT
  naming composer-setup.php; comment lines are now stripped (the §19 shape). Sabotage S1-S7 each caught and
  restored byte-identical. S4 as first written was not a valid mutation (its `\` continuation made every
  laravel check fail) and was redone; S6 (drop the built-source version check) first SURVIVED, so the fixture
  gained tag 1.7.0 whose source reports 1.7.1. Suite 807/807. REAL, in a throwaway 02phpbrew container with a
  scratch tools/: fresh 2.10.2 + laravel v5.31.0 → 2.10.3 + v5.32.0 → bad pin 2.99.99 (named FATAL; old
  source/phar/markers and a planted sentinel untouched) → no-op → 2.10.2 + v5.31.0. Source, phar and laravel
  report the pin every time, the overlay file matches, a planted stale file is gone after each reinstall, no
  temp dir left on success [Verified: ran]. zephir … fabpot are untouched in 15a (15b/15c).
- AS BUILT (15a follow-up, found at 6C): the script now `cd`s into its temp dir. The later blocks
  download with `curl -O` into the cwd and run `rm -rf zephir.pha*` (phalcon/pickle/pie likewise) there on
  EVERY boot; the cwd is compose's `working_dir` `/stack/projects` [Verified: `compose config` →
  `working_dir=/stack/projects`], so a developer file matching the glob was deleted. The old composer block's
  bare `cd` into its source moved that onto composer's tree on reinstall boots; `a40d2e7` (subshell `cd` only)
  left every boot in the projects dir. 66j (a projects-like cwd holding `zephir.phar-notes`, composer
  reinstall + zephir bump) was red first for that reason (`proj=[]`); S8 (drop the `cd`) caught and restored.
  Suite 808/808. REAL: `-w /stack/projects` over a scratch projects dir with the planted file, composer
  2.10.2 → 2.10.3 plus a real zephir 1.4.0 download (3.3 MB phar installed, marker 1.4.0); the planted file
  survived, nothing was added, no temp dir left [Verified: ran]. The `cd` is safe for the two blocks that pipe
  an installer (read to a file, never piped): mago's `$(pwd)` fallback is dead behind `--install-dir`
  (`mago.sh:229`) and castor refuses rather than falling back to `.` once `--install-dir` is given
  (`install:277-285`); both stage under /tmp. Step 15a commits: `a40d2e7` + `5ee3cee`.
- AS BUILT (15b): three helpers. `_pt_phar <tool> <url>` downloads with `curl -f` to
  `${_pt_dl}/<tool>.phar` and opens it with `new Phar()` (signature-verified: `phar.require_hash=1` in the
  image; a truncated file, an HTML page, a one-byte corruption and a copy without the `.phar` name were each
  refused, and all five pinned phars accepted [Verified: probe in the 02phpbrew image]; `require_hash` is PHP's
  default and nothing in the repo sets it, and install-tools resolves the system php, since its PATH adds no
  php [Verified: `git grep`; Inferred from `phpbrew-start.sh:10`]). `_pt_runs` runs a
  file and matches its version with `_pt_names`. `_pt_place` does `install -m 0755` then `cmp`, so a short
  copy FATALs before the marker. deployer and pie (`Deployer <v>`, `(PIE) <v>`; rc 0, stdout only
  [measured]) are version-checked before they are placed. zephir, phalcon and pickle cannot run under the
  image's php 8.5.4 (mbstring missing) [measured], so their version is UNCERTIFIED-BY-EXECUTION: pinned by
  the release URL plus the Phar signature only. None of the five publishes a checksum (pie's `.asc` and
  `.sha256` 404). deployer's `curl -LO` without `-f` (a 404 page installed, marker written) and its
  `mv`/`chmod 2> /dev/null` are gone; so are the four `rm -rf <tool>.pha*` globs. A post-install version
  run was written and then removed: after a `cmp` pass the installed bytes are the checked download's, so it
  could never fire. §67: 41 checks (67a stub non-vacuity ×2; per tool up, down, first install, no-op; 17
  failure cases: not published, HTML page, truncated, and for deployer/pie a `1.6.00` reply; 67g a short
  copy for zephir and deployer), 17 red first with the old code's reasons (HTML and truncated files
  installed with their markers, deployer installing the 404 page, unpublished pins dying unnamed). The
  stub php models the MEASURED open (`.phar` name, `__HALT_COMPILER();`, trailing `GBMB`); the stub curl
  now models a missing `-f`. §25g/25h (zephir only, anchored on the deleted glob) retired: their four
  properties are asserted per tool in §67. Sabotage P1–P6 caught and restored byte-identical; P7 (drop `-f`)
  SURVIVES by design, since the Phar open refuses the 404 page. Suite 845/845. REAL, throwaway 02phpbrew
  container, scratch tools/, cwd a scratch projects dir: all five at their pins (installed sha256 equal to
  independent downloads), deployer v8.0.5 → v8.0.4 → v8.0.5 and pie 1.5.0 → 1.4.3 → 1.5.0, pie 9.9.9 →
  named FATAL with the old pie and marker kept, no-op; no stray file in tools/bin, the projects file
  survived, no temp dir left on success [Verified: ran].
  zephir/phalcon/pickle moved DOWN only in §67c's fixtures; the real runs moved deployer and pie down and
  back. Step 15b commit: `f8e5d03`.
- AS BUILT (15c): symfony and fabpot are checked against their release's `checksums.txt`, but only
  against the asset's OWN line (`awk '$2 == n && length($1) == 64'`; mawk has no `{64}`), since the file
  lists every platform; a file that does not list the asset FATALs as "not listed", not as a mismatch.
  symfony's tarball must list the bare member `symfony` (as upstream's does) and is unpacked in the temp
  dir; mago's pinned release tarball (`mago-<v>-x86_64-unknown-linux-gnu/mago`) replaces `mago.sh | bash`.
  Every one is version-run before it is placed: `symfony version --no-ansi` (its `--version` exits 1),
  `mago --version`, `castor --version`, fabpot `--version` [all measured rc 0, stdout only]. fabpot's
  `curl -LsS -o <the installed binary>` without `-f` is gone: a 404 page no longer overwrites the working
  checker. castor: the old installer's default was the PHAR, and the live `tools/bin/castor` is
  byte-identical to the upstream v1.7.0 phar [Verified: `file -b` + sha256], so it stays a phar (not the
  static build, which embeds its own php and would drop the developer's extensions from castor tasks) and
  joins §67: Phar open + `castor v<v>` (decided in-session, two-way door; not a ruling). mago and castor
  publish no checksum (GitHub attestations; castor's installer looks for a `SHA256SUMS` that v1.7.0 does
  not publish), so their integrity is the listing/Phar signature plus the version run. New helpers:
  `_pt_get`, `_pt_sum`, `_pt_untar`, and `_pt_says` (replaces `_pt_runs`; runs any command); `_pt_place`
  now takes the checked file. §68: 31 checks (fixture non-vacuity; per tool up, down, first, no-op; not
  published, checksum mismatch, tarball without the binary, an HTML page WITH a matching checksum, a `.00`
  version, no checksums.txt, a checksums.txt without the asset's line; 68g no executable line pipes into a
  shell; 68h every curl carries `-f`, counted per CALL with a floor of 4 — two composer calls share a
  line). CORRECTED (6C): §68 is 29 checks, and castor added +8 to §67 (7 was its red count; 67e passes on
  the old code) — 882 - 845 = 37 = 29 + 8. §67 gained castor. Red first: 25 for the old code's reasons (fabpot's 404 page installed with
  its marker; bad checksums and `.00` versions installed; the piped installers never fetching the pin),
  after a fixture fault was fixed first — the symfony tarball had `./symfony` members, which the real one
  does not. Sabotage C1-C10: C3 (drop the listing) SURVIVES by design — extracting a missing member fails
  with the same named FATAL; C10 (drop the not-listed branch) first SURVIVED (fail-closed, only the message
  changed), so the unlisted fixture was added and now catches it. Suite 882/882; shfmt diff 6 → 0,
  shellcheck 7 → 4. REAL, throwaway 02phpbrew container, scratch tools/: all four at their pins, installed
  sha256 equal to upstream's artifacts (castor equal to the live copy); symfony v5.20.0 → v5.17.1, mago
  1.49.0 → 1.48.0, castor v1.7.0 → v1.6.0, fabpot v2.1.3 → v2.1.2 and back; fabpot v9.9.9 → named FATAL
  with the working checker and marker kept; no-op; the 15a/15b tools untouched, no stray file, no temp
  dir left on success [Verified: ran]. CORRECTED (6C): symfony v5.19.0 and v5.18.0 are tags with NO
  release (their tarball 404s too), which is why the down run used v5.17.1. 68g catches `| bash` but not
  `bash <(curl …)` — same class, absent today. Step 15c commit: `ff79ee0`.

### Step 16 — android SDK (S) — RULED 2026-09-24 23:55: option (a) only
- Any change to the 14 SDK inputs wipes `ANDROID_HOME`, `ANDROID_SDK_HOME`, `ANDROID_SDK_ROOT` AND
  `GRADLE_USER_HOME` before a 15+ min multi-GB install (`android-start.sh:168-176`) [Verified: read]. A failed
  install leaves no SDK (the container stays up in `sleep infinity`, unhealthy with an error token).
  Two independent axes: (a) stop wiping `GRADLE_USER_HOME` (Gradle's build cache, unrelated to any SDK pin)
  — cheap; (b) staged install into `${ANDROID_HOME}.new` + verify + swap, so the old SDK stays usable until
  the new one is proven — costs a second full SDK on disk during the install. The AVDs under
  `ANDROID_SDK_HOME` are recreated by `setup-dist.sh` every boot, so (b) leaves them to that step rather
  than staging them [Inferred from §43's `_andd_probe`; to confirm]. Choices: (a) alone / (a)+(b) / leave.
- AS BUILT (16): `GRADLE_USER_HOME` is dropped from the `sudo rm -rf` in `android-start.sh`; the SDK dirs and both
  markers are still wiped whole. The line serves all three triggers — a changed SDK input, a missing
  `android.cli` marker AND `RELOAD_ANDROID=true` — so RELOAD_ANDROID no longer clears the Gradle cache either
  (the ruling is unqualified; step 17 corrects CLAUDE.md's "RELOAD = full reinstall" wording for android).
  `setup.sh:35`'s `chmod -R a+rwx` / `chown -R` of `GRADLE_USER_HOME` now walk a preserved cache on each
  reinstall — harmless, only slower on a large cache. §69: 6 checks run the SHIPPED gate→wipe→mkdir block,
  extracted by anchors, under `env -i` with every path pinned into the test root and a stub `sudo` that refuses
  any path outside it (69a proves the refusal, exit 99, on a SIBLING tmp dir that must survive — first written
  against the live `/stack/tools/android` path, fixed at 6C so a broken guard costs a tmp dir, not the SDK)
  — the block is a real `sudo rm -rf` of variables an ordinary /stack shell exports. 69b-69d red first
  (`gradle=wiped` on all three triggers); the sabotage re-adding `GRADLE_USER_HOME` reds the same three, one
  dropping `ANDROID_HOME` + `ANDROID_SDK_ROOT` (equal in `.env`, so both) reds them on `sdk=kept`, and a stub
  `sudo` that accepts everything reds 69a — each restored byte-identical;
  69e (current → nothing wiped) guards the skip path. A fingerprint of the live `tools/android`, `tools/gradle`
  and both markers was identical before and after every run. Suite 888/888. Certified by the §69 execution
  only: no throwaway 04android run, a one-token change to a 15+ minute multi-GB reinstall path.

### Step 17 — docs (S)
CLAUDE.md hand-off (runtimes now delete-after-install; staged go/zig/hurl; the php.edge exception), memory.
- AS BUILT (17): the unblocked surfaces first, in one commit: `docs/BLAST-RADIUS.md`'s RELOAD row,
  `templates/tips/env-scan.md` (a note under the RELOAD table), `/debug-service`'s two runbook lines, and the
  §67 label (five → six phars; test TEXT only, `bash -n` is the evidence and the tally stays 888). The RELOAD
  inventory covered CLAUDE.md, BLAST-RADIUS, templates/tips, `.env`, `.claude/skills` (`/stack-ask-human`
  states no wipe semantics and is left; `/bump-versions` was WRONGLY left too — its step 5 advised deleting
  the marker or setting RELOAD, the broken path; corrected in step 26; `.env:1448`'s one-line comment is left as a
  pointer). The corrected claim: `RELOAD_NODE*` / `_JAVA*` / `_FLUTTER3` remove only the success and version
  markers [Verified: read `nvm-start.sh:43-46`, `sdkman-start.sh:58-61`, `fvm-start.sh:41-44`], after which
  the installer no-ops on the version dir on disk [Inferred: the step-11 finding, not re-run]. CLAUDE.md
  goes through `/tmp/edit-claudemd-tranche2-20260926.sh` (classifier-blocked): the Common Workflows comment
  (what tranche 2 delivered, with android's pre-install wipe and php.edge as the two exceptions, and hurl's
  00base rebuild), the three RELOAD statements, the test count 685 → 888 with a §60-§69 sentence, and two
  Gotchas lines (the checksums.txt refusal with the URL-only phar versions; `/new-service` scaffolds no gate,
  the scaffold fix logged as a follow-up). The script commits CLAUDE.md alone, then this plan's row 17 with
  that commit's sha. Step 16 commits: `42b5eb2` + `bbcadb2`.

### Not in tranche 2 (still open from the audits)
A3 FRANKENPHP launch skip; A4 caddy plugin pins; A5 nginx/httpd modules; A6 `make rebuild` not pushing;
A7 SDKMAN installer hardcoding 5.23.0; PARTIAL: fvm unplumbed var, nvm raw-pin (latent), yarn patch,
groovy/spark depends_on; B `|| echo` / `curl -L` without `-f` in 00base, phpbrew ext exit-0; C RELOAD_*
escape hatches keeping pkg markers; the `source X && cmd` class.

## Formal Plan — tranche 3 (APPROVED 2026-09-26 11:43; rulings 11:17 and 11:43)

Scope (ruling 11:17): every reinstall site the tranche-2 milestone panel found outside the ruled list — fvm,
deno, bun, rust, phpmyadmin, caddy, httpd, nginx, php.edge — same shape as tranche 2, plus the panel's
round-1 doc findings; then ONE milestone panel over tranches 2+3. Absorbs A4 (caddy plugin pins) and A5
(nginx/httpd modules) from "Not in tranche 2".

**Shape (tranche 2's, unchanged):** fetch into a `mktemp -d` OUTSIDE `tools/` (never the compose
`working_dir` `/stack/projects`), `curl -f`, the published checksum where one exists (fail closed on an
unlisted asset), archive listing, the artifact's own `--version` against the pin, THEN wipe and place, marker
last. Nothing is unpacked beside its old tree in `tools/` (ruling). Bidirectional: every gate stays equality.

Two site classes — the difference is where the install prefix lives [Verified: inventory read 2026-09-26]:
- **Relocatable** (a binary or a self-contained tree): fvm, deno, bun, phpmyadmin, caddy. Built and checked
  entirely in the temp dir; a failed check leaves the old one working.
- **Prefix-baked** (`configure --prefix` / rustup homes / phpbrew's build root): httpd, nginx, php.edge, rust.
  The build cannot run anywhere but its final path. POLICY = RULING NEEDED (see question); draft assumes
  option B: every INPUT fetched and checked before the wipe, then wipe, build at the final path, check the
  build (`--version`/config test), FATAL + error token on failure — the old one is gone on a BUILD failure,
  the same trade the android ruling (a) accepted; a download/checksum failure still leaves it working.
  Consequence stated accurately: since 2026-09-02 each web server writes its own error token and
  `base-wait-for.sh` polls it, so a failed httpd/nginx build makes phpmyadmin/localstack/serverless/alltogether
  fail FAST on that token, not hang 3600s [Verified: CLAUDE.md § token invariant exception; re-read in step].
- **The shared ModSecurity tree** (`tools/http`: libmodsecurity + CRS) is a THIRD prefix-baked site: both
  `httpd-iou-common.sh:57-94` and `nginx-iou-common.sh:55-85` gate the SAME `http.mod_security` marker, then
  `rm -rf` source+lib, `git clone --branch <pin>`, build at `--prefix`, no check [Verified: read]. Whichever
  web server boots first owns the rebuild; they are alternatives (one enabled) [Inferred: CLAUDE.md, not
  enforced — two enabled at once would race on the same path, pre-existing].

**Live-bump consequence of approving:** the composite gates (22-24) change what the web-server markers hold,
so every enabled web server REBUILDS on the first boot after the commit, with no pin bump. Same for
phpmyadmin/the ModSecurity connector if the floating-pin option is taken.

**What is wiped (explicit, so it is ruled, not assumed):** caddy replaces `bin/caddy` only (vhosts/Caddyfile
are regenerated every boot anyway); httpd/nginx wipe their tree EXCEPT `logs/` (the GRADLE_USER_HOME shape);
everything else wipes its whole tree as today.
The shared ModSecurity tree (step 23a) removes only libmodsecurity's source, lib and marker after
its clone is checked; `mod_security/{tmp,logs,conf}` are kept (the setup scripts recreate them and
re-sync conf/ every boot); a lib BUILD failure leaves no library, so the old `mod_security3.so` cannot
load either — httpd/nginx are down until the next boot either way (policy B, accepted).

### Step 18 — fvm (S) · `fvm-bin/global-stack-fvm-start.sh:76-85`
Today: downloads and `sudo rm -rf fvm-*.tar.gz fvm/` in cwd `/stack/projects` (panel P1). Fix: temp dir,
`curl -f`, listing must contain `fvm/fvm`, `fvm --version` = pin, `install -m 0755` into `tools/bin`, marker
last. No checksum published for 4.3.1 [Verified: release assets]. Tests §70: bump up/down, bad tarball →
named FATAL + old binary and marker untouched, projects dir untouched, no `rm` in cwd.
**AS BUILT (`033ba49`):** §70 11 checks (up, down, first, current, RELOAD, four bad pins, `-f` floor+guard); six
sabotages as predicted (S5 `-f` dropped survived until 70h was added). Real 02fvm container: real curl + the Dart
binary, `sudo install` as `developer`, `4.3.1`, projects intact, no temp left. `RELOAD_FVM=true` still removes
`tools/bin/fvm` earlier in the script by design (RELOAD = full wipe). Not covered: §70 pins `FVM_VERSION` and
`GLOBAL_STACK_FVM_VERSION` to the same value, so the "fvm unplumbed var" audit item stays open. The temp dir leaks
on a FATAL path (the prologue owns EXIT; same accepted shape as install-tools).

### Step 19 — deno + bun (M) · `nvm-bin/global-stack-nvm-install-tools.sh:14-51`
Today: deno runs a downloaded `install.sh` in cwd; bun is `curl https://bun.sh/install | bash` (panel P1,
ruling "never pipe"); both `rm -rf` the binary + marker BEFORE fetching. Fix: pinned
`deno-x86_64-unknown-linux-gnu.zip` + `.zip.sha256sum`; `bun-linux-x64.zip` + `SHASUMS256.txt` (asset's own
line) [Verified: assets for v2.9.7 / bun-v1.4.2]; `unzip -l` listing; `deno --version` first line /
`bun --version` = pin; `install -m 0755`; bun's `bunx` symlink recreated (the installer made it — verify
before relying); no installer script at all. `unzip` + `sha256sum` present in 02nvm [Verified: image]. §71.
**AS BUILT (`a6d2e63`):** §71 20 checks; §24 retired (its stubs modelled the removed installers; its five properties
moved into §71, the binary-missing floor for BOTH tools). Ten sabotages red; B2 (unlisted asset) red only after each
bad pin asserted its own FATAL text on `^FATAL: ` lines (the prologue's failure dump quotes ancestor command lines,
memory `feedback-prologue-log-quotes-ancestors`). Behaviour change: `bun completions`, both installers' `~/.bashrc`
edits and deno's shell setup are dropped (container home only, never `tools/`); `bunx` is linked explicitly (it came
from `bun completions`). A deno FATAL stops bun's bump in the same boot (pre-existing order). Real 02nvm run: both
installed from real zips, bunx works, projects intact, no token, no temp left, a second run downloads nothing.

### Step 20 — rust (S) · `rust-bin/global-stack-rust-start.sh:35-39`, `global-stack-rust-iou.sh`
Today: wipes `RUSTUP_HOME` + `CARGO_HOME` before `rust-iou.sh` fetches rustup-init. Fix (prefix-baked
policy): rustup-init fetched + checksum-checked into the temp dir BEFORE the wipe; after install
`rustc --version` must name `GLOBAL_STACK_RUST_VERSION` or FATAL. rustup verifies its own component hashes
from the dist manifest [Unverified: recall — confirm in the step]. The fetch moves from iou to before the
start.sh wipe; §58 (a rustup-only bump lands without a RUST wipe) must stay green. §72.
**AS BUILT (`5f41482`):** the installer script is gone too: rust-iou.sh fetches the pinned `rustup-init` BINARY +
`.sha256` (`<hex> *./rustup-init`) from static.rust-lang.org, the archive the installer used and the one 00base's
Dockerfile already checks. The RUST gate and the wipe moved into rust-iou.sh, after the check; rustc is checked by
path. Toolchain integrity = rustup's own per-component sha256 against the channel manifest [Verified: manifest
`hash` fields; `src/dist/download.rs` at 1.29.1]. §58 rewritten to the binary model (11 checks kept), §72 15 checks;
nine sabotages red where predicted (R1 redone as valid code). Real 02rust: an unpublished rustup-init FATALs with
`jj`, the old toolchain and both markers kept; a real 1.98.0 → 1.98.1 bump wipes and reinstalls (rustc 1.98.1,
rustup 1.29.1, `CARGO_HOME/env` present). The live `tools/bin/rustup.installer.sh` is orphaned; left in place. The
five cargo tools reinstall after a wipe through their `command -v` floor (pre-existing, correct). Stale docs for
step 26: CLAUDE.md:352 describes §58 as "rustup via its own `RUSTUP_VERSION` knob".

### Step 21 — phpmyadmin (M) · `phpmyadmin-bin/global-stack-phpmyadmin-{start,iou}.sh`
Today: wipe first; branch/tag/commit fetched with `curl -LsS` (no `-f`), nothing checksummed; composer +
yarn build run inside the final dir. Fix: build the whole tree in the temp dir (relocatable [Inferred:
inventory; confirm no absolute path is written by the build]), `-f` everywhere, `type=release` checked
against the published `.sha256` [Verified: 5.2.3 URL 200], check `index.php` + `vendor/autoload.php` + the
built JS exist, THEN wipe + move. The pin is `master`/`branch` (annotated `lock:` — intentional), which the
equality gate can never see move — RULING NEEDED (floating pins): the php.edge shape, `(use-sha)
(version-prefix:…) github:phpmyadmin/phpmyadmin` + `TYPE=commit`, so env-update advances a SHA the gate sees. §73.

**AS BUILT (step 21):** the build moved from start.sh into phpmyadmin-iou.sh: the archive is downloaded with `-f`,
listed, and the whole tree is built in a `mktemp -d` (release: checked against the published `.sha256`; branch/tag/
commit: the GitHub archive whose top dir must be `phpmyadmin-<ref>`); `index.php` present and `vendor/autoload.php`
loadable by `php`, THEN the old tree is removed and the new one moved in; the marker follows. `.env` is SHA-tracked
(`(use-sha) (git:…) github:phpmyadmin/phpmyadmin master sha:…`, `TYPE=commit`, no version-prefix: the archive URL
takes the bare sha) — env-update classifies it as a SHA record [Verified: `--check --filter=PHPMYADMIN`]. §73 15
checks, sabotages red; §28d now counts one `_pma_install` guard. Real 04phpmyadmin image, writable scratch tools root,
live php/node/composer read-only: rc 0 in 332 s, the old tree's files gone, autoload loads, temp dir removed, no
token. Full suite 938/939: the one red is 43ac, the pre-existing android verify SIGPIPE race (Fragile, 2026-09-24),
root-caused and fixed in the next commit; that run had the step-22 caddy drafts in the working tree. Follow-ups,
not fixed: phpstan's `vendor/phpstan/extension-installer/src/GeneratedConfig.php` carries the (deleted) temp build
path — dev-only, the old in-place build carried a live one; `--no-dev` would drop it. The composer.json
`phpmyadmin`→`phpmyadminx` `sed -i` moved verbatim and asserts nothing — its reason is unrecorded, so a silent no-op
stays the old behaviour rather than becoming a FATAL. `get-latest-version.sh` has no callers. `.env.local` still
holds `master`/`branch` until the developer runs env-scan.

### Step 22 — caddy (M) · `caddy-bin/global-stack-caddy-{start,iou}.sh`
Today: wipe, `go build` of the core, then `caddy add-package` ×4 — which DOWNLOADS a binary built by
caddyserver.com's build service [Verified: `caddy help add-package` → "Downloads an updated Caddy binary"],
so the shipped binary is neither built locally nor checksummed; the four plugin pins are not gate inputs
(A4). Fix (ruled 2026-09-26 11:43 — xcaddy, add-package dropped): `xcaddy build <CADDY_VERSION> --with <plugin>@<pin>…` (local
build, xcaddy itself a new `.env` pin fetched via its `checksums.txt` [Verified: v0.4.7 assets], plumbed
through the 01caddy compose (compose-env-plumbing surface); build in the temp dir; `caddy version` names the
pin and `caddy list-modules --packages --versions` names each plugin AT its pin; `install -m 0755` over
`bin/caddy` (single binary: vhosts/Caddyfile are regenerated, `logs/` kept). Composite gate
`core;plugins…` with a both-ways guard (the §47 shape). `GLOBAL_STACK_XCADDY_VERSION` is deliberately NOT a
gate input: it is the builder, and the binary is determined by the caddy + plugin pins. Fixes `start:88-90` passing the marker path twice. §74.
**Done** (recovered 2026-09-26 after the session crashed mid-verification; WIP was snapshotted to
`refs/recovery/step22-*` before anything was touched). §74 25 checks. 14 sabotages each red their named
check(s) against a green baseline, restores byte-identical: sha512 neutered, xcaddy/caddy version checks off,
exact and commit-pin plugin compares off, `GOTOOLCHAIN=local` dropped, brotli out of the composite, the
multi-line `"${CADDY_PATH}"` wipe re-added, marker before the iou, iou failure swallowed, caddy-build kept,
`curl -f` stripped, compose plumbing dropped, temp dir kept on FATAL. P2 fixed in recovery: `_cd_fatal`
leaked the xcaddy temp dir on every failed boot; 74h now asserts `tmp=0`. Real 01caddy image, scratch tools
root, live `tools/go` (1.27.1) read-only, GOPATH/GOCACHE in scratch: rc 0 in 258 s — the real xcaddy 0.4.7
passed its SHA-512, caddy `v2.11.4`, list-modules names transform-encoder
`v0.0.0-20260423033309-ba4124974830`, brotli v1.6.0, security v1.1.64, cache-handler v0.17.0; logs kept, no
token, temp dir removed. Full suite ALL PASSED. **Ordering constraint:** `.env.local` lacks
`GLOBAL_STACK_XCADDY_VERSION` until `bin/env-scan.sh` runs (compose resolves it to `""`, verified), and the
composite marker differs from the old plain-version one, so the next 01caddy boot rebuilds and FATALs by
name (`GLOBAL_STACK_XCADDY_VERSION is empty`) — run env-scan BEFORE restarting 01caddy. Not certified by
execution: the full `global-stack-caddy-start.sh` boot in a live container (the probe ran the iou alone).
The Files cell no longer lists `compose-env-plumbing.test.sh`: it tests only `USE_LOCKS`; §74n pins the
compose line and the resolved value was checked by hand.

### Step 23 — httpd (L) · `httpd-bin/global-stack-httpd-{start,iou}.sh`
Today: wipe, `svn checkout http://svn.apache.org` (plain http, no checksum) of httpd/apr/apr-util, build at
the final prefix; apxs connectors (ModSecurity-apache `master`, mod_auth_openidc) install into the prefix;
the gate holds only `HTTPD_VERSION` (A5). Fix (prefix-baked policy): switch to release tarballs + `.sha256`
from **archive.apache.org only** (downloads.apache.org drops superseded releases, so a pin moved DOWN would
404) [Verified: httpd 2.4.68 tarball + .sha256, apr 1.7.6, apr-util 1.6.5 all 200 there]. The `.env` pins and
their svn-listing annotations stay `tags/X` — the install uses `${V#tags/}` — so env-update and its t37j/t37i
tests are untouched; an svn tag with no release tarball fails CLOSED before the wipe (consider
`(verify-asset:)` on the three annotations — confirm its placeholder sees the stripped version first). BUILD
change: tarballs ship `configure` (no `./buildconf`), apr/apr-util extracted into `srclib/apr{,-util}` by
name. Checksum format differs from tranche 2's `checksums.txt`: all three Apache `.sha256` files are
`<64 hex> *<name>` (binary-mode `*`) [Verified: httpd 2.4.68, apr 1.7.6, apr-util 1.6.5], so the match is
`($2 == n || $2 == "*" n) && length($1) == 64` — the tranche-2 awk would fail closed on a GOOD file. Every
source fetched and checked before the wipe; after the build `httpd -v` names the pin and `apachectl -t` passes. Composite gate: httpd,
apr, apr-util, modsec lib, modsec-apache connector (`master` — floating-pins ruling), openidc. `logs/` kept.
**23a — the shared ModSecurity tree** (both `*-iou-common.sh`): clone at the pinned tag into the temp dir
BEFORE the wipe, then wipe, build at the prefix, check `lib/libmodsecurity.so.3` exists and `bin/` holds
at least one file (certain: `iou-common.sh:91` already chmods `bin/*`); `modsec-rules-check` running is a
stronger check [Unverified: not read in v3.0.16's build — add only if the step confirms it is built]; CRS: clone into temp, check `crs-setup.conf.example` +
`rules/` exist, then swap (relocatable). §75.
**Done.** §75 51 checks + 30f2 (and `_ws_decision` now reads `_<srv>_want`, so 30e/30f cannot pass
by comparing a composite gate to ""). Against the pre-change scripts §75 is 50 red / 2 green (the two
"markers current" cases, behaviour that was already right). 24 sabotages, each red on its named check
against a green §30+§75 baseline, restores byte-identical: sha256 neutered, Apache `*name` form
rejected, listing/top-dir/`-v`/`-V`/`apachectl -t`/module checks off, wipe moved before the fetch,
`logs/` not kept, apr-util out of the composite, marker before the iou, start.sh wipe re-added,
`curl -f` stripped, downloads.apache.org, temp dir kept (iou and iou-common), gate on HTTPD_VERSION
alone, submodules not `--recursive`, lib/CRS wiped before the clone, `.so.3` check off, `--with-lua`
re-added, one iou-common copy drifting. Full suite 1018/1018. Real run of the SHIPPED iou-common + iou
in the 01caddy image (its Dockerfile differs from 01httpd's only by a sysctl line, EXPOSE and CMD),
scratch tools root: rc 0/0 in 1888 s — libmodsecurity v3.0.16 (`.so.3`, `modsec-rules-check`), CRS
v4.29.0, `Apache/2.4.68`, `Compiled using: APR 1.7.6, APR-UTIL 1.6.5` (system apr-util is 1.6.3, so
`--with-included-apr` is what makes the apr pins real), `mod_security3.so` RUNPATH → the lib (loads
without LD_LIBRARY_PATH), `mod_auth_openidc.so`, `apachectl -t` Syntax OK with both loaded, logs kept,
no token, no temp left. **Two pre-existing breaks fixed on the way, both measured:** the shared library
could never build — `submodule update --init` leaves Mbed TLS's nested submodules empty ("Mbed TLS was
not found"), and `--with-lua=<pkgconfig dir>` stops configure ("LUA was explicitly requested but not
found"; ruling 15:52 dropped it). The shared wipe moved from BOTH start scripts into iou-common behind
the clone (nginx-start.sh therefore in the Files cell); iou-common runs every boot and gates itself.
The connector is SHA-tracked (`0488c77`, env-update resolves it `(up to date)`); a branch/tag ref
still works. `(verify-asset:)` does not apply to the three svn annotations (it needs `(fetch-json:)`);
the iou fails closed on a missing tarball before any wipe. **UNCERTIFIED-BY-EXECUTION:** a live
01httpd boot through the new start.sh (no 01httpd image exists on this machine; httpd is not enabled
here, so nothing live changes); the lib-bump reinstall path and every failure path are proven by
stubs only. The nginx side of iou-common is byte-identical and stub-tested; nginx's own build is step 24.
Step-26 follow-ups from step 23: `subversion` is still installed by the 01caddy, 01httpd and 01nginx
Dockerfiles although httpd no longer uses svn (drop it once step 24 confirms nginx does not either — an
image change, needs a rebuild); the `GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION` annotation's note "bump
requires rebuilding HTTPD and Nginx images" is stale (the library is built at boot into tools/). For
step 24: no 01nginx image exists locally either, and 01nginx's Dockerfile differs from 01caddy's
(automake for the OpenIDC chain) — `diff` them before reusing 01caddy as the stand-in.

### Step 24 — nginx (M) · `nginx-bin/global-stack-nginx-{start,iou}.sh`
Today: wipe, `curl` of nginx.org tarball with no signature check, connector cloned into
`NGINX_PATH/mods/modsecurity-source` every run and never removed; connector + modsec lib not gate inputs.
Fix: tarball verified against its `.asc` with the five nginx.org developer keys committed in the repo
(`gpg --homedir <tmp> --no-default-keyring --keyring <repo file> --status-fd 1 --verify`, asserting a
`VALIDSIG` line whose fingerprint is in a pinned list — never the exit code alone; a new signing key fails
CLOSED and loud). The five keys, fingerprints derived with `gpg --show-keys` from nginx.org/keys/*.key
[Verified 2026-09-26; cross-check against nginx.org/en/pgp_keys.html by eye in the step]: arut
`43387825DDB1BB97EC36BA5D007C8D7C15D87369`, pluknet `D6786CE303D9A9022998DC6CC8464D549AF75C0A` (signed
1.31.6 [Verified: `gpg --list-packets`]), sb `7338973069ED3F443F4D37DFA64FD5B17ADB39A8`, thresh
`13C82A63B603576156E30A4EA0EA981B66B0D967`, nginx_signing `8540A6F18833A80E9C1653A42FD21310B49F6B46`.
Keyring committed at `docker/config/dist/bin/nginx-bin/nginx-release-keys.asc` (ASCII-armoured — reviewable
in a diff; a clean clone gets it with the scripts). Only `gpg` exists, no `gpgv` [Verified: 00base]; connector cloned into the temp
dir; after the build `nginx -V` names the pin and `nginx -t` passes. Composite gate: nginx, connector,
modsec lib. Fixes `start:202` `nginx stop` → `nginx -s stop`. `logs/` kept. §76.
**Done — `82a3524`.** §76 has 29 checks and runs REAL gpg against three throwaway keys
(pinned / in the keyring but unpinned / stranger). The test copy of the iou gets the test fingerprint
spliced in as a sixth, third-position entry, and 76a asserts exactly that one-line diff. Against the
pre-change scripts: 28 red, 1 green (the fixture check). There are 19 sabotages, each red on its named
check against a green §30+§76 baseline, and each restore is byte-identical. The mutations:
- fingerprint membership by IFS join;
- pinned, listing, connector-`config`, `-V` version, `--add-module` and `nginx -t` checks each switched off;
- wipe moved before the fetch; `logs/` not kept; OpenIDC-chain markers kept;
- connector dropped from the composite; marker written before the iou; start.sh wipe re-added;
- `nginx stop` restored; `curl -f` stripped; temp dir kept on FATAL;
- a pinned fingerprint altered; gate on NGINX_VERSION alone; missing keyring not refused.

Full suite 1047/1047. A real run of the SHIPPED iou in the 01caddy image, against a scratch tools root
and the libmodsecurity built by step 23's run, took 164 s. Results: rc 0; GOODSIG plus a VALIDSIG
whose primary is pluknet's; `nginx version: nginx/1.31.6`; `--add-module` pointing at the connector;
`libmodsecurity.so.3` resolved to the shared lib; `nginx -t` ok; logs kept; no token; no temp dir left.

The five fingerprints were cross-checked on 2026-09-26. nginx.org/en/pgp_keys.html publishes no
fingerprints; it links exactly the five `.key` files. The primaries derived from freshly fetched copies
equal the pinned list. `nginx_signing.key` also carries two older keys, which stay unpinned on purpose.

**Measured along the way:**
- **Membership join:** the first real run REJECTED a good pinned signature. The script's `IFS=$'\n\t'`
  makes `"${arr[*]}"` join with newlines, so the `" ${list[*]} " == *" x "*` membership test could
  never match. It is now a loop, and N1 pins it.
- **gpg-agent:** a gpg-agent-stop helper was added and then REMOVED. Its "two agents left" evidence
  was the probe `pgrep -fa gpg-agent | grep scratch` matching its own `bash -c` command line. Measured
  by exact process name in the image: gpg-agent is alive before `rm -rf` of the temp homedir and gone
  one second after. §76's `agents=` field stays as an observation.
- **svn:** nginx uses no svn, which completes the step-23 `subversion` follow-up below.
- **Build path:** `nginx -V` names the connector's temp path, now deleted. This is cosmetic (static
  module).

**UNCERTIFIED-BY-EXECUTION:**
- A live 01nginx boot through the new start.sh. No 01nginx image exists here, nginx is not enabled,
  and 01caddy stood in, since their Dockerfiles differ only by sysctl, EXPOSE, CMD and an automake step
  that `.env` leaves empty.
- The OpenIDC chain. It is unchanged, but its pins are empty here, so the real run skipped it.
- Every failure path, proven by stubs only.
- Expired and revoked signing keys, which are rejected on the status lines (EXPKEYSIG / REVKEYSIG)
  but have no test key.

### Step 25 — php.edge (S) · `phpbrew-bin/global-stack-phpbrew-start.sh:96-99`
Prefix baked by phpbrew (no `INSTALL_ROOT` exposed) → prefix-baked policy. Today no post-build check (the
`bin/php` FATAL is unreachable for edge). Fix: after the build, `tools/phpbrew/php/php-master/bin/php -r 'echo PHP_VERSION;'` (that path, never PATH's
`php`) must succeed
and end in `-dev`; sidecar `php.edge.build` written only after that. §77.
**Done — `b273b9c`.** Widened slightly, on purpose. The check sits right after the install step
and runs on EVERY php install, not just edge: the php it built must run `-r 'echo PHP_VERSION;'` and
report `X.Y.Z-dev` (edge) or exactly `${PHP_VERSION}` (the others). Measured on the installed builds:
`8.6.0-dev`, `8.4.25` and `8.5.10`. The same gap existed for a fresh 8.4/8.5 install (marker absent),
whose only check was the reinstall-only `-x` test. That `-x` guard stays inside the cleanup block,
local to the `rm -rf` it protects (§60 pins it). A named FATAL exits 1 before the old php is cleaned
and before any marker or sidecar is written; the prologue's EXIT trap writes the token.

§77 has 12 checks and runs the shipped install block against a stub install step that exits 0
whatever it built. Against the old script: 8 red, 4 green (happy paths plus the anchor). There are
6 sabotages, each red on its named check against a green §60+§77 baseline:
- check disabled;
- check reachable only on reinstall (the pre-fix edge shape);
- edge accepting any output;
- a prefix compare;
- FATAL without `exit`;
- check moved after the old-php cleanup.

Full suite 1059/1059. The shipped check lines were also run against the real php-master, php-8.4.25
and php-8.5.10 builds in `tools/`: all accepted, and a pin of 8.4.26 against the 8.4.25 build got the
named FATAL.

**Risk accepted:** a partial non-edge pin (`8.4`) would now FATAL. Every pin is a full version, as
env-update writes them.

**UNCERTIFIED-BY-EXECUTION:** no php.edge rebuild was run, since it needs a 03phpedge boot and a
php-src compile.
**6C follow-up — `747c7ff`.** The advisor pointed out that PHP CLI writes startup warnings to STDOUT.
Measured on php-8.4.25 with a missing `extension=`: the warning lands ahead of the version, so the
exact compare would have failed a working php whose fresh ini loads a missing library. The check now
runs `php -n` (php.ini skipped: it asks the binary, not its config), and a FATAL carries php's own
stderr. §77 is now 14 checks:
- 77c2: the FATAL names php's stderr;
- 77c3: a polluting ini still passes (its stub models the measured stdout warning).

8 sabotages, including `-n` dropped and the diagnostic dropped. Full suite 1061/1061.
`install-version.sh` has one caller, this block, and there is no copy of the script anywhere.
local.05's `alltogether-start.sh` only consumes the php markers and success tokens.

### Step 26 — docs + tranche-2 panel findings (M)
CLAUDE.md hand-off script: the "Two exceptions" / "every downloaded tool" overclaim rewritten for the
tranche-3 end state; Rust pins feed the 00base hurl stage; go/zig/mise also baked into 00base. `.env:1430-1436`
Rust comments. `.claude/skills/bump-versions/SKILL.md:24` stops advising marker deletion / RELOAD. This
plan's wrong `/bump-versions` statement; install-tools stale symfony comment; `LOCAL_RELOAD_FLUTTER3_41_9`
in the do-not-wipe lists; Files cells of rows 14 and 17; the RELOAD question moved to `### Needs input`.
P3: named FATALs for `install-go.sh` `_go_sha=` and `install-mise.sh` first `_mise_got=`.
**Done — `293a8d0` (code + tests), `f87cf44` (images), `b0f846f` (docs); CLAUDE.md via
`/tmp/edit-claudemd-step26-20260926.sh` (classifier-blocked; dry-run on a copy: 7/7 anchors).**

- **Scope widened on purpose (the P2 plumbing finding):** documenting the go/zig/mise "image-baked"
  pins showed a real defect, not just a gap in the docs. 00base installs them at BOOT
  (`base-start.sh` → `base-install-{go,zig,mise}.sh`, sole caller [Verified: git grep + local.* sweep]),
  but their pins reached it only as build args frozen in the image `ENV`. A `.env` bump plus a restart
  therefore gated against the OLD pin and installed nothing. This is F3's shape (USE_LOCKS). The three
  now reach 00base's runtime `environment:`, and the build args stay as the default.
  - `compose-env-plumbing.test.sh` §7 derives the pin set from the installers `base-start.sh` calls.
    It was 3 red before the fix (`<absent>` at runtime) and is 21/21 after. A broken derivation fails
    its floor.
  - 6C follow-up: the bare `MISE_VERSION`, exported by install-mise into the host's `mise.shellrc`, is
    plumbed too (it was also image-frozen). §7 pins hurl staying OUT of the runtime env, and both new
    checks fail on a swap mutation with a byte-identical restore. The skill's step 5 names the two
    ungated sites (frankenphp, awscli).
  - hurl is exempt by name, and is the floor. Its binary is compiled by the image, so its pin must come
    from the same build (install-hurl.sh FATALs on a build/pin mismatch). Plumbing it would turn every
    env-only hurl bump into a failed 00base boot.
  - The old CLAUDE.md line "a hurl bump … until then 00base WARNs" was wrong. That WARN is for images
    built before step 14c; an env-only hurl bump changes nothing until the rebuild.
- **P3 fixes:** named FATALs at `install-go.sh` `_go_sha=` ("cannot fetch the published SHA-256") and
  at `install-mise.sh`'s first `_mise_got=` (the capture now sits inside its `if`). Tests 63n and 64g2
  were red before for exactly that reason: the state was safe but the log had no FATAL line. The stale
  install-tools symfony comment now says what the `cd` still guards; no cwd-relative write remains.
- **Images:** `subversion` is dropped from the 01caddy, 01httpd and 01nginx Dockerfiles. `svn` has no
  user left in any of their trees, dist/bin or http-common. hadolint output is unchanged.
- **Docs:**
  - `.env`: go/zig/mise reinstall on restart; hurl only with a 00base rebuild; both Rust pins feed the
    hurl-build stage (386 s); the ModSecurity note describes the boot-time build, and its two conf
    paths are corrected. env-update still parses all seven records.
  - `/bump-versions` step 5 no longer advises deleting a marker or setting RELOAD, and sorts pins into
    restart vs rebuild.
  - BLAST-RADIUS and the env-scan tip name `LOCAL_RELOAD_FLUTTER3_41_9`.
  - This plan: the line-513 claim is corrected, the Files cells of rows 14 and 17 are completed, and
    the RELOAD question moved to Needs input.
  - CLAUDE.md (hand-off): restart vs rebuild plus the tranche-3 end state, 1063 tests with a §70-§77
    sentence, the §58 model, plumbing §7, and the local flutter switch.
- **Results:** startup-prologue 1063/1063, plumbing 21/21, `config -q` rc 0.
- **UNCERTIFIED-BY-EXECUTION:**
  - The `subversion` removal and the 00base runtime env. The images are not rebuilt and 00base is not
    restarted; the plumbing is proven by `docker compose config` resolution only.

### Step 27 — milestone panel over tranches 2+3 (frozen commit; two consecutive clean rounds, cap 5)

**Certification honesty:** every step is proven by stubbed full-script runs + sabotage in
`startup-prologue.test.sh`, and by a throwaway-container run against a scratch `tools/` where the image
exists. No step is proven by a live bring-up; the web servers and php.edge are UNCERTIFIED-BY-EXECUTION
until the developer rebuilds.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Inventory A (254 annotated pins + aliases) and B (every consumer) | M | done | - | .env |
| 2 | Per-pin reinstall-on-bump trace + gate probes | L | done | - | docker/config/dist/bin/** |
| 3 | Findings report, graded per var | M | done | - | var/claude/** |
| 4 | Pass 2: every non-apt install site honours its pin; anything unpinned; host surface | L | done | - | var/claude/** |
| 5 | A2 phpbrew tools reachable every boot (11/12 pins) | S | done | 0f96073 | docker/config/dist/bin/phpbrew-bin/**, bin/tests/startup-prologue.test.sh |
| 6 | A1 pyenv/rbenv upgrade+downgrade, plugin reachability, fail-fast + delete-after-install | M | done | 3af3d55 | docker/config/dist/bin/pyenv-bin/**, docker/config/dist/bin/rbenv-bin/**, bin/tests/startup-prologue.test.sh |
| 7 | rustup-init honours pin both ways, reachable, marker from installed binary | M | done | da33555 | docker/config/dist/bin/rust-bin/**, bin/tests/startup-prologue.test.sh |
| 8 | Host claude = container-only pin (comment + .env note) + no-ordered-comparison guard | S | done | 90e25db | templates/shell/global-unu.sh, .env, bin/tests/startup-prologue.test.sh, docker/config/dist/bin/rust-bin/** |
| 9 | Docs: CLAUDE.md manager-reinstall claim (hand-off) | S | done | 81c3dcc | CLAUDE.md, bin/tests/startup-prologue.test.sh |
| 10 | Tranche 2: plan the delete-before-install sites (nvm/phpbrew/sdkman/fvm/android/rbenv-plugins), composer bootstrap, env-update downgrade policy | M | done | 1906f6c | docs/plans/** |
| 11 | Runtimes nvm/php/java/flutter delete-after-install (php.edge exempt) | M | done | 902f08f | docker/config/dist/bin/base-bin/**, docker/config/dist/bin/nvm-bin/**, docker/config/dist/bin/phpbrew-bin/**, docker/config/dist/bin/sdkman-bin/**, docker/config/dist/bin/fvm-bin/**, bin/tests/startup-prologue.test.sh |
| 12 | Package slots: cleanup only after the new install succeeded | M | done | f5075ed | docker/config/dist/bin/base-bin/**, docker/config/dist/bin/rbenv-bin/**, docker/config/dist/bin/sdkman-bin/**, bin/tests/startup-prologue.test.sh |
| 13 | rbenv plugins reuse step 6's in-place tag move | S | done | 46e80a7 | docker/config/dist/bin/rbenv-bin/**, bin/tests/startup-prologue.test.sh |
| 14 | go/zig/mise/hurl: check first, then wipe and install fresh (14a/14b/14c) | L | done | 8bae406 | docker/config/dist/bin/base-bin/**, docker/images/00base/**, bin/tests/startup-prologue.test.sh, templates/shell/.profile |
| 15 | all 11 phpbrew tools: check first, then replace (15a/15b/15c) | L | done | ff79ee0 | docker/config/dist/bin/phpbrew-bin/**, bin/tests/startup-prologue.test.sh |
| 16 | android: stop wiping GRADLE_USER_HOME | S | done | 42b5eb2 | docker/config/dist/bin/android-bin/**, bin/tests/startup-prologue.test.sh |
| 17 | Docs: CLAUDE.md tranche 2 (hand-off) | S | done | 3413222 | CLAUDE.md, .claude/skills/debug-service/**, docs/BLAST-RADIUS.md, templates/tips/env-scan.md, docs/plans/**, bin/tests/startup-prologue.test.sh |
| 18 | fvm: temp-dir fetch, listing + --version, install, marker last | S | done | 033ba49 | docker/config/dist/bin/fvm-bin/**, bin/tests/startup-prologue.test.sh |
| 19 | deno + bun: pinned zip + checksum, no installer script, no pipe | M | done | a6d2e63 | docker/config/dist/bin/nvm-bin/**, bin/tests/startup-prologue.test.sh |
| 20 | rust: rustup-init checked before the wipe, rustc --version after | S | done | 5f41482 | docker/config/dist/bin/rust-bin/**, bin/tests/startup-prologue.test.sh |
| 21 | phpmyadmin: build + check in temp, then swap; SHA-tracked pin | M | done | 1f9bea5 | docker/config/dist/bin/phpmyadmin-bin/**, .env, bin/tests/startup-prologue.test.sh |
| 21b | android verify: here-strings, no SIGPIPE on a long `sdk list` (verify + version read) | S | done | 9924ec6 | docker/config/dist/bin/android-bin/**, bin/tests/startup-prologue.test.sh |
| 22 | caddy: xcaddy local build, composite gate, list-modules check | M | done | 8bc5158 | docker/config/dist/bin/caddy-bin/**, docker/images/01caddy/**, .env, bin/tests/startup-prologue.test.sh |
| 23 | httpd + shared ModSecurity: archive tarballs + sha256, composite gate, build check | L | done | f49f7d7 | docker/config/dist/bin/httpd-bin/**, docker/config/dist/bin/nginx-bin/global-stack-nginx-iou-common.sh, docker/config/dist/bin/nginx-bin/global-stack-nginx-start.sh, .env, bin/tests/startup-prologue.test.sh |
| 24 | nginx: PGP-verified tarball, connector in temp, composite gate, build check | M | done | 82a3524 | docker/config/dist/bin/nginx-bin/**, bin/tests/startup-prologue.test.sh |
| 25 | php.edge: post-build php check before the sidecar marker | S | done | b273b9c | docker/config/dist/bin/phpbrew-bin/**, bin/tests/startup-prologue.test.sh |
| 26 | Docs + tranche-2 panel findings (CLAUDE.md hand-off, skill, .env comments, P3s) | M | done | 293a8d0 | CLAUDE.md, .env, .claude/skills/bump-versions/**, docs/plans/**, docs/BLAST-RADIUS.md, templates/tips/env-scan.md, docker/config/dist/bin/base-bin/**, docker/config/dist/bin/phpbrew-bin/**, docker/images/00base/**, docker/images/01caddy/**, docker/images/01httpd/**, docker/images/01nginx/**, bin/tests/** |
| 27 | Milestone panel over tranches 2+3 (frozen commit, two clean rounds) | M | todo | - | var/claude/** |
<!-- /progress-block -->
### Blocked
### Needs input
- RELOAD semantics (moved from Known issues at step 26): `RELOAD_NODE` / `RELOAD_JAVA` / `RELOAD_FLUTTER=true`
  (and `GLOBAL_STACK_LOCAL_RELOAD_FLUTTER3_41_9`, which feeds the same container switch) remove the version
  marker only; the gate says `install`, the installer finds the version already on disk and no-ops, so these
  do NOT reinstall (the php and `RELOAD_FVM` flags do wipe). Found at step 11 3C. Not a pin-bump path — a pin
  bump reinstalls through the gate. Your call: should RELOAD mean a real wipe for these three?
- Resolved and moved to the Decisions Log: A1–A7/B/C ordering and tranche-1 approval (steps 5–9 landed),
  host claude (keep auto-update), env-update downgrade policy (rule 5 stays SKIP, 23:40).
### Needs research
### Fragile
- [2026-09-24 22:13] startup-prologue.test.sh 43q (android verify probe) went red ONCE in a full run —
  `1| ndk-bundle|none` — then green in the immediate rerun (672/672) and 20/20 in an isolated loop of the
  shipped `_andv_probe`. Not caused by tranche 1: no android file touched, §43 runs before §55-§57. No OOM in the
  kernel log; load average ~22-24 at the time. Cause UNKNOWN — watch for a repeat before calling it a flake.
  On a repeat, capture `_andv_probe`'s raw `${out}` (the xtrace of every `android sdk install` the stub got)
  to a file BEFORE it is parsed — `1| ndk-bundle|none` cannot say whether ndk-bundle ever reached the stub.
  RESOLVED 2026-09-26 (repeat: 43ac `1| ndk-bundle|none`, then 43aa `1| build-tools/36.1.0|none` in a §43-only run):
  NOT a test flake — the SHIPPED verify tested each id with `printf '%s\n' "${_installed}" | grep -qF` under
  pipefail; grep -q exits on its first match and a printf still writing dies of SIGPIPE [Verified: PIPESTATUS
  `141 0` on 3/3 runs with a padded listing; 4 false-absent in 3000 unpadded runs at load ~30, 0 with a
  here-string]. A real 04android reinstall could FATAL a good SDK the same way. Fixed with a here-string; 43ad
  pads the stub listing past the pipe buffer so the piped shape reds on every run (3/3 before, 3/3 green after).
  The same sweep over `dist/bin` found one other `| grep -q` (`base-import-pg-project-dump-if-database-empty.sh:13`):
  it matches psql's LAST line, so grep reads everything first, and it has no callers — left as is.
  Second instance, found by the 6C advisor one screen down: the platform-tools version read was
  `printf | awk '… { print $2; exit }'` inside `$(…)` under set -e, so a SIGPIPE ABORTED setup. mawk reads in
  large blocks, so 3000 lines never showed it; 60000 did [Verified: rc 141 on 3/3, host and 04android image].
  Here-string too; 43ae (60000-line listing) red 3/3 before, green 3/3 after.
### Known issues
- mise deletes `MISE_DATA_DIR`/`STATE`/`CONFIG`/`CACHE` BEFORE `curl https://mise.run | sh` (`install-mise.sh:18-21`) — a failed download leaves mise wiped. FIXED in 14b (`008b841`): checked before the wipe (ruling 2026-09-25 09:58). [Verified: read]
- hurl 8.0.1 cannot run in 00base: `libxml2.so.2 => not found` (26.04 ships libxml2.so.16), and upstream publishes no other Linux x86_64 build [Verified: ldd + release assets in a throwaway container]. Being fixed in step 14 (ruling 2026-09-25 09:58). FIXED in 14c (`8bae406`): the live `tools/hurl` stays broken until 00base is rebuilt; until then every 00base boot WARNs (ruling 11:47) and the developer rebuilds later (ruling 2026-09-25).
- `RELOAD_PHP=true` (`phpbrew-start.sh:43`) removes `frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-<php name>` by the
  CURRENT frankenphp pin, so a frankenphp binary built under an older pin is orphaned. Same class step 11 fixed in
  the pin-bump cleanup (`902f08f`); this one is pre-existing and not a pin-bump path. Logged, not fixed.
- A symfony-cli or fabpot release that ships no `checksums.txt`, or one that does not list the linux asset, is now
  REFUSED at boot (named FATAL, old copy kept) where the old code installed it. Fail-closed by design (step 15c),
  but it constrains future pins, and env-update's `github:` fetcher cannot pre-check it (`(verify-asset:)` is
  `url`-only, row 42). Step 17 hand-off material.
- `templates/shell/global-unu.sh:524` pipes `curl -sSL https://claude.ai/install.sh | bash` on the HOST: the same
  class step 15c removed from 02phpbrew (mago/castor). Host surface, outside tranche 2; logged, not fixed.
- `/new-service` (`.claude/skills/new-service/SKILL.md`) scaffolds a startup script with NO version gate at all
  (`grep -c gs_version_gate` → 0), so a service created from it never reinstalls on a pin bump. Step 17 material.
- A consumer container that is ALREADY running when its runtime reinstalls keeps a PATH baked at its own
  boot and loses the old version dir under it. Starting consumers are safe: they wait on
  `successes/<rt>.<AS>`, which the runtime removes before its gate runs [Verified: alltogether `:19-28`,
  phpmyadmin `:13-15`, serverless `:18-25`, android `:58-62`]. Same as before tranche 2.
- `source <file> && <cmd>` (20 lines in 5 files of dist/bin, 2026-09-24): if `source` fails, neither `set -e`
  nor the ERR trap fires (only the final member of an && list does) — `<cmd>` is silently skipped and the script
  continues. pyenv/rbenv's post-install cleanup now proves the install on disk (§57h); the other sites are
  unaudited. Narrow trigger (a shellrc missing while its manager's success marker exists), silent when it fires.
- Tranche-1 milestone live read (2026-09-24, read-only): pyenv at v2.8.6 = tag = marker; rbenv at v1.3.2 = tag =
  marker; ruby-build v20260917 and gemset v0.5.102 checked out = markers = pins; rustup 1.29.1 = marker. So the
  first boots after tranche 1 make no network call; `02rust` only writes `auto_self_update = "disable"`.
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
- TRANCHE 2 (per ruling 14:35, not yet planned): delete-before-install at `nvm-start.sh:72`,
  `phpbrew-start.sh:62`, `sdkman-start.sh:78`, `fvm-start.sh:28,43`, `android-start.sh:169`; slot-package
  DOWNGRADES (`--cleanup-command` for sdkman `sdk uninstall` / gem uninstall) are decision-bidirectional via
  `gs_version_gate` but the install side was never tested downward in either pass (e.g. `sdk uninstall` of the
  current default may refuse). rbenv plugins (`rbenv-iou.sh` ruby-build/gemset arms) `rm -rf plugins/<p>`
  then `git clone` — same delete-before-install shape, REACHABLE since step 6 on every plugin bump: a failed
  clone leaves ruby-build gone until the next boot retries (loud — no marker write — not silent). Also: `phpbrew-install-tools.sh:24-25` bootstraps composer with
  `composer-setup.php` and NO `--version` → `${COMPOSER_HOME}/bin/composer` floats to latest (it builds the
  pinned clone at `:30` and runs `phpbrew-iou.sh:24`; live 2.10.3 equals the pin only by coincidence;
  no installer checksum) — recorded in `pass2/raw/B_piped.md:24` but missing from pass-2 REPORT.md.
- D doc claims refuted: CLAUDE.md android launcher "yields 1.0.15985488"; CLAUDE.md frankenphp gotcha, RELOAD "full unconditional reinstall", "manager-only
  reinstall"; `rbenv-iou.sh:15-19` comment; MASTER.plan.md:1487 MCP "dead"; `.env:277` MODSECURITY_LIB note.
