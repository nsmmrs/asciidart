#!/usr/bin/env bash
# Vendors the themes of highlight.js 11.12.0 (the release hilite ports;
# BSD-3-Clause) for the PDF backend's syntax highlighting: the minified
# stylesheets of styles/ (not base16/) into vendor/highlight.js-styles,
# with the licence, then embeds them (tool/embed_hljs_styles.dart).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=11.12.0
OUT=vendor/highlight.js-styles
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -sSfL "https://registry.npmjs.org/highlight.js/-/highlight.js-$VERSION.tgz" | tar -xz -C "$TMP"
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$TMP"/package/styles/*.min.css "$OUT"/
cp "$TMP"/package/LICENSE "$OUT"/LICENSE
echo "highlight.js $VERSION styles/*.min.css" > "$OUT"/VERSION
dart run tool/embed_hljs_styles.dart
