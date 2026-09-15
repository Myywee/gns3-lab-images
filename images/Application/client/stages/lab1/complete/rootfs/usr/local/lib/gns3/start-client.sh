#!/bin/sh

set -eu

config_file=/etc/dnsmasq.d/lab-cache.conf
mkdir -p /run/dnsmasq
dnsmasq --test --conf-file="$config_file"

resolver_file=$(mktemp /tmp/gns3-resolv.XXXXXX)
trap 'rm -f "$resolver_file"' EXIT HUP INT TERM
printf 'nameserver 127.0.0.1\noptions timeout:2 attempts:2\n' > "$resolver_file"

# Docker generally bind-mounts this file. Replace its contents, not the mount.
cat "$resolver_file" > /etc/resolv.conf
rm -f "$resolver_file"
trap - EXIT HUP INT TERM

dnsmasq --conf-file="$config_file"
exec "$@"
