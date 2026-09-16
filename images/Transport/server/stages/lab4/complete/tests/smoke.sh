#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
image=${IMAGE_TAG:-gns3-lab/transport-server:lab4-complete-smoke}

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=${BASE_IMAGE:-ghcr.io/myywee/ubuntu:basic}" \
        --tag "$image" \
        "$context_dir"
fi

docker run --rm --entrypoint /bin/sh "$image" -ec '
    for command in bash grep ip iperf3 ss tc tcpdump; do
        command -v "$command" >/dev/null
    done
    test -x /gns3/bin/busybox
    test "$(dpkg-query -W -f="\${Status}\n" iperf3 iproute2 tcpdump \
        | grep -c "^install ok installed$")" -eq 3
    iperf3 -s -D -p 5201
    trap "pkill iperf3 2>/dev/null || true" EXIT HUP INT TERM
    iperf3 -c 127.0.0.1 -p 5201 -t 1 -J >/tmp/iperf3-smoke.json
    grep -q "\"sum_sent\"" /tmp/iperf3-smoke.json
'

test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.lab"}}' "$image")" \
    = transport/lab4
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.role"}}' "$image")" \
    = server
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.variant"}}' "$image")" \
    = complete
test "$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")" \
    = '{"5201/tcp":{}}'

printf '%s\n' "PASS: $image"
