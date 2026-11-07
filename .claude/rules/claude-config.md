---
paths:
  - ".claude/**"
  - "CLAUDE.md"
  - "projects/CLAUDE.md"
  - "projects/.claude/**"
  - "projects/.gitkeep"
  - ".gitignore"
  - "claude-setup/**"
  - "docs/BLAST-RADIUS.md"
  - "bin/tests/claude-rules-paths.test.sh"
---

# Claude Code configuration of this repo — inventory and git traps

Split out of `CLAUDE.md` on 2026-11-07 to keep the always-loaded instruction files under the
150,000-char limit (`docs/plans/claude-md-size.plan.md`): the text below is unchanged except one stale fact: the inventory said `.claude/hooks/` holds "PostToolUse + PreCompact" hook scripts; `.claude/settings.json` registers only `PostToolUse` (`jq '.hooks|keys'`, 2026-11-07), and
each entry keeps a one-line index entry in `CLAUDE.md`. A new lesson about these files belongs
HERE, not in `CLAUDE.md`.

## From CLAUDE.md § Claude Code Configuration

The `.claude/rules/` list stays in `CLAUDE.md` § Claude Code Configuration.

Claude Code's configuration for this project lives in:

```
~/.claude/CLAUDE.md                      # Global reasoning framework — the developer's own install
~/.claude/THINKING.md                    #   from his bundle. This repo NEVER writes these; the
~/.claude/BLAST-RADIUS.md                #   container-era bootstrap that did was removed 2026-08-18
~/.claude/settings.json                  # Global settings (model, plugins) — never touched by this repo

claude-setup/claude-setup-global.tar.gz  # The dev's machine bundle: PROVENANCE for the docs above
docs/BLAST-RADIUS.md                     # The /stack blast-radius table — kept IN REPO because the
                                         #   global copy carries only `make hard-restart`

.claude/settings.json                    # Project permissions + hooks — CLAUDE CANNOT WRITE THIS
.claude/settings.local.json              # Local UI preferences (gitignored)
.claude/agents/                          # Agent definitions (project-scoped) — REVIEWERS ONLY;
                                         #   the global-stack-lead-dev orchestrator was deleted
                                         #   2026-08-19, work is done in the main conversation
  stack-infra-reviewer.md                #   ladder lens 1: correctness + regression
  completeness-reviewer.md               #   ladder lens 2: completeness + blast radius
  reproducibility-reviewer.md            #   ladder lens 3: clean-clone + destructive posture
.claude/hooks/                           # PostToolUse hook scripts
  shellcheck-on-write.sh                 # Lint .sh files on write        }
  hadolint-on-write.sh                   # Lint Dockerfiles on write      } all five are LIVE on
  yamllint-on-write.sh                   # Validate YAML on write         } this machine — the
  shfmt-on-write.sh                      # Check shell formatting         } tools are installed
  env-guard-on-write.sh                  # Guard .env edits               }
                                         # (log_obs(): the hooks above source the GLOBAL
                                         #  ~/.claude/hooks/log-helpers.sh, no-op stub when absent —
                                         #  global-is-reference ruling, 2026-08-18; no repo copy)
.claude/skills/                          # Slash skill definitions (read in place, no install)
  lint/  fmt/  check-versions/  bump-versions/  validate/  stack-health/
  env-diff/  service-info/  new-service/  debug-service/            # domain skills
  stack-ask-human/  stack-lenses/        # the two repo-specific workflow/review skills; every
                                         #   other workflow/review skill comes from ~/.claude/skills/
                                         #   (global-is-reference ruling, 2026-08-18)

var/claude/                              # Reports/review outputs (gitignored); handoffs go to the
                                         #   GLOBAL PreCompact hook's memory pipeline, not the repo
```

## The `paths:` frontmatter of `.claude/rules/*.md` — `bin/tests/claude-rules-paths.test.sh`

Added 2026-11-07 (`docs/plans/claude-md-size.plan.md`). A rules file loads only when a file matching
one of its `paths:` globs is opened, so every defect here is silent: a dead or typo glob means the rule
never loads for its area; a missing or unclosed frontmatter means the file is no longer path-scoped and
may load at session start, spending the 150,000-char budget CLAUDE.md was split to fit. The suite
(static, no network, ~3 s) checks, per rules file: frontmatter opens on line 1 and closes, `paths:` is a
non-empty list, and every glob matches at least one REGULAR file (bash `globstar` + `dotglob`). A glob
matching nothing passes only when its path is gitignored by the repo's own `.gitignore`
(`core.excludesFile=/dev/null`) — that keeps `docker/images/local.*` and `projects/.claude` green on a
clean clone. It also checks the `CLAUDE.md` index ("The path-scoped rules files:") both ways: every
rules file has a line, every line names a real file, every glob a line shows is in that file's
`paths:`. **A new rules file therefore needs its index line in `CLAUDE.md` in the same change.**
Built-in fixtures prove each check can fire on every run.

Live behaviour, probed 2026-11-07 (claude 2.1.319, haiku `-p`, throwaway `git init` copy of this repo's
rules and `.gitignore`, stub trigger files; harness `var/claude/rules-probe/`, gitignored): one trigger
per rules file plus every glob shape in use — 14 triggers — each loaded EXACTLY the set bash
`globstar`+`dotglob` predicts, the two gitignored `docker/images/local.*` triggers included; a session
touching nothing and a non-matching file loaded none; a mutated glob in a copy dropped its rule. **A rules
file whose opening `---` is removed loads at SESSION START in every session** — a broken frontmatter
spends the always-loaded budget, which is why the suite fails on it. Probe traps: haiku may pass a
relative `file_path`, and under the global CLAUDE.md it may run the size gate and never read the file —
assert the `Read` happened before trusting "none loaded".

## From CLAUDE.md § Gotchas & Pitfalls

(Moved whole from `CLAUDE.md` § Gotchas on 2026-11-07; the one-line rule stays there.)

- **`jq '… | unique'` on a settings array SORTS it — read the SET, never the diff.** A hand-off script that adds entries with `.permissions.deny = ((.permissions.deny // []) + $add | unique)` rewrites every pre-existing entry in alphabetical order as a side effect. Applying five denies to a 123-entry list produced a ~250-line diff that looked like a rewrite and was almost entirely reordering [observed 2026-08-19, Phase G]. Two consequences: a reviewer reading that diff cannot tell an addition from a reshuffle, and `unique` also silently **collapses duplicates**, which is a content change nobody asked for. Verify with a set difference, not `diff`: `jq -n --slurpfile b old.json --slurpfile s new.json '{added: ($s[0].permissions.deny - $b[0].permissions.deny), lost: ($b[0].permissions.deny - $s[0].permissions.deny)}'` — `lost` must be `[]`. Use `+ $add | unique` only when the sort is wanted; otherwise append and de-duplicate without reordering.
- **`projects/CLAUDE.md` needs `git add -f` — the `.gitignore` negation for it is inert.** `.gitignore`'s bare `/projects` line excludes the whole directory, and git cannot re-include a file whose *parent directory* is excluded, so its `!/projects/.claude/`, `!/projects/CLAUDE.md` and `!/projects/.gitkeep` negations have no effect. The files are still *tracked* (they were added before the exclusion), so they show up in `git status` and `git grep` and can be committed normally — but a plain `git add projects/CLAUDE.md` is refused with *"The following paths are ignored… projects"*. Use `git add -f`. This is safe **only because the path is already tracked** — confirm with `git ls-files <path>` before reaching for `-f`, since on an untracked path `-f` would pull genuinely-ignored machine-local content into the repo. Note `git check-ignore -v projects/CLAUDE.md` exits 1 ("not ignored") for exactly the same reason it is tracked, so it does **not** predict whether `git add` will succeed — the two disagree, and `git add` is the one that decides [observed 2026-08-19].
