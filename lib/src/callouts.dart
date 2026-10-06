/// Callout catalog for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/callouts.rb`.
library;

import 'package:asciidart/src/cursor.dart';

/// A single registered callout: the 1-based [ordinal] of its list item and
/// its unique [id] (e.g. `CO1-1`).
class Callout {
  /// Creates a callout for list item [ordinal] with unique [id], in the
  /// block at [at].
  const new({required this.ordinal, required this.id, this.at});

  /// 1-based ordinal of the list item this callout is associated with.
  final int ordinal;

  /// Unique id of this callout.
  final String id;

  /// Where the block with the callout starts, if known.
  final Cursor? at;
}

/// Maintains a catalog of callouts and their associations.
class Callouts {
  /// Creates a catalog positioned at the first callout list.
  new() {
    nextList();
  }

  final List<List<Callout>> _lists = [];
  int _listIndex = 0;
  int _coIndex = 1;

  /// Registers a new callout for list item [liOrdinal].
  ///
  /// Generates a unique id for this callout based on the index of the next
  /// callout list in the document and the index of this callout since the
  /// end of the last callout list. Returns the unique id of this callout.
  String register(int liOrdinal, {Cursor? at}) {
    final id = _generateNextCalloutId();
    currentList.add(Callout(ordinal: liOrdinal, id: id, at: at));
    _coIndex++;
    return id;
  }

  /// Reads the next callout id in the document and advances the pointer.
  ///
  /// Used during conversion to retrieve the unique id of the callout that
  /// was generated during parsing. Returns `null` when exhausted.
  String? readNextId() {
    String? id;
    final list = currentList;
    if (_coIndex <= list.length) id = list[_coIndex - 1].id;
    _coIndex++;
    return id;
  }

  /// Space-separated list of callout ids for list item [liOrdinal].
  String calloutIds(int liOrdinal) => currentList
      .where((item) => item.ordinal == liOrdinal)
      .map((item) => item.id)
      .join(' ');

  /// The current list for which callouts are being collected.
  List<Callout> get currentList => _lists[_listIndex - 1];

  /// Advances to the next callout list in the document.
  void nextList() {
    _listIndex++;
    if (_lists.length < _listIndex) _lists.add([]);
    _coIndex = 1;
  }

  /// Rewinds the list index pointer, for switching from the parsing to the
  /// conversion phase.
  void rewind() {
    _listIndex = 1;
    _coIndex = 1;
  }

  String _generateNextCalloutId() => _generateCalloutId(_listIndex, _coIndex);

  static String _generateCalloutId(int listIndex, int coIndex) =>
      'CO$listIndex-$coIndex';
}
