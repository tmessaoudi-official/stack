#!/usr/bin/env bash
# Tests for the 00base tool installers and the Dockerfile lines that call them.
#
# The failure this guards (2026-09-28): difftastic 0.71.0 put the version in its
# release asset name, so install-tools.sh's URL 404'd. `curl -L` without `-f`
# saved GitHub's "Not Found" page, `tar` failed on it, `set -e` stopped the
# script, and the Dockerfile's `[ toggle ] && install-tools.sh || echo …` turned
# that failure into "Tools will not be installed" and a green 00base build. Every
# tool after difftastic (sonar-scanner-cli, bat, sops, rtk, claude, yq) was
# silently absent, and the first anyone heard of it was 02sonarqube's
# `COPY --from=… /opt/developer/sonar-scanner-cli: not found`. The same mask hid
# a gitlab-runner install that had been failing on its own for longer.
#
# Contract: a pinned asset is found under either upstream naming scheme; a
# download that 404s fails AT the download; and no Dockerfile line can turn an
# installer's failure into a success.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_TOOLS="${ROOT}/docker/images/00base/conf/bin/global-stack-base-install-tools.sh"
GITLAB_RUNNER="${ROOT}/docker/images/00base/conf/bin/global-stack-base-install-gitlab-runner.sh"
DIND="${ROOT}/docker/images/00base/conf/bin/global-stack-base-install-docker-in-docker.sh"
BASE_BIN="${ROOT}/docker/images/00base/conf/bin"
GLOBAL_UNU="${ROOT}/templates/shell/global-unu.sh"

PASS=0
FAIL=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_GREEN='' C_RED='' C_BOLD='' C_RESET=''
fi

ok() {
  PASS=$((PASS + 1))
  printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}
ko() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$1")
  printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "$1"
}
section() { printf '\n%b── %s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT

# ─── Stubs ────────────────────────────────────────────────────────────────────
# curl models the real upstream, not the script's belief about it: a URL is
# served only when its <version>/<asset> key is in PUBLISHED (the names GitHub's
# API listed for those two releases on 2026-09-28). Anything else is a 404: with
# -f/--fail curl exits 22 and writes nothing, without it curl saves the error
# page and exits 0 — exactly the silent half of the defect.
mkdir -p "${T}/stubs" "${T}/asset"
cat >"${T}/stubs/curl" <<'STUB'
#!/usr/bin/env bash
fail=0 out="" url=""
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --fail) fail=1; shift ;;
    --*) shift ;;
    -*) [[ "$1" == *f* ]] && fail=1; shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "${url}" >>"${STUB_LOG}"
if grep -qxF "${url#*/releases/download/}" "${STUB_PUBLISHED}"; then
  tar -czf "${out}" -C "${STUB_ASSET_DIR}" difft
  exit 0
fi
[[ "${fail}" == 1 ]] && exit 22
printf 'Not Found' >"${out}"
exit 0
STUB
printf '#!/usr/bin/env bash\nexec "$@"\n' >"${T}/stubs/sudo"
printf '#!/usr/bin/env bash\necho "Difftastic NEW"\n' >"${T}/asset/difft"
chmod +x "${T}/stubs/curl" "${T}/stubs/sudo" "${T}/asset/difft"
cat >"${T}/published" <<'EOF'
0.70.0/difft-x86_64-unknown-linux-gnu.tar.gz
0.71.0/difft-0.71.0-x86_64-unknown-linux-gnu.tar.gz
EOF

# Extract a block by its anchor line through the first closing `fi` at the same
# indent. An anchor that stops matching yields an empty block, which exits 0 and
# would read as a pass — hence the non-vacuity checks below.
extract() { # file anchor-regex closing-regex
  awk -v a="$2" -v c="$3" '!on && $0 ~ a {on=1} on {print} on && $0 ~ c {exit}' "$1"
}

# ─── 1. install-tools.sh: difftastic under both naming schemes ───────────────
section "1. install-tools.sh difftastic block"
blk="$(extract "${INSTALL_TOOLS}" '^if \[\[ "" != "\$\{DIFFTASTIC_OPERATING_SYSTEM\}"' '^fi$')"
if [[ "${blk}" == *'difftastic/releases/download'* && "${blk}" == *'difft'* ]]; then
  ok "1a: the difftastic block was extracted (non-vacuity)"
else
  ko "1a: the difftastic block anchor matched nothing — every case below would be vacuous"
fi
# The block writes to /usr/local/bin; point it at the sandbox. Nothing else changes.
printf '%s\n' "${blk//\/usr\/local\/bin/${T}/it-bin}" >"${T}/it-block.sh"

run_it() { # version -> sets RC, OUT
  rm -rf "${T}/it-bin" && mkdir -p "${T}/it-bin"
  : >"${T}/log"
  OUT="$(env -i PATH="${T}/stubs:/usr/bin:/bin" STUB_LOG="${T}/log" \
    STUB_PUBLISHED="${T}/published" STUB_ASSET_DIR="${T}/asset" \
    DIFFTASTIC_OPERATING_SYSTEM=unknown-linux-gnu DIFFTASTIC_ARCH=x86_64 \
    GLOBAL_STACK_DIFFTASTIC_VERSION="$1" \
    bash -eu -o pipefail "${T}/it-block.sh" 2>&1)"
  RC=$?
}
for v in 0.71.0 0.70.0; do
  run_it "${v}"
  if [[ "${RC}" -eq 0 && -x "${T}/it-bin/difft" && "$("${T}/it-bin/difft")" == "Difftastic NEW" ]]; then
    ok "1b: pin ${v} -> difft installed and runnable"
  else
    ko "1b: pin ${v} -> rc ${RC}, difft $([[ -x ${T}/it-bin/difft ]] && echo present || echo absent); urls: $(tr '\n' ' ' <"${T}/log")"
  fi
done
run_it 9.9.9
if [[ "${RC}" -ne 0 && ! -e "${T}/it-bin/difft" && "${OUT}" == *FATAL* ]]; then
  ok "1c: an unpublished pin -> a named FATAL and a non-zero exit, nothing installed"
else
  ko "1c: an unpublished pin -> rc ${RC}, difft $([[ -e ${T}/it-bin/difft ]] && echo present || echo absent), FATAL $([[ ${OUT} == *FATAL* ]] && echo named || echo missing)"
fi

# ─── 2. global-unu.sh template: the same block on the host ───────────────────
section "2. templates/shell/global-unu.sh difftastic block"
ublk="$(extract "${GLOBAL_UNU}" '^\tif \[ "" != "\$\{DIFFTASTIC_ARCH\}" \]' '^\tfi$')"
if [[ "${ublk}" == *'difftastic/releases/download'* ]]; then
  ok "2a: the difftastic block was extracted (non-vacuity)"
else
  ko "2a: the difftastic block anchor matched nothing — every case below would be vacuous"
fi
printf '%s\n' "${ublk}" >"${T}/unu-block.sh"

run_unu() { # version [old-difft] -> sets RC, OUT
  rm -rf "${T:?}/home" && mkdir -p "${T}/home/.local/bin"
  if [[ -n "${2:-}" ]]; then
    printf '#!/usr/bin/env bash\necho "Difftastic %s (old)"\n' "$2" >"${T}/home/.local/bin/difft"
    chmod +x "${T}/home/.local/bin/difft"
  fi
  : >"${T}/log"
  # The host script runs without set -e, so the block does too.
  OUT="$(env -i PATH="${T}/home/.local/bin:${T}/stubs:/usr/bin:/bin" HOME="${T}/home" \
    STUB_LOG="${T}/log" STUB_PUBLISHED="${T}/published" STUB_ASSET_DIR="${T}/asset" \
    DIFFTASTIC_OPERATING_SYSTEM=unknown-linux-gnu DIFFTASTIC_ARCH=x86_64 \
    GLOBAL_STACK_DIFFTASTIC_VERSION="$1" bash "${T}/unu-block.sh" 2>&1)"
  RC=$?
}
for v in 0.71.0 0.70.0; do
  run_unu "${v}" 0.69.0
  if [[ "$("${T}/home/.local/bin/difft")" == "Difftastic NEW" ]]; then
    ok "2b: pin ${v} over an older difft -> the new difft is installed"
  else
    ko "2b: pin ${v} -> difft reports '$("${T}/home/.local/bin/difft" 2>&1)'; urls: $(tr '\n' ' ' <"${T}/log")"
  fi
done
run_unu 9.9.9 0.70.0
if [[ "$("${T}/home/.local/bin/difft")" == "Difftastic 0.70.0 (old)" && "${OUT}" == *FATAL* ]]; then
  ok "2c: an unpublished pin -> a named FATAL and the old difft kept working"
else
  ko "2c: an unpublished pin -> difft reports '$("${T}/home/.local/bin/difft" 2>&1)', FATAL $([[ ${OUT} == *FATAL* ]] && echo named || echo missing)"
fi

# ─── 3. Every 00base installer download fails AT the download ────────────────
section "3. 00base installer curl calls"
mapfile -t curls < <(grep -nHE '(^|[[:space:]])curl[[:space:]]' "${BASE_BIN}"/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | sed "s#^${BASE_BIN}/##")
if ((${#curls[@]} >= 20)); then
  ok "3a: ${#curls[@]} curl calls found across ${BASE_BIN##*/docker/} (floor 20 — non-vacuity)"
else
  ko "3a: only ${#curls[@]} curl calls found (floor 20) — the scan is not seeing the scripts"
fi
nof=()
for l in "${curls[@]}"; do
  [[ "${l}" =~ curl[[:space:]]+(-[A-Za-z]*f[A-Za-z]*|--fail)([[:space:]]|$) ]] || nof+=("$(cut -d: -f1,2 <<<"${l}")")
done
if ((${#nof[@]} == 0)); then
  ok "3b: every curl carries -f (a 404 cannot become a saved error page)"
else
  ko "3b: curl without -f at ${nof[*]}"
fi

# ─── 4. No Dockerfile turns an installer's failure into a success ─────────────
section "4. Dockerfile '[ … ] && cmd || echo' masks"
mapfile -t dfs < <(find "${ROOT}/docker/images" -name 'Dockerfile*' -type f)
if ((${#dfs[@]} >= 40)); then
  ok "4a: ${#dfs[@]} Dockerfiles scanned, local.* included (floor 40 — non-vacuity)"
else
  ko "4a: only ${#dfs[@]} Dockerfiles found (floor 40)"
fi
# `A && B || echo` runs the echo when B FAILS, not only when A is false.
masks="$(grep -nHE '\][[:space:]]*&&[^|]*\|\|[[:space:]]*echo' "${dfs[@]}" | sed "s#^${ROOT}/##" | cut -d: -f1,2)"
if [[ -z "${masks}" ]]; then
  ok "4b: no '[ … ] && cmd || echo' line in any Dockerfile"
else
  ko "4b: masking line(s): $(tr '\n' ' ' <<<"${masks}")"
fi

# ─── 5. gitlab-runner installer ──────────────────────────────────────────────
section "5. install-gitlab-runner.sh"
# GitLab's script.deb.sh writes only the .list file now (measured 2026-09-28);
# a plain rm of both exits 1.
if grep -qE '^sudo rm -f /tmp/gitlab-runner\.sh .*runner_gitlab-runner\.list .*runner_gitlab-runner\.sources' "${GITLAB_RUNNER}"; then
  ok "5a: the repo-file cleanup tolerates the .sources file being absent (rm -f)"
else
  ko "5a: the repo-file cleanup is not 'sudo rm -f … .list … .sources'"
fi
# shellcheck disable=SC2016  # the literal ${…} is what the script must contain
mk="$(grep -n 'mkdir -p "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner"' "${GITLAB_RUNNER}" | head -1 | cut -d: -f1)"
cp_="$(grep -n '^sudo cp /etc/gitlab-runner/config.toml' "${GITLAB_RUNNER}" | head -1 | cut -d: -f1)"
if [[ -n "${mk}" && -n "${cp_}" && "${mk}" -lt "${cp_}" ]]; then
  ok "5b: ~/.gitlab-runner is created before config.toml is copied into it"
else
  ko "5b: no mkdir -p of ~/.gitlab-runner before the config.toml copy (mkdir line '${mk}', cp line '${cp_}')"
fi

# ─── 6. DinD group + rtk init user ───────────────────────────────────────────
section "6. install-docker-in-docker.sh group, install-tools.sh rtk init"
# docker-ce's postinst creates the group; a bare groupadd exits 9 (build log, 2026-09-28).
if grep -qE '^[[:space:]]*sudo groupadd docker' "${DIND}"; then
  ko "6a: a bare 'sudo groupadd docker' — exits 9 once docker-ce has created the group"
elif grep -qE 'getent group docker[^|]*\|\|[[:space:]]*sudo groupadd docker' "${DIND}"; then
  ok "6a: the docker group is created only when absent"
else
  ko "6a: no guarded groupadd for the docker group found — the anchor matched nothing"
fi
# The build runs install-tools as root; rtk --global writes to $HOME/.claude.
mapfile -t rtk_lines < <(grep -nE '^[[:space:]]*[^#]*\brtk (telemetry|init)\b' "${INSTALL_TOOLS}")
bad=()
for l in "${rtk_lines[@]}"; do
  # shellcheck disable=SC2016  # the literal ${…} is what the script must contain
  [[ "${l}" == *'sudo -u "${GLOBAL_STACK_DOCKER_USER_ID}" -H rtk '* ]] || bad+=("${l%%:*}")
done
if ((${#rtk_lines[@]} >= 2 && ${#bad[@]} == 0)); then
  ok "6b: both rtk calls run as the stack user with its HOME (not /root/.claude)"
else
  ko "6b: ${#rtk_lines[@]} rtk call(s) found (floor 2); not run as the stack user at line(s) ${bad[*]:-none}"
fi

# ─── Tally ───────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
if ((FAIL == 0)); then
  printf '\n%bALL PASSED ✓ %d / %d%b\n' "${C_GREEN}" "${PASS}" "${TOTAL}" "${C_RESET}"
  exit 0
fi
printf '\n%bFAILED ✗ %d failures / %d total%b\n' "${C_RED}" "${FAIL}" "${TOTAL}" "${C_RESET}"
exit 1
