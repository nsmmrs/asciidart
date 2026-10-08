#!/usr/bin/env bats
# asciidoctor#4875: the man page converter closed every font span with
# `\fP`, roff's single "previous font", so after a span nested in another
# the text that followed stayed in the inner span's font.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "nested formatting restores the outer font, then roman" {
  cat > input.adoc <<'ADOC'
= example(1)
:doctype: manpage

== NAME

example - demonstrate nested formatting

== DESCRIPTION

Hello, this is a `demonstration __of__ the issue` where text follows.
ADOC
  run -- "$EXE" -b manpage -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.man
  assert_contains actual.man '\f(CRdemonstration \fIof\f(CR the issue\fR where text follows.'
}

@test "unchanged: spans that are not nested still close with the previous font" {
  printf '= example(1)\n:doctype: manpage\n\n== NAME\n\nexample - x\n\n== DESCRIPTION\n\n*bold* and _it_ here.\n' > input.adoc
  run -- "$EXE" -b manpage -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.man
  assert_contains actual.man '\fBbold\fP and \fIit\fP here.'
}
