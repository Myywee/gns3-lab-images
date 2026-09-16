#!/usr/bin/env python3
import argparse
import socket


def main():
    parser = argparse.ArgumentParser(description="UDP Echo Server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--bufsize", type=int, default=65535)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server_sock:
        server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_sock.bind((args.host, args.port))
        print(f"[UDP] listening on {server_sock.getsockname()}", flush=True)

        try:
            while True:
                data, addr = server_sock.recvfrom(args.bufsize)
                sent = server_sock.sendto(data, addr)
                print(
                    f"[UDP] peer={addr} received={len(data)} echoed={sent}",
                    flush=True,
                )
        except KeyboardInterrupt:
            print("\n[UDP] server stopped", flush=True)


if __name__ == "__main__":
    main()
