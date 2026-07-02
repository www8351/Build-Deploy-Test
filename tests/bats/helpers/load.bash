# Shared bats setup. Self-contained: instead of depending on bats-support /
# bats-assert (whose BATS_LIB_PATH resolution is environment-fragile), we define
# the small subset of assertions we use in plain bash on top of bats' built-in
# $status / $output. This keeps the shell suite hermetic across machines and CI.

# Absolute path to the jobs/ dir regardless of where bats is invoked from.
JOBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../jobs" && pwd)"

# Build a stub dir of no-op system tools and prepend it to PATH. The "must never
# run" tools (iptables-restore, aws) exit non-zero and print a marker so a test
# that reaches a real system call is caught.
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

# --- assertion shim (bats-assert-compatible subset) --------------------------

assert_success() {
  if [ "$status" -ne 0 ]; then
    echo "expected success, got exit $status; output:" >&2
    echo "$output" >&2
    return 1
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    echo "expected failure, got exit 0; output:" >&2
    echo "$output" >&2
    return 1
  fi
}

# assert_output [--partial|--regexp] <expected>   (default: exact match)
assert_output() {
  local mode=exact
  case "$1" in
    --partial) mode=partial; shift ;;
    --regexp)  mode=regexp;  shift ;;
  esac
  local expected="$1"
  case "$mode" in
    exact)
      [ "$output" = "$expected" ] && return 0 ;;
    partial)
      [[ "$output" == *"$expected"* ]] && return 0 ;;
    regexp)
      [[ "$output" =~ $expected ]] && return 0 ;;
  esac
  echo "assert_output ($mode) failed; expected: $expected" >&2
  echo "actual output: $output" >&2
  return 1
}

# refute_output --partial <needle>   (fails if the needle IS present)
refute_output() {
  local mode=partial
  case "$1" in
    --partial) mode=partial; shift ;;
  esac
  local needle="$1"
  if [[ "$output" == *"$needle"* ]]; then
    echo "refute_output failed; did not expect: $needle" >&2
    echo "actual output: $output" >&2
    return 1
  fi
}
