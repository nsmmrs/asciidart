#!/usr/bin/env bats
# asciidoctor#3876: a `#` in a URL and a `#` in a cross reference's target
# on the same line were paired as constrained mark text (quotes are
# substituted before macros), breaking both. Formatting marks inside a
# link's URL or a cross reference's target no longer pair with anything.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a URL fragment and an interdocument xref on one line" {
  printf 'Use link:https://example.org/docs/#maven[Maven],\nthe <<maven.adoc#, start guide>> sets it up.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="https://example.org/docs/#maven">Maven</a>'
  assert_contains actual.html '<a href="maven.html">start guide</a>'
  assert_not_contains actual.html '<mark>'
}

@test "a bare URL with a fragment and an interdocument xref" {
  printf 'See https://example.org/#top, then <<other.adoc#,the other page>>.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="https://example.org/#top" class="bare">https://example.org/#top</a>'
  assert_contains actual.html '<a href="other.html">the other page</a>'
}

@test "unchanged: marked text around a whole URL" {
  printf 'Read *https://example.org/x* now.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<strong><a href="https://example.org/x" class="bare">https://example.org/x</a></strong>'
}

@test "unchanged: mark text beside a link" {
  printf 'A #marked# word and link:https://example.org[a link].\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<mark>marked</mark>'
}
