// The hand-written tag scans (xml_balance.dart's xmlTags, docbook5.dart's
// literalTags) against the patterns they replace, on random XML-like text.
import 'dart:math';

import 'package:ptome/src/docbook5.dart' show literalTags;
import 'package:ptome/src/xml_balance.dart';
import 'package:test/test.dart';

final RegExp _tokenRx = RegExp(
  r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<![^>]*>|'
  r'''<(/?)([A-Za-z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>''',
);

final RegExp _literalTagRx = RegExp(
  '<(/?)(literal|emphasis|quote)(?: role="([^"]*)")?>',
);

const List<String> _pieces = [
  '<', '>', '/', '/>', '</', '<a', '<b', '</a>', '</b>', '<x:y.z-1', ' ', //
  '\n', '"', "'", '="v"', "='v'", 'a', 'é', '<!--', '-->', '-', '<![CDATA[', //
  ']]>', ']', '<?', '?>', '<!', '<!DOCTYPE', '<literal>', '</literal>', //
  '<emphasis', '<emphasis>', '</emphasis>', ' role="', 'strong', '<quote', //
  '<quote role="double">', '</quote>', '<literally>', '1',
];

String _text(Random random) => [
  for (var i = random.nextInt(50); i > 0; i--)
    _pieces[random.nextInt(_pieces.length)],
].join();

void main() {
  test('xmlTags finds the tags the token pattern does', () {
    final random = Random(1);
    for (var i = 0; i < 20000; i++) {
      final text = _text(random);
      final expected = [
        for (final m in _tokenRx.allMatches(text))
          if (m[2] case final name?) '${m.start}-${m.end} ${m[1]}$name${m[4]}',
      ];
      final actual = [
        for (final t in xmlTags(text))
          '${t.start}-${t.end} ${t.closing ? '/' : ''}${t.name}'
              '${t.empty ? '/' : ''}',
      ];
      expect(actual, expected, reason: Uri.encodeComponent(text));
    }
  });

  test('literalTags finds the tags the literal pattern does', () {
    final random = Random(2);
    for (var i = 0; i < 20000; i++) {
      final text = _text(random);
      final expected = [
        for (final m in _literalTagRx.allMatches(text))
          '${m.start}-${m.end} ${m[1]}${m[2]} ${m[3]}',
      ];
      final actual = [
        for (final t in literalTags(text))
          '${t.start}-${t.end} ${t.closing ? '/' : ''}${t.name} ${t.role}',
      ];
      expect(actual, expected, reason: Uri.encodeComponent(text));
    }
  });

  test('balanceXml repairs as before', () {
    expect(balanceXml('<a><b></a>'), '<a><b></b></a>');
    expect(balanceXml('</x><a>t</a>'), '<a>t</a>');
    expect(balanceXml('<!-- </a> --><a/>'), '<!-- </a> --><a/>');
  });
}
