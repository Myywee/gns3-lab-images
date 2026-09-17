# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/web-server:lab2-complete
FROM ${BASE_IMAGE}

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    if ! command -v python3 >/dev/null 2>&1 \
        || ! python3 -c 'import flask' >/dev/null 2>&1 \
        || ! command -v pkill >/dev/null 2>&1; then \
        if [ -e /usr/sbin/policy-rc.d ]; then cp -a /usr/sbin/policy-rc.d /tmp/policy-rc.d.saved; fi; \
        printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
        chmod 0755 /usr/sbin/policy-rc.d; \
        apt-get update; \
        apt-get install -y --no-install-recommends python3 python3-flask procps; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
        rm -f /usr/sbin/policy-rc.d; \
        if [ -e /tmp/policy-rc.d.saved ]; then mv /tmp/policy-rc.d.saved /usr/sbin/policy-rc.d; fi; \
    fi; \
    mkdir -p /opt/gns3-labs/lab2-active-backup; \
    if [ -f /etc/nginx/conf.d/portal.conf ]; then \
        cp -a /etc/nginx/conf.d/portal.conf \
            /opt/gns3-labs/lab2-active-backup/portal.conf; \
    fi

COPY rootfs/ /

RUN set -eux; \
    chmod 0555 \
        /opt/exp3/start-exp3.sh \
        /opt/exp3/stop-exp3.sh; \
    chmod 0444 \
        /opt/exp3/vuln-app/app.py \
        /opt/exp3/evil-site/index.html \
        /opt/exp3/nginx/exp3.conf; \
    rm -f \
        /usr/local/lib/gns3/start-web-server.sh \
        /etc/nginx/conf.d/portal.conf \
        /etc/nginx/conf.d/default.conf \
        /etc/nginx/sites-enabled/default; \
    ln -sfn /opt/exp3/nginx/exp3.conf /etc/nginx/conf.d/exp3.conf; \
    mkdir -p /run/nginx /var/log/nginx; \
    python3 -m py_compile /opt/exp3/vuln-app/app.py; \
    python3 -c 'import flask'; \
    grep -F 'server_name networking-experiments.nju-slab.cn;' \
        /opt/exp3/nginx/exp3.conf >/dev/null; \
    grep -F 'server_name networking-experiments-2.nju-slab.cn;' \
        /opt/exp3/nginx/exp3.conf >/dev/null

LABEL io.gns3.lab="application/lab3" \
      io.gns3.role="web-server" \
      io.gns3.variant="vulnerable" \
      io.gns3.stage="middle"

VOLUME ["/etc/nginx/certs"]

EXPOSE 80/tcp 443/tcp

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS --noproxy '*' http://127.0.0.1:5000/healthz \
        | grep -F '"mode":"vulnerable"' >/dev/null || exit 1

CMD ["/bin/bash"]
