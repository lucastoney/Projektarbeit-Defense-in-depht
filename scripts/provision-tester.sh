#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
: "${LAB_PASSWORD:?LAB_PASSWORD muss von Vagrant uebergeben werden}"

apt-get update -qq
apt-get install -y -qq openssh-client sshpass netcat-openbsd

if ! grep -q '^192\.168\.56\.10[[:space:]]\+security-server$' /etc/hosts; then
  printf '%s\n' '192.168.56.10 security-server' >> /etc/hosts
fi

install -d -m 0750 -o root -g vagrant /etc/defense-in-depth
printf '%s' "$LAB_PASSWORD" > /etc/defense-in-depth/lab-password
chown root:vagrant /etc/defense-in-depth/lab-password
chmod 0640 /etc/defense-in-depth/lab-password
unset LAB_PASSWORD

ssh -V
sshpass -V | head -n 1
