#!/usr/bin/env python3
import argparse
import socket
import threading


def handle_client(conn: socket.socket, addr):
    local = conn.getsockname()
    total = 0
    print(f"[TCP] accepted local={local} peer={addr}", flush=True)

    try:
        while True:
            data = conn.recv(65536)
            if not data:
                break
            total += len(data)
            conn.sendall(data)
    except (ConnectionResetError, BrokenPipeError) as exc:
        print(f"[TCP] connection error peer={addr}: {exc}", flush=True)
    finally:
        conn.close()
        print(f"[TCP] closed peer={addr} echoed_bytes={total}", flush=True)


def main():
    parser = argparse.ArgumentParser(description="TCP Echo Server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18080)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server_sock:
        server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_sock.bind((args.host, args.port))
        server_sock.listen(128)
        print(f"[TCP] listening on {server_sock.getsockname()}", flush=True)

        try:
            while True:
                conn, addr = server_sock.accept()
                threading.Thread(
                    target=handle_client,
                    args=(conn, addr),
                    daemon=True,
                ).start()
        except KeyboardInterrupt:
            print("\n[TCP] server stopped", flush=True)


if __name__ == "__main__":
    main()
