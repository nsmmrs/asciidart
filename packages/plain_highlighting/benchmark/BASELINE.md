# Performance

Measured 2026-10-08 on Linux x64 (Dart 3.13 AOT, Node.js 26), over the 7,829
source blocks (2.1 MiB of code) in the AsciiDoc files of the ascii-docs
corpus, each highlighted with its declared language
(`benchmark/throughput.dart` and its twin `benchmark/throughput.mjs`, fed by
`tool/generate/differential.mjs`):

| | first pass | warm |
| --- | --: | --: |
| plain_highlighting (AOT executable) | 0.32 s | 0.17 s |
| plain_highlighting, first-character dispatch only (before) | 0.68 s | 0.52 s |
| plain_highlighting, one alternation per mode (before that) | 1.50 s | 1.38 s |
| highlight.js (Node.js) | 0.72 s | 0.32 s |

(The first two rows were measured interleaved on a shared machine, the
minimum of nine runs each; the last two on a quieter one, where the second
row's code took 0.59 s and 0.47 s.)

plain_highlighting produces the same output for every block
(`tool/differential.dart`). Most of the time is spent in regular expression
matching. Dart's engine is 6 to 10 times slower than V8's on highlight.js's
patterns (a search loop over 1.4 MB of Java and JavaScript: 184 ms against
19 ms for a typical rule alternation, 36 ms against 6 ms for `\w+`), and on
the VM every call into it costs about 90 ns before any matching (it runs
irregexp's bytecode interpreter). So on the Dart VM a mode's rules aren't
searched for as one alternation, as highlight.js does, and most calls are
avoided in Dart:

- The characters each rule's matches can start with are read from its
  source (`lib/src/first_chars.dart`), and a search goes through the text
  trying, at each position, only the rules that can start with the
  character there, each compiled alone, in order: the alternation's
  match, since its first alternative that matches at the leftmost
  position wins.
- A rule that starts words (`\b` before a word character) isn't tried
  right after a word character, and one that starts lines (`^`) only at
  a line's start.
- A rule whose matches start with a run of a class (`[a-z]\w*...`, `\w+`)
  and that didn't match at a position isn't tried further into the same
  run: a match there would also be one from the run's start.
- A rule whose matches start with a literal is tried only where it is;
  one that is a literal alone, or the default end `\B|\b`, is matched
  without the engine.
- A rule whose leading run must be taken whole is tried only where the
  character after the run can follow it; one whose first terms take
  characters of one set before a term that takes, or looks at, one of
  another (Java's declarations, before a `(` or `=`), only where the
  first character out of that set is one of the other.
- A rule that has a literal a few characters in (`.?html\``) is tried
  only near that literal's next occurrence, searched for once.

These are supersets: `test/first_chars_test.dart` checks, against every
rule of every language on upstream's samples, that each lets the rule be
tried wherever it matches. In Unicode mode, no position inside a surrogate
pair is tried (nor does the engine start a match there). A mode with a
rule whose first characters can't be read is searched as one alternation.
Compiled to JavaScript, plain_highlighting uses the platform's engine and
the alternations.

Outside the engine: keywords are found by scanning words in Dart (for the
default `\w+`), the mode buffer is a slice of the code until it can't be,
HTML is written as it is emitted (escaped in one pass) instead of from a
token tree, and each rule's first characters and group count are read once
for all the matchers that share it.
