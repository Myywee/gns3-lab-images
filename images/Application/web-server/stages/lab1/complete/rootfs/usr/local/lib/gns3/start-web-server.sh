#!/bin/sh

set -eu

mkdir -p /run/nginx
nginx -t
exec nginx -g 'daemon off;'
