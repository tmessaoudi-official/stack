# Bash Library Pattern

**What it solves**: Bash projects larger than ~300 lines that become an unmanageable tangle of global variables and functions with no structure. Without a library pattern, sourcing the same file twice silently redefines functions, variable names clash across modules, and there's no clear separation between internal state and public API.

## Include guard (prevent double-sourcing)

Every library file starts with an include guard. If the file has already been sourced, the `return` exits the source call immediately:

```bash
[[ -n "${_MYPROJECT_MODULE_LOADED:-}" ]] && return 0
readonly _MYPROJECT_MODULE_LOADED=1
```

Use `readonly` so the guard variable can never be unset or overwritten by accident.

## Function namespacing

Functions are global in bash — there are no modules. Use a consistent prefix to avoid collisions:

```bash
# Internal functions (not for callers to use directly):
_myproject_module_parse_args() { ... }
_myproject_module_validate() { ... }

# Public API (callable by other scripts):
myproject_module_run() { ... }
```

Convention: all-lowercase with underscores, prefixed by `_projectname_module_` for internal or `projectname_module_` for public. The leading underscore signals "internal — don't call this from outside".

## Variable namespacing

```bash
# Internal state (module-private):
_MYPROJECT_MODULE_CACHE=""
_MYPROJECT_MODULE_COUNT=0

# Public/exported values (available to callers and child processes):
MYPROJECT_RESULT=""
export MYPROJECT_OUTPUT_DIR
```

Convention: `_PROJECT_MODULE_VAR` for internal state (never exported), `PROJECT_VAR` for the public interface.

## Source with path resolution

Scripts that source other files must locate them relative to their own location — not the caller's current directory. This pattern works regardless of where the script is called from:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/module.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
```

`BASH_SOURCE[0]` is the path of the script itself (unlike `$0`, which can be the caller). The `cd && pwd` resolves symlinks and relative paths to an absolute path.

## stdout is a return channel

In bash, functions return values by printing to stdout. This is the idiomatic pattern:

```bash
# Function "returns" a value via stdout
get_version() {
  echo "1.2.3"
}

# Caller captures it
VERSION="$(get_version)"
```

**Consequence**: functions must not print anything to stdout except their return value. Status messages, logs, and errors go to stderr:

```bash
process_file() {
  local file="$1"
  echo "Processing $file..." >&2   # status → stderr
  # ... do work ...
  echo "$result"   # return value → stdout
}
```

## State that must cross subshell boundaries → temp file

Variables set inside a subshell (command substitution `$(...)`, pipe `|`, background `&`) are invisible to the parent. For state that must escape a subshell, write to a temp file:

```bash
_tmpfile="$(mktemp)"
trap 'rm -f "$_tmpfile"' EXIT   # always clean up

some_subshell_operation > "$_tmpfile" 2>&1
_result="$(cat "$_tmpfile")"
```

This is the correct pattern for error propagation across subshells — write the error to a temp file in the subshell, read it back in the parent.

## Gotcha: source inside a subshell doesn't affect the parent

```bash
# This does NOT load the library in the current shell:
(source "${SCRIPT_DIR}/lib/module.sh")

# This does:
source "${SCRIPT_DIR}/lib/module.sh"
```

Subshells are forks — any `source` or variable assignment inside `(...)` is lost when the subshell exits. Always source in the main shell context.
