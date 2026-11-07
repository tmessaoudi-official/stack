# Local registry lifecycle — survive soft-restart, self-heal, fail loudly

## Status

- **State**: steps 1–8 committed in `34a2001`. Round 1 of the milestone panel found 13 items and
  the refuters upheld 12 (the P1 at 5/5); they were fixed in `ff738d5`. Round 2 on `ff738d5`
  found 10 more, all upheld; the code fixes are in `a33c718` and the CLAUDE.md half in
  `63e98a9`. Round 3 on `63e98a9` found 8; the refuters upheld 7 (1 P2, 6 P3) and refuted one
  (the wait cost, already bounded at line 12), and all 7 are fixed in the commit after
  `63e98a9` ("fix: close the registry panel round 3 findings"). Panel round 4 comes next; the
  milestone needs two consecutive clean rounds. Then step 9, the live recovery (the developer's).
- **Panel round 3 fixes**: `up` no longer depends on `generate-buildx` (its first line deletes
  the bake file, so a broken `bake --print` could only stop `down-n-up` after its `down`);
  `.NOTPARALLEL:` keeps "ensure before down" true under `MAKEFLAGS=-j`; the `getent` operand is
  quoted (an empty alias used to enumerate and pass); the getent stub answers like glibc; the
  design section, this Status, a stale `Makefile:306` citation in `opt-developer-updater.plan.md`
  and `templates/tips/docker-local-registry.md` are corrected.
- **Panel round 2 fixes**: the registry check runs before any teardown (the first prerequisite of
  every down-n-* composite, and before soft-restart's `down`); `start-local-registry` checks that
  the alias resolves before any cert, root or daemon step; the curl-6 hint continues with
  `make ensure-local-registry`; both curl probes are bounded (`--connect-timeout 2 --max-time 5`);
  executed e2e cases now prove the no-teardown guarantees; plan, MASTER and BLAST-RADIUS
  statements are corrected.
- **Panel round 1 fixes**: the stub pins the `container ls` argv; `create` no longer swallows a
  failed query; curl exit 6 → `/etc/hosts` hint, not a rotation; `up` and soft-restart run
  ensure before `up`; soft-restart refuses an empty tools path; `build` points at ensure and
  says the stack is DOWN after a failed build; soft-restart has an executed e2e; stale hints
  and `--publish` pointers fixed; stack-ask-human lists the two daemon-restarting targets.
- **Size**: Large
- **Mode**: spec (the `ah` gate fired for this session)
- **Evidence** (round-3 fixes): `bin/tests/local-registry.test.sh` 112 / 112 (74 at `34a2001`,
  92 at `ff738d5`, 107 at `a33c718`/`63e98a9`). The sabotage series runs on a scratch copy and
  never touches the live tree; the commit message gives its mutant count and result. `makefile-posix` 10/10, `wait-healthy` 9/9,
  `check-bake-targets` 12/12, `check-image-versions` 30/30, `env-guard` 12/12; shellcheck and
  shfmt are clean. **All of it runs against stubs**: no live registry start, `make up` or
  daemon restart has run (see UNCERTIFIED-BY-EXECUTION).

### Design refinements made during implementation

- Ruled (Decisions Log, superseding 14:44): `ensure` never touches the cert — the buildx
  builder image COPYs it.
- Implementation detail, not a ruling: the logic lives in `bin/local-registry.sh ensure|create`
  rather than in recipe lines (precedent: `bin/check-bake-targets.sh` — recipes run under dash,
  and a script can be tested directly); `start-local-registry` calls `create`, so the
  `docker run` contract exists once.
- B verified without a throwaway container: `docker ps --filter volume=` matches a bind mount
  by destination AND source (probed on twes-in's live bind mount); no compose file — the
  gitignored `local.*` ones included — mounts `./tools` anywhere but `${GLOBAL_STACK_DOCKER_TOOLS_PATH}`.

### Follow-ups (logged, not in this change)

- `docker/registry/config.json` mirrors port **32728** → endpoint `:5000`, while the registry
  publishes **42728**; and `BUILDKIT_REGISTRY_CONFIG` / `BUILDKIT_EXTRA_MOUNTS` are env vars
  buildkitd does not read (the builder's Mounts list holds only its state volume). Trust works
  through the cert baked into `custom-moby/buildkit`. Looks like dead config [Inferred: not probed].
- The deployed `~/.local/bin/global-stack-make-exec.sh` is the developer's to re-deploy.
- DONE in `63e98a9` (claude-md-size landed as `6d78c5d`, meeting the 15:48 condition):
  the `CLAUDE.md` § Gotchas port-var bullet now names `bin/local-registry.sh` as the `--publish`
  consumer, and § Build chain covers `make up`, the composites' check before `down`, and the
  `/etc/hosts` prerequisite.
- `ensure` never re-creates a running registry whose image is an older
  `GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION` or whose port differs from `.env.local`; it
  waits, then fails with the rotation hint. Pre-existing (panel round 1, observation O2).
- `hard-restart` still calls its sub-makes with `--ignore-errors --keep-going`
  (`start-local-registry`, `create-buildx-builder`, `build`, `up`), so INSIDE hard-restart a
  failed `ensure-local-registry` or bake is still swallowed and `up` still runs, and an alias
  that does not resolve fails `start-local-registry`'s `getent` check only to have the
  openssl, CA-install and daemon-restart lines run anyway (the "refuses before touching
  anything" in CLAUDE.md § Build chain holds for a direct `make start-local-registry` only).
  Pre-existing; the wrapper fix does not reach it (panel round 3 observation).
- Observed while verifying: `make -n <target>` is not side-effect free here — `$(MAKE)` lines
  execute under `-n`, and `generate-buildx` redirects one into `${BUILDX_BAKE_FILE}`, so a
  dry run overwrites `docker-bake.local.json` with printed commands (harmless: regenerated by
  every consumer).

## Problem (root cause, diagnosed 2026-11-07)

`global-stack-start.sh` failed with `dial tcp 127.0.0.1:42728: connect: connection refused`
(buildkit log 13:04–13:07 UTC) because the local registry container had been dead since
10:42:57 CET. The chain, every link observed:

1. `make soft-restart` (run from `/dev/pts/0`, the developer's terminal, confirmed by the
   developer) executed `docker ps -q | xargs -r docker stop` (`Makefile:317`). That line was
   added by `664b215` (2026-09-10) **for hard-restart's prune**; soft-restart has no prune, so
   in soft-restart its only effect beyond the stack is to stop the registry, the buildx builder
   and every other project's containers.
2. soft-restart never runs `start-local-registry`. `--restart=always` does not revive an
   explicitly stopped container while the daemon stays up (`RestartCount=0`, `Exited`,
   daemon PID unchanged since 09:38:33).
3. soft-restart's `make up` succeeded because the images were already in the local store, so
   the dead registry stayed invisible until the next build.
4. The build's registry gate (`Makefile:195-196`, `1da23a3`) printed FATAL, but
   `global-stack-make-exec.sh` passes `--ignore-errors --keep-going`, so make carried on into
   `up-build-force-recreate` and the wrapper exited **0** (scratchpad probe: a failing gate
   followed by `after: STILL RAN`, exit 0; without the flags, exit 2).

The phpbrew Dockerfile edit is not causal — it only made a build happen.

## Design (agreed)

### A. `ensure-local-registry` — idempotent, self-healing, never rotates (as built)

The 14:44 draft had a cert-rotating ensure and a `rotate-local-registry-cert` target. The
14:52 ruling SUPERSEDES it: the buildx builder image COPYs the cert at image build time, so a
rotation without `make create-buildx-builder` breaks trust. Ensure therefore never touches
the cert, and there is no rotate target. What was built (`bin/local-registry.sh ensure`,
called by the Makefile target):

| Registry container (`docker container ls --all --filter name=^/<name>$ --format {{.State}}`) | Action |
|---|---|
| `running` / `restarting` | wait for `/v2/` |
| `exited` / `created` | `docker start`, wait |
| `paused` | `docker unpause`, wait |
| missing, cert + key on disk | `bin/local-registry.sh create` (`docker run`, the old Makefile flags), wait |
| missing, no cert | FAIL → `make start-local-registry create-buildx-builder` |
| `dead` / anything else | FAIL → the same pair |
| the docker query itself fails | FAIL (never read as "missing") |

The wait polls `https://<alias>:<port>/v2/` (`GS_LOCAL_REGISTRY_WAIT_TRIES`, default 30 tries,
1 s apart, each curl bounded by `--connect-timeout 2 --max-time 5`) and FAILS if it never
answers. Worst case is a registry that accepts the connection and never answers:
30 × 5 s + 29 × 1 s ≈ 3 minutes before ensure fails. A refused port fails fast (≈ 30 s). curl's exit code picks the hint: 6 (alias does not resolve) →
add it to `/etc/hosts`; anything else → `docker logs` + the rotation pair.

- `start-local-registry` keeps its name and behaviour (new cert + CA trust + daemon restart),
  now ending in `bin/local-registry.sh create`, so the `docker run` contract exists once. It
  is always paired with `create-buildx-builder`.
- Prerequisite of `build`, `up-build`, `up-build-force-recreate` and (panel round 1,
  15:48) `up`, and the FIRST prerequisite of `down-n-up`, `down-n-rebuild` and
  `down-n-rebuild-force-recreate`, so a registry it cannot heal stops them before `down`
  (panel round 2, 16:07). The FATAL curl gate in `build` stays as the last line of defence
  and points at `make ensure-local-registry`.
- soft-restart runs `ensure-local-registry` after its two guards and BEFORE `$(MAKE) down`
  (so before the scoped stop, the `rm` and `up`), without `--ignore-errors` (panel rounds 1
  and 2).
- `.NOTPARALLEL:` makes that order hold under `-j` too (panel round 3, 16:33): prerequisites
  run in the written order only when make is serial.
- `up` does not depend on `generate-buildx` (panel round 3, 16:33): its first line deletes the
  bake file, so the prerequisite did no work and let a broken `bake --print` stop `down-n-up`
  after its `down`. `build` and `up-build*` keep it; in `down-n-rebuild*` a broken bake is
  the build-failure path ("the stack is DOWN"), and `make up` recovers.

### B. soft-restart stops only what holds `tools/`

`docker ps -q --filter volume=${GLOBAL_STACK_DOCKER_TOOLS_PATH} | xargs -r docker stop`,
after a guard that refuses an empty `GLOBAL_STACK_DOCKER_TOOLS_PATH` (an empty filter matches
nothing and the holders would stay up under the rm — panel round 1).
hard-restart keeps the host-wide stop (its prune needs it — `664b215`).

### C. The wrapper stops swallowing top-level failures

`templates/shell/global-stack-make-exec.sh`: drop `--ignore-errors --keep-going` (keep
`--silent --warn-undefined-variables`). The inner `docker-cli` sub-makes keep their own flags.
The deployed copy in `~/.local/bin/` is the developer's to re-deploy
(`cp templates/shell/global-stack-make-exec.sh ~/.local/bin/`).

## Steps (test-first)

1. **Red**: `bin/tests/local-registry.test.sh` — copy-to-tempdir sandbox (the
   `wait-healthy.test.sh` pattern) with stub `docker`/`curl`/`openssl`/`sudo` recording calls.
   Cases: each row of the state table; poll timeout fails non-zero; a valid cert is never
   rewritten and the daemon is never restarted on the start/run paths; soft-restart's stop is
   mount-filtered and never names the registry; `build` lists `ensure-local-registry` as a
   prerequisite. Confirm each fails for the stated reason.
2. **Red**: wrapper case — `global-stack-make-exec.sh` against a sandbox Makefile whose gate
   fails → wrapper exits non-zero and the next target does not run.
3. **Probe before relying on B**: prove `docker ps --filter volume=<path>` matches a **bind**
   mount. Done without a throwaway container: a read-only query against twes-in's existing live
   bind mount matched by both source and destination (see Design refinements).
4. Implement A, B, C. Green.
5. Prove the three wrapper targets (`down`, `down-n-up`, `down-n-rebuild-force-recreate`) do
   not depend on `--ignore-errors` at top level: sandbox run with stub docker, success path.
6. Sabotage: break the ensure state test (e.g. make the stopped branch `docker run`), the
   mount filter, and the wrapper flag — each must redden its assertion.
7. `bash bin/tests/makefile-posix.test.sh`, `bash bin/tests/wait-healthy.test.sh`, `/lint`.
8. Docs: `docs/BLAST-RADIUS.md` soft-restart row; CLAUDE.md `make soft-restart` gotcha +
   Common Workflows (`ensure-local-registry`, and `start-local-registry create-buildx-builder`
   as the rotation pair — there is no rotate target, 14:52); `.claude/rules/host-tooling.md`
   test entry.
9. Live recovery (developer runs or approves): `make ensure-local-registry` → `docker start`
   path, then `global-stack-start.sh`.

## Risks

- An ensure bug blocks every build → step 1 covers every branch before any live use.
- **Cert rotation and the builder** — resolved at step 4: the planning-time guess that the
  builder bind-mounts the `.crt` was wrong. `docker/buildkit/Dockerfile` COPYs the cert into
  the `custom-moby/buildkit` image, and the builder's only mount is its state volume, so a new
  cert is trusted only after `make create-buildx-builder`. Hence the 14:52 ruling: ensure
  never rotates, and rotation is always the explicit pair.
- Dropping the wrapper flags may expose a top-level line that fails routinely → step 5.
- `soft-restart` ordering: the mount-filtered stop must still precede `sudo rm -rf tools`.

## Rollback

`git revert <sha>`; re-deploy the old wrapper from git; the registry container itself is
untouched by the change (same name, flags, data and cert paths).

## UNCERTIFIED-BY-EXECUTION (expected)

Everything runtime: the ensure, create and soft-restart paths are proven ONLY against stub
`docker`/`curl`/`sudo`/`getent`. Not run: a real `docker start` of the exited registry (step 9,
the developer's), a real /v2/ answer, buildkit trusting the registry, a real `docker stop` of the
tools holders, `make up` coming up healthy, and a cold `make hard-restart`.

## Decisions Log
- [2026-11-07 14:44] AGREED: Registry lifecycle via an idempotent ensure-local-registry target (start if stopped, create if missing, rotate cert only if absent/expiring, poll /v2/), prerequisite of build/up-build/up-build-force-recreate; cert+daemon restart split into rotate-local-registry-cert.
- [2026-11-07 14:44] AGREED: soft-restart stops only containers mounting GLOBAL_STACK_DOCKER_TOOLS_PATH (docker ps --filter volume=); hard-restart keeps its host-wide stop for the prune (664b215).
- [2026-11-07 14:44] AGREED: Drop --ignore-errors --keep-going from global-stack-make-exec.sh only (inner docker-cli sub-makes keep theirs), proven by sandbox tests over the three wrapper targets first.
- [2026-11-07 14:47] AGREED: Go given; certification tier = advisor() at 3C/6C plus one three-lens panel on the frozen commit at the end.
- [2026-11-07 14:52] AGREED: SUPERSEDES the 14:44 registry-lifecycle entry: ensure-local-registry never touches the cert (the buildx builder image COPYs it, so a rotation needs create-buildx-builder). running+answers -> ok; stopped -> docker start; missing+cert -> docker run; cert absent -> fail naming 'make start-local-registry create-buildx-builder'; running but silent -> fail with a logs hint. No rotate-local-registry-cert target; start-local-registry stays the rotate path; the Makefile:199 hint and CLAUDE.md first-build line name both targets.
- [2026-11-07 14:52] AGREED: Wrapper stops on the first failure (no --ignore-errors, no --keep-going): a failed service build aborts global-stack-start.sh before up, non-zero exit.
- [2026-11-07 15:48] AGREED: Panel round 1 fixes: ensure-local-registry becomes a prerequisite of up, and soft-restart runs it (without -i) BEFORE $(MAKE) up — down-n-up and soft-restart can no longer hit connection refused; make up now fails loudly when the registry cannot be made reachable.
- [2026-11-07 15:48] AGREED: CLAUDE.md:370 --publish pointer is NOT edited this round (another session holds uncommitted CLAUDE.md edits, claude-md-size); logged as a follow-up.
- [2026-11-07 15:48] AGREED: Fix round certified by: fixes test-first + sabotage, follow-up commit (no amend), then the full three-lens panel until two consecutive clean rounds.
- [2026-11-07 16:07] AGREED: Panel round 2 N1: the registry check runs BEFORE any teardown — ensure-local-registry is the first prerequisite of down-n-up, down-n-rebuild and down-n-rebuild-force-recreate, and soft-restart runs it before its down; a broken registry fails with the stack untouched.
- [2026-11-07 16:07] AGREED: Panel round 2 N3: start-local-registry first checks that the registry alias resolves (getent hosts) and fails before any cert, root or daemon-restart step; ensure's curl-6 hint continues with make ensure-local-registry, never a rotation.
- [2026-11-07 16:33] AGREED: Panel round 3, R3-I1 (P2): drop generate-buildx from up's prerequisites. up deletes the bake file on its first recipe line, so the prerequisite only let a broken 'bake --print' stop down-n-up after down. down-n-rebuild* keep the build-failure path (the stack is DOWN, then make up recovers).
- [2026-11-07 16:33] AGREED: Panel round 3, R3-I2 (P3): add a global .NOTPARALLEL: so 'ensure before down' (and down before up) hold under MAKEFLAGS=-j. Rejected .WAIT, because GNU make before 4.4 errors on it.

