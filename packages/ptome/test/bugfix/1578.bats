#!/usr/bin/env bats
# asciidoctor#1578: a double hyphen between a word and formatted text
# (`_italicized_--but`) was not replaced with an em dash: the markup of the
# formatted text, already converted, is not a word character.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an em dash follows formatted text" {
  printf '_italicized_--but nevertheless and *bold*--too.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<em>italicized</em>&#8212;&#8203;but nevertheless and <strong>bold</strong>&#8212;&#8203;too.'
}

@test "and precedes it" {
  printf 'this--_that_ one\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'this&#8212;&#8203;<em>that</em> one'
}

@test "and in a man page" {
  printf '= x(1)\n:doctype: manpage\n\n== NAME\n\nx - y\n\n== DESCRIPTION\n\n_italicized_--but nevertheless\n' > input.adoc
  run -- "$EXE" -b manpage -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.man
  assert_contains actual.man '\fIitalicized\fP\(embut nevertheless'
}

@test "unchanged: a double hyphen with a space on one side only stays" {
  printf '*a*-- b and a --b\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<strong>a</strong>-- b and a --b'
}
