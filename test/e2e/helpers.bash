# Shared helpers for the black-box end-to-end suite (loaded via `load helpers`).
#
# The subject under test is parameterized via ASCIIDOCTOR_EXE (path to an
# executable file). It defaults to the Ruby CLI shim so the same suite can
# later run against the Dart executable via:
#
#   ASCIIDOCTOR_EXE=/path/to/asciidart bats test/e2e/

_e2e_dir="${BATS_TEST_DIRNAME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
case "$_e2e_dir" in
  /*) E2E_DIR="$_e2e_dir" ;;
  *) E2E_DIR="$(pwd)/$_e2e_dir" ;;
esac
unset _e2e_dir

: "${ASCIIDOCTOR_EXE:=${E2E_DIR}/bin/asciidoctor-ruby}"
case "$ASCIIDOCTOR_EXE" in
  /*) EXE="$ASCIIDOCTOR_EXE" ;;
  *) EXE="$(pwd)/$ASCIIDOCTOR_EXE" ;;
esac

# Fail fast (from setup_file) if the subject under test is missing.
# ASCIIDOCTOR_EXE must point at an executable file.
check_exe() {
  if [ ! -f "$EXE" ]; then
    echo "ASCIIDOCTOR_EXE is not a file: $EXE" >&2
    echo 'hint: export ASCIIDOCTOR_EXE=<path-to-executable> (default: test/e2e/bin/asciidoctor-ruby)' >&2
    return 1
  fi
  if [ ! -x "$EXE" ]; then
    echo "ASCIIDOCTOR_EXE is not executable: $EXE" >&2
    return 1
  fi
}

# Assert that file $1 contains the fixed string $2 (dumps file on failure).
assert_contains() {
  local file="$1" fragment="$2"
  if ! grep -F -q -- "$fragment" "$file"; then
    echo "expected $file to contain:"
    echo "  $fragment"
    echo 'actual content:'
    cat -- "$file"
    return 1
  fi
}

# Assert that file $1 contains the fixed string $2 as a whole, which may span
# lines (grep -F would match any one of its lines).
assert_contains_text() {
  local file="$1" fragment="$2" content
  content="$(cat -- "$file")"
  if [[ "$content" != *"$fragment"* ]]; then
    echo "expected $file to contain:"
    printf '%s\n' "$fragment"
    echo 'actual content:'
    printf '%s\n' "$content"
    return 1
  fi
}

# Assert that file $1 does not contain the fixed string $2.
assert_not_contains() {
  local file="$1" fragment="$2"
  if grep -F -q -- "$fragment" "$file"; then
    echo "expected $file NOT to contain:"
    echo "  $fragment"
    echo 'actual content:'
    cat -- "$file"
    return 1
  fi
}

# Assert that the bats-captured $output contains the fixed string $1.
assert_output_contains() {
  local fragment="$1"
  if ! grep -F -q -- "$fragment" <<< "$output"; then
    echo 'expected stdout to contain:'
    echo "  $fragment"
    echo 'actual stdout:'
    printf '%s\n' "$output"
    return 1
  fi
}

# Assert that the bats-captured $stderr contains the fixed string $1.
assert_stderr_contains() {
  local fragment="$1"
  if ! grep -F -q -- "$fragment" <<< "$stderr"; then
    echo 'expected stderr to contain:'
    echo "  $fragment"
    echo 'actual stderr:'
    printf '%s\n' "$stderr"
    return 1
  fi
}
