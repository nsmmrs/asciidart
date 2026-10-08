# Performance

Measured 2026-10-08 on Linux x64 (Dart 3.13 AOT, Node.js 26), over the 7,829
source blocks (2.1 MiB of code) in the AsciiDoc files of the ascii-docs
corpus, each highlighted with its declared language
(`benchmark/throughput.dart` and its twin `benchmark/throughput.mjs`, fed by
`tool/generate/differential.mjs`):

| | first pass | warm |
| --- | --: | --: |
| plain_highlighting (AOT executable) | 0.59 s | 0.47 s |
| plain_highlighting, one alternation per mode (before) | 1.50 s | 1.38 s |
| highlight.js (Node.js) | 0.72 s | 0.32 s |

plain_highlighting produces the same output for every block
(`tool/differential.dart`). Nearly all of the time is spent in regular
expression matching. Dart's engine is 6 to 10 times slower than V8's on
highlight.js's patterns (a search loop over 1.4 MB of Java and JavaScript:
184 ms against 19 ms for a typical rule alternation, 36 ms against 6 ms
for `\w+`), so on the Dart VM a mode's rules aren't searched for as one
alternation, as highlight.js does:

- The characters each rule's matches can start with are read from its
  source (`lib/src/first_chars.dart`), and a search goes through the text
  trying, at each position, only the rules that can start with the
  character there, each compiled alone, in order: the alternation's
  match, since its first alternative that matches at the leftmost
  position wins.
- A rule that starts words (`\b` before a word character) isn't tried
  right after a word character.
- A rule whose matches start with a run of a class (`[a-z]\w*...`, `\w+`)
  and that didn't match at a position isn't tried further into the same
  run: a match there would also be one from the run's start.

A mode with a rule whose first characters can't be read (one that can
match empty, such as `\b|\B`; Unicode mode) is searched as one
alternation. Compiled to JavaScript, plain_highlighting uses the platform's
engine and the alternations. `test/first_chars_test.dart` checks what the
search skips by against every rule of every language on upstream's
samples; the markup, detection and differential checks guard the output.
