#!/usr/bin/env bats
# asciidoctor#4500: a cell after one spanning columns took the column spec
# of the column with its index in the row (counting cells, not columns), so
# it was aligned like the wrong column.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a cell after a colspan gets the spec of the column it is in" {
  cat > input.adoc <<'ADOC'
[cols="1,^1,>1"]
|===
| Test 1.2
2+| Test 2.2

2+| Test 1.3
| Test 3.3
|===
ADOC
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<td class="tableblock halign-center valign-top" colspan="2"><p class="tableblock">Test 2.2</p></td>'
  assert_contains actual.html '<td class="tableblock halign-right valign-top"><p class="tableblock">Test 3.3</p></td>'
}

@test "repeated cells in the first row number the columns in order" {
  printf '|===\n3*|a |b\n|c |d |e |f\n|===\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  for n in 1 2 3 4; do
    assert_contains actual.xml "<colspec colname=\"col_$n\""
  done
}
