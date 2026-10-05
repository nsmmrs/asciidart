# Parity with Asciidoctor

The `bugfix` branch is the `2.1.0` branch plus fixes for bugs Asciidoctor
still has; every output difference they make is listed under
[Upstream bugs fixed on the bugfix branch](#upstream-bugs-fixed-on-the-bugfix-branch),
and everything else below holds as on `2.1.0`.

On the `2.1.0` branch, asciidart is compatible with Asciidoctor's
development version (upstream `main` at `30fb8cd5`, reporting
2.1.0.alpha.0), and this file is the
ledger of that claim: the gates below compare it with the gem, and every
difference that remains is deliberate and listed under
[Known intentional differences](#known-intentional-differences).

Byte-identical gate (ADR-0001 D4): the asciidart CLI against the
Asciidoctor gem built from upstream `main` at `30fb8cd5`, via
`tool/differential.dart` (normalization: version stamps and timestamps
only). `master` targets 2.0.26 per
[ADR-0003](../adr/0003-target-latest-stable.md); this branch re-implements
upstream's changes since 2.0.26 on master's architecture (the original
port of main is tagged `archive/2.1.0-original-port`). The 2.0.26 numbers
below come from master; this branch's gates run against the main gem.

## Corpus

- `vendor/asciidoctor/test/fixtures/**` (upstream's fixtures, `*.adoc`,
  `*.asciidoc`, recursive) plus
  `vendor/asciidoctor/data/reference/syntax.adoc`: 30 files per backend.
- `test/parity/**` (documents of our own) plus the syntax reference: 12 files
  per backend. These pin the places where 2.0.26 differs from upstream
  `main` (tilde open blocks, ordered list starts, `link=self`, front matter,
  table and manpage layout, ...) and the differences the corpus check found;
  see [`test/parity/README.md`](../test/parity/README.md).

## Method

From the repository root, with the gem on `PATH`
(`gem install asciidoctor -v 2.0.26`):

```sh
tool/build-exes.sh
tool/parity.sh dist/asciidart-linux-x64
```

`tool/parity.sh` runs both corpora on html5, docbook5 and manpage. Each file
is converted as `<exe> -b <backend> -o - -q <input>` with `TZ=UTC` and
`SOURCE_DATE_EPOCH=0`. CI runs the same script on every push, against the
native executable (`dart-exe-e2e` job) and against the npm package's CLI on
Node.js (`npm` job, `tool/parity.sh test/e2e/bin/asciidart-node`).

## Verdict (2026-10-05): PASS — 126/126 identical

| Corpus | html5 | docbook5 | manpage |
| --- | --: | --: | --: |
| fixtures | 30/30 | 30/30 | 30/30 |
| parity | 12/12 | 12/12 | 12/12 |

Warnings on stderr were compared by hand over the parity corpus and match
too (the harness passes `-q`). The e2e suite (`test/e2e/`, 134 tests) passes
with no skips against the Dart CLI, the Node.js CLI and the gem. The Node.js
CLI gives the same 126/126.

## Corpus check (2026-10-05): 17,900 of 17,900 conversions identical

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
  --exe-b "dist/asciidart-linux-x64 -a highlightjs-mode=client" \
  --out /tmp/corpus-results /tmp/corpus
```

The reference is the 2.0.26 gem without optional gems (asciidart provides
none of Rouge, Pygments, CodeRay or AsciiMath, and behaves as the gem does
without them), and asciidart runs with `highlightjs-mode=client` so that
documents using highlight.js compare with the gem's browser markup (see the
intentional differences). The check found and drove fixes
for: `cols=""`, `%autowidth` with a width, nested description list items
with attached blocks, line breaks in AsciiMath blocks, Ruby's ASCII-only
`\s` and `strip` against Unicode spaces, `\p{Blank}`, full case mapping
(`ß` → `SS`), a dropped table cell's line number, an empty block anchor
crash, and the missing "not available" warnings. `test/parity/` keeps
reproducers of each.

## Known intentional differences

- asciidart names itself: the HTML generator meta tag and the man page
  header say `Asciidart <version>` (`{asciidart-version}`) instead of
  `Asciidoctor 2.0.26`; `--version` prints `Asciidart <version> (compatible
  with Asciidoctor 2.0.26) [https://github.com/nsmmrs/asciidart]` and a
  runtime line naming the Dart runtime; `--help` shows `asciidart` in its
  usage lines; `-h manpage` prints asciidart(1); and messages start with
  `asciidart:` (`asciidart: WARNING: ...`) instead of `asciidoctor:`. The
  `asciidoctor` and `asciidoctor-version` attributes keep their values, so
  documents see the same thing as under the gem. The parity tools treat
  either name as the same stamp or prefix.
- Fatal errors are reported as one `asciidart: FAILED: <message>` line in
  plain wording, without Ruby exception classes, gem names or `Processing
  aborted.` (for example `asciidart: FAILED: failed to load <stdin>:
  missing converter for backend 'pdf'`). Log messages (warnings, errors)
  keep Asciidoctor's wording. Library callers catch `AsciidoctorException`.
- A reader that closes stdout early (`asciidart -o - doc.adoc | head`)
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
  `asciidart init-config`). `-q` silences log messages only, since there
  are no script warnings.
- highlight.js is asciidart's syntax highlighter, and highlights at
  conversion: with `source-highlighter=highlight.js`, source blocks come out
  highlighted (by hilite, a Dart port of highlight.js 11.12.0, byte for byte
  what highlight.js produces in the browser), and the page links only the
  theme's stylesheet (highlight.js 11.12.0 on the CDN, or `highlightjsdir`).
  The gem's behavior, markup for the browser plus the highlight.js 9.18.3
  scripts, is `highlightjs-mode=client`. Blocks with callouts have their
  spans closed at each line end, so the callout numbers sit outside them.
- Rouge, Pygments and CodeRay are not available: they behave as the gem does
  without their gems (no highlighting, the highlighter's `<pre>` class kept),
  and warn in asciidart's words, once: `Rouge syntax highlighting is not
  available. Functionality disabled.` (likewise Pygments and CodeRay).
  `AsciiMath to MathML conversion is not available. Functionality disabled.`
  is the DocBook counterpart for AsciiMath.
- The `missing convert handler` warning names the converter by its Dart
  class (`ManpageConverter`) instead of the Ruby one
  (`Asciidoctor::Converter::ManPageConverter`).

## EPUB3 (`-b epub3`)

The native executable converts to EPUB 3 as the asciidoctor-epub3 2.3.0
gem does on the asciidoctor gem built from upstream `main`
(2.1.0.alpha.0), checked file by file by
`tool/epub_parity.dart`: the entries of the EPUB, their order (`mimetype`
first, stored), and the bytes of every file once the dates that change
with each run (`dcterms:modified`, `dc:date`) are set aside; the messages
too. ZIP compression is not compared (zlib versions differ). With
`--epubcheck`, EPUBCheck must report the same for both EPUBs.

```sh
# With the gem built from main installed (see above), so that it isn't
# replaced by the 2.0 release asciidoctor-epub3 would pull in:
gem install gepub -v 1.0.17 && gem install mime-types sass
gem install asciidoctor-epub3 -v 2.3.0 --ignore-dependencies
dart run tool/epub_parity.dart --exe-a "$(command -v asciidoctor-epub3)" \
  --exe-b dist/asciidart-linux-x64 --epubcheck epubcheck.jar \
  $(find vendor/asciidoctor-epub3/test/fixtures -name '*.adoc')
```

Verdict (2026-10-05): the 72 documents of the gem's spec fixtures
(`vendor/asciidoctor-epub3/test/fixtures`, run in CI) are identical, with
the same EPUBCheck reports. On `master` (Asciidoctor 2.0.26), so are 499
of a 500-document sample of the corpus (the 136 books and 364 other
documents), the one left being the first difference below.

Intentional differences:

- A preamble whose only block is a list becomes the abstract, as in the
  gem, but its list is written as a list: the gem writes a dump of Ruby
  objects there (Asciidoctor's `List#content` is the array of items).
- AsciiMath stays text, as in the gem without the asciimath gem, and the
  warning says so in asciidart's words (`AsciiMath to MathML conversion is
  not available. Functionality disabled.`); likewise the highlighters.
- A custom theme (`epub3-stylesdir`) is read as compiled CSS (`epub3.css`,
  `epub3-css3-only.css`): the gem compiles SCSS, for which asciidart has no
  compiler.
- `revdate` is read in the forms Asciidoctor and documents use (ISO 8601,
  `2026-01-31`, `31 January 2026`, `January 31, 2026`...); Ruby's
  `Time.parse` reads more, so a date in another form is reported as not
  parseable and the document date is used.
- Writing to standard output (`-o -`) is refused with a message; the gem
  fails with an internal error.
- The EPUB3 backend is in the native executable only, not in the npm
  package (see [ADR-0009](../adr/0009-epub3-backend.md)).

## Upstream bugs fixed on the bugfix branch

Bugs reported upstream that the gem built from `main` at `30fb8cd5` still
has (see the [triage](../doc/upstream-triage.md)). Each has a test in
[`test/bugfix/`](../test/bugfix/README.md) that fails on that gem and
passes here; `tool/bugfix_check.sh` checks both, in CI and in the gates.
Documents that don't hit these cases convert as on `2.1.0`.

- Section IDs: a title made only of punctuation gets the separator (`_`,
  then `__2`) instead of an empty ID (#4877). A footnote in a section
  title is numbered where the title is converted, in document order, and
  is left out of the generated ID (`_h3`, not `_h31`) (#2903).
- Man pages: a font span nested in another closes by switching back to
  the outer span's font, and the outer span then closes with `\fR`, so
  the text after it is roman (#4875).
- Tables: a cell takes the spec (alignment, style) of the column it is
  in, counting the columns covered by colspans and by rowspans from rows
  above, instead of the column at its index in the row (#4500, #989,
  #1558, #2889); repeated cells in a first row without `cols` number their
  columns in order (`col_1` to `col_4`, not `col_1`, `col_3`, `col_5`,
  `col_4`). A record of `cols` that isn't a column spec is warned about
  (`invalid column spec in cols attribute: 20strong; using a default
  column`) and stands for a default column instead of being dropped
  (#3349); when no record is valid, the first row still decides the
  columns. Tabs in literal cells expand to `tabsize` (#3412). In an
  AsciiDoc cell, line comments reach the cell's document, so a
  comment-like line in a verbatim block is kept and a comment separates
  two lists (#2496, #2648).
- Paths: a `..` after a doubled slash removes the directory before the
  slashes (`X//../dir` is `dir`) (#4419).
- Author attributes: an assigned `firstname`, `middlename`, `lastname` or
  `authorinitials` (or an indexed one) wins over the one computed from the
  `author` or `authors` attribute (#4209).
- Inline: a superscript or subscript treats a bracketed span inside it as
  one unit, so `^link:fn.html[2^]^` nests the link (#4076). Link text
  holding an element converted before the link (an embedded icon) is not
  read as an attribute list unless it has an `=` outside that element's
  markup (#4075). The anchor shorthand takes `\]` in its reference text
  (#3788). Anchors in section titles are cataloged, so duplicates are
  reported and their reference text is used (#3633). `--` between a word
  and formatted text or a curved quote (on either side) becomes an em dash
  (#1578, #3946). A bare URL ending with a character reference
  (`http://<host>:<port>`) keeps its `;` (#3128).
- Blocks: a line that starts with `[` and ends with `]` is not a block
  attribute line when a `]` in it closes no `[` (outside double quotes)
  and a `[` follows, so `[.red]#Bbb# bbb.footnote:[Bbb.]` is a paragraph
  (#3396); a stray `]` at the end (`[source, xml]]`) still ends an
  attribute list. A list
  continuation after empty lines attaches its block one level up from the
  innermost item per empty line, so one empty line attaches to the parent
  of the innermost item (#2293).
- HTML: section and discrete headings deeper than level 5 use `<h6>`
  (#2032). A quote in an image target or attribute (`src`, `href`,
  `width`, `title`, float, align, roles) is written as `&quot;` (#2862,
  #2661).
