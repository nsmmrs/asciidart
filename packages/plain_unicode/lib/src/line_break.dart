/// Line break opportunities by the Unicode Line Breaking Algorithm
/// (UAX #14, Unicode 18.0), with its default rules.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_unicode/src/line_break_data.g.dart' as data;

/// A Line_Break class (UAX #14, 5.1).
enum LineBreakClass {
  /// Mandatory break.
  bk,

  /// Carriage return.
  cr,

  /// Line feed.
  lf,

  /// Combining mark.
  cm,

  /// Next line.
  nl,

  /// Surrogate.
  sg,

  /// Word joiner.
  wj,

  /// Zero width space.
  zw,

  /// Non-breaking ("glue").
  gl,

  /// Space.
  sp,

  /// Zero width joiner.
  zwj,

  /// Break opportunity before and after.
  b2,

  /// Break after.
  ba,

  /// Break before.
  bb,

  /// Hyphen.
  hy,

  /// Contingent break.
  cb,

  /// Close punctuation.
  cl,

  /// Close parenthesis.
  cp,

  /// Exclamation or interrogation.
  ex,

  /// Inseparable.
  in_,

  /// Nonstarter.
  ns,

  /// Open punctuation.
  op,

  /// Quotation.
  qu,

  /// Infix numeric separator.
  is_,

  /// Numeric.
  nu,

  /// Postfix numeric.
  po,

  /// Prefix numeric.
  pr,

  /// Symbols allowing a break after.
  sy,

  /// Ambiguous (alphabetic or ideographic).
  ai,

  /// Aksara.
  ak,

  /// Alphabetic.
  al,

  /// Aksara prebase.
  ap,

  /// Aksara start.
  as_,

  /// Conditional Japanese starter.
  cj,

  /// Emoji base.
  eb,

  /// Emoji modifier.
  em,

  /// Hangul LV syllable.
  h2,

  /// Hangul LVT syllable.
  h3,

  /// Unambiguous hyphen.
  hh,

  /// Hebrew letter.
  hl,

  /// Ideographic.
  id,

  /// Hangul L jamo.
  jl,

  /// Hangul V jamo.
  jv,

  /// Hangul T jamo.
  jt,

  /// Regional indicator.
  ri,

  /// Complex context dependent (South East Asian).
  sa,

  /// Virama final.
  vf,

  /// Virama.
  vi,

  /// Unknown.
  xx,
}

// The flags of a code point's properties (bits 12-15; see
// line_break_data.g.dart).
const int _eastAsian = 1 << 12;
const int _initialPunctuation = 1 << 13;
const int _finalPunctuation = 1 << 14;
const int _unassignedPictographic = 1 << 15;

/// The line breaking properties of every code point, decoded on first use
/// from the generated three-stage table.
final class _PropertyTable {
  new()
    : palette = Uint16List.fromList(data.palette),
      stage1 = _words(data.stage1),
      stage2 = _words(data.stage2),
      stage3 = base64.decode(data.stage3);

  final Uint16List palette;
  final Uint16List stage1;
  final Uint16List stage2;
  final Uint8List stage3;

  /// The properties of [codePoint] (0 to 0x10FFFF): its class (bits 0-5),
  /// the class the rules use (bits 6-11) and its flags.
  @pragma('vm:prefer-inline')
  @pragma('dart2js:prefer-inline')
  int operator [](int codePoint) =>
      palette[stage3[stage2[stage1[codePoint >> 11] + (codePoint >> 5 & 63)] +
          (codePoint & 31)]];

  /// The little-endian 16-bit integers of [encoded], in base64.
  static Uint16List _words(String encoded) {
    final bytes = base64.decode(encoded);
    final words = Uint16List(bytes.length >> 1);
    for (var i = 0; i < words.length; i++) {
      words[i] = bytes[2 * i] | bytes[2 * i + 1] << 8;
    }
    return words;
  }
}

final _PropertyTable _properties = _PropertyTable();

/// The Line_Break class of [codePoint], as in the Unicode data.
LineBreakClass lineBreakClass(int codePoint) {
  final c = codePoint < 0 ? 0 : (codePoint > 0x10ffff ? 0x10ffff : codePoint);
  return LineBreakClass.values[_properties[c] & 0x3f];
}

/// A place text may (or must) be broken: before the code unit at
/// [offset].
@immutable
final class LineBreak {
  /// A break before [offset]; [mandatory] after a hard line break.
  const new(this.offset, {required this.mandatory});

  /// The code unit offset of the break.
  final int offset;

  /// Whether the line must end here (after a line feed, a paragraph
  /// separator...).
  final bool mandatory;

  @override
  bool operator ==(Object other) =>
      other is LineBreak &&
      other.offset == offset &&
      other.mandatory == mandatory;

  @override
  int get hashCode => Object.hash(offset, mandatory);

  @override
  String toString() => 'LineBreak($offset${mandatory ? ', mandatory' : ''})';
}

/// The break opportunities in [text], in order: every position the
/// default rules of UAX #14 allow a break at, and the end of the text
/// (mandatory). A break at offset 0 is never reported.
List<LineBreak> lineBreaks(String text) => [
  for (final code in _breakCodes(text))
    LineBreak(code >> 1, mandatory: code & 1 != 0),
];

/// The break opportunities of a text, as [lineBreakOffsets] finds them:
/// what [lineBreaks] lists, in one list of integers instead of an object
/// for each break.
extension type const LineBreakOffsets._(List<int> _codes) {
  /// The number of break opportunities.
  int get length => _codes.length;

  /// The code unit offset of the break opportunity at [index]: the text
  /// may break before the code unit there.
  int offsetAt(int index) => _codes[index] >> 1;

  /// Whether the line must end at the break opportunity at [index].
  bool isMandatoryAt(int index) => _codes[index] & 1 != 0;
}

/// The break opportunities in [text], in order, as [lineBreaks] finds
/// them, without an object for each: for hot paths.
LineBreakOffsets lineBreakOffsets(String text) =>
    LineBreakOffsets._(_breakCodes(text));

// The classes, as integers: the indexes of LineBreakClass.
const int _bk = 0;
const int _cr = 1;
const int _lf = 2;
const int _cm = 3;
const int _nl = 4;
const int _wj = 6;
const int _zw = 7;
const int _gl = 8;
const int _sp = 9;
const int _zwj = 10;
const int _b2 = 11;
const int _ba = 12;
const int _bb = 13;
const int _hy = 14;
const int _cb = 15;
const int _cl = 16;
const int _cp = 17;
const int _ex = 18;
const int _in = 19;
const int _ns = 20;
const int _op = 21;
const int _qu = 22;
const int _is = 23;
const int _nu = 24;
const int _po = 25;
const int _pr = 26;
const int _sy = 27;
const int _ak = 29;
const int _al = 30;
const int _ap = 31;
const int _as = 32;
const int _eb = 34;
const int _em = 35;
const int _h2 = 36;
const int _h3 = 37;
const int _hh = 38;
const int _hl = 39;
const int _id = 40;
const int _jl = 41;
const int _jv = 42;
const int _jt = 43;
const int _ri = 44;
const int _vf = 46;
const int _vi = 47;

// The flags of a unit: its base character's (the properties' bits 12-15,
// shifted down), and two of its own.
const int _eastAsianUnit = _eastAsian >> 12;
const int _initialUnit = _initialPunctuation >> 12;
const int _finalUnit = _finalPunctuation >> 12;
const int _unassignedPictographicUnit = _unassignedPictographic >> 12;

/// The unit ends with a zero width joiner (LB8a).
const int _joiner = 1 << 4;

/// The unit's base is U+25CC DOTTED CIRCLE (LB28a).
const int _dottedCircle = 1 << 5;

// The sets of classes the rules test, as bits of a class's entry in
// [_classSets] (not as bit masks of classes: JavaScript's are 32 bits).
const int _noBase = 1;
const int _beforeInitialQuote = 2;
const int _afterFinalQuote = 4;
const int _beforeWordInitialHyphen = 8;
const int _korean = 16;

/// The sets each class is in.
final Uint8List _classSets = () {
  final sets = Uint8List(64);
  void add(int set, List<int> classes) {
    for (final c in classes) {
      sets[c] |= set;
    }
  }

  add(_noBase, [_bk, _cr, _lf, _nl, _sp, _zw]);
  add(_beforeInitialQuote, [_bk, _cr, _lf, _nl, _op, _qu, _gl, _sp, _zw]);
  add(_afterFinalQuote, [
    ...[_sp, _gl, _wj, _cl, _qu, _cp, _ex, _is, _sy, _bk, _cr, _lf, _nl],
    _zw,
  ]);
  add(_beforeWordInitialHyphen, [_bk, _cr, _lf, _nl, _sp, _zw, _cb, _gl]);
  add(_korean, [_jl, _jv, _jt, _h2, _h3]);
  return sets;
}();

/// The units of the rules (a character with the combining marks and
/// joiners after it, LB9), as parallel lists: each unit's resolved class,
/// flags and code unit offset. Reused from text to text, they only grow,
/// up to [_retainedUnits] units.
Uint8List _unitClasses = Uint8List(256);
Uint8List _unitFlags = Uint8List(256);
Int32List _unitStarts = Int32List(256);

/// The most units kept between calls; longer texts get lists of their
/// own.
const int _retainedUnits = 1 << 16;

/// The break opportunities in [text], each as its code unit offset
/// shifted left once, plus 1 if the break is mandatory.
List<int> _breakCodes(String text) {
  final length = text.length;
  var classes = _unitClasses;
  var flags = _unitFlags;
  var starts = _unitStarts;
  if (length > classes.length) {
    final size = length > _retainedUnits
        ? length
        : math.min(math.max(length, classes.length * 2), _retainedUnits);
    classes = Uint8List(size);
    flags = Uint8List(size);
    starts = Int32List(size);
    if (size <= _retainedUnits) {
      _unitClasses = classes;
      _unitFlags = flags;
      _unitStarts = starts;
    }
  }
  final count = _units(text, classes, flags, starts);
  final codes = <int>[];
  // The unit before the spaces that end before unit i (or -1).
  var spaced = -1;
  for (var i = 1; i < count; i++) {
    if (classes[i - 1] != _sp) spaced = i - 1;
    final decision = _decide(classes, flags, count, i, spaced);
    if (decision != _keep) {
      codes.add(starts[i] << 1 | (decision == _mandatory ? 1 : 0));
    }
  }
  if (length > 0) codes.add(length << 1 | 1);
  return codes;
}

/// Fills [classes], [flags] and [starts] with the units of [text]:
/// classes resolved (LB1), combining marks attached to their base (LB9)
/// or made alphabetic (LB10). Returns the number of units.
int _units(String text, Uint8List classes, Uint8List flags, Int32List starts) {
  final table = _properties;
  final sets = _classSets;
  final length = text.length;
  var count = 0;
  var i = 0;
  while (i < length) {
    final start = i;
    var rune = text.codeUnitAt(i++);
    if (rune & 0xfc00 == 0xd800 && i < length) {
      final low = text.codeUnitAt(i);
      if (low & 0xfc00 == 0xdc00) {
        rune = 0x10000 + ((rune & 0x3ff) << 10) + (low & 0x3ff);
        i++;
      }
    }
    final properties = table[rune];
    final cls = properties >> 6 & 0x3f;
    if (cls == _cm || cls == _zwj) {
      final joiner = cls == _zwj ? _joiner : 0;
      if (count > 0 && sets[classes[count - 1]] & _noBase == 0) {
        // LB9: part of the base's unit.
        flags[count - 1] = flags[count - 1] & ~_joiner | joiner;
        continue;
      }
      // LB10: as if it were U+0041 A.
      classes[count] = _al;
      flags[count] = joiner;
      starts[count++] = start;
      continue;
    }
    classes[count] = cls;
    flags[count] = properties >> 12 | (rune == 0x25cc ? _dottedCircle : 0);
    starts[count++] = start;
  }
  return count;
}

// The decisions between two units.
const int _keep = 0;
const int _allow = 1;
const int _mandatory = 2;

/// AK, U+25CC DOTTED CIRCLE, or AS (the `(AK | [◌] | AS)` of LB28a).
bool _aksara(Uint8List classes, Uint8List flags, int i) =>
    classes[i] == _ak || flags[i] & _dottedCircle != 0 || classes[i] == _as;

/// AK or U+25CC DOTTED CIRCLE.
bool _aksaraOrCircle(Uint8List classes, Uint8List flags, int i) =>
    classes[i] == _ak || flags[i] & _dottedCircle != 0;

/// Whether the text may break between units `i - 1` and `i` of the
/// [count] in [classes] and [flags]; [spaced] is the unit before the
/// spaces that end before `i`, or -1.
int _decide(Uint8List classes, Uint8List flags, int count, int i, int spaced) {
  final b = classes[i - 1];
  final a = classes[i];
  final before = flags[i - 1];
  final after = flags[i];
  final s = spaced >= 0 ? classes[spaced] : -1;
  final sets = _classSets;

  // LB4, LB5: hard line breaks.
  if (b == _bk) return _mandatory;
  if (b == _cr && a == _lf) return _keep;
  if (b == _cr || b == _lf || b == _nl) return _mandatory;
  // LB6.
  if (a == _bk || a == _cr || a == _lf || a == _nl) return _keep;
  // LB7.
  if (a == _sp || a == _zw) return _keep;
  // LB8: ZW SP* ÷
  if (s == _zw) return _allow;
  // LB8a.
  if (before & _joiner != 0) return _keep;
  // LB11.
  if (a == _wj || b == _wj) return _keep;
  // LB12.
  if (b == _gl) return _keep;
  // LB12a.
  if (a == _gl && b != _sp && b != _hy && b != _hh) return _keep;
  // LB13.
  if (a == _cl || a == _cp || a == _ex || a == _sy) return _keep;
  // LB14: OP SP* ×
  if (s == _op) return _keep;
  // LB15a: (sot | BK | CR | LF | NL | OP | QU | GL | SP | ZW) [Pi&QU] SP* ×
  if (s == _qu && flags[spaced] & _initialUnit != 0) {
    if (spaced == 0 || sets[classes[spaced - 1]] & _beforeInitialQuote != 0) {
      return _keep;
    }
  }
  // LB15b: × [Pf&QU] (SP | GL | WJ | CL | QU | CP | EX | IS | SY | BK | CR |
  // LF | NL | ZW | eot)
  if (a == _qu && after & _finalUnit != 0) {
    if (i + 1 == count || sets[classes[i + 1]] & _afterFinalQuote != 0) {
      return _keep;
    }
  }
  // LB15c: SP ÷ IS NU
  if (b == _sp && a == _is && i + 1 < count && classes[i + 1] == _nu) {
    return _allow;
  }
  // LB15d.
  if (a == _is) return _keep;
  // LB16: (CL | CP) SP* × NS
  if (a == _ns && (s == _cl || s == _cp)) return _keep;
  // LB17: B2 SP* × B2
  if (a == _b2 && s == _b2) return _keep;
  // LB18.
  if (b == _sp) return _allow;
  // LB19.
  if (a == _qu && after & _initialUnit == 0) return _keep;
  if (b == _qu && before & _finalUnit == 0) return _keep;
  // LB19a.
  if (a == _qu) {
    if (before & _eastAsianUnit == 0) return _keep;
    if (i + 1 == count || flags[i + 1] & _eastAsianUnit == 0) return _keep;
  }
  if (b == _qu) {
    if (after & _eastAsianUnit == 0) return _keep;
    if (i < 2 || flags[i - 2] & _eastAsianUnit == 0) return _keep;
  }
  // LB20.
  if (a == _cb || b == _cb) return _allow;
  // LB20a: (sot | BK | CR | LF | NL | SP | ZW | CB | GL) (HY | HH) ×
  // (AL | HL)
  if ((b == _hy || b == _hh) && (a == _al || a == _hl)) {
    if (i < 2 || sets[classes[i - 2]] & _beforeWordInitialHyphen != 0) {
      return _keep;
    }
  }
  // LB21.
  if (a == _ba || a == _hh || a == _hy || a == _ns || b == _bb) return _keep;
  // LB21a: HL (HY | HH) × [^HL]
  if ((b == _hy || b == _hh) && i >= 2 && classes[i - 2] == _hl && a != _hl) {
    return _keep;
  }
  // LB21b.
  if (b == _sy && a == _hl) return _keep;
  // LB22.
  if (a == _in) return _keep;
  final letterBefore = b == _al || b == _hl;
  final letterAfter = a == _al || a == _hl;
  // LB23.
  if (letterBefore && a == _nu) return _keep;
  if (b == _nu && letterAfter) return _keep;
  // LB23a.
  if (b == _pr && (a == _id || a == _eb || a == _em)) return _keep;
  if ((b == _id || b == _eb || b == _em) && a == _po) return _keep;
  // LB24.
  if ((b == _pr || b == _po) && letterAfter) return _keep;
  if (letterBefore && (a == _pr || a == _po)) return _keep;
  // LB25.
  if (_lb25(classes, count, i)) return _keep;
  // LB26.
  if (b == _jl && (a == _jl || a == _jv || a == _h2 || a == _h3)) return _keep;
  if ((b == _jv || b == _h2) && (a == _jv || a == _jt)) return _keep;
  if ((b == _jt || b == _h3) && a == _jt) return _keep;
  // LB27.
  if (sets[b] & _korean != 0 && a == _po) return _keep;
  if (b == _pr && sets[a] & _korean != 0) return _keep;
  // LB28.
  if (letterBefore && letterAfter) return _keep;
  // LB28a.
  if (b == _ap && _aksara(classes, flags, i)) return _keep;
  if (_aksara(classes, flags, i - 1) && (a == _vf || a == _vi)) return _keep;
  if (b == _vi &&
      i >= 2 &&
      _aksara(classes, flags, i - 2) &&
      _aksaraOrCircle(classes, flags, i)) {
    return _keep;
  }
  if (_aksara(classes, flags, i - 1) &&
      _aksara(classes, flags, i) &&
      i + 1 < count &&
      classes[i + 1] == _vf) {
    return _keep;
  }
  // LB29.
  if (b == _is && letterAfter) return _keep;
  // LB30.
  if ((letterBefore || b == _nu) && a == _op && after & _eastAsianUnit == 0) {
    return _keep;
  }
  if (b == _cp && before & _eastAsianUnit == 0 && (letterAfter || a == _nu)) {
    return _keep;
  }
  // LB30a: an odd number of regional indicators before.
  if (b == _ri && a == _ri) {
    var j = i - 1;
    while (j >= 0 && classes[j] == _ri) {
      j--;
    }
    if ((i - 1 - j).isOdd) return _keep;
  }
  // LB30b.
  if (a == _em && (b == _eb || before & _unassignedPictographicUnit != 0)) {
    return _keep;
  }
  // LB31.
  return _allow;
}

/// LB25: no break inside numbers.
bool _lb25(Uint8List classes, int count, int i) {
  final b = classes[i - 1];
  final a = classes[i];
  final prefixOrPostfix = a == _po || a == _pr;
  // NU (SY | IS)* (CL | CP) × (PO | PR)
  if (prefixOrPostfix &&
      (b == _cl || b == _cp) &&
      _endsNumber(classes, i - 2)) {
    return true;
  }
  // NU (SY | IS)* × (PO | PR)
  if (prefixOrPostfix && _endsNumber(classes, i - 1)) return true;
  if (b == _po || b == _pr) {
    // (PO | PR) × OP NU, (PO | PR) × OP IS NU, (PO | PR) × NU
    if (a == _op) {
      if (i + 1 < count && classes[i + 1] == _nu) return true;
      if (i + 2 < count && classes[i + 1] == _is && classes[i + 2] == _nu) {
        return true;
      }
    }
    if (a == _nu) return true;
  }
  // HY × NU, IS × NU
  if ((b == _hy || b == _is) && a == _nu) return true;
  // NU (SY | IS)* × NU
  if (a == _nu && _endsNumber(classes, i - 1)) return true;
  return false;
}

/// Whether `NU (SY | IS)*` ends at unit [end] (inclusive).
bool _endsNumber(Uint8List classes, int end) {
  var j = end;
  while (j >= 0 && (classes[j] == _sy || classes[j] == _is)) {
    j--;
  }
  return j >= 0 && classes[j] == _nu;
}
