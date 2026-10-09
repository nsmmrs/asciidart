/// What the matchers skip by (`lib/src/first_chars.dart`) holds for every
/// rule of every language: on upstream's markup and detection samples, at
/// every position where a rule matches, its first characters have the
/// character there (or the end), a rule that starts words is at one,
/// where a rule that starts with a run doesn't match, it doesn't match
/// further into the run either, and every filter the matcher applies
/// before trying a rule (line starts, literal prefixes, what follows a
/// run) lets the rule be tried; a literal rule matches exactly where its
/// literal is. The group counts the matcher keeps are the engine's.
///
/// Both tests take every rule of every language, as their matchers
/// search for them.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_highlighting/src/compiler_extensions.dart' as ext;
import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/grammar.dart';
import 'package:plain_highlighting/src/highlighter.dart';
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/mode_compiler.dart';
import 'package:plain_highlighting/src/regex.dart' as regex;
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

/// Text with what Unicode mode reads differently: `ſ` and `K` (U+212A),
/// which fold to `s` and `k`, and surrogate pairs.
const String _beyondAscii =
    'ſ K ſtyle <ſcript> Kelvin \u{1F600}x y\u{1F600} "\u{1F600}" é\n'
    '<\u{1F600}a>def \u{10400}x(): \u{1F600}';

/// Whether [at] is inside a surrogate pair of [text].
bool _inPair(String text, int at) =>
    at > 0 &&
    at < text.length &&
    (text.codeUnitAt(at) & 0xfc00) == 0xdc00 &&
    (text.codeUnitAt(at - 1) & 0xfc00) == 0xd800;

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

  test('what follows a run', () {
    RunFollow? follow(String source, {bool ignoreCase = false}) =>
        firstChars(source, ignoreCase: ignoreCase)!.follow;
    final generic = follow(r'([a-z]\w*)(\s*<)')!;
    expect(generic.admits('abc<', 0), isTrue);
    expect(generic.admits('abc  <', 0), isTrue);
    expect(generic.admits('abc.', 0), isFalse);
    expect(generic.admits('abc', 0), isFalse, reason: 'the end');
    expect(generic.admits('abcé', 0), isTrue, reason: r'\s has more');
    expect(follow(r'\w+$')!.admits('ab', 0), isTrue);
    expect(follow(r'\w+$')!.admits('ab\n', 0), isTrue);
    expect(follow(r'\w+$')!.admits('ab.', 0), isFalse);
    expect(follow('[a-z]+x', ignoreCase: true), isNull, reason: 'x in it');
    expect(follow('[^"]+"')!.admits('aé"', 0), isTrue, reason: 'unseen');
    expect(follow(r'a[b-z]+\(')!.admits('ab-', 0), isFalse);
    expect(follow(r'\.\d+[eE]')!.admits('.12e', 0), isTrue);
    expect(follow(r'\.\d+[eE]')!.admits('.12+', 0), isFalse);
    expect(follow(r'\w+'), isNull, reason: 'nothing follows');
    expect(follow(r'\w+\s*'), isNull, reason: 'the rest can be empty');
    expect(follow(r'\w+\d'), isNull, reason: 'the rest can start the run');
    expect(follow(r'(?=\w+)x'), isNull, reason: 'lookahead');
    expect(follow(r'(\w)+x'), isNull, reason: 'a quantified group');
    expect(follow(r'(\w+)=\1'), isNull, reason: 'backreference');
    expect(follow(r'\w*x'), isNull, reason: 'the run can be empty');
    expect(follow(r'(\w+)\s*=')!.admits('ab =', 0), isTrue);
    expect(follow(r'(?:[a-z]\w*)\s*=')!.admits('ab+', 0), isFalse);
    expect(follow(r'\w+|x'), isNull, reason: 'alternatives');
  });

  test('first characters in Unicode mode', () {
    // Each expression, alone, against characters ASCII and beyond: where
    // the engine matches one, the first characters have it.
    const sources = [
      r'\w',
      r'\W',
      r'\s',
      r'\S',
      r'\d',
      r'\D',
      r'\b\w',
      '.',
      's',
      'K',
      'x',
      '[^s]',
      '[ſ]',
      '[\u0100-\u0200]',
      r'[\u{212A}]',
      r'\u{17F}',
      r'\p{L}',
      r'\P{L}',
      r'[^\p{L}]',
      r'\p{Lu}',
      r'\P{Lu}',
      r'[\p{L}0-9._:-]+',
      r'\p{XID_Start}',
      r'[^\P{Ll}]',
      r'[\w-]',
    ];
    final chars = [
      for (var c = 0; c < 128; c++) c,
      0xe9,
      0x17f,
      0x212a,
      0x130,
      0x131,
      0x3a3,
      0x2028,
      0x10400,
      0x1f600,
    ];
    var read = 0;
    for (final ignoreCase in [false, true]) {
      for (final source in sources) {
        final first = firstChars(source, ignoreCase: ignoreCase, unicode: true);
        if (first == null) continue;
        read++;
        final re = RegExp(source, unicode: true, caseSensitive: !ignoreCase);
        for (final c in chars) {
          if (re.matchAsPrefix(String.fromCharCode(c)) == null) continue;
          expect(
            c < 128 ? first.has(c) : first.nonAscii,
            isTrue,
            reason: '/$source/${ignoreCase ? 'i' : ''} on $c',
          );
        }
      }
    }
    expect(read, sources.length * 2);
    expect(
      firstChars('\u{1F600}', ignoreCase: false, unicode: true),
      isNull,
      reason: 'a surrogate pair is one character',
    );
    expect(
      firstChars('style', ignoreCase: true, unicode: true)!.prefix,
      isNull,
      reason: 'ſ',
    );
    expect(firstChars('<!--', ignoreCase: true, unicode: true)!.prefix, '<!--');
  });

  test('what ends a span', () {
    Stop? stop(String source) => firstChars(source, ignoreCase: false)!.stop;
    final method = stop(r'([a-z]\w*)((?:\s*<[a-z]+>)?\s+)([a-z]+)(\s*(?=\())')!;
    expect(method.admits('void main(', 0), isTrue);
    expect(method.admits('List<T> f (', 0), isTrue);
    expect(method.admits('return x;', 0), isFalse);
    expect(method.admits('int x = 1', 0), isFalse);
    expect(method.admits('a b', 0), isFalse, reason: 'the end');
    final variable = stop(r'([a-z]+)(\s+)([a-z]+)(\s*)(=(?!=))')!;
    expect(variable.admits('int x = 1', 0), isTrue);
    expect(variable.admits('return x;', 0), isFalse);
    expect(stop('[a-z]+[a-z0-9]'), isNull, reason: 'not disjoint');
    expect(stop(r'[a-z]+\s*'), isNull, reason: 'the rest can be empty');
    expect(stop('[a-z]|x'), isNull, reason: 'alternatives');
    expect(stop(r'\w+(?:\s*,)*;')!.admits('a , b.', 0), isFalse);
    expect(stop(r'\w+(?:\s*,)*;')!.admits('ab ,,;', 0), isTrue);
    expect(stop('[^"]+"')!.admits('aé"', 0), isTrue, reason: 'unseen');
  });

  test('literals a few characters in', () {
    Anchor? anchor(String source, {bool ignoreCase = false}) =>
        firstChars(source, ignoreCase: ignoreCase)!.anchor;
    final html = anchor('.?html`')!;
    expect(html, (literal: 'html`', min: 0, max: 1));
    expect(anchorAdmits(html, 'xhtml`', 0), isTrue);
    expect(anchorAdmits(html, 'html`', 0), isTrue);
    expect(anchorAdmits(html, 'xyhtml`', 0), isFalse);
    expect(anchor(r'\b.x?abc'), (literal: 'abc', min: 1, max: 2));
    expect(anchor('.?ab'), isNull, reason: 'too short');
    expect(anchor('html`'), isNull, reason: 'a prefix');
    expect(anchor('.*html`'), isNull, reason: 'unbounded');
    expect(anchor('(?:x|y)html`'), isNull, reason: 'a group');
    expect(anchor('.?HTML', ignoreCase: true), isNull, reason: 'case');
    expect(anchor('.?h|.?html`'), isNull, reason: 'alternatives');
    expect(anchor('(?=.?html`)x'), isNull, reason: 'lookahead');
  });

  test('line starts, literals and empty matches', () {
    FirstChars read(String source, {bool ignoreCase = false}) =>
        firstChars(source, ignoreCase: ignoreCase)!;
    expect(read(r'^\$ ').lineStart, isTrue);
    expect(read('^a|^b').lineStart, isTrue);
    expect(read('(?:^a)b').lineStart, isTrue);
    expect(read('^a|b').lineStart, isFalse);
    expect(read('^?a').lineStart, isFalse);
    expect(read(r'\b^a').lineStart, isFalse);
    expect(read('^a').admitsLine('x\na', 2), isTrue);
    expect(read('^a').admitsLine('x\u2028a', 2), isTrue);
    expect(read('^a').admitsLine('xa', 1), isFalse);
    expect(read('^a').admitsLine('a', 0), isTrue);

    expect(read(r'import java\.').prefix, 'import java.');
    expect(read(r'import java\.').literal, isTrue);
    expect(read(r'(record)(\s+)').prefix, 'record');
    expect(read(r'(record)(\s+)').literal, isFalse);
    expect(read(r'\bif\b').prefix, 'if');
    expect(read(r'\bif\b').literal, isFalse, reason: 'assertions');
    expect(read('if(?!x)').literal, isFalse, reason: 'assertions');
    expect(read('if(?=x)').prefix, 'if');
    expect(read('if(?=x)').literal, isFalse);
    expect(read('(?=ab)abc').prefix, isNull, reason: 'lookahead');
    expect(read('ab?c').prefix, isNull, reason: 'one character');
    expect(read('a').prefix, 'a', reason: 'a literal');
    expect(read('a').literal, isTrue);
    expect(read('a+').prefix, isNull);
    expect(read('ab|ac').prefix, isNull, reason: 'alternatives');
    expect(read('(?:ab|ac)d').prefix, isNull, reason: 'alternatives');
    expect(read('"\u00e9b').prefix, isNull, reason: 'beyond ASCII');
    expect(read('Non-Sealed', ignoreCase: true).prefix, 'non-sealed');
    expect(
      read('Non-Sealed', ignoreCase: true).admitsPrefix('NON-SEALED;', 0),
      isTrue,
    );
    expect(read('Non-Sealed').admitsPrefix('NON-SEALED;', 0), isFalse);
    expect(read('ab').admitsPrefix('xa', 1), isFalse, reason: 'the end');

    expect(matchesEmptyEverywhere(r'\B|\b'), isTrue);
    expect(matchesEmptyEverywhere(r'\B|\b|\)'), isTrue);
    expect(matchesEmptyEverywhere(r'\b|\B'), isFalse, reason: 'not read');
    expect(matchesEmptyEverywhere(r'\B'), isFalse);
  });

  test('every rule of every language, on the samples', () {
    final engine = Engine();
    for (final (name, aliases, at) in allLanguages) {
      engine.registerLanguage(name, () => readGrammar(at), aliases: aliases);
    }
    var checked = 0;
    var followed = 0;
    var lined = 0;
    var prefixed = 0;
    var literals = 0;
    var anchored = 0;
    var stopped = 0;
    for (final name in engine.languageNames) {
      final language = engine.getLanguage(name)!;
      final samples = _samples(name);
      if (samples.isEmpty) continue;
      // (And what folds to ASCII, or is a surrogate pair, in Unicode mode.)
      samples.add(_beyondAscii);
      final ignoreCase = language.caseInsensitive;
      final unicode = language.unicodeRegex;
      for (final source in _rules(compileLanguage(language))) {
        if (matchesEmptyEverywhere(source)) {
          final re = RegExp(source, multiLine: true, unicode: unicode);
          for (final text in samples.take(1)) {
            for (var at = 0; at <= text.length; at++) {
              expect(re.matchAsPrefix(text, at)?[0], '', reason: source);
            }
          }
          continue;
        }
        final first = firstChars(
          source,
          ignoreCase: ignoreCase,
          unicode: unicode,
        );
        if (first == null) continue;
        final re = RegExp(
          source,
          multiLine: true,
          caseSensitive: !ignoreCase,
          unicode: unicode,
        );
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
            // (The matcher never tries one inside a pair in Unicode mode.)
            if (unicode && _inPair(text, at)) continue;
            final match = re.matchAsPrefix(text, at);
            final matched = match != null;
            if (first.literal) {
              final where = '$name: /$source/ at $at, literal';
              final prefix = first.prefix!;
              expect(first.admitsPrefix(text, at), matched, reason: where);
              if (matched) {
                expect(match.end - at, prefix.length, reason: where);
                literals++;
              }
            }
            if (!inRun(text, at)) missedUntil = -1;
            if (!matched) {
              if (missedUntil < 0 && inRun(text, at)) missedUntil = at;
              continue;
            }
            final where = '$name: /$source/ at $at';
            expect(missedUntil, -1, reason: '$where, in a run it missed');
            expect(first.admitsLine(text, at), isTrue, reason: '$where, ^');
            expect(first.admitsPrefix(text, at), isTrue, reason: where);
            if (first.lineStart) lined++;
            if (first.prefix != null) prefixed++;
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
            if (first.anchor case final anchor?) {
              expect(
                anchorAdmits(anchor, text, at),
                isTrue,
                reason: '$where, anchor',
              );
              anchored++;
            }
            if (first.stop case final stop?) {
              expect(stop.admits(text, at), isTrue, reason: '$where, stop');
              stopped++;
            }
            if (first.follow case final follow?) {
              expect(follow.admits(text, at), isTrue, reason: '$where, follow');
              followed++;
            }
            checked++;
          }
        }
      }
    }
    expect(checked, greaterThan(10000));
    expect(followed, greaterThan(1000));
    expect(lined, greaterThan(100));
    expect(prefixed, greaterThan(1000));
    expect(literals, greaterThan(1000));
    expect(anchored, greaterThan(0));
    expect(stopped, greaterThan(1000));
  });

  test('group counts', () {
    final engine = Engine();
    for (final (name, aliases, at) in allLanguages) {
      engine.registerLanguage(name, () => readGrammar(at), aliases: aliases);
    }
    for (final name in engine.languageNames) {
      final language = engine.getLanguage(name)!;
      for (final source in _rules(compileLanguage(language))) {
        // (An empty alternative makes it match the empty text.)
        final re = RegExp(
          '(?:$source)|',
          multiLine: true,
          caseSensitive: !language.caseInsensitive,
          unicode: language.unicodeRegex,
        );
        expect(
          regex.countMatchGroups(source),
          re.firstMatch('')!.groupCount,
          reason: '$name: /$source/',
        );
      }
    }
  });
}
