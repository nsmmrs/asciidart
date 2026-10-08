// The LaTeX converter against Temml 0.14.0 (tool/oracles/temml, installed
// by tool/oracles/setup.sh; the test is skipped where it isn't), over the
// LaTeX of Temml's screen tests (test/fixtures/temml): the examples of
// KaTeX's screenshotter, the Mozilla MathML torture test and LaTeXML's.
//
// The two write the same math differently (Temml: `mi` for `…` and `/`,
// U+2061 after function names, one `mo` per prime, math alphanumerics for
// `\mathbf`, spacing accents, CSS borders for `\underline`), so the test
// compares the characters of the tokens in order, those conventions
// normalized. Measured on 2026-10-08: 137 of the 186 expressions use only
// commands the converter knows, and 136 of those read the same as Temml
// (Temml sets a lone `̸` before `\not{abc}`). The test holds both counts
// and prints what differs, and the commands it doesn't know.
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_math/plain_math.dart';
import 'package:test/test.dart';

const String _temml = 'tool/oracles/temml/render.mjs';

/// The text of [node]'s tokens, in order.
Iterable<String> _texts(MathNode node) sync* {
  switch (node) {
    case MathToken(:final text):
      yield text;
    case MathRow(:final children):
      for (final c in children) {
        yield* _texts(c);
      }
    case MathStyled(:final child) || MathEnclose(:final child):
      yield* _texts(child);
    case MathScripts(:final base, :final sub, :final sup):
      for (final n in [base, sub, sup]) {
        if (n != null) yield* _texts(n);
      }
    case MathUnderOver(:final base, :final under, :final over):
      for (final n in [base, under, over]) {
        if (n != null) yield* _texts(n);
      }
    case MathFraction(:final numerator, :final denominator):
      yield* _texts(numerator);
      yield* _texts(denominator);
    case MathRadical(:final radicand, :final index):
      yield* _texts(radicand);
      if (index != null) yield* _texts(index);
    case MathTable(:final rows):
      for (final cell in rows.expand((r) => r)) {
        yield* _texts(cell);
      }
    case MathSpace():
      break;
  }
}

/// Mathematical Bold Greek and its styles, in the order of each style's
/// 58 code points.
const String _greek =
    'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡϴΣΤΥΦΧΨΩ∇αβγδεζηθικλμνξοπρςστυφχψω∂ϵϑϰϕϱϖ';

/// The letterlike symbols that stand in for math alphanumerics.
const Map<String, String> _letterlike = {
  'ℂ': 'C', 'ℍ': 'H', 'ℕ': 'N', 'ℙ': 'P', 'ℚ': 'Q', 'ℝ': 'R', 'ℤ': 'Z', //
  'ℬ': 'B', 'ℰ': 'E', 'ℱ': 'F', 'ℋ': 'H', 'ℐ': 'I', 'ℒ': 'L', 'ℳ': 'M', //
  'ℛ': 'R', 'ℯ': 'e', 'ℊ': 'g', 'ℴ': 'o', 'ℭ': 'C', 'ℌ': 'H', 'ℑ': 'I', //
  'ℜ': 'R', 'ℨ': 'Z', 'ℎ': 'h',
};

/// Spacing accents (Temml's) as the combining marks and ASCII the
/// converter writes.
const Map<String, String> _accents = {
  'ˊ': '́', 'ˋ': '̀', '¨': '̈', '˙': '̇', //
  '˝': '̋', '˚': '̊', 'ˆ': '^', '˜': '~',
};

/// The characters of [node]'s tokens, the conventions normalized: no
/// spaces or invisible operators, no underline and overline marks, math
/// alphanumerics as letters and digits, spacing accents as combining
/// marks, the TeX logos in capitals as written.
String _normalized(MathNode node) {
  final out = StringBuffer();
  for (final rune in _texts(node).join().runes) {
    if (rune == 0x20 || rune == 0xa0 || (rune >= 0x2061 && rune <= 0x2064)) {
      continue;
    }
    if (rune == 0x5f || rune == 0xaf || rune == 0x203e) continue;
    if (rune >= 0x1d400 && rune <= 0x1d6a3) {
      final k = (rune - 0x1d400) % 52;
      out.writeCharCode(k < 26 ? 0x41 + k : 0x61 + k - 26);
    } else if (rune >= 0x1d6a8 && rune <= 0x1d7c9) {
      out.write(_greek[(rune - 0x1d6a8) % 58]);
    } else if (rune >= 0x1d7ce && rune <= 0x1d7ff) {
      out.writeCharCode(0x30 + (rune - 0x1d7ce) % 10);
    } else {
      final c = String.fromCharCode(rune);
      out.write(_letterlike[c] ?? _accents[c] ?? c);
    }
  }
  return '$out'.replaceAll('LATEX', 'LaTeX').replaceAll('TEX', 'TeX');
}

void main() {
  final ready = Directory('tool/oracles/temml/node_modules').existsSync();
  test("Temml's screen tests", () {
    final expressions = (jsonDecode(
      File('test/fixtures/temml/expressions.json').readAsStringSync(),
    ) as List<Object?>).cast<Map<String, Object?>>();
    final temml = _render([
      for (final e in expressions) {'tex': e['tex'], 'display': e['display']},
    ]);
    var known = 0;
    var same = 0;
    final unknownCommands = <String, int>{};
    final differ = <String>[];
    for (final (i, e) in expressions.indexed) {
      final tex = e['tex']! as String;
      final unknown = <String>{};
      final ours = latexToMath(
        tex,
        display: e['display']! as bool,
        unknown: unknown,
      );
      for (final u in unknown) {
        unknownCommands[u] = (unknownCommands[u] ?? 0) + 1;
      }
      if (unknown.isNotEmpty) continue;
      known++;
      final theirs = temml[i]['mathml'];
      expect(theirs, isNotNull, reason: '$tex: ${temml[i]['error']}');
      final a = _normalized(ours);
      final b = _normalized(parseMathML(theirs! as String));
      if (a == b) {
        same++;
      } else {
        differ.add('$tex\n    ours:  $a\n    Temml: $b');
      }
    }
    final commands = unknownCommands.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // The differences and the commands it doesn't know are the report's
    // point.
    // ignore: avoid_print
    print(
      '$known of ${expressions.length} use only known commands; '
      '$same of them read as Temml does\n'
      '${differ.map((d) => '  $d\n').join()}'
      'unknown: ${commands.map((c) => '${c.key} (${c.value})').join(', ')}',
    );
    expect(known, greaterThanOrEqualTo(137));
    expect(same, greaterThanOrEqualTo(136));
  }, skip: ready ? false : 'run tool/oracles/setup.sh to install Temml');
}

/// Temml's MathML for each of [inputs] (`{mathml}` or `{error}`).
List<Map<String, Object?>> _render(List<Map<String, Object?>> inputs) {
  final dir = Directory.systemTemp.createTempSync('temml_oracle.');
  try {
    final file = File('${dir.path}/input')
      ..writeAsStringSync(jsonEncode(inputs));
    final r = Process.runSync('sh', [
      '-c',
      'node "\$0" < "${file.path}"',
      _temml,
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) throw StateError('Temml: ${r.stderr}');
    return (jsonDecode(r.stdout as String) as List<Object?>)
        .cast<Map<String, Object?>>();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
