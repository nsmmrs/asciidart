/// Edits of the attribute entries in a document's header that leave every
/// other byte of its source as written.
///
/// The parser records where each attribute entry of the header is in the
/// source ([DocumentAttributeEntry.lines]) and where the body starts
/// ([Document.bodyStartLine]); an edit replaces, adds or removes the lines
/// of one attribute's entries. Where the result can't be known from the
/// source alone (an entry in an include, or under a preprocessor
/// conditional) the edit is refused rather than guessed.
library;

import 'package:ptome/src/document.dart';
import 'package:ptome/src/errors.dart';
import 'package:ptome/src/parser.dart';
import 'package:ptome/src/rx.dart';

/// [source] (the source of [document]) with the header attribute [name]
/// set to [value]: the entry that sets it last is rewritten (an unset
/// entry, `:name!:`, becomes a set one), or, when the header has none, an
/// entry is added at the end of the header. Returns [source] itself when
/// that entry already reads `:name: value`.
String setHeaderAttribute(
  Document document,
  String source,
  String name,
  String value,
) {
  if (value.contains('\n') || value.contains('\r')) {
    throw ArgumentError.value(
      value,
      'value',
      'must be one line (a header attribute entry holds one line)',
    );
  }
  final edit = _HeaderEdit(document, source, name);
  final entries = edit.entries;
  if (entries.isEmpty) {
    return edit.insert(edit.insertionLine(), _entryLine(name, value));
  }
  final (:first, :last) = entries.last.lines!;
  final match = edit.entryMatch(first)!;
  final written = match.group(1)!;
  if (first == last &&
      !written.contains('!') &&
      (match.group(2) ?? '') == value) {
    return source;
  }
  return edit.replace(first, last, [
    _entryLine(written.replaceAll('!', ''), value),
  ]);
}

/// [source] (the source of [document]) without the header attribute
/// entries for [name]. Returns [source] itself when the header has none.
String removeHeaderAttribute(Document document, String source, String name) {
  final edit = _HeaderEdit(document, source, name);
  if (edit.entries.isEmpty) return source;
  return edit.remove([for (final entry in edit.entries) entry.lines!]);
}

/// Matches a single-line preprocessor conditional (`ifdef::x[:a: b]`),
/// capturing its content.
final RegExp _singleLineConditionalRx = RegExp(
  r'^if(?:n?def|eval)::[^\[]*\[(.+)\]$',
);

/// The entry line setting [name] to [value].
String _entryLine(String name, String value) =>
    value.isEmpty ? ':$name:' : ':$name: $value';

/// The attribute name an entry for [name] stores (`:Numbered:` sets
/// `sectnums`), or `null` when [name] has no valid characters.
String? _storedName(String name) =>
    switch (Parser.sanitizeAttributeName(name.replaceAll('!', ''))) {
      '' => null,
      'numbered' => 'sectnums',
      'hardbreaks' => 'hardbreaks-option',
      final sanitized => sanitized,
    };

/// One edit of a source: its lines (each with its `\r`, if any), the
/// header's entries for the attribute, and the check that the source alone
/// can make the edit.
final class _HeaderEdit {
  new(this.document, String source, String name)
    : _lines = source.split('\n'),
      _crlf = source.contains('\r\n'),
      key =
          _storedName(name) ??
          (throw ArgumentError.value(
            name,
            'name',
            'is not an attribute name',
          )) {
    _check();
  }

  final Document document;
  final List<String> _lines;
  final bool _crlf;

  /// The name the attribute is stored under.
  final String key;

  /// The header's entries for the attribute, in source order.
  late final List<DocumentAttributeEntry> entries = [
    for (final entry in _headerEntries)
      if (entry.name == key) entry,
  ];

  List<DocumentAttributeEntry> get _headerEntries =>
      document.headerAttributeEntries ?? const [];

  int get _bodyStart =>
      document.bodyStartLine ??
      (throw const AsciidoctorException(
        'cannot edit the header: it ends inside an include',
      ));

  /// Line [lineno] (1-based) without its line terminator and trailing
  /// spaces, as the parser reads it.
  String _line(int lineno) => _lines[lineno - 1].trimRight();

  /// The attribute entry on line [lineno] (1-based), if it holds one.
  RegExpMatch? entryMatch(int lineno) => lineno < 1 || lineno > _lines.length
      ? null
      : attributeEntryRx.firstMatch(_line(lineno));

  /// Refuses an edit the source alone can't make: an entry for the
  /// attribute in an include or under a conditional, or one the parser
  /// skipped (under a conditional that is false).
  void _check() {
    final bodyStart = _bodyStart;
    final covered = <int>{};
    for (final entry in entries) {
      final lines = entry.lines;
      final match = lines == null ? null : entryMatch(lines.first);
      if (lines == null ||
          match == null ||
          _storedName(match.group(1)!) != key) {
        throw AsciidoctorException(
          'cannot edit the header attribute $key: the header sets it in an '
          'include or under a preprocessor conditional',
        );
      }
      for (var lineno = lines.first; lineno <= lines.last; lineno++) {
        covered.add(lineno);
      }
    }
    String? commentFence;
    for (
      var lineno = 1;
      lineno < bodyStart && lineno <= _lines.length;
      lineno++
    ) {
      final line = _line(lineno);
      if (commentFence != null) {
        if (line == commentFence) commentFence = null;
        continue;
      }
      if (line.length >= 4 && line.replaceAll('/', '').isEmpty) {
        commentFence = line;
        continue;
      }
      final match = attributeEntryRx.firstMatch(
        _singleLineConditionalRx.firstMatch(line)?.group(1) ?? line,
      );
      if (match != null &&
          !covered.contains(lineno) &&
          _storedName(match.group(1)!) == key) {
        throw AsciidoctorException(
          'cannot edit the header attribute $key: line $lineno sets it under '
          'a preprocessor conditional',
        );
      }
    }
  }

  /// The 1-based line a new entry goes before: the end of the header's
  /// title block (title, author and revision lines, entries) when it has a
  /// title; else after the header's last entry; else the top.
  int insertionLine() {
    final bodyStart = _bodyStart;
    final titleLine = document.header?.sourceLocation?.lineno;
    if (titleLine != null && titleLine < bodyStart) {
      var lineno = titleLine;
      while (lineno + 1 < bodyStart &&
          lineno < _lines.length &&
          _line(lineno + 1).isNotEmpty) {
        lineno += 1;
      }
      return lineno + 1;
    }
    var last = 0;
    for (final entry in _headerEntries) {
      if (entry.lines case (first: _, last: final end) when end > last) {
        last = end;
      }
    }
    return last + 1;
  }

  /// The source with [line] inserted before line [lineno] (1-based); at
  /// the top of a document whose first line isn't empty, an empty line
  /// separates it from what follows.
  String insert(int lineno, String line) {
    final atTop = lineno == 1 && _lines.isNotEmpty && _line(1).isNotEmpty;
    final atEnd = lineno > _lines.length;
    return _join([
      ..._lines.sublist(0, lineno - 1),
      if (atEnd) line else _terminated(line),
      if (atTop) _terminated(''),
      ..._lines.sublist(lineno - 1),
    ]);
  }

  /// The source with lines [first] to [last] (1-based) replaced by
  /// [replacement].
  String replace(int first, int last, List<String> replacement) => _join([
    ..._lines.sublist(0, first - 1),
    for (final line in replacement) _terminated(line),
    ..._lines.sublist(last),
  ]);

  /// The source without the lines of [spans].
  String remove(List<({int first, int last})> spans) {
    final result = List.of(_lines);
    for (final (:first, :last) in spans.reversed) {
      result.removeRange(first - 1, last);
    }
    return _join(result);
  }

  /// [line] with the source's line terminator (`\r` before the `\n` the
  /// join adds, in a source with CRLF line endings).
  String _terminated(String line) => _crlf ? '$line\r' : line;

  String _join(List<String> lines) => lines.join('\n');
}
