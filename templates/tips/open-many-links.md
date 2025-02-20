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

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://pecl.php.net[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    google-chrome --incognito "${link}" &
    chrome_pid=$!
    wait $chrome_pid
done