/// The index of a document as asciidoctor-pdf catalogs it: terms (up to
/// three levels) under the letter they start with, each with where it's
/// used and the terms it refers to.
library;

import 'package:meta/meta.dart';

/// A name in the index: its text (for sorting) and its inline markup.
@immutable
final class IndexName implements Comparable<IndexName> {
  /// The name of [markup], read as [text].
  const new(this.text, this.markup);

  /// The plain text.
  final String text;

  /// The inline markup.
  final String markup;

  /// The gem's order: case-insensitively (ASCII letters), then by the
  /// characters.
  @override
  int compareTo(IndexName other) {
    final folded = _fold(text).compareTo(_fold(other.text));
    return folded != 0 ? folded : text.compareTo(other.text);
  }

  static String _fold(String text) => text.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => match[0]!.toLowerCase(),
  );

  @override
  bool operator ==(Object other) =>
      other is IndexName && other.text == text && other.markup == markup;

  @override
  int get hashCode => Object.hash(text, markup);
}

/// Where a term is used: its anchor and, once laid out, its page.
final class IndexDestination {
  /// The use at [anchor].
  new(this.anchor);

  /// The anchor at the use.
  final String anchor;

  /// The page's label, once laid out.
  String? page;

  /// The page's number, once laid out.
  int? pageNumber;
}

/// A group of terms: the index's letter categories, and terms with
/// subterms.
base class IndexGroup implements Comparable<IndexGroup> {
  /// The group named [name].
  new(this.name);

  /// The name.
  final IndexName name;

  final Map<IndexName, IndexTerm> _terms = {};

  /// The term [name] of this group (added if new), used at [destination],
  /// referring to [see] or [seeAlso].
  IndexTerm store(
    IndexName name, {
    IndexDestination? destination,
    IndexName? see,
    List<IndexName> seeAlso = const [],
  }) {
    final term = _terms[name] ??= IndexTerm(name);
    if (destination != null) term._destinations.add(destination);
    if (term._seeName == null && see != null) term._seeName = see;
    term._seeAlsoNames.addAll(seeAlso);
    return term;
  }

  /// The terms, in order.
  List<IndexTerm> get terms => _terms.values.toList()..sort();

  @override
  int compareTo(IndexGroup other) => name.compareTo(other.name);
}

/// A letter of the index (`@` for terms that don't start with one).
final class IndexCategory extends IndexGroup {
  /// The category [name].
  new(super.name);
}

/// A term of the index.
final class IndexTerm extends IndexGroup {
  /// The term [name].
  new(super.name) : anchor = '__indextermdef-${_sequence++}';

  static int _sequence = 0;

  /// The anchor of its entry in the index.
  final String anchor;

  final Set<IndexDestination> _destinations = {};
  IndexName? _seeName;
  final List<IndexName> _seeAlsoNames = [];

  /// The term it refers to instead, if any (resolved, or just its name).
  (IndexTerm?, IndexName)? see;

  /// The terms it refers to as well, in order (each resolved, or just its
  /// name).
  List<(IndexTerm?, IndexName)> seeAlso = const [];

  /// Where it's used that was laid out, by page.
  List<IndexDestination> get destinations => [
    for (final destination in _destinations)
      if (destination.page != null) destination,
  ]..sort((a, b) => a.pageNumber!.compareTo(b.pageNumber!));

  /// Whether it's only a container of subterms (not used anywhere laid
  /// out).
  bool get isContainer =>
      _destinations.every((destination) => destination.page == null);

  /// Whether it has no subterms.
  bool get isLeaf => _terms.isEmpty;
}

/// The index of a document.
final class IndexCatalog {
  final Map<String, IndexCategory> _categories = {};
  final Map<String, IndexDestination> _destinations = {};
  int _sequence = 0;

  /// The anchor of the next use of a term.
  String nextAnchor() => '__indexterm-${++_sequence}';

  /// Whether no term was stored.
  bool get isEmpty => _categories.isEmpty;

  /// The categories, in order.
  List<IndexCategory> get categories => _categories.values.toList()..sort();

  /// Stores the term of [names] (one to three levels) used at [anchor],
  /// referring to [see] or [seeAlso].
  void store(
    List<IndexName> names,
    String anchor, {
    IndexName? see,
    List<IndexName> seeAlso = const [],
  }) {
    if (names.isEmpty) return;
    final destination = _destinations[anchor] ??= IndexDestination(anchor);
    IndexGroup group = _category(names.first);
    for (final (i, name) in names.take(3).indexed) {
      final last = i == names.length - 1 || i == 2;
      group = group.store(
        name,
        destination: last ? destination : null,
        see: last ? see : null,
        seeAlso: last ? seeAlso : const [],
      );
    }
  }

  IndexCategory _category(IndexName name) {
    final text = name.text;
    final first = text.isEmpty ? '' : String.fromCharCode(text.runes.first);
    final letter = RegExp(r'^\p{L}', unicode: true).hasMatch(first)
        ? first.toUpperCase()
        : '@';
    return _categories[letter] ??= IndexCategory(IndexName(letter, letter));
  }

  /// Sets the page of the term uses at each anchor, by [pages] (the
  /// physical page of each anchor) and [label] (its label).
  void linkPages(
    int? Function(String anchor) pages,
    String Function(int page) label,
  ) {
    for (final destination in _destinations.values) {
      final page = pages(destination.anchor);
      destination
        ..pageNumber = page
        ..page = page == null ? null : label(page);
    }
  }

  /// Resolves the terms each term refers to (to primary terms by name).
  void linkAssociations() {
    IndexTerm? primary(IndexName name) {
      for (final category in _categories.values) {
        for (final term in category._terms.values) {
          if (term.name == name) return term;
        }
      }
      return null;
    }

    void link(IndexGroup group) {
      for (final term in group._terms.values) {
        if (term._seeName case final name?) {
          term.see = (primary(name), name);
        } else if (term._seeAlsoNames.isNotEmpty) {
          term.seeAlso = [
            for (final name in term._seeAlsoNames) (primary(name), name),
          ]..sort((a, b) => a.$2.compareTo(b.$2));
        }
        if (!term.isLeaf) link(term);
      }
    }

    _categories.values.forEach(link);
  }
}
