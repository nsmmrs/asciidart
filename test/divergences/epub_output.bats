#!/usr/bin/env bats
# An EPUB must be complete in itself. With source-highlighter=highlight.js,
# asciidoctor-epub3 2.3.0 links highlight.js's stylesheet and scripts at
# /highlight.js/9.18.3/ (outside the container, where no reader finds
# them; EPUBCheck reports it). asciidart highlights the code at conversion
# and packs the theme's stylesheet. Found building the Hypermedia Systems
# book with its code highlighted. Fails on the gem.
#
# The gem's EPUB converter is a separate command: set
# ASCIIDOCTOR_EPUB3_EXE to it when ASCIIDOCTOR_EXE is the Ruby CLI.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
  command -v unzip >/dev/null || skip 'needs unzip'
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  EPUB=$EXE
  if [[ $EXE == *asciidoctor-ruby ]]; then
    EPUB=${ASCIIDOCTOR_EPUB3_EXE:-}
    [ -n "$EPUB" ] || skip 'needs ASCIIDOCTOR_EPUB3_EXE for the Ruby CLI'
  fi
}

@test "highlight.js in an EPUB: the theme's stylesheet inside, no scripts" {
  printf '= Doc\n:source-highlighter: highlight.js\n\n== One\n\n[source,python]\n----\ndef f(): pass\n----\n' > input.adoc
  run --separate-stderr -- "$EPUB" -b epub3 -o out.epub input.adoc
  [ "$status" -eq 0 ]
  mkdir book
  (cd book && unzip -q ../out.epub)
  run grep -Eq '(href|src)="(/|https?://)' book/EPUB/*.xhtml
  [ "$status" -eq 1 ]
  run grep -q '<script src=' book/EPUB/*.xhtml
  [ "$status" -eq 1 ]
  grep -lq 'hljs-keyword' book/EPUB/styles/*.css
  grep -q 'class="hljs-keyword"' book/EPUB/*.xhtml
}
