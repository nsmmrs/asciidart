// Imports asciidart's upstream bug-fix reproducers (test/bugfix/*.bats) as
// curated cases: each @test's input document and the format its command
// converts to, under cases/curated/bugfix/<issue>-<n>/.
//
// Usage: dart run tool/import_bugfix.dart ASCIIDART_CHECKOUT
// Then:  dart run bin/ascii_docs.dart regen curated/bugfix
import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: import_bugfix.dart ASCIIDART_CHECKOUT');
    exitCode = 64;
    return;
  }
  final root = p.join(
    p.dirname(p.dirname(Platform.script.toFilePath())),
    'cases',
    'curated',
    'bugfix',
  );
  final files =
      Directory(p.join(args.single, 'test', 'bugfix'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.bats'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  var written = 0;
  for (final file in files) {
    final issue = p.basenameWithoutExtension(file.path);
    final lines = file.readAsLinesSync();
    final summary = [
      for (final line in lines.skip(1).takeWhile((l) => l.startsWith('#')))
        line.substring(1).trim(),
    ].join(' ');
    var n = 0;
    for (var i = 0; i < lines.length; i++) {
      final test = RegExp(r'^@test "(.*)" \{').firstMatch(lines[i]);
      if (test == null) continue;
      String? input;
      List<String>? command;
      for (var j = i + 1; j < lines.length && lines[j] != '}'; j++) {
        final line = lines[j].trim();
        if (input == null) {
          if (RegExp(r"^printf '(.*)' > input\.adoc$").firstMatch(line)
              case final m?) {
            input = _printf(m[1]!);
          } else if (RegExp(r'^printf "(.*)" > input\.adoc$').firstMatch(line)
              case final m?) {
            input = _printf(
              m[1]!.replaceAll(r'\`', '`').replaceAll(r'\"', '"'),
            );
          } else if (RegExp(r"^cat > input\.adoc <<'(\w+)'$").firstMatch(line)
              case final m?) {
            final body = <String>[];
            for (j++; j < lines.length && lines[j] != m[1]; j++) {
              body.add(lines[j]);
            }
            input = '${body.join('\n')}\n';
          }
        }
        final run = RegExp(
          r'^run (?:--separate-stderr )?-- "\$EXE" (.*) input\.adoc',
        ).firstMatch(line);
        if (command == null && run != null)
          command = run[1]!.split(RegExp(r'\s+'));
      }
      if (input == null || command == null) {
        stderr.writeln('$issue: skipped "${test[1]}" (no input or command)');
        continue;
      }
      n++;
      final standalone = !command.contains('-s');
      final backend = switch (command.indexOf('-b')) {
        -1 => 'html5',
        final k => command[k + 1],
      };
      final attributes = <String>[
        for (var k = 0; k < command.length - 1; k++)
          if (command[k] == '-a') command[k + 1],
      ];
      final dir = Directory(p.join(root, '$issue-$n'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'input.adoc')).writeAsStringSync(input);
      String q(String s) =>
          '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
      File(p.join(dir.path, 'case.toml')).writeAsStringSync(
        [
          'description = ${q('asciidoctor#$issue: ${test[1]}. $summary')}',
          'source = "bugfix:asciidoctor#$issue"',
          'features = ["bugfix"]',
          'divergence = "https://github.com/asciidoctor/asciidoctor/issues/$issue (asciidart benchmark/PARITY.md)"',
          'formats = ["$backend"]',
          if (standalone || backend == 'manpage') '\n[options]',
          if (standalone) 'standalone = true',
          if (backend == 'manpage') 'doctype = "manpage"',
          if (attributes.isNotEmpty) '\n[attributes]',
          for (final a in attributes)
            if (a.contains('='))
              '${q(a.substring(0, a.indexOf('=')))} = ${q(a.substring(a.indexOf('=') + 1))}'
            else
              '${q(a)} = ""',
          '',
        ].join('\n'),
      );
      written++;
    }
  }
  stdout.writeln('$written curated bug-fix cases');
}

/// The text bash's `printf FORMAT` (single-quoted, no arguments) writes.
String _printf(String format) {
  final out = StringBuffer();
  for (var i = 0; i < format.length; i++) {
    final c = format[i];
    if (c == r'\' && i + 1 < format.length) {
      final next = format[++i];
      out.write(switch (next) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        r'\' => r'\',
        _ => '\\$next',
      });
    } else if (c == '%' && i + 1 < format.length && format[i + 1] == '%') {
      out.write('%');
      i++;
    } else {
      out.write(c);
    }
  }
  return out.toString();
}
