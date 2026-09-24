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
  re-wipes: the retry converges [Inferred from the code path; not executed]. §60: 34 checks; sabotage
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
- sdkman may refuse to uninstall the version that is still the default; if a probe shows it, `sdk default
  <new>` precedes the cleanup. UNCERTIFIED until probed.
- Certification: real `pip install pkg==<lower>` and `npm add -g pkg@<lower>` downgrades in scratch dirs
  (the two slot commands with no cleanup) [Unverified until run]; `sdk uninstall` of the version that was
  the default before the new install — probed with a real sdkman in a scratch `SDKMAN_DIR` if the download
  is reasonable, otherwise named UNCERTIFIED.

### Step 13 — rbenv plugins: reuse step 6's in-place move (S)
- `rbenv-iou.sh` ruby-build/gemset arms `rm -rf plugins/<p>` then `git clone` [Verified: read]. The plugins
  are git clones at tags — the same object as rbenv itself — so they get step 6's certified block: `.git`
  absent → clone; present → `rev-parse HEAD` vs `refs/tags/<pin>^{commit}`, fetch + `checkout --force` only
  when they differ. No `.new` state, no second shape. (advisor 3C round 1)
- Test §62 on §56's real-git fixture, plugin arms: pin up / down → at the tag; current → no fetch; unknown
  tag → fails, plugin dir intact.

### Step 14 — go / zig / hurl: staged extract, verify, swap (M)
- Today each extracts OVER its tree (`install-go.sh:19`, `install-zig.sh:13`, `install-hurl.sh:17`)
  [Verified: read] — stale files survive, both directions. New, per the 15:05 clean-wipe ruling: extract into
  `<dir>.new`, check the binary's `version` output names the pin, then remove the old tree and `mv` the new
  one into place; marker last. A failed download/extract leaves the old tool working.
- go: GOPATH is `go/home`, INSIDE GOROOT (`.env:350-351`) [Verified]. RULING NEEDED (it amends 15:05's
  "wipe"): (i) staged swap MOVES `home` into the new tree — `go install`ed binaries + module cache survive,
  no `.env` change; (ii) full wipe including GOPATH on every go bump; (iii) move GOPATH out of GOROOT
  (`.env` + shellrc + consumers).
- The `rm -rf <dir>` → `mv <dir>.new <dir>` swap is a sub-second window in which `tools/<tool>` is absent for
  anything with it on PATH (host included) — accepted. `sudo` on tar/chmod/chown applies to the `.new` tree.
- Test §63: stub `curl` serving fake tarballs whose binary prints its version; up / down / failed download /
  GOPATH survives / leftover `.new` cleared. Certification: real go, zig, hurl downloads into scratch dirs,
  up then down.

### Step 15 — composer bootstrap pinned (S)
- `phpbrew-install-tools.sh:24-25` runs `composer-setup.php` with no `--version` → latest [Verified: pass 2
  raw B_piped.md:24]. Add `--version="${COMPOSER_LATEST}"` (the installer's documented flag) and check
  `composer --version` = pin before building the clone (pin is a bare `2.10.3`, taken verbatim [Verified]). Optional, same step: verify the installer's SHA-384
  against `composer.github.io/installer.sig` (security, not pin correctness).
- Test §64 (red first): stub `php` recording the setup args; missing/ignored `--version` reds.

### Step 16 — android SDK (M/L) — DESIGN FORK, needs a ruling
- Any change to the 14 SDK inputs wipes `ANDROID_HOME`, `ANDROID_SDK_HOME`, `ANDROID_SDK_ROOT` AND
  `GRADLE_USER_HOME` before a 15+ min multi-GB install (`android-start.sh:168-176`) [Verified: read]. A failed
  install leaves no SDK (the container stays up in `sleep infinity`, unhealthy with an error token).
  Two independent axes: (a) stop wiping `GRADLE_USER_HOME` (Gradle's build cache, unrelated to any SDK pin)
  — cheap; (b) staged install into `${ANDROID_HOME}.new` + verify + swap, so the old SDK stays usable until
  the new one is proven — costs a second full SDK on disk during the install. The AVDs under
  `ANDROID_SDK_HOME` are recreated by `setup-dist.sh` every boot, so (b) leaves them to that step rather
  than staging them [Inferred from §43's `_andd_probe`; to confirm]. Choices: (a) alone / (a)+(b) / leave.

### Step 17 — docs (S)
CLAUDE.md hand-off (runtimes now delete-after-install; staged go/zig/hurl; the php.edge exception), memory.

### Not in tranche 2 (still open from the audits)
A3 FRANKENPHP launch skip; A4 caddy plugin pins; A5 nginx/httpd modules; A6 `make rebuild` not pushing;
A7 SDKMAN installer hardcoding 5.23.0; PARTIAL: fvm unplumbed var, nvm raw-pin (latent), yarn patch,
groovy/spark depends_on; B `|| echo` / `curl -L` without `-f` in 00base, phpbrew ext exit-0; C RELOAD_*
escape hatches keeping pkg markers; the `source X && cmd` class.

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
| 11 | Runtimes nvm/php/java/flutter delete-after-install (php.edge exempt) | M | done | 80415c0 | docker/config/dist/bin/base-bin/**, docker/config/dist/bin/nvm-bin/**, docker/config/dist/bin/phpbrew-bin/**, docker/config/dist/bin/sdkman-bin/**, docker/config/dist/bin/fvm-bin/**, bin/tests/startup-prologue.test.sh |
| 12 | Package slots: cleanup only after the new install succeeded | M | todo | - | docker/config/dist/bin/base-bin/**, bin/tests/startup-prologue.test.sh |
| 13 | rbenv plugins reuse step 6's in-place tag move | S | todo | - | docker/config/dist/bin/rbenv-bin/**, bin/tests/startup-prologue.test.sh |
| 14 | go/zig/hurl staged extract-verify-swap, GOPATH carried across | M | todo | - | docker/images/00base/**, bin/tests/startup-prologue.test.sh |
| 15 | composer bootstrap pinned + verified | S | todo | - | docker/config/dist/bin/phpbrew-bin/**, bin/tests/startup-prologue.test.sh |
| 16 | android: stop wiping GRADLE_USER_HOME | S | todo | - | docker/config/dist/bin/android-bin/**, bin/tests/startup-prologue.test.sh |
| 17 | Docs: CLAUDE.md tranche 2 (hand-off) | S | todo | - | CLAUDE.md |
<!-- /progress-block -->
### Blocked
### Needs input
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
### Known issues
- `RELOAD_NODE` / `RELOAD_JAVA` / `RELOAD_FLUTTER=true` remove the version marker only. The gate then says
  `install`, the installer finds the version already on disk and no-ops, so these RELOAD flags do NOT
  reinstall anything (the php and `RELOAD_FVM` flags do wipe). Found at step 11 3C; not fixed (it is not a
  pin-bump path). Needs a ruling if RELOAD should mean a real wipe for these three.
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
