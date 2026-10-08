# Vendored files

Files taken unchanged from other projects. `tool/vendor.sh` recreates them
from the pinned revisions below (`tool/vendor.sh --check` verifies them), and
regenerates the embedded copies in `lib/src/data.g.dart` and
`lib/src/cli/help_topics.g.dart`.

## asciidoctor/

From [Asciidoctor](https://github.com/asciidoctor/asciidoctor), MIT License
(`asciidoctor/LICENSE`).

| Path | Upstream revision | Used for |
| --- | --- | --- |
| `data/` | main (`30fb8cd5`) | the default stylesheets, locale attribute files and syntax reference, embedded in the library |
| `test/fixtures/` | main (`30fb8cd5`); upstream's `undef-dir-home.rb` is left out | the documents the tests and the parity gate convert |
| `benchmark/sample-data/mdbasics.adoc` | main (`30fb8cd5`) | benchmark input |
| `LICENSE` | v2.0.26 (`0b99b39c`) | upstream's license |

Change these files only through `tool/vendor.sh` (after changing its pinned
revisions); documents of our own belong in `test/parity/`.

## asciidoctor-epub3/

From [asciidoctor-epub3](https://github.com/asciidoctor/asciidoctor-epub3)
2.3.0, MIT License (`asciidoctor-epub3/LICENSE`, `NOTICE.adoc` lists the
fonts' and icons' licenses). `tool/vendor_epub3.sh` recreates the directory
from the gem and the `v2.3.0` tag, and regenerates
`lib/src/epub3/assets.g.dart`.

| Path | Used for |
| --- | --- |
| `styles/*.css` | the gem's SCSS stylesheets, compiled with the gem's Sass engine and options (byte for byte what the gem writes) |
| `fonts/` | the fonts the gem embeds in every EPUB (and the scripts' variants); Ptome embeds installed fonts only with `epub-embed-fonts`, and the tests and EPUB parity put these on the font path |
| `fonts/awesome/icons.tsv` | the Font Awesome names and code points, and renamed icons, from the gem's `icons.yml` and `shims.yml` |
| `images/` | the default avatar and headshot |
| `test/fixtures/` | the spec fixtures, converted by `tool/epub_parity.dart` |

## asciidoctor-pdf/

From [asciidoctor-pdf](https://github.com/asciidoctor/asciidoctor-pdf)
2.3.27, MIT License (`asciidoctor-pdf/LICENSE`), for the PDF backend.
`tool/vendor_asciidoctor_pdf.sh` recreates the directory from the gem (and
the icon fonts of prawn-icon 3.0.0, the gem's icon dependency) and the
`v2.3.27` tag, and regenerates `lib/src/pdf/assets.g.dart`.

| Path | Used for |
| --- | --- |
| `data/themes/` | the bundled themes (`base`, `default`, `default-sans`...) |
| `data/fonts/` | the gem's fonts (Noto Serif, Noto Sans, M+ 1mn, M+ 1p fallback, Noto Emoji subsets; `LICENSE-*` and `ABOUT-*` give their licenses and sources) and `fa-legacy-mapping.yml`; not compiled in: the tests set their PDFs in them |
| `icons/<set>/` | the icon fonts: Font Awesome Free 5.15.1 (`fas`, `far`, `fab`), Foundation Icons 3 (`fi`), PaymentFont (`pf`), each with its license; used by the tests, as `ptome doctor` installs them for users |
| `icons/<set>.tsv` | icon names and code points: Font Awesome's from the fonts' glyph names, Foundation Icons' and PaymentFont's from their projects' MIT-licensed style sheets |
| `test/spec/` | the spec suite (`*.rb`, `spec_helper/`, `fixtures/`; not the reference PNGs) |
| `test/examples/` | the example documents |

## highlight.js-styles/

The themes of [highlight.js](https://highlightjs.org) 11.12.0 (the release
hilite ports), BSD-3-Clause (`highlight.js-styles/LICENSE`): the minified
stylesheets of its `styles/` directory, which the modern PDF engine reads
for the colors of highlighted code (`highlightjs-theme`).
`tool/vendor_hljs_styles.sh` recreates the directory from the npm package
and regenerates `lib/src/highlight/hljs_styles.g.dart`.
