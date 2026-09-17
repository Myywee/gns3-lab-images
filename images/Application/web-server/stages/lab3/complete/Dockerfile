# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/web-server:lab3-vulnerable
FROM ${BASE_IMAGE}

USER root

COPY rootfs/ /

RUN set -eux; \
    chmod 0444 /opt/exp3/vuln-app/app.py; \
    python3 -m py_compile /opt/exp3/vuln-app/app.py; \
    grep -F 'SESSION_COOKIE_HTTPONLY=True' /opt/exp3/vuln-app/app.py >/dev/null; \
    grep -F 'SESSION_COOKIE_SAMESITE="Lax"' /opt/exp3/vuln-app/app.py >/dev/null; \
    grep -F 'secrets.compare_digest' /opt/exp3/vuln-app/app.py >/dev/null

LABEL io.gns3.lab="application/lab3" \
      io.gns3.role="web-server" \
      io.gns3.variant="complete" \
      io.gns3.stage="complete"

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS --noproxy '*' http://127.0.0.1:5000/healthz \
        | grep -F '"mode":"complete"' >/dev/null || exit 1

CMD ["/bin/bash"]
