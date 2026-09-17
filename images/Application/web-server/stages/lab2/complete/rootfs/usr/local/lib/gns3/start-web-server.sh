#!/bin/sh

set -eu

archive=/opt/gns3-labs/lab2/homepage.tar
document_root=/var/www/portal
source_marker=$document_root/.gns3-homepage-source
certificate_dir=/etc/nginx/certs
certificate=$certificate_dir/networking-experiments.nju-slab.cn.fullchain.pem
private_key=$certificate_dir/networking-experiments.nju-slab.cn.key

fail() {
    printf 'lab2 complete web server: %s\n' "$1" >&2
    exit 1
}

test -r "$archive" || fail "missing homepage archive: $archive"

certificate_mount_options=$(
    awk -v path="$certificate_dir" '$2 == path { print $4; exit }' /proc/mounts
)
test -n "$certificate_mount_options" \
    || fail "$certificate_dir must be a dedicated bind mount from the Docker host"
case ",$certificate_mount_options," in
    *,ro,*) ;;
    *) fail "$certificate_dir must be mounted read-only from the Docker host" ;;
esac

test -f "$certificate" && test -s "$certificate" && test -r "$certificate" \
    || fail "missing or unreadable mounted certificate: $certificate"
test -f "$private_key" && test -s "$private_key" && test -r "$private_key" \
    || fail "missing or unreadable mounted private key: $private_key"

private_key_mode=$(stat -c '%a' "$private_key")
case "$private_key_mode" in
    400|600) ;;
    *) fail "$private_key must have mode 0400 or 0600 on the Docker host (found $private_key_mode)" ;;
esac

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

# This also verifies that the mounted certificate and key form a usable pair.
nginx -t
exec nginx -g 'daemon off;'
