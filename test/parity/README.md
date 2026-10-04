# Parity corpus

Documents that pin behavior where Asciidoctor 2.0.26 (the release this port
targets, see [ADR-0003](../../adr/0003-target-latest-stable.md)) differs from
upstream `main`. The fixture corpus in `test/fixtures` never exercised most of
these, so they live here and run through the same differential harness:

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
