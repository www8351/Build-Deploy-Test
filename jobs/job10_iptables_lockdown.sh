#!/usr/bin/env bash
#
# JOB 10 - lock the host down with a default-DROP iptables ruleset.
# Jenkins: "Execute shell" build step. Runs on a Linux agent as root/sudo.
#   SSH_PORT  - inbound SSH port to keep open   (default: 22)
#   APP_PORT  - inbound app port to keep open   (default: 8351, Nginx)
#   LOG_LIMIT - rate limit for dropped-packet log (default: 5/min)
#   DRY_RUN   - if set, print the ruleset and exit without applying
#
# Applies atomically via `iptables-restore` (whole table swapped at once, no
# half-open window). Default policy is DROP on INPUT/FORWARD/OUTPUT; only
# loopback, established/related, and the two named ingress ports are allowed.
# Dropped inbound packets are logged with a rate limit so a flood cannot fill
# the disk. WARNING: egress is locked to established/related — outbound DNS and
# package updates need an explicit rule added before enabling on a live box.
#
set -Eeuo pipefail

SSH_PORT="${SSH_PORT:-22}"
APP_PORT="${APP_PORT:-8351}"
LOG_LIMIT="${LOG_LIMIT:-5/min}"
DRY_RUN="${DRY_RUN:-}"

RULES_FILE=""

# Remove the temp ruleset on any exit.
cleanup() {
  local rc=$?
  [ -n "$RULES_FILE" ] && [ -f "$RULES_FILE" ] && rm -f -- "$RULES_FILE"
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "ERR: failed at line $LINENO" >&2' ERR

RULES_FILE="$(mktemp)"
cat > "$RULES_FILE" <<RULES
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
# loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
# keep existing / return traffic
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# strictly defined ingress ports
-A INPUT -p tcp --dport ${SSH_PORT} -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport ${APP_PORT} -m conntrack --ctstate NEW -j ACCEPT
# rate-limited log of anything still headed for the DROP policy
-A INPUT -m limit --limit ${LOG_LIMIT} -j LOG --log-prefix "iptables-drop-in: " --log-level 4
COMMIT
RULES

if [ -n "$DRY_RUN" ]; then
  echo "--- DRY_RUN: iptables-restore input ---"
  cat "$RULES_FILE"
  echo "Done: dry run, no rules applied."
  exit 0
fi

command -v iptables-restore >/dev/null 2>&1 || {
  echo "iptables-restore not found (Linux only)." >&2
  exit 1
}

# pass the file as an argument (no redirect, no cat) so it works under sudo and
# stays lint-clean.
sudo iptables-restore "$RULES_FILE"
echo "Done: firewall locked down (SSH ${SSH_PORT}, app ${APP_PORT} open; default DROP)."
