# Changelog

## 0.1.0-dev (unreleased)

- The AsciiMath and LaTeX converters from ptome and the MathML tree from
  plain_pdf, with their history, in one package. The MathML reader is its
  own (no package:xml), strict where package:xml isn't (an unquoted
  attribute value, text after the root element), and `MathStyled.color`
  is the `mathcolor` text as written.
- `asciimathToMath` and `latexToMath` give the tree (read from the
  MathML they write, by the package's own reader).
- The AsciiMath fixtures grow to 1,250 expressions: the gem spec's
  examples and every symbol of its table.
- LaTeX compared with Temml and KaTeX over the 186 examples of Temml's
  screen tests, which found: characters beyond the BMP (`𝐀`) are read
  whole, not as two U+FFFDs; letters of any script are identifiers;
  `\not<` and `\not>` are escaped once; `\not x` strikes the letter;
  `\dots` is centered before an operator; `\operatorname*` and symbols in
  `\operatorname`; any symbol as a `\big` delimiter; `alignat`'s and
  starred matrices' arguments; `rcases`; `\imath`, `\jmath`; unknown
  environments and delimiters are reported.
- `\text` reads TeX's text mode: groups, `~`, `\ `, escaped characters,
  accents (`\"o`), the text style commands, the quote and dash ligatures,
  collapsed spaces and `$...$` math in it.
