/// Corpus parity check: converts every AsciiDoc file under the given paths
/// with two `asciidoctor` commands (normally the gem and this port) in
/// several modes, and compares stdout, stderr and the exit code.
///
/// ```sh
/// dart run tool/corpus_parity.dart --exe-a asciidoctor \
///   --exe-b dist/asciidart-linux-x64 --out /tmp/parity DIR...
/// ```
///
/// Each conversion runs in the directory of its input, so relative includes
/// resolve, with `TZ=UTC`, `SOURCE_DATE_EPOCH=0` and a UTF-8 locale.
/// Fatal errors are worded differently on purpose (benchmark/PARITY.md), so
/// for those only the fact that both failed is compared; log lines
/// (`asciidoctor: WARNING: ...`) must match.
///
/// Writes `results.tsv` (one line per file and mode) and, for every
/// difference, the four outputs under `diffs/` in the `--out` directory.
/// Exits 1 when anything differs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

/// The modes run by default: name and extra arguments.
const Map<String, List<String>> defaultModes = {
  'html5': ['-b', 'html5'],
  'html5-embedded': ['-b', 'html5', '-s'],
  'docbook5': ['-b', 'docbook5'],
  'manpage': ['-b', 'manpage'],
};

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('exe-a', defaultsTo: 'asciidoctor', help: 'Reference command.')
    ..addOption('exe-b', mandatory: true, help: 'Command under test.')
    ..addOption('out', mandatory: true, help: 'Results directory.')
    ..addOption(
      'jobs',
      defaultsTo: '${Platform.numberOfProcessors}',
      help: 'Conversions run at once (each runs both commands).',
    )
    ..addOption('timeout', defaultsTo: '60', help: 'Seconds per conversion.')
    ..addMultiOption(
      'mode',
      help:
          'NAME=ARGS (space-separated arguments) to run instead of the '
          'default modes; repeatable.',
    )
    ..addOption('filter', help: 'Only files whose path contains this text.')
    ..addOption(
      'cache-a',
      help:
          'Directory caching the reference results, keyed by command, '
          'arguments, file, size and modification time.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('corpus_parity: ${e.message}\n${parser.usage}');
    exitCode = 2;
    return;
  }
  if (options.flag('help') || options.rest.isEmpty) {
    stdout.writeln(
      'Usage: corpus_parity.dart [options] PATH...\n${parser.usage}',
    );
    exitCode = options.flag('help') ? 0 : 2;
    return;
  }
  final modeSpecs = options.multiOption('mode');
  final modes = modeSpecs.isEmpty
      ? defaultModes
      : {
          for (final spec in modeSpecs)
            spec.split('=').first: spec
                .substring(spec.indexOf('=') + 1)
                .split(' ')
                .where((arg) => arg.isNotEmpty)
                .toList(),
        };
  final filter = options.option('filter');
  final roots = [
    for (final path in options.rest) Directory(path).absolute.path,
  ];
  final files = [
    for (final path in options.rest) ..._corpusFiles(path),
  ].where((file) => filter == null || file.contains(filter)).toList()..sort();
  final out = Directory(options.option('out')!)..createSync(recursive: true);
  final diffs = Directory('${out.path}/diffs');
  if (diffs.existsSync()) diffs.deleteSync(recursive: true);
  final exeA = _command(options.option('exe-a')!);
  final exeB = _command(options.option('exe-b')!);
  final timeout = Duration(seconds: int.parse(options.option('timeout')!));
  final jobs = int.parse(options.option('jobs')!);
  final cacheA = options.option('cache-a');
  if (cacheA != null) Directory(cacheA).createSync(recursive: true);

  final cases = [
    for (final file in files)
      for (final mode in modes.entries) (file: file, mode: mode),
  ];
  stdout.writeln(
    'corpus_parity: ${files.length} files x ${modes.length} modes '
    '= ${cases.length} conversions, $jobs at a time',
  );
  final results = <String>[];
  final counts = <String, int>{};
  var next = 0;
  var done = 0;
  Future<void> worker() async {
    while (next < cases.length) {
      final item = cases[next++];
      final args = [...item.mode.value, '-o', '-', _basename(item.file)];
      final dir = File(item.file).parent.path;
      final (a, b) = await (
        cacheA == null
            ? _run(exeA, args, dir, timeout)
            : _cached(cacheA, exeA, args, item.file, () {
                return _run(exeA, args, dir, timeout);
              }),
        _run(exeB, args, dir, timeout),
      ).wait;
      final status = _compare(a, b);
      counts.update(status, (n) => n + 1, ifAbsent: () => 1);
      results.add('$status\t${item.mode.key}\t${item.file}');
      if (status != 'same') {
        final name = '${item.mode.key}/${_caseName(item.file, roots)}';
        final caseDir = Directory('${diffs.path}/$name')
          ..createSync(recursive: true);
        File('${caseDir.path}/a.out').writeAsStringSync(a.stdout);
        File('${caseDir.path}/b.out').writeAsStringSync(b.stdout);
        File('${caseDir.path}/a.err').writeAsStringSync(a.stderr);
        File('${caseDir.path}/b.err').writeAsStringSync(b.stderr);
        File('${caseDir.path}/case.txt').writeAsStringSync(
          '${item.file}\n${args.join(' ')}\n'
          'exit a=${a.exitCode} b=${b.exitCode}\n',
        );
      }
      if (++done % 500 == 0) stdout.writeln('  $done/${cases.length}');
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) worker()]);
  results.sort();
  File('${out.path}/results.tsv').writeAsStringSync('${results.join('\n')}\n');
  final summary = (counts.entries.toList()..sort((x, y) => y.value - x.value))
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  stdout.writeln('corpus_parity: $summary');
  exitCode = counts.keys.every((status) => status == 'same') ? 0 : 1;
}

/// A directory name for the case of [file]: its path below the corpus
/// [roots], with separators replaced, shortened with a hash if too long for
/// a file name.
String _caseName(String file, List<String> roots) {
  var relative = file;
  for (final root in roots) {
    final prefix = root.endsWith('/') ? root : '$root/';
    if (file.startsWith(prefix)) {
      relative = file.substring(prefix.length);
      break;
    }
  }
  final name = relative.replaceAll('/', '_').replaceAll(':', '_');
  if (name.length <= 200) return name;
  return '${name.substring(name.length - 180)}-${_fnv1a(name)}';
}

/// The AsciiDoc files at [path] (a file, or a directory searched
/// recursively, skipping hidden directories and `node_modules`).
Iterable<String> _corpusFiles(String path) sync* {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) {
    yield File(path).absolute.path;
    return;
  }
  final pending = [Directory(path).absolute];
  while (pending.isNotEmpty) {
    for (final entity in pending.removeLast().listSync(followLinks: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        if (!name.startsWith('.') && name != 'node_modules') {
          pending.add(entity);
        }
      } else if (entity is File &&
          (name.endsWith('.adoc') || name.endsWith('.asciidoc'))) {
        yield entity.path;
      }
    }
  }
}

String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

/// A command line split on spaces, with relative paths made absolute (the
/// conversions run in other directories).
List<String> _command(String text) {
  final parts = text.split(' ').where((part) => part.isNotEmpty).toList();
  if (parts.first.contains('/')) parts[0] = File(parts.first).absolute.path;
  return parts;
}

typedef _Result = ({int exitCode, String stdout, String stderr});

/// The result of [run] for [file], from the cache in [dir] when present.
Future<_Result> _cached(
  String dir,
  List<String> command,
  List<String> args,
  String file,
  Future<_Result> Function() run,
) async {
  final stat = File(file).statSync();
  final key = _fnv1a(
    [
      ...command,
      ...args,
      file,
      '${stat.size}',
      '${stat.modified}',
    ].join('\u0000'),
  );
  final entry = File('$dir/$key.json');
  if (entry.existsSync()) {
    final json = jsonDecode(entry.readAsStringSync()) as Map<String, Object?>;
    return (
      exitCode: json['exitCode']! as int,
      stdout: json['stdout']! as String,
      stderr: json['stderr']! as String,
    );
  }
  final result = await run();
  entry.writeAsStringSync(
    jsonEncode({
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
    }),
  );
  return result;
}

/// A 64-bit hash of [text] in hex: two 32-bit FNV-1a hashes with
/// different offsets.
String _fnv1a(String text) {
  var low = 0x811c9dc5;
  var high = 0x050c5d1f;
  for (final unit in utf8.encode(text)) {
    low = ((low ^ unit) * 0x01000193) & 0xffffffff;
    high = ((high ^ unit) * 0x01000193) & 0xffffffff;
  }
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}

Future<_Result> _run(
  List<String> command,
  List<String> args,
  String dir,
  Duration timeout,
) async {
  final process = await Process.start(
    command.first,
    [...command.skip(1), ...args],
    workingDirectory: dir,
    environment: {
      'TZ': 'UTC',
      'SOURCE_DATE_EPOCH': '0',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
    },
  );
  await process.stdin.close();
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final err = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  return (exitCode: code, stdout: await out, stderr: await err);
}

/// The comparison of the two runs: `same`, or the parts that differ.
String _compare(_Result a, _Result b) {
  if (a.exitCode == -1 || b.exitCode == -1) {
    final which = [if (a.exitCode == -1) 'a', if (b.exitCode == -1) 'b'];
    return 'timeout-${which.join()}';
  }
  final parts = [
    if (a.exitCode != b.exitCode) 'exit',
    if (_normalizeStdout(a.stdout) != _normalizeStdout(b.stdout)) 'stdout',
    if (_normalizeStderr(a.stderr) != _normalizeStderr(b.stderr)) 'stderr',
  ];
  return parts.isEmpty ? 'same' : parts.join('+');
}

/// The generator stamp asciidart writes as `Asciidart <version>` where the
/// gem writes `Asciidoctor <version>` (HTML meta tag, man page header).
final RegExp _generatorStamp = RegExp(
  r'(<meta name="generator" content="|\.\\" Generator: )'
  '(?:Asciidoctor|Asciidart) [^"\n]*',
);

/// [stdout] with the generator stamp made canonical.
String _normalizeStdout(String stdout) =>
    stdout.replaceAllMapped(_generatorStamp, (m) => '${m[1]}GENERATOR');

/// A log line, from the gem (`asciidoctor:`) or asciidart (`asciidart:`).
final RegExp _logLine = RegExp(
  '^(?:asciidoctor|asciidart): (DEBUG|INFO|WARNING|ERROR|FATAL): ',
);

/// Messages the port words differently on purpose (benchmark/PARITY.md):
/// each pattern maps both wordings to one canonical form.
final List<(RegExp, String)> rewordings = [
  (
    RegExp(
      "optional gem 'rouge' is not available.*|"
      'Rouge syntax highlighting is not available.*',
    ),
    'rouge unavailable',
  ),
  (
    RegExp(
      "optional gem 'pygments.rb' is not available.*|"
      'Pygments syntax highlighting is not available.*',
    ),
    'pygments unavailable',
  ),
  (
    RegExp(
      "optional gem 'coderay' is not available.*|"
      'CodeRay syntax highlighting is not available.*',
    ),
    'coderay unavailable',
  ),
  (
    RegExp(
      "optional gem 'asciimath' is not available.*|"
      'AsciiMath to MathML conversion is not available.*',
    ),
    'asciimath unavailable',
  ),
  // The converter is named by its Ruby or Dart class.
  (RegExp(r'( backend) \([A-Za-z:]+\)$'), r'$1'),
];

/// [stderr] with the intentional rewordings made canonical and the wording
/// of a fatal error left out: log lines are compared, and the message
/// before `Use --trace to show backtrace` (or any other text) counts only as
/// "failed".
String _normalizeStderr(String stderr) {
  final lines = const LineSplitter().convert(stderr);
  final normalized = <String>[];
  var failed = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final beforeTrace =
        i + 1 < lines.length && lines[i + 1].startsWith('  Use --trace');
    if (beforeTrace || !_logLine.hasMatch(line)) {
      if (line.isNotEmpty) failed = true;
      continue;
    }
    var text = line.replaceFirst(RegExp('^asciidart: '), 'asciidoctor: ');
    for (final (pattern, replacement) in rewordings) {
      text = text.replaceAllMapped(
        pattern,
        (match) => replacement.replaceAllMapped(
          RegExp(r'\$(\d)'),
          (ref) => match[int.parse(ref[1]!)] ?? '',
        ),
      );
    }
    normalized.add(text);
  }
  return [...normalized, if (failed) 'FAILED'].join('\n');
}
