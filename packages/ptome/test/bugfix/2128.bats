#!/usr/bin/env bats
# asciidoctor#2128: curved quotes and constrained emphasis blocked each
# other at their boundaries: `_"`text`"_` kept its straight quotes (the
# underscore, a word character, stopped the curved quotes) and
# `"`_text_`"` kept its underscores (emphasis came after the curved
# quotes, and their character reference ends with `;`, which emphasis
# doesn't start after). Both nest now, with single curved quotes too.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "curved double quotes inside emphasis" {
  printf '_"`Italic text`"_\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><em>&#8220;Italic text&#8221;</em></p>'
}

@test "emphasis inside curved double quotes" {
  printf '"`_Italic text_`"\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>&#8220;<em>Italic text</em>&#8221;</p>'
}

@test "and with curved single quotes" {
  printf "_'\`single\`'_ and '\`_single_\`'\n" > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><em>&#8216;single&#8217;</em> and &#8216;<em>single</em>&#8217;</p>'
}

@test "unchanged: strong and curved quotes" {
  printf '*"`Bold`"* and "`*Bold*`"\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p><strong>&#8220;Bold&#8221;</strong> and &#8220;<strong>Bold</strong>&#8221;</p>'
}

@test "unchanged: an underscore inside a word is not emphasis" {
  printf 'snake_case and "`quoted`"\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>snake_case and &#8220;quoted&#8221;</p>'
}
