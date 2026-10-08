# Test fonts

The same fonts as plain_pdf's tests use (`packages/plain_pdf/test/fonts`,
whose README says how each was made):

- `notoserif-regular-latin.ttf`: Noto Serif, Latin subset, distributed with
  asciidoctor-epub3 2.3.0 (Apache License 2.0,
  https://www.apache.org/licenses/LICENSE-2.0; © Google).
- `notoserif-kern-subtables.ttf`: `notoserif-regular-latin.ttf` with a
  `kern` table of two subtables (A V −80; then T o −60 and A V −40).
- `notoserif-features.ttf`: Noto Serif 2.015, Basic Latin, with the
  `onum`, `smcp`, `liga` and `kern` features (SIL Open Font License 1.1,
  https://openfontlicense.org; © 2022 The Noto Project Authors).
- `libertinus-smcp.otf`: Libertinus Serif 7.051, "Abc", whose `smcp` is a
  multiple substitution (SIL Open Font License 1.1; © the Libertinus
  Project Authors).
- `notosansmath-subset.ttf`: Noto Sans Math 3.000, subset to ASCII, the
  Greek letters, the math italic letters and the operators the math tests
  use, its `MATH` table kept (SIL Open Font License 1.1; © 2022 The Noto
  Project Authors).
