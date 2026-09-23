#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

: "${LAB_PASSWORD:?LAB_PASSWORD muss von Vagrant uebergeben werden}"

apt-get update -qq
apt-get install -y -qq \
  openssh-server fail2ban nftables rsyslog auditd audispd-plugins aide \
  netcat-openbsd

install -d -m 0755 -o root -g root /opt/defense-in-depth/monitored
if [[ ! -e /opt/defense-in-depth/monitored/demo.txt ]]; then
  printf '%s\n' 'Unveraenderte AIDE-Baseline' | \
    install -m 0644 -o root -g root /dev/stdin \
      /opt/defense-in-depth/monitored/demo.txt
fi

if ! id -u labuser >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash labuser
fi
printf 'labuser:%s\n' "$LAB_PASSWORD" | chpasswd
unset LAB_PASSWORD

install -m 0644 /vagrant/config/nftables.conf /etc/nftables.conf
nft --check --file /etc/nftables.conf
systemctl enable --now nftables
systemctl restart nftables

install -m 0644 /vagrant/config/rsyslog-defense-in-depth.conf \
  /etc/rsyslog.d/30-defense-in-depth.conf
rsyslogd -N1
systemctl enable --now rsyslog
systemctl restart rsyslog

rm -f /etc/ssh/sshd_config.d/99-defense-in-depth.conf
install -d -m 0755 /run/sshd
if ! cmp -s /vagrant/config/sshd-hardening.conf \
  /etc/ssh/sshd_config.d/00-defense-in-depth.conf; then
  install -m 0644 /vagrant/config/sshd-hardening.conf \
    /etc/ssh/sshd_config.d/00-defense-in-depth.conf
fi
/usr/sbin/sshd -t
systemctl enable --now ssh
systemctl restart ssh

install -m 0644 /vagrant/config/sshd-jail.local \
  /etc/fail2ban/jail.d/sshd-lab.local
install -m 0644 /vagrant/config/fail2ban.local \
  /etc/fail2ban/fail2ban.local
fail2ban-client -t
systemctl enable fail2ban
systemctl restart fail2ban
sleep 3
fail2ban-client ping
fail2ban-client status sshd

install -m 0640 /vagrant/config/audit.rules \
  /etc/audit/rules.d/50-defense-in-depth.rules
augenrules --check
augenrules --load
systemctl enable auditd
service auditd restart
auditctl -s

install -m 0644 /vagrant/config/aide.conf \
  /etc/aide/defense-in-depth.conf
if [[ ! -s /var/lib/aide/defense-in-depth.db.gz ]]; then
  aide --config /etc/aide/defense-in-depth.conf --init
  test -s /var/lib/aide/defense-in-depth.db.new.gz
  mv /var/lib/aide/defense-in-depth.db.new.gz \
    /var/lib/aide/defense-in-depth.db.gz
fi

install -m 0755 /vagrant/scripts/security-test.sh \
  /usr/local/sbin/security-test
install -m 0755 /vagrant/scripts/demo-auditd.sh \
  /usr/local/sbin/demo-auditd
install -m 0755 /vagrant/scripts/demo-aide.sh \
  /usr/local/sbin/demo-aide
install -m 0755 /vagrant/scripts/reset-aide-baseline.sh \
  /usr/local/sbin/reset-aide-baseline
install -m 0755 /vagrant/scripts/capture-fail2ban-ban.sh \
  /usr/local/sbin/capture-fail2ban-ban

/usr/local/sbin/security-test
