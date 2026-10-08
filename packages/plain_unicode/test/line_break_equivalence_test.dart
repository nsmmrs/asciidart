// The optimized line breaker against the frozen one it replaced
// (test/oracle/line_break_v0.dart): the same class for every code point,
// the same breaks for the conformance strings, real paragraphs and random
// strings.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'oracle/line_break_data_v0.dart' as data_v0;
import 'oracle/line_break_v0.dart' as v0;

/// The breaks as text: offsets, `!` after the mandatory ones.
String _signature(List<LineBreak> breaks) =>
    [for (final b in breaks) '${b.offset}${b.mandatory ? '!' : ''}'].join(',');

String _oracle(String text) => [
  for (final b in v0.lineBreaks(text)) '${b.offset}${b.mandatory ? '!' : ''}',
].join(',');

String _codePoints(String text) =>
    text.runes.map((r) => r.toRadixString(16)).join(' ');

/// Compares every text of [texts] with the oracle; the failures, at most
/// 20.
List<String> _differences(Iterable<String> texts) {
  final failures = <String>[];
  for (final text in texts) {
    final expected = _oracle(text);
    final actual = _signature(lineBreaks(text));
    if (actual != expected && failures.length < 20) {
      failures.add('${_codePoints(text)}\n  want $expected\n  got  $actual');
    }
  }
  return failures;
}

/// The strings of the conformance test, LineBreakTest.txt.
List<String> _conformance() => [
  for (final line in const LineSplitter().convert(
    utf8.decode(
      gzip.decode(File('test/unicode/LineBreakTest.txt.gz').readAsBytesSync()),
    ),
  ))
    if (line.split('#').first.trim() case final data when data.isNotEmpty)
      String.fromCharCodes([
        for (final token in data.split(RegExp(r'\s+')))
          if (token != '÷' && token != '×') int.parse(token, radix: 16),
      ]),
];

/// Real text: the paragraphs of the workspace's AsciiDoc files (ptome's
/// fixtures and vendored test suites, the Asciidoctor locales in some 40
/// languages), with their lines joined, and the files whole.
List<String> _corpus() {
  final root = Directory('../ptome');
  if (!root.existsSync()) return const [];
  final texts = <String>[];
  for (final file in root.listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.adoc')) continue;
    if (file.path.contains('.dart_tool')) continue;
    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      continue; // not UTF-8
    }
    texts.add(content);
    for (final paragraph in content.split(RegExp(r'\n\s*\n'))) {
      final joined = paragraph.replaceAll('\n', ' ').trim();
      if (joined.isNotEmpty) texts.add(joined);
    }
  }
  return texts;
}

/// Prose in scripts the corpus has little of.
const List<String> _samples = [
  '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。',
  '「この書生というのは時々我々を捕えて煮て食うという話である。」',
  '（ただ彼の掌に載せられてスーと持ち上げられた時）。2024年10月8日、100％。',
  '“漢字”と‘かな’、«guillemets» and „Anführungszeichen“ — ‹test›.',
  '다람쥐 헌 쳇바퀴에 타고파. 한국어 문장, 123,456원!',
  'ภาษาไทยไม่มีการเว้นวรรคระหว่างคำ ລາວ ខ្មែរ မြန်မာ',
  'עברית: שלום-עולם 12-34 «ציטוט» (סוגריים).',
  'العربية: مرحبا بالعالم، ١٢٣٫٤٥ (أقواس).',
  'हिन्दी में क्षत्रिय ᬅᬓ᭄ᬱᬭ ᬩᬮᬶ ꦲꦏ꧀ꦱꦫ.',
  '👩\u200d👩\u200d👧 👍🏽 🇯🇵🇺🇸🇫 ☝🏻\u200d 🏳\ufe0f\u200d🌈 #\ufe0f\u20e3',
  'a\u200db\u200d c\u200bd\u2060e',
  r'$(12.50) €10,00 100% −5 +3.14e10 1/2 (1) [2] {3} ¥¢£ ¿¡ ‽',
  'http://example.org/path?a=b&c=d#frag e-mail co-op — dash–dash ‐‑',
  'soft\u00adhyphen non\u00a0breaking',
  'line\nbreaks\r\nand\rmore\u0085next\u2028line\u2029para\u000bvt\u000cff',
];

/// Random strings of 1 to 12 code points from [pool].
Iterable<String> _random(Random random, List<int> pool, int count) sync* {
  for (var n = 0; n < count; n++) {
    yield String.fromCharCodes([
      for (var k = random.nextInt(12); k >= 0; k--)
        pool[random.nextInt(pool.length)],
    ]);
  }
}

void main() {
  test('every code point has the same class', () {
    final failures = <String>[];
    for (var c = 0; c <= 0x10ffff; c++) {
      if (lineBreakClass(c).name != v0.lineBreakClass(c).name) {
        failures.add(c.toRadixString(16));
      }
    }
    expect(failures.take(20), isEmpty, reason: '${failures.length} differ');
    for (final c in [-1, -0x7fffffff, 0x110000, 0x7fffffff]) {
      expect(lineBreakClass(c).name, v0.lineBreakClass(c).name, reason: '$c');
    }
  });

  test('the conformance strings break the same', () {
    final texts = _conformance();
    expect(texts.length, greaterThan(15000));
    expect(_differences(texts), isEmpty);
  });

  test('real paragraphs break the same', () {
    final texts = [..._corpus(), ..._samples];
    expect(texts.length, greaterThan(_samples.length + 1000));
    expect(_differences(texts), isEmpty);
  });

  test('random strings break the same', () {
    // One code point for each distinct set of properties, the ones the
    // rules single out, and the common ones again.
    final representatives = <int, int>{};
    for (var r = 0; r < data_v0.rangeStarts.length; r++) {
      representatives.putIfAbsent(
        data_v0.rangeValues[r],
        () => data_v0.rangeStarts[r],
      );
    }
    final pool = [
      ...representatives.values,
      ...[0x25cc, 0x200d, 0x200d, 0x300, 0x301, 0x20, 0x20, 0x20, 0x20],
      ...[0x41, 0x61, 0x31, 0x32, 0x2c, 0x2e, 0x22, 0x27, 0x201c, 0x201d],
      ...[0x2018, 0x2019, 0xab, 0xbb, 0x28, 0x29, 0x5b, 0x5d, 0x2d, 0x2010],
      ...[0x24, 0x25, 0x2f, 0x1f1e6, 0x1f1ef, 0x1f466, 0x1f3fb, 0x1f9d1],
      ...[0x1b05, 0x1b44, 0x1b13, 0x1b34, 0xa9c0, 0x1bf2, 0x11f42, 0x0e01],
      ...[0x3002, 0x300c, 0x300d, 0x3042, 0x30fc, 0xff08, 0xff09, 0xd55c],
      ...[0x1100, 0x1161, 0x11a8, 0xac00, 0xac01, 0xa, 0xd, 0x85, 0x2028],
      ...[0xa0, 0x202f, 0x2060, 0x200b, 0xad, 0x5d0, 0x5be, 0x1f000],
      ...[0xd800, 0xdc00, 0x1fffd, 0xe0001, 0xe0020],
    ];
    final random = Random(14);
    expect(_differences(_random(random, pool, 300000)), isEmpty);
    // Any code point at all, lone surrogates included.
    final any = [for (var k = 0; k < 4096; k++) random.nextInt(0x110000)];
    final bmp = [for (var k = 0; k < 4096; k++) random.nextInt(0x10000)];
    expect(_differences(_random(random, any, 30000)), isEmpty);
    expect(_differences(_random(random, bmp, 30000)), isEmpty);
  });
}
