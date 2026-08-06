---
name: forge
spotlight: true
description: Use when you want adversarial critique of architecture, design patterns, and structural decisions in this repo. Demands justification for every structural choice using the Chesterton's Fence protocol. 9 parallel analysis agents with exclusive ownership feed a synthesis agent that deduplicates and produces a clean action list. Never auto-applies anything.
user-invocable: true
args: "[--quick] [--focus=<A..I>] [--target=<path>]"
side-effects: Writes a report to var/claude/forge/<date>.md (gitignored; never committed)
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack ADAPTATION (2026-08-06) of the rent-watch port (2026-08-06), itself from the twes-in
  (2026-07-29) → pdfturbo (2026-07-27) → phorj (2026-07-22) line, descending from the developer's
  machine bundle `claude-setup-global-20260722` (committed here at
  claude-setup/claude-setup-global.tar.gz). The port's machinery (plain-text questions,
  reviewer-subagent certification, `var/claude/**` reports, the ≤5-agent cap, the Chesterton gate) is
  kept; what was RE-GROUNDED is the domain. rent-watch's housing-tenure hooks and twes-in's invoicing
  hooks are gone — /stack has no analogue. What is load-bearing here instead: the TIER MODEL and its
  build-dependency ordering, the two-phase install (one script serving `MODE=install` and
  `MODE=setup`), file-based health signalling, the three-level env cascade, and host↔container
  binding. These deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Every "ask" means:
     print the question, a minimal concrete example, numbered options, recommended option FIRST with
     its reason — then STOP. Protocol: `.claude/skills/ask-human/SKILL.md`. Every reply ends with a
     `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line.
  2. NO `advisor()` HERE — independent certification = the three fresh-context reviewer subagents in
     `.claude/agents/` (`stack-infra-reviewer`, `completeness-reviewer`, `reproducibility-reviewer`).
     Self-grading must be DISCLOSED as self-graded.
  3. REPORTS GO TO `var/claude/forge/` in the repo — gitignored via the blanket `/var` rule, never
     committed. NOT `~/.claude/projects/…`, which is wiped when the container is reclaimed.
  4. `--scope=global|both` IS REMOVED: `~/.claude/` here is GENERATED from repo files by
     `scripts/claude-bootstrap/install.sh`, so critiquing it critiques a copy.
  5. ≤5 concurrent subagents, in two sequential batches. Every agent writes its raw output to
     `var/claude/forge/raw/<letter>.md` BEFORE returning.
  6. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
  7. THIS REPO HAS AN UNUSUALLY GOOD WHY CORPUS, which is exactly what the Chesterton gate needs:
     `CLAUDE.md` § "Gotchas & Pitfalls" (~25 entries, most carrying their rationale),
     `templates/tips/*.md` (the full `env-update`/`env-scan` references), `TODO.md`, and the git log.
     **Read them before challenging anything.** A challenge to a fence whose WHY is written down in
     § Gotchas is not insight, it is a failure to read — and it is the single most likely way this
     skill produces noise here.
  8. INFRASTRUCTURE IS NOT APPLICATION CODE. Do not import object-oriented or functional-purity
     principles into Bash, Dockerfiles, Compose YAML or Make. The relevant authorities here are
     different: single-sourcing of truth, idempotency, fail-fast, least surprise, and the cost of
     coupling across a build-dependency graph. Flagging "no classes in this shell script" or
     "mutation in a procedural script" is a false positive, and the paradigm section below exists to
     stop it.
═══════════════════════════════════════════════════════════════════════════════════ -->

## Side effects

Read-only analysis. Writes one report to `var/claude/forge/<date>.md` (gitignored) plus per-agent raw
files under `var/claude/forge/raw/`. **Never modifies a single project file and never auto-applies a
recommendation** — every finding is a proposal for the developer to accept or reject.

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /forge — Adversarial design critic: interrogates structural decisions and demands justification
>          via the Chesterton's Fence protocol. Read-only; proposes, never applies.
>
> Usage: /forge [--quick] [--focus=<A..I>] [--target=<path>]
>
> Flags:
>   --quick          Agents A, B and D only
>   --focus=<X>      Run a single agent, then synthesise
>   --target=<path>  Critique a specific directory (default: the repo root)
> ```
>
> Then STOP.

---

# /forge — Adversarial Design Critic

## Differentiation from related skills

- **`/inspect`** — diagnoses health issues (security, dead code, error handling, config drift) and produces a P0–P3 defect list. `/forge` interrogates *design decisions*, not defects.
- **`/sleuth`** — hunts behavioural bugs: silent failures, logic traps, contract violations. `/forge` does not look for runtime bugs; it challenges structural choices that are perfectly functional.
- **`/gaps`** — finds what is missing or unfinished. `/forge` asks whether what exists is *shaped* right.

## Step 0: Setup

```bash
TARGET="${target_arg:-${CLAUDE_PROJECT_DIR:-$PWD}}"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
FORGE_DIR="$REPO_ROOT/var/claude/forge"
mkdir -p "$FORGE_DIR/raw"
TODAY=$(date +%Y-%m-%d-%H%M)
REPORT_PATH="$FORGE_DIR/$TODAY.md"
```

Announce: "Forging: `$TARGET` → saving to `$REPORT_PATH`".

## Step 1: Detect project context and load the WHY corpus

```bash
# The WHY corpus — read these FIRST, per adaptation note 7.
sed -n '/^## Gotchas/,/^## /p' "$TARGET/CLAUDE.md"
ls "$TARGET"/templates/tips/
cat "$TARGET/TODO.md" 2>/dev/null | head -40
git -C "$TARGET" log --oneline -50

# The subject
ls -d "$TARGET"/docker/images/*/ | wc -l
ls "$TARGET"/bin/*.sh "$TARGET"/bin/lib/ 2>/dev/null
find "$TARGET/docker/config/dist/bin" -name '*.sh' | wc -l
grep -c '' "$TARGET/.env"
```

Summarise as `PROJECT_CONTEXT` (tier inventory, script inventory, env-var count) and `WHY_CONTEXT`
(the gotcha list, the tips index, recent commit rationales). **Pass `WHY_CONTEXT` to every agent** —
an agent without it will re-litigate decisions that are already documented, which is this skill's
dominant failure mode.

## Step 2: Spawn analysis agents

Respect flags:
- `--quick`: spawn only A, B, D
- `--focus=<X>`: spawn only that agent, then go to Step 3
- Default: two sequential batches, **never more than 5 concurrent** — Batch 1 = A–E; Batch 2 = F–I.

Every agent writes raw output to `$FORGE_DIR/raw/<letter>.md` before returning, and returns only
`Complete — [N] findings`.

### Chesterton's Fence Protocol (applied inside every agent, for every finding)

Before escalating any structural choice to Questionable or Unjustified:

1. Check `CLAUDE.md` § Gotchas, `templates/tips/*`, inline comments, and `git log` (last 50 commits) for an explicit WHY.
2. Rationale found → verdict is **Justified** — note the rationale, stop. **Do not report the finding.**
3. Rationale not found → escalate **only if all four required fields are populated**:
   - **Named principle violated** — a specific authority (single-source-of-truth, Parnas/information hiding, Fowler/Shotgun Surgery, Ousterhout/deep module, POLA, Fail Fast, Tesler's Law)
   - **Concrete alternative** — one specific better structure, with a two-sentence implementation sketch
   - **Cost to change** — Low (< 1 day) / Medium (1–3 days) / High (> 3 days)
   - **Cost to keep** — the coupling tax, cognitive tax or evolution risk, in one sentence

If any of the four cannot be populated → verdict defaults to **Justified**; drop the finding. Incomplete
challenges are noise.

**The documented-deliberate list is an automatic Justified**, and reporting one is a failure of step 1:
`privileged: true`, `start_period: 24h` + `retries: 99999`, `password = username`,
`core.fileMode=false`, `set -xeE -o pipefail` without `-u` in startup scripts, the `/stack` absolute-path
requirement for host↔container binding, and the tier-number prefix not implying install behaviour
(four tier-02-prefixed services install nothing — that is documented and intentional).

### Paradigm awareness (per file type, not per project)

Identify the idiom before applying a principle:
- **Bash** — procedural and mutation-heavy by nature. Judge on: single-sourcing, idempotency, quoting, fail-fast, function size (>150 lines / >4 nesting is the project's own threshold), and the `# Sources:` convention (lib files declare dependencies, `main.sh` is the sole `source` coordinator).
- **Dockerfile** — judge on layer ordering, `ARG`→`ENV` discipline, build-dependency correctness, and cache friendliness. Not on OO anything.
- **Compose YAML** — judge on dependency expression (`depends_on` + `condition: service_healthy`), healthcheck honesty, and per-service file separation.
- **Make** — judge on DRY macro use, `.PHONY` completeness, and target-name honesty.

Suppress the cross-paradigm false positives. A shell script is not supposed to look like Java.

---

**Agent A — Tier architecture & build-dependency structure.** Is the tier hierarchy still the right decomposition? Interrogate: services whose tier prefix misleads about their role; a tier-03 runtime that could be a tier-02 concern or vice versa; the `05stable`/`05edge` combined images as a maintenance surface; whether the `local.*` escape hatch is load-bearing or accumulated; whether the build chain through the local registry is the simplest thing that works. Own: cross-service structure only.

**Agent B — Duplication & single-sourcing.** The project's own strongest principle. Interrogate: the same value defined in two places (`.env` vs a Dockerfile default vs a compose literal); the same logic in two startup scripts that could live in the prologue; the five Makefile macro families vs a single generated include; per-service compose files that are near-identical; a token or path string spelled out repeatedly instead of derived. Own: duplication only — do not comment on naming (Agent E) or coupling (Agent D).

**Agent C — Abstraction boundaries.** Is `bin/lib/` carved along the right seams, and is `base-bin/global-stack-base-prologue.sh` the right home for what it holds? Interrogate: a helper doing two unrelated jobs; a module boundary that forces callers to know internals; the `_GS_EU2_`/`_GS_ES_` prefix split as evidence of two systems that should share more (or less); the 141/1 prologue-exemption variance — is the exemption list principled or incidental? Own: intra-module structure and helper design.

**Agent D — Coupling & blast radius.** The highest-value lens in this repo. Interrogate the **two-phase model** head-on: one script serving both `MODE=install` and `MODE=setup` means every tier-03 consumer is coupled to its tier-02 installer's script. Is that the right trade (single-sourcing) or the wrong one (shotgun blast radius)? Also: `tools/` as a shared mutable filesystem between all containers; the env cascade making `.env` a global coupling point; `COMPOSE_FILE` as a hand-maintained list; what a new service must touch in seven places. For each: name the tax and the alternative. Own: coupling and change-amplification.

**Agent E — Naming & discoverability.** Interrogate names that mislead about behaviour — `make soft-restart` being the archetype (it `sudo rm -rf`s `tools/`), and `make save` exporting every image on the machine. Also: env-var names that do not say what they control; success/error token names that differ from their service; script names that hide their two-mode nature. A misleading name in a destructive path is the highest severity this agent can assign. Own: naming only.

**Agent F — Configuration design.** Is the `GLOBAL_STACK_*` env system the right shape at its current size? Interrogate: the `.env` → `.env.local` → Dockerfile `ARG` cascade as a three-way sync problem solved by a script rather than by design; nested `${VAR}` expansion and its ordering constraint; the port-var trailing-`:` convention as a footgun the type system cannot catch; the `@todo env-update` annotation language as an in-comment DSL; whether `RELOAD` flags should be flags at all. Propose alternatives with their migration cost. Own: config-system design.

**Agent G — Health-signalling & observability design.** Interrogate the file-based signalling model: is `tools/successes/` + `tools/errors/` + a 24h `start_period` the right mechanism, or a workaround for something else? Consider: a token invariant that must be maintained by hand in two places; healthchecks that cannot distinguish "still installing" from "wedged"; the absence of structured logs across containers; `tools/elapsed` and `locks/` as ad-hoc coordination. Own: health/observability design.

**Agent H — Build & tooling design.** Interrogate the Makefile as the primary interface: DRY macros vs a generated include; `docker-cli` as a central dispatcher; `generate-buildx` producing an untracked artefact that can go stale; `local.Makefile` double-colon extension; the split between `bin/` scripts and `make` targets — is the boundary principled? Own: build system and developer entry points.

**Agent I — Documentation as an interface.** `CLAUDE.md` is ~380 lines and `templates/tips/*` hold the full references. Interrogate the *shape*: is the split between them principled, or has `CLAUDE.md` become the place everything lands? Are the ~25 gotchas a sign of healthy institutional memory or of designs that need fixing rather than documenting? For each gotcha, ask the uncomfortable question: **could this have been made impossible instead of documented?** (e.g. the port trailing-`:` rule could be validated by a preflight check.) That reframing is this agent's whole value. Own: docs-as-interface.

---

## Step 3: Synthesis agent S

Spawn ONE synthesis agent with all nine raw files. It must:
1. Deduplicate — the same fence challenged by two agents becomes one finding with both framings.
2. Drop every finding failing the four-field Chesterton gate, and **report how many were dropped** — that count is a quality signal about the run itself.
3. Rank by (cost to keep) ÷ (cost to change) — best ratio first.
4. Separate **Justified-with-rationale** (a short list, useful as a record of *why* the design is what it is) from **Questionable** and **Unjustified**.
5. Write the full report to `$REPORT_PATH` and return only `Synthesis appended.`

Report shape:

```markdown
# /forge Report — <DATE>
Target: <TARGET> | Agents: <letters> | Findings after dedup: <N> | Dropped by Chesterton gate: <M>

## Executive summary
[3-5 sentences: is this design sound for its size? the single most valuable structural change?]

## Unjustified — no WHY found, all four fields populated
| # | Agent | Structure | Principle | Alternative | Cost to change | Cost to keep |

## Questionable — a WHY exists but is weak or outdated
## Justified — challenged and defended (the record of why this design is what it is)
## Could this have been made impossible instead of documented? (Agent I)
## Ranked action list — best cost-to-keep ÷ cost-to-change first
```

## Step 4: Announce — hard stop

Show the executive summary, the Unjustified table, and the top three ranked actions. Then, in **plain
text** per `/ask-human`, and STOP:

```
N structural findings (Unjustified: X | Questionable: Y | Justified: Z). M challenges were dropped
by the Chesterton gate. Nothing has been changed — every finding is a proposal.

1. Take the top-ranked actions (recommended) — name the IDs, e.g. `F1, F3`.
2. Show the Questionable list in full.
3. Show one agent's findings in full — name it, e.g. `agent D`.
4. Nothing — close the report.

❓ QUESTION — which structural findings should I act on?
```

*Never applies anything. A design critique the developer did not accept is just an opinion.*
