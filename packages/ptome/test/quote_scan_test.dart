// AnchoredScan (constants.dart) finds a pattern's matches by trying it
// only where one can start; these tests hold it to the pattern's own
// matches on random text made of the marks, brackets, prefixes, link and
// cross reference parts and line terminators the patterns care about.
import 'dart:math';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const List<String> _pieces = [
  'a', 'b', 'é', '1', ' ', ' ', '\t', '\n', '\r', ' ', //
  '*', '**', '_', '__', '#', '##', '^', '~', '`', '``', '"', "'", '+', //
  '++', '[', ']', '[x]', '[.r]', r'\', ';', ':', '}', '&', '.', //
  '&#8216;', '&#8220;', '"`', '`"', "'`", "`'", "''",
];

const List<String> _linkPieces = [
  'a', 'x.org', '/', '.', ',', ' ', '\n', '\u2028', '[', ']', '[t]', r'\', //
  'https://', 'http://', 'ftp://', 'irc://', 'file://', '://', 'link:', //
  'mailto:', 'ilto:', 'a@b.org', '&lt;', '&gt;', '&lt;&lt;', '&gt;&gt;', //
  'xref:', '#', '{', '(', ')', ';', '"', "'", '>',
];

const List<String> _macroPieces = [
  'a', 'x', '_', '-', '.', ':', ',', ' ', '\n', '\u2028', r'\', '{', '}', //
  'set:', 'counter:', 'counter2:', '[[', ']]', '[', ']', '[t]', 'anchor:', //
  'footnote', 'footnote:', 'footnoteref:', '</a>', 'x-', ' x-', '+', '++', //
  '`', '``', ';', 'é',
];

String _text(Random random, [List<String> pieces = _pieces]) => [
  for (var i = random.nextInt(40); i > 0; i--)
    pieces[random.nextInt(pieces.length)],
].join();

String _describe(Iterable<Match> matches) => matches.map(_match).join(' ');

String _match(Match m) {
  final groups = [for (var g = 0; g <= m.groupCount; g++) m[g]].join('|');
  return '${m.start}-${m.end}:$groups';
}

/// [pattern]'s matches from [start], a match [skip] rejects passed over
/// and the search going on from its next character (the reference).
Iterable<Match> _reference(
  RegExp pattern,
  String text,
  int start,
  bool Function(Match) skip,
) sync* {
  var at = start;
  while (at <= text.length) {
    final match = pattern.allMatches(text, at).firstOrNull;
    if (match == null) return;
    if (skip(match)) {
      at = match.start + 1;
      continue;
    }
    yield match;
    at = match.end > match.start ? match.end : match.end + 1;
  }
}

void main() {
  final rules = {...quoteSubs[false]!, ...quoteSubs[true]!};
  for (final rule in rules) {
    test(
      '${rule.type} ${rule.scope.name} (${rule.guard}): the same matches',
      () {
        final random = Random(rule.guard.hashCode);
        for (var i = 0; i < 4000; i++) {
          final text = _text(random);
          final start = text.isEmpty ? 0 : random.nextInt(text.length + 1);
          final scan = rule.scan;
          expect(
            _describe(scan.allMatches(text, start)),
            _describe(rule.pattern.allMatches(text, start)),
            reason: 'in ${Uri.encodeComponent(text)} from $start',
          );
          bool skip(Match m) => m.start.isOdd;
          expect(
            _describe(scan.matchesFrom(text, start, skip: skip)),
            _describe(_reference(rule.pattern, text, start, skip)),
            reason: 'skipping, in ${Uri.encodeComponent(text)} from $start',
          );
        }
      },
    );
  }

  for (final (name, scan, pieces) in [
    ('inlineLinkRx', inlineLinkScan, _linkPieces),
    ('inlineLinkMacroRx', inlineLinkMacroScan, _linkPieces),
    ('inlineXrefMacroRx', inlineXrefMacroScan, _linkPieces),
    ('inlineAnchorRx', inlineAnchorScan, _macroPieces),
    ('attributeReferenceRx', attributeReferenceScan, _macroPieces),
    ('inlineFootnoteMacroRx', inlineFootnoteMacroScan, _macroPieces),
    ('inlinePassRx', inlinePassScan[false]!, _macroPieces),
    ('inlinePassRx (compat)', inlinePassScan[true]!, _macroPieces),
  ]) {
    test('$name: the same matches', () {
      final random = Random(name.hashCode);
      for (var i = 0; i < 4000; i++) {
        final text = _text(random, pieces);
        final start = text.isEmpty ? 0 : random.nextInt(text.length + 1);
        expect(
          _describe(scan.allMatches(text, start)),
          _describe(scan.pattern.allMatches(text, start)),
          reason: 'in ${Uri.encodeComponent(text)} from $start',
        );
      }
    });
  }
}
