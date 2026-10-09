// OpenTypeShaper against a frozen copy of it (test/support/frozen): every
// glyph, advance and kerning, and every width, must be what it was.
import 'dart:io';
import 'dart:math' as math;

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/exact_canvas.dart';
import 'support/frozen/shaper.dart';

const _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFTVWAYo0123456789 '
    'fiflffi.,;-–—’“”éàçß\u00ad\u{1F600}';

void main() {
  OpenTypeFont font(String name) =>
      OpenTypeFont.parse(File('test/fonts/$name').readAsBytesSync());
  final fonts = [
    for (final name in [
      'notoserif-regular-latin.ttf',
      'notoserif-features.ttf',
      'notoserif-kern-subtables.ttf',
      'libertinus-smcp.otf',
    ])
      font(name),
  ];
  const featureSets = <Set<String>>[
    {},
    {'smcp'},
    {'onum'},
    {'onum', 'smcp'},
    {'smcp', 'onum'},
  ];

  test('texts shaped and measured as before', () {
    final random = math.Random(7);
    final runes = _alphabet.runes.toList();
    String text() => String.fromCharCodes([
      for (var i = 0, n = random.nextInt(12); i < n; i++)
        runes[random.nextInt(runes.length)],
    ]);
    final texts = [for (var i = 0; i < 400; i++) text()];
    for (final otf in fonts) {
      for (final subtable in [null, 0]) {
        final shaper = OpenTypeShaper(otf, kernTableSubtable: subtable);
        final frozen = FrozenShaper(otf, kernTableSubtable: subtable);
        for (final text in texts) {
          for (final kerning in [true, false]) {
            for (final ligatures in [false, true]) {
              for (final features in featureSets) {
                final glyphs = shaper.shape(
                  text,
                  kerning: kerning,
                  ligatures: ligatures,
                  features: features,
                );
                expect(
                  exact(glyphs),
                  exact(
                    frozen.shape(
                      text,
                      kerning: kerning,
                      ligatures: ligatures,
                      features: features,
                    ),
                  ),
                  reason: '"$text" $kerning $ligatures $features',
                );
              }
            }
          }
          expect(
            shaper.widthOf(text, 10.5),
            frozen.widthOf(text, 10.5),
            reason: text,
          );
        }
      }
    }
  });
}
