Override corneltek/cliframework to fix deprecations
Override fix nullability

Override src/PhpBrew/Tasks/ExtractTask.php: the extraction temp dir is `tmp.<time()>.<random hex>` instead of `tmp.<time()>`.
Every 03php* container shares tools/phpbrew/build, and two that started extracting in the same second (03phpedge and
03php8-5, 2026-09-28) got the same dir; the first to finish rm -rf'd it under the other's tar and left a half-extracted php tree
that phpbrew then reused on every retry. Guarded by bin/tests/phpbrew-extract.test.sh.

This directory is rsynced by global-stack-phpbrew-iou.sh only when it makes a FRESH clone of phpbrew (cold start, or
GLOBAL_STACK_RELOAD_PHPBREW). A phpbrew-src cloned before an override existed never receives it; re-apply by hand:
`rsync -a docker/config/dist/conf/phpbrew/source/src/ tools/phpbrew-src/src/`