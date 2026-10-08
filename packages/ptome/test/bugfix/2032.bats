#!/usr/bin/env bats
# asciidoctor#2032: a leveloffset that pushed a section past level 5
# produced heading elements HTML doesn't have (<h9>, <h10>).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "deep sections use h6" {
  printf ':leveloffset: +6\n\n=== Level\n\n==== Sub\n\n[discrete]\n===== Discrete\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h6 id="_level">Level</h6>'
  assert_contains actual.html '<h6 id="_sub">Sub</h6>'
  assert_contains actual.html '<h6 id="_discrete" class="discrete">Discrete</h6>'
  assert_not_contains actual.html '<h9'
}

@test "unchanged: section levels up to 5" {
  printf '= T\n\n== One\n\n=== Two\n\n====== Five\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2 id="_one">One</h2>'
  assert_contains actual.html '<h6 id="_five">Five</h6>'
}
