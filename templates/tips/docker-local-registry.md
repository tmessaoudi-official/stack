Local Docker registry — first setup, recovery and rotation
==========================================================

Every stack image is tagged with the local registry
(GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS:GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000,
values from .env.local). It serves TLS with a self-signed certificate that the
Makefile mints and installs; no "insecure-registries" entry is needed in
/etc/docker/daemon.json (the trust is /etc/docker/certs.d/<alias>:<port>/ca.crt
plus the system CA store, both written by `make start-local-registry`).

1. /etc/hosts — the only manual step

   Add this line (replace the name with GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS
   from .env.local, e.g. local-global-stack-registry.local):

   127.0.0.1 GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS

   Check: getent hosts <alias>   (must print 127.0.0.1 <alias>)
   `make start-local-registry` refuses to start without it, and
   `make ensure-local-registry` reports "cannot resolve" (curl exit 6).

2. First setup, or a new certificate (rotation)

   make start-local-registry create-buildx-builder

   ALWAYS both, in that order. start-local-registry makes a new certificate,
   installs it (root) and RESTARTS THE DOCKER DAEMON, which stops every
   container on the machine. create-buildx-builder rebuilds the buildx builder,
   whose image copies the certificate in: without it the builder keeps trusting
   the old one and every push fails.

3. Every other time — nothing to do

   `make up`, `make build` and every down-n-* target (global-stack-start.sh,
   global-stack-up.sh) run `make ensure-local-registry` first. It starts a
   stopped registry, creates a missing one from the certificate already on
   disk, waits for https://<alias>:<port>/v2/, and never makes a new
   certificate. When it cannot heal the registry it fails BEFORE anything is
   torn down and says which of the steps above to run. Run it by hand any time:

   make ensure-local-registry

docker/registry/config.json is tracked in the repo; do not create it by hand.
