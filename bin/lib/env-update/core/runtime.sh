#!/bin/bash
# Runtime derivation and CLI-first fallback wrapper.
# Derives the correct runtime version (nvm/pyenv/rbenv) from a .env variable name.
# Provides _gs_eu_cli_with_fallback for CLI-first → API-fallback pattern.

set -eEuo pipefail

[[ -n "${_GS_EU_RUNTIME_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_RUNTIME_SH_LOADED=1

# Given a .env variable name, return a "type:VERSION" string identifying which
# runtime to activate. Returns empty string if no runtime can be derived.
#
# Variable prefix → runtime mapping:
#   GLOBAL_STACK_NODE22_*    → "node:${GLOBAL_STACK_NODE22_VERSION}"
#   GLOBAL_STACK_NODE24_*    → "node:${GLOBAL_STACK_NODE24_VERSION}"
#   GLOBAL_STACK_NODEEDGE_*  → "node:${GLOBAL_STACK_NODEEDGE_VERSION}"
#   GLOBAL_STACK_PYTHON3_*   → "python:${GLOBAL_STACK_PYTHON3_VERSION}"
#   GLOBAL_STACK_RUBY3_*     → "ruby:${GLOBAL_STACK_RUBY3_VERSION}"
#   GLOBAL_STACK_RUBY4_*     → "ruby:${GLOBAL_STACK_RUBY4_VERSION}"
#   GLOBAL_STACK_JAVA11_*    → "java:${GLOBAL_STACK_JAVA11_VERSION}"
#   GLOBAL_STACK_JAVA17_*    → "java:${GLOBAL_STACK_JAVA17_VERSION}"
#   GLOBAL_STACK_JAVA25_*    → "java:${GLOBAL_STACK_JAVA25_VERSION}"
#   anything else → ""
_gs_eu_derive_runtime() {
  local env_var="${1}"
  local runtime_version=""

  case "${env_var}" in
    GLOBAL_STACK_NODE22_*)
      runtime_version="${GLOBAL_STACK_NODE22_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "node:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_NODE24_*)
      runtime_version="${GLOBAL_STACK_NODE24_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "node:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_NODEEDGE_*)
      runtime_version="${GLOBAL_STACK_NODEEDGE_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "node:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_PYTHON3_*)
      runtime_version="${GLOBAL_STACK_PYTHON3_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "python:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_RUBY3_*)
      runtime_version="${GLOBAL_STACK_RUBY3_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "ruby:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_RUBY4_*)
      runtime_version="${GLOBAL_STACK_RUBY4_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "ruby:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_JAVA11_*)
      runtime_version="${GLOBAL_STACK_JAVA11_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "java:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_JAVA17_*)
      runtime_version="${GLOBAL_STACK_JAVA17_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "java:${runtime_version}" || echo ""
      ;;
    GLOBAL_STACK_JAVA25_*)
      runtime_version="${GLOBAL_STACK_JAVA25_VERSION:-}"
      [[ -n "${runtime_version}" ]] && echo "java:${runtime_version}" || echo ""
      ;;
    *)
      echo ""
      ;;
  esac
}

# Given a "TYPE:VERSION" runtime string, return shell commands that activate
# that runtime. The caller will eval these commands in a subshell before
# running the CLI tool.
#
# runtime_type format: "TYPE:VERSION" where TYPE is node/python/ruby/java
#
# Returns empty string for java (handled internally by sdkman.sh) or unknown types.
_gs_eu_cli_setup_commands() {
  local runtime_type="${1}"
  local type="${runtime_type%%:*}"
  local version="${runtime_type#*:}"

  case "${type}" in
    node)
      local nvm_dir="${GLOBAL_STACK_NVM_DIR:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/nvm}"
      echo "export NVM_DIR=\"${nvm_dir}\" && source \"${nvm_dir}/nvm.sh\" --no-use && nvm use \"${version}\" >/dev/null 2>&1"
      ;;
    python)
      local pyenv_root="${GLOBAL_STACK_PYENV_ROOT:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/pyenv}"
      echo "export PYENV_ROOT=\"${pyenv_root}\" && export PATH=\"${pyenv_root}/bin:${PATH}\" && eval \"\$(pyenv init -)\" && export PYENV_VERSION=\"${version}\""
      ;;
    ruby)
      local rbenv_root="${GLOBAL_STACK_RBENV_ROOT:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/rbenv}"
      echo "export RBENV_ROOT=\"${rbenv_root}\" && export PATH=\"${rbenv_root}/bin:${PATH}\" && eval \"\$(rbenv init -)\" && rbenv shell \"${version}\""
      ;;
    java)
      # Java is handled internally by sdkman.sh; return empty
      echo ""
      ;;
    *)
      echo ""
      ;;
  esac
}

# CLI-first fetch with API fallback.
#
# Pattern: try CLI → if fails, log debug message, try API.
#
# Usage: _gs_eu_cli_with_fallback cli_fn api_fn env_var identifier current_version offline no_cache channel [...]
#
# Parameters:
#   $1 — cli_fn:  name of the CLI fetch function to call
#   $2 — api_fn:  name of the API fetch function to call
#   $3 — env_var: the .env variable name (used by _gs_eu_derive_runtime)
#   $4..N — remaining args passed verbatim to both cli_fn and api_fn
#           (caller passes: identifier current_version offline no_cache channel ...)
#
# Note: "offline" is the 6th arg overall (position $6), i.e. 3rd in the $4..N block.
_gs_eu_cli_with_fallback() {
  local cli_fn="${1}"
  local api_fn="${2}"
  local env_var="${3}"
  shift 3
  # Remaining args ($@) are passed to both cli_fn and api_fn
  # offline is now at position $3 in the remaining args (original $6)
  local offline="${3:-}"

  # Skip CLI if offline mode
  if [[ "${offline}" == "true" ]]; then
    "${api_fn}" "$@"
    return $?
  fi

  # Derive runtime for this variable
  local runtime=""
  runtime="$(_gs_eu_derive_runtime "${env_var}")"

  # Get setup commands if we have a runtime
  local setup_cmds=""
  if [[ -n "${runtime}" ]]; then
    setup_cmds="$(_gs_eu_cli_setup_commands "${runtime}")"
  fi

  # Create a temp error file for CLI errors
  local tmp_err_file
  tmp_err_file="$(mktemp /tmp/gs-cli-err.XXXXXX)"

  # Run CLI function in a subshell
  local cli_result=""
  local cli_exit=0
  if [[ -n "${setup_cmds}" ]]; then
    cli_result="$(
      set +eEu
      eval "${setup_cmds}" 2>>"${tmp_err_file}" && "${cli_fn}" "$@" 2>>"${tmp_err_file}"
    )" || cli_exit=$?
  else
    cli_result="$(
      "${cli_fn}" "$@" 2>"${tmp_err_file}"
    )" || cli_exit=$?
  fi

  if [[ ${cli_exit} -eq 0 && -n "${cli_result}" ]]; then
    _gs_eu_log_debug "cli" "${env_var}" "CLI fetch succeeded"
    rm -f "${tmp_err_file}"
    echo "${cli_result}"
    return 0
  fi

  # CLI failed — log debug and fall back to API
  local cli_err_msg=""
  cli_err_msg="$(cat "${tmp_err_file}" 2>/dev/null || true)"
  rm -f "${tmp_err_file}"
  _gs_eu_log_debug "cli" "${env_var}" "CLI fetch failed: ${cli_err_msg}; falling back to API"

  "${api_fn}" "$@"
  return $?
}
