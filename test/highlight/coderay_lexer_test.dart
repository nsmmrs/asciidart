/// Unit tests for the real CodeRay lexer backend.
///
/// Every expected fragment below is byte-identical oracle output,
/// captured with (CodeRay 1.1.3, same options the adapter passes):
/// ```sh
/// ruby -e "require 'coderay'; \
///   print CodeRay::Duo[:ruby, :html, {css: :class, \
///     line_numbers: nil, line_number_start: 1, \
///     line_number_anchors: false, highlight_lines: [], \
///     bold_every: false}].highlight(\$SOURCE)"
/// ```
/// (`highlight_lines: []` renders identically to the `nil` the Ruby
/// adapter passes when the block has no `highlight` attribute.)
library;

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// Highlights [source] as Ruby through the real lexer backend.
String highlightRuby(
  String source, {
  String? language = 'ruby',
  CssMode cssMode = CssMode.classes,
  LineNumbersMode? numberLines,
  int? startLineNumber = 1,
  List<int> highlightLines = const [],
}) {
  final html = const CodeRaySourceLexer().highlight(
    HighlightRequest(
      source: source,
      language: language,
      cssMode: cssMode,
      numberLines: numberLines,
      startLineNumber: startLineNumber,
      highlightLines: highlightLines,
    ),
  );
  return html!;
}

void main() {
  group('strings', () {
    test('fixture', () {
      expect(
        highlightRuby("puts 'Hello, World!'\n"),
        'puts <span class="string"><span class="delimiter">\'</span><span class="content">Hello, World!</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('single-quote', () {
      expect(
        highlightRuby("s = 'single'\n"),
        's = <span class="string"><span class="delimiter">\'</span><span class="content">single</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('double-quote', () {
      expect(
        highlightRuby('s = "double"\n'),
        's = <span class="string"><span class="delimiter">&quot;</span><span class="content">double</span><span class="delimiter">&quot;</span></span>\n',
      );
    });
    test('escapes', () {
      expect(
        highlightRuby('s = "a\\nb\\t\\"end"\n'),
        's = <span class="string"><span class="delimiter">&quot;</span><span class="content">a</span><span class="char">\\n</span><span class="content">b</span><span class="char">\\t</span><span class="char">\\&quot;</span><span class="content">end</span><span class="delimiter">&quot;</span></span>\n',
      );
    });
    test('sq-escape', () {
      expect(
        highlightRuby("s = 'it\\'s'\n"),
        's = <span class="string"><span class="delimiter">\'</span><span class="content">it</span><span class="char">\\\'</span><span class="content">s</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('interp', () {
      expect(
        highlightRuby('s = "v=#{x}!"\n'),
        's = <span class="string"><span class="delimiter">&quot;</span><span class="content">v=</span><span class="inline"><span class="inline-delimiter">#{</span>x<span class="inline-delimiter">}</span></span><span class="content">!</span><span class="delimiter">&quot;</span></span>\n',
      );
    });
    test('interp-nested', () {
      expect(
        highlightRuby('s = "a #{"b #{1 + 2}"} c"\n'),
        's = <span class="string"><span class="delimiter">&quot;</span><span class="content">a </span><span class="inline"><span class="inline-delimiter">#{</span><span class="string"><span class="delimiter">&quot;</span><span class="content">b </span><span class="inline"><span class="inline-delimiter">#{</span><span class="integer">1</span> + <span class="integer">2</span><span class="inline-delimiter">}</span></span><span class="delimiter">&quot;</span></span><span class="inline-delimiter">}</span></span><span class="content"> c</span><span class="delimiter">&quot;</span></span>\n',
      );
    });
    test('interp-vars', () {
      expect(
        highlightRuby('s = "#\$g #@i"\n'),
        's = <span class="string"><span class="delimiter">&quot;</span><span class="escape">#</span><span class="global-variable">\$g</span><span class="content"> </span><span class="escape">#</span><span class="instance-variable">@i</span><span class="delimiter">&quot;</span></span>\n',
      );
    });
    test('multiline-sq', () {
      expect(
        highlightRuby("s = 'l1\nl2'\n"),
        's = <span class="string"><span class="delimiter">\'</span><span class="content">l1\nl2</span><span class="delimiter">\'</span></span>\n',
      );
    });
  });

  group('keywords and names', () {
    test('def', () {
      expect(
        highlightRuby('def foo(bar)\n  bar\nend\n'),
        '<span class="keyword">def</span> <span class="function">foo</span>(bar)\n  bar\n<span class="keyword">end</span>\n',
      );
    });
    test('class', () {
      expect(
        highlightRuby('class Foo < Bar\nend\n'),
        '<span class="keyword">class</span> <span class="class">Foo</span> &lt; <span class="constant">Bar</span>\n<span class="keyword">end</span>\n',
      );
    });
    test('keywords', () {
      expect(
        highlightRuby('if a then b elsif c else d end\n'),
        '<span class="keyword">if</span> a <span class="keyword">then</span> b <span class="keyword">elsif</span> c <span class="keyword">else</span> d <span class="keyword">end</span>\n',
      );
    });
    test('method-op', () {
      expect(
        highlightRuby('def ==(o)\nend\n'),
        '<span class="keyword">def</span> <span class="function">==</span>(o)\n<span class="keyword">end</span>\n',
      );
    });
    test('constant', () {
      expect(
        highlightRuby('X = Foo::BAR\n'),
        '<span class="constant">X</span> = <span class="constant">Foo</span>::<span class="constant">BAR</span>\n',
      );
    });
    test('predefined', () {
      expect(
        highlightRuby('nil true false self __FILE__\n'),
        '<span class="predefined-constant">nil</span> <span class="predefined-constant">true</span> <span class="predefined-constant">false</span> <span class="predefined-constant">self</span> <span class="predefined-constant">__FILE__</span>\n',
      );
    });
  });

  group('comments', () {
    test('comment', () {
      expect(
        highlightRuby('# hello\nputs 1 # trailing\n'),
        '<span class="comment"># hello</span>\nputs <span class="integer">1</span> <span class="comment"># trailing</span>\n',
      );
    });
    test('shebang', () {
      expect(
        highlightRuby('#!/usr/bin/env ruby\n'),
        '<span class="doctype">#!/usr/bin/env ruby</span>\n',
      );
    });
    test('rubydoc', () {
      expect(
        highlightRuby('=begin\ndocs\n=end\nputs 1\n'),
        '<span class="comment">=begin\ndocs\n=end</span>\nputs <span class="integer">1</span>\n',
      );
    });
    test('end-data', () {
      expect(
        highlightRuby('puts 1\n__END__\ndata\n'),
        'puts <span class="integer">1</span>\n<span class="comment">__END__\ndata</span>\n',
      );
    });
  });

  group('numbers', () {
    test('integers', () {
      expect(
        highlightRuby('a = 42\nb = 1_000\n'),
        'a = <span class="integer">42</span>\nb = <span class="integer">1_000</span>\n',
      );
    });
    test('floats', () {
      expect(
        highlightRuby('a = 3.14\nb = 1e10\nc = 1.5e-3\n'),
        'a = <span class="float">3.14</span>\nb = <span class="float">1e10</span>\nc = <span class="float">1.5e-3</span>\n',
      );
    });
    test('bases', () {
      expect(
        highlightRuby('a = 0xff\nb = 0o17\nc = 0b101\n'),
        'a = <span class="integer">0xff</span>\nb = <span class="integer">0</span>o17\nc = <span class="integer">0b101</span>\n',
      );
    });
    test('rat-imag', () {
      expect(
        highlightRuby('a = 2r\nb = 3i\n'),
        'a = <span class="integer">2r</span>\nb = <span class="integer">3i</span>\n',
      );
    });
    test('char-lit', () {
      expect(
        highlightRuby('?a\n?\\n\n'),
        '<span class="integer">?a</span>\n<span class="integer">?\\n</span>\n',
      );
    });
    test('char-lit-needs-value', () {
      // `?x` after a value is a bare `?` operator plus ident: closers
      // leave `value_expected` false (fuzz regression).
      expect(highlightRuby('b=(x) ?x\n'), 'b=(x) ?x\n');
    });
  });

  group('symbols and keys', () {
    test('symbols', () {
      expect(
        highlightRuby(':sym\n:foo?\n:==\n'),
        '<span class="symbol">:sym</span>\n<span class="symbol">:foo?</span>\n<span class="symbol">:==</span>\n',
      );
    });
    test('sym-quoted', () {
      expect(
        highlightRuby(':"a b"\n:\'c d\'\n'),
        '<span class="symbol"><span class="symbol">:</span><span class="delimiter">&quot;</span><span class="content">a b</span><span class="delimiter">&quot;</span></span>\n<span class="symbol"><span class="symbol">:</span><span class="delimiter">\'</span><span class="content">c d</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('hash-keys', () {
      expect(
        highlightRuby('{key: 1, \'s\': 2, "d": 3}\n'),
        '{<span class="key">key</span>: <span class="integer">1</span>, <span class="key"><span class="delimiter">\'</span><span class="content">s</span><span class="delimiter">\'</span></span>: <span class="integer">2</span>, <span class="key"><span class="delimiter">&quot;</span><span class="content">d</span><span class="delimiter">&quot;</span></span>: <span class="integer">3</span>}\n',
      );
    });
    test('key-interp', () {
      expect(
        highlightRuby('"a #{x}": 3\n'),
        '<span class="key"><span class="delimiter">&quot;</span><span class="content">a </span><span class="inline"><span class="inline-delimiter">#{</span>x<span class="inline-delimiter">}</span></span><span class="delimiter">&quot;</span></span>: <span class="integer">3</span>\n',
      );
    });
    test('string-key-before-scope', () {
      // The complete-string rule keys on a plain `:`, so `"s"::sym`
      // splits into key + `:` + symbol (fuzz regression).
      expect(
        highlightRuby('"a\nb"::BEGIN\n'),
        '<span class="key"><span class="delimiter">&quot;</span><span class="content">a\nb</span><span class="delimiter">&quot;</span></span>:<span class="symbol">:BEGIN</span>\n',
      );
    });
    test('key-probe-hash-dollar', () {
      // The key probe's atomic first-win choice pins `#$"`/`#$\` over a
      // bare `#` (fuzz regression: both stay strings).
      expect(
        highlightRuby('"#\$\\"b": 1\n'),
        '<span class="string"><span class="delimiter">&quot;</span><span class="escape">#</span><span class="global-variable">\$\\</span><span class="delimiter">&quot;</span></span>b<span class="string"><span class="delimiter">&quot;</span><span class="content">: 1\n</span></span>',
      );
      expect(
        highlightRuby('"#\$": 1\n'),
        '<span class="string"><span class="delimiter">&quot;</span><span class="escape">#</span><span class="global-variable">\$&quot;</span><span class="content">: 1\n</span></span>',
      );
    });
  });

  group('regexps and division', () {
    test('regexp', () {
      expect(
        highlightRuby('r = /ab+c/\nr2 = /x/imx\n'),
        'r = <span class="regexp"><span class="delimiter">/</span><span class="content">ab+c</span><span class="delimiter">/</span></span>\nr2 = <span class="regexp"><span class="delimiter">/</span><span class="content">x</span><span class="delimiter">/</span><span class="modifier">imx</span></span>\n',
      );
    });
    test('division', () {
      expect(highlightRuby('x = a / b\n'), 'x = a / b\n');
    });
  });

  group('variables and calls', () {
    test('vars', () {
      expect(
        highlightRuby('@i\n@@c\n\$g\n\$1\n\$-w\n'),
        '<span class="instance-variable">@i</span>\n<span class="class-variable">@@c</span>\n<span class="global-variable">\$g</span>\n<span class="global-variable">\$1</span>\n<span class="global-variable">\$-w</span>\n',
      );
    });
    test('calls', () {
      expect(
        highlightRuby('obj.meth\nobj::C\nobj&.safe\nf(1)\n'),
        'obj.meth\nobj::<span class="constant">C</span>\nobj&amp;.safe\nf(<span class="integer">1</span>)\n',
      );
    });
  });

  group('heredocs', () {
    test('heredoc', () {
      expect(
        highlightRuby('s = <<EOS\nhello\nEOS\n'),
        's = <span class="string"><span class="delimiter">&lt;&lt;EOS</span></span><span class="string"><span class="content">\nhello</span><span class="delimiter">\nEOS</span></span>\n',
      );
    });
    test('heredoc-ind', () {
      expect(
        highlightRuby('s = <<-EOS\n  hi\n  EOS\n'),
        's = <span class="string"><span class="delimiter">&lt;&lt;-EOS</span></span><span class="string"><span class="content">\n  hi</span><span class="delimiter">\n  EOS</span></span>\n',
      );
    });
    test('heredoc-sq', () {
      expect(
        highlightRuby("s = <<'EOS'\nno #{x}\nEOS\n"),
        's = <span class="string"><span class="delimiter">&lt;&lt;\'EOS\'</span></span><span class="string"><span class="content">\nno #{x}</span><span class="delimiter">\nEOS</span></span>\n',
      );
    });
    test('heredoc-empty', () {
      expect(
        highlightRuby("<<''\nx\n"),
        '<span class="string"><span class="delimiter">&lt;&lt;\'\'</span></span><span class="string"><span class="delimiter">\nx</span></span>\n',
      );
    });
  });

  group('fancy strings and shell', () {
    test('fancy', () {
      expect(
        highlightRuby('%w[a b]\n%r/x/\n%s(s)\n%x(c)\n'),
        '<span class="string"><span class="delimiter">%w[</span><span class="content">a b</span><span class="delimiter">]</span></span>\n<span class="regexp"><span class="delimiter">%r/</span><span class="content">x</span><span class="delimiter">/</span></span>\n<span class="symbol"><span class="delimiter">%s(</span><span class="content">s</span><span class="delimiter">)</span></span>\n<span class="shell"><span class="delimiter">%x(</span><span class="content">c</span><span class="delimiter">)</span></span>\n',
      );
    });
    test('fancy-nest', () {
      expect(
        highlightRuby('%(a (b) c)\n'),
        '<span class="string"><span class="delimiter">%(</span><span class="content">a </span><span class="content">(</span><span class="content">b</span><span class="content">)</span><span class="content"> c</span><span class="delimiter">)</span></span>\n',
      );
    });
    test('shell', () {
      expect(
        highlightRuby('o = `ls`\n'),
        'o = <span class="shell"><span class="delimiter">`</span><span class="content">ls</span><span class="delimiter">`</span></span>\n',
      );
    });
  });

  group('operators and errors', () {
    test('ternary', () {
      expect(
        highlightRuby('x = y ? 1 : 2\n'),
        'x = y ? <span class="integer">1</span> : <span class="integer">2</span>\n',
      );
    });
    test('error-num', () {
      expect(
        highlightRuby('foo.123\n'),
        'foo.<span class="error">123</span>\n',
      );
    });
  });

  group('unicode and normalization', () {
    test('unicode', () {
      expect(
        highlightRuby('café = 1\n'),
        'café = <span class="integer">1</span>\n',
      );
    });
    test('crlf', () {
      expect(
        highlightRuby('a = 1\r\nb = 2\r\n'),
        'a = <span class="integer">1</span>\nb = <span class="integer">2</span>\n',
      );
    });
    test('escapes-html', () {
      expect(
        highlightRuby('s = \'<a>&"\\t\\x01\'\n'),
        's = <span class="string"><span class="delimiter">\'</span><span class="content">&lt;a&gt;&amp;&quot;</span><span class="content">\\t</span><span class="content">\\x</span><span class="content">01</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('empty', () {
      expect(highlightRuby(''), '');
    });
    test('blank', () {
      expect(highlightRuby('\n'), '\n');
    });
  });

  group('encoder options', () {
    test('style-mode', () {
      expect(
        highlightRuby("puts 'hi' # c\n", cssMode: CssMode.inline),
        'puts <span style="background-color:hsla(0,100%,50%,0.05)"><span style="color:#710">\'</span><span style="color:#D20">hi</span><span style="color:#710">\'</span></span> <span style="color:#777"># c</span>\n',
      );
    });
    test('style-key', () {
      expect(
        highlightRuby("{'k': 1}\n", cssMode: CssMode.inline),
        '{<span style="color:#606"><span style="color:#404">\'</span><span>k</span><span style="color:#404">\'</span></span>: <span style="color:#00D">1</span>}\n',
      );
    });
    test('table', () {
      expect(
        highlightRuby('puts 1\nputs 2\n', numberLines: LineNumbersMode.table),
        '<table class="CodeRay"><tr>\n  <td class="line-numbers"><pre>1\n2\n</pre></td>\n  <td class="code"><pre>puts <span class="integer">1</span>\nputs <span class="integer">2</span>\n</pre></td>\n</tr></table>\n',
      );
    });
    test('inline', () {
      expect(
        highlightRuby('puts 1\nputs 2\n', numberLines: LineNumbersMode.inline),
        '<span class="line-numbers">1</span>puts <span class="integer">1</span>\n<span class="line-numbers">2</span>puts <span class="integer">2</span>\n',
      );
    });
    test('table-start', () {
      expect(
        highlightRuby(
          'a\nb\n',
          numberLines: LineNumbersMode.table,
          startLineNumber: 5,
          highlightLines: <int>[5, 6],
        ),
        '<table class="CodeRay"><tr>\n  <td class="line-numbers"><pre><strong class="highlighted">5</strong>\n<strong class="highlighted">6</strong>\n</pre></td>\n  <td class="code"><pre>a\nb\n</pre></td>\n</tr></table>\n',
      );
    });
    test('inline-hl', () {
      expect(
        highlightRuby(
          'a\nb\n',
          numberLines: LineNumbersMode.inline,
          highlightLines: <int>[2],
        ),
        '<span class="line-numbers">1</span>a\n<span class="line-numbers"><strong class="highlighted">2</strong></span>b\n',
      );
    });
    test('table-empty', () {
      expect(
        highlightRuby('', numberLines: LineNumbersMode.table),
        '<table class="CodeRay"><tr>\n  <td class="line-numbers"><pre>1\n</pre></td>\n  <td class="code"><pre></pre></td>\n</tr></table>\n',
      );
    });
    test('inline-empty', () {
      expect(
        highlightRuby('', numberLines: LineNumbersMode.inline),
        '<span class="line-numbers">1</span>',
      );
    });
    test('inline-multi', () {
      expect(
        highlightRuby("s = 'l1\nl2'\n", numberLines: LineNumbersMode.inline),
        '<span class="line-numbers">1</span>s = <span class="string"><span class="delimiter">\'</span><span class="content">l1</span></span>\n<span class="line-numbers">2</span><span class="string"><span class="content">l2</span><span class="delimiter">\'</span></span>\n',
      );
    });
    test('table-style', () {
      expect(
        highlightRuby(
          'x = 1\n',
          cssMode: CssMode.inline,
          numberLines: LineNumbersMode.table,
          startLineNumber: 3,
          highlightLines: <int>[3],
        ),
        '<table class="CodeRay"><tr>\n  <td class="line-numbers"><pre><strong class="highlighted">3</strong>\n</pre></td>\n  <td class="code"><pre>x = <span style="color:#00D">1</span>\n</pre></td>\n</tr></table>\n',
      );
    });
  });

  group('language dispatch', () {
    test('null language scans as plain text', () {
      expect(highlightRuby('puts 1\n', language: null), 'puts 1\n');
    });
    test('text aliases scan as plain escaped text', () {
      for (final lang in ['text', 'plain', 'plaintext']) {
        expect(
          highlightRuby('a < b & "c"\n', language: lang),
          'a &lt; b &amp; &quot;c&quot;\n',
        );
      }
    });
    test('unknown languages fall back to plain text', () {
      for (final lang in [
        'unknownlang',
        'foo bar',
        'C++',
        'IRB',
        'Irb',
        'JS',
        'Plain',
      ]) {
        expect(highlightRuby('puts 1\n', language: lang), 'puts 1\n');
      }
    });
    test('ruby spellings highlight', () {
      for (final lang in ['ruby', 'Ruby', 'RUBY', 'irb']) {
        expect(
          highlightRuby('puts 1\n', language: lang),
          contains('<span class="integer">1</span>'),
        );
      }
    });
    test('unported scanners stay seam-gated', () {
      for (final lang in [
        'python',
        'java_script',
        'c++',
        'js',
        'debug',
        'raydebug',
        'html',
        'yaml',
        'json',
        'DIFF',
        'PYTHON',
      ]) {
        expect(
          () => highlightRuby('x = 1\n', language: lang),
          throwsA(isA<UnimplementedError>()),
          reason: lang,
        );
      }
    });
    test('scanner stem raises like the oracle PluginNotFound', () {
      expect(
        () => highlightRuby('x = 1\n', language: 'scanner'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('style seam', () {
    test('style members throw (CodeRay never calls them)', () {
      const lexer = CodeRaySourceLexer();
      expect(
        () => lexer.styleAvailable('x'),
        throwsA(isA<UnimplementedError>()),
      );
      expect(() => lexer.baseStyle('x'), throwsA(isA<UnimplementedError>()));
      expect(() => lexer.stylesheet('x'), throwsA(isA<UnimplementedError>()));
    });
    test('name is coderay', () {
      expect(const CodeRaySourceLexer().name, 'coderay');
    });
  });
}
