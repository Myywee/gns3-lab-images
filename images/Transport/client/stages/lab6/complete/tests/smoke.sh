#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
image=${IMAGE_TAG:-gns3-lab/transport-client:lab6-complete-smoke}

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
    test -x tcp_echo_client.py
    test -x udp_echo_client.py
    test -x udp_peer.py
    test ! -e tcp_echo_server.py
    test ! -e udp_echo_server.py
    python3 -m py_compile ./*.py

    python3 -c "
import socket
import threading

tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp_sock.bind((\"127.0.0.1\", 18080))
tcp_sock.listen(1)
udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp_sock.bind((\"127.0.0.1\", 18080))
open(\"/tmp/socket-lab-ready\", \"w\").close()

def echo_tcp():
    conn, _ = tcp_sock.accept()
    with conn:
        while True:
            data = conn.recv(65536)
            if not data:
                break
            conn.sendall(data)
    tcp_sock.close()

def echo_udp():
    for _ in range(3):
        data, addr = udp_sock.recvfrom(65535)
        udp_sock.sendto(data, addr)
    udp_sock.close()

tcp_thread = threading.Thread(target=echo_tcp)
udp_thread = threading.Thread(target=echo_udp)
tcp_thread.start()
udp_thread.start()
tcp_thread.join()
udp_thread.join()
" &
    echo_pid=$!
    trap "kill $echo_pid 2>/dev/null || true" EXIT HUP INT TERM

    attempts=0
    while [ ! -e /tmp/socket-lab-ready ]; do
        attempts=$((attempts + 1))
        test "$attempts" -lt 50
        sleep 0.1
    done

    python3 tcp_echo_client.py --server 127.0.0.1 --msg smoke \
        | grep -F "[TCP] echo test passed"
    python3 udp_echo_client.py --server 127.0.0.1 --count 3 --interval 0 \
        | grep -F "sent=3 received=3 lost=0"
    wait "$echo_pid"
    trap - EXIT HUP INT TERM

    printf "" | python3 udp_peer.py \
        --local-ip 127.0.0.1 --local-port 19001 \
        --peer-ip 127.0.0.1 --peer-port 19002 \
        | grep -F "19001"
'

test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.lab"}}' "$image")" \
    = transport/lab6
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.role"}}' "$image")" \
    = client
test "$(docker image inspect --format '{{index .Config.Labels "io.gns3.variant"}}' "$image")" \
    = complete
test "$(docker image inspect --format '{{json .Config.ExposedPorts}}' "$image")" \
    = '{"19001/udp":{}}'
test "$(docker image inspect --format '{{json .Config.WorkingDir}}' "$image")" \
    = '"/opt/socket-lab"'

printf '%s\n' "PASS: $image"
