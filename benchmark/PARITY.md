# Differential Parity Verdict

Byte-identical gate (ADR-0001 D4): the Dart CLI against the Asciidoctor
**2.0.26** gem, via `tool/differential.dart` (normalization: version stamps
and timestamps only). `master` targets 2.0.26 per
[ADR-0003](../adr/0003-target-latest-stable.md); the earlier port of
upstream `main` (2.1.0.alpha.0) is preserved on the `2.1.0` branch.

## Corpus

- `test/fixtures/**` (`*.adoc`, `*.asciidoc`, recursive) plus
  `data/reference/syntax.adoc`: 32 files per backend.
- `test/parity/**` plus `data/reference/syntax.adoc`: 10 files per backend.
  These pin the places where 2.0.26 differs from upstream `main` (tilde
  open blocks, ordered list starts, `link=self`, front matter, table and
  manpage layout, ...); see [`test/parity/README.md`](../test/parity/README.md).

## Method

From the repository root, with the gem on `PATH`
(`gem install asciidoctor -v 2.0.26`):

```sh
tool/build-exes.sh
tool/parity.sh dist/asciidoctor-linux-x64
```

`tool/parity.sh` runs both corpora on html5, docbook5 and manpage. Each file
is converted as `<exe> -b <backend> -o - -q <input>` with `TZ=UTC` and
`SOURCE_DATE_EPOCH=0`. CI runs the same script on every push, against the
native executable (`dart-exe-e2e` job) and against the npm package's CLI on
Node.js (`npm` job, `tool/parity.sh test/e2e/bin/asciidoctor-node`).

## Verdict (2026-10-04): PASS — 126/126 identical

| Corpus | html5 | docbook5 | manpage |
| --- | --: | --: | --: |
| fixtures | 32/32 | 32/32 | 32/32 |
| parity | 10/10 | 10/10 | 10/10 |

Warnings on stderr were compared by hand over the parity corpus and match
too (the harness passes `-q`). The e2e suite (`test/e2e/`, 134 tests) passes
with no skips against the Dart CLI, the Node.js CLI and the gem. The Node.js
CLI gives the same 126/126.

## Corpus check (2026-10-04): 17,896 of 17,900 conversions identical

Beyond the gate above, `tool/corpus_parity.dart` compares stdout, warnings
and exit codes over a large corpus of real documents: the Asciidoctor
repository at `v2.0.26` (fixtures, docs, and 1,451 snippets extracted from
its Ruby tests), the AsciiDoc language docs, Asciidoctor.js, the PDF, EPUB3,
Diagram and Maven plugin docs, Antora, git's `Documentation/`, and the
Quarkus, Hibernate and Spring Boot reference docs: 4,475 files, each
converted as html5, embedded html5, docbook5 and manpage.

```sh
tool/corpus/fetch.sh /tmp/corpus           # pinned in tool/corpus/sources.txt
dart run tool/corpus_parity.dart --exe-a asciidoctor \
  --exe-b dist/asciidoctor-linux-x64 --out /tmp/corpus-results /tmp/corpus
```

The reference is the 2.0.26 gem with CodeRay as its only optional gem, the
one optional library the port implements (with Rouge or Pygments installed,
the gem highlights where the port cannot). The check found and drove fixes
for: `cols=""`, `%autowidth` with a width, nested description list items
with attached blocks, line breaks in AsciiMath blocks, Ruby's ASCII-only
`\s` and `strip` against Unicode spaces, `\p{Blank}`, full case mapping
(`ß` → `SS`), a dropped table cell's line number, an empty block anchor
crash, and the missing "not available" warnings. `test/parity/` keeps
reproducers of each.

The 4 remaining differences are CodeRay highlighting of Java (see below).

## Known intentional differences

- Fatal errors are reported as one `asciidoctor: FAILED: <message>` line in
  plain wording, without Ruby exception classes, gem names or `Processing
  aborted.` (for example `asciidoctor: FAILED: failed to load <stdin>:
  missing converter for backend 'pdf'`). Log messages (warnings, errors)
  keep Asciidoctor's wording. Library callers catch `AsciidoctorException`.
- A reader that closes stdout early (`asciidoctor -o - doc.adoc | head`)
  ends the run quietly with exit code 0; the gem reports a broken pipe.
- Remote content (`allow-uri-read`) is read by the CLI and by the
  asynchronous API (`convertAsync`, `loadAsync`, ...), which fetch it over
  HTTP before converting; the synchronous API reads it only through an
  `AsciidoctorOptions.uriReader`. The `cache-uri` attribute keeps fetched
  content for later conversions in the same process instead of an on-disk
  cache (the gem needs the `open-uri-cached` gem for it).
- An unknown CLI option prints Ruby's `Did you mean?` hint only in Ruby;
  that suggestion engine depends on the Ruby version (see the notes at the
  top of `lib/src/cli/options.dart`).
- Dart-only features (Mustache templates, `init-config`, `-j/--jobs`) have
  no Ruby counterpart.
- `--help` and `-h manpage` describe `-T` and `-E` as they work in this
  build (Mustache templates) instead of mentioning tilt and gems.
- The Ruby-only options `-r/--require`, `-I/--load-path`, `--eruby` and
  `-w/--warnings` do not exist here and are rejected as unknown options;
  extensions are compiled into a custom binary instead (see
  `asciidoctor init-config`). `-q` silences log messages only, since there
  are no script warnings.
- Features the port does not implement warn in its own words, once, where
  the gem names a missing gem: `Rouge syntax highlighting is not available.
  Functionality disabled.` (likewise Pygments), and `AsciiMath to MathML
  conversion is not available. Functionality disabled.` for DocBook. The
  output is the gem's output without those gems.
- The `missing convert handler` warning names the converter by its Dart
  class (`ManpageConverter`) instead of the Ruby one
  (`Asciidoctor::Converter::ManPageConverter`).
- CodeRay highlights only Ruby and plain text: its other scanners are not
  ported, and a source block in another language with
  `source-highlighter=coderay` fails the conversion (the gem highlights it).
