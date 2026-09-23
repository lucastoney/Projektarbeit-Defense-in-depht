#!/usr/bin/env bash
set -euo pipefail

test_file=/opt/defense-in-depth/monitored/demo.txt
printf 'Auditd-Demo %s\n' "$(date --iso-8601=seconds)" >> "$test_file"
sleep 1
ausearch -k did_demo -ts recent -i | tail -n 30
