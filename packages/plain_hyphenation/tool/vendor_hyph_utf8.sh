#!/usr/bin/env bash
# Vendors the hyphenation patterns of hyph-utf8 (github.com/hyphenation/
# tex-hyphen, pinned) for the languages whose licences let the package
# distribute them: MIT, BSD, LPPL, public domain, Unlicense and the
# all-permissive notices (not the GPL, LGPL or MPL ones, nor those with
# none). Writes vendor/hyph-utf8/patterns/<lang>.pat.txt (and .hyp.txt,
# the exceptions), vendor/hyph-utf8/languages.json (each language's
# hyphenmins and licence) and vendor/hyph-utf8/NOTICES.md (each file's
# notice), then embeds them (tool/generate_patterns.dart).
set -euo pipefail
cd "$(dirname "$0")/.."
SHA=5684c0f51c0b81133db2efbe60a408b4155a3ff5
BASE=https://raw.githubusercontent.com/hyphenation/tex-hyphen/$SHA/hyph-utf8/tex/generic/hyph-utf8/patterns
LANGS="af ar as be bg bn ca cop cu cy da de-1901 de-1996 de-ch-1901 el-monoton el-polyton en-gb en-us eo es et eu fa fi-x-school fi fr fur ga gl grc gu he hi hr hsb ia is it ka kk kmr kn la-x-classic la lt ml mn-cyrl mr mul-ethi nb nl nn no oc or pa pi pl pms pt rm ru sa sh-cyrl sh-latn sk sl sq sv ta te th tk tr uk vi zh-latn-pinyin "
OUT=vendor/hyph-utf8
rm -rf "$OUT" && mkdir -p "$OUT/patterns" "$OUT/tex"
for lang in $LANGS; do
  # A language without patterns (hyph-utf8 keeps some as placeholders) is
  # left out.
  if ! curl -sSfL -o "$OUT/patterns/$lang.pat.txt" "$BASE/txt/hyph-$lang.pat.txt"; then
    rm -f "$OUT/patterns/$lang.pat.txt"
    continue
  fi
  curl -sSfL -o "$OUT/patterns/$lang.hyp.txt" "$BASE/txt/hyph-$lang.hyp.txt" || rm -f "$OUT/patterns/$lang.hyp.txt"
  curl -sSfL -o "$OUT/tex/hyph-$lang.tex" "$BASE/tex/hyph-$lang.tex"
done
dart run tool/hyph_metadata.dart "$OUT" "$SHA"
rm -rf "$OUT/tex"
dart run tool/generate_patterns.dart
