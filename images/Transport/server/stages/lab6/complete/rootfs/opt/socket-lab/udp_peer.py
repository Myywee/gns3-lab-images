#!/usr/bin/env python3
import argparse
import socket
import threading


def receive_loop(sock: socket.socket):
    while True:
        try:
            data, addr = sock.recvfrom(65535)
            print(f"\n[UDP-PEER] from={addr} data={data!r}\n> ", end="", flush=True)
        except OSError:
            return


def main():
    parser = argparse.ArgumentParser(description="Bound UDP peer")
    parser.add_argument("--local-ip", required=True)
    parser.add_argument("--local-port", type=int, required=True)
    parser.add_argument("--peer-ip", required=True)
    parser.add_argument("--peer-port", type=int, required=True)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.local_ip, args.local_port))
        print(f"[UDP-PEER] local={sock.getsockname()} peer={(args.peer_ip, args.peer_port)}")
        threading.Thread(target=receive_loop, args=(sock,), daemon=True).start()

        while True:
            try:
                message = input("> ")
            except (EOFError, KeyboardInterrupt):
                print()
                return
            sock.sendto(message.encode("utf-8"), (args.peer_ip, args.peer_port))


if __name__ == "__main__":
    main()
