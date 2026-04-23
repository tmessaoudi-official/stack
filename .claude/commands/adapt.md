# /adapt — Project Adaptation

Post-import command: explore this project deeply, fill all ADAPT markers left by `/import-setup`,
then self-destruct. Runs once. Safe to re-run — if no markers remain, exits without destroying itself.

---

## Phase 0: Guard — scan before doing anything

Run these two checks:

```bash
grep -rn '<!-- ADAPT:' CLAUDE.md .claude/ 2>/dev/null
find .claude/hooks/ -name '*.sh.template' 2>/dev/null
```

**If both return empty** (zero ADAPT markers, zero `.sh.template` files):
→ Reply: "No ADAPT markers found — this project config is already adapted. Nothing to do."
→ Stop. Do NOT self-destruct (idempotent exit).

**Otherwise**: report a summary before proceeding:
```
Found:
  • N ADAPT markers across M files:
      CLAUDE.md           — X markers
      .claude/settings.json — Y markers  (if any)
      .claude/commands/   — Z markers    (if any)
      .claude/agents/     — W markers    (if any)
  • K hook template(s) pending activation (.sh.template files)
```

---

## Phase 1: Deep exploration — 4 parallel Explore agents

Launch all four agents simultaneously. Brief each agent to return a concise structured report.

**Agent 1 — Tech stack**
Probe: `package.json`, `composer.json`, `Gemfile`, `Cargo.toml`, `go.mod`, `pyproject.toml`,
`requirements.txt`, `*.csproj`, `.nvmrc`, `.ruby-version`, `.python-version`, `.tool-versions`,
`Dockerfile*`, `docker-compose*.yaml`.
Report: primary language + version, framework + version, package manager, notable dependencies.

**Agent 2 — Project structure**
Probe: top-level directory tree (2-3 levels), `README.md`, `docs/`, `CONTRIBUTING.md`,
main entry points, config files, key source dirs.
Report: what the project does (1 sentence), key directories with their purpose, main entry point(s).

**Agent 3 — CI/CD + scripts + workflows**
Probe: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `Makefile`, `bin/`, `scripts/`,
`.pre-commit-config.yaml`, `taskfile.yml`, `justfile`.
Report: build command, dev-server command, deploy command, common one-liners.

**Agent 4 — Testing + quality**
Probe: test directories, `jest.config.*`, `pytest.ini`, `phpunit.xml`, `.rspec`, `go test`,
`.eslintrc*`, `.pylintrc`, `rubocop.yml`, `shellcheck` usage, `prettier.config.*`,
`black` config, `shfmt` usage, `rustfmt.toml`.
Report: test command(s), linter(s) with file extensions, formatter(s) with file extensions.

---

## Phase 2: Phase gate — mandatory stop

Synthesize the four agent reports into a one-screen summary:

```
ADAPT SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Detected stack:   [language+version] / [framework] / [package manager]
Test command:     [command]
Linter(s):        [tool] → [ext]
Formatter(s):     [tool] → [ext]

What will be filled:
  CLAUDE.md › What This Project Is          (from README + stack detection)
  CLAUDE.md › Architecture                  (from dir structure probe)
  CLAUDE.md › Common Workflows              (from Makefile/scripts/CI)
  CLAUDE.md › Testing & Verification        (from test probe)
  CLAUDE.md › File Layout Quick Reference   (from structure probe)
  CLAUDE.md › Gotchas & Pitfalls            (from README warnings / .env.example)
  CLAUDE.md › Credentials & Stateful Data   (from .env.example / config files)
  CLAUDE.md › Debugging section             (inferred from primary component)
  CLAUDE.md › Claude Code Tooling lists     (from .claude/ inventory)
  CLAUDE.md › Claude Code Configuration     (from .claude/ inventory)
  .claude/hooks/lint-on-write.sh.template   → activate as lint-on-write.sh  (if linter found)
  .claude/hooks/format-on-write.sh.template → activate as format-on-write.sh (if formatter found)
  .claude/settings.json                     (add detected tools to allow list)
  [any other ADAPT markers found in Phase 0]

Proceed with adaptation? (yes/no)
```

**Hard stop** — do not write anything until the user replies "yes" (or equivalent affirmation).
If "no": exit without self-destructing.

---

## Phase 3: Fill all ADAPT markers

Work through each file systematically. For every `<!-- ADAPT: ... -->` block, replace it with
project-specific content derived from the exploration above. Never leave a partial fill.

### CLAUDE.md — section by section

**`## What This Project Is`**
Write 2–5 sentences: what the project does, platform/runtime, key tech choices,
single-dev vs team, release cadence. Source: README first paragraph + stack detection.

**`## Architecture`**
Describe key components and their relationships. A Markdown table or annotated list works well.
Source: structure probe + CI/CD probe (services, modules, layers). If microservices found,
map service → purpose. If monolith, map top-level dirs → responsibility.

**`## Common Workflows`**
List the 5–10 most-used commands as bash one-liners with inline comments:
```bash
make test          # Run test suite
make dev           # Start dev server
# ...
```
Source: CI/CD probe. Prefer Makefile targets > package.json scripts > bare CLI commands.

**`## Testing & Verification`**
Include: how to run tests, what "passing" looks like, test types (unit/integration/E2E),
any coverage thresholds. Source: test probe + CI YAML.

**`## File Layout Quick Reference`**
Annotated 2-level tree. Focus on non-obvious directories.
Source: structure probe. Omit `node_modules/`, `.git/`, build output dirs.

**`## Gotchas & Pitfalls`**
3–8 project-specific traps. Look for:
- README "Note:" / "Warning:" / "Important:" sections
- `.env.example` keys with non-obvious values
- CI retry/timeout hacks that hint at flaky areas
- Known workarounds in commit history (if accessible)

**`## Credentials & Stateful Data`**
Where credentials/keys/data live. Source: `.env.example` key names, config file locations,
README setup sections.

**`## Debugging a Failed [X]`**
Fill `[X]` with the primary service/component name (e.g. "Container", "Test Suite", "API").
Write 5–8 numbered steps derived from the project's actual debug surface
(log locations, health-check commands, dependency checks).

**Top-of-file routing block**
- If an agent `.md` exists in `.claude/agents/`: fill with the agent's name and delegation rule.
- If no agent exists: delete the entire routing block (it's optional).

**Claude Code Tooling lists** and **Claude Code Configuration** tree:
Replace all ADAPT placeholders with the actual `.claude/` file inventory
(slash commands present, hooks present, agents present, settings.json summary).

### Hooks — activate templates

For each `*.sh.template` in `.claude/hooks/`:

1. Read the template. Fill `LINTER`/`FORMATTER`, `DIFF_FLAG`, and `EXT` from the probe data.
   - Linter template: use the detected linter binary name + primary source extension
   - Formatter template: use the detected formatter binary name + its diff flag + source extension
2. Write the filled content to the same path without the `.template` suffix (e.g. `lint-on-write.sh`).
3. Make it executable: note in the summary — the user must run `chmod +x .claude/hooks/<name>.sh`.
4. Add a `PostToolUse` entry to `.claude/settings.json`:
   ```json
   {
     "matcher": "Edit|Write",
     "hooks": [{ "type": "command", "command": ".claude/hooks/<name>.sh" }]
   }
   ```
5. Do NOT delete the `.sh.template` file — leave it as documentation of the template that was used.

### settings.json — allow list

Add the detected linter/formatter/test-runner binaries to the `allow` list if not already present.
Preserve all existing entries; only append.

### Commands — any residual ADAPT markers

For each `.md` file in `.claude/commands/` that still contains `<!-- ADAPT: -->` blocks:
fill from probe data where possible; leave unfilled only if probe data is truly insufficient,
and annotate why.

---

## Phase 4: Self-destruct

After all fills are complete:

1. Count residual `<!-- ADAPT:` markers across all files:
   ```bash
   grep -rn '<!-- ADAPT:' CLAUDE.md .claude/ 2>/dev/null | grep -v '.sh.template'
   ```

2. **If zero remaining**: self-destruct and report success:
   ```
   Adaptation complete — all ADAPT markers resolved.
   /adapt has self-destructed (.claude/commands/adapt.md removed).
   
   Next steps:
     chmod +x .claude/hooks/*.sh   (if hooks were activated)
     /sync-config --check          (verify config is coherent)
   ```
   Then delete this file: `rm .claude/commands/adapt.md`

3. **If any remain**: list every residual marker with file + line number, explain why
   the probe couldn't fill it (e.g. "no README found", "ambiguous architecture"),
   and what the user should write there manually. Do NOT self-destruct.
   The user can re-run `/adapt` after manually filling those sections — at that point
   only the remaining markers will be addressed and the self-destruct will trigger.
