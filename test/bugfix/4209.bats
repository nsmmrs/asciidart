#!/usr/bin/env bats
# asciidoctor#4209: when the author comes from the author or authors
# attribute, only an assigned authorinitials survived; an assigned
# firstname, middlename or lastname was replaced by the computed one. They
# all win now, as they do over an implicit author line.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an assigned firstname wins over the one computed from author" {
  printf '= Document Title\n:author: Daniel Allen\n:firstname: Dan\n:authorinitials: DJA\n\n{lastname}, {firstname} ({authorinitials})\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>Allen, Dan (DJA)</p>'
}

@test "and indexed names win over the ones computed from authors" {
  printf '= Document Title\n:authors: Sarah White; Daniel Allen\n:firstname_2: Dan\n:authorinitials_2: DJA\n\n{lastname_2}, {firstname_2} ({authorinitials_2})\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>Allen, Dan (DJA)</p>'
}

@test "unchanged: names from an implicit author line can still be overridden by author" {
  printf '= Document Title\nSarah White\n:author: Daniel Allen\n\n{firstname} {lastname}\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>Daniel Allen</p>'
}
