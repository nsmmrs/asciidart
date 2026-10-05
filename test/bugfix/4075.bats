#!/usr/bin/env bats
# asciidoctor#4075: link text holding an element converted before the link
# (an icon embedded as a data URI) was read as an attribute list because
# the element's markup has equals signs, so the text was cut at its first
# comma, leaving an unterminated attribute and element in the output.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an embedded icon in link text stays whole in DocBook" {
  mkdir -p images/icons
  printf 'GIF89a' > images/icons/github.gif
  printf ':icons:\n:icontype: gif\n:data-uri:\n\nlink:++https://example.com++[icon:github[]bar]\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<imagedata fileref="data:image/gif;base64,R0lGODlh"/>'
  assert_contains actual.xml '</inlinemediaobject>bar</link></simpara>'
}

@test "and in HTML" {
  mkdir -p images/icons
  printf 'GIF89a' > images/icons/github.gif
  printf ':icons:\n:icontype: gif\n:data-uri:\n\nlink:++https://example.com++[icon:github[]bar]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<img src="data:image/gif;base64,R0lGODlh" alt="github"></span>bar</a>'
}

@test "unchanged: attributes in link text still apply" {
  printf 'link:https://example.com[*Home*,role=nav]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="https://example.com" class="nav"><strong>Home</strong></a>'
}
