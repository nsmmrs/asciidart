#!/usr/bin/env bats
# Black-box conversion cases from features/pass_block.feature.
# Golden assertions: byte-exact via `-o -` (stdout) diff.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "pass block: no substitutions by default to html" {
  cat > input.adoc <<'EOF'
:name: value

++++
<p>{name}</p>

image:tiger.png[]
++++
EOF
  cat > expected.html <<'EOF'
<p>{name}</p>

image:tiger.png[]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}

@test "pass block: no substitutions by default to docbook" {
  cat > input.adoc <<'EOF'
:name: value

++++
<simpara>{name}</simpara>

image:tiger.png[]
++++
EOF
  cat > expected.xml <<'EOF'
<simpara>{name}</simpara>

image:tiger.png[]
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  diff -u expected.xml actual.xml
}

@test "pass block: explicit subs to html" {
  cat > input.adoc <<'EOF'
:name: value

[subs="attributes,macros"]
++++
<p>{name}</p>

image:tiger.png[]
++++
EOF
  cat > expected.html <<'EOF'
<p>value</p>

<span class="image"><img src="tiger.png" alt="tiger"></span>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  diff -u expected.html actual.html
}
