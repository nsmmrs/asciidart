/// A growable byte buffer with big-endian writers, for the font writers
/// (CFF and TrueType subsets, WOFF and WOFF2 decoding).
library;

import 'dart:typed_data';

/// Bytes written one after another into one buffer, doubled as it fills
/// (unlike `BytesBuilder(copy: false)`, which allocates a list per
/// `addByte`).
final class ByteSink {
  /// A sink with room for [capacity] bytes before it grows: given the
  /// exact size, [takeBytes] returns the buffer itself.
  new([int capacity = 256]) : _bytes = Uint8List(capacity);

  Uint8List _bytes;
  int _length = 0;

  /// The number of bytes written.
  int get length => _length;

  void _grow(int extra) {
    final needed = _length + extra;
    var size = _bytes.length < 64 ? 64 : _bytes.length * 2;
    while (size < needed) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
  }

  /// Writes the byte [value] (its low 8 bits).
  void addByte(int value) {
    if (_length == _bytes.length) _grow(1);
    _bytes[_length++] = value;
  }

  /// Writes [bytes].
  void add(List<int> bytes) {
    final end = _length + bytes.length;
    if (end > _bytes.length) _grow(bytes.length);
    _bytes.setRange(_length, end, bytes);
    _length = end;
  }

  /// Writes the bytes of [source] from [start] to [end].
  void addRange(Uint8List source, int start, int end) {
    final length = _length + end - start;
    if (length > _bytes.length) _grow(end - start);
    _bytes.setRange(_length, length, source, start);
    _length = length;
  }

  /// Writes [count] zero bytes.
  void zeros(int count) {
    if (count <= 0) return;
    final end = _length + count;
    if (end > _bytes.length) _grow(count);
    _bytes.fillRange(_length, end, 0);
    _length = end;
  }

  /// Writes the 16-bit [value] (signed or not), big-endian.
  void u16(int value) {
    if (_length + 2 > _bytes.length) _grow(2);
    _bytes[_length] = value >> 8;
    _bytes[_length + 1] = value;
    _length += 2;
  }

  /// Writes the 32-bit [value] (signed or not), big-endian.
  void u32(int value) {
    if (_length + 4 > _bytes.length) _grow(4);
    _bytes[_length] = value >> 24;
    _bytes[_length + 1] = value >> 16;
    _bytes[_length + 2] = value >> 8;
    _bytes[_length + 3] = value;
    _length += 4;
  }

  /// The bytes written (the buffer itself when it is full, else a view of
  /// it: never use its `buffer`), and an empty sink.
  Uint8List takeBytes() {
    final bytes = _length == _bytes.length
        ? _bytes
        : Uint8List.sublistView(_bytes, 0, _length);
    _bytes = Uint8List(0);
    _length = 0;
    return bytes;
  }
}
