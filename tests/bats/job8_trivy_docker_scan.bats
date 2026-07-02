#!/usr/bin/env bats
#
# job8: Trivy CVE scan gate. A stub `trivy` emits a canned JSON report (fixtures/)
# so we can assert the threshold gate blocks/passes deployment without pulling a
# real image or running a real scanner. count_vulns uses jq/python3 (present in CI).

setup() {
  load 'helpers/load'
  make_stubs
  # trivy stub: print the fixture named by $FAKE_TRIVY_REPORT for any invocation.
  printf '#!/usr/bin/env bash\ncat "$FAKE_TRIVY_REPORT"\n' > "$BATS_TEST_TMPDIR/stub/trivy"
  chmod +x "$BATS_TEST_TMPDIR/stub/trivy"

  FIX="$BATS_TEST_DIRNAME/fixtures"
  REPORT="$BATS_TEST_TMPDIR/report.json"
  SBOM="$BATS_TEST_TMPDIR/sbom.json"
}

@test "job8 passes when vuln count is within threshold" {
  run env FAKE_TRIVY_REPORT="$FIX/trivy_2vulns.json" \
    IMAGE=nginx SEVERITY=HIGH,CRITICAL THRESHOLD=999 SBOM_FORMAT=none \
    REPORT="$REPORT" bash "$JOBS_DIR/job8_trivy_docker_scan.sh"
  assert_success
  assert_output --partial "Found 2 HIGH,CRITICAL vulnerabilities (threshold: 999)."
  assert_output --partial "within threshold"
  [ -s "$REPORT" ]
}

@test "job8 blocks deployment when count exceeds threshold and keeps the report" {
  run env FAKE_TRIVY_REPORT="$FIX/trivy_2vulns.json" \
    IMAGE=nginx THRESHOLD=0 SBOM_FORMAT=none \
    REPORT="$REPORT" bash "$JOBS_DIR/job8_trivy_docker_scan.sh"
  assert_failure
  assert_output --partial "exceeds threshold"
  # A threshold-exceed keeps its non-empty report as evidence.
  [ -s "$REPORT" ]
}

@test "job8 blocks when count is just over a non-zero threshold" {
  run env FAKE_TRIVY_REPORT="$FIX/trivy_2vulns.json" \
    THRESHOLD=1 SBOM_FORMAT=none REPORT="$REPORT" \
    bash "$JOBS_DIR/job8_trivy_docker_scan.sh"
  assert_failure
}

@test "job8 passes a clean image at threshold 0" {
  run env FAKE_TRIVY_REPORT="$FIX/trivy_0vulns.json" \
    THRESHOLD=0 SBOM_FORMAT=none REPORT="$REPORT" \
    bash "$JOBS_DIR/job8_trivy_docker_scan.sh"
  assert_success
  assert_output --partial "Found 0 HIGH,CRITICAL vulnerabilities"
}

@test "job8 emits an SBOM as evidence before the gate" {
  run env FAKE_TRIVY_REPORT="$FIX/trivy_2vulns.json" \
    THRESHOLD=999 SBOM_FORMAT=cyclonedx SBOM_FILE="$SBOM" \
    REPORT="$REPORT" bash "$JOBS_DIR/job8_trivy_docker_scan.sh"
  assert_success
  assert_output --partial "--- SBOM: cyclonedx ---"
  [ -s "$SBOM" ]
}
