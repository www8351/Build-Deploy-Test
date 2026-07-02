#!/usr/bin/env bats
#
# job10: iptables lockdown. DRY_RUN renders the default-DROP ruleset without ever
# calling iptables-restore (stubbed to fail loudly if reached).

setup() {
  load 'helpers/load'
  make_stubs
}

@test "job10 DRY_RUN renders the default-DROP ruleset and applies nothing" {
  run env DRY_RUN=1 bash "$JOBS_DIR/job10_iptables_lockdown.sh"
  assert_success
  assert_output --partial "--- DRY_RUN: iptables-restore input ---"
  assert_output --partial ":INPUT DROP [0:0]"
  assert_output --partial "COMMIT"
  assert_output --partial "Done: dry run, no rules applied."
  refute_output --partial "REAL iptables-restore called"
}

@test "job10 DRY_RUN honours SSH_PORT and APP_PORT overrides" {
  run env DRY_RUN=1 SSH_PORT=2222 APP_PORT=9000 bash "$JOBS_DIR/job10_iptables_lockdown.sh"
  assert_success
  assert_output --partial "--dport 2222 -m conntrack --ctstate NEW -j ACCEPT"
  assert_output --partial "--dport 9000 -m conntrack --ctstate NEW -j ACCEPT"
}
