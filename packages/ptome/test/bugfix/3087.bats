#!/usr/bin/env bats
# asciidoctor#3087: the reference text of a bibliography entry
# (`[[[gof,{counter:ref}]]]`) was cataloged without substitutions, so a
# cross reference to it showed `[{counter:ref}]`. Its attribute references
# are substituted once, where the entry is, and the entry and its cross
# references show the same text.

load ../e2e/helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "a counter numbers the entries and their cross references" {
  cat > input.adoc <<'ADOC'
Read <<pp>> and <<gof>>.

[bibliography]
== References
:ref: 0

- [[[pp,{counter:ref}]]] Andy Hunt & Dave Thomas. The Pragmatic Programmer.
- [[[gof,{counter:ref}]]] Erich Gamma et al. Design Patterns.
ADOC
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'Read <a href="#pp">[1]</a> and <a href="#gof">[2]</a>.'
  assert_contains actual.html '<p><a id="pp"></a>[1] Andy Hunt'
  assert_contains actual.html '<p><a id="gof"></a>[2] Erich Gamma'
}

@test "an attribute reference in the reference text" {
  cat > input.adoc <<'ADOC'
:abbr: GoF

See <<gof>>.

[bibliography]
== References

- [[[gof,{abbr}]]] Design Patterns.
ADOC
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'See <a href="#gof">[GoF]</a>.'
  assert_contains actual.html '<p><a id="gof"></a>[GoF] Design Patterns.</p>'
}

@test "unchanged: plain reference text" {
  printf 'See <<gof>>.\n\n[bibliography]\n== References\n\n- [[[gof,GoF]]] Design Patterns.\n' > input.adoc
  run -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'See <a href="#gof">[GoF]</a>.'
}
