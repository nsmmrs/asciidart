/// Tests for the Rouge adapter.
library;

import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

import 'fake_source_lexer.dart';

/// Delegate-formatted inner HTML for `puts 'hi'\nputs 'yo'\n`, captured from
/// `Rouge::Formatters::HTML` (rouge 3.30.0).
const twoLineInner =
    '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n'
    '<span class="nb">puts</span> <span class="s1">\'yo\'</span>\n';

/// Backend theme facts captured from rouge 3.30.0.
const githubBaseStyle = 'background-color: #f8f8f8';
const monokaiBaseStyle = 'color: #f8f8f2;background-color: #49483e';

FakeSourceLexer backend({
  String? Function(HighlightRequest request)? onHighlight,
  bool Function(String style)? onStyleAvailable,
  String? Function(String style)? onBaseStyle,
  String? Function(String style)? onStylesheet,
}) => FakeSourceLexer(
  name: 'rouge',
  onHighlight: onHighlight,
  onStyleAvailable: onStyleAvailable ?? ((style) => style != 'nosuchstylezzz'),
  onBaseStyle:
      onBaseStyle ??
      ((style) => switch (style) {
        'github' => githubBaseStyle,
        'monokai' => monokaiBaseStyle,
        _ => null,
      }),
  onStylesheet: onStylesheet,
);

void main() {
  group('canHighlight', () {
    test('is false without a backend', () {
      expect(RougeAdapter().canHighlight, isFalse);
    });

    test('is true with a backend', () {
      expect(RougeAdapter(lexer: backend()).canHighlight, isTrue);
    });
  });

  group('highlight', () {
    test('throws UnimplementedError without a backend', () {
      expect(
        () => RougeAdapter().highlight(source: 'x', language: 'ruby'),
        throwsUnimplementedError,
      );
    });

    test('plain output returns backend HTML verbatim', () {
      const inner =
          '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n';
      final result = RougeAdapter(lexer: backend(onHighlight: (_) => inner))
          .highlight(source: "puts 'hi'\n", language: 'ruby');
      expect(result.html, inner);
      expect(result.sourceOffset, isNull);
    });

    test('inline-css output returns backend HTML verbatim', () {
      const inner =
          '<span style="color: #0086B3">puts</span> '
          '<span style="color: #d14">\'hi\'</span>\n';
      final result = RougeAdapter(lexer: backend(onHighlight: (_) => inner))
          .highlight(
            source: "puts 'hi'\n",
            language: 'ruby',
            cssMode: CssMode.inline,
          );
      expect(result.html, inner);
    });

    test('table numbering lays out the linenotable', () {
      final result =
          RougeAdapter(lexer: backend(onHighlight: (_) => twoLineInner))
              .highlight(
                source: "puts 'hi'\nputs 'yo'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.table,
              );
      expect(
        result.html,
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n2\n</pre></td><td class="code"><pre>'
        '$twoLineInner'
        '</pre></td></tr></tbody></table>',
      );
      expect(result.sourceOffset, isNull);
    });

    test('single-line table reports the code cell offset for callouts', () {
      const inner =
          '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n';
      final result = RougeAdapter(lexer: backend(onHighlight: (_) => inner))
          .highlight(
            source: "puts 'hi'\n",
            language: 'ruby',
            numberLines: LineNumbersMode.table,
            hasCallouts: true,
          );
      expect(
        result.html,
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n</pre></td><td class="code"><pre>'
        '$inner'
        '</pre></td></tr></tbody></table>',
      );
      expect(result.sourceOffset, 111);
    });

    test('inline numbering mode also uses the table layout', () {
      // 2.0.26 has no inline Rouge numberer (rouge-linenums-mode=inline came
      // with asciidoctor#3641); any mode lays out the linenotable.
      final result =
          RougeAdapter(lexer: backend(onHighlight: (_) => twoLineInner))
              .highlight(
                source: "puts 'hi'\nputs 'yo'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.inline,
                startLineNumber: 5,
                hasCallouts: true,
              );
      expect(
        result.html,
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">5\n6\n</pre></td><td class="code"><pre>'
        '$twoLineInner'
        '</pre></td></tr></tbody></table>',
      );
      expect(result.sourceOffset, isNotNull);
    });

    test('emphasized lines gain an hll span holding the newline', () {
      const inner =
          '<span class="nb">puts</span> <span class="s1">\'a\'</span>\n'
          '<span class="nb">puts</span> <span class="s1">\'b\'</span>\n';
      final result = RougeAdapter(lexer: backend(onHighlight: (_) => inner))
          .highlight(
            source: "puts 'a'\nputs 'b'\n",
            language: 'ruby',
            highlightLines: [2],
          );
      expect(
        result.html,
        '<span class="nb">puts</span> <span class="s1">\'a\'</span>\n'
        '<span class="hll">'
        '<span class="nb">puts</span> <span class="s1">\'b\'</span>\n'
        '</span>',
      );
    });

    test('numbering wraps outside emphasis', () {
      const inner =
          '<span class="nb">puts</span> <span class="s1">\'a\'</span>\n'
          '<span class="nb">puts</span> <span class="s1">\'b\'</span>\n';
      final result = RougeAdapter(lexer: backend(onHighlight: (_) => inner))
          .highlight(
            source: "puts 'a'\nputs 'b'\n",
            language: 'ruby',
            numberLines: LineNumbersMode.table,
            highlightLines: [2],
          );
      expect(
        result.html,
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n2\n</pre></td><td class="code"><pre>'
        '<span class="nb">puts</span> <span class="s1">\'a\'</span>\n'
        '<span class="hll">'
        '<span class="nb">puts</span> <span class="s1">\'b\'</span>\n'
        '</span>'
        '</pre></td></tr></tbody></table>',
      );
    });

    test('language and mixed flag pass through to the backend', () {
      final lexer = backend(onHighlight: (_) => 'x\n');
      RougeAdapter(lexer: lexer)
          .highlight(source: 'x', language: 'notalangzzz', mixed: true);
      expect(lexer.lastRequest!.language, 'notalangzzz');
      expect(lexer.lastRequest!.mixed, isTrue);
    });

    test('class mode requires the stylesheet, inline mode does not', () {
      final classes = (RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n')))
        ..highlight(source: 'x', language: 'ruby');
      expect(classes.requiresStylesheet, isTrue);

      final inline = (RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n')))
        ..highlight(source: 'x', language: 'ruby', cssMode: CssMode.inline);
      expect(inline.requiresStylesheet, isFalse);
    });

    test('highlight resolves and records the style', () {
      final adapter = (RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n')))
        ..highlight(source: 'x', language: 'ruby', style: 'monokai');
      expect(adapter.currentStyle, 'monokai');
    });

    test('unknown style falls back to the default', () {
      final adapter = (RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n')))
        ..highlight(source: 'x', language: 'ruby', style: 'nosuchstylezzz');
      expect(adapter.currentStyle, 'github');
    });
  });

  group('line pipeline', () {
    test('splitHtmlLines treats a trailing newline as a terminator', () {
      expect(splitHtmlLines('a\nb\n'), ['a', 'b']);
      expect(splitHtmlLines('a\nb'), ['a', 'b']);
      expect(splitHtmlLines(''), isEmpty);
    });

    test('table numbering right-justifies to the last number width', () {
      // Expected values generated with Ruby's 2.0.26
      // RougeExt::Formatters::HTMLTable.
      expect(
        numberHtmlAsTable('a\nb', startLine: 9),
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno"> 9\n10\n</pre></td>'
        '<td class="code"><pre>a\nb\n</pre></td></tr></tbody></table>',
      );
    });

    test('table numbering keeps a terminated last line', () {
      expect(
        numberHtmlAsTable('a\nb\n'),
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n2\n</pre></td>'
        '<td class="code"><pre>a\nb\n</pre></td></tr></tbody></table>',
      );
    });

    test('table numbering accepts a hanging emphasized last line', () {
      expect(
        numberHtmlAsTable(
          highlightHtmlLines(splitHtmlLines('a\nb'), [2]).join(),
        ),
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n2\n</pre></td>'
        '<td class="code"><pre>a\n<span class="hll">b\n</span></pre></td>'
        '</tr></tbody></table>',
      );
    });

    test('empty input numbers a single line', () {
      expect(highlightHtmlLines(splitHtmlLines('')), isEmpty);
      expect(
        numberHtmlAsTable(''),
        '<table class="linenotable"><tbody><tr><td class="linenos gl">'
        '<pre class="lineno">1\n</pre></td>'
        '<td class="code"><pre>\n</pre></td></tr></tbody></table>',
      );
    });
  });

  group('format', () {
    test('class mode emits the plain envelope', () {
      expect(
        RougeAdapter(
          lexer: backend(),
        ).format(content: "puts 'Hello, World!'\nputs 1 + 2", language: 'ruby'),
        '<pre class="rouge highlight"><code data-lang="ruby">'
        "puts 'Hello, World!'\nputs 1 + 2</code></pre>",
      );
    });

    test('inline mode attaches the theme base style', () {
      final adapter = RougeAdapter(lexer: backend());
      expect(
        adapter.format(content: 'x', language: 'ruby', cssMode: CssMode.inline),
        '<pre class="rouge highlight" '
        'style="background-color: #f8f8f8">'
        '<code data-lang="ruby">x</code></pre>',
      );
      expect(adapter.currentStyle, 'github');
    });

    test('inline mode honors a custom style', () {
      expect(
        RougeAdapter(lexer: backend()).format(
          content: 'x',
          language: 'ruby',
          cssMode: CssMode.inline,
          style: 'monokai',
        ),
        '<pre class="rouge highlight" '
        'style="color: #f8f8f2;background-color: #49483e">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('inline mode without a backend emits no style attribute', () {
      expect(
        RougeAdapter().format(
          content: 'x',
          language: 'ruby',
          cssMode: CssMode.inline,
        ),
        '<pre class="rouge highlight"><code data-lang="ruby">x</code></pre>',
      );
    });

    test('language query options are stripped from data-lang', () {
      expect(
        RougeAdapter(lexer: backend())
            .format(content: 'x', language: 'ruby?foo=bar'),
        '<pre class="rouge highlight"><code data-lang="ruby">x</code></pre>',
      );
    });

    test('missing language omits data-lang', () {
      expect(
        RougeAdapter(lexer: backend())
            .format(content: 'x', cssMode: CssMode.inline),
        '<pre class="rouge highlight" '
        'style="background-color: #f8f8f8"><code>x</code></pre>',
      );
    });
  });

  group('hasDocinfo', () {
    test('is head-only once class-mode output requires the stylesheet', () {
      final adapter = RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n'));
      expect(adapter.hasDocinfo(DocinfoLocation.head), isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.hasDocinfo(DocinfoLocation.head), isTrue);
      expect(adapter.hasDocinfo(DocinfoLocation.footer), isFalse);
    });
  });

  group('styles', () {
    test('stylesheetBasename defaults to the github theme', () {
      expect(RougeAdapter().stylesheetBasename(null), 'rouge-github.css');
      expect(RougeAdapter().stylesheetBasename('monokai'), 'rouge-monokai.css');
    });

    test('readStylesheet falls back without a backend', () {
      expect(
        RougeAdapter().readStylesheet(null),
        '/* Rouge CSS disabled because Rouge is not available. */',
      );
    });

    test('readStylesheet serves backend CSS', () {
      final adapter = RougeAdapter(
        lexer: backend(onStylesheet: (style) => 'css-for-$style'),
      );
      expect(adapter.readStylesheet('monokai'), 'css-for-monokai');
    });

    test('docinfoHead embeds backend CSS', () {
      final adapter = RougeAdapter(lexer: backend(onStylesheet: (_) => 'CSS'));
      expect(adapter.docinfoHead(linkCss: false), '<style>\nCSS\n</style>');
    });

    test('docinfoHead links the resolved stylesheet', () {
      final adapter = (RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n')))
        ..highlight(source: 'x', language: 'ruby');
      expect(
        adapter.docinfoHead(
          linkCss: true,
          stylesDir: 'css',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="css/rouge-github.css"/>',
      );
    });

    test('wantsStylesheetFile tracks the stylesheet requirement', () {
      final adapter = RougeAdapter(lexer: backend(onHighlight: (_) => 'x\n'));
      expect(adapter.wantsStylesheetFile, isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.wantsStylesheetFile, isTrue);
    });

    test('writeStylesheet writes the resolved stylesheet', () {
      final dir = Directory.systemTemp.createTempSync('rouge');
      try {
        RougeAdapter(lexer: backend(onStylesheet: (_) => 'CSS'))
            .writeStylesheet(dir.path);
        expect(File('${dir.path}/rouge-github.css').readAsStringSync(), 'CSS');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
