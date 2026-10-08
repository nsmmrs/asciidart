#!/usr/bin/env bats
# asciidoctor#1558: in DocBook, a cell after a colspan or beside a rowspan
# got the style of the wrong column (emphasis applied to the wrong cell).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "the style of the last column applies to its cells after a colspan" {
  printf '[cols="1,1,1e"]\n|===\n| a | b | c\n2+| Plain | Emphasis\n|===\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<simpara><emphasis>Emphasis</emphasis></simpara>'
  assert_contains actual.xml 'namest="col_1" nameend="col_2"><simpara>Plain</simpara>'
}

@test "and in the rows under a rowspan" {
  printf '[cols="1,1,1e"]\n|===\n| a | b | c\n.2+| Plain | Plain | Emphasis\n| Plain | Emphasis\n|===\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  [ "$(grep -c '<simpara><emphasis>Emphasis</emphasis></simpara>' actual.xml)" -eq 2 ]
}
