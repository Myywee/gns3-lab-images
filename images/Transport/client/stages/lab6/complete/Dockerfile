# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ghcr.io/myywee/ubuntu:basic
FROM ${BASE_IMAGE}

USER root

RUN set -eux; \
    for command in bash grep ip ping python3 ss tcpdump; do \
        command -v "${command}" >/dev/null; \
    done; \
    dpkg-query -W -f='${Status}\n' python3 iproute2 iputils-ping tcpdump \
        | grep -c '^install ok installed$' \
        | grep -qx '4'; 

COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /opt/socket-lab/*.py; \
    python3 -m py_compile /opt/socket-lab/*.py; \
    rm -rf /opt/socket-lab/__pycache__

LABEL io.gns3.lab="transport/lab6" \
      io.gns3.role="client" \
      io.gns3.variant="complete"

EXPOSE 19001/udp

WORKDIR /opt/socket-lab

CMD ["/bin/bash"]
