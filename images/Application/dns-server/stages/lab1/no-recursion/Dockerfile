# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:basic
FROM ${BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    if [ -e /usr/sbin/policy-rc.d ]; then cp -a /usr/sbin/policy-rc.d /tmp/policy-rc.d.saved; fi; \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod 0755 /usr/sbin/policy-rc.d; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bind9 \
        bind9-utils \
        dns-root-data \
        dnsutils; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /usr/sbin/policy-rc.d; \
    if [ -e /tmp/policy-rc.d.saved ]; then mv /tmp/policy-rc.d.saved /usr/sbin/policy-rc.d; fi

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/lib/gns3/start-dns-server.sh; \
    chown root:bind /etc/bind/db.experiment.test; \
    chmod 0640 /etc/bind/db.experiment.test; \
    mkdir -p /run/named /var/cache/bind /var/lib/bind; \
    chown bind:bind /run/named /var/cache/bind /var/lib/bind; \
    named-checkconf -z /etc/bind/named.conf

LABEL io.gns3.lab="application/lab1" \
      io.gns3.role="dns-server" \
      io.gns3.variant="no-recursion"

EXPOSE 53/tcp 53/udp

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=10s --timeout=2s --start-period=2s --retries=3 \
    CMD dig +short +time=1 +tries=1 @127.0.0.1 ns1.experiment.test A | grep -qx 10.10.20.10 || exit 1

CMD ["/usr/local/lib/gns3/start-dns-server.sh"]
