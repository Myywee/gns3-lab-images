#!/bin/sh

set -eu

mkdir -p /run/named /var/cache/bind /var/lib/bind
chown bind:bind /run/named /var/cache/bind /var/lib/bind
named-checkconf -z /etc/bind/named.conf
exec /usr/sbin/named -g -u bind -c /etc/bind/named.conf
