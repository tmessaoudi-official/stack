# base-install-tools-unmask Plan

The 2026-09-28 rebuild failed at `02sonarqube`: `COPY --from=local_global_stack_base
/opt/developer/sonar-scanner-cli/: not found`. Five root causes, all measured. The last one hid the other four:

1. **difftastic 0.71.0 renamed its release assets.** It now publishes
   `difft-0.71.0-x86_64-unknown-linux-gnu.tar.gz`, while 0.70.0 and earlier have no version in the name,
   as GitHub's API asset listing shows. `install-tools.sh` requested the old name and got a 404. Its
   `curl -L` (no `-f`) saved the error page, `tar` exited 2, and `set -e` stopped the script before
   sonar-scanner-cli, bat, sops, rtk, claude and yq. The built image had tools up to yamlfmt and
   nothing after (`command -v` in the image).
2. **The gitlab-runner install had been failing on its own.** GitLab's `script.deb.sh` writes only
   the `.list` file now, so `sudo rm` of `.list` + `.sources` exited 1. Past that, `~/.gitlab-runner`
   was never created before the `cp` into it: the step exists in `templates/tips/ubuntu-packages.md:335`
   but was lost from the script. Reproduced in a throwaway container: RC=1, then RC=0 with both fixes.
3. **Docker-in-Docker had died at `sudo groupadd docker` on every build.** docker-ce's postinst already
   creates the group, so groupadd exits 9 (seen in the first unmasked build). The compose and buildx
   CLI plugins, the reclaim script and `daemon.json` below it were never installed. Only the apt
   `docker` binary made it look fine.
4. **`rtk init --global` ran as root.** The build's `USER root` means `$HOME/.claude = /root/.claude`,
   which does not exist, so install-tools failed there and never reached yq. Found by pre-flighting
   every enabled installer in a throwaway container; it now runs as the stack user with `-H`.
5. **`{ [ toggle ] && installer || echo "… will not be installed"; }` in the Dockerfiles** runs the
   echo when the installer FAILS, not only when the toggle is off. Every failure above therefore
   produced a green `00base` build, and the damage surfaced two images later as an unrelated-looking
   COPY error.

## Decisions Log
- [2026-09-28 07:09] ASSUMED (review): unmask all 15 `[ … ] && cmd || echo` Dockerfile lines (8 in 00base, 01nginx automake, 6 locale sites incl. the gitignored local.05), not just the tools line — because the class hid a second real failure (gitlab-runner) and a mask anywhere repeats this incident. Alternatives: fix only 00base:341; leave the others as known issues.
- [2026-09-28 07:09] ASSUMED (review): difftastic tries the versioned asset name first, then the legacy one, instead of choosing by version — because a pin must install in either direction and the repo bans ordered version comparisons deciding an install (startup-prologue.test.sh §59). Alternatives: new name only (breaks a downgrade below 0.71.0); `sort -V` on 0.71.0.
- [2026-09-28 07:09] ASSUMED (review): the host `~/.local/bin/global-unu.sh` was redeployed from the template, with a timestamped backup beside it — because it differed from the template only by one comment block and carried the same difftastic defect. Alternatives: leave the host copy for the developer to redeploy.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | difftastic asset name (install-tools + global-unu), curl -f on every 00base download, gitlab-runner rm -f + mkdir, DinD guarded groupadd, rtk init as the stack user, unmask 15 Dockerfile lines, bin/tests/base-install-tools.test.sh | M | done | 756e21f | docker/images/*/Dockerfile, docker/images/00base/conf/bin/**, templates/shell/global-unu.sh, bin/tests/base-install-tools.test.sh |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
### Fragile
- `global-stack-base-install-gitlab-runner.sh` depends on the shape of GitLab's `script.deb.sh`, which changed under it once already.
### Known issues
- `bin/tests/startup-prologue.test.sh` §31 (31a-31c) sources `tools/sdkman/src/sdkman-path-helpers.sh`, which is runtime state. With `tools/` emptied (2026-09-28 wipe) it reds 4 of 1095 instead of skipping loudly. This is environmental, not from this change; it goes green once 02sdkman reinstalls.
- `templates/shell/global-unu.sh` still has 15 `curl -L` without `-f`. It runs without `set -e`, so a 404 there leaves the old tool in place rather than killing the script; not changed here.
