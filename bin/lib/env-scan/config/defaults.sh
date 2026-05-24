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
readonly _GS_ES_PATTERN_DIFF_IGNORE='^(ARG )?(GLOBAL_STACK_GITHUB_TOKEN|DOCKER_INIT|GLOBAL_STACK_DOCKER_USER_EMAIL|GLOBAL_STACK_DOCKER_USER_NAME|GLOBAL_STACK_POSTGRES18_DBS|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_HTTPS_CONTAINER_IPS|GLOBAL_STACK_PODMAN_CHANEL|COMPOSE_FILE|COMPOSE_BAKE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|GLOBAL_STACK_HOST_GATEWAY_IP_MASK|COMPOSE_FULL_FILE|BUILDX_BAKE_FILE|GLOBAL_STACK_HOST_GATEWAY_IP|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY|GLOBAL_STACK_BASE_SERVERLESS_ACCESS_KEY|GLOBAL_STACK_(.+)_PORT_[0-9]+(.*))'

# Phase 3: suppress VARIABLE NAMES (not file paths) from scan output.
# Package-manager internal vars and per-version aliases that are not top-level
# .env keys — extracting them would produce false "missing" positives.
# Distinct from scan_ignore_pattern which skips FILE PATHS during the scan walk.
# Config key: scan_var_ignore_pattern   CLI: --scan-var-ignore-pattern
readonly _GS_ES_PATTERN_SCAN_VAR_IGNORE='^(NODE_CONFIG_PACKAGE_|NODE_INSTALL_PACKAGE_|PHP_CONFIG_PACKAGE|PHP_INSTALL_PACKAGE|SDKMAN_CONFIG_PACKAGE|SDKMAN_INSTALL_PACKAGE|PYTHON_CONFIG_PACKAGE_|PYTHON_INSTALL_PACKAGE_|RUBY_CONFIG_PACKAGE_|RUBY_INSTALL_PACKAGE_|JAVA_VERSION|JAVA_VERSION_AS|NODE_VERSION|NODE_VERSION_AS|PYTHON_VERSION_AS|RUBY_VERSION_AS|NVM_MODE|GLOBAL_STACK_NODE_UPGRADE$|GLOBAL_STACK_PYTHON_VERSION|GLOBAL_STACK_RUBY_VERSION|GLOBAL_STACK_CURRENT_VERSION|GLOBAL_STACK_IMAGE_MARIADB_VERSION|GLOBAL_STACK_IMAGE_MONGO_VERSION|GLOBAL_STACK_IMAGE_MYSQL_VERSION|GLOBAL_STACK_IMAGE_POSTGRES_VERSION|GLOBAL_STACK_SHOW_WAITING|GLOBAL_STACK_RELOAD_JAVA|GLOBAL_STACK_RELOAD_NODE|GLOBAL_STACK_RELOAD_PYTHON|GLOBAL_STACK_RELOAD_RUBY|GLOBAL_STACK_RELOAD_FLUTTER)'

# REVERSE check (Check 3): vars in .env.local that have no match in scan output.
# Direction: destination → scan (orphan / stale-entry detection).
# These vars are known to be absent from Docker sources by design (build-tool
# vars, compose internals, secrets) — suppress their missing-from-scan report.
# Config key: reverse_check_ignore_pattern   CLI: --reverse-check-ignore-pattern
readonly _GS_ES_PATTERN_REVERSE_CHECK_IGNORE='^(ARG )?(GLOBAL_STACK_GITHUB_TOKEN|DOCKER_INIT|COMPOSE_DOCKER_CLI_BUILD|COMPOSE_PROJECT_NAME|GLOBAL_STACK_COMPOSE_CLI|COMPOSE_FILE|COMPOSE_BAKE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|GLOBAL_STACK_HOST_GATEWAY_IP_MASK|COMPOSE_FULL_FILE|BUILDX_BAKE_FILE|COMPOSE_HTTP_TIMEOUT|COMPOSE_PATH_SEPARATOR|COMPOSE_REMOVE_ORPHANS|DOCKER_BUILDKIT|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION|GLOBAL_STACK_SERVERLESS_FRAMEWORK_HOST|GLOBAL_STACK_RELOAD_PHP[0-9]+_[0-9]+|GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4566|GLOBAL_STACK_PHP_DEFAULT|GLOBAL_STACK_JAVA_DEFAULT|GLOBAL_STACK_NODE_DEFAULT|GLOBAL_STACK_PYTHON_DEFAULT|GLOBAL_STACK_RUBY_DEFAULT|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY)'

# Phase 4: suppress vars from conflicting-defaults detection (multiple distinct
# values seen across .env + scan output for the same key).
# Config key: conflict_ignore_pattern   CLI: --conflict-ignore-pattern
readonly _GS_ES_PATTERN_CONFLICT_IGNORE='^(GLOBAL_STACK_ERROR_TOKEN|GLOBAL_STACK_DOCKER_USER_EMAIL|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS)'

# Merge phase: suppress orphaned-var warnings for vars in .env.local that are
# intentionally machine-local (no corresponding entry expected in .env or scan).
# Config key: orphan_ignore_pattern   CLI: --orphan-ignore-pattern
readonly _GS_ES_PATTERN_ORPHAN_IGNORE='^(GLOBAL_STACK_LOCAL_(.*))'

# FORWARD checks (Checks 1 + 2): vars found in scan output that are absent from
# .env (Check 1) or from .env.local (Check 2).
# Direction: scan → env files (new-usage detection).
# Tool-managed paths, SDK dirs, and secrets are excluded here because they are
# legitimately absent from the env files even when referenced in Docker sources.
# Config key: forward_check_ignore_pattern   CLI: --forward-check-ignore-pattern
readonly _GS_ES_PATTERN_FORWARD_CHECK_IGNORE='^(ARG )?(GLOBAL_STACK_GITHUB_TOKEN|ANDROID_HOME|ANDROID_NDK_HOME|ANDROID_SDK_HOME|ANDROID_SDK_ROOT|CARGO_HOME|CAROOT|COMPOSER_HOME|COMPOSER_SOURCE|CYPRESS_CACHE_FOLDER|DENO_DIR|DENO_INSTALL|DENO_INSTALL_ROOT|FLUTTER_HOME|FLUTTER_ROOT|FVM_CACHE_PATH|FVM_GIT_CACHE_PATH|FVM_USE_GIT_CACHE|FVM_FLUTTER_URL|GRADLE_USER_HOME|MISE_CACHE_DIR|MISE_CONFIG_DIR|MISE_DATA_DIR|MISE_DEBUG|MISE_INSTALL_PATH|MISE_QUIET|MISE_STATE_DIR|MISE_VERSION|NPM_CACHE_DIR|NVM_DIR|GLOBAL_STACK_RELOAD_PHP|PHPBREW_BIN|GOROOT|GOPATH|PHPBREW_HOME|PHPBREW_RC_ENABLE|PHPBREW_ROOT|PHPBREW_SET_PROMPT|PHPBREW_SKIP_INIT|PHPBREW_SRC|PNPM_HOME|PUB_CACHE|PYENV_ROOT|RBENV_ROOT|RUSTUP_HOME|SDKMAN_DIR|SYMFONY_HOME|YARN_CACHE_FOLDER|YARN_GLOBAL_FOLDER|YARN_OFFLINE_MIRROR|GLOBAL_STACK_DOCKER_USER_CONFIG|GLOBAL_STACK_BASE_USERNAME|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR|GLOBAL_STACK_BASE_USER_HOME|GLOBAL_STACK_BASE_GROUP|PHP_INSTALL_CLI_VARIANTS|PHP_INSTALL_CLI_OPTIONS|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY|GLOBAL_STACK_NODE_UPGRADE$)' # FRAMEWORK var feeds BASE_SERVERLESS_ACCESS_KEY alias in .env.local; injected into all services via base-env.compose.yaml; GLOBAL_STACK_NODE_UPGRADE is a synthetic compose-level alias (set per-tier via GLOBAL_STACK_NODE22_UPGRADE etc.) not a top-level .env key
