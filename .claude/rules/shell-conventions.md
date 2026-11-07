---
paths:
  - "bin/**"
  - "docker/config/dist/bin/**"
  - "docker/images/*/conf/bin/**"
  - "templates/shell/**"
  - ".claude/hooks/**"
---

# Shell coding conventions

Split out of `CLAUDE.md` on 2026-11-07 to keep the always-loaded instruction files under the
150,000-char limit (`docs/plans/claude-md-size.plan.md`): the text below is unchanged, and
each entry keeps a one-line index entry in `CLAUDE.md`. A new lesson about these files belongs
HERE, not in `CLAUDE.md`.

## From CLAUDE.md § Shell Coding Conventions

`CLAUDE.md` keeps the `set` flags, **Dependencies** and **Version ordering**.

- **Variable prefixes**: `_GS_EU2_` for env-update, `_GS_ES_` for env-scan
- **Include guards** (every lib file):
  ```bash
  [[ -n "${_GS_EU2_MODULENAME_SH_LOADED:-}" ]] && return 0
  readonly _GS_EU2_MODULENAME_SH_LOADED=1
  ```
- **Error propagation across subshells**: write to temp files, read back in parent — stdout is reserved for return values
- **Parallel arrays** instead of objects (bash limitation): records indexed by count
- **Function naming**: `_gs_eu2_<module>_<action>` for env-update; `es_<action>` or `_gs_es_<action>` for env-scan
- **CLI-first with API fallback**: activates the correct runtime (nvm/pyenv/rbenv), tries CLI in subshell, falls back to API
- **NO_COLOR** support per no-color.org; color only when `stdout` is a terminal
- **Function size**: functions >150 lines or nesting >4 levels → decompose (precedent: d953279)
- **`# Sources:` convention**: lib files declare their dependencies via `# Sources: <file>` header comments but never `source` them — `main.sh` is the single coordinator of all `source` calls
