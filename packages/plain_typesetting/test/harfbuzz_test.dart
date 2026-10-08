// The OpenType shaper against HarfBuzz (harfbuzzjs 1.6.3, in
// tool/oracles/harfbuzz, installed by tool/oracles/setup.sh; skipped where
// it isn't): the same glyphs and advances, kerning included, for each line
// of test/fixtures/shaping.txt, with ligatures and kerning on and off and
// the onum and smcp features, in fonts kerned by GPOS and by a kern table
// (Libertinus's smcp is a multiple substitution). Measured on 2026-10-08:
// every run of every font shapes as HarfBuzz shapes it.
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

const String _shape = 'tool/oracles/harfbuzz/shape.mjs';

/// A setting: the shaper's options, and HarfBuzz's features for them.
typedef _Setting = ({
  String name,
  bool ligatures,
  bool kerning,
  Set<String> features,
  List<String> harfbuzz,
});

const List<_Setting> _settings = [
  (
    name: 'ligatures and kerning',
    ligatures: true,
    kerning: true,
    features: {},
    harfbuzz: [],
  ),
  (
    name: 'no ligatures',
    ligatures: false,
    kerning: true,
    features: {},
    harfbuzz: ['-liga'],
  ),
  (
    name: 'no kerning',
    ligatures: true,
    kerning: false,
    features: {},
    harfbuzz: ['-kern'],
  ),
  (
    name: 'onum',
    ligatures: true,
    kerning: true,
    features: {'onum'},
    harfbuzz: ['onum'],
  ),
  (
    name: 'smcp',
    ligatures: true,
    kerning: true,
    features: {'smcp'},
    harfbuzz: ['smcp'],
  ),
];

/// Each font, with the number of its (line, setting) runs that must
/// shape as HarfBuzz shapes them: all 55.
const Map<String, int> _fonts = {
  'notoserif-features.ttf': 55,
  'notoserif-regular-latin.ttf': 55,
  'notoserif-kern-subtables.ttf': 55,
  'libertinus-smcp.otf': 55,
};

void main() {
  final ready = Directory('tool/oracles/harfbuzz/node_modules').existsSync();
  final lines = File('test/fixtures/shaping.txt')
      .readAsLinesSync()
      .where((l) => l.isNotEmpty)
      .toList();
  for (final MapEntry(key: name, value: minimum) in _fonts.entries) {
    test('$name shapes as HarfBuzz does', () {
      final path = 'test/fonts/$name';
      final font = OpenTypeShaper(
        OpenTypeFont.parse(File(path).readAsBytesSync()),
      );
      final upem = font.font.unitsPerEm;
      final runs = [
        for (final setting in _settings)
          for (final line in lines)
            {'text': line, 'features': setting.harfbuzz},
      ];
      final theirs = _harfbuzz(path, runs);
      var same = 0;
      final differ = <String>[];
      var i = 0;
      for (final setting in _settings) {
        for (final line in lines) {
          final ours = [
            for (final g in font.shape(
              line,
              kerning: setting.kerning,
              ligatures: setting.ligatures,
              features: setting.features,
            ))
              [g.id, ((g.advance + g.kerning) * upem / 1000).round()],
          ];
          final expected = theirs[i++];
          if (jsonEncode(ours) == jsonEncode(expected)) {
            same++;
          } else {
            differ.add(
              '${setting.name}: $line\n    ours:     $ours\n'
              '    HarfBuzz: $expected',
            );
          }
        }
      }
      // The runs that differ are the report's point.
      // ignore: avoid_print
      print(
        '$name: $same of ${runs.length} runs as HarfBuzz shapes them\n'
        '${differ.take(6).map((d) => '  $d\n').join()}',
      );
      expect(same, greaterThanOrEqualTo(minimum));
    }, skip: ready ? false : 'run tool/oracles/setup.sh to install HarfBuzz');
  }
}

/// HarfBuzz's [glyph id, x advance] pairs for each of [runs] in [font].
List<List<Object?>> _harfbuzz(String font, List<Map<String, Object>> runs) {
  final dir = Directory.systemTemp.createTempSync('harfbuzz_oracle.');
  try {
    final file = File('${dir.path}/input')
      ..writeAsStringSync(jsonEncode({'font': font, 'runs': runs}));
    final r = Process.runSync('sh', [
      '-c',
      'node "\$0" < "${file.path}"',
      _shape,
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) throw StateError('HarfBuzz: ${r.stderr}');
    return (jsonDecode(r.stdout as String) as List<Object?>)
        .cast<List<Object?>>();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
