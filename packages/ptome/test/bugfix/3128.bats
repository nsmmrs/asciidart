#!/usr/bin/env bats
# asciidoctor#3128: a bare URL ending with a placeholder in angle brackets
# (`http://<host>:<port>`) lost the `;` of the escaped `>` (`&gt;`): the
# link ended with `&gt` and a stray `;` followed it.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "the escaped > stays in the URL" {
  printf 'at the end of http://<host>:<port>\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<p>at the end of <a href="http://&lt;host&gt;:&lt;port&gt;" class="bare">http://&lt;host&gt;:&lt;port&gt;</a></p>'
}

@test "unchanged: a trailing ; or ); is moved out of the URL" {
  printf 'see https://example.org; or (https://example.org);\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="https://example.org" class="bare">https://example.org</a>; or (<a href="https://example.org" class="bare">https://example.org</a>);'
}
