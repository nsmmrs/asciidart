# ADR-0020: Units in the Document Model

**Status:** Accepted on 2026-10-09 (all decisions implemented; see Implementation). Decided by the user on 2026-10-08: units are to be a native feature of the ptome language, "not an awkward preprocessing step", in the ideal implementation. Byte identity with milestone 1 is not a goal. It supersedes [ADR-0019](0019-units.md) decision 5, decision 4's port contract and decision 3's scheme format. It keeps ADR-0019's syntax (decision 2), opt-in (decision 1), safety (decision 7) and fixtures policy (decision 8).

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
   - Milestone 1's units model, dumped as canonical JSON (`tool/units_dump.dart`), is the oracle for the native model; the dumps were taken before milestone 1 was removed and are kept outside the repo with the corpus (`tool/units_model_check.dart`). Differences are allowed only with a recorded reason.
   - Milestone 1's outputs are the reference for review, not a byte-for-byte contract.
   - Plain AsciiDoc output and parity stay exactly as they are.

## Consequences

- One parse instead of two, and units work everywhere AsciiDoc does.
- Positions, diagnostics and the API refer to the source as written.
- Scheme files lose their AsciiDoc-emitting templates, and the 24 corpus schemes migrate.
- Milestone 1's reader hooks, renderer and loci's block reader are removed at the end (phase 8 of the plan).

## Implementation

As of 2026-10-09:

- **Recognition (1) and the session (2).** The parser records line origins, keeps a units marker that starts a block out of the paragraph before it, and creates the session after the header. The session walks the finished tree in document order and sends the engine the events decision 2 lists; the engine is loci's, unchanged in its cursor logic. The walk happens once the parse is done rather than as it goes, which gives the same events with the tree complete (forward references to IDs work).
- **The model (3)** is the engine's `Analysis` beside the tree, with each unit's start node and position (`Rendering.starts`).
- **Rendering (4).** Units are node kinds of their own: `InlineContext.unit` (a unit's start, with its ID and label, or its end text), `InlineContext.note` (a caller, an entry; footnotes carry their stream and caller) and `BlockContext.unit` (a unit of blocks holding them, nested; `@^` goes back up). HTML and EPUB render `class="unit"` with `data-scheme`, `data-level` and `data-unit`; DocBook an anchor (a unit of blocks gives its first block its ID and role); PDF a destination, and entries through their role. The API has `UnitMark`, `NoteCall`, `NoteEntry` and `UnitBlock`. They come from typed atoms (placeholders in the text the inline substitutions start from, converted after them); range and term text is wrapped in marks that become role spans around balanced markup and split at markup a range crosses.
- **Scheme format 2 (5)** is the only format read: text templates and presentation keys (`label`, `label-style`, `block-role`, `entry-role` …, `level-presentation`). Format-1 keys are rejected with the keys that replace them. The 24 corpus schemes were migrated with a script outside the repo (loci is a data source, not maintained).
- **Other works (6).** Cited works are parsed natively and cached. `include::X[unit=…]` and `include::#id[]` leave placeholders the session replaces with blocks cut from the cited work's own tree and rendering (quoted, or spliced with headings as discrete headings); `parallel=` builds a table; layers are AsciiDoc documents whose description lists the session weaves in as notes at the words they quote.
- **PDF (7).** Note entries go beside their verse through their role (`role_xref_display: side`); running content cites a level's units from the model (`running_content_units: verse`, `{page-first-unit}`, `{page-last-unit}`, `{page-units}` and `{page-units-long}`, the range said once: `Genesis 2:20–3:7`). The anchor-prefix `running_content_marks` stays for documents not in units.
- **Verification (8).** The model gate agrees on all 28 corpus documents, four with recorded reasons (`tool/units_model_allow.txt`). Reviewed against milestone 1's frozen HTML, 14 documents are identical and the rest differ where milestone 1 was wrong (footnotes cut at `]`, italics broken by lemmas, `(C)` turned into ©, a spliced psalm breaking its section, anchors that overwrote each other) or by reviewed structure.
- **API.** Units have their parents, children and notes; documents their passages, references by address and defined terms; units problems are diagnostics with codes of their own and exact columns; `ptome check --format=json --list` gives the same to tools.
- **Removal.** Milestone 1's reading and lowering, loci's block reader, its parallel-text and include code, and the `units-engine` switch are gone.
