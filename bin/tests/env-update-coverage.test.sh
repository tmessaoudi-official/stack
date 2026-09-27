#!/usr/bin/env bash
# Static coverage cross-check for env-update fetcher types (review-remediation WS8.3, 2026-09-27).
#
# A fetcher type lives in THREE places and every past addition left one out: pecl (2026-05-11),
# ghcr (the link opener had no branch and silently opened nothing), codeberg. A sourced-but-unwired
# fetcher, or one the opener does not know, fails with no error at all. For every
# bin/lib/env-update/fetchers/<T>.sh this asserts:
#   1. main.sh sources it                         (otherwise the function never exists)
#   2. it defines _gs_eu2_fetch_<T>               (main.sh dispatches DYNAMICALLY on that name —
#                                                  main.sh:97-104; there are no case labels)
#   3. bin/open-all-envs.sh either sets _type="<T>" in a URL branch, or lists <T> in
#      _GS_EU_MD_OPEN_SKIP_TYPES (a deliberate "no browser URL / checked manually")
# The inventory counts are asserted first, so an empty glob or a moved directory cannot turn
# every check green by absence.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FETCHERS="${_GS_EUC_FETCHERS:-${ROOT}/bin/lib/env-update/fetchers}"
MAIN="${_GS_EUC_MAIN:-${ROOT}/bin/lib/env-update/main.sh}"
OPENER="${_GS_EUC_OPENER:-${ROOT}/bin/open-all-envs.sh}"

PASS=0; FAIL=0
ok()  { printf '  ✓ %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  ✗ %s\n    %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

types=()
for f in "${FETCHERS}"/*.sh; do [[ -f "$f" ]] && types+=("$(basename "$f" .sh)"); done
skip_line=$(grep -E '^_GS_EU_MD_OPEN_SKIP_TYPES=' "$OPENER" | head -1)

echo "Inventory"
if (( ${#types[@]} >= 12 )); then ok "fetcher inventory: ${#types[@]} types (12 on 2026-09-27; it only grows)"
else bad "fetcher inventory" "found ${#types[@]} in ${FETCHERS} — the glob or the path is wrong"; fi
if [[ -n "$skip_line" ]]; then ok "opener skip list found"; else bad "opener skip list found" "no _GS_EU_MD_OPEN_SKIP_TYPES= line in ${OPENER}"; fi

echo "Per type"
for t in "${types[@]}"; do
  n=$(grep -cE "^[[:space:]]*source[[:space:]]+\"\\\$\(dirname \"\\\$\{BASH_SOURCE\[0\]\}\"\)/fetchers/${t}\.sh\"" "$MAIN") || n=0
  if [[ "$n" == 1 ]]; then ok "${t}: sourced once by main.sh"; else bad "${t}: sourced once by main.sh" "found ${n} source line(s)"; fi
  if grep -qE "^[[:space:]]*(function[[:space:]]+)?_gs_eu2_fetch_${t}[[:space:]]*\(\)" "${FETCHERS}/${t}.sh"; then
    ok "${t}: defines _gs_eu2_fetch_${t} (the dynamic-dispatch name)"
  else bad "${t}: defines _gs_eu2_fetch_${t} (the dynamic-dispatch name)" "no such function in ${t}.sh — main.sh would SKIP every ${t} entry"; fi
  if grep -qE "_type=\"${t}\"" "$OPENER"; then ok "${t}: the opener has a URL branch"
  elif [[ " ${skip_line#*=} " =~ [\"[:space:]]${t}[\"[:space:]] ]]; then ok "${t}: the opener skips it deliberately"
  else bad "${t}: the opener has a URL branch or a deliberate skip" "neither _type=\"${t}\" nor ${t} in _GS_EU_MD_OPEN_SKIP_TYPES — open-all-envs.sh would silently open nothing"; fi
done

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) && echo "ALL PASSED" || exit 1
