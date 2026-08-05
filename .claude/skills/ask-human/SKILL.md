---
name: ask-human
description: >
  PLAIN-TEXT question protocol — never AskUserQuestion. Context, a minimal concrete example,
  clear numbered options, a recommended option first with its reason, then STOP and wait.
user-invocable: true
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj and pdfturbo ports. This skill previously mandated
  `AskUserQuestion` and forbade prose questions. That is now INVERTED:

    `AskUserQuestion` is FORBIDDEN in this project. It TIMES OUT in this container, so a
    question asked that way hangs the turn and can be lost with no trace — the turn ends as
    if nothing was asked. A gate that cannot fire is worse than none.

  The developer's instruction, 2026-08-05, verbatim: *"don't ever use the askuserquestion in
  this container! it times out! … and say it explicitly when there is no question"*.
  That second half is the `⏹ NO QUESTION` marker below.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then STOP — do not execute any other steps.
>
> ```
> /ask-human — Plain-text question protocol: context + example + numbered options,
>              recommended first with its reason, then stop and wait.
>              AskUserQuestion is forbidden — it TIMES OUT in this container.
>
> No flags — invoked automatically by Claude whenever a decision belongs to the developer.
> ```

---

# Plain-text question protocol

Every question to the developer is **ordinary text in the response**. No tool call, no dialog, no
hidden state. Then **STOP**: end the turn and wait. Never assume an answer, never proceed on a
default, never re-ask a different question because the first one went unanswered.

## The five required parts

| # | Part | Requirement |
|---|---|---|
| 1 | **Context** | What is being decided and *why it is being asked now* — one short paragraph. Enough that the developer needs no scrollback. |
| 2 | **Example** | A **minimal concrete example** of the problem — for a config question, the actual variable and its actual current value; for a failure, the real command and its real output. Not a description: the thing itself. |
| 3 | **Options** | Numbered, mutually exclusive, each with its own consequence. Ordinarily 2–4. |
| 4 | **Recommendation** | **Option 1 is the recommended one**, marked `(recommended)`, with the reason it wins stated in the same breath. |
| 5 | **Escape hatch** | A visible final option — *"none of these / challenge the premise"* — plus an explicit invitation to tweak any option. The developer must be able to answer *and* amend in one reply. |

## Shape

```
## Question — <one-line subject>

<Context: what is being decided, why now, what is blocked on it.>

Today:

    <minimal example — actual command, actual output/error, actual env value>

**Option 1 — <name> (recommended).** <What it does.> <Why it wins.>
   After: <the after-state — the same example under this option>

**Option 2 — <name>.** <What it does.> <Cost or risk that makes it second.>
   After: <after-state>

**Option 3 — none of these / challenge the premise.** <What you would want to hear.>

I'll wait for your answer before doing anything else.

❓ QUESTION — <one line naming the decision>
```

**The `❓ QUESTION` marker is the literal last line** — see `CLAUDE.md` § "Every reply ends with a
status marker", which is authoritative. It is mandatory on **every** reply, not just questions: a
reply that asks nothing ends with `⏹ NO QUESTION — <what you are waiting on>` instead. The options
always sit ABOVE the marker.

## Non-negotiable rules

- **Never `AskUserQuestion`.** Not as a fallback, not "just to try", not for a yes/no. It times out.
- **Never a bare `?` with no options.** If a real choice exists, enumerate it. An unstructured
  question makes the developer do the work of designing the options.
- **Always a recommendation.** "What do you prefer?" with no lean is an abdication. State the
  recommendation and why — the developer can then disagree cheaply.
- **The after-state goes in the option.** Prose written *outside* the option list is easy to miss
  while comparing options; put each option's consequence *inside* that option.
- **One STOP per question set.** Batch related questions (3–4 is fine when the developer asked to
  move faster), but end the turn after the batch — never answer your own question and continue.
- **Never re-open a ruled decision** without new evidence, and say what the new evidence is.
- **Challenge before accepting.** If the developer's proposal has a failure mode, say so in one or
  two sentences *and still deliver what was asked* under a stated assumption if they reaffirm it.

## When this protocol is mandatory

- Any **destructive or unrecoverable stack operation**, because the allow-list-only settings mean
  nothing blocks it mechanically: `make hard-restart`, `make soft-restart` (which `sudo rm -rf`s
  `tools/`), `docker volume rm` (the DB reset), `docker system prune`, `git push --force`.
  See `scripts/claude-bootstrap/BLAST-RADIUS.md` § /stack table.
- Any **write to `.env`** that is not a mechanical `env-update` AUTO decision — and
  `bin/env-update.sh --apply` itself, which cascades into `.env.local` and Dockerfile `ARG` lines.
  Preview with `--check --dry-run` first and show the diff in the question.
- Any **`GLOBAL_STACK_RELOAD_*=true`**: it costs a 30+ minute reinstall. Never set one silently.
- Any **change to a documented invariant or gotcha** in `CLAUDE.md`: the token invariant (success and
  error tokens must use the same identifier), the port-var trailing `:` rule, the tier-02-before-tier-03
  dependency, the two-phase `MODE=install`/`MODE=setup` model, `privileged: true` being deliberate.
  Weakening one of these is a project decision, not an implementation detail.
- A **certification loop that hits its cap** (5 rounds with findings still open → ask, never silently
  proceed).
- Any point where two readings of the request lead to **materially different work**.

## When it is NOT needed

- **`git add` / `git commit` / `git push` are autonomously authorised** — `CLAUDE.md` § "Auto-commit
  in /stack sessions" and § "Branch policy". Never ask permission to commit or to push to `master`.
  Asking is the violation here, not the commit.
- Routine judgement calls with an obvious default, and pure information questions.

Asking about everything is its own failure — it converts the developer into a decision queue. The
standing directive for this repo is *no interrupts*: state the task size, announce the plan, build it.
Decide what you can defend, state the assumption, and keep moving.

## Worked example

```
## Question — should 02nvm's error token change when the success token is renamed?

`docker/images/02nvm/docker-compose.yaml` sets GLOBAL_STACK_ERROR_TOKEN=nvm, but the startup
script writes its success marker to tools/successes/nvm-install. The healthcheck requires the
success file to be present AND the error file absent, so this container is permanently
unhealthy while being fully functional — masked by start_period: 24h. Fixing it changes a
health contract, so it is your call which side moves.

Today:

    $ grep ERROR_TOKEN docker/images/02nvm/docker-compose.yaml
    GLOBAL_STACK_ERROR_TOKEN=nvm
    $ ls tools/successes/ | grep nvm
    nvm-install
    $ docker compose ps 02nvm
    02nvm   starting (health: starting)   # ...for 14 hours

**Option 1 — fix the script to write tools/successes/${GLOBAL_STACK_ERROR_TOKEN} (recommended).**
   Single-sources the identifier from the compose file, which is what the token invariant in
   CLAUDE.md already mandates; no other service's marker name changes.
   After: healthcheck goes green within one interval; the invariant holds for 02nvm like the rest.

**Option 2 — change the compose var to GLOBAL_STACK_ERROR_TOKEN=nvm-install.**
   Also single-sources it, but renames the ERROR token, so any tools/errors/nvm left on a
   developer machine becomes an orphan that `make down` will not clear.
   After: healthcheck green, but one stale error file may linger and confuse /stack-health.

**Option 3 — none of these / challenge the premise.** If the mismatch is deliberate (e.g. another
   service greps for nvm-install), say so and I will document it as an exception instead.

I'll wait for your answer before doing anything else.

❓ QUESTION — which side of the 02nvm token mismatch should move?
```
