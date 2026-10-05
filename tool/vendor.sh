#!/usr/bin/env bash
# Refresh vendor/asciidoctor/ from upstream Asciidoctor at pinned revisions
# (see vendor/README.md), then regenerate the embedded data.
#
# Usage: tool/vendor.sh [--check]
#   --check  only report whether vendor/asciidoctor/ matches upstream
#            (exit status 1 when it does not)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo=https://github.com/asciidoctor/asciidoctor.git
# The 2.0.x release (for its license).
release=0b99b39c9df884d4aec13bba45f03cdbab505769 # v2.0.26
# Upstream main, which this branch matches (2.1.0.alpha.0).
main=30fb8cd5f7145c57274b04524ceaa99812f830e0 # 2026-09-01

check=false
case "${1:-}" in
  --check) check=true ;;
  "") ;;
  *) echo "usage: tool/vendor.sh [--check]" >&2; exit 2 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
  local rev="$1" dir="$tmp/$1"
  git init -q "$dir"
  git -C "$dir" remote add origin "$repo"
  git -C "$dir" fetch -q --depth 1 origin "$rev"
  git -C "$dir" checkout -q FETCH_HEAD
}
fetch "$release"
fetch "$main"

out="$tmp/out"
mkdir -p "$out/test" "$out/benchmark/sample-data"
cp "$tmp/$release/LICENSE" "$out/LICENSE"
cp -R "$tmp/$main/data" "$out/data"
cp -R "$tmp/$main/test/fixtures" "$out/test/fixtures"
# A Ruby helper for a Ruby-only test; the port has no use for it.
rm "$out/test/fixtures/undef-dir-home.rb"
cp "$tmp/$main/benchmark/sample-data/mdbasics.adoc" "$out/benchmark/sample-data/"

target="$root/vendor/asciidoctor"
if $check; then
  if diff -r "$out" "$target" > "$tmp/diff"; then
    echo "vendor: vendor/asciidoctor matches upstream"
  else
    cat "$tmp/diff"
    echo "vendor: vendor/asciidoctor differs from upstream" >&2
    exit 1
  fi
  exit 0
fi

rm -rf "$target"
mkdir -p "$(dirname "$target")"
cp -R "$out" "$target"
(cd "$root" && dart run tool/embed_data.dart >/dev/null \
  && dart format lib/src/data.g.dart lib/src/cli/help_topics.g.dart >/dev/null)
echo "vendor: refreshed vendor/asciidoctor and the embedded data"
