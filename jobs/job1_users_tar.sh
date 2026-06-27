#!/usr/bin/env bash
#
# JOB 1 - create a user, make 5 files, tar them.
# Jenkins: "Execute shell" build step. USER is a job parameter (default: tester1).
#
set -euo pipefail

USER_NAME="${USER_NAME:-tester1}"

# Create the user and add to sudo group (idempotent - ignore "already exists").
sudo useradd -m "$USER_NAME" 2>/dev/null || echo "User '$USER_NAME' already exists, continuing."
sudo usermod -aG sudo "$USER_NAME" 2>/dev/null || true
sudo mkdir -p /home/"$USER_NAME"

# Make 5 files and archive them.
touch 1.txt 2.txt 3.txt 4.txt 5.txt
tar -zcvf zipfile.tgz 1.txt 2.txt 3.txt 4.txt 5.txt

echo "Done: user '$USER_NAME' ready, files archived to zipfile.tgz"
ls -l zipfile.tgz
