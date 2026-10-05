# Parity corpus

Documents of our own that pin behavior the vendored fixture corpus
(`vendor/asciidoctor/test/fixtures`) never exercised: where Asciidoctor
2.0.26 (the release this port targets, see
[ADR-0003](../../adr/0003-target-latest-stable.md)) differs from upstream
`main`, and differences found later. They run through the same differential
harness:

```sh
tool/parity.sh build/asciidoctor
```

| File | Covers |
| --- | --- |
| `blocks.adoc` | `~~~~` is not an open block (#1121); empty section ids (#4139); per-section `toclevels` (#2618); thematic-break roles (#4101); page breaks (#4051); `linenums` on source blocks (#3313); ordered list start and marker styles (#2218, #3252); empty list item text before block content (#4182); table widths (#4160) and stripes |
| `inline.adoc` | no `cxx` attribute (#4442); `[` in formatted-text attribute lists (#4306); dots in attribute names (#4147); `link=self` (#3656); inline image ids (#4311); `imagesdir` on image macros (#3661); Wistia; `<quote>` roles (#2947); hdlist column widths; remote include without `allow-uri-read` (#2284) |
| `doctitle-style.adoc` | a block style above the document title (#4151) |
| `front-matter.adoc` | TOML front matter (#4300) and front matter in includes (#3437) |
| `book-toc.adoc` | multipart book TOC levels (#2262, #4814) |
| `manpage-lists.adoc` | manpage list and table cell spacing (#4182, #4482) |
| `olist-markers.adoc` | ordered list marker validation warnings and implicit styles |
| `substitutions.adoc` | full substitutions in titles that feed generated IDs, quote credits (paragraph and Markdown), single-quoted attribute values, reftext and the author line (BUG-fwc380) |
| `corpus-findings.adoc` | differences found by the corpus parity check (`tool/corpus_parity.dart`): `cols=""`, `%autowidth` with a width, a nested description list item with an attached block, line breaks in AsciiMath blocks, special case mappings in generated ids (`ß`, `Σ`), no-break and ideographic spaces |
| `manpage-unicode.adoc` | the same in a man page: upper-cased headings (`ß` → `SS`), a link followed by a no-break space, a trailing ideographic space, `cols=""` |
| `source-coderay-ruby.adoc`, `source-coderay-options.adoc` | CodeRay highlighting of Ruby and its options (line numbers, styles, emphasis) |
