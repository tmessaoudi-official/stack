#!/bin/sh
# Wraps a healthcheck command: writes elapsed time to tools/elapsed on first success per run.
# Container start time is recovered from PID 1 start time in /proc/1/stat since there
# is no T=0 hook available in healthcheck-only mode.
# Freshness gate: re-writes on each compose up by comparing mtime vs successes/base.
# Usage: global-stack-base-healthcheck-elapsed.sh <service-name> <healthcheck-cmd> [args...]
set -e

SERVICE="$1"; shift
SUCCESS_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/${SERVICE}"
BASE_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"
ELAPSED_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"

# Fast path: already written this run (success file newer than current base)
if [ -f "$SUCCESS_FILE" ] && [ -f "$BASE_FILE" ] && [ "$SUCCESS_FILE" -nt "$BASE_FILE" ]; then
  exec "$@"
fi

# Run the real healthcheck
if "$@" >/dev/null 2>&1; then
  # Guard: check freshness again inside (handles rapid retry races)
  if ! { [ -f "$SUCCESS_FILE" ] && [ -f "$BASE_FILE" ] && [ "$SUCCESS_FILE" -nt "$BASE_FILE" ]; }; then
    # Recover container start time from PID 1 (tini/docker-init with init: true)
    # Field 22 of /proc/1/stat = starttime; strip pid+comm first (comm can contain spaces)
    HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
    P1_TICKS=$(sed 's/.*) //' /proc/1/stat | cut -d' ' -f20)
    P1_START_BOOT=$(( P1_TICKS / HZ ))
    HOST_UPTIME=$(cut -d. -f1 /proc/uptime)
    DURATION=$(( HOST_UPTIME - P1_START_BOOT ))
    HOURS=$(( DURATION / 3600 ))
    MINUTES=$(( (DURATION % 3600) / 60 ))
    SECS=$(( DURATION % 60 ))
    printf '%s: %s - %d hours and %d minutes and %d seconds elapsed.\n' \
      "$(date '+%d-%m-%Y %H:%M:%S')" "$SERVICE" "$HOURS" "$MINUTES" "$SECS" \
      >> "$ELAPSED_FILE"
    touch "$SUCCESS_FILE"
  fi
  exit 0
else
  exit 1
fi
