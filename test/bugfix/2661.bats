#!/usr/bin/env bats
# asciidoctor#2661: a quote in an image attribute (align, float, width,
# role, link...) ended the HTML attribute it was written into, letting the
# rest of the value into the markup.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a crafted align value stays in the class attribute" {
  printf 'image::test.png[align=center"><p>this is a paragraph</p>]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html '"><p>this is a paragraph'
  assert_contains actual.html 'class="imageblock text-center&quot;><p>this is a paragraph</p>"'
}

@test "and a crafted width on an inline image" {
  printf 'see image:a.png[A,width="1\\" onload=\\"x"]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html ' onload="x"'
  assert_contains actual.html 'width="1&quot; onload=&quot;x"'
}
