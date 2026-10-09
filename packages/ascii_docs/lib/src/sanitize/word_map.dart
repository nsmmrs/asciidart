/// The shape-preserving word replacement: each word becomes a pseudo-word
/// of the same length, case pattern and script, chosen by a hash of the
/// lowercased word, so the same word maps the same way everywhere (titles,
/// the IDs generated from them, cross references, includes).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A range of letters a letter is replaced within, so a letter keeps its
/// script and kind (accented stays accented, kana stays kana).
final class _Alphabet {
  const _Alphabet(this.from, this.to, {this.step = 1, this.skip = const {}});

  final int from;
  final int to;
  final int step;
  final Set<int> skip;

  bool contains(int rune) =>
      rune >= from &&
      rune <= to &&
      (rune - from) % step == 0 &&
      !skip.contains(rune);

  int pick(int n) {
    final size = (to - from) ~/ step + 1;
    for (var i = 0; i < size; i++) {
      final rune = from + ((n + i) % size) * step;
      if (!skip.contains(rune)) return rune;
    }
    return from;
  }
}

const _alphabets = [
  _Alphabet(0x61, 0x7A), // a-z
  _Alphabet(0xE0, 0xFE, skip: {0xF7}), // à-þ (not ÷)
  _Alphabet(
    0x101,
    0x17F,
    step: 2,
    skip: {0x131, 0x138, 0x149, 0x17F},
  ), // Latin Extended-A lowercase
  _Alphabet(0x3B1, 0x3C9, skip: {0x3C2}), // Greek lowercase (not final sigma)
  _Alphabet(0x430, 0x44F), // Cyrillic lowercase
  _Alphabet(0x5D0, 0x5EA), // Hebrew
  _Alphabet(
    0x628,
    0x64A,
    skip: {0x63B, 0x63C, 0x63D, 0x63E, 0x63F, 0x640},
  ), // Arabic
  _Alphabet(0xE01, 0xE2E), // Thai consonants
  _Alphabet(0x3041, 0x3096), // Hiragana
  _Alphabet(0x30A1, 0x30FA), // Katakana
  _Alphabet(0x4E00, 0x9FFF), // CJK unified ideographs
  _Alphabet(0xAC00, 0xD7A3), // Hangul syllables
];

/// Words a replacement must never become: AsciiDoc gives them meaning in
/// prose positions (admonition labels, macro names, URL schemes, values).
const reservedWords = {
  'note', 'tip', 'important', 'warning', 'caution', //
  'link', 'mailto', 'image', 'include', 'xref', 'footnote', 'footnoteref',
  'kbd', 'btn', 'menu', 'pass', 'stem', 'latexmath', 'asciimath',
  'indexterm', 'indexterm2', 'anchor', 'video', 'audio', 'toc', 'icon',
  'ifdef', 'ifndef', 'ifeval', 'endif', 'http', 'https', 'ftp', 'irc',
  'file', 'true', 'false', 'nil', 'null', 'tag', 'end', 'set',
  'counter', 'counter2', 'abstract', 'partintro', 'preface', 'appendix',
  'glossary', 'bibliography', 'index', 'colophon', 'dedication',
};

/// A rune kept as it is: its case mapping isn't one to one (ß, İ, ı,
/// ligatures), it combines, or it belongs to no known alphabet.
bool _keep(int rune) {
  final s = String.fromCharCode(rune);
  final lower = s.toLowerCase();
  final upper = s.toUpperCase();
  if (lower.runes.length != 1 || upper.runes.length != 1) return true;
  final l = lower.runes.single;
  return !_alphabets.any((a) => a.contains(l));
}

bool _isUpper(int rune) {
  final s = String.fromCharCode(rune);
  return s.toUpperCase() == s && s.toLowerCase() != s;
}

final class WordMap {
  WordMap({this.salt = 'ascii-docs/1'});

  /// A map that is one to one over [vocabulary] (the words of one document
  /// and the files it includes): no two of its words share a replacement,
  /// and no replacement is itself one of its words. Assignments go in
  /// sorted order, so the result depends only on the vocabulary.
  WordMap.forVocabulary(
    Iterable<String> vocabulary, {
    this.salt = 'ascii-docs/1',
  }) {
    final words = {
      for (final w in vocabulary)
        if (w.runes.length > 2) w.toLowerCase(),
    }.toList()..sort();
    final originals = words.toSet();
    final used = <String>{};
    for (final word in words) {
      for (var attempt = 0; ; attempt++) {
        final candidate = _scramble(word, from: attempt * 17);
        final free =
            !used.contains(candidate) &&
            (candidate == word || !originals.contains(candidate));
        if (free || attempt > 64) {
          used.add(candidate);
          _cache[word] = candidate;
          break;
        }
      }
    }
  }

  /// Changing the salt changes every replacement.
  final String salt;
  final Map<String, String> _cache = {};

  /// The replacement of [word] (a run of letters). Words of one or two
  /// letters stay (a, of, I, (C), (TM): not expression, and often syntax).
  String operator [](String word) {
    if (word.runes.length <= 2) return word;
    final lower = word.toLowerCase();
    final base = _cache[lower] ??= _scramble(lower);
    // Reapply the word's own case pattern, letter by letter.
    final out = StringBuffer();
    final original = word.runes.toList();
    final replaced = base.runes.toList();
    if (original.length != replaced.length) return base;
    for (var i = 0; i < original.length; i++) {
      final r = String.fromCharCode(replaced[i]);
      out.write(_isUpper(original[i]) ? r.toUpperCase() : r);
    }
    return out.toString();
  }

  String _scramble(String lower, {int from = 0}) {
    for (var attempt = from; ; attempt++) {
      final digest = sha256
          .convert(utf8.encode('$salt\u0000$lower\u0000$attempt'))
          .bytes;
      var i = 0;
      int next() {
        final n =
            digest[i % digest.length] << 8 | digest[(i + 7) % digest.length];
        i++;
        return n + i * 31;
      }

      final out = StringBuffer();
      for (final rune in lower.runes) {
        if (_keep(rune)) {
          out.writeCharCode(rune);
          continue;
        }
        final alphabet = _alphabets.firstWhere((a) => a.contains(rune));
        out.writeCharCode(alphabet.pick(next()));
      }
      final candidate = out.toString();
      if (candidate == lower && lower.runes.every(_keep)) return candidate;
      if (candidate != lower && !reservedWords.contains(candidate))
        return candidate;
      if (attempt > from + 16) return candidate;
    }
  }

  /// Every word replaced so far, lowercased, with its replacement.
  Map<String, String> get replacements => Map.unmodifiable(_cache);
}

/// A run of letters (with combining marks), the unit [WordMap] replaces.
final wordPattern = RegExp(r'[\p{L}\p{M}]+', unicode: true);

/// [text] with every letter run replaced, and runs that [keep] accepts left.
String scrambleWords(
  String text,
  WordMap map, {
  bool Function(String word)? keep,
}) => text.replaceAllMapped(wordPattern, (m) {
  final word = m[0]!;
  return keep != null && keep(word) ? word : map[word];
});

/// The letter-class shape of [text]: every letter becomes `a`/`A` (by case)
/// or `x` (caseless), everything else stays. A sanitized document whose
/// output has the original output's shape converted the same way.
String shapeOf(String text) => text.replaceAllMapped(wordPattern, (m) {
  final out = StringBuffer();
  for (final rune in m[0]!.runes) {
    final s = String.fromCharCode(rune);
    if (s.toUpperCase() != s.toLowerCase()) {
      out.write(_isUpper(rune) ? 'A' : 'a');
    } else {
      out.write('x');
    }
  }
  return out.toString();
});
