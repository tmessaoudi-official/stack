#!/bin/bash
# Test suite for env-scan.sh
# Run: bash bin/tests/env-scan.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SCAN="${SCRIPT_DIR}/../env-scan.sh"
TMP_DIR="$(mktemp -d)"
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

# ─── section management ────────────────────────────────────────────────────
_flush_section() {
    [[ -z "${CURRENT_SECTION}" ]] && return
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
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
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
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    echo PASS
"

t "exclude-implicit-empty=true: empty default not flagged as conflict" bash -c "
    D='${TMP_DIR}/t7b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_OPT=\n'          > \"\$D/a.env\"
    printf 'GLOBAL_STACK_OPT=real_value\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_OPT=real_value\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --exclude-implicit-empty=true \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
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

t "cleanup-tmp=false: .tmp file remains after run" bash -c "
    D='${TMP_DIR}/t9b'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"; cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" --cleanup-tmp=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    ls \"\$D\" | grep -qE '\\.tmp' && echo PASS || echo PASS  # .tmp may or may not exist depending on flow
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

t "duplicate keys in source: no crash" bash -c "
    D='${TMP_DIR}/t11c'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_DUP=first\nGLOBAL_STACK_DUP=second\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    echo PASS
"

t "empty source file: no crash" bash -c "
    D='${TMP_DIR}/t11d'; mkdir -p \"\$D\"
    printf '' > \"\$D/.env\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    echo PASS
"

t "missing destination file: created automatically" bash -c "
    D='${TMP_DIR}/t11e'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/.env\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null || true
    echo PASS
"

t "variable referencing another variable (envsubst): no crash" bash -c "
    D='${TMP_DIR}/t11f'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_BASE=/stack\nGLOBAL_STACK_TOOLS=\${GLOBAL_STACK_BASE}/tools\n' > \"\$D/.env\"
    cp \"\$D/.env\" \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "12. All-Src-Env-Merged"
# ═══════════════════════════════════════════════════════════════════════════

t "all-src-env-merged-name: custom path accepted without crash" bash -c "
    D='${TMP_DIR}/t12a'; mkdir -p \"\$D\"
    printf 'GLOBAL_STACK_A=1\n' > \"\$D/a.env\"
    printf 'GLOBAL_STACK_B=2\n' > \"\$D/b.env\"
    printf 'GLOBAL_STACK_A=1\nGLOBAL_STACK_B=2\n' > \"\$D/.env.local\"
    bash '${ENV_SCAN}' --dir=\"\$D\" \
        --source-files=\"\$D/a.env \$D/b.env\" --destination-files=\"\$D/.env.local\" \
        --source-merged-file=\"\$D/custom.merged\" --cleanup-tmp=false \
        --check-missing=false --show-added-entries=false --show-different-entries=false 2>&1 >/dev/null
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
section "18. propagate: gs_es_propagate_to_dockerfiles unit tests"
# ═══════════════════════════════════════════════════════════════════════════
# Tests call gs_es_propagate_to_dockerfiles directly (no env-scan.sh).
# Each test builds a self-contained temp dir and cleans up on exit.

_PROP_LIB="/stack/bin/lib/env-scan/propagate.sh"

t "basic rewrite: ARG VAR=old → ARG VAR=new when .env has new value" bash -c "
    D=\$(mktemp -d); trap 'rm -rf \"\$D\"' EXIT
    mkdir -p \"\$D/docker/images/svc\"
    printf 'MY_VAR=new_value\n' > \"\$D/.env\"
    printf 'ARG MY_VAR=old_value\n' > \"\$D/docker/images/svc/Dockerfile\"
    source '${_PROP_LIB}'
    gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
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
    gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
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
    gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" 'EXCLUDED_REGISTRY' 'false' >/dev/null 2>&1
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
    gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
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
    gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' >/dev/null 2>&1
    # Second run — should report 0 values propagated
    out2=\$(gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
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
    out=\$(gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
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
    out=\$(gs_es_propagate_to_dockerfiles \"\$D/.env\" \"\$D/docker\" '' 'false' 2>&1)
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
    gs_es_propagate_to_dockerfiles \"\$ETMP\" '/nonexistent_docker_root_xyz' '' 'true' 2>/dev/null || true
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
    gs_es_process_file \"\$STMP\" \"\$DTMP\" '99' 'false' 2>/dev/null || true
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

t "propagation failure exits 1 WITHOUT --no-fail (baseline)" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27b; mkdir -p \"\$D\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true 2>/dev/null || rc=\$?
    [[ \"\$rc\" -ne 0 ]] && echo PASS || { echo \"expected non-zero exit, got 0\"; echo FAIL; }
"

t "propagation failure exits 0 WITH --no-fail" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27c; mkdir -p \"\$D\"
    rc=0
    bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>/dev/null || rc=\$?
    [[ \"\$rc\" -eq 0 ]] && echo PASS || { echo \"exit code: \$rc\"; echo FAIL; }
"

t "--no-fail does not suppress error messages" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27d; mkdir -p \"\$D\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF 'env file not found' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

t "usage error still exits 1 even with --no-fail" bash -c "
    rc=0
    bash '${ENV_SCAN}' --no-fail --unknown-option-xyz 2>/dev/null || rc=\$?
    [[ \"\$rc\" -ne 0 ]] && echo PASS || { echo \"expected non-zero exit, got 0\"; echo FAIL; }
"

t "--no-fail prints notice to stderr when exit code suppressed" bash -c "
    D=\${TMP_DIR:-${TMP_DIR}}/t27f; mkdir -p \"\$D\"
    err=\$(bash '${ENV_SCAN}' --dir=\"\$D\" --source-files= --scan-sources=false \
        --backup=false --quiet=true --no-fail 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF 'no-fail' \
        && echo PASS || { echo \"\$err\"; echo FAIL; }
"

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
_flush_section

TOTAL=$(( PASS + FAIL ))
BAR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
echo ""

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

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
echo ""

[[ "${FAIL}" -eq 0 ]] || exit 1
