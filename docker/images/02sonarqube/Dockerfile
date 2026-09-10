# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local
ARG GLOBAL_STACK_SONARQUBE_VERSION=2026.4.1-developer

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION} AS local_global_stack_base
FROM sonarqube:${GLOBAL_STACK_SONARQUBE_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root

# apt packages are deliberately NOT pinned — see .hadolint.yaml (DL3008 ignored:
# development environment, intentionally tracks latest). Ruling 2026-09-04, row 26.
RUN apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    libnss3-tools \
    sudo \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /etc/apt/apt.conf.d/docker-clean

ARG GLOBAL_STACK_DOCKER_USER_ID

RUN mkdir -p /opt/sonarqube/sonar-scanner-cli/

COPY --from=local_global_stack_base \
    /usr/local/bin/mkcert \
    /usr/local/bin/

COPY \
    docker/images/00base/conf/bin/ \
    docker/config/dist/bin/base-bin/ \
    docker/config/dist/bin/sonarqube-bin/ \
    /usr/local/bin/

COPY --from=local_global_stack_base /opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/ /opt/sonarqube/sonar-scanner-cli/

RUN find /usr/local/bin/ -type f -exec chmod a+x {} \;

RUN chown -R sonarqube:root /opt/sonarqube/sonar-scanner-cli/ \
    && chmod -R a+rwx /opt/sonarqube/sonar-scanner-cli/

# This is the ONE container where mkcert can see a JDK, so it is the one where
# `mkcert -install` also tries the Java truststore. cacerts ships root:root 644
# and sonarqube runs as uid 1000 gid 0, so mkcert fell back to sudo and got
# "a password is required" -- leaving the JVM unable to validate any local-CA
# certificate, while curl/node/python trusted it fine via ${SSL_CERT_FILE},
# which no JVM reads. Group-write is enough (the user's primary group IS root
# here, same reason the chown above targets sonarqube:root) and keeps mkcert's
# own native mechanism working instead of bolting on a second truststore.
RUN chmod g+w "${JAVA_HOME}/lib/security/cacerts"

ENV PATH="/opt/sonarqube/sonar-scanner-cli/bin:${PATH}"

USER sonarqube

CMD ["global-stack-start-sonarqube.sh"]