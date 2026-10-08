#!/usr/bin/env bats
# asciidoctor#4419: a doubled slash before `..` in a path (here imagesdir)
# made `..` remove the empty segment between the slashes instead of the
# directory before them, so `X//../dir` resolved to `X/dir`.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "imagesdir with a doubled slash before .. finds the image" {
  mkdir -p project/X project/Administration
  printf 'GIF89a' > project/Administration/m.gif
  printf ':imagesdir: ./project/X//../Administration/\n:data-uri:\n\nimage::m.gif[]\n' > input.adoc
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'src="data:image/gif;base64,'
}
