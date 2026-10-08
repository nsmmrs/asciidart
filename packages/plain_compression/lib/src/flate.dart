/// DEFLATE (RFC 1951) and its zlib wrapper (RFC 1950) in pure Dart, so
/// the library compresses the same way, byte for byte, on every platform
/// (including the web).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Compresses [data] in the zlib format (`/FlateDecode` streams).
Uint8List zlibEncode(List<int> data, {int level = 6}) {
  final input = data is Uint8List ? data : Uint8List.fromList(data);
  final out = _BitWriter(input.length)
    ..writeBits(0x78, 8)
    ..writeBits(_zlibFlags(level), 8);
  _deflate(out, input, level);
  final adler = adler32(input);
  return (out
        ..alignToByte()
        ..writeBits(adler >>> 24, 8)
        ..writeBits((adler >> 16) & 0xff, 8)
        ..writeBits((adler >> 8) & 0xff, 8)
        ..writeBits(adler & 0xff, 8))
      .finish();
}

int _zlibFlags(int level) {
  final levelBits = level <= 1
      ? 0
      : level <= 5
      ? 1
      : level == 6
      ? 2
      : 3;
  final flags = levelBits << 6;
  return flags + (31 - ((0x78 << 8) + flags) % 31);
}

/// Expands zlib-format [data]; throws a [FormatException] when it is
/// malformed or its checksum doesn't match.
Uint8List zlibDecode(List<int> data) {
  if (data.length < 6) throw const FormatException('zlib data too short');
  final cmf = data[0];
  final flg = data[1];
  if (cmf & 0x0f != 8 || ((cmf << 8) + flg) % 31 != 0) {
    throw const FormatException('not zlib data');
  }
  if (flg & 0x20 != 0) {
    throw const FormatException('zlib preset dictionaries are not supported');
  }
  final inflater = _Inflater(data, 2);
  final result = inflater.inflate();
  final at = inflater.endOffset;
  if (at + 4 <= data.length) {
    final expected =
        (data[at] << 24) |
        (data[at + 1] << 16) |
        (data[at + 2] << 8) |
        data[at + 3];
    if (expected != adler32(result)) {
      throw const FormatException('zlib checksum mismatch');
    }
  }
  return result;
}

/// The Adler-32 checksum of [data].
int adler32(List<int> data) {
  if (data is Uint8List) return _adler32(data);
  var a = 1;
  var b = 0;
  var i = 0;
  while (i < data.length) {
    final end = i + 5552 < data.length ? i + 5552 : data.length;
    for (; i < end; i++) {
      a += data[i];
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return (b << 16) | a;
}

/// [adler32] over typed bytes, eight at a time; the sums are reduced every
/// 5552 bytes, as zlib does, before `b` could pass 2^32.
int _adler32(Uint8List data) {
  final n = data.length;
  var a = 1;
  var b = 0;
  var i = 0;
  while (i < n) {
    final end = i + 5552 < n ? i + 5552 : n;
    for (; i + 8 <= end; i += 8) {
      a += data[i];
      b += a;
      a += data[i + 1];
      b += a;
      a += data[i + 2];
      b += a;
      a += data[i + 3];
      b += a;
      a += data[i + 4];
      b += a;
      a += data[i + 5];
      b += a;
      a += data[i + 6];
      b += a;
      a += data[i + 7];
      b += a;
    }
    for (; i < end; i++) {
      a += data[i];
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return (b << 16) | a;
}

// ---------------------------------------------------------------- encoder

const int _windowSize = 32768;
const int _minMatch = 3;
const int _maxMatch = 258;
const int _hashBits = 15;
const int _hashSize = 1 << _hashBits;
const int _blockSymbols = 16383;

/// Length codes 257..285: base lengths and extra bits.
const List<int> _lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];
const List<int> _lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];

/// Distance codes 0..29: base distances and extra bits.
const List<int> _distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, //
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
  16385, 24577,
];
const List<int> _distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, //
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];

/// The order code length code lengths are written in.
const List<int> _codeLengthOrder = [
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
];

final Uint16List _lengthCodeOf = () {
  final table = Uint16List(_maxMatch + 1);
  for (var code = 0; code < _lengthBase.length; code++) {
    final base = _lengthBase[code];
    final count = 1 << _lengthExtra[code];
    for (var i = 0; i < count && base + i <= _maxMatch; i++) {
      table[base + i] = code;
    }
  }
  table[_maxMatch] = 28;
  return table;
}();

/// zlib's `_dist_code`: the code of distance `d` is entry `d - 1` up to
/// 256, and entry `256 + ((d - 1) >> 7)` beyond (the codes from 16 on
/// start at multiples of 128, plus one).
final Uint8List _distCodes = () {
  final table = Uint8List(512);
  for (var code = 0; code < _distBase.length; code++) {
    final base = _distBase[code];
    for (var d = base; d < base + (1 << _distExtra[code]); d++) {
      final i = d - 1;
      table[i < 256 ? i : 256 + (i >> 7)] = code;
    }
  }
  return table;
}();

int _distCodeOf(int distance) {
  final i = distance - 1;
  return _distCodes[i < 256 ? i : 256 + (i >> 7)];
}

/// Compresses [data] as a raw DEFLATE stream (no header).
///
/// [level] trades speed for size: 0 stores, 1–9 search for matches
/// further (the chain length grows with the level).
Uint8List deflate(List<int> data, {int level = 6}) {
  final input = data is Uint8List ? data : Uint8List.fromList(data);
  final out = _BitWriter(input.length);
  _deflate(out, input, level);
  return out.finish();
}

/// Writes [input] compressed at [level] to [out]: greedy matching, the
/// longest match within the level's chain length, every position hashed.
void _deflate(_BitWriter out, Uint8List input, int level) {
  final n = input.length;
  if (n == 0) {
    // One final fixed block holding just the end-of-block code.
    out
      ..writeBits(1, 1)
      ..writeBits(1, 2)
      ..writeBits(0, 7);
    return;
  }
  if (level == 0) {
    _writeStored(out, input, 0, n, last: true);
    return;
  }
  final maxChain = switch (level) {
    1 => 4,
    2 => 8,
    3 => 16,
    4 => 32,
    5 => 64,
    6 => 128,
    7 => 256,
    8 => 1024,
    _ => 4096,
  };
  // Positions plus one, so that a new table is empty; a position's link
  // is at its index in the window, which for a short input is the
  // position itself.
  final head = Int32List(_hashSize);
  final prev = Int32List(n < _windowSize ? n : _windowSize);
  final words = ByteData.sublistView(input);
  // Symbols of the current block: literals and match lengths, and
  // distances (0 for a literal).
  final litLen = Uint16List(_blockSymbols + 1);
  final distances = Uint16List(_blockSymbols + 1);
  var count = 0;
  var blockStart = 0;
  // The last position with three bytes to hash.
  final lastHashed = n - _minMatch;
  // zlib's rolling UPDATE_HASH: the hash of position p is ((hash << 5) ^
  // input[p + 2]) & mask with hash that of p - 1, which is (input[p] << 10
  // ^ input[p + 1] << 5 ^ input[p + 2]) & mask, as the bits shifted past
  // the mask drop out. Positions are hashed in order, so when a match is
  // searched at i, `hash` is that of i - 1.
  var hash = n >= 2 ? ((input[0] << 5) ^ input[1]) & (_hashSize - 1) : 0;

  var i = 0;
  while (i < n) {
    var bestLength = 0;
    var bestDistance = 0;
    if (i <= lastHashed) {
      var candidate = head[((hash << 5) ^ input[i + 2]) & (_hashSize - 1)] - 1;
      var chain = maxChain;
      final limit = i - _windowSize;
      final maxLength = n - i < _maxMatch ? n - i : _maxMatch;
      final first = input[i];
      final second = input[i + 1];
      // input[i + bestLength], the byte a longer match must have.
      var scanEnd = first;
      while (candidate >= 0 && candidate > limit && chain-- > 0) {
        // zlib's quick rejection: a match longer than bestLength has the
        // same bytes at 0, 1, bestLength - 1 and bestLength.
        if (input[candidate + bestLength] == scanEnd &&
            (bestLength < 2 ||
                (input[candidate] == first &&
                    input[candidate + 1] == second &&
                    input[candidate + bestLength - 1] ==
                        input[i + bestLength - 1]))) {
          var length = 0;
          while (true) {
            if (length + 4 > maxLength) {
              while (length < maxLength &&
                  input[candidate + length] == input[i + length]) {
                length += 1;
              }
              break;
            }
            // Four bytes at a time; the lowest set bit of the difference
            // is in the first byte that differs.
            final x =
                words.getUint32(candidate + length, Endian.little) ^
                words.getUint32(i + length, Endian.little);
            if (x != 0) {
              length += ((x & -x).bitLength - 1) >> 3;
              break;
            }
            length += 4;
          }
          if (length > bestLength) {
            bestLength = length;
            bestDistance = i - candidate;
            if (length == maxLength) break;
            scanEnd = input[i + length];
          }
        }
        candidate = prev[candidate & (_windowSize - 1)] - 1;
      }
    }
    final advance = bestLength >= _minMatch ? bestLength : 1;
    if (bestLength >= _minMatch) {
      litLen[count] = bestLength;
      distances[count] = bestDistance;
    } else {
      litLen[count] = input[i];
      distances[count] = 0;
    }
    count += 1;
    final stop = i + advance - 1 < lastHashed ? i + advance - 1 : lastHashed;
    for (var p = i; p <= stop; p++) {
      hash = ((hash << 5) ^ input[p + 2]) & (_hashSize - 1);
      prev[p & (_windowSize - 1)] = head[hash];
      head[hash] = p + 1;
    }
    i += advance;
    if (count >= _blockSymbols) {
      _writeBlock(
        out,
        input,
        blockStart,
        i,
        litLen,
        distances,
        count,
        last: i >= n,
      );
      blockStart = i;
      count = 0;
    }
  }
  if (count > 0 || blockStart < n) {
    _writeBlock(
      out,
      input,
      blockStart,
      n,
      litLen,
      distances,
      count,
      last: true,
    );
  }
}

void _writeStored(
  _BitWriter out,
  Uint8List input,
  int start,
  int end, {
  required bool last,
}) {
  var at = start;
  do {
    final length = end - at > 65535 ? 65535 : end - at;
    out
      ..writeBits(last && at + length >= end ? 1 : 0, 1)
      ..writeBits(0, 2)
      ..alignToByte()
      ..writeBits(length, 16)
      ..writeBits(~length & 0xffff, 16)
      ..writeBytes(input, at, at + length);
    at += length;
  } while (at < end);
}

/// Writes the symbols of one block with dynamic Huffman codes, or stored
/// when that is smaller.
void _writeBlock(
  _BitWriter out,
  Uint8List input,
  int start,
  int end,
  Uint16List litLen,
  Uint16List distances,
  int count, {
  required bool last,
}) {
  // Each symbol's literal/length code and distance code, found once.
  final symbols = Uint16List(count);
  final distSymbols = Uint8List(count);
  final litFreq = Int32List(286);
  final distFreq = Int32List(30);
  for (var s = 0; s < count; s++) {
    final distance = distances[s];
    if (distance == 0) {
      final literal = litLen[s];
      symbols[s] = literal;
      litFreq[literal] += 1;
    } else {
      final symbol = 257 + _lengthCodeOf[litLen[s]];
      final distCode = _distCodeOf(distance);
      symbols[s] = symbol;
      distSymbols[s] = distCode;
      litFreq[symbol] += 1;
      distFreq[distCode] += 1;
    }
  }
  litFreq[256] = 1;
  final litLengths = Uint8List.fromList(huffmanLengths(litFreq, 15));
  final distLengths = Uint8List.fromList(huffmanLengths(distFreq, 15));
  // At least one distance code must be defined.
  if (distLengths.every((l) => l == 0)) distLengths[0] = 1;

  var hlit = 286;
  while (hlit > 257 && litLengths[hlit - 1] == 0) {
    hlit -= 1;
  }
  var hdist = 30;
  while (hdist > 1 && distLengths[hdist - 1] == 0) {
    hdist -= 1;
  }
  final allLengths = [
    ...litLengths.sublist(0, hlit),
    ...distLengths.sublist(0, hdist),
  ];
  final rle = _runLengths(allLengths);
  final clFreq = List<int>.filled(19, 0);
  for (final (symbol, _) in rle) {
    clFreq[symbol] += 1;
  }
  // A code with one symbol is incomplete, which decoders reject for the
  // code length code: give it a second symbol.
  if (clFreq.where((f) => f > 0).length < 2) {
    clFreq[clFreq[0] == 0 ? 0 : 1] += 1;
  }
  final clLengths = huffmanLengths(clFreq, 7);
  var hclen = 19;
  while (hclen > 4 && clLengths[_codeLengthOrder[hclen - 1]] == 0) {
    hclen -= 1;
  }

  // Compare the size with storing the block; the symbols' bits are their
  // codes' lengths and extra bits times their frequencies (the
  // end-of-block code's frequency is 1).
  var bits = 3 + 5 + 5 + 4 + hclen * 3;
  for (final (symbol, _) in rle) {
    bits +=
        clLengths[symbol] +
        switch (symbol) {
          16 => 2,
          17 => 3,
          18 => 7,
          _ => 0,
        };
  }
  for (var c = 0; c < 257; c++) {
    bits += litFreq[c] * litLengths[c];
  }
  for (var c = 257; c < 286; c++) {
    bits += litFreq[c] * (litLengths[c] + _lengthExtra[c - 257]);
  }
  for (var c = 0; c < 30; c++) {
    bits += distFreq[c] * (distLengths[c] + _distExtra[c]);
  }
  final storedBits = (end - start) * 8 + ((end - start) ~/ 65535 + 1) * 40;
  if (storedBits < bits) {
    _writeStored(out, input, start, end, last: last);
    return;
  }

  final litCodes = _canonicalCodes(litLengths);
  final distCodes = _canonicalCodes(distLengths);
  final clCodes = _canonicalCodes(clLengths);
  out
    ..writeBits(last ? 1 : 0, 1)
    ..writeBits(2, 2)
    ..writeBits(hlit - 257, 5)
    ..writeBits(hdist - 1, 5)
    ..writeBits(hclen - 4, 4);
  for (var k = 0; k < hclen; k++) {
    out.writeBits(clLengths[_codeLengthOrder[k]], 3);
  }
  for (final (symbol, extra) in rle) {
    out.writeBits(clCodes[symbol], clLengths[symbol]);
    switch (symbol) {
      case 16:
        out.writeBits(extra, 2);
      case 17:
        out.writeBits(extra, 3);
      case 18:
        out.writeBits(extra, 7);
    }
  }
  for (var s = 0; s < count; s++) {
    final symbol = symbols[s];
    if (symbol < 256) {
      out.writeBits(litCodes[symbol], litLengths[symbol]);
    } else {
      // The length code and its extra bits in one write (20 bits at most).
      final code = symbol - 257;
      final codeLength = litLengths[symbol];
      out.writeBits(
        litCodes[symbol] | (litLen[s] - _lengthBase[code]) << codeLength,
        codeLength + _lengthExtra[code],
      );
      final distCode = distSymbols[s];
      out
        ..writeBits(distCodes[distCode], distLengths[distCode])
        ..writeBits(distances[s] - _distBase[distCode], _distExtra[distCode]);
    }
  }
  out.writeBits(litCodes[256], litLengths[256]);
}

/// The code lengths as code length symbols: 0–15 as they are, 16 repeats
/// the previous length 3–6 times, 17 and 18 repeat zero 3–10 and 11–138
/// times; each with its extra bits.
List<(int, int)> _runLengths(List<int> lengths) {
  final result = <(int, int)>[];
  var i = 0;
  while (i < lengths.length) {
    final length = lengths[i];
    var run = 1;
    while (i + run < lengths.length && lengths[i + run] == length) {
      run += 1;
    }
    if (length == 0 && run >= 3) {
      var left = run;
      while (left >= 11) {
        final n = left > 138 ? 138 : left;
        result.add((18, n - 11));
        left -= n;
      }
      if (left >= 3) {
        result.add((17, left - 3));
        left = 0;
      }
      for (; left > 0; left--) {
        result.add((0, 0));
      }
    } else if (length != 0 && run >= 4) {
      result.add((length, 0));
      var left = run - 1;
      while (left >= 3) {
        final n = left > 6 ? 6 : left;
        result.add((16, n - 3));
        left -= n;
      }
      for (; left > 0; left--) {
        result.add((length, 0));
      }
    } else {
      for (var k = 0; k < run; k++) {
        result.add((length, 0));
      }
    }
    i += run;
  }
  return result;
}

/// Huffman code lengths for [frequencies], none longer than [maxBits]
/// (zlib's way of limiting lengths: shorten the deepest codes, then hand
/// the lengths out again by frequency).
List<int> huffmanLengths(List<int> frequencies, int maxBits) {
  final n = frequencies.length;
  final lengths = List<int>.filled(n, 0);
  final used = [
    for (var s = 0; s < n; s++)
      if (frequencies[s] > 0) s,
  ];
  if (used.isEmpty) return lengths;
  if (used.length == 1) {
    lengths[used.single] = 1;
    return lengths;
  }
  // Build the tree with a simple priority queue (nodes: weight, depth via
  // parent links).
  final weights = <int>[];
  final parents = <int>[];
  final queue = <int>[];
  for (final s in used) {
    weights.add(frequencies[s]);
    parents.add(-1);
    queue.add(weights.length - 1);
  }
  int compare(int a, int b) =>
      weights[a] != weights[b] ? weights[a] - weights[b] : a - b;
  queue.sort(compare);
  // Two-queue method: leaves sorted, internal nodes appended in order.
  final internal = <int>[];
  var li = 0;
  var ii = 0;
  int takeMin() {
    if (ii >= internal.length ||
        (li < queue.length && compare(queue[li], internal[ii]) <= 0)) {
      return queue[li++];
    }
    return internal[ii++];
  }

  for (var k = 0; k < used.length - 1; k++) {
    final a = takeMin();
    final b = takeMin();
    weights.add(weights[a] + weights[b]);
    parents.add(-1);
    final node = weights.length - 1;
    parents[a] = node;
    parents[b] = node;
    internal.add(node);
  }
  final depth = List<int>.filled(weights.length, 0);
  for (var node = weights.length - 2; node >= 0; node--) {
    depth[node] = depth[parents[node]] + 1;
  }
  // Count codes per length, clipping at maxBits.
  final blCount = List<int>.filled(maxBits + 1, 0);
  for (var k = 0; k < used.length; k++) {
    blCount[math.min(depth[k], maxBits)] += 1;
  }
  // Clipped codes over-subscribe the code (its Kraft sum, in units of
  // 2^-maxBits, passes 2^maxBits): each step moves a leaf one level down
  // with a clipped code as its brother, taking one unit off, until the
  // code is complete again.
  var kraft = 0;
  for (var bits = 1; bits <= maxBits; bits++) {
    kraft += blCount[bits] << (maxBits - bits);
  }
  for (; kraft > 1 << maxBits; kraft--) {
    var bits = maxBits - 1;
    while (blCount[bits] == 0) {
      bits -= 1;
    }
    blCount[bits] -= 1;
    blCount[bits + 1] += 2;
    blCount[maxBits] -= 1;
  }
  // Hand the lengths out: the least frequent symbols get the longest.
  final byFrequency = [...used]
    ..sort(
      (a, b) => frequencies[a] != frequencies[b]
          ? frequencies[a] - frequencies[b]
          : b - a,
    );
  var at = 0;
  for (var bits = maxBits; bits >= 1; bits--) {
    for (var k = 0; k < blCount[bits]; k++) {
      lengths[byFrequency[at++]] = bits;
    }
  }
  return lengths;
}

/// Canonical Huffman codes for [lengths] (at most 15), bit-reversed for
/// writing.
Int32List _canonicalCodes(List<int> lengths) {
  final counts = Int32List(16);
  for (final length in lengths) {
    counts[length] += 1;
  }
  counts[0] = 0;
  final nextCode = Int32List(16);
  var code = 0;
  for (var bits = 1; bits <= 15; bits++) {
    code = (code + counts[bits - 1]) << 1;
    nextCode[bits] = code;
  }
  final codes = Int32List(lengths.length);
  for (var s = 0; s < lengths.length; s++) {
    final length = lengths[s];
    if (length != 0) codes[s] = _reversed(nextCode[length]++, length);
  }
  return codes;
}

/// Writes bits, least significant first, into one growing buffer.
final class _BitWriter {
  /// A writer for [inputLength] bytes compressed: room for them stored, as
  /// a block is stored when that is smaller (5 bytes per stored block of
  /// 65535 and per block of 16383 symbols or fewer, plus the wrapper).
  new(int inputLength)
    : _buffer = Uint8List(inputLength + (inputLength >> 11) + 64);

  Uint8List _buffer;
  int _used = 0;
  int _bits = 0;
  int _bitCount = 0;

  void _grow(int need) {
    var size = _buffer.length * 2;
    while (size < _used + need) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _used, _buffer);
  }

  /// Writes the [count] bits of [value], which has no more bits: 24 at
  /// most, so with the fewer than 8 bits pending the values stay below
  /// 2^31 (the same with dart2js).
  void writeBits(int value, int count) {
    var bits = _bits | (value << _bitCount);
    var bitCount = _bitCount + count;
    if (bitCount >= 8) {
      if (_used + 4 > _buffer.length) _grow(4);
      final buffer = _buffer;
      var used = _used;
      do {
        buffer[used++] = bits & 0xff;
        bits >>>= 8;
        bitCount -= 8;
      } while (bitCount >= 8);
      _used = used;
    }
    _bits = bits;
    _bitCount = bitCount;
  }

  void alignToByte() {
    if (_bitCount > 0) writeBits(0, 8 - _bitCount);
  }

  /// Writes the bytes of [bytes] from [start] to [end] (at a byte
  /// boundary).
  void writeBytes(Uint8List bytes, int start, int end) {
    if (_used + end - start > _buffer.length) _grow(end - start);
    _buffer.setRange(_used, _used + end - start, bytes, start);
    _used += end - start;
  }

  Uint8List finish() {
    alignToByte();
    if (_used == _buffer.length) return _buffer;
    // As the inflater does: a large result is a view, its buffer's pages
    // past the end never touched.
    if (_used >= 1 << 18) return Uint8List.sublistView(_buffer, 0, _used);
    return _buffer.sublist(0, _used);
  }
}

// ---------------------------------------------------------------- decoder

/// Expands a raw DEFLATE stream.
Uint8List inflate(List<int> data) => _Inflater(data, 0).inflate();

/// Expands the raw DEFLATE stream starting at [start] of [data]: the bytes,
/// and the offset just past the stream (for the container's trailer).
(Uint8List, int) inflateAt(List<int> data, int start) {
  final inflater = _Inflater(data, start);
  return (inflater.inflate(), inflater.endOffset);
}

/// A Huffman decoding table, indexed by the next [rootBits] bits of the
/// stream (zlib's and libdeflate's two-level layout).
///
/// An entry is 0 where no code starts with those bits, `symbol << 8 |
/// length` for a code of that length, or, where codes longer than
/// [rootBits] start, a subtable: `offset << 8 | 0x80 | bits`, indexed by
/// the `bits` bits after the root's; its entries hold the codes' whole
/// lengths.
///
/// The codes are canonical (RFC 1951, 3.2.2) the way puff decodes them:
/// an incomplete code leaves entries 0, and an over-subscribed one keeps
/// the codes that fit their length and loses the rest, which is how the
/// bit-at-a-time decoder before this one read malformed streams.
final class _Table {
  new(this.entries, this.rootBits);

  final Int32List entries;
  final int rootBits;
}

/// The table for the code [lengths] of the [count] symbols from [start],
/// its root at most [maxRootBits] bits.
_Table _table(Uint8List lengths, int start, int count, int maxRootBits) {
  final counts = Int32List(16);
  for (var s = start; s < start + count; s++) {
    counts[lengths[s]] += 1;
  }
  counts[0] = 0;
  final offsets = Int32List(17);
  var maxLength = 0;
  for (var length = 1; length <= 15; length++) {
    offsets[length + 1] = offsets[length] + counts[length];
    if (counts[length] > 0) maxLength = length;
  }
  final root = maxLength == 0
      ? 1
      : (maxLength < maxRootBits ? maxLength : maxRootBits);
  final rootSize = 1 << root;
  // The symbols by length, then symbol, and their codes, up to the first
  // code too big for its length.
  final sorted = Int32List(offsets[16]);
  for (var s = 0; s < count; s++) {
    final length = lengths[start + s];
    if (length != 0) sorted[offsets[length]++] = s;
  }
  final codes = Int32List(sorted.length);
  var defined = 0;
  var code = 0;
  lengths:
  for (var length = 1; length <= 15; length++) {
    for (var k = counts[length]; k > 0; k--) {
      if (code >= 1 << length) break lengths;
      codes[defined++] = code++;
    }
    code <<= 1;
  }
  // The subtables' sizes, by the root bits their codes start with (the
  // codes come by length, so the last one of a prefix is its longest).
  final subBits = Int32List(rootSize);
  for (var k = 0; k < defined; k++) {
    final length = lengths[start + sorted[k]];
    if (length > root) subBits[codes[k] >> (length - root)] = length - root;
  }
  var size = rootSize;
  for (var prefix = 0; prefix < rootSize; prefix++) {
    if (subBits[prefix] > 0) size += 1 << subBits[prefix];
  }
  final entries = Int32List(size);
  final subOffsets = Int32List(rootSize);
  var next = rootSize;
  for (var prefix = 0; prefix < rootSize; prefix++) {
    final bits = subBits[prefix];
    if (bits == 0) continue;
    subOffsets[prefix] = next;
    entries[_reversed(prefix, root)] = next << 8 | 0x80 | bits;
    next += 1 << bits;
  }
  for (var k = 0; k < defined; k++) {
    final symbol = sorted[k];
    final length = lengths[start + symbol];
    final entry = symbol << 8 | length;
    final code = codes[k];
    if (length <= root) {
      for (var i = _reversed(code, length); i < rootSize; i += 1 << length) {
        entries[i] = entry;
      }
    } else {
      final rest = length - root;
      final prefix = code >> rest;
      final offset = subOffsets[prefix];
      final end = 1 << subBits[prefix];
      final first = _reversed(code & ((1 << rest) - 1), rest);
      for (var i = first; i < end; i += 1 << rest) {
        entries[offset + i] = entry;
      }
    }
  }
  return _Table(entries, root);
}

/// The low [length] bits of [code] (at most 15) in reverse order.
int _reversed(int code, int length) =>
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

final _Table _fixedLiterals = _table(
  Uint8List.fromList([for (var s = 0; s < 288; s++) _fixedLength(s)]),
  0,
  288,
  9,
);

int _fixedLength(int symbol) {
  if (symbol < 144) return 8;
  if (symbol < 256) return 9;
  if (symbol < 280) return 7;
  return 8;
}

final _Table _fixedDistances = _table(
  Uint8List(30)..fillRange(0, 30, 5),
  0,
  30,
  5,
);

const _endedEarly = FormatException('deflate data ended early');

/// Inflates with two-level tables and a bit buffer refilled a byte at a
/// time up to 24 to 31 bits, so values stay below 2^31 (the same with
/// dart2js); writes straight into a growing buffer.
final class _Inflater {
  new(List<int> data, this._at)
    : _data = data is Uint8List ? data : Uint8List.fromList(data),
      _out = Uint8List(
        data.length - _at > 0 ? (data.length - _at) * 4 + 64 : 64,
      );

  final Uint8List _data;
  int _at;
  int _bitBuffer = 0;
  int _bitCount = 0;
  Uint8List _out;
  int _pos = 0;

  /// Where the compressed data ended (after the last byte used).
  int get endOffset => _at - (_bitCount >> 3);

  /// Reads bytes while the buffer holds fewer than 24 bits and there are
  /// any.
  void _refill() {
    final data = _data;
    while (_bitCount < 24 && _at < data.length) {
      _bitBuffer |= data[_at++] << _bitCount;
      _bitCount += 8;
    }
  }

  int _bits(int need) {
    if (_bitCount < need) {
      _refill();
      if (_bitCount < need) throw _endedEarly;
    }
    final value = _bitBuffer & ((1 << need) - 1);
    _bitBuffer >>>= need;
    _bitCount -= need;
    return value;
  }

  int _decode(_Table table) {
    if (_bitCount < 15) _refill();
    final entries = table.entries;
    final root = table.rootBits;
    var entry = entries[_bitBuffer & ((1 << root) - 1)];
    if (entry & 0x80 != 0) {
      entry =
          entries[(entry >> 8) +
              ((_bitBuffer >>> root) & ((1 << (entry & 15)) - 1))];
    }
    final length = entry & 15;
    if (length == 0 || length > _bitCount) throw _badCode(length, _bitCount);
    _bitBuffer >>>= length;
    _bitCount -= length;
    return entry >> 8;
  }

  /// The error for a code of [length] (0: none) with [available] bits
  /// left: the bit-at-a-time decoder read 15 bits before it gave up on a
  /// code, so it ran out of data first when fewer were left.
  static FormatException _badCode(int length, int available) =>
      length == 0 && available >= 15
      ? const FormatException('invalid deflate code')
      : _endedEarly;

  void _grow(int need) {
    var size = _out.length * 2;
    while (size < _pos + need) {
      size *= 2;
    }
    _out = Uint8List(size)..setRange(0, _pos, _out);
  }

  Uint8List inflate() {
    var last = 0;
    do {
      last = _bits(1);
      switch (_bits(2)) {
        case 0:
          _stored();
        case 1:
          _codes(_fixedLiterals, _fixedDistances);
        case 2:
          final (literals, distances) = _dynamic();
          _codes(literals, distances);
        default:
          throw const FormatException('invalid deflate block type');
      }
    } while (last == 0);
    // A large result is a view of the buffer: the pages past its end were
    // never touched, and copying would fault in as many again.
    if (_pos == _out.length) return _out;
    if (_pos >= 1 << 18) return Uint8List.sublistView(_out, 0, _pos);
    return _out.sublist(0, _pos);
  }

  void _stored() {
    // Give back the whole bytes the buffer holds; the rest of the current
    // byte is padding.
    _at -= _bitCount >> 3;
    _bitBuffer = 0;
    _bitCount = 0;
    final data = _data;
    if (_at + 4 > data.length) throw _endedEarly;
    final length = data[_at] | (data[_at + 1] << 8);
    final check = data[_at + 2] | (data[_at + 3] << 8);
    _at += 4;
    if (length != (~check & 0xffff)) {
      throw const FormatException('invalid stored block length');
    }
    if (_at + length > data.length) throw _endedEarly;
    if (_pos + length > _out.length) _grow(length);
    _out.setRange(_pos, _pos + length, data, _at);
    _pos += length;
    _at += length;
  }

  (_Table, _Table) _dynamic() {
    final hlit = _bits(5) + 257;
    final hdist = _bits(5) + 1;
    final hclen = _bits(4) + 4;
    final clLengths = Uint8List(19);
    for (var k = 0; k < hclen; k++) {
      clLengths[_codeLengthOrder[k]] = _bits(3);
    }
    final cl = _table(clLengths, 0, 19, 7);
    final total = hlit + hdist;
    final lengths = Uint8List(total);
    var n = 0;
    while (n < total) {
      final symbol = _decode(cl);
      if (symbol < 16) {
        lengths[n++] = symbol;
        continue;
      }
      var value = 0;
      int repeat;
      if (symbol == 16) {
        if (n == 0) throw const FormatException('invalid repeat');
        value = lengths[n - 1];
        repeat = 3 + _bits(2);
      } else {
        repeat = symbol == 17 ? 3 + _bits(3) : 11 + _bits(7);
      }
      if (n + repeat > total) {
        throw const FormatException('too many code lengths');
      }
      lengths.fillRange(n, n + repeat, value);
      n += repeat;
    }
    return (_table(lengths, 0, hlit, 10), _table(lengths, hlit, hdist, 8));
  }

  /// Decodes the symbols of a compressed block up to its end-of-block code.
  void _codes(_Table literals, _Table distances) {
    final data = _data;
    final dataLength = data.length;
    final lit = literals.entries;
    final litRoot = literals.rootBits;
    final litMask = (1 << litRoot) - 1;
    final dist = distances.entries;
    final distRoot = distances.rootBits;
    final distMask = (1 << distRoot) - 1;
    var buffer = _bitBuffer;
    var count = _bitCount;
    var at = _at;
    var out = _out;
    var pos = _pos;
    while (true) {
      if (count < 15) {
        while (count < 24 && at < dataLength) {
          buffer |= data[at++] << count;
          count += 8;
        }
      }
      var entry = lit[buffer & litMask];
      if (entry & 0x80 != 0) {
        entry =
            lit[(entry >> 8) +
                ((buffer >>> litRoot) & ((1 << (entry & 15)) - 1))];
      }
      var length = entry & 15;
      if (length == 0 || length > count) throw _badCode(length, count);
      buffer >>>= length;
      count -= length;
      final symbol = entry >> 8;
      if (symbol < 256) {
        if (pos == out.length) {
          _pos = pos;
          _grow(1);
          out = _out;
        }
        out[pos++] = symbol;
        continue;
      }
      if (symbol == 256) break;
      final code = symbol - 257;
      if (code >= 29) throw const FormatException('invalid length code');
      length = _lengthBase[code];
      final lengthExtra = _lengthExtra[code];
      if (lengthExtra > 0) {
        if (count < lengthExtra) {
          while (count < 24 && at < dataLength) {
            buffer |= data[at++] << count;
            count += 8;
          }
          if (count < lengthExtra) throw _endedEarly;
        }
        length += buffer & ((1 << lengthExtra) - 1);
        buffer >>>= lengthExtra;
        count -= lengthExtra;
      }
      if (count < 15) {
        while (count < 24 && at < dataLength) {
          buffer |= data[at++] << count;
          count += 8;
        }
      }
      entry = dist[buffer & distMask];
      if (entry & 0x80 != 0) {
        entry =
            dist[(entry >> 8) +
                ((buffer >>> distRoot) & ((1 << (entry & 15)) - 1))];
      }
      final codeLength = entry & 15;
      if (codeLength == 0 || codeLength > count) {
        throw _badCode(codeLength, count);
      }
      buffer >>>= codeLength;
      count -= codeLength;
      final distCode = entry >> 8;
      if (distCode >= 30) {
        throw const FormatException('invalid distance code');
      }
      var distance = _distBase[distCode];
      final distExtra = _distExtra[distCode];
      if (distExtra > 0) {
        if (count < distExtra) {
          while (count < 24 && at < dataLength) {
            buffer |= data[at++] << count;
            count += 8;
          }
          if (count < distExtra) throw _endedEarly;
        }
        distance += buffer & ((1 << distExtra) - 1);
        buffer >>>= distExtra;
        count -= distExtra;
      }
      if (distance > pos) {
        throw const FormatException('distance too far back');
      }
      if (pos + length > out.length) {
        _pos = pos;
        _grow(length);
        out = _out;
      }
      final end = pos + length;
      if (distance == 1) {
        out.fillRange(pos, end, out[pos - 1]);
        pos = end;
      } else if (distance >= length && length > 16) {
        out.setRange(pos, end, out, pos - distance);
        pos = end;
      } else {
        for (var from = pos - distance; pos < end; pos++, from++) {
          out[pos] = out[from];
        }
      }
    }
    _bitBuffer = buffer;
    _bitCount = count;
    _at = at;
    _pos = pos;
  }
}
