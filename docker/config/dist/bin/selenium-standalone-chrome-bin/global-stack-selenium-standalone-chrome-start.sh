#!/bin/bash

SECONDS=0

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

global-stack-base-init-mkcert.sh 

# sudo sed -i 's/\-\-no\-sandbox/\-\-no\-sandbox \-\-ignore\-certificate-errors/' /opt/bin/wrap_chrome_binary
# sudo sed -i 's/\-\-no\-sandbox/\-\-no\-sandbox \-\-ignore\-certificate-errors/' /opt/google/chrome/google-chrome
# sudo sed -i "s@\"applicationName\"\: \"${NODE_APPLICATION_NAME}\"@\"applicationName\"\: \"${NODE_APPLICATION_NAME}\"\,\n      \"chromeOptions\"\: \{\"args\"\: \[\"\-\-ignore\-certificate-errors\"\]\}@" /opt/selenium/config.json

# mkdir -p /home/seluser/.pki/nssdb
# certutil -d sql:/home/seluser/.pki/nssdb -A -t "PcTCuwg,PcTCuwg,PcTCuwg" -n 'mkcert development CA' -i "${CAROOT}"/rootCA.pem

/opt/bin/entry_point.sh