FROM alpine:3.21

RUN apk add --no-cache \
        coreutils \
        gawk \
        iproute2 \
        net-tools \
        openssh-server \
        procps \
        shadow

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
