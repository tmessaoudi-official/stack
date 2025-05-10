awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do google-chrome --incognito "${link}"; done

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    google-chrome --incognito "${link}" &
    chrome_pid=$!
    wait $chrome_pid
done

awk '!seen[$0]++' .env | \
grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | \
grep -oE 'http(s)?://[^ ]*' | \
grep -vE 'https://(pecl\.php\.net|pypi\.org|www\.npmjs\.com)' | \
awk '!seen[$0]++' | \
while read -r link; do 
    google-chrome --incognito "${link}" &
    chrome_pid=$!
    wait $chrome_pid
done

source /etc/profile.d/stack.sh
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

npm --global outdated

/stack/tools/pyenv/versions/3.13.3/bin/pip3.13 list --outdated

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://pecl.php.net[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    google-chrome --incognito "${link}" &
    chrome_pid=$!
    wait $chrome_pid
done