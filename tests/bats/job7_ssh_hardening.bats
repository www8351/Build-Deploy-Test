#!/usr/bin/env bats
#
# job7: sshd hardening. Verifies idempotent set_directive (no duplicate lines on
# re-run) + a backup is taken + the missing-config guard. Real sudo/sshd/systemctl
# are stubbed; nothing on the host is touched.

setup() {
  load 'helpers/load'
  make_stubs
  CFG="$BATS_TEST_TMPDIR/sshd_config"
  printf '#Port 22\nPermitRootLogin yes\n#PasswordAuthentication yes\n' > "$CFG"
}

@test "job7 rewrites directives and is idempotent across two runs" {
  run env SSHD_CONFIG="$CFG" bash "$JOBS_DIR/job7_ssh_hardening.sh"
  assert_success
  run env SSHD_CONFIG="$CFG" bash "$JOBS_DIR/job7_ssh_hardening.sh"
  assert_success

  # Exactly one hardened line each — replaced in place, never appended twice.
  run grep -c '^PermitRootLogin no' "$CFG"
  assert_output "1"
  run grep -c '^PasswordAuthentication no' "$CFG"
  assert_output "1"
}

@test "job7 takes a timestamped backup" {
  run env SSHD_CONFIG="$CFG" bash "$JOBS_DIR/job7_ssh_hardening.sh"
  assert_success
  run bash -c "ls '$CFG'.bak.* | wc -l"
  assert_output --regexp '[1-9]'
}

@test "job7 fails cleanly when the config is missing" {
  run env SSHD_CONFIG="$BATS_TEST_TMPDIR/nope" bash "$JOBS_DIR/job7_ssh_hardening.sh"
  assert_failure
  assert_output --partial "No sshd_config"
}
