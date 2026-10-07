/// Structural document model: tables, columns, cells and table parsing.
///
/// Port of `lib/asciidoctor/table.rb` (complete).
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/logging.dart';
import 'package:asciidart/src/parser.dart';
import 'package:asciidart/src/reader.dart';
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/substitutors.dart';
import 'package:meta/meta.dart';

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
double _roundAtPrecision(num value, int precision) {
  var factor = 1;
  for (var i = 0; i < precision; i++) {
    factor *= 10;
  }
  return (value.toDouble() * factor).round() / factor;
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
  /// anything else throws).
  List<List<Cell>> operator [](String section) {
    switch (section) {
      case 'head':
        return head;
      case 'body':
        return body;
      case 'foot':
        return foot;
      default:
        throw ArgumentError.value(section, 'section', 'no such row section');
    }
  }

  /// The rows grouped by section, in document order (head, body, foot).
  ///
  /// Port of `Asciidoctor::Table::Rows#by_section` (the order is head,
  /// body, foot).
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

/// The specification of one table column, parsed from the `cols`
/// attribute.
final class ColumnSpec {
  /// Creates a column spec.
  const new({this.width = 1, this.halign, this.valign, this.style});

  /// The relative width (a negative value requests an automatic width).
  final int width;

  /// The horizontal alignment (`left`, `center` or `right`).
  final String? halign;

  /// The vertical alignment (`top`, `middle` or `bottom`).
  final String? valign;

  /// The column style (e.g. `asciidoc`, `literal`, `header`).
  final String? style;
}

/// The specification of one table cell, parsed from the text before a cell
/// separator.
final class CellSpec {
  /// Creates a cell spec.
  const new({
    this.colspan,
    this.rowspan,
    this.repeat,
    this.halign,
    this.valign,
    this.style,
  });

  /// The number of columns the cell spans, when more than one.
  final int? colspan;

  /// The number of rows the cell spans, when more than one.
  final int? rowspan;

  /// How many times the cell repeats across columns, when more than once.
  final int? repeat;

  /// The horizontal alignment (`left`, `center` or `right`).
  final String? halign;

  /// The vertical alignment (`top`, `middle` or `bottom`).
  final String? valign;

  /// The cell style (e.g. `asciidoc`, `literal`, `header`).
  final String? style;

  /// Whether the spec sets nothing.
  bool get isEmpty =>
      colspan == null &&
      rowspan == null &&
      repeat == null &&
      halign == null &&
      valign == null &&
      style == null;

  /// The alignment and style as node attributes.
  Map<String, String> get attributes => <String, String>{
    'halign': ?halign,
    'valign': ?valign,
    'style': ?style,
  };
}

/// How a table treats its first row.
enum TableHeader {
  /// The first row is the header (the `header` option).
  explicit,

  /// The first row is the header because it is followed by a blank line.
  implicit,

  /// The first row is not the header (the `noheader` option).
  none,

  /// Not decided yet: the parser decides from the first row.
  undecided,
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
  /// attributes.
  new(AbstractBlock? parent, Map<String, String> attributes)
    : super(parent, BlockContext.table) {
    final pcwidth = attributes['width'];
    if (pcwidth != null) {
      var intval = parseLeadingInt(pcwidth);
      if (intval > 100 || intval < 1) {
        if (!(intval == 0 && (pcwidth == '0' || pcwidth == '0%'))) {
          intval = 100;
        }
      }
      this.pcwidth = intval;
    } else {
      this.pcwidth = 100;
    }
    this.attributes['tablepcwidth'] = '${this.pcwidth}';

    final pagewidth = document!.attributes['pagewidth'];
    if (pagewidth != null) {
      final abswidthVal =
          ((this.pcwidth / 100.0) * parseLeadingDouble(pagewidth))
              .truncateAtPrecision(defaultPrecision);
      final value = abswidthVal.toInt() == abswidthVal
          ? abswidthVal.toInt()
          : abswidthVal;
      abswidth = value;
      this.attributes['tableabswidth'] = formatNumber(value);
    }

    if (attributes.containsKey('rotate-option')) {
      this.attributes['orientation'] = 'landscape';
    }
  }

  /// The precision of column widths.
  static const int defaultPrecision = 4;

  /// The width of the table as a percentage of the available width.
  late final int pcwidth;

  /// The absolute width of the table, when the backend has a page width.
  num? abswidth;

  /// The columns of this table.
  List<Column> columns = <Column>[];

  /// The rows of this table (head, foot and body).
  TableRows rows = TableRows();

  /// How this table treats its first row.
  TableHeader header = TableHeader.none;

  /// The number of body rows before the head and foot rows were split off.
  int rowcount = 0;

  /// Whether the row being processed is (or is assumed to be) the header
  /// row; [TableHeader.implicit] when assumed from a blank line.
  ///
  /// Port of `Asciidoctor::Table#header_row?`.
  @internal
  TableHeader get headerRow =>
      (header == TableHeader.explicit || header == TableHeader.implicit) &&
          rows.body.isEmpty
      ? header
      : TableHeader.none;

  /// Creates the [Column] objects from the [colspecs] column specifications.
  ///
  /// Port of `Asciidoctor::Table#create_columns`.
  @internal
  void createColumns(List<ColumnSpec> colspecs) {
    final cols = <Column>[];
    List<Column>? autowidthCols;
    num widthBase = 0;
    for (final colspec in colspecs) {
      final colwidth = colspec.width;
      cols.add(Column(this, cols.length, colspec));
      if (colwidth < 0) {
        (autowidthCols ??= <Column>[]).add(cols.last);
      } else {
        widthBase += colwidth;
      }
    }
    columns = cols;
    if (cols.isNotEmpty) {
      attributes['colcount'] = '${cols.length}';
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
  @internal
  void assignColumnWidths([num? widthBase, List<Column>? autowidthCols]) {
    var baseWidth = widthBase;
    const precision = defaultPrecision;
    num totalWidth = 0;
    num colPcwidth = 0;

    if (baseWidth != null) {
      if (autowidthCols != null) {
        final base = baseWidth;
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
          baseWidth = 100;
        }
        for (final col in autowidthCols) {
          col
            ..width = autowidth
            ..setOption('autowidth');
        }
      }
      for (final col in columns) {
        totalWidth += colPcwidth = col.assignWidth(null, baseWidth, precision);
      }
    } else {
      final computed = (100.0 / columns.length).truncateAtPrecision(precision);
      colPcwidth = computed.toInt() == computed ? computed.toInt() : computed;
      for (final col in columns) {
        totalWidth += col.assignWidth(colPcwidth, null, precision);
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
  @internal
  void partitionHeaderFooter({required bool footer}) {
    final body = rows.body;
    // Set the row count before splitting up the body rows.
    var numBodyRows = rowcount = body.length;
    attributes['rowcount'] = '$numBodyRows';

    if (numBodyRows > 0) {
      if (header == TableHeader.explicit || header == TableHeader.implicit) {
        rows.head = [
          body
              .removeAt(0)
              .map((cell) => cell.reinitialize(hasHeader: true))
              .toList(),
        ];
        numBodyRows -= 1;
      } else if (header == TableHeader.undecided) {
        header = TableHeader.none;
        body.insert(
          0,
          body
              .removeAt(0)
              .map((cell) => cell.reinitialize(hasHeader: false))
              .toList(),
        );
      }
    }

    if (numBodyRows > 0 && footer) {
      rows.foot = [body.removeLast()];
    }
  }
}

/// Methods to manage the columns of an AsciiDoc table.
///
/// Port of `Asciidoctor::Table::Column`.
class Column extends AbstractNode {
  /// Creates a column of the table [parent] at 0-based [index] from [spec],
  /// recording the column number, width and alignments in [attributes].
  new(Table? super.parent, int index, [ColumnSpec spec = const ColumnSpec()])
    : colnumber = index + 1,
      style = spec.style {
    attributes['colnumber'] = '$colnumber';
    width = spec.width;
    attributes['halign'] = spec.halign ?? 'left';
    attributes['valign'] = spec.valign ?? 'top';
    if (spec.style case final style?) attributes['style'] = style;
  }

  @override
  String get contextName => 'table_column';

  @override
  String get nodeName => 'table_column';

  /// The 1-based column number.
  final int colnumber;

  /// The style of this column (e.g. `'asciidoc'`).
  String? style;

  num _width = 1;

  /// The relative width of this column (the `width` attribute).
  num get width => _width;

  set width(num value) {
    _width = value;
    attributes['width'] = formatNumber(value);
  }

  /// The width of this column as a percentage of the table width (the
  /// `colpcwidth` attribute), once assigned.
  num? pcwidth;

  /// The absolute width of this column (the `colabswidth` attribute), when
  /// the table has an absolute width.
  num? abswidth;

  /// An alias for the parent block (which is always a [Table]; mirrors
  /// `alias table parent`).
  Table? get table => parent as Table?;

  /// Calculates and assigns the percentage and absolute widths of this
  /// column, returning the percentage width.
  ///
  /// Port of `Asciidoctor::Table::Column#assign_width`.
  @internal
  num assignWidth(num? colPcwidth, num? widthBase, int precision) {
    var pcwidth = colPcwidth;
    if (widthBase != null) {
      final computed = (_width.toDouble() * 100.0 / widthBase.toDouble())
          .truncateAtPrecision(precision);
      pcwidth = computed.toInt() == computed ? computed.toInt() : computed;
    }
    final resolved = pcwidth!;
    final tableAbswidth = table?.abswidth;
    if (tableAbswidth != null) {
      final computed = ((resolved / 100.0) * tableAbswidth.toDouble())
          .truncateAtPrecision(precision);
      final value = computed.toInt() == computed ? computed.toInt() : computed;
      abswidth = value;
      attributes['colabswidth'] = formatNumber(value);
    }
    this.pcwidth = resolved;
    attributes['colpcwidth'] = formatNumber(resolved);
    return resolved;
  }

  @override
  bool get isBlock => false;

  @override
  bool get isInline => false;
}

/// Methods for managing a cell in an AsciiDoc table.
///
/// Port of `Asciidoctor::Table::Cell`.
class Cell extends AbstractBlock {
  /// Creates a cell of [column] with [cellText].
  ///
  /// [spec] is the cell spec of a PSV table cell, whose text is stripped;
  /// `null` marks a CSV or DSV cell, whose text is taken as is. [cursor] is
  /// the position of the cell in the source.
  ///
  /// AsciiDoc-style cells build a nested document eagerly.
  new(
    Column? column,
    String? cellText, [
    CellSpec? spec = const CellSpec(),
    Cursor? cursor,
  ]) : _column = column,
       super(column?.table, BlockContext.tableCell) {
    var cellContent = cellText;
    if (document!.sourcemap) {
      // Store a copy of the cursor as the source location. The copy
      // matters: the original cursor may advance afterwards (asciidoc
      // cells), which must not move the stored location.
      sourceLocation = cursor?.dup();
    }
    String? cellStyle;
    var inHeaderRow = TableHeader.none;
    // NOTE column is always set when parsing; may not be set when building
    // a table from the API.
    if (column != null) {
      inHeaderRow = column.table!.headerRow;
      if (inHeaderRow != TableHeader.none) {
        if (inHeaderRow == TableHeader.implicit) {
          cellStyle = column.style ?? spec?.style;
          if (cellStyle != null) {
            if (cellStyle == 'asciidoc' || cellStyle == 'literal') {
              _reinitializeArgs = (column, cellContent, spec, cursor);
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
    Cursor? innerDocumentCursor;
    // NOTE when a spec is given, this is a PSV cell, which implies the text
    // needs to be stripped.
    if (spec != null) {
      colspan = spec.colspan;
      rowspan = spec.rowspan;
      if (!spec.isEmpty) {
        // TODO delete style attribute from attributes if set.
        if (inHeaderRow == TableHeader.none) {
          if (spec.style case final style?) cellStyle = style;
        }
        updateAttributes(spec.attributes);
      }
      if (cellStyle == 'asciidoc') {
        asciidoc = true;
        innerDocumentCursor = cursor;
        var text = cellContent!.trimRightAscii();
        if (text.startsWith(lf)) {
          var linesAdvanced = 1;
          while ((text = text.substring(1)).startsWith(lf)) {
            linesAdvanced += 1;
          }
          // NOTE this only works if we remain in the same file.
          cursor!.advance(linesAdvanced);
        } else {
          text = trimLeftAscii(text);
        }
        cellContent = text;
      } else if (cellStyle == 'literal') {
        literal = true;
        var text = cellContent!.trimRightAscii();
        // QUESTION should we use same logic as :asciidoc cell? strip
        // leading space if text doesn't start with newline?
        while (text.startsWith(lf)) {
          text = text.substring(1);
        }
        // Expand tabs as in a literal block (#3412).
        final tabSize = int.tryParse(document!.attr('tabsize') ?? '') ?? 0;
        if (tabSize > 0 && text.contains('\t')) {
          final lines = text.split(lf);
          Parser.adjustIndentation(lines, -1, tabSize);
          text = lines.join(lf);
        }
        cellContent = text;
      } else {
        normalPsv = true;
        // NOTE AsciidoctorJ uses a null cell_text to create an empty cell.
        cellContent = cellContent != null ? cellContent.trimAscii() : '';
      }
    } else {
      colspan = null;
      rowspan = null;
      if (cellStyle == 'asciidoc') {
        asciidoc = true;
        innerDocumentCursor = cursor;
      }
    }
    // NOTE only true for non-header rows.
    if (asciidoc) {
      final parentDoc = document! as Document;
      // FIXME hide doctitle from nested document; temporary workaround to
      // fix nested document seeing doctitle and assuming it has its own
      // document title.
      final parentDoctitle = parentDoc.attributes.remove('doctitle');
      // NOTE we need to process the first line of content as it may not
      // have been processed. The included content cannot expect to match
      // conditional terminators in the remaining lines of table cell
      // content; it must be self-contained logic.
      // Keep trailing empty segments, but an empty string has no lines
      // (`''.split` would yield `['']`).
      final cellSource = cellContent;
      final innerDocumentLines = cellSource == null || cellSource.isEmpty
          ? <String>[]
          : cellSource.split(lf);
      if (innerDocumentLines.isNotEmpty) {
        final unprocessedLine1 = innerDocumentLines[0];
        // QUESTION is it faster to check for `::` before splitting?
        if (unprocessedLine1.contains('::')) {
          final preprocessedLines = PreprocessorReader(parentDoc, [
            unprocessedLine1,
          ], cursor: innerDocumentCursor).readLines();
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
      innerDocument = Document.nested(
        parentDoc,
        innerDocumentLines,
        cursor: innerDocumentCursor,
      );
      if (parentDoctitle != null) {
        parentDoc.attributes['doctitle'] = parentDoctitle;
      }
      // No substitutions: the empty list applies nothing.
      subs = <Sub>[];
    } else if (literal) {
      contentModel = ContentModel.verbatim;
      subs = basicSubs;
    } else {
      if (normalPsv) {
        if (inHeaderRow != TableHeader.none) {
          _cursor = cursor; // Used in the deferred catalog call.
        } else {
          catalogInlineAnchor(cellContent, cursor);
        }
      }
      contentModel = ContentModel.simple;
      subs = normalSubs;
    }
    _text = cellContent;
    style = cellStyle;
  }

  /// Two consecutive line feeds (a blank line).
  static const String doubleLf = '\n\n';

  /// The number of columns this cell spans, if more than one.
  int? colspan;

  /// The number of rows this cell spans, if more than one.
  int? rowspan;

  /// The nested document in an AsciiDoc table cell (only set when the style
  /// is `'asciidoc'`).
  Document? innerDocument;

  Cursor? _cursor;
  (Column?, String?, CellSpec?, Cursor?)? _reinitializeArgs;
  String? _text;

  /// The column this cell belongs to.
  ///
  /// Node parents are [AbstractBlock]s and columns are not blocks, so the
  /// cell's parent is the table and the column is kept here.
  final Column? _column;

  /// An alias for the column this cell belongs to (mirrors
  /// `alias column parent`).
  Column? get column => _column;

  /// Reinitializes this cell for (or out of) the header row.
  ///
  /// Port of `Asciidoctor::Table::Cell#reinitialize`.
  Cell reinitialize({required bool hasHeader}) {
    final args = _reinitializeArgs;
    if (hasHeader) {
      _reinitializeArgs = null;
    } else if (args != null) {
      final (column, text, spec, cursor) = args;
      return Cell(column, text, spec, cursor);
    } else {
      style = attributes['style'];
    }
    if (_cursor != null) catalogInlineAnchor();
    return this;
  }

  /// Catalogs a leading inline anchor in [cellText] (defaulting to this
  /// cell's text), unless there is none.
  ///
  /// Port of `Asciidoctor::Table::Cell#catalog_inline_anchor`.
  void catalogInlineAnchor([String? cellText, Cursor? cursor]) {
    var c = cursor;
    if (c == null) {
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
      document! as Document,
    );
  }

  /// The text of this cell with substitutions applied.
  ///
  /// Used for head-row cells as well as text-only cells in the foot row and
  /// body; not for AsciiDoc-style cells.
  // NOTE `this.` is load-bearing (see list.dart: same import-scope
  // shadowing quirk for substitutor members).
  String get text => this.applySubs(_text ?? '', subs);

  set text(String? value) {
    _text = value;
  }

  /// The text of this cell as written, before substitutions.
  @internal
  String? get sourceText => _text;

  /// The paragraphs of this cell's text with substitutions and the cell
  /// style applied (empty when the text is empty). Not for AsciiDoc-style
  /// cells.
  ///
  /// Port of the paragraph branch of `Asciidoctor::Table::Cell#content`.
  /// The styled paragraphs are parented to this cell's parent (the table),
  /// since inline nodes require a block parent.
  List<String> get paragraphs {
    final cellStyle = style;
    final styled = cellStyle != null && cellStyle != 'header';
    if (_text!.contains(doubleLf)) {
      return splitDropTrailingEmpty(text, _blankLineRx)
          .map(
            (para) => styled
                ? Inline(
                    parent,
                    InlineContext.quoted,
                    text: para,
                    type: cellStyle,
                  ).convert()
                : para,
          )
          .toList();
    }
    final subbedText = text;
    if (subbedText.isEmpty) return <String>[];
    if (styled) {
      return <String>[
        Inline(
          parent,
          InlineContext.quoted,
          text: subbedText,
          type: cellStyle,
        ).convert(),
      ];
    }
    return <String>[subbedText];
  }

  /// The converted content of this cell: the nested document of an
  /// AsciiDoc cell, otherwise the [paragraphs] joined by blank lines.
  @override
  String content() {
    if (style == 'asciidoc') return innerDocument!.convert();
    return paragraphs.join('$lf$lf');
  }

  /// The lines of this cell's text.
  List<String> lines() => splitDropTrailingEmpty(_text!, lf);

  /// The source text of this cell.
  String? source() => _text;

  @override
  String toString() =>
      'Cell(text: ${debugQuote(_text)}, '
      'colspan: ${colspan ?? 1}, '
      'rowspan: ${rowspan ?? 1}, '
      'attributes: $attributes)';
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
  /// Creates a parser context for [table], reading from [reader].
  ///
  /// Port of `Asciidoctor::Table::ParserContext#initialize`.
  new(
    Reader reader,
    Table table, [
    Map<String, String> attributes = const <String, String>{},
  ]) {
    final attrs = attributes;
    _reader = reader..mark();
    _startCursor = reader.cursorAtMark();
    this.table = table;

    late String xsv;
    if (attrs.containsKey('format')) {
      xsv = attrs['format']!;
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
          'illegal table format: $xsv',
          at: reader.cursorAtPrevLine(),
        );
        format = 'psv';
        xsv = table.document!.nested() ? '!sv' : 'psv';
      }
    } else {
      format = 'psv';
      xsv = table.document!.nested() ? '!sv' : 'psv';
    }

    if (attrs.containsKey('separator')) {
      final sep = attrs['separator']!;
      if (sep.isEmpty) {
        final entry = delimiters[xsv]!;
        _delimiter = entry.$1;
        _delimiterRx = entry.$2;
      } else if (sep == r'\t') {
        // NOTE this compares against a literal backslash followed by `t`,
        // not a tab (as Asciidoctor does).
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
    _cellspecs = <CellSpec>[];
    _cellOpen = false;
    _spannedColumns = [<int>{}];
    _position = 0;
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

  /// The shared logger ([LoggerManager.logger]).
  LoggerBase get logger => LoggerManager.logger;

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
  /// Always `null`, as in Asciidoctor (where the reader and the assigned
  /// field have different names); matching uses the private pattern.
  RegExp? get delimiterRe => null;

  late final Reader _reader;

  /// Where the table starts, reported when
  /// the leading separator is missing.
  late final Cursor _startCursor;
  List<CellSpec> _cellspecs = <CellSpec>[];
  bool _cellOpen = false;

  /// The columns covered by cells spanning rows from above, for the current
  /// row and the ones after it.
  List<Set<int>> _spannedColumns = [<int>{}];

  /// The column of the current row the next cell goes in.
  int _position = 0;
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
    buffer = '$buffer${dropLastChar(pre)}$_delimiter';
  }

  /// Whether the buffer has unclosed quotes (used for CSV data).
  ///
  /// Port of `Asciidoctor::Table::ParserContext#buffer_has_unclosed_quotes?`.
  bool bufferHasUnclosedQuotes([String? append, String q = '"']) {
    final record = append != null
        ? (buffer + append).trimAscii()
        : buffer.trimAscii();
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
  CellSpec? takeCellspec() =>
      _cellspecs.isEmpty ? null : _cellspecs.removeAt(0);

  /// Pushes a cell spec onto the stack for the next cell.
  void pushCellspec([CellSpec cellspec = const CellSpec()]) {
    _cellspecs.add(cellspec);
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

  /// Whether the cell being read is an AsciiDoc cell (by its spec or its
  /// column), whose line comments are part of its content: they may sit in
  /// a verbatim block or separate two lists (#2496, #2648).
  bool get readingAsciiDocCell {
    if (format != 'psv' || _cellspecs.isEmpty) return false;
    if (_cellspecs.first.style case final style?) return style == 'asciidoc';
    final columns = table!.columns;
    if (_colcount == -1) return false;
    var position = _position;
    while (_spannedColumns.first.contains(position)) {
      position += 1;
    }
    return position < columns.length && columns[position].style == 'asciidoc';
  }

  /// Whether the current cell has been marked as closed.
  bool get isCellClosed => !_cellOpen;

  /// Closes the open cell, if any, pushing [nextCellspec] for the next
  /// cell, and advances to the next line.
  void closeOpenCell([CellSpec nextCellspec = const CellSpec()]) {
    pushCellspec(nextCellspec);
    if (isCellOpen) closeCell(eol: true);
    _advance();
  }

  /// Closes the current cell, instantiates a [Cell], adds it to the current
  /// row and, when the expected column count is met, closes the row and
  /// begins a new one.
  ///
  /// Port of `Asciidoctor::Table::ParserContext#close_cell`.
  void closeCell({bool eol = false}) {
    late final String cellText;
    late final CellSpec? cellspec;
    late final int repeat;
    if (format == 'psv') {
      cellText = buffer;
      buffer = '';
      final taken = takeCellspec();
      if (taken != null) {
        cellspec = taken;
        repeat = taken.repeat ?? 1;
      } else {
        logger.error(
          'table missing leading separator; recovering automatically',
          at: _startCursor,
        );
        cellspec = const CellSpec();
        repeat = 1;
      }
    } else {
      var text = buffer.trimAscii();
      buffer = '';
      cellspec = null;
      repeat = 1;
      if (format == 'csv' && text.isNotEmpty && text.contains('"')) {
        // This may not be perfect logic, but it hits the 99%.
        if (text.startsWith('"') && text.endsWith('"')) {
          // Unquote.
          if (text.length > 1) {
            // Trim whitespace and collapse escaped quotes.
            text = collapseRuns(
              text.substring(1, text.length - 1).trimAscii(),
              '"',
            );
          } else {
            logger.error(
              'unclosed quote in CSV data; setting cell to empty',
              at: _reader.cursorAtPrevLine(),
            );
            text = '';
          }
        } else {
          // Collapse escaped quotes.
          text = collapseRuns(text, '"');
        }
      }
      cellText = text;
    }

    for (var i = 1; i <= repeat; i++) {
      // TODO make column resolving an operation.
      late final Column? column;
      late final int start;
      if (_colcount == -1) {
        final t = table!;
        start = t.columns.length;
        column = Column(t, start);
        t.columns.add(column);
        final colspan = cellspec?.colspan;
        if (colspan != null) {
          final extraCols = colspan - 1;
          if (extraCols > 0) {
            final offset = t.columns.length;
            for (var j = 0; j < extraCols; j++) {
              t.columns.add(Column(t, offset + j));
            }
          }
        }
      } else {
        // The next column no cell covers: after the cells before it in the
        // row, with their colspans, and around those spanning rows from
        // above (#4500, #989).
        while (_spannedColumns.first.contains(_position)) {
          _position += 1;
        }
        final columns = table!.columns;
        start = _position < columns.length ? _position : columns.length - 1;
        column = columns[start];
      }

      final cursorBeforeMark = _reader.cursorBeforeMark();
      final cell = Cell(column, cellText, cellspec, cursorBeforeMark);
      _reader.mark();
      final rowspan = cell.rowspan;
      if (rowspan != null && rowspan != 1) {
        _activateRowspan(rowspan, start, cell.colspan ?? 1);
      }
      _position = start + (cell.colspan ?? 1);
      _columnVisits += cell.colspan ?? 1;
      _currentRow.add(cell);
      final rowStatus = _endOfRow();
      if (rowStatus > -1 &&
          (_colcount != -1 || _linenum > 0 || (eol && i == repeat))) {
        if (rowStatus > 0) {
          logger.error(
            'dropping cell because it exceeds specified number of columns',
            at: cursorBeforeMark,
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
      'dropping cells from incomplete row detected end of table',
      at: _reader.cursorBeforeMark(),
    );
  }

  /// Closes the row by adding it to the table and resetting the row state.
  void _closeRow([bool drop = false]) {
    if (!drop) table!.rows.body.add(_currentRow);
    // Don't have to account for active rowspans here since this is the
    // first row.
    if (_colcount == -1) _colcount = _columnVisits;
    _columnVisits = 0;
    _position = 0;
    _currentRow = <Cell>[];
    _spannedColumns.removeAt(0);
    if (_spannedColumns.isEmpty) _spannedColumns.add(<int>{});
  }

  /// Covers the [colspan] columns from [start] in the [rowspan] - 1 rows
  /// after the current one.
  void _activateRowspan(int rowspan, int start, int colspan) {
    for (var i = 1; i <= rowspan - 1; i++) {
      while (_spannedColumns.length <= i) {
        _spannedColumns.add(<int>{});
      }
      _spannedColumns[i].addAll([for (var c = 0; c < colspan; c++) start + c]);
    }
  }

  /// Whether the effective column count is met for the current row: -1
  /// when short, 0 when exact, 1 when overrunning.
  int _endOfRow() =>
      _colcount == -1 ? 0 : _effectiveColumnVisits.compareTo(_colcount);

  /// The effective column visits: cells plus active rowspans.
  int get _effectiveColumnVisits =>
      _columnVisits + _spannedColumns.first.length;

  /// Advances to the next line (which may come after the parser begins
  /// processing the next line if the last cell had wrapped content).
  void _advance() {
    _linenum += 1;
  }
}
