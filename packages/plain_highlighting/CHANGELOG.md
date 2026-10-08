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
