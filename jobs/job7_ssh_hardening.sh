#!/usr/bin/env bash
#
# JOB 7 - harden the OpenSSH daemon by rewriting sshd_config idempotently.
# Jenkins: "Execute shell" build step. Runs on a Linux agent as root/sudo.
#   SSHD_CONFIG    - path to sshd_config        (default: /etc/ssh/sshd_config)
#   MAX_AUTH_TRIES - MaxAuthTries value         (default: 3)
#   KEX            - KexAlgorithms value         (default: modern curve25519 set)
#   SSHD_SERVICE   - service name to reload      (default: sshd; Debian uses ssh)
#
# Safe by design: backs up the config, validates with `sshd -t` BEFORE reloading,
# and a trap auto-restores the backup if anything fails, so a bad edit can never
# leave you locked out. Re-running is a no-op (directives are set-in-place).
#
set -Eeuo pipefail

SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
MAX_AUTH_TRIES="${MAX_AUTH_TRIES:-3}"
KEX="${KEX:-curve25519-sha256,curve25519-sha256@libssh.org}"
SSHD_SERVICE="${SSHD_SERVICE:-sshd}"

BACKUP=""

# Restore the original config if we exit non-zero after taking the backup.
cleanup() {
  local rc=$?
  if [ -n "$BACKUP" ] && [ -f "$BACKUP" ] && [ "$rc" -ne 0 ]; then
    echo "ERROR (rc=$rc): restoring $SSHD_CONFIG from $BACKUP" >&2
    sudo cp -f -- "$BACKUP" "$SSHD_CONFIG" || true
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "ERR: failed at line $LINENO" >&2' ERR

# set_directive KEY VALUE - force "KEY VALUE" in $SSHD_CONFIG, idempotently.
# Replaces an existing (even commented-out) line in place, else appends one.
set_directive() {
  local key="$1" val="$2"
  if sudo grep -qiE "^[[:space:]]*#?[[:space:]]*${key}\b" "$SSHD_CONFIG"; then
    sudo sed -ri "s|^[[:space:]]*#?[[:space:]]*(${key})\b.*|\1 ${val}|I" "$SSHD_CONFIG"
  else
    printf '%s %s\n' "$key" "$val" | sudo tee -a "$SSHD_CONFIG" >/dev/null
  fi
}

[ -f "$SSHD_CONFIG" ] || { echo "No sshd_config at $SSHD_CONFIG" >&2; exit 1; }

# Timestamped backup before touching anything.
BACKUP="${SSHD_CONFIG}.bak.$(date +%s)"
sudo cp -f -- "$SSHD_CONFIG" "$BACKUP"
echo "Backup: $BACKUP"

# Enforce the hardening baseline.
set_directive "PermitRootLogin"        "no"
set_directive "PasswordAuthentication" "no"
set_directive "X11Forwarding"          "no"
set_directive "AllowTcpForwarding"     "no"
set_directive "MaxAuthTries"           "$MAX_AUTH_TRIES"
set_directive "KexAlgorithms"          "$KEX"

# Validate the rewritten config BEFORE we reload the daemon.
echo "--- sshd -t validation ---"
sudo sshd -t -f "$SSHD_CONFIG"

# Reload only after validation passed. Skip cleanly where systemctl is absent.
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl reload "$SSHD_SERVICE" 2>/dev/null \
    || sudo systemctl restart "$SSHD_SERVICE"
  echo "Reloaded $SSHD_SERVICE."
else
  echo "systemctl not found; config validated but daemon not reloaded." >&2
fi

echo "Done: sshd hardened; backup at $BACKUP"
