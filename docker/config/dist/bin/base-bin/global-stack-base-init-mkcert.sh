#!/bin/bash
set -euo pipefail

mkcert -install 2>&1 || echo "WARNING: mkcert -install returned non-zero (update-ca-certificates may have failed due to busy ca-certificates.crt) - continuing"
if [[ ! -f "${CAROOT}/rootCA-Bundle.pem" ]]; then
    touch "${CAROOT}/rootCA-Bundle.pem"
    cat "${CAROOT}/rootCA-key.pem" > "${CAROOT}/rootCA-Bundle.pem"
    cat "${CAROOT}/rootCA.pem" >> "${CAROOT}/rootCA-Bundle.pem"
    cat /etc/ssl/certs/ca-certificates.crt >> "${CAROOT}/rootCA-Bundle.pem"
fi