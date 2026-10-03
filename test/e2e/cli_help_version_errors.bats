#!/usr/bin/env bats
# Black-box CLI cases for help, version, stdin input, and CLI error paths.
# Mirrors test/options_test.rb and the error-path coverage in
# test/invoker_test.rb.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "help flag prints usage to stdout" {
  run --separate-stderr -- "$EXE" -h
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [[ "$output" == Usage:* ]]
  assert_output_contains 'unsafe, safe, server, secure'
}

@test "long help flag prints usage to stdout" {
  run --separate-stderr -- "$EXE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == Usage:* ]]
}

@test "help with unknown topic prints usage" {
  run --separate-stderr -- "$EXE" -h unknown
  [ "$status" -eq 0 ]
  [[ "$output" == Usage:* ]]
}

@test "help manpage topic dumps the man page" {
  run --separate-stderr -- "$EXE" -h manpage
  [ "$status" -eq 0 ]
  assert_output_contains '.TH "ASCIIDOCTOR"'
  assert_output_contains 'Manual: Asciidoctor Manual'
}

@test "help syntax topic shows the syntax reference" {
  run --separate-stderr -- "$EXE" -h syntax
  [ "$status" -eq 0 ]
  assert_output_contains '= AsciiDoc Syntax'
  assert_output_contains '== Text Formatting'
}

@test "version flag prints version and runtime" {
  run --separate-stderr -- "$EXE" -V
  [ "$status" -eq 0 ]
  assert_output_contains 'Asciidoctor '
  assert_output_contains '[https://asciidoctor.org]'
  assert_output_contains 'Runtime Environment'
}

@test "long version flag prints version and runtime" {
  run --separate-stderr -- "$EXE" --version
  [ "$status" -eq 0 ]
  assert_output_contains 'Asciidoctor '
  assert_output_contains '[https://asciidoctor.org]'
  assert_output_contains 'Runtime Environment'
}

@test "bare verbose flag prints the version" {
  run --separate-stderr -- "$EXE" -v
  [ "$status" -eq 0 ]
  assert_output_contains 'Asciidoctor '
  assert_output_contains 'Runtime Environment'
}

@test "missing input reports usage with non-zero exit" {
  run --separate-stderr -- "$EXE"
  [ "$status" -eq 1 ]
  assert_stderr_contains 'Usage:'
}

@test "missing input file reports an error" {
  run --separate-stderr -- "$EXE" no-such-file.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'input file no-such-file.adoc is missing'
}

@test "directory input reports an error" {
  mkdir -p somedir
  run --separate-stderr -- "$EXE" somedir
  [ "$status" -eq 1 ]
  assert_stderr_contains 'is a directory, not a file'
}

@test "invalid option reports an error and usage" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" --foobar input.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'invalid option: --foobar'
  assert_output_contains 'Usage:'
}

@test "invalid option argument reports an error" {
  printf 'content\n' > input.adoc
  run --separate-stderr -- "$EXE" -d chapter input.adoc
  [ "$status" -eq 1 ]
  assert_stderr_contains 'invalid argument: -d chapter'
}

@test "missing option argument reports an error" {
  run --separate-stderr -- "$EXE" -b
  [ "$status" -eq 1 ]
  assert_stderr_contains 'option missing argument: -b'
}

@test "accepts document from stdin and writes to stdout" {
  printf 'content\n' > stdin.adoc
  run --separate-stderr -- "$EXE" -e -o - - < stdin.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  assert_output_contains '<p>content</p>'
}

@test "stdin input defaults to stdout output" {
  printf 'content\n' > stdin.adoc
  run --separate-stderr -- "$EXE" -e - < stdin.adoc
  [ "$status" -eq 0 ]
  assert_output_contains '<p>content</p>'
}

@test "accepts document from stdin and writes to output file" {
  printf 'content\n' > stdin.adoc
  run --separate-stderr -- "$EXE" -e -o from-stdin.html - < stdin.adoc
  [ "$status" -eq 0 ]
  [ -f from-stdin.html ]
  assert_contains from-stdin.html '<p>content</p>'
}
