/// The corpus as a whole: profiles, defaults and cases.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'case.dart';
import 'conversion.dart';
import 'normalize.dart';
import 'profile.dart';

final class Corpus {
  Corpus._(this.root, this.profiles, this.defaults);

  /// The corpus directory (the one with `profiles.toml`).
  final String root;
  final Map<String, Profile> profiles;
  final Defaults defaults;

  String get casesRoot => p.join(root, 'cases');

  /// ptome's package, which the corpus is in.
  String get package => p.normalize(p.join(root, '..', '..'));

  /// Makes ptome's package the working directory, as it is for ptome's
  /// tests, so that what results say about paths outside a case (the
  /// working directory's, `{cwd}`) is recorded as the tests see it. Ruby
  /// workers started afterwards inherit it.
  void enterPackage() => Directory.current = package;

  /// This package (drivers, pool sources, triage notes, exclusions), beside
  /// ptome in `packages/`.
  String get toolsRoot =>
      p.normalize(p.join(root, '..', '..', '..', 'ptome_corpus_tools'));

  /// The corpus at [root], or the one found from the working directory:
  /// the nearest directory above it with a `profiles.toml`, or with
  /// `packages/ptome/test/corpus` (the workspace root).
  static Corpus open([String? root]) {
    var dir = p.absolute(root ?? Directory.current.path);
    String? found;
    while (found == null) {
      for (final candidate in [
        dir,
        p.join(dir, 'packages', 'ptome', 'test', 'corpus'),
      ]) {
        if (File(p.join(candidate, 'profiles.toml')).existsSync()) {
          found = candidate;
          break;
        }
      }
      final parent = p.dirname(dir);
      if (found == null && parent == dir) {
        throw StateError('no corpus found (packages/ptome/test/corpus)');
      }
      dir = parent;
    }
    return Corpus._(
      found,
      Profile.load(p.join(found, 'profiles.toml')),
      Defaults.load(p.join(found, 'defaults.toml')),
    );
  }

  /// Every case, or those whose id starts with one of [prefixes].
  List<Case> cases([List<String> prefixes = const []]) => Case.loadAll(
    casesRoot,
    defaults: defaults,
  ).where((c) => prefixes.isEmpty || prefixes.any(c.id.startsWith)).toList();
}

/// What [outcome] records, normalized, for a case converted in [baseDir];
/// writes the output blob to [blobPath] when there is one.
Expected record(
  Outcome outcome, {
  required String baseDir,
  required String Function(String hash) blobPath,
  bool write = true,
}) {
  switch (outcome) {
    case Converted(:final output, :final log):
      final bytes = outputBytes(output, baseDir: baseDir);
      final hash = contentHash(bytes);
      final file = File(blobPath(hash));
      if (write && !file.existsSync()) {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }
      return Expected(
        hash: hash,
        log: [
          for (final entry in log)
            LogEntry(
              entry.severity,
              normalizeText(entry.message, baseDir: baseDir),
              line: entry.line,
            ),
        ],
      );
    case Crashed(:final error):
      return Expected(
        error: normalizeText(error.split('\n').first, baseDir: baseDir),
      );
    case TimedOut():
      return const Expected(error: 'timeout');
  }
}
