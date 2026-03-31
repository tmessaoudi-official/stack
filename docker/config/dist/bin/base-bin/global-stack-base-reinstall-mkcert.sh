#!/bin/bash
set -euo pipefail

# Navigate to SSL directory
cd "${GLOBAL_STACK_SSL_PATH}"

rm -rf "${GLOBAL_STACK_SSL_PATH:?}/"*

# Loop through exposed virtual hosts and generate SSL certificates
# shellcheck disable=SC2086 # word-splitting intentional: GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS is space-separated
for vhost in ${GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS//[\"\']/}; do
    # Remove any existing certificates for the virtual host
    # rm -rf "${GLOBAL_STACK_SSL_PATH}/${vhost}.pem" "${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem" "${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem"

    # Generate new certificate using mkcert
    mkcert -cert-file "${GLOBAL_STACK_SSL_PATH}/${vhost}.pem" -key-file "${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem" -p12-file "${GLOBAL_STACK_SSL_PATH}/${vhost}-p12.pem" "${vhost}"

    touch "${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem"
    cat "${GLOBAL_STACK_SSL_PATH}/${vhost}-key.pem" > "${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem"
    cat "${GLOBAL_STACK_SSL_PATH}/${vhost}.pem" >> "${GLOBAL_STACK_SSL_PATH}/${vhost}-Bundle.pem"
done

# Remove existing certificates for localhost
# rm -rf "${GLOBAL_STACK_SSL_PATH}/localhost+"*

# Generate SSL certificates for localhost and common local IP addresses
mkcert -cert-file "${GLOBAL_STACK_SSL_PATH}/localhost.pem" -key-file "${GLOBAL_STACK_SSL_PATH}/localhost-key.pem" -p12-file "${GLOBAL_STACK_SSL_PATH}/localhost-p12.pem" localhost 127.0.0.1 ::1
touch "${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/localhost-key.pem" > "${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/localhost.pem" >> "${GLOBAL_STACK_SSL_PATH}/localhost-Bundle.pem"

# shellcheck disable=SC2086 # word-splitting intentional: GLOBAL_STACK_HTTPS_CONTAINER_IPS is space-separated
for container_host in ${GLOBAL_STACK_HTTPS_CONTAINER_IPS//[\"\']/}; do
    container_server_ip=$(global-stack-base-get-container-ip.sh "${container_host}")
    if [[ "" != "${container_server_ip}" ]]; then
        if [[ "" != "${GLOBAL_STACK_HTTPS_LOCALHOST_IPS}" ]]; then
            GLOBAL_STACK_HTTPS_LOCALHOST_IPS+=" ${container_host} ${container_server_ip}"
        else
            GLOBAL_STACK_HTTPS_LOCALHOST_IPS="${container_host} ${container_server_ip}"
        fi
    fi

    # Generate new certificate using mkcert
    mkcert -cert-file "${GLOBAL_STACK_SSL_PATH}/${container_host}.pem" -key-file "${GLOBAL_STACK_SSL_PATH}/${container_host}-key.pem" -p12-file "${GLOBAL_STACK_SSL_PATH}/${container_host}-p12.pem" "${container_host}"

    touch "${GLOBAL_STACK_SSL_PATH}/${container_host}-Bundle.pem"
    cat "${GLOBAL_STACK_SSL_PATH}/${container_host}-key.pem" > "${GLOBAL_STACK_SSL_PATH}/${container_host}-Bundle.pem"
    cat "${GLOBAL_STACK_SSL_PATH}/${container_host}.pem" >> "${GLOBAL_STACK_SSL_PATH}/${container_host}-Bundle.pem"
done

# shellcheck disable=SC2086 # word-splitting intentional: GLOBAL_STACK_HTTPS_LOCALHOST_IPS and GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS are space-separated
mkcert -cert-file "${GLOBAL_STACK_SSL_PATH}/localhost+ips.pem" -key-file "${GLOBAL_STACK_SSL_PATH}/localhost+ips-key.pem" -p12-file "${GLOBAL_STACK_SSL_PATH}/localhost+ips-p12.pem" localhost 127.0.0.1 ::1 ${GLOBAL_STACK_HTTPS_LOCALHOST_IPS}
touch "${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/localhost+ips-key.pem" > "${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/localhost+ips.pem" >> "${GLOBAL_STACK_SSL_PATH}/localhost+ips-Bundle.pem"

# shellcheck disable=SC2086 # word-splitting intentional: GLOBAL_STACK_HTTPS_LOCALHOST_IPS and GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS are space-separated
mkcert -cert-file "${GLOBAL_STACK_SSL_PATH}/all.pem" -key-file "${GLOBAL_STACK_SSL_PATH}/all-key.pem" -p12-file "${GLOBAL_STACK_SSL_PATH}/all-p12.pem" localhost 127.0.0.1 ::1 ${GLOBAL_STACK_HTTPS_LOCALHOST_IPS} ${GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS}
touch "${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/all-key.pem" > "${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem"
cat "${GLOBAL_STACK_SSL_PATH}/all.pem" >> "${GLOBAL_STACK_SSL_PATH}/all-Bundle.pem"