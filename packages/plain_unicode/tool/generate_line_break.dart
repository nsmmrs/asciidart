/// Generates `lib/src/line_break_data.g.dart` from the Unicode
/// Character Database files in `vendor/ucd/18.0.0` (Unicode 18.0.0): the
/// Line_Break class of every code point, merged with the other properties
/// the rules of UAX #14 look at (East_Asian_Width F, W or H; the
/// General_Category Pi and Pf; Extended_Pictographic code points that are
/// unassigned), as a three-stage table (the layout of ICU's code point
/// tries) of 16-bit values with the class the rules use resolved.
///
/// ```sh
/// dart run tool/generate_line_break.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The Line_Break classes, in the order of `LineBreakClass` in
/// `lib/src/line_break.dart`.
const List<String> classes = [
  'BK', 'CR', 'LF', 'CM', 'NL', 'SG', 'WJ', 'ZW', 'GL', 'SP', 'ZWJ', //
  'B2', 'BA', 'BB', 'HY', 'CB', 'CL', 'CP', 'EX', 'IN', 'NS', 'OP', 'QU',
  'IS', 'NU', 'PO', 'PR', 'SY', 'AI', 'AK', 'AL', 'AP', 'AS', 'CJ', 'EB',
  'EM', 'H2', 'H3', 'HH', 'HL', 'ID', 'JL', 'JV', 'JT', 'RI', 'SA', 'VF',
  'VI', 'XX',
];

const int eastAsian = 1 << 6;
const int initialPunctuation = 1 << 7;
const int finalPunctuation = 1 << 8;
const int unassignedPictographic = 1 << 9;
const int combiningMark = 1 << 10; // General_Category Mn or Mc

void main() {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final values = Uint16List(0x110000);
  final xx = classes.indexOf('XX');
  values.fillRange(0, values.length, xx);

  void each(String file, void Function(int start, int end, String value) f) {
    for (final line in File(
      '$root/vendor/ucd/18.0.0/$file',
    ).readAsLinesSync()) {
      final data = line.split('#').first.trim();
      if (data.isEmpty) continue;
      final [range, value] = data.split(';').map((s) => s.trim()).toList();
      final bounds = range.split('..');
      final start = int.parse(bounds.first, radix: 16);
      final end = int.parse(bounds.last, radix: 16);
      f(start, end, value);
    }
  }

  each('LineBreak.txt', (start, end, value) {
    final index = classes.indexOf(value);
    if (index < 0) throw StateError('unknown Line_Break class $value');
    for (var c = start; c <= end; c++) {
      values[c] = index;
    }
  });
  each('EastAsianWidth.txt', (start, end, value) {
    if (value == 'F' || value == 'W' || value == 'H') {
      for (var c = start; c <= end; c++) {
        values[c] |= eastAsian;
      }
    }
  });
  final unassigned = List<bool>.filled(0x110000, false);
  each('DerivedGeneralCategory.txt', (start, end, value) {
    final flag = switch (value) {
      'Pi' => initialPunctuation,
      'Pf' => finalPunctuation,
      'Mn' || 'Mc' => combiningMark,
      _ => 0,
    };
    for (var c = start; c <= end; c++) {
      values[c] |= flag;
      if (value == 'Cn') unassigned[c] = true;
    }
  });
  each('emoji-data.txt', (start, end, value) {
    if (value != 'Extended_Pictographic') return;
    for (var c = start; c <= end; c++) {
      if (unassigned[c]) values[c] |= unassignedPictographic;
    }
  });

  // Each code point's properties packed in 16 bits, the class resolved
  // (LB1, LB10's SA marks) at generation time.
  final packed = Uint16List(values.length);
  for (var c = 0; c < values.length; c++) {
    packed[c] = pack(values[c]);
  }
  // The distinct packed values, in order of first use; each code point as
  // an index into them.
  final palette = <int, int>{};
  final indices = Uint8List(packed.length);
  for (var c = 0; c < packed.length; c++) {
    indices[c] = palette.putIfAbsent(packed[c], () => palette.length);
  }
  if (palette.length > 256) throw StateError('palette too large');
  // Stage 3: the distinct blocks of 32 indices. Stage 2: the distinct
  // runs of 64 stage 3 offsets. Stage 1: a stage 2 offset per 2048 code
  // points.
  final stage3 = <int>[];
  final stage3Blocks = <String, int>{};
  final stage3Offsets = <int>[];
  for (var c = 0; c < indices.length; c += 32) {
    final block = indices.sublist(c, c + 32);
    stage3Offsets.add(
      stage3Blocks.putIfAbsent(block.join(','), () {
        stage3.addAll(block);
        return stage3.length - 32;
      }),
    );
  }
  final stage2 = <int>[];
  final stage2Blocks = <String, int>{};
  final stage1 = <int>[];
  for (var b = 0; b < stage3Offsets.length; b += 64) {
    final block = stage3Offsets.sublist(b, b + 64);
    stage1.add(
      stage2Blocks.putIfAbsent(block.join(','), () {
        stage2.addAll(block);
        return stage2.length - 64;
      }),
    );
  }
  if (stage3.length > 0x10000 || stage2.length > 0x10000) {
    throw StateError('stage offsets exceed 16 bits');
  }
  // Check the trie against the data.
  for (var c = 0; c < packed.length; c++) {
    final index = stage3[stage2[stage1[c >> 11] + ((c >> 5) & 63)] + (c & 31)];
    if (palette.keys.elementAt(index) != packed[c]) {
      throw StateError('trie mismatch at ${c.toRadixString(16)}');
    }
  }

  final version = RegExp(r'LineBreak-([\d.]+)\.txt')
      .firstMatch(
        File('$root/vendor/ucd/18.0.0/LineBreak.txt').readAsStringSync(),
      )!
      .group(1);
  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Generated by `dart run tool/generate_line_break.dart` from')
    ..writeln('// the Unicode Character Database $version (vendor/ucd/18.0.0;')
    ..writeln('// see vendor/ucd/18.0.0/license.txt for its terms).')
    ..writeln('// The stages are long base64 strings: one line each.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('/// The line breaking properties of every code point, as a')
    ..writeln('/// three-stage table: the properties of code point `c` are')
    ..writeln('/// `palette[stage3[stage2[stage1[c >> 11] + (c >> 5 & 63)] +')
    ..writeln('/// (c & 31)]]`.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The Unicode version of the data.')
    ..writeln("const String lineBreakUnicodeVersion = '$version';")
    ..writeln()
    ..writeln(
      '/// The distinct properties: the Line_Break class (bits 0-5), the',
    )
    ..writeln('/// class the rules use (bits 6-11), and the flags of')
    ..writeln('/// `line_break.dart` (bits 12-15).')
    ..writeln('const List<int> palette = [')
    ..writeln(_wrap(palette.keys.toList()))
    ..writeln('];')
    ..writeln()
    ..writeln('/// Stage 1: ${stage1.length} 16-bit offsets into stage 2')
    ..writeln('/// (little-endian, base64).')
    ..writeln("const String stage1 = '${_base64Words(stage1)}';")
    ..writeln()
    ..writeln('/// Stage 2: ${stage2.length} 16-bit offsets into stage 3')
    ..writeln('/// (little-endian, base64).')
    ..writeln("const String stage2 = '${_base64Words(stage2)}';")
    ..writeln()
    ..writeln('/// Stage 3: ${stage3.length} palette indices, a byte each')
    ..writeln('/// (base64).')
    ..writeln("const String stage3 = '${base64.encode(stage3)}';");
  final path = '$root/lib/src/line_break_data.g.dart';
  File(path).writeAsStringSync(out.toString());
  Process.runSync(Platform.resolvedExecutable, ['format', path]);
  stdout.writeln(
    'generate_line_break: ${palette.length} distinct values, '
    '${stage1.length * 2 + stage2.length * 2 + stage3.length} bytes',
  );
}

/// The properties [value] (a class and the flags above) packed as
/// `line_break.dart` reads them: the class, the class the rules use (LB1:
/// AI, SG and XX as AL, SA as AL, or as CM for marks; CJ as NS), then the
/// flags from bit 12.
int pack(int value) {
  final original = classes[value & 0x3f];
  final resolved = switch (original) {
    'AI' || 'SG' || 'XX' => 'AL',
    'SA' when value & combiningMark != 0 => 'CM',
    'SA' => 'AL',
    'CJ' => 'NS',
    final c => c,
  };
  var packed = (value & 0x3f) | classes.indexOf(resolved) << 6;
  if (value & eastAsian != 0) packed |= 1 << 12;
  if (value & initialPunctuation != 0) packed |= 1 << 13;
  if (value & finalPunctuation != 0) packed |= 1 << 14;
  if (value & unassignedPictographic != 0) packed |= 1 << 15;
  return packed;
}

/// [words] as little-endian 16-bit integers, in base64.
String _base64Words(List<int> words) {
  final bytes = Uint8List(words.length * 2);
  for (var i = 0; i < words.length; i++) {
    bytes[2 * i] = words[i] & 0xff;
    bytes[2 * i + 1] = words[i] >> 8;
  }
  return base64.encode(bytes);
}

String _wrap(List<int> values) {
  final lines = <String>[];
  var line = StringBuffer('  ');
  for (final value in values) {
    final item = '$value, ';
    if (line.length + item.length > 79) {
      lines.add(line.toString().trimRight());
      line = StringBuffer('  ');
    }
    line.write(item);
  }
  lines.add(line.toString().trimRight());
  return lines.join('\n');
}
