// Reads the headers of hyph-utf8's pattern files (vendor/hyph-utf8/tex,
// fetched by tool/vendor_hyph_utf8.sh) into languages.json (each
// language's name, hyphenmins and licence) and NOTICES.md (each file's
// copyright and licence notice, as the licences ask).
//
// Usage: dart run tool/hyph_metadata.dart vendor/hyph-utf8 COMMIT
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final out = Directory(args[0]);
  final commit = args[1];
  final languages = <String, Object>{};
  final notices = StringBuffer()
    ..writeln('# hyph-utf8 notices')
    ..writeln()
    ..writeln(
      'The hyphenation patterns in `patterns/` come from hyph-utf8 '
      '(https://github.com/hyphenation/tex-hyphen, commit `$commit`), '
      'unchanged, in its plain-text form. Each language keeps its own '
      'licence, reproduced here with its copyright from the header of the '
      "language's TeX file.",
    )
    ..writeln();
  final files =
      Directory('${out.path}/tex').listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final tag = file.uri.pathSegments.last
        .replaceFirst('hyph-', '')
        .replaceFirst('.tex', '');
    final header = [
      for (final line in file.readAsLinesSync())
        if (line.startsWith('%')) line.substring(1) else '',
    ].takeWhile((line) => !line.contains(r'\patterns')).join('\n');
    final name = RegExp(
      r'^ language:\s*\n\s+name:\s*(.+)$',
      multiLine: true,
    ).firstMatch(header)?[1]?.trim();
    final hyphenmins = RegExp(
      r'typesetting:\s*\n\s*left:\s*(\d+)\s*\n\s*right:\s*(\d+)',
    ).firstMatch(header);
    final licence = RegExp(
      r'^ licence:\n((?: {2,}.*\n?)+)',
      multiLine: true,
    ).firstMatch(header)?[1];
    final copyright = [
      for (final m in RegExp(
        r'^ copyright:\s*(.+)$',
        multiLine: true,
      ).allMatches(header))
        m[1]!.trim(),
    ];
    languages[tag] = {
      'name': name ?? tag,
      'left': int.parse(hyphenmins?[1] ?? '2'),
      'right': int.parse(hyphenmins?[2] ?? '3'),
    };
    notices
      ..writeln('## $tag (${name ?? tag})')
      ..writeln()
      ..writeAll(copyright.map((c) => '$c\n'))
      ..writeln()
      ..writeln('```')
      ..writeln(licence?.trimRight() ?? '(see the file)')
      ..writeln('```')
      ..writeln();
  }
  File('${out.path}/languages.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(languages));
  File('${out.path}/NOTICES.md').writeAsStringSync(notices.toString());
  stdout.writeln('hyph_metadata: ${languages.length} languages');
}
