#!/bin/bash

mkcert -install
if [[ ! -f ${CAROOT}/rootCA-Bundle.pem ]]; then
    touch ${CAROOT}/rootCA-Bundle.pem
    cat ${CAROOT}/rootCA-key.pem > ${CAROOT}/rootCA-Bundle.pem
    cat ${CAROOT}/rootCA.pem >> ${CAROOT}/rootCA-Bundle.pem
fi