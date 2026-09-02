#!/usr/bin/env bash

# this first
# _GS_EU_MD_PROFILE_SH is a test seam and nothing else: every real run resolves
# the default. Without it a sandboxed run sources the host profile and is pulled
# straight back onto the real nvm/npm/pyenv (precedent: _GS_CIV_ENV_FILE).
# shellcheck source=/dev/null
source "${_GS_EU_MD_PROFILE_SH:-/etc/profile.d/stack.sh}"

# Resolve the checkout once so `.env` below is read from the repo and not from
# the caller's cwd. Read as a bare relative path, this script enumerated
# nothing, opened ZERO links and still exited 0 from every directory but /stack
# — a run that did nothing was indistinguishable from one that worked.
# BASH_SOURCE is empty when this block is pasted into an interactive shell; the
# host checkout is required to live at /stack (CLAUDE.md § Gotchas: the
# tools/.shellrc exports bake that path in), so that is the fallback.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _GS_EU_MD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  _GS_EU_MD_ROOT="/stack"
fi
_GS_EU_MD_DOT_ENV="${_GS_EU_MD_ROOT}/.env"

## Open all (env-update) links in .env order (one loop, all types, legacy fallback)

# Types to skip when opening links (space-separated)
# Add a type here if you check it manually (e.g. npm via 'npm --global outdated')
# sdkmanager has no browser URL — always skip it here
_GS_EU_MD_OPEN_SKIP_TYPES="npm sdkmanager pypi sdkman"

# How many Ubuntu versions back to probe for url-probe annotations (newest first, only opens valid URLs)
_GS_EU_MD_URL_PROBE_BACK=9

# Resolve {VAR:format} placeholders using environment variables
# Supports: {VAR}, {VAR:major}, {VAR:major.minor}
_gs_eu_md_resolve_url_vars() {
  local input="${1}"
  perl -pe '
    s#\{([A-Z_][A-Z0-9_]*)(?::([^}]+))?\}#
      my ($var, $fmt) = ($1, defined($2) ? $2 : "");
      my $val = $ENV{$var} // "";
      if ($fmt eq "major") {
        $val =~ s|[.\-].*$||;
      } elsif ($fmt eq "major.minor") {
        $val =~ s|^([0-9]+\.[0-9]+).*$|$1|;
      }
      $val
    #ge
  ' <<< "${input}"
}

# Track already-opened URLs so we never open the same tab twice (newline-separated string)
_GS_EU_MD_SEEN_URLS=""

# How many URLs were actually handed to the browser. Zero is a failure, not a
# clean run: it means the .env scan below matched nothing at all.
_GS_EU_MD_OPENED=0

# Helper: open one URL — skips duplicates, sleeps so Firefox processes each tab in order
_gs_eu_md_open_url() {
  local browser="${GLOBAL_STACK_ENV_UPDATE_NAVIGATOR:-firefox}"
  local priv_flag="${GLOBAL_STACK_ENV_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window}"
  grep -qxF "${1}" <<< "${_GS_EU_MD_SEEN_URLS}" && return 0
  _GS_EU_MD_SEEN_URLS+="${1}"$'\n'
  _GS_EU_MD_OPENED=$((_GS_EU_MD_OPENED + 1))
  "${browser}" "${priv_flag}" "${1}" &
  wait $!
  sleep 0.4
}

while read -r line; do
  [[ "${line}" =~ @todo.*env-update ]] || continue

  url=""
  _type=""

  # url: — identifier IS the URL
  if [[ "${line}" =~ url:(https?://[^[:space:]]+) ]]; then
    _type="url"
    url="${BASH_REMATCH[1]}"
  # github:owner/repo[:major]
  elif [[ "${line}" =~ github:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+) ]]; then
    _type="github"
    url="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/releases"
  # codeberg:owner/repo
  elif [[ "${line}" =~ codeberg:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+) ]]; then
    _type="codeberg"
    url="https://codeberg.org/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/releases"
  # ghcr:owner/image (GitHub Container Registry) — ghcr.io redirects to the GitHub package page
  elif [[ "${line}" =~ ghcr:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+) ]]; then
    _type="ghcr"
    url="https://ghcr.io/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  # dockerhub:_/image (official library image) — must come before generic user/image to avoid /r/_/image
  elif [[ "${line}" =~ dockerhub:_/([a-zA-Z0-9_.-]+) ]]; then
    _type="dockerhub"
    url="https://hub.docker.com/_/${BASH_REMATCH[1]}/tags"
  # dockerhub:user/image
  elif [[ "${line}" =~ dockerhub:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+) ]]; then
    _type="dockerhub"
    url="https://hub.docker.com/r/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/tags"
  # dockerhub:image (official, no slash — legacy)
  elif [[ "${line}" =~ dockerhub:([a-zA-Z0-9_.-]+) ]]; then
    _type="dockerhub"
    url="https://hub.docker.com/_/${BASH_REMATCH[1]}/tags"
  # quay:org/image
  elif [[ "${line}" =~ quay:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+) ]]; then
    _type="quay"
    url="https://quay.io/repository/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}?tab=tags"
  # npm:package (including scoped @scope/pkg)
  elif [[ "${line}" =~ npm:(@?[a-zA-Z0-9_./+-]+) ]]; then
    _type="npm"
    url="https://www.npmjs.com/package/${BASH_REMATCH[1]}"
  # pypi:package
  elif [[ "${line}" =~ pypi:([a-zA-Z0-9_.-]+) ]]; then
    _type="pypi"
    url="https://pypi.org/project/${BASH_REMATCH[1]}/"
  # pecl:name
  elif [[ "${line}" =~ pecl:([a-zA-Z0-9_-]+) ]]; then
    _type="pecl"
    url="https://pecl.php.net/package/${BASH_REMATCH[1]}"
  # sdkman:tool
  elif [[ "${line}" =~ sdkman:([a-zA-Z0-9_-]+) ]]; then
    _type="sdkman"
    url="https://sdkman.io/sdks#${BASH_REMATCH[1]}"
  # sdkmanager: — no browser URL (use terminal: sdkmanager --sdk_root="${ANDROID_HOME}" --list)
  elif [[ "${line}" =~ sdkmanager:([a-zA-Z0-9_.-]+) ]]; then
    _type="sdkmanager"
    # no url — handled via terminal command above
  # rubygems:package
  elif [[ "${line}" =~ rubygems:([a-zA-Z0-9_-]+) ]]; then
    _type="rubygems"
    url="https://rubygems.org/gems/${BASH_REMATCH[1]}"
  fi

  # Skip ignored types
  if [[ -n "${_type}" ]] && [[ " ${_GS_EU_MD_OPEN_SKIP_TYPES} " == *" ${_type} "* ]]; then
    continue
  fi

  if [[ -n "${url}" ]]; then
    # New format: open the constructed URL
    _gs_eu_md_open_url "${url}"
    # Also open any urls: reference links on the same line (supplementary)
    # {VAR:format} placeholders are resolved against .env values loaded above
    if [[ "${line}" =~ [[:space:]]urls:[[:space:]]+(.*) ]]; then
      for ref_url in ${BASH_REMATCH[1]}; do
        [[ "${ref_url}" =~ ^https?:// ]] || continue
        # Resolve {VAR:format} placeholders
        if [[ "${ref_url}" == *'{'* ]]; then
          ref_url="$(_gs_eu_md_resolve_url_vars "${ref_url}")"
        fi
        _gs_eu_md_open_url "${ref_url}"
      done
    fi
    # pecl-ref: open the PECL package page when annotation has (pecl-ref:NAME)
    _re_pecl_ref="[(]pecl-ref:([a-zA-Z0-9_-]+)[)]"
    if [[ "${line}" =~ ${_re_pecl_ref} ]]; then
      _gs_eu_md_open_url "https://pecl.php.net/package/${BASH_REMATCH[1]}"
    fi
    # git: open the GitHub commits page when annotation has (git:org/repo) — SHA-pinned pecl extensions
    _re_git_ref="[(]git:([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)[)]"
    if [[ "${line}" =~ ${_re_git_ref} ]]; then
      _gs_eu_md_open_url "https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
    # url-probe: probe the last _GS_EU_MD_URL_PROBE_BACK Ubuntu versions (newest first)
    # curl-probes each URL first — only opens tabs for versions that actually exist (2xx/3xx)
    _re_url_probe="[(]url-probe:([^)]+)[)]"
    if [[ "${line}" =~ ${_re_url_probe} ]]; then
      _probe_paths="${BASH_REMATCH[1]}"
      # All Ubuntu codenames in release order (oldest → newest)
      _all_cns=(xenial bionic focal jammy kinetic lunar mantic noble oracular plucky questing resolute)
      _all_cn_vers=(16.04 18.04 20.04 22.04 22.10 23.04 23.10 24.04 24.10 25.04 25.10 26.04)
      # Find current codename's index in the list
      _cn_base="${GLOBAL_STACK_IMAGE_UBUNTU_VERSION%%-*}"
      _cn_idx=$(( ${#_all_cns[@]} - 1 ))  # default to newest if not found
      for _pi in "${!_all_cns[@]}"; do
        [[ "${_all_cns[_pi]}" == "${_cn_base}" ]] && _cn_idx="${_pi}"
      done
      # Clamp start index so we don't go below 0
      _probe_start=$(( _cn_idx - _GS_EU_MD_URL_PROBE_BACK + 1 ))
      [[ "${_probe_start}" -lt 0 ]] && _probe_start=0
      IFS=',' read -ra _probe_path_list <<< "${_probe_paths}"
      for _probe_path_tpl in "${_probe_path_list[@]}"; do
        for (( _pi = _cn_idx; _pi >= _probe_start; _pi-- )); do
          _pcn="${_all_cns[_pi]}"
          _pcn_ver="${_all_cn_vers[_pi]}"
          _probe_path="${_probe_path_tpl//\{codename\}/${_pcn}}"
          _probe_path="${_probe_path//\{codename-version\}/${_pcn_ver}}"
          _probe_url="${url%/}/${_probe_path}"
          _http_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${_probe_url}" 2>/dev/null || true)"
          [[ "${_http_code}" =~ ^[23] ]] && _gs_eu_md_open_url "${_probe_url}"
        done
      done
    fi
  else
    # Legacy fallback: old-format lines with raw URLs — open all of them in order
    while IFS= read -r raw_url; do
      [[ -z "${raw_url}" ]] && continue
      _gs_eu_md_open_url "${raw_url}"
    done < <(grep -oE 'https?://[^[:space:]]+' <<< "${line}")
  fi

done < <(awk '!seen[$0]++' "${_GS_EU_MD_DOT_ENV}")

# A run that opened nothing did not succeed quietly — the .env above was
# unreadable, or carries no annotations at all. Say so and stop. Pasted into an
# interactive shell this block must not close the developer's terminal, so the
# exit is taken only when running as a script ($- carries 'i' only when
# interactive) — same paste-safety rule as the `(cd X && cmd)` form below.
if ((_GS_EU_MD_OPENED == 0)); then
  echo "ERROR: no links opened — ${_GS_EU_MD_DOT_ENV} is unreadable or has no '@todo env-update' annotations" >&2
  [[ "$-" == *i* ]] || exit 1
fi

# then those
for _GS_EU_MD_NODE_VERSION in $(compgen -v | grep -E '^GLOBAL_STACK_NODE([0-9]+|EDGE|[0-9]+_[0-9]+)_VERSION$'); do echo ""; echo "Node ${_GS_EU_MD_NODE_VERSION}: ${!_GS_EU_MD_NODE_VERSION}"; nvm use "${!_GS_EU_MD_NODE_VERSION}"; npm --global outdated; done
(cd /stack/tools/serverless-framework && npm outdated)
for _GS_EU_MD_PYTHON_VERSION in $(compgen -v | grep -E '^GLOBAL_STACK_PYTHON([0-9]+|EDGE|[0-9]+_[0-9]+)_VERSION$'); do echo ""; echo "Python ${_GS_EU_MD_PYTHON_VERSION}: ${!_GS_EU_MD_PYTHON_VERSION}"; /stack/tools/pyenv/versions/"${!_GS_EU_MD_PYTHON_VERSION}"/bin/pip"${!_GS_EU_MD_PYTHON_VERSION%.*}" list --outdated; done
sdkmanager --sdk_root="${ANDROID_HOME}" --list

# The block below steers sdkman's healthcheck by rewriting ~/.sdkman/etc/config.
# That file belongs to the developer, not to this script: it used to be clobbered
# by the first `>`, deleted outright by `rm -rf`, and left as the single line
# `sdkman_healthcheck_enable=false` even when the run SUCCEEDED. Capture its
# exact bytes here — before the first write — and put them back on every path out.
_GS_EU_MD_SDK_CFG="${HOME}/.sdkman/etc/config"
_GS_EU_MD_SDK_CFG_BAK=""
# Tracked separately from the backup path: inferring "there was a file" from
# "the backup variable is non-empty" is wrong on exactly the path that matters.
# If mktemp fails, the variable is empty while the developer's config very much
# exists, and the restore would take the never-existed branch and DELETE it.
# Defence in depth rather than the live fix: the _SAFE guard below skips the
# whole block when the capture failed, so restore is currently never reached in
# that state and no test can tell this flag from the old inference. It keeps
# _gs_eu_md_sdk_cfg_restore correct on its own terms, so moving or reusing the
# block later cannot silently reopen the deletion path.
_GS_EU_MD_SDK_CFG_EXISTED=false
_GS_EU_MD_SDK_CFG_SAFE=true
if [[ -f "${_GS_EU_MD_SDK_CFG}" ]]; then
  _GS_EU_MD_SDK_CFG_EXISTED=true
  _GS_EU_MD_SDK_CFG_BAK="$(mktemp)"
  # The capture is verified, not assumed. mktemp creates the file, so a cp that
  # fails leaves a 0-byte "backup" that restores cleanly over the original and
  # even passes cmp — both sides being empty.
  if [[ -z "${_GS_EU_MD_SDK_CFG_BAK}" ]] \
    || ! cp -p "${_GS_EU_MD_SDK_CFG}" "${_GS_EU_MD_SDK_CFG_BAK}" \
    || ! cmp -s "${_GS_EU_MD_SDK_CFG}" "${_GS_EU_MD_SDK_CFG_BAK}"; then
    _GS_EU_MD_SDK_CFG_SAFE=false
  fi
fi

# Idempotent on purpose: it runs once explicitly at the end and once more from
# the EXIT trap. It deliberately does NOT clear the trap — a handler that
# returns hands control back to the script, and the lines after it would rewrite
# the file again with nothing armed to undo them. The backup is deleted HERE and
# only after a verified restore: deleting it in the caller would throw away the
# developer's only copy on the very path the WARN says it is being kept.
_gs_eu_md_sdk_cfg_restore() {
  if [[ "${_GS_EU_MD_SDK_CFG_EXISTED}" != true ]]; then
    # No config existed before this run: remove only what the script created.
    rm -f "${_GS_EU_MD_SDK_CFG}"
    return 0
  fi
  [[ -n "${_GS_EU_MD_SDK_CFG_BAK}" && -f "${_GS_EU_MD_SDK_CFG_BAK}" ]] || return 0
  if cp -p "${_GS_EU_MD_SDK_CFG_BAK}" "${_GS_EU_MD_SDK_CFG}" \
    && cmp -s "${_GS_EU_MD_SDK_CFG_BAK}" "${_GS_EU_MD_SDK_CFG}"; then
    rm -f "${_GS_EU_MD_SDK_CFG_BAK}"
  else
    echo "WARN: could not restore ${_GS_EU_MD_SDK_CFG} — your original is kept at ${_GS_EU_MD_SDK_CFG_BAK}" >&2
  fi
}

if [[ "${_GS_EU_MD_SDK_CFG_SAFE}" != true ]]; then
  # Never write to a file that could not be backed up. Listing sdk versions is
  # not worth the developer's config, so the whole block is skipped instead.
  echo "ERROR: could not back up ${_GS_EU_MD_SDK_CFG} — skipping the sdkman version listing rather than risk it" >&2
else
  # EXIT alone is the right signal set: a non-interactive bash killed by INT or
  # TERM runs its EXIT trap and stops [Verified: exit 130 / 143, the line after
  # the kill never runs], so trapping those too would only resume the script
  # mid-block. Not armed interactively, where it would displace the developer's
  # own EXIT trap.
  [[ "$-" == *i* ]] || trap _gs_eu_md_sdk_cfg_restore EXIT

  mkdir -p "${HOME}/.sdkman/etc/"
  touch "${HOME}/.sdkman/etc/config"

  echo "sdkman_healthcheck_enable=true" > "${HOME}/.sdkman/etc/config"

  source "${HOME}/.sdkman/etc/config"

  rm -rf "${HOME}/.sdkman/etc/config"
  # Enumerate sdkman tools dynamically from .env @todo env-update annotations so this
  # list can never drift: extract each sdkman:TOOL identifier (the char class stops at
  # the ':' before any :major suffix, so java:17 → java), strip the prefix, dedup.
  while read -r _GS_EU_MD_SDK_TOOL; do
    [[ -z "${_GS_EU_MD_SDK_TOOL}" ]] && continue
    echo "${_GS_EU_MD_SDK_TOOL}"
    sdk list "${_GS_EU_MD_SDK_TOOL}" | grep ""
  done < <(grep -E '@todo.*env-update.*sdkman:' "${_GS_EU_MD_DOT_ENV}" | grep -oE 'sdkman:[a-zA-Z0-9_-]+' | sed 's/^sdkman://' | sort -u)

  echo "sdkman_healthcheck_enable=false" > "${HOME}/.sdkman/etc/config"

  source "${HOME}/.sdkman/etc/config"

  # The shell now carries sdkman_healthcheck_enable=false, which is the point of
  # the two writes above. Hand the file itself back exactly as it was found.
  _gs_eu_md_sdk_cfg_restore
fi
