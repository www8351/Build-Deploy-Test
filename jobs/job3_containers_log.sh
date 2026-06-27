#!/usr/bin/env bash
#
# JOB 3 - save every container's ID, Image, Name, IP into Log.txt.
# Jenkins: "Execute shell" build step.
#
set -euo pipefail

LOG="Log.txt"
: > "$LOG"   # truncate / create

printf "%-14s %-20s %-20s %-16s\n" "ID" "IMAGE" "NAME" "IP" | tee "$LOG"
printf '%s\n' "-------------------------------------------------------------------------" | tee -a "$LOG"

for id in $(sudo docker ps -q); do
  line="$(sudo docker inspect --format \
    '{{printf "%.12s" .Id}} {{.Config.Image}} {{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
    "$id")"
  # shellcheck disable=SC2086
  set -- $line
  printf "%-14s %-20s %-20s %-16s\n" "${1:-}" "${2:-}" "${3:-}" "${4:-}" | tee -a "$LOG"
done

echo "Wrote container info to $(pwd)/$LOG"
