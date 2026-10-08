#!/usr/bin/env bats
# Black-box conversion cases from features/text_formatting.feature.
# Golden assertions: byte-exact via `-o -` (stdout) diff.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "text formatting: superscript and subscript to html" {
  cat > input.adoc <<'EOF'
_v_~rocket~ is the value
^3^He is the isotope
log~4~x^n^ is the expression
M^me^ White is the address
the 10^th^ point has coordinate (x~10~, y~10~)
EOF
  cat > expected.html <<'EOF'
<div class="paragraph">
<p><em>v</em><sub>rocket</sub> is the value
<sup>3</sup>He is the isotope
log<sub>4</sub>x<sup>n</sup> is the expression
M<sup>me</sup> White is the address
the 10<sup>th</sup> point has coordinate (x<sub>10</sub>, y<sub>10</sub>)</p>
</div>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}

@test "text formatting: ex-inline literal to html" {
  cat > input.adoc <<'EOF'
Use [x-]`{asciidoctor-version}` to print the version of Asciidoctor.
EOF
  cat > expected.html <<'EOF'
<div class="paragraph">
<p>Use <code>{asciidoctor-version}</code> to print the version of Asciidoctor.</p>
</div>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}

@test "text formatting: ex-inline monospaced to html" {
  cat > input.adoc <<'EOF'
:encoding: UTF-8

The document is assumed to be encoded as [x-]+{encoding}+.
EOF
  cat > expected.html <<'EOF'
<div class="paragraph">
<p>The document is assumed to be encoded as <code>UTF-8</code>.</p>
</div>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}
