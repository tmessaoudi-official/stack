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

## Inventory (2026-09-28, read from each tool's own metadata)

| Dir | Installed | Launcher |
|---|---|---|
| `android-studio` | AI-261.26222.65.2614.16379836 | `android-studio.desktop` |
| `jetbrains/idea` | IntelliJ IDEA 2026.2.3 (262.10968.63) | `idea.desktop` |
| `jetbrains/PhpStorm-2026.2.3` | PhpStorm 2026.2.3 (262.10968.76) | `phpstorm.desktop` → `jetbrains/phpstorm` (BROKEN path) |
| `jetbrains/webstorm` | WebStorm 2026.2.3 (262.10968.77) | `webstorm.desktop` |
| `code` | VS Code 1.139.1 | `code.desktop` |
| `devin` | app 1.126.0 (archive named 3.10.35) | `devin.desktop` |
| `sublime_text` | Build 4215 | `sublime_text.desktop` |
| `megit` | 0.11.0 | `megit.desktop` |
| `balena-etcher` | 2.1.7 (from archive name, unconfirmed) | none |
| `task` / `bat` / `sonar-scanner-cli` | 3.53.1 / 0.26.1 / 8.1.0.6389 | PATH via `.profile` (global-unu today) |

Not tools: `oracle-virtualbox-vms`, `root`.

## Formal Plan
<!-- written at Phase 4 approval -->

## Status
### Blocked
### Needs input
### Needs research
- MeGit (eclipsesource/megit) and balenaEtcher (balena-io/etcher) GitHub asset names + digests — deferred until the cold bring-up finishes (api.github.com budget).
- Whether env-update's `url` fetcher `(fetch-json:)` can express each vendor query below, or a new fetcher type is needed.

## Vendor sources (probed 2026-09-28 19:55; every latest == installed, so each feed matches reality)

| Tool | Latest-version source | Artifact | Checksum |
|---|---|---|---|
| IDEA / PhpStorm / WebStorm | `data.services.jetbrains.com/products/releases?code=IIU,PS,WS&latest=true&type=release` → `.version`, `.downloads.linux.link` | `download.jetbrains.com/{idea/idea,webide/PhpStorm,webstorm/WebStorm}-<v>.tar.gz` | `<link>.sha256` |
| Android Studio | `jb.gg/android-studio-releases-list.json` (JetBrains TeamCity mirror); channels Beta/Canary/Patch/Preview/RC/Release — stable = newest of **Release+Patch** (installed is a Patch) | `edgedl.me.gvt1.com/android/studio/ide-zips/<v>/android-studio-<codename>-linux.tar.gz` (name NOT derivable from version — read `link`) | `checksum` field (sha256) |
| VS Code | `update.code.visualstudio.com/api/update/linux-x64/stable/latest`; pinned: `/api/versions/<v>/linux-x64/stable` | `.url` | `.sha256hash` |
| Devin (the Windsurf feed) | `windsurf-stable.codeium.com/api/update/linux-x64/stable/latest` → `productVersion` 1.126.0, `windsurfVersion` 3.10.35 | `.url` (`Devin-linux-x64-<windsurfVersion>.tar.gz`) | `.sha256hash` |
| Sublime Text | `www.sublimetext.com/updates/4/stable_update_check` → `latest_version` | `download.sublimetext.com/sublime_text_build_<n>_x64.tar.xz` | **none published** (`.sha256` → 404) |
### Fragile
- No live api.github.com calls while a cold `make hard-restart` runs: fvm/elasticmq digest checks share the 60/h anonymous limit.
### Known issues
- `phpstorm.desktop` points at a dir that does not exist.
- All 8 hand-made launchers fail `desktop-file-validate` (unregistered Categories `PHP`/`Dev`/`GIT`/`Version`/`Text`, app version in `Version=`, `Name=Sublme Text`); none set StartupWMClass except megit. Fixed by the managed-launcher step.
- `.profile` adds `/opt/$USER/go/bin`, which does not exist.
