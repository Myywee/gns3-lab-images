#!/bin/sh

set -eu

archive=/opt/gns3-labs/lab2/homepage.tar
document_root=/var/www/portal
source_marker=$document_root/.gns3-homepage-source

fail() {
    printf 'lab2 web server: %s\n' "$1" >&2
    exit 1
}

test -r "$archive" || fail "missing homepage archive: $archive"

mkdir -p "$document_root" /run/nginx

if [ ! -e "$source_marker" ]; then
    if [ -z "$(find "$document_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        tar --extract \
            --file "$archive" \
            --directory "$document_root" \
            --strip-components 1 \
            --no-same-owner \
            --no-same-permissions
        sha256sum "$archive" | awk '{print $1}' >"$source_marker"
    elif [ -r "$document_root/index.html" ]; then
        # Adopt an existing persistent portal without overwriting its content.
        printf '%s\n' pre-existing >"$source_marker"
    else
        fail "$document_root is not empty and has no readable index.html"
    fi
fi

test -r "$document_root/index.html" \
    || fail "homepage initialization did not create $document_root/index.html"

nginx -t
exec nginx -g 'daemon off;'
