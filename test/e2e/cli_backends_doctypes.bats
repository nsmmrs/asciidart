#!/usr/bin/env bats
# Black-box CLI cases for backends, doctypes, and embedded output.
# Mirrors test/invoker_test.rb backend/doctype/standalone coverage.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "backend defaults to html5 article" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<html'
  assert_contains actual.html '<body class="article">'
  assert_contains actual.html '<title>Document Title</title>'
}

@test "backend html5 can be selected explicitly" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -b html5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<html'
  assert_contains actual.html '</html>'
}

@test "backend html5 writes .html suffix by default" {
  cat > input.adoc <<'EOF'
content
EOF
  run --separate-stderr -- "$EXE" -b html5 input.adoc
  [ "$status" -eq 0 ]
  [ -f input.html ]
  assert_contains input.html '<html'
}

@test "backend docbook5 produces docbook article" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<article xmlns="http://docbook.org/ns/docbook"'
  assert_contains actual.xml '<simpara>content</simpara>'
}

@test "backend docbook5 writes .xml suffix by default" {
  cat > input.adoc <<'EOF'
content
EOF
  run --separate-stderr -- "$EXE" -b docbook5 input.adoc
  [ "$status" -eq 0 ]
  [ -f input.xml ]
  assert_contains input.xml '<article'
}

@test "backend manpage produces troff output" {
  cat > eve.adoc <<'EOF'
= eve(1)
Andrew Stanton
:doctype: manpage
:manmanual: EVE
:mansource: EVE

== NAME

eve - analyzes an image to determine if it is a picture of a life form

== SYNOPSIS

*eve* ['OPTION']... 'FILE'...
EOF
  run --separate-stderr -- "$EXE" -b manpage eve.adoc
  [ "$status" -eq 0 ]
  [ -f eve.1 ]
  assert_contains eve.1 '.TH "EVE"'
  assert_contains eve.1 'analyzes an image'
}

@test "backend manpage writes a page for each alternate manname" {
  cat > eve.adoc <<'EOF'
= eve(1)
Andrew Stanton
:doctype: manpage
:manmanual: EVE
:mansource: EVE

== NAME

eve, islifeform - analyzes an image to determine if it is a picture of a life form

== SYNOPSIS

*eve* ['OPTION']... 'FILE'...
EOF
  run --separate-stderr -- "$EXE" -b manpage -o eve.1 eve.adoc
  [ "$status" -eq 0 ]
  [ -f eve.1 ]
  [ -f islifeform.1 ]
  assert_contains islifeform.1 '.so eve.1'
}

@test "doctype article can be selected explicitly" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -d article -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<body class="article">'
}

@test "doctype book produces book structure" {
  cat > input.adoc <<'EOF'
= Document Title

== Chapter

content
EOF
  run --separate-stderr -- "$EXE" -d book -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<body class="book">'
}

@test "doctype inline converts a single paragraph" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" -d inline -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [ "$output" = "content" ]
}

@test "doctype inline warns when first block is not an inline candidate" {
  printf '== Section Title\n' > input.adoc
  run --separate-stderr -- "$EXE" -d inline -o out.txt input.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'no inline candidate'
}

@test "embedded flag suppresses header and footer" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html '<html'
  assert_contains actual.html '<p>content</p>'
}

@test "legacy no-header-footer flag suppresses header and footer" {
  cat > input.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" -s -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_not_contains actual.html '<html'
  assert_contains actual.html '<p>content</p>'
}
