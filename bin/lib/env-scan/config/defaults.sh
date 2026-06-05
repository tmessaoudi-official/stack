#!/bin/bash
# defaults.sh — _GS_ES_CFG defaults and pattern constants for env-scan
#
# Exports:   _GS_ES_VERSION  _GS_ES_CFG (global associative array, populated by args.sh)
#            _GS_ES_PATTERN_DIFF_IGNORE  _GS_ES_PATTERN_SCAN_VAR_IGNORE
#            _GS_ES_PATTERN_REVERSE_CHECK_IGNORE  _GS_ES_PATTERN_CONFLICT_IGNORE
#            _GS_ES_PATTERN_ORPHAN_IGNORE  _GS_ES_PATTERN_FORWARD_CHECK_IGNORE
# Sources:   none
# Deps:      bash 4.3+
# Env:       none
#
# Pattern constants are named <SCOPE>_IGNORE and map 1:1 to _GS_ES_CFG keys and
# CLI flags in args.sh.  They are readonly ERE strings consumed by grep -E or
# bash [[ =~ ]] in the pipeline phases:
#   _GS_ES_PATTERN_DIFF_IGNORE          Phase 5 — suppress "different value" warnings
#   _GS_ES_PATTERN_SCAN_VAR_IGNORE      Phase 3 — suppress variable names from scan output
#   _GS_ES_PATTERN_REVERSE_CHECK_IGNORE Phase 5 Check 3 — dest→scan orphan detection
#   _GS_ES_PATTERN_CONFLICT_IGNORE      Phase 4 — suppress conflicting-defaults detection
#   _GS_ES_PATTERN_ORPHAN_IGNORE        merge phase — suppress local-only var warnings
#   _GS_ES_PATTERN_FORWARD_CHECK_IGNORE Phase 5 Checks 1+2 — scan→env new-usage detection

# Include guard
[[ -n "${_GS_ES_DEFAULTS_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_DEFAULTS_SH_LOADED=1

readonly _GS_ES_VERSION="1.0.0"

# Global shared config associative array — populated by args.sh / _gs_es_main
declare -Ag _GS_ES_CFG

# ── Pattern constants ──────────────────────────────────────────────────────
# Each constant maps 1:1 to a config key and a CLI flag (see args.sh).
# Name scheme: <SCOPE>_IGNORE — vars matching the pattern are silently skipped
# by the named phase/check.

# Phase 5: suppress "different value" warnings for credentials, ports, and
# build-tool vars whose values legitimately diverge between .env and .env.local.
# Config key: diff_ignore_pattern   CLI: --diff-ignore-pattern
_gs_es_pattern_buf='^(ARG )?'
_gs_es_pattern_buf+='('
_gs_es_pattern_buf+='GLOBAL_STACK_GITHUB_TOKEN'
_gs_es_pattern_buf+='|DOCKER_INIT'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_USER_EMAIL'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_USER_NAME'
_gs_es_pattern_buf+='|GLOBAL_STACK_POSTGRES18_DBS'
_gs_es_pattern_buf+='|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS'
_gs_es_pattern_buf+='|GLOBAL_STACK_HTTPS_LOCALHOST_IPS'
_gs_es_pattern_buf+='|GLOBAL_STACK_HTTPS_CONTAINER_IPS'
_gs_es_pattern_buf+='|GLOBAL_STACK_PODMAN_CHANEL'
_gs_es_pattern_buf+='|COMPOSE_FILE'
_gs_es_pattern_buf+='|COMPOSE_BAKE'
_gs_es_pattern_buf+='|BUILDX_EXPERIMENTAL'
_gs_es_pattern_buf+='|BUILDKIT_PROGRESS'
_gs_es_pattern_buf+='|BUILDX_BUILDER'
_gs_es_pattern_buf+='|GLOBAL_STACK_HOST_GATEWAY_IP_MASK'
_gs_es_pattern_buf+='|COMPOSE_FULL_FILE'
_gs_es_pattern_buf+='|BUILDX_BAKE_FILE'
_gs_es_pattern_buf+='|GLOBAL_STACK_HOST_GATEWAY_IP'
_gs_es_pattern_buf+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_SERVERLESS_ACCESS_KEY'
_gs_es_pattern_buf+='|GLOBAL_STACK_(.+)_PORT_[0-9]+(.*)'
_gs_es_pattern_buf+=')'
readonly _GS_ES_PATTERN_DIFF_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf

# Phase 3: suppress VARIABLE NAMES (not file paths) from scan output.
# Package-manager internal vars and per-version aliases that are not top-level
# .env keys — extracting them would produce false "missing" positives.
# Distinct from scan_ignore_pattern which skips FILE PATHS during the scan walk.
# Config key: scan_var_ignore_pattern   CLI: --scan-var-ignore-pattern
_gs_es_pattern_buf='^('
_gs_es_pattern_buf+='(SDKMAN|NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_CONFIG_PACKAGE_'
_gs_es_pattern_buf+='|(SDKMAN|NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_INSTALL_PACKAGE_'
_gs_es_pattern_buf+='|(SDKMAN|NVM|PYENV|PHPBREW|RBENV|FVM)_MODE'
_gs_es_pattern_buf+='|(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_VERSION'
_gs_es_pattern_buf+='|(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_VERSION_AS'
_gs_es_pattern_buf+='|GLOBAL_STACK_RELOAD_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)='
_gs_es_pattern_buf+='|GLOBAL_STACK_NODE_UPGRADE$'
_gs_es_pattern_buf+='|GLOBAL_STACK_CURRENT_VERSION'
_gs_es_pattern_buf+=')'
readonly _GS_ES_PATTERN_SCAN_VAR_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf

# REVERSE check (Check 3): vars in .env.local that have no match in scan output.
# Direction: destination → scan (orphan / stale-entry detection).
# These vars are known to be absent from Docker sources by design (build-tool
# vars, compose internals, secrets) — suppress their missing-from-scan report.
# Config key: reverse_check_ignore_pattern   CLI: --reverse-check-ignore-pattern
_gs_es_pattern_buf='^(ARG )?'
_gs_es_pattern_buf+='('
_gs_es_pattern_buf+='GLOBAL_STACK_GITHUB_TOKEN'
_gs_es_pattern_buf+='|DOCKER_INIT'
_gs_es_pattern_buf+='|COMPOSE_DOCKER_CLI_BUILD'
_gs_es_pattern_buf+='|COMPOSE_PROJECT_NAME'
_gs_es_pattern_buf+='|GLOBAL_STACK_COMPOSE_CLI'
_gs_es_pattern_buf+='|COMPOSE_FILE'
_gs_es_pattern_buf+='|COMPOSE_BAKE'
_gs_es_pattern_buf+='|BUILDX_EXPERIMENTAL'
_gs_es_pattern_buf+='|BUILDKIT_PROGRESS'
_gs_es_pattern_buf+='|BUILDX_BUILDER'
_gs_es_pattern_buf+='|GLOBAL_STACK_HOST_GATEWAY_IP_MASK'
_gs_es_pattern_buf+='|COMPOSE_FULL_FILE'
_gs_es_pattern_buf+='|BUILDX_BAKE_FILE'
_gs_es_pattern_buf+='|COMPOSE_HTTP_TIMEOUT'
_gs_es_pattern_buf+='|COMPOSE_PATH_SEPARATOR'
_gs_es_pattern_buf+='|COMPOSE_REMOVE_ORPHANS'
_gs_es_pattern_buf+='|DOCKER_BUILDKIT'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION'
_gs_es_pattern_buf+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_HOST'
_gs_es_pattern_buf+='|GLOBAL_STACK_RELOAD_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)([0-9_]+|EDGE)'
_gs_es_pattern_buf+='|GLOBAL_STACK_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_DEFAULT'
_gs_es_pattern_buf+='|GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4566'
_gs_es_pattern_buf+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY'
_gs_es_pattern_buf+=')'
readonly _GS_ES_PATTERN_REVERSE_CHECK_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf

# Phase 4: suppress vars from conflicting-defaults detection (multiple distinct
# values seen across .env + scan output for the same key).
# Config key: conflict_ignore_pattern   CLI: --conflict-ignore-pattern
_gs_es_pattern_buf='^(GLOBAL_STACK_ERROR_TOKEN'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_USER_EMAIL'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000'
_gs_es_pattern_buf+='|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS'
_gs_es_pattern_buf+='|GLOBAL_STACK_HTTPS_LOCALHOST_IPS)'
readonly _GS_ES_PATTERN_CONFLICT_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf

# Merge phase: suppress orphaned-var warnings for vars in .env.local that are
# intentionally machine-local (no corresponding entry expected in .env or scan).
# Config key: orphan_ignore_pattern   CLI: --orphan-ignore-pattern
_gs_es_pattern_buf='^(GLOBAL_STACK_LOCAL_(.*))'
readonly _GS_ES_PATTERN_ORPHAN_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf

# FORWARD checks (Checks 1 + 2): vars found in scan output that are absent from
# .env (Check 1) or from .env.local (Check 2).
# Direction: scan → env files (new-usage detection).
# Tool-managed paths, SDK dirs, and secrets are excluded here because they are
# legitimately absent from the env files even when referenced in Docker sources.
# Config key: forward_check_ignore_pattern   CLI: --forward-check-ignore-pattern
_gs_es_pattern_buf='^(ARG )?'
_gs_es_pattern_buf+='('
_gs_es_pattern_buf+='GLOBAL_STACK_GITHUB_TOKEN'
_gs_es_pattern_buf+='|ANDROID_HOME'
_gs_es_pattern_buf+='|ANDROID_NDK_HOME'
_gs_es_pattern_buf+='|ANDROID_SDK_HOME'
_gs_es_pattern_buf+='|ANDROID_SDK_ROOT'
_gs_es_pattern_buf+='|CARGO_HOME'
_gs_es_pattern_buf+='|CAROOT'
_gs_es_pattern_buf+='|COMPOSER_HOME'
_gs_es_pattern_buf+='|COMPOSER_SOURCE'
_gs_es_pattern_buf+='|CYPRESS_CACHE_FOLDER'
_gs_es_pattern_buf+='|DENO_DIR'
_gs_es_pattern_buf+='|DENO_INSTALL'
_gs_es_pattern_buf+='|DENO_INSTALL_ROOT'
_gs_es_pattern_buf+='|FLUTTER_HOME'
_gs_es_pattern_buf+='|FLUTTER_ROOT'
_gs_es_pattern_buf+='|FVM_CACHE_PATH'
_gs_es_pattern_buf+='|FVM_GIT_CACHE_PATH'
_gs_es_pattern_buf+='|FVM_USE_GIT_CACHE'
_gs_es_pattern_buf+='|FVM_FLUTTER_URL'
_gs_es_pattern_buf+='|GRADLE_USER_HOME'
_gs_es_pattern_buf+='|MISE_CACHE_DIR'
_gs_es_pattern_buf+='|MISE_CONFIG_DIR'
_gs_es_pattern_buf+='|MISE_DATA_DIR'
_gs_es_pattern_buf+='|MISE_DEBUG'
_gs_es_pattern_buf+='|MISE_INSTALL_PATH'
_gs_es_pattern_buf+='|MISE_QUIET'
_gs_es_pattern_buf+='|MISE_STATE_DIR'
_gs_es_pattern_buf+='|MISE_VERSION'
_gs_es_pattern_buf+='|NPM_CACHE_DIR'
_gs_es_pattern_buf+='|NVM_DIR'
_gs_es_pattern_buf+='|GLOBAL_STACK_RELOAD_PHP'
_gs_es_pattern_buf+='|PHPBREW_BIN'
_gs_es_pattern_buf+='|GOROOT'
_gs_es_pattern_buf+='|GOPATH'
_gs_es_pattern_buf+='|PHPBREW_HOME'
_gs_es_pattern_buf+='|PHPBREW_RC_ENABLE'
_gs_es_pattern_buf+='|PHPBREW_ROOT'
_gs_es_pattern_buf+='|PHPBREW_SET_PROMPT'
_gs_es_pattern_buf+='|PHPBREW_SKIP_INIT'
_gs_es_pattern_buf+='|PHPBREW_SRC'
_gs_es_pattern_buf+='|PNPM_HOME'
_gs_es_pattern_buf+='|PUB_CACHE'
_gs_es_pattern_buf+='|PYENV_ROOT'
_gs_es_pattern_buf+='|RBENV_ROOT'
_gs_es_pattern_buf+='|RUSTUP_HOME'
_gs_es_pattern_buf+='|SDKMAN_DIR'
_gs_es_pattern_buf+='|SYMFONY_HOME'
_gs_es_pattern_buf+='|YARN_CACHE_FOLDER'
_gs_es_pattern_buf+='|YARN_GLOBAL_FOLDER'
_gs_es_pattern_buf+='|YARN_OFFLINE_MIRROR'
_gs_es_pattern_buf+='|GLOBAL_STACK_DOCKER_USER_CONFIG'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_USERNAME'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_USER_HOME'
_gs_es_pattern_buf+='|GLOBAL_STACK_BASE_GROUP'
_gs_es_pattern_buf+='|PHP_INSTALL_CLI_VARIANTS'
_gs_es_pattern_buf+='|PHP_INSTALL_CLI_OPTIONS'
_gs_es_pattern_buf+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY' # feeds BASE_SERVERLESS_ACCESS_KEY alias; injected via base-env.compose.yaml
_gs_es_pattern_buf+='|GLOBAL_STACK_NODE_UPGRADE$'                             # synthetic compose-level alias (per-tier: NODE24_UPGRADE etc.); not a top-level .env key
_gs_es_pattern_buf+=')'
readonly _GS_ES_PATTERN_FORWARD_CHECK_IGNORE="${_gs_es_pattern_buf}"
unset _gs_es_pattern_buf
