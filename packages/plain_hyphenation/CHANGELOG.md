# Changelog

## 0.1.0-dev (unreleased)

- `PatternHyphenator` (Liang's algorithm) from plain_pdf, with its
  history, and the hyph-utf8 patterns of 72 languages, their aliases and
  `patternTag` from ptome, in one package.
- The patterns are stored Brotli-compressed, one stream per language
  family (808 KiB of source, from 1.5 MB of base64 zlib), and decoded a
  family at a time.
- The patterns are compiled to a trie when they are generated, decoded
  straight into typed arrays (German: 0.8 ms instead of 22 ms to build
  the hyphenator), and words are hyphenated by walking it instead of
  looking up every substring in a map (6-15 times faster per word not
  yet cached); the data is 22% smaller (631 KiB of base64, from 808 KiB).
  A frozen copy of the old algorithm is the oracle of a randomized
  equivalence test over all 72 languages.
- Tested against Hyphenopoly and pub.dev's `hyphenation` package
  (given the same patterns: every word the same) on the UDHR's words in
  19 languages.
