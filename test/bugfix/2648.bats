#!/usr/bin/env bats
# asciidoctor#2648: in an AsciiDoc cell, a line comment between two lists
# didn't separate them (the table parser had dropped it), so the second
# list was nested in the first.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a line comment separates two lists in an AsciiDoc cell" {
  printf '[cols="1a"]\n|===\n|\n* first list\n\n//\n\n. second list\n|===\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '</ul>\n</div>\n<div class="olist arabic">')"
}
