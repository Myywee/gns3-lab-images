# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/web-server:lab2-no-https
FROM ${BASE_IMAGE}

USER root

COPY rootfs/ /

RUN set -eux; \
    chmod 0555 /usr/local/lib/gns3/start-web-server.sh; \
    mkdir -p /etc/nginx/certs; \
    test -z "$(find /etc/nginx/certs -mindepth 1 -print -quit)"; \
    grep -F 'listen 443 ssl http2 default_server;' \
        /etc/nginx/conf.d/portal.conf >/dev/null; \
    grep -F 'ssl_certificate /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem;' \
        /etc/nginx/conf.d/portal.conf >/dev/null; \
    grep -F 'ssl_certificate_key /etc/nginx/certs/networking-experiments.nju-slab.cn.key;' \
        /etc/nginx/conf.d/portal.conf >/dev/null

LABEL io.gns3.lab="application/lab2" \
      io.gns3.role="web-server" \
      io.gns3.variant="complete"

# This directory is intentionally empty in the image. At runtime it must be
# replaced by a read-only bind mount from the Docker/GNS3 VM host.
VOLUME ["/etc/nginx/certs"]

EXPOSE 80/tcp 443/tcp

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
    CMD curl -fsS --noproxy '*' -o /dev/null \
        -H 'Host: networking-experiments.nju-slab.cn' \
        http://127.0.0.1/ || exit 1

CMD ["/bin/bash"]
