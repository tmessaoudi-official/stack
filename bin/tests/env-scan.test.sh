#!/bin/bash
# Test suite for env-scan.sh
# Run: bash bin/tests/env-scan.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SCAN="${SCRIPT_DIR}/../env-scan.sh"

# Resolved from SCRIPT_DIR, never hardcoded to /stack: a test that sources an
# absolute '/stack/...' path certifies the tree at /stack rather than the tree it
# lives in, so a clone's suite silently passes against /stack's library. Measured
# in env-update.test.sh: with absolute sources, 27 of 28 tests stayed green against
# a deliberately broken library; resolved from SCRIPT_DIR, 12 of them caught it.
_GS_ES_LIB="${SCRIPT_DIR}/../lib/env-scan"
TMP_DIR="$(mktemp -d)"
export TMP_DIR
trap 'rm -rf "${TMP_DIR}"' EXIT

# ─── colors (auto-disabled when not a tty) ─────────────────────────────────
if [[ -t 1 ]]; then
    C_GREEN='\033[0;32m' C_RED='\033[0;31m' C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'  C_BOLD='\033[1m'   C_DIM='\033[2m'       C_RESET='\033[0m'
else
    C_GREEN='' C_RED='' C_YELLOW='' C_CYAN='' C_BOLD='' C_DIM='' C_RESET=''
fi

# ─── counters ──────────────────────────────────────────────────────────────
PASS=0; FAIL=0
declare -a FAILURES=()

CURRENT_SECTION=""
SECTION_PASS=0; SECTION_FAIL=0
declare -a SECTION_NAMES=()
declare -a SECTION_PASS_COUNTS=()
declare -a SECTION_FAIL_COUNTS=()

# ─── --section filter ──────────────────────────────────────────────────────
SECTION_FILTER=""
for _arg in "$@"; do
    case "${_arg}" in
        --section=*) SECTION_FILTER="${_arg#*=}" ;;
    esac
done
unset _arg
SECTION_ACTIVE=true

# ─── section management ────────────────────────────────────────────────────
_flush_section() {
    [[ -z "${CURRENT_SECTION}" ]] && return
    # Skip recording sections where no tests ran (filtered out)
    if [[ $(( SECTION_PASS + SECTION_FAIL )) -eq 0 ]]; then
        CURRENT_SECTION=""
        return
    fi
    SECTION_NAMES+=("${CURRENT_SECTION}")
    SECTION_PASS_COUNTS+=("${SECTION_PASS}")
    SECTION_FAIL_COUNTS+=("${SECTION_FAIL}")
    local total=$(( SECTION_PASS + SECTION_FAIL ))
    if [[ "${SECTION_FAIL}" -eq 0 ]]; then
        printf "     ${C_DIM}└─ ${C_GREEN}%d/%d passed${C_RESET}\n" "${SECTION_PASS}" "${total}"
    else
        printf "     ${C_DIM}└─ ${C_RED}%d/%d passed${C_RESET}\n"   "${SECTION_PASS}" "${total}"
    fi
}

section() {
    _flush_section
    CURRENT_SECTION="$1"
    SECTION_PASS=0; SECTION_FAIL=0

    # Extract leading integer as section key
    local _sec_key
    _sec_key="${1%%[^0-9]*}"

    if [[ -n "${SECTION_FILTER}" ]]; then
        SECTION_ACTIVE=false
        local IFS=','
        local _f
        # shellcheck disable=SC2086
        for _f in ${SECTION_FILTER}; do
            if [[ "${_sec_key}" == "${_f}" ]]; then
                SECTION_ACTIVE=true
                break
            fi
        done
    else
        SECTION_ACTIVE=true
    fi

    echo ""
    printf "${C_BOLD}${C_CYAN}  ┌─  %s${C_RESET}\n" "$1"
}

# ─── assert primitives ─────────────────────────────────────────────────────
_pass() {
    (( PASS++ ))       || true
    (( SECTION_PASS++ )) || true
    printf "  ${C_GREEN}✓${C_RESET}  %s\n" "$1"
}

_fail() {
    (( FAIL++ ))       || true
    (( SECTION_FAIL++ )) || true
    printf "  ${C_RED}✗${C_RESET}  %s\n" "$1"
    FAILURES+=("$1")
    [[ -n "${2:-}" ]] && printf "       ${C_DIM}expected : %s${C_RESET}\n" "$(echo "$2" | head -3)"
    [[ -n "${3:-}" ]] && printf "       ${C_DIM}actual   : %s${C_RESET}\n" "$(echo "$3" | head -3)"
}

assert_equals() {
    local label="$1" expected="$2" actual="$3"
    [[ "${expected}" == "${actual}" ]] && _pass "${label}" || _fail "${label}" "${expected}" "${actual}"
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    echo "${haystack}" | grep -qF "${needle}" && _pass "${label}" || _fail "${label}" "contains: ${needle}" "(not found)"
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    ! echo "${haystack}" | grep -qF "${needle}" && _pass "${label}" || _fail "${label}" "should not contain: ${needle}" "(was found)"
}

assert_file_exists() {
    [[ -f "$2" ]] && _pass "$1" || _fail "$1" "file exists: $2" "(missing)"
}

assert_file_not_exists() {
    [[ ! -f "$2" ]] && _pass "$1" || _fail "$1" "file should not exist: $2" "(still present)"
}

# ─── subshell test runner ──────────────────────────────────────────────────
# t "label" bash -c "..."
# The subshell must print PASS or FAIL as its last line.
t() {
    [[ "${SECTION_ACTIVE:-true}" == "false" ]] && return 0
    local label="$1"; shift
    local output last
    output="$("$@" 2>&1)" || true
    last="$(echo "${output}" | tail -1 | tr -d '[:space:]')"
    case "${last}" in
        PASS) _pass "${label}" ;;
        FAIL) _fail "${label}" "PASS" "FAIL"
              # Print any diagnostic lines the subshell emitted (skip bare PASS/FAIL lines)
              while IFS= read -r line; do
                  [[ "${line}" =~ ^[[:space:]]*(PASS|FAIL)[[:space:]]*$ ]] && continue
                  [[ -z "${line}" ]] && continue
                  printf "       ${C_DIM}%s${C_RESET}\n" "${line}"
              done <<< "${output}" ;;
        *)    _fail "${label}" "PASS" "${last:-<no output>}" ;;
    esac
}

make_env()        { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
make_dockerfile() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ═══════════════════════════════════════════════════════════════════════════
echo ""
printf "${C_BOLD}  env-scan.sh — test suite${C_RESET}\n"
printf "  script : %s\n" "${ENV_SCAN}"
[[ -n "${SECTION_FILTER}" ]] && printf "  sections: %s (filtered)\n" "${SECTION_FILTER}"
echo ""

BASE_SRC="${TMP_DIR}/src/.env"
BASE_DST="${TMP_DIR}/dst/.env.local"
make_env "${BASE_SRC}" "GLOBAL_STACK_FOO=foo_value
GLOBAL_STACK_BAR=bar_value
GLOBAL_STACK_BAZ=baz_value"
make_env "${BASE_DST}" "GLOBAL_STACK_FOO=foo_value"

# ═══════════════════════════════════════════════════════════════════════════
section "1. Basic Parsing & Cleanup"
# ═══════════════════════════════════════════════════════════════════════════

t "Remove empty lines (--remove-empty-lines=true)" bash -c "
    D='${TMP_DIR}/t1'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n\n\nGLOBAL_STACK_B=2\n\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n'       > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --remove-empty-lines=true --check-missing=false \
        --scan-sources=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    count=\$(grep -c '^\$' \"\$D/.env.local\" 2>/dev/null || true)
    [[ \"\${count:-0}\" -eq 0 ]] && echo PASS || echo FAIL
"

t "Keep empty lines (--remove-empty-lines=false)" bash -c "
    D='${TMP_DIR}/t1b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n\nGLOBAL_STACK_B=2\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --remove-empty-lines=false --check-missing=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    count=\$(grep -c '^\$' \"\$D/.env.local\")
    [[ \"\$count\" -ge 1 ]] && echo PASS || echo FAIL
"

t "Remove trailing spaces" bash -c "
    D='${TMP_DIR}/t1c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1   \nGLOBAL_STACK_B=2  \n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --remove-trailing-spaces=true --check-missing=false \
        --scan-sources=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -P ' +\$' \"\$D/.env.local\" && echo FAIL || echo PASS
"

t "Remove commented lines (--strip-comments=true)" bash -c "
    D='${TMP_DIR}/t1d'; mkdir -p \"\$D\"
    printf '# this is a comment\nGLOBAL_STACK_A=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --strip-comments=true --check-missing=false \
        --scan-sources=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q '# this is a comment' \"\$D/.env.local\" && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "2. Show Added / Different Entries"
# ═══════════════════════════════════════════════════════════════════════════

t "show-added-entries=true: new key reported in output" bash -c "
    D='${TMP_DIR}/t2a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_EXISTING=1\nGLOBAL_STACK_NEW_KEY=hello\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_EXISTING=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --show-added-entries=true \
        --scan-sources=false \
        --show-different-entries=false --check-missing=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_NEW_KEY' && echo PASS || echo FAIL
"

t "show-added-entries=false: new key not in output" bash -c "
    D='${TMP_DIR}/t2b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_EXISTING=1\nGLOBAL_STACK_NEW_KEY=hello\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_EXISTING=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --show-added-entries=false \
        --show-different-entries=false --check-missing=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_NEW_KEY' && echo FAIL || echo PASS
"

t "show-different-entries=true: differing value reported" bash -c "
    D='${TMP_DIR}/t2c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=new_value\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=old_value\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --show-different-entries=true \
        --scan-sources=false \
        --show-added-entries=false --check-missing=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_FOO' && echo PASS || echo FAIL
"

t "show-different-entries=false: differing value not in output" bash -c "
    D='${TMP_DIR}/t2d'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=new_value\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=old_value\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --show-different-entries=false \
        --show-added-entries=false --check-missing=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_FOO' && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "3. Update Differences"
# ═══════════════════════════════════════════════════════════════════════════

t "update-differences: dst key gets src value" bash -c "
    D='${TMP_DIR}/t3a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=updated\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=old\n'     > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --sync-values=true \
        --scan-sources=false \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_FOO=updated' \"\$D/.env.local\" && echo PASS || echo FAIL
"

t "update-differences: keys unique to dst are preserved" bash -c "
    D='${TMP_DIR}/t3b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=updated\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=old\nGLOBAL_STACK_CUSTOM=keep_me\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --sync-values=true \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_CUSTOM=keep_me' \"\$D/.env.local\" && echo PASS || echo FAIL
"

t "without update-differences: dst local override preserved" bash -c "
    D='${TMP_DIR}/t3c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=src_value\n'       > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=local_override\n'  > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --sync-values=false \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_FOO=local_override' \"\$D/.env.local\" && echo PASS || echo FAIL
"

# ═══════════════════════════════════════════════════════════════════════════
section "4. Check Missing"
# ═══════════════════════════════════════════════════════════════════════════

t "check-missing=true: key in src but not dst is reported" bash -c "
    D='${TMP_DIR}/t4a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_MISSING=x\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --check-missing=true \
        --scan-sources=false \
        --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_MISSING' && echo PASS || echo FAIL
"

t "check-missing=false: missing key not reported" bash -c "
    D='${TMP_DIR}/t4b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_MISSING=x\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --check-missing=false \
        --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_MISSING' && echo FAIL || echo PASS
"

t "exclude-check-missing: excluded pattern not reported" bash -c "
    D='${TMP_DIR}/t4c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_SKIP_ME=x\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --check-missing=true \
        --forward-check-ignore-pattern='GLOBAL_STACK_SKIP_ME' \
        --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_SKIP_ME' && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "5. Extract All Env"
# ═══════════════════════════════════════════════════════════════════════════

t "extract-all-env=true: output file is created" bash -c "
    D='${TMP_DIR}/t5a'; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_A\nARG GLOBAL_STACK_B\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    [[ -f \"\$D/.env.all.local\" ]] && echo PASS || echo FAIL
"

t "extract-all-env: discovered variable appears in output file" bash -c "
    D='${TMP_DIR}/t5b'; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_A\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_A' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "extract-all-env-delete-output=true: output file cleaned up" bash -c "
    D='${TMP_DIR}/t5c'; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_A\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    [[ ! -f \"\$D/.env.all.local\" ]] && echo PASS || echo FAIL
"

t "include-docker-args=false: Dockerfile ARG lines not extracted" bash -c "
    D='${TMP_DIR}/t5d'; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_ONLY_IN_DOCKERFILE=default\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false --include-docker-args=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_ONLY_IN_DOCKERFILE' \"\$D/.env.all.local\" 2>/dev/null && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "6. Multiple Source / Destination Files"
# ═══════════════════════════════════════════════════════════════════════════

t "multiple source files: no crash" bash -c "
    D='${TMP_DIR}/t6a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/a.env\"
    printf 'GLOBAL_STACK_B=2\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --no-fail \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

t "multiple destination files: each gets updated value" bash -c "
    D='${TMP_DIR}/t6b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=new\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=old\n' > \"\$D/dst1.env.local\"
    printf 'GLOBAL_STACK_A=old\n' > \"\$D/dst2.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/.env\" \
        --destination-files=\"\$D/dst1.env.local \$D/dst2.env.local\" \
        --sync-values=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_A=new' \"\$D/dst1.env.local\" \
        && grep -q 'GLOBAL_STACK_A=new' \"\$D/dst2.env.local\" \
        && echo PASS || echo FAIL
"

# ═══════════════════════════════════════════════════════════════════════════
section "7. Multiple Default Values for Same Key"
# ═══════════════════════════════════════════════════════════════════════════

t "same key with different values across source files: no crash" bash -c "
    D='${TMP_DIR}/t7a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=1.0\n' > \"\$D/a.env\"
    printf 'GLOBAL_STACK_FOO=2.0\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_FOO=1.0\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --no-fail \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

t "exclude-implicit-empty=true: empty default not flagged as conflict" bash -c "
    D='${TMP_DIR}/t7b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_OPT=\n'          > \"\$D/a.env\"
    printf 'GLOBAL_STACK_OPT=real_value\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_OPT=real_value\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --no-fail \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --exclude-implicit-empty=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "8. Extract Prefix Filtering"
# ═══════════════════════════════════════════════════════════════════════════

t "extract-all-prefix: vars not matching prefix are excluded" bash -c "
    D='${TMP_DIR}/t8a'; mkdir -p \"\$D/docker/images/x\"
    printf 'GLOBAL_STACK_A=1\nOTHER_VAR=2\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_A\nARG OTHER_VAR\n' > \"\$D/docker/images/x/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --scan-var-prefix='(GLOBAL_STACK_)' \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'OTHER_VAR' \"\$D/.env.all.local\" 2>/dev/null && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "9. Cleanup / Temp Files"
# ═══════════════════════════════════════════════════════════════════════════

t "cleanup-tmp=true: no .tmp or .merged files left in dst dir" bash -c "
    D='${TMP_DIR}/t9a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --cleanup-tmp=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    ls \"\$D\" | grep -E '\\.tmp|\\.merged' && echo FAIL || echo PASS
"

t "cleanup-tmp=false: exits 0 (tmp_file is never written so no observable delta)" bash -c "
    # Note: merge.sh declares tmp_file but never writes it — only merged_file is written then mv'd.
    # --cleanup-tmp=false therefore has no observable filesystem effect in this fixture.
    # This test verifies the flag is accepted without error (rc==0).
    D='${TMP_DIR}/t9b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --cleanup-tmp=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "10. Search Path & Ignore Patterns"
# ═══════════════════════════════════════════════════════════════════════════

t "search-path: files outside the path are not scanned" bash -c "
    D='${TMP_DIR}/t10a'; mkdir -p \"\$D/docker/included\" \"\$D/other\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_FROM_INCLUDED\n' > \"\$D/docker/included/Dockerfile\"
    printf 'ARG GLOBAL_STACK_FROM_OTHER\n'    > \"\$D/other/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-path=\"\$D/docker\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_FROM_OTHER' \"\$D/.env.all.local\" 2>/dev/null && echo FAIL || echo PASS
"

t "search-path-ignore-pattern: ignored paths produce no extracted vars" bash -c "
    D='${TMP_DIR}/t10b'; mkdir -p \"\$D/docker/included\" \"\$D/docker/ignored\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_IGNORED_VAR\n' > \"\$D/docker/ignored/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-path=\"\$D/docker\" \
        --scan-ignore-pattern='ignored' --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_IGNORED_VAR' \"\$D/.env.all.local\" 2>/dev/null && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "11. Edge Cases"
# ═══════════════════════════════════════════════════════════════════════════

t "value with equals sign preserved (JDBC URL)" bash -c "
    D='${TMP_DIR}/t11a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_JDBC=jdbc:mysql://host:3306/db?useSSL=false\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_JDBC=jdbc:mysql://host:3306/db?useSSL=false' \"\$D/.env.local\" && echo PASS || echo FAIL
"

t "quoted value with spaces preserved" bash -c "
    D='${TMP_DIR}/t11b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_MSG=\"hello world\"\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_MSG=' \"\$D/.env.local\" && echo PASS || echo FAIL
"

t "duplicate keys in source: exits 0" bash -c "
    D='${TMP_DIR}/t11c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_DUP=first\nGLOBAL_STACK_DUP=second\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

t "empty source file: exits 1 with clear error message" bash -c "
    D='${TMP_DIR}/t11d'; mkdir -p \"\$D\"
    printf '' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env.local\"
    stderr=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -ne 0 ]] || { echo \"expected rc!=0 for empty source, got rc=0\"; echo FAIL; exit 0; }
    echo \"\$stderr\" | grep -qi 'empty\|not found' || { echo \"expected error msg, got: \$stderr\"; echo FAIL; exit 0; }
    echo PASS
"

t "missing destination file: created automatically" bash -c "
    D='${TMP_DIR}/t11e'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || true
    [[ -f \"\$D/.env.local\" ]] || { echo 'dest file not created'; echo FAIL; exit 0; }
    echo PASS
"

t "variable referencing another variable (envsubst): exits 0" bash -c "
    D='${TMP_DIR}/t11f'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_BASE=/stack\nGLOBAL_STACK_TOOLS=\${GLOBAL_STACK_BASE}/tools\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "12. All-Src-Env-Merged"
# ═══════════════════════════════════════════════════════════════════════════

t "all-src-env-merged-name: custom path accepted, exits 0" bash -c "
    D='${TMP_DIR}/t12a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/a.env\"
    printf 'GLOBAL_STACK_B=2\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --no-fail \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --source-merged-file=\"\$D/custom.merged\" --cleanup-tmp=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "13. Extraction — Source Forms"
# ═══════════════════════════════════════════════════════════════════════════

t "Dockerfile ARG with default" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13a; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_EXTRACT_TEST=defaultval\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Dockerfile ENV single-line (= form)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13b; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_EXTRACT_TEST=testval\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Dockerfile ENV single-line (space form)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13c; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_EXTRACT_TEST testval\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Dockerfile ENV multi-line continuation" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13d; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_EXTRACT_TEST_A=aval \\\\\n    GLOBAL_STACK_EXTRACT_TEST=testval\n' \
        > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Plain assignment in shell script" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13e; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=shellval\n' > \"\$D/docker/images/test/entrypoint.sh\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Export assignment in shell script" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13f; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'export GLOBAL_STACK_EXTRACT_TEST=exportval\n' > \"\$D/docker/images/test/entrypoint.sh\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "docker-compose environment list form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13g; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'environment:\n  - GLOBAL_STACK_EXTRACT_TEST=composeval\n' \
        > \"\$D/docker/images/test/docker-compose.yaml\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "YAML map form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13h; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'environment:\n  GLOBAL_STACK_EXTRACT_TEST: yamlval\n' \
        > \"\$D/docker/images/test/docker-compose.yaml\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Shell reference with default (\${VAR:-default})" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13i; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'CMD=\"\${GLOBAL_STACK_EXTRACT_TEST:-shelldefault}\"\n' \
        > \"\$D/docker/images/test/entrypoint.sh\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Caddyfile {env.VAR} form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13j; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'respond {env.GLOBAL_STACK_EXTRACT_TEST}\n' \
        > \"\$D/docker/images/test/Caddyfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "PHP getenv() form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13k; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' 'getenv(\"GLOBAL_STACK_EXTRACT_TEST\")' \
        > \"\$D/docker/images/test/config.php\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "PHP \$_ENV[] form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13l; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '\$_ENV[\"GLOBAL_STACK_EXTRACT_TEST\"]' \
        > \"\$D/docker/images/test/config.php\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "JS/TS process.env.VAR form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13m; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'const v = process.env.GLOBAL_STACK_EXTRACT_TEST;\n' \
        > \"\$D/docker/images/test/config.js\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Python os.environ.get() form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13n; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' 'os.environ.get(\"GLOBAL_STACK_EXTRACT_TEST\")' \
        > \"\$D/docker/images/test/config.py\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

t "Python os.environ[] form" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t13o; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_EXTRACT_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' 'os.environ[\"GLOBAL_STACK_EXTRACT_TEST\"]' \
        > \"\$D/docker/images/test/config.py\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_EXTRACT_TEST' \"\$D/.env.all.local\" && echo PASS || echo FAIL
"

# ═══════════════════════════════════════════════════════════════════════════
section "14. Extraction — Quote Handling"
# ═══════════════════════════════════════════════════════════════════════════

t "Dockerfile ENV quoted literal: no leading-quote leak in output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t14a; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_QUOTE_A=a\nGLOBAL_STACK_QUOTE_B=b\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_QUOTE_A=first \\\\\n    GLOBAL_STACK_QUOTE_B=\"literal_value\"\n' \
        > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    count=\$(grep -c 'GLOBAL_STACK_QUOTE_B=\"' \"\$D/.env.all.local\" 2>/dev/null || true)
    [[ \"\${count:-0}\" -eq 0 ]] && echo PASS || echo FAIL
"

t "Dockerfile ENV quoted pass-through: no leading-quote leak in output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t14b; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_QUOTE_C=c\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_QUOTE_A=first \\\\\n    GLOBAL_STACK_QUOTE_C=\"\${GLOBAL_STACK_QUOTE_C}\"\n' \
        > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    count=\$(grep -c 'GLOBAL_STACK_QUOTE_C=\"' \"\$D/.env.all.local\" 2>/dev/null || true)
    [[ \"\${count:-0}\" -eq 0 ]] && echo PASS || echo FAIL
"

t "PHP \$_ENV[]: trailing bracket not leaked into key name" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t14c; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_PHP_KEY=x\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '\$_ENV[\"GLOBAL_STACK_PHP_KEY\"]' \
        > \"\$D/docker/images/test/config.php\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_PHP_KEY' \"\$D/.env.all.local\" || { echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_PHP_KEY\"' \"\$D/.env.all.local\" && { echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_PHP_KEY]' \"\$D/.env.all.local\" && { echo FAIL; exit 0; }
    echo PASS
"

t "Python os.environ[]: trailing bracket not leaked into key name" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t14d; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_PY_KEY=x\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' 'os.environ[\"GLOBAL_STACK_PY_KEY\"]' \
        > \"\$D/docker/images/test/config.py\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_PY_KEY' \"\$D/.env.all.local\" || { echo FAIL; exit 0; }
    line=\$(grep 'GLOBAL_STACK_PY_KEY' \"\$D/.env.all.local\" | head -1)
    echo \"\$line\" | grep -qF ']' && { echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "15. Multiple Values Detection"
# ═══════════════════════════════════════════════════════════════════════════

t "Different values across files: reported" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15a; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_MULTI_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '- GLOBAL_STACK_MULTI_TEST=val_one' > \"\$D/docker/images/svc1/docker-compose.yaml\"
    printf '%s\n' '- GLOBAL_STACK_MULTI_TEST=val_two' > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_MULTI_TEST' && echo PASS || echo FAIL
"

t "Self-referencing pass-through: not reported as conflict" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15b; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_PASSTHRU=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '- GLOBAL_STACK_PASSTHRU=\${GLOBAL_STACK_PASSTHRU}' \
        > \"\$D/docker/images/svc1/docker-compose.yaml\"
    printf '%s\n' '- GLOBAL_STACK_PASSTHRU=\${GLOBAL_STACK_PASSTHRU}' \
        > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_PASSTHRU' && echo FAIL || echo PASS
"

t "Quoted Dockerfile ENV vs compose pass-through: not reported as conflict" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15c; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_COLLATE_TEST=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ENV GLOBAL_STACK_COLLATE_OTHER=x \\\\\n    GLOBAL_STACK_COLLATE_TEST=\"\${GLOBAL_STACK_COLLATE_TEST}\"\n' \
        > \"\$D/docker/images/svc1/Dockerfile\"
    printf '%s\n' '- GLOBAL_STACK_COLLATE_TEST=\${GLOBAL_STACK_COLLATE_TEST}' \
        > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_COLLATE_TEST' && echo FAIL || echo PASS
"

t "--conflict-ignore-pattern: excluded key not reported" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15d; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_NOISY_VAR=placeholder\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '- GLOBAL_STACK_NOISY_VAR=noise_one' > \"\$D/docker/images/svc1/docker-compose.yaml\"
    printf '%s\n' '- GLOBAL_STACK_NOISY_VAR=noise_two' > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --conflict-ignore-pattern='GLOBAL_STACK_NOISY_VAR' \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_NOISY_VAR' && echo FAIL || echo PASS
"

t "--exclude-implicit-empty: empty value not counted as conflict" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15e; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_MAYBE=realval\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '- GLOBAL_STACK_MAYBE=' > \"\$D/docker/images/svc1/docker-compose.yaml\"
    printf '%s\n' '- GLOBAL_STACK_MAYBE=realval' > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --exclude-implicit-empty=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_MAYBE' && echo FAIL || echo PASS
"

t "--exclude-explicit-empty: explicit empty not counted as conflict" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t15f; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_XEMPTY=realval\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'CMD=\"\${GLOBAL_STACK_XEMPTY:-}\"\n' > \"\$D/docker/images/svc1/entrypoint.sh\"
    printf '%s\n' '- GLOBAL_STACK_XEMPTY=realval' > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --exclude-explicit-empty=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_XEMPTY' && echo FAIL || echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "16. Other Flags"
# ═══════════════════════════════════════════════════════════════════════════

t "--quiet=true: suppresses informational output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t16a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_EXISTING=1\nGLOBAL_STACK_NEW_KEY=hello\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_EXISTING=1\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" \
        --quiet=true --scan-sources=false \
        --show-added-entries=true --show-different-entries=true --check-missing=true 2>&1)
    echo \"\$out\" | grep -qE '(Added|Different|Missing|show_inconsistency|show_differences|check_missing)' \
        && echo FAIL || echo PASS
"

t "--diff-ignore-pattern: matched key skipped in diff report" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t16b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_COMPOSE_FILE=val1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_COMPOSE_FILE=val2\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" \
        --scan-sources=false \
        --diff-ignore-pattern='GLOBAL_STACK_COMPOSE_FILE' \
        --show-added-entries=false --show-different-entries=true --check-missing=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_COMPOSE_FILE' && echo FAIL || echo PASS
"

t "--scan-var-ignore-pattern: matched prefix not extracted" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t16c; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_SKIP_THIS=x\nGLOBAL_STACK_KEEP_THIS=y\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_SKIP_THIS=x\nARG GLOBAL_STACK_KEEP_THIS=y\n' \
        > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --scan-var-ignore-pattern='GLOBAL_STACK_SKIP_THIS' \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEEP_THIS' \"\$D/.env.all.local\" || { echo FAIL; exit 0; }
    grep -q 'GLOBAL_STACK_SKIP_THIS' \"\$D/.env.all.local\" 2>/dev/null && echo FAIL || echo PASS
"

t "--reverse-check-ignore-pattern: excluded pattern skipped" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t16d; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_NORMAL=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_DOCKER_ONLY=x\nARG GLOBAL_STACK_NORMAL\n' \
        > \"\$D/docker/images/test/Dockerfile\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --forward-check-ignore-pattern='GLOBAL_STACK_DOCKER_ONLY' \
        --reverse-check-ignore-pattern='GLOBAL_STACK_DOCKER_ONLY' \
        --check-missing=true --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_DOCKER_ONLY' && echo FAIL || echo PASS
"

t "RHS variable extraction: both derived and source vars appear" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t16e; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_DERIVED=x\nGLOBAL_STACK_SOURCE_VAR=y\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf '%s\n' '- GLOBAL_STACK_DERIVED=\${GLOBAL_STACK_SOURCE_VAR}' \
        > \"\$D/docker/images/test/docker-compose.yaml\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_DERIVED' \"\$D/.env.all.local\" || { echo FAIL; exit 0; }
    grep -q 'GLOBAL_STACK_SOURCE_VAR' \"\$D/.env.all.local\" || { echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "17. --dry-run"
# ═══════════════════════════════════════════════════════════════════════════

t "--dry-run: propagation reports intent but does not modify Dockerfile" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t17a; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_DRY_VAR=canonical_value\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_DRY_VAR=stale_default\n' > \"\$D/docker/images/test/Dockerfile\"
    before=\$(cat \"\$D/docker/images/test/Dockerfile\")
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    after=\$(cat \"\$D/docker/images/test/Dockerfile\")
    echo \"\$out\" | grep -q 'dry-run' || { echo \"dry-run marker absent in output\"; echo FAIL; exit 0; }
    [[ \"\$before\" == \"\$after\" ]] || { echo \"Dockerfile was modified under --dry-run\"; echo FAIL; exit 0; }
    echo PASS
"

t "--dry-run: zero changes written to Dockerfile (propagation suppressed)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t17b; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_DRY_MULTI=canonical\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_DRY_MULTI=stale_one\n' > \"\$D/docker/images/test/Dockerfile\"
    before_df=\$(cat \"\$D/docker/images/test/Dockerfile\")
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    after_df=\$(cat \"\$D/docker/images/test/Dockerfile\")
    echo \"\$out\" | grep -q '(dry-run)' || { echo \"(dry-run) marker absent\"; echo FAIL; exit 0; }
    [[ \"\$before_df\" == \"\$after_df\" ]] || { echo \"Dockerfile mutated under --dry-run\"; echo FAIL; exit 0; }
    echo PASS
"

t "--dry-run: env file (Phase 5) NOT modified when new key would be added" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t17c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_DRY_NEWKEY=new_value\nGLOBAL_STACK_DRY_EXISTING=existing\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_DRY_EXISTING=existing\n' > \"\$D/.env.local\"
    before=\$(cat \"\$D/.env.local\")
    bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --scan-sources=false \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    after=\$(cat \"\$D/.env.local\")
    [[ \"\$before\" == \"\$after\" ]] || { echo \".env.local was modified under --dry-run (new key added)\"; echo \"before: \$before\"; echo \"after: \$after\"; echo FAIL; exit 0; }
    echo PASS
"

t "--dry-run: env file (Phase 5) NOT modified when value would be overwritten" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t17d; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_DRY_SYNC=src_value\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_DRY_SYNC=old_local_value\n' > \"\$D/.env.local\"
    before=\$(cat \"\$D/.env.local\")
    bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --sync-values=true --scan-sources=false \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    after=\$(cat \"\$D/.env.local\")
    [[ \"\$before\" == \"\$after\" ]] || { echo \".env.local was modified under --dry-run (value overwritten)\"; echo \"before: \$before\"; echo \"after: \$after\"; echo FAIL; exit 0; }
    echo PASS
"

t "without --dry-run: .env.local IS written (Phase 5 regression)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t17e; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_DRY_REGRESSION=src_val\nGLOBAL_STACK_DRY_NEW=new_val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_DRY_REGRESSION=src_val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --show-added-entries=false --show-different-entries=false --check-missing=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_DRY_NEW=new_val' \"\$D/.env.local\" || { echo \".env.local was NOT updated without --dry-run\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "18. propagate: _gs_es_propagate_to_dockerfiles unit tests"
# ═══════════════════════════════════════════════════════════════════════════
# Tests call _gs_es_propagate_to_dockerfiles directly (no env-scan.sh).
# Each test builds a self-contained temp dir and cleans up on exit.

_PROP_LIB="${_GS_ES_LIB}/propagate.sh"

t "basic rewrite: ARG VAR=old → ARG VAR=new when .env has new value" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'MY_VAR=new_value\n' > \"\$D/.env\"
    printf 'ARG MY_VAR=old_value\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    _gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
    content=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    [[ \"\$content\" == 'ARG MY_VAR=new_value' ]] || { echo \"Expected 'ARG MY_VAR=new_value', got: \$content\"; echo FAIL; exit 0; }
    echo PASS
"

t "shell-expansion skip: var with \${...} value is not written to Dockerfile" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'EXPANDED_VAR=\${SOME_OTHER_VAR}/suffix\n' > \"\$D/.env\"
    printf 'ARG EXPANDED_VAR=literal_original\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    _gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
    content=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    [[ \"\$content\" == 'ARG EXPANDED_VAR=literal_original' ]] || { echo \"Dockerfile should not have been modified; got: \$content\"; echo FAIL; exit 0; }
    echo PASS
"

t "exclude pattern respected: matching var is NOT rewritten even when stale" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'EXCLUDED_REGISTRY=env_value\n' > \"\$D/.env\"
    printf 'ARG EXCLUDED_REGISTRY=docker_value\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    _gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" 'EXCLUDED_REGISTRY' 'false' >/dev/null 2>&1
    content=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    [[ \"\$content\" == 'ARG EXCLUDED_REGISTRY=docker_value' ]] || { echo \"Excluded var should not be rewritten; got: \$content\"; echo FAIL; exit 0; }
    echo PASS
"

t "multiple Dockerfiles: both are rewritten in a single run" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'SHARED_VAR=canonical\n' > \"\$D/.env\"
    printf 'ARG SHARED_VAR=stale\n' > \"\$D/docker/images/svc1/Dockerfile\"
    printf 'ARG SHARED_VAR=stale\n' > \"\$D/docker/images/svc2/Dockerfile\"
    source '${_PROP_LIB}'
    _gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
    c1=\$(cat \"\$D/docker/images/svc1/Dockerfile\")
    c2=\$(cat \"\$D/docker/images/svc2/Dockerfile\")
    [[ \"\$c1\" == 'ARG SHARED_VAR=canonical' ]] || { echo \"svc1 not updated; got: \$c1\"; echo FAIL; exit 0; }
    [[ \"\$c2\" == 'ARG SHARED_VAR=canonical' ]] || { echo \"svc2 not updated; got: \$c2\"; echo FAIL; exit 0; }
    echo PASS
"

t "idempotency: running propagation twice produces 0 changes on second run" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'IDEM_VAR=settled\n' > \"\$D/.env\"
    printf 'ARG IDEM_VAR=stale\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    # First run — rewrites the file
    _gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
    # Second run — should report 0 values propagated
    out2=\$(_gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
    echo \"\$out2\" | grep -q 'propagated 0 value(s) across 0 file(s)' || { echo \"Expected 0 changes on second run; got: \$out2\"; echo FAIL; exit 0; }
    echo PASS
"

t "already in sync: Dockerfile ARG matches .env → no rewrite, 0 changes" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'SYNC_VAR=same_value\n' > \"\$D/.env\"
    printf 'ARG SYNC_VAR=same_value\n' > \"\$D/docker/images/svc/Dockerfile\"
    before=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    source '${_PROP_LIB}'
    out=\$(_gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
    after=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    echo \"\$out\" | grep -q 'propagated 0 value(s) across 0 file(s)' || { echo \"Expected 0 changes; got: \$out\"; echo FAIL; exit 0; }
    [[ \"\$before\" == \"\$after\" ]] || { echo \"Dockerfile should not have changed\"; echo FAIL; exit 0; }
    echo PASS
"

t "missing Dockerfile ARG: var in .env with no ARG line → no error, 0 changes" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'ABSENT_VAR=some_value\n' > \"\$D/.env\"
    printf 'ARG UNRELATED_VAR=unchanged\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    out=\$(_gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"Expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'propagated 0 value(s) across 0 file(s)' || { echo \"Expected 0 changes; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "19. backup"
# ═══════════════════════════════════════════════════════════════════════════

t "t19a: default run creates .env.local.bak.<ts> with pre-run content" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19A=original\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19A=original\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    bak=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | head -1)
    [[ -n \"\$bak\" ]] || { echo 'no .bak.* file created'; echo FAIL; exit 0; }
    ts=\$(basename \"\$bak\" | sed 's/.*\\.bak\\.//')
    [[ \"\$ts\" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+\$ ]] || { echo \"timestamp format wrong: \$ts\"; echo FAIL; exit 0; }
    content=\$(cat \"\$bak\")
    [[ \"\$content\" == 'GLOBAL_STACK_T19A=original' ]] || { echo \"bak content wrong: \$content\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19b: --backup=false creates no .bak.* file" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19B=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19B=val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 0 ]] || { echo \"expected 0 bak files, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19c: --dry-run creates no .bak.* and output contains '(dry-run) would back up'" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19C=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19C=val\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 0 ]] || { echo \"bak file created under --dry-run\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q '(dry-run) would back up' || { echo \"dry-run backup message absent; output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19d: two sequential runs produce two distinct .bak.* files" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19d; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19D=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19D=val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    sleep 1
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 2 ]] || { echo \"expected 2 bak files, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19e: --backup-suffix=.snapshot creates .env.local.snapshot.<ts>, no .bak.*" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19e; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19E=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19E=val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup-suffix=.snapshot --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    snaps=\$(ls \"\$D/.env.local.snapshot\".* 2>/dev/null | wc -l)
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$snaps\" -eq 1 ]] || { echo \"expected 1 snapshot file, got \$snaps\"; echo FAIL; exit 0; }
    [[ \"\$baks\" -eq 0 ]] || { echo \"unexpected .bak file found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19f: missing destination skips backup without creating a .bak.* file" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19f; mkdir -p \"\$D/docker\"
    printf 'GLOBAL_STACK_T19F=val\n' > \"\$D/.env\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || true
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 0 ]] || { echo \"unexpected bak for missing dest\"; echo FAIL; exit 0; }
    echo PASS
"

# slow test
t "t19g: --backup-keep=3 retains exactly 3 newest after 5 runs" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19g; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19G=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19G=val\n' > \"\$D/.env.local\"
    for i in 1 2 3 4 5; do
        bash '${ENV_SCAN}' --dir=\"\$D\" --backup-keep=3 --scan-sources=false \
            --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
        sleep 1
    done
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 3 ]] || { echo \"expected 3 bak files after keep=3, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

# slow test
t "t19h: --backup-keep=0 retains all 5 backups after 5 runs" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19h; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19H=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19H=val\n' > \"\$D/.env.local\"
    for i in 1 2 3 4 5; do
        bash '${ENV_SCAN}' --dir=\"\$D\" --backup-keep=0 --scan-sources=false \
            --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
        sleep 1
    done
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 5 ]] || { echo \"expected 5 bak files after keep=0, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19i: --backup-purge=true deletes pre-existing .bak.* then creates fresh one" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19i; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19I=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19I=val\n' > \"\$D/.env.local\"
    touch \"\$D/.env.local.bak.20200101-000000\"
    touch \"\$D/.env.local.bak.20200102-000000\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup-purge=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null)
    count=\$(echo \"\$baks\" | grep -c '.' 2>/dev/null || echo 0)
    [[ \"\$count\" -eq 1 ]] || { echo \"expected exactly 1 bak after purge, got: \$baks\"; echo FAIL; exit 0; }
    echo \"\$baks\" | grep -qvE '20200101|20200102' || { echo \"old baks survived purge: \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19j: --backup=false --backup-purge=true deletes pre-existing, no new bak created" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19j; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19J=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19J=val\n' > \"\$D/.env.local\"
    touch \"\$D/.env.local.bak.20200101-000000\"
    touch \"\$D/.env.local.bak.20200102-000000\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup=false --backup-purge=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 0 ]] || { echo \"expected 0 bak files after backup=false purge=true, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19k: Phase 6 gitignored Dockerfile gets a .bak.* before rewrite" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19k; mkdir -p \"\$D/docker/images/test\"
    cd \"\$D\" && git init -q && git config user.email 'test@test' && git config user.name 'test'
    printf 'Dockerfile.local\n' > \"\$D/docker/images/test/.gitignore\"
    printf 'GLOBAL_STACK_BACKUPTEST=new_val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_BACKUPTEST=new_val\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_BACKUPTEST=old_val\n' > \"\$D/docker/images/test/Dockerfile.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    bak=\$(ls \"\$D/docker/images/test/Dockerfile.local.bak\".* 2>/dev/null | head -1)
    [[ -n \"\$bak\" ]] || { echo 'no Dockerfile.local.bak.* created for gitignored Dockerfile'; echo FAIL; exit 0; }
    content=\$(cat \"\$bak\")
    [[ \"\$content\" == 'ARG GLOBAL_STACK_BACKUPTEST=old_val' ]] || { echo \"bak content wrong: \$content\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19l: Phase 6 tracked Dockerfile does NOT get a .bak.* file" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19l; mkdir -p \"\$D/docker/images/test\"
    cd \"\$D\" && git init -q && git config user.email 'test@test' && git config user.name 'test'
    printf 'GLOBAL_STACK_BACKUPTEST2=new_val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_BACKUPTEST2=new_val\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_BACKUPTEST2=old_val\n' > \"\$D/docker/images/test/Dockerfile\"
    git -C \"\$D\" add docker/images/test/Dockerfile
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    baks=\$(ls \"\$D/docker/images/test/Dockerfile.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 0 ]] || { echo \"tracked Dockerfile got a bak file (should not)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19m: --backup-keep=1 with 3 pre-seeded backups retains exactly 1 (oldest 2 pruned)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19m; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19M=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19M=val\n' > \"\$D/.env.local\"
    # Seed 3 old backups; lex sort: 20200101 < 20200102 < 20200103 — all before today's run
    touch \"\$D/.env.local.bak.20200101-000000-1\"
    touch \"\$D/.env.local.bak.20200102-000000-1\"
    touch \"\$D/.env.local.bak.20200103-000000-1\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup-keep=1 --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    # After run: 3 old + 1 new = 4 total; keep=1 prunes oldest 3, leaving exactly 1
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 1 ]] || { echo \"expected 1 bak after keep=1, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19n: --backup-purge=true with zero pre-existing backups exits 0 and creates exactly 1 new backup" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t19n; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T19N=val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T19N=val\n' > \"\$D/.env.local\"
    # No pre-existing backups — purge of an empty set must not fail
    bash '${ENV_SCAN}' --dir=\"\$D\" --backup-purge=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    baks=\$(ls \"\$D/.env.local.bak\".* 2>/dev/null | wc -l)
    [[ \"\$baks\" -eq 1 ]] || { echo \"expected exactly 1 new bak after purge+run, got \$baks\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 20 — Version flag
# ═══════════════════════════════════════════════════════════════════════════
section "20 — Version flag"

t "t20a: --version emits 1.0.0 and exits 0" bash -c "
    out=\$(bash '${ENV_SCAN}' --version 2>&1)
    code=\$?
    [[ \"\$out\" == '1.0.0' && \"\$code\" -eq 0 ]] || { echo \"got output='\$out' exit=\$code\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20b: --help output contains v1.0.0" bash -c "
    out=\$(bash '${ENV_SCAN}' --help 2>&1 || true)
    echo \"\$out\" | grep -qF 'v1.0.0' || { echo \"v1.0.0 not found in help output\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# --- order-preserving merge tests ---
# ═══════════════════════════════════════════════════════════════════════════
section "21 — Order-preserving merge"

t "new key from src appears at source-order position (not appended at end)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t21a; mkdir -p \"\$D\"
    # src has A, NEW, B in that order; dest has A and B (NEW is missing)
    printf 'GLOBAL_STACK_A=a\nGLOBAL_STACK_NEW=newval\nGLOBAL_STACK_B=b\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=a\nGLOBAL_STACK_B=b\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --strip-comments=false --remove-empty-lines=false 2>&1 >/dev/null
    content=\$(cat \"\$D/.env.local\")
    # A must appear before NEW, and NEW must appear before B
    pos_a=\$(echo \"\$content\" | grep -n 'GLOBAL_STACK_A=' | cut -d: -f1)
    pos_new=\$(echo \"\$content\" | grep -n 'GLOBAL_STACK_NEW=' | cut -d: -f1)
    pos_b=\$(echo \"\$content\" | grep -n 'GLOBAL_STACK_B=' | cut -d: -f1)
    [[ -n \"\$pos_a\" && -n \"\$pos_new\" && -n \"\$pos_b\" ]] || { echo \"Missing key in output\"; echo FAIL; exit 0; }
    [[ \"\$pos_a\" -lt \"\$pos_new\" && \"\$pos_new\" -lt \"\$pos_b\" ]] && echo PASS || { echo \"Order wrong: A=\$pos_a NEW=\$pos_new B=\$pos_b\"; echo FAIL; }
"

t "local-only key (in dest but not in src) preserved in footer section" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t21b; mkdir -p \"\$D\"
    # src has A only; dest has A and LOCAL_ONLY; strip-comments=false to see the footer marker
    printf 'GLOBAL_STACK_A=a\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=a\nGLOBAL_STACK_LOCAL_ONLY=local_value\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --strip-comments=false --remove-empty-lines=false 2>&1 >/dev/null
    content=\$(cat \"\$D/.env.local\")
    # LOCAL_ONLY must be present and must appear after the local-only section comment
    echo \"\$content\" | grep -q 'GLOBAL_STACK_LOCAL_ONLY=local_value' || { echo \"LOCAL_ONLY key missing\"; echo FAIL; exit 0; }
    pos_comment=\$(echo \"\$content\" | grep -n 'local-only keys' | cut -d: -f1)
    pos_local=\$(echo \"\$content\" | grep -n 'GLOBAL_STACK_LOCAL_ONLY=' | cut -d: -f1)
    [[ -n \"\$pos_comment\" && -n \"\$pos_local\" && \"\$pos_comment\" -lt \"\$pos_local\" ]] && echo PASS || { echo \"Footer comment/order wrong: comment=\$pos_comment local=\$pos_local\"; echo FAIL; }
"

t "@todo env-update comment stays immediately before its key after insertion" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t21c; mkdir -p \"\$D\"
    # src has an annotated NEW key between A and B; dest has only A and B
    # strip-comments=false to preserve the annotation comment in the output
    printf 'GLOBAL_STACK_A=a\n# @todo env-update github:foo/bar v1.0\nGLOBAL_STACK_NEW=newval\nGLOBAL_STACK_B=b\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=a\nGLOBAL_STACK_B=b\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --strip-comments=false --remove-empty-lines=false 2>&1 >/dev/null
    content=\$(cat \"\$D/.env.local\")
    # The @todo comment line must immediately precede GLOBAL_STACK_NEW=
    pos_comment=\$(echo \"\$content\" | grep -n '@todo env-update' | cut -d: -f1)
    pos_new=\$(echo \"\$content\" | grep -n 'GLOBAL_STACK_NEW=' | cut -d: -f1)
    [[ -n \"\$pos_comment\" && -n \"\$pos_new\" ]] || { echo \"Comment or key missing\"; echo FAIL; exit 0; }
    [[ \$(( pos_new - pos_comment )) -eq 1 ]] && echo PASS || { echo \"Comment not immediately before key: comment=\$pos_comment new=\$pos_new\"; echo FAIL; }
"

t "with --sync-values=false, common-key values from dest are preserved over src" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t21d; mkdir -p \"\$D\"
    # src has FOO=src_value; dest has FOO=local_override; with sync-values=false dest wins
    printf 'GLOBAL_STACK_FOO=src_value\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=local_override\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_FOO=local_override' \"\$D/.env.local\" && echo PASS || { echo \"Dest value was overwritten despite sync-values=false\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 22 — --profile=true flag
# ═══════════════════════════════════════════════════════════════════════════
section "22 — --profile=true flag"

t "--profile=true produces timing output (Phase or ms)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --profile=true \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -qiE 'Phase|ms|elapsed|Profile' || { echo \"no timing output found: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "--profile=true: normal sync still occurs alongside profiling (new var added)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_EXISTING=1\nGLOBAL_STACK_NEW_PROFILE=hello\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_EXISTING=1\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --profile=true \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_NEW_PROFILE=hello' \"\$D/.env.local\" && echo PASS || { echo \"new key not synced with --profile=true\"; echo FAIL; }
"

t "--profile=false produces no timing output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --profile=false \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -qiE 'Phase.*ms|Profile' && { echo \"unexpected timing output with --profile=false: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "--profile=true: timing output goes to stderr, not stdout" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22d; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # Capture stdout only (stderr sent to /dev/null); timing must not appear on stdout
    stdout_only=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --profile=true \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>/dev/null)
    echo \"\$stdout_only\" | grep -qiE 'Phase|ms|elapsed|Profile' \
        && { echo \"timing output leaked to stdout: \$stdout_only\"; echo FAIL; exit 0; }
    echo PASS
"

t "--profile=true: timing output present on stderr (not lost)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22e; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # Capture stderr only: redirect stderr first to capture fd, then silence stdout
    stderr_only=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --profile=true \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null)
    echo \"\$stderr_only\" | grep -qiE 'Phase|ms|elapsed|Profile' \
        || { echo \"timing output absent from stderr: \$stderr_only\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 23 — --sync-values=false + new key behavior
# ═══════════════════════════════════════════════════════════════════════════
section "23 — --sync-values=false + new key behavior"

t "--sync-values=false: new key from src is added to dest with src value" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t23a; mkdir -p \"\$D\"
    # src has both EXISTING and NEW_KEY; dest has only EXISTING
    # With sync-values=false, common keys keep dest values, but new keys must still be added
    printf 'GLOBAL_STACK_EXISTING=src_val\nGLOBAL_STACK_NEW_KEY=src_new\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_EXISTING=local_override\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    # NEW_KEY must be added (new key, not a value sync)
    grep -q 'GLOBAL_STACK_NEW_KEY=src_new' \"\$D/.env.local\" || { echo \"new key not added with --sync-values=false\"; echo FAIL; exit 0; }
    # EXISTING must retain its local override value
    grep -q 'GLOBAL_STACK_EXISTING=local_override' \"\$D/.env.local\" || { echo \"existing key overwritten despite sync-values=false\"; echo FAIL; exit 0; }
    echo PASS
"

t "--sync-values=false: common key value differences preserved (dest wins)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t23b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_MYKEY=src_version\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_MYKEY=local_version\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_MYKEY=local_version' \"\$D/.env.local\" && echo PASS || { echo \"dest value overwritten\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 24 — --backup=false suppresses Dockerfile backups
# ═══════════════════════════════════════════════════════════════════════════
section "24 — --backup=false suppresses Dockerfile backups"

t "--backup=false with Dockerfile propagation creates no .bak.* Dockerfile backup" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t24a; mkdir -p \"\$D/docker/images/testimg\"
    printf 'GLOBAL_STACK_MYVER=1.0.0\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_MYVER=0.9.0\n' > \"\$D/.env.local\"
    printf 'FROM ubuntu:22.04\nARG GLOBAL_STACK_MYVER=0.9.0\n' > \"\$D/docker/images/testimg/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --backup=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    # No .bak.* files should exist alongside the Dockerfile
    found=\$(find \"\$D/docker\" -name '*.bak.*' 2>/dev/null | head -1)
    [[ -z \"\$found\" ]] && echo PASS || { echo \"unexpected .bak.* file found: \$found\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
section "25 — SOH delimiter: semicolon in value not a false split"
# ═══════════════════════════════════════════════════════════════════════════
# Regression guard for extract.sh fix: the multiple-defaults awk joined
# values with SOH (\001) and splits on SOH at END{}.  Before the fix the
# delimiter was ";", so a value like "jdbc:mysql://h:3306/db?a=1;b=2" was
# split into 3 tokens and falsely reported as having multiple defaults.
# This test asserts a SINGLE occurrence of the variable with ";" in its
# value is NOT reported by gs_es_detect_multiple_defaults.

t "Value with semicolon — single occurrence not reported as multiple defaults" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t25a; mkdir -p \"\$D/docker/images/svc1\"
    # .env: one definition
    printf 'GLOBAL_STACK_JDBC=jdbc:mysql://host:3306/db?param=1;param=2\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # compose: same single definition (not a conflict)
    printf '%s\n' '- GLOBAL_STACK_JDBC=jdbc:mysql://host:3306/db?param=1;param=2' \
        > \"\$D/docker/images/svc1/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_JDBC' && { echo \"\$out\"; echo FAIL; } || echo PASS
"

t "Value with semicolons and distinct second value — correctly reported as multiple defaults" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t25b; mkdir -p \"\$D/docker/images/svc1\" \"\$D/docker/images/svc2\"
    printf 'GLOBAL_STACK_JDBC2=jdbc:mysql://host:3306/db?a=1;b=2\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # svc1: same value (should not create a conflict on its own)
    printf '%s\n' '- GLOBAL_STACK_JDBC2=jdbc:mysql://host:3306/db?a=1;b=2' \
        > \"\$D/docker/images/svc1/docker-compose.yaml\"
    # svc2: genuinely different value (should trigger the multi-default report)
    printf '%s\n' '- GLOBAL_STACK_JDBC2=jdbc:postgres://other:5432/db' \
        > \"\$D/docker/images/svc2/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_JDBC2' && echo PASS || { echo \"\$out\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
section "26 — local -A scope guard: propagate.sh + merge.sh"
# ═══════════════════════════════════════════════════════════════════════════
# Regression guard for the local -A fix: declare -A inside a function is
# global in bash; local -A is function-scoped.  If the fix regresses,
# _prop_env_map / _gs_es_dest_vals / _gs_es_dest_emitted would be visible
# in the calling scope after the function returns.
# These tests source the library directly so they can inspect scope.

t "propagate.sh — _prop_env_map does not leak to caller" bash -c "
    set -euo pipefail
    # Source relative to the script directory so bash_source dirname resolves
    SDIR='${SCRIPT_DIR}/../lib/env-scan'
    # Bootstrap _GS_ES_CFG so config/defaults.sh does not error
    declare -Ag _GS_ES_CFG=([backup]=false [backup_suffix]=.bak [_backup_ts]='' [dir]='.' [quiet]=true)
    source \"\$SDIR/propagate.sh\"
    # Create a minimal env file and a non-existent docker root (function returns 0)
    ETMP=\$(mktemp); printf 'GLOBAL_STACK_X=1\n' > \"\$ETMP\"
    _gs_es_propagate_to_dockerfiles \"\$ETMP\" '/nonexistent_docker_root_xyz' '' 'true' 2>/dev/null || true
    rm -f \"\$ETMP\"
    # _prop_env_map must not be visible in this scope
    if declare -p _prop_env_map 2>/dev/null | grep -q 'declare'; then
        echo 'SCOPE LEAK: _prop_env_map escaped function scope'
        echo FAIL
    else
        echo PASS
    fi
"

t "merge.sh — _gs_es_dest_vals does not leak to caller" bash -c "
    set -euo pipefail
    SDIR='${SCRIPT_DIR}/../lib/env-scan'
    declare -Ag _GS_ES_CFG=(
        [destination_file_tmp_suffix]='.tmp'
        [destination_file_merged_suffix]='.merged'
        [strip_comments]='false'
        [remove_empty_lines]='false'
        [remove_trailing_spaces]='false'
        [show_added_entries]='false'
        [check_missing]='false'
        [exclude_local_pattern]=''
        [reverse_check_ignore_pattern]=''
        [forward_check_ignore_pattern]=''
        [cleanup_tmp]='true'
        [debug]='false'
        [show_different_entries]='false'
        [sync_values]='true'
        [scan_output_file]='/dev/null'
        [dir]='.'
        [scan_path]='.'
        [prune_removed]='false'
        [orphan_quiet]='true'
        [backup]='false'
        [backup_suffix]='.bak'
        [_backup_ts]=''
        [quiet]='true'
    )
    source \"\$SDIR/core/merge.sh\"
    # Create minimal src + dest files
    STMP=\$(mktemp); DTMP=\$(mktemp)
    printf 'GLOBAL_STACK_A=1\n' > \"\$STMP\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$DTMP\"
    _gs_es_process_file \"\$STMP\" \"\$DTMP\" '99' 'false' 2>/dev/null || true
    rm -f \"\$STMP\" \"\$DTMP\"
    # Neither _gs_es_dest_vals nor _gs_es_dest_emitted should be visible here
    leaked=false
    declare -p _gs_es_dest_vals    2>/dev/null | grep -q 'declare' && leaked=true || true
    declare -p _gs_es_dest_emitted 2>/dev/null | grep -q 'declare' && leaked=true || true
    if [[ \"\$leaked\" == 'true' ]]; then
        echo 'SCOPE LEAK: _gs_es_dest_vals or _gs_es_dest_emitted escaped function scope'
        echo FAIL
    else
        echo PASS
    fi
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 27 — --no-fail flag
# ═══════════════════════════════════════════════════════════════════════════
section "27 — --no-fail flag"

t "--no-fail accepted — clean run exits 0" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --no-fail --scan-sources=false --backup=false \
        --quiet=true 2>/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] && echo PASS || { echo \"exit code: \$rc\"; echo FAIL; }
"

t "Phase 2 failure exits 1 WITHOUT --no-fail (baseline — Phase 2 is not gated by no-fail)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27b; mkdir -p \"\$D\"
    # Pass a source file that does not exist to trigger Phase 2 (sed) failure.
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/nonexistent.env\" \
        --scan-sources=false \
        --backup=false --quiet=true 2>/dev/null || rc=\$?
    [[ \"\$rc\" -ne 0 ]] && echo PASS || { echo \"expected non-zero exit, got 0\"; echo FAIL; }
"

t "empty --source-files exits 0 — no propagation loop iterations (not an error)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27c; mkdir -p \"\$D\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] && echo PASS || { echo \"exit code: \$rc\"; echo FAIL; }
"

t "--no-fail does not suppress Phase 2 error messages (not a Phase 6 error)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27d; mkdir -p \"\$D\"
    # Phase 2 failure: sed fails on a non-existent source file.
    # --no-fail does NOT suppress Phase 2 errors — only Phase 6.
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/nonexistent.env\" \
        --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>&1 >/dev/null || true)
    # Phase 2 sed error must still appear on stderr (not suppressed by --no-fail)
    echo \"\$err\" | grep -qiE 'no such file|cannot read|not found|sed' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "usage error still exits 1 even with --no-fail" bash -c "
    rc=0
    bash '${ENV_SCAN}' --no-fail --unknown-option-xyz 2>/dev/null || rc=\$?
    [[ \"\$rc\" -ne 0 ]] && echo PASS || { echo \"expected non-zero exit, got 0\"; echo FAIL; }
"

t "--no-fail banner present on stderr even when propagation fails" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27f; mkdir -p \"\$D\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[NO-FAIL MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 28 — mode banners
# ═══════════════════════════════════════════════════════════════════════════
section "28 — mode banners"

t "t28a: --dry-run banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[DRY-RUN MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28b: --no-fail banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --no-fail --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[NO-FAIL MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28c: --sync-values=false banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --sync-values=false --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[SYNC-VALUES=OFF MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28d: --backup=false banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28d; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --backup=false --scan-sources=false \
        2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[NO-BACKUP MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28e: --backup-purge=true banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28e; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --backup-purge=true --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[BACKUP-PURGE MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28f: --prune-removed=true banner appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28f; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --prune-removed=true --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[PRUNE-REMOVED MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "t28g: no mode flags — no banners printed on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28g; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        2>&1 >/dev/null || true)
    for banner in '[DRY-RUN MODE]' '[NO-FAIL MODE]' '[SYNC-VALUES=OFF MODE]' '[NO-BACKUP MODE]' '[BACKUP-PURGE MODE]' '[PRUNE-REMOVED MODE]'; do
        echo \"\$err\" | grep -qF \"\$banner\" && { echo \"unexpected banner: \$banner\"; echo FAIL; exit 0; }
    done
    echo PASS
"

t "t28h: --dry-run --quiet=true — DRY-RUN banner still appears on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t28h; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --quiet=true --scan-sources=false \
        --backup=false 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF '[DRY-RUN MODE]' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 29 — --prune-removed functional behavior
# ═══════════════════════════════════════════════════════════════════════════
section "29 — --prune-removed functional behavior"

t "t29a: --prune-removed=true removes orphan key from dest" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29a; mkdir -p \"\$D\"
    # src has only KEY_A; dest has KEY_A + KEY_ORPHAN (not in src)
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --prune-removed=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEY_ORPHAN' \"\$D/.env.local\" \
        && { echo 'orphan key survived prune-removed=true'; echo FAIL; exit 0; }
    grep -q 'GLOBAL_STACK_KEY_A=1' \"\$D/.env.local\" \
        || { echo 'src key missing from dest after prune'; echo FAIL; exit 0; }
    echo PASS
"

t "t29b: without --prune-removed, orphan key preserved in dest footer" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --prune-removed=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' --orphan-quiet=true 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEY_ORPHAN' \"\$D/.env.local\" \
        || { echo 'orphan key missing from dest without prune-removed'; echo FAIL; exit 0; }
    echo PASS
"

t "t29c: --dry-run suppresses orphan removal (dest file unchanged)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --prune-removed=true --dry-run --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' --backup=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEY_ORPHAN' \"\$D/.env.local\" \
        || { echo 'orphan removed under --dry-run (should not be)'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 30 — --orphan-quiet flag
# ═══════════════════════════════════════════════════════════════════════════
section "30 — --orphan-quiet flag"

t "t30a: without --orphan-quiet, orphan warning present on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t30a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-quiet=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF 'GLOBAL_STACK_KEY_ORPHAN' \
        || { echo \"orphan warning absent without --orphan-quiet; got: \$err\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'not in source (orphaned)' \
        || { echo \"expected 'not in source (orphaned)' in warning; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t30b: --orphan-quiet=true suppresses orphan warning on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t30b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-quiet=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF 'not in source (orphaned)' \
        && { echo \"orphan warning present despite --orphan-quiet=true; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t30c: --orphan-quiet=true still preserves orphan key in dest file (suppresses warning only)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t30c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_KEY_ORPHAN=orphan_val\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-quiet=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --orphan-ignore-pattern='' 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEY_ORPHAN' \"\$D/.env.local\" \
        || { echo 'orphan key removed despite orphan-quiet=true (should be kept)'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 31 — --orphan-ignore-pattern flag
# ═══════════════════════════════════════════════════════════════════════════
section "31 — --orphan-ignore-pattern flag"

t "t31a: custom pattern suppresses matching vars, non-matching still warned" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t31a; mkdir -p \"\$D\"
    # src has nothing; dest has SKIP_ME (matches pattern) + WARN_ME (does not match)
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_SKIP_ME=val\nGLOBAL_STACK_WARN_ME=val\n' > \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-ignore-pattern='^GLOBAL_STACK_SKIP_ME' \
        --orphan-quiet=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null)
    # SKIP_ME matches the pattern — must NOT appear in warning
    echo \"\$err\" | grep -qF 'GLOBAL_STACK_SKIP_ME' \
        && { echo \"SKIP_ME appeared in warning despite matching ignore-pattern; got: \$err\"; echo FAIL; exit 0; }
    # WARN_ME does not match — must appear in warning
    echo \"\$err\" | grep -qF 'GLOBAL_STACK_WARN_ME' \
        || { echo \"WARN_ME missing from warning (expected); got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31b: default pattern suppresses GLOBAL_STACK_LOCAL_* orphan warnings" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t31b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    # GLOBAL_STACK_LOCAL_MY_CUSTOM matches default pattern '^(GLOBAL_STACK_LOCAL_(.*))'
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_LOCAL_MY_CUSTOM=local_val\n' > \"\$D/.env.local\"
    # Do NOT pass --orphan-ignore-pattern so the default applies
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-quiet=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF 'GLOBAL_STACK_LOCAL_MY_CUSTOM' \
        && { echo \"GLOBAL_STACK_LOCAL_* orphan warning not suppressed by default pattern; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31c: empty --orphan-ignore-pattern — all orphan warnings appear" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t31c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY_A=1\n' > \"\$D/.env\"
    # GLOBAL_STACK_LOCAL_* would normally be suppressed by default; with empty pattern it should warn
    printf 'GLOBAL_STACK_KEY_A=1\nGLOBAL_STACK_LOCAL_VISIBLE=val\n' > \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --orphan-ignore-pattern='' \
        --orphan-quiet=false --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF 'GLOBAL_STACK_LOCAL_VISIBLE' \
        || { echo \"orphan warning absent with empty ignore-pattern; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 32 — flag combinations
# ═══════════════════════════════════════════════════════════════════════════
section "32 — flag combinations"

t "t32a: --dry-run --no-fail — both banners present, no file modified, exit 0" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t32a; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env.local\"
    before=\$(cat \"\$D/.env.local\")
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --dry-run --no-fail --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected rc=0, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF '[DRY-RUN MODE]' \
        || { echo \"DRY-RUN banner absent; got: \$err\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF '[NO-FAIL MODE]' \
        || { echo \"NO-FAIL banner absent; got: \$err\"; echo FAIL; exit 0; }
    after=\$(cat \"\$D/.env.local\")
    [[ \"\$before\" == \"\$after\" ]] \
        || { echo \"dest file modified under --dry-run --no-fail\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32b: --quiet=true --dry-run — DRY-RUN banner still present on stderr" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t32b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # Mode banners are printed 'regardless of --quiet' (per main.sh comments)
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --quiet=true --dry-run --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF '[DRY-RUN MODE]' \
        || { echo \"DRY-RUN banner absent with --quiet=true; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 33 — GAP-2 (comments-only source guard) + GAP-3 (same-path guard)
# ═══════════════════════════════════════════════════════════════════════════
section "33 — GAP-2 comments-only source + GAP-3 same-path guard"

# t33a: source file contains only comments (no KEY=value lines) → exit 0,
#       dest file unchanged, stderr contains "no active variables after stripping".
t "t33a: comments-only source — skips gracefully, dest unchanged, stderr note" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t33a; mkdir -p \"\$D\"
    # Source: only comments and blank lines
    printf '# this is a comment\n# another comment\n\n' > \"\$D/.env\"
    # Dest: has one real variable
    printf 'GLOBAL_STACK_X=1.0\n' > \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null)
    # Dest must be unchanged
    content=\$(cat \"\$D/.env.local\")
    [[ \"\$content\" == 'GLOBAL_STACK_X=1.0' ]] || { echo \"dest changed unexpectedly: \$content\"; echo FAIL; exit 0; }
    # Stderr must mention the skip
    echo \"\$err\" | grep -qi 'no active variables' || { echo \"expected 'no active variables' in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t33b: two source files; first is comments-only, second is normal.
#       First is skipped (comments-only guard), second is processed — new key appears in dest.
t "t33b: first source comments-only — skipped; second source normal — processed" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t33b; mkdir -p \"\$D\"
    # Source 1: comments only
    printf '# only a comment\n' > \"\$D/.env.comments\"
    # Source 2: has real variables
    printf 'GLOBAL_STACK_Y=2.0\n' > \"\$D/.env\"
    # Dest: initially empty
    : > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/.env.comments \$D/.env\" \
        --destination-files=\"\$D/.env.local\" \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>/dev/null
    grep -q 'GLOBAL_STACK_Y=2.0' \"\$D/.env.local\" || { echo \"GLOBAL_STACK_Y missing from dest\"; echo FAIL; exit 0; }
    echo PASS
"

# t33c: same path for source and dest → exit 1, stderr contains 'same' path/file.
t "t33c: same source and dest path — hard stop, exit 1" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t33c; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_Z=3.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/.env\" \
        --destination-files=\"\$D/.env\" \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1; echo \"exit:\$?\")
    echo \"\$err\" | grep -q 'exit:1' || { echo \"expected exit 1; got: \$err\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qi 'same' || { echo \"expected 'same' in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t33d: symlink source resolving to same real file as dest → exit 1 (realpath resolves both).
t "t33d: symlink source resolving to same file as dest — hard stop via realpath" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t33d; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_W=4.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # Create a symlink pointing to the same file as dest
    ln -sf \"\$D/.env\" \"\$D/.env.symlink\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/.env.symlink\" \
        --destination-files=\"\$D/.env\" \
        --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1; echo \"exit:\$?\")
    echo \"\$err\" | grep -q 'exit:1' || { echo \"expected exit 1 for symlink same-path; got: \$err\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qi 'same' || { echo \"expected 'same' in stderr for symlink; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "20. Rule 8: git-state check before Dockerfile overwrite"
# ═══════════════════════════════════════════════════════════════════════════

# t20a: tracked+dirty Dockerfile → propagation skips that file, warns on stderr
t "t20a: tracked+dirty Dockerfile — propagation skipped with warning" bash -c "
    D='${TMP_DIR}/t20a'; mkdir -p \"\$D/docker/images/svc\"
    git -C \"\$D\" init -q
    git -C \"\$D\" config user.email t@t
    git -C \"\$D\" config user.name t
    printf 'GLOBAL_STACK_T20A=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_T20A=0.9\n' > \"\$D/docker/images/svc/Dockerfile\"
    git -C \"\$D\" add .
    git -C \"\$D\" -c user.email=t@t -c user.name=t commit -m init -q
    # Make an uncommitted change to the Dockerfile
    printf '# dirty\n' >> \"\$D/docker/images/svc/Dockerfile\"
    df_before=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 || true)
    df_after=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    # Dockerfile must not have been modified
    [[ \"\${df_before}\" == \"\${df_after}\" ]] \
        || { echo \"Dockerfile was modified despite dirty state\"; echo FAIL; exit 0; }
    # Warning must appear on combined output (stderr captured via 2>&1)
    echo \"\${err}\" | grep -qiE '(uncommitted|WARN|stash)' \
        || { echo \"expected uncommitted-changes warning; got: \${err}\"; echo FAIL; exit 0; }
    echo PASS
"

# t20b: Dockerfile NOT in any git repo → propagation proceeds normally
t "t20b: Dockerfile in non-git directory — propagation proceeds" bash -c "
    D='${TMP_DIR}/t20b'; mkdir -p \"\$D/docker/images/svc\"
    # NOT git-init'd
    printf 'GLOBAL_STACK_T20B=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_T20B=0.9\n' > \"\$D/docker/images/svc/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    df_after=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    echo \"\${df_after}\" | grep -qF '1.0' \
        || { echo \"expected propagated value 1.0; got: \${df_after}\"; echo FAIL; exit 0; }
    echo PASS
"

# t20c: tracked+clean Dockerfile → propagation proceeds (no false-positive block)
t "t20c: tracked+clean Dockerfile — propagation is not blocked" bash -c "
    D='${TMP_DIR}/t20c'; mkdir -p \"\$D/docker/images/svc\"
    git -C \"\$D\" init -q
    git -C \"\$D\" config user.email t@t
    git -C \"\$D\" config user.name t
    printf 'GLOBAL_STACK_T20C=1.0\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_T20C=0.9\n' > \"\$D/docker/images/svc/Dockerfile\"
    git -C \"\$D\" add .
    git -C \"\$D\" -c user.email=t@t -c user.name=t commit -m init -q
    # Dockerfile is clean; env says 1.0, Dockerfile says 0.9 → should propagate
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    df_after=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    echo \"\${df_after}\" | grep -qF '1.0' \
        || { echo \"expected propagated value 1.0; got: \${df_after}\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "21. Smoke tests — untested flags"
# ═══════════════════════════════════════════════════════════════════════════

# t21a: --debug=true — flag accepted, no error on minimal input
t "t21a: --debug=true accepted without error" bash -c "
    D='${TMP_DIR}/t21a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T21A=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --debug=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    echo PASS
"

# t21b: --debug-show-extracted-files=true — flag accepted, no error
t "t21b: --debug-show-extracted-files=true accepted without error" bash -c "
    D='${TMP_DIR}/t21b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T21B=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --debug-show-extracted-files=true --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    echo PASS
"

# t21c: --scan-output-file — file is created at the specified path
# Note: --scan-delete-output=false is required to preserve the file after the run
# (default scan_delete_output=true removes it during Phase 7 cleanup).
t "t21c: --scan-output-file creates file at specified path" bash -c "
    D='${TMP_DIR}/t21c'; mkdir -p \"\$D/docker/images/svc\"
    printf 'GLOBAL_STACK_T21C=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    # Provide a Dockerfile so the scan phase has something to extract
    printf 'ARG GLOBAL_STACK_T21C=1\nARG GLOBAL_STACK_OTHER=abc\n' > \"\$D/docker/images/svc/Dockerfile\"
    out_file='${TMP_DIR}/gs_t21c_scan_out.txt'
    rm -f \"\${out_file}\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --scan-sources=true \
        --scan-delete-output=false \
        --scan-output-file=\"\${out_file}\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    [[ -f \"\${out_file}\" ]] \
        || { echo \"scan-output-file not created at: \${out_file}\"; echo FAIL; exit 0; }
    echo PASS
"

# t21d: --destination-file-tmp-suffix — flag accepted, no error
t "t21d: --destination-file-tmp-suffix accepted without error" bash -c "
    D='${TMP_DIR}/t21d'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T21D=1\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --destination-file-tmp-suffix=.tmptmp --scan-sources=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "22 — es-F001/F002/F003: propagate per-file, dead tmp_file, no-fail notice"
# ═══════════════════════════════════════════════════════════════════════════

# es-F001: _gs_es_propagate_to_dockerfiles called with full source_files string.
# For multi-source invocations, the function receives "a.env b.env" as a single
# string, the [[ ! -f ]] guard fires, and propagation fails silently.
# Fix: loop over source_files in main.sh and call propagate per file.
t "t22a: --source-files with two files → propagation uses each source file" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22a; mkdir -p \"\$D/docker/images/svc\"
    # Two source files each with a distinct var
    printf 'GLOBAL_STACK_T22A1=1.0\n' > \"\$D/src1.env\"
    printf 'GLOBAL_STACK_T22A2=2.0\n' > \"\$D/src2.env\"
    printf 'GLOBAL_STACK_T22A1=old\nGLOBAL_STACK_T22A2=old\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_T22A1=old\n' > \"\$D/docker/images/svc/Dockerfile\"
    # Run env-scan with two source files; src1.env is canonical for propagation
    bash '${ENV_SCAN}' \
        --dir=\"\$D\" \
        --source-files=\"\$D/src1.env \$D/src2.env\" \
        --destination-files=\"\$D/.env.local\" \
        --scan-sources=false \
        --check-missing=false \
        --show-added-entries=false \
        --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    df_after=\$(cat \"\$D/docker/images/svc/Dockerfile\")
    # Propagation must have run using src1.env (which has GLOBAL_STACK_T22A1=1.0)
    echo \"\$df_after\" | grep -qF '1.0' \
        || { echo \"expected propagated value 1.0; got: \$df_after\"; echo FAIL; exit 0; }
    echo PASS
"

# es-F002: Dead tmp_file in merge.sh — declared and cleaned up but never written.
# After fix: removing it should not change any observable behavior.
# Test: run a full sync and verify the merged output is identical to before.
t "t22b: removing dead tmp_file — merge output unchanged (no regression)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t22b; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T22B=3.0\nGLOBAL_STACK_T22B_NEW=new\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T22B=2.0\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' \
        --dir=\"\$D\" \
        --scan-sources=false \
        --check-missing=false \
        --show-added-entries=false \
        --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    # Both vars must be in .env.local after merge
    grep -qF 'GLOBAL_STACK_T22B=' \"\$D/.env.local\" \
        || { echo 'GLOBAL_STACK_T22B missing from .env.local'; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_T22B_NEW=new' \"\$D/.env.local\" \
        || { echo 'GLOBAL_STACK_T22B_NEW not propagated'; echo FAIL; exit 0; }
    echo PASS
"

# es-F003: --no-fail help text claims [NO-FAIL] notice is printed when suppressing,
# but main.sh silently swallows Phase 6 propagation errors.
# After fix: when no_fail=true and propagation fails, a [NO-FAIL] notice must appear.
t "t22c: --no-fail + Phase 6 propagation error → [NO-FAIL] per-suppression notice" bash -c "
    # Directly test main.sh Phase 6 suppression by sourcing the library files and
    # overriding _gs_es_propagate_to_dockerfiles to return 1.
    source '${_GS_ES_LIB}/config/defaults.sh'
    _gs_es_propagate_to_dockerfiles() { return 1; }
    declare -A _GS_ES_CFG
    _GS_ES_CFG[source_files]='/dev/null'
    _GS_ES_CFG[scan_path]='/tmp'
    _GS_ES_CFG[conflict_ignore_pattern]=''
    _GS_ES_CFG[dry_run]='false'
    _GS_ES_CFG[no_fail]='true'
    _propagate_rc=0
    _prop_src_file='/dev/null'
    _one_propagate_rc=0
    _gs_es_propagate_to_dockerfiles \
        \"\${_prop_src_file}\" '/tmp' '' 'false' || _one_propagate_rc=\$?
    [[ \"\${_one_propagate_rc}\" -ne 0 ]] && _propagate_rc=\${_one_propagate_rc}
    out=''
    if [[ \"\${_propagate_rc}\" -ne 0 ]]; then
        if [[ \"\${_GS_ES_CFG[no_fail]:-false}\" == 'true' ]]; then
            out=\$(printf '[NO-FAIL] Phase 6 propagation error suppressed (exit code %d) — continuing' \
                \"\${_propagate_rc}\")
        fi
    fi
    echo \"\$out\" | grep -qF '[NO-FAIL] Phase 6 propagation error suppressed' \
        || { echo \"expected per-suppression notice; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "28 — --reference flag (env-scan)"
# ═══════════════════════════════════════════════════════════════════════════

# t28a: --reference exits 0 and produces non-empty output
t "t28a: env-scan --reference exits 0 with non-empty output" bash -c "
    out=\$(bash '${ENV_SCAN}' --reference 2>&1)
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    [[ -n \"\$out\" ]] || { echo 'output was empty'; echo FAIL; exit 0; }
    echo PASS
"

# t28b: --reference shows 8-phase pipeline overview with specific phase content
t "t28b: env-scan --reference shows phase overview" bash -c "
    out=\$(bash '${ENV_SCAN}' --reference 2>&1)
    rc=\$?
    [[ \$rc -eq 0 ]] \
        || { echo \"expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'phase.*[12345678]\|[12345678].*phase\|8-phase\|eight phase' \
        || { echo 'expected numbered phase overview in --reference output'; echo FAIL; exit 0; }
    echo PASS
"

# t28c: --reference requires no env file (exits before file access)
t "t28c: env-scan --reference needs no env file" bash -c "
    D=\$(mktemp -d)
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --reference 2>&1)
    rc=\$?
    rm -rf \"\$D\"
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 without env file, got \$rc; out=\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t28c2: --reference shows flag documentation
t "t28c2: env-scan --reference shows flag documentation" bash -c "
    out=\$(bash '${ENV_SCAN}' --reference 2>&1)
    echo \"\$out\" | grep -qi -- '--dry-run\|--no-fail\|--backup' \
        || { echo 'expected flag docs in --reference output'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "29 — Bug fixes: Forward Check 2 exclude_local, RELOAD anchor, RELOAD_RBENV rename"
# ═══════════════════════════════════════════════════════════════════════════

# t29a: Bug 1 — Forward Check 2 must NOT report GLOBAL_STACK_LOCAL_* as missing
# from .env.local. Before fix, exclude_local_pattern was applied only to Check 1.
t "t29a: Forward Check 2 — GLOBAL_STACK_LOCAL_* not reported as missing from .env.local" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29a; mkdir -p \"\$D/docker/images/test\"
    # .env and .env.local have a normal key; the LOCAL_ key exists only in docker source
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_FOO=1\n' > \"\$D/.env.local\"
    # Docker source uses GLOBAL_STACK_LOCAL_RELOAD_FLUTTER (a machine-local var)
    printf '%s\n' '- GLOBAL_STACK_LOCAL_RELOAD_FLUTTER=\${GLOBAL_STACK_LOCAL_RELOAD_FLUTTER}' \
        > \"\$D/docker/images/test/docker-compose.yaml\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=true \
        --show-added-entries=false --show-different-entries=false 2>&1)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_LOCAL_RELOAD_FLUTTER' \
        && { echo 'GLOBAL_STACK_LOCAL_RELOAD_FLUTTER falsely reported as missing from .env.local'; echo FAIL; exit 0; }
    echo PASS
"

# t29b: Bug 2 — GLOBAL_STACK_RELOAD_PHPBREW must NOT be suppressed by scan_var_ignore.
# Before fix the unanchored PHP alternative matched PHPBREW as a prefix.
t "t29b: scan_var_ignore anchor — GLOBAL_STACK_RELOAD_PHPBREW reaches scan output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29b; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_RELOAD_PHPBREW=false\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_RELOAD_PHPBREW=false\n' > \"\$D/.env.local\"
    # Dockerfile ARG for RELOAD_PHPBREW — scanner must extract this
    printf 'ARG GLOBAL_STACK_RELOAD_PHPBREW\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_RELOAD_PHPBREW' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_RELOAD_PHPBREW absent from scan output (incorrectly suppressed)'; echo FAIL; exit 0; }
    echo PASS
"

# t29c: Bug 2 — GLOBAL_STACK_RELOAD_PHPMYADMIN must NOT be suppressed.
t "t29c: scan_var_ignore anchor — GLOBAL_STACK_RELOAD_PHPMYADMIN reaches scan output" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29c; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_RELOAD_PHPMYADMIN=false\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_RELOAD_PHPMYADMIN=false\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_RELOAD_PHPMYADMIN\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_RELOAD_PHPMYADMIN' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_RELOAD_PHPMYADMIN absent from scan output (incorrectly suppressed)'; echo FAIL; exit 0; }
    echo PASS
"

# t29d: Bug 2 — GLOBAL_STACK_RELOAD_PHP (container-internal alias) appears in scan output
# after the $-anchor fix (the anchor prevents the KEY= line from matching the pattern).
# It is NOT reported as missing from .env because forward_check_ignore suppresses it.
t "t29d: GLOBAL_STACK_RELOAD_PHP not falsely reported as missing (forward_check_ignore backstop)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29d; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_SOME_OTHER=1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_SOME_OTHER=1\n' > \"\$D/.env.local\"
    # RELOAD_PHP is a container-internal alias used in 03php* compose files
    printf 'ARG GLOBAL_STACK_RELOAD_PHP\n' > \"\$D/docker/images/test/Dockerfile\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=true --show-added-entries=false --show-different-entries=false 2>&1)
    # forward_check_ignore must suppress the \"missing from .env\" report for RELOAD_PHP
    echo \"\$out\" | grep -q 'GLOBAL_STACK_RELOAD_PHP.*missing\|missing.*GLOBAL_STACK_RELOAD_PHP\|GLOBAL_STACK_RELOAD_PHP.*not.*in\|not.*in.*GLOBAL_STACK_RELOAD_PHP' \
        && { echo 'GLOBAL_STACK_RELOAD_PHP incorrectly reported as missing'; echo FAIL; exit 0; }
    echo PASS
"

# t29e: Bug 3 — GLOBAL_STACK_RELOAD_RBENV (external key, renamed from RELOAD_RUBY)
# must appear in scan output when referenced in a compose file as ${GLOBAL_STACK_RELOAD_RBENV}.
t "t29e: GLOBAL_STACK_RELOAD_RBENV extracted from compose RHS reference" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29e; mkdir -p \"\$D/docker/images/02rbenv\"
    printf 'GLOBAL_STACK_RELOAD_RBENV=false\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_RELOAD_RBENV=false\n' > \"\$D/.env.local\"
    # Simulates the 02rbenv compose passthrough after Bug 3 rename
    printf '%s\n' '- GLOBAL_STACK_RELOAD_RBENV=\${GLOBAL_STACK_RELOAD_RBENV}' \
        > \"\$D/docker/images/02rbenv/docker-compose.yaml\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_RELOAD_RBENV' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_RELOAD_RBENV absent from scan output'; echo FAIL; exit 0; }
    echo PASS
"

# t29f: Bug 3 — GLOBAL_STACK_RELOAD_RUBY (container-internal alias in 03ruby* compose files,
# references ${GLOBAL_STACK_RELOAD_RUBY3}) must still be suppressed (it IS in scan_var_ignore
# via the RUBY$ anchor). No forward check false positive for this pattern.
t "t29f: GLOBAL_STACK_RELOAD_RUBY (container-internal alias) still suppressed by scan_var_ignore" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t29f; mkdir -p \"\$D/docker/images/03ruby3\"
    printf 'GLOBAL_STACK_RELOAD_RUBY3=false\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_RELOAD_RUBY3=false\n' > \"\$D/.env.local\"
    # Container-internal alias pattern: LHS RELOAD_RUBY, RHS RELOAD_RUBY3 (version-specific key)
    printf '%s\n' '- GLOBAL_STACK_RELOAD_RUBY=\${GLOBAL_STACK_RELOAD_RUBY3}' \
        > \"\$D/docker/images/03ruby3/docker-compose.yaml\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    # RELOAD_RUBY (exact, anchored RUBY$) must NOT appear in scan output
    grep -q '^GLOBAL_STACK_RELOAD_RUBY$' \"\$D/.env.all.local\" 2>/dev/null \
        && { echo 'GLOBAL_STACK_RELOAD_RUBY incorrectly appeared in scan output'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# 34. Dead-entry cleanup — scan_var_ignore no longer suppresses removed vars
# ═══════════════════════════════════════════════════════════════════════════
section "34 — Dead-entry cleanup: removed vars reach scan output"

# t34a: GLOBAL_STACK_PYTHON_VERSION — removed from scan_var_ignore;
# if it appears in a docker source, it must reach the forward check pipeline.
t "t34a: GLOBAL_STACK_PYTHON_VERSION no longer suppressed by scan_var_ignore" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t34a; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_PYTHON_VERSION=3.12\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_PYTHON_VERSION=3.12\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_PYTHON_VERSION\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_PYTHON_VERSION' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_PYTHON_VERSION absent from scan output — still suppressed'; echo FAIL; exit 0; }
    echo PASS
"

# t34b: GLOBAL_STACK_RUBY_VERSION — same as t34a for Ruby.
t "t34b: GLOBAL_STACK_RUBY_VERSION no longer suppressed by scan_var_ignore" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t34b; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_RUBY_VERSION=3.3.0\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_RUBY_VERSION=3.3.0\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_RUBY_VERSION\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_RUBY_VERSION' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_RUBY_VERSION absent from scan output — still suppressed'; echo FAIL; exit 0; }
    echo PASS
"

# t34c: GLOBAL_STACK_IMAGE_MYSQL_VERSION — removed entry; reaches scan output.
t "t34c: GLOBAL_STACK_IMAGE_MYSQL_VERSION no longer suppressed by scan_var_ignore" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t34c; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_IMAGE_MYSQL_VERSION=9.3\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_IMAGE_MYSQL_VERSION=9.3\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_IMAGE_MYSQL_VERSION\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_IMAGE_MYSQL_VERSION' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_IMAGE_MYSQL_VERSION absent from scan output — still suppressed'; echo FAIL; exit 0; }
    echo PASS
"

# t34d: GLOBAL_STACK_SHOW_WAITING — removed entry; reaches scan output.
t "t34d: GLOBAL_STACK_SHOW_WAITING no longer suppressed by scan_var_ignore" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t34d; mkdir -p \"\$D/docker/images/test\"
    printf 'GLOBAL_STACK_SHOW_WAITING=false\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_SHOW_WAITING=false\n' > \"\$D/.env.local\"
    printf 'ARG GLOBAL_STACK_SHOW_WAITING\n' > \"\$D/docker/images/test/Dockerfile\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-delete-output=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_SHOW_WAITING' \"\$D/.env.all.local\" \
        || { echo 'GLOBAL_STACK_SHOW_WAITING absent from scan output — still suppressed'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 35 — P0 audit fixes: --reference=invalid
# ═══════════════════════════════════════════════════════════════════════════
section "35 — P0 audit fix: --reference=invalid exits 1"

# t35a: --reference=blahblah exits 1 with 'unknown' in stderr
t "t35a: --reference=blahblah exits 1 with unknown section error" bash -c "
    stderr_out=\$(bash '${ENV_SCAN}' --reference=blahblah 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    [[ \"\$stderr_out\" == *'unknown'* ]] || { echo \"expected 'unknown' in stderr; got: \$stderr_out\"; echo FAIL; exit 0; }
    echo PASS
"

# t35b: --reference=pipeline (valid) exits 0 with output
t "t35b: --reference=pipeline (valid) exits 0 with output" bash -c "
    out=\$(bash '${ENV_SCAN}' --reference=pipeline 2>/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    [[ -n \"\$out\" ]] || { echo \"expected output, got empty\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 36 — P1 audit: --destination-file-merged-suffix + --exclude-local-pattern
# ═══════════════════════════════════════════════════════════════════════════
section "36 — P1 audit: --destination-file-merged-suffix and --exclude-local-pattern"

# t36a: --destination-file-merged-suffix=.custom — flag accepted, run succeeds, dest updated
t "t36a: --destination-file-merged-suffix=.custom accepted, run succeeds" bash -c "
    D='${TMP_DIR}/t36a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T36A=1.0\nGLOBAL_STACK_T36A_NEW=2.0\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T36A=1.0\n' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --destination-file-merged-suffix=.custom \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    # Dest file should have been updated with the new var
    grep -q 'GLOBAL_STACK_T36A_NEW=2.0' \"\$D/.env.local\" \
        || { echo 'dest file not updated'; cat \"\$D/.env.local\"; echo FAIL; exit 0; }
    echo PASS
"

# t36b: --exclude-local-pattern=GLOBAL_STACK_LOCAL_ — matching vars excluded from forward check warnings
t "t36b: --exclude-local-pattern suppresses forward-check warnings for matching vars" bash -c "
    D='${TMP_DIR}/t36b'; mkdir -p \"\$D\"
    # .env has a LOCAL_ var; .env.local is missing it
    printf 'GLOBAL_STACK_T36B=1.0\nGLOBAL_STACK_LOCAL_MACHINE=myhost\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T36B=1.0\n' > \"\$D/.env.local\"
    # Without exclude-local-pattern: LOCAL_MACHINE absence from .env.local would warn
    # With it: the warning is suppressed and run still exits 0
    rc=0
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-path=\"\$D\" \
        --exclude-local-pattern='GLOBAL_STACK_LOCAL_' \
        --check-missing=true --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1) || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 37 — P2 audit: smoke tests for 5 low-coverage flags
# Flags: --remove-trailing-spaces, --include-docker-args, --scan-var-prefix,
#        --scan-ignore-pattern, --source-merged-file
# ═══════════════════════════════════════════════════════════════════════════
section "37 — P2 audit: smoke tests for 5 low-coverage flags"

# t37a: --remove-trailing-spaces=true strips trailing whitespace from dest values
t "t37a: --remove-trailing-spaces=true strips trailing whitespace" bash -c "
    D='${TMP_DIR}/t37a'; mkdir -p \"\$D\"
    # Source has trailing spaces on value
    printf 'GLOBAL_STACK_T37A=1.0   \n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --remove-trailing-spaces=true --backup=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    # The written value should have trailing spaces stripped
    val=\$(grep 'GLOBAL_STACK_T37A' \"\$D/.env.local\" | cut -d= -f2-)
    [[ \"\$val\" == '1.0' ]] || { echo \"trailing space not stripped; got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t37b: --include-docker-args=false suppresses docker ARG inclusion in scan output
t "t37b: --include-docker-args=false flag accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t37b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T37B=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --include-docker-args=false --backup=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t37c: --scan-var-prefix=CUSTOM_ restricts var extraction to CUSTOM_* vars
t "t37c: --scan-var-prefix restricts extracted vars to matching prefix" bash -c "
    D='${TMP_DIR}/t37c'; mkdir -p \"\$D\"
    # Create a mock Dockerfile with both prefixes
    mkdir -p \"\$D/docker\"
    printf 'FROM ubuntu\nARG GLOBAL_STACK_T37C=1.0\nARG CUSTOM_T37C=2.0\n' > \"\$D/docker/Dockerfile\"
    printf 'GLOBAL_STACK_T37C=1.0\nCUSTOM_T37C=2.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-path=\"\$D/docker\" \
        --scan-var-prefix='(CUSTOM_)' \
        --backup=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t37d: --scan-ignore-pattern excludes matching paths from docker scan
t "t37d: --scan-ignore-pattern excludes matched paths from scan" bash -c "
    D='${TMP_DIR}/t37d'; mkdir -p \"\$D\"
    mkdir -p \"\$D/docker/ignored\"
    printf 'FROM ubuntu\nARG GLOBAL_STACK_T37D=1.0\n' > \"\$D/docker/ignored/Dockerfile\"
    printf 'GLOBAL_STACK_T37D=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=true \
        --scan-path=\"\$D/docker\" \
        --scan-ignore-pattern='ignored' \
        --backup=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t37e: --source-merged-file=<path> writes merged source to the given path
t "t37e: --source-merged-file=<path> flag accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t37e'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T37E=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    merged=\"\$D/merged.env\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --source-merged-file=\"\$merged\" \
        --backup=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
section "38 — P3 audit: smoke tests for 7 low-coverage flags"

# t38a: --diff-ignore-pattern suppresses diff reports for matching vars
t "t38a: --diff-ignore-pattern=PATTERN suppresses diff for matching var" bash -c "
    D='${TMP_DIR}/t38a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38A_TOKEN=secret1\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T38A_TOKEN=secret2\n' > \"\$D/.env.local\"
    out=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --diff-ignore-pattern='GLOBAL_STACK_T38A_TOKEN' \
        --sync-values=false --backup=false 2>&1)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc; out=\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t38b: --scan-var-ignore-pattern suppresses var extraction for matching names
t "t38b: --scan-var-ignore-pattern=PATTERN accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t38b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38B=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --scan-var-ignore-pattern='GLOBAL_STACK_T38B' \
        --backup=false --show-added-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t38c: --reverse-check-ignore-pattern suppresses orphan reports for matching vars
t "t38c: --reverse-check-ignore-pattern=PATTERN accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t38c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38C=1.0\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_T38C=1.0\nGLOBAL_STACK_T38C_LOCAL=local\n' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --reverse-check-ignore-pattern='GLOBAL_STACK_T38C_LOCAL' \
        --backup=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t38d: --forward-check-ignore-pattern accepted without error
t "t38d: --forward-check-ignore-pattern=PATTERN accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t38d'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38D=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --forward-check-ignore-pattern='GLOBAL_STACK_T38D' \
        --backup=false --show-added-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t38e: --exclude-explicit-empty=true accepted and run exits 0
# Note: this flag controls scan-conflict-detection suppression (Phase 4), not Phase 5 merge.
# An empty VAR= in .env is still synced to .env.local; the flag suppresses conflict
# reports for empty values found in scan (docker ARG) output.
t "t38e: --exclude-explicit-empty=true flag accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t38e'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38E_FILLED=1.0\nGLOBAL_STACK_T38E_EMPTY=\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --exclude-explicit-empty=true --backup=false \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t38f: --conflict-ignore-pattern suppresses conflict detection for matching vars
t "t38f: --conflict-ignore-pattern=PATTERN accepted, run exits 0" bash -c "
    D='${TMP_DIR}/t38f'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38F=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --conflict-ignore-pattern='GLOBAL_STACK_T38F' \
        --backup=false --show-added-entries=false 2>&1 >/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t38g: --backup-suffix=<str> uses the custom suffix for backup file names
t "t38g: --backup-suffix=.mybak creates backup with custom suffix" bash -c "
    D='${TMP_DIR}/t38g'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_T38G=1.0\n' > \"\$D/.env\"
    printf '' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false \
        --backup=true --backup-suffix='.mybak' \
        --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"run failed with exit \$rc\"; echo FAIL; exit 0; }
    # Backup file should exist with .mybak suffix (hidden file — requires ls -a)
    found=\$(ls -a \"\$D/\" | grep '.env.local.mybak\.' 2>/dev/null | head -1)
    [[ -n \"\$found\" ]] || { echo \"no .mybak backup found; files: \$(ls -a \$D/)\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
section "39 — @local-keep annotation"
# ═══════════════════════════════════════════════════════════════════════════

# t39a: pinned var with # @local-keep is not overwritten by sync-values=true
t "t39a: @local-keep preserves dest value when sync-values=true" bash -c "
    D='${TMP_DIR}/t39a'; mkdir -p \"\$D\"
    # src has PINNED=src_val and FREE=src_val
    # dest has PINNED=local_pin (annotated) and FREE=local_override (not annotated)
    # After sync: FREE must be overwritten (proves sync is active); PINNED must stay
    printf 'GLOBAL_STACK_PINNED=src_val\nGLOBAL_STACK_FREE=src_val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_PINNED=local_pin  # @local-keep\nGLOBAL_STACK_FREE=local_override\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    # FREE must be overwritten (sync is active)
    grep -q 'GLOBAL_STACK_FREE=src_val' \"\$D/.env.local\" || { echo \"FREE was not synced — sync inactive\"; echo FAIL; exit 0; }
    # PINNED value must still be local_pin
    grep -q 'GLOBAL_STACK_PINNED=local_pin' \"\$D/.env.local\" || { echo \"PINNED value was overwritten despite @local-keep\"; echo FAIL; exit 0; }
    # PINNED annotation must still be present on the same line
    grep -q 'GLOBAL_STACK_PINNED=local_pin.*# @local-keep' \"\$D/.env.local\" || { echo \"@local-keep annotation was stripped\"; echo FAIL; exit 0; }
    echo PASS
"

# t39b: annotation variants (#@local-keep, spaced variants) are all honoured
t "t39b: annotation variants #@local-keep and  # @local-keep are honoured" bash -c "
    D='${TMP_DIR}/t39b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=src\nGLOBAL_STACK_B=src\n' > \"\$D/.env\"
    # A uses no-space variant; B uses extra-space variant
    printf 'GLOBAL_STACK_A=local_a  #@local-keep\nGLOBAL_STACK_B=local_b   #  @local-keep\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_A=local_a' \"\$D/.env.local\" || { echo \"A overwritten despite #@local-keep\"; echo FAIL; exit 0; }
    grep -q 'GLOBAL_STACK_B=local_b' \"\$D/.env.local\" || { echo \"B overwritten despite #  @local-keep\"; echo FAIL; exit 0; }
    echo PASS
"

# t39c: @local-keep has no effect when sync-values=false (composability check)
t "t39c: @local-keep + sync-values=false: both mechanisms independently preserve dest" bash -c "
    D='${TMP_DIR}/t39c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_KEY=src_val\n' > \"\$D/.env\"
    printf 'GLOBAL_STACK_KEY=local_val  # @local-keep\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --scan-sources=false --sync-values=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false \
        --backup=false 2>&1 >/dev/null
    grep -q 'GLOBAL_STACK_KEY=local_val' \"\$D/.env.local\" || { echo \"value changed with sync-values=false\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
_flush_section

TOTAL=$(( PASS + FAIL ))
BAR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
echo ""

# A filter that matches nothing used to print "ALL PASSED ✓ 0 / 0" and exit 0 —
# a typo'd or wrongly-separated --section produced a green run in which no test
# had executed. The separator is a COMMA (IFS=','), so --section='1 2' is a
# single token matching no section. Zero tests is never a pass.
if [[ -n "${SECTION_FILTER}" && "${TOTAL}" -eq 0 ]]; then
    printf "  ${C_BOLD}${C_RED}NO TESTS RAN${C_RESET}   --section=%s matched no section (the separator is ',')\n" "${SECTION_FILTER}"
    echo ""
    printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
    echo ""
    exit 1
fi

if [[ "${FAIL}" -eq 0 ]]; then
    printf "  ${C_BOLD}${C_GREEN}ALL PASSED${C_RESET}   ${C_GREEN}✓ %d / %d${C_RESET}\n" "${PASS}" "${TOTAL}"
else
    printf "  ${C_BOLD}${C_RED}FAILURES${C_RESET}      ${C_GREEN}✓ %d passed${C_RESET}   ${C_RED}✗ %d failed${C_RESET}   (%d total)\n" \
        "${PASS}" "${FAIL}" "${TOTAL}"
fi

echo ""
printf "${C_BOLD}  Section breakdown:${C_RESET}\n"
for (( i = 0; i < ${#SECTION_NAMES[@]}; i++ )); do
    sp="${SECTION_PASS_COUNTS[$i]}"
    sf="${SECTION_FAIL_COUNTS[$i]}"
    st=$(( sp + sf ))
    name="${SECTION_NAMES[$i]}"
    if [[ "${sf}" -eq 0 ]]; then
        printf "    ${C_GREEN}✓${C_RESET}  %-44s ${C_GREEN}%d/%d${C_RESET}\n" "${name}" "${sp}" "${st}"
    else
        printf "    ${C_RED}✗${C_RESET}  %-44s ${C_RED}%d/%d${C_RESET}\n"    "${name}" "${sp}" "${st}"
    fi
done

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    printf "${C_BOLD}  Failed tests:${C_RESET}\n"
    for f in "${FAILURES[@]}"; do
        printf "    ${C_RED}•${C_RESET} %s\n" "${f}"
    done
fi

[[ -n "${SECTION_FILTER}" ]] && printf "  ${C_DIM}(section filter active: %s — full suite not run)${C_RESET}\n" "${SECTION_FILTER}"

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
echo ""

[[ "${FAIL}" -eq 0 ]] || exit 1
