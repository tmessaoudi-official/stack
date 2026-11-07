Local Docker registry — first setup, recovery and rotation
==========================================================

Most stack images build FROM the local registry
(GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS:GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000,
values from .env.local), and many are pushed to and tagged with it. It serves
TLS with a self-signed certificate that the Makefile mints and installs; no
"insecure-registries" entry is needed in /etc/docker/daemon.json (the trust is
/etc/docker/certs.d/<alias>:<port>/ca.crt plus the system CA store, both
written by `make start-local-registry`).

0. .env.local first

   Every value below comes from .env.local. On a fresh clone create it first:
   cp .env .env.local, then bin/env-scan.sh. Without it, the targets below
   stop with "GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS is empty" or
   "... is not set".

1. /etc/hosts — the only system file to edit by hand

   Add this line (replace the name with GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS
   from .env.local, e.g. local-global-stack-registry.local):

   127.0.0.1 GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS

   Check: getent hosts <alias>   (must print 127.0.0.1 <alias>)
   `make start-local-registry` refuses to start without it, and
   `make ensure-local-registry` reports "cannot resolve" (curl exit 6).

2. First setup, or a new certificate (rotation)

   make start-local-registry create-buildx-builder

   ALWAYS both, in that order. Both need root and both restart the Docker
   daemon, which stops every container on the machine (twice in all).
   - start-local-registry makes a new certificate (valid 365 days) and
     installs it.
   - create-buildx-builder rebuilds the buildx builder, whose image copies the
     certificate in. It also deletes the builder's state volume, so the build
     cache is gone and the next build starts cold. Without it the builder
     keeps trusting the old certificate and every push fails.

   When: on first setup, and before the certificate expires. `make build`
   prints a WARNING 30 days ahead; nothing else notices, because the registry
   probes use curl -k. After expiry, pulls and pushes fail with x509 errors.

3. Every other time — nothing to do

   `make up`, `make build`, soft-restart and every down-n-* target
   (global-stack-start.sh, global-stack-up.sh) run `make ensure-local-registry`
   first. It starts a stopped registry, creates a missing one from the
   certificate already on disk, waits for https://<alias>:<port>/v2/, and never
   makes a new certificate. When it cannot heal the registry, it fails BEFORE
   anything is torn down and says what to do. Run it by hand any time:

   make ensure-local-registry

4. A registry that is dead or never answers

   Re-create it from the existing certificate. This needs no root and no daemon
   restart, and the data is kept:

   docker rm -f <GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME> && make ensure-local-registry

   Only if it still does not answer (for example a certificate/key mismatch
   after an interrupted rotation), rotate as in step 2.

docker/registry/config.json is tracked in the repo; do not create it by hand.
