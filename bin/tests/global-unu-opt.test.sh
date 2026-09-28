#!/usr/bin/env bash
# Tests templates/shell/global-unu-opt.sh — the installer that keeps the tools under
# /opt/$USER on their .env pin and owns their desktop launchers.
# Run: bash bin/tests/global-unu-opt.test.sh   (~5 s; no network, no docker)
#
# docs/plans/opt-developer-updater.plan.md. The guarantees under test:
#   - --check writes nothing and fetches nothing;
#   - --apply installs the PIN, and only when the installed version differs;
#   - a download, checksum or version failure leaves the installed copy byte-intact;
#   - a running app is skipped, never swapped underneath itself;
#   - nothing outside the staging dir is ever rm -rf'd;
#   - a launcher is written only after desktop-file-validate accepts it, and only
#     when its content changed.
#
# Everything runs in a temp tree through the script's seams (GS_UNU_OPT_ROOT,
# GS_UNU_OPT_APPS_DIR, GS_UNU_OPT_ENV_FILE, GS_UNU_OPT_PROC_DIR) with a stub curl
# that serves only the URLs the test registers — exiting 22 under -f otherwise,
# the way real curl does — and logs every call.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUT="${REPO_ROOT}/templates/shell/global-unu-opt.sh"

TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+w "${TMP_DIR}" 2>/dev/null; rm -rf "${TMP_DIR}"' EXIT

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
section() { printf '\n%b%s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

[[ -f "${SUT}" ]] || {
  printf '\n  %s is missing — nothing to test.\n\n' "${SUT}"
  exit 1
}
for _dep in jq sha256sum tar desktop-file-validate; do
  command -v "${_dep}" >/dev/null || {
    printf '\n  %s is required by this suite and missing.\n\n' "${_dep}"
    exit 1
  }
done

# ── Stub curl ────────────────────────────────────────────────────────────────
# Serves "$T/routes" (URL<TAB>file). Unknown URL: exit 22 under -f (real curl),
# else an HTML error page. Every call is logged to "$T/curl.log".
STUB_BIN="${TMP_DIR}/bin"
mkdir -p "${STUB_BIN}"
cat >"${STUB_BIN}/curl" <<'STUB'
#!/usr/bin/env bash
out="" fail=0 url=""
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry | --connect-timeout | --max-time) shift 2 ;;
    -*) [[ "$1" == -*f* && "$1" != --* ]] && fail=1; shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "${url}" >>"${T}/curl.log"
src="$(awk -F'\t' -v u="${url}" '$1 == u { print $2; exit }' "${T}/routes")"
if [[ -z "${src}" ]]; then
  ((fail)) && exit 22
  body='<html><body>404 Not Found</body></html>'
  if [[ -n "${out}" ]]; then printf '%s' "${body}" >"${out}"; else printf '%s' "${body}"; fi
  exit 0
fi
if [[ -n "${out}" ]]; then cp "${src}" "${out}"; else cat "${src}"; fi
# Side effect hook: a case can act DURING the archive download (e.g. start the app).
if [[ "${url}" == *.tar.gz && -f "${T}/on-archive" ]]; then bash "${T}/on-archive"; fi
STUB
chmod +x "${STUB_BIN}/curl"

# ── Fixture builders ─────────────────────────────────────────────────────────
JB_API='https://data.services.jetbrains.com/products/releases?code=IIU&type=release'

# $1 dest dir  $2 version  → a fake installed/extracted IDEA tree
_mk_idea_tree() {
  mkdir -p "$1/bin"
  printf '{"name":"IntelliJ IDEA","version":"%s","buildNumber":"263.%s","launch":[{"startupWmClass":"jetbrains-idea"}]}\n' \
    "$2" "${2##*.}" >"$1/product-info.json"
  printf '#!/bin/sh\necho idea %s\n' "$2" >"$1/bin/idea"
  chmod +x "$1/bin/idea"
  printf 'png' >"$1/bin/idea.png"
}

# $1 case dir  $2 archive version (what is INSIDE)  $3 pin/URL version
_mk_idea_release() {
  local d="$1" inside="$2" v="$3" src="$1/src"
  mkdir -p "${src}/idea-IU-263.1" "$d/srv"
  _mk_idea_tree "${src}/idea-IU-263.1" "${inside}"
  tar -czf "$d/srv/idea-${v}.tar.gz" -C "${src}" idea-IU-263.1
  printf '%s *idea-%s.tar.gz\n' "$(sha256sum "$d/srv/idea-${v}.tar.gz" | cut -d' ' -f1)" "${v}" \
    >"$d/srv/idea-${v}.tar.gz.sha256"
  printf '{"IIU":[{"version":"%s","downloads":{"linux":{"link":"https://download.jetbrains.com/idea/idea-%s.tar.gz","checksumLink":"https://download.jetbrains.com/idea/idea-%s.tar.gz.sha256"}}},{"version":"2026.2.3","downloads":{"linux":{"link":"x","checksumLink":"x"}}}]}\n' \
    "${v}" "${v}" "${v}" >"$d/srv/api.json"
  printf '%s\t%s\n' \
    "${JB_API}" "$d/srv/api.json" \
    "https://download.jetbrains.com/idea/idea-${v}.tar.gz" "$d/srv/idea-${v}.tar.gz" \
    "https://download.jetbrains.com/idea/idea-${v}.tar.gz.sha256" "$d/srv/idea-${v}.tar.gz.sha256" \
    >"$d/routes"
}

# $1 case dir → a sandbox with IDEA 2026.2.3 installed, pin $2, release $2 served
_sandbox() {
  local d="${TMP_DIR}/$1"
  mkdir -p "$d/opt/jetbrains" "$d/apps" "$d/proc"
  _mk_idea_tree "$d/opt/jetbrains/idea" 2026.2.3
  printf 'user-data\n' >"$d/opt/jetbrains/idea/keep-me"
  printf 'GLOBAL_STACK_IDEA_VERSION=%s\n' "$2" >"$d/env.local"
  : >"$d/curl.log"
  _mk_idea_release "$d" "$2" "$2"
  printf '%s' "$d"
}

# $1 case dir, rest: script args → stdout+stderr; rc in $RC
_run() {
  local d="$1"
  shift
  OUT="$(env -i HOME="$d" PATH="${STUB_BIN}:/usr/bin:/bin" T="$d" USER=tester \
    GS_UNU_OPT_ROOT="$d/opt" GS_UNU_OPT_APPS_DIR="$d/apps" \
    GS_UNU_OPT_ENV_FILE="$d/env.local" GS_UNU_OPT_PROC_DIR="$d/proc" \
    bash "${SUT}" "$@" 2>&1)"
  RC=$?
}

# Byte-level fingerprint of a tree (paths, modes, content).
_fp() { (cd "$1" && find . -printf '%p %m %s\n' | sort && find . -type f -exec sha256sum {} + | sort) | sha256sum; }

_curl_calls() { grep -c . "$1/curl.log" || true; }

# ═════════════════════════════════════════════════════════════════════════════
section "1. --check reports and changes nothing"
d="$(_sandbox c1 2026.3.1)"
before="$(_fp "$d/opt")$(_fp "$d/apps")"
_run "$d" --check
if [[ ${RC} -eq 0 ]] && grep -qE 'outdated.*idea.*2026\.2\.3.*2026\.3\.1' <<<"${OUT}"; then
  ok "1a: --check reports idea outdated 2026.2.3 → 2026.3.1 (exit 0)"
else
  ko "1a: --check did not report idea outdated (rc=${RC}): ${OUT}"
fi
_run "$d"
if grep -qE 'outdated.*idea' <<<"${OUT}"; then ok "1b: no flag means --check"; else ko "1b: default mode is not --check: ${OUT}"; fi
if [[ "$(_fp "$d/opt")$(_fp "$d/apps")" == "${before}" ]]; then
  ok "1c: /opt tree and launchers byte-identical after two check runs"
else
  ko "1c: --check changed the /opt tree or the launchers"
fi
if [[ "$(_curl_calls "$d")" == 0 ]]; then ok "1d: --check made no network call"; else ko "1d: --check called curl: $(cat "$d/curl.log")"; fi
if [[ ! -e "$d/opt/.gs-staging" && -z "$(ls -A "$d/apps")" ]]; then
  ok "1e: --check created no staging dir and wrote no launcher"
else
  ko "1e: --check wrote something: $(ls -A "$d/opt" "$d/apps")"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "2. --apply installs the pin, then is a no-op"
d="$(_sandbox c2 2026.3.1)"
printf '[Desktop Entry]\nName=Sublme Text\nCategories=PHP;\n' >"$d/apps/idea.desktop"
_run "$d" --apply
got="$(jq -r .version "$d/opt/jetbrains/idea/product-info.json" 2>/dev/null)"
if [[ ${RC} -eq 0 && "${got}" == 2026.3.1 ]]; then ok "2a: idea is 2026.3.1 after --apply"; else ko "2a: rc=${RC} version=${got}: ${OUT}"; fi
if [[ ! -e "$d/opt/jetbrains/idea/keep-me" ]]; then ok "2b: the old tree was replaced, not merged"; else ko "2b: old files survive inside the new tree"; fi
if [[ ! -e "$d/opt/.gs-staging" ]] || [[ -z "$(ls -A "$d/opt/.gs-staging")" ]]; then
  ok "2c: staging (archive + old tree) is gone"
else
  ko "2c: staging left behind: $(ls -A "$d/opt/.gs-staging")"
fi
L="$d/apps/idea.desktop"
if desktop-file-validate "${L}" >/dev/null 2>&1; then ok "2d: idea.desktop validates"; else ko "2d: idea.desktop invalid: $(desktop-file-validate "${L}" 2>&1)"; fi
if grep -qx "Exec=$d/opt/jetbrains/idea/bin/idea" "${L}" && grep -qx 'StartupWMClass=jetbrains-idea' "${L}" \
  && grep -qx 'Version=1.5' "${L}" && ! grep -q Sublme "${L}"; then
  ok "2e: hand-made launcher replaced (Exec path, WM class from product-info, spec Version)"
else
  ko "2e: launcher content wrong: $(cat "${L}")"
fi
m1="$(stat -c %Y.%i "${L}")"
: >"$d/curl.log"
sleep 1
_run "$d" --apply
if [[ ${RC} -eq 0 ]] && grep -qE 'current.*idea.*2026\.3\.1' <<<"${OUT}"; then ok "2f: second --apply reports current"; else ko "2f: rc=${RC}: ${OUT}"; fi
if [[ "$(_curl_calls "$d")" == 0 ]]; then ok "2g: second --apply fetched nothing"; else ko "2g: second --apply called curl"; fi
if [[ "$(stat -c %Y.%i "${L}")" == "${m1}" ]]; then ok "2h: unchanged launcher not rewritten"; else ko "2h: launcher rewritten with identical content"; fi

# ═════════════════════════════════════════════════════════════════════════════
section "3. every failure before the swap leaves the installed copy byte-intact"
# $1 case  $2 label  $3 mutation (runs with d set)
_fail_case() {
  local d
  d="$(_sandbox "$1" 2026.3.1)"
  eval "$3"
  local before
  before="$(_fp "$d/opt/jetbrains/idea")"
  _run "$d" --apply
  if [[ ${RC} -ne 0 && "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]]; then
    ok "$2: exit ${RC}, installed copy byte-identical"
  else
    ko "$2: rc=${RC}, installed copy changed=$([[ "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]] && echo no || echo YES): ${OUT}"
  fi
  if [[ -z "$(ls -A "$d/opt/.gs-staging" 2>/dev/null)" ]]; then ok "$2: staging cleaned"; else ko "$2: staging left: $(ls -A "$d/opt/.gs-staging")"; fi
}
_fail_case c3a "3a checksum mismatch" 'printf "%064d *x\n" 0 >"$d/srv/idea-2026.3.1.tar.gz.sha256"'
_fail_case c3b "3b archive 404" 'awk -F"\t" "\$1 !~ /tar\\.gz\$/" "$d/routes" >"$d/r" && mv "$d/r" "$d/routes"'
_fail_case c3c "3c archive holds another version" '_mk_idea_release "$d" 2026.3.0 2026.3.1'
_fail_case c3d "3d pin absent from the vendor list" 'printf "GLOBAL_STACK_IDEA_VERSION=2099.1\n" >"$d/env.local"'
_fail_case c3e "3e checksum file 404" 'awk -F"\t" "\$1 !~ /sha256\$/" "$d/routes" >"$d/r" && mv "$d/r" "$d/routes"'

# ═════════════════════════════════════════════════════════════════════════════
section "4. a running app is skipped"
d="$(_sandbox c4 2026.3.1)"
mkdir -p "$d/proc/4242"
ln -s "$d/opt/jetbrains/idea/jbr/bin/java" "$d/proc/4242/exe"
before="$(_fp "$d/opt/jetbrains/idea")"
_run "$d" --apply
if grep -qiE 'skip.*idea.*running' <<<"${OUT}" && [[ "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]]; then
  ok "4a: idea running (pid 4242) → skipped, tree untouched"
else
  ko "4a: running app not skipped (rc=${RC}): ${OUT}"
fi
if [[ "$(_curl_calls "$d")" == 0 ]]; then ok "4b: nothing downloaded for a running app"; else ko "4b: downloaded anyway: $(cat "$d/curl.log")"; fi
ln -sfn "$d/opt/jetbrains/idea-other/bin/x" "$d/proc/4242/exe"
_run "$d" --apply
got="$(jq -r .version "$d/opt/jetbrains/idea/product-info.json")"
if [[ "${got}" == 2026.3.1 ]]; then ok "4c: a sibling dir sharing the prefix (idea-other) is not 'running'"; else ko "4c: prefix match blocked the install: ${OUT}"; fi

# ═════════════════════════════════════════════════════════════════════════════
section "5. rm -rf is confined to the staging dir"
# Sourcing the script must define its functions without running main.
# Every probed path is DISPOSABLE (inside this case dir): a regressed guard must
# delete test fixtures, never "/" or $HOME.
d="${TMP_DIR}/c5"
mkdir -p "$d/opt/.gs-staging/x" "$d/victim"
printf 'precious\n' >"$d/victim/file"
_guard() {
  env -i HOME="$d" PATH="/usr/bin:/bin" GS_UNU_OPT_ROOT="$d/opt" bash -c 'source "$1"; _opt_rm_staging "$2"' _ "${SUT}" "$1" >/dev/null 2>&1
}
# Non-vacuity: every 5b "refused" below would pass if sourcing itself failed.
if env -i HOME="$d" PATH="/usr/bin:/bin" GS_UNU_OPT_ROOT="$d/opt" bash -c '[[ -z "$(source "$1" 2>&1)" ]] && source "$1" && declare -F _opt_rm_staging >/dev/null' _ "${SUT}"; then
  ok "5-: sourcing defines _opt_rm_staging and runs nothing"
else
  ko "5-: sourcing the script failed — every 5b result below is vacuous"
fi
if env -i HOME="$d" PATH="/usr/bin:/bin" bash -c 'source "$1" && [[ "${GS_UNU_OPT_ROOT}" == "/opt/$(id -un)" ]]' _ "${SUT}"; then
  ok "5-: USER unset (cron) → root defaults to /opt/\$(id -un), no unbound-variable abort"
else
  ko "5-: sourcing with USER unset failed or picked the wrong root"
fi
if _guard "$d/opt/.gs-staging/x" && [[ ! -e "$d/opt/.gs-staging/x" ]]; then ok "5a: a staging subdir is removed"; else ko "5a: staging subdir not removed"; fi
for p in "$d/victim" "$d/opt/.gs-staging" "$d/opt/.gs-staging/" "$d/opt/.gs-staging/../../victim" "$d/opt" "$d" ""; do
  if ! _guard "${p}" && [[ -f "$d/victim/file" ]]; then ok "5b: refused '${p}'"; else ko "5b: '${p}' was accepted"; fi
done

# ═════════════════════════════════════════════════════════════════════════════
section "6. launchers: validated before writing"
d="$(_sandbox c6 2026.2.3)"
printf 'OLD\n' >"$d/apps/idea.desktop"
cat >"${STUB_BIN}/desktop-file-validate" <<'STUB'
#!/bin/sh
echo "error: stubbed invalid" >&2
exit 1
STUB
chmod +x "${STUB_BIN}/desktop-file-validate"
_run "$d" --apply
rm -f "${STUB_BIN}/desktop-file-validate"
if [[ ${RC} -ne 0 && "$(cat "$d/apps/idea.desktop")" == OLD ]]; then
  ok "6a: an invalid generated launcher is never written (exit ${RC}, old file kept)"
else
  ko "6a: rc=${RC}, launcher now: $(cat "$d/apps/idea.desktop")"
fi
d="$(_sandbox c6b 2026.2.3)"
rm -rf "$d/opt/jetbrains/idea"
printf 'GLOBAL_STACK_IDEA_VERSION=\n' >"$d/env.local"
_run "$d" --apply
if [[ ${RC} -eq 0 && ! -e "$d/apps/idea.desktop" ]] && grep -qE 'unmanaged.*idea' <<<"${OUT}"; then
  ok "6b: empty pin + not installed → unmanaged, no launcher"
else
  ko "6b: rc=${RC}: ${OUT}; apps: $(ls -A "$d/apps")"
fi

d="$(_sandbox c6c 2026.2.3)"
printf 'GLOBAL_STACK_IDEA_VERSION=\n' >"$d/env.local"
_run "$d" --apply
if [[ ${RC} -eq 0 && -f "$d/apps/idea.desktop" && "$(_curl_calls "$d")" == 0 ]] && grep -qE 'unmanaged.*idea.*2026\.2\.3' <<<"${OUT}"; then
  ok "6c: empty pin + installed → nothing installed, launcher still managed (ruling: all 9 launchers)"
else
  ko "6c: rc=${RC}: ${OUT}; apps: $(ls -A "$d/apps")"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "8. the swap itself"
# _opt_install runs as the left side of ||, where set -e is inert: an unchecked
# failed mv of the OLD tree used to let the second mv move the new tree INSIDE it
# (jetbrains/idea/idea-IU-263.1/) and report INSTALLED — the PhpStorm nesting.
d="$(_sandbox c8a 2026.3.1)"
before="$(_fp "$d/opt/jetbrains/idea")"
chmod a-w "$d/opt/jetbrains"
_run "$d" --apply
chmod u+w "$d/opt/jetbrains"
nested="$(find "$d/opt/jetbrains/idea" -maxdepth 1 -name 'idea-IU-*' | head -n 1)"
if [[ ${RC} -ne 0 && -z "${nested}" && "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]]; then
  ok "8a: old tree cannot be moved aside → exit ${RC}, no nested tree, installed copy byte-identical"
else
  ko "8a: rc=${RC} nested='${nested}' changed=$([[ "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]] && echo no || echo YES): ${OUT}"
fi
if ! grep -q INSTALLED <<<"${OUT}"; then ok "8a: no INSTALLED claim"; else ko "8a: claimed INSTALLED after a failed swap"; fi

# The app is started while its multi-GB archive downloads: re-checked before the swap.
d="$(_sandbox c8b 2026.3.1)"
printf 'mkdir -p "%s/proc/999" && ln -sfn "%s/opt/jetbrains/idea/bin/idea" "%s/proc/999/exe"\n' "$d" "$d" "$d" >"$d/on-archive"
before="$(_fp "$d/opt/jetbrains/idea")"
_run "$d" --apply
if grep -qiE 'skip.*idea.*running' <<<"${OUT}" && [[ "$(_fp "$d/opt/jetbrains/idea")" == "${before}" ]]; then
  ok "8b: app started during the download → skipped at the swap, tree untouched"
else
  ko "8b: rc=${RC}: ${OUT}"
fi
if [[ -z "$(ls -A "$d/opt/.gs-staging" 2>/dev/null)" ]]; then ok "8b: staging cleaned after the late skip"; else ko "8b: staging left: $(ls -A "$d/opt/.gs-staging")"; fi

# ═════════════════════════════════════════════════════════════════════════════
section "7. fresh machine and arguments"
d="$(_sandbox c7 2026.3.1)"
rm -rf "$d/opt/jetbrains"
_run "$d" --apply --only=idea
got="$(jq -r .version "$d/opt/jetbrains/idea/product-info.json" 2>/dev/null)"
if [[ ${RC} -eq 0 && "${got}" == 2026.3.1 ]]; then ok "7a: missing tool is installed (parent dir created)"; else ko "7a: rc=${RC} got=${got}: ${OUT}"; fi
_run "$d" --only=nosuchtool
if [[ ${RC} -eq 2 ]]; then ok "7b: unknown --only id → exit 2"; else ko "7b: rc=${RC}: ${OUT}"; fi
_run "$d" --bogus
if [[ ${RC} -eq 2 ]]; then ok "7c: unknown flag → exit 2"; else ko "7c: rc=${RC}"; fi

printf '\n'
if ((FAIL == 0)); then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
  exit 0
fi
printf '  %bFAILURES%b      ✓ %d passed   ✗ %d failed   (%d total)\n' "${C_RED}" "${C_RESET}" "${PASS}" "${FAIL}" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '    • %s\n' "${f}"; done
exit 1
