#!/usr/bin/env bats
# Self-check for the corpus differential harness (ADR-0001 byte-identical
# parity gate). Validates the harness itself with no Dart port involved:
# the reference Ruby CLI (gem) must compare identical to itself, while an injected
# backend difference must be detected.
#
# Run from the repo root:
#   bats test/differential/selfcheck.bats

setup_file() {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  cd "$root" && dart pub get >&2
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUBY_EXE="asciidoctor"  # gem oracle on PATH
  cd "$REPO_ROOT"
}

@test "selfcheck: gem Ruby CLI vs itself is byte-identical (exit 0)" {
  run dart run tool/differential.dart --root "$REPO_ROOT" \
    --exe-a "$RUBY_EXE" --exe-b "$RUBY_EXE"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"files identical"* ]]
}

@test "selfcheck: html5 vs docbook5 backends are detected (exit 1 + diffs)" {
  run dart run tool/differential.dart --root "$REPO_ROOT" \
    --exe-a "$RUBY_EXE" --exe-b "$RUBY_EXE" \
    --backend-a html5 --backend-b docbook5
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIFF "* ]]
  [[ "$output" == *" differ"* ]]
}

@test "selfcheck: small injected diff renders a unified hunk" {
  local mini="$REPO_ROOT/test/differential/miniroot"
  run dart run tool/differential.dart --root "$mini" --extra-file '' \
    --exe-a "sh $REPO_ROOT/test/differential/bin/exe-a.sh" \
    --exe-b "sh $REPO_ROOT/test/differential/bin/exe-b.sh"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"@@ -"* ]]
  [[ "$output" == *"-line three from A"* ]]
  [[ "$output" == *"+line three from B"* ]]
}

@test "selfcheck: version-stamp-only differences normalize away (exit 0)" {
  local mini="$REPO_ROOT/test/differential/miniroot"
  run dart run tool/differential.dart --root "$mini" --extra-file '' \
    --exe-a "sh $REPO_ROOT/test/differential/bin/exe-ver-a.sh" \
    --exe-b "sh $REPO_ROOT/test/differential/bin/exe-ver-b.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"files identical"* ]]
}
