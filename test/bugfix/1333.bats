#!/usr/bin/env bats
# asciidoctor#1333: a block title is interpolated on first use: a cross
# reference converted before the block it points to converts that block's
# title then, so a counter in the titles counted out of document order
# (and the attribute playback of the earlier block counted again from the
# start). A block title's counters (and `{set:...}`) are evaluated once,
# where the title is written, in document order.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "unchanged: counters in titles of blocks with and without IDs" {
  cat > input.adoc <<'ADOC'
.Item {counter:n}
====
first
====

[#second]
.Item {counter:n}
====
second
====

.Item {counter:n}
====
third
====
ADOC
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html "$(printf '<div class="title">Example 1. Item 1</div>\n<div class="content">\n<div class="paragraph">\n<p>first</p>')"
  assert_contains actual.html "$(printf '<div class="title">Example 2. Item 2</div>\n<div class="content">\n<div class="paragraph">\n<p>second</p>')"
  assert_contains actual.html "$(printf '<div class="title">Example 3. Item 3</div>\n<div class="content">\n<div class="paragraph">\n<p>third</p>')"
}

@test "a cross reference shows the title as numbered" {
  printf 'See <<req>>.\n\n.Requirement {counter:req}\nFirst.\n\n[#req]\n.Requirement {counter:req}\nSecond.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#req">Requirement 2</a>'
  assert_contains actual.html '<div class="title">Requirement 1</div>'
  assert_contains actual.html '<div class="title">Requirement 2</div>'
}

@test "unchanged: a title with an attribute reference" {
  printf ':product: Widget\n\n.About {product}\n====\nx\n====\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<div class="title">Example 1. About Widget</div>'
}
