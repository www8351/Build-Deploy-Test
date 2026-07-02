#!/usr/bin/env bash
#
# JOB 8 - scan a container image for CVEs with Trivy and gate deployment.
# Jenkins: "Execute shell" build step. Runs on a Linux agent.
#   IMAGE     - image to scan                 (default: nginx)
#   SEVERITY  - severities to report          (default: HIGH,CRITICAL)
#   THRESHOLD - max vulns allowed before fail (default: 0)
#   REPORT    - JSON report path (CWD)         (default: trivy_report.json)
#
# Writes a structured JSON report and exits non-zero when the count of matching
# vulnerabilities exceeds THRESHOLD, so a downstream deploy stage is blocked.
# Uses a local `trivy` binary if present, otherwise the aquasec/trivy container.
#
set -Eeuo pipefail

IMAGE="${IMAGE:-nginx}"
SEVERITY="${SEVERITY:-HIGH,CRITICAL}"
THRESHOLD="${THRESHOLD:-0}"
REPORT="${REPORT:-trivy_report.json}"
TRIVY_IMAGE_TAG="${TRIVY_IMAGE_TAG:-aquasec/trivy:latest}"

# Drop a partial/empty report if we bailed before Trivy finished writing it.
# A threshold-exceed exit keeps its (non-empty) report on purpose.
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -f "$REPORT" ] && [ ! -s "$REPORT" ]; then
    rm -f -- "$REPORT"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'echo "ERR: failed at line $LINENO" >&2' ERR

# run_trivy ARGS... - local binary preferred, dockerised fallback.
run_trivy() {
  if command -v trivy >/dev/null 2>&1; then
    trivy "$@"
  else
    sudo docker run --rm -v trivy-cache:/root/.cache/ "$TRIVY_IMAGE_TAG" "$@"
  fi
}

# count_vulns REPORT - number of vulnerabilities in the JSON, or "" if no parser.
count_vulns() {
  local report="$1"
  if command -v jq >/dev/null 2>&1; then
    jq '[.Results[]?.Vulnerabilities[]?] | length' "$report"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$report" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(len(r.get("Vulnerabilities") or []) for r in (data.get("Results") or [])))
PY
  else
    echo ""
  fi
}

if ! command -v trivy >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
  echo "Need either 'trivy' or 'docker' on the agent." >&2
  exit 1
fi

echo "--- trivy scan: $IMAGE (severity $SEVERITY) ---"
run_trivy image --severity "$SEVERITY" --format json --quiet "$IMAGE" > "$REPORT"
echo "Report: $(pwd)/$REPORT"

count="$(count_vulns "$REPORT")"

# No JSON parser available: fall back to Trivy's own pass/fail gate.
if [ -z "$count" ]; then
  echo "jq/python3 not found; using trivy --exit-code gate (any $SEVERITY vuln fails)." >&2
  run_trivy image --severity "$SEVERITY" --exit-code 1 --quiet "$IMAGE" >/dev/null
  echo "Done: no $SEVERITY vulnerabilities in $IMAGE."
  exit 0
fi

echo "Found $count $SEVERITY vulnerabilities (threshold: $THRESHOLD)."
if [ "$count" -gt "$THRESHOLD" ]; then
  echo "Vulnerability count exceeds threshold — blocking deployment." >&2
  exit 1
fi

echo "Done: $IMAGE within threshold; report at $(pwd)/$REPORT"
