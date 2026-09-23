#!/usr/bin/env bash
set -u

passed=0
failed=0

pass() { printf '[PASS] %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; failed=$((failed + 1)); }
check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}
sshd_value() { /usr/sbin/sshd -T 2>/dev/null | grep -Eq "^$1 $2$"; }

printf '%s\n' '========================================'
printf '%s\n' ' DEFENSE IN DEPTH - SECURITY VALIDATION'
printf '%s\n' '========================================'
printf '\n'

check 'SSH laeuft' systemctl is-active --quiet ssh
check 'nftables ist aktiv' systemctl is-active --quiet nftables
if nft list chain inet defense_in_depth input 2>/dev/null | grep -q 'policy drop'; then
  pass 'Firewall INPUT-Policy ist drop'
else
  fail 'Firewall INPUT-Policy ist drop'
fi
if sshd_value permitrootlogin no && sshd_value permitemptypasswords no && \
   sshd_value x11forwarding no && sshd_value maxauthtries 3; then
  pass 'SSH-Hardening ist wirksam'
else
  fail 'SSH-Hardening ist wirksam'
fi
check 'Fail2ban laeuft' systemctl is-active --quiet fail2ban
check 'SSH-Jail ist aktiv' fail2ban-client status sshd
check 'Auditd laeuft' systemctl is-active --quiet auditd
if auditctl -l 2>/dev/null | grep -Eq '(-k did_demo|key=did_demo)'; then
  pass 'Audit-Regel did_demo ist geladen'
else
  fail 'Audit-Regel did_demo ist geladen'
fi
check 'AIDE ist verfuegbar' aide --version
if aide --config /etc/aide/defense-in-depth.conf --check >/tmp/aide-security-test.log 2>&1; then
  pass 'AIDE-Baseline ist unveraendert'
else
  fail 'AIDE meldet eine Abweichung (Details: /tmp/aide-security-test.log)'
fi

total=$((passed + failed))
printf '\n%d/%d Pruefungen bestanden\n' "$passed" "$total"
[[ $failed -eq 0 ]]
