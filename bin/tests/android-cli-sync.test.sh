#!/usr/bin/env bash
# Tests docker/config/dist/bin/android-bin/global-stack-android-cli-sync.sh — the script that
# keeps the REAL Android CLI (~80 MB, fetched by the `android` launcher into
# ${ANDROID_USER_HOME:-$HOME/.android}/bin/android-cli) on its .env pin,
# GLOBAL_STACK_ANDROID_CLI_VERSION, instead of whatever dl.google.com serves as `latest`.
# Run: bash bin/tests/android-cli-sync.test.sh   (~3 s; no network, no docker)
#
# docs/plans/android-cli-pin.plan.md. The guarantees under test:
#   - --installed is offline and reports a version ONLY when the bytes at dest are the ones a
#     verified install recorded (an `android update` reads as drift, not as current);
#   - --apply installs the pin from dl.google.com/android/cli/<pin>/linux_x86_64/ checked against
#     the published .sha256, through a cache shared by the host and the containers; a current
#     install, or a recreated $HOME with a valid cache, makes no network call;
#   - any download / checksum failure leaves dest and its record byte-identical;
#   - bad arguments are refused before anything is written; an empty pin is `unmanaged`;
#   - the cache prune removes only version-named dirs strictly inside the cache;
#   - the container wiring: 04android syncs on EVERY boot before SDK setup, the 05* images after
#     waiting for android, the pin never enters the SDK gate (startup-prologue §47).
#
# Stub curl: serves "$T/routes" (URL<TAB>file), exits 22 under -f on anything else (as real curl
# does) and logs every URL to "$T/curl.log".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUT_REL="docker/config/dist/bin/android-bin/global-stack-android-cli-sync.sh"
SUT="${REPO_ROOT}/${SUT_REL}"
AND_START="${REPO_ROOT}/docker/config/dist/bin/android-bin/global-stack-android-start.sh"
AND_SETUP="${REPO_ROOT}/docker/config/dist/bin/android-bin/global-stack-android-setup.sh"
ALL_START="${REPO_ROOT}/docker/config/dist/bin/alltogether/global-stack-alltogether-start.sh"
BASE_URL="https://dl.google.com/android/cli"

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
check() { # $1 name, rest: command → ok when it exits 0
  local name="$1"
  shift
  if "$@"; then ok "${name}"; else ko "${name}"; fi
}
section() { printf '\n%b%s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

for _dep in sha256sum awk git; do
  command -v "${_dep}" >/dev/null || {
    printf '\n  %s is required by this suite and missing.\n\n' "${_dep}"
    exit 1
  }
done

# ── Stub curl ────────────────────────────────────────────────────────────────
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
src="$(awk -F'\t' -v u="${url}" '$1 == u { print $2; exit }' "${T}/routes" 2>/dev/null)"
if [[ -z "${src}" ]]; then
  ((fail)) && exit 22
  body='<html><body>404 Not Found</body></html>'
  if [[ -n "${out}" ]]; then printf '%s' "${body}" >"${out}"; else printf '%s' "${body}"; fi
  exit 0
fi
if [[ -n "${out}" ]]; then cp "${src}" "${out}"; else cat "${src}"; fi
STUB
chmod +x "${STUB_BIN}/curl"

# ── Fixtures ─────────────────────────────────────────────────────────────────
# $1 case dir, $2 version → a fake CLI release served at the versioned URLs. The "binary" is a
# script whose BYTES identify the version; the .sha256 is bare hex with no newline, as Google's is.
_serve() {
  local d="$1" v="$2" bin sum
  mkdir -p "$d/srv/$v"
  bin="$d/srv/$v/android-cli"
  printf '#!/bin/sh\necho %s\n' "$v" >"${bin}"
  sum="$(sha256sum "${bin}" | cut -d' ' -f1)"
  printf '%s' "${sum}" >"$d/srv/$v/android-cli.sha256"
  printf '%s\t%s\n' \
    "${BASE_URL}/$v/linux_x86_64/android-cli" "${bin}" \
    "${BASE_URL}/$v/linux_x86_64/android-cli.sha256" "$d/srv/$v/android-cli.sha256" \
    >>"$d/routes"
}

# $1 case name → a fresh case dir (home + cache), printed
_case() {
  local d="${TMP_DIR}/$1"
  mkdir -p "$d/home" "$d/cache"
  : >"$d/routes"
  : >"$d/curl.log"
  printf '%s' "$d"
}

# $1 case dir, rest: script args → OUT, RC
_run() {
  local d="$1"
  shift
  OUT="$(env -i HOME="$d/home" PATH="${STUB_BIN}:/usr/bin:/bin" T="$d" \
    GS_ANDROID_CLI_MACHINE="${MACHINE:-x86_64}" \
    bash "${SUT}" "$@" 2>&1 </dev/null)"
  RC=$?
}
_apply() { _run "$1" --apply --pin="$2" --dest="$1/home/.android/bin/android-cli" --cache="$1/cache"; }
_installed() { _run "$1" --installed --dest="$1/home/.android/bin/android-cli"; }

DEST_REL="home/.android/bin/android-cli"
REC_REL="home/.android/bin/.android-cli.gs-pin"
_fp() { (cd "$1" && find . -printf '%p %m %s\n' | sort && find . -type f -exec sha256sum {} + | sort) | sha256sum; }
_curl_calls() { grep -c . "$1/curl.log" || true; }
# shellcheck disable=SC2329 # invoked through check()
_same() { cmp -s "$1" "$2"; }

[[ -f "${SUT}" ]] || {
  printf '\n  %s is missing — nothing to test.\n\n' "${SUT}"
  exit 1
}

# ═════════════════════════════════════════════════════════════════════════════
section "1. a fresh --apply installs the pin, verified"
d="$(_case fresh)"
_serve "$d" 1.1.2
_apply "$d" 1.1.2
check "1a: rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "1b: dest holds the pinned bytes" _same "$d/${DEST_REL}" "$d/srv/1.1.2/android-cli"
check "1c: dest is executable (755)" test "$(stat -c %a "$d/${DEST_REL}" 2>/dev/null)" = 755
check "1d: the record is '<pin> <sha256>'" \
  test "$(cat "$d/${REC_REL}" 2>/dev/null)" = "1.1.2 $(cat "$d/srv/1.1.2/android-cli.sha256")"
check "1e: the cache keeps the binary and its .sha256 under <cache>/<pin>/" \
  bash -c "cmp -s '$d/cache/1.1.2/android-cli' '$d/srv/1.1.2/android-cli' && cmp -s '$d/cache/1.1.2/android-cli.sha256' '$d/srv/1.1.2/android-cli.sha256'"
check "1f: exactly the two versioned URLs were fetched" \
  test "$(sort "$d/curl.log" | tr '\n' ' ')" = "${BASE_URL}/1.1.2/linux_x86_64/android-cli ${BASE_URL}/1.1.2/linux_x86_64/android-cli.sha256 "
check "1g: no 'latest' URL is ever requested" bash -c "! grep -q latest '$d/curl.log'"
check "1h: no temp file is left: dest dir = {android-cli, record}, cache = {<pin>/android-cli, <pin>/android-cli.sha256}" \
  test "$(cd "$d/home/.android/bin" 2>/dev/null && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')|$(cd "$d/cache" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')" \
  = "./.android-cli.gs-pin ./android-cli |./1.1.2 ./1.1.2/android-cli ./1.1.2/android-cli.sha256 "
check "1i: it says INSTALLED" grep -q 'INSTALLED' <<<"${OUT}"

section "2. a current install is offline and untouched"
fp="$(_fp "$d/home")"
: >"$d/curl.log"
_apply "$d" 1.1.2
check "2a: rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "2b: no network call" test "$(_curl_calls "$d")" -eq 0
check "2c: dest and record byte-identical" test "$(_fp "$d/home")" = "${fp}"
check "2d: it says current" grep -q 'current' <<<"${OUT}"
_installed "$d"
check "2e: --installed prints the pin (${OUT})" test "${OUT}" = 1.1.2
check "2f: --installed made no network call" test "$(_curl_calls "$d")" -eq 0

section "3. drift: \`android update\` replaced the bytes"
printf '#!/bin/sh\necho 9.9.9\n' >"$d/${DEST_REL}"
_installed "$d"
check "3a: --installed prints nothing for foreign bytes (got '${OUT}')" test -z "${OUT}"
check "3b: --installed rc 0" test "${RC}" -eq 0
_apply "$d" 1.1.2
check "3c: --apply restores the pin (rc ${RC}): ${OUT}" _same "$d/${DEST_REL}" "$d/srv/1.1.2/android-cli"
check "3d: from the valid cache, with no network call" test "$(_curl_calls "$d")" -eq 0

section "4. a recreated \$HOME with a valid cache needs no network"
rm -rf "${d:?}/home"
mkdir -p "$d/home"
_apply "$d" 1.1.2
check "4a: rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "4b: dest holds the pinned bytes" _same "$d/${DEST_REL}" "$d/srv/1.1.2/android-cli"
check "4c: no network call" test "$(_curl_calls "$d")" -eq 0
_installed "$d"
check "4d: --installed prints the pin" test "${OUT}" = 1.1.2

section "5. --installed with nothing installed"
d="$(_case empty)"
_installed "$d"
check "5a: prints nothing, rc 0 (rc ${RC}, '${OUT}')" bash -c "[[ ${RC} -eq 0 && -z '${OUT}' ]]"
printf 'x' >"$d/foreign"
mkdir -p "$d/home/.android/bin"
cp "$d/foreign" "$d/${DEST_REL}"
_installed "$d"
check "5b: a binary with no record prints nothing (the host's pre-pin copy)" test -z "${OUT}"

section "6. every failure leaves dest and record byte-identical"
_seed_old() { # $1 case dir: a verified 1.0.1 install, then 1.1.2 is the new pin
  _serve "$1" 1.0.1
  _apply "$1" 1.0.1
  : >"$1/curl.log"
}
# 6a: the served binary does not match the published .sha256
d="$(_case badsum)"
_seed_old "$d"
_serve "$d" 1.1.2
printf 'tampered\n' >>"$d/srv/1.1.2/android-cli"
fp="$(_fp "$d/home")"
_apply "$d" 1.1.2
check "6a: sha256 mismatch → rc 1 (${RC})" test "${RC}" -eq 1
check "6a: says FAILED" grep -q 'FAILED' <<<"${OUT}"
check "6a: dest + record byte-identical" test "$(_fp "$d/home")" = "${fp}"
check "6a: nothing cached for the bad pin" test ! -e "$d/cache/1.1.2/android-cli"
check "6a: no temp file left in the cache" test -z "$(find "$d/cache" -name '*gs-tmp*' 2>/dev/null)"
# 6b: the pin is not published (404)
d="$(_case notfound)"
_seed_old "$d"
fp="$(_fp "$d/home")"
_apply "$d" 1.1.2
check "6b: 404 → rc 1 (${RC})" test "${RC}" -eq 1
check "6b: dest + record byte-identical" test "$(_fp "$d/home")" = "${fp}"
# 6c: the .sha256 is not a sha256 (an HTML page served 200)
d="$(_case htmlsum)"
_seed_old "$d"
_serve "$d" 1.1.2
printf '<html>oops</html>' >"$d/srv/1.1.2/android-cli.sha256"
fp="$(_fp "$d/home")"
_apply "$d" 1.1.2
check "6c: malformed .sha256 → rc 1 (${RC})" test "${RC}" -eq 1
check "6c: dest + record byte-identical" test "$(_fp "$d/home")" = "${fp}"
# 6d: the dest dir cannot be written — the record must not claim the new pin
d="$(_case rodest)"
_seed_old "$d"
_serve "$d" 1.1.2
chmod 555 "$d/home/.android/bin"
_apply "$d" 1.1.2
chmod 755 "$d/home/.android/bin"
check "6d: unwritable dest dir → rc 1 (${RC})" test "${RC}" -eq 1
check "6d: the record still names the old pin" grep -q '^1\.0\.1 ' "$d/${REC_REL}"
check "6d: dest still holds the old bytes" _same "$d/${DEST_REL}" "$d/srv/1.0.1/android-cli"

# 6e: dest is a DIRECTORY (writable dir around it): a plain `mv -f tmp dest` would move the binary
# INTO it and succeed. The copy must fail, and the record — whose dir IS writable here, unlike 6d —
# must not be written: this is the case that proves the record is written last.
d="$(_case destdir)"
_serve "$d" 1.1.2
mkdir -p "$d/${DEST_REL}/occupied"
_apply "$d" 1.1.2
check "6e: dest is a directory → rc 1 (${RC}): ${OUT}" test "${RC}" -eq 1
check "6e: nothing was moved into it" test "$(find "$d/${DEST_REL}" -mindepth 1 | wc -l)" -eq 1
check "6e: no record claims the pin" test ! -e "$d/${REC_REL}"

# 6f: the RECORD path is a directory. A plain `mv` would park the record inside it and report
# INSTALLED while `--installed` can never read it back (every later boot reinstalls); -T fails it.
d="$(_case recdir)"
_serve "$d" 1.1.2
mkdir -p "$d/${REC_REL}/occupied"
_apply "$d" 1.1.2
check "6f: record path is a directory → rc 1 (${RC}): ${OUT}" test "${RC}" -eq 1
check "6f: nothing was moved into it" test "$(find "$d/${REC_REL}" -mindepth 1 | wc -l)" -eq 1

# 6g: the cached BINARY path is a directory. A plain `mv` would bury the download inside it; the
# run fails later either way, so what this pins is that nothing lands in the directory.
d="$(_case cachedir)"
_serve "$d" 1.1.2
mkdir -p "$d/cache/1.1.2/android-cli/occupied"
_apply "$d" 1.1.2
check "6g: cached binary path is a directory → rc 1 (${RC})" test "${RC}" -eq 1
check "6g: nothing was moved into it" test "$(find "$d/cache/1.1.2/android-cli" -mindepth 1 | wc -l)" -eq 1
check "6g: dest untouched" test ! -e "$d/${DEST_REL}"

section "7. a tampered cache is not trusted"
d="$(_case tamper)"
_serve "$d" 1.1.2
_apply "$d" 1.1.2
rm -rf "${d:?}/home" && mkdir -p "$d/home"
printf 'evil\n' >>"$d/cache/1.1.2/android-cli"
: >"$d/curl.log"
_apply "$d" 1.1.2
check "7a: rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "7b: the cached bytes were re-downloaded" grep -q '/1.1.2/linux_x86_64/android-cli$' "$d/curl.log"
check "7c: dest holds the genuine bytes" _same "$d/${DEST_REL}" "$d/srv/1.1.2/android-cli"

section "8. a pin change installs the new pin and prunes only old version dirs"
d="$(_case bump)"
_seed_old "$d"
_serve "$d" 1.1.2
mkdir -p "$d/cache/keep-me" "$d/cache-sibling/1.0.1"
printf 'k' >"$d/cache/keep-me/f"
printf 's' >"$d/cache-sibling/1.0.1/f"
_apply "$d" 1.1.2
check "8a: rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "8b: dest holds the new pin" _same "$d/${DEST_REL}" "$d/srv/1.1.2/android-cli"
check "8c: the record names the new pin" grep -q '^1\.1\.2 ' "$d/${REC_REL}"
check "8d: the old version dir is pruned" test ! -e "$d/cache/1.0.1"
check "8e: a non-version dir in the cache is kept" test -f "$d/cache/keep-me/f"

check "8f: a version-named dir OUTSIDE the cache is untouched" test -f "$d/cache-sibling/1.0.1/f"

# 8g: an old version dir that cannot be removed (another uid's files, a read-only mount) must not
# fail an install that already succeeded: the pin is in place, the run says WARN and exits 0.
d="$(_case prune-fails)"
_serve "$d" 1.1.2
mkdir -p "$d/cache/1.0.9/locked"
: >"$d/cache/1.0.9/locked/f"
chmod 555 "$d/cache/1.0.9/locked"
_apply "$d" 1.1.2
chmod 755 "$d/cache/1.0.9/locked"
check "8g: an unremovable old version → rc 0 (${RC}): ${OUT}" test "${RC}" -eq 0
check "8g: … with a WARN naming it" grep -q 'WARN.*could not prune.*1\.0\.9' <<<"${OUT}"
check "8g: … and the pin installed" test -f "$d/${REC_REL}"

section "9. arguments are refused before anything is written"
d="$(_case args)"
_serve "$d" 1.1.2
fp="$(_fp "$d")"
_run "$d" --apply --pin=1.1.2 --dest=relative/android-cli --cache="$d/cache"
check "9a: a relative --dest → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d" --apply --pin=1.1.2 --dest= --cache="$d/cache"
check "9b: an empty --dest → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d" --apply --pin=1.1.2 --dest="$d/home/.android/bin/android-cli" --cache=cache
check "9c: a relative --cache → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d" --apply --pin=1.1.2 --dest="$d/home/.android/bin/android-cli"
check "9d: a missing --cache → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d" --apply --pin=../../x --dest="$d/home/.android/bin/android-cli" --cache="$d/cache"
check "9e: a pin that is not a version → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d" --frobnicate
check "9f: an unknown argument → rc 2 (${RC})" test "${RC}" -eq 2
_run "$d"
check "9g: no mode → rc 2 (${RC})" test "${RC}" -eq 2
check "9h: nothing was written and nothing fetched" bash -c "[[ '$(_fp "$d")' == '${fp}' && \$(grep -c . '$d/curl.log' || true) -eq 0 ]]"

section "10. an empty pin is unmanaged; a machine with no build is unsupported"
d="$(_case unmanaged)"
fp="$(_fp "$d")"
_apply "$d" ""
check "10a: empty pin → rc 0 (${RC})" test "${RC}" -eq 0
check "10b: says unmanaged" grep -q 'unmanaged' <<<"${OUT}"
check "10c: nothing written, nothing fetched" bash -c "[[ '$(_fp "$d")' == '${fp}' && \$(grep -c . '$d/curl.log' || true) -eq 0 ]]"
MACHINE=aarch64 _apply "$d" 1.1.2
check "10d: aarch64 → rc 0 (${RC}), says unsupported" bash -c "[[ ${RC} -eq 0 ]] && grep -q unsupported <<<'${OUT}'"
check "10e: nothing written, nothing fetched" bash -c "[[ '$(_fp "$d")' == '${fp}' && \$(grep -c . '$d/curl.log' || true) -eq 0 ]]"

# ═════════════════════════════════════════════════════════════════════════════
section "11. wiring"
_line_of() { # $1 file $2 ERE → first matching non-comment line number
  grep -nE "$2" "$1" | grep -vE '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1
}
check "11a: the script is executable in git (100755) — core.fileMode=false hides a chmod" \
  test "$(git -C "${REPO_ROOT}" ls-files -s -- "${SUT_REL}" | cut -d' ' -f1)" = 100755
sync_l="$(_line_of "${AND_START}" 'global-stack-android-cli-sync\.sh')"
setup_l="$(_line_of "${AND_START}" '^[[:space:]]*global-stack-android-setup\.sh$')"
check "11b: android-start calls the sync (line ${sync_l:-none})" test -n "${sync_l}"
check "11c: … BEFORE setup.sh (${sync_l:-none} < ${setup_l:-none}), so setup's own \`android\` runs the pin" \
  bash -c "[[ -n '${sync_l}' && -n '${setup_l}' && ${sync_l:-0} -lt ${setup_l:-0} ]]"
check "11d: … at column 0, i.e. on every boot, not inside the SDK gate" \
  bash -c "sed -n '${sync_l:-1}p' '${AND_START}' | grep -q '^global-stack-android-cli-sync\.sh '"
# 11e: the shipped call line, executed against a stub sync that records its argv.
_wire_probe() { # $1 file $2 line → the argv the stub saw
  local w="${TMP_DIR}/wire" line
  rm -rf "${w}" && mkdir -p "${w}/bin" "${w}/home"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/argv"\n' "${w}" >"${w}/bin/global-stack-android-cli-sync.sh"
  chmod +x "${w}/bin/global-stack-android-cli-sync.sh"
  line="$(sed -n "$2p" "$1")"
  env -i PATH="${w}/bin:/usr/bin:/bin" HOME="${w}/home" ${3:+ANDROID_USER_HOME="$3"} \
    GLOBAL_STACK_ANDROID_CLI_VERSION=7.7.7 GLOBAL_STACK_DOCKER_TOOLS_PATH=/stack/tools \
    bash -c "${line}" >/dev/null 2>&1
  tr '\n' ' ' <"${w}/argv" 2>/dev/null
}
want="--apply --pin=7.7.7 --dest=${TMP_DIR}/wire/home/.android/bin/android-cli --cache=/stack/tools/android-cli "
got="$(_wire_probe "${AND_START}" "${sync_l:-1}")"
check "11e: android-start passes --apply, the pin, \$HOME/.android/bin/android-cli and tools/android-cli (got: ${got})" \
  test "${got}" = "${want}"
got="$(_wire_probe "${AND_START}" "${sync_l:-1}" /custom/uh)"
check "11f: … and honours ANDROID_USER_HOME, as the launcher does (got: ${got})" \
  test "${got}" = "--apply --pin=7.7.7 --dest=/custom/uh/bin/android-cli --cache=/stack/tools/android-cli "
all_l="$(_line_of "${ALL_START}" 'global-stack-android-cli-sync\.sh')"
wait_l="$(_line_of "${ALL_START}" 'SUCCESSES\}/android"')"
check "11g: alltogether-start calls the sync AFTER waiting for android (${all_l:-none} > ${wait_l:-none})" \
  bash -c "[[ -n '${all_l}' && -n '${wait_l}' && ${all_l:-0} -gt ${wait_l:-0} ]]"
got="$(_wire_probe "${ALL_START}" "${all_l:-1}")"
check "11h: alltogether passes the same arguments (got: ${got})" test "${got}" = "${want}"
check "11i: setup.sh never reads the CLI pin (§47 would put it in the SDK gate and wipe the SDK on a bump)" \
  bash -c "! grep -v '^[[:space:]]*#' '${AND_SETUP}' | grep -q GLOBAL_STACK_ANDROID_CLI_VERSION"
check "11j: the pin is not in GS_ANDROID_SDK_WANT" \
  bash -c "! grep -m1 '^GS_ANDROID_SDK_WANT=' '${AND_START}' | grep -q GLOBAL_STACK_ANDROID_CLI_VERSION"
_n_compose=0
for f in "${REPO_ROOT}"/docker/images/04android/docker-compose.yaml \
  "${REPO_ROOT}"/docker/images/05edge/docker-compose.yaml \
  "${REPO_ROOT}"/docker/images/05stable/docker-compose.yaml \
  "${REPO_ROOT}"/docker/images/local.*android*/docker-compose.yaml; do
  [[ -f "${f}" ]] || continue
  _n_compose=$((_n_compose + 1))
  # shellcheck disable=SC2016 # the literal \${…} is what the compose file must contain
  check "11k: ${f#"${REPO_ROOT}"/} passes the pin" \
    grep -qF -e '- GLOBAL_STACK_ANDROID_CLI_VERSION=${GLOBAL_STACK_ANDROID_CLI_VERSION}' "${f}"
done
check "11l: at least the 3 tracked compose files were checked (${_n_compose})" test "${_n_compose}" -ge 3
ann="$(grep -B1 -m1 '^GLOBAL_STACK_ANDROID_CLI_VERSION=' "${REPO_ROOT}/.env" | head -n 1)"
val="$(sed -n 's/^GLOBAL_STACK_ANDROID_CLI_VERSION=//p' "${REPO_ROOT}/.env")"
check "11m: .env pins GLOBAL_STACK_ANDROID_CLI_VERSION to a version (${val:-none})" \
  bash -c "[[ '${val}' =~ ^[0-9]+(\.[0-9]+)+$ ]]"
# The (verify-asset:) gate keeps env-update from proposing a version whose cli/<v>/… files are
# not published yet (docs/plans/verify-asset-fetch-extract.plan.md).
check "11n: … annotated for env-update from Google's METADATA, gated on the versioned .sha256, current value = the pin" \
  bash -c "[[ '${ann}' == '# @todo env-update (fetch-extract:version=([0-9][0-9.]*)) (verify-asset:https://dl.google.com/android/cli/{version}/linux_x86_64/android-cli.sha256) url:https://dl.google.com/android/cli/latest/linux_x86_64/METADATA ${val}' ]]"

printf '\n'
if ((FAIL == 0)); then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
  exit 0
fi
printf '  %bFAILURES%b      ✓ %d passed   ✗ %d failed   (%d total)\n' "${C_RED}" "${C_RESET}" "${PASS}" "${FAIL}" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '    • %s\n' "${f}"; done
exit 1
