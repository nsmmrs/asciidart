/* Corpus differential harness: byte-identical parity gate (ADR-0001, D4).
 *
 * Runs two asciidoctor executables over the fixture corpus plus
 * `data/reference/syntax.adoc`, normalizes version stamps and timestamps,
 * and reports
 * per-file unified diffs.
 *
 * Run from the repo root:
 *
 * ```sh
 * dart run tool/differential.dart --exe-a <command> --exe-b <command>
 * ```
 *
 * Exit codes: 0 when every corpus file converts identically, 1 when at
 * least one file differs, 2 for harness errors (bad usage, missing
 * corpus, exe would not start).
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

/// Exit code: every corpus file converted identically.
const int exitIdentical = 0;

/// Exit code: at least one corpus file differed.
const int exitDifferences = 1;

/// Exit code: harness error (bad usage, missing corpus, exe won't start).
const int exitHarnessError = 2;

/// Fixed epoch exported to child processes (`SOURCE_DATE_EPOCH`, with
/// `TZ=UTC`) so `docdate`/`doctime`-derived output is deterministic.
const String fixedSourceDateEpoch = '0';

/// Myers edit-distance cap; beyond it the diff falls back to one
/// delete-all/insert-all hunk (still exact, just less granular).
const int maxPreciseEditDistance = 500;

Future<void> main(List<String> arguments) async {
  final parser = buildParser();
  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln('differential: ${e.message}')
      ..writeln()
      ..writeln(usageText(parser));
    exitCode = exitHarnessError;
    return;
  }
  if (results['help'] as bool) {
    stdout.writeln(usageText(parser));
    return;
  }
  final config = DifferentialConfig.tryParse(results, parser);
  if (config == null) {
    exitCode = exitHarnessError;
    return;
  }
  try {
    exitCode = await runDifferential(config);
  } on HarnessError catch (e) {
    stderr.writeln('differential: ${e.message}');
    exitCode = exitHarnessError;
  }
}

/// Builds the command-line parser for the harness.
ArgParser buildParser() {
  return ArgParser()
    ..addOption(
      'exe-a',
      help:
          'Command for implementation A: an exe path or a full '
          'command line (POSIX-style quoting).',
    )
    ..addOption(
      'exe-b',
      help:
          'Command for implementation B: an exe path or a full '
          'command line (POSIX-style quoting).',
    )
    ..addOption(
      'backend',
      defaultsTo: 'html5',
      help: 'Backend for both exes by default.',
    )
    ..addOption('backend-a', help: 'Backend for exe A (overrides --backend).')
    ..addOption('backend-b', help: 'Backend for exe B (overrides --backend).')
    ..addOption('root', help: 'Repo root (default: auto-detect).')
    ..addOption(
      'corpus-dir',
      defaultsTo: 'test/fixtures',
      help: 'Corpus directory, relative to --root unless absolute.',
    )
    ..addMultiOption(
      'extra-file',
      defaultsTo: ['data/reference/syntax.adoc'],
      help: 'Extra corpus file(s), relative to --root unless absolute.',
    )
    ..addOption(
      'extensions',
      defaultsTo: 'adoc,asciidoc',
      help: 'Comma-separated corpus extensions.',
    )
    ..addOption('context', defaultsTo: '3', help: 'Unified-diff context lines.')
    ..addOption(
      'max-diff-lines',
      defaultsTo: '200',
      help: 'Max diff lines printed per file.',
    )
    ..addOption(
      'timeout-secs',
      defaultsTo: '60',
      help: 'Per-conversion timeout in seconds.',
    )
    ..addOption(
      'out-dir',
      help: 'Write raw per-exe outputs here (default: temp dir).',
    )
    ..addFlag('keep-outputs', help: 'Keep the temp output dir after the run.')
    ..addOption(
      'filter',
      help: 'Only convert corpus files whose path contains this string.',
    )
    ..addFlag('quiet', abbr: 'q', help: 'Only print diffs and the summary.')
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage message.',
    );
}

/// Usage text with the synopsis line.
String usageText(ArgParser parser) =>
    'Usage: differential.dart --exe-a <command> --exe-b <command> [options]\n'
    '\n'
    '${parser.usage}';

/// Fatal harness failure. Never a parity verdict.
class HarnessError implements Exception {
  /// Creates an error with a human-readable [message].
  new(this.message);

  /// Human-readable description.
  final String message;

  @override
  String toString() => message;
}

/// Validated harness configuration.
class DifferentialConfig {
  new _({
    required this.exeA,
    required this.exeB,
    required this.rawExeA,
    required this.rawExeB,
    required this.backendA,
    required this.backendB,
    required this.root,
    required this.corpusDir,
    required this.extraFiles,
    required this.extensions,
    required this.contextLines,
    required this.maxDiffLines,
    required this.timeout,
    required this.outDir,
    required this.keepOutputs,
    required this.filter,
    required this.quiet,
  });

  /// argv for implementation A (executable + baked-in arguments).
  final List<String> exeA;

  /// argv for implementation B (executable + baked-in arguments).
  final List<String> exeB;

  /// Raw `--exe-a` text (for log lines).
  final String rawExeA;

  /// Raw `--exe-b` text (for log lines).
  final String rawExeB;

  /// Backend flag passed to exe A.
  final String backendA;

  /// Backend flag passed to exe B.
  final String backendB;

  /// Repo root (absolute, normalized).
  final String root;

  /// Corpus directory (absolute).
  final String corpusDir;

  /// Extra corpus files (absolute).
  final List<String> extraFiles;

  /// Lowercase corpus extensions, without dots.
  final Set<String> extensions;

  /// Unified-diff context lines.
  final int contextLines;

  /// Max diff lines printed per file.
  final int maxDiffLines;

  /// Per-conversion timeout.
  final Duration timeout;

  /// User output dir, or null for a temp dir.
  final String? outDir;

  /// Keep the temp output dir after the run.
  final bool keepOutputs;

  /// Optional substring filter on corpus paths.
  final String? filter;

  /// Suppress per-file `ok` lines.
  final bool quiet;

  /// Parses and validates [results], printing problems plus usage to stderr
  /// and returning null when invalid.
  static DifferentialConfig? tryParse(ArgResults results, ArgParser parser) {
    final problems = <String>[];

    final rawA = (results['exe-a'] as String?)?.trim() ?? '';
    final rawB = (results['exe-b'] as String?)?.trim() ?? '';
    if (rawA.isEmpty) problems.add('missing required option --exe-a');
    if (rawB.isEmpty) problems.add('missing required option --exe-b');
    final exeA = splitCommand(rawA);
    final exeB = splitCommand(rawB);
    if (rawA.isNotEmpty && (exeA.isEmpty || exeA.first.isEmpty)) {
      problems.add('--exe-a names no executable');
    }
    if (rawB.isNotEmpty && (exeB.isEmpty || exeB.first.isEmpty)) {
      problems.add('--exe-b names no executable');
    }

    final backend = _nonEmpty(results['backend'] as String?, 'html5');
    final backendA = _nonEmpty(results['backend-a'] as String?, backend);
    final backendB = _nonEmpty(results['backend-b'] as String?, backend);

    final rootOption = (results['root'] as String?)?.trim() ?? '';
    final root = rootOption.isEmpty
        ? _detectRoot()
        : _normalizePath(rootOption);

    final corpusOption = _nonEmpty(
      results['corpus-dir'] as String?,
      'test/fixtures',
    );
    final corpusDir = _isAbsolutePath(corpusOption)
        ? _normalizePath(corpusOption)
        : _normalizePath(_joinPath(root, corpusOption));
    if (!Directory(corpusDir).existsSync()) {
      problems.add('corpus directory not found: $corpusDir');
    }

    final extraFiles = <String>[];
    for (final extra in results['extra-file'] as List<String>) {
      final trimmed = extra.trim();
      if (trimmed.isEmpty) continue;
      final absolute = _isAbsolutePath(trimmed)
          ? _normalizePath(trimmed)
          : _normalizePath(_joinPath(root, trimmed));
      if (!File(absolute).existsSync()) {
        problems.add('extra corpus file not found: $absolute');
      } else if (!extraFiles.contains(absolute)) {
        extraFiles.add(absolute);
      }
    }

    final extensions = <String>{};
    for (final part in (results['extensions'] as String? ?? '').split(',')) {
      final ext = part.trim().toLowerCase().replaceAll(RegExp(r'^\.+'), '');
      if (ext.isNotEmpty) extensions.add(ext);
    }
    if (extensions.isEmpty) problems.add('--extensions names no extensions');

    final contextLines = int.tryParse(results['context'] as String? ?? '');
    if (contextLines == null || contextLines < 0) {
      problems.add('--context must be a non-negative integer');
    }
    final maxDiffLines = int.tryParse(
      results['max-diff-lines'] as String? ?? '',
    );
    if (maxDiffLines == null || maxDiffLines < 1) {
      problems.add('--max-diff-lines must be a positive integer');
    }
    final timeoutSecs = int.tryParse(results['timeout-secs'] as String? ?? '');
    if (timeoutSecs == null || timeoutSecs < 1) {
      problems.add('--timeout-secs must be a positive integer');
    }

    final outOption = (results['out-dir'] as String?)?.trim() ?? '';
    var outDir = '';
    if (outOption.isNotEmpty) {
      outDir = _normalizePath(outOption);
      try {
        Directory(outDir).createSync(recursive: true);
      } on FileSystemException catch (e) {
        problems.add('cannot create --out-dir $outDir: ${e.message}');
      }
    }

    final filterOption = (results['filter'] as String?)?.trim() ?? '';

    if (problems.isNotEmpty) {
      for (final problem in problems) {
        stderr.writeln('differential: $problem');
      }
      stderr
        ..writeln()
        ..writeln(usageText(parser));
      return null;
    }
    return DifferentialConfig._(
      exeA: exeA,
      exeB: exeB,
      rawExeA: rawA,
      rawExeB: rawB,
      backendA: backendA,
      backendB: backendB,
      root: root,
      corpusDir: corpusDir,
      extraFiles: extraFiles,
      extensions: extensions,
      contextLines: contextLines!,
      maxDiffLines: maxDiffLines!,
      timeout: Duration(seconds: timeoutSecs!),
      outDir: outDir.isEmpty ? null : outDir,
      keepOutputs: results['keep-outputs'] as bool,
      filter: filterOption.isEmpty ? null : filterOption,
      quiet: results['quiet'] as bool,
    );
  }
}

String _nonEmpty(String? value, String fallback) {
  if (value == null || value.trim().isEmpty) return fallback;
  return value.trim();
}

/// Runs the corpus comparison. Returns [exitIdentical] when every corpus
/// file converts identically, [exitDifferences] otherwise.
///
/// Throws [HarnessError] when the comparison itself cannot run.
Future<int> runDifferential(DifferentialConfig config) async {
  final files = _collectCorpus(config);
  if (files.isEmpty) {
    throw HarnessError('corpus is empty (dir: ${config.corpusDir})');
  }

  final configuredOut = config.outDir;
  late final Directory outDir;
  Directory? tempDir;
  if (configuredOut == null) {
    tempDir = Directory.systemTemp.createTempSync('differential-');
    outDir = tempDir;
  } else {
    outDir = Directory(configuredOut);
  }

  if (!config.quiet) {
    stdout
      ..writeln('differential: exe-a: ${config.rawExeA}')
      ..writeln('differential: exe-b: ${config.rawExeB}');
  }
  stdout.writeln(
    'differential: comparing ${files.length} files '
    '(backend-a=${config.backendA} backend-b=${config.backendB})',
  );

  var identical = 0;
  final mismatched = <String>[];
  var preserveEvidence = config.keepOutputs;
  try {
    for (final rel in files) {
      final input = _joinPath(config.root, rel);
      late final _RunResult resultA;
      late final _RunResult resultB;
      try {
        final both = await Future.wait([
          _runExe(
            config.exeA,
            config.backendA,
            input,
            config.root,
            config.timeout,
          ),
          _runExe(
            config.exeB,
            config.backendB,
            input,
            config.root,
            config.timeout,
          ),
        ]);
        resultA = both[0];
        resultB = both[1];
      } on ProcessException catch (e) {
        throw HarnessError('cannot start exe: $e');
      }
      _writeBytes(outDir, 'a', rel, resultA.stdout);
      _writeBytes(outDir, 'b', rel, resultB.stdout);

      final reasons = <String>[];
      if (resultA.timedOut) {
        reasons.add('exe A timed out after ${config.timeout.inSeconds}s');
      }
      if (resultB.timedOut) {
        reasons.add('exe B timed out after ${config.timeout.inSeconds}s');
      }
      if (resultA.exitCode != resultB.exitCode) {
        reasons.add(
          'exit code differs: A=${resultA.exitCode} B=${resultB.exitCode}',
        );
      }
      final textA = normalizeOutput(
        utf8.decode(resultA.stdout, allowMalformed: true),
      );
      final textB = normalizeOutput(
        utf8.decode(resultB.stdout, allowMalformed: true),
      );
      if (reasons.isEmpty && textA == textB) {
        identical++;
        if (!config.quiet) stdout.writeln('ok $rel');
        continue;
      }
      mismatched.add(rel);
      stdout.writeln('DIFF $rel');
      for (final reason in reasons) {
        stdout.writeln('  $reason');
      }
      if (textA != textB) {
        stdout.write(_cappedDiff(rel, textA, textB, config));
      } else if (!config.quiet) {
        stdout.writeln('  (normalized stdout identical)');
      }
    }
    preserveEvidence = preserveEvidence || mismatched.isNotEmpty;

    if (mismatched.isEmpty) {
      stdout.writeln('differential: all ${files.length} files identical');
      return exitIdentical;
    }
    stdout.writeln(
      'differential: $identical identical, '
      '${mismatched.length} differ (${files.length} total)',
    );
    return exitDifferences;
  } finally {
    if (preserveEvidence) {
      stdout.writeln('differential: raw outputs in ${outDir.path}');
    } else if (tempDir != null) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException catch (e) {
        stderr.writeln(
          'differential: warning: cannot remove '
          '${tempDir.path}: ${e.message}',
        );
      }
    }
  }
}

/// Collects corpus paths relative to `config.root`, sorted.
List<String> _collectCorpus(DifferentialConfig config) {
  final rels = <String>{};
  final entities = Directory(config.corpusDir)
      .listSync(recursive: true, followLinks: false);
  for (final entity in entities) {
    if (entity is! File) continue;
    final name = entity.path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) continue;
    final ext = name.substring(dot + 1).toLowerCase();
    if (!config.extensions.contains(ext)) continue;
    rels.add(_relativeTo(config.root, _normalizePath(entity.path)));
  }
  for (final extra in config.extraFiles) {
    rels.add(_relativeTo(config.root, extra));
  }
  final files = rels.toList()..sort();
  final filter = config.filter;
  if (filter != null) {
    files.retainWhere((rel) => rel.contains(filter));
  }
  return files;
}

/// Outcome of one exe invocation.
class _RunResult {
  new({required this.exitCode, required this.stdout, required this.timedOut});

  /// Process exit code, or -1 after a timeout kill.
  final int exitCode;

  /// Raw stdout bytes.
  final List<int> stdout;

  /// Whether the invocation hit the timeout and was killed.
  final bool timedOut;
}

/// Runs one exe over [inputPath], capturing stdout. stderr is drained and
/// ignored; only stdout (plus the exit code) feeds the parity verdict.
Future<_RunResult> _runExe(
  List<String> command,
  String backend,
  String inputPath,
  String workingDirectory,
  Duration timeout,
) async {
  final process = await Process.start(
    command.first,
    [...command.skip(1), '-b', backend, '-o', '-', '-q', inputPath],
    workingDirectory: workingDirectory,
    environment: {'TZ': 'UTC', 'SOURCE_DATE_EPOCH': fixedSourceDateEpoch},
  );
  try {
    final resolved = await Future.wait<dynamic>([
      process.stdout.toList(),
      process.stderr.drain<dynamic>(),
      process.exitCode,
    ]).timeout(timeout);
    final chunks = resolved[0] as List<List<int>>;
    return _RunResult(
      exitCode: resolved[2] as int,
      stdout: chunks.expand((chunk) => chunk).toList(),
      timedOut: false,
    );
  } on TimeoutException {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    return _RunResult(exitCode: -1, stdout: const [], timedOut: true);
  }
}

void _writeBytes(Directory outDir, String side, String rel, List<int> bytes) {
  final file = File(_joinPath(_joinPath(outDir.path, side), rel));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

String _cappedDiff(
  String rel,
  String textA,
  String textB,
  DifferentialConfig config,
) {
  final full = formatUnifiedDiff(
    aLabel: 'a/$rel',
    bLabel: 'b/$rel',
    textA: textA,
    textB: textB,
    contextLines: config.contextLines,
  );
  // `full` ends with a newline, leaving an empty trailing element.
  final lines = (full.split('\n'))..removeLast();
  if (lines.length <= config.maxDiffLines) return full;
  final kept = lines.take(config.maxDiffLines).join('\n');
  return '$kept\n'
      '... [diff truncated: showing ${config.maxDiffLines} '
      'of ${lines.length} lines]\n';
}

final _versionStamp = RegExp('Asciidoctor [0-9][0-9A-Za-z.+_~-]*');
final _lastUpdated = RegExp(
  r'Last updated \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}',
);
final _manDate = RegExp(r'^(\.\" +Date: ).*$', multiLine: true);
final _manThDate = RegExp(r'''(\.TH("[^"\n]*"\s+){2}")\d{4}-\d{2}-\d{2}(")''');

/// Normalizes the narrow volatile stamps (ADR-0001, D4) so two
/// implementations built at different versions or times compare equal:
///
/// * line endings (`\r\n` and `\r` become `\n`),
/// * `Asciidoctor <version>` stamps (HTML generator meta, manpage header),
/// * the HTML footer `Last updated <datetime>` line,
/// * the manpage `Date:` header and `.TH` date field.
///
/// Content-derived dates (e.g. `revdate`) are deliberately left alone:
/// `docdate`/`doctime` determinism comes from the fixed `SOURCE_DATE_EPOCH`
/// exported to both child processes.
String normalizeOutput(String text) {
  var result = text.replaceAll('\r\n', '\n');
  result = result.replaceAll('\r', '\n');
  result = result.replaceAll(_versionStamp, 'Asciidoctor NORMALIZED-VERSION');
  result = result.replaceAll(_lastUpdated, 'Last updated NORMALIZED-DATETIME');
  result = result.replaceAll(_manDate, r'$1NORMALIZED-DATE');
  result = result.replaceAll(_manThDate, r'$1NORMALIZED-DATE$3');
  return result;
}

/// Splits an `--exe-a`/`--exe-b` command string into argv, honoring POSIX-ish
/// single/double quotes and backslash escapes outside single quotes.
List<String> splitCommand(String command) {
  final parts = <String>[];
  final token = StringBuffer();
  var hasToken = false;
  String? quote;
  var escaped = false;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (escaped) {
      token.write(ch);
      escaped = false;
      hasToken = true;
      continue;
    }
    if (quote == null && (ch == ' ' || ch == '\t' || ch == '\n')) {
      if (hasToken) {
        parts.add(token.toString());
        token.clear();
        hasToken = false;
      }
      continue;
    }
    if (ch == r'\') {
      if (quote == "'") {
        token.write(ch);
      } else {
        escaped = true;
      }
      hasToken = true;
      continue;
    }
    if (ch == "'" || ch == '"') {
      if (quote == null) {
        quote = ch;
      } else if (quote == ch) {
        quote = null;
      } else {
        token.write(ch);
      }
      hasToken = true;
      continue;
    }
    token.write(ch);
    hasToken = true;
  }
  if (escaped) {
    token.write(r'\');
  }
  if (hasToken) {
    parts.add(token.toString());
  }
  return parts;
}

/// Formats [textA] vs [textB] as a unified diff with `---`/`+++` headers
/// and [contextLines] of context. Line-level edits come from Myers'
/// O(ND) algorithm, capped by [maxPreciseEditDistance].
String formatUnifiedDiff({
  required String aLabel,
  required String bLabel,
  required String textA,
  required String textB,
  required int contextLines,
}) {
  final a = _splitLines(textA);
  final b = _splitLines(textB);
  final edits =
      _myersEdits(a.lines, b.lines) ?? _replaceAllEdits(a.lines, b.lines);

  final hunks = <_Hunk>[];
  for (var i = 0; i < edits.length; i++) {
    if (edits[i].op == _EditOp.equal) continue;
    final start = max(0, i - contextLines);
    final end = min(edits.length, i + contextLines + 1);
    final last = hunks.isEmpty ? null : hunks.last;
    if (last != null && start <= last.end) {
      last.end = max(last.end, end);
    } else {
      hunks.add(_Hunk(start, end));
    }
  }

  final out = StringBuffer()
    ..writeln('--- $aLabel')
    ..writeln('+++ $bLabel');
  var aLine = 0;
  var bLine = 0;
  var cursor = 0;
  for (final hunk in hunks) {
    while (cursor < hunk.start) {
      final edit = edits[cursor];
      if (edit.op != _EditOp.insert) aLine++;
      if (edit.op != _EditOp.delete) bLine++;
      cursor++;
    }
    var aCount = 0;
    var bCount = 0;
    for (var i = hunk.start; i < hunk.end; i++) {
      final edit = edits[i];
      if (edit.op != _EditOp.insert) aCount++;
      if (edit.op != _EditOp.delete) bCount++;
    }
    out.writeln(
      '@@ -${aCount == 0 ? aLine : aLine + 1},$aCount '
      '+${bCount == 0 ? bLine : bLine + 1},$bCount @@',
    );
    for (var i = hunk.start; i < hunk.end; i++) {
      final edit = edits[i];
      switch (edit.op) {
        case _EditOp.equal:
          out.writeln(' ${a.lines[edit.aLine]}');
          if (_isUnterminatedLast(a, edit.aLine) ||
              _isUnterminatedLast(b, edit.bLine)) {
            out.writeln(r'\ No newline at end of file');
          }
          aLine++;
          bLine++;
        case _EditOp.delete:
          out.writeln('-${a.lines[edit.aLine]}');
          if (_isUnterminatedLast(a, edit.aLine)) {
            out.writeln(r'\ No newline at end of file');
          }
          aLine++;
        case _EditOp.insert:
          out.writeln('+${b.lines[edit.bLine]}');
          if (_isUnterminatedLast(b, edit.bLine)) {
            out.writeln(r'\ No newline at end of file');
          }
          bLine++;
      }
      cursor++;
    }
  }
  return out.toString();
}

enum _EditOp { equal, delete, insert }

class _Edit {
  const new(this.op, this.aLine, this.bLine);

  final _EditOp op;

  /// Index into the A lines, or -1 for insertions.
  final int aLine;

  /// Index into the B lines, or -1 for deletions.
  final int bLine;
}

class _Hunk {
  new(this.start, this.end);

  final int start;
  int end;
}

({List<String> lines, bool trailingNewline}) _splitLines(String text) {
  if (text.isEmpty) return (lines: <String>[], trailingNewline: true);
  final trailingNewline = text.endsWith('\n');
  final lines = text.split('\n');
  if (trailingNewline) lines.removeLast();
  return (lines: lines, trailingNewline: trailingNewline);
}

bool _isUnterminatedLast(
  ({List<String> lines, bool trailingNewline}) file,
  int index,
) => !file.trailingNewline && index == file.lines.length - 1;

/// Myers' greedy diff. Returns null when the edit distance exceeds
/// [maxPreciseEditDistance] so the caller can fall back to [_replaceAllEdits].
List<_Edit>? _myersEdits(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  final max = n + m;
  if (max == 0) return const [];
  final offset = max;
  final v = List<int>.filled(2 * max + 1, 0);
  final trace = <List<int>>[];
  for (var d = 0; d <= max; d++) {
    if (d > maxPreciseEditDistance) return null;
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        x = v[offset + k + 1];
      } else {
        x = v[offset + k - 1] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        trace.add(List<int>.of(v));
        return _backtrack(trace, n, m, offset);
      }
    }
    trace.add(List<int>.of(v));
  }
  return null;
}

List<_Edit> _backtrack(List<List<int>> trace, int n, int m, int offset) {
  var x = n;
  var y = m;
  final reversed = <_Edit>[];
  for (var d = trace.length - 1; d >= 1; d--) {
    final v = trace[d - 1];
    final k = x - y;
    final int prevK;
    if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = v[offset + prevK];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      x--;
      y--;
      reversed.add(_Edit(_EditOp.equal, x, y));
    }
    if (x == prevX) {
      reversed.add(_Edit(_EditOp.insert, -1, prevY));
      y = prevY;
    } else {
      reversed.add(_Edit(_EditOp.delete, prevX, -1));
      x = prevX;
    }
  }
  while (x > 0 && y > 0) {
    x--;
    y--;
    reversed.add(_Edit(_EditOp.equal, x, y));
  }
  while (x > 0) {
    x--;
    reversed.add(_Edit(_EditOp.delete, x, -1));
  }
  while (y > 0) {
    y--;
    reversed.add(_Edit(_EditOp.insert, -1, y));
  }
  return reversed.reversed.toList();
}

/// Whole-file fallback edit script: delete every A line, insert every B line.
List<_Edit> _replaceAllEdits(List<String> a, List<String> b) {
  final edits = <_Edit>[];
  for (var i = 0; i < a.length; i++) {
    edits.add(_Edit(_EditOp.delete, i, -1));
  }
  for (var j = 0; j < b.length; j++) {
    edits.add(_Edit(_EditOp.insert, -1, j));
  }
  return edits;
}

String _detectRoot() {
  final cwd = Directory.current.absolute.path;
  if (_looksLikeRoot(cwd)) return _normalizePath(cwd);
  final parent = Directory.current.parent.absolute.path;
  if (_looksLikeRoot(parent)) return _normalizePath(parent);
  return _scriptRoot() ?? _normalizePath(cwd);
}

String? _scriptRoot() {
  final script = Platform.script;
  if (!script.isScheme('file')) return null;
  final candidate = _normalizePath(
    _joinPath(File.fromUri(script).parent.path, '..'),
  );
  return _looksLikeRoot(candidate) ? candidate : null;
}

bool _looksLikeRoot(String dir) =>
    Directory(_joinPath(dir, 'test/fixtures')).existsSync() &&
    File(_joinPath(dir, 'pubspec.yaml')).existsSync();

String _joinPath(String a, String b) {
  if (_isAbsolutePath(b)) return b;
  var left = a;
  while (left.length > 1 && left.endsWith(Platform.pathSeparator)) {
    left = left.substring(0, left.length - 1);
  }
  return '$left${Platform.pathSeparator}$b';
}

bool _isAbsolutePath(String path) =>
    path.startsWith(Platform.pathSeparator) ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

String _normalizePath(String path) {
  final segments = File(path).absolute.path.split(Platform.pathSeparator);
  final kept = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') {
      if (kept.isEmpty) kept.add(segment);
      continue;
    }
    if (segment == '..') {
      if (kept.length > 1) kept.removeLast();
      continue;
    }
    kept.add(segment);
  }
  if (kept.length == 1 && kept.single.isEmpty) {
    return Platform.pathSeparator;
  }
  return kept.join(Platform.pathSeparator);
}

String _relativeTo(String root, String path) {
  final prefix = '$root${Platform.pathSeparator}';
  if (path.startsWith(prefix)) return path.substring(prefix.length);
  if (path == root) return '.';
  return path;
}
