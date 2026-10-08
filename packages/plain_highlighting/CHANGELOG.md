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
