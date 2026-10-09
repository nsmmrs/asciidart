# ADR-0019: The ptome Language, and Texts Cited by Numbered Units

**Status:** Accepted. Direction decided by the user on 2026-10-08 (lane
EPIC-83z42j). The milestone-1 architecture (decision 5) is the
implementer's and can be revisited.

## Context

Scripture, law, classics, drama, liturgy and specifications are cited by
numbered units: verses, sections, segments, lines, paragraphs. In plain
AsciiDoc every one of those addresses has to be written out as an anchor,
a printed label and a reftext. That means 31,102 verse anchors in the KJV
alone, each restating what its position already says. The loci experiment
(`~/Work/ports/loci`, `SYNTAX.md` and `DESIGN.md`) worked out the smallest
syntax that removes this repetition. It did so against 19 real documents,
each imported from a pinned source and checked against that source's
numbering. Features no text needed were removed.

The user decided that this syntax becomes native to ptome. It is the first
large addition to the *ptome language*, ptome's deliberate superset of
AsciiDoc ("AsciiDoc++"), and it is not a preprocessing tool run before
ptome. loci stays an experiment and a data source; it is not maintained as
a tool.

## Decisions

1. **The ptome language is a superset, opted into per document.** Nothing
   in this ADR is active unless a document names its schemes in its header
   (`:units: bible, kjv`). A document without `:units:` parses exactly as
   before, in every backend and in asciidoctor-compat mode, so Asciidoctor
   parity, the compat corpus and the goldens are untouched. In a units
   document, `\@` is a literal `@`.
2. **The syntax is loci's `SYNTAX.md`.** It adds two constructs:
   - the unit marker: `@`, `@@`, `@label`, bridges such as `@4-5`, `@^`,
     and `@…[attrs]`;
   - ranges: `[name}` … `{name]`.

   It gives new meanings to six existing ones: references (`<<address>>`),
   note streams (`note:STREAM[…]`), includes by ID and by address,
   description-list styles (`[annotations]`, `[overlays]` and speeches),
   and roles (`[.dfn]` and apparatus roles). Everything else is data the
   schemes declare.
3. **Schemes are YAML**, like ptome's themes, with no new dependency. They
   are found in the `schemes/` directory nearest above the document, and a
   later file can override one level setting or add templates, as in loci.
   loci's 24 TOML schemes were converted once, mechanically; each converted
   file reads back equal to its TOML (`tool/` in the units corpus notes).
4. **The engine lives in ptome**, in `packages/ptome/lib/src/units/`, ported
   from loci's `lib/src/dialect/`: the scheme model and label types,
   templates, the reader of units tokens, the engine that computes units,
   addresses, IDs and reftexts and checks labels, citations and the
   renderer. It reaches files only through ptome's platform I/O, so it
   compiles to JavaScript like the rest of the library. The port is
   checked against loci: for all 26 dialect documents it renders every
   source file exactly as loci does (`tool/units_port_check.dart`).
5. **Milestone 1: units render as ptome reads them.**
   - When a document names schemes, ptome's engine analyzes the document
     and its includes.
   - ptome's reader takes each source file's rendered lines in place of
     the file's own: the root document and every file it includes.
   - Rendered means markers become anchors and printed labels, ranges role
     spans, notes footnotes or entries, and references links, all through
     the scheme templates.
   - The reader already processes include and conditional directives as it
     reads, and units are processed the same way: inside ptome, with no
     step before it and no rewritten file on disk.

   The consequence is the contract the user chose for milestone 1: for
   every loci document, ptome's output (HTML5, DocBook 5, PDF) is
   byte-identical to ptome rendering loci's own rendering of it. It holds
   by construction, because the parser sees the same lines. The acceptance
   gate checks it (`tool/units_acceptance.dart`).
6. **Milestone 2 moves units into the document model.**
   - Units, ranges, notes and references become typed nodes with an
     address API in the Dart and JS APIs, and a check command.
   - The PDF engine gets apparatus straight from note streams (entries in
     the side column) and running heads straight from addresses.
   - Parallel texts.

   Each milestone-2 change that alters output is reviewed against the
   milestone-1 output and documented.
7. **Safety.** A units document reads its scheme files, `:works:`,
   overlays and annotation layers from disk, so units are active only when
   the safe mode allows reading files (below `secure`). Under `secure`, a
   units document is read as plain AsciiDoc.
8. **Fixtures and licenses.** The full corpus stays outside the repository
   (Folger's Hamlet is CC BY-NC); the acceptance gate reads it from a local
   path. Committed fixtures are small public-domain excerpts with their
   expected renderings.

## Consequences

- ptome reads loci's documents directly:
  `ptome -b pdf -d article -a pdf-theme=kjv-theme.yml bible/kjv/kjv.adoc`
  gives the reference Bible.
- The scheme templates write AsciiDoc fragments, which is what milestone 1
  needs. Milestone 2 turns them into node constructors or theme keys where
  that is clearer, and keeps the fragments where they serve.
- Diagnostics (gaps, repeats, labels going backwards, references not
  found) go through ptome's logger, so `--failure-level` applies.
