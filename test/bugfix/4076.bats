#!/usr/bin/env bats
# asciidoctor#4076: a superscript around a link whose text ends with the
# `^` shorthand (`^link:fn.html[2^]^`) ended at that `^`, leaving the link
# markup across the end of the superscript (invalid XML and HTML).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a link in a superscript nests in DocBook" {
  printf 'overlaps with `X`^link:fn2.html[2^]^ and more.\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<literal>X</literal><superscript><link xl:href="fn2.html">2</link></superscript> and more.'
}

@test "and in HTML" {
  printf 'overlaps with `X`^link:fn2.html[2^]^ and more.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<code>X</code><sup><a href="fn2.html" target="_blank" rel="noopener">2</a></sup> and more.'
}

@test "unchanged: plain superscripts and subscripts" {
  printf 'E=mc^2^, H~2~O and ^[1]^.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'E=mc<sup>2</sup>, H<sub>2</sub>O and <sup>[1]</sup>.'
}
