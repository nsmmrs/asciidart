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

# A section style DocBook has no element for ([introduction]) became that
# element (<introduction>), which no DocBook schema allows: asciidart
# writes the chapter or section it is. Fails on the gem.
@test "a section style DocBook has no element for gives a chapter" {
  printf '= Book\n:doctype: book\n\n[introduction]\n== Introduction\n\nText.\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  grep -q '<chapter xml:id="_introduction">' actual.xml
  ! grep -q '<introduction' actual.xml
}

# [partintro] on a section that isn't in a part gave <partintro> there,
# where DocBook doesn't allow it: asciidart writes a section. Fails on the
# gem.
@test "a part introduction outside a part gives a section" {
  printf '= Book\n:doctype: book\n\n== Chapter\n\n[partintro]\n=== Intro\n\nText.\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  grep -q '<section xml:id="_intro">' actual.xml
  ! grep -q '<partintro' actual.xml
}

# Emphasis inside monospace gave <emphasis> inside <literal>, which
# DocBook doesn't allow: asciidart writes a phrase. Fails on the gem.
@test "emphasis inside monospace gives a phrase in the literal" {
  printf 'Some `a _b_ c` here.\n' > input.adoc
  run -- "$EXE" -s -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  grep -q '<literal>a <phrase role="emphasis">b</phrase> c</literal>' actual.xml
}
