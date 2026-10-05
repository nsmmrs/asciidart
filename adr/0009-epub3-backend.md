# ADR-0009: The EPUB3 Backend Lives in the Native Executable

**Status:** Final. Decided on 2026-10-05 while implementing EPIC-dp24q5
(step 11 of the roadmap).

## Context

The asciidoctor-epub3 gem (2.3.0) converts a document to an EPUB 3: one
XHTML file per chapter, navigation documents, a package document, its
stylesheets and the fonts they use, zipped by the gepub gem. EPIC-dp24q5
asked for the same EPUB from `asciidart -b epub3`, byte for byte, without
Ruby. Three things set this backend apart from the others:

- its output is a ZIP file, not text;
- every EPUB carries about 1.4 MB of fonts (4.1 MB with every script), and
  the gem compiles SCSS stylesheets each time it converts;
- the package document and the ZIP come from gepub, whose output (element
  order, generated ids, manifest properties guessed from each XHTML file)
  is part of what makes two EPUBs the same.

## Decision

1. **A port of the converter and of the gepub output it relies on.** The
   converter (`lib/src/epub3/converter.dart`) is a port of the gem's; the
   package (`book.dart`) writes the OPF as gepub 1.0.17 does (metadata in
   the order each kind is first added, `item_<name>` ids from gepub's id
   pool, `scripted`/`svg`/`mathml`/`remote-resources` guessed from the
   content, the EPUB 2 cover meta); a small ZIP writer (`zip.dart`)
   stores `mimetype` first and compresses the rest with zlib.
2. **Vendored, compiled data.** `tool/vendor_epub3.sh` takes the fonts and
   images from the gem, compiles its SCSS once with the gem's own Sass
   engine and options (the CSS is byte for byte what the gem writes),
   reduces the Font Awesome metadata to names and code points, and copies
   the release's spec fixtures. `tool/embed_epub3.dart` embeds the assets
   (`assets.g.dart`), so the backend reads no files of its own.
3. **Registered by the native executable only.** `bin/asciidart.dart`
   registers the backend (`registerEpub3`) before running the CLI. The
   library, `package:asciidart/io.dart` and the npm package (whose CLI and
   API are compiled from the same sources) never import it, so their
   bundles don't grow by the fonts. A converter that writes a file of its
   own implements `PackagingConverter`; such a backend can't write to
   standard output, and says so.
4. **Parity is checked file by file.** `tool/epub_parity.dart` converts
   documents with the gem and with asciidart (`-a reproducible`,
   `TZ=UTC`) and compares the entries, their order, `mimetype` stored first,
   every file's bytes (the dates aside) and the messages; with
   `--epubcheck`, both EPUBs are validated and must get the same report.
   The ZIP bytes are not compared: zlib versions compress differently.

## Consequences

- The 72 spec fixtures of asciidoctor-epub3 2.3.0 and a 500-document
  sample of the corpus convert to the same files as the gem, apart from the
  differences in `benchmark/PARITY.md`. CI runs the harness on the
  fixtures.
- A custom theme (`epub3-stylesdir`) must provide compiled CSS:
  asciidart has no Sass compiler.
- The EPUB3 backend is not in the library API or the npm package. Making it
  available there means a separate entry point (or deferred loading of the
  assets), so the web bundle stays small.
