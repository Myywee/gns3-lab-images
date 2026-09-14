FROM gns3/ubuntu:noble

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod 0755 /usr/sbin/policy-rc.d; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        bind9 \
        bind9-utils \
        bind9utils \
        ca-certificates \
        coreutils \
        curl \
        dbus \
        dbus-bin \
        dbus-daemon \
        dbus-session-bus-common \
        dbus-system-bus-common \
        dhcpcd \
        dmsetup \
        dns-root-data \
        dnsmasq-base \
        dnsutils \
        findutils \
        gir1.2-girepository-2.0 \
        gir1.2-glib-2.0 \
        git \
        gzip \
        iperf3 \
        iproute2 \
        iputils-ping \
        libapparmor1 \
        libargon2-1 \
        libcryptsetup12 \
        libdevmapper1.02.1 \
        libfdisk1 \
        libgirepository-1.0-1 \
        libglib2.0-0t64 \
        libglib2.0-data \
        libkmod2 \
        libonig5 \
        libsystemd-shared \
        libxslt1.1 \
        libzip4t64 \
        nano \
        networkd-dispatcher \
        nginx \
        nginx-common \
        openssl \
        php-cli \
        php-common \
        php-curl \
        php-fpm \
        php-gd \
        php-mbstring \
        php-mysql \
        php-xml \
        php-zip \
        php8.3-cli \
        php8.3-common \
        php8.3-curl \
        php8.3-fpm \
        php8.3-gd \
        php8.3-mbstring \
        php8.3-mysql \
        php8.3-opcache \
        php8.3-readline \
        php8.3-xml \
        php8.3-zip \
        procps \
        psmisc \
        python3 \
        python3-dbus \
        python3-flask \
        python3-gi \
        python3-pip \
        shared-mime-info \
        systemd \
        systemd-dev \
        systemd-resolved \
        systemd-timesyncd \
        tar \
        tcpdump \
        ucf \
        xdg-user-dirs; \
    update-ca-certificates; \
    rm -f /usr/sbin/policy-rc.d; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p \
        /run/nginx \
        /run/named \
        /run/php \
        /var/log/nginx \
        /opt/gns3-labs \
        /opt/socket-lab \
        /opt/cc-lab; \
    if getent passwd bind >/dev/null 2>&1; then \
        chown bind:bind /run/named; \
    fi; \
    python3 -c 'import dbus, flask, gi'; \
    nginx -v; \
    named -V | head -n 1; \
    php --version | head -n 1; \
    php-fpm8.3 -v | head -n 1; \
    iperf3 --version | head -n 1

CMD ["/bin/bash"]
