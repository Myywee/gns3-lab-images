# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:basic
FROM ${BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/lib/gns3/start-client.sh; \
    mkdir -p /etc/dnsmasq.d /run/dnsmasq; \
    command -v dnsmasq; \
    dnsmasq --test --conf-file=/etc/dnsmasq.d/lab-cache.conf

LABEL io.gns3.lab="application/lab1" \
      io.gns3.role="client" \
      io.gns3.variant="complete"

HEALTHCHECK --interval=10s --timeout=2s --start-period=2s --retries=3 \
    CMD dig +short +time=1 +tries=1 @127.0.0.1 localhost A | grep -qx 127.0.0.1 || exit 1

ENTRYPOINT ["/usr/local/lib/gns3/start-client.sh"]
CMD ["/bin/bash"]
