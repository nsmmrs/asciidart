# Performance

Measured 2026-10-05 on Linux x64 (Dart 3.13 AOT, Node.js 26), over the 7,418
source blocks (2 MiB of code) found in the asciidart parity corpus, each
highlighted with its declared language (`benchmark/throughput.dart` and its
twin `benchmark/throughput.mjs`, fed by `tool/generate/differential.mjs`):

| | first pass | warm |
| --- | --: | --: |
| plain_highlighting (AOT executable) | 1.68 s | 1.43 s |
| highlight.js (Node.js) | 0.68 s | 0.30 s |

plain_highlighting produces the same output for every block (`tool/differential.dart`),
but is about 5x slower than highlight.js on V8 once warm. Nearly all of the
time (about 90%) is spent in regular expression searches, the same ones
highlight.js runs: Dart's regular expression engine is 6 to 10 times slower
than V8's on these patterns (a search loop over 1.4 MB of Java and
JavaScript: 184 ms against 19 ms for a typical rule alternation, 36 ms
against 6 ms for `\w+`). Compiled to JavaScript, plain_highlighting uses the platform's
engine instead.

In absolute terms plain_highlighting highlights about 1.5 MB of code per second, and
compiling a language on first use is cheap (the first pass is about 15%
slower than the warm ones).

Ideas for the Dart VM, not done yet: skip positions where no rule can start
(a first-character prefilter) before running a mode's alternation, or
compile the rules that are plain enough into a faster matcher, with the
markup, detection and differential checks guarding exactness.
