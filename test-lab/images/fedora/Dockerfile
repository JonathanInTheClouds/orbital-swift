FROM fedora:41

RUN dnf install -y \
        coreutils \
        gawk \
        iproute \
        net-tools \
        openssh-server \
        passwd \
        procps-ng \
        shadow-utils \
    && dnf clean all

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
