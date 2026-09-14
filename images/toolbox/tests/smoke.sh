#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
image=${IMAGE_TAG:-gns3-lab/toolbox:lab1-smoke}

docker build --pull=false --tag "$image" "$context_dir"

docker run --rm "$image" sh -ec '
    for tool in bash curl dig ip ping ss tcpdump; do
        command -v "$tool" >/dev/null
    done
    for shared_daemon in nginx named dnsmasq; do
        command -v "$shared_daemon" >/dev/null
    done
'

printf '%s\n' "PASS: $image"
