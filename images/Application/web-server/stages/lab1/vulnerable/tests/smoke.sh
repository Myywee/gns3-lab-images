#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab1-smoke}
image=${IMAGE_TAG:-gns3-lab/web-server:lab1-vulnerable-smoke}
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "${SKIP_TOOLBOX_BUILD:-0}" != 1 ]; then
    test -f "$repo_root/images/toolbox/Dockerfile"
    docker build --pull=false --tag "$toolbox_image" "$repo_root/images/toolbox"
fi
if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false --build-arg "BASE_IMAGE=$toolbox_image" --tag "$image" "$context_dir"
fi

container=$(docker run --detach "$image" /usr/local/lib/gns3/start-web-server.sh)

attempt=0
until docker exec "$container" curl -fsS -H 'Host: www.experiment.test' http://127.0.0.1/ >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo "web server did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

assert_code() {
    expected=$1
    path=$2
    actual=$(docker exec "$container" curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1$path")
    if [ "$actual" != "$expected" ]; then
        echo "$path: expected HTTP $expected, got $actual" >&2
        exit 1
    fi
}

assert_body() {
    path=$1
    marker=$2
    docker exec "$container" curl -sS "http://127.0.0.1$path" | grep -F "$marker" >/dev/null
}

docker exec "$container" nginx -t
assert_code 200 /
assert_body / 'Experiment 1: Web and DNS Fundamentals'
assert_body / 'Web-Server: 10.10.20.20'
assert_code 200 /secure/
assert_body /secure/ 'This page should not be accessible to all clients.'
assert_code 200 /.git/HEAD
assert_body /.git/HEAD 'ref: refs/heads/master'
assert_code 200 /.git/config
assert_body /.git/config '[core]'
assert_code 404 /config.txt
assert_code 404 /definitely-missing
docker exec "$container" sh -ec '
    test ! -e /var/www/html/config.txt
    git -C /var/www/html log --all -p -- config.txt | grep -F "DB_PASSWORD=supersecret123" >/dev/null
'

printf '%s\n' "PASS: $image"
