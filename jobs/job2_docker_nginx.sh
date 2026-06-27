#!/usr/bin/env bash
#
# JOB 2 - pull nginx, run it on host port 8351, curl it.
# Jenkins: "Execute shell" build step.
#
set -euo pipefail

HOST_PORT="${HOST_PORT:-8351}"

sudo docker pull nginx

# Run detached; container port 80 published to host $HOST_PORT.
cid="$(sudo docker run -d -p "${HOST_PORT}:80" nginx)"
echo "Started container: $cid"

# Give nginx a moment, then hit it via the host port.
sleep 2
echo "--- curl http://localhost:${HOST_PORT} ---"
sudo curl -s "http://localhost:${HOST_PORT}" | head -n 5

echo "Done."
