#!/usr/bin/env bash
set -euo pipefail

test_file=/opt/defense-in-depth/monitored/demo.txt
printf 'AIDE-Demo %s\n' "$(date --iso-8601=seconds)" >> "$test_file"
set +e
aide --config /etc/aide/defense-in-depth.conf --check
result=$?
set -e

if [[ $result -eq 0 ]]; then
  printf '%s\n' 'FEHLER: AIDE hat die kontrollierte Aenderung nicht erkannt.' >&2
  exit 1
fi
printf '%s\n' 'ERFOLG: AIDE hat die kontrollierte Aenderung erkannt.'
