/// The implementations whose outputs the corpus records (`profiles.toml`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import 'conversion.dart';

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
        gems: [for (final gem in table['gems'] as List? ?? const []) '$gem'],
        requires: [
          for (final library in table['requires'] as List? ?? const [])
            '$library',
        ],
        formats: {
          for (final format in table['formats'] as List? ?? const [])
            Format.parse('$format'),
        },
        attributes: attributes,
      ),
      'ptome' => PtomeProfile(
        name,
        compareTo: table['compare-to'] as String?,
        pdfCompareTo: table['pdf-compare-to'] as String?,
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
    this.gems = const [],
    this.requires = const [],
    this.formats = const {},
    super.attributes,
  });

  final String repo;
  final String commit;

  /// Gems of its own (`name:version`), installed in a gem directory of
  /// its own (no optional gems but these); none: the shared gems.
  final List<String> gems;

  /// Libraries the worker requires after Asciidoctor (`asciidoctor-pdf`).
  final List<String> requires;

  /// The formats it converts; none: the text formats.
  final Set<Format> formats;

  /// Whether it converts [format].
  bool converts(Format format) =>
      formats.isEmpty ? !format.binary : formats.contains(format);

  /// The checkout `tool/setup.sh` makes.
  String get adocRoot => p.join(cacheDir, 'refs', name);

  /// The isolated gem directory `tool/setup.sh` fills.
  String? get gemHome => p.join(cacheDir, gems.isEmpty ? 'gems' : 'gems-$name');

  /// The worker's memory cap (systemd-run), or null for none.
  String? get memoryMax => '2G';
}

/// ptome, in-process, at the commit `pubspec.yaml` pins.
final class PtomeProfile extends Profile {
  const PtomeProfile(
    super.name, {
    this.compareTo,
    this.pdfCompareTo,
    super.attributes,
  });

  /// The profile whose output ptome must match except where a case
  /// records a divergence (a fixed upstream bug).
  final String? compareTo;

  /// The profile whose PDF pages ptome's must equal pixel for pixel
  /// (recorded as each PDF's `pixels`).
  final String? pdfCompareTo;
}
