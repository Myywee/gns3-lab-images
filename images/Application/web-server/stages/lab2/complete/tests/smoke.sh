#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
no_https_context=$(dirname "$context_dir")/no-https
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab2-web-complete-smoke}
lab1_image=${LAB1_IMAGE_TAG:-gns3-lab/web-server:lab1-complete-smoke}
no_https_image=${NO_HTTPS_IMAGE_TAG:-gns3-lab/web-server:lab2-no-https-smoke}
image=${IMAGE_TAG:-gns3-lab/web-server:lab2-complete-smoke}
volume=gns3-lab2-complete-portal-$$
certificate_dir=$(mktemp -d /tmp/gns3-lab2-certificates.XXXXXX)
missing_container=
container=

cleanup() {
    if [ -n "$missing_container" ]; then
        docker rm --force --volumes "$missing_container" >/dev/null 2>&1 || true
    fi
    if [ -n "$container" ]; then
        docker rm --force --volumes "$container" >/dev/null 2>&1 || true
    fi
    docker volume rm "$volume" >/dev/null 2>&1 || true
    rm -rf -- "$certificate_dir"
}
trap cleanup EXIT HUP INT TERM

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

if [ "${SKIP_NO_HTTPS_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab1_image" \
        --tag "$no_https_image" \
        "$no_https_context"
fi

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$no_https_image" \
        --tag "$image" \
        "$context_dir"
fi

certificate=$certificate_dir/networking-experiments.nju-slab.cn.fullchain.pem
private_key=$certificate_dir/networking-experiments.nju-slab.cn.key
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=networking-experiments.nju-slab.cn' \
    -addext 'subjectAltName=DNS:networking-experiments.nju-slab.cn' \
    -keyout "$private_key" \
    -out "$certificate" >/dev/null 2>&1
chmod 0644 "$certificate"
chmod 0600 "$private_key"

docker run --rm --entrypoint sh "$image" -ec '
    test -d /etc/nginx/certs
    test -z "$(find /etc/nginx/certs -mindepth 1 -print -quit)"
    test ! -e /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem
    test ! -e /etc/nginx/certs/networking-experiments.nju-slab.cn.key
    grep -F "return 301 https://networking-experiments.nju-slab.cn\$request_uri;" \
        /etc/nginx/conf.d/portal.conf >/dev/null
    grep -F "listen 443 ssl http2 default_server;" \
        /etc/nginx/conf.d/portal.conf >/dev/null
    grep -F "ssl_certificate /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem;" \
        /etc/nginx/conf.d/portal.conf >/dev/null
    grep -F "ssl_certificate_key /etc/nginx/certs/networking-experiments.nju-slab.cn.key;" \
        /etc/nginx/conf.d/portal.conf >/dev/null
'

docker image inspect --format '{{json .Config.Volumes}}' "$image" \
    | grep -F '"/etc/nginx/certs"' >/dev/null

# The complete image must fail closed when the host certificate mount is absent.
missing_container=$(docker create \
    "$image" /usr/local/lib/gns3/start-web-server.sh)
docker start "$missing_container" >/dev/null
missing_exit=$(docker wait "$missing_container")
test "$missing_exit" != 0
docker logs "$missing_container" 2>&1 \
    | grep -F '/etc/nginx/certs must be mounted read-only from the Docker host' >/dev/null
docker rm --force --volumes "$missing_container" >/dev/null
missing_container=

docker volume create "$volume" >/dev/null
container=$(docker run --detach \
    --mount "type=volume,src=$volume,dst=/var/www/portal" \
    --mount "type=bind,src=$certificate_dir,dst=/etc/nginx/certs,readonly" \
    "$image" /usr/local/lib/gns3/start-web-server.sh)

attempt=0
until docker exec "$container" curl -fsS --noproxy '*' \
    --cacert "/etc/nginx/certs/$(basename "$certificate")" \
    --resolve 'networking-experiments.nju-slab.cn:443:127.0.0.1' \
    https://networking-experiments.nju-slab.cn/ >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo 'Lab 2 complete web server did not become ready' >&2
        exit 1
    fi
    sleep 0.25
done

docker exec "$container" curl -sSI --noproxy '*' \
    -H 'Host: networking-experiments.nju-slab.cn' \
    http://127.0.0.1/ \
    | tr -d '\r' \
    | grep -F 'HTTP/1.1 301 Moved Permanently' >/dev/null
docker exec "$container" curl -sSI --noproxy '*' \
    -H 'Host: networking-experiments.nju-slab.cn' \
    http://127.0.0.1/ \
    | tr -d '\r' \
    | grep -i -F 'Location: https://networking-experiments.nju-slab.cn/' >/dev/null

assert_header() {
    path=$1
    expected=$2
    docker exec "$container" curl -sSI --noproxy '*' \
        --cacert "/etc/nginx/certs/$(basename "$certificate")" \
        --resolve 'networking-experiments.nju-slab.cn:443:127.0.0.1' \
        "https://networking-experiments.nju-slab.cn$path" \
        | tr -d '\r' \
        | grep -i -F "$expected" >/dev/null
}

docker exec "$container" curl -fsS --noproxy '*' \
    --cacert "/etc/nginx/certs/$(basename "$certificate")" \
    --resolve 'networking-experiments.nju-slab.cn:443:127.0.0.1' \
    https://networking-experiments.nju-slab.cn/ \
    | grep -F '<title>Shouqian Shi</title>' >/dev/null
assert_header /css/styles.css 'Cache-Control: public, max-age=7200'
assert_header /img/profile.png 'Cache-Control: public, max-age=2592000'
assert_header /img/profile.png 'Access-Control-Allow-Origin: *'
assert_header /index.html 'Cache-Control: no-store, no-cache, must-revalidate'

if docker exec "$container" touch /etc/nginx/certs/write-test >/dev/null 2>&1; then
    echo 'certificate directory is unexpectedly writable' >&2
    exit 1
fi

docker exec "$container" sh -ec '
    test -r /var/www/portal/index.html
    test -s /var/www/portal/.gns3-homepage-source
    nginx -t
    ss -lnt | grep -E "[.:]80[[:space:]]" >/dev/null
    ss -lnt | grep -E "[.:]443[[:space:]]" >/dev/null
'

printf '%s\n' "PASS: $image"
