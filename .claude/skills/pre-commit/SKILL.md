---
name: pre-commit
description: Use before every git commit — analyses staged changes for blast radius, produces the four-dimension evidence table, and emits the exact commit command.
user-invocable: true
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj and pdfturbo ports. These deltas OVERRIDE the body below wherever
  they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Any "ask" below is
     plain prose per `.claude/skills/ask-human/SKILL.md`, and every reply ends with a
     `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line.
  2. NO TASK GATE. `git add` / `git commit` / `git push` are autonomously authorised
     (`CLAUDE.md` § "Git autonomy"), so this skill's job is the
     evidence table and the blast-radius check — never asking permission.
  3. REPORTS: this skill persists nothing; the commit itself is the durable artifact.
  4. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /pre-commit — Staged-diff gate: blast-radius analysis + four-dimension evidence table + exact commit command.
>
> Usage: /pre-commit [--message=<draft-message>]
>
> Flags:
>   --message=<text>   Seed the commit message with a draft (Claude will refine it)
> ```

---

## Differentiation from related skills

| Skill | Scope | Use when |
|-------|-------|----------|
| `/sweep` | All uncommitted changes, read-only smell review | You want bug/contract/security review across the working tree |
| `/pre-commit` | Staged diff only, commit ritual gate | You are about to commit — need blast-radius check + evidence table + commit command |
| `/lint` | Whole repo, tool-driven | You want shellcheck/hadolint/yamllint over every file, not just the diff |

---

## Side effects

**None** — this skill is read-only. It runs `git diff --staged` and `grep` to analyse staged changes,
then displays a report and commit command. It never calls `git commit` and never modifies any file.

---

## Step 0 — Precondition checks

**No task gate** (see adaptation note 2). State the task size in one line and continue.

**When this skill DOES stop**: only if an evidence row comes back INCOMPLETE (Step 5) — that is a real
finding, not a check-in, and it is reported in plain text per `/ask-human`.

**Git checks** (in order; stop at first failure):
1. `command -v git` — if not found: `ERROR: git not found in PATH` and stop.
2. `git rev-parse --is-inside-work-tree 2>/dev/null` — if it fails: `ERROR: Not inside a git repository` and stop.
3. `git diff --staged --name-only` — if empty: `ERROR: No staged changes. Stage files with git add first.` and stop.
4. **Branch check**: `git rev-parse --abbrev-ref HEAD`. If it is not `master`, that is a finding, not a
   warning — `CLAUDE.md` § "Git autonomy" says all work lands on `master`. Report it and stop.
5. Detect active merge/rebase (`.git/MERGE_HEAD`, `.git/rebase-merge/`) — if either exists:
   `WARN: merge or rebase in progress — evidence table will be produced but the commit command suppressed.`

---

## Step 1 — Inventory staged changes

Run `git diff --staged --stat` and `git diff --staged --name-only`. For each staged file, record
status (Added / Modified / Deleted / Renamed), path, and lines changed. Then classify:

- **Public interface** — `bin/*.sh` CLI flags, `make` targets, `.env` variable names, documented
  commands, `SKILL.md` frontmatter, hook behaviour
- **Service definition** — `docker/images/*/docker-compose.yaml`, `docker/images/*/Dockerfile`
- **Startup / runtime** — `docker/config/dist/bin/**` (remember: one script serves BOTH its tier-02
  and every tier-03 consumer)
- **Internal implementation** — `bin/lib/**`, helper functions
- **Tests** — `bin/tests/**`
- **Config/infra** — `Makefile`, root `docker-compose.yaml`, `.gitignore`, `.hadolint.yaml`, `.claude/**`
- **Docs** — `CLAUDE.md`, `README.md`, `TODO.md`, `templates/tips/**`

---

## Step 2 — Blast-radius analysis

For each file in **Public interface**, **Service definition**, **Startup / runtime** or **Config/infra**:

1. Extract the changed symbol, flag, variable, target or token from the diff.
2. Search the repo for references — not `~/.claude/`, which in this container is a generated copy:
   ```bash
   grep -rn "<symbol>" --include='*.sh' --include='*.yaml' --include='*.yml' --include='Dockerfile*' \
     --include='*.md' --include='Makefile' --include='.env' . 2>/dev/null | grep -v '^\./var/'
   ```
3. For each hit, decide whether it is a caller, a doc reference, or a config entry needing update.
4. Flag any reference NOT already in the staged diff as a **potential blast-radius item**.

**/stack-specific blast-radius rules — check every one that applies:**

| Changed thing | Also check |
|---|---|
| A `.env` variable | `.env.local` sync (`bin/env-scan.sh --dry-run`), every Dockerfile `ARG` of the same name, and any `${VAR}` that expands it |
| A startup script under `docker/config/dist/bin/<rt>-bin/` | **Every** service that runs it — the tier-02 installer AND all tier-03 consumers (`grep -rl '<script>' docker/images/*/docker-compose.yaml`) |
| `GLOBAL_STACK_ERROR_TOKEN` or a success-marker write | Both sides of the token invariant, and the healthcheck that polls them |
| A new/renamed service dir | `COMPOSE_FILE` in `.env` (and **no trailing `;`**), the five `Makefile` macro `$(eval $(call …))` lines, and the `.PHONY` block |
| A port variable | Trailing `:` present when set; no collision inside 42700–42899 (or 41700–41899 for `LOCAL`) |
| A `Makefile` target | The `.PHONY` declaration block |
| A Dockerfile `FROM` or image pin | `make check-image-versions`, and whether a rebuild is now required |
| A `bin/env-*.sh` flag or function | `bin/tests/env-*.test.sh`, `templates/tips/env-*.md` |

If a staged file is a deletion: all remaining callers are blast-radius items.

---

## Step 3 — Four-dimension evidence table

```
| Dimension    | Status | Evidence |
|--------------|--------|---------|
| Coverage     | OK / INCOMPLETE | <test file staged + the actual PASS count from running it, OR `bash -n` result for infra, OR "no test suite — N/A with reason"> |
| Docs         | OK / INCOMPLETE | <CLAUDE.md / templates/tips / SKILL.md / README staged, OR "no public interface changed"> |
| Config       | OK / INCOMPLETE | <.env + .env.local + Dockerfile ARG propagation done, COMPOSE_FILE updated, Makefile macros added, OR "no config impact — <reason>"> |
| Blast radius | OK / INCOMPLETE | <grep hits accounted for, OR the list of unresolved references> |
```

**Coverage must name the tool that actually ran.** In this container `shellcheck`, `hadolint`,
`yamllint`, `shfmt` and `yamlfmt` are **not installed**, so `/lint` and `/fmt` and the five
PostToolUse hooks silently no-op. `bash -n` and `bin/tests/*.test.sh` always work. Writing
"lint clean" when nothing linted is a false evidence row — the exact failure this table exists to
prevent. Either fetch a static binary and run it at the project threshold
(`shellcheck -x -S warning -f gcc`, `shfmt -l -i 2 -ci -bn`) or state plainly that only `bash -n` ran.

**INCOMPLETE** rows block the commit command in Step 5. List exactly what must be staged or run to
resolve each one.

---

## Step 4 — Commit message

Parse `--message=<text>` if provided; otherwise derive a draft from the staged diff:
- One imperative subject line (≤72 chars) with a `feat:` / `fix:` / `docs:` / `chore:` / `refactor:`
  prefix, matching the existing history style
- 1–3 short bullet lines for non-obvious context, and the *functional reason*, not just the what

**Never append `Co-Authored-By`** or any Claude attribution — developer directive, 2026-08-05
(their email only; they sign and re-push the commits themselves). `bin/git-strip-coauthored.sh` exists
to clean history where one slipped in.

**Note on file modes**: `core.fileMode=false` in this repo, so a `chmod` is never staged and never
shows in `git diff`. If the change included a permission fix, say so explicitly in the commit body —
that sentence is the only record it will ever have.

---

## Step 5 — Present the commit command

If all four evidence rows are **OK** — and since committing is autonomously authorised in this repo,
**run it** rather than merely printing it, then report the resulting short SHA:

```bash
git commit -F - <<'MSG'
<commit message here>
MSG
git push
```

If any row is **INCOMPLETE**: list what is missing, do NOT commit, and do NOT present the command.
Add the missing staged changes and re-run `/pre-commit`.

---

## Error handling summary

| Condition | Behaviour |
|-----------|----------|
| `git` not in PATH | ERROR + stop |
| Not inside a git repo | ERROR + stop |
| No staged changes | ERROR + stop |
| HEAD is not `master` | FINDING + stop — violates § "Git autonomy" |
| Active merge or rebase | WARN — produce the table, suppress the commit |
| `grep` unavailable | Skip that symbol; note "grep unavailable for `<symbol>`" in the blast-radius row |
| Staged deletion | All remaining callers are blast-radius items |
| Binary file staged | Note in coverage row: "binary file — no diff available; verify manually" |
| Linter not installed | Say so in the evidence row; never imply a lint that did not run |
