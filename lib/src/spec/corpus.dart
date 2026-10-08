/// The repository as a whole: profiles, defaults and cases.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'case.dart';
import 'conversion.dart';
import 'normalize.dart';
import 'profile.dart';

final class Corpus {
  Corpus._(this.root, this.profiles, this.defaults);

  /// The repository root (the directory with `profiles.toml`).
  final String root;
  final Map<String, Profile> profiles;
  final Defaults defaults;

  String get casesRoot => p.join(root, 'cases');

  /// The corpus at [root], or the nearest directory above the working
  /// directory that has a `profiles.toml`.
  static Corpus open([String? root]) {
    var dir = p.absolute(root ?? Directory.current.path);
    while (!File(p.join(dir, 'profiles.toml')).existsSync()) {
      final parent = p.dirname(dir);
      if (parent == dir) {
        throw StateError(
          'not inside an ascii-docs checkout (no profiles.toml)',
        );
      }
      dir = parent;
    }
    return Corpus._(
      dir,
      Profile.load(p.join(dir, 'profiles.toml')),
      Defaults.load(p.join(dir, 'defaults.toml')),
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
