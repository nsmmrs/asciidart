#!/usr/bin/env bats
# Black-box CLI cases for -a/--attribute document attribute assignment.
# Each test observes the attribute through its effect on the output.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "attribute with value takes effect" {
  cat > input.adoc <<'EOF'
= Title

== Section A

content
EOF
  run --separate-stderr -- "$EXE" -e -a idprefix=id -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'id="idsection_a"'
}

@test "attribute value may contain an equal sign" {
  cat > input.adoc <<'EOF'
= Title

== Section A

content
EOF
  run --separate-stderr -- "$EXE" -a toc -a toc-title=t=o=c -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 't=o=c'
}

@test "attribute value may contain spaces" {
  cat > input.adoc <<'EOF'
content

NOTE: a note
EOF
  run --separate-stderr -- "$EXE" -e -a 'note-caption=Note to self:' -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'Note to self:'
}

@test "attribute with no value is set to empty string" {
  cat > input.adoc <<'EOF'
content

NOTE: a note
EOF
  run --separate-stderr -- "$EXE" -e -a icons -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<img src="./images/icons/note.png" alt="Note">'
}

@test "attribute ending in bang unsets the attribute" {
  cat > input.adoc <<'EOF'
== Section A

content
EOF
  run --separate-stderr -- "$EXE" -e -a sectids! -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2>Section A</h2>'
  assert_not_contains actual.html 'id="_section_a"'
}

@test "attribute ending in at-sign loses to document value" {
  cat > input.adoc <<'EOF'
:idprefix: id_

== Section A

content
EOF
  run --separate-stderr -- "$EXE" -e -a idprefix=id@ -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'id="id_section_a"'
}

@test "long attribute flag assigns attributes" {
  cat > input.adoc <<'EOF'
= Title

== Section A

content
EOF
  run --separate-stderr -- "$EXE" --attribute toc -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html 'id="toc"'
}
