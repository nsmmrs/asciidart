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
| `data/` | v2.0.26 (`0b99b39c`) | the default stylesheets, locale attribute files and syntax reference, embedded in the library |
| `test/fixtures/` | v2.0.26 (`0b99b39c`), except `with-front-matter.adoc` from main (`30fb8cd5`); upstream's `undef-dir-home.rb` is left out | the documents the tests and the parity gate convert |
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
| `fonts/` | the fonts every EPUB carries (and the scripts' variants) |
| `fonts/awesome/icons.tsv` | the Font Awesome names and code points, and renamed icons, from the gem's `icons.yml` and `shims.yml` |
| `images/` | the default avatar and headshot |
| `test/fixtures/` | the spec fixtures, converted by `tool/epub_parity.dart` |
