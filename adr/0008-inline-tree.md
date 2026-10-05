# ADR-0008: The Inline Tree Is Recorded, Not Rendered From

**Status:** Final. Decided on 2026-10-05 while implementing FEAT-q86s3x
(step 7 of the roadmap).

## Context

Asciidoctor has no inline tree. Its substitutions are regular-expression
passes over a string: when a pass finds an inline element it converts it
on the spot and splices the output into the string. Later passes then work
on that output:

- they rewrite the element's text inside its markup (replacements inside
  `<strong>...</strong>`, links inside formatted text);
- the characters of the markup decide whether a later pattern matches next
  to it;
- line-based passes see the lines of multi-line output.

FEAT-q86s3x asked for a typed inline tree that the HTML, DocBook and man
page converters render from, with the output byte-identical except for
documented fixes. Three designs were measured against the corpus (17,900
conversions against the gem):

1. **Stand-in tags.** Elements leave placeholder tags in the text and are
   converted from the tree at the end: 443 differences. A placeholder's
   characters are not the markup's. For example, `*a*-- b` keeps its `--`
   in Asciidoctor because the `>` of `</strong>` stops the em-dash rule.
   And the man page link converter compares an element's text with its
   target.
2. **The real output plus invisible markers** at the edges of each
   element's markup: 13 differences. Any character inserted into the
   stream changes some match. The marker inside `&#8220;` defeats the
   constrained-mark rule, which excludes `&#` on purpose. With
   `hardbreaks`, a multi-line image hides its lines from the line-break
   pass.
3. **Tracking:** 0 differences.

## Decision

1. **The output is the substitutions' text.** The converters convert each
   element when a substitution finds it, as before. Nothing is added to the
   text, so the output is identical by construction.
2. **The tree is recorded.** In a tracking run
   (`InlineRun.track`, `applySubsTree`):
   - every replacement the substitutions make records where the output of
     each element it found lands;
   - it also moves the positions of the elements found earlier (a position
     inside a replaced match survives when the match was an element's text,
     which the element's output keeps).
   At the end each element is a range of the text, and the ranges nest into
   the tree. Where an element's text sits in its output is found by
   converting it again with a marker as its text. This is done only for
   elements whose markup wraps their text (formatted text, links, line
   breaks, buttons, visible index terms), and only with the built-in
   converters, which convert them without side effects.
3. **The API gets the tree.** It is available as:
   - `inlines` on paragraphs, other text blocks, admonitions and list items;
   - `titleInlines` on any block;
   - `InlineContent`, a sealed union of `InlineText` and the typed `Inline`
     elements, with `children` for elements that hold text.
   Like `content`, computing it applies the substitutions. Normal
   conversion does not track and costs nothing extra.

## Consequences

- The tree is exact wherever the substitutions nest elements properly.
  Where Asciidoctor itself produces overlapping markup (a pattern matching
  across the edge of an earlier element), the elements involved are left
  out of the tree and their output stays as text. The output is unaffected
  either way.
- Converters still receive each element's converted text, not its
  children: rendering from the tree would need the substitutions to stop
  working on converted output, which is a change of behavior. That belongs
  on the `bugfix` branch, if anywhere, where differences from Asciidoctor
  are allowed.
- Renderers for Flutter, terminals, PDF or EPUB walk `inlines` instead of
  parsing HTML.
