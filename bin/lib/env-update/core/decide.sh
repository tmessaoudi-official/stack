#!/bin/bash
# decide.sh — classify a proposed version into AUTO/HOLD/MANUAL/SKIP/RESOLVED.
#
# Exports:   _gs_eu2_classify_decision  _gs_eu2_classify_sha_decision
# Sources:   core/semver.sh
# Deps:      sort (GNU coreutils — for sort -V in downgrade detection)
# Env:       none
#
# Decision ladder (applied in this order — first match wins):
#   1. No proposed → SKIP
#   2. Floating current (nightly/latest/…) + concrete proposed → RESOLVED
#   3. Current == proposed → SKIP
#   4. Proposed is prerelease AND current is stable:
#      - stable_mode=full → SKIP (force-reject)
#      - unstable_mode=full → bypass (continue)
#      - record_channel=unstable → HOLD (annotation opt-in, review required)
#      - otherwise → SKIP
#   5. Proposed sorts before current (downgrade) → SKIP
#   6. (override) or (manual) flag → MANUAL
#   7. Major jump without major_hint pin → HOLD
#   8. Major jump escapes major_hint pin → HOLD
#   9. Otherwise → AUTO

[[ -n "${_GS_EU2_DECIDE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DECIDE_SH_LOADED=1

# shellcheck source=./semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/semver.sh"

# _gs_eu2_classify_decision — apply the decision ladder to one version update.
#
# Args:    $1 current       — current version string (from annotation or VAR=)
#          $2 proposed      — proposed version string (from fetcher)
#          $3 override      — "true" → MANUAL (even when proposed > current)
#          $4 manual        — "true" → MANUAL (same as override; different annotation flag)
#          $5 major_hint    — pin constraint: proposed must start with this major prefix
#          $6 unstable_mode — "full" → bypass prerelease guard (allow stable→prerelease AUTO)
#          $7 stable_mode   — "full" → force-reject prerelease in classifier (overrides all)
#          $8 record_channel— annotation channel value ("unstable", "rc", ""); when "unstable",
#                             a stable→prerelease transition becomes HOLD (annotation opt-in)
# Prints:  one of: AUTO | HOLD | MANUAL | SKIP | RESOLVED
# Returns: 0 always
#
# Note: caller in main.sh strips tag_channel_prefix before calling here so that
# decide.sh only sees plain semver strings (no leading "dev-" or "nightly-").
# Note: force-auto/force-hold in main.sh upgrade HOLD→AUTO after this function returns.
_gs_eu2_classify_decision() {
  local _cur="${1}" _prop="${2}" _override="${3:-}" _manual="${4:-}" _major_hint="${5:-}" \
        _unstable_mode="${6:-}" _stable_mode="${7:-}" _record_channel="${8:-}"

  # No proposed version → skip
  [[ -z "${_prop}" ]] && { echo "SKIP"; return 0; }

  # Unversioned current (nightly/latest/edge/stable/lts/…): semver comparison is
  # meaningless. When the fetcher has resolved a concrete proposed version, emit
  # RESOLVED (informational — never auto-applied; requires --apply-resolve --apply).
  # When _prop is empty or also unversioned, fall through to SKIP below.
  # (manual)/(override) flags are hoisted here so they apply to the float case too.
  if _gs_eu2_is_unversioned "${_cur}"; then
    if [[ -n "${_prop}" ]] && ! _gs_eu2_is_unversioned "${_prop}"; then
      # Concrete version resolved from a floating ref.
      if [[ "${_override}" == "true" || "${_manual}" == "true" ]]; then
        echo "MANUAL"; return 0   # (manual)/(override) flag on a float → MANUAL
      fi
      echo "RESOLVED"; return 0
    fi
    echo "SKIP"; return 0
  fi

  # Same version → nothing to do; SKIP even for manual/override vars.
  # manual/override means "don't auto-apply changes", not "always surface as MANUAL".
  if [[ "${_cur}" == "${_prop}" ]]; then
    echo "SKIP"; return 0
  fi

  # Prerelease guard: proposed is prerelease, current is stable.
  # Handles both dash-separated (6.3.0-rc1) and no-dash (6.3.0RC1) formats.
  # Priority: stable_mode=full (force-reject) > unstable_mode=full (bypass) > channel:unstable (HOLD) > default (SKIP)
  if _gs_eu2_is_prerelease "${_prop}" && ! _gs_eu2_is_prerelease "${_cur}"; then
    if [[ "${_stable_mode}" == "full" ]]; then
      echo "SKIP"; return 0   # --stable=full: force-reject prerelease regardless of channel
    fi
    if [[ "${_unstable_mode}" != "full" ]]; then
      if [[ "${_record_channel}" == "unstable" ]]; then
        echo "HOLD"; return 0  # annotation opt-in: needs review (major OR minor prerelease)
      fi
      echo "SKIP"; return 0    # no opt-in: skip prerelease silently
    fi
    # unstable_mode=full: bypass this gate entirely, continue to step 5+
  fi

  # Downgrade protection: if proposed sorts before current via sort -V, skip.
  # Use sort -V directly (not semver_compare) to avoid misclassifying platform
  # suffixes like -alpine3.23 as pre-release markers.
  # NOTE: runs BEFORE the manual/override check so that downgrades are suppressed
  # even for manual entries — a fetcher returning an older version is always wrong,
  # regardless of annotation flags.
  local _cv="${_cur#v}" _pv="${_prop#v}"

  # RC→stable promotion guard: sort -V puts the bare base version (37.0.0) BEFORE
  # any suffixed variant (37.0.0-rc2), which falsely triggers downgrade protection.
  # When current is a prerelease AND proposed is stable (no prerelease marker), and
  # both share the same numeric base, this is a forward promotion — skip the sort -V
  # check entirely.  Platform suffixes (e.g. -alpine3.23) are NOT detected as
  # prerelease by _gs_eu2_is_prerelease, so they are unaffected by this guard.
  local _skip_sort_v=false
  if _gs_eu2_is_prerelease "${_cv}" && ! _gs_eu2_is_prerelease "${_pv}"; then
    local _cv_base="${_cv%%-*}" _pv_base="${_pv%%-*}"
    if [[ "${_cv_base}" == "${_pv_base}" ]]; then
      _skip_sort_v=true
    fi
  fi

  if [[ "${_skip_sort_v}" == false && "${_cv}" != "${_pv}" ]]; then
    local _cv_norm _pv_norm _oldest
    _cv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_cv}")"
    _pv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_pv}")"
    _oldest="$(printf '%s\n%s\n' "${_cv_norm}" "${_pv_norm}" | sort -V | head -1)"
    if [[ "${_oldest}" == "${_pv_norm}" && "${_oldest}" != "${_cv_norm}" ]]; then
      echo "SKIP"; return 0
    fi
  fi

  # Override or manual flags → MANUAL (only reached when proposed > current AND no
  # prerelease guard fired — i.e. a genuine forward version change).
  if [[ "${_override}" == "true" || "${_manual}" == "true" ]]; then
    echo "MANUAL"; return 0
  fi

  # Determine semver delta
  local _delta
  _delta="$(_gs_eu2_semver_delta "${_cur}" "${_prop}")"

  # Major jump without major_hint pin → HOLD for review
  if [[ "${_delta}" == "major" && -z "${_major_hint}" ]]; then
    echo "HOLD"; return 0
  fi

  # C3: Major jump with pin but proposed escapes the pin → HOLD
  # Use ([.^_-]|$) anchor to prevent "18" matching "180.x"; _ for Ruby-style tags.
  if [[ -n "${_major_hint}" && ! "${_pv}" =~ ^${_major_hint}([.^_-]|$) ]]; then
    echo "HOLD"; return 0
  fi

  echo "AUTO"
}

# _gs_eu2_classify_sha_decision — classify whether the annotation SHA needs updating.
#
# Args:    $1 annotation_sha — SHA currently stored in the @todo annotation (may be empty)
#          $2 proposed_sha   — SHA fetched from the repo's HEAD (may be empty)
# Prints:  "SHA" when annotation needs updating; "SKIP" otherwise
# Returns: 0 always
#
# This is a secondary classification applied in main.sh after _gs_eu2_classify_decision.
# It can upgrade a SKIP decision to SHA when the version is current but the annotation
# sha: is stale (repo tracking HEAD with git: flag).
_gs_eu2_classify_sha_decision() {
  local _ann_sha="${1:-}" _prop_sha="${2:-}"
  # No proposed SHA → nothing to do
  [[ -z "${_prop_sha}" ]] && { echo "SKIP"; return 0; }
  # Same SHA → nothing to do
  [[ "${_ann_sha}" == "${_prop_sha}" ]] && { echo "SKIP"; return 0; }
  echo "SHA"
}
