/// Tests for the Rouge adapter.
library;

import 'dart:io';

import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/highlight/rouge.dart';
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
        '<table class="linenotable"><tbody>'
        '<tr><td class="linenos"><pre>1</pre></td><td class="code"><pre>'
        '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n'
        '</pre></td></tr>'
        '<tr><td class="linenos"><pre>2</pre></td><td class="code"><pre>'
        '<span class="nb">puts</span> <span class="s1">\'yo\'</span>\n'
        '</pre></td></tr>'
        '</tbody></table>',
      );
      expect(result.sourceOffset, isNull);
    });

    test('single-line table is unclosed like the Ruby formatter', () {
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
        '<table class="linenotable"><tbody>'
        '<tr><td class="linenos"><pre>1</pre></td><td class="code"><pre>'
        '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n'
        '</pre></td></tr>',
      );
      expect(result.sourceOffset, 92);
    });

    test('inline numbering prepends linenos spans', () {
      final result =
          RougeAdapter(lexer: backend(onHighlight: (_) => twoLineInner))
              .highlight(
                source: "puts 'hi'\nputs 'yo'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.inline,
                startLineNumber: 5,
              );
      expect(
        result.html,
        '<span class="linenos">5</span>'
        '<span class="nb">puts</span> <span class="s1">\'hi\'</span>\n'
        '<span class="linenos">6</span>'
        '<span class="nb">puts</span> <span class="s1">\'yo\'</span>\n',
      );
    });

    test('inline numbering with callouts reports no offset', () {
      final result =
          RougeAdapter(lexer: backend(onHighlight: (_) => twoLineInner))
              .highlight(
                source: "puts 'hi'\nputs 'yo'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.inline,
                hasCallouts: true,
              );
      expect(result.sourceOffset, isNull);
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
            numberLines: LineNumbersMode.inline,
            highlightLines: [2],
          );
      expect(
        result.html,
        '<span class="linenos">1</span>'
        '<span class="nb">puts</span> <span class="s1">\'a\'</span>\n'
        '<span class="linenos">2</span>'
        '<span class="hll">'
        '<span class="nb">puts</span> <span class="s1">\'b\'</span>\n'
        '</span>',
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

    test('inline numbering right-justifies to the last number width', () {
      expect(
        numberHtmlLinesInline(['a\n', 'b\n'], startLine: 9),
        '<span class="linenos"> 9</span>a\n'
        '<span class="linenos">10</span>b\n',
      );
    });

    test('numbering terminates an unterminated last line', () {
      expect(
        numberHtmlLinesInline(highlightHtmlLines(splitHtmlLines('a\nb'))),
        '<span class="linenos">1</span>a\n'
        '<span class="linenos">2</span>b\n',
      );
    });

    test('empty input decorates to empty output', () {
      expect(highlightHtmlLines(splitHtmlLines('')), isEmpty);
      expect(numberHtmlLinesInline([]), '');
      expect(numberHtmlLinesAsTable([]), '');
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
