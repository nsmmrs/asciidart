#!/usr/bin/env bash
# Regenerates man/asciidart.1 from man/asciidart.adoc with asciidart itself,
# then refreshes the copy embedded for -h manpage.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date -u +%s)}" \
  dart run bin/asciidart.dart -b manpage -o man/asciidart.1 man/asciidart.adoc
dart run tool/embed_data.dart
dart format lib/src/cli/help_topics.g.dart >/dev/null
