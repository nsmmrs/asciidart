#!/usr/bin/env bats
# Index terms are self-contained: a quote mark inside one (`_hyperscript`)
# doesn't pair with a mark after it. Asciidoctor 2.0.26 lets the emphasis
# open inside the term and close in the text (`an _event filter</em>`), and
# the term loses its underscore. Found in the Hypermedia Systems book.
# Fails on the gem.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "emphasis doesn't pair a mark in an index term with one after it" {
  cat > input.adoc <<'EOF2'
((("_hyperscript", "event filter")))
We can use an _event filter_ syntax in +_hyperscript+ here.
EOF2
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  grep -q 'We can use an <em>event filter</em> syntax in _hyperscript here.' actual.html
}

@test "and the term keeps its text in DocBook" {
  cat > input.adoc <<'EOF2'
((("_hyperscript", "event filter")))
We can use an _event filter_ syntax.
EOF2
  run --separate-stderr -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  grep -q '<primary>_hyperscript</primary><secondary>event filter</secondary>' actual.xml
  grep -q 'We can use an <emphasis>event filter</emphasis> syntax.' actual.xml
}
