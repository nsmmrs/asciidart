#!/usr/bin/env bats
# Black-box conversion cases from features/open_block.feature.
# Golden assertions: byte-exact via `-o -` (stdout) diff, or fixed-fragment
# assertions mirroring the feature's HTML/XML structure expectations.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "open block: paragraph to html matches source exactly" {
  cat > input.adoc <<'EOF'
--
A paragraph in an open block.
--
EOF
  cat > expected.html <<'EOF'
<div class="openblock">
<div class="content">
<div class="paragraph">
<p>A paragraph in an open block.</p>
</div>
</div>
</div>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}

@test "open block: paragraph to docbook matches source exactly" {
  cat > input.adoc <<'EOF'
--
A paragraph in an open block.
--
EOF
  cat > expected.xml <<'EOF'
<simpara>A paragraph in an open block.</simpara>
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  diff -u expected.xml actual.xml
}

@test "open block: paragraph to html has openblock structure" {
  cat > input.adoc <<'EOF'
--
A paragraph in an open block.
--
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<div class="openblock">'
  assert_contains actual.html '<div class="content">'
  assert_contains actual.html '<div class="paragraph">'
  assert_contains actual.html '<p>A paragraph in an open block.</p>'
}

@test "open block: paragraph to docbook has simpara structure" {
  cat > input.adoc <<'EOF'
--
A paragraph in an open block.
--
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<simpara>A paragraph in an open block.</simpara>'
}

@test "open block: list to html has nested list structure" {
  cat > input.adoc <<'EOF'
--
* one
* two
* three
--
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<div class="openblock">'
  assert_contains actual.html '<div class="content">'
  assert_contains actual.html '<div class="ulist">'
  assert_contains actual.html '<ul>'
  assert_contains actual.html '<p>one</p>'
  assert_contains actual.html '<p>two</p>'
  assert_contains actual.html '<p>three</p>'
}
