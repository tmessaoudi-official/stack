---
name: bump-versions
spotlight: true
description: Use when applying pending version updates end-to-end — guided env-update check, explicit approval gate, apply, env-scan propagation, and rebuild reminder. Use after /check-versions reports AUTO entries.
user-invocable: true
---

Guided version-update flow: check → confirm → apply → propagate → rebuild reminder.

Optional filter: $ARGUMENTS (e.g. `--filter=NODE`, `--filter=type:dockerhub` — pass through to every `env-update.sh` call).

**This skill never executes the rebuild.** It prints the rebuild command at the end for the user to run manually.

## Steps:
1. **Check**: run `bin/env-update.sh --check $ARGUMENTS` and present the summary grouped by decision:
   - `[AUTO]` — ready to apply automatically
   - `[HOLD]` — gated (major-version jump or pre-release vs stable); not applied by `--apply`
   - `[SKIP]` — up-to-date
   - `[ERROR]` — fetch failures; explain each
   If there are zero `[AUTO]` entries, stop here and report — nothing to apply.
2. **Approval gate (MANDATORY)**: before any write, use `AskUserQuestion` listing exactly what would change (each AUTO entry: variable, current → new version). Options: apply all AUTO entries / abort. Never skip this gate — `--check` alone writes nothing, but everything after this point modifies `.env`.
3. **Apply**: on approval, run `bin/env-update.sh --apply $ARGUMENTS --yes`. Flag semantics: `--apply` is self-guarding — it TTY-prompts before writing, and non-TTY (this environment) requires `--yes`; the AskUserQuestion gate in step 2 is the human confirmation that `--yes` would otherwise bypass. `--apply` implies `--check`. HOLD entries are never applied (that requires `--force-hold` + `--confirm="Confirm override"` — out of scope for this skill).
4. **Propagate**: run `bin/env-scan.sh` to sync the updated values to `.env.local` and rewrite diverging `ARG` lines in Dockerfiles (`--sync-values=true` is the default). Report what was propagated.
5. **What each change needs + rebuild command**: do NOT advise deleting a `tools/versions/` marker or setting `GLOBAL_STACK_RELOAD_<RUNTIME>=true` — a pin bump needs neither. Runtime-installed tools are gated by `gs_version_gate`, which sees the new pin on the next start, WARNs and reinstalls it (either direction); the two ungated sites need nothing either — frankenphp's download path embeds its version, so a bump fetches a new file, and awscli has no pin. The `RELOAD_NODE*` / `_JAVA*` / `_FLUTTER3` switches do not even wipe (CLAUDE.md § Gotchas). Sort the changed pins into two groups and say which applies:
   - **Reinstalled on the next restart**: pins a startup script reads at boot — the runtimes and their packages, the Rust toolchain (02rust), the phpbrew / nvm / cargo tools, go / zig / mise (00base), phpmyadmin, the web servers and libmodsecurity.
   - **Only take effect after an image rebuild**: pins a Dockerfile consumes — hurl, and the Rust / rustup pins through 00base's hurl-build stage (a Rust bump recompiles hurl, ~6 min, and a pin that fails to build fails the 00base build).

   Then **print** the rebuild command — do not execute it:
   ```
   make down-n-rebuild-force-recreate
   ```

## Output:
- Step 1 summary table (AUTO/HOLD/SKIP/ERROR counts + the AUTO list)
- Confirmation of what was applied and what env-scan propagated
- Reload reminders for affected runtimes
- The rebuild command, clearly marked as **not executed**
