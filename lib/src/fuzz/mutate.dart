/// Text-level mutations of AsciiDoc documents (AFL-style havoc, with
/// AsciiDoc-aware moves: delimiter lengths, markup characters at word
/// boundaries, boundary numbers, splices from other documents).
library;

import '../gen/rng.dart';

const _markup = [
  '*',
  '**',
  '_',
  '__',
  '`',
  '``',
  '#',
  '##',
  '^',
  '~',
  '+',
  '++',
  '+++',
  r'$$',
  '[',
  ']',
  '[[',
  ']]',
  '{',
  '}',
  '<<',
  '>>',
  '|',
  '!',
  ':',
  '::',
  '.',
  '..',
  r'\',
  '//',
  '"`',
  '`"',
  "'",
  '((',
  '))',
  '<',
  '>',
  '&',
  ';;',
  ' +',
  '[.x]',
  '[#y]',
  '{nope}',
  'footnote:[',
  'pass:[',
  'link:',
  'xref:',
];

const _lines = [
  '----',
  '....',
  '====',
  '****',
  '____',
  '++++',
  '////',
  '--',
  '|===',
  ',===',
  ':===',
  '!===',
  '```',
  '+',
  "'''",
  '<<<',
  '[source]',
  '[literal]',
  '[pass]',
  '[quote]',
  '[verse]',
  '[NOTE]',
  '[%header]',
  '[cols="2*"]',
  '[discrete]',
  'endif::[]',
  'ifdef::x[]',
  'include::x.adoc[]',
  ':x: y',
  ':x!:',
  '== T',
  '= T',
  '. item',
  '* item',
  'term:: d',
  '<1> c',
  '.Title',
  '[[a]]',
  '[#a]',
  'image::a.png[]',
  'toc::[]',
  '|a |b',
  '2+|span',
  'a|nested',
];

const _numbers = [
  '0',
  '-1',
  '1',
  '2',
  '7',
  '99',
  '65536',
  '2147483648',
  '-0',
  '1.5',
  '',
];

/// [text] mutated by 1 to 8 random moves; [donors] supply splices.
String mutate(String text, Rng rng, {List<String> donors = const []}) {
  var lines = text.split('\n');
  for (var n = rng.between(1, 8); n > 0; n--) {
    lines = _move(lines, rng, donors);
    if (lines.isEmpty) lines = [''];
  }
  return lines.join('\n');
}

List<String> _move(List<String> lines, Rng rng, List<String> donors) {
  final i = rng.below(lines.length);
  switch (rng.below(12)) {
    case 0: // delete a run of lines
      final n = rng.between(1, 4);
      return [...lines.take(i), ...lines.skip(i + n)];
    case 1: // duplicate a run
      final n = rng.between(1, 4);
      final run = lines.skip(i).take(n);
      return [...lines.take(i + n), ...run, ...lines.skip(i + n)];
    case 2: // splice lines from another document
      if (donors.isEmpty) return lines;
      final donor = rng.pick(donors).split('\n');
      final at = rng.below(donor.length);
      final run = donor.skip(at).take(rng.between(1, 8));
      return [...lines.take(i), ...run, ...lines.skip(i)];
    case 3: // a structural line
      return [...lines.take(i), rng.pick(_lines), ...lines.skip(i)];
    case 4: // change a delimiter's length
      final line = lines[i];
      if (RegExp(r'^([-.=*_+/|~`])\1{1,}').hasMatch(line)) {
        final grown = rng.chance(0.5)
            ? line + line[0]
            : line.substring(0, line.length - 1);
        return [...lines.take(i), grown, ...lines.skip(i + 1)];
      }
      return lines;
    case 5: // markup at a word boundary
      return _edit(lines, i, (line) {
        final bounds = [
          0,
          for (final m in RegExp(r'\b').allMatches(line)) m.start,
          line.length,
        ];
        final at = rng.pick(bounds);
        return '${line.substring(0, at)}${rng.pick(_markup)}${line.substring(at)}';
      });
    case 6: // delete a character
      return _edit(lines, i, (line) {
        if (line.isEmpty) return line;
        final at = rng.below(line.length);
        return line.substring(0, at) + line.substring(at + 1);
      });
    case 7: // a boundary number in place of a number
      return _edit(lines, i, (line) {
        final numbers = RegExp(r'-?\d+').allMatches(line).toList();
        if (numbers.isEmpty) return line;
        final m = rng.pick(numbers);
        return line.replaceRange(m.start, m.end, rng.pick(_numbers));
      });
    case 8: // indentation
      return _edit(
        lines,
        i,
        (line) => rng.chance(0.5)
            ? '${' ' * rng.between(1, 4)}$line'
            : line.trimLeft(),
      );
    case 9: // line endings and odd whitespace
      return _edit(
        lines,
        i,
        (line) => line + rng.pick(['\r', ' ', '\t', ' ', ' \\', '​']),
      );
    case 10: // odd characters
      return _edit(lines, i, (line) {
        final at = line.isEmpty ? 0 : rng.below(line.length);
        return '${line.substring(0, at)}${rng.pick(['é', 'ß', 'İ', '日', '́', '﻿', ' ', '👍', '\u0000', '\u0096'])}${line.substring(at)}';
      });
    default: // swap two lines
      final j = rng.below(lines.length);
      final copy = [...lines];
      final t = copy[i];
      copy[i] = copy[j];
      copy[j] = t;
      return copy;
  }
}

List<String> _edit(List<String> lines, int i, String Function(String) change) =>
    [...lines.take(i), change(lines[i]), ...lines.skip(i + 1)];
