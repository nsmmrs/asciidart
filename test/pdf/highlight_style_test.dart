import 'package:asciidart/src/pdf/highlight_style.dart';
import 'package:test/test.dart';

void main() {
  group('a highlight.js theme', () {
    final style = HighlightStyle.parse(
      'pre code.hljs{display:block}.hljs{color:#24292e;background:#fff}'
      '.hljs-keyword,.hljs-type{color:#d73a49}'
      '.hljs-title.class_{color:#6f42c1;font-weight:700}'
      '.hljs-meta .hljs-keyword{color:navy}'
      '.hljs-comment{color:#6a737d;font-style:italic}'
      '.hljs-string{color:#032f62}.hljs-string{color:#abc}'
      '.hljs{--accent:#C50243}.hljs-number{color:var(--accent)}',
    );

    test('gives tokens their color, weight and style', () {
      expect(style.styleOf({'hljs-keyword'}, const []), (
        color: 'D73A49',
        bold: false,
        italic: false,
      ));
      expect(style.styleOf({'hljs-comment'}, const []).italic, isTrue);
      expect(style.styleOf({'hljs-title', 'class_'}, const []), (
        color: '6F42C1',
        bold: true,
        italic: false,
      ));
      // A compound selector needs all its classes.
      expect(style.styleOf({'hljs-title'}, const []).color, isNull);
    });

    test('lets the more specific rule, then the later, win', () {
      expect(
        style
            .styleOf(
              {'hljs-keyword'},
              [
                {'hljs-meta'},
              ],
            )
            .color,
        '000080',
      );
      expect(style.styleOf({'hljs-string'}, const []).color, 'AABBCC');
    });

    test('reads custom properties and the base color', () {
      expect(style.styleOf({'hljs-number'}, const []).color, 'C50243');
      expect(style.base.color, '24292E');
    });

    test("turns hilite's spans into markup, nested", () {
      expect(
        style.markup(
          '<span class="hljs-meta">@x <span class="hljs-keyword">def</span>'
          '</span> <span class="hljs-title class_">A</span>'
          '<span class="conum">1</span>',
        ),
        '@x <font color="#000080">def</font> '
        '<font color="#6F42C1"><strong>A</strong></font>'
        '<span class="conum">1</span>',
      );
    });
  });

  test('every theme of highlight.js reads', () {
    for (final name in ['github', 'monokai', 'cybertopia-icecap', 'default']) {
      final style = HighlightStyle.named(name)!;
      // Keywords are styled (in color, or in bold).
      expect(
        style.styleOf({'hljs-keyword'}, const []),
        isNot((color: null, bold: false, italic: false)),
        reason: name,
      );
    }
    // An unknown name: GitHub's.
    expect(
      HighlightStyle.named('nope')!.styleOf({'hljs-keyword'}, const []).color,
      'D73A49',
    );
  });
}
