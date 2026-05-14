# lsof — List Open Files / Find What's Using a Port

**What it solves**: The "address already in use" error when starting a server. `lsof` tells you which process holds a port open so you can kill it.

## Find what's using a port

```bash
sudo lsof -i:PORT
# Example:
sudo lsof -i:8080
```

Output includes: `COMMAND` (process name), `PID`, `USER`, and the connection state.

## Kill the process found

```bash
# From lsof output, grab the PID from the second column
kill -9 PID
```

`-9` (SIGKILL) is immediate and cannot be caught. Use `kill PID` (SIGTERM) first if you want the process to clean up gracefully — only escalate to `-9` if it doesn't stop.

## Faster alternative: ss

`ss` is part of `iproute2` (pre-installed on all modern Linux systems) and doesn't require elevated privileges for most cases:

```bash
ss -tlnp | grep :PORT
# Example:
ss -tlnp | grep :8080
```

Flags: `-t` TCP, `-l` listening only, `-n` numeric ports, `-p` show process. This is faster than `lsof` for a quick port check.

## Gotcha: sudo required for other users' processes

`lsof -i:PORT` without `sudo` only shows processes owned by your user. If a system service (nginx, postgres, etc.) holds the port, you'll get empty output. Always use `sudo lsof` when hunting system-level processes.

## Find all open files for a process

```bash
lsof -p PID
```

Useful when debugging "too many open files" errors — shows every file descriptor the process has open.
