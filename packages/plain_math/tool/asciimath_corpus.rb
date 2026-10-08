# Writes test/fixtures/asciimath/expressions.txt and expected.json with the
# asciimath gem 2.0.6 installed: the expressions are the gem spec's
# examples (spec/parser_spec.rb at v2.0.6, given as the first argument),
# the expressions already listed, and every symbol of the gem's table
# alone, applied (`s(a)(b)`) and in scripts (`x_s^s s`); expected.json is
# AsciiMath.parse(e).to_mathml('mml:') for each, or `ERROR: <class>`
# where the gem raises.
#
#   ruby tool/asciimath_corpus.rb path/to/parser_spec.rb
require 'asciimath'
require 'json'

dir = File.join(__dir__, '..', 'test', 'fixtures', 'asciimath')
spec = File.read(ARGV[0])
examples = spec.scan(/example\('((?:[^'\\]|\\.)*)'/).map { |m| m[0].gsub("\\'", "'").gsub('\\\\', '\\') }
existing = File.readlines(File.join(dir, 'expressions.txt'), chomp: true)
builder = AsciiMath::SymbolTableBuilder.new
AsciiMath::Parser.add_default_parser_symbols(builder)
symbols = builder.build.keys.map(&:to_s)
all = (existing + examples + symbols +
       symbols.map { |s| "#{s}(a)(b)" } + symbols.map { |s| "x_#{s}^#{s} #{s}" })
      .uniq.reject(&:empty?)
File.write(File.join(dir, 'expressions.txt'), all.join("\n") + "\n")
out = {}
all.each do |e|
  out[e] = begin
    AsciiMath.parse(e).to_mathml('mml:')
  rescue => x
    "ERROR: #{x.class}"
  end
end
File.write(File.join(dir, 'expected.json'), JSON.pretty_generate(out) + "\n")
puts "#{all.size} expressions"
