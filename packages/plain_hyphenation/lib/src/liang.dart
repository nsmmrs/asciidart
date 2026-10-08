/// Hyphenation by Liang's algorithm over TeX patterns (Franklin Liang,
/// "Word Hy-phen-a-tion by Com-put-er", 1983), the patterns hyph-utf8
/// distributes for many languages.
library;

import 'dart:typed_data';

import 'package:plain_hyphenation/src/trie.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// The hyphenator of the patterns [PatternTrie.encode] wrote to [trie],
/// with [exceptions] (see [PatternHyphenator.new]): how the package loads
/// its languages, without parsing the patterns.
PatternHyphenator compiledHyphenator(
  Uint8List trie, {
  required String exceptions,
  required int left,
  required int right,
}) => PatternHyphenator._(PatternTrie.decode(trie), exceptions, left, right);

/// A hyphenator of TeX hyphenation patterns (`.hy1p`, `a1b2c`...:
/// letters with digits between them, dots for the word's ends) and
/// exceptions (words hyphenated by hand: `as-so-ciate`).
///
/// A word is hyphenated where the highest digit of the patterns that match
/// around a place is odd, keeping at least [left] letters before the first
/// hyphen and [right] after the last (TeX's `\lefthyphenmin` and
/// `\righthyphenmin`).
final class PatternHyphenator {
  /// A hyphenator of [patterns] and [exceptions] (both separated by
  /// whitespace).
  new(String patterns, {String exceptions = '', int left = 2, int right = 3})
    : this._(PatternTrie.parse(patterns), exceptions, left, right);

  new _(this._trie, String exceptions, this.left, this.right) {
    for (final exception in exceptions.split(_whitespace)) {
      if (exception.isEmpty || exception.startsWith('%')) continue;
      final positions = <int>[];
      var length = 0;
      for (final rune in exception.runes) {
        if (rune == 0x2d) {
          positions.add(length);
        } else {
          length++;
        }
      }
      _exceptions[exception.replaceAll('-', '').toLowerCase()] = positions;
    }
  }

  /// The fewest letters before a hyphen.
  final int left;

  /// The fewest letters after a hyphen.
  final int right;

  final PatternTrie _trie;
  final Map<String, List<int>> _exceptions = {};
  final Map<String, List<int>> _cache = {};

  // The word's letters between dots, and the value of the gap before each
  // (reused from word to word).
  Uint16List _work = Uint16List(64);
  Uint8List _values = Uint8List(65);

  /// Whether there are any patterns.
  bool get isEmpty => !_trie.hasPatterns && _exceptions.isEmpty;

  /// The places [word] may be hyphenated: the number of letters before
  /// each hyphen.
  List<int> hyphenate(String word) => _cache[word] ??= _hyphenate(word);

  List<int> _hyphenate(String word) {
    final trie = _trie;
    final pageOf = trie.pageOf;
    final pages = trie.pages;
    final latin = pageOf[0] << 8;
    // The letters of the word in lower case (as String.toLowerCase has
    // them: ASCII here, any other in the loop below), from work[1].
    var length = word.length;
    _reserve(length);
    var work = _work;
    String? lower;
    for (var i = 0; i < length; i++) {
      var c = word.codeUnitAt(i);
      if (c >= 0x80) {
        lower = word.toLowerCase();
        break;
      }
      if (c >= 0x41 && c <= 0x5a) c |= 0x20;
      work[i + 1] = pages[latin + c];
    }
    if (lower != null) {
      _reserve(lower.length);
      work = _work;
      length = 0;
      for (var k = 0; k < lower.length; k++) {
        var c = lower.codeUnitAt(k);
        if (c & 0xfc00 == 0xd800 && k + 1 < lower.length) {
          final low = lower.codeUnitAt(k + 1);
          if (low & 0xfc00 == 0xdc00) {
            c = 0x10000 + ((c & 0x3ff) << 10) + (low & 0x3ff);
            k++;
          }
        }
        work[++length] = pages[pageOf[c >> 8] << 8 | c & 0xff];
      }
    }
    final n = length;
    if (n < left + right) return const [];
    if (_exceptions.isNotEmpty) {
      if (_exceptions[lower ?? word.toLowerCase()] case final positions?) {
        return [
          for (final p in positions)
            if (p >= left && n - p >= right) p,
        ];
      }
    }
    // Each pattern that matches from work[i] raises the gaps it has
    // digits for; values[g] is the value of the gap before work[g].
    final end = n + 2;
    work[0] = work[n + 1] = pages[latin + 0x2e];
    final values = _values..fillRange(0, end + 1, 0);
    final root = trie.root;
    final first = trie.first;
    final letters = trie.letters;
    final digitsOf = trie.digitsOf;
    final shifts = trie.shifts;
    final digitStarts = trie.digitStarts;
    final digits = trie.digits;
    for (var i = 0; i < end; i++) {
      var v = root[work[i]];
      var j = i;
      while (v != 0) {
        final id = digitsOf[v];
        if (id != 0) {
          var g = i + shifts[id];
          for (var k = digitStarts[id]; k < digitStarts[id + 1]; k++, g++) {
            final digit = digits[k];
            if (digit > values[g]) values[g] = digit;
          }
        }
        if (++j == end) break;
        final letter = work[j];
        var e = first[v];
        final last = first[v + 1];
        v = 0;
        for (; e < last; e++) {
          final edge = letters[e];
          if (edge >= letter) {
            if (edge == letter) v = e + 1;
            break;
          }
        }
      }
    }
    // The gap before the word's letter p is the gap before work[p + 1].
    return [
      for (var p = left; p <= n - right; p++)
        if (values[p + 1].isOdd) p,
    ];
  }

  /// Makes the scratch buffers hold a word of [length] letters.
  void _reserve(int length) {
    if (_work.length >= length + 2) return;
    _work = Uint16List(length * 2 + 2);
    _values = Uint8List(length * 2 + 3);
  }
}
