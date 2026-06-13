#!/bin/bash
# =============================================================================
# DEPRECATED TEMPLATE — needs update before use. Known issues:
#   1. Startup script must be moved to docker/config/dist/bin/ghost-blog-bin/
#      (current path conf/bin/ does not match project conventions)
#   2. global-stack-base-init-mkcert.sh call below likely fails — Ghost runs as
#      USER node (non-root) and cannot write to the system CA store; needs a
#      user-space mkcert CA registration approach
#   3. No stackCatch error trap (all other startup scripts use it)
#   4. No file-based health signal: must write tools/successes/<TOKEN> on success
#      and tools/errors/$GLOBAL_STACK_ERROR_TOKEN on failure
# =============================================================================

SECONDS=0

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# you need to install it manually inside the container !! #bug
global-stack-base-init-mkcert.sh
node current/index.js

sleep infinity