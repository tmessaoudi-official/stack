#!/usr/bin/env bash
# Tests for the phpbrew ExtractTask overlay
# (docker/config/dist/conf/phpbrew/source/src/PhpBrew/Tasks/ExtractTask.php).
#
# The failure this guards (2026-09-28 cold start): upstream phpbrew names its
# extraction temp dir `tmp.` + time() inside the SHARED tools/phpbrew/build.
# 03phpedge and 03php8-5 began extracting 0.4 s apart, got the SAME dir, and
# 03phpedge's destructor `rm -rf`'d it while 8.5.11's tar was still writing.
# tar recreated only the tail of the archive, phpbrew reused that tree on every
# retry (its "already extracted" test is just file_exists(<dir>/configure), and
# `configure` sorts late in the archive), and the container burned its restart
# budget on a compile error about a file the tree no longer had.
#
# The contract under test is therefore about the TEMP DIR, not about php:
#   1. two tasks never share a temp dir even when time() AND getmypid() agree
#      (containers have separate PID namespaces and boot identically);
#   2. one task's destructor never removes the other's temp dir;
#   3. each task removes its OWN temp dir, and leaks none.
#
# The real overlay file is executed under a frozen clock and frozen PID against
# stubbed BaseTask/Build classes, so this needs php and tar but no phpbrew
# checkout. Three mutants of the overlay must each go red, and the pristine
# upstream 2.2.0 file (read from the live clone's git HEAD when present) must
# too - that last one is the reproduction of the real bug.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAY_DIR="${REPO}/docker/config/dist/conf/phpbrew/source"
OVERLAY="${OVERLAY_DIR}/src/PhpBrew/Tasks/ExtractTask.php"
PHPBREW_SRC="${GS_TEST_PHPBREW_SRC:-${REPO}/tools/phpbrew-src}"

PASS=0
FAIL=0
SKIP=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_GREEN='' C_RED='' C_BOLD='' C_RESET=''
fi
ok() {
  PASS=$((PASS + 1))
  printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}
ko() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$1")
  printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "$1"
}
skip() {
  SKIP=$((SKIP + 1))
  printf '  -  SKIP  %s\n' "$1"
}
section() { printf '\n%b%s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

# A suite that cannot run must not read as a pass.
for tool in php tar mktemp cmp; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    printf 'ABORT: %s is required and was not found on PATH\n' "${tool}" >&2
    exit 2
  fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ---------------------------------------------------------------- fixtures --
# Two tiny tarballs shaped like a php-src release: a top dir named after the
# file, `configure` and a Zend/ tree. 41 files each.
EXPECT_FILES=41
make_tarball() {
  local name="$1" root="${WORK}/src/$1" i
  mkdir -p "${root}/Zend"
  printf '#!/bin/sh\n' >"${root}/configure"
  for i in $(seq 1 40); do printf 'x%s\n' "${i}" >"${root}/Zend/f${i}.c"; done
  tar -C "${WORK}/src" -czf "${WORK}/${name}.tar.gz" "${name}"
}
make_tarball php-9.9.9
make_tarball php-9.9.8

# The harness runs the file under test with time() and getmypid() frozen in the
# class's own namespace (an unqualified call falls back to the namespaced
# function when one exists). BaseTask/Build are stubs: only what ExtractTask
# touches.
cat >"${WORK}/harness.php" <<'PHP'
<?php
namespace PhpBrew {
    class Build {
        const STATE_EXTRACT = 2;
        public $state = 0;
        private $name;
        public function __construct($name) { $this->name = $name; }
        public function getName() { return $this->name; }
        public function getState() { return $this->state; }
        public function setState($s) { $this->state = $s; }
    }
}
namespace PhpBrew\Exception {
    class SystemCommandException extends \Exception {
        public function __construct($m, $b = null) { parent::__construct($m); }
    }
}
namespace PhpBrew\Tasks {
    function time() { return 1790632049; }
    function getmypid() { return 765; }
    abstract class BaseTask {
        public $log = array();
        public function info($m) { $this->log[] = $m; }
        public function __destruct() {}
    }
}
namespace {
    use PhpBrew\Build;
    use PhpBrew\Tasks\ExtractTask;

    require getenv('EXTRACT_TASK');
    $dir = getenv('BUILD_DIR');

    $tmpOf = function ($task) {
        foreach ($task->log as $line) {
            if (preg_match('#Extracting .* to (.+)/[^/]+$#', $line, $m)) {
                return $m[1];
            }
        }
        return '';
    };
    $count = function ($d) {
        $n = 0;
        $it = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($d, FilesystemIterator::SKIP_DOTS)
        );
        foreach ($it as $f) {
            if ($f->isFile()) { $n++; }
        }
        return $n;
    };
    $yn = function ($b) { return $b ? 1 : 0; };

    $a = new ExtractTask();
    $b = new ExtractTask();
    $ra = $a->extract(new Build('php-9.9.9'), getenv('TAR_A'), $dir);
    $rb = $b->extract(new Build('php-9.9.8'), getenv('TAR_B'), $dir);
    $ta = $tmpOf($a);
    $tb = $tmpOf($b);

    echo "TMP_A=$ta\nTMP_B=$tb\n";
    echo 'CNT_A=' . $count($ra) . "\nCNT_B=" . $count($rb) . "\n";
    echo 'CFG_A=' . $yn(file_exists("$ra/configure")) . "\nCFG_B=" . $yn(file_exists("$rb/configure")) . "\n";

    $a = null; // runs A's destructor while B is still alive
    echo 'A_TMP_AFTER_A_GONE=' . $yn(is_dir($ta)) . "\n";
    echo 'B_TMP_AFTER_A_GONE=' . $yn(is_dir($tb)) . "\n";
    $b = null;
    echo 'B_TMP_AFTER_B_GONE=' . $yn(is_dir($tb)) . "\n";
    echo 'LEAK=' . count(glob($dir . '/tmp.*')) . "\n";
    echo "DONE=1\n";
}
PHP

# ------------------------------------------------------------- evaluation --
declare -A R
CHECK_NAMES=(unique-temp-dir destructor-isolation own-cleanup no-leak complete-trees)
declare -A CHECK_OK CHECK_WHY
HARNESS_ERR=''

# evaluate <task.php>
#   0 = every check held, 1 = at least one assertion failed, 2 = harness error
evaluate() {
  local task="$1" out k v bd
  R=()
  CHECK_OK=()
  CHECK_WHY=()
  bd="$(mktemp -d "${WORK}/build.XXXXXX")"
  out="$(EXTRACT_TASK="${task}" BUILD_DIR="${bd}" TAR_A="${WORK}/php-9.9.9.tar.gz" TAR_B="${WORK}/php-9.9.8.tar.gz" \
    php -n "${WORK}/harness.php" 2>"${WORK}/harness.err")"
  HARNESS_ERR="$(head -c 400 "${WORK}/harness.err")"
  while IFS='=' read -r k v; do
    [[ -n "${k}" ]] && R["${k}"]="${v}"
  done <<<"${out}"
  if [[ "${R[DONE]:-}" != "1" ]]; then
    return 2
  fi

  local n bad=0
  for n in "${CHECK_NAMES[@]}"; do CHECK_OK["${n}"]=1; done
  if [[ -z "${R[TMP_A]}" || "${R[TMP_A]}" == "${R[TMP_B]}" ]]; then
    CHECK_OK["unique-temp-dir"]=0
    CHECK_WHY["unique-temp-dir"]="both tasks used '${R[TMP_A]##*/}'"
  fi
  if [[ "${R[B_TMP_AFTER_A_GONE]}" != "1" ]]; then
    CHECK_OK["destructor-isolation"]=0
    CHECK_WHY["destructor-isolation"]="B's temp dir was gone after A's destructor ran"
  fi
  if [[ "${R[A_TMP_AFTER_A_GONE]}" != "0" || "${R[B_TMP_AFTER_B_GONE]}" != "0" ]]; then
    CHECK_OK["own-cleanup"]=0
    CHECK_WHY["own-cleanup"]="a task's own temp dir survived its destructor"
  fi
  if [[ "${R[LEAK]}" != "0" ]]; then
    CHECK_OK["no-leak"]=0
    CHECK_WHY["no-leak"]="${R[LEAK]} tmp.* dir(s) left in the build dir"
  fi
  if [[ "${R[CNT_A]}" != "${EXPECT_FILES}" || "${R[CNT_B]}" != "${EXPECT_FILES}" || "${R[CFG_A]}" != "1" || "${R[CFG_B]}" != "1" ]]; then
    CHECK_OK["complete-trees"]=0
    CHECK_WHY["complete-trees"]="extracted ${R[CNT_A]}/${R[CNT_B]} files, want ${EXPECT_FILES}"
  fi
  for n in "${CHECK_NAMES[@]}"; do
    [[ "${CHECK_OK[${n}]}" == "1" ]] || bad=1
  done
  return "${bad}"
}

failing_checks() {
  local n out=()
  for n in "${CHECK_NAMES[@]}"; do
    [[ "${CHECK_OK[${n}]}" == "1" ]] || out+=("${n}")
  done
  local IFS=,
  printf '%s' "${out[*]}"
}

# ------------------------------------------------------------------ tests --
section "1. the overlay file exists and parses"
if [[ -f "${OVERLAY}" ]]; then
  ok "overlay present: ${OVERLAY#"${REPO}"/}"
else
  ko "overlay missing: ${OVERLAY#"${REPO}"/}"
fi
if [[ -f "${OVERLAY}" ]] && php -n -l "${OVERLAY}" >/dev/null 2>&1; then
  ok "overlay passes php -l"
else
  ko "overlay does not pass php -l"
fi

section "2. the real overlay, under a frozen clock and a frozen PID"
if [[ -f "${OVERLAY}" ]]; then
  evaluate "${OVERLAY}"
  rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    ko "harness produced no result against the overlay: ${HARNESS_ERR}"
  else
    for n in "${CHECK_NAMES[@]}"; do
      if [[ "${CHECK_OK[${n}]}" == "1" ]]; then
        ok "${n}"
      else
        ko "${n}: ${CHECK_WHY[${n}]}"
      fi
    done
  fi
fi

section "3. mutants of the overlay must each go RED (the harness can tell)"
# mutant <label> <literal-to-remove-or-replace> <replacement> <expected failing check>
# The mutation is verified to have LANDED (the file differs) and to still parse:
# a mutant that failed to apply or to compile would leave the suite green or red
# for a reason unrelated to the guarantee.
mutant() {
  local label="$1" from="$2" to="$3" want="$4" body mfile rc
  [[ -f "${OVERLAY}" ]] || {
    ko "mutant '${label}': overlay missing"
    return
  }
  body="$(<"${OVERLAY}")"
  if [[ "${body}" != *"${from}"* ]]; then
    ko "mutant '${label}': mutation anchor not found in the overlay (nothing to mutate)"
    return
  fi
  mfile="${WORK}/mutant.$RANDOM.php"
  printf '%s\n' "${body/"${from}"/"${to}"}" >"${mfile}"
  if cmp -s "${OVERLAY}" "${mfile}"; then
    ko "mutant '${label}': mutation did not change the file"
    return
  fi
  if ! php -n -l "${mfile}" >/dev/null 2>&1; then
    ko "mutant '${label}': mutant does not parse, so it tests nothing"
    return
  fi
  evaluate "${mfile}"
  rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    ko "mutant '${label}': harness error, not an assertion failure: ${HARNESS_ERR}"
  elif [[ "${rc}" -eq 0 ]]; then
    ko "mutant '${label}': suite stayed GREEN - the guarantee is not being checked"
  elif [[ ",$(failing_checks)," == *",${want},"* ]]; then
    ok "mutant '${label}' → red on: $(failing_checks)"
  else
    ko "mutant '${label}' went red on '$(failing_checks)', expected it to include '${want}'"
  fi
}
RANDOM_SUFFIX=" . '.' . bin2hex(random_bytes(6))"
mutant "back to upstream: tmp.<time()> only" "${RANDOM_SUFFIX}" "" unique-temp-dir
mutant "PID-based suffix" "bin2hex(random_bytes(6))" "getmypid()" unique-temp-dir
# The single quotes are deliberate: the anchor is literal PHP text, and "$this" must not expand.
# shellcheck disable=SC2016
mutant "temp dir never scheduled for removal" '$this->rmDirs[] = $extractDirTemp;' '' own-cleanup

section "4. the pristine upstream 2.2.0 file reproduces the real bug"
if git -C "${PHPBREW_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "${PHPBREW_SRC}" show HEAD:src/PhpBrew/Tasks/ExtractTask.php >"${WORK}/upstream.php" 2>/dev/null; then
    evaluate "${WORK}/upstream.php"
    rc=$?
    if [[ "${rc}" -eq 1 && ",$(failing_checks)," == *",unique-temp-dir,"* && ",$(failing_checks)," == *",destructor-isolation,"* ]]; then
      ok "upstream collides: $(failing_checks)"
    else
      ko "upstream file did not reproduce the collision (rc=${rc}, failing: $(failing_checks)) ${HARNESS_ERR}"
    fi
    # The overlay may differ from upstream by exactly one hunk.
    if [[ -f "${OVERLAY}" ]]; then
      hunks="$(diff -U0 "${WORK}/upstream.php" "${OVERLAY}" | grep -c '^@@')"
      if [[ "${hunks}" -eq 1 ]]; then
        ok "overlay differs from upstream 2.2.0 by exactly one hunk"
      else
        ko "overlay differs from upstream 2.2.0 by ${hunks} hunks, want 1"
      fi
    fi
  else
    skip "upstream ExtractTask.php not readable from ${PHPBREW_SRC} HEAD"
  fi
else
  skip "no phpbrew clone at ${PHPBREW_SRC}: the upstream reproduction and one-hunk check need it"
fi

section "5. the overlay is registered where iou.sh and humans look"
if grep -qE '^ *- src/PhpBrew/Tasks/ExtractTask\.php *$' "${OVERLAY_DIR}/.version"; then
  ok ".version lists src/PhpBrew/Tasks/ExtractTask.php under files:"
else
  ko ".version does not list src/PhpBrew/Tasks/ExtractTask.php"
fi
if grep -q 'ExtractTask' "${OVERLAY_DIR}/OVERRIDE.md"; then
  ok "OVERRIDE.md documents the ExtractTask override"
else
  ko "OVERRIDE.md does not mention ExtractTask"
fi
if [[ -f "${OVERLAY}" ]] && grep -q '# @override_stack' "${OVERLAY}"; then
  ok "overlay carries the # @override_stack marker like the other overlay files"
else
  ko "overlay has no # @override_stack marker"
fi

# ---------------------------------------------------------------- summary --
TOTAL=$((PASS + FAIL))
printf '\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '%bALL PASSED ✓ %d / %d%b' "${C_GREEN}${C_BOLD}" "${PASS}" "${TOTAL}" "${C_RESET}"
  [[ "${SKIP}" -gt 0 ]] && printf '  (%d skipped)' "${SKIP}"
  printf '\n'
  exit 0
fi
printf '%bFAILED ✗ %d of %d%b\n' "${C_RED}${C_BOLD}" "${FAIL}" "${TOTAL}" "${C_RESET}"
for f in "${FAILURES[@]}"; do printf '   - %s\n' "${f}"; done
exit 1
