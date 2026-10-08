#!/usr/bin/env bats
# asciidoctor#3788: a closing square bracket couldn't be escaped in the
# reference text of an inline anchor shorthand: `[[id,[reftext\]]]` ended
# at the escaped bracket, kept the backslash in the reference text and left
# a stray `]` in the text.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an escaped bracket belongs to the reference text" {
  printf '[[id,[reftext\\]]]text that follows <<id>>\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><a id="id"></a>text that follows <a href="#id">[reftext]</a></p>'
}

@test "and in DocBook" {
  printf '[[id,[reftext\\]]]text that follows\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<anchor xml:id="id" xreflabel="[reftext]"/>text that follows'
}

@test "unchanged: reference text without brackets" {
  printf '[[id, The Text ]]after <<id>>\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><a id="id"></a>after <a href="#id">The Text</a></p>'
}
