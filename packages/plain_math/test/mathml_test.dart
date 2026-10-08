// The MathML reader against package:xml: every document of the AsciiMath
// corpus and the LaTeX examples, written back by package:xml in other
// encodings (character references, CDATA, comments and processing
// instructions between children, another prefix, single quotes, space in
// tags), reads as the same tree; documents package:xml rejects, the reader
// rejects too, and so it does the few not well-formed ones package:xml
// reads (an unquoted attribute value, text after the root element).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// [node] as text, every field written.
String _dump(MathNode node) => switch (node) {
  MathToken(
    :final kind,
    :final text,
    :final variant,
    :final stretchy,
    :final largeOperator,
    :final movableLimits,
    :final fence,
    :final form,
  ) =>
    '${kind.name}(${jsonEncode(text)} $variant $stretchy $largeOperator '
        '$movableLimits $fence $form)',
  MathRow(:final children) => 'row[${children.map(_dump).join(', ')}]',
  MathStyled(
    :final child,
    :final display,
    :final scriptLevel,
    :final color,
    :final variant,
  ) =>
    'styled($display $scriptLevel $color $variant ${_dump(child)})',
  MathScripts(:final base, :final sub, :final sup) =>
    'scripts(${_dump(base)} ${_maybe(sub)} ${_maybe(sup)})',
  MathUnderOver(
    :final base,
    :final under,
    :final over,
    :final accent,
    :final accentUnder,
  ) =>
    'underover($accent $accentUnder ${_dump(base)} ${_maybe(under)} '
        '${_maybe(over)})',
  MathFraction(:final numerator, :final denominator, :final lineThickness) =>
    'frac($lineThickness ${_dump(numerator)} ${_dump(denominator)})',
  MathRadical(:final radicand, :final index) =>
    'root(${_dump(radicand)} ${_maybe(index)})',
  MathTable(:final rows, :final columnAlign) =>
    'table($columnAlign ${[for (final r in rows) r.map(_dump).join(' | ')]})',
  MathEnclose(:final child, :final notations) =>
    'enclose($notations ${_dump(child)})',
  MathSpace(:final width) => 'space($width)',
};

String _maybe(MathNode? node) => node == null ? '-' : _dump(node);

/// Every character of [text] as a character reference.
String _references(String text) =>
    [for (final rune in text.runes) '&#x${rune.toRadixString(16)};'].join();

/// [document] written back as XML: [references] writes characters as
/// references, [cdata] text as CDATA sections, [noise] adds comments,
/// processing instructions and space in tags, and [prefix] replaces the
/// elements' namespace prefix.
String _write(
  XmlDocument document, {
  bool references = false,
  bool cdata = false,
  bool noise = false,
  String? prefix,
}) {
  final out = StringBuffer();
  if (noise) out.write('<?xml version="1.0"?>\n<!-- before -->\n');
  void write(XmlNode node) {
    switch (node) {
      case XmlElement():
        final name = prefix == null
            ? node.name.qualified
            : '$prefix:${node.name.local}';
        out.write('<$name');
        for (final a in node.attributes) {
          final value = references
              ? _references(a.value)
              : a.value.replaceAll('&', '&amp;').replaceAll("'", '&apos;');
          final equals = noise ? ' = ' : '=';
          out.write(
            "${noise ? '  ' : ' '}${a.name.qualified}$equals"
            "'${value.replaceAll('<', '&lt;')}'",
          );
        }
        if (node.children.isEmpty && noise) {
          out.write(' />');
          return;
        }
        out.write(noise ? ' >' : '>');
        for (final child in node.children) {
          if (noise && child is XmlElement) out.write('<!--c--><?pi x?>');
          write(child);
        }
        out.write(noise ? '</$name\n>' : '</$name>');
      case XmlText():
        if (cdata && !node.value.contains(']]>')) {
          out.write('<![CDATA[${node.value}]]>');
        } else if (references) {
          out.write(_references(node.value));
        } else {
          out.write(
            node.value
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;'),
          );
        }
      case XmlCDATA():
        out.write('<![CDATA[${node.value}]]>');
      default:
        break;
    }
  }

  write(document.rootElement);
  if (noise) out.write('\n<!-- after -->\n');
  return out.toString();
}

/// LaTeX of every construct the converter knows.
const List<String> _latex = [
  'x+12.5',
  r'\alpha \leq \Omega',
  'x_i^{n+1}',
  "f''",
  r'\sum_{i=1}^n i',
  r'\int_0^1 x\,dx',
  r'\lim_{n\to\infty} a_n',
  r'\dfrac12 + \frac{a}{b}',
  r'\binom{n}{k}',
  r'\sqrt[3]{x} + \sqrt{y}',
  r'\left( x \middle| y \right\}',
  r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
  r'\begin{cases} 1 & x > 0 \\ 0 & \text{otherwise} \end{cases}',
  r'\begin{aligned} a &= b \\ &= c \end{aligned}',
  r'\overline{AB} \hat{x} \vec{v} \underbrace{a+b}_{n}',
  r'\mathbf{F} = m\mathbf{a}, \mathbb{R}, \mathcal{L}, \mathrm{d}',
  r'\color{red}{x} \textcolor{blue}{y}',
  r'\boxed{E = mc^2} \cancel{x}',
  r'a \quad b \qquad c \; d \! e',
  r'x < y \text{ and } y > z \& w',
  r'\operatorname{sinc} x \sin x \log_2 n',
  r'\displaystyle\sum_k \textstyle\sum_k \scriptstyle x',
];

void main() {
  final expressions = File('test/fixtures/asciimath/expressions.txt')
      .readAsLinesSync()
      .where((e) => e.isNotEmpty);
  final documents = {
    for (final e in expressions) ...{
      asciimathToMathml(e),
      asciimathToMathml(e, prefix: 'mml:'),
    },
    for (final tex in _latex) ...{
      latexToMathml(tex),
      latexToMathml(tex, display: true),
    },
  };

  test('${documents.length} documents read the same in every encoding', () {
    final problems = <String>[];
    for (final text in documents) {
      final expected = _dump(parseMathML(text));
      final xml = XmlDocument.parse(text);
      final variants = {
        'package:xml': xml.toXmlString(),
        'references': _write(xml, references: true),
        'CDATA': _write(xml, cdata: true),
        'noise': _write(xml, noise: true),
        'prefix': _write(xml, prefix: 'm'),
        'all': _write(xml, references: true, noise: true, prefix: 'x'),
      };
      for (final MapEntry(key: name, value: variant) in variants.entries) {
        final String actual;
        try {
          actual = _dump(parseMathML(variant));
        } on MathMLException catch (e) {
          problems.add('$name: $e\n  $variant');
          continue;
        }
        if (actual != expected) {
          problems.add('$name:\n  $text\n  $variant\n  $expected\n  $actual');
        }
      }
    }
    expect(problems.take(5), isEmpty, reason: '${problems.length} differ');
  });

  test('a doctype, entities and text around elements', () {
    expect(
      _dump(
        parseMathML(
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!DOCTYPE math PUBLIC "-//W3C//DTD MathML 2.0//EN" '
          '"http://www.w3.org/Math/DTD/mathml2/mathml2.dtd">\n'
          '<math>\n  <mrow>\n    <mi> x </mi>\n    <mo>&lt;</mo>\n'
          '    <mtext> a &amp; b </mtext>\n  </mrow>\n</math>\n',
        ),
      ),
      _dump(
        const MathRow([
          MathToken(MathTokenKind.identifier, 'x'),
          MathToken(MathTokenKind.operator, '<'),
          MathToken(MathTokenKind.text, ' a & b '),
        ]),
      ),
    );
  });

  test('documents package:xml rejects, the reader rejects too', () {
    for (final bad in [
      '',
      'x',
      '<math>',
      '<math><mi>x</math>',
      '<math><mi>x</mo></math>',
      '<math></math><math></math>',
      '<math a="b></math>',
      '<math><!-- x </math>',
      '<math><![CDATA[x</math>',
    ]) {
      expect(() => XmlDocument.parse(bad), throwsA(isA<Exception>()));
      expect(
        () => parseMathML(bad),
        throwsA(isA<MathMLException>()),
        reason: bad,
      );
    }
  });

  test('not well-formed, though package:xml reads it: rejected', () {
    for (final bad in [
      '<math a=b></math>',
      '<math a></math>',
      '<math></math >junk',
    ]) {
      expect(
        () => parseMathML(bad),
        throwsA(isA<MathMLException>()),
        reason: bad,
      );
    }
  });
}
