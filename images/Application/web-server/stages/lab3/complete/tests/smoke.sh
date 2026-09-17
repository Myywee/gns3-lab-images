#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
vulnerable_context=$(dirname "$context_dir")/vulnerable
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab3-web-complete-smoke}
lab1_image=${LAB1_IMAGE_TAG:-gns3-lab/web-server:lab1-complete-lab3-final-smoke}
no_https_image=${NO_HTTPS_IMAGE_TAG:-gns3-lab/web-server:lab2-no-https-lab3-final-smoke}
lab2_image=${LAB2_IMAGE_TAG:-gns3-lab/web-server:lab2-complete-lab3-final-smoke}
vulnerable_image=${VULNERABLE_IMAGE_TAG:-gns3-lab/web-server:lab3-vulnerable-final-smoke}
image=${IMAGE_TAG:-gns3-lab/web-server:lab3-complete-smoke}
certificate_dir=$(mktemp -d /tmp/gns3-lab3-complete-certificates.XXXXXX)
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force --volumes "$container" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$certificate_dir"
}
trap cleanup EXIT HUP INT TERM

if [ "${SKIP_VULNERABLE_BUILD:-0}" != 1 ]; then
    if [ "${SKIP_LAB2_BUILD:-0}" != 1 ]; then
        if [ "${SKIP_NO_HTTPS_BUILD:-0}" != 1 ]; then
            if [ "${SKIP_LAB1_BUILD:-0}" != 1 ]; then
                if [ "${SKIP_TOOLBOX_BUILD:-0}" != 1 ]; then
                    test -f "$repo_root/images/toolbox/Dockerfile"
                    docker build --pull=false --tag "$toolbox_image" "$repo_root/images/toolbox"
                fi
                docker build --pull=false \
                    --build-arg "BASE_IMAGE=$toolbox_image" \
                    --tag "$lab1_image" \
                    "$repo_root/images/Application/web-server/stages/lab1/complete"
            fi
            docker build --pull=false \
                --build-arg "BASE_IMAGE=$lab1_image" \
                --tag "$no_https_image" \
                "$repo_root/images/Application/web-server/stages/lab2/no-https"
        fi
        docker build --pull=false \
            --build-arg "BASE_IMAGE=$no_https_image" \
            --tag "$lab2_image" \
            "$repo_root/images/Application/web-server/stages/lab2/complete"
    fi
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab2_image" \
        --tag "$vulnerable_image" \
        "$vulnerable_context"
fi

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$vulnerable_image" \
        --tag "$image" \
        "$context_dir"
fi

certificate=$certificate_dir/networking-experiments.nju-slab.cn.fullchain.pem
private_key=$certificate_dir/networking-experiments.nju-slab.cn.key
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=networking-experiments.nju-slab.cn' \
    -addext 'subjectAltName=DNS:networking-experiments.nju-slab.cn,DNS:networking-experiments-2.nju-slab.cn' \
    -keyout "$private_key" \
    -out "$certificate" >/dev/null 2>&1
chmod 0644 "$certificate"
chmod 0600 "$private_key"

docker run --rm --entrypoint sh "$image" -ec '
    python3 -m py_compile /opt/exp3/vuln-app/app.py
    grep -F "SESSION_COOKIE_HTTPONLY=True" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "SESSION_COOKIE_SAMESITE=\"Lax\"" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "secrets.compare_digest" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "{{ message }}" /opt/exp3/vuln-app/app.py >/dev/null
    if grep -F "{{ message|safe }}" /opt/exp3/vuln-app/app.py >/dev/null; then
        echo "Complete image still disables Jinja escaping" >&2
        exit 1
    fi
'

docker image inspect --format '{{json .Config.Cmd}}' "$image" \
    | grep -F '["/bin/bash"]' >/dev/null

container=$(docker run --detach \
    --mount "type=bind,src=$certificate_dir,dst=/etc/nginx/certs,readonly" \
    "$image" tail -f /dev/null)

docker exec "$container" /opt/exp3/start-exp3.sh \
    | grep -F 'exp3 started' >/dev/null

attempt=0
until docker exec "$container" curl -fsS --noproxy '*' \
    http://127.0.0.1:5000/healthz \
    | grep -F '"mode":"complete"' >/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        docker logs "$container" >&2 || true
        echo 'Lab 3 complete web server did not become ready' >&2
        exit 1
    fi
    sleep 0.25
done

victim=networking-experiments.nju-slab.cn
attacker=networking-experiments-2.nju-slab.cn
curl_victim() {
    docker exec "$container" curl --noproxy '*' \
        --cacert "/etc/nginx/certs/$(basename "$certificate")" \
        --resolve "$victim:443:127.0.0.1" "$@"
}
curl_attacker() {
    docker exec "$container" curl --noproxy '*' \
        --cacert "/etc/nginx/certs/$(basename "$certificate")" \
        --resolve "$attacker:443:127.0.0.1" "$@"
}

curl_attacker -fsS "https://$attacker/" | grep -F 'id="csrf-form"' >/dev/null

search_response=$(curl_victim -fsSG \
    --data-urlencode 'q=<script>alert(1)</script>' \
    "https://$victim/search")
printf '%s\n' "$search_response" | grep -F '&lt;script&gt;alert(1)&lt;/script&gt;' >/dev/null
if printf '%s\n' "$search_response" | grep -F '<script>alert(1)</script>' >/dev/null; then
    echo 'Complete image reflects an unescaped script' >&2
    exit 1
fi

curl_victim -sS -o /dev/null \
    --data-urlencode 'message=<script>alert(2)</script>' \
    "https://$victim/guestbook"
home_response=$(curl_victim -fsS "https://$victim/")
printf '%s\n' "$home_response" | grep -F '&lt;script&gt;alert(2)&lt;/script&gt;' >/dev/null
if printf '%s\n' "$home_response" | grep -F '<script>alert(2)</script>' >/dev/null; then
    echo 'Complete image renders an unescaped stored script' >&2
    exit 1
fi

curl_victim -sS \
    -D /tmp/lab3-login.headers \
    -c /tmp/lab3-cookies.txt \
    -o /dev/null \
    -d 'username=admin&password=admin123' \
    "https://$victim/login"
docker exec "$container" grep -i '^Set-Cookie:' /tmp/lab3-login.headers \
    | grep -F 'Secure' \
    | grep -i -F 'HttpOnly' \
    | grep -F 'SameSite=Lax' >/dev/null

curl_victim -fsS \
    -b /tmp/lab3-cookies.txt \
    -o /tmp/lab3-profile.html \
    "https://$victim/profile"
csrf_token=$(docker exec "$container" sed -n \
    's/.*name="csrf_token" value="\([a-f0-9]*\)".*/\1/p' \
    /tmp/lab3-profile.html | head -n 1)
test "${#csrf_token}" -eq 64

without_token_status=$(curl_victim -sS \
    -b /tmp/lab3-cookies.txt \
    -H "Origin: https://$attacker" \
    -H "Referer: https://$attacker/" \
    -o /tmp/lab3-without-token.txt \
    -w '%{http_code}' \
    --data 'new_password=bad' \
    "https://$victim/change-password")
test "$without_token_status" = 403
docker exec "$container" grep -F 'CSRF token mismatch' \
    /tmp/lab3-without-token.txt >/dev/null

wrong_token_status=$(curl_victim -sS \
    -b /tmp/lab3-cookies.txt \
    -o /tmp/lab3-wrong-token.txt \
    -w '%{http_code}' \
    --data 'new_password=wrong&csrf_token=invalid-token' \
    "https://$victim/change-password")
test "$wrong_token_status" = 403

with_token_status=$(curl_victim -sS \
    -b /tmp/lab3-cookies.txt \
    -c /tmp/lab3-cookies.txt \
    -H "Origin: https://$victim" \
    -H "Referer: https://$victim/profile" \
    -o /tmp/lab3-with-token.txt \
    -w '%{http_code}' \
    --data-urlencode 'new_password=good' \
    --data-urlencode "csrf_token=$csrf_token" \
    "https://$victim/change-password")
test "$with_token_status" = 200
docker exec "$container" grep -F 'Password changed successfully!' \
    /tmp/lab3-with-token.txt >/dev/null

curl_victim -fsS \
    -b /tmp/lab3-cookies.txt \
    -o /tmp/lab3-profile-new.html \
    "https://$victim/profile"
new_csrf_token=$(docker exec "$container" sed -n \
    's/.*name="csrf_token" value="\([a-f0-9]*\)".*/\1/p' \
    /tmp/lab3-profile-new.html | head -n 1)
test "${#new_csrf_token}" -eq 64
test "$new_csrf_token" != "$csrf_token"

replay_status=$(curl_victim -sS \
    -b /tmp/lab3-cookies.txt \
    -o /tmp/lab3-replay-token.txt \
    -w '%{http_code}' \
    --data-urlencode 'new_password=reused' \
    --data-urlencode "csrf_token=$csrf_token" \
    "https://$victim/change-password")
test "$replay_status" = 403

docker exec "$container" sh -ec '
    nginx -t
    ss -lnt | grep -E "127\.0\.0\.1:5000[[:space:]]" >/dev/null
    ss -lnt | grep -E "[.:]80[[:space:]]" >/dev/null
    ss -lnt | grep -E "[.:]443[[:space:]]" >/dev/null
'

printf '%s\n' "PASS: $image"
