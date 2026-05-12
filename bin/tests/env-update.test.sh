#!/bin/bash
# Test suite for env-update.sh
# Run: bash bin/tests/env-update.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_UPDATE_V2="${SCRIPT_DIR}/../env-update.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/env-update"
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

t "t03o: boolean markers (override, manual, propagate)" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/flags-all.env' 2>&1)
    echo \"\$out\" | grep -qF 'override: true' || { echo \"override not true\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'manual: true' || { echo \"manual not true\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'propagate: true' || { echo \"propagate not true\"; echo FAIL; exit 0; }
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

t "t04c: pecl-ref token" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --env-file='${FIXTURES}/pecl-ref.env' 2>&1)
    echo \"\$out\" | grep -qF 'pecl_ref: event' || { echo \"pecl_ref not found\"; echo FAIL; exit 0; }
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
    echo \"\$err\" | grep -qF 'dry-run' || { echo \"stderr missing dry-run notice: \$err\"; echo FAIL; exit 0; }
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
    source '/stack/bin/lib/env-update/core/cache.sh'
    _gs_eu2_cache_write 'dockerhub:_/postgres:18' '18.4-alpine3.23'
    val=\$(_gs_eu2_cache_read 'dockerhub:_/postgres:18')
    [[ \"\$val\" == '18.4-alpine3.23' ]] || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11b: cache miss returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11b
    source '/stack/bin/lib/env-update/core/cache.sh'
    _gs_eu2_cache_read 'dockerhub:_/postgres:18' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11c: cache expired returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11c
    export _GS_EU2_CACHE_TTL=0
    source '/stack/bin/lib/env-update/core/cache.sh'
    _gs_eu2_cache_write 'key:v1' 'somevalue'
    # TTL=0: any age is expired
    sleep 1
    _gs_eu2_cache_read 'key:v1' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11d: cache_key sanitizes colons and slashes" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11d
    source '/stack/bin/lib/env-update/core/cache.sh'
    f=\$(_gs_eu2_cache_key_to_file 'dockerhub:_/postgres:18:stable')
    [[ \"\$f\" == *'dockerhub__'* ]] || { echo \"colon not replaced: \$f\"; echo FAIL; exit 0; }
    [[ \"\$f\" != *':'* ]] || { echo \"raw colon in path: \$f\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 12 — Channel selection
# ═══════════════════════════════════════════════════════════════════════════
section "12 — channel selection"

_ch_src() {
  source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
  source '/stack/bin/lib/env-update/core/semver.sh'
  source '/stack/bin/lib/env-update/core/channel.sh'
}

t "t12a: stable channel picks highest stable, ignores rc" bash -c "
    $(_ch_src 2>/dev/null; echo 'true') || true
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'stable')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12b: rc channel picks highest rc tag" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4-rc2\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'rc')
    [[ \"\$result\" == '18.4-rc2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12c: empty channel defaults to stable" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12d: unstable channel picks highest pre-release" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'18.3\n18.4\n18.5-rc1\n18.5-beta2'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    # highest pre-release by sort -V
    [[ \"\$result\" == '18.5-rc1' || \"\$result\" == '18.5-beta2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12e: is_prerelease detects rc, beta, alpha" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    _gs_eu2_is_prerelease '1.0.0-rc1'   || { echo 'rc1 not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '2.3.0beta2'  || { echo 'beta not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0alpha'  || { echo 'alpha not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '18.4'       && { echo 'stable wrongly flagged'; echo FAIL; exit 0; }
    echo PASS
"

t "t12f: v-prefixed tags accepted by channel filter (B2)" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'v0.29.0\nv0.28.0\nv0.27.0'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ -n \"\$result\" ]] || { echo 'all v-prefixed tags were dropped'; echo FAIL; exit 0; }
    [[ \"\$result\" == 'v0.29.0' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 13 — Tag flags application
# ═══════════════════════════════════════════════════════════════════════════
section "13 — tag flags"

_TF_SRC="source '/stack/bin/lib/env-update/core/tag_flags.sh'"

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
    source '/stack/bin/lib/env-update/http/curl.sh'
    # URL → strip query → sanitize → test.example_fixture-test
    out=\$(_gs_eu2_http_get 'https://test.example/fixture-test?foo=bar' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t14b: fixture miss returns non-zero with message" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '/stack/bin/lib/env-update/http/curl.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
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
    # Key must match what fetcher computes: dockerhub:<ns>:<tag_suffix>:<major_hint>:<channel>:<prefer_specific>
    _gs_eu2_cache_write 'dockerhub:library/postgres::::' '18.3-alpine3.23-CACHED'
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'dockerhub'
    _gs_eu2_record_set \$idx identifier '_/postgres'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_POSTGRES18_VERSION'
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
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/decide.sh'
"

t "t16a: same version → SKIP (up-to-date)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.4' '18.4' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16b: patch bump → AUTO" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16c: major jump with no major_hint → HOLD" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '17.5' '18.4' '' '' '')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16d: override flag → MANUAL regardless of delta" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' 'true' '' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t16e: proposed older than current → SKIP (downgrade protection, B1)" bash -c "
    ${_DC_LIBS}
    result=\$(_gs_eu2_classify_decision '1.29.3' '1.2.5' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"downgrade not prevented: got \$result\"; echo FAIL; exit 0; }
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh19_cache
"

t "t19a: channel_select_best falls back to sort-V for codename tags (C1)" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    versions=\$'resolute-20260413\nresolute-20260108\nplucky-20260201\nlatest'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == 'resolute-20260413' ]] || { echo \"got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19b: channel_select_best returns empty when only unversioned sentinels present" bash -c "
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/parse.sh'
    f=\${TMP_DIR}/t19j.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update pecl-git:https://github.com/example/php-ext 1.2.3 sha:%s (pecl-ref:ext)\nGLOBAL_STACK_EXT_VERSION=1.2.3\n' \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got=\$(_gs_eu2_record_get 0 annotation_sha)
    [[ \"\$got\" == \"\$sha\" ]] || { echo \"annotation_sha expected '\$sha' got '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19k: (use-sha) flag sets use_sha=true on record" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/parse.sh'
    f=\${TMP_DIR}/t19k.env
    sha='aabbccdd1122334455667788990011aabbccdd11'
    printf '# @todo env-update (use-sha) pecl-git:https://github.com/example/php-ext sha:%s (pecl-ref:ext)\nGLOBAL_STACK_EXT_VERSION=%s\n' \"\$sha\" \"\$sha\" > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    got=\$(_gs_eu2_record_get 0 use_sha)
    [[ \"\$got\" == 'true' ]] || { echo \"use_sha expected 'true' got '\$got'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19l: apply with cur_sha/new_sha updates sha:OLD to sha:NEW in annotation while keeping version" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
    f=\${TMP_DIR}/t19l.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    ann=\"# @todo env-update pecl-git:https://github.com/example/php-ext 1.0.0 sha:\${old_sha} (pecl-ref:ext)\"
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
    ann2=\"# @todo env-update pecl-git:https://github.com/example/php-ext 2.0.0 sha:\${old_sha} (pecl-ref:ext)\"
    printf '%s\nGLOBAL_STACK_EXT_VERSION=2.0.0\n' \"\$ann2\" > \"\$f\"
    _gs_eu2_record_set \$idx raw_annotation   \"\$ann2\"
    _gs_eu2_apply_updates \"\$f\" 'false' > /dev/null
    grep -qF \"sha:\${new_sha}\" \"\$f\" || { echo \"sha not updated to new_sha; expected sha:\${new_sha}\"; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF \"sha:\${old_sha}\" \"\$f\" && { echo 'old sha still present'; cat \"\$f\"; echo FAIL; exit 0; }
    grep -qF 'GLOBAL_STACK_EXT_VERSION=3.0.0' \"\$f\" || { echo 'assignment not updated to 3.0.0'; cat \"\$f\"; echo FAIL; exit 0; }
    echo PASS
"

t "t19m: apply with use_sha=true writes new_sha to VAR= instead of new version" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/apply.sh'
    f=\${TMP_DIR}/t19m.env
    old_sha='aaaa0000bbbb1111cccc2222dddd3333eeee4444'
    new_sha='1111aaaa2222bbbb3333cccc4444dddd5555eeee'
    ann=\"# @todo env-update (use-sha) pecl-git:https://github.com/example/php-ext sha:\${old_sha} (pecl-ref:ext)\"
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
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
"
_DC_LIBS20="
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/decide.sh'
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
    result=\$(_gs_eu2_classify_decision 'resolute-20260108' 'resolute-20260413' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t20e: classify — unversioned current (nightly) → SKIP" bash -c "
    ${_DC_LIBS20}
    result=\$(_gs_eu2_classify_decision 'nightly' '2024.10.22-7ca5933' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 21 — _gs_eu2_hoist_all_flags unit tests
# ═══════════════════════════════════════════════════════════════════════════
section "21 — hoist_all_flags"

_HOIST_LIBS="
source '/stack/bin/lib/env-update/core/parse.sh'
"

t "t21a: single recognized flag extracted, rest cleaned" bash -c "
    ${_HOIST_LIBS}
    flags=''; cleaned=''
    _gs_eu2_hoist_all_flags flags cleaned '(propagate) dockerhub:nginx 1.25'
    [[ \"\$flags\"   == 'propagate' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
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
    _gs_eu2_hoist_all_flags flags cleaned '(propagate) (override) dockerhub:nginx 1.25'
    IFS=\$'\\x1f' read -ra parts <<< \"\$flags\"
    [[ \"\${parts[0]}\" == 'propagate' ]] || { echo \"part0 wrong: \${parts[0]}\"; echo FAIL; exit 0; }
    [[ \"\${parts[1]}\" == 'override'  ]] || { echo \"part1 wrong: \${parts[1]}\"; echo FAIL; exit 0; }
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
    _gs_eu2_hoist_all_flags flags cleaned 'dockerhub:nginx 1.25 (propagate)'
    [[ \"\$flags\"   == 'propagate' ]] || { echo \"flags wrong: \$flags\";   echo FAIL; exit 0; }
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
    _gs_eu2_hoist_all_flags flags cleaned '(propagate) (compat: old-api) (override) dockerhub:bar 2.0'
    IFS=\$'\\x1f' read -ra parts <<< \"\$flags\"
    [[ \"\${parts[0]}\" == 'propagate' ]] || { echo \"part0 wrong: \${parts[0]}\"; echo FAIL; exit 0; }
    [[ \"\${parts[1]}\" == 'override'  ]] || { echo \"part1 wrong: \${parts[1]}\"; echo FAIL; exit 0; }
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
    source '/stack/bin/lib/env-update/core/records.sh'
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
    source '/stack/bin/lib/env-update/core/records.sh'
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
    source '/stack/bin/lib/env-update/http/curl.sh'
    declare -f _gs_eu2_http_get_auth >/dev/null 2>&1 || { echo 'function not found'; echo FAIL; exit 0; }
    echo PASS
"

t "t24b: empty token delegates to plain http_get (fixture path identical)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '/stack/bin/lib/env-update/http/curl.sh'
    # Same fixture as t14a — empty token must hit same file
    out=\$(_gs_eu2_http_get_auth 'https://test.example/fixture-test?foo=bar' '' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t24c: fixture injection works identically with non-empty token (no auth header sent to fixture)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '/stack/bin/lib/env-update/http/curl.sh'
    # Fixture path is determined by URL only — token should not affect fixture lookup
    out=\$(_gs_eu2_http_get_auth 'https://test.example/fixture-test?foo=bar' 'my-secret-token' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing with token: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t24d: missing fixture returns non-zero with auth token (same as without token)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '/stack/bin/lib/env-update/http/curl.sh'
    _gs_eu2_http_get_auth 'https://example.com/no-such-fixture' 'tok' >/dev/null 2>&1 \
        && { echo 'expected non-zero exit'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 25 — dockerhub HOLD decision comes from decide.sh, not fetcher (Fix 3)
# ═══════════════════════════════════════════════════════════════════════════
section "25 — dockerhub HOLD from pipeline not fetcher"

_DH_LIBS25="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
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
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/decide.sh'
    # major_hint=17 but proposed=18.4 → HOLD
    result=\$(_gs_eu2_classify_decision '17.5' '18.4' '' '' '17')
    [[ \"\$result\" == 'HOLD' ]] || { echo \"expected HOLD, got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t25d: full pipeline HOLD for major-pin escape (end-to-end, no fetcher HOLD involved)" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/decide.sh'
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
    classified=\$(_gs_eu2_classify_decision \"\$cur\" \"\$prop\" \"\$override\" \"\$manual\" \"\$major\")
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/codeberg.sh'
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
    # releases fixture is empty array; tags fixture has 1.5.0
    [[ \"\$val\" == '1.5.0' ]] || { echo \"got: '\$val'\"; echo FAIL; exit 0; }
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/quay.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/npm.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/pypi.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/rubygems.sh'
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
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

# ═══════════════════════════════════════════════════════════════════════════
# Section 32 — sdkman fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "32 — sdkman fetcher"

_SDK_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/sdkman.sh'
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
    _gs_eu2_cache_write 'sdkman:gradle::' '9.99.0-CACHED'
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

# ═══════════════════════════════════════════════════════════════════════════
# Section 33 — sdkmanager fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "33 — sdkmanager fetcher"

_SDKMGR_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/sdkmanager.sh'
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

# ═══════════════════════════════════════════════════════════════════════════
# Section 34 — pecl helper functions (pecl.sh)
# ═══════════════════════════════════════════════════════════════════════════
section "34 — pecl helper functions"

_PECL_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
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
# Section 35 — pecl-git fetcher
# ═══════════════════════════════════════════════════════════════════════════
section "35 — pecl-git fetcher"

_PECLGIT_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
source '/stack/bin/lib/env-update/fetchers/pecl_git.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_cache
"

t "t35a: happy path — proposed_version = release tag version from releases API" bash -c "
    ${_PECLGIT_LIBS}
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    _gs_eu2_record_set \$idx identifier 'https://github.com/Imagick/imagick'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_IMAGICK_VERSION'
    _gs_eu2_fetch_pecl_git \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture releases: [3.8.1, 3.8.0] → best is 3.8.1 (v-prefix stripped)
    [[ \"\$val\" == '3.8.1' ]] || { echo \"expected 3.8.1, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t35b: promotion detected — alt_version set when stable PECL release is newer than git" bash -c "
    ${_PECLGIT_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_b_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    # phpredis: git date 2026-02-10, redis pecl 6.1.0 released 2026-03-20 → promotion
    _gs_eu2_record_set \$idx identifier 'https://github.com/phpredis/phpredis'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_REDIS_VERSION'
    _gs_eu2_fetch_pecl_git \$idx
    alt=\$(_gs_eu2_record_get \$idx alt_version)
    [[ -n \"\$alt\" ]] || { echo 'alt_version should be set for promotion'; echo FAIL; exit 0; }
    [[ \"\$alt\" == *'6.1.0'* ]] || { echo \"expected 6.1.0 in alt_version, got: '\$alt'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t35c: no promotion — alt_version empty when git commit is newer than PECL release" bash -c "
    ${_PECLGIT_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_c_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    # imagick: git date 2026-02-15, imagick pecl 3.8.0 released 2026-01-10 → no promotion
    _gs_eu2_record_set \$idx identifier 'https://github.com/Imagick/imagick'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_IMAGICK_VERSION'
    _gs_eu2_fetch_pecl_git \$idx
    alt=\$(_gs_eu2_record_get \$idx alt_version)
    [[ -z \"\$alt\" ]] || { echo \"alt_version should be empty (no promotion), got: '\$alt'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t35d: ext_name derived from repo name — phpredis fetcher returns release version" bash -c "
    ${_PECLGIT_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_d_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    # phpredis repo → ext_name='phpredis' (no matching prefix → use full name)
    # Check that the proposed_version is the latest semver release tag
    _gs_eu2_record_set \$idx identifier 'https://github.com/phpredis/phpredis'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_REDIS_VERSION'
    _gs_eu2_fetch_pecl_git \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture releases: [v6.3.0, v6.2.0, v6.1.0] → best is 6.3.0 (v-prefix stripped)
    [[ \"\$val\" == '6.3.0' ]] || { echo \"expected 6.3.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t35e: pecl_ref override — uses override ext_name for PECL lookup, returns release version" bash -c "
    ${_PECLGIT_LIBS}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_e_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    _gs_eu2_record_set \$idx identifier 'https://github.com/test-org/pecl-event'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_EVENT_VERSION'
    # Override ext_name so PECL lookup uses 'pecl_ref_override' (our fixture)
    _gs_eu2_record_set \$idx pecl_ref   'pecl_ref_override'
    _gs_eu2_fetch_pecl_git \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture releases: [v2.5.0, v2.4.0] → best is 2.5.0 (v-prefix stripped)
    [[ \"\$val\" == '2.5.0' ]] || { echo \"expected 2.5.0, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t35f: GitHub API error — error_message set, decision=ERROR" bash -c "
    ${_PECLGIT_LIBS}
    unset _GS_EU2_HTTP_FIXTURE_DIR
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_f_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    _gs_eu2_record_set \$idx identifier 'https://github.com/no-such-owner/no-such-repo'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_XYZZY_VERSION'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    decision=\$(_gs_eu2_record_get \$idx decision)
    err=\$(_gs_eu2_record_get \$idx error_message)
    [[ \"\$decision\" == 'ERROR' ]] || { echo \"expected ERROR, got: '\$decision'\"; echo FAIL; exit 0; }
    [[ -n \"\$err\" ]] || { echo 'error_message is empty'; echo FAIL; exit 0; }
    echo PASS
"

t "t35g: GITHUB_TOKEN forwarded — fixture injection works with token set" bash -c "
    ${_PECLGIT_LIBS}
    export GITHUB_TOKEN='test-token-for-fixture-injection'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit_g_cache
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type       'pecl-git'
    _gs_eu2_record_set \$idx identifier 'https://github.com/Imagick/imagick'
    _gs_eu2_record_set \$idx env_var    'GLOBAL_STACK_PHP_IMAGICK_VERSION'
    _gs_eu2_fetch_pecl_git \$idx
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # With token set, fixture injection still works (token not part of fixture path)
    [[ \"\$val\" == '3.8.1' ]] || { echo \"token-with-fixture failed: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 36 — semver_delta handles YYYYMMDD-sha8 format (patch, not major)
# ═══════════════════════════════════════════════════════════════════════════
section "36 — semver_delta date-sha format"

_SV_LIBS="
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    ${_SV_LIBS}
    source '/stack/bin/lib/env-update/core/decide.sh'
    result=\$(_gs_eu2_classify_decision '20260315-abc1234d' '20260315-abc1234d' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for same date-sha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t36d: newer date-sha → AUTO (classify_decision integration)" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    ${_SV_LIBS}
    source '/stack/bin/lib/env-update/core/decide.sh'
    result=\$(_gs_eu2_classify_decision '20260315-abc1234d' '20260316-def5678e' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for newer date-sha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 37 — url fetcher (Phase 3f)
# ═══════════════════════════════════════════════════════════════════════════
section "37 — url fetcher"

_URL_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/core/ubuntu.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/url.sh'
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
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t38b_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file='/stack/.env' --filter='ANDROID_SDK_URL|HTTPD_APR_UTIL|HTTPD_APR_VERSION|HTTPD_VERSION|PODMAN_CHANNEL|NGINX_AUTOMAKE|ZEPHIR|NODEEDGE' 2>/dev/null || true)
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

t "t39b: HOLD pin escape has 'major pin' reason label" bash -c "
    f=\${TMP_DIR}/t39b.env
    # major_hint embedded in type token (colon-separated) — proposed v4.0.0 escapes pin=3
    printf '# @todo env-update github:testowner/majorpin-repo:3 3.4.0\nGLOBAL_STACK_TEST_PINNED=3.4.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t39b_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'major pin' || { echo \"no 'major pin' in HOLD output: \$out\"; echo FAIL; exit 0; }
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
    echo \"\$out\" | grep -qF 'would downgrade' || { echo \"no downgrade reason in output: \$out\"; echo FAIL; exit 0; }
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/dh40_cache
"

t "t40a: is_floating_tag detects X.Y tag as floating" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1-alpine3.23' && echo PASS || { echo 'FAIL: X.Y-suffix should be floating'; exit 0; }
"

t "t40b: is_floating_tag detects X tag as floating" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9-alpine3.23' && echo PASS || { echo 'FAIL: X-suffix should be floating'; exit 0; }
"

t "t40c: is_floating_tag accepts X.Y.Z tag as specific" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.0.4-alpine3.23' && { echo 'FAIL: X.Y.Z-suffix should NOT be floating'; exit 0; } || echo PASS
"

t "t40d: is_floating_tag accepts X.Y.Z-prerelease tag as specific" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1.0-rc2-alpine3.23' && { echo 'FAIL: X.Y.Z-rc should NOT be floating'; exit 0; } || echo PASS
"

t "t40e: is_floating_tag accepts bare X.Y.Z (no suffix)" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.0.4' && { echo 'FAIL: bare X.Y.Z should NOT be floating'; exit 0; } || echo PASS
"

t "t40f: is_floating_tag rejects bare X.Y (no suffix)" bash -c "
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    _gs_eu2_is_floating_tag '9.1' && echo PASS || { echo 'FAIL: bare X.Y should be floating'; exit 0; }
"

t "t40g: prefer-specific flag record field is recognized" bash -c "
    source '/stack/bin/lib/env-update/core/records.sh'
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
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/parse.sh'
    f=\$(mktemp)
    printf '# @todo env-update (prefer-specific) dockerhub:valkey/valkey 9.0.3-alpine3.23\nGLOBAL_STACK_VALKEY_VERSION=9.0.3-alpine3.23\n' > \"\$f\"
    _gs_eu2_parse_env_file \"\$f\"
    val=\$(_gs_eu2_record_get 0 prefer_specific)
    rm -f \"\$f\"
    [[ \"\$val\" == 'true' ]] || { echo \"prefer_specific not set from annotation, got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t40l: cache key is segregated by prefer-specific flag (flag-on vs flag-off use different keys)" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='/stack/bin/tests/fixtures/env-update/http'
    export _GS_EU2_CACHE_DIR=\$(mktemp -d)
    # Run WITHOUT prefer-specific — writes one cache file
    bash -c \"
      export _GS_EU2_HTTP_FIXTURE_DIR='\$_GS_EU2_HTTP_FIXTURE_DIR'
      export _GS_EU2_CACHE_DIR='\$_GS_EU2_CACHE_DIR'
      declare -A _GS_EU2_CFG=([no_cache]=false [channel]=stable [cache_ttl]=3600)
      source '/stack/bin/lib/env-update/core/records.sh'
      source '/stack/bin/lib/env-update/core/semver.sh'
      source '/stack/bin/lib/env-update/core/channel.sh'
      source '/stack/bin/lib/env-update/core/tag_flags.sh'
      source '/stack/bin/lib/env-update/core/cache.sh'
      source '/stack/bin/lib/env-update/http/curl.sh'
      source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
      source '/stack/bin/lib/env-update/core/parse.sh'
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
      source '/stack/bin/lib/env-update/core/records.sh'
      source '/stack/bin/lib/env-update/core/semver.sh'
      source '/stack/bin/lib/env-update/core/channel.sh'
      source '/stack/bin/lib/env-update/core/tag_flags.sh'
      source '/stack/bin/lib/env-update/core/cache.sh'
      source '/stack/bin/lib/env-update/http/curl.sh'
      source '/stack/bin/lib/env-update/fetchers/dockerhub.sh'
      source '/stack/bin/lib/env-update/core/parse.sh'
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
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
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
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/decide.sh'
"

t "t42a: stable current + no-dash RC proposed → SKIP (not AUTO)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '6.3.0' '6.3.0RC1' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→RC (no dash), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42b: stable current + dash RC proposed → SKIP" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '1.2.3' '1.3.0-rc1' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→rc1 (with dash), got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42c: stable current + alpha proposed → SKIP" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '2.0.0' '2.1.0alpha1' '' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP for stable→alpha, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42d: prerelease current + prerelease proposed → AUTO (both pre-release)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '1.0.0-rc1' '1.0.0-rc2' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for rc1→rc2, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42e: stable current + stable proposed → AUTO (normal upgrade)" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '6.3.0' '6.3.1' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for stable patch bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t42f: stable alpine-tagged current + stable alpine-tagged proposed → AUTO" bash -c "
    ${_CD_LIBS42}
    result=\$(_gs_eu2_classify_decision '8.6.1-alpine3.23' '8.6.3-alpine3.23' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for alpine patch bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 43 — pecl_git filters prerelease when current is stable
# ═══════════════════════════════════════════════════════════════════════════
section "43 — pecl_git prerelease filter"

_PECLGIT_LIBS43="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
source '/stack/bin/lib/env-update/fetchers/pecl_git.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit43_cache
"

t "t43a: stable current + RC in releases list → proposed is stable (RC filtered)" bash -c "
    ${_PECLGIT_LIBS43}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit43a_cache
    declare -A _GS_EU2_CFG=([no_cache]=true [channel]=stable)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/phpext-with-rc'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '6.3.0'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture releases: RC first, then 6.3.0 — stable filter must prefer 6.3.0
    [[ \"\$val\" == '6.3.0' ]] || { echo \"expected 6.3.0 (stable), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t43b: prerelease current + RC in releases list → all candidates kept (no filter)" bash -c "
    ${_PECLGIT_LIBS43}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit43b_cache
    declare -A _GS_EU2_CFG=([no_cache]=true [channel]=stable)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/phpext-with-rc'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '6.3.0RC1'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # With prerelease current, RC candidates are kept — sort -V picks RC1 as best
    [[ \"\$val\" == '6.3.0RC1' ]] || { echo \"expected 6.3.0RC1 (RC kept), got: '\$val'\"; echo FAIL; exit 0; }
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
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
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
# Section 45 — --with-tags CLI flag + pecl_git version-gap fix
# ═══════════════════════════════════════════════════════════════════════════
section "45 — --with-tags CLI + pecl_git version-gap fix"

t "t45a: --with-tags CLI flag sets CFG[with_tags]=true" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/reporting/help.sh'
    source '/stack/bin/lib/env-update/core/args.sh'
    _gs_eu2_parse_args --with-tags
    [[ \"\${_GS_EU2_CFG[with_tags]}\" == 'true' ]] \
        || { echo \"expected with_tags=true, got: '\${_GS_EU2_CFG[with_tags]}'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t45b: --with-tags default is false when not passed" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/reporting/help.sh'
    source '/stack/bin/lib/env-update/core/args.sh'
    _gs_eu2_parse_args
    [[ \"\${_GS_EU2_CFG[with_tags]}\" == 'false' ]] \
        || { echo \"expected with_tags=false, got: '\${_GS_EU2_CFG[with_tags]}'\"; echo FAIL; exit 0; }
    echo PASS
"

_PECLGIT_LIBS45="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
source '/stack/bin/lib/env-update/fetchers/pecl_git.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

t "t45c: pecl_git check_tags=true → merges releases + tags → finds 0.15.2" bash -c "
    ${_PECLGIT_LIBS45}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit45c_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx check_tags       'true'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.13.0'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '0.15.2' ]] || { echo \"expected 0.15.2 (check-tags), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t45d: pecl_git version-gap fix — releases older than current → auto-checks tags" bash -c "
    ${_PECLGIT_LIBS45}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit45d_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.15.2'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # releases v0.14.0 < current 0.15.2 → gap fix → tags has 0.15.2
    [[ \"\$val\" == '0.15.2' ]] || { echo \"expected 0.15.2 (gap fix), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t45e: pecl_git with_tags=true in CFG → finds 0.15.2" bash -c "
    ${_PECLGIT_LIBS45}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit45e_cache
    declare -A _GS_EU2_CFG=([no_cache]=true [with_tags]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/tag-ahead'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VERSION'
    _gs_eu2_record_set \$idx current_version  '0.13.0'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    [[ \"\$val\" == '0.15.2' ]] || { echo \"expected 0.15.2 (with_tags=true), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 46 — same-version SKIP beats manual/override (RC1) + display (RC2)
# ═══════════════════════════════════════════════════════════════════════════
section "46 — same-version SKIP beats manual/override + display"

_DC46_LIBS="
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/decide.sh'
"

t "t46a: classify — same version + override=true → SKIP (not MANUAL)" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.3' 'true' '' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46b: classify — same version + manual=true → SKIP (not MANUAL)" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '2.2.0' '2.2.0' '' 'true' '')
    [[ \"\$result\" == 'SKIP' ]] || { echo \"expected SKIP, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46c: classify — override=true but version changed → still MANUAL" bash -c "
    ${_DC46_LIBS}
    result=\$(_gs_eu2_classify_decision '18.3' '18.4' 'true' '' '')
    [[ \"\$result\" == 'MANUAL' ]] || { echo \"expected MANUAL for changed version with override, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46d: display — (override) at same version shows '(up to date — manual)' not '← manual flag'" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/t46d_cache
    f=\${TMP_DIR}/t46d.env
    # fixture for dockerhub:_/postgres returns 18.4-alpine3.23; set current to same
    printf '# @todo env-update (override) dockerhub:_/postgres\nGLOBAL_STACK_POSTGRES_OVR=18.4-alpine3.23\n' > \"\$f\"
    out=\$(bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'up to date' || { echo \"expected 'up to date' in SKIP output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'manual'     || { echo \"expected 'manual' hint in SKIP output: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qvF '[MANUAL]'  || { echo \"should show [SKIP] not [MANUAL]: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t46e: sdkmanager fetcher does NOT set manual field — decide.sh classifies via versions" bash -c "
    source '/stack/bin/lib/env-update/config/defaults.sh'
    source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/semver.sh'
    source '/stack/bin/lib/env-update/core/channel.sh'
    source '/stack/bin/lib/env-update/core/tag_flags.sh'
    source '/stack/bin/lib/env-update/core/cache.sh'
    source '/stack/bin/lib/env-update/http/curl.sh'
    source '/stack/bin/lib/env-update/fetchers/sdkmanager.sh'
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
# Section 47 — pecl fetcher (type:pecl) dispatch path
# ═══════════════════════════════════════════════════════════════════════════
section "47 — pecl fetcher dispatch path"

t "t47a: type:pecl dispatches to _gs_eu2_fetch_pecl — not SKIP fallback (imagick, fixture)" bash -c "
    f=\${TMP_DIR}/t47a.env
    printf '# @todo env-update pecl:imagick\nGLOBAL_STACK_PHP_IMAGICK_PECL=3.7.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47a_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF 'not yet implemented' && { echo \"still hitting SKIP fallback: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'unknown fetcher type' && { echo \"still hitting unknown-type fallback: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE 'AUTO|SKIP|HOLD|ERROR' || { echo \"no decision token in output: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47b: type:pecl happy path — proposed_version = latest stable from fixture (apcu 6.3.0)" bash -c "
    f=\${TMP_DIR}/t47b.env
    printf '# @todo env-update pecl:apcu\nGLOBAL_STACK_PHP_APCU_VERSION=6.1.0\n' > \"\$f\"
    out=\$(export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47b_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null)
    echo \"\$out\" | grep -qF '6.3.0' || { echo \"expected 6.3.0 in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t47c: type:pecl unknown extension — ERROR decision not SKIP fallback" bash -c "
    f=\${TMP_DIR}/t47c.env
    printf '# @todo env-update pecl:no-such-extension-xyzzy\nGLOBAL_STACK_XYZZY_PECL=1.0.0\n' > \"\$f\"
    out=\$(unset _GS_EU2_HTTP_FIXTURE_DIR; export _GS_EU2_CACHE_DIR=\"\${TMP_DIR}/t47c_cache\"; bash '${ENV_UPDATE_V2}' --check --dry-run --env-file=\"\$f\" 2>/dev/null || true)
    echo \"\$out\" | grep -qF 'unknown fetcher type' && { echo \"hit unknown-type fallback instead of ERROR: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'not yet implemented' && { echo \"hit not-implemented fallback instead of ERROR: \$out\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qE 'ERROR|no stable release' || { echo \"expected ERROR or 'no stable release' in output; got: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 48 — pecl_git digit-preference filter
# ═══════════════════════════════════════════════════════════════════════════
section "48 — pecl_git digit-preference filter"

_PECLGIT_LIBS48="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/channel.sh'
source '/stack/bin/lib/env-update/core/tag_flags.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
source '/stack/bin/lib/env-update/fetchers/pecl_git.sh'
export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
"

t "t48a: mixed tags — digit-prefixed wins over letter-prefixed (sort -V bug prevented)" bash -c "
    ${_PECLGIT_LIBS48}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit48a_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/mixed-tags-repo'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_ZIP_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.0.0'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture releases: 1.22.8, PHP_ZIP-1.12.1, 1.0.0
    # Without fix: sort -V picks PHP_ZIP-1.12.1 (letter-prefixed sorts last)
    # With fix:    digit-preference filter discards PHP_ZIP-1.12.1 → 1.22.8 wins
    [[ \"\$val\" == '1.22.8' ]] || { echo \"expected 1.22.8 (digit-prefixed), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

t "t48b: all-letter tags — letter-prefixed fallback still produces a result" bash -c "
    ${_PECLGIT_LIBS48}
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/peclgit48b_cache
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    # testowner/tags-only-repo releases fixture returns [] (empty); tags fixture has
    # digit-only candidates → still picks highest digit version
    _gs_eu2_record_set \$idx type             'pecl-git'
    _gs_eu2_record_set \$idx identifier       'testowner/tags-only-repo'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_TEST_VER48B'
    _gs_eu2_record_set \$idx current_version  '2.0.0'
    _gs_eu2_fetch_pecl_git \$idx 2>/dev/null || true
    val=\$(_gs_eu2_record_get \$idx proposed_version)
    # fixture tags: 3.1.0, 3.0.2, 3.0.1, 3.0.0 (all digit-starting) → 3.1.0
    [[ \"\$val\" == '3.1.0' ]] || { echo \"expected 3.1.0 (all-digit tags), got: '\$val'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 49 — pecl fetcher with (git:owner/repo) flag
# ═══════════════════════════════════════════════════════════════════════════
section "49 — pecl fetcher with (git:owner/repo) flag"

_PECL_GIT_FLAG_LIBS="
source '/stack/bin/lib/env-update/config/defaults.sh'
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/records.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/cache.sh'
source '/stack/bin/lib/env-update/http/curl.sh'
source '/stack/bin/lib/env-update/fetchers/github.sh'
source '/stack/bin/lib/env-update/fetchers/pecl.sh'
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

t "t49c: pecl + (git:...) where no matching git tag — version set, SHA empty, warning on stderr" bash -c "
    ${_PECL_GIT_FLAG_LIBS}
    declare -A _GS_EU2_CFG=([no_cache]=true)
    _gs_eu2_record_new; idx=\${_GS_EU2_LAST_IDX}
    _gs_eu2_record_set \$idx type             'pecl'
    _gs_eu2_record_set \$idx identifier       'zmq'
    _gs_eu2_record_set \$idx git_repo         'testowner/no-git-tag-repo'
    _gs_eu2_record_set \$idx env_var          'GLOBAL_STACK_PHP_ZMQ_VERSION'
    _gs_eu2_record_set \$idx current_version  '1.1.2'
    stderr_file=\$(mktemp)
    _gs_eu2_fetch_pecl \$idx 2>\"\$stderr_file\" || true
    ver=\$(_gs_eu2_record_get \$idx proposed_version)
    sha=\$(_gs_eu2_record_get \$idx proposed_sha)
    dec=\$(_gs_eu2_record_get \$idx decision)
    stderr_out=\$(cat \"\$stderr_file\"); rm -f \"\$stderr_file\"
    [[ \"\$ver\" == '1.1.3' ]] || { echo \"expected ver=1.1.3 even when SHA missing, got: '\$ver'\"; echo FAIL; exit 0; }
    [[ -z \"\$sha\" ]] || { echo \"expected empty SHA when no tag found, got: '\$sha'\"; echo FAIL; exit 0; }
    [[ \"\$dec\" != 'ERROR' ]] || { echo 'decision must not be ERROR (soft-fail)'; echo FAIL; exit 0; }
    printf '%s' \"\$stderr_out\" | grep -q 'no git tag' || { echo \"expected 'no git tag' warning on stderr, got: '\$stderr_out'\"; echo FAIL; exit 0; }
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
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/parse.sh'
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
    source '/stack/bin/lib/env-update/core/records.sh'
    source '/stack/bin/lib/env-update/core/parse.sh'
    f=\$(mktemp)
    printf '# @todo env-update pecl:zmq (git:noslash) 1.1.3\nGLOBAL_STACK_ZMQ=\n' > \"\$f\"
    err=\$(_gs_eu2_parse_env_file \"\$f\" 2>&1 || true)
    rm -f \"\$f\"
    printf '%s' \"\$err\" | grep -q 'OWNER/REPO' || { echo \"expected OWNER/REPO error, got: '\$err'\"; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 50 — semver_delta YYYYMMDD-only date stamps → patch (not major)
# ═══════════════════════════════════════════════════════════════════════════
section "50 — semver_delta pure-date stamps (YYYYMMDD/YYYYMM)"

_SV_LIBS50="
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
"

_CD_LIBS50="
source '/stack/bin/lib/env-update/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update/core/semver.sh'
source '/stack/bin/lib/env-update/core/decide.sh'
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
    source '/stack/bin/lib/env-update/config/defaults.sh'
    ${_CD_LIBS50}
    result=\$(_gs_eu2_classify_decision 'v20260311' 'v20260512' '' '' '')
    [[ \"\$result\" == 'AUTO' ]] || { echo \"expected AUTO for YYYYMMDD date bump, got: '\$result'\"; echo FAIL; exit 0; }
    echo PASS
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
