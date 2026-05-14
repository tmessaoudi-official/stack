# Bash Strict Mode

**What it solves**: Bash scripts that silently continue after errors, hide failures in pipes, or crash with unhelpful "line 47: unexpected end of file" messages. Without strict mode, a failed command is silently ignored and execution continues — often producing corrupt output or partial state changes that are hard to debug.

## The canonical header

```bash
#!/usr/bin/env bash
set -eEuo pipefail
```

Add this at the top of every bash script. Here's what each flag does and why.

---

## Flag-by-flag breakdown

### `-e` — exit on error

The script exits immediately when any command returns a non-zero exit code.

```bash
set -e
rm nonexistent_file   # exits here — without -e, execution would continue
echo "this line never runs"
```

**Critical trap**: `-e` does NOT fire inside conditions. Commands in `if`, `while`, `&&`, `||`, and negations (`!`) are evaluated for truth — their failure is expected and intentional:

```bash
# -e does NOT exit here — the false is inside a condition
if false; then
  echo "won't print"
fi

# -e does NOT exit here — && and || are condition operators
false && echo "skipped" || echo "fallback printed"

# -e DOES exit here — bare command, not inside a condition
false
```

This is by design and is usually what you want. If you need to check a command's exit code without triggering `-e`, wrap it:

```bash
if ! some_command; then
  echo "command failed" >&2
  exit 1
fi
```

### `-E` — inherit ERR trap in functions and subshells

Without `-E`, an `ERR` trap defined in the main script does NOT fire inside function calls. `-E` propagates the trap:

```bash
trap 'echo "Error at line $LINENO: $BASH_COMMAND" >&2' ERR

my_function() {
  false   # without -E: trap fires but LINENO is wrong; with -E: correct line reported
}
my_function
```

Always pair `-E` with `-e`.

### `-u` — treat unset variables as errors

Referencing an unset variable exits with an error instead of expanding to an empty string. Catches typos in variable names immediately:

```bash
set -u
echo "$UNDEFINED_VAR"   # Error: UNDEFINED_VAR: unbound variable
```

**This does NOT break default-value syntax** — the following is safe with `-u`:

```bash
echo "${MY_VAR:-default}"   # safe: provides a default if MY_VAR is unset
echo "${MY_VAR:?must be set}"   # exits with a message if MY_VAR is unset or empty
```

Only bare `$VAR` or `${VAR}` without a default/test operator triggers the error.

### `-o pipefail` — pipe failure = command failure

Without `pipefail`, a pipe's exit code is the exit code of the **last** command only. With `pipefail`, the exit code is the **first failed command** in the pipe:

```bash
# Without pipefail: exit code = 0 (grep succeeded)
false | grep "anything"   # false fails but grep succeeds; overall exit = 0

# With pipefail: exit code = 1 (false failed)
set -o pipefail
false | grep "anything"   # exits 1 because false failed
```

**Common gotcha**: `cat file | head -1` exits non-zero if `cat` succeeds but `head` terminates early (closing the pipe). With `pipefail`, this triggers `-e`. Fix by either accepting the behavior, or using process substitution: `head -1 < file`.

---

## Error trap for useful messages

```bash
trap 'echo "Error at line $LINENO: $BASH_COMMAND" >&2' ERR
```

This prints the exact line number and the command that failed. Combined with `-eE`, this fires whenever a command fails (even inside functions, with `-E`).

**Log to file**:
```bash
trap 'echo "$(date -Iseconds) | ERROR | $0 | line $LINENO: $BASH_COMMAND" >> /var/log/myscript.log' ERR
```

---

## Pipes in subshells still need pipefail

`set -o pipefail` applies to the current shell. Subshells inherit it (with `-e`/`-E`), but if you start a new shell explicitly, set it again:

```bash
bash -c "set -o pipefail; false | grep x"
```

Or use `bash -eEuo pipefail -c "..."` for a one-liner subshell with full strict mode.

---

## `set -x` for debug tracing

Prints each command before executing it (with a `+` prefix). Use selectively around the section you're debugging — not globally unless you want extremely verbose output:

```bash
set -x   # start tracing
do_something
do_something_else
set +x   # stop tracing
```

Output goes to stderr. Redirect to a file with `exec 2>trace.log` before `set -x`.
