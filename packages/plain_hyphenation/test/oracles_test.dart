// plain_hyphenation against other hyphenators of the same hyph-utf8
// patterns, over the words of the Universal Declaration of Human Rights in
// 19 languages (test/fixtures/words): typst's hypher (Rust) and
// Hyphenopoly (JavaScript and WebAssembly). The oracles are built by
// tool/oracles/setup.sh; the test is skipped where they aren't.
//
// The implementations ship patterns from different tex-hyphen revisions
// and have quirks of their own, so a word may differ for reasons that
// aren't errors (each language's notes say which). Measured on 2026-10-08:
// hypher agrees with every word in 15 languages and Hyphenopoly in 13, and
// wherever the two disagree with each other, one of them agrees with
// plain_hyphenation. The test holds each language to that agreement and
// prints the words that differ.
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_hyphenation/plain_hyphenation.dart';
import 'package:plain_hyphenation/src/patterns.g.dart';
import 'package:test/test.dart';

const String _hypher = 'tool/oracles/hypher/target/release/hypher-oracle';
const String _hyphenopoly = 'tool/oracles/hyphenopoly/hyphenate.mjs';

/// Each language's tag, its ISO 639-1 code (hypher), its Hyphenopoly
/// code, and the lowest agreement with each oracle, as a fraction.
const List<(String, String, String, double, double)> _languages = [
  ('en-us', 'en', 'en-us', 1, 1),
  // Hyphenopoly's newer patterns: "na-ti-o-nen" for our "na-tio-nen".
  ('de-1996', 'de', 'de', 1, 0.975),
  ('fr', 'fr', 'fr', 1, 1),
  ('es', 'es', 'es', 1, 1),
  // Hyphenopoly leaves words ending in an accented vowel whole ("libertà").
  ('it', 'it', 'it', 1, 0.96),
  ('nl', 'nl', 'nl', 1, 1),
  // Hyphenopoly's other patterns: "paí-ses" for our "pa-í-ses".
  ('pt', 'pt', 'pt', 1, 0.975),
  ('sv', 'sv', 'sv', 1, 1),
  ('pl', 'pl', 'pl', 0.998, 1),
  // hypher splits a single letter off ("ра-з-умом").
  ('ru', 'ru', 'ru', 0.996, 1),
  // hypher's other Finnish patterns ("avi-o-lii-ton" for "avio-lii-ton");
  // Hyphenopoly agrees with every word.
  ('fi', 'fi', 'fi', 0.945, 1),
  ('da', 'da', 'da', 1, 1),
  // Hyphenopoly leaves words starting with a capital dotted I whole.
  ('tr', 'tr', 'tr', 1, 0.995),
  ('uk', 'uk', 'uk', 1, 1),
  ('ca', 'ca', 'ca', 1, 1),
  ('hr', 'hr', 'hr', 1, 1),
  ('sk', 'sk', 'sk', 1, 0.998),
  ('sl', 'sl', 'sl', 1, 1),
  // Hyphenopoly's other patterns ("aner-kjent" for "an-er-kjent").
  ('nb', 'nb', 'nb', 1, 0.99),
];

String _ours(PatternHyphenator h, String word) {
  final points = h.hyphenate(word);
  final runes = word.runes.toList();
  return [
    for (var i = 0; i < runes.length; i++)
      '${points.contains(i) ? '-' : ''}${String.fromCharCode(runes[i])}',
  ].join();
}

void main() {
  final ready =
      File(_hypher).existsSync() &&
      Directory('tool/oracles/hyphenopoly/node_modules').existsSync();
  for (final (tag, iso, hyphenopolyCode, hypherMin, hyphenopolyMin)
      in _languages) {
    test('$tag agrees with hypher and Hyphenopoly', () {
      final words = File('test/fixtures/words/$tag.txt')
          .readAsLinesSync()
          .where((w) => w.isNotEmpty)
          .toList();
      final (left, right, _, _, _, _, _) = hyphenationPatterns[tag]!;
      final ours = [for (final w in words) _ours(hyphenatorFor(tag)!, w)];

      final hypherRun = _withInput(
        _hypher,
        [],
        [for (final w in words) '$iso $left $right $w'].join('\n'),
      );
      final hypherOut = const LineSplitter().convert(hypherRun);

      final hyphenopolyOut = (jsonDecode(
        _withInput(
          'node',
          [_hyphenopoly],
          jsonEncode({
            'lang': hyphenopolyCode,
            'left': left,
            'right': right,
            'words': words,
          }),
        ),
      ) as List<Object?>).cast<String>();

      double agreement(List<String> other, String name) {
        var same = 0;
        final differ = <String>[];
        for (var i = 0; i < words.length; i++) {
          if (ours[i] == other[i]) {
            same++;
          } else if (differ.length < 12) {
            differ.add('${ours[i]} / ${other[i]}');
          }
        }
        final fraction = same / words.length;
        // The words that differ are the report's point.
        // ignore: avoid_print
        print(
          '$tag vs $name: $same of ${words.length} '
          '(${(fraction * 100).toStringAsFixed(1)}%)'
          '${differ.isEmpty ? '' : '; differ: ${differ.join(', ')}'}',
        );
        return fraction;
      }

      expect(agreement(hypherOut, 'hypher'), greaterThanOrEqualTo(hypherMin));
      expect(
        agreement(hyphenopolyOut, 'Hyphenopoly'),
        greaterThanOrEqualTo(hyphenopolyMin),
      );
    }, skip: ready ? false : 'run tool/oracles/setup.sh to build the oracles');
  }
}

/// The standard output of [exe] with [args], given [input].
String _withInput(String exe, List<String> args, String input) {
  final dir = Directory.systemTemp.createTempSync('hyphenation_oracle.');
  try {
    final file = File('${dir.path}/input')..writeAsStringSync(input);
    final r = Process.runSync('sh', [
      '-c',
      '"\$0" "\$@" < "${file.path}"',
      exe,
      ...args,
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) throw StateError('$exe: ${r.stderr}');
    return r.stdout as String;
  } finally {
    dir.deleteSync(recursive: true);
  }
}
