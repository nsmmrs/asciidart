#!/usr/bin/env bats
# Black-box CLI cases for output routing: default naming, -o/--out-file
# (including STDOUT via `-`), destination/source dirs, multiple inputs, globs.
# Mirrors the file-handling coverage in test/invoker_test.rb.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "output defaults to file derived from input name" {
  cat > sample.adoc <<'EOF'
= Document Title

content
EOF
  run --separate-stderr -- "$EXE" sample.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [ -f sample.html ]
  assert_contains sample.html '<title>Document Title</title>'
  assert_contains sample.html '<h1>Document Title</h1>'
}

@test "output can be written to an explicit file" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" -o custom.html input.adoc
  [ "$status" -eq 0 ]
  [ -f custom.html ]
  [ ! -e input.html ]
  assert_contains custom.html '<p>content</p>'
}

@test "output can be written to an explicit file via long flag" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" --out-file custom.html input.adoc
  [ "$status" -eq 0 ]
  [ -f custom.html ]
  assert_contains custom.html '<p>content</p>'
}

@test "output to dash writes converted document to stdout" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  assert_output_contains '<p>content</p>'
  [ ! -e input.html ]
}

@test "output to stdout ends with a trailing newline" {
  printf 'content\n' > input.adoc
  "$EXE" -o - input.adoc > stdout.bin 2> stderr.txt
  [ "$?" -eq 0 ]
  [ ! -s stderr.txt ]
  [ "$(tail -c 1 stdout.bin | od -An -c | tr -d ' ')" = '\n' ]
}

@test "output to file is written without added trailing newline" {
  printf -- '--\nA paragraph in an open block.\n--\n' > input.adoc
  run --separate-stderr -- "$EXE" -e -o actual.html input.adoc
  [ "$status" -eq 0 ]
  [ "$(tail -c 6 actual.html)" = '</div>' ]
}

@test "fails when input file matches specified output file" {
  printf 'content\n' > same.adoc
  run --separate-stderr -- "$EXE" -o same.adoc same.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'input file and output file cannot be the same'
}

@test "fails when input file matches resolved output file" {
  printf 'content\n' > sample.adoc
  run --separate-stderr -- "$EXE" -a outfilesuffix=.adoc sample.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'input file and output file cannot be the same'
}

@test "converts all passed files" {
  printf 'first\n' > first.adoc
  printf 'second\n' > second.adoc
  run --separate-stderr -- "$EXE" first.adoc second.adoc
  [ "$status" -eq 0 ]
  [ -f first.html ]
  [ -f second.html ]
  assert_contains first.html '<p>first</p>'
  assert_contains second.html '<p>second</p>'
}

@test "converts all files matching a glob expression" {
  printf 'a1\n' > a1.adoc
  printf 'a2\n' > a2.adoc
  printf 'b\n' > b.adoc
  run --separate-stderr -- "$EXE" 'a*.adoc'
  [ "$status" -eq 0 ]
  [ -f a1.html ]
  [ -f a2.html ]
  [ ! -e b.html ]
}

@test "destination dir receives output file" {
  mkdir -p src
  printf 'content\n' > src/doc.adoc
  run --separate-stderr -- "$EXE" -D out src/doc.adoc
  [ "$status" -eq 0 ]
  [ -f out/doc.html ]
  [ ! -e src/doc.html ]
  assert_contains out/doc.html '<p>content</p>'
}

@test "destination dir is created when missing" {
  printf 'content\n' > doc.adoc
  run --separate-stderr -- "$EXE" -D nested/deep doc.adoc
  [ "$status" -eq 0 ]
  [ -f nested/deep/doc.html ]
}

@test "source dir preserves directory structure in destination dir" {
  mkdir -p src/sub
  printf 'nested\n' > src/sub/page.adoc
  run --separate-stderr -- "$EXE" -D out -R src src/sub/page.adoc
  [ "$status" -eq 0 ]
  [ -f out/sub/page.html ]
  assert_contains out/sub/page.html '<p>nested</p>'
}

@test "stylesheet is copied next to output when linkcss is set" {
  printf 'content\n' > doc.adoc
  run --separate-stderr -- "$EXE" -a linkcss -o styled/doc.html doc.adoc
  [ "$status" -eq 0 ]
  [ -f styled/doc.html ]
  [ -f styled/asciidoctor.css ]
}

@test "stylesheet is not copied when copycss is unset" {
  printf 'content\n' > doc.adoc
  run --separate-stderr -- "$EXE" -a linkcss -a copycss! -o styled/doc.html doc.adoc
  [ "$status" -eq 0 ]
  [ -f styled/doc.html ]
  [ ! -e styled/asciidoctor.css ]
}
