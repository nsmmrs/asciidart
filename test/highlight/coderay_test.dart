/// Tests for the CodeRay adapter.
library;

import 'dart:io';

import 'package:asciidoctor/src/highlight/coderay.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';
import 'package:asciidoctor/src/stylesheets.dart';
import 'package:test/test.dart';

import 'fake_source_lexer.dart';

/// Backend output for `puts 'hi'\n` in class mode, captured from
/// `CodeRay::Duo[:ruby, :html, ...]` (coderay 1.1.3).
const classOutput =
    'puts <span class="string"><span class="delimiter">\'</span>'
    '<span class="content">hi</span><span class="delimiter">\'</span></span>\n';

/// Backend output for table-numbered `puts 'hi'\n`, captured from coderay
/// 1.1.3. Ruby reports the callout offset for this output as 98.
const tableOutput =
    '<table class="CodeRay"><tr>\n'
    '  <td class="line-numbers"><pre>1\n</pre></td>\n'
    '  <td class="code"><pre>'
    'puts <span class="string"><span class="delimiter">\'</span>'
    '<span class="content">hi</span><span class="delimiter">\'</span></span>\n'
    '</pre></td>\n'
    '</tr></table>\n';

void main() {
  group('canHighlight', () {
    test('is false without a backend', () {
      expect(CodeRayAdapter().canHighlight, isFalse);
    });

    test('is true with a backend', () {
      expect(CodeRayAdapter(lexer: FakeSourceLexer()).canHighlight, isTrue);
    });
  });

  group('highlight', () {
    test('throws UnimplementedError without a backend', () {
      expect(
        () => CodeRayAdapter().highlight(source: 'x', language: 'ruby'),
        throwsUnimplementedError,
      );
    });

    test('returns backend output verbatim', () {
      final lexer = FakeSourceLexer(onHighlight: (_) => classOutput);
      final result = CodeRayAdapter(lexer: lexer)
          .highlight(source: "puts 'hi'\n", language: 'ruby');
      expect(result.html, classOutput);
      expect(result.sourceOffset, isNull);
    });

    test('forwards language, numbering, and emphasis to the backend', () {
      final lexer = FakeSourceLexer(onHighlight: (_) => classOutput);
      CodeRayAdapter(lexer: lexer).highlight(
        source: "puts 'hi'\n",
        language: 'ruby',
        numberLines: LineNumbersMode.inline,
        startLineNumber: 5,
        highlightLines: [2],
      );
      final request = lexer.lastRequest!;
      expect(request.language, 'ruby');
      expect(request.cssMode, CssMode.classes);
      expect(request.numberLines, LineNumbersMode.inline);
      expect(request.startLineNumber, 5);
      expect(request.highlightLines, [2]);
    });

    test('missing language arrives at the backend as text', () {
      final lexer = FakeSourceLexer(onHighlight: (_) => 'x\n');
      CodeRayAdapter(lexer: lexer).highlight(source: 'x\n');
      expect(lexer.lastRequest!.language, 'text');
    });

    test('table numbering with callouts reports the code-cell offset', () {
      final lexer = FakeSourceLexer(onHighlight: (_) => tableOutput);
      final result = CodeRayAdapter(lexer: lexer).highlight(
        source: "puts 'hi'\n",
        language: 'ruby',
        numberLines: LineNumbersMode.table,
        hasCallouts: true,
      );
      expect(result.html, tableOutput);
      expect(result.sourceOffset, 98);
    });

    test('table numbering without callouts reports no offset', () {
      final lexer = FakeSourceLexer(onHighlight: (_) => tableOutput);
      final result = CodeRayAdapter(lexer: lexer).highlight(
        source: "puts 'hi'\n",
        language: 'ruby',
        numberLines: LineNumbersMode.table,
      );
      expect(result.sourceOffset, isNull);
    });

    test('class mode requires the stylesheet, inline mode does not', () {
      final classes = (CodeRayAdapter(
        lexer: FakeSourceLexer(onHighlight: (_) => classOutput),
      ))..highlight(source: 'x', language: 'ruby');
      expect(classes.requiresStylesheet, isTrue);

      final inline = (CodeRayAdapter(
        lexer: FakeSourceLexer(onHighlight: (_) => classOutput),
      ))..highlight(source: 'x', language: 'ruby', cssMode: CssMode.inline);
      expect(inline.requiresStylesheet, isFalse);
    });
  });

  group('format', () {
    test('emits the plain CodeRay envelope', () {
      expect(
        CodeRayAdapter().format(
          content: "puts 'Hello, World!'\nputs 1 + 2",
          language: 'ruby',
        ),
        '<pre class="CodeRay highlight"><code data-lang="ruby">'
        "puts 'Hello, World!'\nputs 1 + 2</code></pre>",
      );
    });
  });

  group('hasDocinfo', () {
    test('is false until class-mode output requires the stylesheet', () {
      final adapter = CodeRayAdapter(
        lexer: FakeSourceLexer(onHighlight: (_) => classOutput),
      );
      expect(adapter.hasDocinfo(DocinfoLocation.head), isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.hasDocinfo(DocinfoLocation.head), isTrue);
      expect(adapter.hasDocinfo(DocinfoLocation.footer), isFalse);
    });
  });

  group('docinfoHead', () {
    test('embeds the CodeRay stylesheet', () {
      final css = CodeRayAdapter().stylesheetData;
      expect(css.length, 3483);
      expect(
        css.startsWith(
          '/*! Stylesheet for CodeRay to loosely match GitHub themes | '
          'MIT License */',
        ),
        isTrue,
      );
      expect(css, Stylesheets.instance.coderayStylesheetData);
      expect(
        CodeRayAdapter().docinfoHead(linkCss: false),
        '<style>\n$css\n</style>',
      );
    });

    test('links the stylesheet when requested', () {
      expect(
        CodeRayAdapter().docinfoHead(
          linkCss: true,
          stylesDir: 'css',
          selfClosingSlash: '/',
        ),
        '<link rel="stylesheet" href="css/coderay-asciidoctor.css"/>',
      );
    });
  });

  group('writeStylesheet', () {
    test('wantsStylesheetFile tracks the stylesheet requirement', () {
      final adapter = CodeRayAdapter(
        lexer: FakeSourceLexer(onHighlight: (_) => classOutput),
      );
      expect(adapter.wantsStylesheetFile, isFalse);
      adapter.highlight(source: 'x', language: 'ruby');
      expect(adapter.wantsStylesheetFile, isTrue);
    });

    test('writes the stylesheet to the target directory', () {
      final dir = Directory.systemTemp.createTempSync('coderay');
      try {
        CodeRayAdapter().writeStylesheet(dir.path);
        expect(
          File('${dir.path}/coderay-asciidoctor.css').readAsStringSync(),
          CodeRayAdapter().stylesheetData,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
