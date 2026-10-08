/// What the matchers skip by (`lib/src/first_chars.dart`) holds for every
/// rule of every language: on upstream's markup and detection samples, at
/// every position where a rule matches, its first characters have the
/// character there (or the end), a rule that starts words is at one, and
/// where a rule that starts with a run doesn't match, it doesn't match
/// further into the run either.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_highlighting/src/compiler_extensions.dart' as ext;
import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/highlighter.dart';
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/mode_compiler.dart';
import 'package:test/test.dart';

/// The sources of the rules of [mode] and of the modes it contains (what
/// their matchers search for).
Set<String> _rules(Mode mode, [Set<Mode>? seen]) {
  final visited = seen ?? <Mode>{};
  final rules = <String>{};
  if (!visited.add(mode)) return rules;
  for (final term in mode.contains ?? const <ContainsEntry>[]) {
    if (term is! Mode) continue;
    if (ext.sourceOf(term.begin) case final begin?) rules.add(begin);
    rules.addAll(_rules(term, visited));
  }
  if (mode.terminatorEnd case final end? when end.isNotEmpty) rules.add(end);
  if (ext.truthy(mode.illegal)) rules.add(ext.sourceOf(mode.illegal)!);
  if (mode.starts case final starts?) rules.addAll(_rules(starts, visited));
  return rules;
}

/// The samples of [language] in upstream's tests.
List<String> _samples(String language) => [
  for (final dir in [
    Directory('vendor/highlight.js/test/markup/$language'),
    Directory('vendor/highlight.js/test/detect/$language'),
  ])
    if (dir.existsSync())
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.txt') && !file.path.endsWith('.expect.txt'))
          file.readAsStringSync(),
];

void main() {
  test('first characters of a few expressions', () {
    FirstChars? read(String source, {bool ignoreCase = false}) =>
        firstChars(source, ignoreCase: ignoreCase);
    String chars(FirstChars? first) => String.fromCharCodes([
      for (var c = 32; c < 127; c++)
        if (first!.has(c)) c,
    ]);
    expect(chars(read('abc|[x-z]d')), 'axyz');
    expect(chars(read('(?:a?b|c)')), 'abc');
    expect(chars(read('a', ignoreCase: true)), 'Aa');
    expect(chars(read(r'(?=\d)\w+')), '0123456789');
    expect(read(r'\d*'), isNull, reason: 'matches empty');
    expect(read('(?<=x)'), isNull, reason: 'matches empty');
    expect(read(r'\b|\B'), isNull, reason: 'matches empty');
    expect(read(r'\p{L}'), isNull, reason: 'not read');
    expect(read(r'$')!.atEnd, isTrue);
    expect(read('[^a]')!.nonAscii, isTrue);
    expect(read('[^a]')!.has(0x61), isFalse);
    expect(read(r'[\w-]')!.has(0x2d), isTrue);
    expect(read(r'\b(if|else)\b')!.wordStart, isTrue);
    expect(read(r'(\b|x)y')!.wordStart, isFalse);
    expect(read(r'\b\.')!.wordStart, isFalse);
    expect(read(r'[a-z]\w*\(')!.run, isNotNull);
    expect(read(r'(\w+)\s*=')!.run, isNotNull);
    expect(read(r'\w[a-z]*'), isNotNull);
    expect(read(r'\w[a-z]*')!.run, isNull, reason: r'\w is not in [a-z]');
    expect(read(r'(\w+)=\1')!.run, isNull, reason: 'backreference');
    expect(read(r'(?=\w+)x')!.run, isNull, reason: 'lookahead');
  });

  test('every rule of every language, on the samples', () {
    final engine = Engine();
    for (final (name, aliases, build) in allLanguages) {
      engine.registerLanguage(name, build, aliases: aliases);
    }
    var checked = 0;
    for (final name in engine.languageNames) {
      final language = engine.getLanguage(name)!;
      if (language.unicodeRegex) continue;
      final samples = _samples(name);
      if (samples.isEmpty) continue;
      final ignoreCase = language.caseInsensitive;
      for (final source in _rules(compileLanguage(language))) {
        final first = firstChars(source, ignoreCase: ignoreCase);
        if (first == null) continue;
        final re = RegExp(source, multiLine: true, caseSensitive: !ignoreCase);
        final run = first.run;
        bool inRun(String text, int at) {
          if (run == null || at >= text.length) return false;
          final c = text.codeUnitAt(at);
          return c < 128 && run[c] != 0;
        }

        for (final text in samples) {
          // Where the rule didn't match at the start of a run, until the
          // run's end.
          var missedUntil = -1;
          for (var at = 0; at <= text.length; at++) {
            final matched = re.matchAsPrefix(text, at) != null;
            if (!inRun(text, at)) missedUntil = -1;
            if (!matched) {
              if (missedUntil < 0 && inRun(text, at)) missedUntil = at;
              continue;
            }
            final where = '$name: /$source/ at $at';
            expect(missedUntil, -1, reason: '$where, in a run it missed');
            if (at == text.length) {
              expect(first.atEnd, isTrue, reason: where);
              continue;
            }
            final c = text.codeUnitAt(at);
            expect(
              c < 128 ? first.has(c) : first.nonAscii,
              isTrue,
              reason: where,
            );
            if (first.wordStart && at > 0) {
              expect(
                isWordChar(text.codeUnitAt(at - 1)),
                isFalse,
                reason: where,
              );
            }
            checked++;
          }
        }
      }
    }
    expect(checked, greaterThan(10000));
  });
}
