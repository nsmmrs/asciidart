# Texts cited by numbered units

Scripture, law, classics, drama, liturgy and specifications are cited by
numbered units: verses, sections, segments, lines, paragraphs. The ptome
language adds a small syntax to AsciiDoc so that such texts are written
with nothing their position already gives. You never write an address, an
ID or a number that just steps; ptome works them out and renders the
anchors, labels, reftexts, notes and links.

```asciidoc
= Exodus
:units: bible, kjv

== @EXO

=== @34

@ And the LORD said unto Moses, Hew thee two tables of stone like unto the first …
@ And be ready in the morning, and come up in the morning unto mount Sinai …

@6 And the LORD passed by before him, and proclaimed, The LORD, The LORD God,
##merciful##note:x[<<Ps 86:15; 103:8–13>>; <<Joel 2:13>>] and gracious …
```

Every verse gets an anchor (`v-exo-34-6`), a reftext (`Exodus 34:6`) and
its printed number. `LORD` is set in small capitals, the cross-references
go into an entry after the verse number, and `<<Ps 86:15>>` links to the
verse. The design is in ADR-0020 (ADR-0019 has the syntax and the
documents it was tested on).

Nothing on this page is active unless a document names its schemes in its
header (`:units:`), or names other works it quotes by address (`:works:`).
Every other document is AsciiDoc and parses exactly as before. To read a
units document as plain AsciiDoc, set `-a units!`. Units read their scheme
files from disk, so they are off under the `secure` safe mode.

## The unit marker

A marker starts a unit where it stands. The unit runs until the next
marker of its level or a higher one, across lines, paragraphs and
headings.

| Form | Means |
| --- | --- |
| `@` | The next unit of the default level (a verse, a line, a stanza). |
| `@@`, `@@@` | The next unit one (two) levels up; the default level starts again at its first (at 0 in a heading). |
| `@label` | The unit with that label. A label may name several levels: `@53:1`, `@(4)(A)(i)`, `@1.30.0`. |
| `@4-5`, `@18-23.1` | A bridge: one unit for several labels. |
| `@^` | Close the innermost unit; the text after it belongs to its parent (law's text after a provision's subdivisions). |
| `@…[name]`, `@…[key=value]` | A marker of a secondary scheme (`@[recital]`), or attributes a template reads (`@[part=F]`). |

The rules:

1. **Where a marker is recognized.** At the start of a line, after
   whitespace or punctuation, or right after a heading's `=` signs. It is
   followed by whitespace or the end of the line. `\@` is a literal `@`.
2. **Layout comes from the level's `break`.**
   - `none`: a marker inside a line is a milestone.
   - `line`: at the start of a line, it also breaks the line (verse drama,
     the Psalter).
   - `block`: at the start of a line, it starts a block (law, stanzas,
     catechism questions, spec paragraphs).
   - `heading`: the level is bound to headings.
3. **A heading is a unit only with a marker.** `== @EXO` sets the book and
   `=== @34` the chapter.
4. **Text before a level's first marker** is unit 0 (a Psalm's title,
   `zero: true`) or belongs to no unit.
5. **Labels are checked** against what their type says comes next. Gaps,
   repeats and numbers going backwards are warnings
   (`ptome: WARNING: exodus.adoc:12:1: verse 6 after 2 (expected 3)`),
   so `--failure-level` applies. An edition declares what it skips on
   purpose (`gaps`, a versification's excluded verses).

## Ranges

`[name}` … `{name]`, with an optional ID and attributes:
`[ins#F1 from=2023-06-01}`. A range spans any stretch, across markers,
paragraphs and headings, and may overlap other ranges. Only names the
schemes declare are recognized. A range renders as role spans, split at
blocks and markers: the words of Jesus, a statute's insertions.

`-a units-as-of=2000-01-01` keeps the text in force on that date:
insertions (`ins`, `sub`) made later are left out, deletions (`del`) made
later are kept.

## Existing syntax with a new meaning

- **References.** A `<<…>>` whose target is not an ID is read as
  citations, in the forms the schemes declare. For example:
  - lists: `<<Ps 86:15; 103:8–13; Joel 2:13>>`;
  - relative addresses: `<<5:3>>`, `<<(b)>>`;
  - ranges;
  - other works (`:works: kjv=../bible/kjv/kjv.adoc`).

  `<<address,text>>` shows other text. `<<"term">>` cites a defined term.
- **Note streams.** `note:STREAM[…]` uses a stream the schemes declare,
  with its callers, when they restart, and where its notes go:
  - `footnote`;
  - `entry`, after the unit's marker (a reference Bible's center column);
  - `end`, after the unit (a catechism's proof texts).

  A note right after `##span##` or a range's close takes it as its lemma.
  `note:F#id[…]` is written once and called again by `note:F#id[]`.
- **Includes.**
  - `include::#id[]` repeats a block of this document, without its ID
    or anchors.
  - `include::kjv[unit="Ps 23:1-3"]` quotes a passage of another work. The
    work is parsed and its units rendered as its own; the quotation is cut
    from that at its units, even mid-line, and leaves out the work's
    anchors, headings and notes. Lists stay lists, so a dialogue keeps its
    speakers.
  - The citation under the quotation is made from the work, not from the
    address as typed. A style the work's schemes declare (`cite=bcp`)
    shapes it. `cite=none` splices the passage in uncited, as the work
    prints it; its headings become discrete headings, so a psalm spliced
    into a section stays in that section.
- **Description lists with a style.**
  - `[annotations]`: a layer of notes kept in another file, each on an
    address and the words it quotes.
  - `[overlays]`: named ranges over the address tree (a juz, a day's
    psalms).
  - Speeches: `HAMLET:: …`.
- **Roles.** `[.dfn]#term#` defines a term. The roles a scheme names as
  apparatus put their blocks in no unit.

## Parallel texts

`include::mn1-pli.adoc[parallel=mn1-en.adoc]` sets two documents in the
same scheme side by side, unit by unit: a text and its translation, the
Arabic and Pickthall.
- Units are matched by address alone; nothing in either document points
  at the other.
- Each heading of the first document comes through as a discrete
  heading. A heading that is only a marker shows its unit's name
  (`Psalms 23`).
- Under each heading, a table (role `parallel-text`) has a row per unit
  of the default level, with the unit's number on both sides.
- `leveloffset` moves the headings down as it does for any include.

## In the output

Units are nodes of their own in the document tree, and each backend
renders them in its own way:

- **A unit's mark** (inline `unit`): where a unit starts, with its ID and
  label, or what it prints at its end. In HTML and EPUB:

  ```html
  <span id="v-exo-34-6" class="unit" data-scheme="bible" data-level="verse"
    data-unit="Exod 34:6"><sup>6</sup></span>
  ```

  In DocBook, an `<anchor>` before the label; in PDF, a destination.
- **Notes** (inline `note`): a caller in the text
  (`<span class="note-call" data-stream="x">…</span>`) and the entry its
  unit's notes are gathered in (`<span class="note-entry xref"
  data-stream="x">…</span>`). Footnotes of a stream say which
  (`stream`, `caller`).
- **Units of blocks** (block `unit`): a provision, a question or a stanza
  holds its blocks, nested as the units are; text after `@^` goes back to
  the unit around the ones it closes.

  ```html
  <div id="art-6-1-a" class="unit point" data-scheme="eu" data-level="point"
    data-unit="Article 6(1)(a)">
  <div class="paragraph">…</div>
  </div>
  ```

  DocBook has no element for one; its first block takes the unit's ID and
  role.

The API has them as `UnitMark`, `NoteCall`, `NoteEntry` and `UnitBlock`
(with their scheme, level, citation and stream), in a paragraph's
`inlines` and among a block's `blocks`.

## A reference Bible in PDF

The PDF engine sets a unit's apparatus where a print edition does, with
theme keys alone (see `doc/pdf.md`):
- The entries of a note stream (the cross-references, spans with the
  stream's `entry-role`, `xref`) go in the center column beside their
  verse (`role_xref_display: side`).
- The running head gives the page's first and last verse, from the verses'
  anchors (`running_content_marks: v-`).

```yaml
# kjv-reference-theme.yml
extends: ./kjv-theme.yml
page:
  columns: 2
  column-gap: 72
role:
  xref:
    display: side
    font-size: 6
side-notes:
  column: center
running-content:
  marks: v-
header:
  recto:
    center:
      content: '{page-first-mark}–{page-last-mark}'
  verso:
    center:
      content: '{page-first-mark}–{page-last-mark}'
```

`ptome -b pdf -d article -a pdf-theme=kjv-reference-theme.yml kjv.adoc`
then gives two columns of verses with their cross-references between
them, the 1611 notes at the foot of the page, the divine name in small
capitals, and `Genesis 2:20–Genesis 3:7` at the head of the page.

## Schemes

`:units: bible, kjv` names YAML files in the `schemes/` directory nearest
above the document (`bible.yml`, `kjv.yml`). Later files add to earlier
ones and may override one setting of a level.

```yaml
canon: "canon-protestant"
scheme:
  bible:
    cite: "{{book.abbr}} {{chapter}}:{{verse}}"
    level:
      - name: "book"
        type: "code"
        break: "heading"
        depth: 1
        id: "b-{{book|lower}}"
        reftext: "{{book.name}}"
      - name: "chapter"
        type: "int"
        break: "heading"
        depth: 2
        sep: " "
        id: "c-{{book|lower}}-{{chapter}}"
        reftext: "{{book.name}} {{chapter}}"
      - name: "verse"
        sep: ":"
        default: true
        zero: true
        bridges: true
        id: "v-{{book|lower}}-{{chapter}}-{{verse}}"
        reftext: "{{book.name}} {{chapter}}:{{verse}}"
```

A second file (`kjv.yml`) adds the edition's note streams, ranges and
terms, and how its units look:

```yaml
stream:
  # Cross-references: lettered in the verse before the phrase they belong
  # to, gathered into the verse's entry for the center column.
  x:
    placement: "entry"
    caller: "a"
    reset: "verse"
    origin: "{{chapter}}:{{verse}}"
    caller-style: "superscript"
    caller-role: "xref-mark"
    caller-after: "\u00a0"
    origin-style: "strong"
    entry-role: "xref"
    entry-after: " "
range:
  wj:
    role: "wj"
term:
  divine-name:
    pattern: "(?<![A-Za-z])(?:LORD|GOD|JEHOVAH|JAH)(?![A-Za-z])"
    role: "nd"
    transform: "titlecase"
level-presentation:
  bible:
    chapter:
      title: "{{book.chapter-label}} {{chapter}}"
      role: "chapter"
      attributes:
        number: "{{chapter}}"
    verse:
      # No number on a chapter's first verse.
      label: "{{^first}}{{^zero}}{{label}}{{/zero}}{{/first}}"
      label-style: "superscript"
      label-after: "\u00a0"
```

A scheme file declares the following.

**Schemes and their levels.**
- *Label types:*
  - `int`, with `insert` letters (`a`, `A`, `uk`, `decimal`) and `every`
    *n*;
  - `alpha`, `alpha2`, `alpha-uk`, `ALPHA`;
  - `roman`, `ROMAN`;
  - `talmud`, `folio`, `stephanus`, `bekker`;
  - `enum`, `code` (a canon's books), `name`;
  - unions such as `alpha|int`.
- *Layout:* `break` and `depth`.
- *Citation forms:* `sep`, `wrap`, `cite-wrap`, `cite-range-wrap`.
- *Stepping:* `auto` (`block`, `paragraph`, `item`), `stepping`, `gaps`,
  `zero`, `hidden`, `bridges`, `absolute`.
- *Templates:* `id`, `reftext`.
- *How its units look* (on the level, or in `level-presentation`):
  - `label` (a template), `label-style` (`plain`, `superscript`,
    `strong`, `emphasis`), `label-role`, `label-before`, `label-after`;
  - `anchor` (`false` for a unit only its label marks), `anchors` (more
    IDs, as templates: a through-line number), `indent`;
  - for a heading that is a unit: `title`, `role`, `attributes`;
  - for a block that is a unit: `block-role` (the level's name without
    one), `block-options` (`hardbreaks`);
  - at a unit's end: `end`, `end-role`, `end-before`, `end-break: line`.

**Everything else.**
- *Canons* (book codes and every name a citation may use) and
  *versifications*.
- *Note streams*, and how their notes look: `caller-style`,
  `caller-role`, `caller-after`; `origin-style`, `lemma-style`,
  `lemma-after`, `prefix` (in a footnote); `entry-role`, `entry-after`,
  `note-separator`, `entry-break: block` (an entry that is a block of its
  own).
- *Ranges* and *term rules*.
- *Settings*: `apparatus` roles, `overlay-role` and `overlay-after`.
- *Citation styles* (`citation:`): how another document cites a passage of
  this one. Each style gives `attribution` and `title` templates, a `block`
  and the `labels` a quotation keeps.

Templates are Mustache and print text, never markup: what a unit prints
is set in the styles and roles above, and every backend renders it its
own way. Text a template prints may refer to document attributes
(`{response}`), with their values where the unit is. Scheme format 1,
whose templates printed AsciiDoc (`lower`, `heading`, `mark`, `entry`,
`templates:`), is no longer read: ptome says which keys replace each.

**What a template can use.**
- the unit's levels by name;
- `label`, `ordinal` (a through-line number), `first`, `zero`;
- marker attributes (`attr.part`) and document attributes (`doc.version`).

**Filters:** `lower`, `titlecase`, `roman`, `hebrew`, `arabic-indic`,
`pad:4`, `every:5`.

## Checking a document

`ptome check FILE...` reads documents as conversion does, without
converting them. It prints each document's problems, then a summary line, and exits with
status 1 when any document has a problem. `-q` prints only the summaries.

```console
$ ptome check exodus.adoc
ptome: WARNING: exodus.adoc:15:1: verse 6 after 2 (expected 3)
exodus.adoc: 1 bible.book, 1 bible.chapter, 4 bible.verse; 2 notes, 2 references; 0 errors, 1 warnings (12 ms)
```

## The API

A parsed document lists its units, in document order (`Document.units`).
Each `Unit` has:
- its scheme and level, and the level's depth;
- its labels by level name (`{book: EXO, chapter: 34, verse: 6}`);
- its ID, reftext and citation (`Exod 34:6`);
- the file and line it starts on.

`Document.unit` finds a unit by ID, or by an address its schemes cite
(`Exodus 34:6`, `Ps 3`). The npm package has the same members.

```dart
final doc = await const Ptome(safe: SafeMode.unsafe).parseFile('exodus.adoc');
for (final verse in doc.units.where((u) => u.level == 'verse')) {
  print('${verse.citation} -> #${verse.id}');
}
print(doc.unit('Exod 34:6')?.reftext); // Exodus 34:6
```

## How it works

ptome's parser reads a document in units as it reads any other, and
records where each line of text came from. Once the document is parsed,
the units session walks it in document order: it finds the units syntax
in the text the parser read (section titles, paragraphs, list items,
description-list entries, verse blocks, table cells) and runs the engine.
The engine finds every unit, its address, ID and reftext, and resolves
notes and references. Because the parser read the text, conditionals,
`leveloffset`, tables and includes all apply as they do anywhere else.

Then the session renders what units print. Headings that are units get
their IDs, titles and roles, and the blocks of each unit of blocks go in a
unit node; markers, notes, references and defined terms become
placeholders in the text the inline substitutions start from, converted
afterwards as unit marks, notes, footnotes and links; ranges and term
rules become role spans around the markup inside them. The source is never rewritten: a block's source still holds what
was written. HTML, DocBook, EPUB and PDF all render units, and so does
the npm package. The units engine lives in `lib/src/units/` (ADR-0020).
