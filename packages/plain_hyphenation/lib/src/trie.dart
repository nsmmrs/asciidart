/// TeX hyphenation patterns compiled to a trie in typed arrays, and its
/// binary form: the generator compiles each language's patterns
/// (`tool/generate_patterns.dart`), and the package decodes them without
/// parsing any text.
library;

import 'dart:typed_data';

final RegExp _whitespace = RegExp(r'\s+');

/// The patterns of a language as a trie whose edges are letters: the
/// patterns that match at a place in a word are the nodes on the path its
/// letters take from the root.
///
/// The letters are numbered from 1 in code point order (0 is any other
/// character) and the nodes in breadth-first order, the root first, so a
/// node's children are consecutive: the edges of node `v` are
/// `first[v] ..< first[v + 1]`, sorted by letter, and edge `e` leads to
/// node `e + 1`. A node that ends a pattern names its digits, with the
/// zeros at either end trimmed; few languages have more than a few hundred
/// different ones.
final class PatternTrie {
  new _(
    Int32List alphabet,
    Int32List first,
    Uint16List letters,
    Int32List digitsOf,
    Int32List shifts,
    Int32List digitStarts,
    Uint8List digits,
  ) : this._paged(
        alphabet,
        first,
        letters,
        digitsOf,
        shifts,
        digitStarts,
        digits,
        _pages(alphabet),
      );

  new _paged(
    this.alphabet,
    this.first,
    this.letters,
    this.digitsOf,
    this.shifts,
    this.digitStarts,
    this.digits,
    (Uint16List, Uint16List) pages,
  ) : pageOf = pages.$1,
      pages = pages.$2,
      root = Int32List(alphabet.length + 1),
      hasPatterns = digitsOf.any((id) => id != 0) {
    for (var e = first[0]; e < first[1]; e++) {
      root[letters[e]] = e + 1;
    }
  }

  /// The trie of [patterns] (separated by whitespace): letters with digits
  /// between them (`.hy1p`, `a1b2c`), the last of any with the same
  /// letters winning.
  factory parse(String patterns) {
    // Every pattern's letters, one after another, and its digits.
    final letters = <int>[];
    final starts = <int>[];
    final vectors = <List<int>>[];
    final alphabet = <int>{};
    for (final pattern in patterns.split(_whitespace)) {
      if (pattern.isEmpty || pattern.startsWith('%')) continue;
      starts.add(letters.length);
      final vector = <int>[0];
      for (final rune in pattern.runes) {
        if (rune >= 0x30 && rune <= 0x39) {
          vector[vector.length - 1] = rune - 0x30;
        } else {
          letters.add(rune);
          alphabet.add(rune);
          vector.add(0);
        }
      }
      vectors.add(vector);
    }
    starts.add(letters.length);
    final sortedAlphabet = Int32List.fromList(alphabet.toList()..sort());
    if (sortedAlphabet.length > 0xffff) {
      throw ArgumentError.value(
        sortedAlphabet.length,
        'patterns',
        'more than 65,535 different letters',
      );
    }
    final codeOf = <int, int>{
      for (var k = 0; k < sortedAlphabet.length; k++) sortedAlphabet[k]: k + 1,
    };
    final codes = Uint16List(letters.length);
    for (var k = 0; k < letters.length; k++) {
      codes[k] = codeOf[letters[k]]!;
    }

    // The patterns in letter order, a prefix before the patterns it
    // starts, and of patterns with the same letters only the last.
    int compare(int a, int b) {
      final aEnd = starts[a + 1];
      final bEnd = starts[b + 1];
      for (var i = starts[a], j = starts[b]; ; i++, j++) {
        if (i == aEnd) return j == bEnd ? a - b : -1;
        if (j == bEnd) return 1;
        final d = codes[i] - codes[j];
        if (d != 0) return d;
      }
    }

    final order = List<int>.generate(vectors.length, (k) => k)..sort(compare);
    bool same(int a, int b) {
      final length = starts[a + 1] - starts[a];
      if (starts[b + 1] - starts[b] != length) return false;
      for (var k = 0; k < length; k++) {
        if (codes[starts[a] + k] != codes[starts[b] + k]) return false;
      }
      return true;
    }

    final sorted = [
      for (var k = 0; k < order.length; k++)
        if (k + 1 == order.length || !same(order[k], order[k + 1])) order[k],
    ];

    // Breadth first: each node is the range of sorted patterns that start
    // with its letters, depth letters long.
    final rangeStart = <int>[0];
    final rangeEnd = <int>[sorted.length];
    final depths = <int>[0];
    final first = <int>[];
    final edgeLetters = <int>[];
    final digitsOf = <int>[];
    final ids = <String, int>{};
    final shifts = <int>[0];
    final digitStarts = <int>[0, 0];
    final digits = <int>[];
    for (var v = 0; v < rangeStart.length; v++) {
      var lo = rangeStart[v];
      final hi = rangeEnd[v];
      final depth = depths[v];
      first.add(edgeLetters.length);
      var id = 0;
      if (lo < hi && starts[sorted[lo] + 1] - starts[sorted[lo]] == depth) {
        final vector = vectors[sorted[lo]];
        var from = 0;
        while (from < vector.length && vector[from] == 0) {
          from++;
        }
        var to = vector.length;
        while (to > from && vector[to - 1] == 0) {
          to--;
        }
        id = ids.putIfAbsent('$from ${vector.sublist(from, to).join()}', () {
          shifts.add(from);
          digits.addAll(vector.getRange(from, to));
          digitStarts.add(digits.length);
          return shifts.length - 1;
        });
        lo++;
      }
      digitsOf.add(id);
      while (lo < hi) {
        final code = codes[starts[sorted[lo]] + depth];
        var end = lo + 1;
        while (end < hi && codes[starts[sorted[end]] + depth] == code) {
          end++;
        }
        edgeLetters.add(code);
        rangeStart.add(lo);
        rangeEnd.add(end);
        depths.add(depth + 1);
        lo = end;
      }
    }
    first.add(edgeLetters.length);
    return PatternTrie._(
      sortedAlphabet,
      Int32List.fromList(first),
      Uint16List.fromList(edgeLetters),
      Int32List.fromList(digitsOf),
      Int32List.fromList(shifts),
      Int32List.fromList(digitStarts),
      Uint8List.fromList(digits),
    );
  }

  /// The trie that [encode] wrote to [bytes].
  factory decode(Uint8List bytes) {
    final reader = _Reader(bytes);
    final alphabet = Int32List(reader.next());
    for (var k = 0, letter = -1; k < alphabet.length; k++) {
      alphabet[k] = letter += reader.next() + 1;
    }
    final nodes = reader.next();
    final first = Int32List(nodes + 1);
    for (var v = 0; v < nodes; v++) {
      first[v + 1] = first[v] + reader.next();
    }
    final letters = Uint16List(first[nodes]);
    for (var v = 0; v < nodes; v++) {
      for (var e = first[v], letter = 0; e < first[v + 1]; e++) {
        letters[e] = letter += reader.next() + 1;
      }
    }
    final digitsOf = Int32List(nodes);
    for (var v = 0; v < nodes; v++) {
      digitsOf[v] = reader.next();
    }
    final vectors = reader.next();
    final shifts = Int32List(vectors + 1);
    final digitStarts = Int32List(vectors + 2);
    final digits = <int>[];
    for (var t = 1; t <= vectors; t++) {
      shifts[t] = reader.next();
      final length = reader.next();
      digits.addAll(reader.bytes(length));
      digitStarts[t + 1] = digitStarts[t] + length;
    }
    return PatternTrie._(
      alphabet,
      first,
      letters,
      digitsOf,
      shifts,
      digitStarts,
      Uint8List.fromList(digits),
    );
  }

  /// The page table of [alphabet] (see [pageOf]): a page of 256 code
  /// points for each that has letters, after page 0, which has none.
  static (Uint16List, Uint16List) _pages(Int32List alphabet) {
    final pageOf = Uint16List(0x1100);
    var count = 1;
    for (final letter in alphabet) {
      if (pageOf[letter >> 8] == 0) pageOf[letter >> 8] = count++;
    }
    final pages = Uint16List(count << 8);
    for (var k = 0; k < alphabet.length; k++) {
      final letter = alphabet[k];
      pages[pageOf[letter >> 8] << 8 | letter & 0xff] = k + 1;
    }
    return (pageOf, pages);
  }

  /// The letters, in code point order: letter `k` is `alphabet[k - 1]`.
  final Int32List alphabet;

  /// Where each node's edges start, and after the last node, where they
  /// end.
  final Int32List first;

  /// Each edge's letter.
  final Uint16List letters;

  /// Each node's digits: 0 for none, or a number from 1 for [shifts] and
  /// [digitStarts].
  final Int32List digitsOf;

  /// Each set of digits' place: the number of letters before the first.
  final Int32List shifts;

  /// Where each set of digits starts in [digits], and where the last ends.
  final Int32List digitStarts;

  /// The digits of every set, one after another, without their zeros at
  /// either end.
  final Uint8List digits;

  /// The child of the root for each letter, 0 for none (the root is no
  /// node's child).
  final Int32List root;

  /// The letter of each code point `c`:
  /// `pages[pageOf[c >> 8] << 8 | c & 0xff]`, 0 if it isn't one.
  final Uint16List pageOf;

  /// See [pageOf].
  final Uint16List pages;

  /// Whether there are any patterns (even one without letters, or without
  /// digits).
  final bool hasPatterns;

  /// The trie as bytes, for [PatternTrie.decode]: numbers as unsigned
  /// LEB128, the letters as the gaps between them, then each node's number
  /// of children, the children's letters as the gaps between siblings
  /// (from 0), each node's digits, and the sets of digits.
  Uint8List encode() {
    final out = _Writer()..add(alphabet.length);
    var previous = -1;
    for (final letter in alphabet) {
      out.add(letter - previous - 1);
      previous = letter;
    }
    final nodes = digitsOf.length;
    out.add(nodes);
    for (var v = 0; v < nodes; v++) {
      out.add(first[v + 1] - first[v]);
    }
    for (var v = 0; v < nodes; v++) {
      var previous = 0;
      for (var e = first[v]; e < first[v + 1]; e++) {
        out.add(letters[e] - previous - 1);
        previous = letters[e];
      }
    }
    digitsOf.forEach(out.add);
    out.add(shifts.length - 1);
    for (var t = 1; t < shifts.length; t++) {
      out
        ..add(shifts[t])
        ..add(digitStarts[t + 1] - digitStarts[t]);
      digits.getRange(digitStarts[t], digitStarts[t + 1]).forEach(out.byte);
    }
    return out.takeBytes();
  }
}

final class _Writer {
  final BytesBuilder _bytes = BytesBuilder();

  /// Writes [value] (not negative) as unsigned LEB128.
  void add(int value) {
    var rest = value;
    while (rest >= 0x80) {
      _bytes.addByte(rest & 0x7f | 0x80);
      rest >>= 7;
    }
    _bytes.addByte(rest);
  }

  void byte(int value) => _bytes.addByte(value);

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class _Reader {
  new(this._bytes);

  final Uint8List _bytes;
  int _at = 0;

  /// The next unsigned LEB128 number.
  int next() {
    var value = 0;
    for (var shift = 0; ; shift += 7) {
      final byte = _bytes[_at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
    }
  }

  /// The next [length] bytes.
  Uint8List bytes(int length) =>
      Uint8List.sublistView(_bytes, _at, _at += length);
}
