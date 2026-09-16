#!/usr/bin/env python3
import argparse
import socket
import sys
import time


def make_datagram(sequence: int, size: int) -> bytes:
    header = f"{sequence:08d}|".encode("ascii")
    if size < len(header):
        raise ValueError(f"size must be at least {len(header)}")
    return header + b"U" * (size - len(header))


def main():
    parser = argparse.ArgumentParser(description="UDP Echo Client")
    parser.add_argument("--server", required=True)
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--size", type=int, default=64)
    parser.add_argument("--interval", type=float, default=0.1)
    parser.add_argument("--timeout", type=float, default=0.5)
    parser.add_argument("--source-ip", default="")
    parser.add_argument("--source-port", type=int, default=0)
    args = parser.parse_args()

    received = 0
    rtts = []

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            if args.source_ip or args.source_port:
                sock.bind((args.source_ip or "0.0.0.0", args.source_port))
            sock.settimeout(args.timeout)

            for sequence in range(1, args.count + 1):
                payload = make_datagram(sequence, args.size)
                started = time.monotonic()
                sock.sendto(payload, (args.server, args.port))
                local = sock.getsockname()

                try:
                    echoed, peer = sock.recvfrom(65535)
                    rtt_ms = (time.monotonic() - started) * 1000
                    if echoed == payload:
                        received += 1
                        rtts.append(rtt_ms)
                        print(
                            f"[UDP] seq={sequence} local={local} peer={peer} "
                            f"rtt={rtt_ms:.2f}ms"
                        )
                    else:
                        print(f"[UDP] seq={sequence} mismatched echo")
                except socket.timeout:
                    print(f"[UDP] seq={sequence} timeout")

                if sequence != args.count:
                    time.sleep(args.interval)

        lost = args.count - received
        loss_percent = 100.0 * lost / args.count if args.count else 0.0
        average = sum(rtts) / len(rtts) if rtts else 0.0
        print(
            f"[UDP] sent={args.count} received={received} lost={lost} "
            f"loss={loss_percent:.1f}% avg_rtt={average:.2f}ms"
        )
        sys.exit(0 if lost == 0 else 1)
    except (OSError, ValueError) as exc:
        print(f"[UDP] error: {exc}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
