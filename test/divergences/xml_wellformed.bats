#!/usr/bin/env bats
# DocBook output must be well-formed XML. An index term that starts with an
# underscore (`_hyperscript`) before constrained emphasis lets the emphasis
# open inside the term and close in the text after it: Asciidoctor 2.0.26
# writes `<primary><emphasis>hyperscript</primary>` and a stray
# `</emphasis>`. Found by the Hypermedia Systems acceptance run; asciidart
# balances the tags (benchmark/PARITY.md). Fails on the gem.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
  command -v xmllint >/dev/null || skip 'needs xmllint'
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "an index term before emphasis leaves DocBook well-formed" {
  cat > input.adoc <<'EOF2'
((("_hyperscript", "event filter")))
We can use an _event filter_ syntax in +_hyperscript+ here.
EOF2
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  xmllint --noout actual.xml
}
