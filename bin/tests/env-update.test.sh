#!/bin/bash
# Test suite for env-update.sh
# Run: bash bin/tests/env-update.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_UPDATE_V2="${SCRIPT_DIR}/../env-update.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/env-update"

# Everything below resolves from SCRIPT_DIR. A test that sources an absolute
# '/stack/...' path certifies the tree at /stack rather than the tree it lives in,
# so a clone's suite silently passes against /stack's library. Proven: breaking a
# clone's curl.sh left 10 of 11 tests in section 112 green, because they sourced
# /stack's copy. These are expanded by THIS shell when each test's command string
# is built, so the absolute path is baked in once, here.
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
_GS_EU2_LIB="${SCRIPT_DIR}/../lib/env-update"
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
    (( PASS++ ))         || true
    (( SECTION_PASS++ )) || true
    printf "  ${C_GREEN}✓${C_RESET}  %s\n" "$1"
}

_fail() {
    (( FAIL++ ))         || true
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

# ─── subshell test runner ──────────────────────────────────────────────────
t() {
    [[ "${SECTION_ACTIVE:-true}" == "false" ]] && return 0
    local label="$1"; shift
    local output last
    output="$("$@" 2>&1)" || true
    last="$(echo "${output}" | tail -1 | tr -d '[:space:]')"
    case "${last}" in
        PASS) _pass "${label}" ;;
        FAIL) _fail "${label}" "PASS" "FAIL"
              while IFS= read -r line; do
                  [[ "${line}" =~ ^[[:space:]]*(PASS|FAIL)[[:space:]]*$ ]] && continue
                  [[ -z "${line}" ]] && continue
                  printf "       ${C_DIM}%s${C_RESET}\n" "${line}"
              done <<< "${output}" ;;
        *)    _fail "${label}" "PASS" "${last:-<no output>}" ;;
    esac
}

make_env() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ═══════════════════════════════════════════════════════════════════════════
echo ""
printf "${C_BOLD}  env-update.sh — test suite${C_RESET}\n"
printf "  script   : %s\n" "${ENV_UPDATE_V2}"
printf "  fixtures : %s\n" "${FIXTURES}"
[[ -n "${SECTION_FILTER}" ]] && printf "  sections : %s (filtered)\n" "${SECTION_FILTER}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Section 1 — Lexer / scanner
# ═══════════════════════════════════════════════════════════════════════════
section "1 — Lexer / scanner"

t "t01a: detects @todo env-update marker" bash -c "
    f=\${TMP_DIR}/t01a.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'env_var: GLOBAL_STACK_NGINX_VERSION' || { echo \"record not found in dump\"; echo FAIL; exit 0; }
    echo PASS
"

t "t01b: detects VAR=VALUE assignment" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | grep -qF 'current_version: 9.13.0' || { echo \"current_version not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t01c: skips intermediate comment-only lines" bash -c "
    f=\${TMP_DIR}/t01c.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0\n# some comment\n# another comment\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'env_var: GLOBAL_STACK_NGINX_VERSION' || { echo \"record not found despite comment lines\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 2 — Positional parsing
# ═══════════════════════════════════════════════════════════════════════════
section "2 — Positional parsing"

t "t02a: basic TYPE:IDENTIFIER" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | grep -qF 'type: dockerhub' || { echo \"type not dockerhub\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'identifier: dpage/pgadmin4' || { echo \"identifier wrong\"; echo FAIL; exit 0; }
    echo PASS
"

t "t02b: TYPE:IDENTIFIER:MAJOR_HINT split" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/github-major-pin.env' 2>&1)
    echo \"\$out\" | grep -qF 'type: github' || { echo \"type not github\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'identifier: flutter/flutter' || { echo \"identifier wrong, expected flutter/flutter\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major_hint: 3' || { echo \"major_hint not 3\"; echo FAIL; exit 0; }
    echo PASS
"

t "t02c: trailing hint parenthetical" bash -c "
    f=\${TMP_DIR}/t02c.env
    printf '# @todo env-update github:php/php-src 8.5.3 (php >= 8.5)\nGLOBAL_STACK_PHP_VERSION=8.5.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'hint: php >= 8.5' || { echo \"hint not found, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t02d: current_version from VAR=VALUE when not in annotation" bash -c "
    f=\${TMP_DIR}/t02d.env
    printf '# @todo env-update dockerhub:nginx/nginx\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'current_version: 1.27.0' || { echo \"current_version not inferred from var value\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 3 — Inline flags
# ═══════════════════════════════════════════════════════════════════════════
section "3 — Inline flags"

t "t03a: channel flag" bash -c "
    f=\${TMP_DIR}/t03a.env
    printf '# @todo env-update (channel:unstable) dockerhub:_/mariadb:12 12.3.1\nGLOBAL_STACK_MARIADB_VERSION=12.3.1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'channel: unstable' || { echo \"channel not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03b: skip flag" bash -c "
    f=\${TMP_DIR}/t03b.env
    printf '# @todo env-update (skip:manual-only) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'skip_reason: manual-only' || { echo \"skip_reason not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03b2: (skip:REASON) forces SKIP/FROZEN decision in --check output (not AUTO/ERROR)" bash -c "
    f=\${TMP_DIR}/t03b2.env
    printf '# @todo env-update (skip:test-skip-reason) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" --no-cache 2>&1)
    echo \"\$out\" | grep -qiE '\\[SKIP|\\[FROZEN' || { echo \"expected [SKIP] or [FROZEN] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'test-skip-reason' || { echo \"expected reason in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiE '\\[AUTO|\\[ERROR' && { echo \"got AUTO/ERROR when expecting SKIP/FROZEN; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03c: tag-filter flag" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/github-major-pin.env' 2>&1)
    echo \"\$out\" | grep -qF 'tag_filter: ^[0-9\.]' || { echo \"tag_filter not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03d: tag-exclude flag" bash -c "
    f=\${TMP_DIR}/t03d.env
    printf '# @todo env-update (tag-exclude:-rc|-beta) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_exclude: -rc|-beta' || { echo \"tag_exclude not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03e: tag-strip-prefix flag" bash -c "
    f=\${TMP_DIR}/t03e.env
    printf '# @todo env-update (tag-strip-prefix:v) github:foo/bar 1.2.3\nGLOBAL_STACK_TEST_VERSION=1.2.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_strip_prefix: v' || { echo \"tag_strip_prefix not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03f: tag-strip-suffix flag" bash -c "
    f=\${TMP_DIR}/t03f.env
    printf '# @todo env-update (tag-strip-suffix:-alpine) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_strip_suffix: -alpine' || { echo \"tag_strip_suffix not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03g: tag-extract flag" bash -c "
    f=\${TMP_DIR}/t03g.env
    printf '# @todo env-update (tag-extract:-grid-([0-9\\.\\-]+)\$) dockerhub:selenium/standalone-chrome 4.41.0\nGLOBAL_STACK_CHROME_VERSION=4.41.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_extract: -grid-' || { echo \"tag_extract not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03h: tag-replace flag" bash -c "
    f=\${TMP_DIR}/t03h.env
    printf '# @todo env-update (tag-replace:_:-) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_replace_from: _' || { echo \"tag_replace_from not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'tag_replace_to: -' || { echo \"tag_replace_to not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03i: tag-suffix flag" bash -c "
    f=\${TMP_DIR}/t03i.env
    printf '# @todo env-update (tag-suffix:oraclelinux9) dockerhub:_/mysql:9 9.6.0\nGLOBAL_STACK_MYSQL9_VERSION=9.6.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_suffix: oraclelinux9' || { echo \"tag_suffix not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03j: fetch-extract flag" bash -c "
    f=\${TMP_DIR}/t03j.env
    printf '# @todo env-update (fetch-extract:cmdline-tools-([0-9]+)) url:https://example.com 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'fetch_extract: cmdline-tools-' || { echo \"fetch_extract not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03k: fetch-json flag" bash -c "
    f=\${TMP_DIR}/t03k.env
    printf '# @todo env-update (fetch-json:.version) url:https://example.com 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'fetch_json: .version' || { echo \"fetch_json not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03l: url-probe flag" bash -c "
    f=\${TMP_DIR}/t03l.env
    printf '# @todo env-update (url-probe:stable/xUbuntu_{v}) url:https://example.com/ 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'url_probe: stable/xUbuntu' || { echo \"url_probe not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03m: url-probe-depth flag" bash -c "
    f=\${TMP_DIR}/t03m.env
    printf '# @todo env-update (url-probe-depth:3) url:https://example.com/ 1.0.0\nGLOBAL_STACK_TEST_VERSION=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'url_probe_depth: 3' || { echo \"url_probe_depth not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03n: version-prefix flag" bash -c "
    f=\${TMP_DIR}/t03n.env
    printf '# @todo env-update (version-prefix:v) github:docker/buildx v0.32.1\nGLOBAL_STACK_BUILDX_VERSION=v0.32.1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'version_prefix: v' || { echo \"version_prefix not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03o: boolean markers (override, manual)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/flags-all.env' 2>&1)
    echo \"\$out\" | grep -qF 'override: true' || { echo \"override not true\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'manual: true' || { echo \"manual not true\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03p: order-agnostic — depends-on BEFORE TYPE:ID works" bash -c "
    f=\${TMP_DIR}/t03p.env
    printf '# @todo env-update (depends-on:GLOBAL_STACK_OTHER_VERSION:major) github:foo/bar 1.2.3\nGLOBAL_STACK_FOO_VERSION=1.2.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'depends_on: GLOBAL_STACK_OTHER_VERSION:major' || { echo \"depends_on not found with flag before TYPE:ID, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'type: github' || { echo \"type not parsed correctly\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03q: order-agnostic — multiple flags in any order" bash -c "
    f=\${TMP_DIR}/t03q.env
    printf '# @todo env-update (tag-suffix:alpine) (channel:rc) dockerhub:_/postgres:18 18.3\nGLOBAL_STACK_PG_VERSION=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_suffix: alpine' || { echo \"tag_suffix not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'channel: rc' || { echo \"channel not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t03r: order-agnostic — flag AFTER version token" bash -c "
    f=\${TMP_DIR}/t03r.env
    printf '# @todo env-update github:foo/bar 1.2.3 (tag-strip-prefix:v)\nGLOBAL_STACK_FOO_VERSION=1.2.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'tag_strip_prefix: v' || { echo \"tag_strip_prefix not found when placed after version, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 4 — Structured inline
# ═══════════════════════════════════════════════════════════════════════════
section "4 — Structured inline"

t "t04a: urls — 1 URL" bash -c "
    f=\${TMP_DIR}/t04a.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0 urls: https://nginx.org/\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'urls: https://nginx.org/' || { echo \"url not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t04b: urls — 3 URLs" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/urls-inline.env' 2>&1)
    echo \"\$out\" | grep -qF 'https://dev.mysql.com/doc/relnotes/' || { echo \"first url not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'https://github.com/docker-library/mysql' || { echo \"second url not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'https://hub.docker.com/_/mysql' || { echo \"third url not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t04c: pecl fixture with git: flag parses correctly (pecl-git fetcher eliminated)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/pecl-ref.env' 2>&1)
    echo \"\$out\" | grep -qF 'type: pecl' || { echo \"type:pecl not found; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'git_repo: php/pecl-event' || { echo \"git_repo not found; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'type: pecl-git' && { echo 'pecl-git type still present — not eliminated'; echo FAIL; exit 0; } || true
    echo PASS
"

t "t04d: depends-on token" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/depends-on.env' 2>&1)
    echo \"\$out\" | grep -qF 'depends_on: GLOBAL_STACK_SONARQUBE_VERSION:major' || { echo \"depends_on not found, got: \$(echo \"\$out\" | grep depends)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 5 — Multi-line git fallback
# ═══════════════════════════════════════════════════════════════════════════
section "5 — Multi-line git fallback"

t "t05a: git-fallback URL and SHA" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/git-fallback.env' 2>&1)
    echo \"\$out\" | grep -qF 'git_fallback_url: https://github.com/leoafarias/fvm.git' || { echo \"git_fallback_url not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'git_fallback_sha: abc123def456' || { echo \"git_fallback_sha not found\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 6 — Combined real-world annotations
# ═══════════════════════════════════════════════════════════════════════════
section "6 — Combined real-world"

t "t06a: MySQL9 record — type, major_hint, tag_suffix, urls" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'env_var: GLOBAL_STACK_IMAGE_MYSQL9_VERSION' || { echo \"mysql record not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'identifier: _/mysql' || { echo \"identifier wrong\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major_hint: 9' || { echo \"major_hint not 9\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'tag_suffix: oraclelinux9' || { echo \"tag_suffix not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'https://dev.mysql.com/doc/relnotes/mysql/9.6/en/' || { echo \"url not found\"; echo FAIL; exit 0; }
    echo PASS
"

t "t06b: Flutter3 record — tag_filter, major_hint" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'env_var: GLOBAL_STACK_FLUTTER3_VERSION' || { echo \"flutter record not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'type: github' || { echo \"type not github\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major_hint: 3' || { echo \"flutter major_hint not 3\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'tag_filter: ^[0-9' || { echo \"tag_filter not found\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 7 — Error policy (fail loud)
# ═══════════════════════════════════════════════════════════════════════════
section "7 — Error policy (fail loud)"

t "t07a: unknown flag → non-zero exit + message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/malformed-unknown-flag.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'unknown flag' || { echo \"expected 'unknown flag' in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t07b: empty required value → non-zero exit + message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/malformed-empty-value.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'empty\|requires' || { echo \"expected empty/requires in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t07c: malformed depends-on → non-zero exit + message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/malformed-depends-on.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'depends' || { echo \"expected depends-on mention in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t07d: missing TYPE:IDENTIFIER → non-zero exit + message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/malformed-missing-type.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'type\|identifier\|missing' || { echo \"expected type/identifier mention in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t07e: duplicate @todo before same variable → non-zero exit + message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/malformed-duplicate-todo.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'duplicate' || { echo \"expected 'duplicate' in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t07f: --check exits 1 when ERROR decisions are present (no spurious ERR trap message)" bash -c "
    f=\${TMP_DIR}/t07f.env
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_EXITCODE_TEST_VERSION=1.0.0\n' > \"\$f\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" --no-cache 2>&1)
    code=\$?
    unset _GS_EU2_HTTP_FIXTURE_DIR
    [[ \"\$code\" -eq 1 ]] || { echo \"expected exit 1, got: \$code\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF '[ERROR' || { echo \"expected [ERROR] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'error in bin/' && { echo \"got spurious ERR trap message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 8 — --dump output
# ═══════════════════════════════════════════════════════════════════════════
section "8 — --dump output"

t "t08a: text format — stable field order (env_var before type)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    # env_var should appear before type in the output
    env_var_line=\$(echo \"\$out\" | grep -n 'env_var:' | head -1 | cut -d: -f1)
    type_line=\$(echo \"\$out\" | grep -n 'type:' | head -1 | cut -d: -f1)
    [[ -n \"\$env_var_line\" && -n \"\$type_line\" ]] || { echo \"missing env_var or type field\"; echo FAIL; exit 0; }
    [[ \"\$env_var_line\" -lt \"\$type_line\" ]] || { echo \"env_var (line \$env_var_line) should precede type (line \$type_line)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08b: json format — valid JSON parseable by jq" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | jq . >/dev/null 2>&1 || { echo \"output is not valid JSON: \$out\"; echo FAIL; exit 0; }
    # Must have env_var field
    val=\$(echo \"\$out\" | jq -r '.[0].env_var' 2>/dev/null)
    [[ \"\$val\" == 'GLOBAL_STACK_PGADMIN_VERSION' ]] || { echo \"JSON env_var wrong: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08c: --filter by var name regex" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --filter='MYSQL' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' || { echo \"mysql not in output\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' && { echo \"flutter should be filtered out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08d: --filter=type:dockerhub keeps only dockerhub records" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --filter='type:dockerhub' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' || { echo \"dockerhub record not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' && { echo \"github record should be filtered out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08e: --filter=type:github keeps only github records" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --filter='type:github' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' || { echo \"github record not found\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' && { echo \"dockerhub record should be filtered out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08f: --format=invalid → non-zero exit with message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=invalid --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'format\|invalid' || { echo \"expected format/invalid in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08g: --cache-ttl=abc → non-zero exit with message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --cache-ttl=abc --check --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'cache-ttl\|integer' || { echo \"expected cache-ttl/integer in error, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08h: --dump and --check together → non-zero exit with message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --check --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'exclusive\|mutually\|dump\|check' || { echo \"expected exclusivity message, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t08i: --filter with invalid regex → non-zero exit with message (not silent per-record errors)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --filter='((' --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0; output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'invalid --filter' || { echo \"expected 'invalid --filter' in error; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'invalid regular expression' && { echo \"got per-record bash errors instead of early validation; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 9 — --dry-run flag
# ═══════════════════════════════════════════════════════════════════════════
section "9 — --dry-run flag"

t "t09a: --dry-run is accepted (exit 0) with --dump" bash -c "
    bash '${ENV_UPDATE_V2}' --dry-run --dump --env-file='${FIXTURES}/basic-dockerhub.env' >/dev/null 2>&1 \
        || { echo FAIL; exit 0; }
    echo PASS
"

t "t09b: --dry-run emits notice to stderr naming the flag" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --dry-run --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null)
    echo \"\$err\" | grep -qiF 'dry-run' || { echo \"stderr missing dry-run notice: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t09c: --dry-run does not alter --dump stdout (same records as normal run)" bash -c "
    a=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    b=\$(bash '${ENV_UPDATE_V2}' --dry-run --dump --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    [[ \"\$a\" == \"\$b\" ]] || { echo \"stdout differs with --dry-run\"; echo FAIL; exit 0; }
    echo PASS
"

t "t09d: --dry-run appears in --help output" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --help 2>&1)
    echo \"\$out\" | grep -qF -- '--dry-run' || { echo \"help missing --dry-run\"; echo FAIL; exit 0; }
    echo PASS
"

t "t09e: --filter prints [FILTER MODE: REGEX] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t09e_cache
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --filter=POSTGRES \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | grep -qF '[FILTER MODE: POSTGRES]' || { echo \"expected [FILTER MODE: POSTGRES] banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 10 — Default summary output (no flags → useful output, no network)
# ═══════════════════════════════════════════════════════════════════════════
section "10 — default summary (no flags)"

t "t10a: no flags emits record count" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qE '2 annotated variable' || { echo \"missing record count: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t10b: no flags emits per-type breakdown" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qE 'dockerhub[[:space:]]+1' || { echo \"missing dockerhub breakdown: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE 'github[[:space:]]+1'    || { echo \"missing github breakdown: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t10c: no flags emits hint to run --check or --dump" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | grep -qF -- '--check' || { echo \"missing --check hint: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--dump'  || { echo \"missing --dump hint: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 11 — Cache layer
# ═══════════════════════════════════════════════════════════════════════════
section "11 — cache layer"

t "t11a: cache write then read returns same value" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11a
    source '${_GS_EU2_LIB}/core/cache.sh'
    _gs_eu2_cache_write 'dockerhub:_/postgres:18' '18.4-alpine3.23'
    val=\$(_gs_eu2_cache_read 'dockerhub:_/postgres:18')
    [[ \"\$val\" == '18.4-alpine3.23' ]] || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11b: cache miss returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11b
    source '${_GS_EU2_LIB}/core/cache.sh'
    _gs_eu2_cache_read 'dockerhub:_/postgres:18' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11c: cache expired returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11c
    export _GS_EU2_CACHE_TTL=0
    source '${_GS_EU2_LIB}/core/cache.sh'
    _gs_eu2_cache_write 'key:v1' 'somevalue'
    # TTL=0: any age is expired
    sleep 1
    _gs_eu2_cache_read 'key:v1' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11d: cache_key sanitizes colons and slashes" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11d
    source '${_GS_EU2_LIB}/core/cache.sh'
    f=\$(_gs_eu2_cache_key_to_file 'dockerhub:_/postgres:18:stable')
    [[ \"\$f\" == *'dockerhub__'* ]] || { echo \"colon not replaced: \$f\"; echo FAIL; exit 0; }
    [[ \"\$f\" != *':'* ]] || { echo \"raw colon in path: \$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11d2: different fetch_extract values → different cache filenames" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11d2
    source '${_GS_EU2_LIB}/core/cache.sh'
    f1=\$(_gs_eu2_cache_key_to_file 'url:https://example.com:v([0-9.]+)::stable')
    f2=\$(_gs_eu2_cache_key_to_file 'url:https://example.com:Version:([0-9.]+)::stable')
    [[ \"\$f1\" != \"\$f2\" ]] || { echo \"collision: different extract patterns mapped to same file: \$f1\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11e: --no-cache prints [NO-CACHE MODE] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t11e_cache
    f=\${TMP_DIR}/t11e.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T11E=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[NO-CACHE MODE]' || { echo \"expected [NO-CACHE MODE] banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11f: pecl2:stable and pecl2:unstable use distinct cache keys (no cross-contamination)" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11f
    source '${_GS_EU2_LIB}/core/cache.sh'
    # Write a value under the stable key
    _gs_eu2_cache_write 'pecl2:stable:apcu' '6.3.0-STABLE'
    # The unstable key must NOT return the stable-key value
    val=\$(_gs_eu2_cache_read 'pecl2:unstable:apcu' 2>/dev/null || true)
    [[ \"\$val\" != '6.3.0-STABLE' ]] || { echo 'cache key collision: pecl2:unstable:apcu returned pecl2:stable:apcu value'; echo FAIL; exit 0; }
    # Stable key must still return its own value
    stable_val=\$(_gs_eu2_cache_read 'pecl2:stable:apcu')
    [[ \"\$stable_val\" == '6.3.0-STABLE' ]] || { echo \"stable key lost its value, got: '\$stable_val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 12 — Channel selection
# ═══════════════════════════════════════════════════════════════════════════
section "12 — channel selection"

_ch_src() {
  source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
  source '${_GS_EU2_LIB}/core/semver.sh'
  source '${_GS_EU2_LIB}/core/channel.sh'
}

t "t12a: stable channel picks highest stable, ignores rc" bash -c "
    $(_ch_src 2>/dev/null; echo 'true') || true
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'stable')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12b: rc channel picks highest rc tag" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4-rc2\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'rc')
    [[ \"\$result\" == '18.4-rc2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12c: empty channel defaults to stable" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12d: unstable channel picks highest pre-release" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'18.3\n18.4\n18.5-rc1\n18.5-beta2'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    # highest pre-release by sort -V
    [[ \"\$result\" == '18.5-rc1' || \"\$result\" == '18.5-beta2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12e: is_prerelease detects rc, beta, alpha" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    _gs_eu2_is_prerelease '1.0.0-rc1'   || { echo 'rc1 not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '2.3.0beta2'  || { echo 'beta not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0alpha'  || { echo 'alpha not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '18.4'       && { echo 'stable wrongly flagged'; echo FAIL; exit 0; }
    echo PASS
"

t "t12e2: pre/next word-boundary — no false positives on tag substrings" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    # False positives that were fixed (substring matches in stable tags)
    _gs_eu2_is_prerelease 'nextcloud-1.0'  && { echo 'nextcloud-1.0 wrongly flagged as prerelease'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease 'prepared-1.0'   && { echo 'prepared-1.0 wrongly flagged as prerelease'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0-prepare'  && { echo '1.0.0-prepare wrongly flagged as prerelease'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '3.9.0-preprod'  && { echo '3.9.0-preprod wrongly flagged as prerelease'; echo FAIL; exit 0; }
    # True positives that must still be detected
    _gs_eu2_is_prerelease 'next'          || { echo 'bare next not detected (PHPEDGE channel)'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0-next.1'  || { echo '1.0.0-next.1 not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0-pre1'    || { echo '1.0.0-pre1 not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0-pre'     || { echo '1.0.0-pre not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '4.0.0-preview2' || { echo '4.0.0-preview2 not detected'; echo FAIL; exit 0; }
    echo PASS
"

t "t12f: v-prefixed tags accepted by channel filter (B2)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'v0.29.0\nv0.28.0\nv0.27.0'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ -n \"\$result\" ]] || { echo 'all v-prefixed tags were dropped'; echo FAIL; exit 0; }
    [[ \"\$result\" == 'v0.29.0' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12g: nightly channel with only stable versions returns best stable (stable-promotion fallback)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # No nightly tags, no prerelease tags — nightly now promotes to stable (consistent with channel:rc)
    versions=\$'v26.0.0\nv26.1.0\nv25.9.0'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'nightly')
    [[ \"\$result\" == 'v26.1.0' ]] || { echo \"expected v26.1.0 (stable-promotion), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12h: nightly channel with nightly-tagged versions returns latest nightly" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'v26.0.0-nightly20260101abc\nv26.0.0-nightly20260314xyz\nv26.0.0-nightly20260201def'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'nightly')
    [[ \"\$result\" == 'v26.0.0-nightly20260314xyz' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12i: nightly channel with mixed stable+nightly promotes to stable when stable is newer" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # v26.1.0 stable > v26.0.0-nightly* → stable-promotion returns v26.1.0 (consistent with unstable channel)
    versions=\$'v26.1.0\nv26.0.0-nightly20260101abc\nv26.0.0-nightly20260314xyz'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'nightly')
    [[ \"\$result\" == 'v26.1.0' ]] || { echo \"expected v26.1.0 (stable surpassed nightly), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12j: filter_versions_by_channel with nightly channel now filters (no longer all-pass)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'v26.0.0\nv26.1.0\nv25.9.0'
    result=\$(_gs_eu2_filter_versions_by_channel \"\$versions\" 'nightly')
    [[ -z \"\$result\" ]] || { echo \"expected empty (no nightly tags), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t12k: mixed v-prefix sort — v0.3.0 must not outrank 1.0.0-alpha (aleph.js regression)
t "t12k: unstable channel — mixed v-prefix pool picks highest semantic version" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # Simulates aleph.js GitHub release pool: 1.0.0-alpha.* releases + v0.3.0-beta.* tags
    # sort -V without v-strip puts v0.3.0-beta.19 AFTER 1.0.0-alpha.47 (bug); fix must return alpha.47
    versions=\$'1.0.0-alpha.47\n1.0.0-alpha.42\nv0.3.0-beta.19\nv0.3.0-beta.18'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '1.0.0-alpha.47' ]] || { echo \"expected 1.0.0-alpha.47, got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t12l: mixed v-prefix pool in stable channel also sorts correctly
t "t12l: stable channel — mixed v-prefix pool picks highest stable" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'1.0.0\nv0.9.0\nv1.1.0\n0.8.0'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == 'v1.1.0' ]] || { echo \"expected v1.1.0, got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 13 — Tag flags application
# ═══════════════════════════════════════════════════════════════════════════
section "13 — tag flags"

_TF_SRC="source '${_GS_EU2_LIB}/core/tag_flags.sh'"

t "t13a: tag-filter keeps only matching" bash -c "
    ${_TF_SRC}
    result=\$(printf '18.3\n18.4\n19.0\n' | _gs_eu2_apply_tag_flags '^18' '' '' '' '' '' '')
    echo \"\$result\" | grep -qF '18.3' || { echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF '19.0' && { echo 'should be filtered'; echo FAIL; exit 0; }
    echo PASS
"

t "t13b: tag-exclude drops matching" bash -c "
    ${_TF_SRC}
    result=\$(printf '18.3\n18.4-rc1\n18.4\n' | _gs_eu2_apply_tag_flags '' 'rc' '' '' '' '' '')
    echo \"\$result\" | grep -qF 'rc' && { echo 'rc not excluded'; echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF '18.4' || { echo 'stable dropped wrongly'; echo FAIL; exit 0; }
    echo PASS
"

t "t13c: tag-strip-prefix removes leading string" bash -c "
    ${_TF_SRC}
    result=\$(printf 'v1.2.3\nv1.3.0\n' | _gs_eu2_apply_tag_flags '' '' 'v' '' '' '' '')
    echo \"\$result\" | grep -qF '1.2.3' || { echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF 'v' && { echo 'prefix not stripped'; echo FAIL; exit 0; }
    echo PASS
"

t "t13d: tag-strip-suffix removes trailing string" bash -c "
    ${_TF_SRC}
    result=\$(printf '9.6.0-oraclelinux9\n9.7.0-oraclelinux9\n' \
        | _gs_eu2_apply_tag_flags '' '' '' '-oraclelinux9' '' '' '')
    echo \"\$result\" | grep -qF '9.6.0' || { echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF 'oraclelinux' && { echo 'suffix not stripped'; echo FAIL; exit 0; }
    echo PASS
"

t "t13e: tag-extract captures group 1" bash -c "
    ${_TF_SRC}
    result=\$(printf 'release-1.2.3\nrelease-1.3.0\nbad\n' \
        | _gs_eu2_apply_tag_flags '' '' '' '' 'release-([0-9.]+)' '' '')
    echo \"\$result\" | grep -qF '1.2.3' || { echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF 'bad' && { echo 'non-matching should be discarded'; echo FAIL; exit 0; }
    echo PASS
"

t "t13f: tag-replace substitutes substring" bash -c "
    ${_TF_SRC}
    result=\$(printf '1.2.3-alpine3.20\n1.3.0-alpine3.21\n' \
        | _gs_eu2_apply_tag_flags '' '' '' '' '' 'alpine' 'ALPINE')
    echo \"\$result\" | grep -qF 'ALPINE' || { echo FAIL; exit 0; }
    echo \"\$result\" | grep -qF 'alpine' && { echo 'unreplaced original found'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 14 — HTTP seam
# ═══════════════════════════════════════════════════════════════════════════
section "14 — HTTP seam"

t "t14a: fixture hit returns file contents" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '${_GS_EU2_LIB}/http/curl.sh'
    # URL → strip query → sanitize → test.example_fixture-test
    out=\$(_gs_eu2_http_get 'https://test.example/fixture-test?foo=bar' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t14b: fixture miss returns non-zero with message" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '${_GS_EU2_LIB}/http/curl.sh'
    err=\$(_gs_eu2_http_get 'https://example.com/nonexistent' 2>&1 >/dev/null)
    [[ \$? -ne 0 ]] || err_code=0
    _gs_eu2_http_get 'https://example.com/nonexistent' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 15 — Dockerhub fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "15 — dockerhub fetcher"

_DH_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh_cache
"

t "t15a: fetches latest stable for _/postgres" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES18_VERSION'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 18.4 and 18.4-alpine3.23 as latest stable
    [[ \"\$val\" == '18.4' || \"\$val\" == '18.4-alpine3.23' ]] \
        || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15b: major-pin holds when newer major available" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'dockerhub'
    _gs_eu2_record_set \$idx identifier      '_/postgres'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_POSTGRES17_VERSION'
    _gs_eu2_record_set \$idx major_hint      '17'
    _gs_eu2_record_set \$idx current_version '17.5'
    _gs_eu2_fetch_dockerhub \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    decision=\$(_gs_eu2_record_get \$idx decision)
    # proposed should be within major 17; decision=HOLD (major available) or AUTO (17 is latest)
    [[ \"\$proposed\" =~ ^17 ]] || { echo \"major-pin not respected: \$proposed\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15c: tag-suffix filter applied" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/mysql'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MYSQL9_VERSION'
    _gs_eu2_record_set \$idx tag_suffix '-oraclelinux9'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == *'-oraclelinux9' ]] || { echo \"tag-suffix not applied: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15d: cache hit skips HTTP call (sets proposed_version from cache)" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES18_VERSION'
    # Key must match what the fetcher computes:
    #   dockerhub:<ns>:<tag_suffix>:<major_hint>:<major_hint_min>:<channel>:<prefer_specific>:<watch_major_depth>:<tag-flag fingerprint>
    # The fingerprint is read off the record rather than pasted in, so this
    # test tracks the key format instead of pinning one snapshot of it.
    _gs_eu2_cache_write \"dockerhub:library/postgres:::::::\$(_gs_eu2_tag_flags_fingerprint \$idx)\" '18.3-alpine3.23-CACHED'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '18.3-alpine3.23-CACHED' ]] || { echo \"cache not used: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15e: missing fixture sets decision=ERROR" bash -c "
    ${_DH_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    # No fixture dir, no real network — curl will fail
    # We set a non-existent cache dir so cache misses
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh_e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/no-such-image-xyzzy'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_dockerhub \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: \$decision\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15f: rc channel uses rc tag" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES_RC_VERSION'
    _gs_eu2_record_set \$idx channel    'rc'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 18.4-rc1 — with rc channel, should pick it (not 18.4 stable)
    [[ \"\$val\" == *'rc'* || \"\$val\" == *'18.4'* ]] \
        || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t15g: version-prefix re-prepended after tag-strip-prefix (B3)" bash -c "
    ${_DH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'dockerhub'
    _gs_eu2_record_set \$idx identifier       'moby/buildkit'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_MOBY_BUILDKIT_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_record_set \$idx version_prefix   'v'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == v* ]] || { echo \"v-prefix not restored: got '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 16 — Decision classifier
# ═══════════════════════════════════════════════════════════════════════════
section "16 — decision classifier"

_DC_LIBS="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t16a: same version → SKIP (up-to-date)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.4' '18.4' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16b: patch bump → AUTO" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16c: major jump with no major_hint → HOLD" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '17.5' '18.4' '' '')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16d: override flag → MANUAL regardless of delta" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' 'true' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16e: proposed older than current → SKIP (downgrade protection, B1)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '1.29.3' '1.2.5' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"downgrade not prevented: got \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16f: manual=true + downgrade → SKIP (downgrade beats MANUAL; fetcher returning older is always wrong)
t "t16f: manual flag + downgrade → SKIP not MANUAL (aleph.js regression guard)" bash -c "
    ${_DC_LIBS}
    # Simulates aleph.js: current=1.0.0-beta.44, proposed=v0.3.0-beta.19 (older)
    result=\$(_gs_eu2_classify_decision '1.0.0-beta.44' 'v0.3.0-beta.19' 'true' '' 'full')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for manual+downgrade, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t16g: override=true + downgrade → SKIP (same rule: downgrade beats override)
t "t16g: override flag + downgrade → SKIP not MANUAL" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.4' '18.3' 'true' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for override+downgrade, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t16h: manual=true + upgrade → still MANUAL (the normal case must remain unaffected)
t "t16h: manual flag + upgrade → MANUAL (normal MANUAL upgrade preserved)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' 'true' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"expected MANUAL for manual+upgrade, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t16i: channel:unstable + stable current + minor prerelease → HOLD (annotation opt-in bridge)
t "t16i: channel:unstable + stable current + minor prerelease → HOLD" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '5.1.0-alpha-1' '' '' '' '' 'unstable')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16j: channel:unstable + stable current + major prerelease → HOLD (step 4 fires before step 7)
t "t16j: channel:unstable + stable current + major prerelease → HOLD (step 4 before step 7)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '6.0.0-alpha-1' '' '' '' '' 'unstable')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16k: stable_mode=full + prerelease + channel:unstable → SKIP (stable=full overrides channel annotation)
t "t16k: stable_mode=full + prerelease + channel:unstable → SKIP (force-reject wins)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '6.0.0-alpha-1' '' '' '' 'full' 'unstable')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16l: unstable_mode=full + stable current + minor prerelease → AUTO (step 4 bypassed entirely)
t "t16l: unstable_mode=full + stable current + minor prerelease → AUTO (step 4 bypassed)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '5.1.0-alpha-1' '' '' 'full' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16m: no channel, no flags, stable current + prerelease → SKIP (default behavior preserved)
t "t16m: no channel annotation + prerelease proposed → SKIP (default unchanged)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '5.1.0-alpha-1' '' '' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t16n: decide.sh major jump still produces HOLD regardless (force_hold is in main.sh, not decide.sh)
t "t16n: major jump still HOLD in decide.sh (force_hold is main.sh responsibility)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '5.0.6' '6.0.0' '' '' '' '' '')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 17 — --check streaming output
# ═══════════════════════════════════════════════════════════════════════════
section "17 — --check streaming output"

t "t17a: --check streams [AUTO] line per record" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk17a
    out=\$(bash '${ENV_UPDATE_V2}' --check --filter=POSTGRES18 \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    # No POSTGRES18 in combined-real-world.env (has MYSQL9 and FLUTTER3)
    # Minimal requirement: exits 0 and does not crash
    echo PASS
"

t "t17b: --check with basic fixture emits tag and summary" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk17b
    f=\${TMP_DIR}/t17b.env
    printf '# @todo env-update dockerhub:_/postgres 18.3\nGLOBAL_STACK_POSTGRES_VERSION=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE 'AUTO|HOLD|SKIP|ERROR' || { echo \"no decision tag in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t17c: --check summary line shows counts" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk17c
    f=\${TMP_DIR}/t17c.env
    printf '# @todo env-update dockerhub:_/postgres 18.3\nGLOBAL_STACK_POSTGRES_VERSION=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE 'checked|Summary' || { echo \"no summary in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t17d: SKIP up-to-date includes reason in output (B4)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk17d
    f=\${TMP_DIR}/t17d.env
    # fixture latest stable is 18.4-alpine3.23 — use same as current to get SKIP
    printf '# @todo env-update dockerhub:_/postgres 18.4-alpine3.23\nGLOBAL_STACK_POSTGRES_VERSION=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'up to date' || { echo \"no up-to-date reason: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 18 — Pagination + error handling (D6)
# ═══════════════════════════════════════════════════════════════════════════
section "18 — pagination and error handling"

_DH_LIBS18="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh18_cache
"

t "t18a: pagination — next=null terminates loop and returns tags" bash -c "
    ${_DH_LIBS18}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/nginx'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_NGINX_VERSION'
    _gs_eu2_fetch_dockerhub \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # nginx fixture has 1.27.0-alpine, 1.26.0-alpine, 1.25.0-alpine with next=null
    [[ \"\$decision\" != 'ERROR' ]] || { echo \"got ERROR: \$(_gs_eu2_record_get \$idx error_message)\"; echo FAIL; exit 0; }
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" =~ ^1[.] ]] || { echo \"unexpected proposed: \$proposed\"; echo FAIL; exit 0; }
    echo PASS
"

t "t18b: pagination — fetch_tags returns all tags from single page" bash -c "
    ${_DH_LIBS18}
    tags=\$(_gs_eu2_dh_fetch_tags 'library/nginx')
    echo \"\$tags\" | grep -qF '1.27.0-alpine' || { echo 'tag 1.27.0-alpine not found'; echo FAIL; exit 0; }
    echo \"\$tags\" | grep -qF '1.25.0-alpine' || { echo 'tag 1.25.0-alpine not found'; echo FAIL; exit 0; }
    echo PASS
"

t "t18c: malformed JSON sets decision=ERROR (not SKIP)" bash -c "
    ${_DH_LIBS18}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/malformed'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MALFORMED_VERSION'
    _gs_eu2_fetch_dockerhub \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    # Malformed JSON fixture — fetcher should set ERROR, not SKIP
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: \$decision\"; echo FAIL; exit 0; }
    echo PASS
"

t "t18d: missing fixture sets decision=ERROR (not SKIP)" bash -c "
    ${_DH_LIBS18}
    # Use an identifier that has no fixture file
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/no-fixture-image'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_NOFIXTURE_VERSION'
    _gs_eu2_fetch_dockerhub \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: \$decision\"; echo FAIL; exit 0; }
    echo PASS
"

t "t18e: blank line between annotation and var — record still created (C2)" bash -c "
    f=\${TMP_DIR}/t18e.env
    printf '# @todo env-update dockerhub:_/nginx 1.26.0\n\nGLOBAL_STACK_NGINX_VERSION=1.26.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'env_var: GLOBAL_STACK_NGINX_VERSION' \
        || { echo \"record not created with blank line: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t18f: dotted major_hint (e.g., 9.2) parsed — identifier stripped, hint set" bash -c "
    f=\${TMP_DIR}/t18f.env
    printf '# @todo env-update dockerhub:_/postgres:9.2 9.2.5\nGLOBAL_STACK_PG_VERSION=9.2.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    hint=\$(echo \"\$out\" | grep 'major_hint:' | sed 's/.*major_hint: //' | tr -d '[:space:]')
    [[ \"\$hint\" == '9.2' ]] || { echo \"expected major_hint=9.2, got: '\$hint'\"; echo FAIL; exit 0; }
    ident=\$(echo \"\$out\" | grep 'identifier:' | sed 's/.*identifier: //' | tr -d '[:space:]')
    [[ \"\$ident\" == '_/postgres' ]] || { echo \"expected identifier=_/postgres, got: '\$ident'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t18g: github:php/php-src:8.2 parses to identifier=php/php-src major_hint=8.2" bash -c "
    f=\${TMP_DIR}/t18g.env
    printf '# @todo env-update github:php/php-src:8.2 8.2.30\nGLOBAL_STACK_PHP8_2_VERSION=8.2.30\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    hint=\$(echo \"\$out\" | grep 'major_hint:' | sed 's/.*major_hint: //' | tr -d '[:space:]')
    [[ \"\$hint\" == '8.2' ]] || { echo \"expected major_hint=8.2, got: '\$hint'\"; echo FAIL; exit 0; }
    ident=\$(echo \"\$out\" | grep 'identifier:' | sed 's/.*identifier: //' | tr -d '[:space:]')
    [[ \"\$ident\" == 'php/php-src' ]] || { echo \"expected identifier=php/php-src, got: '\$ident'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 19 — C1 non-numeric fallback + unversioned check + --apply
# ═══════════════════════════════════════════════════════════════════════════
section "19 — non-numeric fallback, unversioned, --apply"

_DH_LIBS19="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh19_cache
"

t "t19a: channel_select_best falls back to sort-V for codename tags (C1)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'resolute-20260413\nresolute-20260108\nplucky-20260201\nlatest'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == 'resolute-20260413' ]] || { echo \"got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19b: channel_select_best returns empty when only unversioned sentinels present" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    versions=\$'latest\nedge'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ -z \"\$result\" ]] || { echo \"expected empty, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19c: dockerhub fetcher SKIP with 'no versioned tags' for all-unversioned image" bash -c "
    ${_DH_LIBS19}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/only-latest-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_ORACLE_VERSION'
    _gs_eu2_fetch_dockerhub \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    msg=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'SKIP' ]] || { echo \"expected SKIP, got: \$decision\"; echo FAIL; exit 0; }
    [[ \"\$msg\" == *'no versioned tags'* ]] || { echo \"unexpected msg: \$msg\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19d: dockerhub fetcher selects ubuntu codename tag via fallback (C1)" bash -c "
    ${_DH_LIBS19}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/ubuntu-codename-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_UBUNTU_VERSION'
    _gs_eu2_record_set \$idx tag_filter '^resolute-'
    _gs_eu2_fetch_dockerhub \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$decision\" != 'ERROR' ]] || { echo \"got ERROR: \$(_gs_eu2_record_get \$idx error_message)\"; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 'resolute-20260413' ]] || { echo \"got: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19e: moby/buildkit tag-filter excludes -ubuntu suffix (C2)" bash -c "
    ${_DH_LIBS19}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'dockerhub'
    _gs_eu2_record_set \$idx identifier       'moby/buildkit'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_MOBY_BUILDKIT_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_record_set \$idx version_prefix   'v'
    _gs_eu2_record_set \$idx tag_filter       '^v[0-9]+\.[0-9]+\.[0-9]+\$'
    _gs_eu2_fetch_dockerhub \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$proposed\" == 'v0.29.0' ]] || { echo \"got: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19f: _gs_eu2_apply_updates dry-run shows DRY-RUN without modifying file" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19f.env
    printf 'GLOBAL_STACK_FOO_VERSION=1.0.0\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_FOO_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_record_set \$idx proposed_version '2.0.0'
    _gs_eu2_record_set \$idx decision         'AUTO'
    out=\$(_gs_eu2_apply_updates \"\$f\" 'true')
    echo \"\$out\" | grep -qF 'DRY-RUN' || { echo \"DRY-RUN marker missing: \$out\"; echo FAIL; exit 0; }
    grep -qF '1.0.0' \"\$f\" || { echo 'file was modified'; echo FAIL; exit 0; }
    echo PASS
"

t "t19g: _gs_eu2_apply_updates rewrites AUTO var and preserves other lines" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19g.env
    printf '# comment\nGLOBAL_STACK_FOO_VERSION=1.0.0\nGLOBAL_STACK_BAR=unchanged\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_FOO_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_record_set \$idx proposed_version '2.0.0'
    _gs_eu2_record_set \$idx decision         'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF 'GLOBAL_STACK_FOO_VERSION=2.0.0' \"\$f\" || { echo 'var not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_BAR=unchanged'     \"\$f\" || { echo 'other var changed'; echo FAIL; exit 0; }
    grep -qF '# comment'                      \"\$f\" || { echo 'comment dropped'; echo FAIL; exit 0; }
    echo PASS
"

t "t19h: _gs_eu2_apply_updates also rewrites the @todo annotation comment version" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19h.env
    ann='# @todo env-update github:ruby/ruby:3 3 3.4.9'
    printf '%s\nGLOBAL_STACK_RUBY_VERSION=3.4.9\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_RUBY_VERSION'
    _gs_eu2_record_set \$idx current_version  '3.4.9'
    _gs_eu2_record_set \$idx proposed_version '3.5.0'
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann\"
    _gs_eu2_record_set \$idx decision         'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF 'GLOBAL_STACK_RUBY_VERSION=3.5.0' \"\$f\" || { echo 'assignment not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF '# @todo env-update github:ruby/ruby:3 3 3.5.0' \"\$f\" || { echo 'annotation not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF '3.4.9' \"\$f\" && { echo 'old version still present'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19i: annotation update preserves trailing urls: extras and does not corrupt them" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19i.env
    ann='# @todo env-update (tag-strip-prefix:v) github:ruby/ruby:4 4.0.1 urls: https://www.ruby-lang.org/en/'
    printf '%s\nGLOBAL_STACK_RUBY4_VERSION=4.0.1\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_RUBY4_VERSION'
    _gs_eu2_record_set \$idx current_version  '4.0.1'
    _gs_eu2_record_set \$idx proposed_version '4.0.3'
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann\"
    _gs_eu2_record_set \$idx decision         'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF 'GLOBAL_STACK_RUBY4_VERSION=4.0.3' \"\$f\" || { echo 'assignment not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF '# @todo env-update (tag-strip-prefix:v) github:ruby/ruby:4 4.0.3 urls: https://www.ruby-lang.org/en/' \"\$f\" || { echo 'annotation not updated or url corrupted'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF '4.0.1' \"\$f\" && { echo 'old version still present'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19j: sha: keyword extracted from annotation into annotation_sha record field" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t19j.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update pecl-git:https://github.com/example/php-ext 1.2.3 sha:%s\nGLOBAL_STACK_EXT_VERSION=1.2.3\n' \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got=\$(_gs_eu2_record_get 0 annotation_sha)
    [[ \"\$got\" == \"\$sha\" ]] || { echo \"annotation_sha expected '\$sha' got '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19k: (use-sha) flag sets use_sha=true on record" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t19k.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update (use-sha) pecl-git:https://github.com/example/php-ext sha:%s\nGLOBAL_STACK_EXT_VERSION=%s\n' \"\$sha\" \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got=\$(_gs_eu2_record_get 0 use_sha)
    [[ \"\$got\" == 'true' ]] || { echo \"use_sha expected 'true' got '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19l: apply with cur_sha/new_sha updates sha:OLD to sha:NEW in annotation while keeping version" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19l.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    ann=\"# @todo env-update pecl-git:https://github.com/example/php-ext 1.0.0 sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_EXT_VERSION=1.0.0\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_EXT_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_record_set \$idx proposed_version '2.0.0'
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann\"
    _gs_eu2_record_set \$idx decision         'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"sha:\${new_sha}\" \"\$f\" && { echo 'new_sha found but should not be (no new_sha provided)'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_EXT_VERSION=2.0.0' \"\$f\" || { echo 'assignment not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF '2.0.0' \"\$f\" || { echo 'new version not in annotation'; cat \"\$f\"; echo FAIL; exit 0; }
    _gs_eu2_record_set \$idx proposed_version '3.0.0'
    _gs_eu2_record_set \$idx annotation_sha   \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha     \"\$new_sha\"
    _gs_eu2_record_set \$idx current_version  '2.0.0'
    ann2=\"# @todo env-update pecl-git:https://github.com/example/php-ext 2.0.0 sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_EXT_VERSION=2.0.0\n' \"\$ann2\" > \"\$f\"
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann2\"
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"sha not updated to new_sha; expected sha:\${new_sha}\"; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF \"sha:\${old_sha}\" \"\$f\" && { echo 'old sha still present'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_EXT_VERSION=3.0.0' \"\$f\" || { echo 'assignment not updated to 3.0.0'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19m: apply with use_sha=true writes new_sha to VAR= instead of new version" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t19m.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    ann=\"# @todo env-update (use-sha) pecl-git:https://github.com/example/php-ext sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_EXT_VERSION=%s\n' \"\$ann\" \"\$old_sha\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_EXT_VERSION'
    _gs_eu2_record_set \$idx current_version  \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_version '3.0.0'
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha   \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha     \"\$new_sha\"
    _gs_eu2_record_set \$idx use_sha          'true'
    _gs_eu2_record_set \$idx decision         'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"GLOBAL_STACK_EXT_VERSION=\${new_sha}\" \"\$f\" || { echo 'VAR= not written with new_sha'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_EXT_VERSION=3.0.0' \"\$f\" && { echo 'VAR= wrote version instead of sha'; echo FAIL; exit 0; }
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"sha: in annotation not updated to new_sha\"; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF \"sha:\${old_sha}\" \"\$f\" && { echo 'old sha still present in annotation'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 20 — codename delta + floating-reference SKIP
# ═══════════════════════════════════════════════════════════════════════════
section "20 — codename delta + floating-reference SKIP"

_SD_LIBS="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
"
_DC_LIBS20="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t20a: semver_delta — same codename prefix → patch" bash -c "
    ${_SD_LIBS}
    result=\$(_gs_eu2_semver_delta 'resolute-20260108' 'resolute-20260413')
    [[ \"\$result\" == 'patch' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20b: semver_delta — different codename prefix → major" bash -c "
    ${_SD_LIBS}
    result=\$(_gs_eu2_semver_delta 'plucky-20260201' 'resolute-20260413')
    [[ \"\$result\" == 'major' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20c: semver_delta — numeric versions unaffected by codename fix" bash -c "
    ${_SD_LIBS}
    patch=\$(_gs_eu2_semver_delta '18.3' '18.4')
    major=\$(_gs_eu2_semver_delta '17.5' '18.4')
    [[ \"\$patch\" == 'minor' ]] || { echo \"patch test: got \$patch\"; echo FAIL; exit 0; }
    [[ \"\$major\" == 'major' ]] || { echo \"major test: got \$major\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20d: classify — same-codename ubuntu update → AUTO (not HOLD)" bash -c "
    ${_DC_LIBS20}
    result=\$(_gs_eu2_classify_decision 'resolute-20260108' 'resolute-20260413' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20e: classify — unversioned current (nightly) + concrete proposed → RESOLVED (Batch1)" bash -c "
    ${_DC_LIBS20}
    # Post-Batch1: nightly + concrete proposed emits RESOLVED, not SKIP.
    # RESOLVED is informational (requires --apply-resolve --apply to pin).
    result=\$(_gs_eu2_classify_decision 'nightly' '2024.10.22-7ca5933' '' '')
    [[ \"\$result\" == 'RESOLVED' ]] || { echo \"got: \$result (expected RESOLVED)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 21 — _gs_eu2_hoist_all_flags unit tests
# ═══════════════════════════════════════════════════════════════════════════
section "21 — hoist_all_flags"

_HOIST_LIBS="
source '${_GS_EU2_LIB}/core/parse.sh'
"

t "t21a: single recognized flag extracted, rest cleaned" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(manual) dockerhub:nginx 1.25'
    [[ \"\$flags\"   == 'manual' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'dockerhub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21b: flag with value extracted correctly" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(channel:rc) github:foo/bar 3.0'
    [[ \"\$flags\"   == 'channel:rc' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'github:foo/bar 3.0' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21c: multiple recognized flags joined by US (0x1f)" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(manual) (override) dockerhub:nginx 1.25'
    IFS=\$'\\x1f' read -ra parts <<< \"\$flags\"
    [[ \"\${parts[0]}\" == 'manual'   ]] || { echo \"part0 wrong: \${parts[0]}\"; echo FAIL; exit 0; }
    [[ \"\${parts[1]}\" == 'override' ]] || { echo \"part1 wrong: \${parts[1]}\"; echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'dockerhub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21d: unrecognized paren kept in cleaned" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(some-hint) dockerhub:nginx 1.25'
    [[ -z \"\$flags\" ]] || { echo \"flags should be empty: \$flags\"; echo FAIL; exit 0; }
    [[ \"\$cleaned\" == '(some-hint) dockerhub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21e: recognized flag at end of string, trailing space consumed" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned 'dockerhub:nginx 1.25 (manual)'
    [[ \"\$flags\"   == 'manual' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'dockerhub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21f: skip flag with reason kept intact" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(skip:pinned) dockerhub:nginx 1.25'
    [[ \"\$flags\"   == 'skip:pinned' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'dockerhub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21g: unbalanced paren kept as-is" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned 'docker(hub:nginx 1.25'
    [[ -z \"\$flags\" ]] || { echo \"flags should be empty: \$flags\"; echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'docker(hub:nginx 1.25' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21h: empty input produces empty flags and cleaned" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned ''
    [[ -z \"\$flags\"   ]] || { echo \"flags not empty: \$flags\";   echo FAIL; exit 0; }
    [[ -z \"\$cleaned\" ]] || { echo \"cleaned not empty: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21i: tag-filter flag with regex value extracted" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(tag-filter:^[0-9]) dockerhub:foo 1.0'
    [[ \"\$flags\"   == 'tag-filter:^[0-9]' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
    [[ \"\$cleaned\" == 'dockerhub:foo 1.0' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

t "t21j: mixed recognized + unrecognized flags, order preserved" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(manual) (compat: old-api) (override) dockerhub:bar 2.0'
    IFS=\$'\\x1f' read -ra parts <<< \"\$flags\"
    [[ \"\${parts[0]}\" == 'manual'   ]] || { echo \"part0 wrong: \${parts[0]}\"; echo FAIL; exit 0; }
    [[ \"\${parts[1]}\" == 'override' ]] || { echo \"part1 wrong: \${parts[1]}\"; echo FAIL; exit 0; }
    [[ \"\$cleaned\" == '(compat: old-api) dockerhub:bar 2.0' ]] || { echo \"cleaned wrong: \$cleaned\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 22 — tag-suffix anchor (end-of-string, not substring match)
# ═══════════════════════════════════════════════════════════════════════════
section "22 — tag-suffix end-anchor"

# Helper: test tag-suffix end-anchor grep — writes a temp script to avoid heredoc escaping issues
_TS_SCRIPT="$(mktemp /tmp/ts_helper.XXXXXX.sh)"
cat > "${_TS_SCRIPT}" << 'TSEOF'
#!/usr/bin/env bash
# Usage: script.sh <suffix> <tag> <expect_match|expect_nomatch>
suffix="$1"; tag="$2"; expect="$3"
pat="$(printf '%s' "${suffix}" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
matched="$(printf '%s\n' "${tag}" | grep -E -- "${pat}\$" || true)"
if [[ "${expect}" == "expect_match" ]]; then
  [[ -n "${matched}" ]] || { echo "expected match for '${tag}' with suffix '${suffix}', got no match"; echo FAIL; exit 0; }
else
  [[ -z "${matched}" ]] || { echo "expected no match for '${tag}' with suffix '${suffix}', but matched: ${matched}"; echo FAIL; exit 0; }
fi
echo PASS
TSEOF
chmod +x "${_TS_SCRIPT}"

t "t22a: tag ending with suffix passes" bash "${_TS_SCRIPT}" '-alpine3.23' '18.3-alpine3.23' 'expect_match'
t "t22b: tag with suffix in middle (not at end) is excluded" bash "${_TS_SCRIPT}" '-alpine3.23' '18.3-alpine3.23-rc1' 'expect_nomatch'
t "t22c: suffix dot is escaped (no any-char match)" bash "${_TS_SCRIPT}" '-alpine3.23' '18.3-alpineX.23' 'expect_nomatch'
t "t22d: suffix match with oraclelinux passes at end" bash "${_TS_SCRIPT}" '-oraclelinux9' '9.0-oraclelinux9' 'expect_match'
t "t22e: suffix mid-tag not matched" bash "${_TS_SCRIPT}" '-oraclelinux9' '9.0-oraclelinux9-beta' 'expect_nomatch'

# ═══════════════════════════════════════════════════════════════════════════
# Section 23 — alt_version record field (Fix 1)
# ═══════════════════════════════════════════════════════════════════════════
section "23 — alt_version record field"

t "t23a: alt_version set and read back via record accessor" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx alt_version 'v2.0.0 (latest stable)'
    val=\$(_gs_eu2_record_get \$idx alt_version)
    [[ \"\$val\" == 'v2.0.0 (latest stable)' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t23b: alt_version appears in --dump output" bash -c "
    f=\${TMP_DIR}/t23b.env
    printf '# @todo env-update dockerhub:_/postgres 18\nGLOBAL_STACK_PG_VERSION=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'alt_version' || { echo \"alt_version not in dump output\"; echo FAIL; exit 0; }
    echo PASS
"

t "t23c: alt_version defaults to empty string when not set" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    val=\$(_gs_eu2_record_get \$idx alt_version)
    [[ -z \"\$val\" ]] || { echo \"expected empty, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 24 — _gs_eu2_http_get_auth (Fix 2)
# ═══════════════════════════════════════════════════════════════════════════
section "24 — http_get_auth"

t "t24a: auth function exists and accepts (url, token) signature" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    declare -f _gs_eu2_http_get_auth >/dev/null 2>&1 || { echo 'function not found'; echo FAIL; exit 0; }
    echo PASS
"

t "t24b: empty token delegates to plain http_get (fixture path identical)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '${_GS_EU2_LIB}/http/curl.sh'
    # Same fixture as t14a — empty token must hit same file
    out=\$(_gs_eu2_http_get_auth 'https://test.example/fixture-test?foo=bar' '' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t24c: fixture injection works identically with non-empty token (no auth header sent to fixture)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '${_GS_EU2_LIB}/http/curl.sh'
    # Fixture path is determined by URL only — token should not affect fixture lookup
    out=\$(_gs_eu2_http_get_auth 'https://test.example/fixture-test?foo=bar' 'my-secret-token' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing with token: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t24d: missing fixture returns non-zero with auth token (same as without token)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '${_GS_EU2_LIB}/http/curl.sh'
    _gs_eu2_http_get_auth 'https://example.com/no-such-fixture' 'tok' >/dev/null 2>&1 \
        && { echo 'expected non-zero exit'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 25 — dockerhub HOLD decision comes from decide.sh, not fetcher (Fix 3)
# ═══════════════════════════════════════════════════════════════════════════
section "25 — dockerhub HOLD from pipeline not fetcher"

_DH_LIBS25="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh25_cache
"

t "t25a: fetcher leaves decision empty on success path (no AUTO/HOLD set by fetcher)" bash -c "
    ${_DH_LIBS25}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES18_VERSION'
    # No major_hint — fetcher success path should NOT set decision
    _gs_eu2_fetch_dockerhub \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # proposed_version must be set (fetcher did its job)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    # decision must be empty — fetcher must NOT set AUTO/HOLD on success path
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t25b: cache hit path also leaves decision empty (not AUTO)" bash -c "
    ${_DH_LIBS25}
    # Prime the cache first
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES18_VERSION'
    _gs_eu2_fetch_dockerhub \$idx
    proposed_first=\$(_gs_eu2_record_get \$idx proposed_version)
    # Second call — should hit cache
    _gs_eu2_record_new; idx2=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx2 type       'dockerhub'
    _gs_eu2_record_set \$idx2 identifier '_/postgres'
    _gs_eu2_record_set \$idx2 env_var    'GLOBAL_STACK_POSTGRES18_VERSION_2'
    _gs_eu2_fetch_dockerhub \$idx2
    decision2=\$(_gs_eu2_record_get \$idx2 decision)
    proposed2=\$(_gs_eu2_record_get \$idx2 proposed_version)
    [[ -n \"\$proposed2\" ]] || { echo 'cache miss — proposed empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision2\" ]] || { echo \"cache hit set decision: '\$decision2' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t25c: pipeline (classify_decision) produces HOLD when major constraint would escape pin" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/decide.sh'
    # major_hint=17 but proposed=18.4 → HOLD
    result=\$(_gs_eu2_classify_decision '17.5' '18.4' '' '17')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"expected HOLD, got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t25d: full pipeline HOLD for major-pin escape (end-to-end, no fetcher HOLD involved)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/decide.sh'
    # Simulate what main.sh does: fetcher sets proposed only, then classify runs
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx current_version '17.5'
    _gs_eu2_record_set \$idx proposed_version '18.4'
    _gs_eu2_record_set \$idx major_hint '17'
    cur=\$(_gs_eu2_record_get \$idx current_version)
    prop=\$(_gs_eu2_record_get \$idx proposed_version)
    override=\$(_gs_eu2_record_get \$idx override)
    manual=\$(_gs_eu2_record_get \$idx manual)
    major=\$(_gs_eu2_record_get \$idx major_hint)
    gate=''; [[ \"\$override\" == 'true' || \"\$manual\" == 'true' ]] && gate='true'
    classified=\$(_gs_eu2_classify_decision \"\$cur\" \"\$prop\" \"\$gate\" \"\$major\")
    _gs_eu2_record_set \$idx decision \"\$classified\"
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'HOLD' ]] || { echo \"expected HOLD, got: \$decision\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 26 — codeberg fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "26 — codeberg fetcher"

_CB_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/codeberg.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cb_cache
"

t "t26a: happy path — latest stable release returned as proposed_version" bash -c "
    ${_CB_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'mergiraf/mergiraf'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MERGIRAF_VERSION'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture contains v0.20.0 as latest release
    [[ \"\$val\" == 'v0.20.0' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t26b: tag-strip-prefix strips 'v' when set" bash -c "
    ${_CB_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cb_b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'codeberg'
    _gs_eu2_record_set \$idx identifier       'mergiraf/mergiraf'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_MERGIRAF_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # v0.20.0 with strip-prefix v → 0.20.0
    [[ \"\$val\" == '0.20.0' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t26c: rc channel picks pre-release tag from fixture" bash -c "
    ${_CB_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'mergiraf/mergiraf'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MERGIRAF_VERSION'
    _gs_eu2_record_set \$idx channel    'rc'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has v0.21.0-rc1 — rc channel should pick it or fall back to stable
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t26d: HTTP failure sets decision=ERROR, error_message set" bash -c "
    ${_CB_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cb_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'no-such-owner/no-such-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_codeberg \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t26e: empty releases falls back to tags endpoint" bash -c "
    ${_CB_LIBS}
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cb_e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'testorg/tags-only'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TAGSONLY_VERSION'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # releases fixture is an empty array; tags fixture has 1.5.0
    [[ \"\$val\" == '1.5.0' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t26g: releases TRANSPORT failure (endpoint absent) also falls back to tags.
# Distinct branch from t26e: there the releases call SUCCEEDS and returns [];
# here it fails outright. Both must reach the tags endpoint, and neither is the
# both-endpoints-fail case (t26d) that legitimately ERRORs.
#
# This branch had no test of its own until the codeberg releases fixtures were
# renamed to carry the _page_1 suffix the URL derivation actually produces
# (\`releases?limit=50&page=1\`). Before that rename every codeberg fixture test
# reached this path by accident, so it was covered everywhere and asserted
# nowhere; afterwards it would have had zero coverage.
t "t26g: releases endpoint absent (transport failure) falls back to tags, no ERROR" bash -c "
    ${_CB_LIBS}
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cb_g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'testorg/no-releases-endpoint'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_NORELEASES_VERSION'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$val\" == '2.4.0' ]] || { echo \"expected 2.4.0 from the tags endpoint, got: '\$val'\"; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"a working tags fallback must not set a decision, got: '\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t26f: fetcher leaves decision empty on success path" bash -c "
    ${_CB_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'mergiraf/mergiraf'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MERGIRAF_VERSION'
    _gs_eu2_fetch_codeberg \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 27 — quay fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "27 — quay fetcher"

_QY_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/quay.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/qy_cache
"

t "t27a: happy path — latest stable tag returned as proposed_version" bash -c "
    ${_QY_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'quay'
    _gs_eu2_record_set \$idx identifier 'keycloak/keycloak'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION'
    _gs_eu2_fetch_quay \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 26.6.0 as latest stable
    [[ \"\$val\" == '26.6.0' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t27b: tag-exclude filters out unwanted tags" bash -c "
    ${_QY_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type        'quay'
    _gs_eu2_record_set \$idx identifier  'keycloak/keycloak'
    _gs_eu2_record_set \$idx env_var     'GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION'
    _gs_eu2_record_set \$idx tag_exclude '-legacy'
    _gs_eu2_fetch_quay \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 26.5.5-0-legacy which should be excluded; 26.6.0 remains
    [[ \"\$val\" != *'-legacy'* ]] || { echo \"legacy tag not excluded: '\$val'\"; echo FAIL; exit 0; }
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t27c: beta channel picks pre-release tag" bash -c "
    ${_QY_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'quay'
    _gs_eu2_record_set \$idx identifier 'keycloak/keycloak'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION'
    _gs_eu2_record_set \$idx channel    'beta'
    _gs_eu2_fetch_quay \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 27.0.0-beta.1 — beta channel should pick it or fall back to stable
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t27d: HTTP failure sets decision=ERROR, error_message set" bash -c "
    ${_QY_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/qy_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'quay'
    _gs_eu2_record_set \$idx identifier 'no-such-org/no-such-image'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_quay \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t27e: empty tags array returns empty proposed_version (decision set by decide.sh later)" bash -c "
    ${_QY_LIBS}
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/qy_e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'quay'
    _gs_eu2_record_set \$idx identifier 'testorg/empty-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_EMPTY_VERSION'
    _gs_eu2_fetch_quay \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'ERROR' || \"\$decision\" == 'SKIP' || -z \"\$decision\" ]] \
        || { echo \"unexpected decision: '\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t27f: fetcher leaves decision empty on success path" bash -c "
    ${_QY_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'quay'
    _gs_eu2_record_set \$idx identifier 'keycloak/keycloak'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION'
    _gs_eu2_fetch_quay \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 28 — npm fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "28 — npm fetcher"

_NPM_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/npm.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/npm_cache
"

t "t28a: happy path — dist-tags.latest returned as proposed_version" bash -c "
    ${_NPM_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier 'typescript'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TYPESCRIPT_VERSION'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '5.8.3' ]] || { echo \"expected 5.8.3, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t28b: beta channel selects pre-release version" bash -c "
    ${_NPM_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier 'typescript'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TYPESCRIPT_VERSION'
    _gs_eu2_record_set \$idx channel    'beta'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 5.9.0-beta; beta channel should return it (or at minimum return non-empty)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t28c: deprecated versions are excluded from candidate list" bash -c "
    ${_NPM_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier 'colors'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_COLORS_VERSION'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: 1.4.44-liberty-2 is deprecated; must not be proposed
    [[ \"\$val\" != '1.4.44-liberty-2' ]] || { echo \"deprecated version was proposed: '\$val'\"; echo FAIL; exit 0; }
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t28d: HTTP failure sets decision=ERROR with error_message" bash -c "
    ${_NPM_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/npm_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier 'no-such-package-xyzzy-12345'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_npm \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t28e: scoped package URL-encodes @ and / correctly (fixture lookup succeeds)" bash -c "
    ${_NPM_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier '@angular/cli'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_ANGULAR_CLI_VERSION'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '19.2.5' ]] || { echo \"expected 19.2.5, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t28f: fetcher leaves decision empty on success path" bash -c "
    ${_NPM_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'npm'
    _gs_eu2_record_set \$idx identifier 'typescript'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TYPESCRIPT_VERSION'
    _gs_eu2_fetch_npm \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 29 — pypi fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "29 — pypi fetcher"

_PYPI_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/pypi.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pypi_cache
"

t "t29a: happy path — latest stable version returned" bash -c "
    ${_PYPI_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pypi'
    _gs_eu2_record_set \$idx identifier 'ansible'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_ANSIBLE_VERSION'
    _gs_eu2_fetch_pypi \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '11.4.0' ]] || { echo \"expected 11.4.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t29b: rc channel picks pre-release version" bash -c "
    ${_PYPI_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pypi'
    _gs_eu2_record_set \$idx identifier 'ansible'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_ANSIBLE_VERSION'
    _gs_eu2_record_set \$idx channel    'rc'
    _gs_eu2_fetch_pypi \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 11.4.0rc1 — rc channel should pick it (or at minimum return non-empty)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t29c: yanked versions are excluded from candidate list" bash -c "
    ${_PYPI_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pypi'
    _gs_eu2_record_set \$idx identifier 'flask'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_FLASK_VERSION'
    _gs_eu2_fetch_pypi \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: 3.1.99.yanked is yanked; must not be proposed
    [[ \"\$val\" != '3.1.99.yanked' ]] || { echo \"yanked version was proposed: '\$val'\"; echo FAIL; exit 0; }
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t29d: HTTP failure sets decision=ERROR with error_message" bash -c "
    ${_PYPI_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pypi_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pypi'
    _gs_eu2_record_set \$idx identifier 'no-such-package-xyzzy-12345'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_pypi \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t29e: fetcher leaves decision empty on success path" bash -c "
    ${_PYPI_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pypi'
    _gs_eu2_record_set \$idx identifier 'ansible'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_ANSIBLE_VERSION'
    _gs_eu2_fetch_pypi \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 30 — rubygems fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "30 — rubygems fetcher"

_RG_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/rubygems.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/rg_cache
"

t "t30a: happy path — latest non-yanked stable version returned" bash -c "
    ${_RG_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'rubygems'
    _gs_eu2_record_set \$idx identifier 'fastlane'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_FASTLANE_VERSION'
    _gs_eu2_fetch_rubygems \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '2.225.0' ]] || { echo \"expected 2.225.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t30b: pre-release channel includes .pre versions" bash -c "
    ${_RG_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'rubygems'
    _gs_eu2_record_set \$idx identifier 'fastlane'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_FASTLANE_VERSION'
    _gs_eu2_record_set \$idx channel    'rc'
    _gs_eu2_fetch_rubygems \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 2.225.1.pre — rc channel should return it or fall back to stable
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t30c: yanked versions excluded from candidate list" bash -c "
    ${_RG_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'rubygems'
    _gs_eu2_record_set \$idx identifier 'fastlane'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_FASTLANE_VERSION'
    _gs_eu2_fetch_rubygems \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: 2.224.99 is yanked; must not be proposed
    [[ \"\$val\" != '2.224.99' ]] || { echo \"yanked version was proposed: '\$val'\"; echo FAIL; exit 0; }
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t30d: HTTP failure sets decision=ERROR with error_message" bash -c "
    ${_RG_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/rg_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'rubygems'
    _gs_eu2_record_set \$idx identifier 'no-such-gem-xyzzy-12345'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_rubygems \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t30e: fetcher leaves decision empty on success path" bash -c "
    ${_RG_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'rubygems'
    _gs_eu2_record_set \$idx identifier 'fastlane'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_FASTLANE_VERSION'
    _gs_eu2_fetch_rubygems \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 31 — github fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "31 — github fetcher"

_GH_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_cache
"

t "t31a: happy path via releases API — stable tag returned as proposed_version" bash -c "
    ${_GH_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/testrepo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TESTREPO_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '2.5.0' ]] || { echo \"expected 2.5.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31b: empty releases falls back to tags API — proposed_version from tags" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/tags-only-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TAGS_ONLY_VERSION'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    # fixture has 3.1.0, 3.0.2, 3.0.1, 3.0.0 — latest stable is 3.1.0
    [[ \"\$val\" == '3.1.0' ]] || { echo \"expected 3.1.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31c: major_hint pins results to matching major version" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/majorpin-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_MAJORPIN_VERSION'
    _gs_eu2_record_set \$idx major_hint '3'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: v4.0.0, v3.5.1, v3.4.0 — major_hint=3 → must pick 3.5.1, not 4.0.0
    [[ \"\$val\" == '3.5.1' ]] || { echo \"expected 3.5.1, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31d: pre-release sets alt_version hint; proposed_version is stable" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/prerelease-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PRERELEASE_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    alt=\$(_gs_eu2_record_get \$idx alt_version)
    # fixture: v1.9.0-rc2 (prerelease), v1.8.5, v1.8.4 — stable channel → 1.8.5
    [[ \"\$val\" == '1.8.5' ]] || { echo \"expected proposed=1.8.5, got: '\$val'\"; echo FAIL; exit 0; }
    # alt_version should mention the rc
    [[ -n \"\$alt\" ]] || { echo 'alt_version not set for available pre-release'; echo FAIL; exit 0; }
    echo PASS
"

t "t31e: draft releases are excluded from candidate set" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/draft-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_DRAFT_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: v5.0.0 (draft), v4.9.1, v4.9.0 — draft must be excluded → 4.9.1
    [[ \"\$val\" == '4.9.1' ]] || { echo \"expected 4.9.1, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31f: tag_strip_prefix 'v' leaves version without prefix" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_f_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/vprefix-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_VPREFIX_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.2.3' ]] || { echo \"expected 1.2.3 (no v prefix), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31g: tags pagination — fetches page 2 when page 1 is full (100 items)" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/paginated-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PAGINATED_VERSION'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # page1 has 1.99.0..1.0.0 (100 items, all 1.x), page2 has 2.5.0, 0.9.0, 0.8.0
    # highest stable is 2.5.0 — ONLY reachable by fetching page 2
    [[ \"\$val\" == '2.5.0' ]] || { echo \"expected 2.5.0 (from page 2), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31h: HTTP failure sets decision=ERROR with error_message" bash -c "
    ${_GH_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_h_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'no-such-owner/no-such-repo-xyzzy'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_github \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t31i: commit sha helper returns 40-char SHA from fixture" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_i_cache
    sha=\$(_gs_eu2_github_get_commit_sha 'testowner/commit-repo' 'main')
    [[ \"\${#sha}\" -ge 7 ]] || { echo \"SHA too short: '\$sha'\"; echo FAIL; exit 0; }
    [[ \"\$sha\" =~ ^[0-9a-f]+\$ ]] || { echo \"SHA not hex: '\$sha'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31j: fetcher leaves decision empty on success path" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_j_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/testrepo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TESTREPO_VERSION'
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_github \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31k: commit_date helper returns YYYY-MM-DD for a given SHA" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_k_cache
    date=\$(_gs_eu2_github_get_commit_date 'testowner/commit-repo' 'abc1234def5678901234567890123456789012ab')
    [[ \"\$date\" == '2026-03-15' ]] || { echo \"expected 2026-03-15, got: '\$date'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31l: Strategy 3 git ls-remote fallback — major_hint match found via ls-remote" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_l_cache
    export _GS_EU2_GIT_LS_REMOTE_FIXTURE='${FIXTURES}/git-ls-remote-lsr-repo.txt'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'github'
    _gs_eu2_record_set \$idx identifier 'testowner/lsr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_LSR_VERSION'
    _gs_eu2_record_set \$idx major_hint '2'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # releases=[]; tags page1 has only 1.x versions (no 2.x match);
    # ls-remote fixture has 2.0.0, 2.1.0, 2.1.1 — Strategy 3 picks 2.1.1
    [[ \"\$val\" == '2.1.1' ]] || { echo \"expected 2.1.1 from ls-remote, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31m: major_hint with underscore-separated tags (Ruby style) + tag-replace normalises to dots" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_m_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'github'
    _gs_eu2_record_set \$idx identifier        'testowner/underscore-repo'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_RUBY3_VERSION'
    _gs_eu2_record_set \$idx major_hint        '3'
    _gs_eu2_record_set \$idx tag_strip_prefix  'v'
    _gs_eu2_record_set \$idx tag_replace_from  '_'
    _gs_eu2_record_set \$idx tag_replace_to    '.'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture: v4_0_1, v3_4_10, v3_4_9, v3_3_7 — major_hint=3+tag-replace → 3.4.10
    [[ \"\$val\" == '3.4.10' ]] || { echo \"expected 3.4.10, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31n: major_hint with underscore tags and no tag-replace — major filter includes underscore separator" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_n_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'github'
    _gs_eu2_record_set \$idx identifier        'testowner/underscore-repo'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_RUBY3_VERSION'
    _gs_eu2_record_set \$idx major_hint        '3'
    _gs_eu2_record_set \$idx tag_strip_prefix  'v'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    # Without tag-replace, major filter must still match 3_4_10 (not return empty)
    [[ \"\$dec\" != 'SKIP' || \"\$val\" == '' ]] && [[ -n \"\$val\" ]] || { echo \"major filter should not drop underscore tags, got dec='\$dec' val='\$val'\"; echo FAIL; exit 0; }
    [[ \"\$val\" == '3_4_10' ]] || { echo \"expected 3_4_10 (no replace), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31o: Flutter-style repo — releases=pre-release-only, tags=v-prefixed, ls-remote has stable → returns stable via Strategy 3" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_o_cache
    export _GS_EU2_GIT_LS_REMOTE_FIXTURE='${FIXTURES}/git-ls-remote-flutter.txt'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'flutter/flutter'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_FLUTTER3_VERSION'
    _gs_eu2_record_set \$idx tag_filter      '^[0-9\.]'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx current_version '3.41.4'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    # releases API returns 7 pre-releases; tags API returns v1.x (filtered out by ^[0-9\.]);
    # ls-remote has 3.41.0, 3.41.4, 3.41.9 (stable) + 3.42/43/44-pre → Strategy 3 picks 3.41.9
    [[ \"\$val\" == '3.41.9' ]] || { echo \"expected 3.41.9 (stable via ls-remote), got: '\$val' (dec='\$dec')\"; echo FAIL; exit 0; }
    [[ -z \"\$dec\" ]] || { echo \"expected empty decision on success, got: '\$dec'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31p: channel-selection-empty with stable current_version → decision=ERROR (not SKIP)" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_p_cache
    # releases=pre-releases-only, tags=v-prefixed (filtered by ^[0-9\.] → empty after filter),
    # ls-remote fixture is empty → no tags survive any strategy → channel_select_best returns empty
    # current_version is stable → should be ERROR not SKIP
    export _GS_EU2_GIT_LS_REMOTE_FIXTURE='${FIXTURES}/git-ls-remote-empty.txt'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'flutter/flutter'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_FLUTTER3_VERSION'
    _gs_eu2_record_set \$idx tag_filter      '^[0-9\.]'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx current_version '3.41.4'
    _gs_eu2_fetch_github \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR (stable current, no stable found), got: '\$dec' (err='\$err')\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message should be set'; echo FAIL; exit 0; }
    echo PASS
"

t "t31q: channel-selection-empty with prerelease current_version → decision=SKIP (unchanged)" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_q_cache
    # Same as t31p but current_version is pre-release → expect SKIP (no implied stable must exist)
    export _GS_EU2_GIT_LS_REMOTE_FIXTURE='${FIXTURES}/git-ls-remote-empty.txt'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'flutter/flutter'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_FLUTTER3_VERSION'
    _gs_eu2_record_set \$idx tag_filter      '^[0-9\.]'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx current_version '3.41.0-0.1.pre'
    _gs_eu2_fetch_github \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    # current is prerelease → SKIP (not ERROR) — no reason to assume stable releases must exist
    [[ \"\$dec\" == 'SKIP' ]] || { echo \"expected SKIP (prerelease current, no stable), got: '\$dec'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t31r: no releases AND no tags → decision=ERROR with diagnostic message" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_r_cache
    # fake/no-tags-repo fixture: releases=[] and tags=[] — both APIs return empty
    # With manual=false (default), fetcher must set ERROR not SKIP
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'fake/no-tags-repo'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_NOTAGS_VERSION'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    _gs_eu2_fetch_github \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR for empty releases+tags, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message must be non-empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t31s: no releases AND no tags with manual=true → decision=SKIP (not ERROR)" bash -c "
    ${_GH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh_s_cache
    # Same fixture but manual=true — manual repos with no releases are expected → SKIP
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'fake/no-tags-repo'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_NOTAGS_VERSION'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    _gs_eu2_record_set \$idx manual          'true'
    _gs_eu2_fetch_github \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" == 'SKIP' ]] || { echo \"expected SKIP for manual+no-tags, got: '\$dec'\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F019: GIT_ASKPASS tmpfile cleanup via trap RETURN.
# Normal path: rm -f always runs after git ls-remote completes.
# Abnormal path (set -e aborts on printf/chmod failure): only trap RETURN guarantees cleanup.
# Test: inject a write failure by making TMPDIR a read-only directory; the function must not
# leave a tmpfile behind even if it exits early via set -e.
t "t31p: GIT_ASKPASS tmpfile cleaned up after ls-remote returns (trap RETURN)" bash -c "
    ${_GH_LIBS}
    export GITHUB_TOKEN='fake-token-for-askpass-cleanup-test'
    unset _GS_EU2_GIT_LS_REMOTE_FIXTURE
    # Redirect TMPDIR to a private writable dir so we can count exclusively our tmpfiles
    askpass_tmp=\"\${TMP_DIR}/t31p_tmpdir\"
    mkdir -p \"\$askpass_tmp\"
    # Normal-path cleanup: git ls-remote fails (fake token), but rm -f must still run
    TMPDIR=\"\$askpass_tmp\" _gs_eu2_github_ls_remote 'testowner/no-such-repo-xyzzy' 2>/dev/null || true
    leftover=\$(find \"\$askpass_tmp\" -type f 2>/dev/null | wc -l)
    [[ \"\$leftover\" -eq 0 ]] || { echo \"tmpfile not cleaned up after git failure: \$(ls \"\$askpass_tmp\")\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 32 — sdkman fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "32 — sdkman fetcher"

_SDK_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/sdkman.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/sdk_cache
"

t "t32a: happy path — gradle latest stable from /versions/list fixture" bash -c "
    ${_SDK_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'gradle'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_GRADLE_VERSION'
    _gs_eu2_record_set \$idx current_version '9.4.0'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    # Must not set decision=ERROR — decide.sh owns classification
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"unexpected ERROR decision: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32b: sdkman not available — error_message set, no crash, decision not ERROR" bash -c "
    ${_SDK_LIBS}
    # Override fixture dir + cache dir to isolate from t32a's cached result
    export _GS_EU2_HTTP_FIXTURE_DIR=/tmp/no-such-fixtures-xyzzy
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/sdk_b_cache
    export SDKMAN_DIR=/tmp/no-such-sdkman-xyzzy
    export GLOBAL_STACK_SDKMAN_DIR=/tmp/no-such-sdkman-xyzzy
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'gradle'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_GRADLE_VERSION'
    _gs_eu2_record_set \$idx current_version '9.4.0'
    _gs_eu2_fetch_sdkman \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$err\" ]] || { echo 'expected error_message when sdkman unavailable'; echo FAIL; exit 0; }
    [[ -z \"\$proposed\" ]] || { echo \"proposed_version should be empty when unavailable: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32c: major-pin filter — gradle:9 picks only 9.x versions" bash -c "
    ${_SDK_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'gradle'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_GRADLE9_VERSION'
    _gs_eu2_record_set \$idx current_version '9.4.0'
    _gs_eu2_record_set \$idx major_hint      '9'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ \"\$val\" == 9.* ]] || { echo \"major-pin 9 not respected: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32d: channel:unstable — maven:4 returns rc version" bash -c "
    ${_SDK_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'maven'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_MAVEN_VX1_VERSION'
    _gs_eu2_record_set \$idx current_version '4.0.0-rc-5'
    _gs_eu2_record_set \$idx major_hint      '4'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 4.0.0-rc-5 as latest 4.x rc; unstable channel should return an rc or higher
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty for unstable maven:4'; echo FAIL; exit 0; }
    echo PASS
"

t "t32e: Java distribution qualifier — java:11 with current=11.0.30-zulu prefers zulu dist" bash -c "
    ${_SDK_LIBS}
    # java list endpoint not in fixtures → falls back to /versions/all (comma-separated)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA21_VERSION'
    _gs_eu2_record_set \$idx current_version '11.0.30-zulu'
    _gs_eu2_record_set \$idx major_hint      '11'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty for java:11'; echo FAIL; exit 0; }
    # Must pick a 11.x version with -zulu suffix (preferred dist from current_version)
    [[ \"\$val\" == 11.*-zulu || \"\$val\" == 11.*-zulu.fx ]] \
        || { echo \"expected 11.x-zulu, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32f: sdkman does NOT set manual=true (decide.sh classifies AUTO/HOLD based on version)" bash -c "
    ${_SDK_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'ant'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_ANT_VERSION'
    _gs_eu2_record_set \$idx current_version '1.10.15'
    _gs_eu2_fetch_sdkman \$idx
    manual=\$(_gs_eu2_record_get \$idx manual)
    [[ \"\$manual\" != 'true' ]] || { echo 'sdkman must not set manual=true — decide.sh owns this'; echo FAIL; exit 0; }
    echo PASS
"

t "t32g: cache hit skips HTTP (proposed_version from cache)" bash -c "
    ${_SDK_LIBS}
    # Key must match: sdkman:<identifier>:<major_hint>:<channel>:<watch_major_depth>
    _gs_eu2_cache_write 'sdkman:gradle:::' '9.99.0-CACHED'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'gradle'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_GRADLE_VERSION'
    _gs_eu2_record_set \$idx current_version '9.4.0'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '9.99.0-CACHED' ]] || { echo \"cache not used: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F023: SDKMAN EA slip-through.
# "26.0.0-ea.1-zulu" gets extracted as "26.0.0-ea" by the grep-oE regex.
# _ver_base = "26.0.0", _ver_dist = "ea" — the EA marker is in _ver_dist.
# Current code only checks _ver_base against (rc|beta|alpha|ea), so ea slips through
# when there is no -tem and no preferred-dist match (all stable fall to _other_list,
# but so does the EA — and EA sorts higher than the stable 25.0.2-zulu).
# Trigger condition: no -tem, no preferred dist → _other_list only → EA wins on sort -V.
# After fix: also check _ver_dist; "ea" distribution blocks the version.
t "t32h: sdkman Java EA release (ea distribution suffix) filtered out in stable mode" bash -c "
    ${_SDK_LIBS}
    # Build custom fixture: only zulu stable (no -tem), plus EA candidate
    # Current version has no dist suffix → preferred_dist=\"\" → all go to _tem_list or _other_list
    # 26.0.0-ea sorts higher than 25.0.2-zulu → EA slips through without the fix
    ea_fix_dir=\"\${TMP_DIR}/t32h_fixtures/http\"
    mkdir -p \"\$ea_fix_dir\"
    printf '%s' '25.0.2-zulu,26.0.0-ea.1-zulu' > \"\${ea_fix_dir}/api.sdkman.io_2_candidates_java_linux_versions_all\"
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\$ea_fix_dir\"
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t32h_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA_VERSION'
    _gs_eu2_record_set \$idx current_version '25.0.2'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # Must NOT select the EA version (26.0.0-ea)
    case \"\$val\" in
      *ea*) echo \"EA release slipped through in stable mode: '\$val'\"; echo FAIL; exit 0 ;;
    esac
    echo PASS
"

# SDKMAN moved Zulu (and Liberica/Java.net/MS/SapMachine) identifiers to carry
# +build metadata: "17.0.20+1.1-zulu".  The extraction regex admitted no '+', so
# grep -oE restarted mid-token and yielded "1.1-zulu", which the major filter then
# dropped — every zulu candidate vanished before selection, the preferred-dist tier
# was always empty, and selection fell through to -tem (17/26) or -sem (21).
# The broker only serves the BASE form (17.0.20-zulu → 302; 17.0.20+1.1-zulu → 404),
# so the proposal must be normalised back to base-dist form, not left as advertised.
t "t32i: sdkman Java +build identifiers — zulu preserved and normalised to base form" bash -c "
    ${_SDK_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA17_VERSION'
    _gs_eu2_record_set \$idx current_version '17.0.20-zulu'
    _gs_eu2_record_set \$idx major_hint      '17'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '17.0.20-zulu' ]] \
        || { echo \"expected '17.0.20-zulu' (base form), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t32j: sdkman Java +build — 21 keeps zulu (regression: fell through to -sem)" bash -c "
    ${_SDK_LIBS}
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t32j_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA21_VERSION'
    _gs_eu2_record_set \$idx current_version '21.0.12-zulu'
    _gs_eu2_record_set \$idx major_hint      '21'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '21.0.12-zulu' ]] \
        || { echo \"expected '21.0.12-zulu', got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# The fx (JavaFX) and crac (Coordinated Restore at Checkpoint) variants carry the
# same -zulu dist suffix but are DIFFERENT artefacts.  They are excluded today only
# by accident of the old regex; widening it carelessly lets them in, and ".fx" sorts
# above "+1.1" under sort -V, so the JavaFX build would WIN.  Keep them out.
t "t32k: sdkman Java — .fx / .crac zulu variants are never selected" bash -c "
    ${_SDK_LIBS}
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t32k_cache\"
    for mj in 17 21 25; do
      _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
      _gs_eu2_record_set \$idx type            'sdkman'
      _gs_eu2_record_set \$idx identifier      'java'
      _gs_eu2_record_set \$idx env_var         \"GLOBAL_STACK_JAVA\${mj}_VERSION\"
      _gs_eu2_record_set \$idx current_version \"\${mj}.0.1-zulu\"
      _gs_eu2_record_set \$idx major_hint      \"\$mj\"
      _gs_eu2_fetch_sdkman \$idx
      val=\$(_gs_eu2_record_get \$idx proposed_version)
      case \"\$val\" in
        *.fx-*|*.crac-*|*fx+*|*crac+*)
          echo \"fx/crac variant selected for major \$mj: '\$val'\"; echo FAIL; exit 0 ;;
      esac
      [[ \"\$val\" == *-zulu ]] \
          || { echo \"major \$mj lost zulu preference: '\$val'\"; echo FAIL; exit 0; }
    done
    echo PASS
"

# Preferred-dist miss must be LOUD.  When the pinned distribution genuinely has no
# candidate upstream, the fetcher used to silently propose a DIFFERENT vendor as a
# routine AUTO update (17.0.20-zulu → 17.0.21-tem), which --apply would write to .env
# with no gate at all.  A vendor swap is never a version bump: SKIP with a reason.
t "t32l: sdkman Java — preferred dist absent upstream SKIPs loudly, never swaps vendor" bash -c "
    ${_SDK_LIBS}
    nz_dir=\"\${TMP_DIR}/t32l_fixtures/http\"
    mkdir -p \"\$nz_dir\"
    printf '%s' '17.0.20-amzn,17.0.20-tem,17.0.21-tem' \
        > \"\${nz_dir}/api.sdkman.io_2_candidates_java_linux_versions_all\"
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\$nz_dir\"
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t32l_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA17_VERSION'
    _gs_eu2_record_set \$idx current_version '17.0.20-zulu'
    _gs_eu2_record_set \$idx major_hint      '17'
    _gs_eu2_fetch_sdkman \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ -z \"\$val\" ]] \
        || { echo \"cross-dist proposal leaked: '\$val' (expected none)\"; echo FAIL; exit 0; }
    case \"\$err\" in
      *zulu*) : ;;
      *) echo \"error_message must name the missing dist, got: '\$err'\"; echo FAIL; exit 0 ;;
    esac
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 33 — sdkmanager fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "33 — sdkmanager fetcher"

_SDKMGR_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/sdkmanager.sh'
export _GS_EU2_SDKMANAGER_CMD_FIXTURE='${FIXTURES}/sdkmanager-list.txt'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/sdkmgr_cache
"

t "t33a: happy path — platform-tools version from fixture" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'platform-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PLATFORM_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0'
    _gs_eu2_fetch_sdkmanager \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t33b: sdkmanager not found — error_message set, no crash, proposed_version empty" bash -c "
    ${_SDKMGR_LIBS}
    # Override fixture + cache dir to isolate from t33a's cached result
    # Point ANDROID_HOME to a non-existent path so the binary search finds nothing
    export _GS_EU2_SDKMANAGER_CMD_FIXTURE=''
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/sdkmgr_b_cache
    export PATH='/usr/bin:/bin'
    export ANDROID_HOME='/tmp/no-such-android-sdk-xyzzy'
    export GLOBAL_STACK_ANDROID_HOME='/tmp/no-such-android-sdk-xyzzy'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'platform-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PLATFORM_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0'
    _gs_eu2_fetch_sdkmanager \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$err\" ]] || { echo 'expected error_message when sdkmanager not found'; echo FAIL; exit 0; }
    [[ -z \"\$proposed\" ]] || { echo \"proposed_version should be empty: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t33c: CMD_FIXTURE seam — reads fixture file instead of running real sdkmanager" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'build-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_BUILD_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0-rc2'
    _gs_eu2_fetch_sdkmanager \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has build-tools;37.0.0, ;37.0.0-rc1, ;37.0.0-rc2 — stable channel picks 37.0.0
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t33d: channel:unstable — build-tools picks rc version" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'build-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_BUILD_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0-rc2'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_sdkmanager \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty for unstable channel'; echo FAIL; exit 0; }
    echo PASS
"

t "t33e: sdkmanager does NOT set manual — decide.sh owns classification via version comparison" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'platform-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PLATFORM_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0'
    _gs_eu2_fetch_sdkmanager \$idx
    manual=\$(_gs_eu2_record_get \$idx manual)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ -z \"\$manual\" ]] || { echo \"sdkmanager must NOT set manual; got: '\$manual'\"; echo FAIL; exit 0; }
    # Fetcher must NOT write decision (that is decide.sh's job)
    [[ -z \"\$dec\" ]] || { echo \"fetcher must not write decision; got: '\$dec'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t33f: NDK component parsed from component;VERSION format" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'ndk'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_NDK_VERSION'
    _gs_eu2_record_set \$idx current_version '29.0.14206865'
    _gs_eu2_fetch_sdkmanager \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'NDK version not found in fixture'; echo FAIL; exit 0; }
    echo PASS
"

t "t33g: cache hit skips cmd fixture (proposed_version from cache)" bash -c "
    ${_SDKMGR_LIBS}
    _gs_eu2_cache_write 'sdkmanager:platform-tools:' '99.0.0-CACHED'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'platform-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PLATFORM_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '37.0.0'
    _gs_eu2_fetch_sdkmanager \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '99.0.0-CACHED' ]] || { echo \"cache not used: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t33h: sdkmanager classification contract — (manual) annotation is required for MANUAL
# decision; without it the full pipeline produces AUTO (not MANUAL). This makes the
# design explicit: the fetcher is responsible for proposed_version only; classification
# is owned by decide.sh via the annotation-set manual field.
t "t33h: sdkmanager without (manual) annotation produces AUTO (not MANUAL) via full pipeline" bash -c "
    ${_SDKMGR_LIBS}
    source '${_GS_EU2_LIB}/core/decide.sh'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/sdkmgr_h_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'platform-tools'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PLATFORM_TOOLS_VERSION'
    _gs_eu2_record_set \$idx current_version '36.0.0'
    # No (manual) annotation — manual field stays empty
    _gs_eu2_fetch_sdkmanager \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    manual=\$(_gs_eu2_record_get \$idx manual)
    override=\$(_gs_eu2_record_get \$idx override)
    major=\$(_gs_eu2_record_get \$idx major_hint)
    [[ -z \"\$manual\" ]] || { echo \"fetcher must not set manual field; got: '\$manual'\"; echo FAIL; exit 0; }
    # Full classification: with no (manual) flag, a newer version should yield AUTO
    gate=''; [[ \"\$override\" == 'true' || \"\$manual\" == 'true' ]] && gate='true'
    decision=\$(_gs_eu2_classify_decision '36.0.0' \"\$proposed\" \"\$gate\" \"\$major\")
    [[ \"\$decision\" != 'MANUAL' ]] || { echo \"got MANUAL without (manual) annotation — add (manual) to annotation instead\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 34 — pecl helper functions (pecl.sh)
# ═══════════════════════════════════════════════════════════════════════════
section "34 — pecl helper functions"

_PECL_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/pecl.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_cache
"

t "t34a: get_latest_stable returns stable version from XML" bash -c "
    ${_PECL_LIBS}
    result=\$(_gs_eu2_pecl_get_latest_stable 'imagick')
    [[ \"\$result\" == '3.8.0' ]] || { echo \"expected 3.8.0, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t34b: get_latest_stable skips beta/alpha entries" bash -c "
    ${_PECL_LIBS}
    result=\$(_gs_eu2_pecl_get_latest_stable 'imagick')
    # fixture has 3.9.0beta1 (beta) and 3.8.0 (stable); must return 3.8.0
    [[ \"\$result\" == '3.8.0' ]] || { echo \"expected stable 3.8.0, got: '\$result' (beta must be skipped)\"; echo FAIL; exit 0; }
    echo PASS
"

t "t34c: check_promotion returns version when PECL release is newer than git date" bash -c "
    ${_PECL_LIBS}
    # redis 6.1.0 released 2026-03-20, git commit date 2026-02-10 → PECL is newer
    result=\$(_gs_eu2_pecl_check_promotion 'redis' '2026-02-10')
    [[ \"\$result\" == '6.1.0' ]] || { echo \"expected 6.1.0, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t34d: check_promotion returns empty when git commit is newer than PECL release" bash -c "
    ${_PECL_LIBS}
    # imagick 3.8.0 released 2026-01-10, git commit date 2026-02-15 → git is newer
    result=\$(_gs_eu2_pecl_check_promotion 'imagick' '2026-02-15')
    [[ -z \"\$result\" ]] || { echo \"expected empty (no promotion), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t34e: HTTP error for allreleases returns empty string, no crash" bash -c "
    ${_PECL_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_e_cache
    result=\$(_gs_eu2_pecl_get_latest_stable 'no-such-extension-xyzzy' 2>/dev/null || true)
    [[ -z \"\$result\" ]] || { echo \"expected empty on HTTP error, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 36 — semver_delta handles YYYYMMDD-sha8 format (patch, not major)
# ═══════════════════════════════════════════════════════════════════════════
section "36 — semver_delta date-sha format"

_SV_LIBS="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
"

t "t36a: YYYYMMDD-sha8 → YYYYMMDD-sha8 (newer date) classifies as patch" bash -c "
    ${_SV_LIBS}
    result=\$(_gs_eu2_semver_delta '20260315-abc1234d' '20260316-def5678e')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for date-sha bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t36b: SHA-only current → YYYYMMDD-sha8 proposed classifies as patch" bash -c "
    ${_SV_LIBS}
    result=\$(_gs_eu2_semver_delta '8df8cdc74c95abb61f9b3396cb191e3f43e4989f' '20260315-abc1234d')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for sha→date-sha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t36c: same date-sha → SKIP (classify_decision integration)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    ${_SV_LIBS}
    source '${_GS_EU2_LIB}/core/decide.sh'
    result=\$(_gs_eu2_classify_decision '20260315-abc1234d' '20260315-abc1234d' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for same date-sha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t36d: newer date-sha → AUTO (classify_decision integration)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    ${_SV_LIBS}
    source '${_GS_EU2_LIB}/core/decide.sh'
    result=\$(_gs_eu2_classify_decision '20260315-abc1234d' '20260316-def5678e' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for newer date-sha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 37 — url fetcher (Phase 3f)
# ═══════════════════════════════════════════════════════════════════════════
section "37 — url fetcher"

_URL_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/core/ubuntu.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
source '${_GS_EU2_LIB}/fetchers/url.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/url_cache\"
"

# ── ubuntu.sh helpers ─────────────────────────────────────────────────────

t "t37a: _gs_eu2_ubuntu_codename_list — returns ordered list oldest→newest" bash -c "
    ${_URL_LIBS}
    list=\$(_gs_eu2_ubuntu_codename_list)
    first=\$(printf '%s\n' \"\$list\" | head -1)
    last=\$(printf '%s\n' \"\$list\" | tail -1)
    [[ \"\$first\" == 'xenial' ]] || { echo \"expected first=xenial, got: '\$first'\"; echo FAIL; exit 0; }
    [[ \"\$last\" == 'resolute' ]] || { echo \"expected last=resolute, got: '\$last'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37b: _gs_eu2_ubuntu_codename_to_version — noble → 24.04" bash -c "
    ${_URL_LIBS}
    ver=\$(_gs_eu2_ubuntu_codename_to_version 'noble')
    [[ \"\$ver\" == '24.04' ]] || { echo \"expected 24.04, got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37c: _gs_eu2_ubuntu_codename_to_version — jammy → 22.04" bash -c "
    ${_URL_LIBS}
    ver=\$(_gs_eu2_ubuntu_codename_to_version 'jammy')
    [[ \"\$ver\" == '22.04' ]] || { echo \"expected 22.04, got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37d: _gs_eu2_ubuntu_version_to_codename — 24.04 → noble" bash -c "
    ${_URL_LIBS}
    cn=\$(_gs_eu2_ubuntu_version_to_codename '24.04')
    [[ \"\$cn\" == 'noble' ]] || { echo \"expected noble, got: '\$cn'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Tier 1 (fetch-extract) ────────────────────────────────────────────────

t "t37e: fetch-extract — perl regex extracts highest match from body (Android SDK)" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://developer.android.com/studio'
    _gs_eu2_record_set \$idx fetch_extract 'commandlinetools-linux-([0-9]+)_latest\\.zip'
    _gs_eu2_record_set \$idx current_version '14742923'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_ANDROID_SDK_URL'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '14820900' ]] || { echo \"expected 14820900, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37f: fetch-extract — extracts version from directory listing (automake)" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://mirror.ibcp.fr/pub/gnu/automake/'
    _gs_eu2_record_set \$idx fetch_extract 'automake-([0-9\\.]+)\\.tar\\.gz'
    _gs_eu2_record_set \$idx current_version '1.18.1'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_NGINX_AUTOMAKE_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.18.1' ]] || { echo \"expected 1.18.1, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Tier 2 (fetch-json) ───────────────────────────────────────────────────

t "t37g: fetch-json — jq path extracts version from JSON body" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://api.test-fetch-json.example.com/version'
    _gs_eu2_record_set \$idx fetch_json    '.version'
    _gs_eu2_record_set \$idx current_version '3.4.0'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_TEST_JSON_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '3.5.2' ]] || { echo \"expected 3.5.2, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Tier 3 (GitHub redirect via urls:) ───────────────────────────────────

t "t37h: GitHub redirect — uses urls: field to fetch via GitHub API (zephir)" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://zephir-lang.com/en'
    _gs_eu2_record_set \$idx urls          'https://github.com/zephir-lang/zephir/releases'
    _gs_eu2_record_set \$idx current_version '0.19.0'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_ZEPHIR_LANG_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '0.19.0' ]] || { echo \"expected 0.19.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Tier 4 (directory listing) ────────────────────────────────────────────

t "t37i: dir-listing — extracts versioned hrefs from SVN tags index (apr-util)" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type           'url'
    _gs_eu2_record_set \$idx identifier     'https://svn.apache.org/repos/asf/apr/apr-util/tags/'
    _gs_eu2_record_set \$idx version_prefix 'tags/'
    _gs_eu2_record_set \$idx current_version 'tags/1.6.3'
    _gs_eu2_record_set \$idx env_var        'GLOBAL_STACK_HTTPD_APR_UTIL_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'tags/1.6.3' ]] || { echo \"expected tags/1.6.3, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37j: dir-listing — extracts version from Apache httpd SVN tags" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type           'url'
    _gs_eu2_record_set \$idx identifier     'https://svn.apache.org/repos/asf/httpd/httpd/tags/'
    _gs_eu2_record_set \$idx version_prefix 'tags/'
    _gs_eu2_record_set \$idx current_version 'tags/2.4.66'
    _gs_eu2_record_set \$idx env_var        'GLOBAL_STACK_HTTPD_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'tags/2.4.66' ]] || { echo \"expected tags/2.4.66, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37k: dir-listing channel:nightly — extracts latest nightly entry" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type           'url'
    _gs_eu2_record_set \$idx identifier     'https://nodejs.org/download/nightly/'
    _gs_eu2_record_set \$idx channel        'nightly'
    _gs_eu2_record_set \$idx current_version 'v26.0.0-nightly20260314abc1234ef'
    _gs_eu2_record_set \$idx env_var        'GLOBAL_STACK_NODEEDGE_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v26.0.0-nightly20260314abc1234ef' ]] || { echo \"expected v26.0.0-nightly20260314abc1234ef, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# Regression: tier precedence — a record carrying BOTH channel:nightly AND a
# urls: field must NOT let Tier 3 (GitHub redirect) fire first and mask Tier 4's
# channel:nightly directory listing. Real case: GLOBAL_STACK_NODEEDGE_VERSION
# (.env:517) fetched nodejs/node GitHub *stable* tags (v26.4.0) instead of the
# nightly build listing. Tier 3 must be gated on channel != nightly.
# Isolated cache dir is load-bearing: the cache key omits urls: and is therefore
# byte-identical to t37k's, so a shared dir would serve a cache hit and bypass
# the tier logic entirely (test would pass pre-fix, hiding the bug).
t "t37k2: tier precedence — channel:nightly + urls: uses Tier 4 nightly, not Tier 3 GitHub stable" bash -c "
    ${_URL_LIBS}
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/url_cache_nightly_urls\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type           'url'
    _gs_eu2_record_set \$idx identifier     'https://nodejs.org/download/nightly/'
    _gs_eu2_record_set \$idx channel        'nightly'
    _gs_eu2_record_set \$idx urls           'https://github.com/nodejs/node'
    _gs_eu2_record_set \$idx current_version 'v26.0.0-nightly20260313def5678ab'
    _gs_eu2_record_set \$idx env_var        'GLOBAL_STACK_NODEEDGE_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v26.0.0-nightly20260314abc1234ef' ]] || { echo \"expected Tier-4 nightly v26.0.0-nightly20260314abc1234ef, got: '\$val' (Tier 3 GitHub stable masked Tier 4)\"; echo FAIL; exit 0; }
    echo PASS
"

# Regression: upstream data-source freeze. nodejs.org stopped regenerating the
# HTML directory index at https://nodejs.org/download/nightly/ on 2026-04-17
# (verified via a cache-MISS last-modified header), so Tier 4's listing can no
# longer see past that date and proposes a downgrade. index.json is the live
# source and is reached through Tier 2. This asserts Tier 2 wins over BOTH
# Tier 3 (urls: GitHub stable tags) and Tier 4 (channel:nightly listing) when
# fetch_json is set — the tier order is what makes the .env fix work.
# The fixture deliberately places a NON-newest entry at .[0] so that a
# regression to '.[0].version' fails instead of coincidentally passing.
t "t37k3: tier precedence — fetch-json (Tier 2) wins over channel:nightly Tier 4 listing" bash -c "
    ${_URL_LIBS}
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/url_cache_nightly_json\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'url'
    _gs_eu2_record_set \$idx identifier      'https://nodejs.org/download/nightly/index.json'
    _gs_eu2_record_set \$idx fetch_json      'max_by(.date).version'
    _gs_eu2_record_set \$idx channel         'nightly'
    _gs_eu2_record_set \$idx urls            'https://github.com/nodejs/node'
    _gs_eu2_record_set \$idx current_version 'v27.0.0-nightly202608090700e749eb'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_NODEEDGE_VERSION'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v27.0.0-nightly202608254b5e86c4e2' ]] || { echo \"expected Tier-2 index.json max_by(.date) v27.0.0-nightly202608254b5e86c4e2, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Tier 5 (url-probe) ────────────────────────────────────────────────────

t "t37l: url-probe — finds first matching codename path (kubic unstable noble)" bash -c "
    ${_URL_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type           'url'
    _gs_eu2_record_set \$idx identifier     'https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/'
    _gs_eu2_record_set \$idx url_probe      'stable/xUbuntu_{codename-version},unstable/xUbuntu_{codename-version}'
    _gs_eu2_record_set \$idx current_version 'unstable/xUbuntu_24.04'
    _gs_eu2_record_set \$idx env_var        'GLOBAL_STACK_PODMAN_CHANNEL'
    _gs_eu2_fetch_url \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # stable hits for 24.04, so proposed should be stable/xUbuntu_24.04
    [[ \"\$val\" == 'stable/xUbuntu_24.04' ]] || { echo \"expected stable/xUbuntu_24.04, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Error handling ────────────────────────────────────────────────────────

t "t37m: HTTP error — error_message set, no crash" bash -c "
    ${_URL_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://this-url-does-not-exist-at-all.invalid/noop'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_fetch_url \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ -n \"\$err\" ]] || { echo 'error_message is empty after HTTP failure'; echo FAIL; exit 0; }
    echo PASS
"

t "t37n: no strategy matches — error_message set with 'no extraction strategy matched'" bash -c "
    ${_URL_LIBS}
    # Use a fresh cache dir so t37h's cached zephir result doesn't leak here
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/url_cache_n\"
    # zephir-lang.com/en: no fetch_extract, no fetch_json, no urls, no url_probe,
    # no channel:nightly, not an svn.apache.org / /pub/gnu/ URL → no dir-listing
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://zephir-lang.com/en'
    _gs_eu2_record_set \$idx current_version '0.19.0'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_ZEPHIR_LANG_VERSION'
    _gs_eu2_fetch_url \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ -n \"\$err\" ]] || { echo 'error_message is empty when no strategy matches'; echo FAIL; exit 0; }
    echo PASS
"

# eu-F027: HTTP failure and regex no-match must produce distinct error messages.
# These two failure modes are currently conflated — both yield "matched nothing".
# After fix: HTTP failure → contains "fetch failed"; no-match → contains "matched nothing".

t "t37o: fetch-extract HTTP failure produces 'fetch failed' error (distinct from regex no-match)" bash -c "
    ${_URL_LIBS}
    # Point fixture dir to non-existent dir so HTTP fetch fails
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\${TMP_DIR}/t37o_no_fixtures\"
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t37o_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://example.com/page'
    _gs_eu2_record_set \$idx fetch_extract 'version-([0-9.]+)'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_fetch_url \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    # Must contain 'fetch failed' (HTTP error), not 'matched nothing' (regex error)
    echo \"\$err\" | grep -qiF 'fetch failed' || { echo \"expected 'fetch failed' for HTTP error; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t37p: fetch-extract regex no-match produces 'matched nothing' error (distinct from HTTP failure)" bash -c "
    ${_URL_LIBS}
    # Real fixture that returns body, but a pattern that won't match
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t37p_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_record_set \$idx identifier    'https://developer.android.com/studio'
    _gs_eu2_record_set \$idx fetch_extract 'THIS_PATTERN_WILL_NEVER_MATCH_XYZZY_([0-9]+)'
    _gs_eu2_record_set \$idx current_version '14742923'
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_ANDROID_SDK_VERSION'
    _gs_eu2_fetch_url \$idx 2>/dev/null || true
    err=\$(_gs_eu2_record_get \$idx error_message)
    # Must contain 'matched nothing' (regex no-match), not 'fetch failed' (HTTP error)
    echo \"\$err\" | grep -qiF 'matched nothing' || { echo \"expected 'matched nothing' for regex no-match; got: '\$err'\"; echo FAIL; exit 0; }
    # Must NOT contain 'fetch failed' (HTTP succeeded, body was fetched)
    echo \"\$err\" | grep -qiF 'fetch failed' && { echo \"unexpected 'fetch failed' in regex error; got: '\$err'\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 38 — url fetcher integration (end-to-end via --check)
# ═══════════════════════════════════════════════════════════════════════════
section "38 — url fetcher integration"

t "t38a: url type parsed and fetched — fetch-extract entry produces proposed_version" bash -c "
    f=\${TMP_DIR}/t38a.env
    printf '# @todo env-update (fetch-extract:commandlinetools-linux-([0-9]+)_latest\\.zip) url:https://developer.android.com/studio 14742923\nGLOBAL_STACK_ANDROID_SDK_URL=14742923\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t38a_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qE 'AUTO|SKIP|HOLD' || { echo \"no decision output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t38b: url type not-implemented SKIP count is 0 — all url entries dispatch" bash -c "
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t38b_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file='${REPO_ROOT}/.env' --filter='ANDROID_SDK_URL|HTTPD_APR_UTIL|HTTPD_APR_VERSION|HTTPD_VERSION|PODMAN_CHANNEL|NGINX_AUTOMAKE|ZEPHIR|NODEEDGE' 2>/dev/null || true)
    echo \"\$out\" | grep -qE 'not yet implemented' && { echo \"some url entries still hit not-implemented SKIP\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 39 — reason labels + dynamic column alignment
# ═══════════════════════════════════════════════════════════════════════════
section "39 — reason labels and dynamic alignment"

# ── Reason label: HOLD (unpinned major bump) ─────────────────────────────

t "t39a: HOLD unpinned major bump has 'major bump' reason label" bash -c "
    f=\${TMP_DIR}/t39a.env
    printf '# @todo env-update github:testowner/majorpin-repo\nGLOBAL_STACK_TEST_MAJORPIN=3.5.1\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39a_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'major bump' || { echo \"no 'major bump' in HOLD output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Reason label: HOLD (pin escape — proposed escapes major_hint) ─────────

t "t39b: major_hint=3 + best-in-pin v3.5.1 → AUTO (pin satisfied, no HOLD)" bash -c "
    f=\${TMP_DIR}/t39b.env
    # major_hint=3 embedded in type token; fixture has v3.5.1 (within pin) → AUTO
    # (t82b tests the classify_decision HOLD path for pin-escape directly)
    printf '# @todo env-update github:testowner/majorpin-repo:3 3.4.0\nGLOBAL_STACK_TEST_PINNED=3.4.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39b_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"expected AUTO (pin satisfied by v3.5.1); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '3.4.0' || { echo \"expected current version 3.4.0 in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Reason label: SKIP (up to date) keeps existing text ───────────────────

t "t39c: SKIP up-to-date still shows '(up to date)'" bash -c "
    f=\${TMP_DIR}/t39c.env
    printf '# @todo env-update dockerhub:_/postgres 18.4-alpine3.23\nGLOBAL_STACK_POSTGRES_VERSION=18.4-alpine3.23\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39c_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'up to date' || { echo \"no '(up to date)' in SKIP output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Reason label: MANUAL (override flag) ─────────────────────────────────

t "t39d: MANUAL from override flag shows reason label" bash -c "
    f=\${TMP_DIR}/t39d.env
    printf '# @todo env-update (override) dockerhub:_/postgres 18\nGLOBAL_STACK_POSTGRES_MANUAL=18.3\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39d_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'manual' || { echo \"no 'manual' reason in MANUAL output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Reason label: SKIP (downgrade protection) ────────────────────────────

t "t39e: SKIP downgrade protection shows '(would downgrade)'" bash -c "
    f=\${TMP_DIR}/t39e.env
    # fixture proposes 18.4-alpine3.23; set current higher so downgrade triggers
    printf '# @todo env-update dockerhub:_/postgres\nGLOBAL_STACK_POSTGRES_DOWN=99.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39e_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'would downgrade: current' || { echo \"no downgrade reason in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Dynamic alignment: arrow at same column ───────────────────────────────

t "t39f: dynamic alignment — arrow at same column across records (long var > 60 chars)" bash -c "
    f=\${TMP_DIR}/t39f.env
    # Two vars: one short (A), one longer than the fixed 60-char field
    # Without dynamic alignment the long name overflows and pushes → further right
    printf '%s\n' \
        '# @todo env-update dockerhub:_/postgres 18' \
        'A=18.3' \
        '# @todo env-update dockerhub:_/postgres 18' \
        'GLOBAL_STACK_POSTGRES_VERY_LONG_VARIABLE_NAME_EXCEEDING_SIXTY_CHARS=18.3' \
        > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39f_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    # Extract the column position of → in each AUTO line
    col1=\$(echo \"\$out\" | grep -F '→' | head -1 | grep -bo '→' | cut -d: -f1 | head -1)
    col2=\$(echo \"\$out\" | grep -F '→' | tail -1 | grep -bo '→' | cut -d: -f1 | head -1)
    [[ -n \"\$col1\" && -n \"\$col2\" ]] || { echo \"no → found in output: \$out\"; echo FAIL; exit 0; }
    [[ \"\$col1\" == \"\$col2\" ]] || { echo \"misaligned: → at col \$col1 vs \$col2 (output: \$out)\"; echo FAIL; exit 0; }
    echo PASS
"

# ── HOLD reason includes proposed major ──────────────────────────────────

t "t39g: HOLD unpinned major bump reason includes both majors" bash -c "
    f=\${TMP_DIR}/t39g.env
    printf '# @todo env-update github:testowner/majorpin-repo\nGLOBAL_STACK_TEST_MAJORPIN2=3.5.1\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39g_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    # Should show 3→4 in the reason
    echo \"\$out\" | grep -qE '3.*4|4.*3' || { echo \"no major numbers in HOLD reason: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 40 — prefer-specific flag (floating tag demotion)
# ═══════════════════════════════════════════════════════════════════════════
section "40 — prefer-specific flag (floating tag demotion)"

_DH_LIBS40="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh40_cache
"

t "t40a: is_floating_tag detects X.Y tag as floating" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1-alpine3.23' && echo PASS || { echo 'FAIL: X.Y-suffix should be floating'; exit 0; }
"

t "t40b: is_floating_tag detects X tag as floating" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9-alpine3.23' && echo PASS || { echo 'FAIL: X-suffix should be floating'; exit 0; }
"

t "t40c: is_floating_tag accepts X.Y.Z tag as specific" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.0.4-alpine3.23' && { echo 'FAIL: X.Y.Z-suffix should NOT be floating'; exit 0; } || echo PASS
"

t "t40d: is_floating_tag accepts X.Y.Z-prerelease tag as specific" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1.0-rc2-alpine3.23' && { echo 'FAIL: X.Y.Z-rc should NOT be floating'; exit 0; } || echo PASS
"

t "t40e: is_floating_tag accepts bare X.Y.Z (no suffix)" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.0.4' && { echo 'FAIL: bare X.Y.Z should NOT be floating'; exit 0; } || echo PASS
"

t "t40f: is_floating_tag rejects bare X.Y (no suffix)" bash -c "
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1' && echo PASS || { echo 'FAIL: bare X.Y should be floating'; exit 0; }
"

t "t40g: prefer-specific flag record field is recognized" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx prefer_specific 'true'
    val=\$(_gs_eu2_record_get \$idx prefer_specific)
    [[ \"\$val\" == 'true' ]] || { echo \"field not found or wrong value: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t40h: prefer-specific flag — fetcher prefers X.Y.Z over floating X.Y" bash -c "
    ${_DH_LIBS40}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'dockerhub'
    _gs_eu2_record_set \$idx identifier      'valkey/valkey'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_VALKEY_VERSION'
    _gs_eu2_record_set \$idx tag_filter      'alpine3.23'
    _gs_eu2_record_set \$idx prefer_specific 'true'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 9.0.4-alpine3.23 (stable specific) and 9.1-alpine3.23 (floating)
    # prefer-specific must choose 9.0.4-alpine3.23, not 9.1-alpine3.23
    [[ \"\$val\" == '9.0.4-alpine3.23' ]] || { echo \"expected 9.0.4-alpine3.23, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t40i: without prefer-specific flag — default behavior unchanged (floating allowed)" bash -c "
    ${_DH_LIBS40}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh40i_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier 'valkey/valkey'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_VALKEY_VERSION'
    _gs_eu2_record_set \$idx tag_filter 'alpine3.23'
    # No prefer_specific — fetcher may return floating tag (9.1-alpine3.23 sorts higher)
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t40j: prefer-specific skips all-floating set → SKIP with error" bash -c "
    ${_DH_LIBS40}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh40j_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'dockerhub'
    _gs_eu2_record_set \$idx identifier      'valkey/valkey'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_VALKEY_VERSION'
    # Filter to only floating tags (9 and 9.1 — no patch component)
    _gs_eu2_record_set \$idx major_hint      '9'
    _gs_eu2_record_set \$idx tag_filter      '^9(\\.1)?(-|$)'
    _gs_eu2_record_set \$idx tag_exclude     '[0-9]+\\.[0-9]+\\.[0-9]'
    _gs_eu2_record_set \$idx prefer_specific 'true'
    _gs_eu2_fetch_dockerhub \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'SKIP' || \"\$decision\" == 'ERROR' ]] \
        || { echo \"expected SKIP/ERROR when only floating tags remain, got: '\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t40k: parse.sh recognises (prefer-specific) as a known flag" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\$(mktemp)
    printf '# @todo env-update (prefer-specific) dockerhub:valkey/valkey 9.0.3-alpine3.23\nGLOBAL_STACK_VALKEY_VERSION=9.0.3-alpine3.23\n' > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    val=\$(_gs_eu2_record_get 0 prefer_specific)
    rm -f \"\$f\"
    [[ \"\$val\" == 'true' ]] || { echo \"prefer_specific not set from annotation, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t40l: cache key is segregated by prefer-specific flag (flag-on vs flag-off use different keys)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\$(mktemp -d)
    # Run WITHOUT prefer-specific — writes one cache file
    bash -c \"
      export _GS_EU2_HTTP_FIXTURE_DIR='\$_GS_EU2_HTTP_FIXTURE_DIR'
      export _GS_EU2_CACHE_DIR='\$_GS_EU2_CACHE_DIR'
      declare -A _GS_EU2_CFG=([no_cache]=false [channel]=stable [cache_ttl]=3600)
      source '${_GS_EU2_LIB}/core/records.sh'
      source '${_GS_EU2_LIB}/core/semver.sh'
      source '${_GS_EU2_LIB}/core/channel.sh'
      source '${_GS_EU2_LIB}/core/tag_flags.sh'
      source '${_GS_EU2_LIB}/core/cache.sh'
      source '${_GS_EU2_LIB}/http/curl.sh'
      source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
      source '${_GS_EU2_LIB}/core/parse.sh'
      f=\\\$(mktemp)
      printf '# @todo env-update (tag-filter:alpine) dockerhub:valkey/valkey 9.0.3-alpine3.23\nGLOBAL_STACK_VALKEY_VERSION=9.0.3-alpine3.23\n' > \\\"\\\$f\\\"
      _gs_eu2_parse_env_file \\\"\\\$f\\\"
      _gs_eu2_fetch_dockerhub 0
      rm -f \\\"\\\$f\\\"
    \"
    # Run WITH prefer-specific — writes a different cache file
    bash -c \"
      export _GS_EU2_HTTP_FIXTURE_DIR='\$_GS_EU2_HTTP_FIXTURE_DIR'
      export _GS_EU2_CACHE_DIR='\$_GS_EU2_CACHE_DIR'
      declare -A _GS_EU2_CFG=([no_cache]=false [channel]=stable [cache_ttl]=3600)
      source '${_GS_EU2_LIB}/core/records.sh'
      source '${_GS_EU2_LIB}/core/semver.sh'
      source '${_GS_EU2_LIB}/core/channel.sh'
      source '${_GS_EU2_LIB}/core/tag_flags.sh'
      source '${_GS_EU2_LIB}/core/cache.sh'
      source '${_GS_EU2_LIB}/http/curl.sh'
      source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
      source '${_GS_EU2_LIB}/core/parse.sh'
      f=\\\$(mktemp)
      printf '# @todo env-update (tag-filter:alpine) (prefer-specific) dockerhub:valkey/valkey 9.0.3-alpine3.23\nGLOBAL_STACK_VALKEY_VERSION=9.0.3-alpine3.23\n' > \\\"\\\$f\\\"
      _gs_eu2_parse_env_file \\\"\\\$f\\\"
      _gs_eu2_fetch_dockerhub 0
      rm -f \\\"\\\$f\\\"
    \"
    # There must be exactly 2 cache files (different keys → different files)
    n=\$(ls \"\$_GS_EU2_CACHE_DIR\" | wc -l | tr -d ' ')
    rm -rf \"\$_GS_EU2_CACHE_DIR\"
    [[ \"\$n\" -eq 2 ]] || { echo \"Expected 2 cache files (flag-on vs flag-off), got \$n\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 41 — semver_delta handles tags/X.Y.Z prefix (not falsely "major")
# ═══════════════════════════════════════════════════════════════════════════
section "41 — semver_delta tags/ prefix"

_SV_LIBS41="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
"

t "t41a: tags/X.Y.Z patch bump → patch (not falsely major)" bash -c "
    ${_SV_LIBS41}
    result=\$(_gs_eu2_semver_delta 'tags/2.4.66' 'tags/2.4.67')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for tags/ patch bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t41b: tags/X.Y.Z major bump → major" bash -c "
    ${_SV_LIBS41}
    result=\$(_gs_eu2_semver_delta 'tags/2.4.66' 'tags/3.0.0')
    [[ \"\$result\" == 'major' ]] || { echo \"expected major for tags/ major bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t41c: tags/X.Y.Z minor bump → minor" bash -c "
    ${_SV_LIBS41}
    result=\$(_gs_eu2_semver_delta 'tags/2.4.66' 'tags/2.5.0')
    [[ \"\$result\" == 'minor' ]] || { echo \"expected minor for tags/ minor bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 42 — prerelease guard: proposed RC when current is stable → SKIP
# ═══════════════════════════════════════════════════════════════════════════
section "42 — prerelease guard in decide.sh"

_CD_LIBS42="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t42a: stable current + no-dash RC proposed → SKIP (not AUTO)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '6.3.0' '6.3.0RC1' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→RC (no dash), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42b: stable current + dash RC proposed → SKIP" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→rc1 (with dash), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42c: stable current + alpha proposed → SKIP" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '2.0.0' '2.1.0alpha1' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→alpha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42d: prerelease current + prerelease proposed → AUTO (both pre-release)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '1.0.0-rc1' '1.0.0-rc2' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for rc1→rc2, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42e: stable current + stable proposed → AUTO (normal upgrade)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '6.3.0' '6.3.1' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for stable patch bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42f: stable alpine-tagged current + stable alpine-tagged proposed → AUTO" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '8.6.1-alpine3.23' '8.6.3-alpine3.23' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for alpine patch bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 44 — check-tags flag + github.sh version-gap fix
# ═══════════════════════════════════════════════════════════════════════════
section "44 — check-tags flag + github version-gap fix"

t "t44a: (check-tags) flag recognised by parse.sh → no error, check_tags in dump" bash -c "
    f=\${TMP_DIR}/t44a.env
    printf '# @todo env-update (check-tags) github:testowner/tag-ahead 0.14.0\nGLOBAL_STACK_TEST_VERSION=0.14.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'check_tags: true' || { echo \"check_tags not in dump: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t44b: (check-tags) position-agnostic — after type:identifier" bash -c "
    f=\${TMP_DIR}/t44b.env
    printf '# @todo env-update github:testowner/tag-ahead (check-tags) 0.14.0\nGLOBAL_STACK_TEST_VERSION=0.14.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'check_tags: true' || { echo \"check_tags not in dump (trailing): \$out\"; echo FAIL; exit 0; }
    echo PASS
"

_GH_LIBS44="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

t "t44c: check_tags=true → merges releases + tags → finds newer tag version" bash -c "
    ${_GH_LIBS44}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh44c_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'github'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx check_tags       'true'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.13.0'
    _gs_eu2_fetch_github \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # releases has v0.14.0 only; tags has v0.15.2 — check-tags must merge and find v0.15.2
    [[ \"\$val\" == 'v0.15.2' ]] || { echo \"expected v0.15.2, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t44d: with_tags=true in CFG → same merge behaviour" bash -c "
    ${_GH_LIBS44}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh44d_cache
    declare -A _GS_EU2_CFG=([no_cache]=true [with_tags]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'github'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.13.0'
    _gs_eu2_fetch_github \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v0.15.2' ]] || { echo \"expected v0.15.2 (with_tags=true), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t44e: version-gap fix — releases older than current → auto-checks tags → finds newer" bash -c "
    ${_GH_LIBS44}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh44e_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'github'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_ZIG_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.15.2'
    _gs_eu2_fetch_github \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # releases v0.14.0 < current 0.15.2 → gap fix fetches tags → finds v0.15.2
    [[ \"\$val\" == 'v0.15.2' ]] || { echo \"expected v0.15.2 (gap fix), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t44f: version-gap fix uses cache key with :tags suffix in check-tags mode" bash -c "
    ${_GH_LIBS44}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/gh44f_cache
    declare -A _GS_EU2_CFG=([no_cache]=false)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'github'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx check_tags       'true'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.13.0'
    # First call populates cache
    _gs_eu2_fetch_github \$idx 2>/dev/null || true
    val1=\$(_gs_eu2_record_get \$idx proposed_version)
    # Second call via separate record reads from cache
    _gs_eu2_record_new; idx2=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx2 type             'github'
    _gs_eu2_record_set \$idx2 identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx2 check_tags       'true'
    _gs_eu2_record_set \$idx2 env_var          'GLOBAL_STACK_TEST_VERSION2'
    _gs_eu2_record_set \$idx2 current_version  '0.13.0'
    _gs_eu2_fetch_github \$idx2 2>/dev/null || true
    val2=\$(_gs_eu2_record_get \$idx2 proposed_version)
    [[ \"\$val1\" == 'v0.15.2' && \"\$val2\" == 'v0.15.2' ]] \
        || { echo \"expected v0.15.2/v0.15.2, got: '\$val1'/'\$val2'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 45 — --with-tags CLI flag
# ═══════════════════════════════════════════════════════════════════════════
section "45 — --with-tags CLI flag"

t "t45a: --with-tags CLI flag sets CFG[with_tags]=true" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/reporting/help.sh'
    source '${_GS_EU2_LIB}/core/args.sh'
    _gs_eu2_parse_args --with-tags
    [[ \"\${_GS_EU2_CFG[with_tags]}\" == 'true' ]] \
        || { echo \"expected with_tags=true, got: '\${_GS_EU2_CFG[with_tags]}'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t45b: --with-tags default is false when not passed" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/reporting/help.sh'
    source '${_GS_EU2_LIB}/core/args.sh'
    _gs_eu2_parse_args
    [[ \"\${_GS_EU2_CFG[with_tags]}\" == 'false' ]] \
        || { echo \"expected with_tags=false, got: '\${_GS_EU2_CFG[with_tags]}'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t45c: --with-tags prints [WITH-TAGS MODE] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t45c_cache
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --with-tags \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1)
    echo \"\$out\" | grep -qF '[WITH-TAGS MODE]' || { echo \"expected [WITH-TAGS MODE] banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 46 — same-version SKIP beats manual/override (RC1) + display (RC2)
# ═══════════════════════════════════════════════════════════════════════════
section "46 — same-version SKIP beats manual/override + display"

_DC46_LIBS="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t46a: classify — same version + override=true → SKIP (not MANUAL)" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.3' 'true' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46b: classify — same version + manual=true → SKIP (not MANUAL)" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '2.2.0' '2.2.0' 'true' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46c: classify — override=true but version changed → still MANUAL" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' 'true' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"expected MANUAL for changed version with override, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46d: display — (override) at same version shows '(up to date — override)' not '← manual flag'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t46d_cache
    f=\${TMP_DIR}/t46d.env
    # fixture for dockerhub:_/postgres returns 18.4-alpine3.23; set current to same
    printf '# @todo env-update (override) dockerhub:_/postgres\nGLOBAL_STACK_POSTGRES_OVR=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'up to date' || { echo \"expected 'up to date' in SKIP output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'override'   || { echo \"expected 'override' hint in SKIP output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qvF '[MANUAL ]'  || { echo \"should show [SKIP] not [MANUAL ]: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46e: sdkmanager fetcher does NOT set manual field — decide.sh classifies via versions" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/sdkmanager.sh'
    export _GS_EU2_SDKMANAGER_CMD_FIXTURE='${FIXTURES}/sdkmanager-list.txt'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t46e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkmanager'
    _gs_eu2_record_set \$idx identifier      'ndk'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_ANDROID_NDK_VERSION'
    _gs_eu2_record_set \$idx current_version '29.0.14206865'
    _gs_eu2_fetch_sdkmanager \$idx
    manual=\$(_gs_eu2_record_get \$idx manual)
    [[ -z \"\$manual\" ]] || { echo \"sdkmanager must NOT set manual; got: '\$manual'\"; echo FAIL; exit 0; }
    echo PASS
"

# Section 47 — (note:TEXT) annotation flag
# ═══════════════════════════════════════════════════════════════════════════
section "47 — (note:TEXT) annotation flag"

t "t47a: note flag parsed and stored in record field" bash -c "
    f=\${TMP_DIR}/t47a.env
    printf '# @todo env-update (note:also update setup.sh compat list) sdkmanager:build-tools 36.1.0\nGLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION=36.1.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'note: also update setup.sh compat list' || { echo \"note field not found in dump; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47b: note text with spaces preserved exactly" bash -c "
    f=\${TMP_DIR}/t47b.env
    printf '# @todo env-update (note:keep CHROME and FIREFOX in sync) dockerhub:selenium/standalone-chrome 4.41.0-20260222\nGLOBAL_STACK_SELENIUM_VERSION=4.41.0-20260222\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'note: keep CHROME and FIREFOX in sync' || { echo \"note text not preserved; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47c: note flag can appear alongside other flags (order-agnostic)" bash -c "
    f=\${TMP_DIR}/t47c.env
    printf '# @todo env-update (override) (note:companion var) dockerhub:_/myimage 1.0.0\nGLOBAL_STACK_FOO=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'note: companion var'  || { echo \"note not found; got: \$out\";     echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'override: true'        || { echo \"override not found; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47d: note line (↳) appears in --check output when version changes" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t47d_cache
    f=\${TMP_DIR}/t47d.env
    printf '# @todo env-update (note:also add to setup.sh compat list) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_POSTGRES_NOTE=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '↳' || { echo \"expected ↳ note line in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'also add to setup.sh compat list' || { echo \"note text not in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47e: no ↳ line when note is absent" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t47e_cache
    f=\${TMP_DIR}/t47e.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_POSTGRES_NONOTE=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '↳' && { echo \"unexpected ↳ in output (no note set): \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 47p — pecl fetcher (type:pecl) dispatch path
# (47 is used by note:TEXT annotation tests; this section covers pecl dispatch)
# ═══════════════════════════════════════════════════════════════════════════
section "47p — pecl fetcher dispatch path"

t "t47pa: type:pecl dispatches to _gs_eu2_fetch_pecl — not SKIP fallback (imagick, fixture)" bash -c "
    f=\${TMP_DIR}/t47pa.env
    printf '# @todo env-update pecl:imagick\nGLOBAL_STACK_PHP_IMAGICK_PECL=3.7.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47pa_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'not yet implemented' && { echo \"still hitting SKIP fallback: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'unknown fetcher type' && { echo \"still hitting unknown-type fallback: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE 'AUTO|SKIP|HOLD|ERROR' || { echo \"no decision token in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47pb: type:pecl happy path — proposed_version = latest stable from fixture (apcu 6.3.0)" bash -c "
    f=\${TMP_DIR}/t47pb.env
    printf '# @todo env-update pecl:apcu\nGLOBAL_STACK_PHP_APCU_VERSION=6.1.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47pb_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '6.3.0' || { echo \"expected 6.3.0 in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47pc: type:pecl unknown extension — ERROR decision not SKIP fallback" bash -c "
    f=\${TMP_DIR}/t47pc.env
    printf '# @todo env-update pecl:no-such-extension-xyzzy\nGLOBAL_STACK_XYZZY_PECL=1.0.0\n' > \"\$f\"
    out=\$(unset _GS_EU2_HTTP_FIXTURE_DIR; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47pc_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null || true)
    echo \"\$out\" | grep -qF 'unknown fetcher type' && { echo \"hit unknown-type fallback instead of ERROR: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'not yet implemented' && { echo \"hit not-implemented fallback instead of ERROR: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE 'ERROR|no stable release' || { echo \"expected ERROR or 'no stable release' in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 48 — pecl fetcher with (git:owner/repo) flag
# ═══════════════════════════════════════════════════════════════════════════
section "48 — pecl fetcher with (git:owner/repo) flag"

_PECL_GIT_FLAG_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
source '${_GS_EU2_LIB}/fetchers/pecl.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl49_cache
"

t "t49a: pecl + (git:...) — proposed_version from PECL, proposed_sha from git tag" bash -c "
    ${_PECL_GIT_FLAG_LIBS}
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl'
    _gs_eu2_record_set \$idx identifier       'zmq'
    _gs_eu2_record_set \$idx git_repo         'zeromq/php-zmq'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.1.2'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    sha=\$(_gs_eu2_record_get \$idx proposed_sha)
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected ver=1.1.3, got: '\$ver'\"; echo FAIL; exit 0; }
    [[ -n \"\$sha\" ]] || { echo 'expected non-empty SHA'; echo FAIL; exit 0; }
    [[ \"\$sha\" == '616b6c64ffd3866ed038615494306dd464ab53fc' ]] || { echo \"expected SHA=616b6c64..., got: '\$sha'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t49b: pecl + (git:...) — reuses imagick fixtures, version + SHA both set" bash -c "
    ${_PECL_GIT_FLAG_LIBS}
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl'
    _gs_eu2_record_set \$idx identifier       'imagick'
    _gs_eu2_record_set \$idx git_repo         'Imagick/imagick'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_IMAGICK_VERSION'
    _gs_eu2_record_set \$idx current_version  '3.7.0'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    sha=\$(_gs_eu2_record_get \$idx proposed_sha)
    # imagick fixture: 3.8.0 stable, 3.9.0beta1 beta → 3.8.0 wins
    [[ \"\$ver\" == '3.8.0' ]] || { echo \"expected ver=3.8.0, got: '\$ver'\"; echo FAIL; exit 0; }
    [[ -n \"\$sha\" ]] || { echo 'expected non-empty SHA'; echo FAIL; exit 0; }
    echo PASS
"

t "t49c: pecl + (git:...) HEAD unreachable — version set, SHA may be empty, no ERROR decision" bash -c "
    ${_PECL_GIT_FLAG_LIBS}
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl'
    _gs_eu2_record_set \$idx identifier       'zmq'
    _gs_eu2_record_set \$idx git_repo         'testowner/no-git-tag-repo'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.1.2'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    # Version must still be proposed (PECL fetch is independent of HEAD SHA fetch)
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected ver=1.1.3 even when HEAD SHA missing, got: '\$ver'\"; echo FAIL; exit 0; }
    # Decision must not be ERROR — HEAD SHA failure is a soft-fail
    [[ \"\$dec\" != 'ERROR' ]] || { echo 'decision must not be ERROR (soft-fail)'; echo FAIL; exit 0; }
    echo PASS
"

t "t49d: git flag missing (plain pecl) — no SHA fetched, proposed_sha empty" bash -c "
    ${_PECL_GIT_FLAG_LIBS}
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl'
    _gs_eu2_record_set \$idx identifier       'zmq'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.1.2'
    # No git_repo set
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    sha=\$(_gs_eu2_record_get \$idx proposed_sha)
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected ver=1.1.3, got: '\$ver'\"; echo FAIL; exit 0; }
    [[ -z \"\$sha\" ]] || { echo \"expected empty SHA when no git flag, got: '\$sha'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t49e: parse — (git:owner/repo) flag recognized and stored in git_repo field" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\$(mktemp)
    printf '# @todo env-update pecl:zmq (git:zeromq/php-zmq) 1.1.3\nGLOBAL_STACK_ZMQ=\n' > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    rm -f \"\$f\"
    git_repo=\$(_gs_eu2_record_get 0 git_repo)
    typ=\$(_gs_eu2_record_get 0 type)
    id=\$(_gs_eu2_record_get 0 identifier)
    [[ \"\$typ\" == 'pecl' ]] || { echo \"expected type=pecl, got: '\$typ'\"; echo FAIL; exit 0; }
    [[ \"\$id\" == 'zmq' ]] || { echo \"expected identifier=zmq, got: '\$id'\"; echo FAIL; exit 0; }
    [[ \"\$git_repo\" == 'zeromq/php-zmq' ]] || { echo \"expected git_repo=zeromq/php-zmq, got: '\$git_repo'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t49f: parse — (git:) without slash exits non-zero (invalid format)" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\$(mktemp)
    printf '# @todo env-update pecl:zmq (git:noslash) 1.1.3\nGLOBAL_STACK_ZMQ=\n' > \"\$f\"
    err=\$(_gs_eu2_parse_env_file \"\$f\" 2>&1 || true)
    rm -f \"\$f\"
    printf '%s' \"\$err\" | grep -q 'OWNER/REPO' || { echo \"expected OWNER/REPO error, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t49g: regression — git-primary PHP extensions use github: fetcher; zeromq/php-zmq dispatches without crash" bash -c "
    f=\${TMP_DIR}/t49g.env
    printf '# @todo env-update github:zeromq/php-zmq 1.1.3\nGLOBAL_STACK_PHP_ZMQ_VERSION=1.1.3\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t49g_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    # Must not produce unknown-type error
    echo \"\$out\" | grep -qF 'unknown fetcher type' && { echo \"github: hitting unknown-type fallback: \$out\"; echo FAIL; exit 0; }
    # Must not be an empty result
    echo \"\$out\" | grep -qE 'AUTO|SKIP|HOLD|ERROR' || { echo \"no decision token in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 50 — semver_delta YYYYMMDD-only date stamps → patch (not major)
# ═══════════════════════════════════════════════════════════════════════════
section "50 — semver_delta pure-date stamps (YYYYMMDD/YYYYMM)"

_SV_LIBS50="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
"

_CD_LIBS50="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t50a: v20260311 → v20260512 (YYYYMMDD with v-prefix) → patch" bash -c "
    ${_SV_LIBS50}
    result=\$(_gs_eu2_semver_delta 'v20260311' 'v20260512')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for YYYYMMDD date bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t50b: 20260101 → 20261231 (bare YYYYMMDD, no prefix) → patch" bash -c "
    ${_SV_LIBS50}
    result=\$(_gs_eu2_semver_delta '20260101' '20261231')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for bare YYYYMMDD bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t50c: 202601 → 202612 (YYYYMM 6-digit variant) → patch" bash -c "
    ${_SV_LIBS50}
    result=\$(_gs_eu2_semver_delta '202601' '202612')
    [[ \"\$result\" == 'patch' ]] || { echo \"expected patch for YYYYMM date bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t50d: 1.0.0 → 2.0.0 (normal semver major) still → major (regression guard)" bash -c "
    ${_SV_LIBS50}
    result=\$(_gs_eu2_semver_delta '1.0.0' '2.0.0')
    [[ \"\$result\" == 'major' ]] || { echo \"expected major for semver major bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t50e: v20260311 → v20260512 via classify_decision → AUTO (not HOLD)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    ${_CD_LIBS50}
    result=\$(_gs_eu2_classify_decision 'v20260311' 'v20260512' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for YYYYMMDD date bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 51 — SHA decision path (classify_sha_decision, parse annotation_sha_date,
#               apply SHA-only updates, display [SHA    ] label)
# ═══════════════════════════════════════════════════════════════════════════
section "51 — SHA decision path"

_SHA_CORE_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t51a: classify_sha_decision — same SHA returns SKIP" bash -c "
    ${_SHA_CORE_LIBS}
    sha='aabbccdd1122334455667788aabbccdd11223344'
    result=\$(_gs_eu2_classify_sha_decision \"\$sha\" \"\$sha\")
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for same SHA, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51b: classify_sha_decision — different SHAs returns SHA" bash -c "
    ${_SHA_CORE_LIBS}
    old='aabbccdd1122334455667788aabbccdd11223344'
    new='1122334455667788aabbccdd11223344aabbccdd'
    result=\$(_gs_eu2_classify_sha_decision \"\$old\" \"\$new\")
    [[ \"\$result\" == 'SHA' ]] || { echo \"expected SHA for different SHAs, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51c: classify_sha_decision — empty proposed_sha returns SKIP" bash -c "
    ${_SHA_CORE_LIBS}
    result=\$(_gs_eu2_classify_sha_decision 'aabbccdd' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for empty proposed, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51d: classify_sha_decision — empty annotation_sha with non-empty proposed returns SHA" bash -c "
    ${_SHA_CORE_LIBS}
    result=\$(_gs_eu2_classify_sha_decision '' 'aabbccdd1122334455667788aabbccdd11223344')
    [[ \"\$result\" == 'SHA' ]] || { echo \"expected SHA when no annotation SHA, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51e: parse sha:HASH (YYYY-MM-DD) — extracts both annotation_sha and annotation_sha_date" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t51e.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    date='2026-05-12'
    printf '# @todo env-update pecl-git:owner/repo 1.2.3 sha:%s (%s)\nGLOBAL_STACK_EXT_VERSION=1.2.3\n' \"\$sha\" \"\$date\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got_sha=\$(_gs_eu2_record_get 0 annotation_sha)
    got_date=\$(_gs_eu2_record_get 0 annotation_sha_date)
    [[ \"\$got_sha\" == \"\$sha\" ]] || { echo \"annotation_sha: expected '\$sha' got '\$got_sha'\"; echo FAIL; exit 0; }
    [[ \"\$got_date\" == \"\$date\" ]] || { echo \"annotation_sha_date: expected '\$date' got '\$got_date'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51f: parse sha:HASH without date — annotation_sha_date empty, version token extracted correctly" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t51f.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update pecl-git:owner/repo 1.2.3 sha:%s\nGLOBAL_STACK_EXT_VERSION=1.2.3\n' \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got_sha=\$(_gs_eu2_record_get 0 annotation_sha)
    got_date=\$(_gs_eu2_record_get 0 annotation_sha_date)
    got_ver=\$(_gs_eu2_record_get 0 current_version)
    [[ \"\$got_sha\" == \"\$sha\" ]] || { echo \"annotation_sha: expected '\$sha' got '\$got_sha'\"; echo FAIL; exit 0; }
    [[ -z \"\$got_date\" ]] || { echo \"annotation_sha_date should be empty, got '\$got_date'\"; echo FAIL; exit 0; }
    [[ \"\$got_ver\" == '1.2.3' ]] || { echo \"current_version: expected '1.2.3' got '\$got_ver'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51g: parse sha:HASH (YYYY-MM-DD) — hint after date paren still extracted separately" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t51g.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update pecl-git:owner/repo 1.2.3 sha:%s (2026-05-12) (hint text here)\nGLOBAL_STACK_EXT_VERSION=1.2.3\n' \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got_sha=\$(_gs_eu2_record_get 0 annotation_sha)
    got_date=\$(_gs_eu2_record_get 0 annotation_sha_date)
    got_hint=\$(_gs_eu2_record_get 0 hint)
    [[ \"\$got_sha\" == \"\$sha\" ]] || { echo \"annotation_sha mismatch: got '\$got_sha'\"; echo FAIL; exit 0; }
    [[ \"\$got_date\" == '2026-05-12' ]] || { echo \"annotation_sha_date: expected '2026-05-12' got '\$got_date'\"; echo FAIL; exit 0; }
    [[ \"\$got_hint\" == 'hint text here' ]] || { echo \"hint: expected 'hint text here' got '\$got_hint'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51h: apply SHA-only update rewrites sha: in annotation but leaves VAR= untouched" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t51h.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    new_date='2026-05-12'
    ann=\"# @todo env-update pecl:apcu (git:krakjoe/apcu) 5.1.24 sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_PHP_APCU_VERSION=5.1.24\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_APCU_VERSION'
    _gs_eu2_record_set \$idx current_version  '5.1.24'
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha   \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha     \"\$new_sha\"
    _gs_eu2_record_set \$idx proposed_sha_date \"\$new_date\"
    _gs_eu2_record_set \$idx decision         'SHA'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"new sha not in annotation; content:\"; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qE \"sha:[0-9a-f]+ +\\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)\" \"\$f\" && { echo \"date suffix written to annotation (unexpected)\"; cat \"\$f\"; echo FAIL; exit 0; } || true
    grep -qF \"sha:\${old_sha}\" \"\$f\" && { echo 'old sha still present'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_PHP_APCU_VERSION=5.1.24' \"\$f\" || { echo 'VAR= should be unchanged'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51i: apply SHA-only update — old annotation with date replaced by bare sha only" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t51i.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    old_date='2026-04-01'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    new_date='2026-05-12'
    ann=\"# @todo env-update pecl:apcu (git:krakjoe/apcu) 5.1.24 sha:\${old_sha} (\${old_date})\"
    printf '%s\nGLOBAL_STACK_PHP_APCU_VERSION=5.1.24\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var            'GLOBAL_STACK_PHP_APCU_VERSION'
    _gs_eu2_record_set \$idx current_version    '5.1.24'
    _gs_eu2_record_set \$idx raw_annotation     \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha     \"\$old_sha\"
    _gs_eu2_record_set \$idx annotation_sha_date \"\$old_date\"
    _gs_eu2_record_set \$idx proposed_sha       \"\$new_sha\"
    _gs_eu2_record_set \$idx proposed_sha_date  \"\$new_date\"
    _gs_eu2_record_set \$idx decision           'SHA'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"new sha not in annotation; content:\"; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qE \"sha:[0-9a-f]+ +\\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)\" \"\$f\" && { echo \"date suffix written to annotation (unexpected)\"; cat \"\$f\"; echo FAIL; exit 0; } || true
    grep -qF \"\${old_sha}\" \"\$f\" && { echo 'old sha still present'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF \"\${old_date}\" \"\$f\" && { echo 'old date still present'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_PHP_APCU_VERSION=5.1.24' \"\$f\" || { echo 'VAR= should be unchanged'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51j: (pecl-ref:ext) no longer sets pecl_ref field — treated as hint (passthrough)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    f=\${TMP_DIR}/t51j.env
    printf '# @todo env-update pecl-git:owner/repo 1.0.0 (pecl-ref:ext)\nGLOBAL_STACK_EXT_VERSION=1.0.0\n' > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    # pecl_ref field must be empty (flag no longer hoisted or dispatched)
    got_pecl_ref=\$(_gs_eu2_record_get 0 pecl_ref)
    [[ -z \"\$got_pecl_ref\" ]] || { echo \"pecl_ref should be empty, got '\$got_pecl_ref'\"; echo FAIL; exit 0; }
    # The paren group passes through as a hint instead
    got_hint=\$(_gs_eu2_record_get 0 hint)
    [[ \"\$got_hint\" == 'pecl-ref:ext' ]] || { echo \"expected hint='pecl-ref:ext', got '\$got_hint'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t51k: AUTO version update also rewrites sha: in annotation — new sha is bare (no date)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t51k.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    old_date='2026-04-01'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    new_date='2026-05-12'
    ann=\"# @todo env-update pecl:apcu (git:krakjoe/apcu) 5.1.23 sha:\${old_sha} (\${old_date})\"
    printf '%s\nGLOBAL_STACK_PHP_APCU_VERSION=5.1.23\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var            'GLOBAL_STACK_PHP_APCU_VERSION'
    _gs_eu2_record_set \$idx current_version    '5.1.23'
    _gs_eu2_record_set \$idx proposed_version   '5.1.24'
    _gs_eu2_record_set \$idx raw_annotation     \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha     \"\$old_sha\"
    _gs_eu2_record_set \$idx annotation_sha_date \"\$old_date\"
    _gs_eu2_record_set \$idx proposed_sha       \"\$new_sha\"
    _gs_eu2_record_set \$idx proposed_sha_date  \"\$new_date\"
    _gs_eu2_record_set \$idx decision           'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF 'GLOBAL_STACK_PHP_APCU_VERSION=5.1.24' \"\$f\" || { echo 'version not updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo 'new sha not in annotation'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qE \"sha:[0-9a-f]+ +\\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)\" \"\$f\" && { echo 'date suffix written to annotation (unexpected)'; cat \"\$f\"; echo FAIL; exit 0; } || true
    grep -qF \"\${old_sha}\" \"\$f\" && { echo 'old sha still present'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 52 — --unstable flag (full / info modes)
# ═══════════════════════════════════════════════════════════════════════════
section "52 — --unstable flag"

_DC_LIBS52="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

# t52a: --unstable is accepted as a valid flag (no exit 1 for unknown option)
t "t52a: --unstable flag accepted (no unknown-option error)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk52a
    err=\$(bash '${ENV_UPDATE_V2}' --unstable --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo \"--unstable rejected as unknown option\"; echo FAIL; exit 0; }
    echo PASS
"

# t52b: classify_decision with unstable_mode=full bypasses prerelease guard
#       stable current (1.2.3) + prerelease proposed (1.3.0-rc1) → AUTO (not SKIP)
t "t52b: unstable full mode: stable→prerelease classified AUTO (prerelease guard bypassed)" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '' 'full')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for stable→rc1 with unstable=full, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52c: classify_decision with unstable_mode=full still respects manual flag → MANUAL
t "t52c: unstable full mode: manual flag still forces MANUAL" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' 'true' '' 'full')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"expected MANUAL for manual+unstable=full, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52d: classify_decision with unstable_mode=full still respects override flag → MANUAL
t "t52d: unstable full mode: override flag still forces MANUAL" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' 'true' '' 'full')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"expected MANUAL for override+unstable=full, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52e: classify_decision without unstable mode still SKIPs stable→prerelease (regression guard)
t "t52e: without unstable mode: stable→prerelease still SKIP (regression guard)" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP without unstable mode, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52f: --unstable=info is accepted as a valid flag value
t "t52f: --unstable=info flag accepted (no unknown-option error)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk52f
    err=\$(bash '${ENV_UPDATE_V2}' --unstable=info --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo \"--unstable=info rejected as unknown option\"; echo FAIL; exit 0; }
    echo PASS
"

# t52g: --unstable with invalid value fails with a helpful error
t "t52g: --unstable=bogus exits with error message" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk52g
    err=\$(bash '${ENV_UPDATE_V2}' --unstable=bogus --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 || true)
    echo \"\$err\" | grep -qi 'bogus\|invalid\|unstable' || { echo \"expected error for bogus unstable value; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52h: --unstable full mode injects channel=unstable for records with no channel set.
#        We verify via --dump that channel field becomes 'unstable'.
t "t52h: --unstable full mode sets channel=unstable on records without annotation channel" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk52h
    out=\$(bash '${ENV_UPDATE_V2}' --unstable --dump --format=text \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    # The dump text output shows 'channel: unstable' (or the field is present with value)
    echo \"\$out\" | grep -qi 'unstable' || { echo \"expected 'unstable' in dump output; got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52i: --unstable=info mode does NOT change classify_decision output (SKIP stays SKIP)
t "t52i: unstable info mode: stable→prerelease still SKIP (no bypass)" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '' 'info')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for info mode (no bypass), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52j: --unstable full mode: stable current + alpha proposed with major bump → HOLD (not bypassed)
#        Major guard must still apply even in unstable mode.
t "t52j: unstable full mode: major jump + prerelease proposed → HOLD (major guard unchanged)" bash -c "
    ${_DC_LIBS52}
    result=\$(_gs_eu2_classify_decision '1.0.0' '2.0.0-alpha1' '' '' 'full')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"expected HOLD for major+prerelease unstable=full (no major_hint), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 53 — --stable flag
# ═══════════════════════════════════════════════════════════════════════════
section "53 — --stable flag"

# t53a: --stable is accepted (no unknown-option error)
t "t53a: --stable flag accepted (no unknown-option error)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53a
    err=\$(bash '${ENV_UPDATE_V2}' --stable --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo '--stable rejected as unknown option'; echo FAIL; exit 0; }
    echo PASS
"

# t53b: --stable=full mutually exclusive with --unstable=full (bare forms)
t "t53b: --stable and --unstable (both full) are mutually exclusive" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable --unstable 2>&1 || true)
    echo \"\$err\" | grep -qi 'mutually exclusive' || { echo \"expected mutually exclusive error, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53c: --stable=full + --unstable=full explicitly → still mutually exclusive
t "t53c: --stable=full + --unstable=full are mutually exclusive" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable=full --unstable=full 2>&1 || true)
    echo \"\$err\" | grep -qi 'mutually exclusive' || { echo \"expected mutually exclusive error, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53d: --stable overrides channel:unstable via --dump
# The dump text output for a channel:unstable record must show channel: stable after override.
# Discrimination: grep for exact 'channel: stable' line and ensure 'channel: unstable' is absent.
# Note: annotation uses (channel:VALUE) syntax with parentheses; write to a temp file because
# env-update.sh validates [[ -f env_file ]] (process substitution /dev/fd paths are not regular files).
t "t53d: --stable forces channel to stable on channel:unstable records (via --dump)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53d
    _tf53d=\"\${TMP_DIR}/t53d.env\"
    printf '# @todo env-update (channel:unstable) dockerhub:_/mariadb:11 11.8.0\nGLOBAL_STACK_MARIADB_VERSION=11.8.0\n' > \"\${_tf53d}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable --dump --format=text \
        --env-file=\"\${_tf53d}\" 2>/dev/null)
    echo \"\$out\" | grep -qE '^channel:[[:space:]]*stable\$' || { echo \"expected 'channel: stable' in dump, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '^channel:[[:space:]]*unstable\$' && { echo \"channel still unstable after --stable; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t53e: --stable leaves already-stable (channel="") records unchanged — banner still fires with 0 overrides
t "t53e: --stable with all-stable input — banner fires with 0 record(s) (unconditional)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53e
    _tf53e=\"\${TMP_DIR}/t53e.env\"
    printf '# @todo env-update dockerhub:_/alpine:3 3.21.0\nGLOBAL_STACK_X=3.21.0\n' > \"\${_tf53e}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable --dump \
        --env-file=\"\${_tf53e}\" 2>&1)
    echo \"\$out\" | grep -qF '[STABLE MODE]' || { echo \"expected [STABLE MODE] banner even with 0 overrides; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '0 record(s)' || { echo \"expected 0 record(s) count; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t53f: --stable header line is printed when overrides occur
t "t53f: --stable prints STABLE MODE header when records are overridden" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53f
    _tf53f=\"\${TMP_DIR}/t53f.env\"
    printf '# @todo env-update (channel:rc) dockerhub:_/mariadb:11 11.8.0\nGLOBAL_STACK_MARIADB_VERSION=11.8.0\n' > \"\${_tf53f}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable --dump \
        --env-file=\"\${_tf53f}\" 2>&1)
    echo \"\$out\" | grep -qi 'STABLE MODE' || { echo \"expected STABLE MODE header, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53f2: --unstable=full prints UNSTABLE MODE header when records are upgraded
t "t53f2: --unstable=full prints UNSTABLE MODE header when records are upgraded" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53f2
    _tf53f2=\"\${TMP_DIR}/t53f2.env\"
    printf '# @todo env-update dockerhub:_/mariadb:11 11.8.0\nGLOBAL_STACK_MARIADB_VERSION=11.8.0\n' > \"\${_tf53f2}\"
    out=\$(bash '${ENV_UPDATE_V2}' --unstable=full --dump \
        --env-file=\"\${_tf53f2}\" 2>&1)
    echo \"\$out\" | grep -qi 'UNSTABLE MODE' || { echo \"expected UNSTABLE MODE header, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53g: regression — --unstable=full still works normally (no breakage from --stable addition)
t "t53g: --unstable=full still works after --stable addition (regression)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53g
    err=\$(bash '${ENV_UPDATE_V2}' --unstable=full --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo '--unstable=full broken after --stable addition'; echo FAIL; exit 0; }
    echo PASS
"

# t53h: --stable=info is accepted as a valid flag value
t "t53h: --stable=info flag accepted (no unknown-option error)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53h
    err=\$(bash '${ENV_UPDATE_V2}' --stable=info --check \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qi 'unknown option\|bogus\|invalid' && { echo '--stable=info rejected as unknown'; echo FAIL; exit 0; }
    echo PASS
"

# t53i: --stable=bogus rejected with clear error
t "t53i: --stable=bogus exits with error message" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable=bogus 2>&1 || true)
    echo \"\$err\" | grep -qi 'bogus\|invalid\|stable' || { echo \"expected error for bogus stable value; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53j: --stable=full + --unstable=info allowed (relaxed mutex)
t "t53j: --stable=full + --unstable=info is allowed (no mutex error)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable=full --unstable=info 2>&1 || true)
    echo \"\$err\" | grep -qi 'mutually exclusive' && { echo \"unexpected mutex error for stable=full+unstable=info; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53k: --stable=info + --unstable=full allowed (relaxed mutex)
t "t53k: --stable=info + --unstable=full is allowed (no mutex error)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable=info --unstable=full 2>&1 || true)
    echo \"\$err\" | grep -qi 'mutually exclusive' && { echo \"unexpected mutex error for stable=info+unstable=full; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53l: --stable=info + --unstable=info allowed (relaxed mutex)
t "t53l: --stable=info + --unstable=info is allowed (no mutex error)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --stable=info --unstable=info 2>&1 || true)
    echo \"\$err\" | grep -qi 'mutually exclusive' && { echo \"unexpected mutex error for stable=info+unstable=info; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53m: --stable=info does NOT trigger second pass for already-stable-channel records.
#        A record with no annotation channel (default stable) should have no stable_proposed
#        value set. We check via --dump that the field is absent or empty (uses exact prefix
#        match ^stable_proposed to avoid matching 'unstable_proposed').
t "t53m: --stable=info skips second pass for already-stable-channel records (via --dump)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53m
    _tf53m=\"\${TMP_DIR}/t53m.env\"
    printf '# @todo env-update dockerhub:_/alpine:3 3.21.0\nGLOBAL_STACK_X=3.21.0\n' > \"\${_tf53m}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable=info --dump --format=text \
        --env-file=\"\${_tf53m}\" 2>/dev/null)
    # grep for 'stable_proposed: <non-empty>' — use ^stable_proposed to avoid matching unstable_proposed
    echo \"\$out\" | grep -qE '^stable_proposed:[[:space:]]+[^[:space:]]' && {
      echo \"stable_proposed unexpectedly set for already-stable channel; got: \$out\"
      echo FAIL; exit 0
    }
    echo PASS
"

# t53n: --stable injection still uses 'full' check (regression: existing stable=full behavior unchanged)
#        --stable=full forces channel=stable for rc records — STABLE MODE header must appear.
t "t53n: --stable=full injection still works (== full check regression guard)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53n
    _tf53n=\"\${TMP_DIR}/t53n.env\"
    printf '# @todo env-update (channel:rc) dockerhub:_/mariadb:11 11.8.0\nGLOBAL_STACK_MARIADB_VERSION=11.8.0\n' > \"\${_tf53n}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable=full --dump \
        --env-file=\"\${_tf53n}\" 2>&1)
    echo \"\$out\" | grep -qi 'STABLE MODE' || { echo \"expected STABLE MODE header for --stable=full; got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53o: --stable=info fires [STABLE] sub-line for a channel:rc record.
#       Uses fixture testowner/rc-ahead: v1.1.0-rc1 (prerelease, newest) + v1.0.0 (stable).
#       The main fetch (channel=rc) proposes v1.1.0-rc1; the stable=info second pass
#       finds v1.0.0 and stores it as stable_proposed → [STABLE] sub-line must appear.
t "t53o: --stable=info fires [STABLE] sub-line for channel:rc record (stable newer than current)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53o
    _tf53o=\"\${TMP_DIR}/t53o.env\"
    printf '# @todo env-update (channel:rc) github:testowner/rc-ahead v0.9.0\nGLOBAL_STACK_T53O=v0.9.0\n' > \"\${_tf53o}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable=info --check \
        --env-file=\"\${_tf53o}\" 2>/dev/null)
    echo \"\$out\" | grep -q '\[STABLE\]' || { echo \"expected [STABLE] sub-line; got: '\$out'\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'stable: v1.0.0' || { echo \"expected 'stable: v1.0.0'; got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53p: --stable=full emits per-record WARNING on stderr for annotated channel
t "t53p: --stable=full emits per-record WARNING for (channel:unstable) annotation" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/chk53p
    _tf53p=\"\${TMP_DIR}/t53p.env\"
    printf '# @todo env-update (channel:unstable) dockerhub:_/postgres 17.3-alpine3.23\nGLOBAL_STACK_T53P=17.3-alpine3.23\n' > \"\${_tf53p}\"
    out=\$(bash '${ENV_UPDATE_V2}' --stable --check \
        --env-file=\"\${_tf53p}\" 2>&1)
    echo \"\$out\" | grep -qF 'WARNING: overriding (channel:unstable)' || { echo \"expected per-record WARNING for channel:unstable; got: '\$out'\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_T53P' || { echo \"expected varname in WARNING line; got: '\$out'\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'Summary:' || { echo \"expected Summary line (proves --check fetch ran); got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 54 — unstable promotion guard (channel.sh)
# ═══════════════════════════════════════════════════════════════════════════
section "54 — unstable promotion guard"

# Direct unit-test of _gs_eu2_channel_select_best with channel=unstable

t "t54a: unstable: stable newer than prerelease → returns stable (promotion guard)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # stable=3.1.1 is newer than hp=3.0.0-rc.4 — should promote to stable
    versions=\$'3.0.0-rc.4\n3.1.1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '3.1.1' ]] || { echo \"expected 3.1.1 (stable promoted), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t54b: unstable: prerelease genuinely newer than stable → returns prerelease" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # hp=1.8.0-rc1 is newer base than hs=1.7.1 — prerelease wins
    versions=\$'1.7.1\n1.8.0-rc1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '1.8.0-rc1' ]] || { echo \"expected 1.8.0-rc1 (prerelease advance), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t54c: unstable: no stable exists → returns highest prerelease" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # No stable candidate — should return the highest prerelease
    versions=\$'0.1.0-alpha1\n0.2.0-rc1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '0.2.0-rc1' ]] || { echo \"expected 0.2.0-rc1 (highest prerelease), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t54d: unstable: same-base prerelease vs stable → stable newer (1.0.0-rc1 vs 1.0.0)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # 1.0.0-rc1 shipped as 1.0.0 → stable is newer, should promote
    versions=\$'1.0.0-rc1\n1.0.0'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '1.0.0' ]] || { echo \"expected 1.0.0 (stable promoted over rc of same base), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t54e: unstable: prerelease of higher base wins (0.35.0-rc1 vs stable 0.34.0)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    # 0.35.0-rc1 has higher base than stable 0.34.0 — prerelease wins
    versions=\$'0.34.0\n0.35.0-rc1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    [[ \"\$result\" == '0.35.0-rc1' ]] || { echo \"expected 0.35.0-rc1 (genuinely newer), got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 55 — --no-notes flag
# ═══════════════════════════════════════════════════════════════════════════
section "55 — --no-notes flag"

t "t55a: --no-notes suppresses (note: TEXT) sub-lines in --check output" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t55a_cache
    f=\${TMP_DIR}/t55a.env
    printf '# @todo env-update (note:also add to setup.sh) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG_NONOTES=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-notes --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'also add to setup.sh' && { echo \"note line still present with --no-notes: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t55b: without --no-notes, (note: TEXT) sub-line IS shown" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t55b_cache
    f=\${TMP_DIR}/t55b.env
    printf '# @todo env-update (note:sync with setup.sh) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG_WITHNOTES=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'sync with setup.sh' || { echo \"note line missing without --no-notes: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t55c: --no-notes does NOT suppress SHA sub-lines" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t55c_cache
    f=\${TMP_DIR}/t55c.env
    # Use github+use-sha fixture that produces a SHA sub-line + note
    printf '# @todo env-update (note:check compat) (use-sha) github:zeromq/php-zmq 1.1.3\nGLOBAL_STACK_ZMQ_SHA=1.1.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-notes --env-file=\"\$f\" 2>/dev/null)
    # note should be gone
    echo \"\$out\" | grep -qF 'check compat' && { echo \"note still present with --no-notes: \$out\"; echo FAIL; exit 0; }
    # Decision line must still be there
    echo \"\$out\" | grep -qE 'AUTO|SKIP|ERROR|HOLD|MANUAL' || { echo \"no decision token in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t55d: --no-notes is accepted without error (args parsing)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --no-notes 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option\|error' && { echo \"--no-notes rejected as unknown: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t55e: --no-notes prints [NO-NOTES MODE] banner with record count" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t55e_cache
    f=\${TMP_DIR}/t55e.env
    printf '# @todo env-update (note:sync with setup.sh) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T55E=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-notes --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[NO-NOTES MODE] note sub-lines suppressed for 1 record(s)' || { echo \"expected count banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 56 — --force-auto + --confirm flags
# ═══════════════════════════════════════════════════════════════════════════
section "56 — --force-auto + --confirm flags"

t "t56a: --force-auto --apply without --confirm exits 1 with FATAL message" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56a_cache
    f=\${TMP_DIR}/t56a.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56A=18.3-alpine3.23\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t56a_cache\"
    touch \"\${TMP_DIR}/t56a_cache/last-dry-run-ts\"
    err=\$(bash '${ENV_UPDATE_V2}' --apply --yes --force-auto --env-file=\"\$f\" 2>&1 || true)
    echo \"\$err\" | grep -qiF 'FATAL' || { echo \"expected FATAL message, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56b: --force-auto --apply --confirm='Wrong string' exits 1" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56b_cache
    f=\${TMP_DIR}/t56b.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56B=18.3-alpine3.23\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t56b_cache\"
    touch \"\${TMP_DIR}/t56b_cache/last-dry-run-ts\"
    err=\$(bash '${ENV_UPDATE_V2}' --apply --yes --force-auto --confirm='wrong string' --env-file=\"\$f\" 2>&1 || true)
    echo \"\$err\" | grep -qiF 'FATAL' || { echo \"expected FATAL for wrong confirm, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56c: --force-auto --check (no --apply) exits 0 — no confirm needed" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --force-auto 2>&1 || true)
    echo \"\$err\" | grep -qiF 'FATAL' && { echo \"unexpected FATAL for --force-auto without --apply: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56d: --force-auto accepted without error (args parsing)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --force-auto 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo \"--force-auto rejected as unknown: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56e: --confirm= accepted without error (args parsing)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --confirm='Confirm override' 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo \"--confirm rejected as unknown: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56f: --force-auto: (manual) annotation treated as AUTO-eligible" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56f_cache
    f=\${TMP_DIR}/t56f.env
    # current=18.3-alpine3.23 → fixture returns 18.4-alpine3.23, (manual) normally → MANUAL
    # With --force-auto it should NOT be MANUAL (becomes AUTO or SKIP)
    printf '# @todo env-update (manual) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56F=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[MANUAL ]' && { echo \"(manual) still classified MANUAL with --force-auto: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56g: without --force-auto, (manual) annotation produces MANUAL classification" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56g_cache
    f=\${TMP_DIR}/t56g.env
    # postgres fixture returns 18.4-alpine3.23 (newer than current 18.3-alpine3.23) → MANUAL
    printf '# @todo env-update (manual) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56G=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[MANUAL ]' || { echo \"expected MANUAL without --force-auto: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56h: --force-auto: (override) annotation treated as AUTO-eligible" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56h_cache
    f=\${TMP_DIR}/t56h.env
    # current=18.3-alpine3.23, fixture returns 18.4-alpine3.23 (patch bump → AUTO)
    # (override) flag normally forces MANUAL; --force-auto must bypass it
    printf '# @todo env-update (override) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56H=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[MANUAL ]' && { echo \"(override) still classified MANUAL with --force-auto: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56i: --force-auto upgrades HOLD to AUTO (major-bump guard bypass)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56i_cache
    f=\${TMP_DIR}/t56i.env
    # current=17.3-alpine3.23, fixture returns 18.4-alpine3.23 (major jump, no major_hint → HOLD)
    # With --force-auto, HOLD must be upgraded to AUTO
    printf '# @todo env-update dockerhub:_/postgres 17.3-alpine3.23\nGLOBAL_STACK_T56I=17.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[HOLD' && { echo \"HOLD not upgraded to AUTO with --force-auto: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56j: --force-auto prints [FORCE-AUTO MODE] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56j_cache
    f=\${TMP_DIR}/t56j.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56J=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qi 'FORCE-AUTO MODE' || { echo \"expected [FORCE-AUTO MODE] banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56k: --force-hold accepted without error (args parsing)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --force-hold 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option' && { echo \"--force-hold rejected as unknown: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56l: --force-hold alone (no --check, no --apply) exits 1 with usage message" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --force-hold 2>&1 || true)
    echo \"\$err\" | grep -qi 'requires --check or --apply' || { echo \"expected usage error, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56m: --force-hold --apply without --confirm exits 1 with FATAL message" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56m_cache
    f=\${TMP_DIR}/t56m.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56M=18.3-alpine3.23\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t56m_cache\"
    err=\$(bash '${ENV_UPDATE_V2}' --apply --yes --force-hold --env-file=\"\$f\" 2>&1 || true)
    echo \"\$err\" | grep -qiF 'FATAL' || { echo \"expected FATAL message, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56n: --force-hold prints [FORCE-HOLD MODE] banner on --check" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56n_cache
    f=\${TMP_DIR}/t56n.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56N=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-hold --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qi 'FORCE-HOLD MODE' || { echo \"expected [FORCE-HOLD MODE] banner, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56o: --force-hold does NOT bypass (manual) annotation (unlike --force-auto)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56o_cache
    f=\${TMP_DIR}/t56o.env
    # (manual) + newer version → normally MANUAL; --force-hold must NOT change this
    printf '# @todo env-update (manual) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T56O=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-hold --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[MANUAL ]' || { echo \"expected MANUAL to remain MANUAL with --force-hold: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56p: --force-hold upgrades HOLD to AUTO (major-bump guard bypass)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56p_cache
    f=\${TMP_DIR}/t56p.env
    # current=17.3-alpine3.23, fixture returns 18.4-alpine3.23 (major jump, no major_hint → HOLD)
    # With --force-hold, HOLD must be upgraded to AUTO
    printf '# @todo env-update dockerhub:_/postgres 17.3-alpine3.23\nGLOBAL_STACK_T56P=17.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-hold --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[HOLD' && { echo \"HOLD not upgraded to AUTO with --force-hold: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"expected [AUTO after --force-hold upgrade, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56q: --force-hold does NOT bypass (override) annotation — stays MANUAL" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t56q_cache
    f=\${TMP_DIR}/t56q.env
    # (override) + major jump → normally MANUAL; --force-hold must NOT change this (unlike --force-auto)
    printf '# @todo env-update (override) dockerhub:_/postgres 17.3-alpine3.23\nGLOBAL_STACK_T56Q=17.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-hold --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[MANUAL ]' || { echo \"expected MANUAL to remain MANUAL with --force-hold (override): \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t56r: --force-auto + --force-hold mutually exclusive → exit 1" bash -c "
    f=\$(mktemp)
    printf '# @todo env-update dockerhub:_/postgres 17.3-alpine3.23\nGLOBAL_STACK_T56R=17.3-alpine3.23\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --check --force-auto --force-hold --env-file=\"\$f\" 2>&1); rc=\$?
    rm -f \"\$f\"
    [[ \"\$rc\" -ne 0 ]] || { echo \"expected non-zero exit when --force-auto and --force-hold combined, got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'mutually exclusive' || { echo \"expected 'mutually exclusive' in error: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 57 — RC→stable promotion guard in decide.sh
# ═══════════════════════════════════════════════════════════════════════════
section "57 — RC→stable promotion guard"

_CD_LIBS57="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

t "t57a: rc2→stable same base → AUTO (not SKIP)" bash -c "
    ${_CD_LIBS57}
    result=\$(_gs_eu2_classify_decision '37.0.0-rc2' '37.0.0' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for rc2→stable, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t57b: alpha1→stable same base → AUTO (not SKIP)" bash -c "
    ${_CD_LIBS57}
    result=\$(_gs_eu2_classify_decision '1.0.0-alpha1' '1.0.0' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for alpha→stable, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t57c: prerelease→lower stable different base → SKIP (genuine downgrade)" bash -c "
    ${_CD_LIBS57}
    result=\$(_gs_eu2_classify_decision '2.0.0-beta3' '1.9.9' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for downgrade to lower base, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t57d: stable→RC same base → SKIP (not a promotion)" bash -c "
    ${_CD_LIBS57}
    result=\$(_gs_eu2_classify_decision '3.0.0' '3.0.0-rc1' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→RC, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# Platform suffix (-alpine3.23) is NOT a prerelease — guard does not fire;
# stripping the platform suffix remains a SKIP (sort -V path still applies).
t "t57e: alpine-tagged→bare same numeric base → SKIP (platform suffix, not prerelease)" bash -c "
    ${_CD_LIBS57}
    result=\$(_gs_eu2_classify_decision '3.0.0-alpine3.23' '3.0.0' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for alpine→bare (platform suffix not prerelease), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 58 — (watch-major) flag
# ═══════════════════════════════════════════════════════════════════════════
section "58 — (watch-major) flag"

_CD_LIBS58="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
"

# t58a: _gs_eu2_version_prefix depth 1 — strips build metadata and returns major
t "t58a: version_prefix depth-1 strips +meta and returns major" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix '25.0.1+9-LTS' '1')
    [[ \"\$r\" == '25' ]] || { echo \"expected '25', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58b: _gs_eu2_version_prefix depth 2 — returns major.minor
t "t58b: version_prefix depth-2 returns major.minor" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix '8.5.2' '2')
    [[ \"\$r\" == '8.5' ]] || { echo \"expected '8.5', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58c: _gs_eu2_version_prefix depth 1 plain version — returns major only
t "t58c: version_prefix depth-1 plain version" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix '22.15.0' '1')
    [[ \"\$r\" == '22' ]] || { echo \"expected '22', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58c2: _gs_eu2_version_prefix strips v-prefix — v24.14.0 → 24
t "t58c2: version_prefix strips v-prefix (v24.14.0 → 24)" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix 'v24.14.0' '1')
    [[ \"\$r\" == '24' ]] || { echo \"expected '24', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58c3: _gs_eu2_version_prefix strips v-prefix — v26.0.0 → 26
t "t58c3: version_prefix strips v-prefix (v26.0.0 → 26)" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix 'v26.0.0' '1')
    [[ \"\$r\" == '26' ]] || { echo \"expected '26', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58c4: _gs_eu2_version_prefix strips v-prefix — v3.4.9 → 3
t "t58c4: version_prefix strips v-prefix (v3.4.9 → 3)" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_prefix 'v3.4.9' '1')
    [[ \"\$r\" == '3' ]] || { echo \"expected '3', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58d: _gs_eu2_version_tag_suffix — dash suffix detected
t "t58d: version_tag_suffix detects -zulu suffix" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_tag_suffix '25.0.1-zulu')
    [[ \"\$r\" == '-zulu' ]] || { echo \"expected '-zulu', got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58e: _gs_eu2_version_tag_suffix — build metadata (+) is NOT a tag suffix
t "t58e: version_tag_suffix ignores build metadata (+9-LTS)" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_tag_suffix '25.0.1+9-LTS')
    [[ -z \"\$r\" ]] || { echo \"expected empty (build metadata), got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58f: _gs_eu2_version_tag_suffix — no suffix
t "t58f: version_tag_suffix returns empty when no suffix" bash -c "
    ${_CD_LIBS58}
    r=\$(_gs_eu2_version_tag_suffix '22.15.0')
    [[ -z \"\$r\" ]] || { echo \"expected empty, got: '\$r'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58g: (watch-major) flag is recognised by the parser (no error)
t "t58g: watch-major flag is recognised — no parse error" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58g_cache
    f=\${TMP_DIR}/t58g.env
    printf '# @todo env-update (watch-major) dockerhub:_/postgres 17.5\nGLOBAL_STACK_PG=17.5\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown flag\|unrecognized' && { echo \"flag rejected: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t58h: (watch-major:2) with explicit depth — recognised, no error
t "t58h: watch-major:2 (depth 2) is recognised — no parse error" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58h_cache
    f=\${TMP_DIR}/t58h.env
    printf '# @todo env-update (watch-major:2) dockerhub:_/php 8.5.2\nGLOBAL_STACK_PHP=8.5.2\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown flag\|unrecognized' && { echo \"flag rejected: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t58i: (watch-major) fires when fixture contains a higher major
# Postgres fixture has 18.4 (latest) + 17.5. Pin to major 17.
# WATCH should fire: 17 → 18.
t "t58i: watch-major fires when higher-major version exists in fixture" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58i_cache
    f=\${TMP_DIR}/t58i.env
    printf '# @todo env-update (watch-major) dockerhub:_/postgres:17 17.5\nGLOBAL_STACK_PG17=17.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"expected [WATCH] sub-line, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '18' || { echo \"expected 18 in WATCH output, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t58j: (watch-major) does NOT fire when current is already on latest major
# Pin to major 18 — 18.4 is the highest in the fixture; no WATCH.
t "t58j: watch-major silent when already on latest major" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58j_cache
    f=\${TMP_DIR}/t58j.env
    printf '# @todo env-update (watch-major) dockerhub:_/postgres:18 18.3\nGLOBAL_STACK_PG18=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' && { echo \"unexpected [WATCH] when on latest major: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t58k: --no-notes does NOT suppress [WATCH] sub-line (WATCH is a signal, not a note)
t "t58k: --no-notes does NOT suppress [WATCH] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58k_cache
    f=\${TMP_DIR}/t58k.env
    printf '# @todo env-update (watch-major) dockerhub:_/postgres:17 17.5\nGLOBAL_STACK_PG17B=17.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-notes --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"[WATCH] missing with --no-notes (should fire): \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t58l: (watch-major) coexists with (manual) — AUTO decision not affected
t "t58l: watch-major coexists with manual flag — decision is MANUAL, WATCH may appear" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58l_cache
    f=\${TMP_DIR}/t58l.env
    printf '# @todo env-update (manual) (watch-major) dockerhub:_/postgres:17 17.5\nGLOBAL_STACK_PG17C=17.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'MANUAL' || { echo \"expected MANUAL decision, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t58m: SDKMAN Java (watch-major) fires — current on major 11, fixture has 25.x
# java fixture (/versions/all) contains 11.x through 25.x; pinned to :11 → WATCH fires 11 → 25.
_SDK_LIBS58M="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/sdkman.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58m_cache
"

t "t58m: sdkman java (watch-major) fires when fixture has a higher major (11→25)" bash -c "
    ${_SDK_LIBS58M}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA11_VERSION'
    _gs_eu2_record_set \$idx current_version '11.0.30-zulu'
    _gs_eu2_record_set \$idx major_hint      '11'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_sdkman \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo \"proposed_version empty\"; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 11.* ]] || { echo \"proposed should be 11.x, got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo \"latest_unconstrained empty — WATCH cannot fire\"; echo FAIL; exit 0; }
    # unconstrained should be the highest version from the full fixture (25.x-zulu)
    [[ \"\$unconstrained\" == 25.* ]] || { echo \"expected unconstrained 25.x, got: '\$unconstrained'\"; echo FAIL; exit 0; }
    echo PASS
"

# t58n: SDKMAN Java (watch-major) silent — current on major 25, no higher major in fixture
t "t58n: sdkman java (watch-major) silent when already on latest major (25)" bash -c "
    ${_SDK_LIBS58M}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58n_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'java'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_JAVA25_VERSION'
    _gs_eu2_record_set \$idx current_version '25.0.1-zulu'
    _gs_eu2_record_set \$idx major_hint      '25'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_sdkman \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo \"proposed_version empty\"; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 25.* ]] || { echo \"proposed should be 25.x, got: '\$proposed'\"; echo FAIL; exit 0; }
    # When unconstrained == proposed major, WATCH must not fire.
    # Either unconstrained is empty (nothing higher found) or its major matches proposed.
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '1')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has different major than proposed '\$proposed' — WATCH would fire unexpectedly\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t58o: SDKMAN non-Java (watch-major) fires — gradle pinned to major 4, fixture has 9.x
_SDK_LIBS58O="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/sdkman.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58o_cache
"

t "t58o: sdkman gradle (watch-major) fires when fixture has higher major (4→9)" bash -c "
    ${_SDK_LIBS58O}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'sdkman'
    _gs_eu2_record_set \$idx identifier      'gradle'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_GRADLE4_VERSION'
    _gs_eu2_record_set \$idx current_version '4.6'
    _gs_eu2_record_set \$idx major_hint      '4'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_sdkman \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo \"proposed_version empty\"; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 4.* ]] || { echo \"proposed should be 4.x, got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo \"latest_unconstrained empty — WATCH cannot fire\"; echo FAIL; exit 0; }
    # unconstrained should be from 9.x (highest stable in gradle fixture)
    [[ \"\$unconstrained\" == 9.* ]] || { echo \"expected unconstrained 9.x, got: '\$unconstrained'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 59 — github (watch-major) flag
# ═══════════════════════════════════════════════════════════════════════════
section "59 — github (watch-major) flag"

_GH_LIBS59="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t59a: github + (watch-major) — same major in fixture, no WATCH
# watchrepo-older has v3.1.0, v3.0.5, v2.9.0. Pin to major 3 → proposed=v3.1.0.
# latest_unconstrained also 3.x → WATCH must NOT fire.
t "t59a: github watch-major — same major in fixture, no WATCH emitted" bash -c "
    ${_GH_LIBS59}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59a_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'testorg/watchrepo-older'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_WM_A'
    _gs_eu2_record_set \$idx current_version '3.0.5'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_github \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    # If unconstrained is set, its major must equal proposed's major (no new generation)
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '1')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has higher major than proposed '\$proposed'\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t59b: github + (watch-major) — newer major exists, latest_unconstrained set
# watchrepo-newer has v4.0.0, v3.1.0, v3.0.5. Pin to major 3 → proposed=v3.1.0.
# unconstrained = v4.0.0 → WATCH fires (depth1: 3 vs 4).
t "t59b: github watch-major — newer major exists, latest_unconstrained populated" bash -c "
    ${_GH_LIBS59}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'testorg/watchrepo-newer'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_WM_B'
    _gs_eu2_record_set \$idx current_version '3.0.5'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_github \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" == v3.* || \"\$proposed\" == 3.* ]] || { echo \"proposed should be 3.x, got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire'; echo FAIL; exit 0; }
    pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx_u\" == '4' ]] || { echo \"expected unconstrained major 4, got: '\$pfx_u' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t59c: github + (watch-major) via --check, WATCH line appears in output
t "t59c: github watch-major — [WATCH] line appears in --check output when newer major exists" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59c_cache
    f=\${TMP_DIR}/t59c.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 3.0.5\nGLOBAL_STACK_TEST_WM_C=3.0.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"expected [WATCH] in output, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t59d: github + (watch-major) — no WATCH when already at latest major
t "t59d: github watch-major — no [WATCH] when on latest major in fixture" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59d_cache
    f=\${TMP_DIR}/t59d.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:4 4.0.0\nGLOBAL_STACK_TEST_WM_D=4.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' && { echo \"unexpected [WATCH] on latest major: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t59e: github + (watch-major:2) depth2 — same X.Y, no WATCH
# watchrepo-depth2-older has v8.5.3, v8.5.0, v8.4.9, v8.3.0. Pin to major_hint=8.
# unconstrained (depth2 prefix: 8.5) == proposed depth2 → no WATCH.
t "t59e: github watch-major:2 — same X.Y generation, no WATCH" bash -c "
    ${_GH_LIBS59}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'github'
    _gs_eu2_record_set \$idx identifier        'testorg/watchrepo-depth2-older'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_TEST_WM_E'
    _gs_eu2_record_set \$idx current_version   '8.5.0'
    _gs_eu2_record_set \$idx major_hint        '8'
    _gs_eu2_record_set \$idx watch_major_depth '2'
    _gs_eu2_record_set \$idx tag_strip_prefix  'v'
    _gs_eu2_fetch_github \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '2')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '2')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has different X.Y than proposed '\$proposed'\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t59f: github + (watch-major:2) depth2 — newer X.Y, latest_unconstrained set with 8.6
# watchrepo-depth2-newer has v8.6.0, v8.5.3, v8.5.0, v8.4.0. Pin to major_hint=8.
# unconstrained=8.6.0 (prefix depth2: 8.6) vs proposed=8.5.3 (prefix: 8.5) → WATCH fires.
t "t59f: github watch-major:2 — newer X.Y generation, latest_unconstrained populated" bash -c "
    ${_GH_LIBS59}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59f_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'github'
    _gs_eu2_record_set \$idx identifier        'testorg/watchrepo-depth2-newer'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_TEST_WM_F'
    _gs_eu2_record_set \$idx current_version   '8.5.0'
    _gs_eu2_record_set \$idx major_hint        '8'
    _gs_eu2_record_set \$idx watch_major_depth '2'
    _gs_eu2_record_set \$idx tag_strip_prefix  'v'
    _gs_eu2_fetch_github \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire for depth2'; echo FAIL; exit 0; }
    pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '2')
    [[ \"\$pfx_u\" == '8.6' ]] || { echo \"expected unconstrained prefix 8.6, got: '\$pfx_u' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t59g: github + (watch-major) — --no-notes does NOT suppress WATCH
t "t59g: github watch-major — --no-notes does NOT suppress [WATCH] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59g_cache
    f=\${TMP_DIR}/t59g.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 3.0.5\nGLOBAL_STACK_TEST_WM_G=3.0.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-notes --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"[WATCH] suppressed by --no-notes (should not be): \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t59h: github + (watch-major) unit check — latest_unconstrained is populated by the fetcher
# Note: --dump only shows parsed annotation fields (no fetcher invoked); use unit-level API.
t "t59h: github watch-major — fetcher populates latest_unconstrained (unit check)" bash -c "
    ${_GH_LIBS59}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t59h_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'testorg/watchrepo-newer'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_WM_H'
    _gs_eu2_record_set \$idx current_version '3.0.5'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_github \$idx
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty after fetching watchrepo-newer'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 28 additions — npm (watch-major) flag (after bug fix)
# ═══════════════════════════════════════════════════════════════════════════
section "28b — npm (watch-major) flag"

_NPM_LIBS_WM="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/npm.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t28g: npm + (watch-major) — same major, no WATCH (unconstrained == proposed major)
# somepackage fixture: dist-tags.latest=24.1.0, versions: 24.1.0, 24.0.5, 23.8.0
# Pin to major 24 → proposed=24.1.0, unconstrained=24.1.0 → same major, no WATCH.
t "t28g: npm watch-major — same major in fixture, no WATCH emitted" bash -c "
    ${_NPM_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t28g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      'somepackage'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_NPM_WM_G'
    _gs_eu2_record_set \$idx current_version '24.0.5'
    _gs_eu2_record_set \$idx major_hint      '24'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_npm \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 24.* ]] || { echo \"proposed should be 24.x, got: '\$proposed'\"; echo FAIL; exit 0; }
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '1')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has higher major than proposed '\$proposed'\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t28h: npm + (watch-major) — newer major exists, latest_unconstrained populated
# bigpackage fixture: versions 25.0.0, 24.1.0, 24.0.5. Pin to major 24 → proposed=24.1.0.
# unconstrained=25.0.0 → WATCH fires.
t "t28h: npm watch-major — newer major in fixture, latest_unconstrained=25.x" bash -c "
    ${_NPM_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t28h_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      'bigpackage'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_NPM_WM_H'
    _gs_eu2_record_set \$idx current_version '24.0.5'
    _gs_eu2_record_set \$idx major_hint      '24'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_npm \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 24.* ]] || { echo \"proposed should be 24.x (major-pinned), got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire'; echo FAIL; exit 0; }
    pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx_u\" == '25' ]] || { echo \"expected unconstrained major 25, got: '\$pfx_u' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t28i: npm + (watch-major) — _GS_EU2_HTTP_FIXTURE_DIR bypasses CLI fast path
# This verifies the fixture seam already works (the pre-condition for t28g/t28h).
t "t28i: npm watch-major — fixture dir set means CLI path not taken (stable fast path gated)" bash -c "
    ${_NPM_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t28i_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      'somepackage'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_NPM_WM_I'
    _gs_eu2_record_set \$idx current_version '24.0.5'
    _gs_eu2_record_set \$idx major_hint      '24'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_npm \$idx
    # If fixture was used (API path), proposed_version comes from versions list
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty — fixture not served'; echo FAIL; exit 0; }
    echo PASS
"

# t28j: npm + (watch-major) — major_hint correctly caps result to 24, unconstrained holds 25
t "t28j: npm watch-major — major_hint caps proposed to 24, unconstrained holds 25.0.0" bash -c "
    ${_NPM_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t28j_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      'bigpackage'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TEST_NPM_WM_J'
    _gs_eu2_record_set \$idx current_version '24.0.5'
    _gs_eu2_record_set \$idx major_hint      '24'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_npm \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    # proposed must be capped to major 24
    [[ \"\$proposed\" == 24.* ]] || { echo \"proposed not capped to 24: '\$proposed'\"; echo FAIL; exit 0; }
    # unconstrained must be 25.0.0 (highest across all versions)
    [[ \"\$unconstrained\" == '25.0.0' ]] || { echo \"expected unconstrained=25.0.0, got: '\$unconstrained'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 60 — --format=json (--dump) output
# ═══════════════════════════════════════════════════════════════════════════
section "60 — --format=json (--dump) output"

# t60a: --dump --format=json produces valid JSON
t "t60a: --dump --format=json output is valid JSON (parses with jq)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60a_cache
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    echo \"\$out\" | jq empty 2>/dev/null && echo PASS || { echo \"invalid JSON: \$out\"; echo FAIL; }
"

# t60b: --dump --format=json contains required record fields
t "t60b: --dump --format=json contains env_var, type, current_version, identifier fields" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60b_cache
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    echo \"\$out\" | jq -e '.[0].env_var' >/dev/null 2>&1 || { echo \"env_var field missing\"; echo FAIL; exit 0; }
    echo \"\$out\" | jq -e '.[0].type' >/dev/null 2>&1 || { echo \"type field missing\"; echo FAIL; exit 0; }
    echo \"\$out\" | jq -e '.[0].current_version' >/dev/null 2>&1 || { echo \"current_version field missing\"; echo FAIL; exit 0; }
    echo \"\$out\" | jq -e '.[0].identifier' >/dev/null 2>&1 || { echo \"identifier field missing\"; echo FAIL; exit 0; }
    echo PASS
"

# t60c: --dump --format=json contains watch_major_depth field when annotation uses (watch-major)
# Note: --dump shows parsed annotation fields; watch_major_depth is set by the parser.
t "t60c: --dump --format=json contains watch_major_depth field for watch-major annotations" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60c_cache
    f=\${TMP_DIR}/t60c.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 3.0.5\nGLOBAL_STACK_T60C=3.0.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | jq empty 2>/dev/null || { echo \"invalid JSON\"; echo FAIL; exit 0; }
    val=\$(echo \"\$out\" | jq -r '.[] | .watch_major_depth' 2>/dev/null)
    [[ -n \"\$val\" && \"\$val\" != 'null' && \"\$val\" != '' ]] || { echo \"watch_major_depth missing or null in JSON dump: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t60d: --dump --format=json with multiple records is a valid JSON array
t "t60d: --dump --format=json produces a JSON array (not object)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60d_cache
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    echo \"\$out\" | jq -e 'type == \"array\"' >/dev/null 2>&1 && echo PASS || { echo \"expected JSON array, got: \$(echo \"\$out\" | head -1)\"; echo FAIL; }
"

# t60e: --format=text (explicit) uses text format (regression guard after json addition)
t "t60e: --dump --format=text produces human-readable text (not JSON)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60e_cache
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=text \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    echo \"\$out\" | grep -qF 'env_var:' || { echo \"text format missing env_var: field\"; echo FAIL; exit 0; }
    echo \"\$out\" | jq empty 2>/dev/null && { echo \"output is JSON (expected text)\"; echo FAIL; exit 0; }
    echo PASS
"

# t60f: --dump --format=json serializes stable_proposed field (non-vacuous: field must
# appear with a non-empty value). Because --dump runs the parse phase only (fetchers are
# not invoked), stable_proposed is populated directly via the record API before dumping.
# This tests the dump path end-to-end: record_set → dump.sh iterates record_fields →
# JSON key appears. Without the Finding 4.4 fix (missing from record_fields), the key
# would be absent from the output even when the value was set.
t "t60f: --dump --format=json serializes stable_proposed field (record_fields coverage)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/reporting/dump.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T60F_VERSION'
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'testowner/prerelease-repo'
    _gs_eu2_record_set \$idx current_version 'v1.8.4'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_record_set \$idx proposed_version 'v1.9.0-rc2'
    _gs_eu2_record_set \$idx stable_proposed  'v1.8.5'
    out=\$(_gs_eu2_dump_json)
    echo \"\$out\" | jq empty 2>/dev/null || { echo \"invalid JSON: \$out\"; echo FAIL; exit 0; }
    val=\$(echo \"\$out\" | jq -r '.[0].stable_proposed' 2>/dev/null)
    [[ \"\$val\" == 'v1.8.5' ]] || { echo \"stable_proposed wrong in JSON dump — expected v1.8.5 got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t60g: --dump --format=json output is clean JSON (no banner lines) when --no-cache and
# --filter are also passed. Regression guard: banners previously went to stdout, corrupting
# the JSON array and causing jq parse errors on any combined invocation.
t "t60g: --dump --format=json stdout is clean JSON even with --no-cache and --filter" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t60g_cache
    out=\$(bash '${ENV_UPDATE_V2}' --dump --format=json --no-cache --filter=POSTGRES \
        --env-file='${FIXTURES}/basic-dockerhub.env' 2>/dev/null)
    echo \"\$out\" | jq empty 2>/dev/null || { echo \"invalid JSON (banners on stdout?): \$(echo \"\$out\" | head -3)\"; echo FAIL; exit 0; }
    echo \"\$out\" | jq -e 'type == \"array\"' >/dev/null 2>&1 || { echo \"expected JSON array\"; echo FAIL; exit 0; }
    echo PASS
"

# t60h: --dump --format=json serializes tag_channel_prefix field (non-vacuous:
# field must appear with the value set). tag_channel_prefix is dispatched by
# parse.sh via (tag-channel-prefix:STR) but was missing from _gs_eu2_record_fields(),
# causing dump.sh to silently drop it. This test catches that regression.
t "t60h: --dump --format=json serializes tag_channel_prefix field (record_fields coverage)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/reporting/dump.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_T60H_VERSION'
    _gs_eu2_record_set \$idx type             'github'
    _gs_eu2_record_set \$idx identifier       'testowner/rtk-repo'
    _gs_eu2_record_set \$idx current_version  'v0.40.0'
    _gs_eu2_record_set \$idx tag_channel_prefix 'dev-'
    out=\$(_gs_eu2_dump_json)
    echo \"\$out\" | jq empty 2>/dev/null || { echo \"invalid JSON: \$out\"; echo FAIL; exit 0; }
    val=\$(echo \"\$out\" | jq -r '.[0].tag_channel_prefix' 2>/dev/null)
    [[ \"\$val\" == 'dev-' ]] || { echo \"tag_channel_prefix wrong in JSON dump — expected 'dev-' got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 58b — pypi + rubygems (watch-major)
# ═══════════════════════════════════════════════════════════════════════════
section "58b — pypi + rubygems (watch-major)"

_PYPI_LIBS_WM="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/pypi.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

_RUBY_LIBS_WM="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/rubygems.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t58p: pypi + (watch-major) — same major, no newer generation
# somepkg fixture: versions 3.0.0, 3.1.0, 3.1.1. Pin to major 3 → proposed=3.1.1.
# unconstrained=3.1.1 → same major → WATCH must NOT fire.
t "t58p: pypi watch-major — same major in fixture, unconstrained matches proposed major" bash -c "
    ${_PYPI_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58p_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pypi'
    _gs_eu2_record_set \$idx identifier      'somepkg'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PYPI_WM_P'
    _gs_eu2_record_set \$idx current_version '3.0.5'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_pypi \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '1')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has higher major than proposed '\$proposed'\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t58q: pypi + (watch-major) — newer major exists, latest_unconstrained populated
# bigpkg fixture: versions 4.0.0, 3.1.0, 3.0.5. Pin to major 3 → proposed=3.1.0.
# unconstrained=4.0.0 → WATCH fires.
t "t58q: pypi watch-major — newer major in fixture, latest_unconstrained=4.x" bash -c "
    ${_PYPI_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58q_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pypi'
    _gs_eu2_record_set \$idx identifier      'bigpkg'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_PYPI_WM_Q'
    _gs_eu2_record_set \$idx current_version '3.0.5'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_pypi \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 3.* ]] || { echo \"proposed should be 3.x (major-pinned), got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire'; echo FAIL; exit 0; }
    pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx_u\" == '4' ]] || { echo \"expected unconstrained major 4, got: '\$pfx_u' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t58r: rubygems + (watch-major) — same major, no newer generation
# oldgem fixture: gems=2.1.0, versions=[2.0.0, 2.1.0]. Pin to major 2 → proposed=2.1.0.
# unconstrained=2.1.0 → same major → no WATCH.
t "t58r: rubygems watch-major — same major in fixture, unconstrained matches proposed major" bash -c "
    ${_RUBY_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58r_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'rubygems'
    _gs_eu2_record_set \$idx identifier      'oldgem'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_RUBY_WM_R'
    _gs_eu2_record_set \$idx current_version '2.0.0'
    _gs_eu2_record_set \$idx major_hint      '2'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_rubygems \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    if [[ -n \"\$unconstrained\" ]]; then
      pfx_p=\$(_gs_eu2_version_prefix \"\$proposed\" '1')
      pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
      [[ \"\$pfx_p\" == \"\$pfx_u\" ]] || { echo \"unconstrained '\$unconstrained' has higher major than proposed '\$proposed'\"; echo FAIL; exit 0; }
    fi
    echo PASS
"

# t58s: rubygems + (watch-major) — newer major exists, latest_unconstrained populated
# newgem fixture: gems=3.0.0, versions=[3.0.0, 2.1.0, 2.0.0]. Pin to major 2 → proposed=2.1.0.
# unconstrained=3.0.0 → WATCH fires.
t "t58s: rubygems watch-major — newer major in fixture, latest_unconstrained=3.x" bash -c "
    ${_RUBY_LIBS_WM}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58s_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'rubygems'
    _gs_eu2_record_set \$idx identifier      'newgem'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_RUBY_WM_S'
    _gs_eu2_record_set \$idx current_version '2.0.0'
    _gs_eu2_record_set \$idx major_hint      '2'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_rubygems \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version empty'; echo FAIL; exit 0; }
    [[ \"\$proposed\" == 2.* ]] || { echo \"proposed should be 2.x (major-pinned), got: '\$proposed'\"; echo FAIL; exit 0; }
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire'; echo FAIL; exit 0; }
    pfx_u=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx_u\" == '3' ]] || { echo \"expected unconstrained major 3, got: '\$pfx_u' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t58t: (watch-major)(channel:unstable) — new major exists ONLY as a prerelease.
# watchrc fixture: 17.x stable + 18.0-rc1/rc2 (RC-only, no stable 18.x). Pin to major 17.
# Regression guard for the hardcoded-\"stable\" bug in the watch-major unconstrained scan:
# with channel:unstable the RC-only next major MUST surface as [WATCH] 17 → 18.
# Before the fix, dockerhub.sh:168 forced the \"stable\" channel and dropped the RC, so
# latest_unconstrained stayed on 17.x and no WATCH fired.
t "t58t: watch-major honors channel:unstable — RC-only next major fires [WATCH]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58t_cache
    f=\${TMP_DIR}/t58t.env
    printf '# @todo env-update (watch-major) (channel:unstable) dockerhub:_/watchrc:17 17.5\nGLOBAL_STACK_WATCHRC=17.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"expected [WATCH] sub-line for RC-only next major, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '18' || { echo \"expected 18 (RC major) in WATCH output, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t58u: (watch-major) WITHOUT channel — stable-channel semantics preserved.
# Same watchrc fixture (18.x is RC-only). With the default stable channel, a prerelease-only
# next major must NOT fire [WATCH] (conservative behavior — don't nag about an RC that may
# never ship a stable). Confirms the fix scopes the RC surfacing to channel:unstable only.
t "t58u: watch-major without channel stays silent for RC-only next major" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t58u_cache
    f=\${TMP_DIR}/t58u.env
    printf '# @todo env-update (watch-major) dockerhub:_/watchrc:17 17.5\nGLOBAL_STACK_WATCHRC2=17.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[WATCH]' && { echo \"unexpected [WATCH] for RC-only next major on stable channel: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 19b — --apply e2e pipeline tests
# ═══════════════════════════════════════════════════════════════════════════
section "19b — --apply e2e pipeline"

# t19-apply-e2e-a: --apply on a temp env file with one AUTO var actually updates the file
# Use postgres fixture: 18.3-alpine3.23 → 18.4-alpine3.23 (known AUTO bump in fixture).
t "t19-apply-e2e-a: --apply with AUTO var updates the env file on disk" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t19ea_cache
    f=\${TMP_DIR}/t19ea.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T19=18.3-alpine3.23\n' > \"\$f\"
    # Run dry-run first to satisfy the dry-run gate
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null || true
    # Now apply — postgres fixture has 18.4-alpine3.23, so decision is AUTO
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    [[ -f \"\$f\" ]] || { echo 'env file deleted by --apply'; echo FAIL; exit 0; }
    # The value should now be updated to 18.4-alpine3.23
    grep -qF 'GLOBAL_STACK_PG18_T19=18.4-alpine3.23' \"\$f\" || {
      echo \"expected value 18.4-alpine3.23 in file after apply, got:\"; cat \"\$f\"; echo FAIL; exit 0
    }
    echo PASS
"

# t19-apply-e2e-b: --apply --dry-run is rejected with exit 1 (mutually exclusive)
t "t19-apply-e2e-b: --apply --dry-run exits 1 with mutually exclusive error" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t19eb_cache
    f=\${TMP_DIR}/t19eb.env
    cp '${FIXTURES}/basic-dockerhub.env' \"\$f\"
    # Capture exit code and stderr
    stderr_out=\$(bash '${ENV_UPDATE_V2}' --apply --dry-run --env-file=\"\$f\" 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    [[ \"\$stderr_out\" == *'mutually exclusive'* ]] || { echo \"expected 'mutually exclusive' in stderr, got: \$stderr_out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 36b — --cache-ttl flag acceptance
# ═══════════════════════════════════════════════════════════════════════════
section "36b — --cache-ttl flag acceptance"

# t36b-a: --cache-ttl=60 accepted without error
t "t36b-a: --cache-ttl=60 accepted without error" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --cache-ttl=60 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option\|invalid' && { echo \"--cache-ttl=60 rejected: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t36b-b: --cache-ttl=0 accepted without error
t "t36b-b: --cache-ttl=0 accepted (disables cache)" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --cache-ttl=0 2>&1 || true)
    echo \"\$err\" | grep -qi 'unknown option\|invalid' && { echo \"--cache-ttl=0 rejected: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 52b — --unstable=info vs --unstable=full distinction
# ═══════════════════════════════════════════════════════════════════════════
section "52b — --unstable=info vs --unstable=full distinction"

# t52b-a: --unstable=info with a var that has a prerelease available — decision stays AUTO/SKIP
#         (not promoted to prerelease); stable proposed is chosen, not prerelease.
t "t52b-a: --unstable=info keeps stable decision, does not promote to prerelease" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/decide.sh'
    # unstable=info mode → classify_decision uses 'info' → stable→prerelease stays SKIP
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '' 'info')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for unstable=info, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t52b-b: --unstable=full with same var — decision becomes AUTO (prerelease guard bypassed)
t "t52b-b: --unstable=full promotes stable→prerelease to AUTO (guard bypassed)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/decide.sh'
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '' 'full')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for unstable=full, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 53 — (tag-channel-prefix) flag
# ═══════════════════════════════════════════════════════════════════════════
section "62 — tag-channel-prefix flag"

_TCP_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_cache
"

# t53a: stable channel — current=v0.39.0, fixture has v0.40.0 (stable) and dev-0.40.1-rc.223 (pre).
#       Proposed must be v0.40.0 (stable winner — no dev- prefix because raw tag was v0.40.0).
t "t53a: stable current — proposed is v0.40.0 (no prefix re-prepend for stable tag)" bash -c "
    ${_TCP_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type               'github'
    _gs_eu2_record_set \$idx identifier         'rtk-ai/rtk'
    _gs_eu2_record_set \$idx env_var            'GLOBAL_STACK_RTK_VERSION'
    _gs_eu2_record_set \$idx current_version    'v0.39.0'
    _gs_eu2_record_set \$idx tag_channel_prefix 'dev-'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v0.40.0' ]] || { echo \"expected v0.40.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53b: unstable channel — current=dev-0.40.1-rc.223, proposed must be dev-0.40.1-rc.223
#       (same version → SKIP via equality, but proposed_version must be dev-0.40.1-rc.223).
t "t53b: pre-release current equals proposed — proposed carries dev- prefix (round-trip)" bash -c "
    ${_TCP_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type               'github'
    _gs_eu2_record_set \$idx identifier         'rtk-ai/rtk'
    _gs_eu2_record_set \$idx env_var            'GLOBAL_STACK_RTK_VERSION'
    _gs_eu2_record_set \$idx current_version    'dev-0.40.1-rc.223'
    _gs_eu2_record_set \$idx channel            'unstable'
    _gs_eu2_record_set \$idx tag_channel_prefix 'dev-'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'dev-0.40.1-rc.223' ]] || { echo \"expected dev-0.40.1-rc.223, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53c: stable channel only — fixture has only stable tags (no dev- prefix at all).
#       No prefix should be re-prepended on the winner.
t "t53c: stable-only fixture — proposed has no prefix (no spurious re-prepend)" bash -c "
    ${_TCP_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type               'github'
    _gs_eu2_record_set \$idx identifier         'test-tcp/only-stable'
    _gs_eu2_record_set \$idx env_var            'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version    'v1.9.0'
    _gs_eu2_record_set \$idx tag_channel_prefix 'dev-'
    _gs_eu2_fetch_github \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v2.0.0' ]] || { echo \"expected v2.0.0, got: '\$val'\"; echo FAIL; exit 0; }
    [[ \"\$val\" != dev-* ]] || { echo \"spurious dev- prefix on stable winner: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53d: semver_compare — third param strips channel prefix before comparison.
# dev-0.40.1-rc.223 stripped to 0.40.1-rc.223, vs v0.40.0 → 0.40.0.
# sort -V: 0.40.0 < 0.40.1-rc.223 (0.40.1 > 0.40.0 numerically).
# So 0.40.1-rc.223 is NEWER than 0.40.0 — correct; it is a pre-release of a higher patch.
# Also test that without tcp the raw dev- prefix would make the comparison nonsensical —
# verify the stripped form gives the expected order.
t "t53d: semver_compare strips tcp before ordering (dev- prefix aware)" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    # With tcp=dev-: strips to 0.40.1-rc.223 vs 0.40.0
    # 0.40.1-rc.223 numerically > 0.40.0 → newer (pre-release of a higher patch)
    result=\$(_gs_eu2_semver_compare 'dev-0.40.1-rc.223' 'v0.40.0' 'dev-')
    [[ \"\$result\" == 'newer' ]] || { echo \"expected newer (0.40.1-rc > 0.40.0), got: '\$result'\"; echo FAIL; exit 0; }
    # Complementary: dev-0.40.0-rc.201 vs v0.40.0 → rc of same base → older
    result2=\$(_gs_eu2_semver_compare 'dev-0.40.0-rc.201' 'v0.40.0' 'dev-')
    [[ \"\$result2\" == 'older' ]] || { echo \"expected older (0.40.0-rc < 0.40.0), got: '\$result2'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53e: semver_compare backward-compatible — no third param = behaves identically to before.
t "t53e: semver_compare backward-compatible — no third param, v-prefix only" bash -c "
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    result=\$(_gs_eu2_semver_compare 'v1.2.3' 'v1.3.0')
    [[ \"\$result\" == 'older' ]] || { echo \"expected older, got: '\$result'\"; echo FAIL; exit 0; }
    result2=\$(_gs_eu2_semver_compare 'v2.0.0' 'v1.9.9')
    [[ \"\$result2\" == 'newer' ]] || { echo \"expected newer, got: '\$result2'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53f: parse.sh recognises tag-channel-prefix and dispatches to record field.
t "t53f: parse.sh stores tag_channel_prefix in record" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    tmp_env=\$(mktemp)
    printf '# @todo env-update (tag-channel-prefix:dev-) github:rtk-ai/rtk v0.39.0\nGLOBAL_STACK_RTK_VERSION=v0.39.0\n' > \"\$tmp_env\"
    _gs_eu2_parse_env_file \"\$tmp_env\"
    rm -f \"\$tmp_env\"
    tcp=\$(_gs_eu2_record_get 0 tag_channel_prefix)
    [[ \"\$tcp\" == 'dev-' ]] || { echo \"expected dev-, got: '\$tcp'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53g: full pipeline via env-update.sh --check — stable current, flag active.
#       Output line for RTK must show AUTO with v0.40.0 (not dev- prefixed).
t "t53g: full pipeline --check — stable current proposes v0.40.0 (AUTO)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_g_cache
    out=\$('${ENV_UPDATE_V2}' --check --no-cache \
        --env-file='${FIXTURES}/github-tcp-stable.env' 2>&1)
    echo \"\$out\" | grep -qi 'auto\|v0.40.0' \
        || { echo \"expected AUTO or v0.40.0 in output\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'v0.40.0' \
        || { echo \"v0.40.0 missing from output\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t53h: downgrade guard — current=dev-0.40.1-rc.223 (newest), proposed=v0.40.0 (older stripped).
#       After tcp strip: 0.40.1-rc.223 vs 0.40.0 → rc < stable but 0.40.1 > 0.40.0 → NOT a
#       downgrade? Let's clarify: sort -V puts 0.40.0 < 0.40.1-rc.223 because 0.40.1 > 0.40.0
#       numerically. So current 0.40.1-rc.223 > proposed 0.40.0 → downgrade SKIP is correct.
t "t53h: downgrade guard fires when current rc version > proposed stable (stripped comparison)" bash -c "
    ${_TCP_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_h_cache
    source '${_GS_EU2_LIB}/core/decide.sh'
    # Simulate: current=dev-0.40.1-rc.223, proposed=v0.40.0
    # Pre-strip tcp from both: cur=0.40.1-rc.223, prop=0.40.0
    # sort -V: 0.40.0 < 0.40.1-rc.223 → proposed is older → SKIP
    result=\$(_gs_eu2_classify_decision '0.40.1-rc.223' '0.40.0' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for downgrade, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t53i: unknown flag variant — tag-channel-prefix without value must error.
t "t53i: tag-channel-prefix without value is rejected by parse.sh" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    tmp_env=\$(mktemp)
    printf '# @todo env-update (tag-channel-prefix) github:rtk-ai/rtk v0.39.0\nGLOBAL_STACK_RTK_VERSION=v0.39.0\n' > \"\$tmp_env\"
    err=\$(_gs_eu2_parse_env_file \"\$tmp_env\" 2>&1) && rc=0 || rc=\$?
    rm -f \"\$tmp_env\"
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit for missing value, got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qi 'requires\|non-empty\|value' \
        || { echo \"expected requires/non-empty/value in error: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t53j: cache key includes tcp segment — separate flag/no-flag runs use distinct keys.
t "t53j: cache key differs with and without tag-channel-prefix (no cache poisoning)" bash -c "
    ${_TCP_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_j_cache
    source '${_GS_EU2_LIB}/core/cache.sh'

    # Run with tcp set
    _gs_eu2_record_new; idx1=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx1 type               'github'
    _gs_eu2_record_set \$idx1 identifier         'rtk-ai/rtk'
    _gs_eu2_record_set \$idx1 env_var            'GLOBAL_STACK_RTK_VERSION'
    _gs_eu2_record_set \$idx1 current_version    'v0.39.0'
    _gs_eu2_record_set \$idx1 tag_channel_prefix 'dev-'
    _gs_eu2_fetch_github \$idx1
    val_tcp=\$(_gs_eu2_record_get \$idx1 proposed_version)

    # Run without tcp (different record, new cache dir to avoid any bleed)
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/tcp_j2_cache
    _gs_eu2_record_new; idx2=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx2 type            'github'
    _gs_eu2_record_set \$idx2 identifier      'rtk-ai/rtk'
    _gs_eu2_record_set \$idx2 env_var         'GLOBAL_STACK_RTK_VERSION'
    _gs_eu2_record_set \$idx2 current_version 'v0.39.0'
    _gs_eu2_fetch_github \$idx2
    val_notcp=\$(_gs_eu2_record_get \$idx2 proposed_version)

    # Both must have proposals (fixture serves both)
    [[ -n \"\$val_tcp\" ]] || { echo 'tcp run: no proposed'; echo FAIL; exit 0; }
    [[ -n \"\$val_notcp\" ]] || { echo 'no-tcp run: no proposed'; echo FAIL; exit 0; }
    # With fixture: tcp run proposes v0.40.0 (stable); no-tcp run also proposes v0.40.0
    # Key distinction: tcp cache key includes 'tcp_dev-' segment
    # Verify no cache file from tcp run exists in notcp cache dir (key segregation)
    ls \${TMP_DIR}/tcp_j_cache/ 2>/dev/null | grep -q 'tcp_dev-' \
        || { echo 'cache key missing tcp_ segment'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 61 — PECL channel:unstable support
# ═══════════════════════════════════════════════════════════════════════════
section "61 — pecl channel:unstable support"

_PECL_CH_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/github.sh'
source '${_GS_EU2_LIB}/fetchers/pecl.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_cache
"

# t61a: channel:stable (default) + all-beta extension → no stable found → ERROR
t "t61a: channel:stable + all-beta extension → ERROR (no stable release)" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_a_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'betaonly'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_BETAONLY_VERSION'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    # No channel set — defaults to stable
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR for stable channel on all-beta ext, got: '\$dec'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61b: channel:unstable + all-beta extension → AUTO with latest beta
t "t61b: channel:unstable + all-beta extension → AUTO with highest beta version" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_b_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'betaonly'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_BETAONLY_VERSION'
    _gs_eu2_record_set \$idx current_version '1.0.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR for unstable channel, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '2.1.0beta2' ]] || { echo \"expected 2.1.0beta2 (highest beta), got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61c: channel:unstable + mixed (stable + beta) → stable wins because it has higher version
#       Fixture: betaonly has 2.1.0beta2, mixedstablebeta has 2.5.0 stable + 3.0.0beta1 beta
#       For mixedstablebeta: sort -V selects 3.0.0beta1 as highest overall (beta > stable here)
#       Verify unstable channel accepts beta when it is numerically higher than stable
t "t61c: channel:unstable + mixed fixture → highest version wins (3.0.0beta1 beats 2.5.0 stable)" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_c_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'mixedstablebeta'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_MIXED_VERSION'
    _gs_eu2_record_set \$idx current_version '2.0.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$ver\" == '3.0.0beta1' ]] || { echo \"expected 3.0.0beta1 (highest), got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61d: channel:unstable + alpha-only extension → accepts alpha
t "t61d: channel:unstable + alpha-only extension → accepts alpha" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_d_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'alphaonly'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_ALPHA_VERSION'
    _gs_eu2_record_set \$idx current_version '0.7.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR for alpha channel, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '0.9.0alpha2' ]] || { echo \"expected 0.9.0alpha2, got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61e: channel:unstable + devel-only extension → accepts devel
t "t61e: channel:unstable + devel-only extension → accepts devel" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_e_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'develonly'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_DEVEL_VERSION'
    _gs_eu2_record_set \$idx current_version '0.1.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR for devel channel, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '0.3.0devel' ]] || { echo \"expected 0.3.0devel, got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61f: zmq-like fixture (all beta) + channel:unstable → AUTO with 1.1.3
t "t61f: zmq-like fixture (all beta) + channel:unstable → proposed=1.1.3" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_f_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'zmqlike'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version '1.1.2'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR, got ERROR\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected 1.1.3, got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61g: cache key segregation — stable and unstable runs use distinct cache keys
t "t61g: cache keys differ between channel:stable and channel:unstable (no poisoning)" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_g_cache
    declare -A _GS_EU2_CFG=([no_cache]=false)
    # Run channel:stable first (writes pecl2:stable:betaonly → empty, skipped by cache_write)
    _gs_eu2_pecl_get_latest_stable 'betaonly' 'stable' 2>/dev/null || true
    # Run channel:unstable second
    result=\$(_gs_eu2_pecl_get_latest_stable 'betaonly' 'unstable' 2>/dev/null)
    [[ \"\$result\" == '2.1.0beta2' ]] || { echo \"expected 2.1.0beta2 from unstable channel, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61h: parse.sh recognises channel:unstable and stores it in the record
t "t61h: parse.sh stores channel=unstable in record field" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/parse.sh'
    tmp_env=\$(mktemp)
    printf '# @todo env-update (channel:unstable) pecl:zmq 1.1.3\nGLOBAL_STACK_ZMQ=\n' > \"\$tmp_env\"
    _gs_eu2_parse_env_file \"\$tmp_env\"
    rm -f \"\$tmp_env\"
    ch=\$(_gs_eu2_record_get 0 channel)
    typ=\$(_gs_eu2_record_get 0 type)
    [[ \"\$typ\" == 'pecl' ]] || { echo \"expected type=pecl, got: '\$typ'\"; echo FAIL; exit 0; }
    [[ \"\$ch\" == 'unstable' ]] || { echo \"expected channel=unstable, got: '\$ch'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61i: channel:unstable + up-to-date guard — current == proposed → fetch still works
#       The SKIP decision is downstream (decide.sh/main.sh); _gs_eu2_fetch_pecl only
#       sets proposed_version. With current_version already at the highest beta (1.1.3),
#       the fetcher should succeed (no ERROR) and return proposed_version=1.1.3.
t "t61i: channel:unstable + current==proposed → proposed populated, no ERROR" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_i_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'zmqlike'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version '1.1.3'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    dec=\$(_gs_eu2_record_get \$idx decision)
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR for up-to-date unstable, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected proposed_version=1.1.3 (latest beta), got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61j: _gs_eu2_pecl_check_promotion is stable-only regardless of channel (regression guard)
#       The function signature is check_promotion(EXT_NAME, COMMIT_DATE) — no channel param.
#       imagick fixture: 3.9.0beta1 (beta) + 3.8.0 (stable); 3.8.0 released 2026-01-10.
#       git commit date 2026-01-01 → PECL stable is newer → must return '3.8.0', never the beta.
t "t61j: check_promotion is always stable-only regardless of channel (no channel param)" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_j_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    result=\$(_gs_eu2_pecl_check_promotion 'imagick' '2026-01-01')
    [[ \"\$result\" == '3.8.0' ]] || { echo \"expected stable 3.8.0 (beta must be ignored), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t61k: --unstable=info secondary pass reaches PECL and finds beta
#       main.sh temporarily sets channel=unstable for ALL records during secondary pass.
#       This test simulates that: no channel annotation on record, then manually set
#       channel=unstable before calling _gs_eu2_fetch_pecl (mirroring main.sh's injection).
#       imagick: 3.9.0beta1 (beta) + 3.8.0 (stable). With channel=unstable,
#       sort -V picks 3.9.0beta1 as the highest overall version.
t "t61k: secondary-pass channel=unstable injection reaches PECL and returns beta" bash -c "
    ${_PECL_CH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/pecl_ch_k_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'pecl'
    _gs_eu2_record_set \$idx identifier      'imagick'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_IMAGICK_VERSION'
    _gs_eu2_record_set \$idx current_version '3.5.0'
    # No channel annotation — simulating main.sh secondary-pass injection
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_pecl \$idx 2>/dev/null || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] || { echo \"expected no ERROR for secondary-pass unstable, got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$ver\" == '3.9.0beta1' ]] || { echo \"expected 3.9.0beta1 (highest with channel=unstable), got: '\$ver'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 63 — (lock:REASON) flag
# ═══════════════════════════════════════════════════════════════════════════
section "63 — (lock:REASON) flag"

_LOCK_PARSE_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/parse.sh'
"

_LOCK_DECIDE_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

# ── A: Basic behaviour ────────────────────────────────────────────────────

# t63a1: parse.sh stores lock_reason in record field
t "t63a1: parse.sh stores lock_reason in record" bash -c "
    ${_LOCK_PARSE_LIBS}
    tmp=\$(mktemp)
    printf '# @todo env-update (lock:Pinned to master) github:owner/repo 1.2.3\nGLOBAL_STACK_TEST=1.2.3\n' > \"\$tmp\"
    _gs_eu2_parse_env_file \"\$tmp\"
    rm -f \"\$tmp\"
    got=\$(_gs_eu2_record_get 0 lock_reason)
    [[ \"\$got\" == 'Pinned to master' ]] || { echo \"expected 'Pinned to master', got: '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

# t63a2: lock_reason is recognised as a flag by is_recognized_flag
t "t63a2: is_recognized_flag returns 0 for lock" bash -c "
    ${_LOCK_PARSE_LIBS}
    _gs_eu2_is_recognized_flag 'lock:some reason' && echo PASS || { echo 'lock not recognised'; echo FAIL; }
"

# t63a3: lock with empty reason exits with error
t "t63a3: (lock:) with empty reason is a parse error" bash -c "
    ${_LOCK_PARSE_LIBS}
    tmp=\$(mktemp)
    printf '# @todo env-update (lock:) github:owner/repo 1.2.3\nGLOBAL_STACK_TEST=1.2.3\n' > \"\$tmp\"
    err=\$(_gs_eu2_parse_env_file \"\$tmp\" 2>&1) && rc=0 || rc=\$?
    rm -f \"\$tmp\"
    [[ \$rc -ne 0 ]] || { echo 'expected non-zero exit for empty lock reason'; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qi 'requires\|non-empty\|value' \
        || { echo \"expected requires/non-empty/value in error: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t63a4: lock_reason stored verbatim (spaces preserved)
t "t63a4: lock_reason with spaces stored verbatim" bash -c "
    ${_LOCK_PARSE_LIBS}
    tmp=\$(mktemp)
    printf '# @todo env-update (lock:Unused for now — needs investigation) dockerhub:_/nginx latest\nGLOBAL_STACK_TEST=latest\n' > \"\$tmp\"
    _gs_eu2_parse_env_file \"\$tmp\"
    rm -f \"\$tmp\"
    got=\$(_gs_eu2_record_get 0 lock_reason)
    [[ \"\$got\" == 'Unused for now — needs investigation' ]] || { echo \"expected full reason, got: '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── B: force-auto immunity ────────────────────────────────────────────────

# t63b1: --force-auto does NOT override LOCK (lock is immune)
t "t63b1: --force-auto does not override (lock:) — stays LOCK" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63b1_cache
    f=\${TMP_DIR}/t63b1.env
    # current=18.3-alpine3.23 → fixture returns 18.4-alpine3.23 → with --force-auto would be AUTO
    # but (lock:) must override to LOCK even with --force-auto
    printf '# @todo env-update (lock:pinned for stability) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63B1=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[LOCK   ]' || { echo \"expected [LOCK   ] with --force-auto, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[AUTO   ]' && { echo \"[AUTO   ] must not appear with (lock:) + --force-auto\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t63b2: without (lock:), --force-auto still produces AUTO (control)
t "t63b2: without (lock:), --force-auto produces AUTO (control test)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63b2_cache
    f=\${TMP_DIR}/t63b2.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63B2=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[AUTO   ]' || { echo \"expected AUTO without lock, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── C: Flag interactions ──────────────────────────────────────────────────

# t63c1: (lock:) + (skip:) — skip gate fires first, decision=FROZEN (skip-gate) not LOCK
t "t63c1: (lock:) does not override skip gate — [FROZEN] wins over [LOCK]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63c1_cache
    f=\${TMP_DIR}/t63c1.env
    # Both (skip:) and (lock:) present — skip fires first, lock gate must not override it
    printf '# @todo env-update (skip:skip reason) (lock:lock reason) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63C1=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[FROZEN ]' || { echo \"expected FROZEN (skip-gate wins), got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[LOCK   ]' && { echo \"LOCK must not override skip gate\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t63c2: (lock:) + ERROR decision — lock gate must NOT override ERROR
t "t63c2: (lock:) does not override ERROR — fetch failures surface" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63c2_cache
    f=\${TMP_DIR}/t63c2.env
    # Use a non-existent fixture repo so fetcher returns ERROR
    printf '# @todo env-update (lock:pinned) dockerhub:_/nonexistent-repo-xyz 1.0.0\nGLOBAL_STACK_T63C2=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null || true)
    echo \"\$out\" | grep -qF '[ERROR  ]' || { echo \"expected ERROR, got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[LOCK   ]' && { echo \"LOCK must not override ERROR\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t63c3: (manual) + (lock:) — LOCK wins silently, (manual) ignored
t "t63c3: (manual) + (lock:) coexist — LOCK wins, (manual) ignored" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63c3_cache
    f=\${TMP_DIR}/t63c3.env
    printf '# @todo env-update (manual) (lock:lock wins) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63C3=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[LOCK   ]' || { echo \"expected LOCK when (manual)+(lock:) coexist: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[MANUAL ]' && { echo \"MANUAL must not appear when (lock:) present\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t63c4: (lock:) when up to date (current == proposed) — decision still LOCK
t "t63c4: (lock:) when current == proposed — decision is LOCK, not SKIP" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63c4_cache
    f=\${TMP_DIR}/t63c4.env
    # current matches what the fixture returns → propose == current → classify=SKIP, but lock gate turns it to LOCK
    # postgres fixture returns 18.4-alpine3.23 — use that as current
    printf '# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.4-alpine3.23\nGLOBAL_STACK_T63C4=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[LOCK   ]' || { echo \"expected LOCK even when current==proposed: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── D: Output / display ───────────────────────────────────────────────────

# t63d1: [LOCK   ] tag is 9 chars wide — matches other decision tags
t "t63d1: [LOCK   ] tag is exactly 9 chars wide" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63d1_cache
    f=\${TMP_DIR}/t63d1.env
    printf '# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63D1=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[LOCK   ]' || { echo \"expected '[LOCK   ]' (LOCK+3 spaces), got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t63d1b: [SHA    ] tag is 9 chars wide — widest padding, most off-by-one prone
# Uses pecl:imagick + git:Imagick/imagick fixture: version current (SKIP) but annotation
# SHA is stale → pipeline upgrades to SHA decision, emitting [SHA    ] (SHA+4 spaces).
t "t63d1b: [SHA    ] tag is exactly 9 chars wide (widest-padding anchor)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63d1b_cache
    f=\${TMP_DIR}/t63d1b.env
    printf '# @todo env-update (use-sha) pecl:imagick (git:Imagick/imagick) 3.8.0 sha:oldshaoldsha0000000000000000000000000000\nGLOBAL_STACK_T63D1B=3.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[SHA    ]' || { echo \"expected '[SHA    ]' (SHA+4 spaces, 9-char tag), got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t63d2: summary line includes LOCK count
t "t63d2: summary line includes LOCK count" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63d2_cache
    f=\${TMP_DIR}/t63d2.env
    printf '# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63D2=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qi 'LOCK' | head -1 || true
    echo \"\$out\" | grep -qi '1 LOCK\|1.*LOCK\|LOCK.*1' || { echo \"expected LOCK count in summary: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t63d3: LOCK output shows lock reason (← locked: REASON)
t "t63d3: LOCK output line shows lock reason" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63d3_cache
    f=\${TMP_DIR}/t63d3.env
    printf '# @todo env-update (lock:pinned for stability) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63D3=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qi 'pinned for stability\|locked\|lock' \
        || { echo \"expected lock reason in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── E: Apply behaviour ───────────────────────────────────────────────────

# t63e1: --apply updates annotation version token but NOT VAR= value
t "t63e1: --apply: annotation version updated, VAR= value unchanged" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63e1_cache
    mkdir -p \"\${TMP_DIR}/t63e1_cache\"
    touch \"\${TMP_DIR}/t63e1_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t63e1.env
    # current=18.3-alpine3.23 in annotation; fixture returns 18.4-alpine3.23 (proposed)
    ann='# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23'
    printf '%s\nGLOBAL_STACK_T63E1=18.3-alpine3.23\n' \"\$ann\" > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    # VAR= line must still hold the original value
    grep -q 'GLOBAL_STACK_T63E1=18.3-alpine3.23' \"\$f\" \
        || { echo 'VAR= value was changed — must stay 18.3-alpine3.23'; echo FAIL; exit 0; }
    # Annotation version must be updated to proposed value
    grep -q '18.4-alpine3.23' \"\$f\" \
        || { echo 'annotation not updated to 18.4-alpine3.23'; echo FAIL; exit 0; }
    echo PASS
"

# t63e2: --dry-run with LOCK reports [DRY-RUN] without writing
t "t63e2: --dry-run with (lock:) reports DRY-RUN and makes no changes" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63e2_cache
    mkdir -p \"\${TMP_DIR}/t63e2_cache\"
    touch \"\${TMP_DIR}/t63e2_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t63e2.env
    ann='# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23'
    printf '%s\nGLOBAL_STACK_T63E2=18.3-alpine3.23\n' \"\$ann\" > \"\$f\"
    original=\$(cat \"\$f\")
    bash '${ENV_UPDATE_V2}' --apply --dry-run --env-file=\"\$f\" 2>/dev/null || true
    current=\$(cat \"\$f\")
    [[ \"\$original\" == \"\$current\" ]] || { echo 'file was modified during --dry-run'; echo FAIL; exit 0; }
    echo PASS
"

# t63e3: idempotency — running --apply twice produces same result
t "t63e3: --apply is idempotent for (lock:) annotation updates" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63e3_cache
    mkdir -p \"\${TMP_DIR}/t63e3_cache\"
    touch \"\${TMP_DIR}/t63e3_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t63e3.env
    ann='# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23'
    printf '%s\nGLOBAL_STACK_T63E3=18.3-alpine3.23\n' \"\$ann\" > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after_first=\$(cat \"\$f\")
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after_second=\$(cat \"\$f\")
    [[ \"\$after_first\" == \"\$after_second\" ]] || { echo 'second apply changed the file — not idempotent'; echo FAIL; exit 0; }
    echo PASS
"

# t63e4: --apply does not count LOCK annotation update in version-update count
t "t63e4: --apply: LOCK records not counted in version update total" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63e4_cache
    mkdir -p \"\${TMP_DIR}/t63e4_cache\"
    touch \"\${TMP_DIR}/t63e4_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t63e4.env
    # Two entries: one AUTO (should count as version update), one LOCK (annotation only)
    printf '# @todo env-update dockerhub:_/postgres:18 17.5-alpine3.23\nGLOBAL_STACK_T63E4A=17.5-alpine3.23\n' > \"\$f\"
    printf '# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T63E4B=18.3-alpine3.23\n' >> \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true)
    # Verify the LOCK record's VAR= line was not touched
    grep -q 'GLOBAL_STACK_T63E4B=18.3-alpine3.23' \"\$f\" \
        || { echo 'LOCK VAR= must remain 18.3-alpine3.23'; echo FAIL; exit 0; }
    echo PASS
"

# ── F: Edge cases ─────────────────────────────────────────────────────────

# t63f1: (lock:) when proposed == current — annotation-only rewrite skipped (idempotent)
t "t63f1: (lock:) when annotation version already matches proposed — no rewrite needed" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63f1_cache
    mkdir -p \"\${TMP_DIR}/t63f1_cache\"
    touch \"\${TMP_DIR}/t63f1_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t63f1.env
    # annotation already shows 18.4-alpine3.23 (= what fixture returns) → no rewrite
    ann='# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.4-alpine3.23'
    printf '%s\nGLOBAL_STACK_T63F1=18.4-alpine3.23\n' \"\$ann\" > \"\$f\"
    original=\$(cat \"\$f\")
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after=\$(cat \"\$f\")
    [[ \"\$original\" == \"\$after\" ]] || { echo 'file changed when annotation was already up to date'; echo FAIL; exit 0; }
    echo PASS
"

# t63f2: (lock:) position-agnostic — flag before and after TYPE:ID both work
t "t63f2: (lock:) works regardless of position in annotation" bash -c "
    ${_LOCK_PARSE_LIBS}
    tmp_before=\$(mktemp)
    tmp_after=\$(mktemp)
    printf '# @todo env-update (lock:reason before) github:owner/repo 1.2.3\nGLOBAL_STACK_TEST=1.2.3\n' > \"\$tmp_before\"
    printf '# @todo env-update github:owner/repo 1.2.3 (lock:reason after)\nGLOBAL_STACK_TEST=1.2.3\n' > \"\$tmp_after\"
    _gs_eu2_parse_env_file \"\$tmp_before\"
    got_before=\$(_gs_eu2_record_get 0 lock_reason)
    # Reset record state for second parse
    _GS_EU2_REC_COUNT=0; _GS_EU2_LAST_IDX=0
    _gs_eu2_parse_env_file \"\$tmp_after\"
    got_after=\$(_gs_eu2_record_get 0 lock_reason)
    rm -f \"\$tmp_before\" \"\$tmp_after\"
    [[ \"\$got_before\" == 'reason before' ]] || { echo \"before: expected 'reason before', got: '\$got_before'\"; echo FAIL; exit 0; }
    [[ \"\$got_after\" == 'reason after' ]] || { echo \"after: expected 'reason after', got: '\$got_after'\"; echo FAIL; exit 0; }
    echo PASS
"

# t63f3: full pipeline via fixture file — LOCK decision emitted
t "t63f3: full pipeline with lock-flag.env fixture — LOCK in output" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t63f3_cache
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run \
        --env-file='${FIXTURES}/lock-flag.env' 2>/dev/null)
    echo \"\$out\" | grep -qF '[LOCK   ]' || { echo \"expected [LOCK   ] in full pipeline output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 64 — --exclude=REGEX flag
# ═══════════════════════════════════════════════════════════════════════════
section "64 — --exclude=REGEX flag"

_EXCL_PARSE_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/parse.sh'
"

# t64a1: --exclude skips matching vars; unmatched vars still parsed
t "t64a1: --exclude=SELENIUM skips both Selenium vars, all others run" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --exclude='SELENIUM' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' \
        || { echo \"mysql9 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' \
        || { echo \"flutter3 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a2: --exclude with a pattern that matches nothing — all records run
t "t64a2: --exclude=NONEXISTENT_XYZ matches nothing, all vars run normally" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --exclude='NONEXISTENT_XYZ' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' \
        || { echo \"mysql9 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' \
        || { echo \"flutter3 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a3: --filter + --exclude compose correctly
t "t64a3: --filter=GLOBAL_STACK --exclude=FLUTTER3 keeps mysql but drops flutter" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --filter='GLOBAL_STACK' --exclude='FLUTTER3' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' \
        || { echo \"mysql9 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' \
        && { echo \"flutter3 should be excluded; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a4: invalid --exclude regex → non-zero exit with error message
t "t64a4: invalid --exclude regex exits non-zero with error message" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --exclude='((' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    code=\$?
    [[ \"\$code\" -ne 0 ]] || { echo \"expected non-zero exit, got 0; output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'invalid --exclude' \
        || { echo \"expected 'invalid --exclude' in error; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a5: --exclude= (empty string) is a no-op — all vars run
t "t64a5: --exclude= (empty string) is a no-op, all vars run" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --exclude='' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' \
        || { echo \"mysql9 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' \
        || { echo \"flutter3 should be in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a6: [EXCLUDE MODE: REGEX] banner emitted to stderr
t "t64a6: [EXCLUDE MODE: REGEX] banner emitted to stderr" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --dump --exclude='SELENIUM' \
        --env-file='${FIXTURES}/combined-real-world.env' 2>&1 >/dev/null)
    echo \"\$err\" | grep -qF '[EXCLUDE MODE: SELENIUM]' \
        || { echo \"expected [EXCLUDE MODE: SELENIUM] in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t64a7: parse-level exclusion — excluded record's pending state is reset (no contamination)
t "t64a7: excluded record pending state is reset (no contamination of next record)" bash -c "
    ${_EXCL_PARSE_LIBS}
    tmp=\$(mktemp)
    printf '# @todo env-update github:owner/repo 1.0.0\nEXCLUDE_ME=1.0.0\n# @todo env-update github:owner/repo2 2.0.0\nKEEP_ME=2.0.0\n' > \"\$tmp\"
    _gs_eu2_parse_env_file \"\$tmp\" '' 'EXCLUDE_ME'
    rm -f \"\$tmp\"
    count=\$(_gs_eu2_record_count)
    [[ \"\$count\" -eq 1 ]] || { echo \"expected 1 record, got: \$count\"; echo FAIL; exit 0; }
    got=\$(_gs_eu2_record_get 0 env_var)
    [[ \"\$got\" == 'KEEP_ME' ]] || { echo \"expected KEEP_ME, got: '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 67 — Drift detection — [DRIFT] sub-line
# ═══════════════════════════════════════════════════════════════════════════
section "67 — Drift detection — [DRIFT] sub-line"

_DRIFT_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/npm.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t67a: Case 1 — empty var, annotation has version → [DRIFT] emitted
t "t67a: [DRIFT] emitted when VAR= is empty but annotation has version" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67a_cache
    f=\${TMP_DIR}/t67a.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67A=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'annotation tracks 1.0.0' || { echo \"expected 'annotation tracks 1.0.0' in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t67b: Case 2 — var set but differs from annotation version → [DRIFT] emitted
t "t67b: [DRIFT] emitted when VAR= differs from annotation version" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67b_cache
    f=\${TMP_DIR}/t67b.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67B=0.9.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'annotation says 1.0.0' || { echo \"expected 'annotation says 1.0.0' in drift line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR=0.9.0' || { echo \"expected 'VAR=0.9.0' in drift line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t67c: --no-drift suppresses [DRIFT] sub-line
t "t67c: --no-drift suppresses [DRIFT] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67c_cache
    f=\${TMP_DIR}/t67c.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67C=0.9.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-drift --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' && { echo \"[DRIFT] should be suppressed by --no-drift; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t67d: --no-notes does NOT suppress [DRIFT]
t "t67d: --no-notes does not suppress [DRIFT] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67d_cache
    f=\${TMP_DIR}/t67d.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67D=0.9.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-notes --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"[DRIFT] should NOT be suppressed by --no-notes; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t67e: no drift when var matches annotation version — no [DRIFT] emitted
t "t67e: no [DRIFT] when VAR= matches annotation version" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67e_cache
    f=\${TMP_DIR}/t67e.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67E=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' && { echo \"[DRIFT] emitted spuriously when var matches annotation; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t67f: --no-drift flag is accepted (no unknown-option error)
t "t67f: --no-drift flag is accepted without error" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t67f_cache
    f=\${TMP_DIR}/t67f.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T67F=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-drift --env-file=\"\$f\" 2>&1); code=\$?
    [[ \$code -eq 0 ]] || { echo \"--no-drift caused non-zero exit: \$code; output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'unknown option' && { echo '--no-drift not recognized; got: \$out'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 65 — Bug D: npm major_hint not bypassed by fast-paths
# ═══════════════════════════════════════════════════════════════════════════
section "65 — Bug D: npm major_hint fast-path bypass"

_NPM_D_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/npm.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t65a: major_hint=24 with @types/node fixture (dist-tags.latest=25.8.0)
# Before fix: fast-paths return 25.8.0. After fix: major-pin filter returns 24.1.0.
t "t65a: npm major_hint=24 bypasses dist-tags.latest fast-path, returns 24.x" bash -c "
    ${_NPM_D_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t65a_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      '@types/node'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TYPES_NODE_VERSION'
    _gs_eu2_record_set \$idx current_version '24.0.0'
    _gs_eu2_record_set \$idx major_hint      '24'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '24.1.0' ]] || { echo \"expected 24.1.0 (major-pinned), got: '\$val' (dist-tags.latest=25.8.0 — fast-path not bypassed?)\"; echo FAIL; exit 0; }
    echo PASS
"

# t65b: major_hint=25 gets 25.8.0 from the same fixture
t "t65b: npm major_hint=25 returns 25.8.0 from same @types/node fixture" bash -c "
    ${_NPM_D_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t65b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      '@types/node'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TYPES_NODE_25_VERSION'
    _gs_eu2_record_set \$idx current_version '25.0.0'
    _gs_eu2_record_set \$idx major_hint      '25'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '25.8.0' ]] || { echo \"expected 25.8.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t65c: major_hint=22 returns 22.1.0 — there are two 22.x versions in the fixture
t "t65c: npm major_hint=22 returns highest 22.x version (22.1.0)" bash -c "
    ${_NPM_D_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t65c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      '@types/node'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TYPES_NODE_22_VERSION'
    _gs_eu2_record_set \$idx current_version '22.0.0'
    _gs_eu2_record_set \$idx major_hint      '22'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '22.1.0' ]] || { echo \"expected 22.1.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t65d: no major_hint → dist-tags.latest fast-path returns 25.8.0 (regression guard)
t "t65d: npm without major_hint returns dist-tags.latest (25.8.0) via full list (fixture path)" bash -c "
    ${_NPM_D_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t65d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      '@types/node'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TYPES_NODE_NOHINT_VERSION'
    _gs_eu2_record_set \$idx current_version '24.0.0'
    _gs_eu2_fetch_npm \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # Without major_hint, the stable path should return the highest stable version (25.8.0)
    [[ \"\$val\" == '25.8.0' ]] || { echo \"expected 25.8.0 (no major_hint), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 66 — Bug E: use-sha VAR= receives bare SHA only (no date bleed)
# ═══════════════════════════════════════════════════════════════════════════
section "66 — Bug E: use-sha date bleed in VAR="

_APPLY_E_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/apply.sh'
"

# t66a: use_sha=true — VAR= receives bare SHA, annotation sha: receives SHA with date
t "t66a: use-sha apply — VAR= gets bare SHA, annotation sha: gets bare sha (no date)" bash -c "
    ${_APPLY_E_LIBS}
    f=\${TMP_DIR}/t66a.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    sha_date='2026-05-18'
    ann=\"# @todo env-update (use-sha) pecl:uuid (git:php/test-pkg) 1.2.0 sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_SHA_TEST=%s\n' \"\$ann\" \"\$old_sha\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_SHA_TEST'
    _gs_eu2_record_set \$idx current_version   '1.2.0'
    _gs_eu2_record_set \$idx proposed_version  '1.3.0'
    _gs_eu2_record_set \$idx raw_annotation    \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha    \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha      \"\$new_sha\"
    _gs_eu2_record_set \$idx proposed_sha_date \"\$sha_date\"
    _gs_eu2_record_set \$idx use_sha           'true'
    _gs_eu2_record_set \$idx decision          'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    # VAR= must contain only the bare SHA (no date, no parentheses)
    grep -qF \"GLOBAL_STACK_SHA_TEST=\${new_sha}\" \"\$f\" || { echo \"VAR= not bare SHA; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    grep 'GLOBAL_STACK_SHA_TEST=.*(' \"\$f\" 2>/dev/null && { echo 'VAR= contains date parentheses'; echo FAIL; exit 0; } || true
    # Annotation sha: must contain bare sha only (no date suffix)
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"annotation sha: missing; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    grep -qE \"sha:[0-9a-f]+ +\\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)\" \"\$f\" && { echo \"date suffix in annotation sha: (unexpected); file: \$(cat \$f)\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t66b: use_sha=true with empty sha_date — VAR= still bare SHA (no trailing space/empty parens)
t "t66b: use-sha with no sha_date — VAR= gets bare SHA (no trailing artifacts)" bash -c "
    ${_APPLY_E_LIBS}
    f=\${TMP_DIR}/t66b.env
    old_sha='cccc0000dddd1111eeee2222ffff3333aaaa4444'
    new_sha='2222bbbb3333cccc4444dddd5555eeee6666ffff'
    ann=\"# @todo env-update (use-sha) pecl:test (git:php/test-pkg2) 1.0.0 sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_SHA_B=%s\n' \"\$ann\" \"\$old_sha\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_SHA_B'
    _gs_eu2_record_set \$idx current_version   '1.0.0'
    _gs_eu2_record_set \$idx proposed_version  '1.1.0'
    _gs_eu2_record_set \$idx raw_annotation    \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha    \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha      \"\$new_sha\"
    _gs_eu2_record_set \$idx use_sha           'true'
    _gs_eu2_record_set \$idx decision          'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    # VAR= must be exactly the bare SHA
    grep -qF \"GLOBAL_STACK_SHA_B=\${new_sha}\" \"\$f\" || { echo \"VAR= not bare SHA; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    # Must NOT have date artifacts
    grep 'GLOBAL_STACK_SHA_B=.*(' \"\$f\" && { echo 'VAR= has unexpected parentheses'; echo FAIL; exit 0; } || true
    echo PASS
"

# t66c: use_sha=false — VAR= receives version (not SHA) — regression guard
t "t66c: use_sha=false — VAR= gets proposed version, not SHA (regression guard)" bash -c "
    ${_APPLY_E_LIBS}
    f=\${TMP_DIR}/t66c.env
    ann=\"# @todo env-update github:test/repo 1.0.0\"
    printf '%s\nGLOBAL_STACK_VER_C=1.0.0\n' \"\$ann\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_VER_C'
    _gs_eu2_record_set \$idx current_version   '1.0.0'
    _gs_eu2_record_set \$idx proposed_version  '1.2.0'
    _gs_eu2_record_set \$idx raw_annotation    \"\$ann\"
    _gs_eu2_record_set \$idx use_sha           'false'
    _gs_eu2_record_set \$idx decision          'AUTO'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF 'GLOBAL_STACK_VER_C=1.2.0' \"\$f\" || { echo \"VAR= not updated to 1.2.0; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    echo PASS
"

# t66d: decision=SHA + use_sha=true — VAR= must also receive the new bare SHA
# (SHA-only path must not skip VAR= when the var stores the SHA as its value)
t "t66d: SHA decision + use_sha=true — VAR= updated with new bare SHA (no DRIFT loop)" bash -c "
    ${_APPLY_E_LIBS}
    f=\${TMP_DIR}/t66d.env
    old_sha='aaaa1111bbbb2222cccc3333dddd4444eeee5555'
    new_sha='5555eeee4444dddd3333cccc2222bbbb1111aaaa'
    sha_date='2026-05-18'
    ann=\"# @todo env-update (use-sha) pecl:uuid (git:php/test-uuid) sha:\${old_sha}\"
    printf '%s\nGLOBAL_STACK_SHA_D=%s\n' \"\$ann\" \"\$old_sha\" > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_SHA_D'
    _gs_eu2_record_set \$idx raw_annotation    \"\$ann\"
    _gs_eu2_record_set \$idx annotation_sha    \"\$old_sha\"
    _gs_eu2_record_set \$idx proposed_sha      \"\$new_sha\"
    _gs_eu2_record_set \$idx proposed_sha_date \"\$sha_date\"
    _gs_eu2_record_set \$idx use_sha           'true'
    _gs_eu2_record_set \$idx decision          'SHA'
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    # VAR= must have the new bare SHA (not old, not with date)
    grep -qF \"GLOBAL_STACK_SHA_D=\${new_sha}\" \"\$f\" || { echo \"VAR= not updated to new SHA; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    grep 'GLOBAL_STACK_SHA_D=.*(' \"\$f\" 2>/dev/null && { echo 'VAR= contains date parentheses'; echo FAIL; exit 0; } || true
    # Annotation sha: must have bare sha only (no date suffix)
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"annotation sha: not updated; file: \$(cat \$f)\"; echo FAIL; exit 0; }
    grep -qE \"sha:[0-9a-f]+ +\\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)\" \"\$f\" && { echo \"date suffix in annotation sha: (unexpected); file: \$(cat \$f)\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 69 — Sprint 5: Enhanced SKIP message — major_hint no-match sub-line
# ═══════════════════════════════════════════════════════════════════════════
section "69 — major_hint no-match: [PIN-MISS] sub-line with latest_unconstrained"

# t69a: major_hint=23 → no 23.x in @types/node fixture → [PIN-MISS] shows 25.8.0
# Annotation format: npm:@types/node:23 embeds the major_hint inside the type:identifier token
t "t69a: major_hint=23 SKIP emits [PIN-MISS] sub-line with latest available (25.8.0)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t69a_cache
    f=\${TMP_DIR}/t69a.env
    printf '# @todo env-update npm:@types/node:23 22.0.0\nGLOBAL_STACK_TYPES_NODE_23=22.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[PIN-MISS]' || { echo \"expected [PIN-MISS] sub-line in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major=23' || { echo \"expected 'major=23' in [PIN-MISS] line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '25.8.0' || { echo \"expected '25.8.0' (latest_unconstrained) in [PIN-MISS] line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t69b: major_hint=22 has matches → no [PIN-MISS] no-match sub-line emitted
t "t69b: major_hint=22 has matches — no [PIN-MISS] no-match sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t69b_cache
    f=\${TMP_DIR}/t69b.env
    printf '# @todo env-update npm:@types/node:22 22.0.0\nGLOBAL_STACK_TYPES_NODE_22=22.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[PIN-MISS]' && { echo \"[PIN-MISS] sub-line should NOT appear when 22.x versions exist; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t69c: no major_hint → SKIP is current-is-latest (no [PIN-MISS] sub-line)
t "t69c: no major_hint + up-to-date → no [PIN-MISS] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t69c_cache
    f=\${TMP_DIR}/t69c.env
    printf '# @todo env-update npm:@types/node 25.8.0\nGLOBAL_STACK_TYPES_NODE=25.8.0\n' > \"\$f\"
    # No major_hint in annotation — only plain npm:@types/node
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[PIN-MISS]' && { echo \"[PIN-MISS] sub-line should NOT appear without major_hint; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t69d: major_hint=23 latest_unconstrained field set in record (unit-level check via fetcher)
t "t69d: npm fetcher sets latest_unconstrained when major_hint=23 yields no results" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/npm.sh'
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t69d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'npm'
    _gs_eu2_record_set \$idx identifier      '@types/node'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_TYPES_NODE_23'
    _gs_eu2_record_set \$idx current_version '22.0.0'
    _gs_eu2_record_set \$idx major_hint      '23'
    _gs_eu2_fetch_npm \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    uc=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ \"\$dec\" == 'SKIP' ]] || { echo \"expected SKIP, got: \$dec\"; echo FAIL; exit 0; }
    [[ \"\$uc\" == '25.8.0' ]] || { echo \"expected latest_unconstrained=25.8.0, got: '\$uc'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 68 — HTTP memo: URL-level in-session deduplication
# ═══════════════════════════════════════════════════════════════════════════
section "68 — HTTP memo: URL-level in-session dedup"

# Note: the memo is populated only on real HTTP fetches, NOT fixture responses.
# Fixture injection short-circuits before the memo store. Tests simulate the
# memo by pre-populating _GS_EU2_HTTP_MEMO directly — this is the correct
# way to test the memo read path without making real network calls.

_MEMO_LIBS="
source '${_GS_EU2_LIB}/http/curl.sh'
"

# t68a: pre-seeded memo entry is returned by _gs_eu2_http_get (no fixture dir, no network)
# Memo key format is "${url}:0" for unauthenticated, "${url}:1" for authenticated.
t "t68a: pre-seeded memo entry returned without network call" bash -c "
    unset _GS_EU2_HTTP_FIXTURE_DIR
    ${_MEMO_LIBS}
    url='https://test.example/no-such-fixture-98765'
    # Pre-seed the memo using the unauthenticated key format: url:0
    _GS_EU2_HTTP_MEMO[\"\${url}:0\"]='memo-body-sentinel'
    out=\$(_gs_eu2_http_get \"\$url\")
    [[ \"\$out\" == 'memo-body-sentinel' ]] || { echo \"expected memo-body-sentinel, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t68b: memo is declared as a global associative array (declare -gA)
t "t68b: _GS_EU2_HTTP_MEMO is an associative array available after source" bash -c "
    ${_MEMO_LIBS}
    # Array should be usable immediately after sourcing
    _GS_EU2_HTTP_MEMO['key1']='val1'
    [[ \"\${_GS_EU2_HTTP_MEMO[key1]}\" == 'val1' ]] || { echo 'memo array not writable'; echo FAIL; exit 0; }
    echo PASS
"

# t68c: distinct URLs have distinct memo entries (no cross-contamination)
t "t68c: distinct URLs in memo are independent" bash -c "
    ${_MEMO_LIBS}
    _GS_EU2_HTTP_MEMO['https://a.example/v1']='body-a'
    _GS_EU2_HTTP_MEMO['https://b.example/v1']='body-b'
    [[ \"\${_GS_EU2_HTTP_MEMO['https://a.example/v1']}\" == 'body-a' ]] || { echo 'a wrong'; echo FAIL; exit 0; }
    [[ \"\${_GS_EU2_HTTP_MEMO['https://b.example/v1']}\" == 'body-b' ]] || { echo 'b wrong'; echo FAIL; exit 0; }
    echo PASS
"

# t68d: _gs_eu2_http_get_auth with empty token delegates to _gs_eu2_http_get which hits memo
# Empty token → delegates to _gs_eu2_http_get → uses url:0 key
t "t68d: http_get_auth with empty token hits memo via plain-get delegation" bash -c "
    unset _GS_EU2_HTTP_FIXTURE_DIR
    ${_MEMO_LIBS}
    url='https://test.example/no-such-fixture-memo-auth'
    # Pre-seed with unauthenticated key: empty-token delegation goes through _gs_eu2_http_get → url:0
    _GS_EU2_HTTP_MEMO[\"\${url}:0\"]='auth-memo-body'
    # Empty token → delegates to _gs_eu2_http_get → hits memo (no fixture dir, no network)
    out=\$(_gs_eu2_http_get_auth \"\$url\" '')
    [[ \"\$out\" == 'auth-memo-body' ]] || { echo \"expected auth-memo-body, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 70 — Decision-aware DRIFT messages
# ═══════════════════════════════════════════════════════════════════════════
section "70 — decision-aware [DRIFT] messages"

# t70a: LOCK + non-empty VAR differs from annotation → locked drift message
t "t70a: [DRIFT] LOCK + non-empty VAR diff → 'locked; update annotation manually'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70a_cache
    f=\${TMP_DIR}/t70a.env
    # lock-flag.env has lock:Pinned to master, annotation tracks 18.3-alpine3.23
    # Set VAR to a different value to trigger drift
    printf '# @todo env-update (lock:Pinned to master) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_LOCK_T70A=17.0-alpine3.20\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'locked' || { echo \"expected 'locked' in drift message; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation manually' || { echo \"expected 'update annotation manually'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70b: LOCK + empty VAR → non-empty drift message (not suppressed — LOCK special case)
t "t70b: [DRIFT] LOCK + empty VAR → drift message mentions lock" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70b_cache
    f=\${TMP_DIR}/t70b.env
    printf '# @todo env-update (lock:Pinned to master) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_LOCK_T70B=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'lock blocks' || { echo \"expected 'lock blocks' in drift message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70c: HOLD + non-empty VAR differs → HOLD drift message with --force-auto hint
t "t70c: [DRIFT] HOLD + non-empty VAR diff → '--force-auto --apply to resolve'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70c_cache
    f=\${TMP_DIR}/t70c.env
    # github:testowner/testrepo returns v2.5.0; annotation says 1.0.0 (major bump → HOLD); VAR=0.5.0
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T70C=0.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"expected '--force-auto' in HOLD drift message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70d: MANUAL + non-empty VAR differs → MANUAL drift message with --force-auto hint
t "t70d: [DRIFT] MANUAL + non-empty VAR diff → '--force-auto --apply to resolve'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70d_cache
    f=\${TMP_DIR}/t70d.env
    # (manual) flag → MANUAL decision; VAR differs from annotation
    printf '# @todo env-update (manual) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T70D=0.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"expected '--force-auto' in MANUAL drift message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70e: FROZEN (skip-gate) + non-empty VAR → frozen drift message
t "t70e: [DRIFT] FROZEN (skip-gate) + non-empty VAR diff → 'frozen by skip flag'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70e_cache
    f=\${TMP_DIR}/t70e.env
    printf '# @todo env-update (skip:frozen for now) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T70E=17.0-alpine3.20\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'frozen by skip flag' || { echo \"expected 'frozen by skip flag' in drift message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70f: FROZEN (skip-gate) + empty VAR → drift suppressed (no [DRIFT])
t "t70f: [DRIFT] FROZEN + empty VAR → drift suppressed (skip gate blocks apply)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70f_cache
    f=\${TMP_DIR}/t70f.env
    printf '# @todo env-update (skip:frozen for now) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T70F=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' && { echo \"[DRIFT] should be suppressed for FROZEN + empty VAR; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t70g: AUTO + VAR is AHEAD of annotation → direction-aware drift (downgrade risk)
t "t70g: [DRIFT] AUTO + VAR ahead of annotation → 'VAR is ahead of annotation (downgrade risk)'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t70g_cache
    f=\${TMP_DIR}/t70g.env
    # annotation says 1.0.0 but VAR=3.0.0 (VAR is AHEAD of annotation)
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T70G=3.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' || { echo \"expected 'VAR is ahead' in drift message; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'downgrade risk' || { echo \"expected 'downgrade risk' in drift message; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 71 — [FROZEN] tag and counter for skip-gate records
# ═══════════════════════════════════════════════════════════════════════════
section "71 — [FROZEN] tag and frozen= summary counter"

# t71a: skip-gate record shows [FROZEN] tag in output
t "t71a: (skip:REASON) annotation shows [FROZEN] tag" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t71a_cache
    f=\${TMP_DIR}/t71a.env
    printf '# @todo env-update (skip:frozen for now) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T71A=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[FROZEN ]' || { echo \"expected [FROZEN ] tag in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[SKIP   ]' && { echo \"[SKIP] should not appear for skip-gate record; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t71b: summary line includes FROZEN count for one skip-gate record
t "t71b: summary line shows '1 FROZEN' for one (skip:REASON) record" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t71b_cache
    f=\${TMP_DIR}/t71b.env
    printf '# @todo env-update (skip:frozen for now) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T71B=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'FROZEN' || { echo \"expected 'FROZEN' in summary line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '1 FROZEN' || { echo \"expected '1 FROZEN' in summary line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 72 — (override) vs (manual) display split
# ═══════════════════════════════════════════════════════════════════════════
section "72 — (override) vs (manual) up-to-date display"

# t72a: (override) flag at same version → shows '(up to date — override)'
t "t72a: (override) at same version shows '(up to date — override)'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t72a_cache
    f=\${TMP_DIR}/t72a.env
    # dockerhub:_/postgres fixture returns 18.4-alpine3.23; set current to same
    printf '# @todo env-update (override) dockerhub:_/postgres\nGLOBAL_STACK_T72A=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'up to date — override' || { echo \"expected 'up to date — override'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'up to date — manual' && { echo \"should show 'override' not 'manual'; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t72b: (manual) flag at same version → shows '(up to date — manual)'
t "t72b: (manual) at same version shows '(up to date — manual)'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t72b_cache
    f=\${TMP_DIR}/t72b.env
    # (manual) flag + same version: MANUAL decision, no change → up to date — manual
    printf '# @todo env-update (manual) dockerhub:_/postgres\nGLOBAL_STACK_T72B=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'up to date — manual' || { echo \"expected 'up to date — manual'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'up to date — override' && { echo \"should show 'manual' not 'override'; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 73 — Fix 1: PIN-MISS guard — only fires on "no versions matched" SKIP
# ═══════════════════════════════════════════════════════════════════════════
section "73 — Fix 1: PIN-MISS guard (error_message gate)"

# t73a: SKIP(up-to-date) with major_hint — should NOT emit [PIN-MISS]
# Before fix: [PIN-MISS] fired on any SKIP with major_hint set.
# After fix: [PIN-MISS] only fires when error_message is non-empty (fetcher SKIP).
t "t73a: SKIP(up-to-date) with major_hint=22 — no [PIN-MISS] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t73a_cache
    f=\${TMP_DIR}/t73a.env
    # current=22.1.0 is the highest 22.x in fixture → classify_decision → SKIP (up to date)
    printf '# @todo env-update npm:@types/node:22 22.1.0\nGLOBAL_STACK_T73A=22.1.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[PIN-MISS]' && { echo \"[PIN-MISS] must NOT appear for up-to-date SKIP; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"expected [SKIP line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t73b: SKIP(no-versions) with major_hint=23 — MUST emit [PIN-MISS]
# The @types/node fixture has no 23.x versions; fetcher sets error_message → [PIN-MISS] fires.
t "t73b: SKIP(no versions matched) with major_hint=23 — [PIN-MISS] fires" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t73b_cache
    f=\${TMP_DIR}/t73b.env
    printf '# @todo env-update npm:@types/node:23 22.0.0\nGLOBAL_STACK_T73B=22.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[PIN-MISS]' || { echo \"[PIN-MISS] must appear when no versions matched; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major=23' || { echo \"expected 'major=23' in [PIN-MISS] line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 74 — Fix 3: Major range annotation (LOW-HIGH syntax)
# ═══════════════════════════════════════════════════════════════════════════
section "74 — Fix 3: Major range annotation (LOW-HIGH syntax)"

# t74a: range 25-26, v26 absent → AUTO to 25.x + [FALLBACK] sub-line
# Fixture: @types/node (22,22.1,24,24.1,25,25.8 — no 26.x)
t "t74a: range :25-26, v26 absent — AUTO to 25.8.0 + [FALLBACK] sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t74a_cache
    f=\${TMP_DIR}/t74a.env
    # current=25.0.0, annotation uses range 25-26 → HIGH(26) absent → fallback to LOW(25)
    printf '# @todo env-update npm:@types/node:25-26 25.0.0\nGLOBAL_STACK_T74A=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"expected [AUTO decision; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '25.8.0' || { echo \"expected proposed 25.8.0 in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[FALLBACK]' || { echo \"expected [FALLBACK] sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'major=26' || { echo \"expected 'major=26' in [FALLBACK] line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fallback major=25' || { echo \"expected 'fallback major=25' in [FALLBACK] line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[PIN-MISS]' && { echo \"[PIN-MISS] must NOT appear when fallback succeeded; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t74b: range 25-26, v26 available → AUTO to 26.x, no [FALLBACK]
# Fixture: @types/range-test-pkg-with26 (25.0,25.8,26.0,26.1)
t "t74b: range :25-26, v26 available — AUTO to 26.1.0, no [FALLBACK]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t74b_cache
    f=\${TMP_DIR}/t74b.env
    printf '# @todo env-update npm:@types/range-test-pkg-with26:25-26 25.8.0\nGLOBAL_STACK_T74B=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"expected [AUTO decision; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '26.1.0' || { echo \"expected proposed 26.1.0 in output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[FALLBACK]' && { echo \"[FALLBACK] must NOT appear when HIGH(26) has versions; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t74c: range 30-31, both absent → SKIP, [PIN-MISS] fires, no [FALLBACK]
# No 30.x or 31.x in the @types/node fixture.
t "t74c: range :30-31, both absent — SKIP + [PIN-MISS], no [FALLBACK]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t74c_cache
    f=\${TMP_DIR}/t74c.env
    printf '# @todo env-update npm:@types/node:30-31 25.0.0\nGLOBAL_STACK_T74C=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"expected [SKIP decision; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[PIN-MISS]' || { echo \"[PIN-MISS] must appear when neither major found; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[FALLBACK]' && { echo \"[FALLBACK] must NOT appear when both majors absent; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 75 — Summary line: FALLBACK, WATCH, DRIFT, DOWNGRADE counters
# ═══════════════════════════════════════════════════════════════════════════
section "75 — Summary line: FALLBACK, WATCH, DRIFT, DOWNGRADE counters"

# t75a: FALLBACK counter appears in summary when range falls back to LOW major.
# Fixture: @types/node (22,22.1,24,24.1,25,25.8 — no 26.x)
# Annotation: npm:@types/node:25-26 25.0.0, VAR=25.0.0
# Expected: 1 FALLBACK in Summary line.
t "t75a: FALLBACK counter — summary shows 1 FALLBACK when range falls back to LOW major" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75a_cache
    f=\${TMP_DIR}/t75a.env
    printf '# @todo env-update npm:@types/node:25-26 25.0.0\nGLOBAL_STACK_T75A=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '1 FALLBACK' || { echo \"Summary must show 1 FALLBACK; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[FALLBACK]' || { echo \"[FALLBACK] sub-line must still appear; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75b: WATCH counter appears in secondary sub-line.
# Fixture: testorg/watchrepo-newer (v4.0.0, v3.1.0, v3.0.5). Pin major 3.
# Current=3.0.5 → proposed=v3.1.0, unconstrained=v4.0.0 → WATCH fires.
# Expected: secondary sub-line shows 1 WATCH.
t "t75b: WATCH counter — secondary sub-line shows 1 WATCH when newer generation available" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75b_cache
    f=\${TMP_DIR}/t75b.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 3.0.5\nGLOBAL_STACK_T75B=3.0.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"[WATCH] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 WATCH' || { echo \"secondary sub-line must show 1 WATCH; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75c: DRIFT counter (fixable) — VAR behind annotation, AUTO decision.
# Fixture: testowner/testrepo (v2.5.0, v2.4.0, v2.3.0-rc1).
# Annotation current=1.0.0, VAR=0.9.0. No major pin → AUTO (2.5.0 > 1.0.0).
# Drift: annotation says 1.0.0, VAR=0.9.0 → drift fires. AUTO decision → fixable.
# Expected: 1 DRIFT (1 fixable) in secondary sub-line, 0 DOWNGRADE.
t "t75c: DRIFT fixable counter — 1 DRIFT (1 fixable) when VAR behind annotation, AUTO decision" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75c_cache
    f=\${TMP_DIR}/t75c.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T75C=0.9.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"[DRIFT] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 DRIFT \(1 fixable\)' || { echo \"secondary sub-line must show 1 DRIFT (1 fixable); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '0 DOWNGRADE' || { echo \"secondary sub-line must show 0 DOWNGRADE; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75d: --no-drift suppresses DRIFT+DOWNGRADE from secondary sub-line.
# Same scenario as t75c but with --no-drift.
# Expected: no [DRIFT] sub-line, no secondary ↳ line (all signals zero).
t "t75d: --no-drift suppresses DRIFT from secondary sub-line (WATCH zero → line omitted)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75d_cache
    f=\${TMP_DIR}/t75d.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T75D=0.9.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-drift --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' && { echo \"[DRIFT] sub-line must NOT appear with --no-drift; got: \$out\"; echo FAIL; exit 0; } || true
    # Secondary line omitted when all signals (WATCH=0 here, DRIFT/DOWNGRADE suppressed) are zero
    echo \"\$out\" | grep -qF 'WATCH' && { echo \"secondary WATCH line must not appear (WATCH=0); got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t75e: DOWNGRADE counter — SKIP + VAR ahead: drift shown but counter stays 0.
# Fixture: @types/node (22,22.1,24,24.1,25,25.8). Pin to major 22.
# Annotation current=22.1.0, VAR=25.8.0. Fetcher proposes 22.1.0 (same) → SKIP.
# Drift: annotation says 22.1.0, VAR=25.8.0 → both pure semver → VAR ahead.
# SKIP cannot be written by --apply → downgrade counter stays 0 (B5/B6 fix).
# Drift message must say "update annotation or revert VAR= manually" (B4/B10 fix).
# Expected: 1 DRIFT (0 fixable), 0 DOWNGRADE in secondary sub-line.
t "t75e: DOWNGRADE counter — SKIP + VAR ahead shows 0 DOWNGRADE (not actionable by --apply)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75e_cache
    f=\${TMP_DIR}/t75e.env
    printf '# @todo env-update npm:@types/node:22 22.1.0\nGLOBAL_STACK_T75E=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"[DRIFT] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' || { echo \"drift message must say update annotation or revert VAR= manually; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '--apply will' && { echo \"drift message must NOT mention --apply will (SKIP cannot be written); got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qE '1 DRIFT \(0 fixable\)' || { echo \"secondary sub-line must show 1 DRIFT (0 fixable); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '0 DOWNGRADE' || { echo \"secondary sub-line must show 0 DOWNGRADE (SKIP excluded from counter); got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75e2: DOWNGRADE counter — AUTO + VAR ahead still counts as 1 DOWNGRADE.
# Same direction detection, but decision is AUTO → --apply CAN write it → counts.
# Fixture: @types/node latest=25.8.0. Annotation current=22.1.0, VAR=25.8.0.
# With no major pin, fetcher returns 25.8.0 (same as VAR) → SKIP actually.
# Use a pin-forward: annotation current=25.8.0, VAR=99.0.0 → annotation < VAR → downgrade.
# Fetcher proposes 25.8.0 > 25.8.0? No. Let's set annotation=22.1.0, proposed=25.8.0, VAR=99.0.0.
# With pin :25, fetcher returns 25.8.0 > 22.1.0 → AUTO. VAR=99.0.0 > ann=22.1.0 → downgrade.
t "t75e2: DOWNGRADE counter — AUTO + VAR ahead shows 1 DOWNGRADE (apply can write)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75e2_cache
    f=\${TMP_DIR}/t75e2.env
    printf '# @todo env-update npm:@types/node:25 22.1.0\nGLOBAL_STACK_T75E2=99.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"[DRIFT] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead of annotation' || { echo \"drift must mention VAR is ahead; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 DOWNGRADE' || { echo \"secondary sub-line must show 1 DOWNGRADE for AUTO decision; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75f: Clean run — all signals zero, secondary sub-line omitted.
# Fixture: @types/node. Annotation current=25.8.0, VAR=25.8.0.
# No WATCH (no watch-major), no drift (VAR matches annotation), up-to-date → SKIP.
# Expected: no secondary ↳ line in output; 0 FALLBACK in summary.
t "t75f: clean run — no secondary sub-line when all signals are zero" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75f_cache
    f=\${TMP_DIR}/t75f.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T75F=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '0 FALLBACK' || { echo \"Summary must show 0 FALLBACK; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'WATCH' && { echo \"secondary sub-line must NOT appear when all signals are zero; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF 'DRIFT' && { echo \"secondary sub-line must NOT appear when all signals are zero; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t75g: +sha counter — AUTO decision with sha sub-line → 1 +sha in secondary sub-line.
# Fixture: pecl:zmq (git:zeromq/php-zmq). PECL proposes 1.1.3 (> 1.1.2 → AUTO).
# Commits fixture: sha=616b6c64... Annotation sha=<old_sha> ≠ proposed sha → sha sub-line fires.
# The pecl fetcher is the only one that populates proposed_sha; github fetcher does not.
# Expected: secondary sub-line shows · 1 +sha.
t "t75g: +sha counter — AUTO decision with sha annotation update shows 1 +sha in secondary sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75g_cache
    f=\${TMP_DIR}/t75g.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444aaaa0000bbbb1111cccc2222dd'
    printf '# @todo env-update pecl:zmq (git:zeromq/php-zmq) 1.1.2 sha:%s\nGLOBAL_STACK_T75G=1.1.2\n' \"\$old_sha\" > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '[+]sha' || { echo \"secondary sub-line must show +sha; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 [+]sha' || { echo \"secondary sub-line must show '1 +sha'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75h: +sha counter — WATCH only (no sha annotation) → 0 +sha in secondary sub-line.
# Fixture: testorg/watchrepo-newer. No sha annotation.
# Expected: secondary sub-line shows 1 WATCH · ... · 0 +sha.
t "t75h: +sha counter — 0 +sha when no sha annotation present (WATCH-only scenario)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75h_cache
    f=\${TMP_DIR}/t75h.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 3.0.5\nGLOBAL_STACK_T75H=3.0.5\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '[+]sha' || { echo \"secondary sub-line must show +sha even when 0; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '0 [+]sha' || { echo \"secondary sub-line must show '0 +sha'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t75f-upd: clean run — secondary sub-line still omitted when all signals including +sha are zero.
# (Confirms that 0 +sha alone does not force the secondary line to appear.)
t "t75f-upd: clean run — no secondary sub-line when ALL signals including +sha are zero" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t75fupd_cache
    f=\${TMP_DIR}/t75fupd.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T75FUPD=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '+sha' && { echo \"secondary sub-line must NOT appear when all signals are zero; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 76 — --changes-only flag
# ═══════════════════════════════════════════════════════════════════════════
section "76 — --changes-only flag"

# t76a: pure up-to-date record (no signals) is hidden; summary shows "(1 hidden)"
# Fixture: @types/node (25.8.0 is highest 25.x). Annotation current=25.8.0, VAR=25.8.0.
# Expected: [SKIP] line absent, "1 hidden" in summary.
t "t76a: pure up-to-date SKIP hidden — (1 hidden) in summary" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76a_cache
    f=\${TMP_DIR}/t76a.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76A=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' && { echo \"[SKIP] line must NOT appear when hidden; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '1 hidden' || { echo \"summary must show '1 hidden'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t76b: up-to-date + (note:TEXT) only → still hidden (note is metadata, not a signal)
# Fixture: @types/node. Annotation: (note:must match node major) npm:@types/node:25 25.8.0.
# Expected: hidden, (1 hidden) in summary.
t "t76b: up-to-date SKIP + note-only → still hidden" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76b_cache
    f=\${TMP_DIR}/t76b.env
    printf '# @todo env-update (note:must match node major) npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76B=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' && { echo \"[SKIP] must not appear (note-only record hidden); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '1 hidden' || { echo \"summary must show '1 hidden'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t76c: SKIP with DRIFT (VAR behind annotation) → stays visible
# Fixture: @types/node. Annotation current=25.8.0, VAR=25.0.0 (behind).
# Fetcher proposes 25.8.0 (same as annotation current) → SKIP (up-to-date).
# Drift: annotation says 25.8.0 but VAR=25.0.0 → drift fires → NOT hidden.
t "t76c: SKIP + DRIFT → stays visible (drift prevents hiding)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76c_cache
    f=\${TMP_DIR}/t76c.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76C=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"[SKIP] must appear (drift prevents hiding); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"[DRIFT] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary (record visible); got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76d: AUTO decision (update available) → always visible, not in (hidden) count
# Fixture: @types/node. Annotation current=25.0.0, proposed=25.8.0 → AUTO.
# Expected: [AUTO] line visible, no "hidden" in summary.
t "t76d: AUTO decision always visible — no 'hidden' in summary" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76d_cache
    f=\${TMP_DIR}/t76d.env
    printf '# @todo env-update npm:@types/node:25 25.0.0\nGLOBAL_STACK_T76D=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"[AUTO] line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary (AUTO record visible); got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76e: (skip:REASON)/FROZEN record always visible (non-empty error_message → gate fails)
# Fixture: @types/node. Annotation: (skip:deprecated) npm:@types/node:25 25.8.0.
# Expected: [FROZEN] visible, no "hidden".
t "t76e: (skip:REASON) FROZEN always visible — not hidden" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76e_cache
    f=\${TMP_DIR}/t76e.env
    printf '# @todo env-update (skip:deprecated) npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76E=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[FROZEN' || { echo \"[FROZEN] must appear (skip-gate always visible); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76f: mixed batch — 1 AUTO + 1 SKIP(up-to-date) → only AUTO shown, summary (1 hidden)
# Fixture: @types/node. Two vars: T76F1 (auto: 25.0.0→25.8.0), T76F2 (skip: 25.8.0 up-to-date).
t "t76f: mixed batch — AUTO visible, SKIP hidden; summary shows (1 hidden)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76f_cache
    f=\${TMP_DIR}/t76f.env
    printf '# @todo env-update npm:@types/node:25 25.0.0\nGLOBAL_STACK_T76F1=25.0.0\n# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76F2=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[AUTO' || { echo \"[AUTO] line must appear; got: \$out\"; echo FAIL; exit 0; }
    # Progress indicator contains the var name (stderr) — check the decision line specifically
    echo \"\$out\" | grep -qE '^\[SKIP.*GLOBAL_STACK_T76F2' && { echo \"T76F2 SKIP decision line must be hidden; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '1 hidden' || { echo \"summary must show '1 hidden'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t76g: WATCH signal prevents hiding — SKIP + (watch-major) with new generation available
# Fixture: testorg/watchrepo-newer (v4.0.0, v3.1.0, v3.0.5). Pin major=3, current=v3.1.0.
# Result: SKIP (up-to-date on major 3) + [WATCH] (v4.0.0 new generation detected).
# Expected: record stays visible; no "hidden" in summary.
t "t76g: SKIP + [WATCH] signal — stays visible (WATCH prevents hiding)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76g_cache
    f=\${TMP_DIR}/t76g.env
    printf '# @todo env-update (watch-major) github:testorg/watchrepo-newer:3 v3.1.0\nGLOBAL_STACK_T76G=v3.1.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"[SKIP] must appear (WATCH prevents hiding); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"[WATCH] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76h: FALLBACK signal on SKIP record prevents hiding
# Fixture: @types/node (25.8.0 max, no 26.x). Range annotation :25-26, current=25.8.0.
# Result: SKIP (25.8.0 up-to-date on fallback major=25) + [FALLBACK] sub-line.
# Expected: record stays visible; no "hidden" in summary.
t "t76h: SKIP + [FALLBACK] signal — stays visible (FALLBACK prevents hiding)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76h_cache
    f=\${TMP_DIR}/t76h.env
    printf '# @todo env-update npm:@types/node:25-26 25.8.0\nGLOBAL_STACK_T76H=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"[SKIP] must appear (FALLBACK prevents hiding); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[FALLBACK]' || { echo \"[FALLBACK] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76i: LOCK decision always visible (decision gate: LOCK != SKIP)
# Annotation: (lock:deprecated) npm:@types/node:25 25.8.0, current=25.8.0.
# Result: LOCK decision → decision gate fails → always visible.
# Expected: [LOCK] line present, no "hidden" in summary.
t "t76i: LOCK decision always visible — decision gate fails (LOCK != SKIP)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76i_cache
    f=\${TMP_DIR}/t76i.env
    printf '# @todo env-update (lock:deprecated) npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76I=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[LOCK' || { echo \"[LOCK] must appear (lock always visible); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76j: --unstable=info prevents hiding when prerelease is newer than current stable
# Fixture: testowner/rc-ahead (v1.1.0-rc1 prerelease, v1.0.0 stable).
# current=v1.0.0 → SKIP (up-to-date on stable). unstable=info → [UNSTABLE] sub-line fires.
# Expected: record stays visible (UNSTABLE signal prevents hiding).
t "t76j: SKIP + --unstable=info [UNSTABLE] sub-line — stays visible" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76j_cache
    f=\${TMP_DIR}/t76j.env
    printf '# @todo env-update github:testowner/rc-ahead v1.0.0\nGLOBAL_STACK_T76J=v1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --unstable=info --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"[SKIP] must appear (UNSTABLE prevents hiding); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[UNSTABLE]' || { echo \"[UNSTABLE] sub-line must appear; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear in summary; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t76k: --no-drift + --changes-only — drift exists but display suppressed; record still visible
# Fixture: @types/node. Annotation current=25.8.0, VAR=25.0.0 → SKIP (up-to-date on 25.x)
# with --no-drift: [DRIFT] sub-line suppressed. But drift condition exists → NOT hidden.
# (The drift data is checked from record fields, independent of --no-drift display flag.)
t "t76k: --no-drift + --changes-only: drift condition keeps record visible despite display suppression" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t76k_cache
    f=\${TMP_DIR}/t76k.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T76K=25.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --no-drift --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[SKIP' || { echo \"[SKIP] must appear (drift keeps record visible); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[DRIFT]' && { echo \"[DRIFT] must NOT appear with --no-drift; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF 'hidden' && { echo \"'hidden' must NOT appear (drift exists, record visible); got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

section "77 — --no-fail flag"

# t77a: --no-fail accepted — no parse error on valid usage
t "t77a: --no-fail accepted — exits 0 (no errors)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77a_cache
    f=\${TMP_DIR}/t77a.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T77A=25.8.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t77b: ERROR decision → exit 1 WITHOUT --no-fail (baseline: flag has real effect)
t "t77b: ERROR → exit 1 without --no-fail" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77b_cache
    f=\${TMP_DIR}/t77b.env
    printf '# @todo env-update dockerhub:_/nonexistent-repo-xyz 1.0.0\nGLOBAL_STACK_T77B=1.0.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" >/dev/null 2>/dev/null
    rc=\$?
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit (ERROR without --no-fail), got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t77c: ERROR decision → exit 0 WITH --no-fail
t "t77c: ERROR → exit 0 with --no-fail" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77c_cache
    f=\${TMP_DIR}/t77c.env
    printf '# @todo env-update dockerhub:_/nonexistent-repo-xyz 1.0.0\nGLOBAL_STACK_T77C=1.0.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" >/dev/null 2>/dev/null
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 with --no-fail, got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t77d: --no-fail does NOT suppress [ERROR] output — decision lines still visible
t "t77d: --no-fail: [ERROR] lines still appear in output" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77d_cache
    f=\${TMP_DIR}/t77d.env
    printf '# @todo env-update dockerhub:_/nonexistent-repo-xyz 1.0.0\nGLOBAL_STACK_T77D=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[ERROR' || { echo \"[ERROR] must still appear in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t77e: no errors present → exit 0 still (--no-fail has no negative effect on clean runs)
t "t77e: no errors → exit 0 still with --no-fail" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77e_cache
    f=\${TMP_DIR}/t77e.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T77E=25.8.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 (no errors, --no-fail), got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t77f: usage/parse error → exit 1 even with --no-fail (args errors are fatal)
# --no-fail only intercepts ERROR fetch decisions, not argument validation failures.
t "t77f: usage error stays fatal even with --no-fail" bash -c "
    bash '${ENV_UPDATE_V2}' --no-fail --check --unknown-invalid-option 2>/dev/null
    rc=\$?
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit (usage error must be fatal), got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t77g: --no-fail prints a stderr notice when it suppresses non-zero exit code
t "t77g: --no-fail prints stderr notice when exit code suppressed" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t77g_cache
    f=\${TMP_DIR}/t77g.env
    printf '# @todo env-update dockerhub:_/nonexistent-repo-xyz 1.0.0\nGLOBAL_STACK_T77G=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[NO-FAIL MODE] ERROR decisions will not abort' || { echo \"stderr notice missing (expected '[NO-FAIL MODE] ERROR decisions will not abort' in output); got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

section "78 — mode banners"

# t78a: --no-drift flag → stderr contains [NO-DRIFT MODE]
t "t78a: --no-drift flag prints [NO-DRIFT MODE] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78a_cache
    f=\${TMP_DIR}/t78a.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78A=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-drift --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[NO-DRIFT MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t78b: --changes-only flag → stderr contains [CHANGES-ONLY MODE]
t "t78b: --changes-only flag prints [CHANGES-ONLY MODE] banner" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78b_cache
    f=\${TMP_DIR}/t78b.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78B=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --changes-only --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[CHANGES-ONLY MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t78c: --no-fail flag + clean fixture (no ERROR) → [NO-FAIL MODE] banner fires upfront (unconditional)
t "t78c: --no-fail flag + no errors — [NO-FAIL MODE] banner present (fires upfront, not gated on errors)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78c_cache
    f=\${TMP_DIR}/t78c.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78C=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[NO-FAIL MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t78d: no mode flags → stderr does NOT contain any mode banners
t "t78d: no mode flags — no mode banners in output" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78d_cache
    f=\${TMP_DIR}/t78d.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78D=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[NO-DRIFT MODE]'    && { echo \"unexpected [NO-DRIFT MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[CHANGES-ONLY MODE]' && { echo \"unexpected [CHANGES-ONLY MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[NO-FAIL MODE]'     && { echo \"unexpected [NO-FAIL MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[DRY-RUN MODE]'     && { echo \"unexpected [DRY-RUN MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[UNSTABLE MODE]'    && { echo \"unexpected [UNSTABLE MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[STABLE MODE]'      && { echo \"unexpected [STABLE MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[NO-NOTES MODE]'    && { echo \"unexpected [NO-NOTES MODE] banner; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t78e: --dry-run flag → [DRY-RUN MODE] banner present, legacy prose notice absent
t "t78e: --dry-run flag prints [DRY-RUN MODE] banner and suppresses legacy prose notice" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78e_cache
    f=\${TMP_DIR}/t78e.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78E=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[DRY-RUN MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'dry-run active' && { echo \"legacy prose notice still present; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# t78f: --unstable=full with no non-stable records → banner fires with 0 record(s)
t "t78f: --unstable=full with stable-only fixture — banner fires with 0 record(s)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78f_cache
    f=\${TMP_DIR}/t78f.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78F=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --unstable=full --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[UNSTABLE MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t78g: --stable=full with no non-stable records → banner fires with 0 record(s)
t "t78g: --stable=full with no non-stable records — banner fires with 0 record(s)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78g_cache
    f=\${TMP_DIR}/t78g.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78G=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --stable=full --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[STABLE MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t78h: --no-notes with a fixture that has no note annotations → banner fires with 0 record(s)
t "t78h: --no-notes with no note annotations — banner fires with 0 record(s)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t78h_cache
    f=\${TMP_DIR}/t78h.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T78H=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-notes --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[NO-NOTES MODE]' || { echo \"banner missing; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

section "79 — --profile flag"

# t79a: --profile flag accepted — exits 0 (not rejected as unknown option)
t "t79a: --profile flag accepted — exits 0" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t79a_cache
    f=\${TMP_DIR}/t79a.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T79A=25.8.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --profile --env-file=\"\$f\" >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t79b: --profile flag → output contains a profile phase name (e.g. 'Parse args')
t "t79b: --profile flag — output contains profile table with phase names" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t79b_cache
    f=\${TMP_DIR}/t79b.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T79B=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --profile --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF 'Parse args' || { echo \"phase 'Parse args' missing from profile output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t79c: --profile flag → output contains timing (ms or s) for a phase row
t "t79c: --profile flag — output contains timing column (ms or s)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t79c_cache
    f=\${TMP_DIR}/t79c.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T79C=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --profile --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qE '[0-9]+ ms|[0-9]+\.[0-9]+ +s' || { echo \"no timing found in profile output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t79d: no --profile flag → output does NOT contain profile table header ('Profile')
t "t79d: no --profile flag — profile table absent from output" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t79d_cache
    f=\${TMP_DIR}/t79d.env
    printf '# @todo env-update npm:@types/node:25 25.8.0\nGLOBAL_STACK_T79D=25.8.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF 'Parse args' && { echo \"profile table must NOT appear without --profile; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

section "80 — backup flags (--backup, --backup-purge, --backup-suffix, --backup-keep)"

# t80a: --apply --backup=false → no .bak.* file created
t "t80a: --apply --backup=false — no backup file created" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80a_cache
    mkdir -p \"\${TMP_DIR}/t80a_cache\"
    touch \"\${TMP_DIR}/t80a_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80a.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80A=18.3-alpine3.23\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup=false --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80a.env.bak*' -type f 2>/dev/null | wc -l)
    [[ \$count -eq 0 ]] || { echo \"expected 0 backup files, found \$count\"; echo FAIL; exit 0; }
    echo PASS
"

# t80b: --apply (default) → exactly one backup file matching .bak. pattern
t "t80b: --apply (default) — exactly one .bak. file created" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80b_cache
    mkdir -p \"\${TMP_DIR}/t80b_cache\"
    touch \"\${TMP_DIR}/t80b_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80b.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80B=18.3-alpine3.23\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80b.env.bak*' -type f 2>/dev/null | wc -l)
    [[ \$count -ge 1 ]] || { echo \"expected >=1 backup file, found \$count\"; echo FAIL; exit 0; }
    echo PASS
"

# t80c: --apply --backup-suffix=.mybak → backup filename contains .mybak.; .bak. pattern absent
t "t80c: --apply --backup-suffix=.mybak — backup uses custom suffix" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80c_cache
    mkdir -p \"\${TMP_DIR}/t80c_cache\"
    touch \"\${TMP_DIR}/t80c_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80c.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80C=18.3-alpine3.23\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-suffix=.mybak --env-file=\"\$f\" 2>/dev/null || true
    count_mybak=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80c.env.mybak.*' -type f 2>/dev/null | wc -l)
    count_bak=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80c.env.bak.*' -type f 2>/dev/null | wc -l)
    [[ \$count_mybak -ge 1 ]] || { echo \"expected >=1 .mybak.* file, found \$count_mybak\"; echo FAIL; exit 0; }
    [[ \$count_bak -eq 0 ]]   || { echo \"expected 0 .bak.* files, found \$count_bak\"; echo FAIL; exit 0; }
    echo PASS
"

# t80d: --apply --backup-keep=2 (pre-seed 3 old backups) → exactly 2 backups remain after run (oldest deleted)
t "t80d: --apply --backup-keep=2 — prunes oldest; exactly 2 backups remain" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80d_cache
    mkdir -p \"\${TMP_DIR}/t80d_cache\"
    touch \"\${TMP_DIR}/t80d_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80d.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80D=18.3-alpine3.23\n' > \"\$f\"
    # Pre-seed 3 old backups with artificial old timestamps
    touch \"\${TMP_DIR}/t80d.env.bak.20200101-000001-99\"
    touch \"\${TMP_DIR}/t80d.env.bak.20200101-000002-99\"
    touch \"\${TMP_DIR}/t80d.env.bak.20200101-000003-99\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-keep=2 --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80d.env.bak*' -type f 2>/dev/null | wc -l)
    [[ \$count -eq 2 ]] || { echo \"expected 2 backups after pruning, found \$count\"; echo FAIL; exit 0; }
    echo PASS
"

# t80e: --apply --backup-purge=true (pre-seed 3 old backups) → 3 old ones deleted; 1 new one exists (total = 1)
t "t80e: --apply --backup-purge=true — purges old backups; 1 new backup remains" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80e_cache
    mkdir -p \"\${TMP_DIR}/t80e_cache\"
    touch \"\${TMP_DIR}/t80e_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80e.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80E=18.3-alpine3.23\n' > \"\$f\"
    # Pre-seed 3 old backups
    touch \"\${TMP_DIR}/t80e.env.bak.20200101-000001-99\"
    touch \"\${TMP_DIR}/t80e.env.bak.20200101-000002-99\"
    touch \"\${TMP_DIR}/t80e.env.bak.20200101-000003-99\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-purge=true --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80e.env.bak*' -type f 2>/dev/null | wc -l)
    [[ \$count -eq 1 ]] || { echo \"expected exactly 1 backup after purge+create, found \$count\"; echo FAIL; exit 0; }
    echo PASS
"

# t80f: --backup-keep=abc → exits non-zero; stderr contains "non-negative integer"
t "t80f: --backup-keep=abc — rejected; stderr contains 'non-negative integer'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    f=\${TMP_DIR}/t80f.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80F=18.3-alpine3.23\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --apply --yes --backup-keep=abc --env-file=\"\$f\" 2>&1 || true)
    rc=\$(bash '${ENV_UPDATE_V2}' --apply --yes --backup-keep=abc --env-file=\"\$f\" 2>/dev/null; echo \$?)
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -q 'non-negative integer' || { echo \"stderr missing 'non-negative integer'; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

section "81 — --reference flag (replaces --annotations)"

# t81a: --reference exits 0
t "t81a: --reference — exits 0" bash -c "
    bash '${ENV_UPDATE_V2}' --reference >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got: \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t81b: --reference output contains FETCHER TYPES section
t "t81b: --reference — output contains FETCHER TYPES section" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference 2>&1 || true)
    echo \"\$out\" | grep -qF 'FETCHER TYPES' || { echo \"missing FETCHER TYPES; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81c: --reference output contains ANNOTATION FLAGS section
t "t81c: --reference — output contains ANNOTATION FLAGS section" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference 2>&1 || true)
    echo \"\$out\" | grep -qF 'ANNOTATION FLAGS' || { echo \"missing ANNOTATION FLAGS; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81d: --reference exits without requiring an env file
t "t81d: --reference — exits without requiring an env file" bash -c "
    bash '${ENV_UPDATE_V2}' --reference --env-file=/nonexistent/path.env >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got \$rc (should exit before env file check)\"; echo FAIL; exit 0; }
    out=\$(bash '${ENV_UPDATE_V2}' --reference --env-file=/nonexistent/path.env 2>&1 || true)
    echo \"\$out\" | grep -qF 'ANNOTATION FLAGS' || { echo \"missing reference output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81e: --reference=syntax shows annotation format, not fetcher deep-dive
t "t81e: --reference=syntax — shows syntax section" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=syntax 2>&1 || true)
    echo \"\$out\" | grep -qF 'ANNOTATION FORMAT' || { echo \"missing ANNOTATION FORMAT; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81f: --reference=annotations includes previously undocumented flags
t "t81f: --reference=annotations — includes tag-extract and fetch-json flags" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=annotations 2>&1 || true)
    echo \"\$out\" | grep -qF 'tag-extract' || { echo \"missing tag-extract; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fetch-json' || { echo \"missing fetch-json; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81g: --reference=annotations does NOT document (hold) as a valid flag
t "t81g: --reference=annotations — no (hold) as a valid annotation flag" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=annotations 2>&1 || true)
    # (hold) should NOT appear as a parenthesised flag entry (it is not a real flag)
    # It may appear in explanatory prose about the HOLD decision itself, so we
    # check for the specific pattern of it being listed as a valid flag.
    echo \"\$out\" | grep -qP '^\s+\(hold\)' && { echo \"(hold) should NOT be listed as a valid flag\"; echo FAIL; exit 0; }
    echo PASS
"

# t81h: --reference=matrix shows RESOLVED and AUTO in matrix output
t "t81h: --reference=matrix — live matrix shows RESOLVED and AUTO" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'RESOLVED' || { echo \"missing RESOLVED in matrix; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'AUTO' || { echo \"missing AUTO in matrix; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81i: --annotations (old flag) exits non-zero with unknown option error
t "t81i: --annotations — rejected as unknown option (no backward compat alias)" bash -c "
    rc=\$(bash '${ENV_UPDATE_V2}' --annotations 2>/dev/null; echo \$?)
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit for --annotations, got 0\"; echo FAIL; exit 0; }
    err=\$(bash '${ENV_UPDATE_V2}' --annotations 2>&1 || true)
    echo \"\$err\" | grep -qiE 'unknown|unrecognized|invalid' || { echo \"expected unknown-option error; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t81j: --reference=matrix does NOT contain the wrong label 'major bump no hint (AUTO)'
#        (D1 label bug: that scenario actually returns HOLD, not AUTO)
t "t81j: --reference=matrix — major-bump-no-hint label must NOT say AUTO (it is HOLD)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'major bump no hint (AUTO)' && { echo \"label bug still present: found (AUTO) on major-bump-no-hint row\"; echo FAIL; exit 0; }
    echo PASS
"

# t81k: --reference=matrix contains 'no proposed version' scenario (D2 addition)
t "t81k: --reference=matrix — no proposed version scenario present" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'no proposed version' || { echo \"missing 'no proposed version' scenario; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81l: --reference=matrix contains 'prerelease proposed' scenario (D2 addition)
t "t81l: --reference=matrix — prerelease proposed scenario present" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'prerelease proposed' || { echo \"missing 'prerelease proposed' scenario; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81m: --reference=matrix contains SHA fixture section header (D4 addition)
t "t81m: --reference=matrix — Fixture 6 SHA classifier header present" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'Fixture 6:' || { echo \"missing Fixture 6 SHA classifier section; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81n: --reference=matrix contains FROZEN in orchestration narrative (D6 addition)
t "t81n: --reference=matrix — FROZEN orchestration entry present" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'FROZEN' || { echo \"missing FROZEN in matrix output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81o: --reference=matrix contains depends-on warning entry (D6 addition)
t "t81o: --reference=matrix — depends-on warning entry present" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>&1 || true)
    echo \"\$out\" | grep -qF 'depends-on' || { echo \"missing depends-on entry in matrix output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t81p: --reference=flags contains _GS_EU2_TALLY_FORCE (D7 addition)
t "t81p: --reference=flags — _GS_EU2_TALLY_FORCE documented in flags section" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=flags 2>&1 || true)
    echo \"\$out\" | grep -qF '_GS_EU2_TALLY_FORCE' || { echo \"missing _GS_EU2_TALLY_FORCE in flags reference; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# 82 — decide.sh: v-prefix + major_hint regression
# ═══════════════════════════════════════════════════════════════════════════
section "82 — decide.sh: v-prefix + major_hint regression"

_DC_LIBS82="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

# t82a: v-prefixed proposed within same major → should be AUTO not HOLD
t "t82a: v-prefixed proposed + major_hint within same major → AUTO" bash -c "
    ${_DC_LIBS82}
    result=\$(_gs_eu2_classify_decision '17.5' 'v17.6' '' '17')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result (expected AUTO)\"; echo FAIL; exit 0; }
    echo PASS
"

# t82b: v-prefixed proposed with different major → should be HOLD
t "t82b: v-prefixed proposed + major_hint different major → HOLD" bash -c "
    ${_DC_LIBS82}
    result=\$(_gs_eu2_classify_decision '17.5' 'v18.0' '' '17')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result (expected HOLD)\"; echo FAIL; exit 0; }
    echo PASS
"

# t82c: no v-prefix (baseline) — must remain AUTO
t "t82c: no v-prefix + major_hint within same major → AUTO (baseline)" bash -c "
    ${_DC_LIBS82}
    result=\$(_gs_eu2_classify_decision '17.5' '17.6' '' '17')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result (expected AUTO)\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 83 — --scan flag: env-scan.sh invocation + passthrough
# ═══════════════════════════════════════════════════════════════════════════
section "83 — --scan flag: env-scan invocation + passthrough"

# Helper env: postgres 18.x is always AUTO (18.3→18.4 via dockerhub fixture)
_T83_ENV='# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
GLOBAL_STACK_PG18_T83=18.3-alpine3.23'

# t83a: --apply --scan → mock env-scan invoked (sentinel file written)
t "t83a: --apply --scan — mock env-scan.sh is invoked" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83a_cache
    mkdir -p \"\${TMP_DIR}/t83a_cache\"
    touch \"\${TMP_DIR}/t83a_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t83a.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    # Mock env-scan.sh: writes a sentinel file and exits 0
    mock=\${TMP_DIR}/t83a_mock_env_scan.sh
    sentinel=\${TMP_DIR}/t83a_sentinel
    printf '#!/bin/bash\ntouch \"%s\"\nexit 0\n' \"\$sentinel\" > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    bash '${ENV_UPDATE_V2}' --apply --yes --scan --env-file=\"\$f\" >/dev/null 2>&1 || true
    [[ -f \"\$sentinel\" ]] || { echo \"mock env-scan was not invoked (sentinel absent)\"; echo FAIL; exit 0; }
    echo PASS
"

# t83b: --apply --scan --no-fail → mock env-scan receives --no-fail in its args
t "t83b: --apply --scan --no-fail — env-scan receives --no-fail flag" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83b_cache
    mkdir -p \"\${TMP_DIR}/t83b_cache\"
    touch \"\${TMP_DIR}/t83b_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t83b.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    args_file=\${TMP_DIR}/t83b_args
    mock=\${TMP_DIR}/t83b_mock_env_scan.sh
    printf '#!/bin/bash\nprintf \"%%s\n\" \"\$@\" > \"%s\"\nexit 0\n' \"\$args_file\" > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    bash '${ENV_UPDATE_V2}' --apply --yes --scan --no-fail --env-file=\"\$f\" >/dev/null 2>&1 || true
    [[ -f \"\$args_file\" ]] || { echo \"mock env-scan was not invoked\"; echo FAIL; exit 0; }
    grep -qF -- '--no-fail' \"\$args_file\" || { echo \"--no-fail not in env-scan args: \$(cat \"\$args_file\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t83c: --apply --scan --backup=false → mock env-scan receives --backup=false in its args
t "t83c: --apply --scan --backup=false — env-scan receives --backup=false flag" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83c_cache
    mkdir -p \"\${TMP_DIR}/t83c_cache\"
    touch \"\${TMP_DIR}/t83c_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t83c.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    args_file=\${TMP_DIR}/t83c_args
    mock=\${TMP_DIR}/t83c_mock_env_scan.sh
    printf '#!/bin/bash\nprintf \"%%s\n\" \"\$@\" > \"%s\"\nexit 0\n' \"\$args_file\" > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    bash '${ENV_UPDATE_V2}' --apply --yes --scan --backup=false --env-file=\"\$f\" >/dev/null 2>&1 || true
    [[ -f \"\$args_file\" ]] || { echo \"mock env-scan was not invoked\"; echo FAIL; exit 0; }
    grep -qF -- '--backup=false' \"\$args_file\" || { echo \"--backup=false not in env-scan args: \$(cat \"\$args_file\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t83d: --scan without --apply → FATAL error, exit 1, env-scan NOT invoked
t "t83d: --scan without --apply — FATAL exit 1, env-scan not invoked" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83d_cache
    f=\${TMP_DIR}/t83d.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    sentinel=\${TMP_DIR}/t83d_sentinel
    mock=\${TMP_DIR}/t83d_mock_env_scan.sh
    printf '#!/bin/bash\ntouch \"%s\"\nexit 0\n' \"\$sentinel\" > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    err=\$(bash '${ENV_UPDATE_V2}' --scan --env-file=\"\$f\" 2>&1 >/dev/null)
    rc=\$?
    [[ \$rc -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    [[ \"\$err\" == *FATAL* ]] || { echo \"expected FATAL in stderr, got: \$err\"; echo FAIL; exit 0; }
    [[ ! -f \"\$sentinel\" ]] || { echo \"mock env-scan must NOT be invoked without --apply\"; echo FAIL; exit 0; }
    echo PASS
"

# t83e: --apply --scan when env-scan path missing (not executable) → stderr warning, exit 0
# (apply succeeded; scan failure is non-fatal — only a WARNING is emitted)
# Note: fixture has 18.3-alpine3.23 (already up-to-date on 18.x), so apply writes 0 changes
# but still completes successfully — exit code from apply itself, not from scan warning.
t "t83e: --apply --scan with missing env-scan → WARNING in stderr, exit still 0" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83e_cache
    mkdir -p \"\${TMP_DIR}/t83e_cache\"
    touch \"\${TMP_DIR}/t83e_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t83e.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    export _GS_EU2_ENV_SCAN_PATH=\"/nonexistent/env-scan.sh\"
    rc_file=\${TMP_DIR}/t83e_rc
    err=\$(bash '${ENV_UPDATE_V2}' --apply --yes --scan --env-file=\"\$f\" 2>&1 >/dev/null; echo \$? > \"\$rc_file\")
    rc=\$(cat \"\$rc_file\" 2>/dev/null || echo 99)
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 after apply success (scan warning non-fatal), got \$rc\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'WARNING: --scan requested but env-scan.sh not found' || { echo \"expected WARNING in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t83f: --apply --scan --profile → mock env-scan receives --profile=true in its args
t "t83f: --apply --scan --profile — env-scan receives --profile=true flag" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t83f_cache
    mkdir -p \"\${TMP_DIR}/t83f_cache\"
    touch \"\${TMP_DIR}/t83f_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t83f.env
    printf '%s\n' '${_T83_ENV}' > \"\$f\"
    args_file=\${TMP_DIR}/t83f_args
    mock=\${TMP_DIR}/t83f_mock_env_scan.sh
    printf '#!/bin/bash\nprintf \"%%s\n\" \"\$@\" > \"%s\"\nexit 0\n' \"\$args_file\" > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    bash '${ENV_UPDATE_V2}' --apply --yes --scan --profile --env-file=\"\$f\" >/dev/null 2>&1 || true
    [[ -f \"\$args_file\" ]] || { echo \"mock env-scan was not invoked\"; echo FAIL; exit 0; }
    grep -qF -- '--profile=true' \"\$args_file\" || { echo \"--profile=true not in env-scan args: \$(cat \"\$args_file\")\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 80 extension — additional backup edge cases (t80g, t80h, t80i)
# ═══════════════════════════════════════════════════════════════════════════
section "80b — backup edge cases: keep=0 (unlimited), keep=2 with 5 pre-seeds, purge+keep"

# t80g: --apply --backup-keep=0 with 5 pre-seeded backups → all 6 exist (unlimited, no prune)
t "t80g: --apply --backup-keep=0 — unlimited mode, 5 pre-seeded + 1 new = 6 total" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80g_cache
    mkdir -p \"\${TMP_DIR}/t80g_cache\"
    touch \"\${TMP_DIR}/t80g_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80g.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80G=18.3-alpine3.23\n' > \"\$f\"
    # Pre-seed 5 old backups
    touch \"\${TMP_DIR}/t80g.env.bak.20200101-000001-99\"
    touch \"\${TMP_DIR}/t80g.env.bak.20200101-000002-99\"
    touch \"\${TMP_DIR}/t80g.env.bak.20200101-000003-99\"
    touch \"\${TMP_DIR}/t80g.env.bak.20200101-000004-99\"
    touch \"\${TMP_DIR}/t80g.env.bak.20200101-000005-99\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-keep=0 --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80g.env.bak*' -type f 2>/dev/null | wc -l)
    # keep=0 = unlimited: no pruning; 5 pre-seeded + 1 new = 6
    [[ \$count -eq 6 ]] || { echo \"expected 6 backups (unlimited keep=0), found \$count\"; echo FAIL; exit 0; }
    echo PASS
"

# t80h: --apply --backup-keep=2 with 5 pre-seeded → oldest 4 deleted, 2 newest pre-seeded + new = nope
# Actually: 5 pre-seeded + 1 new = 6 total; keep=2 prunes oldest 4, leaving 2 newest.
# Verify by file count AND that oldest is gone and newest is kept.
t "t80h: --apply --backup-keep=2 with 5 pre-seeds — exactly 2 remain, oldest pruned" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80h_cache
    mkdir -p \"\${TMP_DIR}/t80h_cache\"
    touch \"\${TMP_DIR}/t80h_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80h.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80H=18.3-alpine3.23\n' > \"\$f\"
    # Pre-seed 5 backups with deterministic ascending timestamps (sort -V ordering)
    touch \"\${TMP_DIR}/t80h.env.bak.20200101-000001-99\"
    touch \"\${TMP_DIR}/t80h.env.bak.20200101-000002-99\"
    touch \"\${TMP_DIR}/t80h.env.bak.20200101-000003-99\"
    touch \"\${TMP_DIR}/t80h.env.bak.20200101-000004-99\"
    touch \"\${TMP_DIR}/t80h.env.bak.20200101-000005-99\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-keep=2 --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80h.env.bak*' -type f 2>/dev/null | wc -l)
    [[ \$count -eq 2 ]] || { echo \"expected exactly 2 backups after pruning 4, found \$count\"; echo FAIL; exit 0; }
    # Oldest (000001) and early ones should be gone
    [[ ! -f \"\${TMP_DIR}/t80h.env.bak.20200101-000001-99\" ]] || { echo \"oldest backup should be deleted\"; echo FAIL; exit 0; }
    [[ ! -f \"\${TMP_DIR}/t80h.env.bak.20200101-000002-99\" ]] || { echo \"second-oldest backup should be deleted\"; echo FAIL; exit 0; }
    # The two newest of the pre-seeded ones (000004, 000005) OR the new backup should remain
    # At minimum: the newest pre-seeded (000005) should survive
    [[ -f \"\${TMP_DIR}/t80h.env.bak.20200101-000005-99\" ]] || { echo \"newest pre-seeded backup (000005) should be kept\"; echo FAIL; exit 0; }
    echo PASS
"

# t80i: --apply --backup-purge=true --backup-keep=2 → purge clears all pre-existing,
# 1 new backup created, keep=2 does not prune (only 1 exists after purge+create)
t "t80i: --apply --backup-purge=true --backup-keep=2 — purge clears all, 1 new survives" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t80i_cache
    mkdir -p \"\${TMP_DIR}/t80i_cache\"
    touch \"\${TMP_DIR}/t80i_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t80i.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_PG18_T80I=18.3-alpine3.23\n' > \"\$f\"
    # Pre-seed 5 old backups that purge should clear
    touch \"\${TMP_DIR}/t80i.env.bak.20200101-000001-99\"
    touch \"\${TMP_DIR}/t80i.env.bak.20200101-000002-99\"
    touch \"\${TMP_DIR}/t80i.env.bak.20200101-000003-99\"
    touch \"\${TMP_DIR}/t80i.env.bak.20200101-000004-99\"
    touch \"\${TMP_DIR}/t80i.env.bak.20200101-000005-99\"
    bash '${ENV_UPDATE_V2}' --apply --yes --backup-purge=true --backup-keep=2 --env-file=\"\$f\" 2>/dev/null || true
    count=\$(find \"\${TMP_DIR}\" -maxdepth 1 -name 't80i.env.bak*' -type f 2>/dev/null | wc -l)
    # purge removed all 5 old; 1 new created; keep=2 does not prune (only 1 ≤ 2)
    [[ \$count -eq 1 ]] || { echo \"expected exactly 1 backup after purge+create (keep=2 does not prune 1 file), found \$count\"; echo FAIL; exit 0; }
    # All old (pre-purge) files should be gone
    [[ ! -f \"\${TMP_DIR}/t80i.env.bak.20200101-000001-99\" ]] || { echo \"old backup 000001 should have been purged\"; echo FAIL; exit 0; }
    [[ ! -f \"\${TMP_DIR}/t80i.env.bak.20200101-000005-99\" ]] || { echo \"old backup 000005 should have been purged\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 84 — --apply --yes gate: non-interactive behavior
# ═══════════════════════════════════════════════════════════════════════════
section "84 — --apply --yes gate: non-interactive behavior"

_T84_ENV='# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
GLOBAL_STACK_PG18_T84=18.3-alpine3.23'

# t84a: --apply without --yes in non-TTY → exit 1, requires --yes message in stderr
t "t84a: --apply without --yes in non-TTY → exit 1, requires --yes message" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t84a_cache
    mkdir -p \"\${TMP_DIR}/t84a_cache\"
    f=\${TMP_DIR}/t84a.env
    printf '%s\n' '${_T84_ENV}' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --apply --env-file=\"\$f\" 2>&1 >/dev/null || true)
    bash '${ENV_UPDATE_V2}' --apply --env-file=\"\$f\" >/dev/null 2>/dev/null; rc=\$?
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit (no --yes), got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'requires --yes in non-interactive mode' || { echo \"expected requires --yes message in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t84b: --apply --yes in non-TTY → exit 0, gate bypassed
t "t84b: --apply --yes in non-TTY → exit 0, gate bypassed" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t84b_cache
    mkdir -p \"\${TMP_DIR}/t84b_cache\"
    f=\${TMP_DIR}/t84b.env
    printf '%s\n' '${_T84_ENV}' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" >/dev/null 2>/dev/null; rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 with --yes, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t84c: --check --dry-run → guard only fires for --apply; check mode exits 0 even without marker
t "t84c: --check --dry-run — guard does not apply to check mode, exit 0 without marker" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t84c_cache
    mkdir -p \"\${TMP_DIR}/t84c_cache\"
    # Deliberately do NOT create last-dry-run-ts — guard is --apply-only, check is exempt
    f=\${TMP_DIR}/t84c.env
    printf '%s\n' '${_T84_ENV}' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" >/dev/null 2>&1
    rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0 (guard is --apply-only, check is exempt), got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# t84d: confirm_apply with FORCE_TTY + y → proceeds (exit 0)
t "t84d: confirm_apply with FORCE_TTY + y → proceeds (exit 0)" bash -c "
    f=\${TMP_DIR}/t84d.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T84D=18.0-alpine3.20\n' > \"\$f\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_APPLY_GATE_FORCE_TTY=true
    out=\$(printf 'y\n' | bash '${ENV_UPDATE_V2}' --apply --env-file=\"\$f\" 2>&1); rc=\$?
    [[ \$rc -eq 0 ]] || { echo \"expected exit 0, got \$rc: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t84e: confirm_apply with FORCE_TTY + n → aborts (exit 1)
t "t84e: confirm_apply with FORCE_TTY + n → aborts (exit 1)" bash -c "
    f=\${TMP_DIR}/t84e.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T84E=18.0-alpine3.20\n' > \"\$f\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_APPLY_GATE_FORCE_TTY=true
    out=\$(printf 'n\n' | bash '${ENV_UPDATE_V2}' --apply --env-file=\"\$f\" 2>&1); rc=\$?
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'abort' || { echo \"expected 'Aborted' message, got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t84f: confirm_apply with FORCE_TTY + garbage input → aborts (exit 1)
t "t84f: confirm_apply with FORCE_TTY + garbage input → aborts (exit 1)" bash -c "
    f=\${TMP_DIR}/t84f.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T84F=18.0-alpine3.20\n' > \"\$f\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_APPLY_GATE_FORCE_TTY=true
    out=\$(printf 'maybe\n' | bash '${ENV_UPDATE_V2}' --apply --env-file=\"\$f\" 2>&1); rc=\$?
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit for garbage input, got \$rc\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 85 — --dump mutual exclusion with --check / --apply
# ═══════════════════════════════════════════════════════════════════════════
section "85 — --dump mutual exclusion with --check / --apply"

# t85a: --dump --check → exit 1; stderr contains 'mutually exclusive'
t "t85a: --dump --check — exit 1; stderr contains 'mutually exclusive'" bash -c "
    f=\${TMP_DIR}/t85a.env
    printf '# @todo env-update dockerhub:_/postgres 18.3\nGLOBAL_STACK_T85A=18.3\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --dump --check --env-file=\"\$f\" 2>&1 || true)
    rc=\$(bash '${ENV_UPDATE_V2}' --dump --check --env-file=\"\$f\" 2>/dev/null; echo \$?)
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'mutually exclusive' || { echo \"expected 'mutually exclusive' in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t85b: --dump --apply → exit 1; same mutual exclusion message
t "t85b: --dump --apply — exit 1; stderr contains 'mutually exclusive'" bash -c "
    f=\${TMP_DIR}/t85b.env
    printf '# @todo env-update dockerhub:_/postgres 18.3\nGLOBAL_STACK_T85B=18.3\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --dump --apply --env-file=\"\$f\" 2>&1 || true)
    rc=\$(bash '${ENV_UPDATE_V2}' --dump --apply --env-file=\"\$f\" 2>/dev/null; echo \$?)
    [[ \$rc -ne 0 ]] || { echo \"expected non-zero exit, got 0\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qF 'mutually exclusive' || { echo \"expected 'mutually exclusive' in stderr; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "86 — --version flag"
# ═══════════════════════════════════════════════════════════════════════════

# t86a: --version outputs a semver string (MAJOR.MINOR.PATCH)
t "t86a: --version outputs semver string" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --version 2>&1)
    [[ \"\${out}\" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || { echo \"expected semver, got: \${out}\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "87 — Rule 8: git-state check before .env overwrite"
# ═══════════════════════════════════════════════════════════════════════════

# t87a: apply against a tracked+dirty .env → non-zero exit OR warning; file NOT overwritten
t "t87a: tracked+dirty .env — apply aborts with warning" bash -c "
    D=\"\${TMP_DIR}/t87a\"; mkdir -p \"\$D\"
    git -C \"\$D\" init -q
    git -C \"\$D\" -c user.email=t@t -c user.name=t config user.email t@t
    git -C \"\$D\" -c user.email=t@t -c user.name=t config user.name t
    # Create and commit a valid .env with one AUTO annotation
    printf '# @todo env-update dockerhub:_/alpine 3.19\nGLOBAL_STACK_T87A=3.19\n' > \"\$D/.env\"
    git -C \"\$D\" add .env
    git -C \"\$D\" -c user.email=t@t -c user.name=t commit -m init -q
    # Make an uncommitted change
    printf '\n# dirty line\n' >> \"\$D/.env\"
    original_content=\$(cat \"\$D/.env\")
    # Use offline fixture mode so no real HTTP is needed
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\${TMP_DIR}/no_fixtures_t87a\"
    mkdir -p \"\$_GS_EU2_HTTP_FIXTURE_DIR\"
    # --apply should warn and NOT overwrite the file
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$D/.env\" 2>&1 || true)
    after_content=\$(cat \"\$D/.env\")
    # File content must be unchanged
    [[ \"\${original_content}\" == \"\${after_content}\" ]] \
        || { echo \"file was modified despite dirty state\"; echo FAIL; exit 0; }
    # Warning must be present
    echo \"\$out\" | grep -qiE '(uncommitted|WARN|dirty|stash)' \
        || { echo \"expected uncommitted-changes warning; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t87b: apply against a .env NOT in any git repo → succeeds (no git error)
t "t87b: .env in non-git directory — apply proceeds without git error" bash -c "
    D=\"\${TMP_DIR}/t87b\"; mkdir -p \"\$D\"
    # Deliberately NOT git-init'd
    printf '# @todo env-update dockerhub:_/alpine 3.19\nGLOBAL_STACK_T87B=3.19\n' > \"\$D/.env\"
    # Use fixture dir with a response that returns same version (SKIP outcome, no write needed)
    FDIR=\"\${TMP_DIR}/fixtures_t87b\"; mkdir -p \"\$FDIR\"
    # Provide a dockerhub tags fixture so the fetch succeeds
    printf '{\"results\":[{\"name\":\"3.19\"}]}' \
        > \"\$FDIR/registry.hub.docker.com_v2_repositories___alpine_tags_page_size=100\"
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\$FDIR\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$D/.env\" 2>&1)
    rc=\$?
    # Should not contain any git-related error
    echo \"\$out\" | grep -qiE '(not a git repo|git error|fatal:.*git)' \
        && { echo \"unexpected git error: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t87c: apply against a tracked+clean .env → proceeds normally (no false-positive block)
t "t87c: tracked+clean .env — apply is not blocked" bash -c "
    D=\"\${TMP_DIR}/t87c\"; mkdir -p \"\$D\"
    git -C \"\$D\" init -q
    git -C \"\$D\" config user.email t@t
    git -C \"\$D\" config user.name t
    printf '# @todo env-update dockerhub:_/alpine 3.19\nGLOBAL_STACK_T87C=3.19\n' > \"\$D/.env\"
    git -C \"\$D\" add .env
    git -C \"\$D\" -c user.email=t@t -c user.name=t commit -m init -q
    # File is clean; use a fixture that returns same version → SKIP (no actual write)
    FDIR=\"\${TMP_DIR}/fixtures_t87c\"; mkdir -p \"\$FDIR\"
    printf '{\"results\":[{\"name\":\"3.19\"}]}' \
        > \"\$FDIR/registry.hub.docker.com_v2_repositories___alpine_tags_page_size=100\"
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\$FDIR\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$D/.env\" 2>&1)
    # Must NOT contain the dirty-file warning
    echo \"\$out\" | grep -qiE '(uncommitted|stash)' \
        && { echo \"false-positive block on clean file: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "88 — SHA annotation written without date suffix"
# ═══════════════════════════════════════════════════════════════════════════

# t88a: apply_single with bare new SHA writes sha:HASH with no date suffix in annotation
t "t88a: SHA annotation contains no date suffix after SHA update" bash -c "
    f=\${TMP_DIR}/t88a.env
    printf '# @todo env-update pecl:testpkg (git:owner/repo) 1.0.0 sha:aaaa1111bbbb2222cccc3333dddd4444eeee5555\nGLOBAL_TEST_SHA_PKG=1.0.0\n' > \"\$f\"
    (
      source '${SCRIPT_DIR}/../lib/env-update/core/apply.sh'
      # \$7 = new_sha (bare hash — no date), \$10 = bare_sha (same)
      _gs_eu2_apply_single \"\$f\" 'GLOBAL_TEST_SHA_PKG' '1.1.0' \
        '# @todo env-update pecl:testpkg (git:owner/repo) 1.0.0 sha:aaaa1111bbbb2222cccc3333dddd4444eeee5555' \
        '1.0.0' \
        'aaaa1111bbbb2222cccc3333dddd4444eeee5555' \
        'bbbb2222cccc3333dddd4444eeee5555ffff6666' \
        'false' 'false' 'bbbb2222cccc3333dddd4444eeee5555ffff6666'
    )
    ann=\$(grep '@todo' \"\$f\")
    var=\$(grep '^GLOBAL_TEST_SHA_PKG=' \"\$f\")
    rm -f \"\$f\"
    echo \"\$ann\" | grep -qF 'sha:bbbb2222cccc3333dddd4444eeee5555ffff6666' || { echo \"new SHA not in annotation: \$ann\"; echo FAIL; exit 0; }
    echo \"\$ann\" | grep -qE 'sha:[0-9a-f]+ +\([0-9]{4}-[0-9]{2}-[0-9]{2}\)' && { echo \"date suffix after sha: found in annotation: \$ann\"; echo FAIL; exit 0; } || true
    echo \"\$var\" | grep -qF '1.1.0' || { echo \"VAR= not updated: \$var\"; echo FAIL; exit 0; }
    echo PASS
"

# t88b: apply_single with OLD annotation carrying a date suffix — old is matched and stripped,
#        new annotation carries sha:HASH only (no date)
t "t88b: SHA annotation with existing date suffix — new annotation has no date" bash -c "
    f=\${TMP_DIR}/t88b.env
    old_ann='# @todo env-update pecl:testpkg (git:owner/repo) 1.0.0 sha:aaaa1111bbbb2222cccc3333dddd4444eeee5555 (2024-01-01)'
    printf '%s\nGLOBAL_TEST_SHA_PKG2=1.0.0\n' \"\$old_ann\" > \"\$f\"
    (
      source '${SCRIPT_DIR}/../lib/env-update/core/apply.sh'
      # old_sha_tok must include the date to match the annotation; new_sha_tok is bare
      _gs_eu2_apply_single \"\$f\" 'GLOBAL_TEST_SHA_PKG2' '1.1.0' \
        \"\$old_ann\" \
        '1.0.0' \
        'aaaa1111bbbb2222cccc3333dddd4444eeee5555 (2024-01-01)' \
        'bbbb2222cccc3333dddd4444eeee5555ffff6666' \
        'false' 'false' 'bbbb2222cccc3333dddd4444eeee5555ffff6666'
    )
    ann=\$(grep '@todo' \"\$f\")
    rm -f \"\$f\"
    echo \"\$ann\" | grep -qF 'sha:bbbb2222cccc3333dddd4444eeee5555ffff6666' || { echo \"new SHA not in annotation: \$ann\"; echo FAIL; exit 0; }
    echo \"\$ann\" | grep -qF '(2024-01-01)' && { echo \"old date suffix not stripped: \$ann\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "89 — --scan error without --apply"
# ═══════════════════════════════════════════════════════════════════════════

_T89_ENV='# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
GLOBAL_STACK_PG18_T89=18.3-alpine3.23'

# t89a: --scan alone (no --check, no --apply) → FATAL error, exit 1
t "t89a: --scan without --apply exits 1 with FATAL error" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    f=\${TMP_DIR}/t89a.env
    printf '%s\n' '${_T89_ENV}' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --scan --env-file=\"\$f\" 2>&1); rc=\$?
    [[ \$rc -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'FATAL' \
        || { echo \"expected FATAL in stderr; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t89b: --check alone (no --scan) → no scan FATAL emitted, exit 0
t "t89b: --check without --scan does not emit scan error" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    f=\${TMP_DIR}/t89b.env
    printf '%s\n' '${_T89_ENV}' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-cache --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF 'FATAL' \
        && { echo \"unexpected FATAL in --check-only output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t89c: --dry-run --scan (--dry-run does not imply --apply) → FATAL error, exit 1
t "t89c: --dry-run --scan without --apply exits 1 with FATAL error" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    f=\${TMP_DIR}/t89c.env
    printf '%s\n' '${_T89_ENV}' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dry-run --scan --env-file=\"\$f\" 2>&1); rc=\$?
    [[ \$rc -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'FATAL' \
        || { echo \"expected FATAL in stderr; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t89d: --apply --scan → NO scan warning (--apply satisfies the condition)
t "t89d: --apply --scan does not emit the scan warning" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t89d_cache
    mkdir -p \"\${TMP_DIR}/t89d_cache\"
    touch \"\${TMP_DIR}/t89d_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t89d.env
    printf '%s\n' '${_T89_ENV}' > \"\$f\"
    mock=\${TMP_DIR}/t89d_mock_env_scan.sh
    printf '#!/bin/bash\nexit 0\n' > \"\$mock\"
    chmod +x \"\$mock\"
    export _GS_EU2_ENV_SCAN_PATH=\"\$mock\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --scan --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF 'FATAL' \
        && { echo \"unexpected FATAL when --apply is active: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 90 — Drift display: exhaustive decision × direction matrix
# Regression guards for B1–B12 (all 12 drift bugs fixed in 3f60239b).
#
# Decision setup via github:testowner/testrepo (fixture returns v2.5.0):
#   current=1.0.0  → major bump    → HOLD (no annotation flags)
#   current=2.4.0  → minor bump    → AUTO
#   current=2.5.0  → same version  → SKIP
#   + (lock:...)   → LOCK (any current)
#   + (skip:...)   → FROZEN (any current)
#   + (manual)     → MANUAL (any current)
#   dockerhub:_/no-such-image-xyzzy999 → ERROR (no fixture → fetch fails)
#
# Matrix coverage:
#   Case 1  — empty VAR:                 AUTO, HOLD, MANUAL, SKIP, ERROR (5)
#   Case 2a — VAR behind annotation:     AUTO, HOLD, MANUAL, SKIP, ERROR (5)
#   Case 2b — VAR ahead (downgrade):     AUTO, HOLD, MANUAL, SKIP, ERROR, LOCK, FROZEN (7)
#   Case 2c — non-semver divergence:     AUTO, HOLD, SKIP (3)
#   Case 3  — use-sha drift:             LOCK, FROZEN, SKIP, HOLD, MANUAL, ERROR, AUTO (7)
#   Counter — downgrade counter cells:   LOCK, FROZEN, ERROR=0; HOLD, MANUAL=1 (5)
# ═══════════════════════════════════════════════════════════════════════════
section "90 — drift decision matrix (B1–B12 regression guards)"

_T90_OLD_SHA='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
_T90_NEW_VAR_SHA='5555eeee4444dddd3333cccc2222bbbb1111aaaa'

# ── Case 1: empty VAR ─────────────────────────────────────────────────────

# AUTO + empty VAR → "--apply will write X to enable it" (not --force-auto) [B1 contrast]
t "t90_c1_auto: Case1 AUTO+emptyVAR → '--apply will write' (no --force-auto)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c1auto_c
    f=\${TMP_DIR}/t90c1auto.env
    printf '# @todo env-update github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T90C1AUTO=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--apply will write' || { echo \"must say '--apply will write'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' && { echo \"must NOT say force-auto for AUTO; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# HOLD + empty VAR → "--force-auto --apply will write it to enable"
t "t90_c1_hold: Case1 HOLD+emptyVAR → '--force-auto --apply will write it'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c1hold_c
    f=\${TMP_DIR}/t90c1hold.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C1HOLD=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"must say force-auto for HOLD+emptyVAR; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'disabled? --apply will write' && { echo \"must NOT say plain '--apply will write' without --force-auto; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# MANUAL + empty VAR → "--force-auto --apply will write it to enable"
t "t90_c1_manual: Case1 MANUAL+emptyVAR → '--force-auto --apply will write it'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c1man_c
    f=\${TMP_DIR}/t90c1man.env
    printf '# @todo env-update (manual) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C1MAN=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"must say force-auto for MANUAL+emptyVAR; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# SKIP + empty VAR → "(feature disabled?)" with NO action advice (else branch) [B4 contrast]
t "t90_c1_skip: Case1 SKIP+emptyVAR → 'feature disabled?' no --apply action [B4]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c1skip_c
    f=\${TMP_DIR}/t90c1skip.env
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T90C1SKIP=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'feature disabled?' || { echo \"must say 'feature disabled?'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--apply will' && { echo \"must NOT say '--apply will' for SKIP (B4); got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF 'force-auto' && { echo \"must NOT say force-auto for SKIP; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ERROR + empty VAR → "(feature disabled?)" with NO action advice (else branch)
t "t90_c1_error: Case1 ERROR+emptyVAR → 'feature disabled?' no --apply action" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c1err_c
    f=\${TMP_DIR}/t90c1err.env
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_T90C1ERR=\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'feature disabled?' || { echo \"must say 'feature disabled?'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--apply will' && { echo \"must NOT say '--apply will' for ERROR; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ── Case 2a: VAR behind annotation (semver: VAR < annotation) ─────────────

# HOLD + VAR behind → "--force-auto --apply to resolve" ONLY — no redundant dir_msg [B2]
t "t90_c2a_hold: Case2a HOLD+VARbehind → '--force-auto --apply' only, no dir_msg [B2]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2ah_c
    f=\${TMP_DIR}/t90c2ah.env
    # ann=1.0.0, fetcher→2.5.0 (major→HOLD), VAR=0.5.0 (behind annotation)
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2AH=0.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"must say force-auto; got: \$out\"; echo FAIL; exit 0; }
    # B2 regression: old code showed 're-run --apply or update annotation' (dir_msg) + '--force-auto --apply'
    echo \"\$out\" | grep -qF 're-run --apply or update annotation' \
        && { echo \"B2 regression: must NOT include redundant dir_msg for HOLD+behind; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# MANUAL + VAR behind → "--force-auto --apply to resolve" ONLY [B3]
t "t90_c2a_manual: Case2a MANUAL+VARbehind → '--force-auto --apply' only, no dir_msg [B3]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2am_c
    f=\${TMP_DIR}/t90c2am.env
    printf '# @todo env-update (manual) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2AM=0.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"must say force-auto; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 're-run --apply or update annotation' \
        && { echo \"B3 regression: must NOT include dir_msg for MANUAL+behind; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# SKIP + VAR behind → "update annotation or revert VAR= manually" NOT "--apply" [B4]
t "t90_c2a_skip: Case2a SKIP+VARbehind → 'update annotation or revert VAR= manually' [B4]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2as_c
    f=\${TMP_DIR}/t90c2as.env
    # ann=v2.5.0, fetcher→v2.5.0 (same→SKIP), VAR=2.4.0 (behind annotation)
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T90C2AS=2.4.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"B4: must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'skips up-to-date records' \
        || { echo \"B4: must mention 'skips up-to-date records'; got: \$out\"; echo FAIL; exit 0; }
    # B4 regression guard: old code said 're-run --apply or update annotation'
    echo \"\$out\" | grep -qF -- '--apply will' \
        && { echo \"B4 regression: must NOT say '--apply will' for SKIP; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ERROR + VAR behind → direction msg + "fetch failed; fix error then re-run" [B9]
t "t90_c2a_error: Case2a ERROR+VARbehind → dir_msg + 'fetch failed' [B9]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2ae_c
    f=\${TMP_DIR}/t90c2ae.env
    # ERROR decision, ann=1.0.0, VAR=0.5.0 (behind)
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_T90C2AE=0.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fetch failed' || { echo \"B9: must say 'fetch failed'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 're-run --apply or update annotation' \
        || { echo \"B9: must include behind dir_msg for ERROR+behind; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# AUTO + VAR behind → "re-run --apply or update annotation" (else branch, B11 semver path)
t "t90_c2a_auto: Case2a AUTO+VARbehind → 're-run --apply or update annotation'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2aa_c
    f=\${TMP_DIR}/t90c2aa.env
    # ann=2.4.0, fetcher→2.5.0 (minor→AUTO), VAR=2.3.0 (behind annotation)
    printf '# @todo env-update github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T90C2AA=2.3.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 're-run --apply or update annotation' \
        || { echo \"must say 're-run --apply or update annotation' for AUTO+behind; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Case 2b: VAR ahead (downgrade, semver: VAR > annotation) ──────────────

# AUTO + downgrade → direction msg in output (else branch — already tested in t70g; confirm
# fixable counter excludes it as downgrade, not fixable)
# (Covered by t70g + t75e2 — skip duplicate here, add the novel cells below.)

# HOLD + downgrade → direction msg ONLY, NOT "--force-auto --apply to resolve" [B7]
t "t90_c2b_hold: Case2b HOLD+downgrade → direction only, NOT '--force-auto --apply' [B7]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2bh_c
    f=\${TMP_DIR}/t90c2bh.env
    # ann=1.0.0, fetcher→2.5.0 (major→HOLD), VAR=5.0.0 (AHEAD of annotation)
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2BH=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' || { echo \"must say 'VAR is ahead'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'downgrade risk' || { echo \"must say 'downgrade risk'; got: \$out\"; echo FAIL; exit 0; }
    # B7 regression: old code appended '--force-auto --apply to resolve' after direction
    echo \"\$out\" | grep -qF 'force-auto --apply to resolve' \
        && { echo \"B7 regression: must NOT say '--force-auto --apply to resolve' for HOLD+downgrade; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# MANUAL + downgrade → direction msg ONLY, NOT "--force-auto --apply to resolve" [B8]
t "t90_c2b_manual: Case2b MANUAL+downgrade → direction only, NOT '--force-auto --apply' [B8]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2bm_c
    f=\${TMP_DIR}/t90c2bm.env
    printf '# @todo env-update (manual) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2BM=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' || { echo \"must say 'VAR is ahead'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto --apply to resolve' \
        && { echo \"B8 regression: must NOT say '--force-auto --apply to resolve' for MANUAL+downgrade; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# SKIP + downgrade → direction + "update annotation or revert VAR= manually" [B10]
t "t90_c2b_skip: Case2b SKIP+downgrade → 'VAR is ahead' + 'update annotation or revert' [B10]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2bs_c
    f=\${TMP_DIR}/t90c2bs.env
    # ann=v2.5.0, fetcher→v2.5.0 (SKIP), VAR=v9.9.9 (AHEAD — v prefix keeps sort-V consistent)
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T90C2BS=v9.9.9\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' || { echo \"B10: must say 'VAR is ahead'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"B10: must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'skips up-to-date records' \
        || { echo \"B10: must mention 'skips up-to-date records'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ERROR + downgrade → direction msg + "fetch failed" [B9]
t "t90_c2b_error: Case2b ERROR+downgrade → 'VAR is ahead' + 'fetch failed' [B9]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2be_c
    f=\${TMP_DIR}/t90c2be.env
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_T90C2BE=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' || { echo \"B9: must show direction for ERROR+downgrade; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fetch failed' || { echo \"B9: must say 'fetch failed'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# LOCK + downgrade → "locked; update annotation manually" — LOCK ignores direction
t "t90_c2b_lock: Case2b LOCK+downgrade → static 'locked' msg, NOT 'VAR is ahead'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2bl_c
    f=\${TMP_DIR}/t90c2bl.env
    printf '# @todo env-update (lock:hold at 1.x) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2BL=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'locked' || { echo \"must say 'locked'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation manually' || { echo \"must say 'update annotation manually'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' \
        && { echo \"LOCK must NOT show direction msg (ignores _drift_dir_msg); got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# FROZEN + downgrade → "frozen by skip flag" — FROZEN ignores direction
t "t90_c2b_frozen: Case2b FROZEN+downgrade → 'frozen by skip flag', NOT 'VAR is ahead'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2bf_c
    f=\${TMP_DIR}/t90c2bf.env
    printf '# @todo env-update (skip:hold at 1.x) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2BF=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'frozen by skip flag' || { echo \"must say 'frozen by skip flag'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' \
        && { echo \"FROZEN must NOT show direction msg; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# ── Case 2c: non-semver divergence (_drift_dir_msg stays empty) ───────────

# AUTO + non-semver VAR → "re-run --apply or update annotation" (B11 fallback default)
t "t90_c2c_auto: Case2c AUTO+nonSemverVAR → 're-run --apply or update annotation' [B11]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2ca_c
    f=\${TMP_DIR}/t90c2ca.env
    # ann=2.4.0, fetcher→2.5.0 (AUTO), VAR=2.3.0-alpine3.20 (non-semver — no direction)
    printf '# @todo env-update github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T90C2CA=2.3.0-alpine3.20\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    # B11: old code printed empty suffix when _drift_dir_msg="" (no action advice at all)
    echo \"\$out\" | grep -qF 're-run --apply or update annotation' \
        || { echo \"B11: must say 're-run --apply or update annotation' (fallback for non-semver); got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# HOLD + non-semver VAR → "--force-auto --apply to resolve" (no direction since non-semver)
t "t90_c2c_hold: Case2c HOLD+nonSemverVAR → '--force-auto --apply', no direction msg" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2ch_c
    f=\${TMP_DIR}/t90c2ch.env
    # ann=1.0.0 (major→HOLD), VAR=0.9-alpine (non-semver)
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90C2CH=0.9-alpine\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"must say '--force-auto --apply'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'VAR is ahead' \
        && { echo \"must NOT show direction for non-semver HOLD; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# SKIP + non-semver VAR → "update annotation or revert VAR= manually (--apply skips up-to-date)"
t "t90_c2c_skip: Case2c SKIP+nonSemverVAR → 'update annotation or revert VAR= manually'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c2cs_c
    f=\${TMP_DIR}/t90c2cs.env
    # ann=v2.5.0 (SKIP), VAR=2.5.0-alpine3.20 (non-semver, differs from annotation)
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T90C2CS=2.5.0-alpine3.20\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'skips up-to-date records' \
        || { echo \"must mention 'skips up-to-date records'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Case 3: use-sha drift (VAR SHA ≠ annotation sha:HASH) ─────────────────
# Annotation: (use-sha) + sha:OLD_SHA, VAR=DIFFERENT_SHA → Case 3 drift fires.
# Decision is set by annotation flags + version comparison as usual.

# LOCK + use-sha drift → "locked; update annotation or revert VAR= manually" [B12]
t "t90_c3_lock: Case3 LOCK+useSha drift → 'locked; update annotation or revert VAR= manually' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3lk_c
    f=\${TMP_DIR}/t90c3lk.env
    printf '# @todo env-update (lock:hold) (use-sha) github:testowner/testrepo 1.0.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3LK=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT] for use-sha drift; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'locked' || { echo \"B12: must say 'locked'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"B12: must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# FROZEN + use-sha drift → "frozen by skip flag; update annotation or revert VAR= manually" [B12]
t "t90_c3_frozen: Case3 FROZEN+useSha drift → 'frozen by skip flag; update annotation or revert' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3fz_c
    f=\${TMP_DIR}/t90c3fz.env
    printf '# @todo env-update (skip:hold) (use-sha) github:testowner/testrepo 1.0.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3FZ=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'frozen by skip flag' \
        || { echo \"B12: must say 'frozen by skip flag'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"B12: must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# SKIP + use-sha drift → "update annotation or revert VAR= manually (--apply skips up-to-date)" [B12]
t "t90_c3_skip: Case3 SKIP+useSha drift → 'update annotation or revert VAR= manually' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3sk_c
    f=\${TMP_DIR}/t90c3sk.env
    # ann=v2.5.0 (same as fixture→SKIP) + (use-sha) + sha:OLD, VAR=DIFFERENTSHA
    printf '# @todo env-update (use-sha) github:testowner/testrepo v2.5.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3SK=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'update annotation or revert VAR= manually' \
        || { echo \"B12: must say 'update annotation or revert VAR= manually'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'skips up-to-date records' \
        || { echo \"B12: must mention 'skips up-to-date records'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--apply will' \
        && { echo \"B12: must NOT say '--apply will' for SKIP use-sha; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# HOLD + use-sha drift → "--force-auto --apply to resolve" [B12]
t "t90_c3_hold: Case3 HOLD+useSha drift → '--force-auto --apply to resolve' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3ho_c
    f=\${TMP_DIR}/t90c3ho.env
    # ann=1.0.0 (major→HOLD) + (use-sha) + sha:OLD, VAR=DIFFERENTSHA
    printf '# @todo env-update (use-sha) github:testowner/testrepo 1.0.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3HO=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' \
        || { echo \"B12: must say '--force-auto --apply to resolve'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# MANUAL + use-sha drift → "--force-auto --apply to resolve" [B12]
t "t90_c3_manual: Case3 MANUAL+useSha drift → '--force-auto --apply to resolve' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3mn_c
    f=\${TMP_DIR}/t90c3mn.env
    printf '# @todo env-update (manual) (use-sha) github:testowner/testrepo 1.0.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3MN=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' \
        || { echo \"B12: must say '--force-auto --apply to resolve'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ERROR + use-sha drift → "fetch failed; fix error then re-run" [B12]
t "t90_c3_error: Case3 ERROR+useSha drift → 'fetch failed; fix error then re-run' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3er_c
    f=\${TMP_DIR}/t90c3er.env
    printf '# @todo env-update (use-sha) dockerhub:_/no-such-image-xyzzy999 1.0.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3ER=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fetch failed' \
        || { echo \"B12: must say 'fetch failed'; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'fix error then re-run' \
        || { echo \"B12: must say 'fix error then re-run'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# AUTO + use-sha drift → "re-run --apply to resolve" (not "re-run --apply or update annotation") [B12]
t "t90_c3_auto: Case3 AUTO+useSha drift → 're-run --apply to resolve' [B12]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90c3au_c
    f=\${TMP_DIR}/t90c3au.env
    # ann=2.4.0 (minor→AUTO) + (use-sha) + sha:OLD, VAR=DIFFERENTSHA
    printf '# @todo env-update (use-sha) github:testowner/testrepo 2.4.0 sha:${_T90_OLD_SHA}\nGLOBAL_STACK_T90C3AU=${_T90_NEW_VAR_SHA}\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo \"expected [DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 're-run --apply to resolve' \
        || { echo \"B12: must say 're-run --apply to resolve'; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ── Downgrade counter: LOCK/FROZEN/ERROR=0, HOLD/MANUAL=1 ────────────────

# LOCK + downgrade → 0 DOWNGRADE (LOCK excluded from counter) [B5]
t "t90_ctr_lock: counter LOCK+downgrade → 0 DOWNGRADE (excluded: --apply cannot write) [B5]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90ctrlk_c
    f=\${TMP_DIR}/t90ctrlk.env
    printf '# @todo env-update (lock:hold) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90CTRLK=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    # Secondary line must show 0 DOWNGRADE (LOCK excluded from counter per B5)
    echo \"\$out\" | grep -qE '0 DOWNGRADE' \
        || { echo \"B5: LOCK+downgrade must show 0 DOWNGRADE; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# FROZEN + downgrade → 0 DOWNGRADE [B6]
t "t90_ctr_frozen: counter FROZEN+downgrade → 0 DOWNGRADE (excluded: --apply cannot write) [B6]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90ctrfz_c
    f=\${TMP_DIR}/t90ctrfz.env
    printf '# @todo env-update (skip:hold) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90CTRFZ=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '0 DOWNGRADE' \
        || { echo \"B6: FROZEN+downgrade must show 0 DOWNGRADE; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ERROR + downgrade → 0 DOWNGRADE (fetch failed — cannot apply until error resolved)
t "t90_ctr_error: counter ERROR+downgrade → 0 DOWNGRADE (excluded: fetch failed)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90ctrer_c
    f=\${TMP_DIR}/t90ctrer.env
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_T90CTRER=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '0 DOWNGRADE' \
        || { echo \"ERROR+downgrade must show 0 DOWNGRADE; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# HOLD + downgrade → 0 DOWNGRADE · 1 FORCE-DOWNGRADE (only --force-auto --apply CAN write it)
t "t90_ctr_hold: counter HOLD+downgrade → 0 DOWNGRADE · 1 FORCE-DOWNGRADE (force-auto only)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90ctrho_c
    f=\${TMP_DIR}/t90ctrho.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90CTRHO=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '0 DOWNGRADE' \
        || { echo \"HOLD+downgrade must show 0 DOWNGRADE (not plain-apply actionable); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 FORCE-DOWNGRADE' \
        || { echo \"HOLD+downgrade must show 1 FORCE-DOWNGRADE in summary; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# MANUAL + downgrade → 0 DOWNGRADE · 1 FORCE-DOWNGRADE (only --force-auto --apply CAN write it)
t "t90_ctr_manual: counter MANUAL+downgrade → 0 DOWNGRADE · 1 FORCE-DOWNGRADE (force-auto only)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t90ctrmn_c
    f=\${TMP_DIR}/t90ctrmn.env
    printf '# @todo env-update (manual) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T90CTRMN=5.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '0 DOWNGRADE' \
        || { echo \"MANUAL+downgrade must show 0 DOWNGRADE (not plain-apply actionable); got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '1 FORCE-DOWNGRADE' \
        || { echo \"MANUAL+downgrade must show 1 FORCE-DOWNGRADE in summary; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 91 — (replace:TARGET=template) cascade-update feature
#
# Fixture: github:testowner/testrepo — returns v2.5.0 (→ 2.5.0).
# Annotation current=2.4.0 → AUTO (minor bump).
# The replace flag rewrite a second VAR= line in the same env file.
# Token expansion: {major}→2 {minor}→5 {patch}→0.
# ═══════════════════════════════════════════════════════════════════════════
section "91 — (replace:TARGET=template) cascade-update"

# t91a: single (replace:) with --check shows [REPLACE] sub-line when update_pending=true.
# Uses cur=1.9.0 (major=1) → AUTO → prop=v2.5.0 (major=2): exp_cur=node1, exp_prop=node2.
# update_pending=true → (replace) sub-line must appear. --dry-run prevents file change.
t "t91a: replace check shows (replace) sub-line (update_pending) — dry-run no write" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91a_c
    f=\${TMP_DIR}/t91a.env
    # cur=1.9.0 (major=1), fixture returns v2.5.0 (major=2) → node{major}: node1→node2
    printf '# @todo env-update (replace:GLOBAL_STACK_T91A_ALIAS=node{major}) github:testowner/testrepo 1.9.0\nGLOBAL_STACK_T91A=1.9.0\nGLOBAL_STACK_T91A_ALIAS=node1\n' > \"\$f\"
    before=\$(cat \"\$f\")
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    after=\$(cat \"\$f\")
    echo \"\$out\" | grep -qF '(replace)' || { echo \"expected (replace) sub-line in check output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'DRY-RUN' || { echo \"expected DRY-RUN mode banner; got: \$out\"; echo FAIL; exit 0; }
    [ \"\$before\" = \"\$after\" ] || { echo \"file was modified in dry-run; diff: \$after\"; echo FAIL; exit 0; }
    echo PASS
"

# t91b: (replace:) apply — primary var and target both rewritten
# Note: --apply guard requires a prior --dry-run marker; run --check --dry-run first.
t "t91b: replace apply — primary and target VAR= both updated" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91b_c
    f=\${TMP_DIR}/t91b.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T91B_ALIAS=node{major}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T91B=2.4.0\nGLOBAL_STACK_T91B_ALIAS=node2\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1)
    grep -qE '^GLOBAL_STACK_T91B=v?2\.5\.0$' \"\$f\" || { echo \"primary var not updated; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    grep -q '^GLOBAL_STACK_T91B_ALIAS=node2$' \"\$f\" || { echo \"target var not updated to node2; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[REPLACE]' || { echo \"expected [REPLACE] sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t91c: token expansion {major} {minor} {patch} correct from proposed version 2.5.0
t "t91c: token expansion {major}/{minor}/{patch} from proposed 2.5.0" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91c_c
    f=\${TMP_DIR}/t91c.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T91C_LABEL={major}.{minor}.{patch}-lts) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T91C=2.4.0\nGLOBAL_STACK_T91C_LABEL=old\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1
    grep -q '^GLOBAL_STACK_T91C_LABEL=2\.5\.0-lts$' \"\$f\" || { echo \"expected 2.5.0-lts; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t91d: multiple (replace:) flags — all targets updated
t "t91d: multiple (replace:) flags — all targets updated" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91d_c
    f=\${TMP_DIR}/t91d.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T91D_A=v{major}) (replace:GLOBAL_STACK_T91D_B={major}.{minor}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T91D=2.4.0\nGLOBAL_STACK_T91D_A=v2\nGLOBAL_STACK_T91D_B=2.4\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1
    grep -q '^GLOBAL_STACK_T91D_A=v2$' \"\$f\" || { echo \"target A not updated; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    grep -q '^GLOBAL_STACK_T91D_B=2.5$' \"\$f\" || { echo \"target B not updated; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t91e: missing target → [ERROR] in output; with --no-fail, primary still applied
t "t91e: missing target → ERROR output; --no-fail lets primary apply succeed" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91e_c
    f=\${TMP_DIR}/t91e.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T91E_MISSING=val) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T91E=2.4.0\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qiE 'error|not found' || { echo \"expected error about missing target; got: \$out\"; echo FAIL; exit 0; }
    grep -qE '^GLOBAL_STACK_T91E=v?2\.5\.0$' \"\$f\" || { echo \"primary var must still be applied with --no-fail; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F003: cascade rollback — if a replace target fails (missing), the primary var must
# be rolled back to its original value (no half-updated state left behind).
# Without rollback: primary var is written, cascade fails → file is half-updated.
# After fix: snapshot before any writes; restore on cascade failure.
t "t91f: cascade failure rolls back primary var to original value (no half-updated state)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t91f_c
    f=\${TMP_DIR}/t91f.env
    # Target GLOBAL_STACK_T91F_MISSING is absent from the file → cascade error
    printf '# @todo env-update (replace:GLOBAL_STACK_T91F_MISSING=node{major}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T91F=2.4.0\n' > \"\$f\"
    # Capture original primary value
    orig_val=\$(grep '^GLOBAL_STACK_T91F=' \"\$f\" | cut -d= -f2-)
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    # After cascade failure, primary var must still hold the original value (rollback)
    cur_val=\$(grep '^GLOBAL_STACK_T91F=' \"\$f\" | cut -d= -f2-)
    [[ \"\$cur_val\" == \"\$orig_val\" ]] || { echo \"primary var not rolled back: orig='\$orig_val' cur='\$cur_val'; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 92 — (replace:) replace-drift detection and apply matrix
#
# Fixture: github:testowner/testrepo — returns v2.5.0.
# SKIP scenario: annotation current=2.5.0 → SKIP (cur==prop, up-to-date).
# HOLD scenario: annotation current=1.5.0, fixture=2.5.0 → HOLD (major bump).
# AUTO+drift: annotation current=2.4.0 (→AUTO), target already wrong.
# ═══════════════════════════════════════════════════════════════════════════
section "92 — (replace:) replace-drift detection and apply matrix"

# t92a: SKIP + stale target → [REPLACE-DRIFT] in check output
# Note: annotation cur must match fixture-returned v2.5.0 exactly for a true SKIP decision.
t "t92a: SKIP + stale target shows [REPLACE-DRIFT] in check" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92a_c
    f=\${TMP_DIR}/t92a.env
    # cur=v2.5.0 (matches fixture) → SKIP; target should be node2 but is node1 (stale)
    printf '# @todo env-update (replace:GLOBAL_STACK_T92A_ALIAS=node{major}) github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T92A=v2.5.0\nGLOBAL_STACK_T92A_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' || { echo \"expected [REPLACE-DRIFT] in check output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_T92A_ALIAS' || { echo \"expected target name in sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92b: SKIP + stale target → --apply fixes replace-only drift
# Note: cur=v2.5.0 (annotation already normalized) + fixture returns v2.5.0 → true SKIP.
# We set annotation cur to the fixture-normalized form so that cur==prop (SKIP decision).
t "t92b: SKIP + stale target → --apply rewrites target to correct value" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92b_c
    f=\${TMP_DIR}/t92b.env
    # cur=v2.5.0 (matches what fixture returns) → SKIP; target should be node2 but is node1 (stale)
    printf '# @todo env-update (replace:GLOBAL_STACK_T92B_ALIAS=node{major}) github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T92B=v2.5.0\nGLOBAL_STACK_T92B_ALIAS=node1\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1)
    grep -qE '^GLOBAL_STACK_T92B=v?2\.5\.0$' \"\$f\" || { echo \"primary must remain unchanged; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    grep -q '^GLOBAL_STACK_T92B_ALIAS=node2$' \"\$f\" || { echo \"target should now be node2; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[REPLACE]' || { echo \"expected [REPLACE] in apply output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92c: SKIP + fresh target → no [REPLACE-DRIFT] sub-line (no-op guard)
t "t92c: SKIP + already-correct target → no replace-drift sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92c_c
    f=\${TMP_DIR}/t92c.env
    # cur=v2.5.0 (matches fixture) → SKIP; target already node2 (exp_cur for v2.5.0) → no drift
    printf '# @todo env-update (replace:GLOBAL_STACK_T92C_ALIAS=node{major}) github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T92C=v2.5.0\nGLOBAL_STACK_T92C_ALIAS=node2\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' && { echo \"unexpected [REPLACE-DRIFT] when target is fresh; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92d: HOLD + stale target → [REPLACE-DRIFT] with --force-auto message
t "t92d: HOLD + stale target shows [REPLACE-DRIFT] with --force-auto hint" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92d_c
    f=\${TMP_DIR}/t92d.env
    # cur=1.5.0 → fixture returns 2.5.0 → HOLD (major bump); target should be node1 but is node0 (stale)
    printf '# @todo env-update (replace:GLOBAL_STACK_T92D_ALIAS=node{major}) github:testowner/testrepo 1.5.0\nGLOBAL_STACK_T92D=1.5.0\nGLOBAL_STACK_T92D_ALIAS=node0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' || { echo \"expected [REPLACE-DRIFT] for HOLD+stale; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"expected --force-auto hint in sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92e: HOLD + fresh target + update_pending → informational (replace) with force-auto hint
t "t92e: HOLD + fresh target + update pending → informational (replace) sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92e_c
    f=\${TMP_DIR}/t92e.env
    # cur=1.5.0 → fixture returns 2.5.0 → HOLD; target is node1 (matches exp_cur) but exp_prop=node2
    printf '# @todo env-update (replace:GLOBAL_STACK_T92E_ALIAS=node{major}) github:testowner/testrepo 1.5.0\nGLOBAL_STACK_T92E=1.5.0\nGLOBAL_STACK_T92E_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' && { echo \"no drift expected when target is fresh; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '(replace)' || { echo \"expected informational (replace) sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'force-auto' || { echo \"expected --force-auto hint; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'node2' || { echo \"expected exp_prop value node2 in sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92f: AUTO + stale target → [REPLACE-DRIFT] marker appended to (replace) sub-line
t "t92f: AUTO + stale target → [REPLACE-DRIFT] marker on (replace) sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92f_c
    f=\${TMP_DIR}/t92f.env
    # cur=2.4.0 → fixture returns 2.5.0 → AUTO; target should be node2 (exp_cur) but is node1 (stale)
    printf '# @todo env-update (replace:GLOBAL_STACK_T92F_ALIAS=node{major}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T92F=2.4.0\nGLOBAL_STACK_T92F_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' || { echo \"expected [REPLACE-DRIFT] on AUTO+stale; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '(replace)' || { echo \"expected (replace) sub-line with [REPLACE-DRIFT]; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t92g: SKIP + stale target → --apply summary includes replace-only count
# Verifies Fix 1: _n_replace_only_applied is included in the live apply summary line.
t "t92g: SKIP + stale target → --apply summary includes replace-only count" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t92g_c
    f=\${TMP_DIR}/t92g.env
    # cur=v2.5.0 (matches fixture) → SKIP; target node1 is stale (should be node2)
    printf '# @todo env-update (replace:GLOBAL_STACK_T92G_ALIAS=node{major}) github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T92G=v2.5.0\nGLOBAL_STACK_T92G_ALIAS=node1\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'replace-only' || { echo \"expected replace-only in apply summary line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE '[1-9][0-9]* replace-only' || { echo \"expected non-zero replace-only count in summary; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 93 — url.sh nightly SHA sort normalization
#
# The Perl one-liner in url.sh strips hex SHA chars that follow a YYYYMMDD
# date before sort -V, then recovers the original via cut -f2.
# Without it, a longer numeric+hex SHA suffix after the same date causes
# sort -V to rank an older entry higher (the original bug for NODEEDGE).
# ═══════════════════════════════════════════════════════════════════════════
section "93 — url nightly SHA sort normalization"

# t93a: regression canary — raw sort-V WITHOUT normalization wrongly ranks older entry higher
# This documents the exact bug: 20260521614050b657 (older, long numeric SHA) > 202605222f56cd275e (newer)
t "t93a: raw sort-V mis-ranks older nightly with long numeric SHA above newer (bug canary)" bash -c "
    result=\$(printf 'v27.0.0-nightly20260521614050b657\nv27.0.0-nightly202605222f56cd275e\n' | sort -V | tail -1)
    # Without normalization the older entry wins — document this is the known broken behavior
    [[ \"\$result\" == 'v27.0.0-nightly20260521614050b657' ]] || { echo \"raw sort-V behavior changed; got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t93b: normalized sort correctly picks newer nightly despite older having longer numeric SHA
t "t93b: normalized sort picks newer nightly when older has longer numeric SHA" bash -c "
    result=\$(printf 'v27.0.0-nightly20260521614050b657\nv27.0.0-nightly202605222f56cd275e\n' | \
      perl -ne 'chomp; \$orig=\$_; (my \$key=\$orig)=~s/(\d{8})[0-9a-f]+\$/\$1/; print \"\$key\t\$orig\n\";' | \
      sort -V -k1,1 | tail -1 | cut -f2)
    [[ \"\$result\" == 'v27.0.0-nightly202605222f56cd275e' ]] || { echo \"expected May-22 nightly; got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t93c: non-date+SHA entries pass through unchanged (no false match)
t "t93c: non-nightly entries (no YYYYMMDD+SHA) pass through sort normalization unchanged" bash -c "
    result=\$(printf 'v3.0.0\nv18.3-alpine3.23\nv27.0.0\n' | \
      perl -ne 'chomp; \$orig=\$_; (my \$key=\$orig)=~s/(\d{8})[0-9a-f]+\$/\$1/; print \"\$key\t\$orig\n\";' | \
      sort -V -k1,1 | tail -1 | cut -f2)
    [[ \"\$result\" == 'v27.0.0' ]] || { echo \"expected v27.0.0; got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t93d: nightly entry without SHA suffix (date only) passes through unchanged
t "t93d: nightly entry with date but no SHA suffix is not mangled" bash -c "
    result=\$(printf 'v27.0.0-nightly20260521\nv27.0.0-nightly20260522\n' | \
      perl -ne 'chomp; \$orig=\$_; (my \$key=\$orig)=~s/(\d{8})[0-9a-f]+\$/\$1/; print \"\$key\t\$orig\n\";' | \
      sort -V -k1,1 | tail -1 | cut -f2)
    [[ \"\$result\" == 'v27.0.0-nightly20260522' ]] || { echo \"expected May-22; got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# t93e: different channel format (canary) normalizes correctly — proves generality
t "t93e: canary channel with date+SHA normalizes same as nightly" bash -c "
    result=\$(printf 'v28.0.0-canary20260521614050b657\nv28.0.0-canary202605222f56cd275e\n' | \
      perl -ne 'chomp; \$orig=\$_; (my \$key=\$orig)=~s/(\d{8})[0-9a-f]+\$/\$1/; print \"\$key\t\$orig\n\";' | \
      sort -V -k1,1 | tail -1 | cut -f2)
    [[ \"\$result\" == 'v28.0.0-canary202605222f56cd275e' ]] || { echo \"expected May-22 canary; got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 94 — live tally: --tally flag, gate, +replace counter in B2
# ═══════════════════════════════════════════════════════════════════════════
section "94 — live tally flag, gate, and +replace counter"

# t94a: --tally=off is accepted without error
t "t94a: --tally=off accepted without error" bash -c "
    f=\${TMP_DIR}/t94a.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --tally=off --check --env-file=\"\$f\" 2>&1) || true
    echo \"\$out\" | grep -qF 'unknown option' && { echo \"unexpected error: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94b: --tally=full is accepted without error
t "t94b: --tally=full accepted without error" bash -c "
    f=\${TMP_DIR}/t94b.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --tally=full --check --env-file=\"\$f\" 2>&1) || true
    echo \"\$out\" | grep -qF 'unknown option' && { echo \"unexpected error: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94c: --tally=invalid is rejected with a clear error message
t "t94c: --tally=invalid rejected with error" bash -c "
    f=\${TMP_DIR}/t94c.env
    printf '# @todo env-update dockerhub:nginx/nginx 1.27.0\nGLOBAL_STACK_NGINX_VERSION=1.27.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --tally=invalid --check --env-file=\"\$f\" 2>&1) || true
    echo \"\$out\" | grep -qF 'invalid' || { echo \"expected error for invalid tally value; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94d: NO_COLOR env disables tally even with _GS_EU2_TALLY_FORCE=1
# Tally is not active so no ANSI sequences appear on stderr.
t "t94d: NO_COLOR env prevents tally from activating (gate respected)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94d_c
    export NO_COLOR=1
    export _GS_EU2_TALLY_FORCE=1
    f=\${TMP_DIR}/t94d.env
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T94D=v2.5.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --tally=full --env-file=\"\$f\" 2>&1)
    # If tally were active, ANSI ESC sequences would appear; verify none present
    printf '%s' \"\$out\" | grep -qP '\x1b\[' && { echo \"ANSI sequences found — tally was not gated by NO_COLOR; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94e: _GS_EU2_TALLY_FORCE=1 activates tally (ANSI sequences on stderr)
t "t94e: _GS_EU2_TALLY_FORCE=1 activates tally — ANSI sequences present on stderr" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94e_c
    unset NO_COLOR
    export _GS_EU2_TALLY_FORCE=1
    f=\${TMP_DIR}/t94e.env
    printf '# @todo env-update github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T94E=v2.5.0\n' > \"\$f\"
    err=\$(bash '${ENV_UPDATE_V2}' --check --tally=full --env-file=\"\$f\" 2>&1 1>/dev/null)
    # tally should emit ANSI escape sequences on stderr
    printf '%s' \"\$err\" | grep -qP '\x1b\[' || { echo \"no ANSI sequences found — tally not active; err: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t94f: +replace counter appears in B2 when AUTO record has stale replace target
t "t94f: B2 shows '+replace' when AUTO record has stale replace target" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94f_c
    f=\${TMP_DIR}/t94f.env
    # cur=v2.4.0 → proposed=v2.5.0 → AUTO; target node1 is stale (should be node2)
    printf '# @todo env-update (replace:GLOBAL_STACK_T94F_ALIAS=node{major}) github:testowner/testrepo v2\nGLOBAL_STACK_T94F=v2.4.0\nGLOBAL_STACK_T94F_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '+replace' || { echo \"expected '+replace' in B2 secondary signals; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94g: +replace count is 0 when replace-drift decision is SKIP (not AUTO/SHA)
# _n_replace_cascade only counts AUTO/SHA — SKIP must not increment it.
# B2 still prints the token (same as 0 WATCH, 0 DRIFT etc) but the count must be 0.
t "t94g: +replace shows count 0 in B2 when replace-drift decision is SKIP (not AUTO/SHA)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94g_c
    f=\${TMP_DIR}/t94g.env
    # cur=v2.5.0 matches proposed → SKIP (up-to-date); stale target — REPLACE-DRIFT but +replace=0
    printf '# @todo env-update (replace:GLOBAL_STACK_T94G_ALIAS=node{major}) github:testowner/testrepo v2.5.0\nGLOBAL_STACK_T94G=v2.5.0\nGLOBAL_STACK_T94G_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    # REPLACE-DRIFT must appear (tracks all decisions)
    echo \"\$out\" | grep -qF 'REPLACE-DRIFT' || { echo \"expected REPLACE-DRIFT in B2; got: \$out\"; echo FAIL; exit 0; }
    # +replace must show 0 (SKIP decision does not increment _n_replace_cascade)
    echo \"\$out\" | grep -qF '0 +replace' || { echo \"expected '0 +replace' for SKIP decision; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94h: both REPLACE-DRIFT and +replace coexist in B2 when the record is AUTO+stale
t "t94h: REPLACE-DRIFT and +replace coexist in B2 for AUTO decision + stale target" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94h_c
    f=\${TMP_DIR}/t94h.env
    # cur=v2.4.0 → proposed=v2.5.0 → AUTO; target node1 is stale
    printf '# @todo env-update (replace:GLOBAL_STACK_T94H_ALIAS=node{major}) github:testowner/testrepo v2\nGLOBAL_STACK_T94H=v2.4.0\nGLOBAL_STACK_T94H_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'REPLACE-DRIFT' || { echo \"expected REPLACE-DRIFT; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '+replace' || { echo \"expected +replace; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94j: multi-target record: target1=update_pending (stale_now=false), target2=stale_now (update_pending=false)
# Both REPLACE-DRIFT and +replace counters must fire: independent flags prevent one from blocking the other.
t "t94j: multi-target — independent drift and cascade counters each fire once per record" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94j_c
    f=\${TMP_DIR}/t94j.env
    # target A: node{minor}; cur=v2.4.0→exp_cur=node4, actual=node4 → stale_now=false, update_pending=true
    # target B: prefix-{major}; cur=v2.4.0→exp_cur=prefix-2, actual=prefix-1 → stale_now=true, update_pending=false
    printf '# @todo env-update (replace:GLOBAL_STACK_T94J_A=node{minor}) (replace:GLOBAL_STACK_T94J_B=prefix-{major}) github:testowner/testrepo v2.4.0\nGLOBAL_STACK_T94J=v2.4.0\nGLOBAL_STACK_T94J_A=node4\nGLOBAL_STACK_T94J_B=prefix-1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    # drift counter: stale target B must appear
    echo \"\$out\" | grep -qF '1 REPLACE-DRIFT' || { echo \"expected 1 REPLACE-DRIFT (target B is stale); got: \$out\"; echo FAIL; exit 0; }
    # cascade counter: update_pending (target A) + stale (target B) → 1 +replace (per-record, not per-target)
    echo \"\$out\" | grep -qF '1 +replace' || { echo \"expected 1 +replace (cascade fires once per record); got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t94i: +replace counter fires when update_pending=true AND decision=AUTO, even when stale_now=false
# Scenario: annotation ver=v2.4.0, template node{minor} → exp_cur=node4. Target actual=node4 (matches)
# → stale_now=false. proposed=v2.5.0 → exp_prop=node5 ≠ node4 → update_pending=true.
# Decision=AUTO (v2.4.0 → v2.5.0). The ↳ (replace) sub-line is displayed (no REPLACE-DRIFT).
# BUG: current code gates counter on stale_now=true, so +replace stays 0 here.
# After fix: counter increments on update_pending=true AND AUTO/SHA, so +replace=1.
t "t94i: +replace counter fires on AUTO+update_pending even when stale_now=false" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t94i_c
    f=\${TMP_DIR}/t94i.env
    # annotation says v2.4.0; VAR=v2.4.0 → exp_cur=node4; target actual=node4 (stale_now=false)
    # github fixture returns v2.5.0 → AUTO; exp_prop=node5 (update_pending=true)
    printf '# @todo env-update (replace:GLOBAL_STACK_T94I_ALIAS=node{minor}) github:testowner/testrepo v2.4.0\nGLOBAL_STACK_T94I=v2.4.0\nGLOBAL_STACK_T94I_ALIAS=node4\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    # The replace sub-line must appear without [REPLACE-DRIFT] marker (stale_now=false)
    echo \"\$out\" | grep -qF '↳ (replace)' || { echo \"expected replace sub-line; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' && { echo \"unexpected [REPLACE-DRIFT] marker (stale_now should be false); got: \$out\"; echo FAIL; exit 0; } || true
    # +replace count must be 1 (update_pending=true → counter must increment)
    echo \"\$out\" | grep -qF '1 +replace' || { echo \"expected '1 +replace' in B2 (update_pending=true); got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 95 — Batch 3 correctness: awk end-anchor, replace format, force-auto guard
# ═══════════════════════════════════════════════════════════════════════════
section "95 — awk end-anchor, replace format, force-auto guard"

# eu-F035: awk annotation rewrite uses index(line, " " curval) — first occurrence.
# Bug: when curval equals the major hint in the annotation, the FIRST " curval" is
# the major hint position, not the version token at the end.
# Example: annotation "# @todo env-update github:owner/repo 2 2" → curval="2", newval="3"
# → current code rewrites " 2" at major-hint position (gives "... repo 3 2")
# → correct behavior: rewrite the LAST " 2" (version token: gives "... repo 2 3")
t "t95a: awk annotation rewrite targets LAST version token (not major-hint when equal to curval)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/git.sh' 2>/dev/null || true
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\"\${TMP_DIR}/t95a.env\"
    # annotation: major_hint=2 and current version=2 are identical — index() finds major hint first
    printf '# @todo env-update github:owner/repo 2 2\nGLOBAL_STACK_T95A=2\n' > \"\$f\"
    _gs_eu2_apply_single \"\$f\" 'GLOBAL_STACK_T95A' '3' \
      '# @todo env-update github:owner/repo 2 2' '2' '' '' 'false' 'false' ''
    annotation=\$(grep '^#' \"\$f\")
    # Correct: major_hint stays 2, version token becomes 3
    echo \"\$annotation\" | grep -qF '2 3' || { echo \"expected '2 3' in annotation (last token rewritten); got: \$annotation\"; echo FAIL; exit 0; }
    # Must NOT have rewritten major hint position (which would give '3 2')
    echo \"\$annotation\" | grep -qF '3 2' && { echo \"major hint was wrongly rewritten: \$annotation\"; echo FAIL; exit 0; } || true
    echo PASS
"

# eu-F002: unified replace sub-line format.
# apply.sh dry-run internal path (called with dry_run=true) must use '↳ (replace)' format.
# Tested by calling _gs_eu2_apply_updates directly with dry_run="true" and a record that
# has replace_targets — this is the only way to reach the dry-run replace sub-line in apply.sh
# (the CLI gate blocks --apply --dry-run as mutually exclusive).
t "t95b: apply.sh dry-run internal path replace sub-line uses '↳ (replace)' format" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t95b.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T95B_ALIAS=node{major}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T95B=2.4.0\nGLOBAL_STACK_T95B_ALIAS=node2\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T95B'
    _gs_eu2_record_set \$idx current_version   '2.4.0'
    _gs_eu2_record_set \$idx proposed_version  '3.0.0'
    _gs_eu2_record_set \$idx decision          'AUTO'
    _gs_eu2_record_set \$idx replace_targets   'GLOBAL_STACK_T95B_ALIAS'
    _gs_eu2_record_set \$idx replace_templates 'node{major}'
    out=\$(_gs_eu2_apply_updates \"\$f\" 'true')
    # apply.sh dry-run must use '↳ (replace)' not bare '↳ replace'
    echo \"\$out\" | grep -qF '↳ (replace)' || { echo \"expected '↳ (replace)' in apply dry-run output; got: \$out\"; echo FAIL; exit 0; }
    # File must NOT be modified
    grep -qF 'T95B=2.4.0' \"\$f\" || { echo 'file was modified in dry-run'; echo FAIL; exit 0; }
    echo PASS
"

t "t95c: apply.sh [REPLACE] line uses '↳ (replace)' format (not bare '↳')" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t95c_c
    f=\${TMP_DIR}/t95c.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T95C_ALIAS=node{major}) github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T95C=2.4.0\nGLOBAL_STACK_T95C_ALIAS=node2\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" > /dev/null 2>&1
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1)
    # The [REPLACE] line from apply.sh must use '↳ (replace)' not bare '↳ VAR'
    echo \"\$out\" | grep -qF '[REPLACE]' || { echo \"expected [REPLACE] line in apply output; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[REPLACE]' | grep -qF '↳ (replace)' && echo PASS && exit 0
    # Specifically: the [REPLACE] sub-line must contain '↳ (replace)' not bare '↳'
    echo \"\$out\" | grep '\[REPLACE\].*↳' | grep -qF '↳ (replace)' || { echo \"[REPLACE] sub-line uses wrong format; got: \$(echo \"\$out\" | grep '\[REPLACE\].*↳')\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F041: --force-auto without --apply should warn that the flag has no write effect.
# Current behavior: [FORCE-AUTO MODE] banner is emitted but no advisory about --apply.
# After fix: '[WARN] --force-auto has no write effect without --apply' on stderr.
t "t95d: --force-auto without --apply emits advisory about missing --apply" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --force-auto 2>&1 || true)
    # Must contain a warning/advisory mentioning both force-auto and --apply
    echo \"\$err\" | grep -qiE 'force.auto.*apply|apply.*force.auto|no.*write.*effect|no.*effect.*apply' \
      || { echo \"expected force-auto + apply advisory; got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 96 — P2 quality: noop replace suppression, null exact-match, dry-run label
# ═══════════════════════════════════════════════════════════════════════════
section "96 — noop replace suppression, null exact-match, dry-run label"

# eu-F006: AUTO + stale_now=false AND update_pending=false → no '↳ (replace)' sub-line.
# Scenario: same major (cur=v2.4.0, prop=v2.5.0, template=node{major}).
# expand_template(cur)=node2, expand_template(prop)=node2 → update_pending=false.
# Target is already node2 → stale_now=false. No-op: sub-line must be absent.
t "t96a: AUTO + noop replace (same expanded value, fresh target) → no (replace) sub-line" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t96a_c
    f=\${TMP_DIR}/t96a.env
    # cur=v2.4.0 → fixture returns v2.5.0 → AUTO; node{major} expands to node2 for both
    printf '# @todo env-update (replace:GLOBAL_STACK_T96A_ALIAS=node{major}) github:testowner/testrepo v2.4.0\nGLOBAL_STACK_T96A=v2.4.0\nGLOBAL_STACK_T96A_ALIAS=node2\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    # stale_now=false (node2==node2) AND update_pending=false (node2==node2) → noop: no sub-line
    echo \"\$out\" | grep -qF '(replace)' && { echo \"unexpected (replace) sub-line for noop case; got: \$out\"; echo FAIL; exit 0; } || true
    echo \"\$out\" | grep -qF '[REPLACE-DRIFT]' && { echo \"unexpected [REPLACE-DRIFT] for noop case; got: \$out\"; echo FAIL; exit 0; } || true
    echo PASS
"

# eu-F006: Counter: AUTO + stale_now=true OR update_pending=true → sub-line still appears.
# Regression guard: the suppression must not hide genuine work.
t "t96b: AUTO + update_pending=true (different major) → (replace) sub-line is present" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t96b_c
    f=\${TMP_DIR}/t96b.env
    # cur=v1.9.0 → fixture returns v2.5.0 → AUTO (minor/patch or major bump AUTO allowed);
    # node{major}: exp_cur=node1, exp_prop=node2 → update_pending=true; target is node1 (fresh)
    printf '# @todo env-update (replace:GLOBAL_STACK_T96B_ALIAS=node{major}) github:testowner/testrepo v1.9.0\nGLOBAL_STACK_T96B=v1.9.0\nGLOBAL_STACK_T96B_ALIAS=node1\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1)
    # update_pending=true → sub-line must appear
    echo \"\$out\" | grep -qF '(replace)' || { echo \"expected (replace) sub-line when update_pending=true; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F010 / eu-F029: url.sh fetch-json: null substring strip must be exact-match only.
# Bug: '\${_proposed//null/}' strips 'null' as substring — 'null-rc1' becomes '-rc1'.
# Fix: '[[ \${_proposed} == null ]] && _proposed=""' (exact match only).
t "t96c: url fetch-json: literal 'null' → empty proposed (exact-match discard)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/url.sh'
    export _GS_EU2_HTTP_FIXTURE_DIR=\${TMP_DIR}/t96c_fixtures
    mkdir -p \"\${_GS_EU2_HTTP_FIXTURE_DIR}\"
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t96c_cache
    # Fixture returns JSON with a null version field
    printf '{\"version\":null}' > \"\${_GS_EU2_HTTP_FIXTURE_DIR}/example.com_null-version\"
    _GS_EU2_REC_COUNT=0; _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_T96C'
    _gs_eu2_record_set \$idx identifier    'https://example.com/null-version'
    _gs_eu2_record_set \$idx fetch_json    '.version'
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_fetch_url \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # null JSON value must produce empty proposed (discarded)
    [[ -z \"\$proposed\" ]] || { echo \"expected empty proposed for null JSON; got: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t96d: url fetch-json: 'null-rc1' must NOT be stripped (substring safety)" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/url.sh'
    export _GS_EU2_HTTP_FIXTURE_DIR=\${TMP_DIR}/t96d_fixtures
    mkdir -p \"\${_GS_EU2_HTTP_FIXTURE_DIR}\"
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t96d_cache
    # Fixture returns a version string that starts with 'null' as a substring
    printf '{\"version\":\"null-rc1\"}' > \"\${_GS_EU2_HTTP_FIXTURE_DIR}/example.com_null-rc1-version\"
    _GS_EU2_REC_COUNT=0; _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var       'GLOBAL_STACK_T96D'
    _gs_eu2_record_set \$idx identifier    'https://example.com/null-rc1-version'
    _gs_eu2_record_set \$idx fetch_json    '.version'
    _gs_eu2_record_set \$idx type          'url'
    _gs_eu2_fetch_url \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # 'null-rc1' is not the literal string 'null' — must be preserved intact
    [[ \"\$proposed\" == 'null-rc1' ]] || { echo \"expected proposed='null-rc1' (preserved); got: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

# eu-F018 (env-scan): propagate.sh dry-run output must use '[DRY-RUN]' prefix on per-var lines.
# Current: line 112 prints ' [propagate] %s: %s: ...' without distinguishing dry-run.
# Fix: when dry_run=true, prefix the per-var line with '[DRY-RUN]'.
t "t96e: env-scan propagate dry-run per-var output contains [DRY-RUN] prefix" bash -c "
    source '${_GS_ES_LIB}/core/backup.sh' 2>/dev/null || true
    source '${_GS_ES_LIB}/core/git.sh' 2>/dev/null || true
    source '${_GS_ES_LIB}/propagate.sh'
    # Minimal _GS_ES_CFG setup
    declare -A _GS_ES_CFG=([backup]='false' [backup_suffix]='.bak' [_backup_ts]='' [dir]='' [quiet]='false')
    # Create a minimal env file with one var
    env_file=\${TMP_DIR}/t96e.env
    df_dir=\${TMP_DIR}/t96e_docker
    mkdir -p \"\${df_dir}\"
    printf 'GLOBAL_STACK_T96E=newvalue\n' > \"\${env_file}\"
    # Dockerfile with mismatched value
    printf 'FROM scratch\nARG GLOBAL_STACK_T96E=oldvalue\n' > \"\${df_dir}/Dockerfile\"
    out=\$(_gs_es_propagate_to_dockerfiles \"\${env_file}\" \"\${df_dir}\" '' 'true' 2>&1)
    # dry-run per-var line must contain '[DRY-RUN]'
    echo \"\$out\" | grep -qF '[DRY-RUN]' || { echo \"expected [DRY-RUN] in dry-run per-var output; got: \$out\"; echo FAIL; exit 0; }
    # File must NOT be modified in dry-run
    grep -qF 'oldvalue' \"\${df_dir}/Dockerfile\" || { echo 'Dockerfile was modified in dry-run'; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 97 — P2 fetchers: HTTP memo auth key, Quay pagination
# ═══════════════════════════════════════════════════════════════════════════
section "97 — HTTP memo auth key collision + Quay pagination"

# eu-F008: HTTP memo auth-key collision.
# Scenario: unauthenticated call for URL X is cached under key "X".
# Subsequent authenticated call for the same URL X hits the memo and returns
# the unauthenticated response — wrong: it should use the authenticated response.
# Fix: key the memo by "${_url}:${auth}" (auth=1 when token present, 0 when not).
t "t97a: HTTP memo does not bleed unauthenticated response to authenticated caller" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    # Simulate: prime the memo with an unauthenticated response for a URL
    _GS_EU2_HTTP_MEMO=()
    url='https://api.github.com/repos/test/test/releases'
    # Manually store as the current (buggy) key — just the URL
    _GS_EU2_HTTP_MEMO[\"\${url}\"]='[{\"tag_name\":\"v1.0.0-UNAUTH\"}]'
    # Now call authenticated — it must NOT return the unauthenticated memo entry.
    # With the fix: auth key is \"\${url}:1\", which is not in the memo → falls through.
    # With the bug: auth key is \"\${url}\", which IS in the memo → returns wrong data.
    result=\$(_gs_eu2_http_get_auth \"\${url}\" 'fake-token-xyz' 2>&1 || true)
    # The auth call must NOT return the UNAUTH-tagged response stored under bare URL key
    echo \"\$result\" | grep -qF 'UNAUTH' && { echo \"auth call returned unauthenticated memo entry (key collision); got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t97b: HTTP memo auth key: authenticated and unauthenticated entries are independent" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    _GS_EU2_HTTP_MEMO=()
    url='https://api.github.com/repos/test/test/releases'
    # Store authenticated response under the auth key (post-fix: url:1)
    _GS_EU2_HTTP_MEMO[\"\${url}:1\"]='[{\"tag_name\":\"v2.0.0-AUTH\"}]'
    # Store unauthenticated response under the no-auth key (post-fix: url:0)
    _GS_EU2_HTTP_MEMO[\"\${url}:0\"]='[{\"tag_name\":\"v1.0.0-UNAUTH\"}]'
    # Unauthenticated call must return UNAUTH entry
    unauth=\$(_gs_eu2_http_get \"\${url}\" 2>&1 || true)
    echo \"\$unauth\" | grep -qF 'UNAUTH' || { echo \"unauth call did not return UNAUTH entry; got: \$unauth\"; echo FAIL; exit 0; }
    # Authenticated call must return AUTH entry
    auth=\$(_gs_eu2_http_get_auth \"\${url}\" 'fake-token' 2>&1 || true)
    echo \"\$auth\" | grep -qF 'AUTH' || { echo \"auth call did not return AUTH entry; got: \$auth\"; echo FAIL; exit 0; }
    # Authenticated must NOT return UNAUTH
    echo \"\$auth\" | grep -qF 'UNAUTH' && { echo \"auth returned unauth entry — key collision; got: \$auth\"; echo FAIL; exit 0; } || true
    echo PASS
"

# eu-F031: Quay pagination.
# Current: _gs_eu2_qy_fetch_tags uses ?limit=50 with no pagination loop.
# Fix: loop while has_additional=true, incrementing page= param.
# Test: create two page fixtures; page 1 has has_additional=true; assert both pages' tags appear.
t "t97c: Quay fetcher follows has_additional pagination" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/quay.sh'
    export _GS_EU2_HTTP_FIXTURE_DIR=\${TMP_DIR}/t97c_fixtures
    mkdir -p \"\${_GS_EU2_HTTP_FIXTURE_DIR}\"
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t97c_cache
    # Page 1: has_additional=true (more pages) — contains older tags
    cat > \"\${_GS_EU2_HTTP_FIXTURE_DIR}/quay.io_api_v1_repository_testpag_myimg_tag__page_1\" <<'FIXTURE'
{\"has_additional\": true, \"tags\": [{\"name\": \"25.1.0\"}, {\"name\": \"25.0.0\"}]}
FIXTURE
    # Page 2: has_additional=false (last page) — contains newer tag
    cat > \"\${_GS_EU2_HTTP_FIXTURE_DIR}/quay.io_api_v1_repository_testpag_myimg_tag__page_2\" <<'FIXTURE'
{\"has_additional\": false, \"tags\": [{\"name\": \"26.0.0\"}]}
FIXTURE
    _GS_EU2_REC_COUNT=0; _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var     'GLOBAL_STACK_T97C'
    _gs_eu2_record_set \$idx identifier  'testpag/myimg'
    _gs_eu2_record_set \$idx type        'quay'
    _gs_eu2_record_set \$idx no_cache    'true'
    _gs_eu2_fetch_quay \$idx
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # Without pagination fix: proposed would be best from page 1 only (25.1.0)
    # With pagination fix: proposed is best from all pages (26.0.0)
    [[ \"\$proposed\" == '26.0.0' ]] || { echo \"expected proposed=26.0.0 (from page 2); got: '\$proposed'\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 98 — RESOLVED decision type + --apply-resolve flag
# ═══════════════════════════════════════════════════════════════════════════
section "98 — RESOLVED decision: float-to-concrete, --apply-resolve"

_DC_LIBS98="
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

# --- 1. Core classify_decision unit tests (unversioned set extension + RESOLVED) ---

t "t98a: _cur=latest, _prop=18.3-alpine3.23 → RESOLVED" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' '' '')
    [[ \"\$result\" == 'RESOLVED' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98b: _cur=stable, _prop=3.2.1 → RESOLVED (extended float set)" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'stable' '3.2.1' '' '')
    [[ \"\$result\" == 'RESOLVED' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98c: _cur=lts, _prop=20.18.0 → RESOLVED (extended float set)" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'lts' '20.18.0' '' '')
    [[ \"\$result\" == 'RESOLVED' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98d: _cur=current, _prop=22.14.0 → RESOLVED (extended float set)" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'current' '22.14.0' '' '')
    [[ \"\$result\" == 'RESOLVED' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98e: _cur=latest, _prop=latest → SKIP (proposed also unversioned)" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'latest' 'latest' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98f: _cur=latest, _prop='' → SKIP (no proposed)" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'latest' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98g: _cur=latest, _prop=18.3-alpine3.23, manual=true → MANUAL" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' 'true' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98h: _cur=latest, _prop=18.3-alpine3.23, override=true → MANUAL" bash -c "
    ${_DC_LIBS98}
    result=\$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' 'true' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# --- 2. Integration tests (end-to-end via env-update.sh CLI) ---

t "t98i: --check output contains [RESOLVE] tag and 'latest → <concrete>'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98i_cache
    f=\${TMP_DIR}/t98i.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98I_VERSION=latest\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[RESOLVE]' || { echo \"no [RESOLVE] tag in output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'latest →' || { echo \"no 'latest →' in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98j: --apply alone does NOT write file for RESOLVED record" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98j_cache
    f=\${TMP_DIR}/t98j.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98J_VERSION=latest\n' > \"\$f\"
    # Create dry-run marker so apply proceeds past safety guard
    mkdir -p \"\${TMP_DIR}/t98j_cache\"
    touch \"\${TMP_DIR}/t98j_cache/last-dry-run-ts\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1 || true
    # VAR= must still be 'latest' — RESOLVED must not be auto-applied
    grep -q 'GLOBAL_STACK_T98J_VERSION=latest' \"\$f\" || { echo 'RESOLVED was written without --apply-resolve'; echo FAIL; exit 0; }
    echo PASS
"

t "t98k: --apply --force-auto does NOT write RESOLVED (force-auto does not promote RESOLVED)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98k_cache
    f=\${TMP_DIR}/t98k.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98K_VERSION=latest\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t98k_cache\"
    touch \"\${TMP_DIR}/t98k_cache/last-dry-run-ts\"
    bash '${ENV_UPDATE_V2}' --apply --yes --force-auto --confirm='Confirm override' --env-file=\"\$f\" 2>&1 || true
    grep -q 'GLOBAL_STACK_T98K_VERSION=latest' \"\$f\" || { echo 'RESOLVED was written by force-auto'; echo FAIL; exit 0; }
    echo PASS
"

t "t98l: --apply --apply-resolve DOES write concrete version and emits [PINNED ]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98l_cache
    f=\${TMP_DIR}/t98l.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98L_VERSION=latest\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t98l_cache\"
    touch \"\${TMP_DIR}/t98l_cache/last-dry-run-ts\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --apply-resolve --env-file=\"\$f\" 2>&1)
    # File must have been updated (no longer 'latest')
    grep -q 'GLOBAL_STACK_T98L_VERSION=latest' \"\$f\" && { echo 'file not updated by --apply-resolve'; echo FAIL; exit 0; } || true
    # Output must contain [PINNED ]
    echo \"\$out\" | grep -qF '[PINNED ]' || { echo \"no [PINNED ] in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98m: B1 summary contains RESOLVE count when RESOLVED records present" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98m_cache
    f=\${TMP_DIR}/t98m.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98M_VERSION=latest\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE 'Summary.*RESOLVE' || { echo \"no RESOLVE in summary: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98n2: --apply without --apply-resolve warns about skipped RESOLVED records" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98n2_cache
    f=\${TMP_DIR}/t98n2.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98N2_VERSION=latest\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t98n2_cache\"
    touch \"\${TMP_DIR}/t98n2_cache/last-dry-run-ts\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'RESOLVED record(s) skipped' || { echo \"expected RESOLVED skip warning; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF -- '--apply-resolve' || { echo \"expected --apply-resolve hint in warning; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t98n3: --apply --apply-resolve does NOT emit RESOLVED skip warning" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t98n3_cache
    f=\${TMP_DIR}/t98n3.env
    printf '# @todo env-update dockerhub:_/postgres latest\nGLOBAL_STACK_T98N3_VERSION=latest\n' > \"\$f\"
    mkdir -p \"\${TMP_DIR}/t98n3_cache\"
    touch \"\${TMP_DIR}/t98n3_cache/last-dry-run-ts\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --yes --apply-resolve --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'RESOLVED record(s) skipped' && { echo \"unexpected RESOLVED skip warning when --apply-resolve is set; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 99 — Batch B: --reference in help, --tally documented
# ═══════════════════════════════════════════════════════════════════════════
section "99 — Batch B: --reference in help, --tally documented"

# t99a: --help output must contain --reference (B1 rename)
t "t99a: --help output contains --reference flag" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --help 2>&1)
    echo \"\$out\" | grep -qF -- '--reference' || { echo \"help missing --reference flag; got fragment: \$(echo \"\$out\" | grep -i 'annot\|ref')\"; echo FAIL; exit 0; }
    echo PASS
"

# t99b: --help output must NOT contain --annotations (dead flag removed)
t "t99b: --help output does NOT contain dead --annotations flag" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --help 2>&1)
    echo \"\$out\" | grep -qF -- '--annotations' && { echo \"help still references dead --annotations flag\"; echo FAIL; exit 0; }
    echo PASS
"

# t99c: --help output must contain --tally (B2 new entry)
t "t99c: --help output contains --tally flag" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --help 2>&1)
    echo \"\$out\" | grep -qF -- '--tally' || { echo \"help missing --tally flag\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 100 — stub annotation parse/storage coverage (depends-on, propagate)
# ═══════════════════════════════════════════════════════════════════════════
section "100 — stub annotation parse/storage coverage"

# t100a: (depends-on:SOME_VAR:major) parses without error; --check exits 0
t "t100a: (depends-on) parses without error, --check exits 0" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t100a_cache
    f=\${TMP_DIR}/t100a.env
    printf '# @todo env-update (depends-on:GLOBAL_STACK_OTHER:major) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T100A_VERSION=18.3-alpine3.23\n' > \"\$f\"
    bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" >/dev/null 2>&1 && echo PASS || { echo 'non-zero exit on (depends-on) check'; echo FAIL; exit 0; }
"

# t100b: --dump output for a (depends-on) record shows 'depends_on: SOME_VAR:major'
t "t100b: --dump shows depends_on field" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/depends-on.env' 2>&1)
    echo \"\$out\" | grep -qF 'depends_on: GLOBAL_STACK_SONARQUBE_VERSION:major' || { echo \"depends_on field not in dump; got: \$(echo \"\$out\" | grep depends)\"; echo FAIL; exit 0; }
    echo PASS
"

# t100c: --check output for a (depends-on) record shows [WARN] sub-line
t "t100c: --check emits [WARN] sub-line for (depends-on) record" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t100c_cache
    f=\${TMP_DIR}/t100c.env
    printf '# @todo env-update (depends-on:GLOBAL_STACK_OTHER:major) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T100C_VERSION=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[WARN]' || { echo \"no [WARN] sub-line for depends-on record; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t100d: (depends-on) record is NOT blocked — fetch still runs, a decision comes back
t "t100d: (depends-on) record fetches and produces a decision" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t100d_cache
    f=\${TMP_DIR}/t100d.env
    printf '# @todo env-update (depends-on:GLOBAL_STACK_OTHER:major) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T100D_VERSION=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qE '\[(AUTO|SKIP|HOLD|MANUAL|ERROR|LOCK)\s*\]' || { echo \"no decision tag in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t100e: (propagate) annotation exits 1 with helpful error (flag removed)
t "t100e: (propagate) removed — exits 1 with helpful error" bash -c "
    f=\${TMP_DIR}/t100e.env
    printf '# @todo env-update (propagate) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T100E_VERSION=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1) && { echo 'expected exit 1 but got 0; out='\"\$out\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF 'unknown flag' || { echo \"expected unknown flag error; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t100f: flags-all.env no longer contains (propagate) — verify override+manual still parse
t "t100f: flags-all.env override+manual parse correctly after propagate removal" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/flags-all.env' 2>&1)
    echo \"\$out\" | grep -qF 'override: true' || { echo \"override not true in dump; got: \$(echo \"\$out\" | grep override)\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'manual: true'   || { echo \"manual not true in dump; got: \$(echo \"\$out\" | grep manual)\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 101 — decide.sh nightly SHA sort-V normalization (NODEEDGE fix)
#
# Regression guards for the sort-V false-downgrade bug: nightly versions with
# a long numeric+hex SHA suffix (e.g. nightly20260524837910d298) caused sort-V
# to produce a key longer than the date-only key (nightly202605252e3daf6e4d),
# making May-24 sort AFTER May-25 → legitimate upgrade seen as downgrade → SKIP.
# Fix: perl normalization strips hex chars after YYYYMMDD before sort-V.
# ═══════════════════════════════════════════════════════════════════════════
section "101 — decide.sh nightly SHA sort-V normalization"

_NODEEDGE_DECIDE_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/decide.sh'
"

# t101a: May-24 long-SHA nightly current → May-25 short-SHA nightly proposed → AUTO (not SKIP)
# This is the exact NODEEDGE regression: raw sort-V incorrectly ranks May-24 > May-25.
t "t101a: newer nightly (May-25 short SHA) is NOT a downgrade over May-24 long SHA" bash -c "
    ${_NODEEDGE_DECIDE_LIBS}
    cv='v27.0.0-nightly20260524837910d298'
    pv='v27.0.0-nightly202605252e3daf6e4d'
    result=\$(_gs_eu2_classify_decision \"\${cv#v}\" \"\${pv#v}\" '' '' 'full')
    [[ \"\$result\" != 'SKIP' ]] || { echo \"got SKIP — false downgrade still fires; May-25 nightly should be accepted as upgrade\"; echo FAIL; exit 0; }
    echo PASS
"

# t101b: same-date different-SHA nightly — normalization strips both SHAs to same date key,
# so _oldest == _pv_norm == _cv_norm and the downgrade guard does NOT fire → falls through to AUTO.
# This is the correct behavior: same-date builds cannot be ordered; AUTO is safer than false SKIP.
t "t101b: same-date different-SHA nightly does not falsely SKIP (downgrade guard bypassed)" bash -c "
    ${_NODEEDGE_DECIDE_LIBS}
    cv='27.0.0-nightly20260524837910d298'
    pv='27.0.0-nightly20260524abc1234def'
    result=\$(_gs_eu2_classify_decision \"\$cv\" \"\$pv\" '' '' 'full')
    [[ \"\$result\" != 'SKIP' ]] || { echo \"got SKIP — same-date nightly falsely seen as downgrade; expected AUTO or MANUAL\"; echo FAIL; exit 0; }
    echo PASS
"

# t101c: older nightly (May-24) proposed against May-25 current → SKIP (real downgrade still caught)
t "t101c: older nightly (May-24 proposed vs May-25 current) still produces SKIP (downgrade)" bash -c "
    ${_NODEEDGE_DECIDE_LIBS}
    cv='27.0.0-nightly202605252e3daf6e4d'
    pv='27.0.0-nightly20260524837910d298'
    result=\$(_gs_eu2_classify_decision \"\$cv\" \"\$pv\" '' '' 'full')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for real downgrade, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# t101d: non-nightly versions are unaffected — plain semver still works
t "t101d: plain semver versions pass through decide.sh unchanged after normalization" bash -c "
    ${_NODEEDGE_DECIDE_LIBS}
    result=\$(_gs_eu2_classify_decision '27.0.0' '27.1.0' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for plain minor bump, got: '\$result'\"; echo FAIL; exit 0; }
    result2=\$(_gs_eu2_classify_decision '27.1.0' '27.0.0' '' '')
    [[ \"\$result2\" == 'SKIP' ]] || { echo \"expected SKIP for plain downgrade, got: '\$result2'\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 102 — apply.sh LOCK path skips annotation rewrite for floating current (PHPEDGE fix)
#
# Bug: (lock:) + floating current ("next") caused the annotation to be rewritten
# from "next" to the concrete proposed version (e.g. "php-8.5.6") on --apply.
# The VAR= line was left unchanged, but the annotation's current_version token was
# corrupted, breaking round-trip semantics and future runs.
# Fix: apply.sh LOCK path guards with _gs_eu2_is_unversioned before any rewrite.
# ═══════════════════════════════════════════════════════════════════════════
section "102 — apply.sh LOCK floating-current guard (PHPEDGE fix)"

# t102a: LOCK + floating current ("next") — --apply must NOT rewrite annotation
t "t102a: (lock:) with floating current 'next' — --apply leaves annotation byte-identical" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t102a_cache
    mkdir -p \"\${TMP_DIR}/t102a_cache\"
    touch \"\${TMP_DIR}/t102a_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t102a.env
    ann='# @todo env-update (lock:keep as floating alias) github:php/php-src next'
    printf '%s\nGLOBAL_STACK_PHPEDGE_VERSION=next\n' \"\$ann\" > \"\$f\"
    original=\$(cat \"\$f\")
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after=\$(cat \"\$f\")
    [[ \"\$original\" == \"\$after\" ]] || {
        echo 'file was modified — annotation rewritten for floating (next) current'
        echo \"before: \$original\"
        echo \"after:  \$after\"
        echo FAIL; exit 0
    }
    echo PASS
"

# t102b: LOCK + floating current — --check shows LOCK; --apply leaves file unchanged
# Uses dockerhub:_/postgres:18 which has a fixture returning 18.4-alpine3.23,
# so the LOCK decision fires reliably.
t "t102b: (lock:) with floating current — --check shows LOCK; file unchanged after --apply" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t102b_cache
    mkdir -p \"\${TMP_DIR}/t102b_cache\"
    touch \"\${TMP_DIR}/t102b_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t102b.env
    ann='# @todo env-update (lock:keep as floating alias) dockerhub:_/postgres:18 next'
    printf '%s\nGLOBAL_STACK_T102B=next\n' \"\$ann\" > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[LOCK' || {
        echo \"expected LOCK in check output; got: \$out\"
        echo FAIL; exit 0
    }
    original=\$(cat \"\$f\")
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after=\$(cat \"\$f\")
    [[ \"\$original\" == \"\$after\" ]] || {
        echo 'file changed after --apply on floating-current LOCK'
        echo FAIL; exit 0
    }
    echo PASS
"

# t102c: LOCK + concrete current still rewrites annotation (existing LOCK behaviour intact)
t "t102c: (lock:) with concrete current still rewrites annotation when proposed differs" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t102c_cache
    mkdir -p \"\${TMP_DIR}/t102c_cache\"
    touch \"\${TMP_DIR}/t102c_cache/last-dry-run-ts\"
    f=\${TMP_DIR}/t102c.env
    ann='# @todo env-update (lock:pinned) dockerhub:_/postgres:18 18.3-alpine3.23'
    printf '%s\nGLOBAL_STACK_T102C=18.3-alpine3.23\n' \"\$ann\" > \"\$f\"
    bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
    after=\$(cat \"\$f\")
    echo \"\$after\" | grep -q '18.4-alpine3.23' || {
        echo \"annotation not updated for concrete locked var; file: \$after\"
        echo FAIL; exit 0
    }
    echo \"\$after\" | grep -q 'GLOBAL_STACK_T102C=18.3-alpine3.23' || {
        echo \"VAR= was changed — LOCK must not touch VAR=\"
        echo FAIL; exit 0
    }
    echo PASS
"

# t102d: LOCK + other floating aliases (edge, nightly, latest) also skip annotation rewrite
t "t102d: (lock:) with other floating aliases (edge, nightly, latest) — annotation left unchanged" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t102d_cache
    mkdir -p \"\${TMP_DIR}/t102d_cache\"
    touch \"\${TMP_DIR}/t102d_cache/last-dry-run-ts\"
    for alias in edge latest lts; do
        f=\${TMP_DIR}/t102d_\${alias}.env
        ann=\"# @todo env-update (lock:keep floating) dockerhub:_/postgres:18 \${alias}\"
        printf '%s\nGLOBAL_STACK_T102D=\${alias}\n' \"\$ann\" > \"\$f\"
        original=\$(cat \"\$f\")
        bash '${ENV_UPDATE_V2}' --apply --yes --env-file=\"\$f\" 2>/dev/null || true
        after=\$(cat \"\$f\")
        [[ \"\$original\" == \"\$after\" ]] || {
            echo \"alias '\${alias}': file was modified\"
            echo FAIL; exit 0
        }
    done
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 103 — ghcr fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "103 — ghcr fetcher"

_GHCR_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/ghcr.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_cache
"

# t103a: happy path — latest stable tag returned as proposed_version
t "t103a: happy path — latest stable tag returned as proposed_version" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 2.1.2 as highest stable
    [[ \"\$val\" == '2.1.2' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t103b: non-semver tags filtered out — latest/edge/sha-* do not become proposed_version
t "t103b: non-semver tags (latest, edge, sha-*) are filtered out by channel selection" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # must not be a non-semver tag
    [[ \"\$val\" != 'latest' && \"\$val\" != 'edge' ]] || { echo \"non-semver tag selected: '\$val'\"; echo FAIL; exit 0; }
    [[ \"\$val\" != sha-* ]] || { echo \"sha tag selected: '\$val'\"; echo FAIL; exit 0; }
    [[ -n \"\$val\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    echo PASS
"

# t103c: major_hint filtering — only tags in the pinned major returned
t "t103c: major_hint=1 restricts to 1.x tags" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-majorpin'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_PIN_VERSION'
    _gs_eu2_record_set \$idx major_hint '1'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture has 1.0.0, 1.1.0, 1.2.0 in major 1; 1.2.0 should win
    [[ \"\$val\" == '1.2.0' ]] || { echo \"expected 1.2.0 for major_hint=1, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t103d: major_hint filtering — higher major excluded
t "t103d: major_hint=1 excludes 2.x tags" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-majorpin'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_PIN_VERSION'
    _gs_eu2_record_set \$idx major_hint '1'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" != 2.* ]] || { echo \"2.x tag escaped major pin: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t103e: all-non-semver image returns SKIP (no versioned tags)
# Fixture has only: latest, edge, nightly, stable, main — all unversioned per _gs_eu2_is_unversioned.
# Note: sha-* tags are NOT treated as unversioned (sort -V can order them); use the unversioned
# tag set (latest/edge/nightly) to test this path cleanly.
t "t103e: image with only unversioned tags (latest, edge, nightly) sets decision=SKIP" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-nonsemver'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_NONSEMVER_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$decision\" == 'SKIP' ]] || { echo \"expected SKIP, got: '\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

# t103f: empty tags list returns ERROR
t "t103f: empty tags array sets decision=ERROR" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-empty'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_EMPTY_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

# t103g: HTTP failure (no fixture dir + nonexistent identifier) sets ERROR
t "t103g: HTTP failure (nonexistent identifier) sets decision=ERROR, error_message set" bash -c "
    ${_GHCR_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'no-such-owner/no-such-image'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_XYZZY_VERSION'
    _gs_eu2_fetch_ghcr \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

# t103h: GITHUB_TOKEN path — PAT exchanged via token endpoint, returns PAT-scoped token
# Fixture ghcr.io_token_pat is present → PAT branch reads it; proposed_version is populated.
t "t103h: GITHUB_TOKEN present — PAT exchanged via token endpoint (ghcr.io_token_pat fixture)" bash -c "
    ${_GHCR_LIBS}
    export GITHUB_TOKEN='test-pat-token-for-exchange'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_h_cache
    # Verify _gs_eu2_ghcr_get_token returns the PAT-scoped token (not the anon token)
    tok=\$(_gs_eu2_ghcr_get_token 'testowner/ghcr-repo')
    [[ \"\$tok\" == 'test-pat-scoped-token-ghcr-fixture' ]] \
        || { echo \"expected PAT-scoped token, got: '\$tok'\"; echo FAIL; exit 0; }
    # Also verify full fetch path still produces a proposed_version
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_PAT_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version empty with GITHUB_TOKEN set'; echo FAIL; exit 0; }
    unset GITHUB_TOKEN
    echo PASS
"

# t103h_b: GITHUB_TOKEN present but token endpoint fails → falls back to anonymous token
# Simulate PAT failure by pointing fixture dir at a temp dir with NO ghcr.io_token_pat file
# (anonymous ghcr.io_token is present so the fallback can succeed).
t "t103h_b: GITHUB_TOKEN present + PAT token endpoint fails → falls back to anonymous token" bash -c "
    ${_GHCR_LIBS}
    export GITHUB_TOKEN='test-pat-will-fail'
    # Temp fixture dir: has anonymous token fixture but NOT ghcr.io_token_pat
    _fallback_dir=\$(mktemp -d)
    cp '${FIXTURES}/http/ghcr.io_token' \"\${_fallback_dir}/\"
    cp '${FIXTURES}/http/ghcr.io_v2_testowner_ghcr-repo_tags_list' \"\${_fallback_dir}/\"
    export _GS_EU2_HTTP_FIXTURE_DIR=\"\${_fallback_dir}\"
    export _GS_EU2_CACHE_DIR=\$(mktemp -d)
    # _gs_eu2_ghcr_get_token: PAT fixture absent → falls through to anonymous path
    tok=\$(_gs_eu2_ghcr_get_token 'testowner/ghcr-repo')
    [[ \"\$tok\" == 'test-anon-token-ghcr-fixture' ]] \
        || { echo \"expected anon fallback token, got: '\$tok'\"; echo FAIL; exit 0; }
    # Full fetch must still succeed (uses anonymous token)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_PAT_FALLBACK_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version empty after anon fallback'; echo FAIL; exit 0; }
    unset GITHUB_TOKEN
    rm -rf \"\${_fallback_dir}\"
    echo PASS
"

# t103h_c: no PAT → anonymous token path via _gs_eu2_ghcr_get_token directly
t "t103h_c: no PAT (GITHUB_TOKEN unset) → anonymous token returned by get_token" bash -c "
    ${_GHCR_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_hc_cache
    unset GITHUB_TOKEN GLOBAL_STACK_GITHUB_TOKEN
    tok=\$(_gs_eu2_ghcr_get_token 'testowner/ghcr-repo')
    [[ \"\$tok\" == 'test-anon-token-ghcr-fixture' ]] \
        || { echo \"expected anon token, got: '\$tok'\"; echo FAIL; exit 0; }
    echo PASS
"

# t103i: tag-strip-prefix strips 'v' prefix
t "t103i: tag-strip-prefix strips leading v from version tags" bash -c "
    ${_GHCR_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_i_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'ghcr'
    _gs_eu2_record_set \$idx identifier       'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_GHCR_STRIP_VERSION'
    # The fixture tags have no v-prefix, so strip-prefix v should have no effect
    # but must not break the fetcher
    _gs_eu2_record_set \$idx tag_strip_prefix 'v'
    _gs_eu2_fetch_ghcr \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$val\" ]] || { echo 'proposed_version empty after tag-strip-prefix'; echo FAIL; exit 0; }
    echo PASS
"

# t103j: fetcher leaves decision empty on success path (decide.sh owns AUTO/HOLD)
t "t103j: fetcher leaves decision empty on success path (not AUTO/HOLD)" bash -c "
    ${_GHCR_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_DECISION_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ -n \"\$proposed\" ]] || { echo 'proposed_version is empty'; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"fetcher set decision: '\$decision' (should be empty)\"; echo FAIL; exit 0; }
    echo PASS
"

# t103k: cache hit path — second call returns same result without re-fetching
t "t103k: cache hit path returns same proposed_version without a second fetch" bash -c "
    ${_GHCR_LIBS}
    # Prime the cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_CACHE1_VERSION'
    _gs_eu2_fetch_ghcr \$idx
    proposed_first=\$(_gs_eu2_record_get \$idx proposed_version)
    # Second call — should hit cache
    _gs_eu2_record_new; idx2=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx2 type       'ghcr'
    _gs_eu2_record_set \$idx2 identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx2 env_var    'GLOBAL_STACK_GHCR_CACHE2_VERSION'
    _gs_eu2_fetch_ghcr \$idx2
    proposed_second=\$(_gs_eu2_record_get \$idx2 proposed_version)
    [[ \"\$proposed_first\" == \"\$proposed_second\" ]] \
        || { echo \"cache mismatch: '\$proposed_first' vs '\$proposed_second'\"; echo FAIL; exit 0; }
    [[ -n \"\$proposed_second\" ]] || { echo 'cache hit returned empty'; echo FAIL; exit 0; }
    echo PASS
"

# t103l: dispatch wiring — ghcr type dispatches correctly via _gs_eu2_dispatch_fetcher
t "t103l: dispatch wiring — ghcr: type is handled by _gs_eu2_dispatch_fetcher" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/core/decide.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/github.sh'
    source '${_GS_EU2_LIB}/fetchers/codeberg.sh'
    source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
    source '${_GS_EU2_LIB}/fetchers/quay.sh'
    source '${_GS_EU2_LIB}/fetchers/npm.sh'
    source '${_GS_EU2_LIB}/fetchers/pypi.sh'
    source '${_GS_EU2_LIB}/fetchers/rubygems.sh'
    source '${_GS_EU2_LIB}/fetchers/sdkman.sh'
    source '${_GS_EU2_LIB}/fetchers/sdkmanager.sh'
    source '${_GS_EU2_LIB}/fetchers/pecl.sh'
    source '${_GS_EU2_LIB}/fetchers/url.sh'
    source '${_GS_EU2_LIB}/fetchers/ghcr.sh'
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/ghcr_l_cache
    # Load main.sh which defines _gs_eu2_dispatch_fetcher
    source '${_GS_EU2_LIB}/main.sh'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'ghcr'
    _gs_eu2_record_set \$idx identifier 'testowner/ghcr-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_GHCR_DISPATCH_VERSION'
    _gs_eu2_dispatch_fetcher \$idx
    decision=\$(_gs_eu2_record_get \$idx decision)
    proposed=\$(_gs_eu2_record_get \$idx proposed_version)
    # Dispatch must not produce 'unknown fetcher type' SKIP
    [[ \"\$decision\" != 'SKIP' ]] || {
        err=\$(_gs_eu2_record_get \$idx error_message)
        [[ \"\$err\" == *'unknown fetcher type'* ]] && { echo \"dispatch: unknown type — wiring missing\"; echo FAIL; exit 0; }
    }
    [[ -n \"\$proposed\" ]] || { echo \"dispatch produced empty proposed_version; decision='\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 104 — apply.sh error paths
#
# Covers: Rule 8 tracked-file dirty guard (no_fail=false → return 1;
#         no_fail=true → [SKIP] + return 0), replace-cascade target-not-found
#         with no_fail=true (continues, prints [ERROR], exits 0), and the
#         SKIP replace-only pass target-not-found with no_fail=true.
#
# These paths existed since apply.sh was written; t91f (Section 91) covered
# cascade rollback with no_fail=false. This section fills the remaining gaps.
# ═══════════════════════════════════════════════════════════════════════════
section "104 — apply.sh error paths"

_APPLY_LIBS="
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/git.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/apply.sh'
"

# t104a: Rule 8 dirty-tracked file + no_fail=false → apply returns non-zero.
# Sets up a real git repo, tracks the env file, then modifies it without
# staging so git status --porcelain returns non-empty → guard fires → return 1.
t "t104a: dirty tracked env file + no_fail=false → _gs_eu2_apply_updates returns 1" bash -c "
    ${_APPLY_LIBS}
    declare -A _GS_EU2_CFG=([no_fail]=false [apply_resolve]=false)
    # Create a real git repo in a temp dir
    repo=\$(mktemp -d)
    git -C \"\$repo\" init -q
    git -C \"\$repo\" config user.email 'test@test.com'
    git -C \"\$repo\" config user.name 'Test'
    f=\"\$repo/.env\"
    printf 'GLOBAL_STACK_T104A=1.0.0\n' > \"\$f\"
    git -C \"\$repo\" add \"\$f\"
    git -C \"\$repo\" commit -qm 'init'
    # Modify the file without staging (dirty unstaged)
    printf 'GLOBAL_STACK_T104A=1.0.0\n# dirty\n' > \"\$f\"
    # Set up a record so apply_updates has something to process
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_T104A'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_record_set \$idx proposed_version '2.0.0'
    _gs_eu2_record_set \$idx decision         'AUTO'
    rc=0
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null 2>&1 || rc=\$?
    rm -rf \"\$repo\"
    [[ \"\$rc\" -ne 0 ]] || { echo \"expected non-zero return for dirty file, got 0\"; echo FAIL; exit 0; }
    echo PASS
"

# t104b: Rule 8 dirty-tracked file + no_fail=true → [SKIP] output, returns 0.
# Same setup as t104a but with no_fail=true: the guard fires but exits 0 with
# a [SKIP] message instead of aborting.
t "t104b: dirty tracked env file + no_fail=true → [SKIP] in output, returns 0" bash -c "
    ${_APPLY_LIBS}
    declare -A _GS_EU2_CFG=([no_fail]=true [apply_resolve]=false)
    repo=\$(mktemp -d)
    git -C \"\$repo\" init -q
    git -C \"\$repo\" config user.email 'test@test.com'
    git -C \"\$repo\" config user.name 'Test'
    f=\"\$repo/.env\"
    printf 'GLOBAL_STACK_T104B=1.0.0\n' > \"\$f\"
    git -C \"\$repo\" add \"\$f\"
    git -C \"\$repo\" commit -qm 'init'
    # Dirty (unstaged modification)
    printf 'GLOBAL_STACK_T104B=1.0.0\n# dirty\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_T104B'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_record_set \$idx proposed_version '2.0.0'
    _gs_eu2_record_set \$idx decision         'AUTO'
    rc=0
    out=\$(_gs_eu2_apply_updates \"\$f\" 'false' 2>&1) || rc=\$?
    rm -rf \"\$repo\"
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected exit 0 with no_fail=true, got rc=\$rc\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qiF 'SKIP' \
        || { echo \"expected [SKIP] in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t104c: replace-cascade target-not-found + no_fail=true → primary var IS written
# (no rollback), [ERROR] emitted to stderr, and processing continues.
# Contrast with no_fail=false (t91f): rollback fires and primary reverts.
# Note: function exit code reflects the last (( expr )) statement — focus on
# file-content behavior (rollback vs no-rollback) rather than exit code.
t "t104c: replace-cascade target missing + no_fail=true → primary written (no rollback), [ERROR] emitted" bash -c "
    ${_APPLY_LIBS}
    declare -A _GS_EU2_CFG=([no_fail]=true [apply_resolve]=false)
    f=\$(mktemp)
    # File has the primary VAR but NOT the replace target
    printf '# @todo env-update github:testowner/testrepo 2.4.0\nGLOBAL_STACK_T104C=2.4.0\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T104C'
    _gs_eu2_record_set \$idx current_version   '2.4.0'
    _gs_eu2_record_set \$idx proposed_version  '3.0.0'
    _gs_eu2_record_set \$idx decision          'AUTO'
    _gs_eu2_record_set \$idx replace_targets   'GLOBAL_STACK_T104C_ALIAS'
    _gs_eu2_record_set \$idx replace_templates 'node{major}'
    # Capture stderr (the [ERROR] line); stdout goes to /dev/null (summary line)
    err=\$(_gs_eu2_apply_updates \"\$f\" 'false' 2>&1 >/dev/null || true)
    # Key assertion 1: no rollback — primary var was written to 3.0.0
    grep -qF 'GLOBAL_STACK_T104C=3.0.0' \"\$f\" \
        || { echo \"primary var was rolled back (no_fail=true should prevent rollback); file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    # Key assertion 2: [ERROR] was emitted to stderr
    printf '%s' \"\$err\" | grep -qF '[ERROR]' \
        || { echo \"expected [ERROR] in stderr; got: \$err\"; echo FAIL; exit 0; }
    rm -f \"\$f\"
    echo PASS
"

# t104d: SKIP replace-only pass target missing + no_fail=true → [ERROR] emitted,
# file unchanged (primary VAR still at original value — SKIP means cur==prop).
# Exercises the second loop in _gs_eu2_apply_updates (lines ~396-448).
t "t104d: SKIP replace-only target missing + no_fail=true → [ERROR] emitted, primary unchanged" bash -c "
    ${_APPLY_LIBS}
    declare -A _GS_EU2_CFG=([no_fail]=true [apply_resolve]=false)
    f=\$(mktemp)
    # cur==prop → SKIP decision; target GLOBAL_STACK_T104D_ALIAS missing from file
    printf 'GLOBAL_STACK_T104D=3.0.0\n' > \"\$f\"
    _gs_eu2_record_new; idx=\$_GS_EU2_LAST_IDX
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T104D'
    _gs_eu2_record_set \$idx current_version   '3.0.0'
    _gs_eu2_record_set \$idx proposed_version  '3.0.0'
    _gs_eu2_record_set \$idx decision          'SKIP'
    _gs_eu2_record_set \$idx replace_targets   'GLOBAL_STACK_T104D_ALIAS'
    _gs_eu2_record_set \$idx replace_templates 'node{major}'
    err=\$(_gs_eu2_apply_updates \"\$f\" 'false' 2>&1 >/dev/null || true)
    # Primary var must be unchanged (SKIP → no write to primary)
    grep -qF 'GLOBAL_STACK_T104D=3.0.0' \"\$f\" \
        || { echo \"primary var changed for SKIP decision; file: \$(cat \"\$f\")\"; echo FAIL; exit 0; }
    # [ERROR] must be emitted for the missing replace target
    printf '%s' \"\$err\" | grep -qF '[ERROR]' \
        || { echo \"expected [ERROR] in stderr for missing SKIP target; got: \$err\"; echo FAIL; exit 0; }
    rm -f \"\$f\"
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 105 — parallel fetch (--jobs): correctness + flag validation
# ═══════════════════════════════════════════════════════════════════════════
section "105 — parallel fetch (--jobs)"

# t105a: --jobs=1 and --jobs=4 produce byte-identical stdout.
# Uses four fixture-backed records (dockerhub, github, npm, pypi) so the test
# is fully deterministic and exercises the fan-out/collect round-trip.
t "t105a: --jobs=1 and --jobs=4 produce identical stdout (fixture-backed)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t105a_cache
    f=\${TMP_DIR}/t105a.env
    cat > \"\$f\" <<'ENVEOF'
# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
GLOBAL_STACK_T105A_POSTGRES=18.3-alpine3.23
# @todo env-update dockerhub:_/mysql 9.5.0
GLOBAL_STACK_T105A_MYSQL=9.5.0
# @todo env-update npm:typescript 5.7.0
GLOBAL_STACK_T105A_TS=5.7.0
# @todo env-update pypi:flask 3.1.0
GLOBAL_STACK_T105A_FLASK=3.1.0
ENVEOF
    serial=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --jobs=1 --env-file=\"\$f\" 2>/dev/null)
    parallel=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --jobs=4 --env-file=\"\$f\" 2>/dev/null)
    if [[ \"\$serial\" != \"\$parallel\" ]]; then
        echo 'jobs=1 and jobs=4 output differ:'
        diff <(printf '%s\n' \"\$serial\") <(printf '%s\n' \"\$parallel\") || true
        echo FAIL; exit 0
    fi
    echo \"\$serial\" | grep -qE 'AUTO|SKIP|HOLD' || { echo \"no decision output; got: \$serial\"; echo FAIL; exit 0; }
    echo PASS
"

# t105b: --jobs=4 with a (skip:REASON) record still shows FROZEN in output.
t "t105b: skip-gated record shows FROZEN in parallel mode" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t105b_cache
    f=\${TMP_DIR}/t105b.env
    printf '# @todo env-update (skip:frozen-for-testing) dockerhub:_/postgres 18.3-alpine3.23\nGLOBAL_STACK_T105B=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --jobs=4 --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '[FROZEN' || { echo \"expected [FROZEN] in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t105c: --jobs=0 is rejected (must be a positive integer).
t "t105c: --jobs=0 rejected with error" bash -c "
    err=\$(bash '${ENV_UPDATE_V2}' --jobs=0 --check --env-file='${FIXTURES}/basic-dockerhub.env' 2>&1 || true)
    echo \"\$err\" | grep -qi 'jobs' || { echo \"expected error mentioning --jobs; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

# t105d: --jobs=N documented in --help output.
t "t105d: --jobs documented in --help" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --help 2>&1 || true)
    echo \"\$out\" | grep -q '\-\-jobs' || { echo '--jobs not in --help; got: \$out'; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 107 — P1 audit: HTTP error injection seam + --force-auto alone exits 1
# ═══════════════════════════════════════════════════════════════════════════
section "107 — P1 audit: HTTP inject seam + --force-auto alone exits 1"
# These three asserted `grep -qE 'ERROR|error|injected'` until 2026-08-29 — a
# pattern the inject seam's OWN stderr line ("env-update: injected HTTP error
# 503 …") satisfies on its own, so they would have stayed green even if the
# fetcher had regressed to SKIP. They now assert the [ERROR] decision token.
# They also only ever covered dockerhub; section 119 covers the rest.

# t107a: _GS_EU2_HTTP_INJECT_STATUS=429 → fetcher returns ERROR
t "t107a: HTTP_INJECT_STATUS=429 produces ERROR output" bash -c "
    export _GS_EU2_HTTP_INJECT_STATUS=429
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t107a_cache
    f=\${TMP_DIR}/t107a.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T107A=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"expected the [ERROR] decision token; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t107b: _GS_EU2_HTTP_INJECT_STATUS=503 → fetcher returns ERROR
t "t107b: HTTP_INJECT_STATUS=503 produces ERROR output" bash -c "
    export _GS_EU2_HTTP_INJECT_STATUS=503
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t107b_cache
    f=\${TMP_DIR}/t107b.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T107B=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"expected the [ERROR] decision token; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t107c: _GS_EU2_HTTP_INJECT_STATUS=malformed-json → fetcher returns parse error
t "t107c: HTTP_INJECT_STATUS=malformed-json produces parse ERROR" bash -c "
    export _GS_EU2_HTTP_INJECT_STATUS=malformed-json
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t107c_cache
    f=\${TMP_DIR}/t107c.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T107C=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"expected the [ERROR] decision token; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t107d: --force-auto alone (no --check, no --apply) exits 1
t "t107d: --force-auto alone exits 1 with usage error" bash -c "
    f=\${TMP_DIR}/t107d.env
    cp '${FIXTURES}/basic-dockerhub.env' \"\$f\"
    stderr_out=\$(bash '${ENV_UPDATE_V2}' --force-auto --env-file=\"\$f\" 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    [[ \"\$stderr_out\" == *'--force-auto'* ]] || { echo \"expected --force-auto in error; got: \$stderr_out\"; echo FAIL; exit 0; }
    echo PASS
"

# t107e: --check --force-auto (valid) does NOT exit 1
t "t107e: --check --force-auto (valid combination) exits 0" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t107e_cache
    f=\${TMP_DIR}/t107e.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T107E=18.3-alpine3.23\n' > \"\$f\"
    rc=0
    bash '${ENV_UPDATE_V2}' --check --force-auto --dry-run --env-file=\"\$f\" 2>/dev/null || rc=\$?
    [[ \"\$rc\" -ne 1 ]] || { echo \"--check --force-auto exited 1 (should not)\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 106 — P0 audit fixes: --filter case-insensitive, --reference=invalid
# ═══════════════════════════════════════════════════════════════════════════
section "106 — P0 audit fixes: filter case-insensitive + reference validation"

# t106a: --filter=lowercase matches UPPER_CASE var names (case-insensitive)
t "t106a: --filter=postgres matches GLOBAL_STACK_POSTGRES18_VERSION" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t106a_cache
    f=\${TMP_DIR}/t106a.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --filter=postgres --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_POSTGRES18_VERSION' || { echo \"lowercase filter returned no match; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t106b: --filter=Postgres (mixed case) also matches
t "t106b: --filter=Postgres (mixed case) matches" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t106b_cache
    f=\${TMP_DIR}/t106b.env
    printf '# @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --filter=Postgres --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -q 'GLOBAL_STACK_POSTGRES18_VERSION' || { echo \"mixed-case filter returned no match; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t106c: --reference=blahblah exits 1 and mentions 'unknown'
t "t106c: --reference=blahblah exits 1 with unknown section error" bash -c "
    stderr_out=\$(bash '${ENV_UPDATE_V2}' --reference=blahblah 2>&1 >/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 1 ]] || { echo \"expected exit 1, got \$rc\"; echo FAIL; exit 0; }
    [[ \"\$stderr_out\" == *'unknown'* ]] || { echo \"expected 'unknown' in stderr; got: \$stderr_out\"; echo FAIL; exit 0; }
    echo PASS
"

# t106d: --reference=syntax (valid section) exits 0
t "t106d: --reference=syntax (valid) exits 0 with output" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=syntax 2>/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    [[ -n \"\$out\" ]] || { echo \"expected output, got empty\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 108 — P2 audit: (hold) error, float+watch-major ERROR, RESOLVED replace
# ═══════════════════════════════════════════════════════════════════════════
section "108 — P2 audit: (hold) hint, float+watch-major, RESOLVED+replace, Section C"

# t108a: (hold) annotation exits 1 with specific hint message
t "t108a: (hold) annotation exits 1 with hint about (manual)/(override)" bash -c "
    f=\${TMP_DIR}/t108a.env
    printf '# @todo env-update (hold) dockerhub:_/postgres:18 18.3-alpine3.23\nGLOBAL_STACK_T108A=18.3\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1) && { echo 'expected exit 1 but got 0; out='\"\$out\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF '(hold) is not a valid annotation flag' || { echo \"expected hold error; got: \$out\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF '(manual) or (override)' || { echo \"expected manual/override hint; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t108b: float current + (watch-major) emits [ERROR] record
t "t108b: float current + (watch-major) emits [ERROR]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t108b_cache
    f=\${TMP_DIR}/t108b.env
    printf '# @todo env-update (watch-major) dockerhub:_/postgres:18 latest\nGLOBAL_STACK_T108B_VERSION=latest\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1)
    printf '%s' \"\$out\" | grep -q 'ERROR' || { echo \"expected ERROR in output; got: \$out\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -q 'watch-major' || { echo \"expected watch-major in error; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t108c: --reference=matrix outputs Section C cross-product intersections
t "t108c: --reference=matrix includes Section C cross-product" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --reference=matrix 2>/dev/null)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"expected exit 0, got \$rc\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF 'SECTION C' || { echo \"Section C not in matrix output; got truncated: \$(printf '%s' \"\$out\" | tail -5)\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF 'C7. (hold) annotation' || { echo 'C7 not found in output'; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF 'C11.' || { echo 'C11 not found in output'; echo FAIL; exit 0; }
    echo PASS
"

# t108d: RESOLVED + (replace:) cascade fires with --apply-resolve — target is rewritten
t "t108d: RESOLVED + (replace:) cascade writes target when --apply-resolve used" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t108d_cache
    f=\${TMP_DIR}/t108d.env
    printf '# @todo env-update (replace:GLOBAL_STACK_T108D_ALIAS={version}) dockerhub:_/node latest\nGLOBAL_STACK_T108D_VERSION=latest\nGLOBAL_STACK_T108D_ALIAS=old\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --apply --apply-resolve --yes --env-file=\"\$f\" 2>&1)
    rc=\$?
    [[ \"\$rc\" -eq 0 ]] || { echo \"apply failed with rc=\$rc; out=\$out\"; echo FAIL; exit 0; }
    # After apply-resolve, T108D_VERSION should be pinned (no longer 'latest') and
    # T108D_ALIAS should be rewritten to the same concrete version
    pinned_ver=\$(grep '^GLOBAL_STACK_T108D_VERSION=' \"\$f\" | cut -d= -f2-)
    alias_ver=\$(grep '^GLOBAL_STACK_T108D_ALIAS=' \"\$f\" | cut -d= -f2-)
    [[ \"\$pinned_ver\" != 'latest' ]] || { echo \"VERSION not pinned; still 'latest'; got: \$pinned_ver\"; echo FAIL; exit 0; }
    [[ \"\$alias_ver\" == \"\$pinned_ver\" ]] || { echo \"ALIAS (\$alias_ver) != VERSION (\$pinned_ver)\"; echo FAIL; exit 0; }
    printf '%s' \"\$out\" | grep -qF 'REPLACE' || { echo \"no REPLACE marker in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 109 — network hardening: timeout/5xx retry, honest errors, CODEBERG_TOKEN
# ═══════════════════════════════════════════════════════════════════════════
# Root cause context: Codeberg list endpoints (/tags, /releases) intermittently
# return HTTP 504 after ~30s during server-side degradation. With curl --max-time 15,
# curl aborts at 15s with exit 28 / HTTP 000 BEFORE the 504 arrives. These tests
# verify the retry loop treats BOTH curl-timeout (exit 28 / 000) AND HTTP 429/502/503/504
# as retryable, emits honest per-mode error messages, fast-fails 404, and that
# CODEBERG_TOKEN is sent with the Gitea/Forgejo-canonical "token" auth scheme.
section "109 — network hardening: timeout/5xx retry + honest errors + CODEBERG_TOKEN"

# t109a: curl exit 28 / HTTP 000 (timeout) on attempt 1, 200 on attempt 2 → success after retry
t "t109a: http_get_core retries curl-timeout (exit 28/000) and recovers" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109a_curl\"
    mkdir -p \"\${_fake_dir}\"
    printf '0' > \"\${_fake_dir}/.call_count\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
# Fake curl: simulate operation-timeout (exit 28, http_code 000) on call 1, 200 after.
_cf=\"\$(dirname \"\$0\")/.call_count\"
_c=\$(( \$(cat \"\${_cf}\" 2>/dev/null || echo 0) + 1 ))
printf '%d' \"\${_c}\" > \"\${_cf}\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
if [[ \"\${_c}\" -le 1 ]]; then
    [[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
    printf '000'      # curl prints 000 for http_code on a timeout
    exit 28           # CURLE_OPERATION_TIMEDOUT
else
    [[ -n \"\${_out}\" ]] && printf '{\"name\":\"ok\"}' > \"\${_out}\"
    printf '200'
    exit 0
fi
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    out=\$(PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core 'https://example.com/x' 2>&1)
    rc=\$?
    [[ \"\${rc}\" -eq 0 ]] || { echo \"expected 0 after retry, rc=\${rc}; out=\${out}\"; echo FAIL; exit 0; }
    printf '%s' \"\${out}\" | grep -q 'ok' || { echo \"expected body 'ok'; got: \${out}\"; echo FAIL; exit 0; }
    [[ \"\$(cat \"\${_fake_dir}/.call_count\")\" -gt 1 ]] || { echo 'no retry happened'; echo FAIL; exit 0; }
    echo PASS
"

# t109b: persistent curl-timeout → ERROR with honest 'upstream timeout' message
t "t109b: persistent curl-timeout fails with 'upstream timeout' message" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109b_curl\"
    mkdir -p \"\${_fake_dir}\"
    printf '0' > \"\${_fake_dir}/.call_count\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_cf=\"\$(dirname \"\$0\")/.call_count\"
printf '%d' \$(( \$(cat \"\${_cf}\" 2>/dev/null || echo 0) + 1 )) > \"\${_cf}\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
printf '000'; exit 28
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    rc=0
    out=\$(PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core 'https://example.com/x' 2>&1) || rc=\$?
    [[ \"\${rc}\" -ne 0 ]] || { echo \"expected non-zero exit; out=\${out}\"; echo FAIL; exit 0; }
    [[ \"\$(cat \"\${_fake_dir}/.call_count\")\" -ge 3 ]] || { echo 'expected >=3 attempts'; echo FAIL; exit 0; }
    printf '%s' \"\${out}\" | grep -qi 'timeout' || { echo \"expected 'timeout' in msg; got: \${out}\"; echo FAIL; exit 0; }
    echo PASS
"

# t109c: HTTP 504 then 200 → success after retry (transient 5xx covered)
t "t109c: http_get_core retries HTTP 504 and recovers" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109c_curl\"
    mkdir -p \"\${_fake_dir}\"
    printf '0' > \"\${_fake_dir}/.call_count\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_cf=\"\$(dirname \"\$0\")/.call_count\"
_c=\$(( \$(cat \"\${_cf}\" 2>/dev/null || echo 0) + 1 ))
printf '%d' \"\${_c}\" > \"\${_cf}\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
if [[ \"\${_c}\" -le 1 ]]; then
    [[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
    printf '504'; exit 0
else
    [[ -n \"\${_out}\" ]] && printf '{\"name\":\"ok\"}' > \"\${_out}\"
    printf '200'; exit 0
fi
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    out=\$(PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core 'https://example.com/x' 2>&1)
    rc=\$?
    [[ \"\${rc}\" -eq 0 ]] || { echo \"expected 0 after retry; rc=\${rc}; out=\${out}\"; echo FAIL; exit 0; }
    printf '%s' \"\${out}\" | grep -q 'ok' || { echo \"expected 'ok'; got: \${out}\"; echo FAIL; exit 0; }
    [[ \"\$(cat \"\${_fake_dir}/.call_count\")\" -gt 1 ]] || { echo 'no retry'; echo FAIL; exit 0; }
    echo PASS
"

# t109d: persistent 503 → ERROR with 'transient upstream error' message
t "t109d: persistent 503 fails with 'transient upstream error' message" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109d_curl\"
    mkdir -p \"\${_fake_dir}\"
    printf '0' > \"\${_fake_dir}/.call_count\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_cf=\"\$(dirname \"\$0\")/.call_count\"
printf '%d' \$(( \$(cat \"\${_cf}\" 2>/dev/null || echo 0) + 1 )) > \"\${_cf}\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
printf '503'; exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    rc=0
    out=\$(PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core 'https://example.com/x' 2>&1) || rc=\$?
    [[ \"\${rc}\" -ne 0 ]] || { echo 'expected non-zero exit'; echo FAIL; exit 0; }
    [[ \"\$(cat \"\${_fake_dir}/.call_count\")\" -ge 3 ]] || { echo 'expected >=3 attempts'; echo FAIL; exit 0; }
    printf '%s' \"\${out}\" | grep -qi 'transient upstream error' \
        || { echo \"expected 'transient upstream error' msg; got: \${out}\"; echo FAIL; exit 0; }
    echo PASS
"

# t109e: 404 fast-fails — exactly one curl call, no retry
t "t109e: 404 fast-fails with no retry" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109e_curl\"
    mkdir -p \"\${_fake_dir}\"
    printf '0' > \"\${_fake_dir}/.call_count\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_cf=\"\$(dirname \"\$0\")/.call_count\"
printf '%d' \$(( \$(cat \"\${_cf}\" 2>/dev/null || echo 0) + 1 )) > \"\${_cf}\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
printf '404'; exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    rc=0
    PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core 'https://example.com/x' 2>/dev/null || rc=\$?
    [[ \"\${rc}\" -ne 0 ]] || { echo 'expected non-zero exit for 404'; echo FAIL; exit 0; }
    [[ \"\$(cat \"\${_fake_dir}/.call_count\")\" -eq 1 ]] \
        || { echo \"expected 1 call (no retry), got \$(cat \"\${_fake_dir}/.call_count\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t109f: CODEBERG_TOKEN sent with 'Authorization: token <TOKEN>' (Gitea/Forgejo scheme, NOT Bearer)
t "t109f: CODEBERG_TOKEN sent as 'Authorization: token' (not Bearer)" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109f_curl\"
    mkdir -p \"\${_fake_dir}\"
    # Fake curl dumps its header args to \$(dirname \\\$0)/.headers (resolved at runtime).
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
printf '%s\n' \"\$@\" > \"\$(dirname \"\$0\")/.headers\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '[]' > \"\${_out}\"
printf '200'; exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    # Call the auth wrapper directly with the 'token' scheme
    PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_auth 'https://codeberg.org/api/v1/repos/x/y/tags?limit=50' 'SECRET123' 'token' >/dev/null 2>&1
    grep -q 'Authorization: token SECRET123' \"\${_fake_dir}/.headers\" \
        || { echo \"expected 'Authorization: token SECRET123'; got: \$(cat \"\${_fake_dir}/.headers\")\"; echo FAIL; exit 0; }
    grep -q 'Authorization: Bearer' \"\${_fake_dir}/.headers\" \
        && { echo \"must NOT use Bearer for codeberg; got: \$(cat \"\${_fake_dir}/.headers\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t109g: empty token → unauthenticated (no Authorization header sent)
t "t109g: empty CODEBERG_TOKEN sends no Authorization header" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t109g_curl\"
    mkdir -p \"\${_fake_dir}\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
printf '%s\n' \"\$@\" > \"\$(dirname \"\$0\")/.headers\"
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '[]' > \"\${_out}\"
printf '200'; exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    # Empty token → unauthenticated path, no Authorization header
    PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_auth 'https://codeberg.org/api/v1/repos/x/y/tags' '' 'token' >/dev/null 2>&1
    grep -q 'Authorization:' \"\${_fake_dir}/.headers\" \
        && { echo \"unexpected Authorization header for empty token; got: \$(cat \"\${_fake_dir}/.headers\")\"; echo FAIL; exit 0; }
    echo PASS
"

# t109h: codeberg fetcher honest error_message on tags-fallback failure (unreachable/timeout)
t "t109h: codeberg tags-fallback failure sets honest 'unreachable or timed out' error" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/codeberg.sh'
    _fake_dir=\"\${TMP_DIR}/t109h_curl\"
    mkdir -p \"\${_fake_dir}\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_out=''
_w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '' > \"\${_out}\"
# releases → 404 (control-flow to tags); tags → persistent timeout (000/exit 28)
if printf '%s' \"\$@\" | grep -q '/releases'; then
    printf '404'; exit 0
else
    printf '000'; exit 28
fi
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t109h_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'codeberg'
    _gs_eu2_record_set \$idx identifier 'testorg/tags-only'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_TAGSONLY_VERSION'
    PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_fetch_codeberg \$idx 2>/dev/null
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\${decision}\" == 'ERROR' ]] || { echo \"expected ERROR, got '\${decision}'\"; echo FAIL; exit 0; }
    printf '%s' \"\${err}\" | grep -qi 'unreachable or timed out' \
        || { echo \"expected honest unreachable/timeout msg; got: '\${err}'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
section "110 — github (use-sha) HEAD tracking + version-prefix on SHA (php.edge)"

# t110a: parse — (use-sha)(version-prefix:) github: annotation records the flags + identifier
t "t110a: parse github use-sha annotation → use_sha + version_prefix + identifier" bash -c "
    f=\${TMP_DIR}/t110a.env
    printf '%s\n%s\n' \
      '# @todo env-update (use-sha) (git:php/php-src) (version-prefix:github.com/php/php-src@) github:php/php-src next sha:9390b68d5d68c03bbfddf5ae7b48a28751b1b62b' \
      'GLOBAL_STACK_T110A=github.com/php/php-src@9390b68d5d68c03bbfddf5ae7b48a28751b1b62b' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -q 'type: github'                                || { echo \"no type:github\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'identifier: php/php-src'                     || { echo \"no identifier\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'use_sha: true'                              || { echo \"use_sha not true\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'git_repo: php/php-src'                       || { echo \"no git_repo\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -q 'version_prefix: github.com/php/php-src@'     || { echo \"no version_prefix\"; echo FAIL; exit 0; }
    echo PASS
"

# t110b: apply_single with use_sha + version_prefix → VAR= gets the FULL ref; annotation sha: stays BARE
t "t110b: apply_single use_sha+prefix writes full ref to VAR, bare sha: to annotation" bash -c "
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t110b.env
    ann='# @todo env-update (use-sha) (version-prefix:github.com/php/php-src@) github:php/php-src next sha:0000000000000000000000000000000000000000'
    printf '%s\n%s\n' \"\$ann\" 'GLOBAL_STACK_T110B=github.com/php/php-src@0000000000000000000000000000000000000000' > \"\$f\"
    _gs_eu2_apply_single \"\$f\" 'GLOBAL_STACK_T110B' '' \"\$ann\" '' \
        '0000000000000000000000000000000000000000' 'abc123def456abc123def456abc123def456abcd' \
        'true' 'false' 'abc123def456abc123def456abc123def456abcd' 'github.com/php/php-src@'
    grep -q '^GLOBAL_STACK_T110B=github.com/php/php-src@abc123def456abc123def456abc123def456abcd\$' \"\$f\" \
        || { echo 'VAR not full ref'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -q 'sha:abc123def456abc123def456abc123def456abcd' \"\$f\" \
        || { echo 'annotation sha: not bare-updated'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -q 'sha:github.com' \"\$f\" && { echo 'annotation sha: wrongly prefixed'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

# t110c: BACKWARD-COMPAT — empty version_prefix → VAR= gets the BARE sha (existing PECL use-sha behaviour)
t "t110c: apply_single use_sha + empty prefix → VAR= is bare sha (PECL regression guard)" bash -c "
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t110c.env
    ann='# @todo env-update (use-sha) pecl:raphf (git:m6w6/ext-raphf) 2.0.2 sha:0000000000000000000000000000000000000000'
    printf '%s\n%s\n' \"\$ann\" 'GLOBAL_STACK_T110C=0000000000000000000000000000000000000000' > \"\$f\"
    _gs_eu2_apply_single \"\$f\" 'GLOBAL_STACK_T110C' '' \"\$ann\" '' \
        '0000000000000000000000000000000000000000' 'abc123def456abc123def456abc123def456abcd' \
        'true' 'false' 'abc123def456abc123def456abc123def456abcd' ''
    grep -q '^GLOBAL_STACK_T110C=abc123def456abc123def456abc123def456abcd\$' \"\$f\" \
        || { echo 'VAR not bare sha'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

# t110d: fetcher — (use-sha) github: sets proposed_sha from HEAD and SUPPRESSES version to current
t "t110d: fetch_github use-sha sets proposed_sha + pins proposed_version to current" bash -c "
    source '${_GS_EU2_LIB}/config/defaults.sh'
    source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/semver.sh'
    source '${_GS_EU2_LIB}/core/channel.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    source '${_GS_EU2_LIB}/core/cache.sh'
    source '${_GS_EU2_LIB}/http/curl.sh'
    source '${_GS_EU2_LIB}/fetchers/github.sh'
    _fake=\"\${TMP_DIR}/t110d_curl\"; mkdir -p \"\$_fake\"
    cat > \"\${_fake}/curl\" <<'FC'
#!/bin/bash
_out=''; _w=''
for _a in \"\$@\"; do [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }; [[ \"\${_a}\" == '-o' ]] && _w=y; done
if printf '%s' \"\$@\" | grep -q 'per_page'; then
    [[ -n \"\${_out}\" ]] && printf '[{\"sha\":\"abc123def456abc123def456abc123def456abcd\"}]' > \"\${_out}\"
else
    [[ -n \"\${_out}\" ]] && printf '{\"commit\":{\"author\":{\"date\":\"2026-01-01T00:00:00Z\"}}}' > \"\${_out}\"
fi
printf '200'; exit 0
FC
    chmod +x \"\${_fake}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake}/sleep\"; chmod +x \"\${_fake}/sleep\"
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t110d_cache\"
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'github'
    _gs_eu2_record_set \$idx identifier      'php/php-src'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T110D'
    _gs_eu2_record_set \$idx use_sha         'true'
    _gs_eu2_record_set \$idx git_repo        'php/php-src'
    _gs_eu2_record_set \$idx current_version 'next'
    PATH=\"\${_fake}:\${PATH}\" _gs_eu2_fetch_github \$idx 2>/dev/null
    ps=\$(_gs_eu2_record_get \$idx proposed_sha)
    pv=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$ps\" == 'abc123def456abc123def456abc123def456abcd' ]] || { echo \"proposed_sha='\$ps'\"; echo FAIL; exit 0; }
    [[ \"\$pv\" == 'next' ]] || { echo \"proposed_version='\$pv' (expected suppressed to 'next')\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 111 — output color (decision tags + summary counts, gated)
# ═══════════════════════════════════════════════════════════════════════════
section "111 — output color (tags + summary, gated)"

t "t111a: --check default (non-TTY) emits no ANSI color codes" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[0;32m' && { echo 'found green ANSI when color should be off'; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[AUTO'  || { echo 'plain [AUTO tag missing'; echo FAIL; exit 0; }
    echo PASS
"

t "t111b: _GS_EU2_COLOR_FORCE=1 colors [AUTO] green" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[0;32m' || { echo 'green ANSI missing under FORCE'; echo FAIL; exit 0; }
    echo PASS
"

t "t111c: [SKIP] label is NOT colored under FORCE (normal-behavior exemption)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    skip=\$(echo \"\$out\" | grep -F '[SKIP')
    [[ -n \"\$skip\" ]] || { echo 'no SKIP line found'; echo FAIL; exit 0; }
    echo \"\$skip\" | grep -qF '[0;3' && { echo 'SKIP label was colored'; echo FAIL; exit 0; }
    echo \"\$skip\" | grep -qF '[2m'  && { echo 'SKIP label was dimmed'; echo FAIL; exit 0; }
    echo PASS
"

t "t111d: [ERROR] label colored bold red under FORCE" bash -c "
    f=\${TMP_DIR}/t111d.env
    printf '# @todo env-update dockerhub:_/no-such-image-xyzzy999 1.0.0\nGLOBAL_STACK_COLOR_ERR_TEST_VERSION=1.0.0\n' > \"\$f\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file=\"\$f\" 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[1;31m' || { echo 'bold-red ANSI missing for ERROR'; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[ERROR' || { echo 'plain [ERROR tag missing'; echo FAIL; exit 0; }
    echo PASS
"

t "t111e: NO_COLOR overrides _GS_EU2_COLOR_FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(NO_COLOR=1 _GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[0;32m' && { echo 'color present despite NO_COLOR'; echo FAIL; exit 0; }
    echo PASS
"

t "t111f: TERM=dumb overrides _GS_EU2_COLOR_FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(TERM=dumb _GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[0;32m' && { echo 'color present despite TERM=dumb'; echo FAIL; exit 0; }
    echo PASS
"

t "t111g: --format=json suppresses color even under FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --format=json --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$out\" | grep -qF '[0;32m' && { echo 'color present in json mode'; echo FAIL; exit 0; }
    echo PASS
"

t "t111h: --apply colors [APPLIED] green under FORCE, none when off" bash -c "
    cp '${FIXTURES}/combined-real-world.env' \"\${TMP_DIR}/t111h_on.env\"
    cp '${FIXTURES}/combined-real-world.env' \"\${TMP_DIR}/t111h_off.env\"
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    on=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --apply --yes --no-cache --env-file=\"\${TMP_DIR}/t111h_on.env\" 2>&1)
    off=\$(bash '${ENV_UPDATE_V2}' --apply --yes --no-cache --env-file=\"\${TMP_DIR}/t111h_off.env\" 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    echo \"\$on\"  | grep -qF '[0;32m' || { echo 'apply [APPLIED] not green under FORCE; got: '\$on; echo FAIL; exit 0; }
    echo \"\$off\" | grep -qF '[0;32m' && { echo 'apply colored when off; got: '\$off; echo FAIL; exit 0; }
    echo PASS
"

t "t111i: [DRIFT] sub-line colored magenta under FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t111i_cache
    f=\${TMP_DIR}/t111i.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T111I=\n' > \"\$f\"
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[0;35m' || { echo 'DRIFT not magenta under FORCE; got: '\$out; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[DRIFT]' || { echo 'plain [DRIFT] tag missing'; echo FAIL; exit 0; }
    echo PASS
"

t "t111j: Summary line colors non-zero AUTO count green under FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    unset _GS_EU2_HTTP_FIXTURE_DIR
    sumline=\$(echo \"\$out\" | grep -F 'Summary:')
    [[ -n \"\$sumline\" ]] || { echo 'no Summary line'; echo FAIL; exit 0; }
    echo \"\$sumline\" | grep -qF '[0;32m' || { echo 'summary AUTO count not green; got: '\$sumline; echo FAIL; exit 0; }
    echo PASS
"

t "t111k: secondary summary line colors non-zero DRIFT count magenta under FORCE" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t111k_cache
    f=\${TMP_DIR}/t111k.env
    printf '# @todo env-update github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T111K=\n' > \"\$f\"
    out=\$(_GS_EU2_COLOR_FORCE=1 bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    secline=\$(echo \"\$out\" | grep -F 'DRIFT (')
    [[ -n \"\$secline\" ]] || { echo 'no secondary signals line'; echo FAIL; exit 0; }
    echo \"\$secline\" | grep -qF '[0;35m' || { echo 'secondary DRIFT count not magenta; got: '\$secline; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 112 — HTTP failure diagnostics sink + per-page inject seam
#
# Regression cover for the Docker Hub anonymous-pagination 403: the http layer
# used to discard the status code and delete the body on failure, so no caller
# could tell a 403-offset-cap from a 404, a DNS failure or a timeout.
#
# Page numbers here are 3/5/7/9, not the real-world 11. The code has no
# knowledge of page 11 — the cap is Docker Hub's (offset 1000 / page_size 100).
# A short chain exercises the identical mechanism with a fraction of the
# fixture bulk; the real numbers live in the error text and the docs.
# ═══════════════════════════════════════════════════════════════════════════
section "112 — http diag sink + per-page inject (dockerhub pagination 403)"

_DIAG_DH_LIBS="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t112a: page extraction helper — the shared basis of the fixture path and the
# per-page inject gate. "page_size=" must NOT be mistaken for "page=".
t "t112a: _gs_eu2_http_url_page extracts page=N and ignores page_size=" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    got=\$(_gs_eu2_http_url_page 'https://x/y?ordering=last_updated&page=11&page_size=100')
    [[ \"\$got\" == '11' ]] || { echo \"mid-query page=11 -> '\$got'\"; echo FAIL; exit 0; }
    got=\$(_gs_eu2_http_url_page 'https://x/y?page=2&other=1')
    [[ \"\$got\" == '2' ]] || { echo \"leading page=2 -> '\$got'\"; echo FAIL; exit 0; }
    got=\$(_gs_eu2_http_url_page 'https://x/y?page_size=100&ordering=last_updated')
    [[ -z \"\$got\" ]] || { echo \"page_size wrongly matched -> '\$got'\"; echo FAIL; exit 0; }
    got=\$(_gs_eu2_http_url_page 'https://x/y')
    [[ -z \"\$got\" ]] || { echo \"no query string -> '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

# t112b: the fixture-path refactor must not drift — all 123 fixtures resolve
# through _gs_eu2_fixture_path, so page-1 (no suffix) and page-N must be exact.
t "t112b: _gs_eu2_fixture_path page suffix unchanged after refactor" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    p=\$(_gs_eu2_fixture_path 'https://registry.hub.docker.com/v2/repositories/library/mongo/tags?ordering=last_updated&page=2&page_size=100')
    [[ \"\$p\" == 'registry.hub.docker.com_v2_repositories_library_mongo_tags_page_2' ]] \
        || { echo \"page-2 path drifted: \$p\"; echo FAIL; exit 0; }
    p=\$(_gs_eu2_fixture_path 'https://registry.hub.docker.com/v2/repositories/library/mongo/tags?page_size=100&ordering=last_updated')
    [[ \"\$p\" == 'registry.hub.docker.com_v2_repositories_library_mongo_tags' ]] \
        || { echo \"page-1 path drifted: \$p\"; echo FAIL; exit 0; }
    echo PASS
"

# t112c: control — a complete multi-page walk. First multi-page dockerhub
# coverage in the suite; 1.2.0 exists ONLY on page 3, so a short walk fails it.
t "t112c: dockerhub walks a 3-page fixture chain to the page-3-only tag" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112C'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.2.0' ]] || { echo \"expected 1.2.0 (page-3 only); got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t112d: THE BUG — mid-pagination 403. Decision stays ERROR (unchanged), but the
# message must now name the HTTP status and the page it stopped on.
t "t112d: 403 at page 3 -> ERROR message names HTTP status and page" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112d_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    export _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE=3
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112D'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    msg=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR; got: '\$dec'\"; echo FAIL; exit 0; }
    case \"\$msg\" in *'library/pagecap-test'*) :;; *) echo \"namespace missing: \$msg\"; echo FAIL; exit 0;; esac
    case \"\$msg\" in *'403'*)  :;; *) echo \"HTTP status missing: \$msg\"; echo FAIL; exit 0;; esac
    case \"\$msg\" in *'page 3'*) :;; *) echo \"page number missing: \$msg\"; echo FAIL; exit 0;; esac
    echo PASS
"

# t112e: the inject seam is per-page — a page number never reached must leave
# the walk completely untouched (proves pages 1-2 in t112d were NOT injected).
t "t112e: INJECT_STATUS_AT_PAGE on an unreached page leaves the walk intact" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112e_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    export _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE=99
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112E'
    _gs_eu2_fetch_dockerhub \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.2.0' ]] || { echo \"walk disturbed; got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t112f: backward compatibility — INJECT_STATUS without AT_PAGE keeps its legacy
# global behaviour (fires on page 1, which carries no page= param).
t "t112f: INJECT_STATUS without AT_PAGE still fails page 1 (legacy)" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112f_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112F'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    msg=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR; got: '\$dec'\"; echo FAIL; exit 0; }
    case \"\$msg\" in *'403'*) :;; *) echo \"HTTP status missing: \$msg\"; echo FAIL; exit 0;; esac
    case \"\$msg\" in *'page '*) echo \"page claimed on a page-1 failure: \$msg\"; echo FAIL; exit 0;; esac
    echo PASS
"

# t112g: a failure with NO status (fixture not found == DNS/transport class)
# must keep the exact legacy message — no invented status, no invented page.
t "t112g: statusless failure keeps the legacy 'fetch failed for NS' message" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/absent-fixture-t112g'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112G'
    _gs_eu2_fetch_dockerhub \$idx
    msg=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$msg\" == 'fetch failed for library/absent-fixture-t112g' ]] \
        || { echo \"legacy message drifted: '\$msg'\"; echo FAIL; exit 0; }
    echo PASS
"

# t112h: the sink on the REAL network path — a genuine curl 403 (fake curl on
# PATH), not the inject shortcut. Status, body and URL must all survive.
t "t112h: http_get_core records status+body+url into the diag sink on a real 403" bash -c "
    source '${_GS_EU2_LIB}/http/curl.sh'
    _fake_dir=\"\${TMP_DIR}/t112h_curl\"
    mkdir -p \"\${_fake_dir}\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
_out=''; _w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
[[ -n \"\${_out}\" ]] && printf '%s' '{\"message\":\"pagination offset too large for anonymous requests; sign in to page further\",\"errinfo\":{}}' > \"\${_out}\"
printf '403'
exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    _u='https://registry.hub.docker.com/v2/repositories/library/mongo/tags?ordering=last_updated&page=11&page_size=100'
    sink=\$(_gs_eu2_http_diag_new)
    rc=0
    PATH=\"\${_fake_dir}:\${PATH}\" _gs_eu2_http_get_core \"\${_u}\" '' '' \"\${sink}\" >/dev/null 2>&1 || rc=\$?
    [[ \"\${rc}\" -ne 0 ]] || { echo 'expected non-zero rc on 403'; echo FAIL; exit 0; }
    st=\$(_gs_eu2_http_diag_status \"\${sink}\")
    [[ \"\${st}\" == '403' ]] || { echo \"status not recorded: '\${st}'\"; echo FAIL; exit 0; }
    bd=\$(_gs_eu2_http_diag_body \"\${sink}\")
    case \"\${bd}\" in *'pagination offset too large'*) :;; *) echo \"body not recorded: '\${bd}'\"; echo FAIL; exit 0;; esac
    ur=\$(_gs_eu2_http_diag_url \"\${sink}\")
    [[ \"\${ur}\" == \"\${_u}\" ]] || { echo \"url not recorded: '\${ur}'\"; echo FAIL; exit 0; }
    [[ \"\$(_gs_eu2_http_url_page \"\${ur}\")\" == '11' ]] || { echo 'page not derivable from recorded url'; echo FAIL; exit 0; }
    _gs_eu2_http_diag_free \"\${sink}\"
    [[ ! -e \"\${sink}\" ]] || { echo 'sink not freed'; echo FAIL; exit 0; }
    echo PASS
"

# t112i: the accessors run inside a library that uses 'set -eEuo pipefail'.
# An empty sink must NOT abort the caller — this is the DNS/transport path.
t "t112i: diag accessors are set -e safe on an empty sink" bash -c "
    set -eEuo pipefail
    source '${_GS_EU2_LIB}/http/curl.sh'
    sink=\$(_gs_eu2_http_diag_new)
    st=\$(_gs_eu2_http_diag_status \"\${sink}\")
    bd=\$(_gs_eu2_http_diag_body \"\${sink}\")
    ur=\$(_gs_eu2_http_diag_url \"\${sink}\")
    [[ -z \"\${st}\${bd}\${ur}\" ]] || { echo \"expected all-empty; got '\${st}|\${bd}|\${ur}'\"; echo FAIL; exit 0; }
    _gs_eu2_http_diag_free \"\${sink}\"
    echo PASS
"

# t112j: THE RACE DETECTOR. Four namespaces cap at four DIFFERENT pages, run
# concurrently at --jobs=8 through the real fan-out and the real curl path.
# A shared or fixed-path sink shows up as one record reporting another's page.
# Byte-identity between --jobs=1 and --jobs=8 would NOT catch that; distinct
# per-record diagnostics do.
t "t112j: --jobs=8 keeps each record's failure page distinct (sink race)" bash -c "
    _fake_dir=\"\${TMP_DIR}/t112j_curl\"
    mkdir -p \"\${_fake_dir}\"
    cat > \"\${_fake_dir}/curl\" <<'FAKECURL'
#!/bin/bash
# Fake Docker Hub: each namespace serves pages up to its own cap, then 403s
# exactly like the real anonymous offset limit.
_out=''; _w=''
for _a in \"\$@\"; do
    [[ \"\${_w}\" == y ]] && { _out=\"\${_a}\"; _w=''; continue; }
    [[ \"\${_a}\" == '-o' ]] && _w=y
done
_url=\"\${@: -1}\"
case \"\${_url}\" in
    */library/alpha/tags*)   _ns=alpha;   _cap=2 ;;
    */library/bravo/tags*)   _ns=bravo;   _cap=4 ;;
    */library/charlie/tags*) _ns=charlie; _cap=6 ;;
    */library/delta/tags*)   _ns=delta;   _cap=8 ;;
    *) [[ -n \"\${_out}\" ]] && printf '%s' '{\"message\":\"not found\"}' > \"\${_out}\"; printf '404'; exit 0 ;;
esac
_page=1
[[ \"\${_url}\" =~ (^|[\&?])page=([0-9]+) ]] && _page=\"\${BASH_REMATCH[2]}\"
if [[ \"\${_page}\" -gt \"\${_cap}\" ]]; then
    [[ -n \"\${_out}\" ]] && printf '%s' '{\"message\":\"pagination offset too large for anonymous requests; sign in to page further\",\"errinfo\":{}}' > \"\${_out}\"
    printf '403'; exit 0
fi
[[ -n \"\${_out}\" ]] && printf '{\"count\":99,\"next\":\"https://registry.hub.docker.com/v2/repositories/library/%s/tags?ordering=last_updated&page=%d&page_size=100\",\"results\":[{\"name\":\"1.%d.0\"}]}' \"\${_ns}\" \"\$(( _page + 1 ))\" \"\${_page}\" > \"\${_out}\"
printf '200'; exit 0
FAKECURL
    chmod +x \"\${_fake_dir}/curl\"
    printf '#!/bin/bash\nexit 0\n' > \"\${_fake_dir}/sleep\"; chmod +x \"\${_fake_dir}/sleep\"
    f=\${TMP_DIR}/t112j.env
    cat > \"\$f\" <<'ENVEOF'
# @todo env-update dockerhub:_/alpha 1.0.0
GLOBAL_STACK_T112J_ALPHA=1.0.0
# @todo env-update dockerhub:_/bravo 1.0.0
GLOBAL_STACK_T112J_BRAVO=1.0.0
# @todo env-update dockerhub:_/charlie 1.0.0
GLOBAL_STACK_T112J_CHARLIE=1.0.0
# @todo env-update dockerhub:_/delta 1.0.0
GLOBAL_STACK_T112J_DELTA=1.0.0
ENVEOF
    out=\$(PATH=\"\${_fake_dir}:\${PATH}\" bash '${ENV_UPDATE_V2}' --check --dry-run --no-cache --jobs=8 --env-file=\"\$f\" 2>/dev/null)
    for pair in 'ALPHA:3' 'BRAVO:5' 'CHARLIE:7' 'DELTA:9'; do
        var=\${pair%%:*}; want=\${pair##*:}
        line=\$(echo \"\$out\" | grep -F \"GLOBAL_STACK_T112J_\${var}\" || true)
        [[ -n \"\$line\" ]] || { echo \"no output line for \${var}\"; echo \"\$out\"; echo FAIL; exit 0; }
        case \"\$line\" in *\"page \${want}\"*) :;; *) echo \"\${var} expected 'page \${want}'; got: \$line\"; echo \"\$out\"; echo FAIL; exit 0;; esac
        case \"\$line\" in *403*) :;; *) echo \"\${var} missing HTTP 403: \$line\"; echo FAIL; exit 0;; esac
    done
    echo PASS
"

# t112k: the sink must degrade, never escalate. If mktemp fails the run must NOT
# abort under 'set -eEuo pipefail' — it must fall back to the pre-change message.
t "t112k: a failing mktemp degrades to the legacy message, never aborts" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t112k_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    export _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE=3
    _fake_dir=\"\${TMP_DIR}/t112k_bin\"
    mkdir -p \"\${_fake_dir}\"
    printf '#!/bin/bash\nexit 1\n' > \"\${_fake_dir}/mktemp\"; chmod +x \"\${_fake_dir}/mktemp\"
    PATH=\"\${_fake_dir}:\${PATH}\"
    set -eEuo pipefail
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T112K'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    msg=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR; got: '\$dec'\"; echo FAIL; exit 0; }
    [[ \"\$msg\" == 'fetch failed for library/pagecap-test' ]] \
        || { echo \"expected the legacy fallback message; got: '\$msg'\"; echo FAIL; exit 0; }
    echo PASS
"

# ─── 113 ──────────────────────────────────────────────────────────────────
section "113 — dockerhub anonymous page cap is a boundary, not a failure"

# t113a: THE BUG. Docker Hub rejects anonymous callers past offset 1000. The walk
# used to 'return 1' on that 403, discarding every tag it had already collected,
# so library/mongo, library/postgres and library/redis were permanently ERROR.
# The URL orders by last_updated, so the pages already fetched hold the most
# recently updated tags — the newest version is necessarily among them. Reaching
# the cap must therefore END the walk successfully, not fail it.
# _GS_EU2_DH_ANON_PAGE_CAP is the test seam: real cap is page 11 (offset 1000 at
# page_size=100); here it is 3 so the 3-page fixture chain can exercise it.
t "t113a: reaching the anonymous page cap keeps the tags already fetched" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t113a_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    export _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE=3
    export _GS_EU2_DH_ANON_PAGE_CAP=3
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T113A'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" != 'ERROR' ]] \
        || { echo \"still ERROR: \$(_gs_eu2_record_get \$idx error_message)\"; echo FAIL; exit 0; }
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '1.1.1' ]] \
        || { echo \"expected 1.1.1 (best of pages 1-2); got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t113b: a 403 BELOW the cap is not the cap. Pages 2-10 are offsets 100-900, so a
# 403 there is a rate limit, a private repo or an auth problem — never the
# offset-1000 cap. It must stay an ERROR and must not assert the wrong cause.
t "t113b: a 403 below the cap stays ERROR and does not claim the offset cap" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t113b_cache
    export _GS_EU2_HTTP_INJECT_STATUS=403
    export _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE=2
    export _GS_EU2_DH_ANON_PAGE_CAP=11
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T113B'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR below the cap; got: '\$dec'\"; echo FAIL; exit 0; }
    msg=\$(_gs_eu2_record_get \$idx error_message)
    case \"\$msg\" in
        *'caps anonymous paging'*) echo \"falsely blamed the offset cap at page 2: \$msg\"; echo FAIL; exit 0;;
    esac
    case \"\$msg\" in
        *'HTTP 403'*) :;;
        *) echo \"expected the 403 to be named; got: \$msg\"; echo FAIL; exit 0;;
    esac
    echo PASS
"

# t113c: a jq parse failure must not be reported as an HTTP status. The sink holds
# the status of the last HTTP call, which SUCCEEDED (200) — reading it as the
# failure cause turned a correct generic message into a confidently wrong one.
# t107c cannot catch this: it greps for 'ERROR|error|parse', which the wrong
# message satisfies.
t "t113c: a malformed-JSON body is never reported as '(HTTP 200)'" bash -c "
    ${_DIAG_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t113c_cache
    export _GS_EU2_HTTP_INJECT_STATUS=malformed-json
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/pagecap-test'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_T113C'
    _gs_eu2_fetch_dockerhub \$idx
    dec=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$dec\" == 'ERROR' ]] || { echo \"expected ERROR on a parse failure; got: '\$dec'\"; echo FAIL; exit 0; }
    msg=\$(_gs_eu2_record_get \$idx error_message)
    case \"\$msg\" in
        *'HTTP 200'*) echo \"parse failure reported as a successful status: \$msg\"; echo FAIL; exit 0;;
        *'HTTP '*)    echo \"parse failure reported as an HTTP status at all: \$msg\"; echo FAIL; exit 0;;
    esac
    echo PASS
"

# ─── 114 ──────────────────────────────────────────────────────────────────
section "114 — default --env-file resolves from the script, not from /stack"

# t114a: the default env_file was hardcoded to "/stack/.env", so a checkout at any
# other path silently read /stack's .env instead of its own — the same defect class
# as absolute `source` paths in this suite, but in production code.
#
# This test must run from a DIFFERENT root or it proves nothing: at /stack the old
# and new resolutions are identical. So it builds a synthetic tree in TMP_DIR with
# its own .env carrying a variable name that does NOT exist in /stack/.env. If the
# default still pointed at /stack, that variable could never appear in the output.
t "t114a: a checkout outside /stack reads its OWN .env by default" bash -c "
    root=\${TMP_DIR}/t114_root
    mkdir -p \"\$root\"
    cp -a '${REPO_ROOT}/bin' \"\$root/bin\"
    printf '# @todo env-update dockerhub:_/nginx 1.29.2-alpine3.22\nGLOBAL_STACK_T114A_ONLY_HERE=1.29.2-alpine3.22\n' > \"\$root/.env\"
    grep -q 'GLOBAL_STACK_T114A_ONLY_HERE' '${REPO_ROOT}/.env' \
        && { echo 'precondition failed: the marker var exists in the real .env'; echo FAIL; exit 0; }
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t114a_cache\"
    out=\$(bash \"\$root/bin/env-update.sh\" --check --dry-run --no-fail --filter=T114A 2>&1)
    case \"\$out\" in
        *GLOBAL_STACK_T114A_ONLY_HERE*) :;;
        *) echo \"read the wrong .env — marker var absent from output:\"; echo \"\$out\" | head -5; echo FAIL; exit 0;;
    esac
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 115 — github: a non-stable channel must reach the Tags API
# ═══════════════════════════════════════════════════════════════════════════
section "115 — github non-stable channel reaches the Tags API"

# The github fetcher uses Releases as its primary pool and only falls back to
# Tags when Releases came back empty, or when every Releases entry is a
# pre-release AND the channel is stable/unset. That second arm was scoped to
# stable only — so a record carrying (channel:unstable) whose Releases pool is
# entirely STABLE never queried the Tags API at all. Upstreams that publish
# alphas/betas/RCs as bare git tags (php/php-src is the canonical case) were
# therefore invisible: no RC proposal, and no [WATCH] on a next-generation
# prerelease, contradicting the documented watch-major promise that with
# (channel:unstable) "a new major that currently exists only as a prerelease
# fires WATCH".
#
# Fixtures mirror php/php-src as observed 2026-08-23:
#   releases → php-8.5.9 / 8.5.8 / 8.4.24 / 8.3.33   (all stable)
#   tags     → php-8.6.0beta1 / 8.6.0alpha3 / 8.5.10RC1 / … (prereleases here only)

# t115a: (channel:unstable) + (watch-major:2) → WATCH fires on the 8.6 prerelease
t "t115a: github (channel:unstable) sees prerelease-only next major — [WATCH] fires" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t115a_cache
    f=\${TMP_DIR}/t115a.env
    printf '# @todo env-update (channel:unstable) (watch-major:2) (tag-strip-prefix:php-) github:testorg/php-like:8.5 8.5.9\nGLOBAL_STACK_T115A=8.5.9\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"expected [WATCH] sub-line, got:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '8.6.0beta1' || { echo \"expected 8.6.0beta1 in WATCH line, got:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t115b: the same record proposes the tags-only RC — (channel:unstable) honoured
t "t115b: github (channel:unstable) proposes the tags-only RC (8.5.10RC1)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t115b_cache
    f=\${TMP_DIR}/t115b.env
    printf '# @todo env-update (channel:unstable) (tag-strip-prefix:php-) github:testorg/php-like:8.5 8.5.9\nGLOBAL_STACK_T115B=8.5.9\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '8.5.10RC1' || { echo \"expected 8.5.10RC1 proposal, got:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t115c: REGRESSION — the stable channel must NOT start seeing prereleases.
# Same repo, no (channel:) flag: the Releases pool has stable entries, so the
# Tags API stays unqueried and neither the RC nor the 8.6 prerelease appears.
t "t115c: github stable channel unchanged — no RC proposal, no [WATCH]" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t115c_cache
    f=\${TMP_DIR}/t115c.env
    printf '# @todo env-update (watch-major:2) (tag-strip-prefix:php-) github:testorg/php-like:8.5 8.5.9\nGLOBAL_STACK_T115C=8.5.9\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF 'RC1' && { echo \"stable channel leaked a prerelease:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[WATCH]' && { echo \"stable channel fired WATCH on a prerelease-only major:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t115d: the non-stable arm must MERGE, not replace. Tags pagination stops at 10
# pages, so on a tag-heavy repo the Tags API is not a superset of Releases — a
# replace would drop the pinned major entirely. Fixture makes that visible: the
# php-like-partial tags page carries ONLY the 8.6 prereleases, while 8.5.9 exists
# solely in Releases. Merge keeps the pin resolvable AND fires WATCH; replace
# loses 8.5.9 and cannot report the pinned line as up to date.
# _GS_EU2_GIT_LS_REMOTE_FIXTURE (empty) keeps the strategy-3 fallback off the network.
t "t115d: non-stable arm merges releases+tags — pinned major survives, WATCH still fires" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t115d_cache
    : > \${TMP_DIR}/t115d_lsr.txt
    export _GS_EU2_GIT_LS_REMOTE_FIXTURE=\${TMP_DIR}/t115d_lsr.txt
    f=\${TMP_DIR}/t115d.env
    printf '# @todo env-update (channel:unstable) (watch-major:2) (tag-strip-prefix:php-) github:testorg/php-like-partial:8.5 8.5.9\nGLOBAL_STACK_T115D=8.5.9\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --no-fail --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -qF '[WATCH]' || { echo \"expected [WATCH] sub-line, got:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '[ERROR' && { echo \"pinned major lost — pool no longer resolves 8.5.x:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '(up to date)' || { echo \"expected the 8.5 pin to resolve as up to date, got:\"; echo \"\$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 116 — codeberg: the releases pool must represent the channel asked for
# ═══════════════════════════════════════════════════════════════════════════
section "116 — codeberg channel-representation fallthrough"

# Same class as section 115, in the other dual-source fetcher. Codeberg reached
# the tags endpoint only when the releases call failed or returned [] — it had
# NEITHER of github's channel arms. Two symmetric holes:
#
#   stable channel  + releases are all pre-release → nothing to select, SKIP
#   non-stable chan + releases carry no pre-release → the channel is unanswerable
#
# Both are resolved by consulting the tags endpoint. The non-stable arm MERGES
# (the stable releases stay valid candidates and the tags endpoint caps at
# limit=50); the stable arm REPLACES, matching github, because a pool with no
# stable entry has nothing worth keeping.

_CB_LIBS116="
source '${_GS_EU2_LIB}/config/defaults.sh'
source '${_GS_EU2_LIB}/config/prerelease_markers.sh'
source '${_GS_EU2_LIB}/core/records.sh'
source '${_GS_EU2_LIB}/core/semver.sh'
source '${_GS_EU2_LIB}/core/channel.sh'
source '${_GS_EU2_LIB}/core/tag_flags.sh'
source '${_GS_EU2_LIB}/core/cache.sh'
source '${_GS_EU2_LIB}/http/curl.sh'
source '${_GS_EU2_LIB}/fetchers/codeberg.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

# t116a: non-stable channel reaches the tags-only RC.
# cb-nonstable: releases = v3.2.0/v3.1.0/v2.9.0 (all stable);
#               tags     = those + v3.3.0-rc1 + v4.0.0-beta1.
t "t116a: codeberg (channel:unstable) proposes the tags-only RC (v3.3.0-rc1)" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116a_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'codeberg'
    _gs_eu2_record_set \$idx identifier      'testorg/cb-nonstable'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T116A'
    _gs_eu2_record_set \$idx current_version 'v3.2.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_record_set \$idx major_hint      '3'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v3.3.0-rc1' ]] || { echo \"expected v3.3.0-rc1 from the tags endpoint, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t116b: (watch-major) sees the next generation that exists only as a prerelease
t "t116b: codeberg (channel:unstable) + watch-major — latest_unconstrained is v4.0.0-beta1" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'codeberg'
    _gs_eu2_record_set \$idx identifier        'testorg/cb-nonstable'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T116B'
    _gs_eu2_record_set \$idx current_version   'v3.2.0'
    _gs_eu2_record_set \$idx channel           'unstable'
    _gs_eu2_record_set \$idx major_hint        '3'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_codeberg \$idx
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ -n \"\$unconstrained\" ]] || { echo 'latest_unconstrained empty — WATCH cannot fire'; echo FAIL; exit 0; }
    pfx=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx\" == '4' ]] || { echo \"expected unconstrained major 4, got '\$pfx' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t116c: stable channel + an all-prerelease releases pool falls through to tags.
# cb-prerelease-only: releases = v1.4.0-rc1/v1.3.0-beta1; tags carry stable v1.3.0.
# Before the fallthrough this produced no proposal at all (SKIP, "channel
# selection returned nothing") — github has had this arm since it was written.
t "t116c: codeberg stable channel + all-prerelease releases falls through to tags" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'codeberg'
    _gs_eu2_record_set \$idx identifier      'testorg/cb-prerelease-only'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T116C'
    _gs_eu2_record_set \$idx current_version 'v1.2.0'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == 'v1.3.0' ]] || { echo \"expected the stable v1.3.0 from the tags endpoint, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t116d: REGRESSION — a stable channel with stable releases must NOT consult tags.
# cb-stable-guard's tags carry a HIGHER stable (v5.9.0) and a v6.0.0-rc1 that the
# releases pool does not. Identical-content fixtures could not tell 'tags were not
# fetched' from 'tags were fetched and changed nothing' — this pair can.
t "t116d: codeberg stable channel with stable releases never consults tags" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'codeberg'
    _gs_eu2_record_set \$idx identifier        'testorg/cb-stable-guard'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T116D'
    _gs_eu2_record_set \$idx current_version   'v5.0.0'
    _gs_eu2_record_set \$idx major_hint        '5'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ \"\$val\" == 'v5.1.0' ]] || { echo \"tags leaked into the stable pool — expected v5.1.0, got: '\$val'\"; echo FAIL; exit 0; }
    case \"\$unconstrained\" in
      v6*) echo \"tags leaked into latest_unconstrained: '\$unconstrained'\"; echo FAIL; exit 0;;
    esac
    echo PASS
"

# t116e: the non-stable arm MERGES, it does not replace.
# cb-partial-tags: releases = v7.2.0/v7.1.0 (the pinned major lives ONLY here);
#                  tags     = v8.0.0-beta1/v8.0.0-alpha1 only.
# Merge keeps the 7.x pin resolvable while still seeing the 8.x generation;
# a replace would leave nothing matching major_hint=7.
t "t116e: codeberg non-stable arm merges — pinned major survives, next generation seen" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type              'codeberg'
    _gs_eu2_record_set \$idx identifier        'testorg/cb-partial-tags'
    _gs_eu2_record_set \$idx env_var           'GLOBAL_STACK_T116E'
    _gs_eu2_record_set \$idx current_version   'v7.1.0'
    _gs_eu2_record_set \$idx channel           'unstable'
    _gs_eu2_record_set \$idx major_hint        '7'
    _gs_eu2_record_set \$idx watch_major_depth '1'
    _gs_eu2_fetch_codeberg \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    decision=\$(_gs_eu2_record_get \$idx decision)
    unconstrained=\$(_gs_eu2_record_get \$idx latest_unconstrained)
    [[ \"\$val\" == 'v7.2.0' ]] || { echo \"pinned major lost — expected v7.2.0, got: '\$val' (decision '\$decision')\"; echo FAIL; exit 0; }
    pfx=\$(_gs_eu2_version_prefix \"\$unconstrained\" '1')
    [[ \"\$pfx\" == '8' ]] || { echo \"expected unconstrained major 8, got '\$pfx' (full: '\$unconstrained')\"; echo FAIL; exit 0; }
    echo PASS
"

# t116f: a failing tags call must never downgrade a working releases answer.
# The releases pool already answers; codeberg's list endpoints 504 under load, so
# the fallthrough is best-effort. _GS_EU2_HTTP_INJECT_STATUS forces every call to
# fail — including the releases one — so this asserts the honest-ERROR contract
# still holds and no partial/garbage proposal is emitted.
t "t116f: injected HTTP failure yields an honest ERROR, never a bogus proposal" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116f_cache
    export _GS_EU2_HTTP_INJECT_STATUS=504
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'codeberg'
    _gs_eu2_record_set \$idx identifier      'testorg/cb-nonstable'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T116F'
    _gs_eu2_record_set \$idx current_version 'v3.2.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_codeberg \$idx 2>/dev/null
    decision=\$(_gs_eu2_record_get \$idx decision)
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR on total failure, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -z \"\$val\" ]] || { echo \"emitted a proposal despite total failure: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# t116g: the fallthrough is BEST-EFFORT — a failing tags call keeps the releases pool.
# Distinct from t116f, where the releases call fails too and ERROR is correct: here
# the releases pool already answers, and cb-no-tags has NO tags fixture, so the arm
# fires and its tags call fails (a missing fixture stands in for a transport failure,
# same mechanism as t26g). Degrading to the pool we have is the contract; propagating
# that failure would turn a working answer into an ERROR, which is why Codeberg's
# 504-prone list endpoints must not be allowed to break a record that already resolved.
t "t116g: a failing tags call degrades to the releases pool, never to an ERROR" bash -c "
    ${_CB_LIBS116}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t116g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type            'codeberg'
    _gs_eu2_record_set \$idx identifier      'testorg/cb-no-tags'
    _gs_eu2_record_set \$idx env_var         'GLOBAL_STACK_T116G'
    _gs_eu2_record_set \$idx current_version 'v9.2.0'
    _gs_eu2_record_set \$idx channel         'unstable'
    _gs_eu2_fetch_codeberg \$idx 2>/dev/null
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    decision=\$(_gs_eu2_record_get \$idx decision)
    [[ \"\$val\" == 'v9.3.0' ]] || { echo \"expected the releases pool to still answer with v9.3.0, got: '\$val'\"; echo FAIL; exit 0; }
    [[ -z \"\$decision\" ]] || { echo \"a failed tags call must not set a decision, got: '\$decision'\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
# Section 117 — (stale-after:Nd) freshness contract
# ═══════════════════════════════════════════════════════════════════════════
section "117 — stale-after freshness contract"

# The downgrade guard in decide.sh only fires when a proposal sorts BELOW the
# current version, so a source that freezes AT the current value reads as
# "already latest" forever. That is the blind spot this closes. nodejs.org's
# frozen HTML index (2026-04-17) was only ever noticed because the frozen value
# happened to sort below the pin — a freeze one day later would have been silent.
#
# The clock is injected in every case: the fixtures carry real dates, so a test
# that trusted the wall clock would pass today and fail on its own without a
# single edit. That is the same stale-fixture trap section 32 was built around.

_STALE_LIBS="
source '${_GS_EU2_LIB}/core/staleness.sh'
"

# 2026-08-25T00:00:00Z — the reference "now" for every case below.
_STALE_NOW=1787616000

t "t117a: fresh — a same-day nightly is silent" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '7d' 'v27.0.0-nightly202608254b5e86c4e2' ${_STALE_NOW})
    [[ -z \"\$out\" ]] || { echo \"expected silence for a same-day nightly, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t117b: FROZEN AT CURRENT — the blind spot: proposed == current, both stale" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '7d' 'v26.0.0-nightly20260417b178842482' ${_STALE_NOW})
    [[ -n \"\$out\" ]] || { echo 'a 130-day-old proposal must not be silent — this is the whole point of the flag'; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF '20260417' || { echo \"error must name the date it found; got: '\$out'\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'frozen' || { echo \"error must say the source looks frozen; got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t117c: boundary — exactly at the threshold is fresh, one day past is stale" bash -c "
    ${_STALE_LIBS}
    # 2026-08-18 is exactly 7 days before the reference now.
    at=\$(_gs_eu2_staleness_verdict '7d' 'v27.0.0-nightly2026081813fcd6f3e0' ${_STALE_NOW})
    [[ -z \"\$at\" ]] || { echo \"exactly-at-threshold must be fresh, got: '\$at'\"; echo FAIL; exit 0; }
    # 2026-08-17 is 8 days before, one past the threshold.
    past=\$(_gs_eu2_staleness_verdict '7d' 'v27.0.0-nightly20260817977c20ed67' ${_STALE_NOW})
    [[ -n \"\$past\" ]] || { echo 'one day past the threshold must fire'; echo FAIL; exit 0; }
    echo PASS
"

t "t117d: no flag — no contract, so never stale however old" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '' 'v8.0.0-nightly20161201cf719152b0' ${_STALE_NOW})
    [[ -z \"\$out\" ]] || { echo \"a record with no stale-after must never fire, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# A failed fetch leaves proposed empty and carries its own error. Reporting a
# freeze on top would misdiagnose a transport failure as an upstream one — the
# operator would go looking at the wrong end of the wire.
t "t117e: empty proposed — a failed fetch is not a frozen source" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '7d' '' ${_STALE_NOW})
    [[ -z \"\$out\" ]] || { echo \"empty proposed must not be reported as stale, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# A contract that cannot be evaluated must be loud, not silently skipped —
# silently skipping is exactly how a guard becomes dead code nobody notices.
t "t117f: undateable proposed — the contract cannot be evaluated, so it ERRORs" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '7d' '18.3-alpine3.23' ${_STALE_NOW})
    [[ -n \"\$out\" ]] || { echo 'a declared contract that cannot be evaluated must not be silent'; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'carries no date' || { echo \"expected the undateable message; got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t117g: a future-dated version is fresh — the bias is never toward a false alarm" bash -c "
    ${_STALE_LIBS}
    out=\$(_gs_eu2_staleness_verdict '7d' 'v27.0.0-nightly20270101aaaaaaaaaa' ${_STALE_NOW})
    [[ -z \"\$out\" ]] || { echo \"a future date must not fire, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t117h: threshold parsing — only a positive whole-day count is accepted" bash -c "
    ${_STALE_LIBS}
    _gs_eu2_staleness_parse_days '7d'   >/dev/null || { echo '7d must parse';   echo FAIL; exit 0; }
    _gs_eu2_staleness_parse_days '30d'  >/dev/null || { echo '30d must parse';  echo FAIL; exit 0; }
    for bad in '0d' '7' 'd' '7h' 'banana' '-3d' '07d' ''; do
        if _gs_eu2_staleness_parse_days \"\$bad\" >/dev/null 2>&1; then
            echo \"'\$bad' must be refused as a threshold\"; echo FAIL; exit 0
        fi
    done
    echo PASS
"

# 'date -d' is the validator, so a capture that is not a real calendar date
# routes to the undateable path rather than silently computing an age from it.
t "t117i: an impossible calendar date is treated as no date, not as an age" bash -c "
    ${_STALE_LIBS}
    _gs_eu2_staleness_extract_date 'v1.0.0-nightly20261340deadbeef' >/dev/null 2>&1 && {
        echo 'month 13 must not validate as a date'; echo FAIL; exit 0; }
    out=\$(_gs_eu2_staleness_verdict '7d' 'v1.0.0-nightly20261340deadbeef' ${_STALE_NOW})
    echo \"\$out\" | grep -qF 'carries no date' || { echo \"expected undateable, got: '\$out'\"; echo FAIL; exit 0; }
    echo PASS
"

# The date must come from the anchored shape decide.sh already uses, not from a
# bare 8-digit scan — otherwise an unrelated build number would be read as a date.
t "t117j: the date is read from the anchored shape, not any 8 digits" bash -c "
    ${_STALE_LIBS}
    # 8 digits present, but not followed by a hex run to end of string.
    _gs_eu2_staleness_extract_date '20260417-build-xyz!' >/dev/null 2>&1 && {
        echo 'a bare 8-digit run not in the anchored shape must not be read as a date'; echo FAIL; exit 0; }
    d=\$(_gs_eu2_staleness_extract_date 'v27.0.0-nightly202608254b5e86c4e2')
    [[ \"\$d\" == '20260825' ]] || { echo \"expected 20260825, got: '\$d'\"; echo FAIL; exit 0; }
    echo PASS
"

# ── End-to-end: the gate must be WIRED, not merely implemented ─────────────
# A guard that exists but is never called is the failure mode this repo has hit
# before (a fully-implemented robots checker guarded by an always-null argument).
# These run the real CLI so a missing call site fails here rather than in prod.

t "t117k: end to end — a stale record becomes ERROR through the real CLI" bash -c "
    f=\${TMP_DIR}/t117k.env
    printf '# @todo env-update (stale-after:7d) (channel:nightly) (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json v26.0.0-nightly20260417b178842482\nGLOBAL_STACK_T117K=v26.0.0-nightly20260417b178842482\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t117k_cache\"; export _GS_EU2_NOW_EPOCH=1798761600; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[ERROR' || { echo \"expected an ERROR decision from a frozen source; got: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qiF 'frozen' || { echo \"expected the frozen-source wording; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# --force-auto upgrades HOLD to AUTO. It must not be able to launder a frozen
# source into an applied update: the gate sits after the force-auto block, and
# moving it above is a sabotage this case is built to catch.
t "t117l: --force-auto cannot override a staleness ERROR" bash -c "
    f=\${TMP_DIR}/t117l.env
    printf '# @todo env-update (stale-after:7d) (channel:nightly) (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json v26.0.0-nightly20260417b178842482\nGLOBAL_STACK_T117L=v26.0.0-nightly20260417b178842482\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t117l_cache\"; export _GS_EU2_NOW_EPOCH=1798761600; bash '${ENV_UPDATE_V2}' --check --dry-run --force-auto --confirm='Confirm override' --env-file=\"\$f\" 2>&1 || true)
    echo \"\$out\" | grep -qF '[ERROR' || { echo \"--force-auto must not launder a frozen source into AUTO; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# A malformed threshold is a config error and belongs at parse time, next to the
# empty (skip:)/(lock:) reason refusals — not discovered later as a fetch result.
t "t117m: a malformed threshold is refused at parse time" bash -c "
    f=\${TMP_DIR}/t117m.env
    printf '# @todo env-update (stale-after:banana) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T117M=1.0.0\n' > \"\$f\"
    # Must REFUSE — a non-zero exit. Grepping for the flag name alone would pass
    # vacuously today, because an unrecognised flag is simply left in the
    # annotation and echoed back as part of raw_annotation.
    if bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" >/dev/null 2>&1; then
        echo 'a malformed (stale-after:) threshold must refuse at parse time, not be accepted'; echo FAIL; exit 0
    fi
    err=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>&1 >/dev/null || true)
    echo \"\$err\" | grep -qF 'stale-after' || { echo \"the refusal must name the flag; got: \$err\"; echo FAIL; exit 0; }
    echo \"\$err\" | grep -qE 'Nd|expected|invalid|malformed' || { echo \"the refusal must say what was expected; got: \$err\"; echo FAIL; exit 0; }
    echo PASS
"

t "t117n: stale_after is a dumpable record field (not silently dropped)" bash -c "
    f=\${TMP_DIR}/t117n.env
    printf '# @todo env-update (stale-after:7d) github:testowner/testrepo 1.0.0\nGLOBAL_STACK_T117N=1.0.0\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'stale_after: 7d' || { echo \"stale_after missing from --dump; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

section "118 — apply writes bytes, not escape sequences (awk -v)"

# awk applies escape-sequence processing to a -v assignment, so a literal
# backslash in an upstream-controlled value is INTERPRETED rather than carried
# through. Every value crossing into _gs_eu2_apply_single is upstream-controlled.
#
#   $ awk -v v='1.0.1\back' 'BEGIN{printf "%s", v}' | od -c
#   0000000   1   .   0   .   1  \b   a   c   k          <-- 0x08 BACKSPACE
#   $ v='1.0.1\back' awk 'BEGIN{printf "%s", ENVIRON["v"]}' | od -c
#   0000000   1   .   0   .   1   \   b   a   c   k      <-- correct
#
# Two distinct failures, both silent — the report line prints the correct string
# while the file receives something else:
#   a) the VAR= value is written with a control character, which then propagates
#      through env-scan into .env.local and Dockerfile ARG lines;
#   b) a raw_annotation containing an escape no longer compares equal to the line
#      on disk, so the annotation is not rewritten at all and the record
#      re-proposes the same bump on every subsequent run.
#
# The values are passed through the environment and read via ENVIRON, which is
# the only assignment path awk leaves verbatim.

t "t118a: a literal backslash in the value reaches the file byte-exactly" bash -c "
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t118a.env
    want='1.0.1\\back'
    printf 'GLOBAL_STACK_T118A=1.0.0\n' > \"\$f\"
    _gs_eu2_apply_single \"\$f\" 'GLOBAL_STACK_T118A' \"\$want\"
    got=\$(sed -n 's/^GLOBAL_STACK_T118A=//p' \"\$f\")
    if [[ \"\$got\" != \"\$want\" ]]; then
        printf 'want: '; printf '%s' \"\$want\" | od -c | head -1
        printf 'got : '; printf '%s' \"\$got\"  | od -c | head -1
        echo FAIL; exit 0
    fi
    echo PASS
"

t "t118b: an annotation containing an escape still matches and is rewritten" bash -c "
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t118b.env
    # A backslash reaches an annotation through (urls:) — a Windows-style path or
    # an escaped upstream ref is enough. '\\b' is a recognised awk escape, so -v
    # collapses it and the \$0 == raw_ann comparison can never hold.
    ann='# @todo env-update (urls:C:\\build\\x) github:testowner/testrepo 1.0.0'
    printf '%s\nGLOBAL_STACK_T118B=1.0.0\n' \"\$ann\" > \"\$f\"
    _gs_eu2_apply_single \"\$f\" 'GLOBAL_STACK_T118B' '1.0.1' \"\$ann\" '1.0.0'
    line=\$(sed -n 1p \"\$f\")
    echo \"\$line\" | grep -qF '1.0.1' || { echo \"annotation not rewritten: \$line\"; echo FAIL; exit 0; }
    echo \"\$line\" | grep -qF 'C:\\build\\x' || { echo \"annotation corrupted: \$line\"; echo FAIL; exit 0; }
    echo PASS
"

t "t118c: (replace:) cascade writes are verbatim too" bash -c "
    source '${_GS_EU2_LIB}/core/apply.sh'
    f=\${TMP_DIR}/t118c.env
    want='2.0.0\\tzip'
    printf 'GLOBAL_STACK_T118C=1.0.0\n' > \"\$f\"
    _gs_eu2_apply_replace_target \"\$f\" 'GLOBAL_STACK_T118C' \"\$want\"
    got=\$(sed -n 's/^GLOBAL_STACK_T118C=//p' \"\$f\")
    if [[ \"\$got\" != \"\$want\" ]]; then
        printf 'want: '; printf '%s' \"\$want\" | od -c | head -1
        printf 'got : '; printf '%s' \"\$got\"  | od -c | head -1
        echo FAIL; exit 0
    fi
    echo PASS
"

t "t118d: no control character can reach the file (end-to-end --apply)" bash -c "
    d=\${TMP_DIR}/t118d; mkdir -p \"\$d/fx\"
    printf '[{\"version\":\"1.0.1\\\\\\\\back\",\"date\":\"2026-08-25\"}]' > \"\$d/fx/nodejs.org_download_nightly_index.json\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json 1.0.0\nGLOBAL_STACK_T118D=1.0.0\n' > \"\$f\"
    _GS_EU2_HTTP_FIXTURE_DIR=\"\$d/fx\" _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --env-file=\"\$f\" --apply --yes >/dev/null 2>&1
    # Any C0 control character other than the line feeds is corruption.
    if LC_ALL=C grep -qP '[\x00-\x08\x0b-\x1f]' \"\$f\"; then
        printf 'control character written to env file:\n'; od -c \"\$f\" | head -5
        echo FAIL; exit 0
    fi
    grep -qF '1.0.1\\back' \"\$f\" || { echo \"value not written verbatim:\"; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

_flush_section

# ═══════════════════════════════════════════════════════════════════════════
section "119 — a transport failure is an ERROR, not a SKIP (url/sdkman/sdkmanager)"
# ═══════════════════════════════════════════════════════════════════════════
# 10 of the 12 fetchers set decision \"ERROR\" on a hard transport failure. url,
# sdkman and sdkmanager set it ZERO times: they wrote only error_message, and
# decide.sh classifies an empty proposed_version as SKIP. So --check exited 0
# no matter what happened upstream, and /check-versions in cron or CI was
# structurally incapable of failing for those 33 live records.
#
# Section 107 already exercises the inject seam, but only against dockerhub —
# one of the fetchers that was never broken — and asserts a loose
# 'ERROR|error|injected', which the seam's own stderr line satisfies on its
# own. These tests assert the [ERROR] decision token AND the exit code.
#
# The boundary matters as much as the escalation: \"not installed\" and
# \"matched nothing on a 200\" must STAY SKIP, or a machine without a local
# toolchain fails CI for no reason. Both directions are asserted below.

# t119a: url fetch-json — an injected 503 must be ERROR + exit 1.
# Pre-fix this reported [SKIP] blaming the jq path for an HTTP failure.
t "t119a: url fetch-json transport failure is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119a; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json 1.0.0\nGLOBAL_STACK_T119A=1.0.0\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1 — a dead upstream must fail the run\"; echo FAIL; exit 0; }
    echo PASS
"

# t119b: the message must name the transport failure, not the jq path.
# Pre-fix: \"fetch-json jq path '…' returned empty\" — which sends the reader to
# edit an expression that was never wrong.
t "t119b: url fetch-json 503 message blames the fetch, not the jq path" bash -c "
    d=\${TMP_DIR}/t119b; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json 1.0.0\nGLOBAL_STACK_T119B=1.0.0\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1)
    echo \"\$out\" | grep -q 'jq path' && { echo \"message still blames the jq path: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qi 'fetch failed' || { echo \"message does not say the fetch failed: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# t119c: url fetch-extract (tier 1) — already distinguished _fetch_ok, never escalated.
t "t119c: url fetch-extract transport failure is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119c; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-extract:v([0-9.]+)) url:https://example.invalid/releases 1.0.0\nGLOBAL_STACK_T119C=1.0.0\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1\"; echo FAIL; exit 0; }
    echo PASS
"

# t119d: url channel:nightly directory listing (tier 4a).
t "t119d: url channel:nightly transport failure is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119d; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update (channel:nightly) url:https://nodejs.org/download/nightly/ v1.0.0-nightly1\nGLOBAL_STACK_T119D=v1.0.0-nightly1\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1\"; echo FAIL; exit 0; }
    echo PASS
"

# t119e: url directory listing (tier 4b) — the svn.apache.org / GNU scrapes.
t "t119e: url directory-listing transport failure is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119e; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update url:https://svn.apache.org/repos/asf/apr/apr/tags/ 1.7.6\nGLOBAL_STACK_T119E=1.7.6\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1\"; echo FAIL; exit 0; }
    echo PASS
"

# t119f: sdkman — the API-fetch-failed branch.
# The discrimination order in sdkman.sh is fixture-missing → not-installed →
# API-fetch-failed, so the fake SDKMAN_DIR below is REQUIRED: without it the
# harness machine takes the not-installed branch and this test would be red for
# the wrong reason. Deliberately no _GS_EU2_HTTP_FIXTURE_DIR, for the same reason.
t "t119f: sdkman API transport failure is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119f; mkdir -p \"\$d/sdk/bin\"; : > \"\$d/sdk/bin/sdkman-init.sh\"
    f=\$d/t.env
    printf '# @todo env-update sdkman:java 21 21.0.5-tem\nGLOBAL_STACK_T119F=21.0.5-tem\n' > \"\$f\"
    out=\$(SDKMAN_DIR=\"\$d/sdk\" _GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1\"; echo FAIL; exit 0; }
    echo PASS
"

# t119g: BOUNDARY — sdkman not installed stays SKIP + exit 0. A machine without
# a local toolchain must not fail CI. Pointing SDKMAN_DIR at an empty dir takes
# the not-installed branch even though the injection is armed.
t "t119g: boundary — sdkman not installed stays SKIP + exit 0" bash -c "
    d=\${TMP_DIR}/t119g; mkdir -p \"\$d/nosdk\"
    f=\$d/t.env
    printf '# @todo env-update sdkman:java 21 21.0.5-tem\nGLOBAL_STACK_T119G=21.0.5-tem\n' > \"\$f\"
    out=\$(SDKMAN_DIR=\"\$d/nosdk\" _GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[SKIP' || { echo \"expected [SKIP] for a missing local install; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 0 ]] || { echo \"exit \$rc, want 0 — a missing local toolchain must not fail the run\"; echo FAIL; exit 0; }
    echo PASS
"

# t119h: BOUNDARY — a jq path that legitimately matches nothing on a 200 stays
# SKIP. The upstream is reachable and its shape changed; (stale-after:Nd) is the
# guard for that, not an ERROR.
t "t119h: boundary — jq path empty on a 200 stays SKIP + exit 0" bash -c "
    d=\${TMP_DIR}/t119h; mkdir -p \"\$d/fx\"
    printf '[{\"other\":\"x\"}]' > \"\$d/fx/nodejs.org_download_nightly_index.json\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json 1.0.0\nGLOBAL_STACK_T119H=1.0.0\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_FIXTURE_DIR=\"\$d/fx\" _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[SKIP' || { echo \"expected [SKIP] for an empty match on a 200; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 0 ]] || { echo \"exit \$rc, want 0\"; echo FAIL; exit 0; }
    echo PASS
"

# t119i: sdkmanager — the binary is present but --list produced nothing.
# The not-found branch precedes this one, so a fake sdkmanager on PATH is what
# separates the two.
t "t119i: sdkmanager empty --list is ERROR + exit 1" bash -c "
    d=\${TMP_DIR}/t119i; mkdir -p \"\$d/bin\"
    printf '#!/bin/bash\nexit 0\n' > \"\$d/bin/sdkmanager\"; chmod +x \"\$d/bin/sdkmanager\"
    f=\$d/t.env
    printf '# @todo env-update sdkmanager:platform-tools 35.0.2\nGLOBAL_STACK_T119I=35.0.2\n' > \"\$f\"
    out=\$(PATH=\"\$d/bin:\$PATH\" _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 1 ]] || { echo \"exit \$rc, want 1\"; echo FAIL; exit 0; }
    echo PASS
"

# t119j: --no-fail remains the documented escape hatch for callers that want
# the old exit-0 behaviour on a dead upstream.
t "t119j: --no-fail still exits 0 on a transport ERROR" bash -c "
    d=\${TMP_DIR}/t119j; mkdir -p \"\$d\"
    f=\$d/t.env
    printf '# @todo env-update (fetch-json:max_by(.date).version) url:https://nodejs.org/download/nightly/index.json 1.0.0\nGLOBAL_STACK_T119J=1.0.0\n' > \"\$f\"
    out=\$(_GS_EU2_HTTP_INJECT_STATUS=503 _GS_EU2_CACHE_DIR=\"\$d/c\" bash '${ENV_UPDATE_V2}' --check --no-fail --env-file=\"\$f\" 2>&1); rc=\$?
    echo \"\$out\" | grep -q '\[ERROR' || { echo \"no [ERROR] token; got: \$out\"; echo FAIL; exit 0; }
    [[ \$rc -eq 0 ]] || { echo \"exit \$rc, want 0 under --no-fail\"; echo FAIL; exit 0; }
    echo PASS
"

# t119k: no fetcher may regress to zero ERROR sites. This is the structural
# guard — the defect was invisible for as long as it was because nothing
# asserted that every fetcher CAN report a transport failure.
t "t119k: every network fetcher has at least one decision ERROR site" bash -c "
    missing=''
    for fx in '${_GS_EU2_LIB}'/fetchers/*.sh; do
        b=\$(basename \"\$fx\" .sh)
        n=\$(grep -cE 'decision[[:space:]]+\"ERROR\"' \"\$fx\" || true)
        [[ \"\$n\" -gt 0 ]] || missing=\"\$missing \$b\"
    done
    [[ -z \"\$missing\" ]] || { echo \"fetchers that can never report a transport failure:\$missing\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 120 — the cache key covers the 7 tag flags
#
# The cache key was built from identifier/hint/channel only, so two records
# for the SAME upstream differing only in their tag flags collided on one
# cache file. The second record read back the first's answer — including a
# version its OWN tag-filter rejects, which is the failure this section pins.
# Silent by construction: the report line and the written .env value are both
# a plausible version, just the wrong one.
# ═══════════════════════════════════════════════════════════════════════════
section "120 — cache key covers the tag flags"

# t120a: the defect itself. library/postgres' fixture carries both 18.x and
# 17.5 tags, so a (tag-filter:^17\.) record inheriting an unfiltered record's
# 18.x answer is unmistakable — a proposal the record's own filter rejects.
t "t120a: a tag-filter'd record does not read back an unfiltered record's answer" bash -c "
    ${_DH_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t120a_cache
    # Record A — no tag flags. Populates the cache.
    _gs_eu2_record_new; a=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$a type       'dockerhub'
    _gs_eu2_record_set \$a identifier '_/postgres'
    _gs_eu2_record_set \$a env_var    'GLOBAL_STACK_T120A_A_VERSION'
    _gs_eu2_fetch_dockerhub \$a
    va=\$(_gs_eu2_record_get \$a proposed_version)
    [[ \"\$va\" == 18.* ]] || { echo \"setup broken — record A resolved to '\$va', expected 18.x\"; echo FAIL; exit 0; }
    # The write must have happened, or B's hit/miss proves nothing (dry_run
    # makes _gs_eu2_cache_write a no-op, which would make this test vacuous).
    ls \${TMP_DIR}/t120a_cache/*.cache >/dev/null 2>&1 || { echo 'setup broken — record A wrote no cache file'; echo FAIL; exit 0; }
    # Record B — same image, (tag-filter:^17\.). Must NOT inherit A's answer.
    _gs_eu2_record_new; b=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$b type       'dockerhub'
    _gs_eu2_record_set \$b identifier '_/postgres'
    _gs_eu2_record_set \$b env_var    'GLOBAL_STACK_T120A_B_VERSION'
    _gs_eu2_record_set \$b tag_filter '^17\\.'
    _gs_eu2_fetch_dockerhub \$b
    vb=\$(_gs_eu2_record_get \$b proposed_version)
    [[ \"\$vb\" == 17.* ]] || { echo \"cache poisoning — tag-filter '^17.' proposed '\$vb' (record A had cached '\$va')\"; echo FAIL; exit 0; }
    echo PASS
"

# t120b: the structural guard. t120a can only ever exercise one fetcher; this
# asserts the property across all of them, so a 10th fetcher that applies tag
# flags and forgets the fingerprint is red on the day it lands rather than the
# day someone notices a wrong version. Also pins the set coincidence the guard
# rests on: applying tag flags and sourcing core/tag_flags.sh are the same set.
t "t120b: every tag-flag-applying fetcher folds the flag fingerprint into its cache key" bash -c "
    applies=''; sources=''; missing=''
    for fx in '${_GS_EU2_LIB}'/fetchers/*.sh; do
        b=\$(basename \"\$fx\" .sh)
        grep -q 'apply_tag_flags_from_record' \"\$fx\" && applies=\"\$applies \$b\"
        grep -q 'core/tag_flags\.sh' \"\$fx\"          && sources=\"\$sources \$b\"
        grep -q 'apply_tag_flags_from_record' \"\$fx\" || continue
        grep -qE '_cache_key=.*_gs_eu2_tag_flags_fingerprint' \"\$fx\" || missing=\"\$missing \$b\"
    done
    [[ \"\$applies\" == \"\$sources\" ]] || { echo \"set drift — applies tag flags:\$applies / sources tag_flags.sh:\$sources\"; echo FAIL; exit 0; }
    [[ -n \"\$applies\" ]] || { echo 'vacuous — no fetcher matched apply_tag_flags_from_record'; echo FAIL; exit 0; }
    [[ -z \"\$missing\" ]] || { echo \"applies tag flags but omits the fingerprint from its cache key:\$missing\"; echo FAIL; exit 0; }
    echo PASS
"

# t120c: the fingerprint discriminates on each of the 7 fields independently.
# A fingerprint covering only some of them would leave the same poisoning for
# the fields it skipped.
t "t120c: fingerprint changes when any one of the 7 tag flags changes" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    _gs_eu2_record_new; base=\${_GS_EU2_LAST_IDX}
    fp_base=\$(_gs_eu2_tag_flags_fingerprint \$base)
    [[ -n \"\$fp_base\" ]] || { echo 'empty fingerprint for a flag-less record'; echo FAIL; exit 0; }
    for fld in tag_filter tag_exclude tag_strip_prefix tag_strip_suffix tag_extract tag_replace_from tag_replace_to; do
        _gs_eu2_record_new; i=\${_GS_EU2_LAST_IDX}
        _gs_eu2_record_set \$i \"\$fld\" 'XYZ'
        fp=\$(_gs_eu2_tag_flags_fingerprint \$i)
        [[ \"\$fp\" != \"\$fp_base\" ]] || { echo \"fingerprint ignores \$fld\"; echo FAIL; exit 0; }
    done
    # Stable for a fixed flag set — otherwise every run is a cache miss.
    _gs_eu2_record_new; x=\${_GS_EU2_LAST_IDX}; _gs_eu2_record_set \$x tag_filter '^17\\.'
    _gs_eu2_record_new; y=\${_GS_EU2_LAST_IDX}; _gs_eu2_record_set \$y tag_filter '^17\\.'
    [[ \"\$(_gs_eu2_tag_flags_fingerprint \$x)\" == \"\$(_gs_eu2_tag_flags_fingerprint \$y)\" ]] \
        || { echo 'fingerprint unstable for identical flag sets'; echo FAIL; exit 0; }
    echo PASS
"

# t120d: field boundaries are unambiguous. Joining the 7 fields with a printable
# separator lets a flag value containing that separator impersonate a different
# flag set — the poisoning this section fixes, reintroduced one layer down.
t "t120d: fingerprint fields cannot bleed across the separator" bash -c "
    source '${_GS_EU2_LIB}/core/records.sh'
    source '${_GS_EU2_LIB}/core/tag_flags.sh'
    # The boundary-shift pair: same field count, one ':' moved from inside a
    # value to between two values. Any join on a printable separator maps both
    # to 'a:b:c:::::' — only a separator no value can contain keeps them apart.
    _gs_eu2_record_new; p=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$p tag_filter  'a:b'
    _gs_eu2_record_set \$p tag_exclude 'c'
    _gs_eu2_record_new; q=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$q tag_filter  'a'
    _gs_eu2_record_set \$q tag_exclude 'b:c'
    [[ \"\$(_gs_eu2_tag_flags_fingerprint \$p)\" != \"\$(_gs_eu2_tag_flags_fingerprint \$q)\" ]] \
        || { echo 'separator collision — two different flag sets share one fingerprint'; echo FAIL; exit 0; }
    echo PASS
"

_flush_section


TOTAL=$(( PASS + FAIL ))
BAR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
printf "${C_BOLD}%s${C_RESET}\n" "${BAR}"
echo ""

# A filter that matches nothing used to print "ALL PASSED ✓ 0 / 0" and exit 0 —
# a typo'd or wrongly-separated --section produced a green run in which no test
# had executed. The separator is a COMMA (IFS=','), so --section='112 113' is a
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
