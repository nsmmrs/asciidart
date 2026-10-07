# Web font fixtures

Noto Serif (SIL Open Font License 1.1; see
`vendor/asciidoctor-pdf/data/fonts/LICENSE-noto`), subset to Basic Latin
from the subsets vendored with asciidoctor-pdf:

- `notoserif-regular-ascii.woff2`: `pyftsubset notoserif-regular-subset.ttf
  --unicodes=U+0020-007E --name-IDs='*'`, then `woff2_compress`.
- `notoserif-bold-ascii.woff`: the same of `notoserif-bold-subset.ttf`,
  saved as WOFF with fontTools.
