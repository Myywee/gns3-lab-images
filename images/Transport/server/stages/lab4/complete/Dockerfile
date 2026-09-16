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
        | grep -qx '3'; 

LABEL io.gns3.lab="transport/lab4" \
      io.gns3.role="server" \
      io.gns3.variant="complete"

EXPOSE 5201/tcp

CMD ["/bin/bash"]
