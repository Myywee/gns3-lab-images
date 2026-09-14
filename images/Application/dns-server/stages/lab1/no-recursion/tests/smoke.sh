#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab1-smoke}
image=${IMAGE_TAG:-gns3-lab/dns-server:lab1-no-recursion-smoke}
network=gns3-lab1-dns-no-recursion-$$
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

if [ "${SKIP_TOOLBOX_BUILD:-0}" != 1 ]; then
    test -f "$repo_root/images/toolbox/Dockerfile"
    docker build --pull=false --tag "$toolbox_image" "$repo_root/images/toolbox"
fi
if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false --build-arg "BASE_IMAGE=$toolbox_image" --tag "$image" "$context_dir"
fi

docker network create --subnet 10.10.20.0/24 "$network" >/dev/null
container=$(docker run --detach --network "$network" --ip 10.10.20.10 "$image")

attempt=0
until docker exec "$container" dig +short +time=1 +tries=1 @127.0.0.1 ns1.experiment.test A | grep -qx 10.10.20.10; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo "DNS server did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

docker exec "$container" named-checkconf -z /etc/bind/named.conf
docker exec "$container" named-checkzone experiment.test /etc/bind/db.experiment.test
rendered_config=$(docker exec "$container" named-checkconf -p /etc/bind/named.conf)
printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*recursion no;' >/dev/null
if printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*forwarders[[:space:]]*\{' >/dev/null; then
    echo "no-recursion variant unexpectedly configures a forwarder" >&2
    exit 1
fi
docker exec "$container" grep -F 'include "/etc/bind/named.conf.default-zones";' /etc/bind/named.conf >/dev/null
docker exec "$container" sh -ec 'test "$(stat -c "%U:%G %a" /etc/bind/db.experiment.test)" = "root:bind 640"'

for transport in udp tcp; do
    if [ "$transport" = tcp ]; then
        tcp_flag=+tcp
    else
        tcp_flag=+notcp
    fi
    answer=$(docker exec "$container" dig "$tcp_flag" +time=1 +tries=1 @127.0.0.1 www.experiment.test A)
    printf '%s\n' "$answer" | grep -F 'status: NOERROR' >/dev/null
    printf '%s\n' "$answer" | grep -E '^www\.experiment\.test\..*[[:space:]]A[[:space:]]+10\.10\.20\.20$' >/dev/null
    printf '%s\n' "$answer" | grep -E 'flags:.*[[:space:]]aa([[:space:];]|$)' >/dev/null
done

external_answer=$(docker run --rm --network "$network" "$toolbox_image" \
    dig +short +time=1 +tries=1 @10.10.20.10 www.experiment.test A)
printf '%s\n' "$external_answer" | grep -qx 10.10.20.20

probe=$(docker exec "$container" dig +time=1 +tries=1 @127.0.0.1 www.example.com A)
if printf '%s\n' "$probe" | grep -E 'flags:.*[[:space:]]ra([[:space:];]|$)' >/dev/null; then
    echo "no-recursion variant unexpectedly advertises recursion" >&2
    exit 1
fi
if printf '%s\n' "$probe" | grep -E '^www\.example\.com\..*[[:space:]]A[[:space:]]+' >/dev/null; then
    echo "no-recursion variant unexpectedly returned a recursive answer" >&2
    exit 1
fi

printf '%s\n' "PASS: $image"
