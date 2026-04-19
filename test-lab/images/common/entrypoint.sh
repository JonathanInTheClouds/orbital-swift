#!/bin/sh

set -eu

install -d -m 700 -o orbital -g orbital /home/orbital/.ssh
install -m 600 -o orbital -g orbital /tmp/orbital_lab_key.pub /home/orbital/.ssh/authorized_keys

mkdir -p /var/run/sshd
ssh-keygen -A

exec /usr/sbin/sshd -D -e
