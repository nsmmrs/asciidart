/// The implementations whose outputs the corpus records (`profiles.toml`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

/// Where checkouts, gems, the raw pool and fuzz state live; never committed.
String get cacheDir =>
    Platform.environment['ASCII_DOCS_CACHE'] ??
    p.join(Platform.environment['HOME']!, '.cache', 'ascii-docs');

/// One implementation.
sealed class Profile {
  const Profile(this.name, {this.attributes = const {}});

  final String name;

  /// Attributes this profile always converts with, as soft defaults.
  final Map<String, String> attributes;

  /// Reads every profile from [path].
  static Map<String, Profile> load(String path) {
    final doc = TomlDocument.loadSync(path).toMap();
    return {
      for (final MapEntry(:key, :value) in doc.entries)
        key: Profile._parse(key, (value as Map).cast<String, Object?>()),
    };
  }

  static Profile _parse(String name, Map<String, Object?> table) {
    final attributes = (table['attributes'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k as String, v.toString()),
    );
    return switch (table['kind']) {
      'ruby' => RubyProfile(
        name,
        repo: table['repo']! as String,
        commit: table['commit']! as String,
        attributes: attributes,
      ),
      'asciidart' => AsciidartProfile(
        name,
        compareTo: table['compare-to'] as String?,
        attributes: attributes,
      ),
      final kind => throw FormatException('profile $name: unknown kind $kind'),
    };
  }
}

/// Asciidoctor (Ruby) at a commit, run by `drivers/ruby/worker.rb`.
final class RubyProfile extends Profile {
  const RubyProfile(
    super.name, {
    required this.repo,
    required this.commit,
    super.attributes,
  });

  final String repo;
  final String commit;

  /// The checkout `tool/setup.sh` makes.
  String get adocRoot => p.join(cacheDir, 'refs', name);

  /// The isolated gem directory `tool/setup.sh` fills.
  String? get gemHome => p.join(cacheDir, 'gems');

  /// The worker's memory cap (systemd-run), or null for none.
  String? get memoryMax => '2G';
}

/// asciidart, in-process, at the commit `pubspec.yaml` pins.
final class AsciidartProfile extends Profile {
  const AsciidartProfile(super.name, {this.compareTo, super.attributes});

  /// The profile whose output asciidart must match except where a case
  /// records a divergence (a fixed upstream bug).
  final String? compareTo;
}
