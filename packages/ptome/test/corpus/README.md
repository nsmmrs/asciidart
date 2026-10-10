# The corpus

AsciiDoc documents with the files the Asciidoctor command line writes for
them, and ptome checked against those files
([ADR-0022](../../../../adr/0022-the-corpus-is-the-gate.md)).

```text
goldens.yml           the release compared with, and the attributes every
                      conversion gets (a fixed clock and home)
<case>/
  input.adoc          the document, with the files it reads beside it
  case.yml            optional: formats, safe, doctype, attributes, source,
                      defects (formats whose golden shows an Asciidoctor
                      defect, with what it is: not compared)
  expected/<release>/<format>/<file>
                      the file Asciidoctor wrote (`input.html`, `input.xml`,
                      the man page, `input.pdf`, `input.epub`)
  ptome.yml           the last ptome PDF and EPUB found equal, by hash
```

## Running it

```sh
dart test -t corpus                     # all of it
dart test -t corpus -N asciidoctor-pdf  # the cases whose name matches
```

It is red until compatibility settings close every difference, so the rest
of the suite runs without it (`dart test -x corpus`), and CI runs it as a
job of its own.

ptome converts each case as the command line does (`-b <format> -D <dir>
input.adoc`), as a whole document, with `asciidoctor-compat`, the
attributes in `goldens.yml` and the case's own:

- **html5, xhtml5, docbook5, manpage:** its file must match the golden's
  bytes (the generator's name in its stamp aside). A failure shows the
  first line that differs.
- **pdf:** its pages, rendered by `pdftoppm` at 50 dpi, must equal the
  golden's pixel for pixel.
- **epub3:** the files in it (`unzip`) must equal the golden's.

A PDF or EPUB whose hash is in `ptome.yml` passes at once. When it changed
and still compares equal, the test records the new hash there: commit it.
Without `pdftoppm` or `unzip`, a changed one is skipped. Page images and
unpacked EPUBs are kept by hash in `.dart_tool/corpus`.

## Changing it

- **A difference** is closed in ptome, by a setting of the engine that
  `asciidoctor-compat` sets, never by editing a golden.
- **A defect** of Asciidoctor's (invalid or broken output, something it
  documents and doesn't do) is never reproduced: the case names it under
  `defects` in `case.yml`, and that format isn't compared.
- **A new case** is a folder with `input.adoc` (and `case.yml` when it
  needs options) and its goldens: `dart run bin/corpus.dart add NAME
  FILE -f html5 -f docbook5` in `packages/ptome_corpus_tools` writes both
  (or write the folder and run `goldens/generate.rb`). The anchor builder
  and the fuzzer's `promote` write cases the same way.
- **A new release** of Asciidoctor gets a bundle (`goldens/<release>/`),
  goldens in `expected/<release>/`, and `release` in `goldens.yml`.
- **A behavior ptome means to have and Asciidoctor doesn't** (a fixed bug)
  isn't a case here but a folder of `test/upstream_fixes`.
