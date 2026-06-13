# /stack File Layout Quick Reference

```
.env                                 # Master config (tracked)
.env.local                           # Active machine config (gitignored)
Makefile                             # Primary build automation
local.Makefile                       # Machine-specific Makefile extensions
bin/env-update.sh                    # Version checker entry point (all 12 fetcher types)
bin/env-scan.sh                      # Env sync tool entry point
bin/lib/env-update/                  # Modular env-update library
  config/   defaults, prerelease_markers
  core/     apply, args, cache, channel, decide, drift, git, parallel, parse, passes, records, semver, tag_flags, ubuntu
  reporting/ dump, help, profile, reference, summary, tally
  fetchers/ codeberg, dockerhub, ghcr, github, npm, pecl, pypi, quay, rubygems, sdkman, sdkmanager, url
bin/lib/env-scan/                    # Modular env-scan library
bin/tests/env-scan.test.sh           # Test suite (custom harness)
bin/tests/env-update.test.sh         # Test suite (749+ tests, 112 sections)
bin/tests/startup-prologue.test.sh   # Test suite for base-prologue.sh + GS_STARTUP_DRY_RUN seam
docker/images/<tier><name>/          # Per-image Dockerfile + docker-compose.yaml
docker/config/dist/bin/              # Container startup scripts
docker/config/dist/conf/             # Per-service runtime configs
docker/config/root/                  # Root home (SSH keys, etc.) — bind-mounted
docker/registry/                     # Local TLS Docker registry config
docker/buildkit/                     # Custom BuildKit image with local CA
tools/                               # Shared volume (gitignored — lives on host)
  successes/ errors/ locks/ elapsed/ # Health/coordination markers
  versions/                          # Installed version markers (skip reinstall)
  .shellrc/                          # Runtime env exports (host sources these)
  bin/                               # Shared executables (mkcert, etc.)
var/                                 # Static assets + backups (gitignored)
  tools/                           #   Seed copy restored by `make soft-restart` (DESTRUCTIVE)
  images/                          #   Docker image tarballs written by `make save`, loaded by `make load`
projects/                            # Project source code (gitignored)
templates/ghost-blog/                # Template for adding a new service
templates/tips/                      # markdown cheat sheets
templates/shell/                     # Host system shell config templates
```

> Per-service `docker-compose.yaml` files use `extends:` to pull in shared `environment:` blocks from `docker/config/compose-fragments/` (base-env, node-packages, php-packages, etc.). Services without a matching fragment still repeat their `environment:` block directly — Docker Compose v3 dropped cross-file YAML anchors, so direct repetition is intentional for those services.
