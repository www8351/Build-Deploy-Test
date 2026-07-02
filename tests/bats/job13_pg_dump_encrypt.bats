#!/usr/bin/env bats
#
# job13: encrypted pg_dump. Verifies the required-var guard and that DRY_RUN
# prints the streamed pg_dump|zstd|gpg pipeline without dumping anything.

setup() {
  load 'helpers/load'
  make_stubs
}

@test "job13 fails when GPG_RECIPIENT is unset" {
  run bash "$JOBS_DIR/job13_pg_dump_encrypt.sh"
  assert_failure
  assert_output --partial "set GPG_RECIPIENT"
}

@test "job13 DRY_RUN prints the streamed encrypt pipeline" {
  run env GPG_RECIPIENT="me@example.com" DRY_RUN=1 bash "$JOBS_DIR/job13_pg_dump_encrypt.sh"
  assert_success
  assert_output --partial 'pg_dump "postgres"'
  assert_output --partial 'zstd -T0 -19 -c'
  assert_output --partial 'gpg --encrypt --recipient "me@example.com"'
  assert_output --partial "Done: dry run, nothing dumped."
}

@test "job13 DRY_RUN honours PGDATABASE and ZSTD_LEVEL overrides" {
  run env GPG_RECIPIENT="me@example.com" PGDATABASE="app" ZSTD_LEVEL=9 DRY_RUN=1 \
    bash "$JOBS_DIR/job13_pg_dump_encrypt.sh"
  assert_success
  assert_output --partial 'pg_dump "app"'
  assert_output --partial 'zstd -T0 -9 -c'
}
