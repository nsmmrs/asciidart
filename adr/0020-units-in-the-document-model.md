# ADR-0020: Units in the Document Model

**Status:** Proposed. Decided by the user on 2026-10-08: units are to be a native feature of the ptome language, "not an awkward preprocessing step", in the ideal implementation. Byte identity with milestone 1 is not a goal. When accepted, this supersedes [ADR-0019](0019-units.md) decision 5, decision 4's port contract and decision 3's scheme format. It keeps ADR-0019's syntax (decision 2), opt-in (decision 1), safety (decision 7) and fixtures policy (decision 8).

## Context

Milestone 1 (ADR-0019) reads a units document with loci's engine:
- It has its own block reader, which approximates ptome's parser: it ignores conditionals, table cells and leveloffset, and treats delimited blocks as paragraphs.
- It rewrites every source line into AsciiDoc through templates that emit AsciiDoc markup.
- ptome then parses the rewritten lines.

The output is right, but units are not part of the language. They exist only as the markup they were rewritten into. Positions are columns in the rewritten text, ranges are split into spans line by line, and a cited work is quoted by searching another rewritten text for its anchors.

## Decisions

1. **The parser recognizes units.** Markers, ranges, notes, references by address and defined terms are found in the text ptome's parser actually reads. Conditionals, include tags and leveloffset, tables, lists, verse and literal content, and passthroughs therefore all apply as they do for any other syntax.
2. **The engine runs during the parse.**
   - A `UnitsSession` exists only for a document that names schemes or works.
   - The parser sends it typed events: headings, block beginnings, tokens and line breaks inside verse blocks. Each event carries the AST node and an exact source position (line origins, with columns).
   - Unit IDs, reftexts and section titles are fixed as the parse goes.
   - A finalize pass at the end of the parse works out unit ends, note callers, references, overlays and layers, as-of visibility, and unclosed ranges.
3. **A units model sits beside the AST.**
   - It holds units with their text positions and extents, an address index, notes, ranges as intervals, references resolved to units (here or in other works), terms and overlays.
   - Converters walk the AST, and the model answers what the AST doesn't hold.
4. **Units render as nodes.**
   - New inline kinds: unit marks (start, end, overlay) and notes (call, entry). Footnotes gain streams and callers.
   - A new block kind: unit containers, for provisions and stanzas.
   - Every backend renders them natively, for example semantic HTML with `class="unit verse"` and `data-unit="Exod 34:6"`.
   - Ranges are wrapped by an algorithm that understands tags, so overlaps are well formed.
   - Term rules apply to text only.
5. **Schemes write text, not markup (scheme format v2).**
   - Templates make IDs, reftexts, labels, titles, end texts and note entries. A template's named values become parts with roles.
   - Presentation comes from theme keys, the stylesheet and output templates.
   - `lower`, `lower-block`, `lower-end`, `lower-resume`, `heading` and the stream keys `mark` and `lower` are removed. A tool migrates v1 files.
6. **Other works are parsed natively.**
   - A works registry parses the cited documents (cached).
   - A quotation is a view of the other work's tree, cut at unit positions and cited by that work's citation styles.
   - A parallel text is a real table.
   - Annotation layers are placed on the parsed text.
7. **The PDF apparatus comes from the model.** Note entries go to the side column through their stream, and running heads come from the units of a level (`running_content_units`, `{page-units}`), not from ID-prefix conventions.
8. **Verification.**
   - Milestone 1's units model, dumped as canonical JSON (`tool/units_oracle.dart`), is the oracle for the native model. Differences are allowed only with a recorded reason.
   - Milestone 1's outputs are the reference for review, not a byte-for-byte contract.
   - Plain AsciiDoc output and parity stay exactly as they are.

## Consequences

- One parse instead of two, and units work everywhere AsciiDoc does.
- Positions, diagnostics and the API refer to the source as written.
- Scheme files lose their AsciiDoc-emitting templates, and the 24 corpus schemes migrate.
- Milestone 1's reader hooks, renderer and loci's block reader are removed at the end (phase 8 of the plan).
