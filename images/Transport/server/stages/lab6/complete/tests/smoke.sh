#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
image=${IMAGE_TAG:-gns3-lab/transport-server:lab6-complete-smoke}

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false \
        --build-arg "BASE_IMAGE=${BASE_IMAGE:-ghcr.io/myywee/ubuntu:basic}" \
        --tag "$image" \
        "$context_dir"
fi

docker run --rm --entrypoint /bin/sh "$image" -ec '
    for command in bash grep ip ping python3 ss tcpdump; do
        command -v "$command" >/dev/null
    done
    test -x /gns3/bin/busybox
    test "$(dpkg-query -W -f="\${Status}\n" python3 iproute2 iputils-ping tcpdump \
        | grep -c "^install ok installed$")" -eq 4

    cd /opt/socket-lab
    test -x tcp_echo_server.py
    test -x udp_echo_server.py
    test -x udp_peer.py
    test ! -e tcp_echo_client.py
    test ! -e udp_echo_client.py
    python3 -m py_compile ./*.py

    python3 -u tcp_echo_server.py --host 127.0.0.1 --port 18080 \
        >/tmp/tcp-server.log 2>&1 &
    tcp_pid=$!
    python3 -u udp_echo_server.py --host 127.0.0.1 --port 18080 \
        >/tmp/udp-server.log 2>&1 &
    udp_pid=$!
    trap "kill $tcp_pid $udp_pid 2>/dev/null || true" EXIT HUP INT TERM

    attempts=0
    until ss -ltn "sport = :18080" | grep -q LISTEN \
        && ss -lun "sport = :18080" | grep -q 18080; do
        attempts=$((attempts + 1))
        test "$attempts" -lt 50
        sleep 0.1
    done

    python3 -c "
import socket

payload = b\"server-smoke\"
with socket.create_connection((\"127.0.0.1\", 18080), timeout=2) as sock:
    sock.sendall(payload)
    sock.shutdown(socket.SHUT_WR)
    echoed = b\"\"
    while len(echoed) < len(payload):
        chunk = sock.recv(65536)
        if not chunk:
            break
        echoed += chunk
    assert echoed == payload

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.settimeout(2)
    sock.sendto(payload, (\"127.0.0.1\", 18080))
    echoed, peer = sock.recvfrom(65535)
    assert echoed == payload
    assert peer == (\"127.0.0.1\", 18080)
"
    attempts=0
    until grep -q "echoed_bytes=12" /tmp/tcp-server.log \
        && grep -q "received=12 echoed=12" /tmp/udp-server.log; do
        attempts=$((attempts + 1))
        test "$attempts" -lt 50
        sleep 0.1
    done

    printf "" | python3 udp_peer.py \
        --local-ip 127.0.0.1 --local-port 19002 \
        --peer-ip 127.0.0.1 --peer-port 19001 \
        | grep -F "19002"
'

test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.lab"}}' "$image")" \
    = transport/lab6
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.role"}}' "$image")" \
    = server
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.variant"}}' "$image")" \
    = complete
test "$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")" \
    = '{"18080/tcp":{},"18080/udp":{},"19002/udp":{}}'
test "$(docker image inspect --format '{{json .Config.WorkingDir}}' "$image")" \
    = '"/opt/socket-lab"'

printf '%s\n' "PASS: $image"
