#!/bin/bash
# sdkmanager.sh — Android SDK component fetcher, read from Google's repository XML.
#
# Exports:   _gs_eu2_sdkmanager_get_repo  _gs_eu2_sdkmanager_parse_versions
#            _gs_eu2_fetch_sdkmanager
# Sources:   core/records.sh  core/semver.sh  core/channel.sh  core/cache.sh
#            http/curl.sh
# Deps:      awk, sort -V
# Env:       _GS_EU2_CFG[no_cache]
#            _GS_EU2_SDKMANAGER_REPO_URL (override; default below)
#            _GS_EU2_HTTP_FIXTURE_DIR (test seam, via http/curl.sh — fixture name
#              dl.google.com_android_repository_repository2-3.xml)
#
# Input:  record index — reads identifier/channel/offset
# Output: writes proposed_version + error_message back into record
#         (decision is NOT written except on a transport failure — owned by decide.sh)
#
# Strategy (row 41 — no local binary any more):
#   1. GET the repository XML — the same document `sdkmanager --list` / `android sdk
#      list` download before printing anything. The old fetcher shelled out to a
#      local `sdkmanager` on the tools/ volume, so it resolved NOTHING on a machine
#      with the stack down (tools/ is wiped by hard-restart) and could not parse
#      `platforms;android-<LEVEL>` at all (its regex wanted `platforms;<digit>`),
#      which is why the three API-level vars were (lock:)ed for a year.
#   2. Parse every <remotePackage path="…"> whose path IS the component (bare,
#      single-instance ids: platform-tools, ndk-bundle, emulator) or STARTS WITH
#      `component;` (versioned ids: build-tools;37.0.0, ndk;30.0.…, platforms;android-37.2).
#   3. Channel selection + (offset:N) → proposed.
#
# Version rendering:
#   - versioned path → the part after `;`, verbatim (betas/rcs carry their suffix
#     there: build-tools;37.0.0-rc2, platforms;android-37.2-beta1). For `platforms`
#     the `android-` prefix is stripped so the value IS the API level (37.2), which
#     is what global-stack-android-setup.sh re-prefixes. Extension SDKs
#     (`36-ext18`) are a different product and are dropped; codenames (CANARY,
#     UpsideDownCake) have no numeric shape and are dropped.
#   - bare path → <revision> major[.minor[.micro]], `-rcN` when <preview>N is set
#     (Google's own convention for the versioned ids: 37.0.0-rc2 has <preview>2).
#   - a package served in a NON-stable channel with no prerelease marker of its own
#     gets `-<channel name>` (36.6.11-dev) so the stable pick cannot land on it.
#     Only the bare ids need this in practice (a dev emulator has a plain revision);
#     the channel tag does NOT mark prereleases in general — build-tools;37.0.0-rc2
#     sits in channel-0 — so selection keys on the version STRING, not the channel.
#   - obsolete="true" packages are skipped, as `sdkmanager --list` skips them
#     without --include_obsolete.
#
# Not found vs. unreachable:
#   - repository unreachable → decision ERROR (a dead upstream must fail --check,
#     §119), never SKIP: there is no "toolchain not installed" case left.
#   - component absent from the repository → error_message only → SKIP via
#     decide.sh. The three (lock:)ed system-images records name components this
#     document does not carry (tags/abi live in the sys-img XMLs); they must keep
#     reading as SKIP + lock reason, not as a failed run.

[[ -n "${_GS_EU2_SDKMANAGER_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SDKMANAGER_SH_LOADED=1

# shellcheck source=../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"

: "${_GS_EU2_SDKMANAGER_REPO_URL:=https://dl.google.com/android/repository/repository2-3.xml}"

# _gs_eu2_sdkmanager_get_repo — return the repository XML body.
#
# Args:    $1 sink — (optional) HTTP diagnostic sink from _gs_eu2_http_diag_new
# Prints:  raw XML
# Returns: 0 on success; 1 on transport failure or an empty body
# Side fx: one HTTP GET (memoised by http/curl.sh, so the 11 live records share it)
_gs_eu2_sdkmanager_get_repo() {
  local _sink="${1:-}" _body
  if ! _body="$(_gs_eu2_http_get "${_GS_EU2_SDKMANAGER_REPO_URL}" "${_sink}" 2>/dev/null)"; then
    return 1
  fi
  [[ -z "${_body}" ]] && return 1
  printf '%s\n' "${_body}"
}

# _gs_eu2_sdkmanager_parse_versions — extract version strings for a component.
#
# Args:    $1 xml       — repository XML body
#          $2 component — component name (e.g. "platform-tools", "build-tools",
#                         "ndk", "platforms")
# Prints:  newline-separated sorted version list (sort -uV); nothing if no match
# Returns: 0 always
#
# awk, one pass, state per <remotePackage>: the path attribute is taken with
# match() because `obsolete="true"` precedes `path=` on some lines; revision
# fields are read ONLY inside <revision>…</revision> — a <dependency> block
# carries a <min-revision><major> of its own that would otherwise overwrite them.
# The component reaches awk through ENVIRON, not -v: -v processes escapes.
_gs_eu2_sdkmanager_parse_versions() {
  local _xml="${1}" _component="${2}"
  printf '%s\n' "${_xml}" | _GS_EU2_SDKM_COMP="${_component}" awk '
    BEGIN { comp = ENVIRON["_GS_EU2_SDKM_COMP"] }
    /<channel id="channel-[0-9]+">/ {
      s = $0; sub(/.*<channel id="/, "", s); id = s; sub(/".*/, "", id)
      name = s; sub(/^[^>]*>/, "", name); sub(/<.*/, "", name)
      chan[id] = name; next
    }
    /<remotePackage / {
      inpkg = 1; inrev = 0; obsolete = ($0 ~ /obsolete="true"/)
      path = ""; major = ""; minor = ""; micro = ""; preview = ""; cref = ""
      if (match($0, /path="[^"]*"/)) path = substr($0, RSTART + 6, RLENGTH - 7)
      next
    }
    inpkg && /<revision>/  { inrev = 1; next }
    inpkg && /<\/revision>/ { inrev = 0; next }
    inpkg && inrev && /<major>/   { s = $0; sub(/.*<major>/, "", s);   sub(/<.*/, "", s); major = s;   next }
    inpkg && inrev && /<minor>/   { s = $0; sub(/.*<minor>/, "", s);   sub(/<.*/, "", s); minor = s;   next }
    inpkg && inrev && /<micro>/   { s = $0; sub(/.*<micro>/, "", s);   sub(/<.*/, "", s); micro = s;   next }
    inpkg && inrev && /<preview>/ { s = $0; sub(/.*<preview>/, "", s); sub(/<.*/, "", s); preview = s; next }
    inpkg && /<channelRef ref="/ { s = $0; sub(/.*<channelRef ref="/, "", s); sub(/".*/, "", s); cref = s; next }
    inpkg && /<\/remotePackage>/ {
      inpkg = 0
      if (obsolete) next
      v = ""
      if (path == comp) {
        v = major
        if (v != "" && minor != "") v = v "." minor
        if (v != "" && micro != "") v = v "." micro
        if (v != "" && preview != "") v = v "-rc" preview
      } else if (index(path, comp ";") == 1) {
        v = substr(path, length(comp) + 2)
        if (comp == "platforms") {
          if (index(v, "android-") != 1) next
          v = substr(v, 9)
          if (v ~ /-ext[0-9]+$/) next
        }
        if (v !~ /^[0-9]/) next
      } else next
      if (v == "") next
      if (cref != "" && cref != "channel-0" && v !~ /-(rc|beta|alpha|dev|canary)[0-9.]*$/)
        v = v "-" ((cref in chan) ? chan[cref] : cref)
      print v
      next
    }
  ' | sort -uV
}

# _gs_eu2_fetch_sdkmanager — main entry point for the sdkmanager: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, offset
# Sets:    record fields: proposed_version, error_message
#          (decision only on a transport failure — otherwise owned by decide.sh)
# Prints:  nothing
# Returns: 0 always
_gs_eu2_fetch_sdkmanager() {
  local _idx="${1}"

  local _identifier _channel _offset _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _offset="$(_gs_eu2_record_get "${_idx}" offset)"
  _offset="${_offset:-0}"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Cache key — the offset MUST be part of it: three sdkmanager:platforms records
  # differ only by offset, and a key without it hands all three the same value.
  local _cache_key="sdkmanager:${_identifier}:${_channel}:off${_offset}"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "" "" && return 0

  # Repository XML
  local _sink _xml
  _sink="$(_gs_eu2_http_diag_new)" || _sink=""
  if ! _xml="$(_gs_eu2_sdkmanager_get_repo "${_sink}")"; then
    local _st=""
    [[ -n "${_sink}" ]] && _st="$(_gs_eu2_http_diag_status "${_sink}")"
    _gs_eu2_http_diag_free "${_sink}"
    _gs_eu2_record_set "${_idx}" decision "ERROR"
    _gs_eu2_record_set "${_idx}" error_message \
      "sdkmanager: repository fetch failed for ${_GS_EU2_SDKMANAGER_REPO_URL}${_st:+ (HTTP ${_st})}"
    return 0
  fi
  _gs_eu2_http_diag_free "${_sink}"

  # Parse versions for this component
  local _versions
  _versions="$(_gs_eu2_sdkmanager_parse_versions "${_xml}" "${_identifier}")"

  if [[ -z "$(printf '%s\n' "${_versions}" | grep -v '^$' || true)" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "no versions found for sdkmanager:${_identifier} in the repository XML"
    return 0
  fi

  # Channel selection (+ offset) → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}" "${_offset}")"

  if [[ -z "${_proposed}" ]]; then
    if [[ "${_offset}" -gt 0 ]]; then
      local _n_stable
      _n_stable="$(_gs_eu2_channel_count_stable "${_versions}")"
      _gs_eu2_record_set "${_idx}" error_message \
        "offset ${_offset} reaches past the ${_n_stable} distinct stable version(s) upstream serves for sdkmanager:${_identifier}"
    else
      _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for sdkmanager:${_identifier}"
    fi
    return 0
  fi

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
