# Dockerfile ARG vs ENV

**What it solves**: Build arguments (`ARG`) that mysteriously disappear at runtime, or the confusion about when to use `ARG` vs `ENV` and how to make a build argument available inside a running container.

## The core distinction

| | `ARG` | `ENV` |
|---|---|---|
| **Available at** | Build time only | Build time AND runtime |
| **Visible after build** | No (gone after the build stage) | Yes (persists in the image) |
| **Override at build** | `--build-arg NAME=value` | Not directly — use ARG+ENV together |
| **Override at runtime** | Not possible (already gone) | `-e NAME=value` in `docker run` |
| **Appears in `docker history`** | Yes (values are logged) | Yes (values are logged) |

## The propagation pattern

To make a build argument available at runtime, declare both:

```dockerfile
ARG MY_VAR
ENV MY_VAR=${MY_VAR}
```

`ARG` receives the value at build time. `ENV` bakes it into the image layer so it's available when the container runs.

## Multi-ARG block (keeps Dockerfiles clean)

```dockerfile
ARG VAR_A
ARG VAR_B
ARG VAR_C

# Propagate all to runtime in one ENV declaration:
ENV VAR_A=${VAR_A} \
    VAR_B=${VAR_B} \
    VAR_C=${VAR_C}
```

Grouping `ENV` declarations reduces image layers compared to one `ENV` per variable.

## Default values

```dockerfile
# Default applies when --build-arg is not provided:
ARG APP_ENV=development

# Override at build time:
# docker build --build-arg APP_ENV=production .
```

If the `--build-arg` is not passed and no default is set, the `ARG` expands to an empty string (not an error) unless you add validation.

## ARG before FROM — global scope

An `ARG` declared before the first `FROM` is available in `FROM` lines and in ALL stages. `ARG` declared inside a stage is stage-scoped:

```dockerfile
ARG BASE_IMAGE=ubuntu:24.04   # available in all FROM lines

FROM ${BASE_IMAGE} AS builder
ARG BUILD_FLAGS               # scoped to builder stage only

FROM ${BASE_IMAGE} AS runtime
# BUILD_FLAGS is NOT available here
```

## Multi-stage builds: re-declare to pass between stages

Each stage starts fresh. To pass an `ARG` from one stage to another, re-declare it in the receiving stage:

```dockerfile
ARG VERSION=1.0.0

FROM ubuntu:24.04 AS builder
ARG VERSION           # re-declare to use in this stage
RUN echo "Building version $VERSION"

FROM ubuntu:24.04 AS runtime
ARG VERSION           # re-declare again to use in runtime stage
ENV APP_VERSION=${VERSION}
```

## Gotcha: empty string if ARG was never passed

If you declare `ENV FOO=${FOO}` but never declare `ARG FOO`, or declare the `ARG` but don't pass `--build-arg FOO=value`, `FOO` is an empty string at runtime. Use a default:

```dockerfile
ARG FOO=fallback-default
ENV FOO=${FOO}
```

Or validate at build time:
```dockerfile
ARG FOO
RUN test -n "$FOO" || (echo "ERROR: --build-arg FOO is required" && exit 1)
```

## Gotcha: ARG values appear in `docker history`

```bash
docker history --no-trunc my-image
```

Build arguments are visible in the history output. **Do not use `ARG` for secrets** (passwords, tokens, private keys). Use BuildKit secrets instead:

```dockerfile
# BuildKit secret — NOT visible in docker history:
RUN --mount=type=secret,id=my_token \
    MY_TOKEN="$(cat /run/secrets/my_token)" && \
    curl -H "Authorization: Bearer $MY_TOKEN" https://api.example.com/...
```

Build with:
```bash
docker build --secret id=my_token,src=./token.txt .
```

The secret is mounted as a tmpfs at `/run/secrets/my_token` for the duration of the `RUN` command only — it never becomes an image layer.
