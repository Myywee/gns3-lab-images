#!/usr/bin/env python3
import argparse
import socket
import sys
import threading
import time


def make_payload(message: str, size: int) -> bytes:
    if size <= 0:
        return message.encode("utf-8")
    pattern = b"0123456789abcdef"
    return (pattern * ((size + len(pattern) - 1) // len(pattern)))[:size]


def recv_exactly(sock: socket.socket, expected_len: int) -> bytes:
    chunks = []
    received = 0
    while received < expected_len:
        chunk = sock.recv(min(65536, expected_len - received))
        if not chunk:
            break
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)


def main():
    parser = argparse.ArgumentParser(description="TCP Echo Client")
    parser.add_argument("--server", required=True)
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--msg", default="hello from tcp client")
    parser.add_argument("--size", type=int, default=0,
                        help="generated payload bytes; overrides --msg when > 0")
    parser.add_argument("--source-ip", default="")
    parser.add_argument("--source-port", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    payload = make_payload(args.msg, args.size)
    send_error = []

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(args.timeout)
            if args.source_ip or args.source_port:
                sock.bind((args.source_ip or "0.0.0.0", args.source_port))

            started = time.monotonic()
            sock.connect((args.server, args.port))
            print(f"[TCP] local={sock.getsockname()} peer={sock.getpeername()}")

            def sender():
                try:
                    sock.sendall(payload)
                    sock.shutdown(socket.SHUT_WR)
                except OSError as exc:
                    send_error.append(exc)

            thread = threading.Thread(target=sender)
            thread.start()
            echoed = recv_exactly(sock, len(payload))
            thread.join()
            elapsed = time.monotonic() - started

            if send_error:
                raise send_error[0]

            print(
                f"[TCP] sent={len(payload)} received={len(echoed)} "
                f"elapsed={elapsed:.3f}s"
            )
            if echoed != payload:
                print("[TCP] echo test failed", file=sys.stderr)
                sys.exit(1)
            print("[TCP] echo test passed")
    except socket.timeout:
        print("[TCP] timeout", file=sys.stderr)
        sys.exit(2)
    except OSError as exc:
        print(f"[TCP] socket error: {exc}", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
