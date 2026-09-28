---
name: stack-ask-human
description: >
  /stack's additions to the global /ask-human question protocol — its mandatory cases
  (destructive stack ops, .env writes, RELOAD flags, documented invariants), git autonomy and a
  worked example. The protocol itself is global ask-human § Question quality.
user-invocable: true
---

<!-- THINNED 2026-09-28 (review-remediation 7.6): the shared question-quality protocol (five parts,
  shape, non-negotiable rules, when mandatory / not) moved to the global `ask-human` skill,
  § "Question quality"; this file keeps only what is specific to /stack. History: AskUserQuestion was
  banned (developer directive, 2026-08-05) in the cloud-container era (it failed silently there) and re-inverted 2026-08-18
  (de-containerization ruling); renamed ask-human → stack-ask-human the same day (a repo skill may not share
  a global skill's name). The full pre-thinning text is in git history. -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then STOP — do not execute any other steps.
>
> ```
> /stack-ask-human — /stack's additions to the global /ask-human question protocol:
>     its mandatory-question cases and a worked example.
>
> No flags — invoked automatically by Claude whenever a decision belongs to the developer.
> ```

---

# Question protocol — /stack additions

The protocol — the five required parts, the non-negotiable rules, when a question is mandatory and
when it is not — is the global `/ask-human` skill, § "Question quality". Whether a question stops
the turn or is shown and answered with the recommended option is the GLOBAL `~/.claude/CLAUDE.md` § "Mode — spec or autonomous". This file adds
only what is specific to this repo.

## Repo notes

- **Part 2 (the minimal example) here:** A **minimal concrete example** of the problem — the actual command output, the actual marker file, the actual compose line. Not a description of the state: the state.

## When a question is mandatory here

- Any **destructive or unrecoverable stack operation**, because the allow-list-only settings mean
  nothing blocks it mechanically: `make hard-restart`, `make soft-restart` (which `sudo rm -rf`s
  `tools/`), `docker volume rm` (the DB reset), `docker system prune`, `git push --force`.
  See `docs/BLAST-RADIUS.md` § /stack table.
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

The global cases (two readings leading to materially different work, …) apply as well.

## Not a question here

- **`git add` / `git commit` / `git push` are autonomously authorised** — `CLAUDE.md`
  § "Git autonomy". Never ask permission to commit or to push to `master`. Asking is the violation
  here, not the commit. (Push with plain `git push` — never `-u`; see that section.)

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
```
