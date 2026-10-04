/// Tests for the Pygments adapter.
library;

import 'dart:io';

import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/highlight/pygments.dart';
import 'package:test/test.dart';

import 'fake_source_lexer.dart';

/// Raw backend output for `puts 'hi'\n`, captured from pygments.rb 5.0.0.
const rawPlain =
    '<div class="lineno"><pre><span></span>'
    '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
    '<span class="tok-s1">&#39;hi&#39;</span>\n'
    '</pre></div>';

/// The wrapper-stripped form of [rawPlain].
const strippedPlain =
    '<span></span>'
    '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
    '<span class="tok-s1">&#39;hi&#39;</span>\n';

/// Raw backend output for inline-numbered `puts 'hi'\nputs 'yo'\n` starting
/// at 5, captured from pygments.rb 5.0.0. Modern Pygments emits `linenos`
/// spans directly.
const rawInlineNums =
    '<div class="lineno"><pre><span></span>'
    '<span class="linenos">5</span>'
    '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
    '<span class="tok-s1">&#39;hi&#39;</span>\n'
    '<span class="linenos">6</span>'
    '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
    '<span class="tok-s1">&#39;yo&#39;</span>\n'
    '</pre></div>';

/// Raw backend output for table-numbered `puts 'hi'\n`, captured from
/// pygments.rb 5.0.0. The adapter passes modern table output through
/// untouched; Ruby reports the callout offset for this output as 162.
const rawTable =
    '<div class="lineno"><table class="linenotable"><tr>'
    '<td class="linenos"><div class="linenodiv"><pre>'
    '<span class="normal">1</span></pre></div></td>'
    '<td class="code"><div><pre><span></span>'
    '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
    '<span class="tok-s1">&#39;hi&#39;</span>\n'
    '</pre></div></td></tr></table></div>';

/// Raw backend output for noclasses inline-numbered `puts 'hi'\n`,
/// captured from pygments.rb 5.0.0.
const rawInlineNumsNoclasses =
    '<div class="lineno"><pre style="line-height: 125%;"><span></span>'
    '<span style="color: inherit; background-color: transparent; '
    'padding-left: 5px; padding-right: 5px;">5</span>'
    '<span style="color: #008000">puts</span>'
    '<span style="color: #BBB"> </span>'
    '<span style="color: #BA2121">&#39;hi&#39;</span>\n'
    '</pre></div>';

/// Backend style facts captured from pygments.rb 5.0.0.
const defaultBaseStyle = 'background: #f8f8f8;';
const monokaiBaseStyle = 'background: #272822; color: #F8F8F2';

FakeSourceLexer backend({
  String? Function(HighlightRequest request)? onHighlight,
  bool Function(String style)? onStyleAvailable,
  String? Function(String style)? onBaseStyle,
  String? Function(String style)? onStylesheet,
}) => FakeSourceLexer(
  name: 'pygments',
  onHighlight: onHighlight,
  onStyleAvailable: onStyleAvailable ?? ((style) => style != 'nosuchstylezzz'),
  onBaseStyle:
      onBaseStyle ??
      ((style) => switch (style) {
        'default' => defaultBaseStyle,
        'monokai' => monokaiBaseStyle,
        _ => null,
      }),
  onStylesheet: onStylesheet,
);

void main() {
  group('canHighlight', () {
    test('is false without a backend', () {
      expect(PygmentsAdapter().canHighlight, isFalse);
    });

    test('is true with a backend', () {
      expect(PygmentsAdapter(lexer: backend()).canHighlight, isTrue);
    });
  });

  group('highlight', () {
    test('throws UnimplementedError without a backend', () {
      expect(
        () => PygmentsAdapter().highlight(source: 'x', language: 'ruby'),
        throwsUnimplementedError,
      );
    });

    test('strips the wrapper envelope', () {
      final result = PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      ).highlight(source: "puts 'hi'\n", language: 'ruby');
      expect(result.html, strippedPlain);
      expect(result.sourceOffset, isNull);
    });

    test('strips a styled wrapper envelope', () {
      const raw =
          '<div class="lineno"><pre style="line-height: 125%;">BODY</pre></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(source: 'x', language: 'ruby', cssMode: CssMode.inline);
      expect(result.html, 'BODY');
    });

    test('modern inline numbers survive the strip untouched', () {
      final result =
          PygmentsAdapter(lexer: backend(onHighlight: (_) => rawInlineNums))
              .highlight(
                source: "puts 'hi'\nputs 'yo'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.inline,
                startLineNumber: 5,
              );
      expect(
        result.html,
        '<span></span>'
        '<span class="linenos">5</span>'
        '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
        '<span class="tok-s1">&#39;hi&#39;</span>\n'
        '<span class="linenos">6</span>'
        '<span class="tok-nb">puts</span><span class="tok-w"> </span>'
        '<span class="tok-s1">&#39;yo&#39;</span>\n',
      );
    });

    test('legacy inline lineno spans are normalized to linenos', () {
      const raw =
          '<div class="lineno"><pre><span></span>'
          '<span class="lineno"> 5 </span>X\n'
          '</pre></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: 'x',
            language: 'ruby',
            numberLines: LineNumbersMode.inline,
          );
      expect(result.html, '<span></span><span class="linenos"> 5</span>X\n');
    });

    test('styled inline lineno spans are normalized to linenos', () {
      final result =
          PygmentsAdapter(
            lexer: backend(onHighlight: (_) => rawInlineNumsNoclasses),
          ).highlight(
            source: "puts 'hi'\n",
            language: 'ruby',
            cssMode: CssMode.inline,
            numberLines: LineNumbersMode.inline,
            startLineNumber: 5,
          );
      expect(
        result.html,
        '<span></span><span class="linenos">5</span>'
        '<span style="color: #008000">puts</span>'
        '<span style="color: #BBB"> </span>'
        '<span style="color: #BA2121">&#39;hi&#39;</span>\n',
      );
    });

    test('styled spans elsewhere are left alone', () {
      const raw =
          '<div class="lineno"><pre><span></span>'
          '<span class="tok-x">a</span><span style="color: x">5</span>'
          '</pre></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: 'x',
            language: 'ruby',
            cssMode: CssMode.inline,
            numberLines: LineNumbersMode.inline,
          );
      expect(
        result.html,
        '<span></span>'
        '<span class="tok-x">a</span><span style="color: x">5</span>',
      );
    });

    test('modern table output passes through untouched', () {
      final result =
          PygmentsAdapter(lexer: backend(onHighlight: (_) => rawTable))
              .highlight(
                source: "puts 'hi'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.table,
              );
      expect(result.html, rawTable);
      expect(result.sourceOffset, isNull);
    });

    test('table output with callouts reports the code-cell offset', () {
      final result =
          PygmentsAdapter(lexer: backend(onHighlight: (_) => rawTable))
              .highlight(
                source: "puts 'hi'\n",
                language: 'ruby',
                numberLines: LineNumbersMode.table,
                hasCallouts: true,
              );
      expect(result.html, rawTable);
      expect(result.sourceOffset, 162);
    });

    test('legacy table wrapper is reduced to a bare pre envelope', () {
      const raw = '<div class="lineno"><pre>TABLE</pre></div>\n';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: 'x',
            language: 'ruby',
            numberLines: LineNumbersMode.table,
          );
      expect(result.html, '<pre>TABLE</pre>');
    });

    test('styled table columns are normalized in noclasses mode', () {
      const raw =
          '<div class="lineno"><table><tr>'
          '<td><div class="linenodiv" style="a: b;">'
          '<pre style="c: d;">1</pre></div></td>'
          '<td class="code">X</td></tr></table></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: 'x',
            language: 'ruby',
            cssMode: CssMode.inline,
            numberLines: LineNumbersMode.table,
          );
      expect(
        result.html,
        '<div class="lineno"><table><tr>'
        '<td class="linenos"><div class="linenodiv"><pre>'
        '1</pre></div></td>'
        '<td class="code">X</td></tr></table></div>',
      );
    });

    test('null start line takes the non-table path', () {
      const raw = '<div class="lineno"><pre>TABLE</pre></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: 'x',
            language: 'ruby',
            numberLines: LineNumbersMode.table,
            startLineNumber: null,
          );
      expect(result.html, 'TABLE');
    });

    test('emphasized lines flow through the strip', () {
      const raw =
          '<div class="lineno"><pre><span></span>'
          '<span class="tok-nb">puts</span>'
          '<span class="tok-w"> </span>'
          '<span class="tok-s1">&#39;a&#39;</span>\n'
          '<span class="hll">'
          '<span class="tok-nb">puts</span>'
          '<span class="tok-w"> </span>'
          '<span class="tok-s1">&#39;b&#39;</span>\n'
          '</span></pre></div>';
      final result = PygmentsAdapter(lexer: backend(onHighlight: (_) => raw))
          .highlight(
            source: "puts 'a'\nputs 'b'\n",
            language: 'ruby',
            highlightLines: [2],
          );
      expect(
        result.html,
        '<span></span>'
        '<span class="tok-nb">puts</span>'
        '<span class="tok-w"> </span>'
        '<span class="tok-s1">&#39;a&#39;</span>\n'
        '<span class="hll">'
        '<span class="tok-nb">puts</span>'
        '<span class="tok-w"> </span>'
        '<span class="tok-s1">&#39;b&#39;</span>\n'
        '</span>',
      );
    });

    test('backend failure falls back to escaped source', () {
      final lexer = backend(onHighlight: (_) => null);
      final table = PygmentsAdapter(lexer: lexer)
          .highlight(source: 'x < 1\n', numberLines: LineNumbersMode.table);
      expect(table.html, 'x &lt; 1\n');
      final plain = PygmentsAdapter(lexer: lexer).highlight(source: 'x < 1\n');
      expect(plain.html, 'x &lt; 1\n');
    });

    test('resolved style, emphasis, and mixed flag reach the backend', () {
      final lexer = backend(onHighlight: (_) => rawPlain);
      PygmentsAdapter(lexer: lexer).highlight(
        source: 'x',
        language: 'php',
        highlightLines: [1, 3],
        style: 'monokai',
        mixed: true,
      );
      final request = lexer.lastRequest!;
      expect(request.language, 'php');
      expect(request.style, 'monokai');
      expect(request.highlightLines, [1, 3]);
      expect(request.mixed, isTrue);
    });

    test('class mode requires the stylesheet, inline mode does not', () {
      final classes = (PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      ))..highlight(source: 'x', language: 'ruby');
      expect(classes.requiresStylesheet, isTrue);

      final inline = (PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      ))..highlight(source: 'x', language: 'ruby', cssMode: CssMode.inline);
      expect(inline.requiresStylesheet, isFalse);
    });

    test('highlight memoizes the first resolved style', () {
      final adapter =
          (PygmentsAdapter(lexer: backend(onHighlight: (_) => rawPlain)))
            ..highlight(source: 'x', language: 'ruby', style: 'monokai')
            ..highlight(source: 'x', language: 'ruby', style: 'default');
      expect(adapter.currentStyle, 'monokai');
    });
  });

  group('format', () {
    test('class mode emits the plain envelope', () {
      expect(
        PygmentsAdapter(
          lexer: backend(),
        ).format(content: "puts 'Hello, World!'\nputs 1 + 2", language: 'ruby'),
        '<pre class="pygments highlight"><code data-lang="ruby">'
        "puts 'Hello, World!'\nputs 1 + 2</code></pre>",
      );
    });

    test('inline mode attaches the default base style', () {
      final adapter = PygmentsAdapter(lexer: backend());
      expect(
        adapter.format(content: 'x', language: 'ruby', cssMode: CssMode.inline),
        '<pre class="pygments highlight" style="background: #f8f8f8;">'
        '<code data-lang="ruby">x</code></pre>',
      );
      expect(adapter.currentStyle, 'default');
    });

    test('inline mode honors a custom style', () {
      expect(
        PygmentsAdapter(lexer: backend()).format(
          content: 'x',
          language: 'ruby',
          cssMode: CssMode.inline,
          style: 'monokai',
        ),
        '<pre class="pygments highlight" '
        'style="background: #272822; color: #F8F8F2">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('inline mode falls back to the default style', () {
      expect(
        PygmentsAdapter(lexer: backend()).format(
          content: 'x',
          language: 'ruby',
          cssMode: CssMode.inline,
          style: 'nosuchstylezzz',
        ),
        '<pre class="pygments highlight" style="background: #f8f8f8;">'
        '<code data-lang="ruby">x</code></pre>',
      );
    });

    test('inline mode without a backend emits no style attribute', () {
      expect(
        PygmentsAdapter().format(
          content: 'x',
          language: 'ruby',
          cssMode: CssMode.inline,
        ),
        '<pre class="pygments highlight"><code data-lang="ruby">x</code></pre>',
      );
    });
  });

  group('hasDocinfo', () {
    test('is head-only once class-mode output requires the stylesheet', () {
      final adapter = PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      );
      expect(adapter.hasDocinfo(DocinfoLocation.head), isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.hasDocinfo(DocinfoLocation.head), isTrue);
      expect(adapter.hasDocinfo(DocinfoLocation.footer), isFalse);
    });
  });

  group('styles', () {
    test('stylesheetBasename defaults to the default style', () {
      expect(
        PygmentsAdapter().stylesheetBasename(null),
        'pygments-default.css',
      );
      expect(
        PygmentsAdapter().stylesheetBasename('monokai'),
        'pygments-monokai.css',
      );
    });

    test('readStylesheet falls back without a backend', () {
      expect(
        PygmentsAdapter().readStylesheet(null),
        '/* Pygments CSS disabled because Pygments is not available. */',
      );
    });

    test('readStylesheet reports backend CSS failures', () {
      final adapter = PygmentsAdapter(
        lexer: backend(onStylesheet: (_) => null),
      );
      expect(
        adapter.readStylesheet('default'),
        '/* Failed to load Pygments CSS. */',
      );
    });

    test('readStylesheet serves backend CSS', () {
      final adapter = PygmentsAdapter(
        lexer: backend(onStylesheet: (style) => 'css-for-$style'),
      );
      expect(adapter.readStylesheet('monokai'), 'css-for-monokai');
    });

    test('docinfoHead links the resolved stylesheet', () {
      final adapter = (PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      ))..highlight(source: 'x', language: 'ruby');
      expect(
        adapter.docinfoHead(
          linkCss: true,
          stylesDir: 'css',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="css/pygments-default.css"/>',
      );
    });

    test('wantsStylesheetFile tracks the stylesheet requirement', () {
      final adapter = PygmentsAdapter(
        lexer: backend(onHighlight: (_) => rawPlain),
      );
      expect(adapter.wantsStylesheetFile, isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.wantsStylesheetFile, isTrue);
    });

    test('writeStylesheet writes the resolved stylesheet', () {
      final dir = Directory.systemTemp.createTempSync('pygments');
      try {
        PygmentsAdapter(lexer: backend(onStylesheet: (_) => 'CSS'))
            .writeStylesheet(dir.path);
        expect(
          File('${dir.path}/pygments-default.css').readAsStringSync(),
          'CSS',
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
