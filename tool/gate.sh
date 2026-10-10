#!/usr/bin/env bash
# The quality gate, in two tiers (ADR-0022):
#
#   tool/gate.sh [fast]   every commit, about half a minute: formatting,
#                         analysis, and ptome's tests but the slow ones (the
#                         corpus included, held to test/corpus/red.txt)
#   tool/gate.sh full     before a push: the same over every test, with the
#                         coverage floor (packages/ptome/tool/coverage_floor.txt),
#                         the API and JavaScript projection checks, the CLI
#                         on a built executable (bats), the plain_* packages,
#                         and the suites on Node.js and the npm package
#   tool/gate.sh ptome    the full tier's ptome part alone (CI's gate job;
#                         other jobs run the packages and Node.js in parallel)
#
# Live oracles (the gem, asciidoctor-epub3, EPUBCheck) never run here; the
# nightly CI workflow runs them. Tools a step needs and the machine lacks
# (pdftoppm, unzip, bats, node) skip that step with a note; CI has them.
# Scratch files go to $TMPDIR (default /tmp).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tier="${1:-fast}"
case "$tier" in fast|full|ptome) ;; *) echo "usage: tool/gate.sh [fast|full|ptome]" >&2; exit 64 ;; esac
work="${TMPDIR:-/tmp}/ptome-gate"
rm -rf "$work" && mkdir -p "$work"
failed=()
step() { printf '== %s\n' "$1"; }
fail() { failed+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }

cd "$root"
step format
dart format --output=none --set-exit-if-changed packages >/dev/null || fail format
step analyze
dart analyze --fatal-infos . | tail -1 || fail analyze

cd "$root/packages/ptome"
have pdftoppm || echo "(no pdftoppm: PDF pages are compared by hash only)"
if [ "$tier" = fast ]; then
  step "ptome tests (but slow)"
  dart test -x slow --file-reporter "json:$work/tests.json" -r failures-only \
    > "$work/tests.log" 2>&1
else
  step "build the executable"
  dart compile exe -o "$work/ptome" bin/ptome.dart >/dev/null || fail "build"
  export PTOME_EXE="$work/ptome"
  step "ptome tests, with coverage"
  dart test --branch-coverage --coverage="$work/coverage" \
    --file-reporter "json:$work/tests.json" -r failures-only \
    > "$work/tests.log" 2>&1
fi
dart run tool/corpus_red.dart "$work/tests.json" || {
  echo "(the run's output: $work/tests.log)"
  fail tests
}

if [ "$tier" != fast ]; then
  step coverage
  dart run tool/coverage_gate.dart "$work/coverage" || fail coverage
  step "public API and JavaScript projection"
  dart run tool/api_check.dart | tail -1 || fail api
  dart run tool/generate_js.dart --check || fail js
  step "CLI (bats, the built executable)"
  if have bats; then
    ASCIIDOCTOR_EXE="$PTOME_EXE" bats test/e2e/ > "$work/bats.log" 2>&1 || {
      grep '^not ok' "$work/bats.log"
      fail bats
    }
    tail -1 "$work/bats.log"
  else
    echo "(no bats: skipped)"
  fi
fi

if [ "$tier" = full ]; then
  cd "$root"
  for pkg in packages/plain_*/; do
    step "$pkg"
    (cd "$pkg" && dart test -r failures-only | tail -1) || fail "$pkg"
    if [ -f "$pkg/tool/api_check.dart" ]; then
      (cd "$pkg" && dart run tool/api_check.dart | tail -1) || fail "$pkg api"
    fi
  done
  cd "$root/packages/ptome"
  if have node; then
    step "ptome tests on Node.js"
    dart test -p node -x corpus -r failures-only | tail -1 || fail node
    step "npm package"
    if ./tool/build-npm.sh > "$work/npm.log" 2>&1; then
      (cd test/npm && npm ci --silent >/dev/null 2>&1 &&
        node --test > "$work/npm-test.log" 2>&1) || fail npm
      grep -E '^ℹ (pass|fail)|^✖' "$work/npm-test.log" | head -12
    else
      tail -5 "$work/npm.log"
      fail "npm build"
    fi
  else
    echo "(no node: the Node.js and npm suites skipped)"
  fi
fi

if [ ${#failed[@]} -eq 0 ]; then
  echo "gate ($tier): green"
else
  echo "gate ($tier): FAILED: ${failed[*]}"
  exit 1
fi
