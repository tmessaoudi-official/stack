# CLAUDE.md

## Agent Delegation

**IMPORTANT**: For all development tasks in this project, you MUST immediately delegate to the `global-stack-lead-dev` agent (subagent_type: `global-stack-lead-dev`). This includes builds, fixes, refactors, architecture, feature work, and orchestration. The agent can further delegate to other tools and agents as needed. Do not do significant development work directly — always route through this agent.

---

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Global Stack is a dockerized local development environment that runs 60+ containerized services (databases, web servers, language runtimes, tooling) via Docker Compose. All services share a common Docker bridge network and mounted volumes for projects and tools.

## First-Time Setup

1. `cp .env .env.local` — then customize (choose services, set credentials)
2. Set `GLOBAL_STACK_DOCKER_USER_ID` in `.env.local` (defaults to `developer`) — used as password for all DBs, pgAdmin, Keycloak
3. Set `GLOBAL_STACK_DOCKER_USER_NAME` and `GLOBAL_STACK_DOCKER_USER_EMAIL` for git identity inside containers
4. Set `COMPOSE_FILE` in `.env.local` to select which services to run (always include `docker-compose.yaml` first)
5. Set `GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS` to list all virtual hostnames (space-separated)
6. Add those hostnames to `/etc/hosts`
7. Copy SSH keys to `docker/config/root/.ssh/` (see SSH Keys section)
8. `make create-paths && make up-build`

## Common Commands

All orchestration goes through Make. The `.env` file holds defaults; `.env.local` holds local overrides (gitignored).

```bash
make help                            # Setup guide and available targets
make up                              # Start the stack
make down                            # Stop the stack
make up-build                        # Start with rebuild
make up-build-force-recreate         # Start with rebuild + force-recreate containers
make down-n-rebuild-force-recreate   # Full teardown + rebuild + start
make down-n-rebuild                  # Teardown + rebuild + start (no force-recreate)
make down-n-up                       # Soft restart (down then up)
make hard-restart                    # DESTRUCTIVE: wipes all images, volumes, prunes entire Docker system
make rebuild                         # Rebuild from running state (alias for up-build)
make rebuild-force-recreate          # Rebuild + force-recreate from running state
make create-paths                    # Create required host directories
make generate-buildx                 # Generate docker buildx bake config
make create-buildx-builder           # Set up custom BuildKit builder
make start-local-registry            # Start local Docker registry with SSL
make login-<service>                 # Shell into a container (e.g. make login-03node24)
make log-<service>                   # Tail logs for a container
```

## Architecture

### Service Tiers

Services live in `docker/images/` and are numbered by tier:

| Tier | Purpose | Examples |
|------|---------|---------|
| `00*` | Base Ubuntu image + core tooling (Go, Rust, Zig, Docker-in-Docker, mkcert) | `00base` |
| `01*` | Infrastructure: databases, cache, web servers, mail, cloud sim | MySQL, Postgres, Redis, Nginx, Mailpit, LocalStack |
| `02*` | Language/version managers | NVM, PHPBrew, PyEnv, RbEnv, SDKMAN, FVM, Keycloak, SonarQube |
| `03*` | Pre-configured language runtimes (build on tier 02 managers) | Node 22/24, PHP 8.2–8.5, Python 3, Ruby 3/4, Java 11/17/25, Flutter |
| `04*` | Specialized tools | PhpMyAdmin, Android SDK, Serverless Framework |
| `05*` | Combined all-in-one images | `05stable`, `05edge` |
| `local.*` | Project-specific custom images | Per-project overrides |

Each service has its own `docker-compose.yaml`. They are composed together via the `COMPOSE_FILE` variable in `.env`.

### All-in-One Images (05stable / 05edge)

`05stable` and `05edge` are mega-images that combine all runtimes (Node, PHP, Python, Ruby, Java, Flutter, Android, Rust) into a single container. Use when you need multiple runtimes in one shell. `05stable` uses pinned versions; `05edge` tracks bleeding-edge versions. `local.*` images (e.g. `local.05php8-4-n-node22-n-ruby4-n-rust-n-python3-n-java25-n-android-n-flutter3-35-4`) are project-specific variants of this pattern.

### Key Dependency Chain

Higher-tier services depend on lower-tier ones:
- Language runtimes (`03*`) → version managers (`02*`) → base (`00base`)
- `00base` runs privileged (Docker-in-Docker support)

### Shared Volumes

All services mount:
- `./projects → /projects` — shared source code
- `./tools → /stack/tools` — shared executables (npm, composer, go, cargo, etc.)

### Networking

- Single Docker bridge network: `public` (subnet `172.18.0.0/16`)
- Services communicate by container name (e.g., `01postgres18`, `01redis`)
- 50+ virtual hosts declared in `GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS`
- Host port range: `42700–42811`

### Web Server Options

Three reverse proxy options are available — enable whichever via `COMPOSE_FILE`:
- `01httpd` — Apache
- `01nginx` — Nginx
- `01caddy` — Caddy

Virtual host configs go in each service's respective conf directory inside its image folder.

### Build System

`COMPOSE_BAKE=true` (default) uses Docker BuildX bake for all builds. `make generate-buildx` generates `docker-bake.local.json` and `docker-compose.full.local.yaml` — these are intermediate build artifacts (gitignored). If build behavior is unexpected, inspect these files. `make build` pushes images through buildx one target at a time.

### Configuration Pattern

```
.env            # Tracked defaults (versions, ports, credentials, COMPOSE_FILE list)
.env.local      # Gitignored local overrides
```

All image versions, database credentials, ports, and feature flags are controlled via env vars prefixed `GLOBAL_STACK_*`. Build-time ARGs pass these into Dockerfiles.

### Credentials Pattern

`GLOBAL_STACK_DOCKER_USER_ID` (default: `developer`) is the master credential — all database passwords, admin usernames, pgAdmin login, and Keycloak admin default to this value. Set it in `.env.local` before first start.

### Adding/Enabling a Service

1. Add its compose file path to `COMPOSE_FILE` in `.env.local`
2. Add its hostname to `GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS`
3. Add the hostname to host `/etc/hosts`
4. Place a virtual host config in the service's conf directory

### Local Overrides (gitignored)

Files named `local.Makefile`, `Makefile.local`, or `docker-compose.local.yaml` are gitignored and safe for personal customization without affecting git history. Add custom compose files to `COMPOSE_FILE` in `.env.local`.

### Local Images (gitignored)

`local.*` image directories under `docker/images/` are project-specific customizations and are **not tracked by git** (see `.gitignore`). They will not survive a fresh clone or machine rebuild.

**Important:** Back up your `local.*` image directories manually or store them in a separate private repository. Current known local images on this machine include `local.01postgres13`, `local.01postgres14`, `local.01postgres15`, `local.03flutter3-35-4`, `local.03node10`, and project-specific `local.05*` variants.

### Version Tracking

Image versions in `.env` are annotated with `# @todo check-updates <image> <registry-url> <current-version>` comments. When bumping a version, update both the `.env` variable and the matching `ARG` in the relevant Dockerfiles (grep for the old version string to find all occurrences).

### Stateful Data

Persistent data lives in `docker/data/<service>/`. Deleting a service's data directory and restarting is the universal fix for credential/corruption issues:
- `docker/data/mysql/<version>/`
- `docker/data/postgres/<version>/` (also `local.01postgres*/`)
- `docker/data/mongo/`
- `docker/storage/mailpit/` (mailpit uses `docker/storage/` not `docker/data/`)

### Database Credentials Issue

MySQL/MariaDB may reject credentials on first startup. Fix: stop stack, delete `docker/data/mysql/<version>/`, restart. Same pattern applies to other databases.

### SSH Keys

Place any SSH key files (named keys like `id_rsa`, `id_ed25519`, `id_work_ed25519`, etc.) and `known_hosts` in `docker/config/root/.ssh/` before starting — the entire directory is mounted into all containers. Multiple named key files are supported.

## Templates & Tips

`templates/` contains ready-to-use references:
- `templates/tips/` — 30+ markdown tip files for Docker, Ubuntu, git, SSL, Rust/WASM, and tooling tasks
- `templates/shell/` — shell script templates
- `templates/ghost-blog/` — Ghost blog setup template

## Projects

- `projects/prsnl/` — personal applications (PHP/Angular, Laravel, etc.)
- `projects/trngs/` — training/test projects
