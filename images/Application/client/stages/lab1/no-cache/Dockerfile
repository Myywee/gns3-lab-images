# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:slab
FROM ${BASE_IMAGE}

USER root

RUN set -eux; \
    apt-get purge -y dnsmasq-base; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/lib/gns3/start-client.sh; \
    ! command -v dnsmasq; \
    ! dpkg-query -W -f='${Status}' dnsmasq-base 2>/dev/null | grep -q 'install ok installed'

LABEL io.gns3.lab="application/lab1" \
      io.gns3.role="client" \
      io.gns3.variant="no-cache"

ENTRYPOINT ["/usr/local/lib/gns3/start-client.sh"]
CMD ["/bin/bash"]
