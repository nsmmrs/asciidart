#!/usr/bin/env bats
# asciidoctor#1678: a cross reference to an ID with `__` in it was turned
# into emphasis (quotes are substituted before the xref macro), and the
# other `__` could pair with one later in the line. The target of an xref
# (macro or shorthand) is no longer formatted.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an xref shorthand to an ID with double underscores" {
  printf 'See <<foo__bar__baz,the part>>.\n\n[[foo__bar__baz]]\n== Part\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#foo__bar__baz">the part</a>'
}

@test "the xref macro" {
  printf 'See xref:foo__bar__baz[the part].\n\n[[foo__bar__baz]]\n== Part\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#foo__bar__baz">the part</a>'
}

@test "emphasis after it in the line pairs on its own" {
  printf 'See <<foo__bar>> if b__u__z.\n\n[[foo__bar]]\n== Part\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<xref linkend="foo__bar"/> if b<emphasis>u</emphasis>z.'
}

@test "unchanged: emphasis around a whole xref" {
  printf 'See __<<part>>__.\n\n[[part]]\n== Part\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<em><a href="#part">Part</a></em>'
}
