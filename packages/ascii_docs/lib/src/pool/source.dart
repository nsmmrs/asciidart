/// The repositories the pool draws documents from (`sources.toml`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import '../spec/profile.dart';

/// The pool's working directory: checkouts, manifest, measurements.
String get poolDir => p.join(cacheDir, 'pool');

final class PoolSource {
  const PoolSource({
    required this.name,
    required this.url,
    required this.commit,
    required this.license,
    this.documents = const [],
    this.heredocs = const [],
    this.sparse = const [],
  });

  final String name;
  final String url;
  final String commit;

  /// SPDX expression, for the record: pool documents never reach the
  /// corpus unsanitized.
  final String license;

  /// Globs of document files.
  final List<String> documents;

  /// Globs of Ruby files whose `<<~` heredocs are documents.
  final List<String> heredocs;

  /// Paths to check out (all when empty).
  final List<String> sparse;

  String get checkout => p.join(poolDir, 'src', name);

  static List<PoolSource> load(String path) {
    final doc = TomlDocument.loadSync(path).toMap();
    List<String> strings(Object? list) => [
      for (final item in (list as List? ?? const [])) item as String,
    ];
    return [
      for (final table in (doc['source'] as List).cast<Map<String, Object?>>())
        PoolSource(
          name: table['name']! as String,
          url: table['url']! as String,
          commit: table['commit']! as String,
          license: table['license']! as String,
          documents: strings(table['documents']),
          heredocs: strings(table['heredocs']),
          sparse: strings(table['sparse']),
        ),
    ];
  }

  /// Checks the source out at its commit (shallow, blobless, sparse).
  Future<void> fetch() async {
    Future<String> git(List<String> args, {bool check = true}) async {
      final result = await Process.run('git', ['-C', checkout, ...args]);
      if (check && result.exitCode != 0) {
        throw ProcessException(
          'git',
          args,
          '${result.stderr}',
          result.exitCode,
        );
      }
      return (result.stdout as String).trim();
    }

    if (!Directory(p.join(checkout, '.git')).existsSync()) {
      Directory(checkout).createSync(recursive: true);
      await git(['init', '-q']);
      await git(['remote', 'add', 'origin', url]);
    }
    if (await git(['rev-parse', '-q', '--verify', 'HEAD'], check: false) ==
        commit) {
      return;
    }
    if (sparse.isNotEmpty) {
      await git(['sparse-checkout', 'set', '--no-cone', ...sparse]);
    }
    await git([
      'fetch',
      '-q',
      '--depth',
      '1',
      '--filter=blob:none',
      'origin',
      commit,
    ]);
    await git(['checkout', '-q', '--detach', 'FETCH_HEAD']);
  }
}
