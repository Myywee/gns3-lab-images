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
    apt-get install -y --no-install-recommends git nginx; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /usr/sbin/policy-rc.d; \
    if [ -e /tmp/policy-rc.d.saved ]; then mv /tmp/policy-rc.d.saved /usr/sbin/policy-rc.d; fi

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/lib/gns3/start-web-server.sh; \
    ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default; \
    rm -f /var/www/html/index.nginx-debian.html; \
    git -C /var/www/html init -b master; \
    git -C /var/www/html config user.name 'Lab Administrator'; \
    git -C /var/www/html config user.email 'admin@experiment.test'; \
    git -C /var/www/html add index.html secure/index.html; \
    git -C /var/www/html commit -m 'Initial website'; \
    printf 'DB_PASSWORD=supersecret123\n' > /var/www/html/config.txt; \
    git -C /var/www/html add config.txt; \
    git -C /var/www/html commit -m 'Add configuration file'; \
    git -C /var/www/html rm config.txt; \
    git -C /var/www/html commit -m 'Remove exposed configuration'; \
    test -f /var/www/html/secure/index.html; \
    test -f /var/www/html/.git/HEAD; \
    test ! -e /var/www/html/config.txt; \
    git -C /var/www/html log --all -p -- config.txt | grep -F 'DB_PASSWORD=supersecret123'; \
    nginx -t

LABEL io.gns3.lab="application/lab1" \
      io.gns3.role="web-server" \
      io.gns3.variant="vulnerable"

EXPOSE 80/tcp

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=2s --start-period=2s --retries=3 \
    CMD curl -fsS -H 'Host: www.experiment.test' http://127.0.0.1/ || exit 1

CMD ["/bin/bash"]
