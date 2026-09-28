# opt-developer-updater Plan

Keep the GUI tools/IDEs under `/opt/developer` on a reviewed pin, the way `global-unu.sh`
already keeps `task`, `bat` and `sonar-scanner-cli`.

## Decisions Log
- [2026-09-28 19:48] AGREED: Scope: android-studio, IntelliJ IDEA, PhpStorm, WebStorm, VS Code, Sublime Text, MeGit, Devin, balenaEtcher; move task/bat/sonar-scanner-cli into the same mechanism; delete the downloaded archive after a verified swap; drop the stale /opt/$USER/go/bin PATH entry.
- [2026-09-28 19:48] AGREED: Versions are .env pins with @todo env-update annotations (env-update proposes, HOLD on majors); the installer installs the pin (equality-based), never a live 'latest'.
- [2026-09-28 19:48] AGREED: global-unu.sh is the single entry point that controls all updates: the new logic lives in it or is called at its end (which one: pending confirmation).
- [2026-09-28 19:51] AGREED: Placement: a separate script, templates/shell/global-unu-opt.sh (deployed next to global-unu.sh in ~/.local/bin), called as the LAST step of global-unu.sh from its own directory; global-unu.sh stays the single entry point.
- [2026-09-28 19:51] AGREED: Mode: called from global-unu.sh it installs the pin when installed != pin; run standalone it defaults to --check and needs --apply to install.
- [2026-09-28 19:51] AGREED: Rollback: no <dir>.previous kept; the old dir is deleted only after the new one is downloaded, checksum-verified where the vendor publishes one, extracted and passes its version check.
- [2026-09-28 20:00] AGREED: Install layout: every JetBrains IDE lives at jetbrains/<lowercase product> (idea, phpstorm, webstorm), never a version-named dir; the version is read from product-info.json.
- [2026-09-28 20:00] AGREED: Launchers: global-unu-opt.sh fully manages the .desktop file of all 9 GUI apps (android-studio, idea, phpstorm, webstorm, code, devin, sublime_text, megit, balena-etcher): canonical Name/Exec/TryExec/Icon/Categories + StartupWMClass read from the app, rewritten only when content differs, desktop-file-validate'd, then update-desktop-database; hand edits to those 9 files are overwritten.
- [2026-09-28 20:00] AGREED: Launcher definitions live inside global-unu-opt.sh (one file to deploy), not as template files.
- [2026-09-28 20:16] REJECTED: Pin name GLOBAL_STACK_ANDROIDSTUDIO_VERSION — developer ruling 20:24: use GLOBAL_STACK_ANDROID_STUDIO_VERSION. (The stated reason was also overstated: no doc prescribes an `ANDROID` filter; only a hand-typed `--filter=ANDROID` would sweep it in.)
- [2026-09-28 20:16] AGREED (ratified ASSUMED): Stray archives: the script never deletes a file it did not download; today's hand-downloaded archives get a one-off handoff command — because deleting user files by pattern is irreversible. Alternatives: pattern-delete managed-tool archives in /opt/developer on --apply.
- [2026-09-28 20:26] AGREED: Plan approved (go) including 9 new .env pins; Android Studio pin is GLOBAL_STACK_ANDROID_STUDIO_VERSION; Sublime keeps a bare-build pin (4215) and every build bump stays HOLD (apply with --force-hold --confirm).
- [2026-09-28 20:56] AGREED (ratified ASSUMED 21:22): Android Studio pin holds the BUILD id (AI-261.26222.65.2614.16379836, from the release list's .build), not the marketing version 2026.1.4.8 — because the installed tree carries only the build id (product-info.json, build.txt), so --check can compare without a network lookup. Gate: a patch or quarterly release within 261 is AUTO, 261→262 (Quail→Rabbit) HOLDs [Verified: _gs_eu2_classify_decision]. Alternatives: marketing-version pin + a .gs-version marker written at install (the current hand install would re-download once).
- [2026-09-28 21:25] AGREED: Android Studio tracks the STABLE channels only (Release+Patch); Rabbit (262) arrives as a HOLD once it goes stable and is applied with --force-hold. PhpStorm move: developer runs /tmp/mv-phpstorm-layout-20260928.sh now. Next: step 4 (VS Code, Devin, Sublime).

## Inventory (2026-09-28, read from each tool's own metadata)

| Dir | Installed | Version source | Launcher |
|---|---|---|---|
| `android-studio` | build AI-261.26222.65.2614.16379836 (= 2026.1.4.8) | `product-info.json` `.version` — the build id IS the pin (ASSUMED 20:56) | `android-studio.desktop` |
| `jetbrains/idea` | IntelliJ IDEA 2026.2.3 (262.10968.63) | `product-info.json` `.version` | `idea.desktop` |
| `jetbrains/PhpStorm-2026.2.3` | PhpStorm 2026.2.3 (262.10968.76) | `product-info.json` `.version` | `phpstorm.desktop` → `jetbrains/phpstorm` (BROKEN path; handoff `/tmp/mv-phpstorm-layout-20260928.sh`) |
| `jetbrains/webstorm` | WebStorm 2026.2.3 (262.10968.77) | `product-info.json` `.version` | `webstorm.desktop` |
| `code` | VS Code 1.139.1 | `resources/app/package.json` `.version` | `code.desktop` |
| `devin` | windsurfVersion 3.10.35 (productVersion 1.126.0) | `resources/app/product.json` `.windsurfVersion` | `devin.desktop` |
| `sublime_text` | Build 4215 | first `Build NNNN` in `changelog.txt` (non-executing; `--version` would run an unchecked download) | `sublime_text.desktop` |
| `megit` | 0.11.0 (plugin 0.11.0.20260428-1215) | `plugins/com.eclipsesource.megit.plugin_<v>.jar` | `megit.desktop` |
| `balena-etcher` | 2.1.7 | `package.json` inside `resources/app.asar` (asar header) | none |
| `task` / `bat` / `sonar-scanner-cli` | 3.53.1 / 0.26.1 / 8.1.0.6389 | `--version` | PATH via `.profile` (global-unu today) |

Not tools: `oracle-virtualbox-vms`, `root`.

## Vendor sources (probed 2026-09-28 19:55-20:10; every latest == installed, so each feed matches reality)

| Tool | Latest-version source (env-update `url:` + `(fetch-json:)`) | Artifact | Checksum |
|---|---|---|---|
| IDEA / PhpStorm / WebStorm | `data.services.jetbrains.com/products/releases?code=<IIU\|PS\|WS>&latest=true&type=release` → `.<CODE>[0].version` | `.downloads.linux.link` | `<link>.sha256` |
| Android Studio | `jb.gg/android-studio-releases-list.json` → `[.content.item[]\|select(.channel=="Release" or .channel=="Patch")]\|max_by(.version\|split(".")\|map(tonumber))\|.build` (the BUILD id) | the item whose `.build` == pin, `.download[]` ending `-linux.tar.gz` (codename in name — never derived) | item `checksum` (sha256) |
| VS Code | `update.code.visualstudio.com/api/update/linux-x64/stable/latest` → `.productVersion`; install from `/api/versions/<v>/linux-x64/stable` | `.url` | `.sha256hash` |
| Devin (Windsurf feed) | `windsurf-stable.codeium.com/api/update/linux-x64/stable/latest` → `.windsurfVersion` | `.url` | `.sha256hash` |
| Sublime Text | `www.sublimetext.com/updates/4/stable_update_check` → `.latest_version` | `download.sublimetext.com/sublime_text_build_<n>_x64.tar.xz` | **none published** (`.sha256` → 404) |
| sonar-scanner-cli | (existing github pin) | binaries.sonarsource.com zip | `<zip>.sha256` (200) |
| MeGit / Etcher / task / bat | github releases | release asset | GitHub asset `digest` (api.github.com) — step 5/6 |

## Formal Plan

**My understanding:** add `templates/shell/global-unu-opt.sh`, which installs the `.env`-pinned
version of the 12 `/opt/developer` tools (download → checksum → extract → version check → swap,
old dir deleted only after the new one passes) and owns their 9 launchers; `global-unu.sh` calls it
last with `--apply`; env-update proposes the pins.

### Script shape (`templates/shell/global-unu-opt.sh`, `set -euo pipefail`)

- **Flags**: `--check` (default: report `current` / `outdated` / `missing` / `skipped` per tool, write
  nothing), `--apply` (install + launchers), `--only=<id>[,<id>]`, `--help`. Never prompts (make
  runs it under `yes y |`).
- **Pins**: read literally from `${GLOBAL_STACK_DOCKER_ROOT_PATH:-/stack}/.env.local`
  (`^GLOBAL_STACK_<X>_VERSION=`), no `eval`. An empty/absent pin = tool unmanaged, reported.
- **Seams for tests**: `GS_UNU_OPT_ROOT` (default `/opt/${USER}`), `GS_UNU_OPT_APPS_DIR`
  (default `${XDG_DATA_HOME:-$HOME/.local/share}/applications`), `GS_UNU_OPT_ENV_FILE`.
- **One row per tool**: id, install dir, pin var, installed-version reader, artifact resolver
  (url + sha256 or `none`), app-root inside the archive, launcher fields.
- **Install engine** (`--apply`, only when installed != pin):
  1. resolve url + checksum for the PIN (never "latest"; Devin: feed version != pin → WARN + skip);
  2. `curl -fL` into `${ROOT}/.gs-staging/<id>/` (same filesystem, so the swap is a rename; `/tmp` is tmpfs);
  3. sha256 check (Sublime: none published — reported as `unverified-checksum`);
  4. extract, locate the app root, read ITS version == pin — always a NON-executing read
     (metadata file, jar name, asar header, Sublime's `changelog.txt`), never running staged bytes;
  5. skip with WARN if any `/proc/*/exe` resolves under the install dir (app running);
  6. `mv old → staging/old`, `mv new → final`, then `rm -rf` staging (old + archive). A failed
     second `mv` moves the old dir back. Every `rm -rf` is refused unless the path is under
     `${ROOT}/.gs-staging/`.
  Any failure before step 6 leaves the installed copy untouched and exits non-zero at the end
  (other tools still run).
- **Launchers**: canonical text per app (Name, GenericName, Comment, Exec with `%F` where the app
  takes files, TryExec, Icon, `Categories=Development;IDE;` (+ `TextEditor`/`RevisionControl`/
  `Utility` where apt), `Version=1.5` (the spec version — never the app's), `StartupWMClass` only where VERIFIED — JetBrains from `product-info.json`
  `.launch[].startupWmClass`, others only after an `xprop` check, else omitted). Validated with
  `desktop-file-validate` BEFORE replacing; written only when content differs; one
  `update-desktop-database` at the end if anything changed.
- **Stray archives**: the script never deletes a file it did not download. Today's ~2.7 GB of
  hand-downloaded archives get a one-off handoff command.

### Pins (`.env`, next to `GLOBAL_STACK_BAT_VERSION`)

`GLOBAL_STACK_{IDEA,PHPSTORM,WEBSTORM,ANDROID_STUDIO,VSCODE,DEVIN,SUBLIME_TEXT,MEGIT,BALENA_ETCHER}_VERSION`,
each with its `@todo env-update` record from the Vendor sources table plus a trailing `urls:` human
release page (so `open-all-envs.sh` opens something readable). A hand-typed `--filter=ANDROID` also
matches `GLOBAL_STACK_ANDROID_STUDIO_VERSION` — filter the SDK window by its own var names.
**Review gate caveat**: decide.sh rule 7 HOLDs only a MAJOR change, and for year-versioned tools
(JetBrains `2026.2.3`) the major is the YEAR — `2026.2 → 2026.3` is AUTO, only `2026 → 2027`
HOLDs. Android Studio's pin is its build id, whose major is the platform line: a patch or
quarterly release inside `261` is AUTO, `261 → 262` (Quail → Rabbit) HOLDs. VS Code/Devin/MeGit majors are rare; Sublime's build number is
a single integer, so every build bump is a "major" and HOLDs. [Verified 20:20: `_gs_eu2_classify_decision` →
`4215→4216` HOLD, `2026.2.3→2026.3.1` AUTO, `2026.1.4.8→2026.2.1.1` AUTO, `2026.2.3→2027.1` HOLD,
`3.10.35→3.11.0` AUTO, `3.10.35→4.0.0` HOLD.]
Live checks are always filtered: `bin/env-update.sh --check --filter='IDEA|PHPSTORM|WEBSTORM|ANDROID_STUDIO|VSCODE|DEVIN|SUBLIME_TEXT'`
(an unfiltered `--check` spends the shared api.github.com budget).
Host dependencies: `curl`, `jq`, `sha256sum`, `tar`, `unzip`, `python3` (Etcher's asar header), `desktop-file-utils`.
`templates/shell/*.sh` is scanned by `startup-prologue.test.sh` §59 (no ordered version comparison in an
install path) — the new script is equality-based, so it must pass that scan on its first commit. `bin/env-scan.sh` carries
them to `.env.local`. Existing `GLOBAL_STACK_{TASK,BAT,SONAR_SCANNER_CLI}_VERSION` keep their
names (00base shares the bat/sonar pins).

### Steps

1. **Parser proof** (S): env-update test that a `url:` record with `?`/`&` in the URL and `"` +
   nested parens in `(fetch-json:)` parses and resolves intact (fixture seam). Red first; fix
   `parse.sh` only if it is red for that reason.
2. **Engine + harness** (L): the script skeleton above plus `bin/tests/global-unu-opt.test.sh`:
   temp root/apps dir, stub `curl` serving fixture archives built by the test, checksums computed
   in the test. Cases: check writes nothing; current → no-op; outdated → installed; bad checksum,
   404, wrong version inside → old copy byte-intact + non-zero; running app → skipped; `rm`
   outside staging refused (stub proves it on a disposable sibling); launcher valid, rewritten
   only on change (mtime), invalid generated launcher never written. Sabotage each guarantee.
3. **JetBrains ×3 + Android Studio** (M): pins, rows, launchers; filtered `--check` resolves each to the installed version.
4. **VS Code + Devin + Sublime** (M): pins, rows, launchers; WM classes checked with `xprop`.
5. **MeGit + Etcher** (M): after the stack is healthy (api.github.com budget); GitHub asset
   digest; Etcher gets its first launcher.
6. **Move task / bat / sonar-scanner-cli** (M): delete their blocks from `global-unu.sh`, add rows
   (sonar `.sha256`, task/bat GitHub digest); PATH entries in `.profile` unchanged.
7. **Hook + cleanup + docs** (S): `global-unu.sh` runs
   `"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/global-unu-opt.sh" --apply` as its last
   step BEFORE the final `echo "Successful :)"` (the script has no `set -e`, so a failure must be
   reported, not swallowed: print it and exit non-zero instead of claiming success); drop the
   `go/bin` block from `templates/shell/.profile`; CLAUDE.md (test bullet, hard-restart now
   refreshes IDEs), `templates/tips/file-layout.md` if it lists `templates/shell`.
8. **Deploy + live check** (S): copy both scripts to `~/.local/bin` (timestamped backup first),
   drop `go/bin` from `~/.profile` (backup), run `global-unu-opt.sh --check` against the real
   `/opt/developer` (read-only, expect 12 × current); `--apply` there is yours to run (the
   firewall denies my writes under `/opt`).

**Acceptance**: suite green + every sabotage red; `--check` on the real tree reports all 12
current; all 9 launchers pass `desktop-file-validate`; `global-unu.sh` still ends `Successful :)`.
**Rollback**: `git revert` the step commits; `~/.local/bin` and `~/.profile` from their backups;
a tool swap cannot be undone once the old dir is deleted — re-pin the old version and `--apply`.

### Step 3 real-artifact evidence (21:15)
The install path of the three new rows was checked against the real vendor archives already in
`/opt/developer` (read with python `tarfile` — the firewall denies `tar -x` there): each holds ONE
top-level dir (`PhpStorm-262.10968.76`, `WebStorm-262.10968.77`, `android-studio`), its
`product-info.json` `.version` equals the pin (`2026.2.3`, `2026.2.3`,
`AI-261.26222.65.2614.16379836`), and `sha256sum -c` passes against the vendor checksum
(JetBrains `.sha256`; the release list's `checksum` for the AS `-linux.tar.gz`).

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Parser proof: url + fetch-json with quotes/?& | S | done | 617105b | bin/tests/env-update.test.sh, bin/lib/env-update/core/parse.sh |
| 2 | Engine + test harness (+ the IDEA row as its vehicle) | L | done | c2e5e61 | templates/shell/global-unu-opt.sh, bin/tests/global-unu-opt.test.sh |
| 3 | JetBrains x3 + Android Studio | M | done | 64ac247 | .env, templates/shell/global-unu-opt.sh |
| 4 | VS Code + Devin + Sublime | M | doing | - | .env, templates/shell/global-unu-opt.sh |
| 5 | MeGit + Etcher | M | todo | - | .env, templates/shell/global-unu-opt.sh |
| 6 | Move task/bat/sonar-scanner-cli | M | todo | - | templates/shell/global-unu.sh, templates/shell/global-unu-opt.sh |
| 7 | Hook + .profile + docs | S | todo | - | templates/shell/global-unu.sh, templates/shell/.profile, CLAUDE.md |
| 8 | Deploy + live check | S | todo | - | - |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
- MeGit (eclipsesource/megit) and balenaEtcher (balena-io/etcher) asset names + digests — after the cold bring-up (api.github.com budget).
- Devin feed is `.../stable/latest` only — no versioned download found; the installer refuses a pin that is no longer latest (WARN + skip).
- StartupWMClass for VS Code, Devin, Sublime, Etcher — verify with `xprop` on a running window, else omit.
### Fragile
- No live api.github.com calls while a cold `make hard-restart` runs: fvm/elasticmq digest checks share the 60/h anonymous limit.
- `make hard-restart` runs `yes y | global-unu.sh`, so once step 7 lands a hard restart also installs any IDE whose pin moved.
- `Makefile:306` is `yes y | global-unu.sh || echo 'script does not exit'`: a failed IDE install makes global-unu exit non-zero, and hard-restart swallows it with a misleading message — the only signal there is the script's own output.
- ORDER: run `/tmp/mv-phpstorm-layout-20260928.sh` BEFORE the first `global-unu.sh` after step 7. Otherwise `--apply` downloads a fresh PhpStorm into `jetbrains/phpstorm`, the handoff then refuses (target exists) and `jetbrains/PhpStorm-2026.2.3/` is left orphaned (~3 GB).
### Known issues
- `phpstorm.desktop` points at a dir that does not exist — handoff `/tmp/mv-phpstorm-layout-20260928.sh` pending on the developer's side; Inventory row stays until they report.
- All 8 hand-made launchers fail `desktop-file-validate` (unregistered Categories `PHP`/`Dev`/`GIT`/`Version`/`Text`, app version in `Version=`, `Name=Sublme Text`); none set StartupWMClass except megit. Fixed by the managed launchers.
- `.profile` adds `/opt/$USER/go/bin`, which does not exist.
