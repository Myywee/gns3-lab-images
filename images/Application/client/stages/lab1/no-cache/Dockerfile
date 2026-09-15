# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:basic
FROM ${BASE_IMAGE}

USER root

RUN set -eux; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/lib/gns3/start-client.sh;

LABEL io.gns3.lab="application/lab1" \
      io.gns3.role="client" \
      io.gns3.variant="no-cache"

ENTRYPOINT ["/usr/local/lib/gns3/start-client.sh"]
CMD ["/bin/bash"]
