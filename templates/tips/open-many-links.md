awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}"; done

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}" &
    navigator_pid=$!
    wait $navigator_pid
done

source /etc/profile.d/stack.sh

nvm use 22
npm --global outdated
nvm use 24
npm --global outdated
nvm use 26
npm --global outdated
/stack/tools/pyenv/versions/${GLOBAL_STACK_PYTHON3_VERSION}/bin/pip${GLOBAL_STACK_PYTHON3_VERSION%.*} list --outdated
sdkmanager --sdk_root="${ANDROID_HOME}" --list

sdk offline disable
sdk list ant
sdk list gradle
sdk list kotlin
sdk list maven
sdk list pomchecker
sdk list springboot
sdk list tomcat
sdk list groovy
sdk list micronaut
sdk list quarkus
sdk list spark
sdk list java

awk '!seen[$0]++' .env | grep -oE '(#(.*)@todo(.*)check-update(s)? (.*)http(s)?://pecl.php.net[^ ]*|# @todo could be a repo url https://[^ ]* branch or commit [^ ]*)' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}" &
    navigator_pid=$!
    wait $navigator_pid
done

awk '!seen[$0]++' .env | \
grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | \
grep -oE 'http(s)?://[^ ]*' | \
grep -vE 'https://(pecl\.php\.net|pypi\.org|www\.npmjs\.com)' | \
awk '!seen[$0]++' | \
while read -r link; do 
    ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}" &
    navigator_pid=$!
    wait $navigator_pid
done