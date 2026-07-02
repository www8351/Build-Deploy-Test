# Shared bats setup: load assertion libraries and expose common paths + a PATH
# stub dir so tests never invoke real sudo/sshd/iptables/aws.
#
# bats-support / bats-assert are provided by bats-core/bats-action in CI, which
# sets BATS_LIB_PATH. bats_load_library resolves them from there.
bats_load_library bats-support
bats_load_library bats-assert

# Absolute path to the jobs/ dir regardless of where bats is invoked from.
JOBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../jobs" && pwd)"

# Build a stub dir of no-op system tools and prepend it to PATH. If any of these
# is actually reached in a dry-run/idempotency test, that is a bug we want to
# catch — so the "must never run" ones (iptables-restore, aws) exit non-zero.
make_stubs() {
  local dir="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nexec "$@"\n'  > "$dir/sudo"        # transparent
  printf '#!/usr/bin/env bash\nexit 0\n'      > "$dir/sshd"        # sshd -t OK
  printf '#!/usr/bin/env bash\nexit 0\n'      > "$dir/systemctl"   # reload OK
  printf '#!/usr/bin/env bash\necho "REAL iptables-restore called" >&2\nexit 99\n' > "$dir/iptables-restore"
  printf '#!/usr/bin/env bash\necho "REAL aws called" >&2\nexit 99\n'              > "$dir/aws"
  chmod +x "$dir"/*
  PATH="$dir:$PATH"
}
