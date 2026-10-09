part of 'api.dart';

/// A document's units model, shared by the views of its units.
final class _UnitsModel {
  new _(this.analysis);

  /// The model of [analysis], made once.
  factory of(impl.Analysis analysis) =>
      _models[analysis] ??= _UnitsModel._(analysis);

  static final Expando<_UnitsModel> _models = Expando('units model');

  final impl.Analysis analysis;

  final Map<impl.Unit, Unit> _views = Map.identity();

  /// The units in document order.
  late final List<impl.Unit> ordered = [...analysis.units]
    ..sort((a, b) => a.start.compareTo(b.start));

  /// Each unit's parent: the unit of the nearest level above with the
  /// labels it has there.
  late final Map<impl.Unit, impl.Unit?> _parents = {
    for (final u in analysis.units) u: _findParent(u),
  };

  late final Map<impl.Unit, List<impl.Unit>> _children = () {
    final children = <impl.Unit, List<impl.Unit>>{};
    for (final u in ordered) {
      if (_parents[u] case final parent?) (children[parent] ??= []).add(u);
    }
    return children;
  }();

  impl.Unit? _findParent(impl.Unit u) {
    final scheme = u.level.scheme;
    for (var d = u.level.depth - 1; d >= 0; d--) {
      if (u.labels[d] == null) continue;
      final found =
          analysis.index[analysis.keyOf(scheme, u.labels.sublist(0, d + 1))];
      if (found != null && !identical(found, u)) return found;
    }
    return null;
  }

  Unit view(impl.Unit u) => _views[u] ??= Unit._(this, u);

  Unit? parentOf(impl.Unit u) => switch (_parents[u]) {
    final p? => view(p),
    null => null,
  };

  List<Unit> childrenOf(impl.Unit u) => [
    for (final c in _children[u] ?? const <impl.Unit>[]) view(c),
  ];

  /// Where [loc] was read: its file and 1-based line.
  (String, int)? where(impl.Loc? loc) {
    if (loc == null) return null;
    final origin = loc.file.originOf(loc.line);
    return origin == null
        ? (loc.file.path, loc.line + 1)
        : (origin.file ?? origin.path, origin.line);
  }
}

/// A numbered unit of a document written in units (`:units:` in its
/// header; see `doc/units.md`): a verse, a chapter, a section, a line.
final class Unit {
  new _(this._model, this._unit);

  final _UnitsModel _model;
  final impl.Unit _unit;

  /// The name of the scheme the unit belongs to (`bible`).
  String get scheme => _unit.level.scheme.name;

  /// The name of the unit's level (`verse`).
  String get level => _unit.level.name;

  /// The level's depth in its scheme (0 for the outermost: a book).
  int get depth => _unit.level.depth;

  /// The labels of the unit's level and the levels above it, by level
  /// name, as markers write them (`{book: EXO, chapter: 34, verse: 6}`).
  Map<String, String> get labels => {
    for (final (d, label) in _unit.labels.indexed)
      if (label != null) _unit.level.scheme.levels[d].name: label.text,
  };

  /// The unit's ID (`v-exo-34-6`), its anchor in the output.
  String get id => _unit.id;

  /// The unit's reftext (`Exodus 34:6`), what references to it show.
  String get reftext => _unit.reftext;

  /// The unit as its scheme cites it (`Exod 34:6`).
  String get citation =>
      impl.passageText(impl.Passage(_unit, _unit), _model.analysis.config);

  /// The path of the source file the unit starts in.
  String get path => _model.where(_unit.start)!.$1;

  /// The line the unit starts on (1-based).
  int get line => _model.where(_unit.start)!.$2;

  /// The unit it is in: the unit of the nearest level above (a verse's
  /// chapter), if any.
  Unit? get parent => _model.parentOf(_unit);

  /// The units in it at the levels below, in document order (a chapter's
  /// verses).
  List<Unit> get children => _model.childrenOf(_unit);

  /// The notes that belong to it (at their streams' reset level), in the
  /// order of their callers.
  List<UnitNote> get notes => [
    for (final uses in _unit.notes.values)
      for (final use in uses) UnitNote._(_model, use),
  ];

  @override
  String toString() => citation;
}

/// A note of a note stream in a document written in units (`note:x[…]`).
final class UnitNote {
  new _(this._model, this._use);

  final _UnitsModel _model;
  final impl.NoteUse _use;

  /// The note's stream (`x`).
  String get stream => _use.stream.name;

  /// Its caller in its stream (`a`), if the stream has callers.
  String? get caller => _use.caller.isEmpty ? null : _use.caller;

  /// The words it is on, if it has any (`##merciful##note:x[…]`).
  String? get lemma => _use.note.lemma;

  /// The note's text, as written.
  String get text => _use.note.body;

  /// The unit it belongs to, if any.
  Unit? get unit => switch (_use.unit) {
    final u? => _model.view(u),
    null => null,
  };

  @override
  String toString() => text;
}

/// A passage of a document written in units: the units from one to
/// another (`Exod 34:6-7`).
final class Passage {
  new _(this._model, this._passage);

  final _UnitsModel _model;
  final impl.Passage _passage;

  /// Its first unit.
  Unit get start => _model.view(_passage.start);

  /// Its last unit.
  Unit get end => _model.view(_passage.end);

  /// The passage as its scheme cites it, what its ends share said once
  /// (`Exod 34:6–7`).
  String get citation => impl.passageText(_passage, _model.analysis.config);

  /// Its units at its last unit's level and below, in document order.
  List<Unit> get units {
    final start = _passage.start.start;
    final end = _passage.end;
    impl.Loc? stop;
    for (final u in _model.ordered) {
      if (u.level.scheme == end.level.scheme &&
          u.level.depth <= end.level.depth &&
          !u.isZero &&
          u.start.compareTo(end.start) > 0) {
        stop = u.start;
        break;
      }
    }
    return [
      for (final u in _model.ordered)
        if (u.start.compareTo(start) >= 0 &&
            (stop == null || u.start.compareTo(stop) < 0) &&
            u.level.scheme == end.level.scheme &&
            u.level.depth >= end.level.depth)
          _model.view(u),
    ];
  }

  @override
  String toString() => citation;
}

/// A reference by address in a document written in units
/// (`<<Ps 86:15; 103:8–13>>`), resolved.
final class UnitReference {
  new _(this._model, this._use);

  final _UnitsModel _model;
  final impl.RefUse _use;

  /// The reference as written, between its brackets.
  String get text => _use.xref.content;

  /// The path of the source file it is in.
  String get path => _model.where(_use.xref.loc)!.$1;

  /// The line it is on (1-based).
  int get line => _model.where(_use.xref.loc)!.$2;

  /// The passages it cites, each with what it links to; a passage not
  /// found has no target.
  List<UnitReferenceLink> get links => [
    for (final part in _use.parts)
      if (part case impl.RefLink(:final text, :final id, :final file))
        UnitReferenceLink._(text.trim(), id, file),
  ];

  @override
  String toString() => text;
}

/// A passage a reference cites, and the anchor it links to.
@immutable
final class UnitReferenceLink {
  const new _(this.text, this.id, this.document);

  /// The passage as written (`103:8–13`).
  final String text;

  /// The ID it links to (`v-psa-103-8`).
  final String id;

  /// The other document it is in, for a passage of another work.
  final String? document;

  @override
  bool operator ==(Object other) =>
      other is UnitReferenceLink &&
      other.text == text &&
      other.id == id &&
      other.document == document;

  @override
  int get hashCode => Object.hash(text, id, document);

  @override
  String toString() => text;
}
