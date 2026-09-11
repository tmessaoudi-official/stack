# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION=4.0.1
ARG GLOBAL_STACK_IMAGE_UBUNTU_VERSION=resolute-20260901

# Timezone data source. This base image CANNOT install tzdata itself -- see the note on the
# COPY below -- so the zone files come from the same pinned Ubuntu that 00base builds on.
# Same FROM shape as 00base (DL3026 for docker.io bases is tolerated repo-wide, unpragma'd).
FROM ubuntu:${GLOBAL_STACK_IMAGE_UBUNTU_VERSION} AS tzdata_source
ENV DEBIAN_FRONTEND="noninteractive"
# apt packages are deliberately NOT pinned -- see .hadolint.yaml (DL3008 ignored).
RUN apt-get update \
    && apt-get install -y --no-install-recommends --fix-missing \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# shellcheck disable=SC2148
FROM mongoclient/mongoclient:${GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root


# Same symptom as 01epiclabs-docker-oracle-xe-11g -- TZ is declared in the compose file but
# the zone cannot be resolved, so the container runs UTC while printing the literal "Europe"
# as the zone name -- but it needs a DIFFERENT cure, because apt cannot fix it here:
#   1. This base is Debian 8 (jessie). Its apt is 1.0.9.8.6, which predates
#      --allow-releaseinfo-change (apt 1.5, 2017) and rejects it outright, exit 100.
#   2. Dropping that option is not enough: jessie is archived, so every source in the image's
#      sources.list 404s on deb.debian.org and `apt-get update` still exits 100.
#   3. Even reaching archive.debian.org would not help: the image was slimmed by deleting
#      /usr/share/zoneinfo WITHOUT telling dpkg, which still reports tzdata 2019c as
#      "install ok installed" and owning 1902 files. `apt-get install tzdata` is therefore a
#      SILENT no-op -- success, nothing installed -- and --reinstall cannot download.
# So the zone files are copied in from the pinned Ubuntu stage above instead. Verified: this
# image's glibc 2.19 reads the modern TZif files correctly (CEST in summer, CET in winter).
COPY --from=tzdata_source /usr/share/zoneinfo /usr/share/zoneinfo

RUN chown -R node:node /home/node/ \
    && find /home/node/ -type f -exec chmod 600 {} \; \
    && find /home/node/ -type d -exec chmod 700 {} \;

USER node