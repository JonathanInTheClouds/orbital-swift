ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        coreutils \
        gawk \
        iproute2 \
        net-tools \
        openssh-server \
        passwd \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/sh orbital \
    && echo 'orbital:orbital' | chpasswd \
    && mkdir -p /home/orbital/.ssh \
    && chown -R orbital:orbital /home/orbital/.ssh

COPY keys/orbital_lab_key.pub /tmp/orbital_lab_key.pub
COPY images/common/sshd_config /etc/ssh/sshd_config
COPY images/common/entrypoint.sh /usr/local/bin/orbital-entrypoint

RUN chmod 755 /usr/local/bin/orbital-entrypoint

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/orbital-entrypoint"]
