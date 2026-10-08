// Case mapping against two oracles: Ruby 4.0.7's String#upcase and
// #downcase for every code point (test/fixtures/ruby_case_mapping.txt,
// written by tool/ruby_case_mapping.rb), and, where Node.js is installed,
// JavaScript's toUpperCase and toLowerCase (Unicode 17.0 in Node.js 26),
// Final_Sigma included.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

bool _has(String tool) =>
    Process.runSync('which', [tool]).exitCode == 0 ||
    Process.runSync('where', [tool], runInShell: true).exitCode == 0;

/// Ruby's mappings by method (`upcase`, `downcase`): code point to text.
Map<String, Map<int, String>> _ruby() {
  final tables = <String, Map<int, String>>{};
  Map<int, String>? current;
  for (final line in File(
    'test/fixtures/ruby_case_mapping.txt',
  ).readAsLinesSync()) {
    if (line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      current = tables[line.substring(1, line.length - 1)] = {};
      continue;
    }
    final [cp, ...mapped] = line.split(' ');
    current![int.parse(cp, radix: 16)] = String.fromCharCodes([
      for (final c in mapped) int.parse(c, radix: 16),
    ]);
  }
  return tables;
}

/// Prints JavaScript's upper and lower case of every non-ASCII code point
/// they change: `cp upper lower`, code points in hexadecimal, `.`-joined.
const String _nodeMappings = r'''
const out = [];
for (let cp = 0x80; cp <= 0x10ffff; cp++) {
  if (cp >= 0xd800 && cp <= 0xdfff) continue;
  const c = String.fromCodePoint(cp);
  const u = c.toUpperCase(), l = c.toLowerCase();
  const hex = (s) => [...s].map((x) => x.codePointAt(0).toString(16)).join('.');
  if (u !== c || l !== c) out.push(`${cp.toString(16)} ${hex(u)} ${hex(l)}`);
}
process.stdout.write(out.join('\n'));
''';

/// Prints JavaScript's toLowerCase of each string of the JSON array in
/// argv 1, as JSON.
const String _nodeLowerCase = '''
const samples = JSON.parse(process.argv[1]);
process.stdout.write(JSON.stringify(samples.map((s) => s.toLowerCase())));
''';

bool _isScalar(int cp) => cp < 0xd800 || cp > 0xdfff;

void main() {
  test('the Unicode versions', () {
    expect(caseMappingUnicodeVersion, '17.0.0');
    expect(lineBreakUnicodeVersion, '18.0.0');
  });

  test("Ruby's upcase and downcase, for every code point", () {
    final ruby = _ruby();
    final problems = <String>[];
    for (var cp = 0x80; cp <= 0x10ffff; cp++) {
      if (!_isScalar(cp)) continue;
      final char = String.fromCharCode(cp);
      final up = ruby['upcase']![cp] ?? char;
      final down = ruby['downcase']![cp] ?? char;
      if (upperCase(char) != up) {
        problems.add('upcase U+${cp.toRadixString(16)}');
      }
      if (lowerCase(char) != down) {
        problems.add('downcase U+${cp.toRadixString(16)}');
      }
    }
    expect(problems, isEmpty);
  });

  test('special mappings, ASCII, and text', () {
    expect(upperCase('straße'), 'STRASSE');
    expect(upperCase('ŉ'), 'ʼN');
    expect(lowerCase('İ'), 'i̇');
    expect(upperCase('Hello, World'), 'HELLO, WORLD');
    expect(lowerCase('ΣΟΦΟΣ ΣΟΦΟΣ'), 'σοφοσ σοφοσ');
    expect(lowerCase('ΣΟΦΟΣ ΣΟΦΟΣ.', finalSigma: true), 'σοφος σοφος.');
  });

  test('Final_Sigma: a cased letter before, none after, marks skipped', () {
    expect(lowerCase('Σ', finalSigma: true), 'σ'); // nothing before
    expect(lowerCase('AΣ', finalSigma: true), 'aς');
    expect(lowerCase('AΣB', finalSigma: true), 'aσb');
    expect(lowerCase('AΣ́', finalSigma: true), 'aς́');
    expect(lowerCase('ÁΣ', finalSigma: true), 'áς');
    expect(lowerCase("AΣ'B", finalSigma: true), "aσ'b");
    expect(isCased(0x41), isTrue);
    expect(isCaseIgnorable(0x301), isTrue);
    expect(isCased(0x31), isFalse);
  });

  test(
    "JavaScript's toUpperCase and toLowerCase (Node.js), every code point",
    () {
      final node = Process.runSync('node', [
        '-e',
        _nodeMappings,
      ], stdoutEncoding: utf8);
      expect(node.exitCode, 0, reason: '${node.stderr}');
      final js = <int, (String, String)>{};
      String text(String hex) => String.fromCharCodes([
        for (final c in hex.split('.')) int.parse(c, radix: 16),
      ]);
      for (final line in const LineSplitter().convert('${node.stdout}')) {
        final [cp, upper, lower] = line.split(' ');
        js[int.parse(cp, radix: 16)] = (text(upper), text(lower));
      }
      final problems = <String>[];
      for (var cp = 0x80; cp <= 0x10ffff; cp++) {
        if (!_isScalar(cp)) continue;
        final char = String.fromCharCode(cp);
        final (up, down) = js[cp] ?? (char, char);
        // A lone capital sigma: JavaScript applies Final_Sigma (there is
        // no letter before, so σ).
        if (upperCase(char) != up ||
            lowerCase(char, finalSigma: true) != down) {
          problems.add('U+${cp.toRadixString(16)}');
        }
      }
      expect(problems, isEmpty);
      // Final_Sigma in context, against JavaScript.
      const samples = ['ΣΟΦΟΣ ΣΟΦΟΣ.', 'AΣ́ b', 'ÁΣ', "AΣ'B", 'ΑΣ.Σ', '·Σ'];
      final context = Process.runSync('node', [
        '-e',
        _nodeLowerCase,
        jsonEncode(samples),
      ], stdoutEncoding: utf8);
      expect([
        for (final s in samples) lowerCase(s, finalSigma: true),
      ], jsonDecode('${context.stdout}'));
    },
    skip: _has('node') ? false : 'Node.js is not installed',
    tags: ['tools'],
  );
}
