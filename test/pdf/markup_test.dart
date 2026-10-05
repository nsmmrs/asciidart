// The inline markup of the PDF backend: parsing and transforming into
// fragments, as asciidoctor-pdf 2.3.27's FormattedText does.
@TestOn('vm')
library;

import 'package:asciidart/src/pdf/markup.dart';
import 'package:asciidart/src/pdf/theme.dart';
import 'package:test/test.dart';

List<Fragment> format(String text, [Theme? theme]) =>
    MarkupTransform(theme).apply(parseMarkup(text)!);

void main() {
  group('parse', () {
    test('text, elements, void elements and character references', () {
      final nodes = parseMarkup(
        'a <strong>b <em>c</em></strong>&amp;<br>d<img src="x.png" alt="x"/>',
      )!;
      expect(nodes.length, 6);
      expect(nodes[1], isA<MarkupElement>());
      final strong = nodes[1] as MarkupElement;
      expect(strong.name, 'strong');
      expect(strong.content!.length, 2);
      expect((nodes[2] as MarkupCharRef).text, '&');
      expect((nodes[3] as MarkupElement).content, isNull);
      expect((nodes[5] as MarkupElement).attributes, {
        'src': 'x.png',
        'alt': 'x',
      });
    });

    test('character references by name, decimal and hex', () {
      expect(
        [
          for (final n in parseMarkup('&lt;&#160;&#x2014;&nbsp;')!)
            (n as MarkupCharRef).text,
        ],
        ['<', ' ', '—', ' '],
      );
    });

    test('anything else fails the whole string', () {
      expect(parseMarkup('a < b'), isNull);
      expect(parseMarkup('a & b'), isNull);
      expect(parseMarkup('<strong>unclosed'), isNull);
      expect(parseMarkup('<div>x</div>'), isNull);
      expect(parseMarkup("<a href='x'>y</a>"), isNull);
      // End tags aren't matched against start tags.
      expect(parseMarkup('<strong>x</em>'), isNotNull);
    });
  });

  group('transform', () {
    test('styles nest and adjacent text merges', () {
      final fragments = format('a <strong>b <em>c</em></strong> d&amp;e');
      expect([for (final f in fragments) f.text], ['a ', 'b ', 'c', ' d&e']);
      expect(fragments[1].styles, {FragmentStyle.bold});
      expect(fragments[2].styles, {FragmentStyle.bold, FragmentStyle.italic});
      expect(fragments[3].styles, isNull);
    });

    test('built-in settings without a theme', () {
      final [code, link, mark] = format(
        '<code>x</code><a href="https://example.org">y</a><mark>z</mark>',
      );
      expect(code.font, 'Courier');
      expect(link.link, 'https://example.org');
      expect(link.color, const HexColor('0000FF'));
      expect(mark.backgroundColor, const HexColor('FFFF00'));
      expect(mark.callbacks, [FragmentCallback.textBackgroundAndBorder]);
    });

    test('font, span, sub, sup and del', () {
      final fragments = format(
        '<font size="1.2em" color="#f00">a</font>'
        '<font size="9" name="Serif" color="[0, 100, 100, 0]">b</font>'
        '<span style="font-weight: bold; color: #00ff00">c</span>'
        '<sub>d</sub><sup>e</sup><del>f</del>',
      );
      expect(fragments[0].size, '1.2em');
      expect(fragments[0].color, const HexColor('ff0000'));
      expect(fragments[1].size, '9.0');
      expect(fragments[1].font, 'Serif');
      expect(fragments[1].color, const CmykThemeColor([0, 100, 100, 0]));
      expect(fragments[2].styles, {FragmentStyle.bold});
      expect(fragments[2].color, const HexColor('00ff00'));
      expect(fragments[3].styles, {FragmentStyle.subscript});
      expect(fragments[4].styles, {FragmentStyle.superscript});
      expect(fragments[5].styles, {FragmentStyle.strikethrough});
    });

    test('anchors, destinations and empty elements', () {
      final fragments = format(
        'see <a anchor="sec">here</a> <a id="mark"></a>and '
        '<a id="term" type="indexterm">t</a>',
      );
      expect(fragments[1].anchor, 'sec');
      expect(fragments.any((f) => f.name == 'term' && f.isMarker), isTrue);
      // An empty element, and an invisible index term, drop the space
      // before them.
      expect(fragments[2].text, 'and');
    });

    test('a <br> is a line feed', () {
      expect([for (final f in format('a<br>b')) f.text], ['a\nb']);
    });

    test('theme settings: codespan, links, roles, big and small', () {
      final theme = ThemeLoader().loadYaml('''
base:
  font-size: 10
  border-color: CCCCCC
codespan:
  font-family: M+ 1mn
  font-color: B12146
  background-color: F5F5F5
  border-width: 0.5
  border-offset: 2
link:
  font-color: 428BCA
  text-decoration: underline
role:
  red:
    font-color: FF0000
    font-style: bold
  plain:
    font-style: normal
''');
      final [code, link, red, plain, big] = format(
        '<code>c</code><a href="x">l</a><span class="red">r</span>'
        '<strong><span class="plain">p</span></strong>'
        '<span class="big">b</span>',
        theme,
      );
      expect(code.font, 'M+ 1mn');
      expect(code.color, const HexColor('B12146'));
      expect(code.borderColor, const HexColor('CCCCCC'));
      expect(code.align, 'center');
      expect(code.callbacks, [
        FragmentCallback.textBackgroundAndBorder,
        FragmentCallback.inlineTextAligner,
      ]);
      expect(link.styles, {FragmentStyle.underline});
      expect(red.color, const HexColor('FF0000'));
      expect(red.styles, {FragmentStyle.bold});
      expect(plain.styles, isNull, reason: 'normal clears bold');
      expect(big.size, '1.1667em');
    });

    test('text transforms keep the pieces apart', () {
      final theme = ThemeLoader().loadYaml('''
role:
  loud:
    text-transform: uppercase
''');
      final fragments = format(
        '<span class="loud">ab <em>cd</em></span>',
        theme,
      );
      expect([for (final f in fragments) f.text], ['AB ', 'CD']);
    });
  });
}
