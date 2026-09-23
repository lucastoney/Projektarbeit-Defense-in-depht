#!/usr/bin/env bash
set -euo pipefail

config=/etc/aide/defense-in-depth.conf
new_database=/var/lib/aide/defense-in-depth.db.new.gz
database=/var/lib/aide/defense-in-depth.db.gz

rm -f "$new_database"
aide --config "$config" --init
test -s "$new_database"
mv "$new_database" "$database"
printf '%s\n' 'AIDE-Baseline wurde kontrolliert neu erstellt.'
