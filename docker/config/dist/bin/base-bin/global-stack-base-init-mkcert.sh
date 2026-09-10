#!/bin/bash
set -euo pipefail

# Containers do NOT reach the local CA through the OS trust store. Every one of
# them gets SSL_CERT_FILE / CURL_CA_BUNDLE / NODE_EXTRA_CA_CERTS /
# REQUESTS_CA_BUNDLE pointed at the ${CAROOT}/rootCA-Bundle.pem built below, and
# `mkcert -install` reports "already installed" precisely because Go honours
# SSL_CERT_FILE -- it never touches /etc/ssl/certs at all. So a non-zero exit here
# is not fatal and must not abort the 31 containers that run this script.
#
# It is not nothing either. mkcert ALSO targets a JAVA truststore whenever it can
# see one, and a JVM reads none of the four variables above. 02sonarqube is the
# only container with JAVA_HOME + keytool visible, its $JAVA_HOME/lib/security/
# cacerts is root:root 644 while it runs as uid 1000, so mkcert shells out to sudo
# and gets "a password is required". Print mkcert's OWN output and say which store
# is left untrusting -- do not guess a cause. (This previously blamed a "busy
# ca-certificates.crt", which cannot single out the one container with a JDK, and
# hid mkcert's two ERROR lines under a reassuring WARNING.)
if ! _mkcert_output="$(mkcert -install 2>&1)"; then
  printf '%s\n' "${_mkcert_output}"
  printf 'WARNING: mkcert -install exited non-zero; the output above names the store it could not update.\n'
  printf '         Non-fatal for curl/node/python/Go, which trust the CA via SSL_CERT_FILE.\n'
  printf '         A JVM reads none of those, so it will reject local-CA certificates until its\n'
  printf '         own truststore is writable - continuing.\n'
else
  printf '%s\n' "${_mkcert_output}"
fi
if [[ ! -f "${CAROOT}/rootCA-Bundle.pem" ]]; then
  touch "${CAROOT}/rootCA-Bundle.pem"
  cat "${CAROOT}/rootCA-key.pem" >"${CAROOT}/rootCA-Bundle.pem"
  cat "${CAROOT}/rootCA.pem" >>"${CAROOT}/rootCA-Bundle.pem"
  cat /etc/ssl/certs/ca-certificates.crt >>"${CAROOT}/rootCA-Bundle.pem"
fi
