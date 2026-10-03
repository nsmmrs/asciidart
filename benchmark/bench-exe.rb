#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Exe benchmark for ADR-0001 D2 (AOT binary must beat Ruby).
#
# Same method as benchmark/baseline.rb — CLI end to end (process spawn +
# convert) over the fixed corpus x backend matrix, wall-clock medians —
# but the subject under test is any exe command line, so Ruby, Dart VM,
# and the AOT binary are timed identically.
#
# Usage (from repo root):
#   ruby benchmark/bench-exe.rb --exe 'ruby -Ilib bin/asciidoctor' [--iterations N] [--warmup N]
#   ruby benchmark/bench-exe.rb --exe 'dart run dart/bin/asciidoctor.dart' [--iterations N] [--warmup N]
#   ruby benchmark/bench-exe.rb --exe /tmp/dist/asciidoctor-linux-x64 [--iterations N] [--warmup N]
#
# Each cell runs `<exe> -b <backend> -o <tmp> <doc>` N times (after W
# warmup runs) and prints every sample plus the median.

require 'optparse'
require 'shellwords'
require 'tmpdir'

CORPUS = {
  'small' => 'test/fixtures/basic.adoc', # 86 B
  'medium' => 'test/fixtures/lists.adoc', # 1431 B
  'large' => 'benchmark/sample-data/mdbasics.adoc', # 7840 B
}.freeze

BACKENDS = %w[html5 docbook5].freeze

options = { iterations: 21, warmup: 3, exe: nil }
OptionParser.new do |o|
  o.on('--exe CMD', 'Subject command line (shell-quoted)') {|v| options[:exe] = v }
  o.on('--iterations N', Integer) {|v| options[:iterations] = v }
  o.on('--warmup N', Integer) {|v| options[:warmup] = v }
end.parse!

abort 'missing required option --exe' if options[:exe].nil? || options[:exe].empty?

EXE = Shellwords.split options[:exe]

def median(samples)
  s = samples.sort
  s[s.size / 2]
end

def run_once(doc, backend, out)
  start = Process.clock_gettime Process::CLOCK_MONOTONIC
  ok = system(*EXE, '-b', backend, '-o', out, doc,
    out: File::NULL, err: File::NULL)
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
