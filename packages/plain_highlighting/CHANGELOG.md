# Changelog

## 0.1.0 (unreleased)

- Renamed from `hilite` to `plain_highlighting`, and moved with its history
  into the ptome pub workspace (github.com/nsmmrs/ptome,
  `packages/plain_highlighting`; ptome's ADR-0018). The API is
  `Highlighting` (the class) and `highlighting` (the default instance), in
  place of `Hilite` and `hilite`.
- First version: a pure-Dart port of highlight.js 11.12.0 with all 193 of
  its languages (generated from upstream), `highlight`, `highlightAuto` and
  language lookup. Byte-identical with highlight.js on upstream's 568 markup
  tests, and the same auto-detection on 766 samples.
- About three times faster on the Dart VM (0.47 s for 2.1 MiB of code,
  from 1.38 s; highlight.js on Node.js: 0.32 s): a mode's rules are tried
  only where they can start (read from their sources), each alone,
  instead of searching for one alternation of them (see
  `benchmark/BASELINE.md`). JavaScript keeps the platform's engine.
- The languages are data, not code: the generator writes each mode graph
  as a compact grammar (a string table and the modes' keys), all of them
  one Brotli stream decoded the first time a language is used (15 ms),
  each language read from it then. The generated sources go from 3.1 MB to
  0.36 MB, ptome's executable from 18.6 MB to 14.9 MB, and its JavaScript
  bundle from 2.74 MB to 1.57 MB (gzipped 731 KB to 688 KB); highlighting
  is unchanged (the graphs were compared with the generated code's,
  language by language). Regenerating keeps the committed stream when its
  content is the same (Brotli's bytes differ between versions).
- highlight.js's 82 themes (`highlightJsStyles`, each stylesheet by name),
  moved from ptome.
