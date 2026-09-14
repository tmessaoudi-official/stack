#!/bin/bash
# androidsdk.sh — Android SDK component fetcher, read from Google's repository XML.
#
# Row 46: this was sdkmanager.sh and the `sdkmanager:` type. Upstream deprecated
# that CLI in favour of `android sdk` and 04android already calls the new one, so
# the type followed. The fetch path is unchanged -- it never needed the binary
# (row 41). parse.sh refuses a leftover `sdkmanager:`: dispatch is dynamic, and
# a type with no fetcher would otherwise SKIP silently.
#
# Exports:   _gs_eu2_androidsdk_get_repo  _gs_eu2_androidsdk_parse_versions
#            _gs_eu2_androidsdk_stable_paths  _gs_eu2_androidsdk_sibling_keep
#            _gs_eu2_fetch_androidsdk
# Sources:   core/records.sh  core/semver.sh  core/channel.sh  core/cache.sh
#            http/curl.sh
# Deps:      awk, sort -V
# Env:       _GS_EU2_CFG[no_cache]
#            _GS_EU2_ANDROIDSDK_REPO_URL (override; default below)
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
#   3. (require-sibling:) filter, when present — see below.
#   4. Channel selection + (offset:N) → proposed.
#
# (require-sibling:URL|ID_TEMPLATE,…) — row 43:
#   A package can be STABLE while its companions are not. `platforms;android-37.2`
#   reached channel-0 while both of its system images stayed on channel-2 (dev),
#   and since `android sdk install` is stable-only and exits 0 on "Package not
#   found", the window rolled onto a level whose images could never install: the
#   verify loop in global-stack-android-setup.sh FATALed. Row 41 had anticipated a
#   TAG RENAME; the class that bit is CHANNEL SKEW.
#   Each pair names the XML the companion lives in, because the tag → document
#   mapping (google_apis_ps16k → sys-img/google_apis/sys-img2-3.xml) is data
#   Google publishes, not a rule derivable from the id. Each XML is fetched ONCE
#   and every candidate tested against the resulting set in memory.
#   The filter runs BEFORE channel selection so (offset:N) counts qualifying
#   levels only — after it, offset 0 would land on 37.2 and the gate would have
#   nothing left to do.
#   It FAILS CLOSED: an unreachable companion XML is ERROR, never an empty
#   package set, which a filter would read as "nothing to exclude" and pass every
#   candidate — shipping the broken pin exactly when the check could not run.
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

[[ -n "${_GS_EU2_ANDROIDSDK_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_ANDROIDSDK_SH_LOADED=1

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

: "${_GS_EU2_ANDROIDSDK_REPO_URL:=https://dl.google.com/android/repository/repository2-3.xml}"

# _gs_eu2_androidsdk_get_repo — return the repository XML body.
#
# Args:    $1 sink — (optional) HTTP diagnostic sink from _gs_eu2_http_diag_new
# Prints:  raw XML
# Returns: 0 on success; 1 on transport failure or an empty body
# Side fx: one HTTP GET (memoised by http/curl.sh, so the 11 live records share it)
_gs_eu2_androidsdk_get_repo() {
  local _sink="${1:-}" _body
  if ! _body="$(_gs_eu2_http_get "${_GS_EU2_ANDROIDSDK_REPO_URL}" "${_sink}" 2>/dev/null)"; then
    return 1
  fi
  [[ -z "${_body}" ]] && return 1
  printf '%s\n' "${_body}"
}

# _gs_eu2_androidsdk_parse_versions — extract version strings for a component.
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
_gs_eu2_androidsdk_parse_versions() {
  local _xml="${1}" _component="${2}"
  printf '%s\n' "${_xml}" | _GS_EU2_ASDK_COMP="${_component}" awk '
    BEGIN { comp = ENVIRON["_GS_EU2_ASDK_COMP"] }
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

# _gs_eu2_androidsdk_stable_paths — the INSTALLABLE package paths in a repo XML.
#
# Args:    $1 xml — repository XML body (main or sys-img)
# Prints:  newline-separated path= values that are channel-0 and not obsolete
# Returns: 0 always
#
# Qualifying means present AND channel-0 AND not obsolete="true" — presence alone
# is exactly what let 37.2 through. A missing <channelRef> counts as stable, which
# matches _gs_eu2_androidsdk_parse_versions' own reading of the same attribute.
_gs_eu2_androidsdk_stable_paths() {
  local _xml="${1}"
  printf '%s\n' "${_xml}" | awk '
    /<remotePackage / {
      inpkg = 1; obsolete = ($0 ~ /obsolete="true"/); path = ""; cref = ""
      if (match($0, /path="[^"]*"/)) path = substr($0, RSTART + 6, RLENGTH - 7)
      next
    }
    inpkg && /<channelRef ref="/ { s = $0; sub(/.*<channelRef ref="/, "", s); sub(/".*/, "", s); cref = s; next }
    inpkg && /<\/remotePackage>/ {
      inpkg = 0
      if (obsolete) next
      if (cref != "" && cref != "channel-0") next
      if (path == "") next
      print path
      next
    }
  '
}

# _gs_eu2_androidsdk_sibling_keep — drop candidates whose companion is absent.
#
# Args:    $1 versions  — newline-separated candidate list
#          $2 template  — companion id with a {version} placeholder
#          $3 paths     — qualifying path set from _gs_eu2_androidsdk_stable_paths
# Prints:  the surviving candidates, newline-separated, order preserved
# Returns: 0 always
#
# Pure by design: the HTTP call stays in the caller so a transport failure can be
# told apart from "no candidate qualifies". Conflating them is how a fail-open
# filter gets written.
_gs_eu2_androidsdk_sibling_keep() {
  local _versions="${1}" _tpl="${2}" _paths="${3}"
  local _v _need _out=""
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    _need="${_tpl//\{version\}/${_v}}"
    if printf '%s\n' "${_paths}" | grep -Fxq -- "${_need}"; then
      _out+="${_v}"$'\n'
    fi
  done <<<"${_versions}"
  printf '%s' "${_out}"
}

# _gs_eu2_fetch_androidsdk — main entry point for the androidsdk: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, offset
# Sets:    record fields: proposed_version, error_message
#          (decision only on a transport failure — otherwise owned by decide.sh)
# Prints:  nothing
# Returns: 0 always
_gs_eu2_fetch_androidsdk() {
  local _idx="${1}"

  local _identifier _channel _offset _no_cache _require_sibling
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _offset="$(_gs_eu2_record_get "${_idx}" offset)"
  _offset="${_offset:-0}"
  _require_sibling="$(_gs_eu2_record_get "${_idx}" require_sibling)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Cache key — the offset MUST be part of it: three androidsdk:platforms records
  # differ only by offset, and a key without it hands all three the same value.
  # The sibling spec is in for the same reason one level up: a gated and an
  # ungated record on the same identifier and offset legitimately resolve to
  # DIFFERENT versions, and without it the second read returns the first's answer.
  # Appended only when SET (:+ not :-), so an ungated record's key is byte-identical
  # to the pre-row-43 one: an unconditional segment leaves a trailing colon that
  # invalidates every cached entry on this type and reds t33g, which pins the shape.
  local _cache_key="androidsdk:${_identifier}:${_channel}:off${_offset}${_require_sibling:+:${_require_sibling}}"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "" "" && return 0

  # Repository XML
  local _sink _xml
  _sink="$(_gs_eu2_http_diag_new)" || _sink=""
  if ! _xml="$(_gs_eu2_androidsdk_get_repo "${_sink}")"; then
    local _st=""
    [[ -n "${_sink}" ]] && _st="$(_gs_eu2_http_diag_status "${_sink}")"
    _gs_eu2_http_diag_free "${_sink}"
    _gs_eu2_record_set "${_idx}" decision "ERROR"
    _gs_eu2_record_set "${_idx}" error_message \
      "androidsdk: repository fetch failed for ${_GS_EU2_ANDROIDSDK_REPO_URL}${_st:+ (HTTP ${_st})}"
    return 0
  fi
  _gs_eu2_http_diag_free "${_sink}"

  # Parse versions for this component
  local _versions
  _versions="$(_gs_eu2_androidsdk_parse_versions "${_xml}" "${_identifier}")"

  if [[ -z "$(printf '%s\n' "${_versions}" | grep -v '^$' || true)" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "no versions found for androidsdk:${_identifier} in the repository XML"
    return 0
  fi

  # (require-sibling:) — companion availability, BEFORE selection so the offset
  # counts qualifying levels only.
  if [[ -n "${_require_sibling}" ]]; then
    local _rs_oldifs="${IFS}" _rs_pair _rs_url _rs_tpl _rs_body _rs_paths _rs_sink _rs_st
    IFS=','
    # shellcheck disable=SC2206  # deliberate split on the comma list
    local _rs_pairs=(${_require_sibling})
    IFS="${_rs_oldifs}"
    for _rs_pair in "${_rs_pairs[@]}"; do
      [[ -z "${_rs_pair}" ]] && continue
      _rs_url="${_rs_pair%%|*}"
      _rs_tpl="${_rs_pair#*|}"
      _rs_sink="$(_gs_eu2_http_diag_new)" || _rs_sink=""
      if ! _rs_body="$(_gs_eu2_http_get "${_rs_url}" "${_rs_sink}" 2>/dev/null)" || [[ -z "${_rs_body}" ]]; then
        _rs_st=""
        [[ -n "${_rs_sink}" ]] && _rs_st="$(_gs_eu2_http_diag_status "${_rs_sink}")"
        _gs_eu2_http_diag_free "${_rs_sink}"
        _gs_eu2_record_set "${_idx}" decision "ERROR"
        _gs_eu2_record_set "${_idx}" error_message \
          "androidsdk: (require-sibling:) fetch failed for ${_rs_url}${_rs_st:+ (HTTP ${_rs_st})} — cannot prove companion availability, leaving the pin unchanged"
        return 0
      fi
      _gs_eu2_http_diag_free "${_rs_sink}"
      _rs_paths="$(_gs_eu2_androidsdk_stable_paths "${_rs_body}")"
      _versions="$(_gs_eu2_androidsdk_sibling_keep "${_versions}" "${_rs_tpl}" "${_rs_paths}")"
      [[ -z "${_versions}" ]] && break
    done
    if [[ -z "$(printf '%s\n' "${_versions}" | grep -v '^$' || true)" ]]; then
      _gs_eu2_record_set "${_idx}" error_message \
        "no version of androidsdk:${_identifier} has all its (require-sibling:) companions published on the stable channel — leaving the pin unchanged"
      return 0
    fi
  fi

  # Channel selection (+ offset) → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}" "${_offset}")"

  if [[ -z "${_proposed}" ]]; then
    if [[ "${_offset}" -gt 0 ]]; then
      local _n_stable
      _n_stable="$(_gs_eu2_channel_count_stable "${_versions}")"
      _gs_eu2_record_set "${_idx}" error_message \
        "offset ${_offset} reaches past the ${_n_stable} distinct stable version(s) upstream serves for androidsdk:${_identifier}"
    else
      _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for androidsdk:${_identifier}"
    fi
    return 0
  fi

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
