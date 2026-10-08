#!/usr/bin/env bats
# asciidoctor#3633: inline anchors in section titles were not registered in
# the catalog, so a duplicate went unreported (and tools reading the
# catalog couldn't resolve them).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a duplicate anchor in section titles is reported" {
  printf '= Title\n\nLink to <<foo>>.\n\n== [[foo]]Section 1\n\nText.\n\n== [[foo]]Section 2\n\nText.\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'input.adoc: line 9: id assigned to anchor already in use: foo'
}

@test "an anchor in a title is registered for its reference text" {
  printf '= Title\n\nSee <<foo>>.\n\n== [[foo,the first section]]Section 1\n\nText.\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#foo">the first section</a>'
}

@test "unchanged: a trailing anchor is the section id" {
  printf '= Title\n\nSee <<sec>>.\n\n== Section 1 [[sec]]\n\nText.\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2 id="sec">Section 1</h2>'
  assert_contains actual.html '<a href="#sec">Section 1</a>'
}
