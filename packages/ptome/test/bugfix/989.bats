#!/usr/bin/env bats
# asciidoctor#989: the cells next to one spanning rows took the column spec
# of the column on their left.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "cells beside a rowspan get the specs of their own columns" {
  cat > input.adoc <<'ADOC'
[cols="^,<,>"]
|===
|Name | Class | Grades

.2+|Richard
|Programming |16
|Digital Systems | 18
|===
ADOC
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<td class="tableblock halign-left valign-top"><p class="tableblock">Digital Systems</p></td>'
  assert_contains actual.html '<td class="tableblock halign-right valign-top"><p class="tableblock">18</p></td>'
}
