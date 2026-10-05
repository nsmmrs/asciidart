# Vendored files

`highlight.js/` holds files from [highlight.js](https://github.com/highlightjs/highlight.js)
11.12.0 (commit `f7f7d3803bd898e37c017ffb881317f0cde04a70`), unchanged, under
its BSD 3-Clause license (`highlight.js/LICENSE`):

- `src/`: the engine sources hilite's engine (`lib/src`) is ported from, and
  the language definitions its generated languages come from;
- `test/markup` and `test/detect`: upstream's tests, which hilite runs
  against itself (`test/markup_test.dart`, `test/detect_test.dart`).

`tool/vendor.sh` recreates the folder; `tool/vendor.sh --check` verifies it.
