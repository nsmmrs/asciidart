#!/usr/bin/env bash
# Byte-identical parity gate against the Asciidoctor gem (ADR-0003).
#
# Runs tool/differential.dart over the fixture corpus (plus
# vendor/asciidoctor/data/reference/syntax.adoc) and the parity corpus in test/parity, on the
# html5, docbook5 and manpage backends. Exits nonzero on any difference.
#
# Usage: tool/parity.sh DART_EXE [RUBY_EXE]
#   DART_EXE  the Dart CLI to check (e.g. build/asciidoctor)
#   RUBY_EXE  the reference CLI (default: asciidoctor, the gem on PATH)
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo 'usage: tool/parity.sh DART_EXE [RUBY_EXE]' >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_exe="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ruby_exe="${2:-asciidoctor}"

status=0
for corpus in vendor/asciidoctor/test/fixtures test/parity; do
  for backend in html5 docbook5 manpage; do
    echo "== $corpus ($backend)"
    dart run "$root/tool/differential.dart" --root "$root" -q \
      --corpus-dir "$corpus" --backend "$backend" \
      --exe-a "$ruby_exe" --exe-b "$dart_exe" || status=1
  done
done
exit "$status"
