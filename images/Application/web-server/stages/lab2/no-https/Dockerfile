# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/web-server:lab1-complete
FROM ${BASE_IMAGE}

USER root

RUN set -eux; \
    mkdir -p /opt/gns3-labs/lab1-nginx-backup; \
    cp -a /etc/nginx/. /opt/gns3-labs/lab1-nginx-backup/

COPY resources/homepage.tar /opt/gns3-labs/lab2/homepage.tar
COPY rootfs/ /

RUN set -eux; \
    chmod 0555 /usr/local/lib/gns3/start-web-server.sh; \
    chmod 0444 /opt/gns3-labs/lab2/homepage.tar; \
    mkdir -p /var/www/portal; \
    mkdir -p /opt/gns3-labs/disabled-nginx-config; \
    test -e /etc/nginx/sites-enabled/default \
        && mv /etc/nginx/sites-enabled/default \
            /opt/gns3-labs/disabled-nginx-config/default; \
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf; \
    tar -tf /opt/gns3-labs/lab2/homepage.tar \
        | grep -x 'homepage/index.html' >/dev/null; \
    if tar -tf /opt/gns3-labs/lab2/homepage.tar \
        | grep -Eq '(^/|(^|/)\.\.(/|$))'; then \
        echo 'homepage.tar contains an unsafe path' >&2; \
        exit 1; \
    fi; \
    tar -tf /opt/gns3-labs/lab2/homepage.tar | head -20; \
    tar -xf /opt/gns3-labs/lab2/homepage.tar \
        -C /var/www/portal \
        --strip-components=1; \
    test -f /var/www/portal/index.html; \
    nginx -t

LABEL io.gns3.lab="application/lab2" \
      io.gns3.role="web-server" \
      io.gns3.variant="no-https"

VOLUME ["/var/www/portal"]

EXPOSE 80/tcp

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 \
    CMD curl -fsS --noproxy '*' -H 'Host: networking-experiments.nju-slab.cn' \
        http://127.0.0.1/ >/dev/null || exit 1

CMD ["bin/bash"]
