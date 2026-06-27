#!/usr/bin/env bash
#
# JOB 6 - send an "it's all good" mail at the end of the pipeline.
# Jenkins: "Execute shell" build step. RECIPIENT is a job parameter.
#
# NOTE: the production path is Jenkins' "Editable Email Notification"
# (email-ext) post-build step, configured with your SMTP server. This script
# is the CLI fallback using mail/mailx (needs a configured MTA on the agent).
#
set -euo pipefail

RECIPIENT="${RECIPIENT:?set RECIPIENT (email address)}"
SUBJECT="${SUBJECT:-Pipeline OK}"
BODY="${BODY:-All good - all jobs finished successfully.}"

if command -v mail >/dev/null 2>&1; then
  printf '%s\n' "$BODY" | mail -s "$SUBJECT" "$RECIPIENT"
  echo "Mail sent to $RECIPIENT via mail."
elif command -v mailx >/dev/null 2>&1; then
  printf '%s\n' "$BODY" | mailx -s "$SUBJECT" "$RECIPIENT"
  echo "Mail sent to $RECIPIENT via mailx."
else
  echo "No mail/mailx on agent. Use Jenkins Editable Email Notification instead." >&2
  exit 1
fi
