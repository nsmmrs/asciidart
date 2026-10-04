// Positional params mirror Ruby signatures for port fidelity.
// The table reader is dynamic so tests can pass fakes; dynamic dispatch on
// it mirrors Ruby duck typing.
// ignore_for_file: avoid_positional_boolean_parameters, avoid_dynamic_calls
/// Structural document model: tables, columns, cells and table parsing.
///
/// Port of `lib/asciidoctor/table.rb` (complete).
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/parser.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/substitutors.dart';

/// Scans for a leading, non-escaped anchor (id + optional reference text).
///
/// Port of `Asciidoctor::LeadingInlineAnchorRx`. Per `PORTING-REGEXP.md`
/// rules B1/B9/R1/R2: `CC_ALPHA` becomes `\p{Alphabetic}`, `CC_WORD` becomes
/// `\w` with `unicode: true`, `CC_ANY` (`.`, no `/m`) becomes `[^\n]`, and
/// the `^` anchor requires `multiLine: true`.
final RegExp _leadingInlineAnchorRx = RegExp(
  r'^\[\[([\p{Alphabetic}_:][\w\-:.]*)(?:, *([^\n]+?))?\]\]',
  multiLine: true,
  unicode: true,
);

/// Matches a blank line (two or more newlines).
///
/// Port of `Asciidoctor::BlankLineRx` (verbatim; no flags needed).
final RegExp _blankLineRx = RegExp(r'\n{2,}');

/// Rounds [value] to [precision] decimal places, half away from zero.
/// Port of Ruby's `Float#round` with a precision argument.
double _roundAtPrecision(num value, int precision) {
  var factor = 1;
  for (var i = 0; i < precision; i++) {
    factor *= 10;
  }
  return (value.toDouble() * factor).round() / factor;
}

/// Minimal forward stub for `Asciidoctor::Reader::Cursor` (reader.dart not
/// yet ported). Only used to carry a source location into log messages.
class ReaderCursor {
  /// Creates a cursor wrapping opaque [data] (as returned by `mark`).
  new(this.data);

  /// The opaque cursor data.
  final List<Object?> data;

  @override
  String toString() => 'ReaderCursor($data)';
}

/// A data object that encapsulates the collection of rows (head, foot,
/// body) for a table.
///
/// Port of `Asciidoctor::Table::Rows`.
class TableRows {
  /// Creates a row collection (all sections default to empty).
  new([List<List<Cell>>? head, List<List<Cell>>? foot, List<List<Cell>>? body])
    : head = head ?? <List<Cell>>[],
      foot = foot ?? <List<Cell>>[],
      body = body ?? <List<Cell>>[];

  /// The head rows.
  List<List<Cell>> head;

  /// The foot rows.
  List<List<Cell>> foot;

  /// The body rows.
  List<List<Cell>> body;

  /// Returns the rows of the [section] (`'head'`, `'body'` or `'foot'`;
  /// anything else throws, mirroring Ruby's `method_missing` on the
  /// `Rows#[]` → `send` alias).
  List<List<Cell>> operator [](Object section) {
    switch (section.toString()) {
      case 'head':
        return head;
      case 'body':
        return body;
      case 'foot':
        return foot;
      default:
        throw ArgumentError.value(
          section,
          'section',
          'no such row section (mirrors Ruby send)',
        );
    }
  }

  /// The rows grouped by section, in document order (head, body, foot).
  ///
  /// Port of `Asciidoctor::Table::Rows#by_section` (note the order really
  /// is head, body, foot despite the doc comment in Ruby).
  List<(String, List<List<Cell>>)> get bySection =>
      <(String, List<List<Cell>>)>[
        ('head', head),
        ('body', body),
        ('foot', foot),
      ];

  /// The rows as a map from section name to rows.
  ///
  /// Port of `Asciidoctor::Table::Rows#to_h`.
  Map<String, List<List<Cell>>> toMap() => <String, List<List<Cell>>>{
    'head': head,
    'body': body,
    'foot': foot,
  };
}

/// Methods and constants for managing AsciiDoc table content in a document.
///
/// Port of `Asciidoctor::Table`.
class Table extends AbstractBlock {
  /// Creates a table with [parent], resolving the table widths from the
  /// `'width'` and page-width attributes.
  ///
  /// Note that [attributes] is only read here (for `'width'` and
  /// `'rotate-option'`); the computed values land on this table's own
  /// attributes, exactly as in Ruby.
  new(AbstractBlock? parent, Map<String, Object?> attributes)
    : super(parent, 'table') {
    final pcwidth = attributes['width'];
    late final int pcwidthIntval;
    if (isTruthy(pcwidth)) {
      var intval = rubyToInteger(pcwidth);
      if (intval > 100 || intval < 1) {
        if (!(intval == 0 && (pcwidth == '0' || pcwidth == '0%'))) {
          intval = 100;
        }
      }
      pcwidthIntval = intval;
    } else {
      pcwidthIntval = 100;
    }
    this.attributes['tablepcwidth'] = pcwidthIntval;

    final pagewidth = document!.attributes['pagewidth'];
    if (isTruthy(pagewidth)) {
      final abswidthVal = ((pcwidthIntval / 100.0) * rubyToDouble(pagewidth))
          .truncateAtPrecision(defaultPrecision);
      this.attributes['tableabswidth'] = abswidthVal.toInt() == abswidthVal
          ? abswidthVal.toInt()
          : abswidthVal;
    }

    if (isTruthy(attributes['rotate-option'])) {
      this.attributes['orientation'] = 'landscape';
    }
  }

  /// The precision of column widths.
  static const int defaultPrecision = 4;

  /// The columns of this table.
  List<Column> columns = <Column>[];

  /// The rows of this table (head, foot and body).
  TableRows rows = TableRows();

  /// Whether this table has a header row: `true`, `'implicit'`, `false`
  /// or `null` (each with distinct meaning in [partitionHeaderFooter]).
  Object? hasHeaderOption = false;

  /// The current state of the header option (`true` or `'implicit'`) when
  /// the row being processed is (or is assumed to be) the header row,
  /// otherwise `false`.
  ///
  /// Port of `Asciidoctor::Table#header_row?`.
  Object get headerRow {
    final value = hasHeaderOption;
    return isTruthy(value) && rows.body.isEmpty ? value! : false;
  }

  /// Creates the [Column] objects from the [colspecs] column specifications.
  ///
  /// Port of `Asciidoctor::Table#create_columns`.
  void createColumns(List<Map<String, Object?>> colspecs) {
    final cols = <Column>[];
    List<Column>? autowidthCols;
    num widthBase = 0;
    for (final colspec in colspecs) {
      final colwidth = colspec['width']! as num;
      cols.add(Column(this, cols.length, colspec));
      if (colwidth < 0) {
        (autowidthCols ??= <Column>[]).add(cols.last);
      } else {
        widthBase += colwidth;
      }
    }
    columns = cols;
    if (cols.isNotEmpty) {
      attributes['colcount'] = cols.length;
      final base = widthBase > 0 || autowidthCols != null ? widthBase : null;
      assignColumnWidths(base, autowidthCols);
    }
  }

  /// Assigns column widths to the columns.
  ///
  /// Percentage widths are rounded to 4 decimal places and the balance, if
  /// any, is donated to the final column. Assumes at least one column.
  ///
  /// Port of `Asciidoctor::Table#assign_column_widths`.
  void assignColumnWidths([Object? widthBase, List<Column>? autowidthCols]) {
    const precision = defaultPrecision;
    num totalWidth = 0;
    num colPcwidth = 0;

    if (isTruthy(widthBase)) {
      if (autowidthCols != null) {
        final base = widthBase! as num;
        late final num autowidth;
        if (base > 100) {
          autowidth = 0;
          logger.warn(
            'total column width must not exceed 100% when using '
            'autowidth columns; got $base%',
          );
        } else {
          final computed = ((100.0 - base.toDouble()) / autowidthCols.length)
              .truncateAtPrecision(precision);
          autowidth = computed.toInt() == computed
              ? computed.toInt()
              : computed;
          widthBase = 100;
        }
        final autowidthAttrs = <String, Object?>{
          'width': autowidth,
          'autowidth-option': '',
        };
        for (final col in autowidthCols) {
          col.updateAttributes(autowidthAttrs);
        }
      }
      for (final col in columns) {
        totalWidth += colPcwidth =
            (col.assignWidth(null, widthBase, precision)! as num);
      }
    } else {
      final computed = (100.0 / columns.length).truncateAtPrecision(precision);
      colPcwidth = computed.toInt() == computed ? computed.toInt() : computed;
      for (final col in columns) {
        totalWidth += (col.assignWidth(colPcwidth, null, precision)! as num);
      }
    }

    // Donate the balance, if any, to the final column (half up rounding).
    if (totalWidth != 100) {
      columns.last.assignWidth(
        _roundAtPrecision(100 - totalWidth + colPcwidth, precision),
        null,
        precision,
      );
    }
  }

  /// Partitions the body rows into header, footer and body as determined by
  /// the options on the table.
  ///
  /// Port of `Asciidoctor::Table#partition_header_footer`.
  void partitionHeaderFooter(Map<String, Object?> attrs) {
    final body = rows.body;
    // Set the row count before splitting up the body rows.
    var numBodyRows = body.length;
    attributes['rowcount'] = numBodyRows;

    if (numBodyRows > 0) {
      if (isTruthy(hasHeaderOption)) {
        rows.head = [
          body.removeAt(0).map((cell) => cell.reinitialize(true)).toList(),
        ];
        numBodyRows -= 1;
      } else if (hasHeaderOption == null) {
        hasHeaderOption = false;
        body.insert(
          0,
          body.removeAt(0).map((cell) => cell.reinitialize(false)).toList(),
        );
      }
    }

    if (numBodyRows > 0 && isTruthy(attrs['footer-option'])) {
      rows.foot = [body.removeLast()];
    }
  }
}

/// Methods to manage the columns of an AsciiDoc table.
///
/// Port of `Asciidoctor::Table::Column`.
class Column extends AbstractNode {
  /// Creates a column of [table] at 0-based [index], resolving the column
  /// number and the `width`/`halign`/`valign` defaults into [attributes]
  /// (mutating the passed map, as in Ruby) and copying them onto this
  /// column.
  new(Table? table, int index, [Map<String, Object?>? attributes])
    : super(table, 'table_column') {
    final attrs = attributes ?? <String, Object?>{};
    style = attrs['style'] as String?;
    attrs['colnumber'] = index + 1;
    if (!isTruthy(attrs['width'])) attrs['width'] = 1;
    if (!isTruthy(attrs['halign'])) attrs['halign'] = 'left';
    if (!isTruthy(attrs['valign'])) attrs['valign'] = 'top';
    updateAttributes(attrs);
  }

  /// The style of this column (e.g. `'asciidoc'`).
  String? style;

  /// An alias for the parent block (which is always a [Table]; mirrors
  /// `alias table parent`).
  Table? get table => parent as Table?;

  /// Calculates and assigns the percentage and absolute widths of this
  /// column, returning the resolved `colpcwidth` value.
  ///
  /// Port of `Asciidoctor::Table::Column#assign_width`.
  Object? assignWidth(Object? colPcwidth, Object? widthBase, int precision) {
    var pcwidth = colPcwidth as num?;
    if (isTruthy(widthBase)) {
      final computed =
          ((attributes['width']! as num).toDouble() *
                  100.0 /
                  (widthBase! as num).toDouble())
              .truncateAtPrecision(precision);
      pcwidth = computed.toInt() == computed ? computed.toInt() : computed;
    }
    final tableAbswidth = parent!.attributes['tableabswidth'];
    if (isTruthy(tableAbswidth)) {
      final computed = ((pcwidth! / 100.0) * (tableAbswidth! as num).toDouble())
          .truncateAtPrecision(precision);
      attributes['colabswidth'] = computed.toInt() == computed
          ? computed.toInt()
          : computed;
    }
    return attributes['colpcwidth'] = pcwidth;
  }

  @override
  bool get isBlock => false;

  @override
  bool get isInline => false;
}

/// Adapts a [Cursor] to [NodeSourceLocation] (mirrors the private adapters
/// in `parser.dart` and `document.dart`).
class _CursorSourceLocation implements NodeSourceLocation {
  /// Creates a source location from [cursor].
  new(this._cursor);

  final Cursor _cursor;

  @override
  String? get file {
    final file = _cursor.file;
    return file is String ? file : file?.toString();
  }

  @override
  int? get lineno => _cursor.lineno;
}

/// An immutable [NodeSourceLocation] snapshot (copy semantics for location
/// values passed directly, e.g. test doubles).
class _SnapshotSourceLocation implements NodeSourceLocation {
  /// Creates a snapshot of [file]:[lineno].
  new(this.file, this.lineno);

  @override
  final String? file;

  @override
  final int? lineno;
}

/// Methods for managing a cell in an AsciiDoc table.
///
/// Port of `Asciidoctor::Table::Cell`.
class Cell extends AbstractBlock {
  /// Creates a cell of [column] with [cellText].
  ///
  /// The [attributes] map selects the PSV path (it is mutated: `colspan`
  /// and `rowspan` are removed); an explicit `null` selects the
  /// CSV/DSV path. [opts] carries the parser cursor under `'cursor'`.
  /// The default is a shared empty map, which is safe because Ruby never
  /// mutates the default (the empty-attributes branch performs no writes).
  ///
  /// AsciiDoc-style cells build a nested document eagerly (see the
  /// `asciidoc` branch below), mirroring Ruby.
  new(
    Column? column,
    String? cellText, [
    Map<String, Object?>? attributes = const <String, Object?>{},
    Map<String, Object?>? opts,
  ]) : _column = column,
       super(column?.table, 'table_cell') {
    final attrs = attributes;
    if (document!.sourcemap) {
      // Port of `@source_location = opts[:cursor].dup if @document.sourcemap`
      // (`lib/asciidoctor/table.rb`); `nil.dup` is `nil` in Ruby. The copy
      // matters: the original cursor may advance afterwards (asciidoc
      // cells), which must not move the stored location.
      final cursor = opts?['cursor'];
      // Ruby dups the cursor (`nil.dup` is `nil`). Real cursors are exposed
      // through the wave-local adapter since `Cursor` does not implement
      // `NodeSourceLocation` itself; doubles implementing the interface
      // (e.g. `FakeCursor`) are snapshotted (immutable copy semantics).
      sourceLocation = switch (cursor) {
        Cursor() => _CursorSourceLocation(cursor.dup()),
        NodeSourceLocation() => _SnapshotSourceLocation(
          cursor.file,
          cursor.lineno,
        ),
        _ => null,
      };
    }
    String? cellStyle;
    Object? inHeaderRow;
    // NOTE column is always set when parsing; may not be set when building
    // a table from the API.
    if (column != null) {
      inHeaderRow = column.table!.headerRow;
      if (isTruthy(inHeaderRow)) {
        if (inHeaderRow == 'implicit') {
          cellStyle =
              column.style ??
              (attrs == null ? null : attrs['style'] as String?);
          if (isTruthy(cellStyle)) {
            if (cellStyle == 'asciidoc' || cellStyle == 'literal') {
              _reinitializeArgs = <Object?>[
                column,
                cellText,
                if (attrs == null) null else Map<String, Object?>.of(attrs),
                opts,
              ];
            }
            cellStyle = null;
          }
        }
      } else {
        cellStyle = column.style;
      }
      // REVIEW feels hacky to inherit all attributes from column.
      updateAttributes(column.attributes);
    }
    var asciidoc = false;
    var literal = false;
    var normalPsv = false;
    Object? innerDocumentCursor;
    // NOTE when attributes is defined, this is a PSV cell, which implies
    // the text needs to be stripped.
    if (attrs != null) {
      if (attrs.isEmpty) {
        colspan = null;
        rowspan = null;
      } else {
        colspan = attrs.remove('colspan');
        rowspan = attrs.remove('rowspan');
        // TODOdelete style attribute from @attributes if set.
        if (!isTruthy(inHeaderRow)) {
          final attrStyle = attrs['style'];
          if (isTruthy(attrStyle)) cellStyle = (attrStyle! as String);
        }
        updateAttributes(attrs);
      }
      if (cellStyle == 'asciidoc') {
        asciidoc = true;
        innerDocumentCursor = opts?['cursor'];
        var text = cellText!.rstrip();
        if (text.startsWith(lf)) {
          var linesAdvanced = 1;
          while ((text = text.substring(1)).startsWith(lf)) {
            linesAdvanced += 1;
          }
          // NOTE this only works if we remain in the same file.
          (opts?['cursor'] as dynamic).advance(linesAdvanced);
        } else {
          text = lstrip(text);
        }
        cellText = text;
      } else if (cellStyle == 'literal') {
        literal = true;
        var text = cellText!.rstrip();
        // QUESTION should we use same logic as :asciidoc cell? strip
        // leading space if text doesn't start with newline?
        while (text.startsWith(lf)) {
          text = text.substring(1);
        }
        cellText = text;
      } else {
        normalPsv = true;
        // NOTE AsciidoctorJ uses nil cell_text to create an empty cell.
        cellText = cellText != null ? cellText.trim() : '';
      }
    } else {
      colspan = null;
      rowspan = null;
      if (cellStyle == 'asciidoc') {
        asciidoc = true;
        innerDocumentCursor = opts?['cursor'];
      }
    }
    // NOTE only true for non-header rows.
    if (asciidoc) {
      // NodeDocument/Document unification pending: the document is always
      // a Document here (same cast as `catalogInlineAnchor`).
      final parentDoc = document! as Document;
      // FIXME hide doctitle from nested document; temporary workaround to
      // fix nested document seeing doctitle and assuming it has its own
      // document title.
      final parentDoctitle = parentDoc.attributes.remove('doctitle');
      // NOTE we need to process the first line of content as it may not
      // have been processed. The included content cannot expect to match
      // conditional terminators in the remaining lines of table cell
      // content; it must be self-contained logic.
      // Dart's `split` keeps trailing empty segments like Ruby's
      // `split LF, -1`, except that `''.split` yields `['']` where Ruby
      // yields `[]`.
      final cellSource = cellText;
      final innerDocumentLines = cellSource == null || cellSource.isEmpty
          ? <String>[]
          : cellSource.split(lf);
      if (innerDocumentLines.isNotEmpty) {
        final unprocessedLine1 = innerDocumentLines[0];
        // QUESTION is it faster to check for `::` before splitting?
        if (unprocessedLine1.contains('::')) {
          final preprocessedLines = PreprocessorReader(
            parentDoc.asReaderDocument(),
            [unprocessedLine1],
            innerDocumentCursor,
          ).readlines().whereType<String>().toList();
          if (!(preprocessedLines.isNotEmpty &&
              unprocessedLine1 == preprocessedLines[0] &&
              preprocessedLines.length < 2)) {
            innerDocumentLines.removeAt(0);
            if (preprocessedLines.isNotEmpty) {
              innerDocumentLines.insertAll(0, preprocessedLines);
            }
          }
        }
      }
      innerDocument = Document(innerDocumentLines, {
        'standalone': false,
        'parent': parentDoc,
        'cursor': innerDocumentCursor,
      });
      if (parentDoctitle != null) {
        parentDoc.attributes['doctitle'] = parentDoctitle;
      }
      // Ruby assigns `@subs = nil` (a nil subs list applies nothing);
      // `subs` is non-nullable here, so the empty list plays that role.
      subs = <String>[];
    } else if (literal) {
      contentModel = 'verbatim';
      subs = basicSubs;
    } else {
      if (normalPsv) {
        if (isTruthy(inHeaderRow)) {
          _cursor = opts?['cursor']; // Used in the deferred catalog call.
        } else {
          catalogInlineAnchor(cellText, opts?['cursor']);
        }
      }
      contentModel = 'simple';
      subs = normalSubs;
    }
    _text = cellText;
    style = cellStyle;
  }

  /// Two consecutive line feeds (a blank line).
  static const String doubleLf = '\n\n';

  /// The number of columns this cell spans, if set.
  Object? colspan;

  /// The number of rows this cell spans, if set.
  Object? rowspan;

  /// The nested document in an AsciiDoc table cell (only set when the style
  /// is `'asciidoc'`).
  Document? innerDocument;

  dynamic _cursor;
  List<Object?>? _reinitializeArgs;
  String? _text;

  /// The column this cell belongs to.
  ///
  /// Ruby parents the cell to the column, but the port types node parents
  /// as [AbstractBlock] and columns are not blocks, so the constructor
  /// passes the table instead and the column is kept here.
  final Column? _column;

  /// An alias for the column this cell belongs to (mirrors
  /// `alias column parent`).
  Column? get column => _column;

  /// Reinitializes this cell for (or out of) the header row.
  ///
  /// Port of `Asciidoctor::Table::Cell#reinitialize`.
  Cell reinitialize(bool hasHeader) {
    if (hasHeader) {
      _reinitializeArgs = null;
    } else if (_reinitializeArgs != null) {
      final args = _reinitializeArgs!;
      return Cell(
        args[0] as Column?,
        args[1] as String?,
        args[2] as Map<String, Object?>?,
        args[3] as Map<String, Object?>?,
      );
    } else {
      style = attributes['style'] as String?;
    }
    if (_cursor != null) catalogInlineAnchor();
    return this;
  }

  /// Catalogs a leading inline anchor in [cellText] (defaulting to this
  /// cell's text), unless there is none.
  ///
  /// Port of `Asciidoctor::Table::Cell#catalog_inline_anchor`.
  void catalogInlineAnchor([String? cellText, Object? cursor]) {
    var c = cursor;
    if (!isTruthy(c)) {
      c = _cursor;
      _cursor = null;
    }
    final text = cellText ?? _text!;
    if (!text.startsWith('[[')) return;
    final match = _leadingInlineAnchorRx.firstMatch(text);
    if (match == null) return;
    Parser.catalogInlineAnchor(
      match.group(1)!,
      match.group(2),
      this,
      c,
      // NodeDocument/Document unification pending: the document is always
      // a Document here (same cast as Parser._docOf).
      document as Document?,
    );
  }

  /// The text of this cell with substitutions applied.
  ///
  /// Used for head-row cells as well as text-only cells in the foot row and
  /// body; not for AsciiDoc-style cells. (The writer mirrors
  /// `attr_writer :text`.)
  // NOTE `this.` is load-bearing (see list.dart: same import-scope
  // shadowing quirk for substitutor members).
  String? get text => this.applySubs(_text, subs) as String?;

  set text(String? value) {
    _text = value;
  }

  /// Handles the body data, applying styles and partitioning into
  /// paragraphs. Not for head-row or literal-style cells.
  ///
  /// Port of `Asciidoctor::Table::Cell#content`. Ruby parents the styled
  /// paragraphs to the column; the port passes this cell's parent (the
  /// table) instead, since inline nodes require a block parent.
  @override
  Object? content() {
    final cellStyle = style;
    if (cellStyle == 'asciidoc') {
      return innerDocument!.convert();
    } else if (_text!.contains(doubleLf)) {
      return rubySplit(text!, _blankLineRx)
          .map(
            (para) => isTruthy(cellStyle) && cellStyle != 'header'
                ? (Inline(
                        parent,
                        'quoted',
                        text: para,
                        type: cellStyle,
                      ).convert()!
                      as String)
                : para,
          )
          .toList();
    } else {
      final subbedText = text!;
      if (subbedText.isEmpty) return <String>[];
      if (isTruthy(cellStyle) && cellStyle != 'header') {
        return <String>[
          Inline(parent, 'quoted', text: subbedText, type: cellStyle).convert()!
              as String,
        ];
      }
      return <String>[subbedText];
    }
  }

  /// The lines of this cell's text.
  List<String> lines() => rubySplit(_text!, lf);

  /// The source text of this cell.
  String? source() => _text;

  @override
  String toString() =>
      '${super.toString()} - [text: ${_text ?? ''}, '
      'colspan: ${isTruthy(colspan) ? colspan : 1}, '
      'rowspan: ${isTruthy(rowspan) ? rowspan : 1}, '
      'attributes: $attributes]';
}

/// Methods for managing the parsing of an AsciiDoc table.
///
/// Instances of this class track the buffer of a cell as the parser moves
/// through the table lines. When a cell boundary is located, the previous
/// cell is closed, a [Cell] is instantiated, the row is closed when the cell
/// satisfies the column count, and a new buffer tracks the next cell.
///
/// Port of `Asciidoctor::Table::ParserContext`.
class TableParserContext {
  /// Creates a parser context for [table], reading from [reader] (a
  /// `Reader`; `dynamic` until `reader.dart` lands).
  ///
  /// Port of `Asciidoctor::Table::ParserContext#initialize`.
  new(dynamic reader, Table table, [Map<String, Object?>? attributes]) {
    final attrs = attributes ?? <String, Object?>{};
    _reader = reader;
    _startCursorData = reader.mark();
    this.table = table;

    late String xsv;
    if (attrs.containsKey('format')) {
      xsv = attrs['format'] as String? ?? '';
      if (formats.contains(xsv)) {
        if (xsv == 'tsv') {
          // NOTE tsv is just an alias for csv with a tab separator.
          format = 'csv';
        } else {
          format = xsv;
          if (xsv == 'psv' && table.document!.nested()) {
            xsv = '!sv';
          }
        }
      } else {
        logger.error(
          messageWithContext('illegal table format: $xsv', {
            'sourceLocation': reader.cursorAtPrevLine(),
          }),
        );
        format = 'psv';
        xsv = table.document!.nested() ? '!sv' : 'psv';
      }
    } else {
      format = 'psv';
      xsv = table.document!.nested() ? '!sv' : 'psv';
    }

    if (attrs.containsKey('separator')) {
      final sep = attrs['separator'] as String?;
      if (sep == null || sep.isEmpty) {
        final entry = delimiters[xsv]!;
        _delimiter = entry.$1;
        _delimiterRx = entry.$2;
      } else if (sep == r'\t') {
        // NOTE the Ruby source compares against single-quoted '\t', i.e.
        // a literal backslash followed by `t`, not a tab.
        final entry = delimiters['tsv']!;
        _delimiter = entry.$1;
        _delimiterRx = entry.$2;
      } else {
        _delimiter = sep;
        _delimiterRx = RegExp(RegExp.escape(sep));
      }
    } else {
      final entry = delimiters[xsv]!;
      _delimiter = entry.$1;
      _delimiterRx = entry.$2;
    }

    _colcount = table.columns.isEmpty ? -1 : table.columns.length;
    buffer = '';
    _cellspecs = <Map<String, Object?>>[];
    _cellOpen = false;
    _activeRowspans = <int>[0];
    _columnVisits = 0;
    _currentRow = <Cell>[];
    _linenum = -1;
  }

  /// The table formats recognized in AsciiDoc.
  static const Set<String> formats = <String>{'psv', 'csv', 'dsv', 'tsv'};

  /// The default cell delimiters (string and pattern) per table format.
  ///
  /// The three literal patterns port verbatim (no flags needed per
  /// `PORTING-REGEXP.md`: no anchors, no character-class shorthands).
  static final Map<String, (String, RegExp)> delimiters =
      <String, (String, RegExp)>{
        'psv': ('|', RegExp(r'\|')),
        'csv': (',', RegExp(',')),
        'dsv': (':', RegExp(':')),
        'tsv': ('\t', RegExp(r'\t')),
        '!sv': ('!', RegExp('!')),
      };

  /// The shared logger.
  ///
  /// Routes to [AbstractNode.currentLogger], the [NodeLogger] seam shared by
  /// every node (mirrors the `logger` method from the `Logging` mixin).
  NodeLogger get logger => AbstractNode.currentLogger;

  /// Builds a log message carrying [text] plus optional [context] entries
  /// (e.g. `{'sourceLocation': cursor}`).
  ///
  /// Port of `Logging#message_with_context`, which returns a Hash extended
  /// with auto-formatting; here the entries are folded into a plain string.
  /// (The logging wave may replace the folding with a structured message.)
  String messageWithContext(
    String text, [
    Map<String, Object?> context = const <String, Object?>{},
  ]) {
    if (context.isEmpty) return text;
    final details = context.entries
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    return '$text ($details)';
  }

  /// The table currently being parsed.
  Table? table;

  /// The AsciiDoc table format (`'psv'`, `'csv'` or `'dsv'`).
  String? format;

  int _colcount = -1;

  /// The expected column count for a row (-1 takes the count from the first
  /// line).
  int get colcount => _colcount;

  /// The buffer of the currently open cell.
  String buffer = '';

  late final String _delimiter;

  /// The cell delimiter for this table.
  String get delimiter => _delimiter;

  late final RegExp _delimiterRx;

  /// The compiled cell-delimiter pattern for this table.
  ///
  /// Faithful quirk: in Ruby only the `delimiter_re` reader is declared
  /// while the constructor assigns `@delimiter_rx`, so `delimiter_re` is
  /// always `nil` (verified with `ruby -Ilib -e`). This getter preserves
  /// that behavior; matching uses the private pattern.
  RegExp? get delimiterRe => null;

  dynamic _reader;
  Object? _startCursorData;
  List<Map<String, Object?>> _cellspecs = <Map<String, Object?>>[];
  bool _cellOpen = false;
  List<int> _activeRowspans = <int>[0];
  int _columnVisits = 0;
  List<Cell> _currentRow = <Cell>[];
  int _linenum = -1;

  /// Whether [line] starts with the cell delimiter of this table.
  bool startsWithDelimiter(String line) => line.startsWith(_delimiter);

  /// Matches the cell delimiter in [line], returning the match (or `null`
  /// when the line holds no delimiter).
  RegExpMatch? matchDelimiter(String line) => _delimiterRx.firstMatch(line);

  /// Skips past the matched delimiter because it sits inside quoted text.
  void skipPastDelimiter(String pre) {
    buffer = '$buffer$pre$_delimiter';
  }

  /// Skips past the matched delimiter because it is escaped.
  void skipPastEscapedDelimiter(String pre) {
    buffer = '$buffer${chopLast(pre)}$_delimiter';
  }

  /// Whether the buffer has unclosed quotes (used for CSV data).
  ///
  /// Port of `Asciidoctor::Table::ParserContext#buffer_has_unclosed_quotes?`.
  bool bufferHasUnclosedQuotes([String? append, String q = '"']) {
    final record = append != null ? (buffer + append).trim() : buffer.trim();
    if (record == q) return true;
    if (record.startsWith(q)) {
      final qq = q + q;
      final trailingQuote = record.endsWith(q);
      if ((trailingQuote && record.endsWith(qq)) || record.startsWith(qq)) {
        final stripped = record.replaceAll(qq, '');
        return stripped.startsWith(q) && !stripped.endsWith(q);
      }
      return !trailingQuote;
    }
    return false;
  }

  /// Takes a cell spec from the stack (cell specs precede the delimiter, so
  /// a stack carries the spec from the previous cell to the current one).
  Map<String, Object?>? takeCellspect() =>
      _cellspecs.isEmpty ? null : _cellspecs.removeAt(0);

  /// Pushes a cell spec onto the stack for the next cell.
  void pushCellspect([Map<String, Object?>? cellspec]) {
    // This shouldn't be null, but we check anyway.
    _cellspecs.add(cellspec ?? <String, Object?>{});
  }

  /// Marks that the cell stays open (used at end of line when the cell may
  /// hold additional text).
  void keepCellOpen() {
    _cellOpen = true;
  }

  /// Marks the cell as closed so the parser instantiates a new cell and
  /// adds it to the current row.
  void markCellClosed() {
    _cellOpen = false;
  }

  /// Whether the current cell is still open.
  bool get isCellOpen => _cellOpen;

  /// Whether the current cell has been marked as closed.
  bool get isCellClosed => !_cellOpen;

  /// Closes the open cell, if any, pushing [nextCellspect] for the next
  /// cell, and advances to the next line.
  void closeOpenCell([Map<String, Object?>? nextCellspect]) {
    pushCellspect(nextCellspect);
    if (isCellOpen) closeCell(true);
    _advance();
  }

  /// Closes the current cell, instantiates a [Cell], adds it to the current
  /// row and, when the expected column count is met, closes the row and
  /// begins a new one.
  ///
  /// Port of `Asciidoctor::Table::ParserContext#close_cell`.
  void closeCell([bool eol = false]) {
    late final String cellText;
    late final Map<String, Object?>? cellspec;
    late final int repeat;
    if (format == 'psv') {
      cellText = buffer;
      buffer = '';
      final taken = takeCellspect();
      if (taken != null) {
        cellspec = taken;
        final repeatcol = taken.remove('repeatcol');
        repeat = isTruthy(repeatcol) ? rubyToInteger(repeatcol) : 1;
      } else {
        logger.error(
          messageWithContext(
            'table missing leading separator; recovering automatically',
            {
              'sourceLocation': ReaderCursor(
                List<Object?>.of(_startCursorData! as List<Object?>),
              ),
            },
          ),
        );
        cellspec = <String, Object?>{};
        repeat = 1;
      }
    } else {
      var text = buffer.trim();
      buffer = '';
      cellspec = null;
      repeat = 1;
      if (format == 'csv' && text.isNotEmpty && text.contains('"')) {
        // This may not be perfect logic, but it hits the 99%.
        if (text.startsWith('"') && text.endsWith('"')) {
          // Unquote.
          if (text.length > 1) {
            // Trim whitespace and collapse escaped quotes.
            text = squeezeChar(text.substring(1, text.length - 1).trim(), '"');
          } else {
            logger.error(
              messageWithContext(
                'unclosed quote in CSV data; setting cell to empty',
                {'sourceLocation': _reader.cursorAtPrevLine()},
              ),
            );
            text = '';
          }
        } else {
          // Collapse escaped quotes.
          text = squeezeChar(text, '"');
        }
      }
      cellText = text;
    }

    for (var i = 1; i <= repeat; i++) {
      // TODOmake column resolving an operation.
      late final Column? column;
      if (_colcount == -1) {
        final t = table!;
        column = Column(t, t.columns.length + i - 1);
        t.columns.add(column);
        final cs = cellspec;
        if (cs != null && cs.containsKey('colspan')) {
          final extraCols = rubyToInteger(cs['colspan']) - 1;
          if (extraCols > 0) {
            final offset = t.columns.length;
            for (var j = 0; j < extraCols; j++) {
              t.columns.add(Column(t, offset + j));
            }
          }
        }
      } else {
        column = table!.columns[_currentRow.length];
      }

      final cell = Cell(column, cellText, cellspec, {
        'cursor': _reader.cursorBeforeMark(),
      });
      _reader.mark();
      if (isTruthy(cell.rowspan) && cell.rowspan != 1) {
        _activateRowspan(
          rubyToInteger(cell.rowspan),
          isTruthy(cell.colspan) ? rubyToInteger(cell.colspan) : 1,
        );
      }
      _columnVisits += isTruthy(cell.colspan) ? rubyToInteger(cell.colspan) : 1;
      _currentRow.add(cell);
      final rowStatus = _endOfRow();
      if (rowStatus > -1 &&
          (_colcount != -1 || _linenum > 0 || (eol && i == repeat))) {
        if (rowStatus > 0) {
          logger.error(
            messageWithContext(
              'dropping cell because it exceeds specified number of columns',
              {'sourceLocation': _reader.cursorBeforeMark()},
            ),
          );
          _closeRow(true);
        } else {
          _closeRow();
        }
      }
    }
    _cellOpen = false;
  }

  /// Reports cells dropped from an incomplete row at the end of the table.
  void closeTable() {
    if (_columnVisits == 0) return;
    logger.error(
      messageWithContext(
        'dropping cells from incomplete row detected end of table',
        {'sourceLocation': _reader.cursorBeforeMark()},
      ),
    );
  }

  /// Closes the row by adding it to the table and resetting the row state.
  void _closeRow([bool drop = false]) {
    if (!drop) table!.rows.body.add(_currentRow);
    // Don't have to account for active rowspans here since this is the
    // first row.
    if (_colcount == -1) _colcount = _columnVisits;
    _columnVisits = 0;
    _currentRow = <Cell>[];
    _activeRowspans.removeAt(0);
    if (_activeRowspans.isEmpty) _activeRowspans.add(0);
  }

  /// Activates a rowspan of [rowspan] rows over [colspan] columns.
  void _activateRowspan(int rowspan, int colspan) {
    for (var i = 1; i <= rowspan - 1; i++) {
      while (_activeRowspans.length <= i) {
        _activeRowspans.add(0);
      }
      _activeRowspans[i] += colspan;
    }
  }

  /// Whether the effective column count is met for the current row: -1
  /// when short, 0 when exact, 1 when overrunning.
  int _endOfRow() =>
      _colcount == -1 ? 0 : _effectiveColumnVisits.compareTo(_colcount);

  /// The effective column visits: cells plus active rowspans.
  int get _effectiveColumnVisits => _columnVisits + _activeRowspans[0];

  /// Advances to the next line (which may come after the parser begins
  /// processing the next line if the last cell had wrapped content).
  void _advance() {
    _linenum += 1;
  }
}
