#!/usr/bin/env bats
#
# job15: EC2 provisioning. DRY_RUN prints the plan + base64 user-data and decodes
# it, proving IMDSv2 is required and the first-boot script hardens sshd — all
# without calling the aws CLI (stubbed to fail loudly if reached).

setup() {
  load 'helpers/load'
  make_stubs
}

@test "job15 DRY_RUN prints the plan with IMDSv2 required and calls no AWS" {
  run env DRY_RUN=1 bash "$JOBS_DIR/job15_aws_ec2_provision.sh"
  assert_success
  assert_output --partial "HttpTokens=required"
  assert_output --partial "Done: dry run."
  refute_output --partial "REAL aws called"
}

@test "job15 DRY_RUN decodes user-data that hardens sshd" {
  run env DRY_RUN=1 bash "$JOBS_DIR/job15_aws_ec2_provision.sh"
  assert_success
  assert_output --partial "--- decoded user-data ---"
  assert_output --partial "PasswordAuthentication"
  assert_output --partial "PermitRootLogin"
}

@test "job15 DRY_RUN honours region and instance-type overrides" {
  run env AWS_REGION="eu-west-1" INSTANCE_TYPE="t3.small" DRY_RUN=1 \
    bash "$JOBS_DIR/job15_aws_ec2_provision.sh"
  assert_success
  assert_output --partial "region=eu-west-1 type=t3.small"
}
