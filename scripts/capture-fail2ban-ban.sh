#!/usr/bin/env bash
set -euo pipefail

tester_ip=${1:-192.168.56.20}
evidence_file=${2:-/vagrant/evidence/current/T05-ban-status.txt}

install -d -m 0755 "$(dirname "$evidence_file")"
exec >"$evidence_file" 2>&1

for _ in $(seq 1 40); do
  status=$(fail2ban-client status sshd)
  if grep -Fq "$tester_ip" <<<"$status"; then
    printf '%s\n' "$status"
    printf '%s\n' '=== nftables ==='
    nft list ruleset
    exit 0
  fi
  sleep 0.5
done

printf 'Kein aktiver Ban fuer %s innerhalb des Zeitfensters.\n' "$tester_ip" >&2
fail2ban-client status sshd >&2
exit 1
