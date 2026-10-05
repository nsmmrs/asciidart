#!/usr/bin/env bats
# asciidoctor#3946: a double hyphen after a curved quote ("`hello`"--world)
# was not replaced with an em dash.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an em dash follows a curved quote" {
  printf '"`hello`"--world and '"'"'`it`'"'"'--here\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '&#8220;hello&#8221;&#8212;&#8203;world and &#8216;it&#8217;&#8212;&#8203;here'
}

@test "and precedes one" {
  printf 'hello--"`world`"\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'hello&#8212;&#8203;&#8220;world&#8221;'
}
