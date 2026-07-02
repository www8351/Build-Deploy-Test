#!/usr/bin/env bash
#
# JOB 13 - encrypted PostgreSQL logical backup.
# Jenkins: "Execute shell" build step. Runs on a Linux agent.
#   GPG_RECIPIENT      - key id / email to encrypt to        (required)
#   PGDATABASE         - database to dump                    (default: postgres)
#   OUT_DIR            - output directory                    (default: .)
#   ZSTD_LEVEL         - zstd compression level              (default: 19)
#   RECIPIENT_KEY_FILE - if set, import this pubkey into a   (default: unset)
#                        throwaway keyring, shredded on exit
#   DRY_RUN            - if set, print the pipeline and exit
#
# Streams pg_dump -> zstd -> gpg with NO unencrypted intermediate file: the
# plaintext dump never touches disk. Standard libpq env vars (PGHOST, PGUSER,
# PGPASSWORD, ...) are honoured by pg_dump. A trap shreds any temporary keyring
# created for the recipient key before exit.
#
set -Eeuo pipefail

GPG_RECIPIENT="${GPG_RECIPIENT:?set GPG_RECIPIENT (key id or email)}"
PGDATABASE="${PGDATABASE:-postgres}"
OUT_DIR="${OUT_DIR:-.}"
ZSTD_LEVEL="${ZSTD_LEVEL:-19}"
RECIPIENT_KEY_FILE="${RECIPIENT_KEY_FILE:-}"
DRY_RUN="${DRY_RUN:-}"

WORKDIR=""

# Shred any throwaway keyring material, then drop the temp dir. Runs on any exit.
cleanup() {
  local rc=$?
  if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
    find "$WORKDIR" -type f -exec shred -u {} + 2>/dev/null || true
    rm -rf -- "$WORKDIR"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "ERR: failed at line $LINENO" >&2' ERR

OUTFILE="${OUT_DIR%/}/${PGDATABASE}_$(date +%Y%m%d%H%M%S).sql.zst.gpg"

GPG=(gpg --batch --yes --trust-model always)

# Optional isolated keyring: import the recipient pubkey into a temp GNUPGHOME
# that the trap will shred, so no key material is left on the agent.
if [ -n "$RECIPIENT_KEY_FILE" ]; then
  WORKDIR="$(mktemp -d)"
  chmod 700 "$WORKDIR"
  export GNUPGHOME="$WORKDIR"
  "${GPG[@]}" --import "$RECIPIENT_KEY_FILE"
fi

if [ -n "$DRY_RUN" ]; then
  echo "pg_dump \"$PGDATABASE\" | zstd -T0 -${ZSTD_LEVEL} -c | gpg --encrypt --recipient \"$GPG_RECIPIENT\" --output \"$OUTFILE\""
  echo "Done: dry run, nothing dumped."
  exit 0
fi

for bin in pg_dump zstd gpg; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found." >&2; exit 1; }
done

# Streamed pipeline; pipefail makes a failure in any stage abort the whole job.
pg_dump "$PGDATABASE" \
  | zstd -T0 "-${ZSTD_LEVEL}" -c \
  | "${GPG[@]}" --encrypt --recipient "$GPG_RECIPIENT" --output "$OUTFILE"

echo "Done: encrypted backup at $OUTFILE"
