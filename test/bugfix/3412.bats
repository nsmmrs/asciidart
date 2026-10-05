#!/usr/bin/env bats
# asciidoctor#3412: tabs in a literal table cell were not expanded when the
# document sets tabsize, as they are in a literal block.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "tabs in a literal cell expand to tabsize" {
  printf ':tabsize: 4\n\n|===\nl|a\tb\n|===\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<div class="literal"><pre>a   b</pre></div>'
}

@test "unchanged: without tabsize the tab stays" {
  printf '|===\nl|a\tb\n|===\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '<pre>a\tb</pre>')"
}
