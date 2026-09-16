# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/dns-server:lab1-complete
FROM ${BASE_IMAGE}

USER root

COPY rootfs/ /

RUN set -eux; \
    chown root:bind /etc/bind/db.networking-experiments.nju-slab.cn; \
    chmod 0640 /etc/bind/db.networking-experiments.nju-slab.cn; \
    named-checkconf -z /etc/bind/named.conf

LABEL io.gns3.lab="application/lab2" \
      io.gns3.role="dns-server" \
      io.gns3.variant="complete"

EXPOSE 53/tcp 53/udp

STOPSIGNAL SIGTERM
