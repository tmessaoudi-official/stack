# php86-rc Plan

Add PHP 8.6 (currently a release candidate) as `03php8-6`, alongside 8.4 / 8.5 / edge.

## Decisions Log
- [2026-10-23 10:25] AGREED: `GLOBAL_STACK_PHP8_6_VERSION` is a bare version (`8.6.0RC4`), shaped like 8.5 — phpbrew's `VersionDslParser` maps `^(php-)?X.Y.Z(alpha|beta|RC)N$` to the php-src GitHub tag tarball (`is_tag: true`) before it consults the php.net release list, so the `github.com/php/php-src@php-…` form (which env-update `--apply` would rewrite bare anyway, and which fails the start script's `PHP_VERSION` pin check) is not needed. Supersedes the "option 1" (tracker var + start-script strip) the developer first picked on an unverified premise.
- [2026-10-23 10:25] AGREED: scaffold the per-version surfaces 8.6 lacks by copying 8.5's tracked files with 8.5 → 8.6: `GLOBAL_STACK_FRANKENPHP_8_6_VERSION`, `dist/bin/php8.6-bin/{setup-version,setup-project}.sh`, `dist/conf/php8.6-{conf.d,php-fpm.d,frankenphp}/`. Nothing is committed — the developer reviews first.

## Formal Plan
1. `.env`: `GLOBAL_STACK_PHP8_6_VERSION=8.6.0RC4`, plus one comment line above the 8.6 annotation: `(channel:unstable)` comes off at GA. Add `GLOBAL_STACK_FRANKENPHP_8_6_VERSION=${GLOBAL_STACK_FRANKENPHP_VERSION}` after the 8.5 one. `CLAUDE.md` § Architecture: add 8.6 to the tier-03 PHP list.
2. `docker/config/dist/bin/php8.6-bin/`: copies of the two 8.5 scripts (neither carries an 8.5 literal), mode 775.
3. `docker/config/dist/conf/php8.6-*`: copies of the TRACKED 8.5 files only (`docker-xdebug.ini` with `idekey=php8.6-dev`, `fatal-error-backtrace.ini`, the empty `docker-fpm.conf` and `example.caddy`); the untracked machine-local `*.caddy` sites stay 8.5-only.

Verify: `env-update --check --dry-run --filter=PHP8_6` → 0 DRIFT / 0 REPLACE-DRIFT (red before: `[DRIFT] annotation says 8.6.0RC4 but VAR=github.com/…`); a surface check listing every 8.5 path's 8.6 twin (red before); `bash -n` + shellcheck on the new scripts; `startup-prologue.test.sh` (discovers new sourcing scripts). UNCERTIFIED-BY-EXECUTION: `03php8-6` coming up healthy (needs env-scan, a build and a 10+ min cold install).

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | .env 8.6 version bare + FrankenPHP 8.6 var | S | done | - | .env, CLAUDE.md |
| 2 | php8.6-bin setup scripts | S | done | - | docker/config/dist/bin/php8.6-bin/** |
| 3 | php8.6 conf dirs | S | done | - | docker/config/dist/conf/php8.6-*/** |
| 4 | env-scan → .env.local | S | done | - | .env.local |
| 5 | developer review, then commit (git add --chmod=+x for php8.6-bin) | S | todo | - | - |
| 6 | make build + up: 03php8-6 healthy | M | todo | - | - |
<!-- /progress-block -->
### Blocked
- [2026-10-23 10:56] Step 1 unblocked: the developer told Claude to run `/tmp/fix-php86-env-20261023.sh` (the Edit tool stays denied on `.env`; the script ran via Bash). `.env.bak.php86.*` kept for review.
### Needs input
### Needs research
### Fragile
### Known issues
- `startup-prologue.test.sh` reds 15 of 1111, all §76 (nginx signature/clone cases, 76a keygen green), on 2026-10-23 — independent of this change: §76 reads no `.env` or php path, and the nginx scripts and the suite are clean vs HEAD. Not reproduced on a clean baseline (the in-place baseline was firewall-denied; a `git archive` copy aborts with exit 128). Same 15 with `TMPDIR=/tmp/p86`, so not a socket-path-length issue.
- New shebang files must land as 100755 in git (`base-set-permissions.test.sh` §3) while `core.fileMode=false`: commit them with `git add --chmod=+x`.
