#!/usr/bin/env bats
# Black-box CLI cases for safe modes, base dir, logging, and diagnostics:
# -S/--safe-mode, --safe, -B/--base-dir, --log-level, --failure-level,
# -q/--quiet, -v/--verbose, --trace, -t/--timings.
# Mirrors the corresponding coverage in test/invoker_test.rb.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "safe mode defaults to unsafe and allows ancestor includes" {
  mkdir -p sub
  printf 'OUTSIDE CONTENT\n' > outside.adoc
  cat > sub/doc.adoc <<'EOF'
before

include::../outside.adoc[]

after
EOF
  run --separate-stderr -- "$EXE" -e -o - sub/doc.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>OUTSIDE CONTENT</p>'
}

@test "safe mode blocks includes above the jail" {
  mkdir -p sub
  printf 'OUTSIDE CONTENT\n' > outside.adoc
  cat > sub/doc.adoc <<'EOF'
before

include::../outside.adoc[]

after
EOF
  run --separate-stderr -- "$EXE" -e -S safe -o - sub/doc.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_stderr_contains 'illegal reference to ancestor of jail'
  assert_stderr_contains 'include file not found'
  assert_contains actual.html 'Unresolved directive in doc.adoc - include::../outside.adoc[]'
  assert_not_contains actual.html 'OUTSIDE CONTENT'
}

@test "secure safe mode leaves include directives unprocessed" {
  printf 'SIBLING CONTENT\n' > sibling.adoc
  cat > doc.adoc <<'EOF'
before

include::sibling.adoc[]
EOF
  run --separate-stderr -- "$EXE" -e -S secure -o - doc.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html 'SIBLING CONTENT'
  assert_contains actual.html 'class="bare include"'
}

@test "all named safe modes are accepted" {
  printf 'content\n' > input.adoc
  for mode in unsafe safe server secure; do
    run --separate-stderr -- "$EXE" -S "$mode" -o "out-$mode.html" input.adoc
    [ "$status" -eq 0 ] || { echo "safe mode $mode failed with status $status: $stderr"; return 1; }
  done
}

@test "legacy safe flag is accepted" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" --safe -o out.html input.adoc
  [ "$status" -eq 0 ]
  [ -f out.html ]
}

@test "base dir resolves includes when reading from stdin" {
  mkdir -p base
  printf 'INCLUDED VIA BASEDIR\n' > base/inc.adoc
  printf 'include::inc.adoc[]\n' > stdin.adoc
  run --separate-stderr -- "$EXE" -e --base-dir base -o - - < stdin.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>INCLUDED VIA BASEDIR</p>'
}

@test "warnings are printed to stderr by default" {
  printf '1. first\n3. third\n' > input.adoc
  run --separate-stderr -- "$EXE" -o out.html input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'WARNING'
  assert_stderr_contains 'list item index: expected 2, got 3'
}

@test "log level info reveals info messages" {
  require_log_level_flag
  cat > input.adoc <<'EOF'
skip to <<install>>

. download
. install[[install]]
. run
EOF
  run --separate-stderr -- "$EXE" --log-level INFO -o - input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'asciidoctor: INFO: possible invalid reference: install'
}

@test "log level warn hides info messages" {
  require_log_level_flag
  cat > input.adoc <<'EOF'
skip to <<install>>

. download
. install[[install]]
. run
EOF
  run --separate-stderr -- "$EXE" --log-level WARN -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
}

@test "log level error hides warnings" {
  require_log_level_flag
  printf '1. first\n3. third\n' > input.adoc
  run --separate-stderr -- "$EXE" --log-level ERROR -o out.html input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
}

@test "failure level yields non-zero exit code when reached" {
  printf '1. first\n3. third\n' > input.adoc
  run --separate-stderr -- "$EXE" -q --failure-level WARN -o out.html input.adoc
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
}

@test "failure level below warning keeps zero exit code" {
  printf '1. first\n3. third\n' > input.adoc
  run --separate-stderr -- "$EXE" --failure-level ERROR -o out.html input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'WARNING'
}

@test "quiet flag silences warnings" {
  printf '1. first\n3. third\n' > input.adoc
  run --separate-stderr -- "$EXE" -q -o out.html input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
}

@test "verbose flag reveals info messages" {
  cat > input.adoc <<'EOF'
skip to <<install>>

. download
. install[[install]]
. run
EOF
  run --separate-stderr -- "$EXE" -v -o - input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'possible invalid reference: install'
}

@test "error without trace suggests the trace flag" {
  printf 'content\n' > same.adoc
  run --separate-stderr -- "$EXE" -o same.adoc same.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'input file and output file cannot be the same'
  assert_stderr_contains 'Use --trace to show backtrace'
}

@test "error with trace shows a backtrace instead of the hint" {
  printf 'content\n' > same.adoc
  run --separate-stderr -- "$EXE" --trace -o same.adoc same.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'input file and output file cannot be the same'
  [ "$(printf '%s\n' "$stderr" | wc -l)" -gt 1 ]
  if grep -F -q 'Use --trace to show backtrace' <<< "$stderr"; then
    echo 'trace output must not contain the --trace hint'
    printf '%s\n' "$stderr"
    return 1
  fi
}

@test "timings flag prints a timings report to stderr" {
  printf 'Sample *AsciiDoc*\n' > input.adoc
  run --separate-stderr -- "$EXE" -t -o out.html input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'Total time'
}
