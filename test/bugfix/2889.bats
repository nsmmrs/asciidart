#!/usr/bin/env bats
# asciidoctor#2889: in DocBook, cells in the rows under a rowspan were
# aligned like the column on their left.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "rows under a rowspan keep the alignment of their columns" {
  cat > input.adoc <<'ADOC'
[cols=">13,11,15"]
|===
.3+| Project
|SPMP |PCERT-SPMP
|PHD  |PCERT-PHD
|SQAP |PCERT-SQAP
|===
ADOC
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<entry align="left" valign="top"><simpara>PHD</simpara></entry>'
  assert_contains actual.xml '<entry align="left" valign="top"><simpara>SQAP</simpara></entry>'
}
