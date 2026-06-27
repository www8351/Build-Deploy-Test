#!/usr/bin/env bash
#
# JOB 5 - deploy 3 containers and print each container's IP.
# Jenkins: "Execute shell" build step.
#
set -euo pipefail

IMAGE="${IMAGE:-nginx}"
COUNT="${COUNT:-3}"

sudo docker pull "$IMAGE"

echo "Deploying $COUNT '$IMAGE' containers ..."
for i in $(seq 1 "$COUNT"); do
  name="web${i}"
  sudo docker rm -f "$name" >/dev/null 2>&1 || true
  sudo docker run -d --name "$name" "$IMAGE" >/dev/null
done

echo "--- Container IPs ---"
for i in $(seq 1 "$COUNT"); do
  name="web${i}"
  ip="$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")"
  printf "%-8s %s\n" "$name" "$ip"
done

echo "Done."
