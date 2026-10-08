/// A growable byte buffer that writes PDF tokens straight to bytes: numbers
/// by integer math, names and strings with their escapes. Content streams
/// are built in one.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_pdf/src/objects.dart';

/// Bytes appended in order, with PDF's number, name and string syntax.
///
/// A number [formatNumber] rejects throws as it does, and takes back what
/// was written since the last [commit]: content goes in whole operators,
/// as it did when each line was formatted before it was added.
@internal
final class ByteWriter {
  Uint8List _buffer = Uint8List(1024);

  /// The bytes written.
  int get length => _length;
  int _length = 0;

  int _committed = 0;

  /// Marks what is written so far as kept when a later number throws.
  @pragma('vm:prefer-inline')
  void commit() => _committed = _length;

  /// A copy of the bytes written.
  Uint8List toBytes() => _buffer.sublist(0, _length);

  @pragma('vm:prefer-inline')
  void _ensure(int extra) {
    if (_length + extra > _buffer.length) _grow(extra);
  }

  void _grow(int extra) {
    var size = _buffer.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _length, _buffer);
  }

  /// Appends [byte].
  @pragma('vm:prefer-inline')
  void byte(int byte) {
    _ensure(1);
    _buffer[_length++] = byte;
  }

  /// Appends [bytes].
  void bytes(List<int> bytes) {
    _ensure(bytes.length);
    _buffer.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  /// Appends the code units of [text] (ASCII).
  void ascii(String text) {
    _ensure(text.length);
    for (var i = 0; i < text.length; i++) {
      _buffer[_length++] = text.codeUnitAt(i);
    }
  }

  /// Appends [operator] and a line feed, and [commit]s.
  void operator(String operator) {
    _ensure(operator.length + 1);
    for (var i = 0; i < operator.length; i++) {
      _buffer[_length++] = operator.codeUnitAt(i);
    }
    _buffer[_length++] = 0x0a;
    _committed = _length;
  }

  /// Appends [value] in decimal, as `'$value'` writes it.
  void integer(int value) {
    if (value < 0) {
      byte(0x2d);
      _digits(-value);
    } else {
      _digits(value);
    }
  }

  /// Appends the digits of [value], at least 0.
  void _digits(int value) {
    _ensure(20);
    if (value < 10) {
      _buffer[_length++] = 0x30 + value;
      return;
    }
    var digits = 1;
    for (var rest = value; rest >= 10; rest ~/= 10) {
      digits++;
    }
    var at = _length + digits;
    _length = at;
    var rest = value;
    while (rest >= 10) {
      final quotient = rest ~/ 10;
      _buffer[--at] = 0x30 + (rest - quotient * 10);
      rest = quotient;
    }
    _buffer[--at] = 0x30 + rest;
  }

  /// Appends [value] as `formatNumber(value)` writes it.
  void numeric(num value) {
    if (value is! int) return number(value.toDouble(), 5);
    // Zero as formatNumber writes it (on the web, -0.0 is an int).
    if (value == 0 || value <= -_integerLimit || value >= _integerLimit) {
      return ascii(formatNumber(value));
    }
    integer(value);
  }

  static const int _integerLimit = 1000000000000000; // 1e15

  /// Appends [value] as `formatNumber(value, precision: precision)`
  /// writes it, byte for byte, computing the digits with integer math.
  ///
  /// `toStringAsFixed` rounds the exact binary value to the nearest
  /// multiple of 10^-precision, ties away from zero. The scaled value
  /// `|value| * 10^precision` is within half an ulp of the exact product,
  /// so wherever its fraction is clear of one half by more than that, it
  /// rounds the same way; at (or next to) a tie, and outside the exactly
  /// representable integers, [formatNumber] decides.
  void number(double value, int precision) {
    if (value == value.truncateToDouble() && value.abs() < 1e15) {
      // Zero goes the slow way: on the web, -0.0 is an int `formatNumber`
      // writes as `-0.0`.
      if (value == 0) return _slow(value, precision);
      return integer(value.toInt());
    }
    if (precision < 1 || precision > 9 || !value.isFinite) {
      return _slow(value, precision);
    }
    final negative = value < 0;
    final scaled = (negative ? -value : value) * _powersOfTen[precision];
    if (scaled >= 4503599627370496.0) return _slow(value, precision); // 2^52
    final floor = scaled.floorToDouble();
    final fraction = scaled - floor; // exact
    if ((fraction - 0.5).abs() <= scaled * 2.3e-16) {
      return _slow(value, precision);
    }
    var digits = (fraction > 0.5 ? floor + 1 : floor).toInt();
    if (digits == 0) return byte(0x30);
    var places = precision;
    while (places > 0 && digits % 10 == 0) {
      digits ~/= 10;
      places--;
    }
    if (negative) byte(0x2d);
    if (places == 0) return _digits(digits);
    final unit = _integerPowersOfTen[places];
    final whole = digits ~/ unit;
    var rest = digits - whole * unit;
    _digits(whole);
    _ensure(places + 1);
    _buffer[_length++] = 0x2e;
    var at = _length + places;
    _length = at;
    for (var i = 0; i < places; i++) {
      final quotient = rest ~/ 10;
      _buffer[--at] = 0x30 + (rest - quotient * 10);
      rest = quotient;
    }
  }

  void _slow(double value, int precision) {
    var formatted = false;
    try {
      ascii(formatNumber(value, precision: precision));
      formatted = true;
    } finally {
      // It threw: the operator being written goes too.
      if (!formatted) _length = _committed;
    }
  }

  static final Float64List _powersOfTen = Float64List.fromList(const [
    1, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, //
  ]);

  static const List<int> _integerPowersOfTen = [
    1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, //
    1000000000,
  ];

  /// Appends the name [value] (`/Name`), as [PdfName] writes it.
  void name(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x21 || c > 0x7e || _escaped[c]) {
        final out = BytesBuilder();
        PdfName(value).writeTo(out);
        return bytes(out.takeBytes());
      }
    }
    _ensure(value.length + 1);
    _buffer[_length++] = 0x2f;
    for (var i = 0; i < value.length; i++) {
      _buffer[_length++] = value.codeUnitAt(i);
    }
  }

  /// The ASCII characters a name escapes: the delimiters and `#`.
  static final List<bool> _escaped = List.generate(
    0x80,
    (c) => '()<>[]{}/%#'.codeUnits.contains(c),
  );

  /// Appends the bytes of [codes] (each taken modulo 256) from [start] to
  /// [end] as a string, as [PdfString] writes it: hexadecimal when [hex],
  /// else literal.
  void string(List<int> codes, int start, int end, {required bool hex}) {
    _ensure(2 * (end - start) + 2);
    if (hex) {
      _buffer[_length++] = 0x3c; // <
      for (var i = start; i < end; i++) {
        final b = codes[i] & 0xff;
        _buffer[_length++] = _hexDigits[b >> 4];
        _buffer[_length++] = _hexDigits[b & 0xf];
      }
      _buffer[_length++] = 0x3e; // >
      return;
    }
    _buffer[_length++] = 0x28; // (
    for (var i = start; i < end; i++) {
      final b = codes[i] & 0xff;
      switch (b) {
        case 0x28 || 0x29 || 0x5c: // ( ) \
          _buffer[_length++] = 0x5c;
          _buffer[_length++] = b;
        case 0x0d: // \r would be read as an end of line
          _buffer[_length++] = 0x5c;
          _buffer[_length++] = 0x72;
        default:
          _buffer[_length++] = b;
      }
    }
    _buffer[_length++] = 0x29; // )
  }

  static final Uint8List _hexDigits = Uint8List.fromList(
    '0123456789ABCDEF'.codeUnits,
  );
}
