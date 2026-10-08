#!/usr/bin/env bats
# asciidoctor#2903: a footnote in a section title was numbered when the
# parser converted the title to generate the section's ID, before the
# footnotes of the blocks above it: two footnotes got number 1, and the
# number ended up in the ID.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "footnotes in titles are numbered in document order" {
  printf '== H2\n\nPara1.footnote:[fn 1]\n\n=== H3footnote:[fn 2]\n\nPara2.footnote:[fn 3]\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h3 id="_h3">H3<sup class="footnote">[<a id="_footnoteref_2" class="footnote" href="#_footnotedef_2" title="View footnote.">2</a>]</sup></h3>'
  assert_contains actual.html '<a href="#_footnoteref_2">2</a>. fn 2'
  assert_contains actual.html '<a href="#_footnoteref_3">3</a>. fn 3'
}

@test "unchanged: attribute references in a title resolve where it is" {
  printf ':v: one\n\n== Title {v}\n\n:v: two\n\nText {v}.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2 id="_title_one">Title one</h2>'
  assert_contains actual.html '<p>Text two.</p>'
}
