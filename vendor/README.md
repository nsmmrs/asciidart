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
