# Container Sweep — all 46 containers + `tools/elapsed`

## Metadata

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Scope | all 46 containers (44 stack services + registry + buildx builder) + `tools/elapsed` |
| Nature | **READ-ONLY** — nothing was changed; `git status --porcelain` empty before, during and after |
| Logs analysed | 77.7 MB, stdout **and** stderr |
| Stack version | `2_0_0_local` |
| Total findings | **21** (P1: 1 · P2: 5 · P3: 13 · Notable: 2) |
| Actionable | 7 of 21 |
| Status | No issue here is urgent. The stack works. This is a backlog document for a later session. |

---

## 1. Method & coverage

| What | How |
|---|---|
| Containers enumerated | `docker ps -aq` → 46 (44 stack services + local registry + buildx builder) |
| Logs analysed | 77.7 MB, **stdout AND stderr**, for all 44 `global_stack-*` services |
| Non-stack containers | separate pass over `local-global-stack-registry` and `buildx_buildkit_docker-buildx-builder0` |
| xtrace noise | stripped with `grep -avE '^\++ '` before histogramming, so `set -x` lines don't drown real output |
| Health markers | `tools/successes/` and `tools/errors/` read with shell builtins (`[ -e ]`), never rtk-rewritten `ls` |
| Defined-vs-actual services | `compose config --services` vs `compose ps -a --format '{{.Service}}'` |
| Env consistency | key-set comparison under `LC_ALL=C` |
| Version markers | `tools/versions/*` content-compared against the live env values |
| Compose validation | `env -i HOME=$HOME PATH=$PATH docker compose --env-file .env.local config -q`, stderr captured |

### Deliberately NOT run

- **`bin/env-scan.sh --dry-run`** — it has a backup pre-flight phase that writes to disk. A pure read-only key comparison was substituted instead.
- **Any `make` target**, any restart, any prune. `bin/check-image-versions.sh` was grepped for write patterns *before* being executed.

---

## 2. Summary — 21 findings

**7 actionable · 14 informational (explained, no action needed).**

| # | Band | Finding | Action? |
|---|---|---|---|
| 1 | **P1** | `04android`: `avdmanager` resolves the SDK root one level too high | **yes** |
| 2 | P2 | `phpbrew ext install` exit code is trusted but untrustworthy (swoole is the known instance) | yes (latent) |
| 3 | P2 | Log rotation absent on 39 of 44 containers | **yes** |
| 4 | P2 | Security-flavoured warnings (6 services) | partly |
| 5 | P2 | `02rust` yanked crates | no — expected |
| 6 | P2 | 16 dangling images, 793 MB | **yes** (trivial) |
| 7 | P3 | `successes/serverless` written with a hardcoded literal, not the token var | yes (hygiene) |
| 8 | P3 | `sed` EBUSY in 9 containers | no |
| 9 | P3 | `02keycloak` DEBUG log level | no — intentional |
| 10 | P3 | `01valkey` Tini / PID 1 | no — upstream |
| 11 | P3 | `01mariadb13` `memory.pressure` not writable | no — upstream |
| 12 | P3 | `01caddy` stop-API connection refused | no — startup order |
| 13 | P3 | `02dpage-pgadmin4` SyntaxWarning | no — upstream |
| 14 | P3 | `02sonarqube` JDK deprecations | no — upstream |
| 15 | P3 | `03flutter3` git cache recreate | no — self-healing |
| 16 | P3 | `01postgres18` first-run relation errors | no — expected |
| 17 | P3 | `02mongoclient` RestartCount=1 | no — restart policy |
| 18 | P3 | Registry 404-shaped `level=error` lines | no — normal push probes |
| 19 | P3 | BuildKit warnings | no — expected config |
| 20 | Notable | Postgres collation fixed → a CLAUDE.md caveat is now **stale** | **yes** (doc) |
| 21 | Notable | `tools/elapsed` mtime anomaly explained | no |

---

## 3. Clean baseline — what is genuinely healthy

All **[Verified]**:

- 46 containers, **all running**. 44 stack services **all healthy**. Registry and buildkit have no healthcheck, which is expected.
- `tools/errors/` is **empty**.
- 44 success tokens == 44 `tools/elapsed` entries. Perfect correspondence.
- No `OOMKilled`. No non-zero exit code anywhere.
- CPU idle — highest is redis at 2.09%. 30 GiB RAM in use, sonarqube the largest single consumer at 1.9 GB.
- `make check-image-versions` → exit 0, **zero output** → no `.env` ↔ Dockerfile `ARG` drift.
- Clean-environment `docker compose config -q` (`env -i`, stderr captured) → exit 0, **zero bytes** → no unset-variable warnings.
- `.env` vs `.env.local` → **zero missing keys**; the 28 extras are all `LOCAL_*`, which is by design.
- **All** `tools/versions/*` markers match their env values — including all 14 android SDK inputs. **No pending reinstall is armed.**
- Every service in `COMPOSE_FILE` has a container — `config --services` vs `ps -a` produced a zero diff, so nothing is silently absent. `COMPOSE_FILE` has no trailing `;`.
- Both env files (19:48, 19:50) predate the earliest container start (20:19:49), so mid-run drift is structurally impossible.
- Disk 61% used, 351 G free.

---

# P1

## 1. `04android` — `avdmanager` resolves the SDK root one level too high

**Grade: [Verified]**

### Problem

`04android` ends up with **two** cmdline-tools trees, and they are *both* created deliberately on every SDK install:

| Path | Created by | SDK root it derives |
|---|---|---|
| `${ANDROID_HOME}/cmdline-tools/bin` | `global-stack-android-setup.sh:39-40` — unzips `commandlinetools-linux-*.zip` straight into `${ANDROID_HOME}` | `/stack/tools` ❌ |
| `${ANDROID_HOME}/cmdline-tools/23.0/bin` | `global-stack-android-setup.sh:104` — the `cmdline-tools;23.0` entry in `_pkgs` | `/stack/tools/android` ✅ |

The two launcher scripts are **byte-identical**. They resolve their location the standard Gradle-wrapper way:

```bash
cd "`dirname \"$PRG\"`/.." >/dev/null      # line 23
APP_HOME="`pwd -P`"                        # line 24
DEFAULT_JVM_OPTS='"-Dcom.android.sdkmanager.toolsdir=$APP_HOME"'   # line 31
```

…and the SDK root is then derived as `APP_HOME/../..`. From the **versioned** directory that lands on `/stack/tools/android` — correct. From the **unversioned** one it lands on `/stack/tools` — the entire shared tools volume.

`global-stack-android-start.sh:48` builds PATH with the **unversioned directory first**:

```
…:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:…:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:…
```

So a bare `avdmanager` always gets the broken one.

### Evidence

Caller confirmed by log ordering: `+ avdmanager create avd --force --name …` at line **2615**, and the warnings begin at **2616**, immediately below it.

`global-stack-android-setup-dist.sh:70` creates **3 AVDs on every container start**. Every warning count in the log divides exactly by 3, which corroborates the loop count. Per AVD create:

| Count | Warning |
|---|---|
| 23 | `Observed package id '<pkg>' in inconsistent location '/stack/tools/android/<pkg>' (Expected '/stack/tools/<pkg>')` |
| 45 | `Invalid package.xml found` |
| 45 | `Found corrupted package.xml` |
| 27 | `package.xml parsing problem. DOCTYPE is disallowed…` |
| 15 | `package.xml parsing problem. unexpected element (uri:"http://pear.php.net/dtd/package-2.0", local:"package")` |
| 3 | `package.xml parsing problem. unexpected element (uri:"", local:"package")` |
| 6 | `Error: Could not load devices from …/devices.xml` |

Totals in the current log: 69 / 135 / 135 / 81 / 45 / 9 / 18 — i.e. exactly three boots' worth.

**The `Expected` path is the proof.** It asks for `/stack/tools/platforms/android-37.1`, with no `android/` segment. That is only possible if the tool believes the SDK root is `/stack/tools`.

**The PEAR line is the smoking gun.** 15 warnings per run are `avdmanager` parsing *phpbrew's* PEAR `package.xml` — `uri:"http://pear.php.net/dtd/package-2.0"` — as though it were an Android repository descriptor. It is walking the whole shared tools volume.

### Impact

Cosmetically: ~250 warning lines per boot. Functionally: the AVDs are created (the 3 `create avd` calls succeed), but `avdmanager` cannot read `devices.xml`, so device-profile resolution is degraded. This repeats on **every single container start**, not only on reinstall.

Worth stating precisely: `global-stack-android-setup.sh` itself is **correct** — it passes the global `android --sdk="${ANDROID_HOME}"` at all three call sites, exactly as row 31 fixed. Only the bare `avdmanager` in `setup-dist.sh` is affected.

### Recommendation

Two candidate fixes, in preference order:

1. **Pass the SDK root explicitly.** `avdmanager` accepts the same global option shape as `android`. Making `setup-dist.sh:70` explicit removes all dependence on PATH ordering and on which of the two trees wins. Most robust, smallest blast radius, and matches what `setup.sh` already does.
2. **Reorder PATH** in `android-start.sh:48` so the versioned directory precedes the unversioned one. One-line change, but it fixes this *by accident of ordering* rather than by stating intent — and anything else that shells out to a bare cmdline-tool stays at the mercy of PATH.

I would take (1), and optionally (2) as belt-and-braces.

> **Correction (2026-09-14, row 47 of `docs/plans/MASTER.plan.md`): recommendation (1) does not work.**
> `avdmanager` has no usable SDK-root option — `--sdk_root` is rejected both as a global flag and
> after the verb, and `ANDROID_SDK_ROOT` in the environment alone still produced the warnings
> [Verified 2026-09-14 in the running `04android`]. What shipped instead: `setup-dist.sh` calls the
> VERSIONED binary by path, `${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin/avdmanager`
> (a real `create avd` from it printed 0 warning lines), with a named FATAL when it is missing; plus
> (2) at all five android PATH sites (both `android-start.sh` lines, both `alltogether-start.sh`
> lines, `templates/shell/profile.sh`), which also dropped three dead legacy entries. The unversioned
> `cmdline-tools/bin` stays on PATH, after the versioned one: a reinstall's bare `android` needs it
> before `<ver>` exists. `startup-prologue.test.sh` §43u–43y and §54 pin both halves.

**Do not** "fix" this by deleting `cmdline-tools/bin`. It is recreated by the unzip on every reinstall — deleting it is a change that undoes itself.

**Verification if fixed:** count `inconsistent location` in the `04android` log after one restart. Expect 0, not 69.

---

# P2

## 2. `phpbrew ext install` exit code is trusted but untrustworthy

**Grade: [Verified] — and NOTE the correction below**

### ⚠️ Correction to my first pass

My initial report claimed *"every php invocation prints `Unable to load dynamic library 'swoole.so'`"*. **That was wrong**, and the developer corrected it. The real state:

- `docker/config/dist/conf/phpbrew-conf.d/swoole.ini` ships `; extension=swoole.so` — **commented out**.
- `global-stack-phpbrew-copy-dist-conf.sh` runs **after** the package loop in `global-stack-phpbrew-start.sh`, overwriting the ini phpbrew wrote.
- Live check on the running container: `php -m | grep -ci swoole` → **0**. All three ini files (`var/db/swoole.ini`, `var/db/cli/swoole.ini`, `var/db/fpm/swoole.ini`) contain `; extension=swoole.so`.
- The warning occurs **4 log lines total** — 2 unique events duplicated across stdout and stderr — all inside the install window before the dist-conf copy. Not per-invocation.

`copy-dist-conf.sh:42` documents the design explicitly: *"(zephir_parser, phalcon, swoole, xdebug) that conf.d ships commented out."* **This is deliberate and already handled.** swoole's incompatibility with php-master is known.

### What remains

The swoole *symptom* is handled. The underlying *mechanism* is still worth knowing about:

```
ext-src/php_swoole_private.h:121: #error "require PHP version 8.5 or earlier"
make: *** [Makefile:208: ext-src/swoole_coroutine.lo] Error 1      ← stderr 4561
===> Enabling extension swoole                                     ← stdout 4563  (AFTER the failure)
```

phpbrew prints "Enabling", writes the ini entry, and **exits 0** despite `make` having returned 1. Since the stack's health signalling rests on `set -eE` + the prologue ERR trap, a zero exit means no error token is ever written.

For scale: php8-4 and php8-5 emit ~132 compile lines each for swoole; phpedge emits 2.

### Impact

**None today** — the dist-conf layer catches it. The latent risk is that *any future* extension which half-installs would behave identically: build fails, phpbrew exits 0, the stack believes it succeeded, and it would only be caught if someone happened to ship a commented-out ini for it too.

### Recommendation

**Low priority — genuinely optional.** If you ever want it closed, the class fix is install-then-verify: after the package loop, assert each *intended-to-be-enabled* extension actually appears in `php -m`, and FATAL + write the error token if not. This mirrors what `global-stack-android-setup.sh` already does, and it is the same lesson as row 31 (the install reported success; only the verify caught it).

Two cautions if you do:
- It must skip the deliberately-commented-out set (zephir_parser, phalcon, swoole, xdebug) or it will red on all four by design.
- `03phpedge` is a `depends_on` for `05edge`, so an over-eager assertion takes both down.

Given the dist-conf layer already handles the real case, **"leave it" is a defensible answer.**

---

## 3. Log rotation absent on 39 of 44 containers

**Grade: [Verified] for the config; [Inferred] for the daily projections**

### Problem

Only 5 of 44 services set `max-size` / `max-file` in their compose logging options: `01epiclabs-docker-oracle-xe-11g`, `04selenium-chrome`, `04selenium-firefox`, `02keycloak-keycloak`, `02sonarqube`.

There is **no `/etc/docker/daemon.json`**, so there is no daemon-level default either. The other 39 containers write unbounded `json-file` logs.

### Evidence

Worst offender is `01mongo7`: **38.0 MB in 13.3 hours**, unrotated.

Cause is its own healthcheck — `docker/images/01mongo7/docker-compose.yaml:26-30` sets `interval: 10s`, and each `mongosh` probe opens ~5 connections. Result:

```
22,333  "Connection accepted"
22,333  "client metadata"
22,331  "Connection ended"
──────
103,891 lines of pure healthcheck churn
```

Stack-wide: 77.7 MB across ~13 h.

Projections are **[Inferred]** — derived from `docker logs` byte counts. The on-disk `json-file` wrapper adds per-line JSON overhead that was not measured (that needs sudo). So treat ~69 MB/day for mongo and ~140 MB/day stack-wide as **lower bounds**.

### Recommendation

Two options, and I'd do both:

1. **Set a daemon-wide default** in `/etc/docker/daemon.json` (`log-driver: json-file`, `max-size: 10m`, `max-file: 3`). One file, covers every container including future ones, and covers the registry and buildkit too. Caveat: it is a **host-level** change outside the repo, so it does not travel with a clean clone — and it needs a Docker daemon restart.
2. **Add the logging block per service** in compose, matching what the 5 already do. Travels with the repo, reproducible on a clean clone, but it is 39 edits and a new service can forget it.

(1) gives immediate relief; (2) makes it reproducible. They are complementary, not alternatives.

**Separately worth considering:** `01mongo7`'s 10 s healthcheck interval is aggressive given `start_period: 24h` and `retries: 99999`. Raising it to 30 s or 60 s would cut that 103,891-line churn by 3–6× at the source. Fixing the cause beats rotating the symptom — though note the interval is also what makes the service come healthy quickly on boot, so this is a real trade-off, not a free win.

---

## 4. Security-flavoured warnings

**Grade: [Verified from logs]**

All six are local-dev-acceptable. Listing them because you asked for everything abnormal, not because any is an emergency on a single-developer local stack.

| Service | Warning |
|---|---|
| `04serverless-framework` | npm audit: **10 vulnerabilities — 6 moderate, 3 HIGH, 1 CRITICAL**. The log does not name the packages. |
| `01mongo7` | `Access control is not enabled for the database. Read and write access to data and configuration is unrestricted` |
| `01mongo7` | soft rlimit `nofile` **1024** vs recommended minimum **64000** |
| `01mysql9` | `root@localhost is created with an empty password!` (`--initialize-insecure`) |
| `01mysql9` | `CA certificate ca.pem is self signed` |
| `01postgres18` | initdb: `enabling "trust" authentication for local connections` |
| `02sonarqube` | `OAuth authentication should use HTTPS` |

### Recommendation

**Only two of these are worth acting on**, and for non-security reasons:

- **The serverless npm CRITICAL** is the one I would actually look at — not because it is exploitable here, but because you cannot triage what you cannot see. Running `npm audit` inside the container would name the packages and tell you whether it is a transitive dev-dependency (almost certainly) or something in the execution path. Read-only, 30 seconds.
- **The mongo `nofile` 1024 limit** is a genuine operational ceiling, not a security matter — mongo itself calls it out. Raising it via an `ulimits` block in the compose file is cheap.

The rest — empty mysql root password, postgres trust auth, mongo access control, self-signed CA, sonarqube HTTP — are all the **documented, intentional posture** of this stack. CLAUDE.md already records `privileged: true` and `password = username` as known local-dev trade-offs; these are the same category. **I would not change them**, and I'd resist any future audit that flags them as findings.

---

## 5. `02rust` — yanked crates in upstream Cargo.lock

**Grade: [Verified] — NO ACTION NEEDED**

```
warning: package `chacha20 v0.10.1` in Cargo.lock is yanked in registry `crates-io`   (under cargo install … jj-cli)
warning: package `chacha20 v0.10.0` in Cargo.lock is yanked in registry `crates-io`   (under cargo-nextest)
warning: package `der v0.8.0`       in Cargo.lock is yanked in registry `crates-io`   (under cargo-nextest)
```

### Why this is expected, not a regression

All five rust installs pass `--locked`:

```
global-stack-rust-install-jujutsu.sh:15         --locked
global-stack-rust-install-cargo-nextest.sh:20   --locked
global-stack-rust-install-cargo-outdated.sh:15  --locked
global-stack-rust-install-mergiraf.sh:21        --locked
global-stack-rust-install-cargo-zigbuild.sh:20  --locked
```

`--locked` is precisely what makes cargo **warn** about a yanked pin instead of silently re-resolving to something untested. That warning is the feature working. Without it you get `6e3f6c9`'s failure mode — cargo re-resolved `jiff 0.2.36`, which was yanked the same day and could not compile at all.

Important attribution detail: the warnings sit under **jj** and **cargo-nextest**, **not** under `cargo-outdated`. So they are **not** a consequence of `6e3f6c9`. They are upstream lockfile facts belonging to those two projects.

Also present: `refs/tags/vN … is not a commit!` — a cosmetic git-ref notice, no impact.

### Recommendation

**Do nothing.** Keep `--locked`. If the warnings ever become actionable it will be because upstream jj or nextest cut a release with a refreshed lockfile — which arrives on its own via the normal `env-update` bump.

---

## 6. 16 dangling images, 793 MB reclaimable

**Grade: [Verified]** — `docker system df` + dangling-image listing.

Leftovers from the rebuild on 2026-09-12.

### Recommendation

`docker image prune` (dangling only — **not** `docker system prune`, which reaches across every project on the daemon, per `docs/BLAST-RADIUS.md`). Trivial, reversible only by rebuilding, 793 MB back. Do it whenever convenient.

---

# P3 — noise, cosmetic, and explained

## 7. `successes/serverless` is the only token written with a hardcoded literal

**Grade: [Verified]**

`global-stack-serverless-framework-start.sh:261`:

```bash
echo "framework" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}"/serverless
```

Two oddities: the filename is the literal `serverless` rather than `${GLOBAL_STACK_ERROR_TOKEN}`, and the file has **content** (`"framework"`, 10 bytes) — it is the only one of the 44 tokens that is not empty.

**Harmless today** — compose line 98 sets `GLOBAL_STACK_ERROR_TOKEN=serverless`, so the literal happens to equal the variable. But this is exactly the token-invariant drift CLAUDE.md warns about: rename the token in compose and the success write silently keeps pointing at the old path, producing a permanently-unhealthy-yet-functional container masked by the 24h `start_period`.

**Recommendation:** substitute the variable. One-line hygiene fix that removes a latent trap. `bin/tests/startup-prologue.test.sh` §21 already pins this invariant for the web servers, so the pattern is established.

## 8. `sed` EBUSY in 9 containers

**Grade: [Verified]** — `find /home/developer/ -type f -exec sed -i` hits the two bind-mounted shell-history files → `cannot rename …: Device or resource busy`. Only shell history is affected; nothing else fails. **No action** — it is inherent to bind-mounting a file rather than a directory.

## 9. `02keycloak` DEBUG log level

**Grade: [Verified] — intentional.** `docker-compose.yaml:14` sets `--verbose`, `:36` sets `KC_LOG_LEVEL=DEBUG`, plus `KC_HOSTNAME_DEBUG=true`. Result: 90,934 of 93,042 log lines are DEBUG, 16.8 MB over 13 h — but keycloak **is** one of the 5 services that rotates. **No action** unless you want less noise.

## 10. `01valkey` — `Tini is not running as PID 1 / not registered as child subreaper`

**Grade: [Verified]** — upstream image packaging. Zombie reaping is degraded in theory; nothing observed. **No action.**

## 11. `01mariadb13` — `/sys/fs/cgroup///memory.pressure not writable`

**Grade: [Verified]** — note the triple slash, an upstream path-join bug. Cosmetic. **No action.**

## 12. `01caddy` — `failed using API to stop instance … connection refused`

**Grade: [Verified]** — startup ordering: the stop-API is called before the admin endpoint is listening. Self-resolving. **No action.**

## 13. `02dpage-pgadmin4` — `SyntaxWarning: 'return' in a 'finally' block`

**Grade: [Verified]** — in bundled `sshtunnel.py`, upstream. **No action.**

## 14. `02sonarqube` — JDK deprecation warnings

**Grade: [Verified]** — terminally-deprecated `sun.misc.Unsafe` access, and the COMPAT locale provider removal. Upstream; will be fixed by a future sonarqube release. **No action**, but it is the kind of thing that becomes a hard failure on a future JDK bump — worth remembering when sonarqube's base image moves.

## 15. `03flutter3` — `[WARN] Git cache is invalid; recreating from scratch`

**Grade: [Verified]** — self-healing; flutter rebuilds its cache. **No action** unless it recurs every boot (it did not here).

## 16. `01postgres18` — first-run `relation does not exist` errors

**Grade: [Verified]** — `databasechangeloglock` (keycloak's liquibase bootstrap) and `migration_model` (sonarqube's). Both are the normal "check whether the schema exists yet" probe on a fresh volume. Expected. **No action.**

## 17. `02mongoclient` — `RestartCount=1`

**Grade: [Verified]** — exited 0, restarted 5 s later by the restart policy. Not a crash. **No action.**

## 18. Registry — 173 `level=error` lines

**Grade: [Verified]** — all 404-shaped existence probes from yesterday's push: 48 `manifest unknown`, 24 `unknown tag=2_0_0_local`, 101 `blob unknown`. This is `docker push`'s normal "do you already have this layer?" check, which the registry logs at error level. **Nothing failed.** No 500s remain. **No action.**

## 19. BuildKit — warnings only

**Grade: [Verified]** — `using host network as the default`, `skipping containerd worker (socket absent)`, and repeated `failed to match any cache with layers` on image export (cold cache). All expected for this builder configuration. **No action.**

---

# Notable

## 20. Postgres collation is FIXED — and a CLAUDE.md caveat is now stale

**Grade: [Verified]**

Live query on the running cluster: **every** database now reports `datlocprovider='b'` (builtin), `datcollate=C`, `datctype=C.UTF-8`. Sort order is `Banana, Zebra, apple, cherry` — code-point order, exactly as before, but now **honestly labelled** instead of claiming `en_US.utf8`.

Two consequences:

1. **CLAUDE.md is now out of date.** The Gotchas entry says *"`initdb` only runs on an EMPTY data dir, so the existing volume keeps the lying metadata until it is recreated."* That is no longer true — the volume **was** recreated, and the metadata is correct. That sentence will mislead a future session.
2. **All Postgres data is fresh from init.** The volume recreation means keycloak's and the six `*_grdf_clts` databases were rebuilt from scratch. Worth registering if you expected prior data to be there.

**Recommendation:** update the CLAUDE.md Gotchas paragraph to record that the fix has landed and the volume has been recreated. This is the one documentation change I'd actually prioritise, because a stale gotcha is worse than no gotcha — it actively sends the next session down a wrong path.

## 21. `tools/elapsed` mtime anomaly — explained, not a defect

**Grade: [Inferred], with the mechanism Verified**

Observed: `mtime`/`ctime`/`atime` all 2026-09-13 09:03:05 (mtime .461, ctime .463, atime .538 — a write, then a read 77 ms later), while the last *entry inside* the file is `12-09-2026 22:20:56`.

Why this is not the stack: `docker/config/dist/bin/base-bin/global-stack-base-healthcheck-elapsed.sh` only ever **appends**:

```bash
printf '%s: %s - %d hours and %d minutes and %d seconds elapsed.\n' … >> "$ELAPSED_FILE"
```

It has a fast path that `exec`s straight through when the success file is newer than the base file, so on a warm stack it does not touch the file at all. The content is intact and internally consistent — 44 entries matching 44 success tokens, and the last entry's timestamp equals `successes/serverless`'s mtime.

**Conclusion:** a write-then-read 77 ms apart with unchanged content is an editor saving an open buffer. The file was open in the IDE. **No action.**

---

# Appendix — false positives I caught and did NOT report

Recording these so a future sweep does not "rediscover" them:

| Apparent finding | Why it was wrong |
|---|---|
| 8 `GLOBAL_STACK_LOCALSTACK_*` vars missing from `.env.local` | `comm` printed `file 1 is not in sorted order` — a locale collation mismatch between `sort` and `comm`. Re-run under `LC_ALL=C` → **zero** missing keys. |
| Version-marker DRIFT on php.8.4, php.8.5, java.17, java.21, java.26 | My check used wrong variable names. Java's real var is `GLOBAL_STACK_JAVA17_VERSION`, not `..._JAVA17_ZULU_VERSION`; and php markers legitimately hold `PHP_VERSION_NAME` (`php-8.4.25`), per `global-stack-phpbrew-start.sh:57`. Corrected → all markers match. |
| "rtk dropped a row from the container listing" | I miscounted. All 46 were listed; rtk dropped nothing. |
| swoole warning on every php invocation | Wrong — see item 2. The dist-conf layer comments the extension out; 4 log lines total, all during install. Corrected after developer feedback. |

**Lesson worth keeping:** three of those four came from trusting my own tooling rather than the system. The `comm` one in particular would have produced a confident, entirely fictitious finding.

---

*Read-only sweep. No container, config or script in the repo was modified — this document is the only artefact it produced.*
