#!/usr/bin/env bash
# Fetch the parity corpus (tool/corpus/sources.txt) into DIR, then extract
# the snippets of Asciidoctor's Ruby tests.
#
# Usage: tool/corpus/fetch.sh DIR
# Then:  dart run tool/corpus_parity.dart --exe-b EXE --out OUT DIR
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dir="${1:?usage: tool/corpus/fetch.sh DIR}"
mkdir -p "$dir"
grep -v '^#' "$root/tool/corpus/sources.txt" | while read -r name url commit sparse; do
  [ -z "$name" ] && continue
  target="$dir/$name"
  if [ ! -d "$target/.git" ]; then
    git init -q "$target"
    git -C "$target" remote add origin "$url"
  fi
  if [ -n "${sparse:-}" ]; then
    git -C "$target" sparse-checkout set ${sparse//,/ }
  fi
  git -C "$target" fetch -q --depth 1 --filter=blob:none origin "$commit"
  git -C "$target" checkout -q --detach FETCH_HEAD
  echo "fetched $name"
done
dart run "$root/tool/corpus/extract_snippets.dart" "$dir/asciidoctor/test"
