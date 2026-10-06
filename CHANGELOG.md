# Changelog

## 0.1.0 (unreleased)

First release of asciidart, an AsciiDoc processor for Dart compatible with
the Asciidoctor **2.0.26** release. Not affiliated with or endorsed by the
Asciidoctor project.

- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor 2.0.26 gem on every backend, checked in
  CI by `tool/parity.sh` over the fixture and parity corpora; the end-to-end
  CLI suite (134 tests) passes against both asciidart and the gem.
- A small, typed public API designed from usage scenarios
  (`doc/api.md`): an `Asciidart` configuration (safe mode, attributes,
  extensions, an HTML override, highlighters, Mustache templates) with
  `parse`, `parseHeader`, `convert` and asynchronous variants; the default
  configuration `asciidoc`; a sealed tree of typed nodes (`Section`,
  `Paragraph`, `Listing`, `Admonition`, lists, tables, inline elements)
  with `descendants<T>()` and `plainText`; inline content as a typed tree
  (`inlines`, `titleInlines`: text and formatted text, links, images...,
  nested; ADR-0008); typed attributes; source-preserving edits of header
  attributes (`withAttribute`, `withoutAttribute`: only the entry's lines
  change); an EPUB 3 backend in the native executable (`-b epub3`), the
  same EPUB as the asciidoctor-epub3 2.3.0 gem file by file (ADR-0009);
  diagnostics
  collected per document; callback-based extensions (`InlineMacro`,
  `BlockMacro`, `CustomBlock`, `IncludeResolver` (may be asynchronous),
  `TreeProcessor`, `Preprocessor`, `Postprocessor`, `Docinfo`).
  `package:asciidart/asciidart.dart` has no file system access and runs on
  the web; `package:asciidart/io.dart` adds `parseFile`, `convertFile` and
  `convertTree`; `package:asciidart/cli.dart` runs the command line with a
  configuration compiled in. Everything else is private;
  `tool/api_surface.txt` records the public API and CI checks it.
- A PDF backend (`-b pdf`, native executable) that converts as the
  asciidoctor-pdf 2.3.27 gem does and reads its YAML themes unchanged, drawn
  with libpdf (asciidart's own pure-Dart PDF library; no Prawn code). It
  covers:
  - title pages, covers and backgrounds (PDF pages included);
  - running content;
  - tables, images (raster and SVG), icons and admonitions;
  - the table of contents, the index, footnotes and outlines;
  - `media=prepress` books (recto starts and inner and outer margins) and
    man pages.

  By default the layout is asciidart's own: justified paragraphs are
  broken where their spacing is most even (Knuth and Plass) and
  hyphenated in the document's language (hyph-utf8's patterns, 72
  languages; `:hyphens!:` turns it off; code spans stay whole), and a
  paragraph leaves at least two lines on either side of a page break
  (`prose_orphans`, `prose_widows`). Text is kerned by the font's GPOS
  pairs and set with its standard ligatures (`base_font_ligatures: none`
  turns them off), emphasis inside italic text is upright
  (`base_emphasis_inversion`), and paragraph indents may be given in
  `em` or `rem`. Listings split only between lines, leaving at least two
  on either side of a page break (`code_orphans`, `code_widows`); a line
  too long for the block wraps with a return arrow past its end and a
  hanging indent (`code_wrap_marker`, `code_wrap_indent`); a caption
  stays with its block; and text in a column too narrow for a single
  character is set anyway rather than dropped. With `-a pdf-compat` the layout is the gem's, and
  `hyphens` and `base_hyphens` hyphenate as the gem does with text-hyphen.
  In that mode, 763 of the 797 documents of the gem's spec suite convert the same (words,
  positions, outline, links, labels, pixels and colors; `benchmark/PARITY.md`),
  6 to 15 times faster than the gem (`benchmark/BASELINE.md`).
- Remote content (`allow-uri-read`): `parseAsync` and `convertAsync` fetch
  includes and data-URI images, honoring `cache-uri`.
- The `asciidart` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `asciidart:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names asciidart and the Asciidoctor
  release it is compatible with; `man/asciidart.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Syntax highlighting with highlight.js at conversion (hilite, a Dart port
  of highlight.js 11.12.0); `highlightjs-mode=client` gives Asciidoctor's
  browser-side markup. Rouge, Pygments and CodeRay behave as when their gems
  are missing.
- Custom converters: Mustache templates (`-T`, `templateDirs`) and HTML
  overrides in Dart, in place of Ruby's Tilt templates (ADR-0002).
- `{asciidoctor-version}` (and `asciidoctorVersion` in the API) report
  2.0.26, so documents written for Asciidoctor keep working;
  `{asciidart-version}` (`asciidartVersion`) reports asciidart's version,
  which also appears in the HTML generator meta tag and the man page
  header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- The same core builds as the npm package `asciidart` for Node.js and
  browsers (ADR-0005). Its API is generated from the Dart API, with the
  same names and shapes, plus TypeScript declarations
  (`tool/generate_js.dart`, ADR-0007).
