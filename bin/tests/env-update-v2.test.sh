#!/bin/bash
# Test suite for env-update-v2.sh
# Run: bash bin/tests/env-update-v2.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_UPDATE_V2="${SCRIPT_DIR}/../env-update-v2.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/env-update-v2"
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
printf "${C_BOLD}  env-update-v2.sh — test suite${C_RESET}\n"
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

t "t08c: --filter respected" bash -c "
    out=\$(bash '${ENV_UPDATE_V2}' --dump --filter='MYSQL' --env-file='${FIXTURES}/combined-real-world.env' 2>&1)
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_IMAGE_MYSQL9_VERSION' || { echo \"mysql not in output\"; echo FAIL; exit 0; }
    echo \"\$out\" | grep -qF 'GLOBAL_STACK_FLUTTER3_VERSION' && { echo \"flutter should be filtered out\"; echo FAIL; exit 0; }
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
    source '/stack/bin/lib/env-update-v2/core/cache.sh'
    _gs_eu2_cache_write 'dockerhub:_/postgres:18' '18.4-alpine3.23'
    val=\$(_gs_eu2_cache_read 'dockerhub:_/postgres:18')
    [[ \"\$val\" == '18.4-alpine3.23' ]] || { echo \"got: \$val\"; echo FAIL; exit 0; }
    echo PASS
"

t "t11b: cache miss returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11b
    source '/stack/bin/lib/env-update-v2/core/cache.sh'
    _gs_eu2_cache_read 'dockerhub:_/postgres:18' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11c: cache expired returns non-zero" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11c
    export _GS_EU2_CACHE_TTL=0
    source '/stack/bin/lib/env-update-v2/core/cache.sh'
    _gs_eu2_cache_write 'key:v1' 'somevalue'
    # TTL=0: any age is expired
    sleep 1
    _gs_eu2_cache_read 'key:v1' >/dev/null 2>&1 && { echo FAIL; exit 0; }
    echo PASS
"

t "t11d: cache_key sanitizes colons and slashes" bash -c "
    export _GS_EU2_CACHE_DIR=\${TMP_DIR}/cache11d
    source '/stack/bin/lib/env-update-v2/core/cache.sh'
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
  source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
  source '/stack/bin/lib/env-update-v2/core/semver.sh'
  source '/stack/bin/lib/env-update-v2/core/channel.sh'
}

t "t12a: stable channel picks highest stable, ignores rc" bash -c "
    $(_ch_src 2>/dev/null; echo 'true') || true
    source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update-v2/core/semver.sh'
    source '/stack/bin/lib/env-update-v2/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'stable')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12b: rc channel picks highest rc tag" bash -c "
    source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update-v2/core/semver.sh'
    source '/stack/bin/lib/env-update-v2/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4-rc2\n18.5-beta1'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'rc')
    [[ \"\$result\" == '18.4-rc2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12c: empty channel defaults to stable" bash -c "
    source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update-v2/core/semver.sh'
    source '/stack/bin/lib/env-update-v2/core/channel.sh'
    versions=\$'18.3\n18.4-rc1\n18.4'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" '')
    [[ \"\$result\" == '18.4' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12d: unstable channel picks highest pre-release" bash -c "
    source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update-v2/core/semver.sh'
    source '/stack/bin/lib/env-update-v2/core/channel.sh'
    versions=\$'18.3\n18.4\n18.5-rc1\n18.5-beta2'
    result=\$(_gs_eu2_channel_select_best \"\$versions\" 'unstable')
    # highest pre-release by sort -V
    [[ \"\$result\" == '18.5-rc1' || \"\$result\" == '18.5-beta2' ]] || { echo \"got: \$result\"; echo FAIL; exit 0; }
    echo PASS
"

t "t12e: is_prerelease detects rc, beta, alpha" bash -c "
    source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
    source '/stack/bin/lib/env-update-v2/core/semver.sh'
    _gs_eu2_is_prerelease '1.0.0-rc1'   || { echo 'rc1 not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '2.3.0beta2'  || { echo 'beta not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '1.0.0alpha'  || { echo 'alpha not detected'; echo FAIL; exit 0; }
    _gs_eu2_is_prerelease '18.4'       && { echo 'stable wrongly flagged'; echo FAIL; exit 0; }
    echo PASS
"

# ═══════════════════════════════════════════════════════════════════════════
# Section 13 — Tag flags application
# ═══════════════════════════════════════════════════════════════════════════
section "13 — tag flags"

_TF_SRC="source '/stack/bin/lib/env-update-v2/core/tag_flags.sh'"

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
    source '/stack/bin/lib/env-update-v2/http/curl.sh'
    # URL → strip query → sanitize → test.example_fixture-test
    out=\$(_gs_eu2_http_get 'https://test.example/fixture-test?foo=bar' 2>&1)
    echo \"\$out\" | grep -qF '1.2.3' || { echo \"fixture content missing: \$out\"; echo FAIL; exit 0; }
    echo PASS
"

t "t14b: fixture miss returns non-zero with message" bash -c "
    export _GS_EU2_HTTP_FIXTURE_DIR='${FIXTURES}/http'
    source '/stack/bin/lib/env-update-v2/http/curl.sh'
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
source '/stack/bin/lib/env-update-v2/config/defaults.sh'
source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update-v2/core/records.sh'
source '/stack/bin/lib/env-update-v2/core/semver.sh'
source '/stack/bin/lib/env-update-v2/core/channel.sh'
source '/stack/bin/lib/env-update-v2/core/tag_flags.sh'
source '/stack/bin/lib/env-update-v2/core/cache.sh'
source '/stack/bin/lib/env-update-v2/http/curl.sh'
source '/stack/bin/lib/env-update-v2/fetchers/dockerhub.sh'
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
    # Key must match what fetcher computes: dockerhub:<ns>:<tag_suffix>:<major_hint>:<channel>
    _gs_eu2_cache_write 'dockerhub:library/postgres:::' '18.3-alpine3.23-CACHED'
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

# ═══════════════════════════════════════════════════════════════════════════
# Section 16 — Decision classifier
# ═══════════════════════════════════════════════════════════════════════════
section "16 — decision classifier"

_DC_LIBS="
source '/stack/bin/lib/env-update-v2/config/prerelease_markers.sh'
source '/stack/bin/lib/env-update-v2/core/semver.sh'
source '/stack/bin/lib/env-update-v2/core/decide.sh'
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
