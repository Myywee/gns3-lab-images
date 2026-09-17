#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab2-web-smoke}
lab1_image=${LAB1_IMAGE_TAG:-gns3-lab/web-server:lab1-complete-smoke}
image=${IMAGE_TAG:-gns3-lab/web-server:lab2-no-https-smoke}
volume=gns3-lab2-portal-$$
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
    docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

test -f "$context_dir/resources/homepage.tar"
tar -tf "$context_dir/resources/homepage.tar" \
    | grep -x homepage/index.html >/dev/null

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

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab1_image" \
        --tag "$image" \
        "$context_dir"
fi

docker run --rm --entrypoint sh "$image" -ec '
    test -f /opt/gns3-labs/lab2/homepage.tar
    test "$(stat -c "%U:%G %a" /opt/gns3-labs/lab2/homepage.tar)" = "root:root 444"
    tar -tf /opt/gns3-labs/lab2/homepage.tar \
        | grep -x homepage/index.html >/dev/null
    test -d /opt/gns3-labs/lab1-nginx-backup
    test ! -e /etc/nginx/certs/fullchain.pem
    test ! -e /etc/nginx/certs/privkey.pem
    test ! -e /etc/nginx/sites-enabled/default
    grep -F "listen 80 default_server" /etc/nginx/conf.d/portal.conf >/dev/null
    if grep -R -E "listen[[:space:]]+443|ssl_certificate" /etc/nginx/conf.d; then
        echo "no-https image unexpectedly contains TLS configuration" >&2
        exit 1
    fi
    nginx -t
'

docker volume create "$volume" >/dev/null
container=$(docker run --detach \
    --mount "type=volume,src=$volume,dst=/var/www/portal" \
    "$image" /usr/local/lib/gns3/start-web-server.sh)

attempt=0
until docker exec "$container" curl -fsS --noproxy '*' \
    -H 'Host: networking-experiments.nju-slab.cn' \
    http://127.0.0.1/ >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo 'Lab 2 web server did not become ready' >&2
        exit 1
    fi
    sleep 0.25
done

assert_header() {
    path=$1
    expected=$2
    docker exec "$container" curl -sSI --noproxy '*' \
        -H 'Host: networking-experiments.nju-slab.cn' \
        "http://127.0.0.1$path" \
        | tr -d '\r' \
        | grep -i -F "$expected" >/dev/null
}

status=$(docker exec "$container" curl -sS --noproxy '*' \
    -o /dev/null -w '%{http_code}' \
    -H 'Host: networking-experiments.nju-slab.cn' http://127.0.0.1/)
test "$status" = 200

docker exec "$container" curl -fsS --noproxy '*' \
    -H 'Host: networking-experiments.nju-slab.cn' http://127.0.0.1/ \
    | grep -F '<title>Shouqian Shi</title>' >/dev/null
assert_header /css/styles.css 'Cache-Control: public, max-age=7200'
assert_header /img/profile.png 'Cache-Control: public, max-age=2592000'
assert_header /img/profile.png 'Access-Control-Allow-Origin: *'
assert_header /index.html 'Cache-Control: no-store, no-cache, must-revalidate'

hidden_status=$(docker exec "$container" curl -sS --noproxy '*' \
    -o /dev/null -w '%{http_code}' \
    -H 'Host: networking-experiments.nju-slab.cn' \
    http://127.0.0.1/.gitignore)
case "$hidden_status" in
    403|404) ;;
    *)
        echo "hidden file unexpectedly returned HTTP $hidden_status" >&2
        exit 1
        ;;
esac

docker exec "$container" sh -ec '
    test -r /var/www/portal/index.html
    test -s /var/www/portal/.gns3-homepage-source
    printf "%s\n" persistent-student-data >/var/www/portal/student-note.txt
    nginx -t
    ss -lnt | grep -E "[.:]80[[:space:]]" >/dev/null
    if ss -lnt | grep -E "[.:]443[[:space:]]" >/dev/null; then
        echo "no-https image unexpectedly listens on port 443" >&2
        exit 1
    fi
'

docker rm --force "$container" >/dev/null
container=$(docker run --detach \
    --mount "type=volume,src=$volume,dst=/var/www/portal" \
    "$image" /usr/local/lib/gns3/start-web-server.sh)

attempt=0
until docker exec "$container" curl -fsS --noproxy '*' \
    -H 'Host: networking-experiments.nju-slab.cn' \
    http://127.0.0.1/ >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo 'Lab 2 web server did not restart with its persistent portal' >&2
        exit 1
    fi
    sleep 0.25
done
docker exec "$container" grep -qx persistent-student-data /var/www/portal/student-note.txt

printf '%s\n' "PASS: $image"
