#!/usr/bin/env bats
# asciidoctor#2293: a list continuation after empty lines attached its
# block to the outermost list item, whatever the number of empty lines.
# Each empty line moves up one level from the innermost item, so one empty
# line attaches to the parent of the innermost item.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "one empty line attaches to the parent item" {
  printf '. grandparent\n.. parent\n... child\n\n+\nattached\n.. parent b\n. grandparent b\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  # The paragraph follows the child list, in the parent item, and parent b
  # is the next item of the same list.
  assert_contains_text actual.html "$(printf '<p>child</p>\n</li>\n</ol>\n</div>\n<div class="paragraph">\n<p>attached</p>\n</div>\n</li>\n<li>\n<p>parent b</p>')"
}

@test "unchanged: two empty lines attach to the grandparent item" {
  printf '. grandparent\n.. parent\n... child\n\n\n+\nattached\n. grandparent b\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '</ol>\n</div>\n</li>\n</ol>\n</div>\n<div class="paragraph">\n<p>attached</p>\n</div>\n</li>\n<li>\n<p>grandparent b</p>')"
}

@test "unchanged: one empty line in a two-level list attaches to the parent" {
  printf '* parent\n** child\n\n+\nattached\n* another\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '</ul>\n</div>\n<div class="paragraph">\n<p>attached</p>\n</div>\n</li>\n<li>\n<p>another</p>')"
}

@test "unchanged: repeated continuations climb one level each (upstream's own case)" {
  printf '* bullet 1\n. numbered 1.1\n** bullet 1.1.1\n\n+\nnumbered 1.1 paragraph\n\n+\nbullet 1 paragraph\n\n* bullet 2\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains_text actual.html "$(printf '<p>bullet 1.1.1</p>\n</li>\n</ul>\n</div>\n<div class="paragraph">\n<p>numbered 1.1 paragraph</p>\n</div>\n</li>\n</ol>\n</div>\n<div class="paragraph">\n<p>bullet 1 paragraph</p>')"
}
