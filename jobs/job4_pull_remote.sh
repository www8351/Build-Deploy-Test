#!/usr/bin/env bash
#
# JOB 4 - pull a docker image onto ANOTHER machine over SSH.
# Jenkins: "Execute shell" build step. Set these as job parameters / credentials:
#   REMOTE_HOST  - target host/IP        (required)
#   REMOTE_USER  - ssh user              (default: root)
#   IMAGE        - image to pull         (default: nginx)
# The Jenkins agent must have key-based SSH access to REMOTE_HOST.
#
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:?set REMOTE_HOST (target machine)}"
REMOTE_USER="${REMOTE_USER:-root}"
IMAGE="${IMAGE:-nginx}"

echo "Pulling '$IMAGE' on ${REMOTE_USER}@${REMOTE_HOST} ..."
ssh -o StrictHostKeyChecking=accept-new "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo docker pull '${IMAGE}' && sudo docker images '${IMAGE}'"

echo "Done: '$IMAGE' pulled on $REMOTE_HOST."
