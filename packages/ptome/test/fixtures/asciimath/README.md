# AsciiMath fixtures

`expected.json` is what the `asciimath` gem 2.0.6 (MIT) writes for each
expression of `expressions.txt`: `AsciiMath.parse(e).to_mathml('mml:')`,
or `ERROR: <class>` where the gem raises. Regenerate it with the gem
installed:

```sh
ruby -e 'require "asciimath"; require "json"; out = {}
File.readlines(ARGV[0], chomp: true).each { |e| out[e] = begin
AsciiMath.parse(e).to_mathml("mml:") rescue => x; "ERROR: #{x.class}" end }
puts JSON.pretty_generate(out)' expressions.txt > expected.json
```
