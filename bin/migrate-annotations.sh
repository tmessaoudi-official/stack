#!/bin/bash
# migrate-annotations.sh — One-shot migration of legacy @todo check-updates
# annotations in .env to the new unified type:identifier format.
#
# Usage:
#   bin/migrate-annotations.sh [OPTIONS]
#
# Options:
#   --dry-run    Show what would change, don't modify
#   --no-backup  Skip creating .env.bak (default: backup is created)
#   --help

set -eEuo pipefail

# --------------------------------------------------------------------------
# Script location
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly STACK_DIR
LIB_DIR="${SCRIPT_DIR}/lib/check-updates"
readonly LIB_DIR
ENV_FILE="${STACK_DIR}/.env"
readonly ENV_FILE

# --------------------------------------------------------------------------
# Source required libraries
# --------------------------------------------------------------------------
# shellcheck source=lib/check-updates/core/report.sh
source "${LIB_DIR}/core/report.sh"
# shellcheck source=lib/check-updates/config/type_map.sh
source "${LIB_DIR}/config/type_map.sh"
# shellcheck source=lib/check-updates/config/codename_map.sh
source "${LIB_DIR}/config/codename_map.sh"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
MIGRATE_DRY_RUN="false"
MIGRATE_BACKUP="true"
_GS_CU_MIGRATE_SHOW_ALREADY_MIGRATED="false"

# --------------------------------------------------------------------------
# Known depends-on relationships (hardcoded map)
# --------------------------------------------------------------------------
declare -A _GS_CU_MIGRATE_DEPENDS_ON_MAP=(
  ["GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION"]="depends-on:GLOBAL_STACK_SONARQUBE_VERSION:major"
)

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
_gs_cu_migrate_show_help() {
  cat <<'EOF'
bin/migrate-annotations.sh — Migrate legacy .env annotations to new format

Usage:
  bin/migrate-annotations.sh [OPTIONS]

Options:
  --dry-run               Show what would change, don't modify .env
  --no-backup             Skip creating .env.bak (default: backup is created)
  --show-already-migrated (-s)  List lines already in new format
  --help                  Show this help

This script rewrites all @todo check-updates annotations in .env from the
legacy URL-based format to the new structured type:identifier format.

Example transformations:
  Before: # @todo check-updates axllent/mailpit https://hub.docker.com/r/axllent/mailpit/tags v1.29.3
  After:  # @todo check-updates dockerhub:axllent/mailpit v1.29.3

  Before: # @todo check-updates https://github.com/golang/go/tags 1.26.1
  After:  # @todo check-updates github:golang/go 1.26.1

  Before: # @todo (override) check-updates dpage/pgadmin4 https://hub.docker.com/r/dpage/pgadmin4/tags 9.13.0
  After:  # @todo check-updates (override) dockerhub:dpage/pgadmin4 9.13.0

  Before: # @todo check-updates https://github.com/php/php-src/tags 8.2.30
  After:  # @todo check-updates github:php/php-src:8.2 8.2.30

  Before: # @todo check-updates https://pecl.php.net/package/imagick 3.8.1 (php >= 8.1)
  After:  # @todo check-updates pecl:imagick 3.8.1 (php >= 8.1)
EOF
}

_gs_cu_migrate_parse_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)                MIGRATE_DRY_RUN="true" ;;
      --no-backup)              MIGRATE_BACKUP="false" ;;
      --show-already-migrated|-s) _GS_CU_MIGRATE_SHOW_ALREADY_MIGRATED="true" ;;
      --help)                   _gs_cu_migrate_show_help; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "${arg}" >&2
        _gs_cu_migrate_show_help >&2
        exit 1
        ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Resolve higher semver from a "A | B" or "A | B (compat)" string
# Returns the higher version of the two sides
# --------------------------------------------------------------------------
_gs_cu_resolve_pipe_version() {
  local combined="${1}"
  # Extract both sides of the pipe
  local lhs="${combined%%|*}"
  local rhs="${combined##*|}"

  # Strip outer whitespace
  lhs="${lhs#"${lhs%%[! ]*}"}"
  lhs="${lhs%"${lhs##*[! ]}"}"
  rhs="${rhs#"${rhs%%[! ]*}"}"
  rhs="${rhs%"${rhs##*[! ]}"}"

  # Extract the last version-like token from each side (keep full token including pre-release suffix)
  local lhs_tok rhs_tok
  lhs_tok="$(printf '%s' "${lhs}" | grep -oE 'v?[0-9]+\.[0-9]+[.0-9a-zA-Z-]*' | tail -1 || echo "")"
  rhs_tok="$(printf '%s' "${rhs}" | grep -oE 'v?[0-9]+\.[0-9]+[.0-9a-zA-Z-]*' | tail -1 || echo "")"

  if [[ -z "${lhs_tok}" && -z "${rhs_tok}" ]]; then echo ""; return 0; fi
  if [[ -z "${lhs_tok}" ]]; then echo "${rhs_tok}"; return 0; fi
  if [[ -z "${rhs_tok}" ]]; then echo "${lhs_tok}"; return 0; fi

  # A token is a pre-release if it contains letters after the numeric part (a/b/rc/alpha/beta)
  local _re_prerelease='[0-9][a-zA-Z]|-(alpha|beta|rc|a|b)[0-9]'
  local lhs_is_pre=false rhs_is_pre=false
  [[ "${lhs_tok}" =~ ${_re_prerelease} ]] && lhs_is_pre=true
  [[ "${rhs_tok}" =~ ${_re_prerelease} ]] && rhs_is_pre=true

  # Prefer stable over pre-release regardless of version number
  if [[ "${lhs_is_pre}" == "false" && "${rhs_is_pre}" == "true" ]]; then
    echo "${lhs_tok}"; return 0
  fi
  if [[ "${rhs_is_pre}" == "false" && "${lhs_is_pre}" == "true" ]]; then
    echo "${rhs_tok}"; return 0
  fi

  # Both same stability type — return the higher semver
  local lhs_ver rhs_ver
  lhs_ver="$(printf '%s' "${lhs_tok}" | grep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1)"
  rhs_ver="$(printf '%s' "${rhs_tok}" | grep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1)"
  local higher
  higher="$(printf '%s\n%s\n' "${lhs_ver}" "${rhs_ver}" | sort -V | tail -1)"
  if [[ "${higher}" == "${rhs_ver}" && "${lhs_ver}" != "${rhs_ver}" ]]; then
    echo "${rhs_tok}"
  else
    echo "${lhs_tok}"
  fi
}

# --------------------------------------------------------------------------
# Normalize a compat hint like "php >= 7.0.0" → "compat:php>=7.0"
# --------------------------------------------------------------------------
_gs_cu_normalize_compat_hint() {
  local hint="${1}"
  local lower="${hint,,}"

  # Pattern: runtime operator version
  local _re_compat='^([a-z_]+)[[:space:]]*(>=|<=|>|<|==|=)[[:space:]]*([0-9]+\.[0-9]+)'
  if [[ "${lower}" =~ ${_re_compat} ]]; then
    local runtime="${BASH_REMATCH[1]}"
    local op="${BASH_REMATCH[2]}"
    local ver="${BASH_REMATCH[3]}"
    # Normalize op: == → =
    op="${op//==/=}"
    echo "compat:${runtime}${op}${ver}"
    return 0
  fi

  echo "${hint}"
}

# --------------------------------------------------------------------------
# Pre-scan to detect adjacent pecl-git pairs
# Builds _GS_CU_MIGRATE_PECL_GIT_PAIRS associative array
# Keys: annotation line numbers, values: "REPLACE:git_url:sha:ext_name:compat" or "DROP"
# --------------------------------------------------------------------------
declare -gA _GS_CU_MIGRATE_PECL_GIT_PAIRS=()
declare -ga _GS_CU_MIGRATE_ORIG_LINES=()
declare -ga _GS_CU_MIGRATE_MIGRATED_LINES=()
declare -ga _GS_CU_MIGRATE_CHANGE_LNUMS=()
declare -gi _GS_CU_MIGRATE_ALREADY_COUNT=0
declare -ga _GS_CU_MIGRATE_ALREADY_LINES=()

_gs_cu_migrate_pre_scan_pecl_git_pairs() {
  local line_number=0
  local pending_git_url=""
  local pending_git_sha=""
  local pending_git_line=0
  local in_pair_scan="false"

  local _re_git_url
  _re_git_url='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url[[:space:]]+(https://github[^[:space:]]+)[[:space:]]+(branch[[:space:]]+or[[:space:]]+commit[[:space:]]+)?([a-f0-9]+)'

  local _re_pecl_url
  _re_pecl_url='^[[:space:]]*#.*@todo.*check-updates.*https://pecl\.php\.net/package/([^[:space:]]+)[[:space:]]+([0-9][^[:space:]]*)'

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    if [[ "${line}" =~ ${_re_git_url} ]]; then
      pending_git_url="${BASH_REMATCH[1]}"
      pending_git_sha="${BASH_REMATCH[3]}"
      pending_git_line="${line_number}"
      in_pair_scan="true"
      continue
    fi

    if [[ "${in_pair_scan}" == "true" ]]; then
      # Allow blank lines, comment-only lines, and CONFIG_PACKAGE var assignments
      # between the "could be a repo url" line and the "check-updates pecl" line
      if [[ "${line}" =~ @todo.*check-updates && "${line}" =~ ${_re_pecl_url} ]]; then
        local ext_name="${BASH_REMATCH[1]}"
        # Use | as separator (safe: can't appear in a git URL or sha)
        _GS_CU_MIGRATE_PECL_GIT_PAIRS[${pending_git_line}]="DROP"
        _GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]="REPLACE|${pending_git_url}|${pending_git_sha}|${ext_name}"
        in_pair_scan="false"
        pending_git_url=""
        pending_git_sha=""
        pending_git_line=0
        continue
      fi
      # Another "could be a repo url" line resets the window (next pair starts)
      if [[ "${line}" =~ ${_re_git_url} ]]; then
        pending_git_url="${BASH_REMATCH[1]}"
        pending_git_sha="${BASH_REMATCH[3]}"
        pending_git_line="${line_number}"
        continue
      fi
      # Any other @todo check-updates (non-PECL) ends the window
      if [[ "${line}" =~ @todo.*check-updates && ! "${line}" =~ pecl\.php\.net ]]; then
        in_pair_scan="false"
        pending_git_url=""
        pending_git_sha=""
        pending_git_line=0
      fi
      # Blank lines, comment lines, and variable assignments: stay in scan window
      continue
    fi
  done < "${ENV_FILE}"
}

# --------------------------------------------------------------------------
# Pre-scan to detect adjacent "@todo change ... everywhere" + "@todo check-updates" pairs
# Keys: line number of the "change" line → "DROP" (paired) or "STANDALONE:VAR_NAME"
#       line number of the "check-updates" line → "ADD_PROPAGATE" (add (propagate) flag)
# --------------------------------------------------------------------------
declare -gA _GS_CU_MIGRATE_PROPAGATE_PAIRS=()

_gs_cu_migrate_pre_scan_propagate_pairs() {
  local line_number=0
  local pending_change_line=0
  local pending_change_varname=""

  local _re_todo_change
  _re_todo_change='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+(change[[:space:]]+this[[:space:]]+|change[[:space:]]+)ARG[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=[^[:space:]].*everywhere'

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    if [[ "${line}" =~ ${_re_todo_change} ]]; then
      pending_change_line="${line_number}"
      pending_change_varname="${BASH_REMATCH[2]}"
      continue
    fi

    if [[ "${pending_change_line}" -gt 0 ]]; then
      # Allow blank lines and comment-only lines (not @todo annotations) between pair members
      if [[ -z "${line}" || ( "${line}" =~ ^[[:space:]]*# && ! "${line}" =~ @todo ) ]]; then
        continue
      fi
      # Paired with a check-updates annotation?
      if [[ "${line}" =~ @todo.*check-updates ]]; then
        _GS_CU_MIGRATE_PROPAGATE_PAIRS[${pending_change_line}]="DROP"
        _GS_CU_MIGRATE_PROPAGATE_PAIRS[${line_number}]="ADD_PROPAGATE"
      else
        # Standalone (no check-updates partner)
        _GS_CU_MIGRATE_PROPAGATE_PAIRS[${pending_change_line}]="STANDALONE:${pending_change_varname}"
      fi
      pending_change_line=0
      pending_change_varname=""
    fi
  done < "${ENV_FILE}"

  # Any remaining pending_change_line with no partner is standalone
  if [[ "${pending_change_line}" -gt 0 ]]; then
    _GS_CU_MIGRATE_PROPAGATE_PAIRS[${pending_change_line}]="STANDALONE:${pending_change_varname}"
  fi
}

# --------------------------------------------------------------------------
# Build a pecl-git merged annotation from pair data
# --------------------------------------------------------------------------
_gs_cu_build_pecl_git_annotation() {
  local prefix="${1}"
  local todo_prefix="${2}"
  local flags="${3}"
  local git_url="${4}"
  local ext_name="${5}"
  local version="${6}"
  local hint="${7:-}"

  local flags_str=""
  [[ -n "${flags}" ]] && flags_str="${flags} "

  local hint_str=""
  [[ -n "${hint}" ]] && hint_str=" (${hint})"

  local pecl_ref_str=""
  # ext_name from pecl URL might differ from repo name — add pecl-ref if needed
  local repo_name="${git_url##*/}"
  repo_name="${repo_name,,}"
  repo_name="${repo_name#ext-}"
  if [[ "${repo_name}" != "${ext_name,,}" ]]; then
    pecl_ref_str=" (pecl-ref:${ext_name})"
  fi

  printf '%s%scheck-updates %specl-git:%s %s%s%s\n' \
    "${prefix}" "${todo_prefix}" "${flags_str}" \
    "${git_url}" "${version}" "${hint_str}" "${pecl_ref_str}"
}

# --------------------------------------------------------------------------
# Migration transformation functions
# --------------------------------------------------------------------------

# Given a raw annotation line, produce the migrated version.
# Returns the new line (echoed) or the original line if no migration needed/possible.
_gs_cu_migrate_annotation_line() {
  local line="${1}"
  local line_number="${2:-0}"

  # Must contain @todo ... check-updates
  if [[ ! "${line}" =~ @todo.*check-updates ]]; then
    echo "${line}"
    return 0
  fi

  # Check for DROP (git-url pair lines handled by pre-scan)
  if [[ -n "${_GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]+x}" ]]; then
    local pair_action="${_GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]}"
    if [[ "${pair_action}" == "DROP" ]]; then
      # Return empty to signal this line should be deleted
      echo "__DROP_LINE__"
      return 0
    fi
    if [[ "${pair_action}" =~ ^REPLACE: ]]; then
      # Will be handled in the REPLACE path below
      : # fall through to migration
    fi
  fi

  # Already in new format? Require type to follow immediately after check-updates + optional flags
  local _re_already_migrated
  _re_already_migrated='^[[:space:]]*#.*@todo[[:space:]]+(check-updates|propagate)[[:space:]]+(\([^)]+\)[[:space:]]+)*(dockerhub:|quay:|github:|npm:|pecl:|pecl-git:|sdkman:|sdkmanager:|pypi:|url:|[A-Z_][A-Z0-9_]+$)'
  if [[ "${line}" =~ ${_re_already_migrated} ]]; then
    _gs_cu_log_debug "Already migrated: ${line}"
    echo "${line}"
    return 0
  fi

  # Extract leading whitespace + comment prefix
  local prefix=""
  if [[ "${line}" =~ ^([[:space:]]*#[[:space:]]*) ]]; then
    prefix="${BASH_REMATCH[1]}"
  fi

  # Extract everything after the comment prefix
  local content="${line#"${prefix}"}"

  # Extract @todo prefix
  local todo_prefix=""
  local check_updates_content=""
  if [[ "${content}" =~ ^(@todo[[:space:]]+)(.*)$ ]]; then
    todo_prefix="${BASH_REMATCH[1]}"
    check_updates_content="${BASH_REMATCH[2]}"
  fi

  # Extract flags in parens before or after check-updates
  local flags=""
  local remaining="${check_updates_content}"
  local _flag_re='^[(]([^)]+)[)][[:space:]]*(.*)'

  while [[ "${remaining}" =~ ${_flag_re} ]]; do
    local flag_val="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
    flag_val="${flag_val,,}"
    flag_val="${flag_val//overriden/override}"
    flag_val="${flag_val//overridden/override}"
    flags+="(${flag_val}) "
  done

  # Strip "check-updates" keyword
  remaining="${remaining#check-updates}"
  remaining="${remaining# }"

  # Handle flags after check-updates keyword too
  while [[ "${remaining}" =~ ${_flag_re} ]]; do
    local flag_val="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
    flag_val="${flag_val,,}"
    flag_val="${flag_val//overriden/override}"
    flag_val="${flag_val//overridden/override}"
    flags+="(${flag_val}) "
  done
  flags="${flags% }"

  # -----------------------------------------------------------------------
  # Handle pecl-git REPLACE (paired annotations)
  # -----------------------------------------------------------------------
  if [[ -n "${_GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]+x}" ]]; then
    local pair_action="${_GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]}"
    if [[ "${pair_action}" =~ ^REPLACE\|(.+)\|([a-f0-9]+)\|([^|]+)$ ]]; then
      local git_url="${BASH_REMATCH[1]}"
      local git_sha="${BASH_REMATCH[2]}"
      local ext_name="${BASH_REMATCH[3]}"
      # Extract compat hint from the PECL annotation remaining (e.g. "php >= 7.0.0")
      local compat_hint=""
      local _re_compat_paren='[(](php[^)]+)[)]'
      if [[ "${remaining}" =~ ${_re_compat_paren} ]]; then
        compat_hint="$(_gs_cu_normalize_compat_hint "${BASH_REMATCH[1]}")"
      fi
      echo "$(_gs_cu_build_pecl_git_annotation "${prefix}" "${todo_prefix}" "${flags}" "${git_url}" "${ext_name}" "${git_sha}" "${compat_hint}")"
      return 0
    fi
  fi

  # -----------------------------------------------------------------------
  # Extract trailing parenthetical tokens before main tokenizer
  # This prevents stability keywords and compat hints from corrupting the version
  # -----------------------------------------------------------------------
  local extracted_parens=()
  local cleaned_remaining="${remaining}"
  local _re_trailing_paren='^(.*)[[:space:]]*[(]([^)]+)[)]([[:space:]]*)$'
  while [[ "${cleaned_remaining}" =~ ${_re_trailing_paren} ]]; do
    extracted_parens+=("${BASH_REMATCH[2]}")
    cleaned_remaining="${BASH_REMATCH[1]}"
    # Stop if nothing left before the paren
    cleaned_remaining="${cleaned_remaining%"${cleaned_remaining##*[! ]}"}"
    [[ -z "${cleaned_remaining}" ]] && break
  done
  remaining="${cleaned_remaining}"

  # -----------------------------------------------------------------------
  # Handle sdkmanager pattern
  # -----------------------------------------------------------------------
  if [[ "${remaining}" =~ sdkmanager.*grep[[:space:]]+([^[:space:]|]+)[[:space:]]*--[[:space:]]*([^[:space:]]+) ]]; then
    local component="${BASH_REMATCH[1]}"
    local version="${BASH_REMATCH[2]}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %ssdkmanager:%s %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${component}" "${version}"
    return 0
  fi

  # -----------------------------------------------------------------------
  # Handle JAVA_VERSION pattern (SDKMAN java with major)
  # -----------------------------------------------------------------------
  local _re_java_version='^GLOBAL_STACK_JAVA([0-9]+)_VERSION[[:space:]]+([^[:space:]]+)'
  if [[ "${remaining}" =~ ${_re_java_version} ]]; then
    local java_major="${BASH_REMATCH[1]}"
    local java_version="${BASH_REMATCH[2]}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %ssdkman:java:%s %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${java_major}" "${java_version}"
    return 0
  fi

  # -----------------------------------------------------------------------
  # Handle SDKMAN variable reference pattern
  # -----------------------------------------------------------------------
  if [[ "${remaining}" =~ ^(GLOBAL_STACK_[A-Z0-9_]+_INSTALL_PACKAGE_([A-Z_]+)_(VX[0-9]+_)?VERSION)[[:space:]]+([^[:space:]]+) ]]; then
    local candidate_upper="${BASH_REMATCH[2]}"
    local vx_part="${BASH_REMATCH[3]}"
    local version="${BASH_REMATCH[4]}"
    local candidate="${candidate_upper,,}"
    local major="${version%%.*}"
    local type_id_str="sdkman:${candidate}"
    [[ -n "${vx_part}" ]] && type_id_str="sdkman:${candidate}:${major}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %s%s %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${type_id_str}" "${version}"
    return 0
  fi

  # -----------------------------------------------------------------------
  # Android SDK URL pattern
  # -----------------------------------------------------------------------
  if [[ "${remaining}" =~ ^https://developer\.android\.com/studio[[:space:]]+([0-9]+) ]]; then
    local version="${BASH_REMATCH[1]}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %surl:https://developer.android.com/studio %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${version}"
    return 0
  fi

  # -----------------------------------------------------------------------
  # Handle pipe in remaining (e.g. "v1.2.3 | v1.2.4")
  # -----------------------------------------------------------------------
  local pipe_compat=""
  if [[ "${remaining}" =~ \| ]]; then
    local lhs="${remaining%%|*}"
    local rhs="${remaining##*|}"
    rhs="${rhs#"${rhs%%[! ]*}"}"

    # Extract compat from lhs if present
    local _re_paren_extract='^.*[(]([^)]+)[)]'
    if [[ "${lhs}" =~ ${_re_paren_extract} ]]; then
      pipe_compat="${BASH_REMATCH[1]}"
    fi

    # Resolve: take the stable/bigger version from both sides
    local resolved
    resolved="$(_gs_cu_resolve_pipe_version "${remaining}")"
    if [[ -n "${resolved}" ]]; then
      # Keep URLs and non-version tokens from the LHS; replace the version with the resolved one
      # Strip all version-like tokens from lhs to get just the URL/name prefix
      local lhs_prefix
      lhs_prefix="$(printf '%s' "${lhs}" | sed -E 's/[[:space:]]+v?[0-9]+[.][0-9]+[^ ]*([[:space:]]+.*)?$//')"
      lhs_prefix="${lhs_prefix%"${lhs_prefix##*[! ]}"}"  # rtrim
      remaining="${lhs_prefix} ${resolved}"
    fi
  fi

  # -----------------------------------------------------------------------
  # Main tokenizer
  # -----------------------------------------------------------------------
  local tokens=()
  # shellcheck disable=SC2207
  read -ra tokens <<< "${remaining}"

  if [[ ${#tokens[@]} -lt 2 ]]; then
    echo "${line}"
    return 0
  fi

  # The last token should be the version
  local version="${tokens[${#tokens[@]}-1]}"

  # Check if version looks like a hint or stability keyword — not a version
  if [[ "${version}" == *")"* || "${version}" == *"("* ]]; then
    echo "${line}"
    return 0
  fi

  # Adjust for stability token at end
  if [[ ${#tokens[@]} -ge 3 ]]; then
    local last_tok="${tokens[${#tokens[@]}-1]}"
    local second_last="${tokens[${#tokens[@]}-2]}"
    if [[ "${last_tok}" =~ ^(stable|beta|alpha)$ && "${second_last}" =~ ^[0-9] ]]; then
      version="${second_last}"
    fi
  fi

  # Handle "next" version (PHPEDGE-style)
  if [[ "${version}" == "next" ]]; then
    # Find the github URL in tokens
    local next_url=""
    local t
    for t in "${tokens[@]}"; do
      if [[ "${t}" =~ ^https://github\.com/ ]]; then
        next_url="${t}"
        break
      fi
    done
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    if [[ -n "${next_url}" ]]; then
      printf '%s%scheck-updates %sgithub:%s next urls: %s/commits/master/\n' \
        "${prefix}" "${todo_prefix}" "${flags_str}" \
        "$(printf '%s' "${next_url}" | grep -oE 'github\.com/[^/]+/[^/[:space:]]+')" \
        "${next_url}"
    else
      echo "${line}"
    fi
    return 0
  fi

  # Collect URLs from middle tokens
  local urls=()
  local bare_names=()
  local i
  for (( i=0; i<${#tokens[@]}-1; i++ )); do
    local tok="${tokens[${i}]}"
    if [[ "${tok}" =~ ^https?:// ]]; then
      urls+=("${tok}")
    elif [[ "${tok}" =~ ^http:// ]]; then
      urls+=("${tok}")
    else
      bare_names+=("${tok}")
    fi
  done

  # Determine type:id
  local type_id=""

  if [[ ${#urls[@]} -gt 0 ]]; then
    # Use the LAST URL as the principal one — user places the most relevant URL last
    local best_url="${urls[${#urls[@]}-1]}"
    type_id="$(_gs_cu_infer_type_from_url "${best_url}" "${version}")"

    # PHP major-pin inference
    if [[ "${type_id}" == "github:php/php-src" && "${version}" =~ ^([0-9]+\.[0-9]+)\. ]]; then
      type_id="github:php/php-src:${BASH_REMATCH[1]}"
    fi

  elif [[ ${#bare_names[@]} -gt 0 ]]; then
    local name="${bare_names[0]}"
    if [[ "${name}" =~ ^[a-z][a-z0-9_-]+$ ]]; then
      type_id="sdkman:${name}"
    else
      type_id="url:${name}"
    fi
  else
    echo "${line}"
    return 0
  fi

  # -----------------------------------------------------------------------
  # Build hint string from extracted_parens and pipe_compat
  # -----------------------------------------------------------------------
  local hint_str=""
  local extra_urls_str=""

  # Process extracted parens: stability keywords become hints, URLs become extra_urls
  local paren_hint=""
  local _re_compat_check='[a-z].*(>=|<=|>|<|==|=)'
  for paren in "${extracted_parens[@]+"${extracted_parens[@]}"}"; do
    if [[ "${paren}" =~ ^(stable|beta|alpha)$ ]]; then
      paren_hint="${paren}"
    elif [[ "${paren}" =~ ^https?:// ]]; then
      urls+=("${paren}")
    elif [[ "${paren}" =~ ${_re_compat_check} ]]; then
      # Looks like a compat constraint
      paren_hint="$(_gs_cu_normalize_compat_hint "${paren}")"
    else
      paren_hint="${paren}"
    fi
  done

  # pipe_compat also contributes to hint
  if [[ -n "${pipe_compat}" && -z "${paren_hint}" ]]; then
    paren_hint="$(_gs_cu_normalize_compat_hint "${pipe_compat}")"
  fi

  if [[ -n "${paren_hint}" ]]; then
    hint_str=" (${paren_hint})"
  fi

  # Build extra_urls: collect non-authoritative URLs not used as type_id source
  local used_url=""
  [[ "${type_id}" == url:* ]] && used_url="${type_id#url:}"
  local extra_url_tokens=()
  for u in "${urls[@]+"${urls[@]}"}"; do
    [[ "${u}" == "${used_url}" ]] && continue
    # Don't add the authoritative URL that was already used for type inference
    local inferred_check
    inferred_check="$(_gs_cu_infer_type_from_url "${u}" "${version}" 2>/dev/null || echo "")"
    if [[ "${inferred_check}" == "${type_id}" ]]; then
      continue
    fi
    extra_url_tokens+=("${u}")
  done

  if [[ ${#extra_url_tokens[@]} -gt 0 ]]; then
    extra_urls_str=" urls:"
    for u in "${extra_url_tokens[@]}"; do
      extra_urls_str+=" ${u}"
    done
  fi

  # -----------------------------------------------------------------------
  # Check for depends-on mapping
  # -----------------------------------------------------------------------
  local depends_on_str=""
  # The env var name is on the next line — we can only check the mapping here
  # We'll append depends-on in _gs_cu_run_migration after seeing the variable name

  # -----------------------------------------------------------------------
  # Final output
  # -----------------------------------------------------------------------
  local flags_str=""
  [[ -n "${flags}" ]] && flags_str="${flags} "

  printf '%s%scheck-updates %s%s %s%s%s\n' \
    "${prefix}" "${todo_prefix}" "${flags_str}" "${type_id}" "${version}" \
    "${hint_str}" "${extra_urls_str}"
}

# --------------------------------------------------------------------------
# Main migration logic
# --------------------------------------------------------------------------
_gs_cu_run_migration() {
  local line_number=0
  local changed_count=0
  local unchanged_count=0

  # Pre-scan for pecl-git pairs and propagate pairs
  _gs_cu_migrate_pre_scan_pecl_git_pairs
  _gs_cu_migrate_pre_scan_propagate_pairs

  # Arrays to collect changes — declared at script scope so dry-run report can read them
  _GS_CU_MIGRATE_ORIG_LINES=()
  _GS_CU_MIGRATE_MIGRATED_LINES=()
  _GS_CU_MIGRATE_CHANGE_LNUMS=()
  _GS_CU_MIGRATE_ALREADY_COUNT=0
  _GS_CU_MIGRATE_ALREADY_LINES=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    # Handle "@todo change ... everywhere" lines from propagate pre-scan
    if [[ "${line}" =~ @todo[[:space:]]+(change[[:space:]]+this[[:space:]]+|change[[:space:]]+)ARG ]]; then
      local _prop_action="${_GS_CU_MIGRATE_PROPAGATE_PAIRS[${line_number}]:-}"
      if [[ "${_prop_action}" == "DROP" ]]; then
        # Paired with a check-updates — drop this line
        _GS_CU_MIGRATE_ORIG_LINES+=("${line}")
        _GS_CU_MIGRATE_MIGRATED_LINES+=("")
        _GS_CU_MIGRATE_CHANGE_LNUMS+=("${line_number}")
        (( changed_count++ )) || true
      elif [[ "${_prop_action}" == STANDALONE:* ]]; then
        # No check-updates partner — migrate to standalone propagate annotation
        local _varname="${_prop_action#STANDALONE:}"
        local _prop_prefix
        _prop_prefix="$(printf '%s' "${line}" | grep -oE '^[[:space:]]*#[[:space:]]*')"
        local _migrated_prop="${_prop_prefix}@todo propagate ${_varname}"
        _GS_CU_MIGRATE_ORIG_LINES+=("${line}")
        _GS_CU_MIGRATE_MIGRATED_LINES+=("${_migrated_prop}")
        _GS_CU_MIGRATE_CHANGE_LNUMS+=("${line_number}")
        (( changed_count++ )) || true
      fi
      continue
    fi

    # Handle "could be a repo url" lines — these are DROP candidates from pecl-git pre-scan
    if [[ "${line}" =~ @todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo ]]; then
      if [[ "${_GS_CU_MIGRATE_PECL_GIT_PAIRS[${line_number}]:-}" == "DROP" ]]; then
        _GS_CU_MIGRATE_ORIG_LINES+=("${line}")
        _GS_CU_MIGRATE_MIGRATED_LINES+=("")
        _GS_CU_MIGRATE_CHANGE_LNUMS+=("${line_number}")
        (( changed_count++ )) || true
      fi
      continue
    fi

    # Only process annotation lines
    if [[ "${line}" =~ @todo.*check-updates ]]; then
      local migrated
      migrated="$(_gs_cu_migrate_annotation_line "${line}" "${line_number}")"

      # Inject (propagate) flag if this check-updates line is paired with a change line
      if [[ "${migrated}" != "${line}" && "${_GS_CU_MIGRATE_PROPAGATE_PAIRS[${line_number}]:-}" == "ADD_PROPAGATE" ]]; then
        # Insert (propagate) flag after "check-updates " in the migrated output
        migrated="${migrated/check-updates /check-updates (propagate) }"
      elif [[ "${migrated}" == "${line}" && "${_GS_CU_MIGRATE_PROPAGATE_PAIRS[${line_number}]:-}" == "ADD_PROPAGATE" ]]; then
        # Annotation was already in new format — still need to add propagate flag
        migrated="${migrated/check-updates /check-updates (propagate) }"
      fi

      if [[ "${migrated}" == "__DROP_LINE__" ]]; then
        # This line should be removed entirely
        _GS_CU_MIGRATE_ORIG_LINES+=("${line}")
        _GS_CU_MIGRATE_MIGRATED_LINES+=("")
        _GS_CU_MIGRATE_CHANGE_LNUMS+=("${line_number}")
        (( changed_count++ )) || true
      elif [[ "${migrated}" != "${line}" ]]; then
        # Check if we need to inject depends-on for the next variable
        # We do this after seeing the variable name, but we need to know the annotation line
        _GS_CU_MIGRATE_ORIG_LINES+=("${line}")
        _GS_CU_MIGRATE_MIGRATED_LINES+=("${migrated}")
        _GS_CU_MIGRATE_CHANGE_LNUMS+=("${line_number}")
        (( changed_count++ )) || true
        _gs_cu_log_debug "Line ${line_number} migrated"
      else
        (( unchanged_count++ )) || true
        (( _GS_CU_MIGRATE_ALREADY_COUNT++ )) || true
        _GS_CU_MIGRATE_ALREADY_LINES+=("${line}")
      fi
    fi
  done < "${ENV_FILE}"

  # Second pass: for each changed annotation, look ahead to find env var name
  # and inject depends-on if in the map
  local k
  for (( k=0; k<${#_GS_CU_MIGRATE_CHANGE_LNUMS[@]}; k++ )); do
    local ann_line_num="${_GS_CU_MIGRATE_CHANGE_LNUMS[${k}]}"
    local ann_migrated="${_GS_CU_MIGRATE_MIGRATED_LINES[${k}]}"
    [[ -z "${ann_migrated}" ]] && continue  # DROP line

    # Read forward from ann_line_num to find the variable name
    local scan_line=0
    local found_var=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
      (( scan_line++ )) || true
      [[ ${scan_line} -le ${ann_line_num} ]] && continue
      # Skip blank/comment lines
      if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      # Variable assignment?
      if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        found_var="${BASH_REMATCH[1]}"
        break
      fi
      break  # Non-blank, non-comment, non-var line — give up
    done < "${ENV_FILE}"

    # Inject depends-on if mapped
    if [[ -n "${found_var}" && -n "${_GS_CU_MIGRATE_DEPENDS_ON_MAP[${found_var}]+x}" ]]; then
      local dep_annotation="${_GS_CU_MIGRATE_DEPENDS_ON_MAP[${found_var}]}"
      ann_migrated="${ann_migrated} (${dep_annotation})"
      _GS_CU_MIGRATE_MIGRATED_LINES[${k}]="${ann_migrated}"
    fi

    # Apply major-pin from variable name pattern (e.g. NODE22 → :22, RUBY3 → :3)
    # Pattern: GLOBAL_STACK_<TOOL><MAJOR>_VERSION  (single integer major, not PHP/JAVA already handled)
    if [[ -n "${found_var}" ]]; then
      local _re_major_pin_var='^GLOBAL_STACK_([A-Z]+)([0-9]+)_VERSION$'
      if [[ "${found_var}" =~ ${_re_major_pin_var} ]]; then
        local _mp_tool="${BASH_REMATCH[1],,}"   # e.g. "node", "ruby", "flutter"
        local _mp_major="${BASH_REMATCH[2]}"    # e.g. "22", "3"
        # Only apply to github: identifiers that don't already have a pin
        local _re_github_no_pin='(github:[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)( )'
        if [[ "${ann_migrated}" =~ ${_re_github_no_pin} ]]; then
          local _cur_id="${BASH_REMATCH[1]}"
          # Skip if already pinned (has a second colon in the identifier part)
          local _id_part="${_cur_id#github:}"
          if [[ "${_id_part}" != *:* ]]; then
            ann_migrated="${ann_migrated//${_cur_id} /${_cur_id}:${_mp_major} }"
            _GS_CU_MIGRATE_MIGRATED_LINES[${k}]="${ann_migrated}"
          fi
        fi
      fi
    fi
  done

  if [[ "${MIGRATE_DRY_RUN}" == "true" ]]; then
    _gs_cu_migrate_print_dry_run_report "${change_line_numbers[@]+"${change_line_numbers[@]}"}"
    return 0
  fi

  if [[ "${changed_count}" -eq 0 ]]; then
    printf 'No annotations need migration.\n'
    return 0
  fi

  # Create backup
  if [[ "${MIGRATE_BACKUP}" == "true" ]]; then
    cp "${ENV_FILE}" "${ENV_FILE}.bak"
    printf 'Backup created: %s.bak\n' "${ENV_FILE}"
  fi

  # Apply changes in-place using a temp file
  local tmpfile
  tmpfile="$(mktemp)"
  local current_line=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( current_line++ )) || true

    # Check if this line number needs migration
    local needs_change="false"
    local kk
    for (( kk=0; kk<${#_GS_CU_MIGRATE_CHANGE_LNUMS[@]}; kk++ )); do
      if [[ "${_GS_CU_MIGRATE_CHANGE_LNUMS[${kk}]}" -eq "${current_line}" ]]; then
        local ml="${_GS_CU_MIGRATE_MIGRATED_LINES[${kk}]}"
        if [[ -n "${ml}" ]]; then
          printf '%s\n' "${ml}" >> "${tmpfile}"
        fi
        # If ml is empty, the line is dropped (not written)
        needs_change="true"
        break
      fi
    done

    if [[ "${needs_change}" == "false" ]]; then
      printf '%s\n' "${line}" >> "${tmpfile}"
    fi
  done < "${ENV_FILE}"

  mv "${tmpfile}" "${ENV_FILE}"

  printf 'Migration complete: %d annotations updated, %d line(s) already in new format (skipped).\n' \
    "${changed_count}" "${_GS_CU_MIGRATE_ALREADY_COUNT}"

  if [[ "${_GS_CU_MIGRATE_SHOW_ALREADY_MIGRATED}" == "true" && "${_GS_CU_MIGRATE_ALREADY_COUNT}" -gt 0 ]]; then
    printf '%b\n' "${_GS_CU_CLR_DIM}Already in new format:${_GS_CU_CLR_RESET}"
    local _al
    for _al in "${_GS_CU_MIGRATE_ALREADY_LINES[@]}"; do
      printf '  %b%s%b\n' "${_GS_CU_CLR_CYAN}" "${_al}" "${_GS_CU_CLR_RESET}"
    done
  fi
}

_gs_cu_migrate_print_dry_run_report() {
  # Uses the global arrays already computed (including second-pass adjustments)
  # by _gs_cu_run_migration: _GS_CU_MIGRATE_ORIG_LINES, _GS_CU_MIGRATE_MIGRATED_LINES,
  # _GS_CU_MIGRATE_CHANGE_LNUMS
  printf '%b\n' "${_GS_CU_CLR_BOLD}=== DRY-RUN: Migration Preview ===${_GS_CU_CLR_RESET}"
  local count="${#_GS_CU_MIGRATE_CHANGE_LNUMS[@]}"
  local k
  for (( k=0; k<count; k++ )); do
    local _orig="${_GS_CU_MIGRATE_ORIG_LINES[${k}]}"
    local _migr="${_GS_CU_MIGRATE_MIGRATED_LINES[${k}]}"
    local _lnum="${_GS_CU_MIGRATE_CHANGE_LNUMS[${k}]}"
    printf '%b  Line %d:\n' "${_GS_CU_CLR_DIM}" "${_lnum}"
    printf '  %bBEFORE:%b %s\n' "${_GS_CU_CLR_RED}" "${_GS_CU_CLR_RESET}" "${_orig}"
    if [[ -z "${_migr}" ]]; then
      printf '  %bAFTER: %b (line removed)\n' "${_GS_CU_CLR_GREEN}" "${_GS_CU_CLR_RESET}"
    else
      printf '  %bAFTER: %b %s\n' "${_GS_CU_CLR_GREEN}" "${_GS_CU_CLR_RESET}" "${_migr}"
    fi
    printf '\n'
  done
  printf '%d annotation(s) would be migrated.\n' "${count}"
  printf '%d line(s) already in new format.\n' "${_GS_CU_MIGRATE_ALREADY_COUNT}"

  if [[ "${_GS_CU_MIGRATE_SHOW_ALREADY_MIGRATED}" == "true" && "${_GS_CU_MIGRATE_ALREADY_COUNT}" -gt 0 ]]; then
    printf '%b\n' "${_GS_CU_CLR_DIM}Already in new format:${_GS_CU_CLR_RESET}"
    local _al
    for _al in "${_GS_CU_MIGRATE_ALREADY_LINES[@]}"; do
      printf '  %b%s%b\n' "${_GS_CU_CLR_CYAN}" "${_al}" "${_GS_CU_CLR_RESET}"
    done
  fi
}

# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------
main() {
  _gs_cu_migrate_parse_args "$@"

  if [[ ! -f "${ENV_FILE}" ]]; then
    printf 'ERROR: .env file not found at %s\n' "${ENV_FILE}" >&2
    exit 1
  fi

  _gs_cu_log_info "Migrating annotations in: ${ENV_FILE}"
  if [[ "${MIGRATE_DRY_RUN}" == "true" ]]; then
    _gs_cu_log_info "DRY-RUN mode — no files will be modified"
  fi

  _gs_cu_run_migration
}

main "$@"
