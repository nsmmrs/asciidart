# Writes the reference for test/pdf/text_box_test.dart: paragraphs laid
# out by Prawn 2.4 with asciidoctor-pdf 2.3.27's extensions.
#
#   ruby test/pdf/fixtures/prawn_text.rb test/pdf/fixtures/prawn_text.pdf
#
# (with a gem home where asciidoctor-pdf 2.3.27 is installed)
require 'asciidoctor/pdf'
FONTS = File.join Gem.loaded_specs['asciidoctor-pdf'].full_gem_path, 'data', 'fonts'
lorem = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.'
klass = Class.new(Prawn::Document) { include Asciidoctor::Logging; include Asciidoctor::Prawn::Extensions }
pdf = klass.new page_size: 'A4', margin: [36, 48, 48, 48]
pdf.font_families.update('Noto Serif' => { normal: "#{FONTS}/notoserif-regular-subset.ttf", bold: "#{FONTS}/notoserif-bold-subset.ttf", italic: "#{FONTS}/notoserif-italic-subset.ttf", bold_italic: "#{FONTS}/notoserif-bold_italic-subset.ttf" })
pdf.font 'Noto Serif', size: 10.5
lh = 1.15
size = 10.5
lhl = lh * size; leading = lhl - size
pad_top = leading / 2 + pdf.font.line_gap; pad_bot = leading / 2
fmt = Asciidoctor::PDF::FormattedText::Formatter.new
[[lorem, :justify], [lorem, :left], ['Some <strong>bold</strong> and <em>italic</em> text with <code>code</code> in it, and <a href="https://example.org">a link</a>.', :left], ['Centered text over a couple of lines, to see where each line starts when it is centered.', :center], ['line one<br>line two', :left]].each do |(text, align)|
  frags = fmt.format text
  pdf.formatted_text frags, leading: leading, initial_gap: pad_top, final_gap: false, align: align
  pdf.move_down pad_bot
  pdf.move_down 12
end
30.times { pdf.formatted_text (fmt.format lorem), leading: leading, initial_gap: pad_top, final_gap: false, align: :justify; pdf.move_down pad_bot; pdf.move_down 12 }
pdf.render_file ARGV[0]
