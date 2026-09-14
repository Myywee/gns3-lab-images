#!/bin/sh

set -eu

resolver_file=$(mktemp /tmp/gns3-resolv.XXXXXX)
trap 'rm -f "$resolver_file"' EXIT HUP INT TERM
printf 'nameserver 10.10.20.10\noptions timeout:2 attempts:2\n' > "$resolver_file"

# Docker generally bind-mounts this file. Replace its contents, not the mount.
cat "$resolver_file" > /etc/resolv.conf
rm -f "$resolver_file"
trap - EXIT HUP INT TERM

exec "$@"
