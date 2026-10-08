/// Subsetting CFF font programs (Compact Font Format, Adobe TN 5176;
/// Type 2 charstrings, Adobe TN 5177): the glyphs a document uses keep
/// their charstrings and their glyph ids, the others become empty glyphs,
/// and the subroutines no kept glyph calls become empty too. Name-keyed
/// and CID-keyed fonts alike.
library;

import 'dart:typed_data';

import 'package:plain_fonts/src/byte_sink.dart';

/// The CFF table [cff] with only the charstrings of [glyphs] (glyph ids
/// kept; all of them when null) and the subroutines they call, and an
/// identity charset for a CID font; null when it can't be rewritten
/// (CFF2, `seac` accents, a damaged table), so the font is embedded whole.
Uint8List? subsetCff(Uint8List cff, Set<int>? glyphs) {
  try {
    return _Cff(cff).subset(glyphs);
  } on _Unsupported {
    return null;
    // A damaged table reads out of bounds: embed the font as it is.
    // ignore: avoid_catching_errors
  } on RangeError {
    return null;
  }
}

final class _Unsupported implements Exception {
  const new();
}

/// An INDEX of the CFF data: where each item starts, and where the last
/// one ends.
final class _Index {
  new(this.data, this.offsets);

  /// The empty INDEX.
  new empty(this.data) : offsets = Int32List(1);

  final Uint8List data;

  /// The start of each item in [data], then the end of the last.
  final Int32List offsets;

  int get length => offsets.length - 1;

  bool get isEmpty => offsets.length == 1;

  /// Item [i], as a view of [data].
  Uint8List operator [](int i) =>
      Uint8List.sublistView(data, offsets[i], offsets[i + 1]);
}

/// An INDEX to write: the items of [source], each kept as it is or (when
/// [kept] says no) replaced by the one-byte [stub].
final class _Rewrite {
  new(this.source, this.kept, this.stub);

  /// The items of [source] as they are.
  new copy(_Index source) : this(source, null, 0);

  final _Index source;
  final bool Function(int item)? kept;
  final int stub;

  int get length => source.length;

  bool get isEmpty => source.isEmpty;

  /// The size of the items' data.
  late final int dataSize = () {
    final kept = this.kept;
    final offsets = source.offsets;
    if (kept == null) return offsets[length] - offsets[0];
    var size = 0;
    for (var i = 0; i < length; i++) {
      size += kept(i) ? offsets[i + 1] - offsets[i] : 1;
    }
    return size;
  }();

  late final int _offSize = _Cff._offSize(dataSize + 1);

  /// The size of the INDEX as written.
  int get size => isEmpty ? 2 : 3 + (length + 1) * _offSize + dataSize;

  void writeTo(ByteSink out) {
    if (isEmpty) {
      out
        ..addByte(0)
        ..addByte(0);
      return;
    }
    final kept = this.kept;
    final offsets = source.offsets;
    final data = source.data;
    final offSize = _offSize;
    out
      ..u16(length)
      ..addByte(offSize);
    var offset = 1;
    _Cff._writeOffset(out, offset, offSize);
    for (var i = 0; i < length; i++) {
      offset += kept == null || kept(i) ? offsets[i + 1] - offsets[i] : 1;
      _Cff._writeOffset(out, offset, offSize);
    }
    if (kept == null) {
      out.addRange(data, offsets[0], offsets[length]);
      return;
    }
    for (var i = 0; i < length; i++) {
      if (kept(i)) {
        out.addRange(data, offsets[i], offsets[i + 1]);
      } else {
        out.addByte(stub);
      }
    }
  }
}

/// A DICT: operands by operator (two-byte operators as 1200 + the second
/// byte).
typedef _Dict = Map<int, List<num>>;

final class _Cff {
  new(this._data);

  final Uint8List _data;

  Uint8List subset(Set<int>? glyphs) {
    if (_data.isEmpty || _data[0] != 1) throw const _Unsupported();
    final hdrSize = _data[2];
    final (names, afterNames) = _index(hdrSize);
    final (topDicts, afterTop) = _index(afterNames);
    final (strings, afterStrings) = _index(afterTop);
    final (globalSubrs, _) = _index(afterStrings);
    if (topDicts.length != 1) throw const _Unsupported();
    final top = _dict(topDicts[0]);
    if (_int(top, 1206, 2) != 2) throw const _Unsupported();
    final (charStrings, _) = _index(_int(top, 17));
    final count = charStrings.length;
    bool kept(int g) => g == 0 || glyphs == null || glyphs.contains(g);
    final cid = top.containsKey(1230);

    // The private DICTs (one per font DICT for a CID font) and their local
    // subroutines, and which private DICT each glyph uses.
    final privates = <(_Dict, _Index)>[];
    final List<_Dict> fontDicts;
    Uint8List? fdSelect;
    int Function(int glyph) fdOf;
    if (cid) {
      final (fdArray, _) = _index(_int(top, 1236));
      fontDicts = [for (var i = 0; i < fdArray.length; i++) _dict(fdArray[i])];
      for (final fd in fontDicts) {
        privates.add(_private(fd));
      }
      final (select, selectEnd) = _fdSelect(_int(top, 1237), count);
      fdSelect = Uint8List.sublistView(_data, _int(top, 1237), selectEnd);
      fdOf = (glyph) => select[glyph];
    } else {
      fontDicts = const [];
      privates.add(_private(top));
      fdOf = (_) => 0;
    }

    // The subroutines the kept glyphs call.
    final usedGlobal = <int>{};
    final usedLocal = [for (final _ in privates) <int>{}];
    final charstring = _Charstring(_data, globalSubrs, usedGlobal);
    void visit(int glyph) {
      final fd = fdOf(glyph);
      charstring
        ..local = privates[fd].$2
        ..usedLocal = usedLocal[fd]
        ..start(charStrings.offsets[glyph], charStrings.offsets[glyph + 1]);
    }

    if (glyphs == null) {
      for (var g = 0; g < count; g++) {
        visit(g);
      }
    } else {
      for (final glyph in {0, ...glyphs}) {
        if (glyph < 0 || glyph >= count) continue;
        visit(glyph);
      }
    }

    // The layout: header, Name, Top DICT, String and Global Subr INDEXes,
    // then the charset, encoding, FDSelect, CharStrings, FDArray and the
    // private DICTs with their subroutines. Integers in DICTs are written
    // in 5 bytes, so a DICT's size doesn't depend on the offsets in it.
    // A CID font gets an identity charset: CID n is glyph n, as PDF text
    // addresses it.
    final charset = cid
        ? _identityCharset(count)
        : _optionalTable(top, 15, count);
    final encoding = cid ? null : _optionalTable(top, 16, count);
    final newCharStrings = _Rewrite(charStrings, kept, 0x0e); // endchar
    final newGlobal = _Rewrite(
      globalSubrs,
      usedGlobal.contains,
      0x0b, // return
    );
    // Each private DICT (pointing at its subroutines right after it), and
    // its subroutines.
    final privateParts = [
      for (final (fd, (private, subrs)) in privates.indexed)
        (
          _writeDict(_withSubrs(private, isEmpty: subrs.isEmpty)),
          _Rewrite(subrs, usedLocal[fd].contains, 0x0b),
        ),
    ];

    Uint8List fdArray(List<int> offsets) => _writeIndex([
      for (final (i, fd) in fontDicts.indexed)
        _writeDict({
          ...fd,
          18: [privateParts[i].$1.length, offsets[5 + i]],
        }),
    ]);

    Uint8List topDict(List<int> offsets) {
      final newTop = {...top}
        ..[17] = [offsets[3]]
        ..remove(18)
        ..remove(1236)
        ..remove(1237);
      if (charset != null) newTop[15] = [offsets[0]];
      if (encoding != null) newTop[16] = [offsets[1]];
      if (cid) {
        newTop[1236] = [offsets[4]];
        newTop[1237] = [offsets[2]];
      } else {
        newTop[18] = [privateParts[0].$1.length, offsets[5]];
      }
      return _writeIndex([_writeDict(newTop)]);
    }

    // Sizes don't depend on offsets: measure with zeros, then place the
    // parts after the INDEXes: charset, encoding, FDSelect, CharStrings,
    // FDArray, then each private DICT.
    final zeros = List.filled(5 + privateParts.length, 0);
    final names2 = _Rewrite.copy(names);
    final strings2 = _Rewrite.copy(strings);
    var at =
        hdrSize +
        names2.size +
        topDict(zeros).length +
        strings2.size +
        newGlobal.size;
    final offsets = <int>[];
    for (final size in [
      charset?.length ?? 0,
      encoding?.length ?? 0,
      fdSelect?.length ?? 0,
      newCharStrings.size,
      if (cid) fdArray(zeros).length else 0,
      for (final (dict, subrs) in privateParts)
        dict.length + (subrs.isEmpty ? 0 : subrs.size),
    ]) {
      offsets.add(at);
      at += size;
    }
    final out = ByteSink(at)..addRange(_data, 0, hdrSize);
    names2.writeTo(out);
    out.add(topDict(offsets));
    strings2.writeTo(out);
    newGlobal.writeTo(out);
    if (charset != null) out.add(charset);
    if (encoding != null) out.add(encoding);
    if (fdSelect != null) out.add(fdSelect);
    newCharStrings.writeTo(out);
    if (cid) out.add(fdArray(offsets));
    for (final (dict, subrs) in privateParts) {
      out.add(dict);
      if (!subrs.isEmpty) subrs.writeTo(out);
    }
    return out.takeBytes();
  }

  /// A charset that gives glyph n the CID n (format 2, one range).
  static Uint8List _identityCharset(int glyphs) {
    if (glyphs < 2) return Uint8List.fromList([0]);
    final left = glyphs - 2;
    return Uint8List.fromList([2, 0, 1, left >> 8, left & 0xff]);
  }

  /// A private DICT and its local subroutines, from the `Private` entry
  /// of [dict].
  (_Dict, _Index) _private(_Dict dict) {
    final entry = dict[18];
    if (entry == null || entry.length != 2) {
      return (<int, List<num>>{}, _Index.empty(_data));
    }
    final size = entry[0].toInt();
    final offset = entry[1].toInt();
    final private = _dict(Uint8List.sublistView(_data, offset, offset + size));
    final subrs = private.containsKey(19)
        ? _index(offset + _int(private, 19)).$1
        : _Index.empty(_data);
    return (private, subrs);
  }

  /// [dict] pointing at its subroutines right after it (or without
  /// them, when it has none).
  static _Dict _withSubrs(_Dict dict, {required bool isEmpty}) {
    final copy = {...dict}..remove(19);
    if (isEmpty) return copy;
    // The offset is the DICT's own size, which includes the offset's 5
    // bytes.
    final size = _writeDict({
      ...copy,
      19: [0],
    }).length;
    return copy..[19] = [size];
  }

  /// The charset or encoding table at the offset of [key] in [top], when
  /// it isn't a predefined one (offsets 0–2), copied as it is.
  Uint8List? _optionalTable(_Dict top, int key, int glyphs) {
    final offset = top[key]?.firstOrNull?.toInt();
    if (offset == null || offset <= 2) return null;
    final end = key == 15 ? _charsetEnd(offset, glyphs) : _encodingEnd(offset);
    return Uint8List.sublistView(_data, offset, end);
  }

  int _charsetEnd(int offset, int glyphs) {
    final format = _data[offset];
    var at = offset + 1;
    switch (format) {
      case 0:
        return at + 2 * (glyphs - 1);
      case 1 || 2:
        var covered = 1;
        while (covered < glyphs) {
          final left = format == 1
              ? _data[at + 2]
              : _data[at + 2] << 8 | _data[at + 3];
          at += format == 1 ? 3 : 4;
          covered += left + 1;
        }
        return at;
      default:
        throw const _Unsupported();
    }
  }

  int _encodingEnd(int offset) {
    final format = _data[offset];
    var at = offset + 1;
    switch (format & 0x7f) {
      case 0:
        at += 1 + _data[at];
      case 1:
        at += 1 + 2 * _data[at];
      default:
        throw const _Unsupported();
    }
    if (format & 0x80 != 0) at += 1 + 3 * _data[at];
    return at;
  }

  /// The font DICT of each glyph, and where the FDSelect ends.
  (List<int>, int) _fdSelect(int offset, int glyphs) {
    final format = _data[offset];
    switch (format) {
      case 0:
        return (
          [for (var g = 0; g < glyphs; g++) _data[offset + 1 + g]],
          offset + 1 + glyphs,
        );
      case 3:
        final ranges = _data[offset + 1] << 8 | _data[offset + 2];
        final select = List.filled(glyphs, 0);
        var at = offset + 3;
        for (var r = 0; r < ranges; r++) {
          final first = _data[at] << 8 | _data[at + 1];
          final fd = _data[at + 2];
          final next = _data[at + 3] << 8 | _data[at + 4];
          for (var g = first; g < next && g < glyphs; g++) {
            select[g] = fd;
          }
          at += 3;
        }
        return (select, at + 2);
      default:
        throw const _Unsupported();
    }
  }

  /// The INDEX at [at] and where it ends; throws a [RangeError] when an
  /// item would be outside the data.
  (_Index, int) _index(int at) {
    final count = _data[at] << 8 | _data[at + 1];
    if (count == 0) return (_Index.empty(_data), at + 2);
    final offSize = _data[at + 2];
    int offset(int i) {
      var value = 0;
      for (var k = 0; k < offSize; k++) {
        value = value << 8 | _data[at + 3 + i * offSize + k];
      }
      return value;
    }

    final base = at + 3 + (count + 1) * offSize - 1;
    final offsets = Int32List(count + 1);
    var previous = base + offset(0);
    if (previous < 0 || previous > _data.length) {
      throw RangeError.range(previous, 0, _data.length);
    }
    offsets[0] = previous;
    for (var i = 1; i <= count; i++) {
      final next = base + offset(i);
      if (next < previous || next > _data.length) {
        throw RangeError.range(next, previous, _data.length);
      }
      offsets[i] = previous = next;
    }
    return (_Index(_data, offsets), previous);
  }

  static int _int(_Dict dict, int key, [int? fallback]) {
    final value = dict[key]?.firstOrNull;
    if (value == null) {
      if (fallback != null) return fallback;
      throw const _Unsupported();
    }
    return value.toInt();
  }

  /// The DICT in [bytes].
  static _Dict _dict(Uint8List bytes) {
    final dict = <int, List<num>>{};
    var operands = <num>[];
    var at = 0;
    while (at < bytes.length) {
      final b0 = bytes[at];
      if (b0 <= 21) {
        var key = b0;
        at++;
        if (b0 == 12) key = 1200 + bytes[at++];
        dict[key] = operands;
        operands = <num>[];
      } else if (b0 == 28) {
        operands.add(_signed16(bytes[at + 1] << 8 | bytes[at + 2]));
        at += 3;
      } else if (b0 == 29) {
        operands.add(ByteData.sublistView(bytes, at + 1, at + 5).getInt32(0));
        at += 5;
      } else if (b0 == 30) {
        final (value, end) = _real(bytes, at + 1);
        operands.add(value);
        at = end;
      } else if (b0 >= 32 && b0 <= 246) {
        operands.add(b0 - 139);
        at++;
      } else if (b0 >= 247 && b0 <= 250) {
        operands.add((b0 - 247) * 256 + bytes[at + 1] + 108);
        at += 2;
      } else if (b0 >= 251 && b0 <= 254) {
        operands.add(-(b0 - 251) * 256 - bytes[at + 1] - 108);
        at += 2;
      } else {
        throw const _Unsupported();
      }
    }
    return dict;
  }

  static (num, int) _real(Uint8List bytes, int start) {
    final text = StringBuffer();
    var at = start;
    outer:
    while (true) {
      final byte = bytes[at++];
      for (final nibble in [byte >> 4, byte & 0xf]) {
        switch (nibble) {
          case <= 9:
            text.write(nibble);
          case 0xa:
            text.write('.');
          case 0xb:
            text.write('E');
          case 0xc:
            text.write('E-');
          case 0xe:
            text.write('-');
          case 0xf:
            break outer;
        }
      }
    }
    return (num.tryParse(text.toString()) ?? 0, at);
  }

  static int _signed16(int value) => value >= 0x8000 ? value - 0x10000 : value;

  /// [dict] as DICT data: integers that are offsets (and every other
  /// integer) in the 5-byte form, reals as reals.
  static Uint8List _writeDict(_Dict dict) {
    final out = ByteSink();
    final keys = dict.keys.toList()
      // ROS must come first in a CID font's Top DICT; SyntheticBase too.
      ..sort((a, b) => a == 1230 ? -1 : (b == 1230 ? 1 : 0));
    for (final key in keys) {
      for (final operand in dict[key]!) {
        if (operand is int ||
            (operand is double && operand == operand.roundToDouble())) {
          final value = operand.toInt();
          out
            ..addByte(29)
            ..u32(value);
        } else {
          out
            ..addByte(30)
            ..add(_encodeReal(operand.toDouble()));
        }
      }
      if (key >= 1200) {
        out
          ..addByte(12)
          ..addByte(key - 1200);
      } else {
        out.addByte(key);
      }
    }
    return out.takeBytes();
  }

  static List<int> _encodeReal(double value) {
    final text = value.toString().replaceAll('e', 'E');
    final nibbles = <int>[];
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == 'E' && i + 1 < text.length && text[i + 1] == '-') {
        nibbles.add(0xc);
        i++;
      } else if (char == 'E') {
        nibbles.add(0xb);
      } else if (char == '.') {
        nibbles.add(0xa);
      } else if (char == '-') {
        nibbles.add(0xe);
      } else if (char == '+') {
        continue;
      } else {
        nibbles.add(int.parse(char));
      }
    }
    nibbles.add(0xf);
    if (nibbles.length.isOdd) nibbles.add(0xf);
    return [
      for (var i = 0; i < nibbles.length; i += 2)
        nibbles[i] << 4 | nibbles[i + 1],
    ];
  }

  /// The offset size of an INDEX whose last offset is [last].
  static int _offSize(int last) => last <= 0xff
      ? 1
      : last <= 0xffff
      ? 2
      : last <= 0xffffff
      ? 3
      : 4;

  static void _writeOffset(ByteSink out, int value, int offSize) {
    for (var k = offSize - 1; k >= 0; k--) {
      out.addByte((value >> (8 * k)) & 0xff);
    }
  }

  static Uint8List _writeIndex(List<Uint8List> items) {
    if (items.isEmpty) return Uint8List.fromList([0, 0]);
    final total = items.fold<int>(0, (sum, item) => sum + item.length) + 1;
    final offSize = _offSize(total);
    final out = ByteSink(3 + (items.length + 1) * offSize + total - 1)
      ..u16(items.length)
      ..addByte(offSize);
    var offset = 1;
    _writeOffset(out, offset, offSize);
    for (final item in items) {
      offset += item.length;
      _writeOffset(out, offset, offSize);
    }
    items.forEach(out.add);
    return out.takeBytes();
  }
}

/// Runs Type 2 charstrings far enough to find the subroutines they call
/// (their operands, the stems before a hint mask): one glyph at a time,
/// in the CFF data itself.
final class _Charstring {
  new(this._data, this._global, this._usedGlobal)
    : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  final _Index _global;
  final Set<int> _usedGlobal;

  /// The local subroutines of the glyph, and those it calls.
  late _Index local;
  late Set<int> usedLocal;

  /// The operands (only their count and the last one matter).
  Int32List _stack = Int32List(48);
  int _top = 0;
  int _stems = 0;
  bool _hintsDone = false;
  int _depth = 0;

  static int _bias(int count) => count < 1240
      ? 107
      : count < 33900
      ? 1131
      : 32768;

  /// Runs the glyph whose charstring is the data from [start] to [end].
  void start(int start, int end) {
    _top = 0;
    _stems = 0;
    _hintsDone = false;
    _depth = 0;
    _run(start, end);
  }

  void _push(int value) {
    if (_top == _stack.length) {
      _stack = Int32List(_stack.length * 2)..setRange(0, _top, _stack);
    }
    _stack[_top++] = value;
  }

  int _pop() {
    if (_top == 0) throw const _Unsupported();
    return _stack[--_top];
  }

  void _run(int start, int end) {
    if (++_depth > 10) throw const _Unsupported();
    final code = _data;
    var at = start;
    while (at < end) {
      final b0 = code[at];
      if (b0 >= 32 || b0 == 28) {
        if (b0 == 28) {
          if (at + 3 > end) throw const _Unsupported();
          _push(_Cff._signed16(code[at + 1] << 8 | code[at + 2]));
          at += 3;
        } else if (b0 <= 246) {
          _push(b0 - 139);
          at++;
        } else if (b0 <= 250) {
          if (at + 2 > end) throw const _Unsupported();
          _push((b0 - 247) * 256 + code[at + 1] + 108);
          at += 2;
        } else if (b0 <= 254) {
          if (at + 2 > end) throw const _Unsupported();
          _push(-(b0 - 251) * 256 - code[at + 1] - 108);
          at += 2;
        } else {
          // 16.16 fixed (only its integer part is ever used).
          if (at + 5 > end) throw const _Unsupported();
          _push(_view.getInt32(at + 1) ~/ 65536);
          at += 5;
        }
        continue;
      }
      at++;
      switch (b0) {
        case 1 || 3 || 18 || 23: // hstem, vstem, hstemhm, vstemhm
          _stems += _top ~/ 2;
          _top = 0;
        case 19 || 20: // hintmask, cntrmask
          if (!_hintsDone) {
            // Implicit vstem before the first mask.
            _stems += _top ~/ 2;
            _hintsDone = true;
          }
          _top = 0;
          at += (_stems + 7) ~/ 8;
        case 10: // callsubr
          final subrs = local;
          final index = _pop() + _bias(subrs.length);
          if (index < 0 || index >= subrs.length) throw const _Unsupported();
          usedLocal.add(index);
          _run(subrs.offsets[index], subrs.offsets[index + 1]);
        case 29: // callgsubr
          final index = _pop() + _bias(_global.length);
          if (index < 0 || index >= _global.length) {
            throw const _Unsupported();
          }
          _usedGlobal.add(index);
          _run(_global.offsets[index], _global.offsets[index + 1]);
        case 11: // return
          _depth--;
          return;
        case 14: // endchar
          // With four or more arguments it's a `seac` accent, which refers
          // to other glyphs by standard encoding.
          if (_top >= 4) throw const _Unsupported();
          _depth--;
          return;
        case 12:
          at++;
          _top = 0;
        default:
          _top = 0;
      }
    }
    _depth--;
  }
}
