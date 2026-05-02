# /stack File Layout Quick Reference

```
.env                                 # Master config (tracked)
.env.local                           # Active machine config (gitignored)
Makefile                             # Primary build automation
local.Makefile                       # Machine-specific Makefile extensions
bin/env-update.sh                    # Version checker entry point (all 12 fetcher types)
bin/env-scan.sh                      # Env sync tool entry point
bin/lib/env-update/                  # Modular env-update library
  config/   prerelease_markers, type_map
  core/     apply, args, cache, channel, decide, parse, records, semver, tag_flags, ubuntu
  fetchers/ codeberg, dockerhub, github, npm, pecl, pecl_git, pypi, quay, rubygems, sdkman, sdkmanager, url
bin/lib/env-scan/                    # Modular env-scan library
bin/tests/env-scan.test.sh           # Test suite (custom harness)
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
var/                                 # Backups, CA certs, hosts (gitignored)
projects/                            # Project source code (gitignored)
templates/ghost-blog/                # Template for adding a new service
templates/tips/                      # markdown cheat sheets
templates/shell/                     # Host system shell config templates
```
