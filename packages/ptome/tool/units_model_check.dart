// The model equivalence gate (ADR-0020): reads each document of a corpus,
// dumps its units model (tool/units_dump.dart), and compares it with the
// oracle: the models milestone 1 (ADR-0019) found for the same documents,
// dumped the same way before it was removed and kept outside the repo.
//
//   dart run tool/units_model_check.dart ORACLE_DIR CORPUS [--allow FILE] \
//       [DOC...]
//
// Prints, per document, whether the models agree and, where they don't,
// the first differences of each part (units, notes, references, terms,
// overlays, diagnostics). A document listed in the allow file
// (`path: reason`, tool/units_model_allow.txt) may differ, for its reason.
import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/units/files.dart' as p;

import 'units_dump.dart';

void main(List<String> arguments) {
  final args = [...arguments];
  final allowAt = args.indexOf('--allow');
  final allowed = <String, String>{};
  if (allowAt >= 0) {
    for (final line in File(args[allowAt + 1]).readAsLinesSync()) {
      final colon = line.indexOf(': ');
      if (line.startsWith('#') || colon < 0) continue;
      allowed[line.substring(0, colon)] = line.substring(colon + 2);
    }
    args.removeRange(allowAt, allowAt + 2);
  }
  final oracle = args[0];
  final corpus = Directory(args[1]).absolute.path;
  final docs =
      args.length > 2
            ? args.sublist(2)
            : [
                for (final f in Directory(oracle).listSync(recursive: true))
                  if (f is File && f.path.endsWith('.json'))
                    p
                        .relative(f.path, from: oracle)
                        .replaceAll(RegExp(r'\.json$'), ''),
              ]
        ..sort();
  var failed = 0;
  for (final doc in docs) {
    final want = jsonDecode(
      File('$oracle/$doc.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final watch = Stopwatch()..start();
    final document = loadFile(
      p.join(corpus, doc),
      options: const AsciidoctorOptions(safe: SafeMode.unsafe),
    );
    final analysis = document.unitsSession?.analysis;
    if (analysis == null) {
      stdout.writeln('FAIL $doc: not read as a document in units');
      failed++;
      continue;
    }
    final got =
        jsonDecode(jsonEncode(dump(analysis, corpus))) as Map<String, Object?>;
    final problems = <String>[];
    for (final part in want.keys) {
      final w = want[part];
      final g = got[part];
      if (jsonEncode(w) == jsonEncode(g)) continue;
      problems.add('  $part: ${_difference(w, g)}');
    }
    final reason = allowed[doc];
    if (problems.isNotEmpty && reason == null) failed++;
    stdout.writeln(
      '${problems.isEmpty
          ? 'ok  '
          : reason != null
          ? 'allowed'
          : 'FAIL'} '
      '$doc (${watch.elapsedMilliseconds} ms)',
    );
    if (problems.isNotEmpty && reason != null) stdout.writeln('  ($reason)');
    problems.forEach(stdout.writeln);
  }
  stdout.writeln(
    failed == 0 ? 'units model: all agree' : 'units model: $failed differ',
  );
  exit(failed == 0 ? 0 : 1);
}

/// Where [want] and [got] first differ, briefly.
String _difference(Object? want, Object? got) {
  if (want is List && got is List) {
    for (var i = 0; i < want.length && i < got.length; i++) {
      if (jsonEncode(want[i]) != jsonEncode(got[i])) {
        return '${want.length} vs ${got.length}; first at $i:\n'
            '    want ${jsonEncode(want[i])}\n'
            '    got  ${jsonEncode(got[i])}';
      }
    }
    return '${want.length} vs ${got.length} entries';
  }
  return 'want ${jsonEncode(want)}\n    got ${jsonEncode(got)}';
}
