#!/usr/bin/env bash
# Tests for the `paths:` frontmatter of .claude/rules/*.md and the CLAUDE.md index of those files.
#
# A path-scoped rules file loads only when a file matching one of its `paths:` globs is opened.
# Three silent failures, none of which produces an error anywhere:
#   - a typo or dead glob: the rule never loads for the area it was written for;
#   - missing or malformed frontmatter: the file is no longer path-scoped, so it may load at
#     session start and spend the 150,000-char instruction budget CLAUDE.md was split to fit;
#   - an index line in CLAUDE.md ("The path-scoped rules files:") that names a file or glob the
#     rules directory no longer has.
#
# Glob semantics: bash globstar + dotglob, the same as the Python glob(recursive, include_hidden)
# the 2026-11-07 conservation check used, and matching Claude Code's own loading as probed live on
# 2026-11-07 (results in .claude/rules/claude-config.md). A glob must match at least one REGULAR
# file. A glob that matches nothing passes only when the path it targets is gitignored by the
# repo's .gitignore files (core.excludesFile=/dev/null drops the personal global excludes; a
# machine-local .git/info/exclude would still count), so a clean clone without
# docker/images/local.* or projects/.claude stays green.
#
# Every run also proves the checker can fire: built-in fixtures (dead glob, directory-only glob,
# missing/unclosed frontmatter, empty paths list, stale index line) must each be flagged.
#
# Seams: GS_RULES_ROOT (repo root), GS_RULES_DIR (rules dir), GS_RULES_CLAUDE_MD (index file).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${GS_RULES_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
RULES_DIR="${GS_RULES_DIR:-${REPO_ROOT}/.claude/rules}"
CLAUDE_MD="${GS_RULES_CLAUDE_MD:-${REPO_ROOT}/CLAUDE.md}"

PASS=0
FAIL=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
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

# rules_globs <rules-file> — print its `paths:` globs, one per line, quotes stripped.
# Exit 2: no opening `---` on line 1, or frontmatter never closed. Exit 3: no non-empty `paths:` list.
rules_globs() {
  awk '
    NR == 1 { if ($0 != "---") { bad = 2; exit } ; infm = 1; next }
    infm && $0 == "---" { closed = 1; exit }
    infm && /^paths:[ \t]*$/ { inp = 1; next }
    infm && inp && /^[ \t]+-[ \t]/ {
      g = $0
      sub(/^[ \t]+-[ \t]+/, "", g)
      sub(/[ \t]+$/, "", g)
      gsub(/^["\047]|["\047]$/, "", g)
      print g
      n++
      next
    }
    infm && inp { inp = 0 }
    END {
      if (bad) exit bad
      if (!closed) exit 2
      if (!n) exit 3
    }
  ' "$1"
}

# glob_files <root> <glob> — number of REGULAR files the glob matches under <root>.
glob_files() {
  (
    cd "$1" || exit 1
    shopt -s globstar dotglob nullglob
    # shellcheck disable=SC2206 # the glob must expand here, and globs carry no spaces
    local -a hits=($2)
    local n=0 f
    for f in "${hits[@]}"; do
      [[ -f ${f} ]] && n=$((n + 1))
    done
    printf '%s\n' "${n}"
  )
}

# glob_ignored <root> <glob> — true when the path the glob targets is gitignored by the repo's
# own rules: each `**` and `*` becomes a literal segment character, then git check-ignore --no-index.
glob_ignored() {
  local probe=${2//\*\*/x}
  probe=${probe//\*/x}
  git -C "$1" -c core.excludesFile=/dev/null check-ignore -q --no-index -- "${probe}"
}

# check_rules <rules-dir> <root> — one line per verdict:
#   OK <file> <glob> <n>   IGN <file> <glob>   BAD <file> <reason>
check_rules() {
  local dir=$1 root=$2 f base globs rc g n
  for f in "${dir}"/*.md; do
    [[ -f ${f} ]] || continue
    base=${f##*/}
    globs=$(rules_globs "${f}")
    rc=$?
    case ${rc} in
      0) ;;
      2)
        printf 'BAD %s frontmatter missing or unclosed\n' "${base}"
        continue
        ;;
      3)
        printf 'BAD %s no non-empty paths: list\n' "${base}"
        continue
        ;;
      *)
        printf 'BAD %s parser exit %s\n' "${base}" "${rc}"
        continue
        ;;
    esac
    while IFS= read -r g; do
      n=$(glob_files "${root}" "${g}")
      if [[ ${n} -gt 0 ]]; then
        printf 'OK %s %s %s\n' "${base}" "${g}" "${n}"
      elif glob_ignored "${root}" "${g}"; then
        printf 'IGN %s %s\n' "${base}" "${g}"
      else
        printf 'BAD %s %s matches no regular file\n' "${base}" "${g}"
      fi
    done <<<"${globs}"
  done
}

# check_index <claude-md> <rules-dir> — the "  <name>.md   #   glob, glob, …" lines of CLAUDE.md:
#   BAD-INDEX lines for a listed file that is missing, a shown glob the file lacks, or a rules
#   file with no index line; then one `INDEXED <n>` line.
check_index() {
  local md=$1 dir=$2 line name shown g seen=" " f n=0 real
  local -a parts
  while IFS= read -r line; do
    name=${line#"  "}
    name=${name%%[[:space:]]*}
    shown=${line#*\#}
    shown=${shown#"${shown%%[![:space:]]*}"}
    n=$((n + 1))
    seen+="${name} "
    if [[ ! -f "${dir}/${name}" ]]; then
      printf 'BAD-INDEX %s listed in CLAUDE.md but absent\n' "${name}"
      continue
    fi
    real=$(rules_globs "${dir}/${name}")
    IFS=',' read -r -a parts <<<"${shown}"
    for g in "${parts[@]}"; do
      g=${g#"${g%%[![:space:]]*}"}
      g=${g%"${g##*[![:space:]]}"}
      [[ -z ${g} || ${g} == "…" ]] && continue
      grep -qxF -e "${g}" <<<"${real}" \
        || printf 'BAD-INDEX %s shows %s, not in its paths:\n' "${name}" "${g}"
    done
  done < <(grep -E '^  [a-z0-9-]+\.md +# ' "${md}")
  for f in "${dir}"/*.md; do
    [[ -f ${f} ]] || continue
    [[ ${seen} == *" ${f##*/} "* ]] || printf 'BAD-INDEX %s has no index line in CLAUDE.md\n' "${f##*/}"
  done
  printf 'INDEXED %s\n' "${n}"
}

printf '\n%bclaude-rules-paths%b\n' "${C_BOLD}" "${C_RESET}"

# ── 1. The real rules directory ────────────────────────────────────────────────────
printf '\n%b── 1. %s ──%b\n' "${C_BOLD}" "${RULES_DIR#"${REPO_ROOT}/"}" "${C_RESET}"
mapfile -t RULE_FILES < <(compgen -G "${RULES_DIR}/*.md")
REAL=$(check_rules "${RULES_DIR}" "${REPO_ROOT}")
N_GLOBS=$(grep -cE '^(OK|IGN|BAD) ' <<<"${REAL}")
if [[ ${#RULE_FILES[@]} -eq 0 || ${N_GLOBS} -eq 0 ]]; then
  ko "vacuity: ${#RULE_FILES[@]} rules files, ${N_GLOBS} verdicts — nothing was checked"
else
  ok "vacuity: ${#RULE_FILES[@]} rules files, ${N_GLOBS} verdicts"
fi
while IFS= read -r v; do
  [[ -n ${v} ]] || continue
  case ${v} in
    OK\ *) ok "${v#OK }" ;;
    IGN\ *) ok "${v#IGN } (gitignored, absent here)" ;;
    *) ko "${v}" ;;
  esac
done <<<"${REAL}"

# ── 2. The CLAUDE.md index ─────────────────────────────────────────────────────────
printf '\n%b── 2. CLAUDE.md index of the rules files ──%b\n' "${C_BOLD}" "${C_RESET}"
INDEX=$(check_index "${CLAUDE_MD}" "${RULES_DIR}")
INDEXED=$(sed -n 's/^INDEXED //p' <<<"${INDEX}")
if [[ ${INDEXED:-0} -eq 0 ]]; then
  ko "index: no '  <name>.md   #   …' lines found in ${CLAUDE_MD} — the check would be vacuous"
else
  ok "index: ${INDEXED} lines read"
fi
BAD_INDEX=$(grep '^BAD-INDEX ' <<<"${INDEX}")
if [[ -z ${BAD_INDEX} ]]; then
  ok "index and rules directory agree both ways"
else
  while IFS= read -r v; do ko "${v}"; done <<<"${BAD_INDEX}"
fi

# ── 3. The checker can fire (fixtures) ─────────────────────────────────────────────
printf '\n%b── 3. fixtures: every defect is flagged ──%b\n' "${C_BOLD}" "${C_RESET}"
FX=$(mktemp -d)
trap 'rm -rf -- "${FX}"' EXIT
git -C "${FX}" init -q
mkdir -p "${FX}/real" "${FX}/emptydir/sub" "${FX}/rules"
printf 'x\n' >"${FX}/real/a.txt"
printf '/ign\n' >"${FX}/.gitignore"
fm() { printf -- '---\npaths:\n%b---\n\n# body\n' "$1" >"${FX}/rules/$2"; }
fm '  - "real/**"\n' good.md
fm '  - "nope/**"\n' dead.md
fm '  - "emptydir/**"\n' dironly.md
fm '  - "ign/**"\n' ignored.md
printf '# no frontmatter\n' >"${FX}/rules/nofm.md"
printf -- '---\npaths:\n  - "real/**"\n# never closed\n' >"${FX}/rules/unclosed.md"
printf -- '---\npaths:\n---\n' >"${FX}/rules/empty.md"
FXOUT=$(check_rules "${FX}/rules" "${FX}")
expect() { # expect <label> <regex>
  if grep -qE -e "$2" <<<"${FXOUT}"; then ok "fixture: $1"; else ko "fixture: $1 — not flagged; got: ${FXOUT//$'\n'/ | }"; fi
}
expect "good glob passes" '^OK good\.md real/\*\* 1$'
expect "dead glob flagged" '^BAD dead\.md nope/\*\* matches no regular file$'
expect "directory-only glob flagged" '^BAD dironly\.md emptydir/\*\* matches no regular file$'
expect "gitignored absent glob passes" '^IGN ignored\.md ign/\*\*$'
expect "missing frontmatter flagged" '^BAD nofm\.md frontmatter missing or unclosed$'
expect "unclosed frontmatter flagged" '^BAD unclosed\.md frontmatter missing or unclosed$'
expect "empty paths list flagged" '^BAD empty\.md no non-empty paths: list$'
printf '  good.md                #   real/**, gone/**, …\n  ghost.md               #   x/**\n' >"${FX}/CLAUDE.md"
FXOUT=$(check_index "${FX}/CLAUDE.md" "${FX}/rules")
expect "index glob absent from the file flagged" '^BAD-INDEX good\.md shows gone/\*\*, not in its paths:$'
expect "index line for a missing file flagged" '^BAD-INDEX ghost\.md listed in CLAUDE\.md but absent$'
expect "rules file without an index line flagged" '^BAD-INDEX dead\.md has no index line in CLAUDE\.md$'

# ── Summary ──────────────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
printf '\n'
if [[ ${TOTAL} -eq 0 ]]; then
  printf '  %bNO TESTS RAN%b\n\n' "${C_RED}${C_BOLD}" "${C_RESET}"
  exit 1
fi
if [[ ${FAIL} -eq 0 ]]; then
  printf '  %bALL PASSED   ✓ %d / %d%b\n\n' "${C_GREEN}${C_BOLD}" "${PASS}" "${TOTAL}" "${C_RESET}"
  exit 0
fi
printf '  %bFAILED       ✗ %d / %d%b\n' "${C_RED}${C_BOLD}" "${FAIL}" "${TOTAL}" "${C_RESET}"
for f in "${FAILURES[@]}"; do
  printf '    • %s\n' "${f}"
done
printf '\n'
exit 1
