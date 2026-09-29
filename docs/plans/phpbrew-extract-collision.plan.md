# phpbrew-extract-collision Plan

## Decisions Log
- [2026-09-29 06:58] AGREED: Developer chose 'Recover + fix cause' (AskUserQuestion 2026-09-29): remove the broken php-8.5.11 tree, restart 03php8-5, and fix the phpbrew tmp.<time()> collision at its origin.
- [2026-09-29 06:58] ASSUMED (review): Temp-dir uniqueness comes from bin2hex(random_bytes(6)), never the PID — every container has its own PID namespace and boots identically, so siblings share low PIDs (advisor, verified: install-version.sh ran as pid 765 in 03php8-5). Alternatives: uniqid(), mktemp via shell.
- [2026-09-29 06:58] ASSUMED (review): No boot-time re-sync of the overlay into an existing phpbrew-src: the live clone is patched by hand now, every future clone (cold start, RELOAD_PHPBREW) gets it from iou.sh, and a new script on the 02phpbrew critical path (everything downstream waits on its marker) is more risk than the residual gap — a pin bump of >=2 php versions on a volume whose phpbrew-src predates the fix. Documented as a Known issue with the exact rsync. Alternatives: rsync the overlay src/ tree every install boot; a cmp/install of this one file.
- [2026-09-29 06:58] ASSUMED (review): Do not delete tools/errors/php.8.5 by hand: setup mode rm -f's its own token at start (phpbrew-start.sh:41), so a restart clears it. Alternatives: delete it explicitly.

## Formal Plan

**Symptom (2026-09-29 morning check of the overnight cold restart):** `tools/errors/php.8.5` is the only error token; `03php8-5` exited 255 after its 5 `on-failure` restarts and five dependents (`05php8-5-…`, `05stable`, `05edge`, `04phpmyadmin`, `04serverless-framework`) sit in `Created`. `tools/elapsed` holds the same failure six times.

**Root cause (Verified, see the Evidence lines):** phpbrew's `ExtractTask::extract()` names its temp dir `tmp.` + `time()` inside the SHARED `tools/phpbrew/build` (`ExtractTask.php:45`). `03phpedge` and `03php8-5` started extracting 0.4 s apart at 21:47:29 and got the identical `tmp.1790632049`. `03phpedge` finished first and its `__destruct` `rm -rf`'d that dir while 8.5.11's tar was still writing (`rm: cannot remove '…/php-8.5.11/Zend': Directory not empty`, 21:47:39). tar recreated only the tail of the archive, so `build/php-8.5.11` kept ~5,711 fewer files than its tarball (5,635 under `Zend/`, incl. `zend_alloc.c` and `zend_dtrace.d`). phpbrew then reused that tree on every retry because its "already extracted" test is only `file_exists(<dir>/configure)` and `configure` sorts late in the archive. The compile error (`dtrace … zend_dtrace.d: No such file`) was a downstream symptom.

**Fix:**
1. Overlay `docker/config/dist/conf/phpbrew/source/src/PhpBrew/Tasks/ExtractTask.php` = upstream 2.2.0 file with the temp dir made unique per task: `tmp.<time()>.<bin2hex(random_bytes(6))>`. NOT PID-based: every container has its own PID namespace and boots the same way, so sibling containers reuse low PIDs. Listed in the overlay `.version` `files:` and `OVERRIDE.md`.
2. `bin/tests/phpbrew-extract.test.sh`, written first: runs the real overlay PHP file with a frozen `time()` AND `getmypid()` and two tasks in one extract dir; asserts unique temp dirs, that one task's destructor never removes the other's, and that each task's own temp dir is gone afterwards. Carries its own mutants (revert to upstream, PID-suffix, no-cleanup) that must each go red.
3. Recovery: apply the overlay file to the live `tools/phpbrew-src`, remove the broken `build/php-8.5.11` and the partial `php/php-8.5.11`, recreate `03php8-5` through `env -i HOME=$HOME PATH=$PATH make up` (config-hash prediction: 44 of 44 services match the running containers, so nothing healthy is recreated).

**Out of scope, on purpose:** (a) `RegExpPatchRule.php:127` names a backup with `time()` but per patched file inside its own build dir, so it cannot collide across containers. (b) The shared autoconf `config.cache` is written by `configure` through `mv -f confcache "$cache_file"$$ && mv -f "$cache_file"$$ "$cache_file"`, an atomic rename, and is only a cache. (c) A boot-time re-sync of the overlay into an already-cloned `phpbrew-src` — see the ASSUMED entry.

**Certified by execution:** the unique-temp-dir and cleanup properties (test + mutants), and one uncontended live extraction. **NOT certified by execution:** the concurrent cold-start race itself (UNCERTIFIED-BY-EXECUTION) — proving it needs a full cold start with two php installs beginning in the same second.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Write failing test + mutants (red for the stated reason) | M | todo | - | bin/tests/phpbrew-extract.test.sh |
| 2 | Overlay ExtractTask.php + .version + OVERRIDE.md | S | todo | - | docker/config/dist/conf/phpbrew/source/** |
| 3 | Docs: CLAUDE.md gotcha + test entry | S | todo | - | CLAUDE.md |
| 4 | Recovery: live overlay, remove broken tree, recreate 03php8-5 | M | todo | - | - |
| 5 | Verify: log shows patched class ran, 03php8-5 healthy, dependents up | M | todo | - | - |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
### Fragile
### Known issues
- The overlay is rsynced only when `phpbrew-iou.sh` makes a FRESH clone (cold start, `RELOAD_PHPBREW`). A `phpbrew-src` cloned before an overlay file existed never receives it; re-apply by hand with `rsync -a docker/config/dist/conf/phpbrew/source/src/ tools/phpbrew-src/src/`.
