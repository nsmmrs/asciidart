# Long-lived Asciidoctor conversion server for ascii-docs.
#
# usage: ADOC_ROOT=<asciidoctor checkout> ruby worker.rb [--coverage]
#
# Reads one JSON request per line on stdin, writes one JSON response per line
# on stdout, in order. The first line written is a header:
#   {"ready": true, "version": "...", "universe": {"lines": [...], "branches": [...]},
#    "load_time": {"lines": [...], "branches": [...]}}
# ("universe" only with --coverage: every relevant line and branch arm of the
# checkout's lib/, as "file:line" and "file:line:col:type:arm@line:col";
# "load_time": the universe indices loading alone reaches).
#
# Request:  {"id", "input", "base_dir", "backend", "doctype"?, "safe",
#            "standalone", "attributes": {name: value}, "options"?: {...}}
#   "options": other API options, passed as they are (captured test inputs).
#   An attribute named "name!" unsets name; a value ending in "@" is soft.
# Response: {"id", "ok", "output"?, "log": [{"severity", "message", "lineno"?, "path"?}],
#            "err"?, "ms", "lines"?, "branches"?}
#   lines/branches (with --coverage): universe indices this case reached.
require 'json'
require 'coverage'

ROOT = File.expand_path ENV.fetch('ADOC_ROOT')
LIB = File.join ROOT, 'lib'
COVERAGE = ARGV.include? '--coverage'

# Optional gems and stdlib load before Coverage.start so they are not
# tracked: every tracked file makes each per-case Coverage.result slower.
begin
  gem 'cgi' # Ruby 4's default cgi lacks CGI.parse
rescue Gem::LoadError
end
%w(cgi open-uri pathname strscan uri set logger erb stringio).each do |lib|
  require lib
rescue LoadError
end
verbose, $VERBOSE = $VERBOSE, nil # rouge's lexers redefine constants
begin
  require 'rouge'
  lexers = File.join Gem.loaded_specs['rouge'].full_gem_path, 'lib/rouge/lexers'
  Dir[File.join lexers, '*.rb'].sort.each do |file|
    require file
  rescue Exception # rubocop:disable Lint/RescueException
  end
rescue LoadError
end
begin
  require 'coderay'
  CodeRay::Scanners.list.each {|scanner| CodeRay::Scanners[scanner] rescue nil }
rescue LoadError
end
begin
  require 'asciimath'
rescue LoadError
end
$VERBOSE = verbose

Coverage.start lines: true, branches: true if COVERAGE
$LOAD_PATH.unshift LIB
require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor/cli'
# Lazily required parts load now, so their load-time lines are baseline
# instead of being charged to the first case that needs them.
%w(converter/html5 converter/docbook5 converter/manpage converter/template
   syntax_highlighter syntax_highlighter/highlightjs syntax_highlighter/rouge
   syntax_highlighter/coderay syntax_highlighter/prettify
   syntax_highlighter/html_pipeline syntax_highlighter/pygments timings).each do |part|
  require "asciidoctor/#{part}"
rescue LoadError
end

def lib_file? path
  path.start_with?(LIB) && path.end_with?('.rb')
end

LINE_TAB = Hash.new {|h, k| h[k] = [] }
ARM_TAB = Hash.new {|h, k| h[k] = {} }
universe = nil
load_time = nil
baseline = nil
if COVERAGE
  lines = []
  branches = []
  (baseline = Coverage.peek_result).each do |file, cov|
    next unless lib_file? file
    rel = file.delete_prefix "#{ROOT}/"
    cov[:lines].each_with_index do |count, i|
      next if count.nil?
      LINE_TAB[file][i] = lines.size
      lines << "#{rel}:#{i + 1}"
    end
    cov[:branches].each do |(ctype, _cid, cl, cc, _el, _ec), arms|
      arms.each_key do |(atype, aid, al, ac, _ael, _aec)|
        ARM_TAB[file][aid] = branches.size
        branches << "#{rel}:#{cl}:#{cc}:#{ctype}:#{atype}@#{al}:#{ac}"
      end
    end
  end
  universe = { lines: lines, branches: branches }
  Coverage.result stop: false, clear: true # load-time counts are baseline
end

def reached result
  lines = []
  branches = []
  result.each do |file, cov|
    next unless (tab = LINE_TAB.fetch file, nil)
    cov[:lines].each_with_index {|count, i| lines << tab[i] if count && count > 0 && tab[i] }
    arms = ARM_TAB[file]
    cov[:branches].each_value do |counts|
      counts.each {|arm, n| n > 0 && (x = arms[arm[1]]) && branches << x }
    end
  end
  [lines.sort, branches.sort]
end

SEVERITIES = { Logger::DEBUG => 'debug', Logger::INFO => 'info', Logger::WARN => 'warning',
               Logger::ERROR => 'error', Logger::FATAL => 'fatal' }.freeze

def log_entry message
  entry = { severity: SEVERITIES[message[:severity]] || message[:severity].to_s.downcase }
  text = message[:message]
  if Hash === text
    entry[:message] = text[:text].to_s
    if (loc = text[:source_location])
      entry[:lineno] = loc.lineno if loc.respond_to? :lineno
      entry[:path] = loc.path if loc.respond_to?(:path) && loc.path
    end
  else
    entry[:message] = text.to_s
  end
  entry
end

def convert request
  logger = Asciidoctor::MemoryLogger.new
  Asciidoctor::LoggerManager.logger = logger
  opts = {
    safe: (request['safe'] || 'safe').to_sym,
    backend: request['backend'] || 'html5',
    standalone: request['standalone'] ? true : false,
    attributes: request['attributes'] || {},
    to_file: false,
  }
  (request['options'] || {}).each do |key, value|
    opts[key.to_sym] = %w(safe doctype).include?(key) && String === value ? value.to_sym : value
  end
  opts[:to_file] = false
  opts.delete :to_dir
  opts[:doctype] = request['doctype'] if request['doctype']
  opts[:base_dir] = request['base_dir'] if request['base_dir']
  output = Asciidoctor.convert request['input'], opts
  [output, logger.messages.map {|m| log_entry m }]
ensure
  Asciidoctor::LoggerManager.logger = nil
end

$stdout.sync = true
if COVERAGE
  # What loading alone runs (class bodies, constants): covered by every case.
  l, b = reached baseline
  load_time = { lines: l, branches: b }
end
$stdout.puts JSON.generate(ready: true, version: Asciidoctor::VERSION, universe: universe, load_time: load_time)
$stdin.each_line do |line|
  request = JSON.parse line
  t0 = Process.clock_gettime Process::CLOCK_MONOTONIC
  response = { id: request['id'] }
  begin
    output, log = convert request
    response[:ok] = true
    response[:output] = output.to_s
    response[:log] = log
  rescue Exception => e # rubocop:disable Lint/RescueException
    response[:ok] = false
    frame = e.backtrace&.find {|l| l.start_with? LIB } || e.backtrace&.first
    response[:err] = "#{e.class}: #{e.message.to_s[0, 300]}"
    response[:frame] = frame&.delete_prefix("#{ROOT}/")
    response[:log] = []
  end
  response[:ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round 3
  if COVERAGE
    response[:lines], response[:branches] = reached Coverage.result(stop: false, clear: true)
  end
  $stdout.puts JSON.generate(response)
end
