awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}"; done

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR:-firefox} ${GLOBAL_STACK_CHECK_UPDATE_NAVIGATOR_PRIVATE_ARG:---private-window} "${link}" &
    navigator_pid=$!
    wait $navigator_pid
done

look for noble|oracular|plucky|questing and try to replace them with resolute (look is there is a release)

source /etc/profile.d/stack.sh

nvm use ${GLOBAL_STACK_NODE22_VERSION}
npm --global outdated
nvm use ${GLOBAL_STACK_NODE24_VERSION}
npm --global outdated
nvm use ${GLOBAL_STACK_NODEEDGE_VERSION}
npm --global outdated
GLOBA_STACK_CURRENT_DIRECTORY=$(pwd)
cd /stack/tools/serverless-framework
npm outdated
cd "${GLOBA_STACK_CURRENT_DIRECTORY}"
/stack/tools/pyenv/versions/${GLOBAL_STACK_PYTHON3_VERSION}/bin/pip${GLOBAL_STACK_PYTHON3_VERSION%.*} list --outdated
sdkmanager --sdk_root="${ANDROID_HOME}" --list
sdk offline disable
echo "ant"
sdk list ant | grep ""
echo "gradle"
sdk list gradle | grep ""
echo "kotlin"
sdk list kotlin | grep ""
echo "maven"
sdk list maven | grep ""
echo "pomchecker"
sdk list pomchecker | grep ""
echo "springboot"
sdk list springboot | grep ""
echo "tomcat"
sdk list tomcat | grep ""
echo "groovy"
sdk list groovy | grep ""
echo "micronaut"
sdk list micronaut | grep ""
echo "quarkus"
sdk list quarkus | grep ""
echo "spark"
sdk list spark | grep ""
echo "java"
sdk list java | grep ""

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