#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Ruby baseline benchmark for ADR-0001 D2 (AOT binary must beat Ruby).
#
# Times the repo Ruby CLI end to end (process spawn + convert) over a fixed
# corpus x backend matrix and reports wall-clock medians.
#
# Usage (from repo root):
#   ruby benchmark/baseline.rb [--iterations N] [--warmup N]
#
# Each cell runs `ruby -Ilib bin/asciidoctor -b <backend> -o <tmp> <doc>`
# N times (after W warmup runs) and prints every sample plus the median.

require 'optparse'
require 'tmpdir'

CORPUS = {
  'small' => 'test/fixtures/basic.adoc', # 86 B
  'medium' => 'test/fixtures/lists.adoc', # 1431 B
  'large' => 'benchmark/sample-data/mdbasics.adoc', # 7840 B
}.freeze

BACKENDS = %w[html5 docbook5].freeze

options = { iterations: 21, warmup: 3 }
OptionParser.new do |o|
  o.on('--iterations N', Integer) {|v| options[:iterations] = v }
  o.on('--warmup N', Integer) {|v| options[:warmup] = v }
end.parse!

def median(samples)
  s = samples.sort
  s[s.size / 2]
end

def run_once(doc, backend, out)
  start = Process.clock_gettime Process::CLOCK_MONOTONIC
  ok = system 'ruby', '-Ilib', 'bin/asciidoctor', '-b', backend, '-o', out, doc,
    out: File::NULL, err: File::NULL
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  raise %(conversion failed: #{doc} #{backend}) unless ok
  elapsed
end

Dir.mktmpdir do |dir|
  out = File.join dir, 'out'
  CORPUS.each do |label, doc|
    raise %(missing corpus file: #{doc}) unless File.file? doc
    BACKENDS.each do |backend|
      options[:warmup].times { run_once doc, backend, out }
      samples = Array.new(options[:iterations]) { run_once doc, backend, out }
      puts %(#{label}/#{backend} n=#{samples.size} median=#{format '%.1f', median(samples) * 1000.0}ms)
      puts %(  samples_ms=#{samples.map {|t| (t * 1000.0).round 1 }.join ','})
    end
  end
end
