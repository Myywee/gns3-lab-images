#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab1-smoke}
image=${IMAGE_TAG:-gns3-lab/client:lab1-complete-smoke}
network=gns3-lab1-client-complete-$$
upstream=
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
    if [ -n "$upstream" ]; then
        docker rm --force "$upstream" >/dev/null 2>&1 || true
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
upstream=$(docker run --detach --network "$network" --ip 10.10.20.10 \
    --entrypoint /bin/sh "$toolbox_image" -ec '
        printf "10.10.20.20 www.experiment.test\n192.0.2.200 cache-smoke.test\n" > /tmp/lab.hosts
        exec dnsmasq \
            --keep-in-foreground \
            --conf-file=/dev/null \
            --port=53 \
            --listen-address=10.10.20.10 \
            --bind-interfaces \
            --no-resolv \
            --no-hosts \
            --addn-hosts=/tmp/lab.hosts \
            --local-ttl=120 \
            --cache-size=0
    ')

attempt=0
until docker run --rm --network "$network" "$toolbox_image" \
    dig +short +time=1 +tries=1 @10.10.20.10 www.experiment.test A | grep -qx 10.10.20.20; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$upstream" >&2 || true
        echo "synthetic BIND endpoint did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

container=$(docker run --detach --network "$network" "$image")

attempt=0
until docker exec "$container" dig +short +time=1 +tries=1 @127.0.0.1 localhost A | grep -qx 127.0.0.1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo "local DNS cache did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

docker exec "$container" sh -ec '
    command -v dnsmasq >/dev/null
    dpkg-query -W -f="\${Status}" dnsmasq-base | grep -q "install ok installed"
    dnsmasq --test --conf-file=/etc/dnsmasq.d/lab-cache.conf
    grep -qx "listen-address=127.0.0.1" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "no-resolv" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "server=10.10.20.10" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "cache-size=1000" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "log-queries" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "log-facility=/var/log/dnsmasq-lab.log" /etc/dnsmasq.d/lab-cache.conf
    grep -qx "pid-file=/run/dnsmasq-lab.pid" /etc/dnsmasq.d/lab-cache.conf
    test "$(sed -n "1p" /etc/resolv.conf)" = "nameserver 127.0.0.1"
    test "$(sed -n "2p" /etc/resolv.conf)" = "options timeout:2 attempts:2"
    test "$(wc -l < /etc/resolv.conf)" -eq 2
    test -s /run/dnsmasq-lab.pid
    test -f /var/log/dnsmasq-lab.log
'

authoritative_answer=$(docker exec "$container" dig +short +time=1 +tries=1 www.experiment.test A)
printf '%s\n' "$authoritative_answer" | grep -qx 10.10.20.20

docker exec "$container" sh -ec '
    kill -HUP "$(cat /run/dnsmasq-lab.pid)"
    : > /var/log/dnsmasq-lab.log
'
first_answer=$(docker exec "$container" dig +short +time=1 +tries=1 @127.0.0.1 cache-smoke.test A)
printf '%s\n' "$first_answer" | grep -qx 192.0.2.200
docker exec "$container" grep -E 'forwarded cache-smoke\.test to 10\.10\.20\.10' /var/log/dnsmasq-lab.log >/dev/null

docker stop "$upstream" >/dev/null
cached_answer=$(docker exec "$container" dig +short +time=1 +tries=1 @127.0.0.1 cache-smoke.test A)
printf '%s\n' "$cached_answer" | grep -qx 192.0.2.200
docker exec "$container" grep -E 'cached cache-smoke\.test' /var/log/dnsmasq-lab.log >/dev/null

printf '%s\n' "PASS: $image"
