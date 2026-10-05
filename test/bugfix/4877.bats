#!/usr/bin/env bats
# asciidoctor#4877: a section title made only of punctuation got an empty
# generated id (`<h2 id="">`); it keeps the separator instead.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a punctuation-only section title gets a non-empty id" {
  printf '== ...\n\ntext\n\n== ---\n\ntext\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html 'id=""'
  assert_contains actual.html '<h2 id="_">'
  assert_contains actual.html '<h2 id="__2">'
}

@test "with an empty idprefix too" {
  printf ':idprefix:\n\n== &\n\ntext\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2 id="_">'
}
