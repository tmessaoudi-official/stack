# Open many links — new annotation format (type:identifier)

# Ubuntu dist check

look for noble|oracular|plucky|questing and try to replace them with resolute (if resolute dist exists else replace with the newest available dist) (look is there is a release)


```bash

# this first
source /etc/profile.d/stack.sh

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

# Helper: open one URL — skips duplicates, sleeps so Firefox processes each tab in order
_gs_eu_md_open_url() {
  local browser="${GLOBAL_STACK_ENV_UPDATE_NAVIGATOR:-firefox}"
  local priv_flag="${GLOBAL_STACK_ENV_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window}"
  grep -qxF "${1}" <<< "${_GS_EU_MD_SEEN_URLS}" && return 0
  _GS_EU_MD_SEEN_URLS+="${1}"$'\n'
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

done < <(awk '!seen[$0]++' .env)

# then those
for _GS_EU_MD_NODE_VERSION in $(compgen -v | grep -E '^GLOBAL_STACK_NODE([0-9]+|EDGE|[0-9]+_[0-9]+)_VERSION$'); do echo ""; echo "Node ${_GS_EU_MD_NODE_VERSION}: ${!_GS_EU_MD_NODE_VERSION}"; nvm use ${!_GS_EU_MD_NODE_VERSION}; npm --global outdated; done
GLOBA_STACK_CURRENT_DIRECTORY=$(pwd)
cd /stack/tools/serverless-framework
npm outdated
cd "${GLOBA_STACK_CURRENT_DIRECTORY}"
for _GS_EU_MD_PYTHON_VERSION in $(compgen -v | grep -E '^GLOBAL_STACK_PYTHON([0-9]+|EDGE|[0-9]+_[0-9]+)_VERSION$'); do echo ""; echo "Python ${_GS_EU_MD_PYTHON_VERSION}: ${!_GS_EU_MD_PYTHON_VERSION}"; /stack/tools/pyenv/versions/"${!_GS_EU_MD_PYTHON_VERSION}"/bin/pip"${!_GS_EU_MD_PYTHON_VERSION%.*}" list --outdated; done
sdkmanager --sdk_root="${ANDROID_HOME}" --list
sdk offline disable
echo "ant";        sdk list ant        | grep ""
echo "gradle";     sdk list gradle     | grep ""
echo "kotlin";     sdk list kotlin     | grep ""
echo "maven";      sdk list maven      | grep ""
echo "pomchecker"; sdk list pomchecker | grep ""
echo "springboot"; sdk list springboot | grep ""
echo "tomcat";     sdk list tomcat     | grep ""
echo "groovy";     sdk list groovy     | grep ""
echo "micronaut";  sdk list micronaut  | grep ""
echo "quarkus";    sdk list quarkus    | grep ""
echo "spark";      sdk list spark      | grep ""
echo "java";       sdk list java       | grep ""

bin/env-update.sh --check --no-cache
```

---

# Notes on annotation flags

- `(channel:nightly)` — vars tracked as nightly builds. env-update.sh uses lexicographic comparison (date-suffixed). The fetcher uses `url:` type with `channel:nightly` to scrape directory listings.
- `(tag-filter:REGEX)` / `(tag-strip-prefix:PREFIX)` — used for repos with non-standard tag formats (e.g. `go1.26.1` → filter `^go[0-9]`, strip `go`).
- `{VAR:format}` in `urls:` fields — resolved against `.env` values when opening supplemental links. Supports `:major` and `:major.minor` format specifiers.

---