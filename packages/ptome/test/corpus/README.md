# The corpus

AsciiDoc documents and the output each implementation gives them: ptome's
black-box suite. `test/corpus_test.dart` converts every case with ptome and
compares the result with the one recorded for the `ptome` profile, one test
per case and format:

```sh
dart test test/corpus_test.dart                       # all of it, a few seconds
dart test test/corpus_test.dart -N 'curated/bugfix'   # the cases whose id matches
```

`packages/ptome_corpus_tools` writes the corpus (anchors from real
documents, the generator and fuzzer's finds, Asciidoctor's results); see its
README. When a change to ptome changes an output on purpose, record the new
result there with `dart run bin/corpus.dart regen -p ptome` and review the
diff of the `versions.toml` files.

## Layout

```text
profiles.toml     the implementations recorded: Asciidoctor 2.0.26, Asciidoctor main, ptome
defaults.toml     options every case starts from (fixed clock, safe mode, embedded output)
cases/<set>/<name>/
  case.toml       description, source, features, formats, options, attributes,
                  known-issues (formats not checked yet, with the reason)
  input.adoc      the document (one input, converted to each listed format)
  fixtures/       files it includes or references (base directory: the case directory)
  expected/       <format>.<hash>.<ext>: each distinct output once, by content hash
  versions.toml   [<format>.<profile>] output = "<hash>" | error = "...", log, divergence
```

The sets are `anchor` (real documents cut down and sanitized), `found` (the
generator and fuzzer's finds) and `curated` (hand-written, such as the
reproducers of fixed upstream bugs).

A PDF case also has the PDF the asciidoctor-pdf gem makes (the
`asciidoctor-pdf` profile), and ptome's PDF, with `asciidoctor-compat`,
must have the same pages, pixel for pixel (ADR-0022): `pixels` in
`versions.toml` says how they compare (`identical`, or where they first
differ). The test passes at once when ptome's PDF is the one recorded;
when it changed, it renders both PDFs (`pdftoppm`, page images kept in
`.dart_tool/corpus-pages`) and, when the pages are still identical,
records the new hash in the case (commit it). ptome's PDFs and EPUBs
aren't kept, only their hashes. Without `pdftoppm` a changed
PDF is skipped.

A recorded result is normalized narrowly, so that real differences show:
version stamps, the HTML footer's time and the manpage date are replaced,
and so are the case directory (`{base}`) and the working directory
(`{cwd}`) in outputs and messages. A hash is the first 12 hex digits of the
SHA-256 of the normalized output. A log entry is `severity:line: message`.
