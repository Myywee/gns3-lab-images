#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab3-dns-smoke}
lab1_image=${LAB1_IMAGE_TAG:-gns3-lab/dns-server:lab1-complete-lab3-smoke}
lab2_image=${LAB2_IMAGE_TAG:-gns3-lab/dns-server:lab2-complete-lab3-smoke}
image=${IMAGE_TAG:-gns3-lab/dns-server:lab3-complete-smoke}
network=gns3-lab3-dns-$$
container=

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

if [ "${SKIP_LAB2_BUILD:-0}" != 1 ]; then
    if [ "${SKIP_LAB1_BUILD:-0}" != 1 ]; then
        if [ "${SKIP_TOOLBOX_BUILD:-0}" != 1 ]; then
            test -f "$repo_root/images/toolbox/Dockerfile"
            docker build --pull=false --tag "$toolbox_image" "$repo_root/images/toolbox"
        fi
        docker build --pull=false \
            --build-arg "BASE_IMAGE=$toolbox_image" \
            --tag "$lab1_image" \
            "$repo_root/images/Application/dns-server/stages/lab1/complete"
    fi
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab1_image" \
        --tag "$lab2_image" \
        "$repo_root/images/Application/dns-server/stages/lab2/complete"
fi

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=$lab2_image" \
        --tag "$image" \
        "$context_dir"
fi

docker network create --subnet 10.10.20.0/24 "$network" >/dev/null
container=$(docker run --detach --network "$network" --ip 10.10.20.10 "$image")

attempt=0
until docker exec "$container" \
    dig +short +time=1 +tries=1 @127.0.0.1 networking-experiments-2.nju-slab.cn A \
    | grep -qx 10.10.20.20; do
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
docker exec "$container" named-checkzone networking-experiments.nju-slab.cn \
    /etc/bind/db.networking-experiments.nju-slab.cn
docker exec "$container" named-checkzone networking-experiments-2.nju-slab.cn \
    /etc/bind/db.networking-experiments-2.nju-slab.cn

rendered_config=$(docker exec "$container" named-checkconf -p /etc/bind/named.conf)
printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*recursion yes;' >/dev/null
if printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*forwarders[[:space:]]*\{' >/dev/null; then
    echo "lab3 complete variant unexpectedly configures a forwarder" >&2
    exit 1
fi
for zone in \
    experiment.test \
    networking-experiments.nju-slab.cn \
    networking-experiments-2.nju-slab.cn; do
    printf '%s\n' "$rendered_config" | grep -F "zone \"$zone\"" >/dev/null
done

docker exec "$container" sh -ec \
    'test "$(stat -c "%U:%G %a" /etc/bind/db.networking-experiments-2.nju-slab.cn)" = "root:bind 640"'
docker exec "$container" ss -lnut | grep -E 'udp.*10\.10\.20\.10:53' >/dev/null
docker exec "$container" ss -lnt | grep -E 'tcp.*10\.10\.20\.10:53' >/dev/null

container_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container")

for transport in udp tcp; do
    if [ "$transport" = tcp ]; then
        tcp_flag=+tcp
    else
        tcp_flag=+notcp
    fi

    for zone in networking-experiments.nju-slab.cn networking-experiments-2.nju-slab.cn; do
        answer=$(docker run --rm --network "$network" "$toolbox_image" \
            dig "$tcp_flag" +time=1 +tries=1 "@$container_ip" "$zone" A)
        printf '%s\n' "$answer" | grep -F 'status: NOERROR' >/dev/null
        printf '%s\n' "$answer" | awk -v name="$zone." \
            '$1 == name && $4 == "A" && $5 == "10.10.20.20" { found=1 } END { exit !found }'
        printf '%s\n' "$answer" | grep -E 'flags:.*[[:space:]]aa([[:space:];]|$)' >/dev/null
        printf '%s\n' "$answer" | grep -E 'flags:.*[[:space:]]ra([[:space:];]|$)' >/dev/null
    done
done

ns_answer=$(docker exec "$container" \
    dig +short +time=1 +tries=1 @127.0.0.1 networking-experiments-2.nju-slab.cn NS)
printf '%s\n' "$ns_answer" | grep -qx 'ns.networking-experiments-2.nju-slab.cn.'

ns_address=$(docker exec "$container" \
    dig +short +time=1 +tries=1 @127.0.0.1 ns.networking-experiments-2.nju-slab.cn A)
printf '%s\n' "$ns_address" | grep -qx 10.10.20.10

printf '%s\n' "PASS: $image"
