awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do google-chrome --incognito "${link}"; done

awk '!seen[$0]++' .env | grep -oE '#(.*)@todo(.*)check-update(s)? (.*)http(s)?://[^ ]*' | grep -oE 'http(s)?://[^ ]*' | awk '!seen[$0]++' | while read -r link; do 
    google-chrome --incognito "${link}" &
    chrome_pid=$!
    wait $chrome_pid
done