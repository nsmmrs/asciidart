/// Keywords are found without the keyword pattern when it is `\w+`
/// ([Mode.keywordsAreWords]): runs of [isWordChar] are exactly the
/// pattern's matches, on random text, with the flags such modes have.
library;

import 'dart:math';

import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/grammar.dart';
import 'package:plain_highlighting/src/highlighter.dart';
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/mode_compiler.dart';
import 'package:test/test.dart';

/// The runs of word characters in [text], as `start-end`.
List<String> _runs(String text) {
  final runs = <String>[];
  var i = 0;
  while (i < text.length) {
    if (!isWordChar(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    final start = i;
    while (i < text.length && isWordChar(text.codeUnitAt(i))) {
      i++;
    }
    runs.add('$start-$i');
  }
  return runs;
}

/// Random text of word characters, others, and the characters that
/// Unicode case folding relates to word characters (ſ, K).
String _text(Random random) {
  const pool = 'aZ_09 .\t\n-(éſKıİßΣ\u{1F600}';
  final chars = pool.runes.toList();
  return String.fromCharCodes([
    for (var i = random.nextInt(40); i > 0; i--)
      chars[random.nextInt(chars.length)],
  ]);
}

void main() {
  test(r'word runs are the matches of \w+', () {
    final random = Random(7);
    for (final (unicode, ignoreCase) in [
      (false, false),
      (false, true),
      (true, false),
    ]) {
      final re = RegExp(
        r'\w+',
        multiLine: true,
        caseSensitive: !ignoreCase,
        unicode: unicode,
      );
      for (var n = 0; n < 5000; n++) {
        final text = _text(random);
        expect(_runs(text), [
          for (final m in re.allMatches(text)) '${m.start}-${m.end}',
        ], reason: '${(unicode, ignoreCase)}: ${text.runes.toList()}');
      }
    }
    // Not so in a language both Unicode and case-insensitive.
    final both = RegExp(r'\w+', unicode: true, caseSensitive: false);
    expect(both.hasMatch('ſ'), isTrue);
  });

  test(r'every mode of every language that scans words has `\w+`', () {
    final engine = Engine();
    for (final (name, aliases, at) in allLanguages) {
      engine.registerLanguage(name, () => readGrammar(at), aliases: aliases);
    }
    var scanned = 0;
    for (final name in engine.languageNames) {
      final language = engine.getLanguage(name)!;
      final seen = <Mode>{};
      void visit(Mode mode) {
        if (!seen.add(mode)) return;
        final re = mode.keywordPatternRe!;
        expect(
          mode.keywordsAreWords,
          re.pattern == r'\w+' && !(re.isUnicode && !re.isCaseSensitive),
          reason: '$name: /${re.pattern}/',
        );
        if (mode.keywordsAreWords) scanned++;
        for (final c in mode.contains ?? const <ContainsEntry>[]) {
          if (c is Mode) visit(c);
        }
        if (mode.starts case final starts?) visit(starts);
      }

      visit(compileLanguage(language));
    }
    expect(scanned, greaterThan(1000));
  });
}
