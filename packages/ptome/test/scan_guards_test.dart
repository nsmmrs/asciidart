// The substitutions skip a pass when a cheap check says its pattern cannot
// match. Each check must be a necessary condition: these tests hold it to
// the pattern on random text made of the characters the pattern cares
// about, two-byte letters included.
import 'dart:math';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const List<String> _emailPieces = [
  'a', 'Z', '0', '9', '_', '-', '.', '%', '+', ';', '&amp;', '&', '@', '@', //
  '@@', ' ', '\n', '>', ':', '/', r'\', 'é', 'α', '’', '–', '\u200d', //
  '\u0301', '😀', 'org', '.org', 'x.io', '.c', '#', '*', '!', '"', "'", '=',
];

const List<String> _literalPieces = [
  'a', 'k', 'l', 'n', ':', '[', ']', '(', ')', '&', ';', 'g', 't', '<', '>', //
  '+', r'$', 's', '@', '-', '.', "'", '"', ' ', '\n', '\x7f', 'é', '’', //
  '😀', 'link:', 'lt;', '&gt;', 'xref', 'ss:', 'dexterm', '((', '))', '--',
];

const List<String> _literals = [
  '((', '))', 'dexterm', '{', '://', 'link:', 'mailto:', 'ilto:', '&lt;&lt;', //
  'xref:', '[', ':', ':[', 'kbd:', 'btn:', 'menu:', '"', '&gt;', 'image:', //
  'icon:', '[[', 'or:', '&', ';&l', 'tnote', '++', r'$$', 'ss:', 'stem:', //
  'math:', '--', '...', '(', '\n', '\x7f', 'é', '’', '😀', 'a’', '’s',
];

const List<String> _replacementPieces = [
  'a', 'Z', '1', '_', 'é', '😀', '\u{1d400}', '\u{1d7cf}', '\u0301', r'\', //
  '-', '--', '---', ' ', '\n', //
  '\u2028', '</em>', '</', '/', '>', '<', '<b>', '<!', '&#8217;', '&#8221;', //
  '&#8216;', '&#8220;', ';', "'", "`'", '(C)', '(R)', '(TM)', '(', ')', //
  '...', '.', '&gt;', '&lt;', '-&gt;', '=&gt;', '&lt;-', '&lt;=', '&amp;', //
  'amp;', '#123;', '#x1F;', 'x;', '&',
];

String _describe(Iterable<Match> matches) => [
  for (final m in matches)
    [m.start, m.end, for (var g = 0; g <= m.groupCount; g++) m[g]].join('|'),
].join(' ');

String _text(Random random, List<String> pieces, [int max = 24]) => [
  for (var i = random.nextInt(max); i > 0; i--)
    pieces[random.nextInt(pieces.length)],
].join();

void main() {
  test('mayHoldEmail: false only where inlineEmailRx cannot match', () {
    final random = Random(549);
    var held = 0;
    for (var i = 0; i < 200000; i++) {
      final text = _text(random, _emailPieces);
      if (inlineEmailRx.hasMatch(text)) {
        held++;
        expect(
          mayHoldEmail(text),
          isTrue,
          reason: 'in ${Uri.encodeComponent(text)}',
        );
      }
    }
    // The alphabet has to produce addresses for the test to mean anything.
    expect(held, greaterThan(1000));
  });

  test('mayHoldEmail: verse lines starting with "@ " are skipped', () {
    expect(mayHoldEmail('@ In the beginning God created the heaven.'), isFalse);
    expect(mayHoldEmail('@ a’s @ b–c @'), isFalse);
    expect(mayHoldEmail('write to me@example.org'), isTrue);
    expect(mayHoldEmail('ἀ@β'), isTrue);
    for (final short in ['', '@', 'a@', '@b']) {
      expect(mayHoldEmail(short), isFalse);
    }
    expect(mayHoldEmail('a@b'), isTrue);
  });

  test('hasLiteral, literalIndexOf and hasAnyChar: as String.contains', () {
    final random = Random(96);
    final texts = [for (var i = 0; i < 300; i++) _text(random, _literalPieces)];
    for (var i = 0; i < 100000; i++) {
      // Texts asked about in turn and again (the mask is kept for the
      // last one).
      final text = texts[random.nextInt(texts.length)];
      final literal = _literals[random.nextInt(_literals.length)];
      final reason = 'for $literal in ${Uri.encodeComponent(text)}';
      expect(hasLiteral(text, literal), text.contains(literal), reason: reason);
      final start = random.nextInt(text.length + 1);
      expect(
        literalIndexOf(text, literal, start),
        text.indexOf(literal, start),
        reason: '$reason from $start',
      );
      const classChars = "*_`#^~'+&<>([";
      final chars = [
        for (var k = random.nextInt(4) + 1; k > 0; k--)
          classChars[random.nextInt(classChars.length)],
      ].join();
      expect(
        hasAnyChar(text, chars),
        chars.split('').any(text.contains),
        reason: 'for any of $chars in ${Uri.encodeComponent(text)}',
      );
    }
  });

  test('hasReplaceableText: as replaceableTextRx', () {
    const pieces = [
      'a', '-', '--', '.', '..', '(', ')', 'C', 'R', 'T', 'M', '(C)', '(TM', //
      '&', "'", ' ', 'é', '’',
    ];
    final random = Random(909);
    for (var i = 0; i < 50000; i++) {
      final text = _text(random, pieces, 8);
      expect(
        hasReplaceableText(text),
        replaceableTextRx.hasMatch(text),
        reason: 'in ${Uri.encodeComponent(text)}',
      );
    }
  });

  for (final (n, rule) in replacements.indexed) {
    test('replacement $n (${rule.guard}): its scan finds the same matches', () {
      // The farthest starts from the guard, then random text.
      const edges = [
        "\u{1d400}\\'s", "x\u{1d7cf}\\'\u{1d400}", '\u{1d400}\\--\u{1d400}', //
        r'a\--b', r'</em>\--b', r'&#8217;\--x', '</a</b>--c', r'\(TM)', //
        r'\&amp;#123;',
      ];
      final random = Random(n);
      for (var i = 0; i < 20000; i++) {
        final text = i < edges.length
            ? edges[i]
            : _text(random, _replacementPieces, 16);
        final start = i < edges.length ? 0 : random.nextInt(text.length + 1);
        expect(
          _describe(rule.scan.allMatches(text, start)),
          _describe(rule.pattern.allMatches(text, start)),
          reason: 'in ${Uri.encodeComponent(text)} from $start',
        );
      }
    });
  }

  test('subSpecialchars: as specialCharsRx and specialCharsTr', () {
    const pieces = ['a', '<', '&', '>', '&amp;', ';', ' ', 'é', '😀', '\n'];
    final random = Random(450);
    for (var i = 0; i < 20000; i++) {
      final text = _text(random, pieces, 12);
      expect(
        subSpecialchars(text),
        text.replaceAllMapped(
          specialCharsRx,
          (match) => specialCharsTr[match.group(0)]!,
        ),
        reason: 'in ${Uri.encodeComponent(text)}',
      );
    }
  });

  const macroPieces = [
    'a', 'x', '-', ',', ' ', '\n', r'\', r'\\', '[', ']', '[x]', '[a,b]', //
    '[[', ']]', '(', ')', '((', '))', '(((', ')))', 'indexterm:', //
    'indexterm2:', 'kbd:', 'btn:', 'menu:', 'File', '&gt;', ' &gt; ', '"', //
    'image:', 'icon:', 'x.png', 'stem:', 'latexmath:', 'asciimath:', //
    'pass:', 'pass:q', '+', '++', '+++', r'$', r'$$', ':', 'é', '😀',
  ];
  for (final (name, scan) in [
    ('inlineIndextermMacroRx', inlineIndextermMacroScan),
    ('inlineKbdBtnMacroRx', inlineKbdBtnMacroScan),
    ('inlineMenuMacroRx', inlineMenuMacroScan),
    ('inlineMenuRx', inlineMenuScan),
    ('inlineImageMacroRx', inlineImageMacroScan),
    ('inlineStemMacroRx', inlineStemMacroScan),
    ('inlinePassMacroRx', inlinePassMacroScan),
  ]) {
    test('$name: its scan finds the same matches', () {
      const edges = [r'[x]\\++a++', r'\[x]\++a++', r'[a]$$b$$', r'\pass:[x]'];
      final random = Random(name.hashCode);
      for (var i = 0; i < 20000; i++) {
        final text = i < edges.length ? edges[i] : _text(random, macroPieces);
        final start = i < edges.length ? 0 : random.nextInt(text.length + 1);
        final pattern = switch (scan) {
          AnchoredScan(:final pattern) || StartsScan(:final pattern) => pattern,
          _ => throw StateError('$scan'),
        };
        expect(
          _describe(scan.allMatches(text, start)),
          _describe(pattern.allMatches(text, start)),
          reason: 'in ${Uri.encodeComponent(text)} from $start',
        );
      }
    });
  }

  test('mayBeListItem: false only where the list patterns cannot match', () {
    const pieces = [
      ' ', '\t', '-', '*', '**', '•', '.', '..', '1', '12.', 'a', 'Z', 'i', //
      'IV)', 'x)', ')', '<', '<1>', '<.>', '>', ':', '::', ':::', ';;', ';', //
      '//', '/', 'é', 'term', '\n', '\r', ' ', '#',
    ];
    final random = Random(1384);
    var matched = 0;
    for (var i = 0; i < 100000; i++) {
      final line = _text(random, pieces, 8);
      for (final context in listRxMap.keys) {
        final match = listRxMap[context]!.firstMatch(line);
        if (match != null) matched++;
        expect(
          listItemMatch(context, line)?.group(0),
          match?.group(0),
          reason: '$context in ${Uri.encodeComponent(line)}',
        );
      }
    }
    expect(matched, greaterThan(10000));
  });
}
