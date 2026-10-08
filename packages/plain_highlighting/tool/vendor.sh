#!/usr/bin/env bash
# Recreates vendor/highlight.js from the pinned upstream release: the engine
# sources (the reference for lib/src), the language definitions (the input of
# the generator's callbacks) and the markup and detection tests.
#
# Usage: tool/vendor.sh [--check]
#   --check  compare instead of writing; exit 1 when vendor/ differs
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
url=https://github.com/highlightjs/highlight.js.git
tag=11.12.0
commit=f7f7d3803bd898e37c017ffb881317f0cde04a70
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$url" "$tmp/src"
actual="$(git -C "$tmp/src" rev-parse HEAD)"
if [ "$actual" != "$commit" ]; then
  echo "vendor.sh: $tag is $actual, expected $commit" >&2
  exit 1
fi
out="$tmp/vendor/highlight.js"
mkdir -p "$out/src" "$out/test"
cp "$tmp/src/LICENSE" "$out/"
cp -r "$tmp/src/src/lib" "$tmp/src/src/languages" "$tmp/src/src/highlight.js" "$out/src/"
cp -r "$tmp/src/test/markup" "$tmp/src/test/detect" "$out/test/"
if [ "${1:-}" = "--check" ]; then
  diff -r "$out" "$root/vendor/highlight.js" >/dev/null || {
    echo "vendor.sh: vendor/highlight.js differs from $tag" >&2
    exit 1
  }
  echo "vendor.sh: vendor/highlight.js matches $tag ($commit)"
else
  rm -rf "$root/vendor/highlight.js"
  cp -r "$out" "$root/vendor/"
  echo "vendor.sh: wrote vendor/highlight.js from $tag ($commit)"
fi
