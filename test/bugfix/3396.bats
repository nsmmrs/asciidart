#!/usr/bin/env bats
# asciidoctor#3396: a paragraph that starts with formatted text with a role
# and ends with a macro (`[.red]#Bbb# bbb.footnote:[Bbb.]`) was taken for a
# block attribute line, since it starts with `[` and ends with `]`, and
# disappeared from the output (its text became the role of the next block).

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "the paragraph is kept" {
  printf 'Aaa.\n\n[.red]#Bbb# bbb.footnote:[Bbb.]\n\nCcc.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><span class="red">Bbb</span> bbb.<sup class="footnote">'
  assert_contains_text actual.html "$(printf '<div class="paragraph">\n<p>Ccc.</p>')"
}

@test "unchanged: attribute lists with brackets in quoted values" {
  printf '[title="a ] b",role=x]\nText.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<div class="paragraph x">'
  assert_contains actual.html '<div class="title">a ] b</div>'
}

@test "unchanged: a stray ] at the end of an attribute list" {
  printf '[source, xml]]\n----\n<a/>\n----\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'data-lang="xml]"'
}
