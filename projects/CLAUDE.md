# /stack/projects/ — Independent Projects Zone

This directory contains projects that are **independent** of the `/stack` infrastructure.
They may *run inside* stack runtime containers (e.g. `03node24`, `03php84`, `03python3`),
but they are NOT part of `/stack` infra tooling and MUST NOT inherit its rules.

## Routing (important)

Do **NOT** delegate tasks in this tree to the `global-stack-lead-dev` agent. That agent
is scoped to `/stack` infrastructure only (Docker images, Makefile, `bin/*`, `docker/*`,
env annotation system, compose configs). Tasks here are handled:

1. **By each sub-project's own config** if it defines `CLAUDE.md` or `.claude/` — defer to it.
2. **Otherwise directly by the main conversation** using the global reasoning framework
   (`~/.claude/CLAUDE.md`): task categorization → 8-phase workflow → mental models.

When a task genuinely crosses the boundary (e.g. "the node container this project runs in
is failing to start") — clearly state that it's a `/stack` infra concern and route the
infra portion explicitly, but do NOT auto-route anything written inside `/stack/projects/`.

## Config isolation

This directory's `.claude/settings.json` sets `claudeMdExcludes: ["/stack/CLAUDE.md"]`
so the parent `/stack/CLAUDE.md` (which mandates delegation to `global-stack-lead-dev`)
is NOT loaded when working here. The global `~/.claude/CLAUDE.md` still loads — that's
correct, it contains the domain-agnostic reasoning framework.

## Per-project config

Each sub-project may add its own `.claude/` subdir with project-specific settings,
hooks, agents, and `CLAUDE.md`. Those take precedence over this file.

Examples of sub-projects (gitignored, machine-local):
- `prsnl/` — personal project
- `trngs/` — training/learning experiments

## Quick guide for new sub-projects

```
/stack/projects/<name>/
├── .claude/
│   ├── settings.json     # project-specific permissions (hooks, allows, denies)
│   └── hooks/            # project-specific PostToolUse hooks (optional)
├── CLAUDE.md             # project-specific instructions (optional)
└── ...project files...
```
