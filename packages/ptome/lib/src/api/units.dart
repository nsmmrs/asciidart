part of 'api.dart';

/// A numbered unit of a document written in units (`:units:` in its
/// header; see `doc/units.md`): a verse, a chapter, a section, a line.
final class Unit {
  const new _({
    required this.scheme,
    required this.level,
    required this.depth,
    required this.labels,
    required this.id,
    required this.reftext,
    required this.citation,
    required this.path,
    required this.line,
  });

  /// The name of the scheme the unit belongs to (`bible`).
  final String scheme;

  /// The name of the unit's level (`verse`).
  final String level;

  /// The level's depth in its scheme (0 for the outermost: a book).
  final int depth;

  /// The labels of the unit's level and the levels above it, by level
  /// name, as markers write them (`{book: EXO, chapter: 34, verse: 6}`).
  final Map<String, String> labels;

  /// The unit's ID (`v-exo-34-6`), its anchor in the output.
  final String id;

  /// The unit's reftext (`Exodus 34:6`), what references to it show.
  final String reftext;

  /// The unit as its scheme cites it (`Exod 34:6`).
  final String citation;

  /// The path of the source file the unit starts in.
  final String path;

  /// The line the unit starts on (1-based).
  final int line;

  @override
  String toString() => citation;
}

Unit _unit(impl.Analysis analysis, impl.Unit u) {
  final config = analysis.config;
  // Where the parser read the unit's start.
  final origin = u.start.file.originOf(u.start.line);
  return Unit._(
    scheme: u.level.scheme.name,
    level: u.level.name,
    depth: u.level.depth,
    labels: {
      for (final (d, label) in u.labels.indexed)
        if (label != null) u.level.scheme.levels[d].name: label.text,
    },
    id: u.id,
    reftext: u.reftext,
    citation: impl.passageText(impl.Passage(u, u), config),
    path: origin?.file ?? origin?.path ?? u.start.file.path,
    line: origin?.line ?? u.start.line + 1,
  );
}
