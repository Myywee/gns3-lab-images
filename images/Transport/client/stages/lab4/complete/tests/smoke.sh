#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
image=${IMAGE_TAG:-gns3-lab/transport-client:lab4-complete-smoke}

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
    test -x /opt/cc-lab/run_cc_client.sh
    bash -n /opt/cc-lab/run_cc_client.sh
    script_status=0
    /opt/cc-lab/run_cc_client.sh >/dev/null 2>&1 || script_status=$?
    test "$script_status" -eq 2
    iperf3 --help 2>&1 | grep -F -- "--congestion" >/dev/null
    test "$(dpkg-query -W -f="\${Status}\n" iperf3 iproute2 tcpdump \
        | grep -c "^install ok installed$")" -eq 3
'

test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.lab"}}' "$image")" \
    = transport/lab4
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.role"}}' "$image")" \
    = client
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.variant"}}' "$image")" \
    = complete

printf '%s\n' "PASS: $image"
