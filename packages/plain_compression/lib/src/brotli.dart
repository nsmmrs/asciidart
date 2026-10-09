/// A Brotli decoder (RFC 7932).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_compression/src/brotli_data.g.dart';
import 'package:plain_compression/src/flate.dart';

/// Expands the Brotli stream [data]; throws a [FormatException] when it is
/// malformed.
Uint8List brotliDecode(List<int> data) =>
    _Decoder(data is Uint8List ? data : Uint8List.fromList(data)).decode();

/// The static dictionary, expanded the first time it is needed.
final Uint8List _dictionary = zlibDecode(base64Decode(brotliDictionaryZlib));

/// The number of bits of the word index, by word length (RFC 7932,
/// section 8).
const List<int> _dictionaryBits = [
  0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, //
  9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5, 5,
];

/// Where the words of each length start in the dictionary.
final List<int> _dictionaryOffsets = () {
  final offsets = List.filled(25, 0);
  for (var length = 4; length < 24; length++) {
    offsets[length + 1] =
        offsets[length] + length * (1 << _dictionaryBits[length]);
  }
  return offsets;
}();

/// Insert lengths: the base and the extra bits of each code.
const List<int> _insertBase = [
  0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, //
  578, 1090, 2114, 6210, 22594,
];
const List<int> _insertExtra = [
  0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, //
  24,
];

/// Copy lengths: the base and the extra bits of each code.
const List<int> _copyBase = [
  2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, //
  198, 326, 582, 1094, 2118,
];
const List<int> _copyExtra = [
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  1,
  2,
  2,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  7,
  8,
  9,
  10,
  24,
];

/// The insert and copy length codes each cell of 64 insert-and-copy codes
/// starts at.
const List<int> _cellInsert = [0, 0, 0, 0, 8, 8, 0, 16, 8, 16, 16];
const List<int> _cellCopy = [0, 8, 0, 8, 0, 8, 16, 0, 16, 8, 16];

/// Block counts: the base and the extra bits of each code.
const List<int> _blockBase = [
  1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, //
  305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625,
];
const List<int> _blockExtra = [
  2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, //
  12, 13, 24,
];

/// The order code length code lengths come in.
const List<int> _codeLengthOrder = [
  1,
  2,
  3,
  4,
  0,
  5,
  17,
  6,
  16,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
];

/// The code of the code length code lengths, by the next four bits: how
/// many of them it takes, and the length it stands for.
const List<int> _codeLengthBits = [
  2, 2, 2, 3, 2, 2, 2, 4, 2, 2, 2, 3, 2, 2, 2, 4, //
];
const List<int> _codeLengthValue = [
  0, 4, 3, 2, 0, 4, 3, 1, 0, 4, 3, 2, 0, 4, 3, 5, //
];

/// The bits of a Brotli stream, least significant first, through a bit
/// buffer refilled a byte at a time up to 24 to 31 bits (below 2^31, so
/// the same with dart2js); past the end of the data it fills with zeros.
final class _Bits {
  new(this._data) : _end = _data.length * 8;

  final Uint8List _data;
  final int _end;

  /// The position, in bits, of the next bit.
  int _at = 0;

  /// The bits from [_at] on, [_count] of them, and the byte they end at.
  int _buffer = 0;
  int _count = 0;
  int _next = 0;

  void _refill() {
    final data = _data;
    while (_count < 24) {
      if (_next < data.length) _buffer |= data[_next] << _count;
      _next++;
      _count += 8;
    }
  }

  /// The next [n] bits (at most 24), consumed.
  @pragma('vm:prefer-inline')
  int read(int n) {
    if (_at + n > _end) throw const FormatException('Brotli data too short');
    if (_count < n) _refill();
    final v = _buffer & ((1 << n) - 1);
    _buffer >>>= n;
    _count -= n;
    _at += n;
    return v;
  }

  /// The next [n] bits (at most 24), zeros past the end.
  @pragma('vm:prefer-inline')
  int peek(int n) {
    if (_count < n) _refill();
    return _buffer & ((1 << n) - 1);
  }

  /// Skips [n] bits, no more than the last [peek] looked at.
  @pragma('vm:prefer-inline')
  void skip(int n) {
    if (_at + n > _end) throw const FormatException('Brotli data too short');
    _buffer >>>= n;
    _count -= n;
    _at += n;
  }

  /// Skips to the next byte, whose padding bits must be zeros.
  void align() {
    final pad = -_at & 7;
    if (read(pad) != 0) throw const FormatException('Brotli padding not zero');
  }

  /// The byte offset (at a byte boundary).
  int get byteOffset => _at >> 3;
  set byteOffset(int value) {
    _at = value * 8;
    _next = value;
    _buffer = 0;
    _count = 0;
  }
}

/// A prefix code: canonical codes from code lengths, decoded through a
/// table of 8 bits and subtables for the longer codes (Google's layout).
///
/// An entry is `symbol << 8 | length`, or for a subtable `offset << 8 |
/// 0x80 | bits`, indexed by the `bits` bits after the first 8. The codes
/// this decoder reads are complete (or of one symbol), so every entry is
/// filled.
final class _Code {
  factory(List<int> lengths) {
    final count = Int32List(16);
    for (final length in lengths) {
      count[length]++;
    }
    count[0] = 0;
    final offsets = Int32List(16);
    for (var length = 1; length < 15; length++) {
      offsets[length + 1] = offsets[length] + count[length];
    }
    final symbols = Int32List(lengths.length);
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      if (lengths[symbol] != 0) symbols[offsets[lengths[symbol]]++] = symbol;
    }
    // The filling moved each offset to the end of its length's symbols.
    final used = offsets[15];
    if (used == 1) return _Code._single(symbols[0]);
    var maxLength = 15;
    while (maxLength > 0 && count[maxLength] == 0) {
      maxLength--;
    }
    final root = maxLength < 8 ? maxLength : 8;
    final rootSize = 1 << root;
    // The codes, by length then symbol; the subtables' sizes by the root
    // bits their codes start with (the last code of a prefix is its
    // longest).
    final codes = Int32List(used);
    final subBits = Int32List(rootSize);
    var code = 0;
    var k = 0;
    for (var length = 1; length <= maxLength; length++) {
      for (var n = count[length]; n > 0; n--) {
        if (length > root) subBits[code >> (length - root)] = length - root;
        codes[k++] = code++;
      }
      code <<= 1;
    }
    var size = rootSize;
    final subOffsets = Int32List(rootSize);
    for (var prefix = 0; prefix < rootSize; prefix++) {
      if (subBits[prefix] == 0) continue;
      subOffsets[prefix] = size;
      size += 1 << subBits[prefix];
    }
    final table = Int32List(size);
    for (var prefix = 0; prefix < rootSize; prefix++) {
      if (subBits[prefix] == 0) continue;
      table[_reverse(prefix, root)] =
          subOffsets[prefix] << 8 | 0x80 | subBits[prefix];
    }
    for (k = 0; k < used; k++) {
      final symbol = symbols[k];
      final length = lengths[symbol];
      final entry = symbol << 8 | length;
      if (length <= root) {
        for (
          var i = _reverse(codes[k], length);
          i < rootSize;
          i += 1 << length
        ) {
          table[i] = entry;
        }
      } else {
        final rest = length - root;
        final prefix = codes[k] >> rest;
        final offset = subOffsets[prefix];
        final end = 1 << subBits[prefix];
        final first = _reverse(codes[k] & ((1 << rest) - 1), rest);
        for (var i = first; i < end; i += 1 << rest) {
          table[offset + i] = entry;
        }
      }
    }
    return _Code._(table, root, -1);
  }

  new _single(int symbol) : this._(Int32List(0), 0, symbol);

  new _(this._table, this._rootBits, this._only);

  final Int32List _table;
  final int _rootBits;

  /// The symbol of a code of one symbol (which takes no bits), else -1.
  final int _only;

  @pragma('vm:prefer-inline')
  int decode(_Bits bits) {
    if (_only >= 0) return _only;
    final peek = bits.peek(15);
    var entry = _table[peek & ((1 << _rootBits) - 1)];
    if (entry & 0x80 != 0) {
      entry =
          _table[(entry >> 8) +
              ((peek >> _rootBits) & ((1 << (entry & 15)) - 1))];
    }
    // Past the end of the data, the zeros peeked may make a code longer
    // than what is left: skipping it fails then.
    bits.skip(entry & 15);
    return entry >> 8;
  }
}

/// The low [length] bits of [code] (at most 15) in reverse order.
int _reverse(int code, int length) =>
    ((_reversedBytes[code & 0xff] << 8) | _reversedBytes[code >> 8]) >>
    (16 - length);

final Uint8List _reversedBytes = () {
  final table = Uint8List(256);
  for (var b = 0; b < 256; b++) {
    var r = 0;
    for (var k = 0; k < 8; k++) {
      r |= ((b >> k) & 1) << (7 - k);
    }
    table[b] = r;
  }
  return table;
}();

/// The state of a category of blocks (literals, insert-and-copy commands
/// or distances) in a meta-block.
final class _Blocks {
  new(this.types, this.typeCode, this.countCode);

  final int types;
  final _Code? typeCode;
  final _Code? countCode;
  int type = 0;
  int previous = 1;
  int left = 1 << 24;
}

final class _Decoder {
  new(Uint8List data) : _bits = _Bits(data);

  final _Bits _bits;
  Uint8List _out = Uint8List(1 << 16);
  int _length = 0;

  /// The last four distances, the last one at [_distanceAt].
  final Int32List _distances = Int32List.fromList([16, 15, 11, 4]);
  int _distanceAt = 3;

  Uint8List decode() {
    final windowBits = _windowBits();
    final maxBackward = (1 << windowBits) - 16;
    for (;;) {
      final last = _bits.read(1) == 1;
      if (last && _bits.read(1) == 1) break;
      final nibbles = _bits.read(2);
      if (nibbles == 3) {
        _skipMetadata();
        if (last) break;
        continue;
      }
      final mlen = _readMetaLength(nibbles + 4);
      if (!last && _bits.read(1) == 1) {
        _bits.align();
        final at = _bits.byteOffset;
        if (at + mlen > _bits._data.length) {
          throw const FormatException('Brotli data too short');
        }
        _reserve(mlen);
        _out.setRange(_length, _length + mlen, _bits._data, at);
        _length += mlen;
        _bits.byteOffset = at + mlen;
        continue;
      }
      _metaBlock(mlen, maxBackward);
      if (last) break;
    }
    return Uint8List.sublistView(_out, 0, _length);
  }

  int _windowBits() {
    if (_bits.read(1) == 0) return 16;
    var n = _bits.read(3);
    if (n != 0) return 17 + n;
    n = _bits.read(3);
    if (n == 1) throw const FormatException('Brotli large windows');
    return n == 0 ? 17 : 8 + n;
  }

  int _readMetaLength(int nibbles) {
    var value = 0;
    for (var i = 0; i < nibbles; i++) {
      final nibble = _bits.read(4);
      if (i == nibbles - 1 && i >= 4 && nibble == 0) {
        throw const FormatException('Brotli meta-block length');
      }
      value |= nibble << (4 * i);
    }
    return value + 1;
  }

  void _skipMetadata() {
    if (_bits.read(1) != 0) throw const FormatException('Brotli reserved bit');
    final bytes = _bits.read(2);
    var length = 0;
    for (var i = 0; i < bytes; i++) {
      final byte = _bits.read(8);
      if (i == bytes - 1 && i > 0 && byte == 0) {
        throw const FormatException('Brotli metadata length');
      }
      length |= byte << (8 * i);
    }
    if (bytes > 0) length++;
    _bits.align();
    final at = _bits.byteOffset + length;
    if (at > _bits._data.length) {
      throw const FormatException('Brotli data too short');
    }
    _bits.byteOffset = at;
  }

  void _reserve(int n) {
    if (_length + n <= _out.length) return;
    var size = _out.length * 2;
    while (size < _length + n) {
      size *= 2;
    }
    _out = Uint8List(size)..setRange(0, _length, _out);
  }

  /// A count of 1 to 256 (block types, prefix trees).
  int _readCount() {
    if (_bits.read(1) == 0) return 1;
    final n = _bits.read(3);
    return n == 0 ? 2 : (1 << n) + _bits.read(n) + 1;
  }

  _Blocks _readBlocks() {
    final types = _readCount();
    if (types < 2) return _Blocks(1, null, null);
    final blocks = _Blocks(types, _readCode(types + 2), _readCode(26));
    blocks.left = _readBlockCount(blocks.countCode!);
    return blocks;
  }

  int _readBlockCount(_Code code) {
    final c = code.decode(_bits);
    return _blockBase[c] + _bits.read(_blockExtra[c]);
  }

  void _switchBlock(_Blocks blocks) {
    if (blocks.typeCode == null) {
      blocks.left = 1 << 24;
      return;
    }
    var type = blocks.typeCode!.decode(_bits);
    type = switch (type) {
      0 => blocks.previous,
      1 => blocks.type + 1,
      _ => type - 2,
    };
    if (type >= blocks.types) type -= blocks.types;
    blocks
      ..previous = blocks.type
      ..type = type
      ..left = _readBlockCount(blocks.countCode!);
  }

  /// A prefix code over [size] symbols (RFC 7932, section 3).
  _Code _readCode(int size) {
    final lengths = Int32List(size);
    final kind = _bits.read(2);
    if (kind == 1) {
      // A simple prefix code: one to four symbols listed.
      var symbolBits = 0;
      while ((1 << symbolBits) < size) {
        symbolBits++;
      }
      final n = _bits.read(2) + 1;
      final symbols = [for (var i = 0; i < n; i++) _bits.read(symbolBits)];
      if (symbols.any((s) => s >= size) || symbols.toSet().length != n) {
        throw const FormatException('Brotli simple prefix code');
      }
      final codeLengths = switch (n) {
        1 => const [0],
        2 => const [1, 1],
        3 => const [1, 2, 2],
        _ => _bits.read(1) == 0 ? const [2, 2, 2, 2] : const [1, 2, 3, 3],
      };
      if (n == 1) return _Code._single(symbols[0]);
      for (var i = 0; i < n; i++) {
        lengths[symbols[i]] = codeLengths[i];
      }
      return _Code(lengths);
    }
    // A complex prefix code: the code lengths, themselves coded.
    final codeLengthLengths = Int32List(18);
    var space = 32;
    var codes = 0;
    for (var i = kind; i < 18; i++) {
      final peek = _bits.peek(4);
      _bits.skip(_codeLengthBits[peek]);
      final length = _codeLengthValue[peek];
      codeLengthLengths[_codeLengthOrder[i]] = length;
      if (length != 0) {
        space -= 32 >> length;
        codes++;
        if (space <= 0) break;
      }
    }
    if (codes != 1 && space != 0) {
      throw const FormatException('Brotli code length code');
    }
    final codeLengthCode = _Code(codeLengthLengths);
    var symbol = 0;
    var previous = 8;
    var repeat = 0;
    var repeatLength = 0;
    space = 32768;
    while (symbol < size && space > 0) {
      final length = codeLengthCode.decode(_bits);
      if (length < 16) {
        repeat = 0;
        lengths[symbol++] = length;
        if (length != 0) {
          previous = length;
          space -= 32768 >> length;
        }
        continue;
      }
      final extraBits = length == 16 ? 2 : 3;
      final newLength = length == 16 ? previous : 0;
      if (repeatLength != newLength) {
        repeat = 0;
        repeatLength = newLength;
      }
      final oldRepeat = repeat;
      if (repeat > 0) repeat = (repeat - 2) << extraBits;
      repeat += _bits.read(extraBits) + 3;
      final delta = repeat - oldRepeat;
      if (symbol + delta > size) {
        throw const FormatException('Brotli code lengths overflow');
      }
      for (var i = 0; i < delta; i++) {
        lengths[symbol++] = repeatLength;
      }
      if (repeatLength != 0) space -= delta << (15 - repeatLength);
    }
    if (space != 0) throw const FormatException('Brotli prefix code');
    return _Code(lengths);
  }

  /// A context map of [size] entries over [trees] prefix codes.
  Uint8List _readContextMap(int size, int trees) {
    final map = Uint8List(size);
    if (trees < 2) return map;
    final rleMax = _bits.read(1) == 1 ? _bits.read(4) + 1 : 0;
    final code = _readCode(trees + rleMax);
    for (var i = 0; i < size;) {
      final c = code.decode(_bits);
      if (c == 0) {
        map[i++] = 0;
      } else if (c <= rleMax) {
        final zeros = (1 << c) + _bits.read(c);
        if (i + zeros > size) {
          throw const FormatException('Brotli context map overflow');
        }
        i += zeros;
      } else {
        map[i++] = c - rleMax;
      }
    }
    if (_bits.read(1) == 1) {
      // Inverse move-to-front.
      final mtf = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);
      for (var i = 0; i < size; i++) {
        final index = map[i];
        final value = mtf[index];
        map[i] = value;
        for (var j = index; j > 0; j--) {
          mtf[j] = mtf[j - 1];
        }
        mtf[0] = value;
      }
    }
    return map;
  }

  void _metaBlock(int mlen, int maxBackward) {
    final literals = _readBlocks();
    final commands = _readBlocks();
    final distances = _readBlocks();
    final postfixBits = _bits.read(2);
    final direct = _bits.read(4) << postfixBits;
    final postfixMask = (1 << postfixBits) - 1;
    final modes = Uint8List(literals.types);
    for (var i = 0; i < modes.length; i++) {
      modes[i] = _bits.read(2);
    }
    final literalTrees = _readCount();
    final literalMap = _readContextMap(64 * literals.types, literalTrees);
    final distanceTrees = _readCount();
    final distanceMap = _readContextMap(4 * distances.types, distanceTrees);
    final literalCodes = [
      for (var i = 0; i < literalTrees; i++) _readCode(256),
    ];
    final commandCodes = [
      for (var i = 0; i < commands.types; i++) _readCode(704),
    ];
    final distanceCodes = [
      for (var i = 0; i < distanceTrees; i++)
        _readCode(16 + direct + (48 << postfixBits)),
    ];

    var left = mlen;
    _reserve(mlen);
    final out = _out;
    while (left > 0) {
      if (commands.left == 0) _switchBlock(commands);
      commands.left--;
      final command = commandCodes[commands.type].decode(_bits);
      final cell = command >> 6;
      final insertCode = _cellInsert[cell] + ((command >> 3) & 7);
      final copyCode = _cellCopy[cell] + (command & 7);
      final insert =
          _insertBase[insertCode] + _bits.read(_insertExtra[insertCode]);
      final copy = _copyBase[copyCode] + _bits.read(_copyExtra[copyCode]);
      if (insert > left) {
        throw const FormatException('Brotli insert past the meta-block');
      }
      if (insert > 0) {
        // The context is that of the last two bytes, by the mode of the
        // block type, which changes only at a block switch.
        var at = _length;
        var p1 = at > 0 ? out[at - 1] : 0;
        var p2 = at > 1 ? out[at - 2] : 0;
        var lut = modes[literals.type] * 512;
        var mapAt = literals.type * 64;
        for (final end = at + insert; at < end; at++) {
          if (literals.left == 0) {
            _switchBlock(literals);
            lut = modes[literals.type] * 512;
            mapAt = literals.type * 64;
          }
          literals.left--;
          final context =
              brotliContextLookup[lut + p1] |
              brotliContextLookup[lut + 256 + p2];
          final literal = literalCodes[literalMap[mapAt + context]].decode(
            _bits,
          );
          out[at] = literal;
          p2 = p1;
          p1 = literal;
        }
        _length = at;
      }
      left -= insert;
      if (left == 0) break;

      int distance;
      var code = 0;
      if (cell < 2) {
        distance = _distances[_distanceAt];
      } else {
        if (distances.left == 0) _switchBlock(distances);
        distances.left--;
        final context = copy > 4 ? 3 : copy - 2;
        code = distanceCodes[distanceMap[distances.type * 4 + context]].decode(
          _bits,
        );
        distance = _distance(code, direct, postfixBits, postfixMask);
      }
      final maxDistance = _length < maxBackward ? _length : maxBackward;
      if (distance > maxDistance) {
        left -= _dictionaryWord(distance - maxDistance - 1, copy, left);
        continue;
      }
      if (code != 0) {
        _distanceAt = (_distanceAt + 1) & 3;
        _distances[_distanceAt] = distance;
      }
      if (copy > left) {
        throw const FormatException('Brotli copy past the meta-block');
      }
      final end = _length + copy;
      if (distance >= copy && copy > 16) {
        out.setRange(_length, end, out, _length - distance);
      } else {
        for (var at = _length; at < end; at++) {
          out[at] = out[at - distance];
        }
      }
      _length = end;
      left -= copy;
    }
  }

  int _distance(int code, int direct, int postfixBits, int postfixMask) {
    if (code < 16) {
      final last = _distances[_distanceAt];
      final secondLast = _distances[(_distanceAt - 1) & 3];
      final distance = switch (code) {
        0 => last,
        1 => secondLast,
        2 => _distances[(_distanceAt - 2) & 3],
        3 => _distances[(_distanceAt - 3) & 3],
        < 10 => last + _shortDelta(code - 4),
        _ => secondLast + _shortDelta(code - 10),
      };
      if (distance <= 0) throw const FormatException('Brotli distance');
      return distance;
    }
    if (code < 16 + direct) return code - 15;
    final value = code - direct - 16;
    final bits = 1 + (value >> (postfixBits + 1));
    final high = value >> postfixBits;
    final low = value & postfixMask;
    final offset = ((2 + (high & 1)) << bits) - 4;
    return ((offset + _bits.read(bits)) << postfixBits) + low + direct + 1;
  }

  /// -1, +1, -2, +2, -3, +3 for 0 to 5.
  static int _shortDelta(int i) => (i & 1) == 0 ? -(i >> 1) - 1 : (i >> 1) + 1;

  /// Writes the word [id] of [length] (transformed), and returns its
  /// length.
  int _dictionaryWord(int id, int length, int left) {
    if (length < 4 || length > 24) {
      throw const FormatException('Brotli dictionary word length');
    }
    final bits = _dictionaryBits[length];
    final index = id & ((1 << bits) - 1);
    final transform = id >> bits;
    if (transform >= brotliTransforms.length) {
      throw const FormatException('Brotli dictionary transform');
    }
    final start = _dictionaryOffsets[length] + index * length;
    final (prefix, type, suffix) = brotliTransforms[transform];
    var word = Uint8List.sublistView(_dictionary, start, start + length);
    if (type >= 1 && type <= 9) {
      word = Uint8List.sublistView(word, 0, type > length ? 0 : length - type);
    } else if (type >= 12 && type <= 20) {
      final skip = type - 11;
      word = Uint8List.sublistView(word, skip > length ? length : skip);
    }
    final total = prefix.length + word.length + suffix.length;
    if (total > left) {
      throw const FormatException('Brotli word past the meta-block');
    }
    final out = _out;
    var at = _length;
    for (final b in prefix) {
      out[at++] = b;
    }
    final wordAt = at;
    out.setRange(at, at + word.length, word);
    at += word.length;
    if (type == 10 || type == 11) {
      var i = wordAt;
      while (i < at) {
        final b = out[i];
        if (b < 0xc0) {
          if (b >= 0x61 && b <= 0x7a) out[i] ^= 32;
          i += 1;
        } else if (b < 0xe0) {
          if (i + 1 < at) out[i + 1] ^= 32;
          i += 2;
        } else {
          if (i + 2 < at) out[i + 2] ^= 5;
          i += 3;
        }
        if (type == 10) break;
      }
    }
    for (final b in suffix) {
      out[at++] = b;
    }
    _length = at;
    return total;
  }
}
