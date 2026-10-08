#!/usr/bin/env bats
# asciidoctor#3877: an attribute entry inside a delimited block wasn't seen
# by the preprocessor directives after it in the same block: the block's
# lines were preprocessed (its ifdef, ifndef and include directives
# evaluated) before the entries in them were read, so `ifdef` reported the
# attribute as unset. Directives in a block now run in document order, as
# they do outside blocks.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "ifdef sees an attribute set earlier in the same block" {
  printf '====\n:var: defined\n\nifdef::var[]\nyes\nendif::[]\nifndef::var[]\nno\nendif::[]\n====\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>yes</p>'
  assert_not_contains actual.html '<p>no</p>'
}

@test "ifndef sees an attribute unset earlier in the same block" {
  printf ':var: defined\n\n****\n:var!:\n\nifndef::var[]\nunset\nendif::[]\nifdef::var[]\nstill set\nendif::[]\n****\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>unset</p>'
  assert_not_contains actual.html 'still set'
}

@test "an include target uses an attribute set earlier in the same block" {
  printf 'Included text.\n' > part.adoc
  printf '====\n:part: part.adoc\n\ninclude::{part}[]\n====\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>Included text.</p>'
}

@test "unchanged: an attribute set before the block" {
  printf ':var: defined\n\n====\nifdef::var[]\nyes\nendif::[]\n====\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>yes</p>'
}

@test "unchanged: a conditional around a whole block" {
  printf 'ifdef::nope[]\n====\nhidden\n====\nendif::[]\nshown\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html 'hidden'
  assert_contains actual.html '<p>shown</p>'
}
