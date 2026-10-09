# Runs Asciidoctor's test suite and records every top-level document its
# tests construct, with the options they pass, one JSON object per line:
#   {"test": "file_test.rb:LINE", "input": "..." | "path": "...",
#    "options": {...}, "unreplayable": ["opt", ...]}
# (Asciidoctor.load/convert and the helpers' Document.new all go through
# Document#initialize; nested documents, such as AsciiDoc table cells, are
# skipped.)
#
# usage: ADOC_ROOT=<checkout> CAPTURE_OUT=out.jsonl ruby capture.rb
require 'json'
gem 'cgi' # Ruby 4's default cgi lacks CGI.parse
require 'cgi'
ROOT = File.expand_path ENV.fetch('ADOC_ROOT')
OUT = File.open ENV.fetch('CAPTURE_OUT'), 'w'
$LOAD_PATH.unshift File.join(ROOT, 'lib'), File.join(ROOT, 'test')
require 'asciidoctor'

module Capture
  SIMPLE = [String, Symbol, Integer, Float, TrueClass, FalseClass, NilClass].freeze

  def self.jsonable value
    case value
    when *SIMPLE then true
    when Array then value.all? {|x| jsonable x }
    when Hash then value.all? {|k, x| (String === k || Symbol === k) && jsonable(x) }
    else false
    end
  end

  def initialize input = nil, options = {}
    unless (options || {})[:parent]
      begin
        frame = caller_locations.find {|l| l.path.end_with? '_test.rb' }
        record = { test: frame && "#{File.basename frame.path}:#{frame.lineno}" }
        case input
        when ::File then record[:path] = input.path
        when ::String then record[:input] = input
        when ::Array then record[:input] = input.map(&:chomp).join("\n")
        end
        if record[:path] || record[:input]
          opts = (options || {}).dup
          opts.delete :input_mtime
          record[:options] = opts.select {|_, v| Capture.jsonable v }.transform_values {|v| Symbol === v ? v.to_s : v }
          record[:unreplayable] = opts.reject {|_, v| Capture.jsonable v }.keys.map(&:to_s)
          OUT.puts JSON.generate(record)
        end
      rescue => e
        OUT.puts JSON.generate(capture_error: e.message)
      end
    end
    super
  end
end
Asciidoctor::Document.prepend Capture
Dir[File.join(ROOT, 'test/**/*_test.rb')].sort.each {|f| require f }
Minitest.after_run { OUT.close }
ARGV.replace %w(--seed 1)
