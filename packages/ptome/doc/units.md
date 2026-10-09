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
verse. The design and the documents it was tested on are in ADR-0019.

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
  - `include::#id[]` repeats a block of this document.
  - `include::kjv[unit="Ps 23:1-3"]` quotes a passage of another work. The
    quotation is cut at its units, even mid-line, and leaves out the work's
    anchors, headings and notes.
  - The citation under the quotation is made from the work, not from the
    address as typed. A style the work's schemes declare (`cite=bcp`)
    shapes it; `cite=none` splices the passage in uncited.
- **Description lists with a style.**
  - `[annotations]`: a layer of notes kept in another file, each on an
    address and the words it quotes.
  - `[overlays]`: named ranges over the address tree (a juz, a day's
    psalms).
  - Speeches: `HAMLET:: …`.
- **Roles.** `[.dfn]#term#` defines a term. The roles a scheme names as
  apparatus put their blocks in no unit.

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

A second file (`kjv.yml`) adds the edition's note streams, ranges, terms
and templates:

```yaml
stream:
  # Cross-references: lettered in the verse before the phrase they belong
  # to, gathered into the verse's entry for the center column.
  x:
    placement: "entry"
    caller: "a"
    reset: "verse"
    origin: "{{chapter}}:{{verse}}"
    mark: "[.xref-mark]^{{caller}}^"
    entry: "[.xref]##*{{origin}}* {{#notes}}{{^first}} {{/first}}^{{caller}}^{nbsp}{{body}}{{/notes}}## "
range:
  wj:
    role: "wj"
term:
  divine-name:
    pattern: "(?<![A-Za-z])(?:LORD|GOD|JEHOVAH|JAH)(?![A-Za-z])"
    role: "nd"
    transform: "titlecase"
templates:
  bible:
    verse:
      lower: "[[{{id}},{{reftext}}]]{{^first}}{{^zero}}^{{label}}^{nbsp}{{/zero}}{{/first}}"
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
- *Templates:* `id`, `reftext`, `heading`, `lower`, `lower-block`,
  `lower-end`.

**Everything else.**
- *Canons* (book codes and every name a citation may use) and
  *versifications*.
- *Note streams*, *ranges* and *term rules*.
- *Settings*: `apparatus` roles, the overlay template.
- *Citation styles* (`citation:`): how another document cites a passage of
  this one. Each style gives `attribution` and `title` templates, a `block`
  and the `labels` a quotation keeps.

Templates are Mustache, and they write ptome markup.

**What a template can use.**
- the unit's levels by name;
- `label`, `ordinal` (a through-line number), `first`, `zero`;
- marker attributes (`attr.part`) and document attributes (`doc.version`).

**Filters:** `lower`, `titlecase`, `roman`, `hebrew`, `arabic-indic`,
`pad:4`, `every:5`.

## How it works

When a document names schemes, ptome's units engine analyzes the document
and its includes. The engine finds every unit, its address, ID and
reftext, and resolves notes and references. ptome's reader then reads
each source file as the engine renders it, through the scheme templates.
The parser and every backend see units as the markup they render to, so
HTML, DocBook, EPUB and PDF all support them, and so does the npm package.
The units engine lives in `lib/src/units/` (ADR-0019).
