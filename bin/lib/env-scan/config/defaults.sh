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

# Global shared config associative array — populated by args.sh / gs_es_main
declare -Ag _GS_ES_CFG

# ── Pattern constants ──────────────────────────────────────────────────────
# Each constant maps 1:1 to a config key and a CLI flag (see args.sh).
# Name scheme: <SCOPE>_IGNORE — vars matching the pattern are silently skipped
# by the named phase/check.

# Phase 5: suppress "different value" warnings for credentials, ports, and
# build-tool vars whose values legitimately diverge between .env and .env.local.
# Config key: diff_ignore_pattern   CLI: --diff-ignore-pattern
_p='^(ARG )?'
_p+='('
_p+='GLOBAL_STACK_GITHUB_TOKEN'
_p+='|DOCKER_INIT'
_p+='|GLOBAL_STACK_DOCKER_USER_EMAIL'
_p+='|GLOBAL_STACK_DOCKER_USER_NAME'
_p+='|GLOBAL_STACK_POSTGRES18_DBS'
_p+='|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS'
_p+='|GLOBAL_STACK_HTTPS_LOCALHOST_IPS'
_p+='|GLOBAL_STACK_HTTPS_CONTAINER_IPS'
_p+='|GLOBAL_STACK_PODMAN_CHANEL'
_p+='|COMPOSE_FILE'
_p+='|COMPOSE_BAKE'
_p+='|BUILDX_EXPERIMENTAL'
_p+='|BUILDKIT_PROGRESS'
_p+='|BUILDX_BUILDER'
_p+='|GLOBAL_STACK_HOST_GATEWAY_IP_MASK'
_p+='|COMPOSE_FULL_FILE'
_p+='|BUILDX_BAKE_FILE'
_p+='|GLOBAL_STACK_HOST_GATEWAY_IP'
_p+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY'
_p+='|GLOBAL_STACK_BASE_SERVERLESS_ACCESS_KEY'
_p+='|GLOBAL_STACK_(.+)_PORT_[0-9]+(.*)'
_p+=')'
readonly _GS_ES_PATTERN_DIFF_IGNORE="${_p}"
unset _p

# Phase 3: suppress VARIABLE NAMES (not file paths) from scan output.
# Package-manager internal vars and per-version aliases that are not top-level
# .env keys — extracting them would produce false "missing" positives.
# Distinct from scan_ignore_pattern which skips FILE PATHS during the scan walk.
# Config key: scan_var_ignore_pattern   CLI: --scan-var-ignore-pattern
_p='^('
_p+='(SDKMAN|NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_CONFIG_PACKAGE_'
_p+='|(SDKMAN|NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_INSTALL_PACKAGE_'
_p+='|(SDKMAN|NVM|PYENV|PHPBREW|RBENV|FVM)_MODE'
_p+='|(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_VERSION'
_p+='|(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_VERSION_AS'
_p+='|GLOBAL_STACK_RELOAD_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)$'
_p+='|GLOBAL_STACK_NODE_UPGRADE$'
_p+='|GLOBAL_STACK_CURRENT_VERSION'
_p+=')'
readonly _GS_ES_PATTERN_SCAN_VAR_IGNORE="${_p}"
unset _p

# REVERSE check (Check 3): vars in .env.local that have no match in scan output.
# Direction: destination → scan (orphan / stale-entry detection).
# These vars are known to be absent from Docker sources by design (build-tool
# vars, compose internals, secrets) — suppress their missing-from-scan report.
# Config key: reverse_check_ignore_pattern   CLI: --reverse-check-ignore-pattern
_p='^(ARG )?'
_p+='('
_p+='GLOBAL_STACK_GITHUB_TOKEN'
_p+='|DOCKER_INIT'
_p+='|COMPOSE_DOCKER_CLI_BUILD'
_p+='|COMPOSE_PROJECT_NAME'
_p+='|GLOBAL_STACK_COMPOSE_CLI'
_p+='|COMPOSE_FILE'
_p+='|COMPOSE_BAKE'
_p+='|BUILDX_EXPERIMENTAL'
_p+='|BUILDKIT_PROGRESS'
_p+='|BUILDX_BUILDER'
_p+='|GLOBAL_STACK_HOST_GATEWAY_IP_MASK'
_p+='|COMPOSE_FULL_FILE'
_p+='|BUILDX_BAKE_FILE'
_p+='|COMPOSE_HTTP_TIMEOUT'
_p+='|COMPOSE_PATH_SEPARATOR'
_p+='|COMPOSE_REMOVE_ORPHANS'
_p+='|DOCKER_BUILDKIT'
_p+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME'
_p+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION'
_p+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_HOST'
_p+='|GLOBAL_STACK_RELOAD_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)([0-9_]+|EDGE)'
_p+='|GLOBAL_STACK_(NODE|PHP|PYTHON|RUBY|JAVA|FLUTTER)_DEFAULT'
_p+='|GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4566'
_p+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY'
_p+=')'
readonly _GS_ES_PATTERN_REVERSE_CHECK_IGNORE="${_p}"
unset _p

# Phase 4: suppress vars from conflicting-defaults detection (multiple distinct
# values seen across .env + scan output for the same key).
# Config key: conflict_ignore_pattern   CLI: --conflict-ignore-pattern
_p='^(GLOBAL_STACK_ERROR_TOKEN'
_p+='|GLOBAL_STACK_DOCKER_USER_EMAIL'
_p+='|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000'
_p+='|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS'
_p+='|GLOBAL_STACK_HTTPS_LOCALHOST_IPS)'
readonly _GS_ES_PATTERN_CONFLICT_IGNORE="${_p}"
unset _p

# Merge phase: suppress orphaned-var warnings for vars in .env.local that are
# intentionally machine-local (no corresponding entry expected in .env or scan).
# Config key: orphan_ignore_pattern   CLI: --orphan-ignore-pattern
_p='^(GLOBAL_STACK_LOCAL_(.*))'
readonly _GS_ES_PATTERN_ORPHAN_IGNORE="${_p}"
unset _p

# FORWARD checks (Checks 1 + 2): vars found in scan output that are absent from
# .env (Check 1) or from .env.local (Check 2).
# Direction: scan → env files (new-usage detection).
# Tool-managed paths, SDK dirs, and secrets are excluded here because they are
# legitimately absent from the env files even when referenced in Docker sources.
# Config key: forward_check_ignore_pattern   CLI: --forward-check-ignore-pattern
_p='^(ARG )?'
_p+='('
_p+='GLOBAL_STACK_GITHUB_TOKEN'
_p+='|ANDROID_HOME'
_p+='|ANDROID_NDK_HOME'
_p+='|ANDROID_SDK_HOME'
_p+='|ANDROID_SDK_ROOT'
_p+='|CARGO_HOME'
_p+='|CAROOT'
_p+='|COMPOSER_HOME'
_p+='|COMPOSER_SOURCE'
_p+='|CYPRESS_CACHE_FOLDER'
_p+='|DENO_DIR'
_p+='|DENO_INSTALL'
_p+='|DENO_INSTALL_ROOT'
_p+='|FLUTTER_HOME'
_p+='|FLUTTER_ROOT'
_p+='|FVM_CACHE_PATH'
_p+='|FVM_GIT_CACHE_PATH'
_p+='|FVM_USE_GIT_CACHE'
_p+='|FVM_FLUTTER_URL'
_p+='|GRADLE_USER_HOME'
_p+='|MISE_CACHE_DIR'
_p+='|MISE_CONFIG_DIR'
_p+='|MISE_DATA_DIR'
_p+='|MISE_DEBUG'
_p+='|MISE_INSTALL_PATH'
_p+='|MISE_QUIET'
_p+='|MISE_STATE_DIR'
_p+='|MISE_VERSION'
_p+='|NPM_CACHE_DIR'
_p+='|NVM_DIR'
_p+='|GLOBAL_STACK_RELOAD_PHP'
_p+='|PHPBREW_BIN'
_p+='|GOROOT'
_p+='|GOPATH'
_p+='|PHPBREW_HOME'
_p+='|PHPBREW_RC_ENABLE'
_p+='|PHPBREW_ROOT'
_p+='|PHPBREW_SET_PROMPT'
_p+='|PHPBREW_SKIP_INIT'
_p+='|PHPBREW_SRC'
_p+='|PNPM_HOME'
_p+='|PUB_CACHE'
_p+='|PYENV_ROOT'
_p+='|RBENV_ROOT'
_p+='|RUSTUP_HOME'
_p+='|SDKMAN_DIR'
_p+='|SYMFONY_HOME'
_p+='|YARN_CACHE_FOLDER'
_p+='|YARN_GLOBAL_FOLDER'
_p+='|YARN_OFFLINE_MIRROR'
_p+='|GLOBAL_STACK_DOCKER_USER_CONFIG'
_p+='|GLOBAL_STACK_BASE_USERNAME'
_p+='|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS'
_p+='|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR'
_p+='|GLOBAL_STACK_BASE_USER_HOME'
_p+='|GLOBAL_STACK_BASE_GROUP'
_p+='|PHP_INSTALL_CLI_VARIANTS'
_p+='|PHP_INSTALL_CLI_OPTIONS'
_p+='|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY' # feeds BASE_SERVERLESS_ACCESS_KEY alias; injected via base-env.compose.yaml
_p+='|GLOBAL_STACK_NODE_UPGRADE$'                             # synthetic compose-level alias (per-tier: NODE22_UPGRADE etc.); not a top-level .env key
_p+=')'
readonly _GS_ES_PATTERN_FORWARD_CHECK_IGNORE="${_p}"
unset _p
