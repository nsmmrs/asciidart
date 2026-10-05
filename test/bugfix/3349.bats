#!/usr/bin/env bats
# asciidoctor#3349: a record of the cols attribute that isn't a column spec
# (`20strong`) silently dropped its column, so every row overran the table
# and its cells were dropped with errors that pointed elsewhere. The column
# stays, as a default one, and the record is reported.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an invalid column spec keeps its column and is reported" {
  printf '[cols="20strong,20d,10d,40a"]\n|===\n|a |b |c |d\n|===\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'input.adoc: line 3: invalid column spec in cols attribute: 20strong; using a default column'
  [ "$(grep -c '^<col ' <<< "$output")" -eq 4 ]
  assert_output_contains '<p>d</p>'
}

@test "unchanged: with no valid column spec the first row decides the columns" {
  printf '[cols="20]\n|===\n| a | b\n|===\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$(grep -c '^<col ' <<< "$output")" -eq 2 ]
}
