# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:basic
FROM ${BASE_IMAGE}

USER root

RUN set -eux; \
    for command in bash grep ip iperf3 ss tc tcpdump; do \
        command -v "${command}" >/dev/null; \
    done; \
    dpkg-query -W -f='${Status}\n' iperf3 iproute2 tcpdump \
        | grep -c '^install ok installed$' \
        | grep -qx '3'; \
    iperf3 --help 2>&1 | grep -F -- '--congestion' >/dev/null

COPY --chown=root:root rootfs/ /

RUN set -eux; \
    chmod 0755 /opt/cc-lab/run_cc_client.sh; \
    bash -n /opt/cc-lab/run_cc_client.sh

LABEL io.gns3.lab="transport/lab4" \
      io.gns3.role="client" \
      io.gns3.variant="complete"

CMD ["/bin/bash"]
