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
# Every argv, so a case can prove a secret never reached the command line.
printf '%s\n' "$*" >>"${T}/curl-argv.log"
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    # A header, or "@-": the header lines on stdin (how a token is passed).
    -H)
      if [[ "$2" == @- ]]; then cat >>"${T}/headers.log"; else printf '%s\n' "$2" >>"${T}/headers.log"; fi
      shift 2
      ;;
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

# ── Stub sudo ────────────────────────────────────────────────────────────────
# Logs every call to "$T/sudo.log". "$T/no-sudo" present: exits 1, as `sudo -n`
# does with no cached credentials. chown to root cannot happen as a user, so it
# only does what the kernel does to the file: chown(2) clears setuid/setgid — so a
# chmod 4755 placed BEFORE the chown is undone, as on the real machine. chmod is
# applied (setuid on one's own file is allowed).
cat >"${STUB_BIN}/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${T}/sudo.log"
# sudo -v is the operator typing a password: it works unless "$T/deny-v" exists, and
# afterwards `sudo -n` succeeds (the credentials are cached).
if [[ "$1" == -v ]]; then
  [[ -e "${T}/deny-v" ]] && exit 1
  rm -f "${T}/no-sudo"
  exit 0
fi
[[ -e "${T}/no-sudo" ]] && exit 1
[[ "$1" == -n ]] && shift
case "$1" in
  chown) exec chmod u-s,g-s "${@: -1}" ;;
  chmod) exec chmod "${@:2}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${STUB_BIN}/sudo"

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
  # stdin is closed on purpose: a run from a terminal must never reach the engine's
  # interactive `sudo -v`. The fixtures belong to the test user, not root, so the
  # sandbox owner the engine expects is a seam (default root; a case that needs a
  # "correct" sandbox sets SANDBOX_OWNER to the test user).
  OUT="$(env -i HOME="$d" PATH="${STUB_BIN}:/usr/bin:/bin" T="$d" USER=tester \
    GS_UNU_OPT_ROOT="$d/opt" GS_UNU_OPT_APPS_DIR="$d/apps" \
    GS_UNU_OPT_ENV_FILE="$d/env.local" GS_UNU_OPT_PROC_DIR="$d/proc" \
    GS_UNU_OPT_SANDBOX_OWNER="${SANDBOX_OWNER:-root}" \
    bash "${SUT}" "$@" 2>&1 </dev/null)"
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

# Two FAILED paths park the previous tree at .gs-staging/<id>/old and say so; the
# next run must refuse rather than wipe staging and delete the only copy.
d="$(_sandbox c8c 2026.3.1)"
mkdir -p "$d/opt/.gs-staging/idea/old"
printf 'parked tree\n' >"$d/opt/.gs-staging/idea/old/marker"
b_old="$(_fp "$d/opt/.gs-staging/idea/old")" b_inst="$(_fp "$d/opt/jetbrains/idea")"
_run "$d" --apply
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/.gs-staging/idea/old")" == "${b_old}" && "$(_fp "$d/opt/jetbrains/idea")" == "${b_inst}" ]] \
  && ! grep -q DOWNLOAD <<<"${OUT}"; then
  ok "8c: a parked staging/old stops the install (exit ${RC}); parked and installed trees byte-identical, nothing downloaded"
else
  ko "8c: rc=${RC}, parked tree $([[ -e "$d/opt/.gs-staging/idea/old/marker" ]] && echo kept || echo DELETED): ${OUT}"
fi

if grep -q 'compare them, keep one' <<<"${OUT}"; then ok "8c: installed tree present → message says compare, not 'move it back'"; else ko "8c: wrong remedy: ${OUT}"; fi

d="$(_sandbox c8d 2026.3.1)"
mkdir -p "$d/opt/.gs-staging/idea/old"
mv "$d/opt/jetbrains/idea" "$d/opt/.gs-staging/idea/old/tree"
_run "$d" --apply
if [[ ${RC} -ne 0 && -d "$d/opt/.gs-staging/idea/old/tree" ]] && grep -q "put it back with: mv" <<<"${OUT}"; then
  ok "8d: nothing installed + parked tree → exit ${RC}, tree kept, message gives the mv back"
else
  ko "8d: rc=${RC}: ${OUT}"
fi

# A tree an install already REPLACED is superseded, not parked: it must not block.
d="$(_sandbox c8e 2026.3.1)"
mkdir -p "$d/opt/.gs-staging/idea/superseded"
printf 'leftover\n' >"$d/opt/.gs-staging/idea/superseded/marker"
_run "$d" --apply
got="$(jq -r .version "$d/opt/jetbrains/idea/product-info.json")"
if [[ ${RC} -eq 0 && "${got}" == 2026.3.1 && -z "$(ls -A "$d/opt/.gs-staging" 2>/dev/null)" ]]; then
  ok "8e: a leftover superseded/ does not block; the install wipes it"
else
  ko "8e: rc=${RC} got=${got}: ${OUT}"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "9. fresh machine and arguments"
d="$(_sandbox c7 2026.3.1)"
rm -rf "$d/opt/jetbrains"
_run "$d" --apply --only=idea
got="$(jq -r .version "$d/opt/jetbrains/idea/product-info.json" 2>/dev/null)"
if [[ ${RC} -eq 0 && "${got}" == 2026.3.1 ]]; then ok "9a: missing tool is installed (parent dir created)"; else ko "9a: rc=${RC} got=${got}: ${OUT}"; fi
_run "$d" --only=nosuchtool
if [[ ${RC} -eq 2 ]]; then ok "9b: unknown --only id → exit 2"; else ko "9b: rc=${RC}: ${OUT}"; fi
_run "$d" --bogus
if [[ ${RC} -eq 2 ]]; then ok "9c: unknown flag → exit 2"; else ko "9c: rc=${RC}"; fi

# ═════════════════════════════════════════════════════════════════════════════
section "10. tool rows: JetBrains IDEs and Android Studio"
# Each shipped row, fresh machine: --apply installs exactly the pin into its
# dir, writes its launcher under the name the hand-made one had, and a second
# --check reads the installed version back as current (no network).

# $1 case dir  $2 API code  $3 archive url  $4 top dir  $5 bin  $6 version  $7 wm class
_mk_jb_like() {
  local d="$1" code="$2" url="$3" top="$4" bin="$5" v="$6" wm="$7" src="$1/src" a
  a="$d/srv/$(basename "${url}")"
  mkdir -p "${src}/${top}/bin" "$d/srv"
  printf '{"version":"%s","launch":[{"startupWmClass":"%s"}]}\n' "${v}" "${wm}" >"${src}/${top}/product-info.json"
  printf '#!/bin/sh\n' >"${src}/${top}/bin/${bin}"
  chmod +x "${src}/${top}/bin/${bin}"
  printf 'png' >"${src}/${top}/bin/${bin}.png"
  tar -czf "${a}" -C "${src}" "${top}"
  SUM="$(sha256sum "${a}" | cut -d' ' -f1)"
  printf '%s\t%s\n' "${url}" "${a}" >>"$d/routes"
}

# $1 id  $2 pin var  $3 install dir  $4 bin  $5 launcher file  $6 wm class  $7 pin
_row_case() {
  local id="$1" var="$2" dir="$3" bin="$4" desk="$5" wm="$6" pin="$7" d="${TMP_DIR}/row-$1"
  mkdir -p "$d/opt" "$d/apps" "$d/proc" "$d/srv"
  : >"$d/curl.log"
  : >"$d/routes"
  printf '%s=%s\n' "${var}" "${pin}" >"$d/env.local"
  if [[ "${id}" == android_studio ]]; then
    local url="https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.1.4.9/android-studio-quail4-patch2-linux.tar.gz"
    _mk_jb_like "$d" - "${url}" android-studio studio "${pin}" "${wm}"
    printf '{"content":{"item":[{"version":"2026.2.1.1","channel":"Canary","build":"AI-262.1.1.2621.1","download":[]},{"version":"2026.1.4.9","channel":"Patch","build":"%s","download":[{"link":"https://edgedl.me.gvt1.com/x.deb","checksum":"0"},{"link":"%s","checksum":"%s"}]}]}}\n' \
      "${pin}" "${url}" "${SUM}" >"$d/srv/list.json"
    printf '%s\t%s\n' 'https://jb.gg/android-studio-releases-list.json' "$d/srv/list.json" >>"$d/routes"
  else
    local code url
    # The vendor's product codes, from the live API (2026-09-28) — never read from the SUT.
    case "${id}" in
      phpstorm) code=PS ;;
      webstorm) code=WS ;;
    esac
    url="https://download.jetbrains.com/x/${bin}-${pin}.tar.gz"
    _mk_jb_like "$d" "${code}" "${url}" "${bin}-263.1" "${bin}" "${pin}" "${wm}"
    printf '%s  %s\n' "${SUM}" "${bin}-${pin}.tar.gz" >"$d/srv/sum"
    printf '{"%s":[{"version":"%s","downloads":{"linux":{"link":"%s","checksumLink":"%s.sha256"}}}]}\n' \
      "${code}" "${pin}" "${url}" "${url}" >"$d/srv/api.json"
    printf '%s\t%s\n' \
      "https://data.services.jetbrains.com/products/releases?code=${code}&type=release" "$d/srv/api.json" \
      "${url}.sha256" "$d/srv/sum" >>"$d/routes"
  fi
  _run "$d" --apply --only="${id}"
  local got L="$d/apps/${desk}"
  got="$(jq -r .version "$d/opt/${dir}/product-info.json" 2>/dev/null)"
  if [[ ${RC} -eq 0 && "${got}" == "${pin}" ]]; then ok "10 ${id}: --apply installs ${pin} into ${dir}"; else ko "10 ${id}: rc=${RC} got='${got}': ${OUT}"; fi
  if desktop-file-validate "${L}" >/dev/null 2>&1 && grep -qx "Exec=$d/opt/${dir}/bin/${bin}" "${L}" \
    && grep -qx "Icon=$d/opt/${dir}/bin/${bin}.png" "${L}" && grep -qx "StartupWMClass=${wm}" "${L}"; then
    ok "10 ${id}: ${desk} valid (Exec, Icon, StartupWMClass=${wm})"
  else
    ko "10 ${id}: launcher ${desk}: $(cat "${L}" 2>&1)"
  fi
  : >"$d/curl.log"
  _run "$d" --check --only="${id}"
  if grep -qE "current.*${id} ${pin}" <<<"${OUT}" && [[ "$(_curl_calls "$d")" == 0 ]]; then
    ok "10 ${id}: --check reads it back as current, offline"
  else
    ko "10 ${id}: --check: ${OUT}"
  fi
}
_row_case phpstorm GLOBAL_STACK_PHPSTORM_VERSION jetbrains/phpstorm phpstorm phpstorm.desktop jetbrains-phpstorm 2026.3.1
_row_case webstorm GLOBAL_STACK_WEBSTORM_VERSION jetbrains/webstorm webstorm webstorm.desktop jetbrains-webstorm 2026.3.1
_row_case android_studio GLOBAL_STACK_ANDROID_STUDIO_VERSION android-studio studio android-studio.desktop jetbrains-studio AI-261.26222.65.2614.16500000

# ═════════════════════════════════════════════════════════════════════════════
section "11. tool rows: VS Code, Devin, Sublime Text"
# Shapes from the real vendor archives (2026-09-28): VS Code → VSCode-linux-x64/ with
# resources/app/package.json .version; Devin → Devin/ with resources/app/product.json
# .windsurfVersion; Sublime → sublime_text/ whose changelog.txt names the build first.

# $1 case dir  $2 id  $3 pin var  $4 pin → a fresh sandbox (nothing installed)
_fresh() {
  local d="${TMP_DIR}/$1"
  mkdir -p "$d/opt" "$d/apps" "$d/proc" "$d/srv" "$d/src"
  : >"$d/curl.log"
  : >"$d/routes"
  printf '%s=%s\n' "$3" "$4" >"$d/env.local"
  printf '%s' "$d"
}
# $1 case dir  $2 root dir name  $3 archive url  $4 tar flag (z|J) → SUM set
_pack() {
  local a
  a="$1/srv/$(basename "$3")"
  tar -c"$4"f "${a}" -C "$1/src" "$2"
  SUM="$(sha256sum "${a}" | cut -d' ' -f1)"
  printf '%s\t%s\n' "$3" "${a}" >>"$1/routes"
}
# $1 case dir  $2 id  $3 launcher file  $4 installed exec  $5 installed icon  $6 pin  $7 version reader (jq path or 'changelog')
_row_assert() {
  local d="$1" id="$2" L="$1/apps/$3"
  if [[ ${RC} -eq 0 ]] && grep -q "INSTALLED.*${id} $6" <<<"${OUT}"; then ok "11 ${id}: --apply installs $6"; else ko "11 ${id}: rc=${RC}: ${OUT}"; fi
  if desktop-file-validate "${L}" >/dev/null 2>&1 && grep -qx "Exec=$d/opt/$4 %F" "${L}" && grep -qx "Icon=$d/opt/$5" "${L}" \
    && ! grep -q '^StartupWMClass=' "${L}"; then
    ok "11 ${id}: $3 valid (Exec %F, Icon, no unverified StartupWMClass)"
  else
    ko "11 ${id}: launcher $3: $(cat "${L}" 2>&1)"
  fi
  : >"$d/curl.log"
  _run "$d" --check --only="${id}"
  if grep -qE "current.*${id} $6" <<<"${OUT}" && [[ "$(_curl_calls "$d")" == 0 ]]; then ok "11 ${id}: --check reads $6 back, offline"; else ko "11 ${id}: --check: ${OUT}"; fi
}

# VS Code: pinned download from the versions API, sha256hash.
d="$(_fresh c11code code GLOBAL_STACK_VSCODE_VERSION 1.140.0)"
mkdir -p "$d/src/VSCode-linux-x64/resources/app/resources/linux"
printf '{"version":"1.140.0"}\n' >"$d/src/VSCode-linux-x64/resources/app/package.json"
printf 'png' >"$d/src/VSCode-linux-x64/resources/app/resources/linux/code.png"
printf '#!/bin/sh\n' >"$d/src/VSCode-linux-x64/code" && chmod +x "$d/src/VSCode-linux-x64/code"
printf 'elf' >"$d/src/VSCode-linux-x64/chrome-sandbox" && chmod 755 "$d/src/VSCode-linux-x64/chrome-sandbox"
_pack "$d" VSCode-linux-x64 'https://vscode.download.prss.microsoft.com/dbazure/download/stable/abc/code-stable-x64-1.tar.gz' z
printf '{"productVersion":"1.140.0","url":"https://vscode.download.prss.microsoft.com/dbazure/download/stable/abc/code-stable-x64-1.tar.gz","sha256hash":"%s"}\n' "${SUM}" >"$d/srv/v.json"
printf '%s\t%s\n' 'https://update.code.visualstudio.com/api/versions/1.140.0/linux-x64/stable' "$d/srv/v.json" >>"$d/routes"
_run "$d" --apply --only=code
_row_assert "$d" code code.desktop code/code code/resources/app/resources/linux/code.png 1.140.0

# Devin: the Windsurf feed only serves its LATEST build — a pin must equal it.
_devin_src() { # $1 case dir  $2 version inside
  mkdir -p "$1/src/Devin/resources/app/resources/linux"
  printf '{"nameShort":"Devin","version":"1.127.0","windsurfVersion":"%s"}\n' "$2" >"$1/src/Devin/resources/app/product.json"
  printf 'png' >"$1/src/Devin/resources/app/resources/linux/code.png"
  printf '#!/bin/sh\n' >"$1/src/Devin/devin-desktop" && chmod +x "$1/src/Devin/devin-desktop"
  printf 'elf' >"$1/src/Devin/chrome-sandbox" && chmod 755 "$1/src/Devin/chrome-sandbox"
}
DEVIN_FEED='https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest'
d="$(_fresh c11devin devin GLOBAL_STACK_DEVIN_VERSION 3.11.0)"
_devin_src "$d" 3.11.0
_pack "$d" Devin 'https://windsurf-stable.codeiumdata.com/linux-x64/stable/abc/Devin-linux-x64-3.11.0.tar.gz' z
printf '{"url":"https://windsurf-stable.codeiumdata.com/linux-x64/stable/abc/Devin-linux-x64-3.11.0.tar.gz","windsurfVersion":"3.11.0","sha256hash":"%s"}\n' "${SUM}" >"$d/srv/feed.json"
printf '%s\t%s\n' "${DEVIN_FEED}" "$d/srv/feed.json" >>"$d/routes"
_run "$d" --apply --only=devin
_row_assert "$d" devin devin.desktop devin/devin-desktop devin/resources/app/resources/linux/code.png 3.11.0
printf 'GLOBAL_STACK_DEVIN_VERSION=3.10.35\n' >"$d/env.local"
before="$(_fp "$d/opt/devin")"
_run "$d" --apply --only=devin
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/devin")" == "${before}" ]] && grep -q '3.10.35.*no longer downloadable' <<<"${OUT}" \
  && ! grep -q 'tar.gz$' "$d/curl.log"; then
  ok "11 devin: a pin the feed no longer serves → exit ${RC}, names the pin, nothing downloaded, tree untouched"
else
  ko "11 devin: stale pin: rc=${RC}: ${OUT}"
fi

# Sublime: no published checksum — installed on its build number alone, and says so.
d="$(_fresh c11subl sublime_text GLOBAL_STACK_SUBLIME_TEXT_VERSION 4216)"
mkdir -p "$d/src/sublime_text/Icon/256x256"
printf '<h3>Build 4216</h3>\n<p>fixes</p>\n<h3>Build 4215</h3>\n' >"$d/src/sublime_text/changelog.txt"
printf 'png' >"$d/src/sublime_text/Icon/256x256/sublime-text.png"
printf '#!/bin/sh\necho EXECUTED >"%s/ran"\n' "$d" >"$d/src/sublime_text/sublime_text" && chmod +x "$d/src/sublime_text/sublime_text"
_pack "$d" sublime_text 'https://download.sublimetext.com/sublime_text_build_4216_x64.tar.xz' J
_run "$d" --apply --only=sublime_text
_row_assert "$d" sublime_text sublime_text.desktop sublime_text/sublime_text sublime_text/Icon/256x256/sublime-text.png 4216
d2="$(_fresh c11subl2 sublime_text GLOBAL_STACK_SUBLIME_TEXT_VERSION 4216)"
cp "$d/srv/"*.tar.xz "$d2/srv/"
printf '%s\t%s\n' 'https://download.sublimetext.com/sublime_text_build_4216_x64.tar.xz' "$d2/srv/sublime_text_build_4216_x64.tar.xz" >>"$d2/routes"
_run "$d2" --apply --only=sublime_text
if grep -q 'NOCHECKSUM.*sublime_text' <<<"${OUT}" && [[ ! -e "$d/ran" && ! -e "$d2/ran" ]]; then
  ok "11 sublime_text: installed without a checksum says so, and the staged binary was never executed"
else
  ko "11 sublime_text: NOCHECKSUM missing or the binary ran: ${OUT}"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "12. CLI rows moved from global-unu.sh: task, bat, sonar-scanner-cli"
# Shapes from the real releases (2026-09-28): task → a FLAT tar.gz (no top dir)
# listed in task_checksums.txt; bat → bat-<v>-x86_64-unknown-linux-gnu/, NO
# published checksum, version = first "# v…" of CHANGELOG.md; sonar →
# sonar-scanner-<v>-linux-<arch>/ in a zip with a bare-hash .sha256 next to it,
# version = lib/sonar-scanner-cli-<v>.jar. No launchers: they are on PATH.

# task
d="$(_fresh c12task task GLOBAL_STACK_TASK_VERSION v3.54.0)"
mkdir -p "$d/src/flat"
printf '#!/bin/sh\necho 3.54.0\n' >"$d/src/flat/task" && chmod +x "$d/src/flat/task"
printf 'readme\n' >"$d/src/flat/README.md"
tar -czf "$d/srv/task_linux_amd64.tar.gz" -C "$d/src/flat" task README.md
printf '%s  task_3.54.0_linux_amd64.deb\n%s  task_linux_amd64.tar.gz\n' "$(printf '%064d' 1)" "$(sha256sum "$d/srv/task_linux_amd64.tar.gz" | cut -d' ' -f1)" >"$d/srv/sums"
printf '%s\t%s\n' \
  'https://github.com/go-task/task/releases/download/v3.54.0/task_linux_amd64.tar.gz' "$d/srv/task_linux_amd64.tar.gz" \
  'https://github.com/go-task/task/releases/download/v3.54.0/task_checksums.txt' "$d/srv/sums" >>"$d/routes"
_run "$d" --apply --only=task
if [[ ${RC} -eq 0 && -x "$d/opt/task/task" && -f "$d/opt/task/README.md" ]] && grep -q 'INSTALLED.*task v3.54.0' <<<"${OUT}"; then
  ok "12 task: flat archive installed into task/ (checksum from task_checksums.txt)"
else
  ko "12 task: rc=${RC}: ${OUT}; tree: $(ls -A "$d/opt/task" 2>&1)"
fi
if [[ -z "$(ls -A "$d/apps")" ]]; then ok "12 task: no launcher for a CLI tool"; else ko "12 task: wrote a launcher: $(ls "$d/apps")"; fi
: >"$d/curl.log"
_run "$d" --check --only=task
if grep -qE 'current.*task v3.54.0' <<<"${OUT}" && [[ "$(_curl_calls "$d")" == 0 ]]; then ok "12 task: --check reads v3.54.0 back, offline"; else ko "12 task: --check: ${OUT}"; fi
d="$(_fresh c12task2 task GLOBAL_STACK_TASK_VERSION v3.54.0)"
cp "${TMP_DIR}/c12task/srv/task_linux_amd64.tar.gz" "$d/srv/"
printf '%s  task_linux_amd64.tar.gz\n' "$(printf '%064d' 7)" >"$d/srv/sums"
printf '%s\t%s\n' \
  'https://github.com/go-task/task/releases/download/v3.54.0/task_linux_amd64.tar.gz' "$d/srv/task_linux_amd64.tar.gz" \
  'https://github.com/go-task/task/releases/download/v3.54.0/task_checksums.txt' "$d/srv/sums" >>"$d/routes"
_run "$d" --apply --only=task
if [[ ${RC} -ne 0 && ! -e "$d/opt/task" ]]; then ok "12 task: a checksums.txt that disagrees → nothing installed"; else ko "12 task: bad checksum installed anyway (rc=${RC}): ${OUT}"; fi

# bat: no checksum; version from CHANGELOG.md; the staged binary never runs
d="$(_fresh c12bat bat GLOBAL_STACK_BAT_VERSION v0.27.0)"
top=bat-v0.27.0-x86_64-unknown-linux-gnu
mkdir -p "$d/src/${top}"
printf '# v0.27.0\n\n## Features\n\n# v0.26.1\n' >"$d/src/${top}/CHANGELOG.md"
printf '#!/bin/sh\necho RAN >"%s/ran"\n' "$d" >"$d/src/${top}/bat" && chmod +x "$d/src/${top}/bat"
_pack "$d" "${top}" "https://github.com/sharkdp/bat/releases/download/v0.27.0/${top}.tar.gz" z
_run "$d" --apply --only=bat
if [[ ${RC} -eq 0 && -x "$d/opt/bat/bat" && ! -e "$d/ran" ]] && grep -q 'NOCHECKSUM.*bat' <<<"${OUT}"; then
  ok "12 bat: installed on its CHANGELOG version, NOCHECKSUM logged, binary never executed"
else
  ko "12 bat: rc=${RC} ran=$([[ -e "$d/ran" ]] && echo YES || echo no): ${OUT}"
fi
_run "$d" --check --only=bat
if grep -qE 'current.*bat v0.27.0' <<<"${OUT}" && [[ ! -e "$d/ran" ]]; then ok "12 bat: --check current without running bat"; else ko "12 bat: --check: ${OUT}"; fi

# sonar-scanner-cli (zip)
_mk_sonar() { # $1 case dir  $2 version  $3 arch
  local top="sonar-scanner-$2-linux-$3"
  mkdir -p "$1/src/${top}/lib" "$1/src/${top}/bin"
  printf 'jar' >"$1/src/${top}/lib/sonar-scanner-cli-$2.jar"
  printf '#!/bin/sh\n' >"$1/src/${top}/bin/sonar-scanner" && chmod +x "$1/src/${top}/bin/sonar-scanner"
  (cd "$1/src" && zip -qr "$1/srv/sonar-scanner-cli-$2-linux-$3.zip" "${top}")
  sha256sum "$1/srv/sonar-scanner-cli-$2-linux-$3.zip" | cut -d' ' -f1 | tr -d '\n' >"$1/srv/zip.sha256"
  printf '%s\t%s\n' \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$2-linux-$3.zip" "$1/srv/sonar-scanner-cli-$2-linux-$3.zip" \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$2-linux-$3.zip.sha256" "$1/srv/zip.sha256" >>"$1/routes"
}
d="$(_fresh c12sonar sonar_scanner_cli GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION 8.2.0.7000)"
_mk_sonar "$d" 8.2.0.7000 x64
_run "$d" --apply --only=sonar_scanner_cli
if [[ ${RC} -eq 0 && -x "$d/opt/sonar-scanner-cli/bin/sonar-scanner" ]] && grep -q 'INSTALLED.*sonar_scanner_cli 8.2.0.7000' <<<"${OUT}"; then
  ok "12 sonar: zip installed into sonar-scanner-cli/ (bare-hash .sha256)"
else
  ko "12 sonar: rc=${RC}: ${OUT}"
fi
_run "$d" --check --only=sonar_scanner_cli
if grep -qE 'current.*sonar_scanner_cli 8.2.0.7000' <<<"${OUT}"; then ok "12 sonar: --check reads the jar version back"; else ko "12 sonar: --check: ${OUT}"; fi

# Architecture: aarch64 gets sonar's aarch64 zip; tools published for x86_64 only
# are reported unsupported — never fed an x86_64 archive, never a failure.
d="$(_fresh c12arm sonar_scanner_cli GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION 8.2.0.7000)"
printf 'GLOBAL_STACK_TASK_VERSION=v3.54.0\nGLOBAL_STACK_IDEA_VERSION=2026.3.1\n' >>"$d/env.local"
_mk_sonar "$d" 8.2.0.7000 aarch64
OUT="$(env -i HOME="$d" PATH="${STUB_BIN}:/usr/bin:/bin" T="$d" USER=tester GS_UNU_OPT_MACHINE=aarch64 \
  GS_UNU_OPT_ROOT="$d/opt" GS_UNU_OPT_APPS_DIR="$d/apps" GS_UNU_OPT_ENV_FILE="$d/env.local" GS_UNU_OPT_PROC_DIR="$d/proc" \
  bash "${SUT}" --apply --only=sonar_scanner_cli,task,idea 2>&1)"
RC=$?
if [[ ${RC} -eq 0 && -d "$d/opt/sonar-scanner-cli" ]] && grep -qE 'unsupported.*task.*aarch64' <<<"${OUT}" && grep -qE 'unsupported.*idea.*aarch64' <<<"${OUT}" \
  && ! grep -qE 'task_linux|idea-' "$d/curl.log"; then
  ok "12 arch: aarch64 → sonar's aarch64 zip installed; task and idea unsupported (nothing fetched, exit 0)"
else
  ko "12 arch: rc=${RC}: ${OUT}; curl: $(cat "$d/curl.log")"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "13. global-unu.sh runs it last, with --apply"
# The hook is the "# >>> gs-unu-opt" … "# <<< gs-unu-opt" block of the SHIPPED
# global-unu.sh, extracted by anchor (never by line number) and run next to a stub
# global-unu-opt.sh — the whole script would run apt, snap and curl.
UNU="${REPO_ROOT}/templates/shell/global-unu.sh"
HOOK="$(sed -n '/^# >>> gs-unu-opt/,/^# <<< gs-unu-opt/p' "${UNU}")"
if [[ "$(grep -c . <<<"${HOOK}")" -ge 4 ]]; then ok "13-: hook block extracted ($(grep -c . <<<"${HOOK}") lines)"; else ko "13-: no '# >>> gs-unu-opt' block in global-unu.sh — every 13x below is vacuous"; fi
# $1 case  $2 stub body ('' = no sibling) → OUT, RC
_hook_run() {
  local d="${TMP_DIR}/$1"
  mkdir -p "$d"
  printf '%s\n' "${HOOK}" >"$d/global-unu.sh"
  [[ -n "$2" ]] && printf '#!/usr/bin/env bash\necho "ARGS:$*" >"%s/args"\n%s\n' "$d" "$2" >"$d/global-unu-opt.sh"
  OUT="$(cd / && env -i PATH=/usr/bin:/bin bash "$d/global-unu.sh" 2>&1)"
  RC=$?
}
_hook_run c13a 'exit 0'
if [[ ${RC} -eq 0 && "$(cat "${TMP_DIR}/c13a/args")" == "ARGS:--apply" ]]; then ok "13a: calls the sibling global-unu-opt.sh with --apply (found from its own dir, cwd /)"; else ko "13a: rc=${RC} args=$(cat "${TMP_DIR}/c13a/args" 2>&1): ${OUT}"; fi
_hook_run c13b 'exit 1'
if [[ ${RC} -ne 0 ]] && grep -q 'global-unu-opt.sh' <<<"${OUT}"; then ok "13b: a failing installer fails global-unu.sh (exit ${RC}), named"; else ko "13b: rc=${RC}: ${OUT}"; fi
_hook_run c13c ''
if [[ ${RC} -ne 0 ]] && grep -q 'not found' <<<"${OUT}"; then ok "13c: a missing sibling fails loudly (exit ${RC})"; else ko "13c: rc=${RC}: ${OUT}"; fi
last_other="$(grep -nE '^(if |[a-z_]+\(\)|curl |sudo )' "${UNU}" | tail -n 1 | cut -d: -f1)"
hook_end="$(grep -n '^# <<< gs-unu-opt' "${UNU}" | cut -d: -f1)"
succ="$(grep -n 'echo -e "Successful :)"' "${UNU}" | cut -d: -f1)"
if [[ -n "${hook_end}" && -n "${succ}" && "${hook_end}" -lt "${succ}" && "${last_other}" -lt "${hook_end}" ]]; then
  ok "13d: the hook is the last step, before 'Successful :)'"
else
  ko "13d: hook end=${hook_end} last other step=${last_other} Successful=${succ}"
fi
if ! grep -qE '/opt/\$\{USER\}/(task|bat|sonar-scanner-cli)|GLOBAL_STACK_(TASK|BAT|SONAR_SCANNER_CLI)_VERSION' "${UNU}"; then
  ok "13e: global-unu.sh no longer installs task, bat or sonar-scanner-cli itself"
else
  ko "13e: global-unu.sh still installs a moved tool: $(grep -nE '/opt/\$\{USER\}/(task|bat|sonar)|GLOBAL_STACK_(TASK|BAT|SONAR_SCANNER_CLI)_VERSION' "${UNU}" | head -3)"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "14. tool rows: MeGit, balenaEtcher"
# Shapes from the real 2026-09-28 archives: MeGit → MeGit/ whose version is the
# plugins/com.eclipsesource.megit.plugin_<X.Y.Z>.<qualifier>.jar name, checked
# against GitHub's asset digest (its only checksum); Etcher → balenaEtcher-linux-x64/
# whose version is package.json inside resources/app.asar, checked against the
# release's SHA256SUMS.Linux.x64.txt, and whose chrome-sandbox must end up root
# setuid. Both binaries write $T/ran if executed: a staged binary never may be.
TOKEN=ghp_TESTTOKEN0000000000000000000000000000
_mk_megit_src() { # $1 dest parent  $2 version (X.Y.Z)
  mkdir -p "$1/MeGit/plugins/org.eclipse.platform_4.39.0.v1"
  # shellcheck disable=SC2016 # $T expands when the stub runs, not here
  printf '#!/bin/sh\ntouch "$T/ran"\n' >"$1/MeGit/megit" && chmod +x "$1/MeGit/megit"
  printf 'jar' >"$1/MeGit/plugins/com.eclipsesource.megit.plugin_$2.20260428-1215.jar"
  printf 'png' >"$1/MeGit/plugins/org.eclipse.platform_4.39.0.v1/eclipse512.png"
}
# $1 case dir  $2 version  $3 arch  $4 digest override ('' = the real one) → routes
_megit_release() {
  local d="$1" v="$2" a="megit-$2-linux.gtk.$3.tar.gz" dg
  _mk_megit_src "$d/src" "$v"
  tar -czf "$d/srv/${a}" -C "$d/src" MeGit
  dg="${4:-sha256:$(sha256sum "$d/srv/${a}" | cut -d' ' -f1)}"
  jq -n --arg a "${a}" --arg v "$v" --arg dg "${dg}" '{tag_name: ("v" + $v), assets: [
      {name: ("megit-" + $v + "-macosx.cocoa.x86_64.tar.gz"), digest: "sha256:00", browser_download_url: "https://example.invalid/mac"},
      {name: $a, digest: $dg, browser_download_url: ("https://github.com/eclipsesource/megit/releases/download/v" + $v + "/" + $a)}]}' >"$d/srv/release.json"
  printf '%s\t%s\n' \
    "https://api.github.com/repos/eclipsesource/megit/releases/tags/v$v" "$d/srv/release.json" \
    "https://github.com/eclipsesource/megit/releases/download/v$v/${a}" "$d/srv/${a}" >>"$d/routes"
}
# $1 dest dir (the app tree)  $2 version → an Electron-shaped Etcher tree with a real
# asar header (pickle: u32 4, u32 header size, u32 payload, u32 json len, json, pad).
_mk_etcher_tree() {
  mkdir -p "$1/resources"
  # shellcheck disable=SC2016 # $T expands when the stub runs, not here
  printf '#!/bin/sh\ntouch "$T/ran"\n' >"$1/balena-etcher" && chmod +x "$1/balena-etcher"
  printf 'elf' >"$1/chrome-sandbox" && chmod 755 "$1/chrome-sandbox"
  python3 - "$1/resources/app.asar" "$2" <<'PY'
import json, struct, sys
pkg = json.dumps({"name": "balena-etcher", "version": sys.argv[2]}).encode()
hdr = json.dumps({"files": {"package.json": {"size": len(pkg), "offset": "0"}}}).encode()
pad = b"\0" * (-len(hdr) % 4)
payload = 4 + len(hdr) + len(pad)
open(sys.argv[1], "wb").write(struct.pack("<IIII", 4, payload + 4, payload, len(hdr)) + hdr + pad + pkg)
PY
}
# $1 case dir  $2 version  $3 list the zip in SHA256SUMS? (1/0) → routes
_etcher_release() {
  local d="$1" z="balenaEtcher-linux-x64-$2.zip" base="https://github.com/balena-io/etcher/releases/download/v$2"
  _mk_etcher_tree "$d/src/balenaEtcher-linux-x64" "$2"
  (cd "$d/src" && zip -qr "$d/srv/${z}" balenaEtcher-linux-x64)
  {
    printf 'f8678185cbc76e51bc465607e001147a7c7239f31d21f2712fcc6e372bc29809  balena-etcher-%s-1.x86_64.rpm\n' "$2"
    [[ "$3" == 1 ]] && printf '%s  %s\n' "$(sha256sum "$d/srv/${z}" | cut -d' ' -f1)" "${z}"
  } >"$d/srv/sums.txt"
  printf '%s\t%s\n' "${base}/SHA256SUMS.Linux.x64.txt" "$d/srv/sums.txt" "${base}/${z}" "$d/srv/${z}" >>"$d/routes"
}

# MeGit, fresh, with a token: installed, the token sent as a header on stdin only.
d="$(_fresh c14m megit GLOBAL_STACK_MEGIT_VERSION v0.12.0)"
printf 'GLOBAL_STACK_GITHUB_TOKEN=%s\n' "${TOKEN}" >>"$d/env.local"
_megit_release "$d" 0.12.0 x86_64 ''
_run "$d" --apply --only=megit
if [[ ${RC} -eq 0 && -x "$d/opt/megit/megit" && ! -e "$d/ran" ]] && grep -q 'INSTALLED.*megit v0.12.0' <<<"${OUT}"; then
  ok "14a: MeGit installed into megit/ against the asset digest, binary never run"
else
  ko "14a: rc=${RC} ran=$([[ -e "$d/ran" ]] && echo YES || echo no): ${OUT}"
fi
if grep -qx "Authorization: Bearer ${TOKEN}" "$d/headers.log" 2>/dev/null && ! grep -q "${TOKEN}" "$d/curl-argv.log"; then
  ok "14b: the token went to api.github.com as a header on stdin, never in curl's argv"
else
  ko "14b: headers=$(cat "$d/headers.log" 2>&1) argv-has-token=$(grep -c "${TOKEN}" "$d/curl-argv.log")"
fi
L="$d/apps/megit.desktop"
if desktop-file-validate "${L}" >/dev/null 2>&1 && grep -qx "Exec=$d/opt/megit/megit" "${L}" && grep -qx 'StartupWMClass=megit' "${L}" \
  && grep -qx "Icon=$d/opt/megit/plugins/org.eclipse.platform_4.39.0.v1/eclipse512.png" "${L}"; then
  ok "14c: megit.desktop valid (Exec, StartupWMClass=megit, the Eclipse platform icon)"
else
  ko "14c: megit.desktop: $(cat "${L}" 2>&1)"
fi
: >"$d/curl.log"
_run "$d" --check --only=megit
if grep -qE 'current.*megit v0.12.0' <<<"${OUT}" && [[ "$(_curl_calls "$d")" == 0 && ! -e "$d/ran" ]]; then ok "14d: --check reads v0.12.0 from the plugin jar name, offline"; else ko "14d: --check: ${OUT}"; fi

# MeGit without a token: anonymous, no Authorization header at all.
d="$(_fresh c14anon megit GLOBAL_STACK_MEGIT_VERSION v0.12.0)"
_megit_release "$d" 0.12.0 x86_64 ''
_run "$d" --apply --only=megit
if [[ ${RC} -eq 0 ]] && grep -q 'INSTALLED.*megit v0.12.0' <<<"${OUT}" && ! grep -qi 'authorization' "$d/headers.log" 2>/dev/null; then
  ok "14e: no token → anonymous call, no Authorization header, still installed"
else
  ko "14e: rc=${RC} headers=$(cat "$d/headers.log" 2>&1): ${OUT}"
fi

# MeGit: a wrong digest, and a release without the asset → the old tree is untouched.
d="$(_fresh c14bad megit GLOBAL_STACK_MEGIT_VERSION v0.12.0)"
_mk_megit_src "$d/old" 0.11.0 && mv "$d/old/MeGit" "$d/opt/megit"
before="$(_fp "$d/opt/megit")"
_megit_release "$d" 0.12.0 x86_64 "sha256:$(printf '0%.0s' {1..64})"
_run "$d" --apply --only=megit
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/megit")" == "${before}" ]] && grep -q 'sha256 mismatch' <<<"${OUT}"; then
  ok "14f: a digest mismatch fails and leaves the installed MeGit byte-identical"
else
  ko "14f: rc=${RC}: ${OUT}"
fi
d="$(_fresh c14noasset megit GLOBAL_STACK_MEGIT_VERSION v0.12.0)"
_megit_release "$d" 0.12.0 aarch64 ''
_run "$d" --apply --only=megit
if [[ ${RC} -ne 0 ]] && grep -q 'megit-0.12.0-linux.gtk.x86_64.tar.gz' <<<"${OUT}" && ! grep -q '\.tar\.gz$' "$d/curl.log"; then
  ok "14g: a release without the x86_64 asset fails naming it, nothing downloaded"
else
  ko "14g: rc=${RC}: ${OUT}; curl: $(cat "$d/curl.log")"
fi

# Etcher over an installed 2.1.7 (root setuid sandbox, as on the real machine).
d="$(_fresh c14e balena_etcher GLOBAL_STACK_BALENA_ETCHER_VERSION v2.2.0)"
_mk_etcher_tree "$d/opt/balena-etcher" 2.1.7 && chmod 4755 "$d/opt/balena-etcher/chrome-sandbox"
_etcher_release "$d" 2.2.0 1
_run "$d" --apply --only=balena_etcher
sb_stage="$d/opt/.gs-staging/balena_etcher/x/balenaEtcher-linux-x64/chrome-sandbox"
if [[ ${RC} -eq 0 && ! -e "$d/ran" ]] && grep -q 'INSTALLED.*balena_etcher v2.2.0' <<<"${OUT}"; then
  ok "14h: Etcher v2.2.0 installed against SHA256SUMS.Linux.x64.txt, binary never run"
else
  ko "14h: rc=${RC} ran=$([[ -e "$d/ran" ]] && echo YES || echo no): ${OUT}"
fi
if grep -qx -- "-n chown root:root ${sb_stage}" "$d/sudo.log" 2>/dev/null && grep -qx -- "-n chmod 4755 ${sb_stage}" "$d/sudo.log" \
  && [[ "$(stat -c %a "$d/opt/balena-etcher/chrome-sandbox")" == 4755 ]]; then
  ok "14i: chrome-sandbox made root:root 4755 with sudo -n on the STAGED tree, before the swap"
else
  ko "14i: sudo.log=$(cat "$d/sudo.log" 2>&1) mode=$(stat -c %a "$d/opt/balena-etcher/chrome-sandbox" 2>&1)"
fi
L="$d/apps/balena-etcher.desktop"
if desktop-file-validate "${L}" >/dev/null 2>&1 && grep -qx "Exec=$d/opt/balena-etcher/balena-etcher" "${L}" \
  && grep -qx 'Categories=Utility;' "${L}" && ! grep -qE '^(Icon|StartupWMClass)=' "${L}"; then
  ok "14j: balena-etcher.desktop valid (Exec, Utility, no Icon it does not ship, no unverified StartupWMClass)"
else
  ko "14j: balena-etcher.desktop: $(cat "${L}" 2>&1)"
fi
: >"$d/curl.log"
_run "$d" --check --only=balena_etcher
if grep -qE 'current.*balena_etcher v2.2.0' <<<"${OUT}" && [[ "$(_curl_calls "$d")" == 0 && ! -e "$d/ran" ]]; then ok "14k: --check reads v2.2.0 from the app.asar header, offline, without running it"; else ko "14k: --check: ${OUT}"; fi

# Etcher with no cached sudo, and with SHA256SUMS not listing the zip.
d="$(_fresh c14nosudo balena_etcher GLOBAL_STACK_BALENA_ETCHER_VERSION v2.2.0)"
_mk_etcher_tree "$d/opt/balena-etcher" 2.1.7 && chmod 4755 "$d/opt/balena-etcher/chrome-sandbox"
before="$(_fp "$d/opt/balena-etcher")"
_etcher_release "$d" 2.2.0 1
: >"$d/no-sudo"
_run "$d" --apply --only=balena_etcher
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/balena-etcher")" == "${before}" && ! -e "$d/opt/.gs-staging/balena_etcher" ]] && grep -q 'chrome-sandbox' <<<"${OUT}" && grep -q 'sudo' <<<"${OUT}"; then
  ok "14l: no cached sudo → FAILED naming chrome-sandbox and sudo; installed 2.1.7 byte-identical, staging gone"
else
  ko "14l: rc=${RC}: ${OUT}"
fi
d="$(_fresh c14nosum balena_etcher GLOBAL_STACK_BALENA_ETCHER_VERSION v2.2.0)"
_etcher_release "$d" 2.2.0 0
_run "$d" --apply --only=balena_etcher
if [[ ${RC} -ne 0 ]] && grep -q 'balenaEtcher-linux-x64-2.2.0.zip' <<<"${OUT}" && ! grep -q '\.zip$' "$d/curl.log"; then
  ok "14m: SHA256SUMS not listing the zip fails naming it, nothing downloaded"
else
  ko "14m: rc=${RC}: ${OUT}; curl: $(cat "$d/curl.log")"
fi

# Order: only a CHECKSUMMED chrome-sandbox may become root setuid. A zip whose hash
# does not match must fail before sudo is ever called.
d="$(_fresh c14order balena_etcher GLOBAL_STACK_BALENA_ETCHER_VERSION v2.2.0)"
_mk_etcher_tree "$d/opt/balena-etcher" 2.1.7 && chmod 4755 "$d/opt/balena-etcher/chrome-sandbox"
before="$(_fp "$d/opt/balena-etcher")"
_etcher_release "$d" 2.2.0 1
sed -i -E 's/^[0-9a-f]{64}(  balenaEtcher-linux-x64-2\.2\.0\.zip)$/'"$(printf '0%.0s' {1..64})"'\1/' "$d/srv/sums.txt"
_run "$d" --apply --only=balena_etcher
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/balena-etcher")" == "${before}" && ! -e "$d/sudo.log" ]] && grep -q 'sha256 mismatch' <<<"${OUT}"; then
  ok "14o: a zip failing its sha256 never reaches sudo — setuid only ever lands on a checksummed sandbox"
else
  ko "14o: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && cat "$d/sudo.log" || echo no): ${OUT}"
fi

# aarch64: MeGit takes its aarch64 asset; Etcher (x86_64-only) is unsupported.
d="$(_fresh c14arm megit GLOBAL_STACK_MEGIT_VERSION v0.12.0)"
printf 'GLOBAL_STACK_BALENA_ETCHER_VERSION=v2.2.0\n' >>"$d/env.local"
_megit_release "$d" 0.12.0 aarch64 ''
OUT="$(env -i HOME="$d" PATH="${STUB_BIN}:/usr/bin:/bin" T="$d" USER=tester GS_UNU_OPT_MACHINE=aarch64 \
  GS_UNU_OPT_ROOT="$d/opt" GS_UNU_OPT_APPS_DIR="$d/apps" GS_UNU_OPT_ENV_FILE="$d/env.local" GS_UNU_OPT_PROC_DIR="$d/proc" \
  bash "${SUT}" --apply --only=megit,balena_etcher 2>&1)"
RC=$?
if [[ ${RC} -eq 0 && -d "$d/opt/megit" ]] && grep -qE 'unsupported.*balena_etcher.*aarch64' <<<"${OUT}" && ! grep -q 'etcher' "$d/curl.log"; then
  ok "14n: aarch64 → MeGit's aarch64 asset installed; Etcher unsupported, nothing fetched"
else
  ko "14n: rc=${RC}: ${OUT}; curl: $(cat "$d/curl.log")"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "15. Electron sandbox: VS Code, Devin and Etcher end up with a root setuid chrome-sandbox"
# Electron aborts at startup ("The SUID sandbox helper binary was found, but is not
# configured correctly … aborting") unless <tree>/chrome-sandbox is root-owned 4755 —
# measured on the real Devin 2026-09-29, where an upgrade left developer:developer 755.
# Fixtures belong to the test user, so a "correct" sandbox needs SANDBOX_OWNER=$ME.
ME="$(id -un)"
_mk_devin_tree() { # $1 dest dir  $2 version
  mkdir -p "$1/resources/app/resources/linux"
  printf '{"nameShort":"Devin","version":"1.127.0","windsurfVersion":"%s"}\n' "$2" >"$1/resources/app/product.json"
  printf 'png' >"$1/resources/app/resources/linux/code.png"
  printf '#!/bin/sh\n' >"$1/devin-desktop" && chmod +x "$1/devin-desktop"
  printf 'elf' >"$1/chrome-sandbox" && chmod 755 "$1/chrome-sandbox"
}
_devin_release() { # $1 case dir  $2 version  $3 'nosandbox' = the archive lacks chrome-sandbox
  local u="https://windsurf-stable.codeiumdata.com/linux-x64/stable/abc/Devin-linux-x64-$2.tar.gz"
  _mk_devin_tree "$1/src/Devin" "$2"
  [[ "${3:-}" == nosandbox ]] && rm -f "$1/src/Devin/chrome-sandbox"
  _pack "$1" Devin "${u}" z
  printf '{"url":"%s","windsurfVersion":"%s","sha256hash":"%s"}\n' "${u}" "$2" "${SUM}" >"$1/srv/feed.json"
  printf '%s\t%s\n' "${DEVIN_FEED}" "$1/srv/feed.json" >>"$1/routes"
}
_mk_code_tree() { # $1 dest dir  $2 version
  mkdir -p "$1/resources/app/resources/linux"
  printf '{"version":"%s"}\n' "$2" >"$1/resources/app/package.json"
  printf 'png' >"$1/resources/app/resources/linux/code.png"
  printf '#!/bin/sh\n' >"$1/code" && chmod +x "$1/code"
  printf 'elf' >"$1/chrome-sandbox" && chmod 755 "$1/chrome-sandbox"
}
_code_release() { # $1 case dir  $2 version
  local u="https://vscode.download.prss.microsoft.com/dbazure/download/stable/abc/code-stable-x64-$2.tar.gz"
  _mk_code_tree "$1/src/VSCode-linux-x64" "$2"
  _pack "$1" VSCode-linux-x64 "${u}" z
  printf '{"productVersion":"%s","url":"%s","sha256hash":"%s"}\n' "$2" "${u}" "${SUM}" >"$1/srv/v.json"
  printf '%s\t%s\n' "https://update.code.visualstudio.com/api/versions/$2/linux-x64/stable" "$1/srv/v.json" >>"$1/routes"
}

# Devin and VS Code over an installed older build: the STAGED sandbox is made root
# 4755 with sudo -n before the swap, so the live tree is never without it.
d="$(_fresh c15a devin GLOBAL_STACK_DEVIN_VERSION 3.11.0)"
_mk_devin_tree "$d/opt/devin" 3.10.35 && chmod 4755 "$d/opt/devin/chrome-sandbox"
_devin_release "$d" 3.11.0
_run "$d" --apply --only=devin
sb_stage="$d/opt/.gs-staging/devin/x/Devin/chrome-sandbox"
if [[ ${RC} -eq 0 ]] && grep -q 'INSTALLED.*devin 3.11.0' <<<"${OUT}" \
  && grep -qx -- "-n chown root:root ${sb_stage}" "$d/sudo.log" 2>/dev/null && grep -qx -- "-n chmod 4755 ${sb_stage}" "$d/sudo.log" \
  && [[ "$(stat -c %a "$d/opt/devin/chrome-sandbox")" == 4755 ]]; then
  ok "15a: Devin 3.11.0 installed; its STAGED chrome-sandbox made root:root 4755 with sudo -n before the swap"
else
  ko "15a: rc=${RC} sudo.log=$(cat "$d/sudo.log" 2>&1) mode=$(stat -c %a "$d/opt/devin/chrome-sandbox" 2>&1): ${OUT}"
fi
d="$(_fresh c15b code GLOBAL_STACK_VSCODE_VERSION 1.141.0)"
_mk_code_tree "$d/opt/code" 1.140.0 && chmod 4755 "$d/opt/code/chrome-sandbox"
_code_release "$d" 1.141.0
_run "$d" --apply --only=code
sb_stage="$d/opt/.gs-staging/code/x/VSCode-linux-x64/chrome-sandbox"
if [[ ${RC} -eq 0 ]] && grep -q 'INSTALLED.*code 1.141.0' <<<"${OUT}" \
  && grep -qx -- "-n chown root:root ${sb_stage}" "$d/sudo.log" 2>/dev/null && grep -qx -- "-n chmod 4755 ${sb_stage}" "$d/sudo.log" \
  && [[ "$(stat -c %a "$d/opt/code/chrome-sandbox")" == 4755 ]]; then
  ok "15b: VS Code 1.141.0 installed; its STAGED chrome-sandbox made root:root 4755 with sudo -n before the swap"
else
  ko "15b: rc=${RC} sudo.log=$(cat "$d/sudo.log" 2>&1) mode=$(stat -c %a "$d/opt/code/chrome-sandbox" 2>&1): ${OUT}"
fi

# No cached sudo, no tty: FAILED naming the sandbox and sudo, the installed copy
# byte-identical, staging gone — and no interactive `sudo -v` is ever attempted.
d="$(_fresh c15c devin GLOBAL_STACK_DEVIN_VERSION 3.11.0)"
_mk_devin_tree "$d/opt/devin" 3.10.35 && chmod 4755 "$d/opt/devin/chrome-sandbox"
before="$(_fp "$d/opt/devin")"
_devin_release "$d" 3.11.0
: >"$d/no-sudo"
_run "$d" --apply --only=devin
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/devin")" == "${before}" && ! -e "$d/opt/.gs-staging/devin" ]] \
  && grep -q 'chrome-sandbox' <<<"${OUT}" && grep -q 'sudo' <<<"${OUT}" && [[ "$(grep -c -- '^-v' "$d/sudo.log")" == 0 ]]; then
  ok "15c: Devin, no cached sudo and no tty → FAILED naming chrome-sandbox and sudo; installed copy byte-identical; no sudo -v"
else
  ko "15c: rc=${RC} sudo.log=$(cat "$d/sudo.log" 2>&1): ${OUT}"
fi

# Order: a download failing its sha256 must never reach sudo; an archive without
# a chrome-sandbox cannot start under Electron and is refused, old copy intact.
d="$(_fresh c15d code GLOBAL_STACK_VSCODE_VERSION 1.141.0)"
_mk_code_tree "$d/opt/code" 1.140.0 && chmod 4755 "$d/opt/code/chrome-sandbox"
before="$(_fp "$d/opt/code")"
_code_release "$d" 1.141.0
sed -i -E 's/"sha256hash":"[0-9a-f]{64}"/"sha256hash":"'"$(printf '0%.0s' {1..64})"'"/' "$d/srv/v.json"
_run "$d" --apply --only=code
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/code")" == "${before}" && ! -e "$d/sudo.log" ]] && grep -q 'sha256 mismatch' <<<"${OUT}"; then
  ok "15d: a VS Code archive failing its sha256 never reaches sudo; installed copy byte-identical"
else
  ko "15d: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && cat "$d/sudo.log" || echo no): ${OUT}"
fi
d="$(_fresh c15e devin GLOBAL_STACK_DEVIN_VERSION 3.11.0)"
_mk_devin_tree "$d/opt/devin" 3.10.35 && chmod 4755 "$d/opt/devin/chrome-sandbox"
before="$(_fp "$d/opt/devin")"
_devin_release "$d" 3.11.0 nosandbox
_run "$d" --apply --only=devin
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/devin")" == "${before}" ]] && grep -q 'no chrome-sandbox' <<<"${OUT}"; then
  ok "15e: a Devin archive without chrome-sandbox is refused naming it; installed copy byte-identical"
else
  ko "15e: rc=${RC}: ${OUT}"
fi

# An installed tool that is already CURRENT is repaired on --apply: this is exactly
# the state a plain upgrade leaves (developer 755), and `--check` said "current".
d="$(_fresh c15f devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35
_run "$d" --apply --only=devin
sb="$d/opt/devin/chrome-sandbox"
if [[ ${RC} -eq 0 ]] && grep -q 'REPAIRED.*devin' <<<"${OUT}" \
  && grep -qx -- "-n chown root:root ${sb}" "$d/sudo.log" 2>/dev/null && grep -qx -- "-n chmod 4755 ${sb}" "$d/sudo.log" \
  && [[ "$(stat -c %a "${sb}")" == 4755 && "$(_curl_calls "$d")" == 0 ]]; then
  ok "15f: a current Devin with a 755 sandbox is REPAIRED to root:root 4755 on --apply, nothing downloaded"
else
  ko "15f: rc=${RC} sudo.log=$(cat "$d/sudo.log" 2>&1) mode=$(stat -c %a "${sb}" 2>&1): ${OUT}"
fi
# A correct sandbox costs nothing: no sudo call at all, so an unattended run stays quiet.
d="$(_fresh c15g devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35 && chmod 4755 "$d/opt/devin/chrome-sandbox"
SANDBOX_OWNER="${ME}" _run "$d" --apply --only=devin
if [[ ${RC} -eq 0 && ! -e "$d/sudo.log" ]] && ! grep -q 'REPAIRED' <<<"${OUT}"; then
  ok "15g: a correct sandbox → no sudo call, no REPAIRED"
else
  ko "15g: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && cat "$d/sudo.log" || echo no): ${OUT}"
fi
# setuid alone is not enough: a sandbox that is mode 4755 but not root-owned is still
# refused by Electron, so the OWNER is half of "correct" (a check on the mode only
# would leave developer:developer 4755 as it is).
d="$(_fresh c15o devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35 && chmod 4755 "$d/opt/devin/chrome-sandbox"
_run "$d" --apply --only=devin
sb="$d/opt/devin/chrome-sandbox"
if [[ ${RC} -eq 0 ]] && grep -q 'REPAIRED.*devin' <<<"${OUT}" && grep -qx -- "-n chown root:root ${sb}" "$d/sudo.log" 2>/dev/null; then
  ok "15o: a 4755 sandbox that is not root-owned is still repaired (the owner is half of correct)"
else
  ko "15o: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && cat "$d/sudo.log" || echo no): ${OUT}"
fi
# A repair that cannot get sudo fails loudly, names the exact command, changes nothing.
d="$(_fresh c15h devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35
before="$(_fp "$d/opt/devin")"
: >"$d/no-sudo"
_run "$d" --apply --only=devin
sb="$d/opt/devin/chrome-sandbox"
if [[ ${RC} -ne 0 && "$(_fp "$d/opt/devin")" == "${before}" ]] \
  && grep -qF "sudo chown root:root '${sb}' && sudo chmod 4755 '${sb}'" <<<"${OUT}" && [[ "$(grep -c -- '^-v' "$d/sudo.log")" == 0 ]]; then
  ok "15h: repair without sudo → exit ${RC}, the exact fix command printed, tree byte-identical, no sudo -v"
else
  ko "15h: rc=${RC}: ${OUT}"
fi
# --check reports a broken sandbox (it was silent: "current devin" while Devin could
# not start) and stays read-only and sudo-free.
d="$(_fresh c15i devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35
before="$(_fp "$d/opt/devin")"
_run "$d" --check --only=devin
if [[ ${RC} -eq 0 ]] && grep -qE '^\[sandbox +\] devin' <<<"${OUT}" && [[ ! -e "$d/sudo.log" && "$(_fp "$d/opt/devin")" == "${before}" ]]; then
  ok "15i: --check reports a wrong sandbox, exit 0, no sudo call, tree untouched"
else
  ko "15i: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && echo YES || echo no): ${OUT}"
fi
chmod 4755 "$d/opt/devin/chrome-sandbox"
SANDBOX_OWNER="${ME}" _run "$d" --check --only=devin
if [[ ${RC} -eq 0 ]] && ! grep -q 'sandbox' <<<"${OUT}"; then ok "15j: --check is silent about a correct sandbox"; else ko "15j: rc=${RC}: ${OUT}"; fi

# The set is exactly the three Electron apps: Etcher and VS Code are repaired too,
# and a tool outside it (IDEA, whose jcef helper also ships a chrome-sandbox) never
# reaches sudo.
d="$(_fresh c15k balena_etcher GLOBAL_STACK_BALENA_ETCHER_VERSION v2.1.7)"
_mk_etcher_tree "$d/opt/balena-etcher" 2.1.7
_run "$d" --apply --only=balena_etcher
if [[ ${RC} -eq 0 ]] && grep -q 'REPAIRED.*balena_etcher' <<<"${OUT}" && [[ "$(stat -c %a "$d/opt/balena-etcher/chrome-sandbox")" == 4755 ]]; then
  ok "15k: a current Etcher with a 755 sandbox is repaired too"
else
  ko "15k: rc=${RC}: ${OUT}"
fi
d="$(_fresh c15l code GLOBAL_STACK_VSCODE_VERSION 1.140.0)"
_mk_code_tree "$d/opt/code" 1.140.0
_run "$d" --apply --only=code
if [[ ${RC} -eq 0 ]] && grep -q 'REPAIRED.*code' <<<"${OUT}" && [[ "$(stat -c %a "$d/opt/code/chrome-sandbox")" == 4755 ]]; then
  ok "15l: a current VS Code with a 755 sandbox is repaired too"
else
  ko "15l: rc=${RC}: ${OUT}"
fi
d="$(_sandbox c15m 2026.2.3)"
mkdir -p "$d/opt/jetbrains/idea/plugins/jcef-plugin/jcef"
printf 'elf' >"$d/opt/jetbrains/idea/plugins/jcef-plugin/jcef/chrome-sandbox" && chmod 755 "$d/opt/jetbrains/idea/plugins/jcef-plugin/jcef/chrome-sandbox"
# The real jcef sandbox is nested, where the repair never looks — so on its own it could
# not tell "outside the set" from "nothing to find". This tree also ships one at its
# ROOT, wrong, which only the membership of the set keeps out of reach of sudo.
printf 'elf' >"$d/opt/jetbrains/idea/chrome-sandbox" && chmod 755 "$d/opt/jetbrains/idea/chrome-sandbox"
_run "$d" --apply --only=idea
if [[ ${RC} -eq 0 && ! -e "$d/sudo.log" ]] && ! grep -q 'sandbox' <<<"${OUT}"; then
  ok "15m: IDEA (not an Electron app; its jcef helper's sandbox is left alone) never reaches sudo"
else
  ko "15m: rc=${RC} sudo called=$([[ -e "$d/sudo.log" ]] && cat "$d/sudo.log" || echo no): ${OUT}"
fi

# The interactive path: with a tty and no cached credentials the engine asks once
# (sudo -v), then retries sudo -n. Run under script(1) so stdin really is a tty.
d="$(_fresh c15n devin GLOBAL_STACK_DEVIN_VERSION 3.10.35)"
_mk_devin_tree "$d/opt/devin" 3.10.35
: >"$d/no-sudo"
if command -v script >/dev/null; then
  OUT="$(script -qec "env -i HOME=$d PATH=${STUB_BIN}:/usr/bin:/bin T=$d USER=tester GS_UNU_OPT_ROOT=$d/opt GS_UNU_OPT_APPS_DIR=$d/apps GS_UNU_OPT_ENV_FILE=$d/env.local GS_UNU_OPT_PROC_DIR=$d/proc GS_UNU_OPT_SANDBOX_OWNER=root bash ${SUT} --apply --only=devin" /dev/null 2>&1 </dev/null)"
  RC=$?
  vline="$(grep -n -- '^-v' "$d/sudo.log" 2>/dev/null | head -1 | cut -d: -f1)"
  cline="$(grep -n -- '^-n chmod 4755' "$d/sudo.log" 2>/dev/null | tail -1 | cut -d: -f1)"
  if [[ ${RC} -eq 0 && -n "${vline}" && -n "${cline}" && "${vline}" -lt "${cline}" && "$(stat -c %a "$d/opt/devin/chrome-sandbox")" == 4755 ]]; then
    ok "15n: with a tty and no cached sudo the engine runs sudo -v once, then sudo -n succeeds and the sandbox is repaired"
  else
    ko "15n: rc=${RC} sudo.log=$(cat "$d/sudo.log" 2>&1): ${OUT}"
  fi
else
  printf '  %b(skip)%b 15n: script(1) is not installed — the tty path is UNCERTIFIED here\n' "${C_BOLD}" "${C_RESET}"
fi

printf '\n'
if ((FAIL == 0)); then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
  exit 0
fi
printf '  %bFAILURES%b      ✓ %d passed   ✗ %d failed   (%d total)\n' "${C_RED}" "${C_RESET}" "${PASS}" "${FAIL}" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '    • %s\n' "${f}"; done
exit 1
