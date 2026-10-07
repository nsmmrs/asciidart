# The house style

asciidart's PDF, HTML page, website and EPUB share one look by default
(ADR-0011). It starts from Asciidoctor's and asciidoctor-pdf's and
changes what the rules of typesetting ask for: Matthew Butterick's
*Practical Typography* (and *Typography for Lawyers*), Robert
Bringhurst's *The Elements of Typographic Style*, and, for code, notes and
figures, the conventions of technical publishers' books. The markup is
Asciidoctor's; only the PDF theme and the stylesheets change.

The classic looks are a setting away: `-a stylesheet=asciidoctor` (HTML,
website), `-a epub3-stylesheet=asciidoctor-epub3` (EPUB), `-a
pdf-theme=default` (PDF; `-a pdf-compat` for asciidoctor-pdf's layout
too).

## Values

| Element | Rule | PDF (theme `asciidart`) | HTML and website | EPUB |
| --- | --- | --- | --- | --- |
| Text face | a serif with real italics and small capitals | Noto Serif | Noto Serif | Noto Serif |
| Heading and label face | a sans, bold | M+ 1p | Open Sans, 600 | M+ 1p |
| Code face | a monospace, a little smaller than the text | M+ 1mn, 0.9 of the text | Droid Sans Mono, 0.9em | M+ 1mn |
| Text size | 10–12 pt in print, 16–20 px on screen | 10.5 pt | 1.0625rem (17 px) | the reader's |
| Line spacing | 120–145% in print, about 160% on screen | 1.4 | 1.6 | 1.5 |
| Measure | 45–90 characters, 60–75 best | about 75: Letter or A4 with 1.5in side margins | 42em (about 80 characters) | the reader's |
| Paragraphs | space between or a first-line indent, not both: space, as technical books do | 6 pt apart, no indent | 1em apart (Asciidoctor's) | Asciidoctor-epub3's |
| Alignment | justified only with hyphenation | justified and hyphenated | left | left, hyphenated with `:hyphens:` |
| Headings | bold, near-black, a modest scale, more space above than below, kept with what follows | 26 / 20 / 14 / 12 / 11 / 10.5 pt; 1.5em above, 0.5em below; `heading_min_height_after: auto` | #191919 (not Asciidoctor's red) | M+ 1p (asciidoctor-epub3's) |
| Text color | not pure black on screen | #1F1F1F | Asciidoctor's | asciidoctor-epub3's |
| Color | for links and labels only | links #2156A5 | links #2156A5 | links #2156A5 |
| Code blocks | a light tint, no border, room around | #F7F7F8, no border, 9 pt padding | #F7F7F8 (Asciidoctor's), no border | asciidoctor-epub3's |
| Notes and warnings | a label in the heading face, a rule beside the text | label in M+ 1p bold, a rule in the label's color | Asciidoctor's | asciidoctor-epub3's |
| Tables | horizontal rules only, a heavier one under the header | 0.5 pt rows, 1 pt under the head, no columns, no stripes | rows only | asciidoctor-epub3's |
| Captions | smaller, in the heading face | M+ 1p, 0.9 of the text, #555555 | Asciidoctor's | asciidoctor-epub3's |
| Small capitals | from the font, never shrunk capitals | `small-caps` role: `smcp` | `small-caps` role: `font-variant: small-caps` | same |
| Keep together | `%unbreakable` | kept on one page | `break-inside: avoid` in print | `break-inside: avoid` |
| Footnotes | at the foot of the page in print | page bottom (modern engine) | end of the page | pop-ups |

Generated text (caption numbers, footnote markers, callout markers) is
not part of the style: its defaults are Asciidoctor's (ADR-0010), and the
templates change it.
