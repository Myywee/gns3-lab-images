#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
context_dir=$(dirname "$script_dir")
repo_root=${REPO_ROOT:-$(CDPATH='' cd -- "$script_dir/../../../../../../.." && pwd)}
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab1-smoke}
image=${IMAGE_TAG:-gns3-lab/dns-server:lab1-complete-smoke}
network=gns3-lab1-dns-$$
authority=
container=
temporary_dir=$(mktemp -d)

cleanup() {
    if [ -n "$container" ]; then
        docker rm --force "$container" >/dev/null 2>&1 || true
    fi
    if [ -n "$authority" ]; then
        docker rm --force "$authority" >/dev/null 2>&1 || true
    fi
    docker network rm "$network" >/dev/null 2>&1 || true
    rm -rf "$temporary_dir"
}
trap cleanup EXIT HUP INT TERM

if [ "${SKIP_TOOLBOX_BUILD:-0}" != 1 ]; then
    test -f "$repo_root/images/toolbox/Dockerfile"
    docker build --pull=false --tag "$toolbox_image" "$repo_root/images/toolbox"
fi
if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build --pull=false --build-arg "BASE_IMAGE=$toolbox_image" --tag "$image" "$context_dir"
fi

mkdir -p "$temporary_dir/authority"
cat > "$temporary_dir/authority/named.conf" <<'EOF'
options {
    directory "/tmp";
    pid-file "/tmp/authority-named.pid";
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    recursion no;
    allow-query { any; };
    allow-query-cache { none; };
    dnssec-validation no;
};
zone "." {
    type primary;
    file "/tmp/root.zone";
};
EOF
cat > "$temporary_dir/authority/root.zone.in" <<'EOF'
$ORIGIN .
$TTL 300
@                   IN SOA  ns.root. hostmaster.root. ( 1 3600 900 604800 300 )
                    IN NS   ns.root.
ns.root.            IN A    AUTHORITY_IP
recursive-probe.    IN A    192.0.2.123
EOF
chmod 0755 "$temporary_dir/authority"
chmod 0644 "$temporary_dir/authority/named.conf" "$temporary_dir/authority/root.zone.in"

docker network create --subnet 10.10.20.0/24 "$network" >/dev/null
authority=$(docker run --detach --network "$network" \
    --volume "$temporary_dir/authority:/probe:ro" \
    "$image" /bin/sh -ec '
        authority_ip=$(hostname -i | awk "{ print \$1 }")
        sed "s/AUTHORITY_IP/$authority_ip/" /probe/root.zone.in > /tmp/root.zone
        exec /usr/sbin/named -g -u bind -c /probe/named.conf
    ')
authority_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$authority")

cat > "$temporary_dir/root.hints" <<EOF
.          3600 IN NS ns.root.
ns.root.   3600 IN A  $authority_ip
EOF
chmod 0644 "$temporary_dir/root.hints"

# The production image keeps DNSSEC validation enabled. This isolated smoke
# root is intentionally synthetic and unsigned, so disable validation only in
# the mounted test copy; every other recursive setting remains unchanged.
sed 's/dnssec-validation auto;/dnssec-validation no;/' \
    "$context_dir/rootfs/etc/bind/named.conf.options" \
    > "$temporary_dir/named.conf.options"
chmod 0644 "$temporary_dir/named.conf.options"

attempt=0
until docker run --rm --network "$network" "$toolbox_image" \
    dig +short +time=1 +tries=1 "@$authority_ip" recursive-probe. A | grep -qx 192.0.2.123; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$authority" >&2 || true
        echo "synthetic root server did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

container=$(docker run --detach --network "$network" \
    --ip 10.10.20.10 \
    --volume "$temporary_dir/root.hints:/usr/share/dns/root.hints:ro" \
    --volume "$temporary_dir/named.conf.options:/etc/bind/named.conf.options:ro" \
    "$image")

attempt=0
until docker exec "$container" dig +short +time=1 +tries=1 @127.0.0.1 ns1.experiment.test A | grep -qx 10.10.20.10; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        docker logs "$container" >&2 || true
        echo "DNS server did not become ready" >&2
        exit 1
    fi
    sleep 0.25
done

docker exec "$container" named-checkconf -z /etc/bind/named.conf
docker exec "$container" named-checkzone experiment.test /etc/bind/db.experiment.test
rendered_config=$(docker exec "$container" named-checkconf -p /etc/bind/named.conf)
printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*recursion yes;' >/dev/null
if printf '%s\n' "$rendered_config" | grep -E '^[[:space:]]*forwarders[[:space:]]*\{' >/dev/null; then
    echo "complete variant unexpectedly configures a forwarder" >&2
    exit 1
fi
docker exec "$container" grep -F 'include "/etc/bind/named.conf.default-zones";' /etc/bind/named.conf >/dev/null
docker exec "$container" sh -ec 'test "$(stat -c "%U:%G %a" /etc/bind/db.experiment.test)" = "root:bind 640"'
container_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container")

external_authoritative=$(docker run --rm --network "$network" "$toolbox_image" \
    dig +time=1 +tries=1 "@$container_ip" www.experiment.test A)
printf '%s\n' "$external_authoritative" | grep -F 'status: NOERROR' >/dev/null
printf '%s\n' "$external_authoritative" | grep -E '^www\.experiment\.test\..*[[:space:]]A[[:space:]]+10\.10\.20\.20$' >/dev/null

for transport in udp tcp; do
    if [ "$transport" = tcp ]; then
        tcp_flag=+tcp
    else
        tcp_flag=+notcp
    fi
    answer=$(docker exec "$container" dig "$tcp_flag" +time=1 +tries=1 @127.0.0.1 www.experiment.test A)
    printf '%s\n' "$answer" | grep -F 'status: NOERROR' >/dev/null
    printf '%s\n' "$answer" | grep -E '^www\.experiment\.test\..*[[:space:]]A[[:space:]]+10\.10\.20\.20$' >/dev/null
    printf '%s\n' "$answer" | grep -E 'flags:.*[[:space:]]aa([[:space:];]|$)' >/dev/null
    printf '%s\n' "$answer" | grep -E 'flags:.*[[:space:]]ra([[:space:];]|$)' >/dev/null
done

recursive_answer=$(docker run --rm --network "$network" "$toolbox_image" \
    dig +cdflag +time=2 +tries=1 "@$container_ip" recursive-probe. A)
printf '%s\n' "$recursive_answer" | grep -F 'status: NOERROR' >/dev/null
printf '%s\n' "$recursive_answer" | grep -E 'flags:.*[[:space:]]ra([[:space:];]|$)' >/dev/null
printf '%s\n' "$recursive_answer" | grep -E '^recursive-probe\..*[[:space:]]A[[:space:]]+192\.0\.2\.123$' >/dev/null

# A second answer must survive removal of the upstream authority, proving that
# the complete server cached the recursively obtained record.
docker stop "$authority" >/dev/null
cached_answer=$(docker exec "$container" dig +cdflag +short +time=1 +tries=1 @127.0.0.1 recursive-probe. A)
printf '%s\n' "$cached_answer" | grep -qx 192.0.2.123

printf '%s\n' "PASS: $image"
