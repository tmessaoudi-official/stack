---
paths:
  - ".env*"
  - "bin/env-update.sh"
  - "bin/env-scan.sh"
  - "bin/lib/env-update/**"
  - "bin/lib/env-scan/**"
  - "templates/tips/env-update.md"
  - "templates/tips/env-scan.md"
  - ".claude/skills/bump-versions/**"
  - "docker/config/dist/bin/**"
  - "docker/images/local.*/**"
---

# `.env` pins and LOCAL vars — what a pin bump needs, LOCAL ports

Split out of `CLAUDE.md` on 2026-11-07 to keep the always-loaded instruction files under the
150,000-char limit (`docs/plans/claude-md-size.plan.md`): the text below is unchanged, and
each entry keeps a one-line index entry in `CLAUDE.md`. A new lesson about these files belongs
HERE, not in `CLAUDE.md`.

## From CLAUDE.md § Common Workflows — after a pin bump

```bash
# If a pinned version changed, what it needs depends on WHO reads the pin:
# - a pin a startup script reads at boot — every runtime (node/php/python/ruby/java/flutter/
#   rust), package slot and runtime-installed tool (phpbrew/nvm/cargo tools, go/zig/mise,
#   phpmyadmin, caddy/httpd/nginx, libmodsecurity): nothing to do. On the next restart the
#   content-compare gate (gs_version_gate) sees marker != pin, WARNs and reinstalls. Every
#   gate is EQUALITY-based, so a pin moved DOWN reinstalls exactly like one moved up.
# - a pin a Dockerfile consumes — hurl (compiled by 00base; Ubuntu 26.04 has no
#   libxml2.so.2), and the Rust/rustup pins, which also feed 00base's hurl-build stage
#   (~6 min): only the image rebuild below applies it; a restart changes nothing.
# How a reinstall treats the old copy (docs/plans/pin-bump-reinstall-audit.plan.md):
# pyenv/rbenv move their git checkout to the pinned tag (a pin no definition matches FAILS
# and deletes nothing); nvm, phpbrew, sdkman, fvm, package slots and the rbenv plugins
# remove the old version only AFTER the new one installed; every downloaded tool (go, zig,
# mise, fvm, deno, bun, the 11 phpbrew tools, rustup-init, phpmyadmin, caddy's xcaddy) is
# fetched and checked in a temp dir with what its upstream allows — a published checksum or
# signature where there is one (for elasticmq and fvm it is the SHA-256 GitHub serves as the
# release asset's digest; phpMyAdmin commit builds and the zephir/phalcon/pickle phars have
# none), an archive listing, its own --version or
# manifest version where it can run — before its old copy is replaced, so a failed download
# or check leaves the old one working. The prefix-baked builds (httpd, nginx, libmodsecurity) fetch and check
# every input BEFORE their wipe (nginx's tarball against the nginx.org PGP keys committed
# next to its iou), then build at the prefix and check the result; a failed BUILD leaves no
# server and writes the error token. A RUST bump wipes and reinstalls the toolchain after
# rustup-init is checked. Two sites still wipe first: php.edge (phpbrew fetches the source
# itself; its php must run and report X.Y.Z-dev before any marker), and android, which wipes
# its SDK BEFORE the reinstall (ruling 2026-09-24 23:55; only GRADLE_USER_HOME is kept), so a
# failed android bump leaves no SDK. GLOBAL_STACK_RELOAD_<RUNTIME>=true forces a reinstall —
# see § Gotchas for the ones that do not wipe and for RELOAD_ANDROID keeping the Gradle cache.
```

## From CLAUDE.md § Gotchas & Pitfalls

- **LOCAL port range**: `GLOBAL_STACK_LOCAL_*_PORT_*` use host range **41700–41899** (200 slots). Standard `GLOBAL_STACK_*_PORT_*` use 42700–42899. Next free LOCAL slot: 41720 (41719 is taken — the `…_TWES_IN_PORT_41719=41719` line of `.env.local`).
- **LOCAL port var names for `local.05php8-5-...`**: the 7 port vars use SHORT form (`..._RUBY_N_RUST_N_PYTHON_N_JAVA_N_...`, no version suffixes), but `ALLTOGETHER_NAME` uses the LONG form with `05` prefix (`GLOBAL_STACK_LOCAL_05PHP8_5_N_NODE24_N_RUBY4_N_RUST_N_PYTHON3_N_JAVA27_N_ANDROID_N_FLUTTER3_41_9_ALLTOGETHER_NAME`). Pattern: env vars (short) vs healthcheck token (long).
