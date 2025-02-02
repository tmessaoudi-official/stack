#!/bin/bash

# Navigate to SSL directory
cd "${GLOBAL_STACK_SSL_PATH}"

rm -rf ${GLOBAL_STACK_SSL_PATH}/*

# Loop through exposed virtual hosts and generate SSL certificates
for vhost in ${GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS//[\"\']/}; do
    # Remove any existing certificates for the virtual host
    # rm -rf "${GLOBAL_STACK_SSL_PATH}/${vhost}.pem" "${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem" "${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem"
    
    # Generate new certificate using mkcert
    mkcert -cert-file ${GLOBAL_STACK_SSL_PATH}/${vhost}.pem -key-file ${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem -p12-file ${GLOBAL_STACK_SSL_PATH}/${vhost}-p12.pem ${vhost}

    touch ${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem
    cat "${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem" > ${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem
    cat "${GLOBAL_STACK_SSL_PATH}/${vhost}.pem" >> ${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem
done

# Remove existing certificates for localhost
# rm -rf "${GLOBAL_STACK_SSL_PATH}/localhost+"*

# Generate SSL certificates for localhost and common local IP addresses
mkcert -cert-file ${GLOBAL_STACK_SSL_PATH}/localhost.pem -key-file ${GLOBAL_STACK_SSL_PATH}/localhost-key.pem -p12-file ${GLOBAL_STACK_SSL_PATH}/localhost-p12.pem localhost 127.0.0.1 ::1
touch ${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/localhost-key.pem" > ${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/localhost.pem" >> ${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem

caddy_server_ip=$(global-stack-base-get-container-ip.sh 01caddy)
if [[ "" != ${caddy_server_ip} ]]; then
    if [[ "" != ${GLOBAL_STACK_HTTPS_LOCALHOST_IPS} ]]; then
        GLOBAL_STACK_HTTPS_LOCALHOST_IPS+=" ${caddy_server_ip}"
    else
        GLOBAL_STACK_HTTPS_LOCALHOST_IPS=${caddy_server_ip}
    fi
fi

mkcert -cert-file ${GLOBAL_STACK_SSL_PATH}/localhost+ips.pem -key-file ${GLOBAL_STACK_SSL_PATH}/localhost+ips-key.pem -p12-file ${GLOBAL_STACK_SSL_PATH}/localhost+ips-p12.pem localhost 127.0.0.1 ::1 ${GLOBAL_STACK_HTTPS_LOCALHOST_IPS}
touch ${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/localhost+ips-key.pem" > ${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/localhost+ips.pem" >> ${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem

mkcert -cert-file ${GLOBAL_STACK_SSL_PATH}/all.pem -key-file ${GLOBAL_STACK_SSL_PATH}/all-key.pem -p12-file ${GLOBAL_STACK_SSL_PATH}/all-p12.pem localhost 127.0.0.1 ::1 ${GLOBAL_STACK_HTTPS_LOCALHOST_IPS} ${GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS}
touch ${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/all-key.pem" > ${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem
cat "${GLOBAL_STACK_SSL_PATH}/all.pem" >> ${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem