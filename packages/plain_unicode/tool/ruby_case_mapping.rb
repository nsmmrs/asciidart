# Writes test/fixtures/ruby_case_mapping.txt: Ruby's String#upcase and
# String#downcase for every non-ASCII code point they change, the oracle
# test/case_test.dart checks the generated tables against. Run with the Ruby
# whose Unicode version the tables are generated for (Ruby 4.0.7, Unicode
# 17.0.0):
#
#   ruby tool/ruby_case_mapping.rb
def table(method)
  (0x80..0x10FFFF).filter_map do |cp|
    next if cp.between?(0xD800, 0xDFFF)
    char = cp.chr('UTF-8')
    mapped = char.public_send(method)
    next if mapped == char
    "#{cp.to_s(16)} #{mapped.codepoints.map { |c| c.to_s(16) }.join(' ')}"
  end
end

out = File.join(__dir__, '..', 'test', 'fixtures', 'ruby_case_mapping.txt')
File.open(out, 'w') do |f|
  f.puts "# Ruby #{RUBY_VERSION} (Unicode #{RbConfig::CONFIG['UNICODE_VERSION']}): " \
         'code point, then its mapping (hexadecimal)'
  f.puts '[upcase]'
  table(:upcase).each { |line| f.puts line }
  f.puts '[downcase]'
  table(:downcase).each { |line| f.puts line }
end
puts "wrote #{out}"
