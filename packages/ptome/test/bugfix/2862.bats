#!/usr/bin/env bats
# asciidoctor#2862: a quote in an image target (`image::"foo.png"[]`) was
# written into the src attribute as is, ending it early (invalid HTML).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "quotes in a block image target are escaped" {
  printf 'image::"foo.png"[Foo]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<img src="&quot;foo.png&quot;" alt="Foo">'
}

@test "and in an inline image target" {
  printf 'see image:"foo.png"[Foo]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<img src="&quot;foo.png&quot;" alt="Foo">'
}
