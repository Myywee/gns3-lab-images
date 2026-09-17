#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab3-web-vulnerable-smoke}
lab1_image=${LAB1_IMAGE_TAG:-gns3-lab/web-server:lab1-complete-lab3-smoke}
no_https_image=${NO_HTTPS_IMAGE_TAG:-gns3-lab/web-server:lab2-no-https-lab3-smoke}
lab2_image=${LAB2_IMAGE_TAG:-gns3-lab/web-server:lab2-complete-lab3-smoke}
image=${IMAGE_TAG:-gns3-lab/web-server:lab3-vulnerable-smoke}
certificate_dir=$(mktemp -d /tmp/gns3-lab3-vulnerable-certificates.XXXXXX)
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force --volumes "$container" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$certificate_dir"
}
trap cleanup EXIT HUP INT TERM

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

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab2_image" \
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
    test -L /etc/nginx/conf.d/exp3.conf
    test ! -e /etc/nginx/conf.d/portal.conf
    test -r /opt/exp3/evil-site/index.html
    test -r /opt/exp3/vuln-app/app.py
    test -r /opt/gns3-labs/lab2-active-backup/portal.conf
    python3 -m py_compile /opt/exp3/vuln-app/app.py
    grep -F "SESSION_COOKIE_HTTPONLY=False" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "SESSION_COOKIE_SAMESITE=\"None\"" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "{{ message|safe }}" /opt/exp3/vuln-app/app.py >/dev/null
    grep -F "document.getElementById(\"csrf-form\").submit()" \
        /opt/exp3/evil-site/index.html >/dev/null
    test ! -e /usr/local/lib/gns3/start-web-server.sh
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
    | grep -F '"mode":"vulnerable"' >/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        docker logs "$container" >&2 || true
        echo 'Lab 3 vulnerable web server did not become ready' >&2
        exit 1
    fi
    sleep 0.25
done

for host in networking-experiments.nju-slab.cn networking-experiments-2.nju-slab.cn; do
    docker exec "$container" curl -sSI --noproxy '*' -H "Host: $host" \
        http://127.0.0.1/ \
        | tr -d '\r' \
        | grep -F 'HTTP/1.1 301 Moved Permanently' >/dev/null
    docker exec "$container" curl -sSI --noproxy '*' -H "Host: $host" \
        http://127.0.0.1/ \
        | tr -d '\r' \
        | grep -i -F "Location: https://$host/" >/dev/null
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

curl_victim -fsS "https://$victim/" | grep -F 'Experiment 3 Vulnerable Web App' >/dev/null
curl_attacker -fsS "https://$attacker/" | grep -F 'id="csrf-form"' >/dev/null

curl_victim -fsSG \
    --data-urlencode 'q=<script>alert(1)</script>' \
    "https://$victim/search" \
    | grep -F '<script>alert(1)</script>' >/dev/null

curl_victim -sS -o /dev/null \
    --data-urlencode 'message=<script>alert(2)</script>' \
    "https://$victim/guestbook"
curl_victim -fsS "https://$victim/" \
    | grep -F '<script>alert(2)</script>' >/dev/null

curl_victim -sS \
    -D /tmp/lab3-login.headers \
    -c /tmp/lab3-cookies.txt \
    -o /dev/null \
    -d 'username=admin&password=admin123' \
    "https://$victim/login"
docker exec "$container" grep -i '^Set-Cookie:' /tmp/lab3-login.headers \
    | grep -F 'Secure' \
    | grep -F 'SameSite=None' >/dev/null
if docker exec "$container" grep -i '^Set-Cookie:' /tmp/lab3-login.headers \
    | grep -i -F 'HttpOnly' >/dev/null; then
    echo 'Vulnerable session cookie unexpectedly has HttpOnly' >&2
    exit 1
fi

csrf_status=$(curl_victim -sS \
    -b /tmp/lab3-cookies.txt \
    -H "Origin: https://$attacker" \
    -H "Referer: https://$attacker/" \
    -o /tmp/lab3-csrf-response.txt \
    -w '%{http_code}' \
    --data 'new_password=hacked' \
    "https://$victim/change-password")
test "$csrf_status" = 200
docker exec "$container" grep -F 'Password changed successfully!' \
    /tmp/lab3-csrf-response.txt >/dev/null

docker exec "$container" sh -ec '
    nginx -t
    ss -lnt | grep -E "127\.0\.0\.1:5000[[:space:]]" >/dev/null
    ss -lnt | grep -E "[.:]80[[:space:]]" >/dev/null
    ss -lnt | grep -E "[.:]443[[:space:]]" >/dev/null
'

printf '%s\n' "PASS: $image"
