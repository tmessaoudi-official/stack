# Claude container bootstrap

The `/stack` remote Claude containers are **ephemeral** — `~/.claude` starts empty every session,
while the project `CLAUDE.md` routes non-/stack work to "the global reasoning framework defined in
`~/.claude/CLAUDE.md`". Verified 2026-08-05: a fresh container has **no `~/.claude/CLAUDE.md` at
all**, so that reference was dangling and every non-/stack task ran with the framework silently
missing. This directory restores it per-session. Only committed state survives container reclaim, so
the framework has to travel in the repo.

| File | What | Provenance |
|---|---|---|
| `CLAUDE-global.md` | The 8-phase workflow + core rules + mental models, with a `/stack` adaptation header. The body is the dev's bundle verbatim **except** the amendments listed in that header | Bundle `claude-setup-global-20260722-103235` |
| `THINKING.md` | Thinking-frameworks library (loaded on demand, not at session start) | Same bundle, **byte-identical** |
| `BLAST-RADIUS.md` | Pre-flight state checks for destructive commands, + a `/stack` blast-radius table | Same bundle + `/stack` note |
| `install.sh` | Idempotent `cp -u` into `~/.claude/` (never clobbers a newer user copy) | New |
| `hooks/precompact-handoff.sh` | **PreCompact hook** — writes a deterministic handoff to `var/claude/handoff/` just before context compaction | Bundle hook, substantially adapted |
| `hooks/log-helpers.sh` | `log_obs()` structured logging, never fatal (framework Rule 13) | Bundle |
| `apply-pending-settings.sh` | Applies a `settings.json.pending` that Claude is classifier-blocked from writing (see below) | New |

The source bundle is committed at **`claude-setup/claude-setup-global.tar.gz`** (sha256 `74b18d40…`),
which is where the three documentation files above came from. Before this directory existed, that
tarball was in the repo but referenced by nothing.

Runs automatically via the `SessionStart` hook in `.claude/settings.json`. Safe to run by hand:

```bash
bash scripts/claude-bootstrap/install.sh      # idempotent; silent no-op when current
```

`install.sh` is **one-directional** (repo → `~/.claude`) on purpose. It must never copy anything *out*
of `~/.claude`: `~/.claude.json` holds the OAuth account, `userID` and `machineID`, and this working
tree is one `git add -A` away from history. The upstream port this was adapted from did exactly that
behind a commented-out block; it is omitted here rather than merely disabled.

## Skills and agents — repo-native, no install

The skills live under `.claude/skills/` and Claude Code reads them **in place** from the clone;
`install.sh` does not touch them. **23** in total — 10 domain + 13 ported:

- **10 domain skills**, pre-existing and /stack-specific: `/lint`, `/fmt`, `/check-versions`,
  `/bump-versions`, `/validate`, `/stack-health`, `/env-diff`, `/service-info`, `/debug-service`,
  `/new-service`.
- **13 ported from the bundle** (2026-08-05/06), each carrying an adaptation header that records what
  was changed and why: `/ask-human`, `/handoff`, `/pre-commit`, `/sweep`, `/expanding-context`,
  `/converge`, `/retrospective`, `/sleuth`, `/inspect`, `/gaps`, `/forge`, `/cross-check`,
  `/aggregate-findings`. That is the same 13-skill core the four sibling repos (`phorj`, `pdfturbo`,
  `twes-in`, `rent-watch`) converged on.

All 23 declare `disallowed-tools: AskUserQuestion`, which removes the tool from the pool while a skill
is active — the only mechanical backing the plain-text question rule has, and it clears on the next
user message.

The review skills each add a **mandatory `/stack` lens K** on top of the generic dimensions, because
the generic A–J set does not know what makes this repo fail: infrastructure divergence (`/sleuth`),
configuration hygiene (`/inspect`), and a per-service completeness matrix (`/gaps`).

### Agent definitions — the certification panel

`advisor()` does not exist in this environment, so the reviewer subagents in `.claude/agents/` are the
**top** rung of certification, not a fallback. `CLAUDE.md` § "Certification ladder" is authoritative;
`/converge` executes it mechanically.

| Lens | Agent |
|---|---|
| correctness + regression | `stack-infra-reviewer` |
| completeness + blast radius | `completeness-reviewer` |
| reproducibility + destructive posture + secrets | `reproducibility-reviewer` |

Plus `global-stack-lead-dev`, the pre-existing orchestrator that /stack infrastructure work is
delegated to. `completeness-reviewer` is the one lens name shared with `pdfturbo`, `twes-in` and
`rent-watch` — the content is per-project, the lens is the convention.

Deliberately **not** imported: the bundle's memory-pipeline and config-portability families, all 57
`mcp/**` files, and `/qa-sweep` (browser QA — this project has no application UI).

## Questions are PLAIN TEXT — `AskUserQuestion` is forbidden here

Developer ruling, 2026-08-05. `AskUserQuestion` **times out in this container**, so a question asked
that way hangs the turn and can be lost with no trace — a gate that cannot fire is worse than no
gate. Every question is: context → a minimal concrete example → numbered options → the recommended
option **first** with its reason → a visible *"none of these / challenge the premise"* escape →
**STOP**. `.claude/skills/ask-human/SKILL.md` is that protocol, and `CLAUDE-global.md`'s question
rules were rewritten to match (upstream mandated the exact opposite).

Paired with it: **every reply ends with a `❓ QUESTION` or `⏹ NO QUESTION` status marker** as its
literal last line, so a pause is never mistaken for a question. See the project `CLAUDE.md`, which is
authoritative on both.

## `settings.json` — the hand-over loop

Claude Code's classifier blocks Claude from writing `.claude/settings.json` (it is Claude's own
permission surface) — **verified in this container on 2026-08-05**, a one-line `Edit` was denied. In a
remote container the developer has no terminal either, so a settings change travels through the repo:

1. Claude writes `scripts/claude-bootstrap/settings.json.pending` and commits it.
2. The developer pulls and runs:

   ```bash
   bash scripts/claude-bootstrap/apply-pending-settings.sh
   ```

3. They review the diff, commit and push. Claude pulls to re-sync.

The script validates the JSON with `jq` **before** touching the live file (a malformed
`settings.json` breaks every future session), backs up the old one to a gitignored
`.claude/settings.json.bak.<epoch>`, and **deletes the pending file** on success — so the repo never
carries two copies of the settings. It stages, commits and pushes nothing.

### Current settings shape

`defaultMode: auto`, an **allow-list only** — no `deny`, no `ask` — plus four hook events.

The allow-list-only decision is the developer's (2026-08-05): this container is driven from the
web/mobile app, where an `ask` can block *him* with no terminal to approve from, and a `deny` blocks
him too. Machine-level protections for destructive stack operations stay in his personal global
settings, which this repo never touches.

**The trade-off is explicit**: nothing here mechanically stops `make soft-restart` (which `sudo rm
-rf`s `tools/`), a `docker volume rm` (which is the DB reset), or a stray `RELOAD` flag. The previous
settings had 23 `deny` rules covering these. `BLAST-RADIUS.md` now carries that weight by discipline
instead — its `/stack` table lists each of those blast radii. Two of those `deny` rules were
**already inert in this container anyway**: they were written as absolute paths
(`Read(/stack/var/**)`, `Read(/stack/docker/data/**)`) and this checkout lives at
`/home/user/stack`, so they matched nothing.

Hooks wired: `SessionStart` → `install.sh`; `PreCompact` (both `auto` and `manual` matchers) →
`hooks/precompact-handoff.sh`; plus the project's pre-existing `SubagentStop` reminder and five
`PostToolUse` lint hooks.

> **Container caveat on the lint hooks**: `shellcheck`, `hadolint`, `yamllint`, `shfmt` and `yamlfmt`
> are **not installed** in this remote container, so those five `PostToolUse` hooks silently no-op
> here. They work on the developer's machine. Anything written from a container session should be
> linted explicitly before commit — see the "Testing & Verification" section of the project
> `CLAUDE.md`.

## The PreCompact handoff

`hooks/precompact-handoff.sh` writes `var/claude/handoff/handoff-<stamp>.md` plus a `latest.md`
immediately before compaction: git state, the uncommitted paths, the last 5 commits, **the `/stack`
health markers** (`tools/errors/` + `tools/successes/` — the state `git status` cannot see, and the
fastest explanation for a red stack), the **last 8 user messages verbatim**, the last thing Claude
said, and the pointers to resume from. Everything under `var/` is already gitignored, so these are
never committed.

It is **deterministic — no LLM call**. The upstream hook shelled out to `claude -p` (Haiku) on every
compaction; that spends the same weekly quota the developer is rationing and fails whenever the API
is unreachable. Opt in with `GS_HANDOFF_LLM=1` (model via `GS_HANDOFF_MODEL`) to append a narrative on
top of the deterministic note. `GS_HANDOFF_DIR` overrides the output directory (default:
`<cwd>/var/claude/handoff`). The `GS_` prefix follows the `GS_STARTUP_DRY_RUN` precedent and keeps
these out of the `GLOBAL_STACK_*` namespace that `env-scan`/`env-update` manage.

Contract: a PreCompact hook must never block compaction, so it **always exits 0** — every failure
path still logs a reason through `log_obs`. Verify with:

```bash
bash bin/tests/precompact-handoff.test.sh
```
