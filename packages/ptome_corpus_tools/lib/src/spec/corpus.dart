/// ptome's corpus (`packages/ptome/test/corpus`) and the tools' profiles.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'case.dart';
import 'profile.dart';

final class Corpus {
  Corpus._(this.root, this.release, this.attributes, this.profiles);

  /// The corpus directory (the one with `goldens.yml`); each case is a
  /// directory in it.
  final String root;

  /// The release the goldens are of (`asciidoctor-2.0.26`).
  final String release;

  /// The attributes every conversion gets (a fixed clock and home).
  final Map<String, String> attributes;

  /// The implementations the tools run (this package's `profiles.toml`).
  final Map<String, Profile> profiles;

  /// ptome's package, which the corpus is in.
  String get package => p.normalize(p.join(root, '..', '..'));

  /// Makes ptome's package the working directory, as it is for ptome's
  /// tests, so that what results say about paths outside a case (the
  /// working directory's, `{cwd}`) is what the tests see. Ruby workers
  /// started afterwards inherit it.
  void enterPackage() => Directory.current = package;

  /// This package (drivers, profiles, pool sources, triage notes,
  /// exclusions), beside ptome in `packages/`.
  String get toolsRoot =>
      p.normalize(p.join(root, '..', '..', '..', 'ptome_corpus_tools'));

  List<RubyProfile> get rubyProfiles =>
      profiles.values.whereType<RubyProfile>().toList();
  PtomeProfile get ptome => profiles.values.whereType<PtomeProfile>().single;

  /// The Ruby profile ptome is compared with.
  RubyProfile get reference => profiles[ptome.compareTo]! as RubyProfile;

  /// The corpus at [root], or the one found from the working directory:
  /// the nearest directory above it with a `goldens.yml`, or with
  /// `packages/ptome/test/corpus` (the workspace root).
  static Corpus open([String? root]) {
    var dir = p.absolute(root ?? Directory.current.path);
    String? found;
    while (found == null) {
      for (final candidate in [
        dir,
        p.join(dir, 'packages', 'ptome', 'test', 'corpus'),
      ]) {
        if (File(p.join(candidate, 'goldens.yml')).existsSync()) {
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
    final settings = loadYaml(
      File(p.join(found, 'goldens.yml')).readAsStringSync(),
    ) as YamlMap;
    final tools = p.normalize(
      p.join(found, '..', '..', '..', 'ptome_corpus_tools'),
    );
    return Corpus._(found, settings['release']! as String, {
      for (final MapEntry(:key, :value)
          in (settings['attributes'] as YamlMap? ?? YamlMap()).entries)
        '$key': '$value',
    }, Profile.load(p.join(tools, 'profiles.toml')));
  }

  /// The directory of the case [name].
  String caseDir(String name) => p.join(root, name);

  /// Whether there is a case [name].
  bool has(String name) =>
      File(p.join(caseDir(name), 'input.adoc')).existsSync();

  /// Every case, or those whose name starts with one of [prefixes].
  List<Case> cases([List<String> prefixes = const []]) {
    final names =
        [
              for (final entry in Directory(root).listSync())
                if (entry is Directory) p.basename(entry.path),
            ]
            .where(has)
            .where((name) => prefixes.isEmpty || prefixes.any(name.startsWith))
            .toList()
          ..sort();
    return [
      for (final name in names)
        Case.load(caseDir(name), attributes: attributes),
    ];
  }

  /// Writes the case [name]: [input] as `input.adoc`, [options] as
  /// `case.yml`, and the files it reads, copied from [files] (a directory,
  /// laid out as the case is) when given. A case of that name is replaced.
  /// Its goldens are [generateGoldens]'s to write.
  String write(
    String name,
    String input,
    CaseOptions options, {
    String? files,
  }) {
    final dir = Directory(caseDir(name));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    if (files != null) {
      for (final entity in Directory(files).listSync(recursive: true)) {
        if (entity is! File) continue;
        File(p.join(dir.path, p.relative(entity.path, from: files)))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(entity.readAsBytesSync());
      }
    }
    File(p.join(dir.path, 'input.adoc')).writeAsStringSync(input);
    File(p.join(dir.path, 'case.yml')).writeAsStringSync(options.toYaml());
    return dir.path;
  }

  /// Writes the goldens of the cases [names] that have none
  /// (`goldens/generate.rb`, with the release's bundle that
  /// `tool/setup.sh` installs); its report.
  Future<String> generateGoldens(List<String> names, {int jobs = 4}) async {
    if (names.isEmpty) return '';
    final goldens = p.join(toolsRoot, 'goldens');
    final result = await Process.run(
      'bundle',
      ['exec', 'ruby', 'generate.rb', '-j', '$jobs', root, ...names],
      workingDirectory: goldens,
      environment: {
        'BUNDLE_GEMFILE': p.join(goldens, release, 'Gemfile'),
        'BUNDLE_PATH': p.join(cacheDir, 'bundle-$release'),
      },
    );
    if (result.exitCode != 0 && '${result.stdout}'.isEmpty) {
      throw ProcessException(
        'bundle',
        ['exec', 'ruby', 'generate.rb'],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }
}
