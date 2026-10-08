# AsciiMath fixtures

`expected.json` is what the `asciimath` gem 2.0.6 (MIT) writes for each
expression of `expressions.txt`: `AsciiMath.parse(e).to_mathml('mml:')`,
or `ERROR: <class>` where the gem raises.

`expressions.txt` (1,250 expressions) holds the gem spec's examples
(`spec/parser_spec.rb` at v2.0.6), earlier hand-picked expressions, and
every symbol of the gem's table alone, applied (`s(a)(b)`) and in scripts
(`x_s^s s`). `tool/asciimath_corpus.rb` regenerates both files with the gem
installed:

```sh
ruby tool/asciimath_corpus.rb path/to/asciimath/spec/parser_spec.rb
```
