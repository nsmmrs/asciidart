# Makes the golden files of the corpus (packages/ptome/test/corpus): for each
# case and each of its formats, the file the Asciidoctor command line writes,
# in <case>/expected/<release>/<format>/.
#
#   cd packages/ptome_corpus_tools/goldens
#   BUNDLE_GEMFILE=asciidoctor-2.0.26/Gemfile bundle exec ruby generate.rb \
#     [--replace] [-j N] ../../ptome/test/corpus [CASE...]
#
# The release is the bundle's (asciidoctor-<version>). Each case is converted
# as `asciidoctor -b <backend> -D <dir> input.adoc` (with asciidoctor-pdf and
# asciidoctor-epub3 loaded) with the corpus's attributes (goldens.yml: a
# fixed clock) and the case's own (case.yml: attributes, safe mode, doctype),
# from two copies of the case in different directories: a result that
# differs between them (a path in the output) is refused. Existing goldens
# are kept unless --replace; a conversion that fails writes none.
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'asciidoctor'
require 'asciidoctor/cli'
require 'asciidoctor-pdf'
require 'asciidoctor-epub3'

BACKENDS = %w(html5 xhtml5 docbook5 manpage pdf epub3).freeze

replace = !(ARGV.delete '--replace').nil?
jobs = 4
if (i = ARGV.index '-j')
  jobs = Integer ARGV[i + 1]
  ARGV.slice! i, 2
end
corpus = File.expand_path(ARGV.shift || abort('usage: generate.rb [--replace] [-j N] CORPUS [CASE...]'))
only = ARGV
release = %(asciidoctor-#{Asciidoctor::VERSION})
suite = YAML.safe_load_file File.join(corpus, 'goldens.yml')
suite_attributes = suite['attributes'] || {}

# `-a` arguments for attributes: a value of false unsets the attribute.
def attribute_args attributes
  attributes.flat_map do |name, value|
    ['-a', value == false ? %(#{name}!) : (value.to_s.empty? ? name : %(#{name}=#{value}))]
  end
end

# Converts the case in dir to backend into out; the file written, or nil.
def convert dir, backend, args, out
  FileUtils.mkdir_p out
  Dir.chdir dir do
    invoker = Asciidoctor::Cli::Invoker.new [*args, '-b', backend, '-D', out, '-q', 'input.adoc']
    invoker.invoke!
    return nil unless invoker.code == 0
  end
  # The file written (a man page is named after its name and volume, not the
  # input), not a stylesheet copied beside it.
  written = Dir.children(out).reject {|name| name.end_with? '.css' }
  written.size == 1 ? File.join(out, written[0]) : nil
end

cases = Dir.children(corpus).sort.select {|name| File.file? File.join(corpus, name, 'input.adoc') }
cases &= only unless only.empty?
results = { written: 0, kept: 0, failed: [], located: [] }
queue = cases.dup
running = {}
reports = Dir.mktmpdir 'goldens-reports'

work = lambda do |name|
  dir = File.join corpus, name
  meta = File.file?(path = File.join(dir, 'case.yml')) ? YAML.safe_load_file(path) : {}
  args = attribute_args suite_attributes
  args += attribute_args meta['attributes'] || {}
  args += ['-S', meta['safe']] if meta['safe']
  args += ['-d', meta['doctype']] if meta['doctype']
  report = []
  (meta['formats'] || ['html5']).each do |backend|
    raise %(#{name}: unknown format #{backend}) unless BACKENDS.include? backend
    target = File.join dir, 'expected', release, backend
    if !replace && Dir.exist?(target) && !Dir.empty?(target)
      report << [:kept, backend]
      next
    end
    outputs = Dir.mktmpdir do |tmp|
      %w(a b/c).map do |where|
        copy = File.join tmp, where, name
        FileUtils.mkdir_p copy
        Dir.children(dir).each do |entry|
          FileUtils.cp_r File.join(dir, entry), copy unless entry == 'expected' || entry == 'ptome.yml'
        end
        # (Inside the case: a safe mode keeps the output there.)
        file = convert copy, backend, args, File.join(copy, '.golden', backend)
        file && [File.basename(file), File.binread(file)]
      end
    end
    if outputs.any?(&:nil?)
      report << [:failed, backend]
    elsif outputs[0] != outputs[1]
      report << [:located, backend]
    else
      FileUtils.rm_rf target
      FileUtils.mkdir_p target
      File.binwrite File.join(target, outputs[0][0]), outputs[0][1]
      report << [:written, backend]
    end
  end
  report
end

until queue.empty? && running.empty?
  while running.size < jobs && (name = queue.shift)
    pid = fork do
      $stderr.reopen File::NULL
      report = begin
        work.call name
      rescue Exception => e # rubocop:disable Lint/RescueException
        [[:failed, %(all: #{e.class}: #{e.message[0, 200]})]]
      end
      File.binwrite File.join(reports, name), Marshal.dump(report)
      exit! 0
    end
    running[pid] = name
  end
  pid = Process.wait
  running.delete pid
end
cases.each do |name|
  path = File.join reports, name
  report = File.file?(path) ? Marshal.load(File.binread path) : [[:failed, 'all: the process died']] # rubocop:disable Security/MarshalLoad
  report.each do |(kind, format)|
    case kind
    when :written then results[:written] += 1
    when :kept then results[:kept] += 1
    when :failed then results[:failed] << %(#{name}##{format})
    when :located then results[:located] << %(#{name}##{format})
    end
  end
end
FileUtils.rm_rf reports
puts %(#{release}: #{results[:written]} written, #{results[:kept]} kept)
results[:failed].each {|id| puts %(  no golden (the conversion failed): #{id}) }
results[:located].each {|id| puts %(  no golden (the output depends on the case's directory): #{id}) }
exit(results[:located].empty? ? 0 : 1)
