#!/usr/bin/env bats
# asciidoctor#2496: the table parser dropped every line comment in the
# table, including the lines of a verbatim block in an AsciiDoc cell that
# look like one (`// some comment` in a literal block).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a comment-like line in a verbatim block in an AsciiDoc cell is kept" {
  printf '|===\na|\n....\nline\n// some comment\n....\n|===\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '<pre>line\n// some comment</pre>')"
}

@test "unchanged: comments between rows and in other cells are dropped" {
  printf '|===\n// before\n|a\n// in a cell\n|b\n// between\n|c |d\n|===\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html 'before'
  assert_not_contains actual.html 'in a cell'
  assert_not_contains actual.html 'between'
  assert_contains actual.html '<p class="tableblock">a</p>'
}

@test "unchanged: a line comment in an AsciiDoc cell is not output" {
  printf '[cols="1a"]\n|===\n|text\n// a note\nmore\n|===\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html 'a note'
}

@test "unchanged: comments around rows don't change the implicit header or the cells" {
  printf '|===\n| a | b\n// comment\n\n| c | d\n// trailing\n|===\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  [ "$(grep -c '<th ' actual.html)" -eq 2 ]
  [ "$(grep -c '<td ' actual.html)" -eq 2 ]
}
