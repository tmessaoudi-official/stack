# Bash Subshell Data Flow

**What it solves**: The baffling experience of setting a variable inside a loop, function, or command substitution and finding it empty afterward. This is one of the most common sources of "bash doesn't work" frustration — and the fix requires understanding what actually creates a subshell.

## Why subshells can't set parent variables

A subshell is a **fork of the current process**. It inherits a copy of the parent's environment, but modifications to that copy are invisible to the parent when the subshell exits. The parent process continues with its original state.

What creates a subshell:
- `$(command)` — command substitution
- `(command)` — explicit subshell
- `command1 | command2` — each side of a pipe runs in a subshell
- `command &` — background process

```bash
MY_VAR="original"

# This does NOT change MY_VAR in the parent:
MY_VAR="changed" &    # subshell (background process)
wait
echo "$MY_VAR"        # prints: original

# This ALSO does not change MY_VAR:
echo "ignored" | MY_VAR="changed"   # right side of pipe = subshell
echo "$MY_VAR"        # prints: original
```

## The temp file pattern

For state that must escape a subshell, write to a file:

```bash
_tmpfile="$(mktemp)"
trap 'rm -f "$_tmpfile"' EXIT   # always clean up

# Write from subshell:
some_command > "$_tmpfile"

# Read in parent:
_result="$(cat "$_tmpfile")"
rm -f "$_tmpfile"
```

Use this for error propagation across subshells — write the error message or exit code to a file inside the subshell, read it back in the parent.

## stdout as a return channel

Functions communicate return values via stdout. The caller captures with `$()`:

```bash
get_value() {
  echo "the result"   # "returns" via stdout
}

VALUE="$(get_value)"  # captures stdout — note: this IS a subshell
```

**Consequence**: only one "return channel" exists (stdout). If your function needs to return multiple values, either: (1) use multiple temp files, (2) print a structured format and parse it, or (3) use file descriptor 3+.

## File descriptor 3+ for secondary output

stdout is reserved for return values. For a second output channel without going through a file:

```bash
exec 3>&1   # save stdout to fd 3
output="$(my_function 2>&1 1>&3)"  # capture stdout, let stderr through to fd 3
exec 3>&-   # close fd 3
```

This is advanced — use temp files unless you have a specific reason to avoid them.

## `mapfile`/`readarray` for array output without subshell

Capturing command output into an array without a subshell (avoids the variable-in-subshell problem):

```bash
# This works — process substitution, not a pipe:
mapfile -t MY_ARRAY < <(some_command)

# This does NOT work — pipe creates a subshell for the while loop:
some_command | while IFS= read -r line; do
  MY_ARRAY+=("$line")   # lost when pipe subshell exits
done
```

`< <(cmd)` is process substitution — the `while` loop runs in the current shell, not a subshell.

## The pipe-while bug (bash < 4.2)

In bash versions before 4.2, the last segment of a pipeline always runs in a subshell, even `while read`. The fix is the process substitution pattern above:

```bash
# Broken in bash < 4.2 (variable lost after loop):
command | while IFS= read -r line; do
  COUNTER=$((COUNTER + 1))
done

# Fixed — process substitution keeps while in the current shell:
while IFS= read -r line; do
  COUNTER=$((COUNTER + 1))
done < <(command)
```

Check your bash version: `bash --version`. Most modern Linux systems have 5.x, but Docker base images sometimes have 4.x.

## Named pipe (FIFO) for streaming between processes

When you need two long-running processes to communicate without polling a file:

```bash
_fifo="$(mktemp -u)"
mkfifo "$_fifo"
trap 'rm -f "$_fifo"' EXIT

producer_command > "$_fifo" &
consumer_command < "$_fifo"
wait
```

The `&` runs the producer in the background. The consumer reads from the FIFO as data arrives (streaming, not batch). Useful for pipelines where you can't buffer everything in memory.
