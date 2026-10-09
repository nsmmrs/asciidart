/// Line reader with preprocessor directive support.
///
/// Port of `lib/asciidoctor/reader.rb` (`Reader` and `PreprocessorReader`).
///
/// The reader is a line stack with a 1-based line number. Lines are stored in
/// reverse so the next line is always the last element. [Reader] is a plain
/// line source; [PreprocessorReader] additionally expands conditional
/// (`ifdef`/`ifndef`/`ifeval`/`endif`) and `include` preprocessor directives
/// as lines are read.
library;

import 'dart:convert' show Encoding, ascii, latin1, utf8;
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/constants.dart';
import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/errors.dart';
import 'package:ptome/src/extensions.dart';
import 'package:ptome/src/helpers.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/parser.dart';
import 'package:ptome/src/ruby_semantics.dart';
import 'package:ptome/src/rx.dart';
import 'package:ptome/src/substitutors.dart' as substitutors;
import 'package:ptome/src/text_case.dart';
import 'package:ptome/src/units/reading.dart';

export 'package:ptome/src/cursor.dart' show Cursor;

/// How source lines are normalized during preparation.
enum _LineNormalization {
  /// No normalization; string input is chomped and split only.
  none,

  /// Coerce to Unicode and strip trailing whitespace.
  full,

  /// Strip a single trailing line terminator only.
  chomp,
}

/// Methods for retrieving lines from AsciiDoc source.
///
/// Port of `Asciidoctor::Reader`. Lines are held on a stack in reverse; the
/// next line is the last element. A `null` entry peeks as end-of-data but still
/// occupies (and is consumed from) the stack when read directly.
class Reader {
  /// Initializes the reader with source [lines].
  ///
  /// [cursor] gives the file, directory, path and line number of the first
  /// line (default: standard input at line 1). When [normalize] is set,
  /// lines are stripped of trailing whitespace.
  ///
  /// [continuationPlaceholders] are the indexes in [lines] of empty lines
  /// that stand for a list continuation (see
  /// [nextLineIsContinuationPlaceholder]).
  ///
  /// [origins] are where [lines] were read (see [recordOrigins]), aligned
  /// with them: a reader of lines already read keeps their origins.
  new(
    List<String> lines, {
    Cursor? cursor,
    bool normalize = false,
    Set<int> continuationPlaceholders = const {},
    List<LineOrigin>? origins,
  }) {
    _initCursor(cursor);
    if (origins != null) {
      _presetOrigins = origins;
      _presetBase = _lineno;
      recordOrigins = true;
    }
    _sourceLines = _prepareLines(
      lines: lines,
      normalize: normalize ? _LineNormalization.full : _LineNormalization.none,
    );
    _lines = _sourceLines.reversed.toList();
    _placeholderLinenos = {
      for (final index in continuationPlaceholders) _lineno + index,
    };
  }

  /// Initializes the reader with the AsciiDoc [source] text (an empty
  /// reader when `null`). See [Reader.new].
  new fromString(String? source, {Cursor? cursor, bool normalize = false}) {
    _initCursor(cursor);
    _sourceLines = _prepareLines(
      source: source,
      normalize: normalize ? _LineNormalization.full : _LineNormalization.none,
    );
    _lines = _sourceLines.reversed.toList();
  }

  void _initCursor(Cursor? cursor) {
    if (cursor == null) {
      _file = null;
      _dir = '.';
      _path = '<stdin>';
      _lineno = 1;
      return;
    }
    final cursorFile = cursor.file;
    if (cursorFile != null) {
      _file = cursorFile;
      _dir = cursor.dir ?? _dirname(cursorFile);
      _path = cursor.path ?? Helpers.basename(cursorFile);
    } else {
      _file = null;
      _dir = cursor.dir ?? '.';
      _path = cursor.path ?? '<stdin>';
    }
    _lineno = cursor.lineno;
  }

  String? _file;
  late String _dir;

  /// Whether the current file is a remote (URI) include, so relative
  /// include targets resolve against [dir] as a URI.
  bool _remote = false;
  late String _path;
  late int _lineno;
  late List<String> _lines;
  late List<String> _sourceLines;
  Cursor? _mark;
  int _lookAhead = 0;

  /// The line numbers of the continuation placeholders (a line keeps its
  /// number when it is read and restored).
  Set<int> _placeholderLinenos = const {};

  /// Whether the next line is an empty line standing for a list
  /// continuation: the lines of a list item keep the continuations that
  /// attach blocks to a nested item this way (Asciidoctor marks those lines
  /// by identity).
  @internal
  bool get nextLineIsContinuationPlaceholder =>
      _placeholderLinenos.contains(_lineno);

  /// Whether lines are processed using [processLine] on first visit.
  bool processLines = true;
  bool _unescapeNextLine = false;

  /// Whether the end of the reader was reached with a delimited block open.
  bool unterminated = false;
  _ReaderState? _savedState;

  /// Whether [readLinesUntil] reports where each line it returns was read
  /// ([lastOrigins]); set for documents in units (ADR-0020), whose
  /// positions point into the source as written.
  bool recordOrigins = false;

  /// Where the lines the last [readLinesUntil] returned were read, aligned
  /// with them (empty unless [recordOrigins]).
  List<LineOrigin> lastOrigins = const [];

  /// The origins of the lines this reader was made of, by line number from
  /// [_presetBase], when they were read elsewhere first.
  List<LineOrigin>? _presetOrigins;
  int _presetBase = 1;

  /// Where the line [shift] last returned was read (when [recordOrigins]).
  late LineOrigin _shiftOrigin;

  /// The origins of the lines shifted most recently (newest last), so a
  /// line restored by [unshift] keeps where it was read even when the
  /// reader has left its include since (when [recordOrigins]).
  final List<LineOrigin> _shiftedOrigins = [];

  /// The origins of restored lines, the next to read last.
  final List<LineOrigin> _restoredOrigins = [];

  /// Where the line at [lineno] of this reader was read.
  LineOrigin _originAt(int lineno) {
    final preset = _presetOrigins;
    if (preset != null) {
      final index = lineno - _presetBase;
      if (index >= 0 && index < preset.length) return preset[index];
    }
    return (file: _file, path: _path, line: lineno, column: 0);
  }

  /// Takes [origins] as where this reader's lines were read (lines read
  /// elsewhere first, aligned with them), and records origins from now on.
  @internal
  void adoptOrigins(List<LineOrigin> origins) {
    _presetOrigins = origins;
    _presetBase = _lineno;
    recordOrigins = true;
  }

  /// Where the next line to read was read (when [recordOrigins]).
  @internal
  LineOrigin get nextLineOrigin =>
      _restoredOrigins.isNotEmpty ? _restoredOrigins.last : _originAt(_lineno);

  /// The file under the cursor, if known (a path or a URI).
  String? get file => _file;

  /// The directory of [file] (a path or a URI).
  String get dir => _dir;

  /// The document-relative path of [file].
  String get path => _path;

  /// The 1-based offset of the current line.
  int get lineno => _lineno;

  /// The live document source lines (normal order).
  List<String> get sourceLines => _sourceLines;

  /// Whether there are any lines left to read.
  bool hasMoreLines() {
    if (_lines.isEmpty) {
      _lookAhead = 0;
      return false;
    }
    return true;
  }

  /// Whether this reader is empty (contains no lines).
  bool get isEmpty {
    if (_lines.isEmpty) {
      _lookAhead = 0;
      return true;
    }
    return false;
  }

  /// Whether the next line is empty (or there are no more lines). Does not
  /// consume the line.
  bool isNextLineEmpty() => peekLine().isNullOrEmpty;

  /// Peeks at the next line of source data. Processes the line if not
  /// already visited, but does not consume it.
  ///
  /// When [direct] is set, processing is bypassed and the top stack element
  /// is returned immediately. Returns `null` when there is no more data.
  String? peekLine({bool direct = false}) {
    while (true) {
      final nextLine = _lines.isEmpty ? null : _lines.last;
      if (direct || _lookAhead > 0) {
        if (_unescapeNextLine) return nextLine?.substring(1);
        return nextLine;
      }
      if (nextLine != null) {
        final line = processLine(nextLine);
        if (line != null) return line;
      } else {
        _lookAhead = 0;
        return null;
      }
    }
  }

  /// Peeks at the next [num] lines (all lines when `null`) without consuming
  /// them. When [direct] is set, processing is disabled while reading.
  List<String> peekLines(int? num, {bool direct = false}) {
    final oldLookAhead = _lookAhead;
    final result = <String>[];
    for (var i = 0; i < (num ?? maxInt); i++) {
      final line = direct ? shift() : readLine();
      if (line != null) {
        result.add(line);
      } else {
        if (direct) _lineno -= 1;
        break;
      }
    }

    if (result.isNotEmpty) {
      unshiftAll(result);
      if (direct) _lookAhead = oldLookAhead;
    }

    return result;
  }

  /// Gets the next line of source data, consuming the line returned.
  /// Returns `null` when there is no more data.
  String? readLine() {
    // hasMoreLines triggers preprocessing in subclasses.
    if (_lookAhead > 0 || hasMoreLines()) return shift();
    return null;
  }

  /// Gets the remaining lines of source data, processing each in turn.
  List<String> readLines() {
    final lines = <String>[];
    // hasMoreLines triggers preprocessing in subclasses.
    while (hasMoreLines()) {
      final line = shift();
      if (line == null) break;
      lines.add(line);
    }
    return lines;
  }

  /// Gets the remaining lines of source data joined as a string.
  String read() => readLines().join(lf);

  /// Advances past the next line, returning whether a line was consumed.
  bool advance() => shift() != null;

  /// Pushes [lineToRestore] as the next line to read. The line is marked as
  /// processed immediately.
  void unshiftLine(String lineToRestore) {
    unshift(lineToRestore);
  }

  /// Pushes [linesToRestore] as the next lines to read. The lines are marked
  /// as processed immediately.
  void unshiftLines(List<String> linesToRestore) {
    unshiftAll(linesToRestore);
  }

  /// Replaces the next line with [replacement]. Returns `true`.
  bool replaceNextLine(String replacement) {
    shift();
    unshift(replacement);
    return true;
  }

  /// Skips blank lines at the cursor.
  ///
  /// Returns the number of lines skipped, or `null` when all lines have been
  /// consumed (even when lines were skipped).
  int? skipBlankLines() {
    if (isEmpty) return null;

    var numSkipped = 0;
    // optimized code for shortest execution path
    String? nextLine;
    while ((nextLine = peekLine()) != null) {
      if (nextLine!.isNotEmpty) return numSkipped;
      shift();
      numSkipped += 1;
    }
    return null;
  }

  /// Skips consecutive comment lines and block comments.
  void skipCommentLines() {
    if (isEmpty) return;

    String? nextLine;
    while ((nextLine = peekLine()) != null && nextLine!.isNotEmpty) {
      final line = nextLine;
      if (!line.startsWith('//')) break;
      if (line.startsWith('///')) {
        final length = line.length;
        if (!(length > 3 && line == '/' * length)) break;
        readLinesUntil(
          terminator: line,
          skipFirstLine: true,
          readLastLine: true,
          skipProcessing: true,
          context: 'comment',
        );
      } else {
        shift();
      }
    }
  }

  /// Skips consecutive comment lines and returns them.
  ///
  /// This method assumes the reader only contains simple lines (no blocks).
  List<String> skipLineComments() {
    if (isEmpty) return [];

    final commentLines = <String>[];
    // optimized code for shortest execution path
    String? nextLine;
    while ((nextLine = peekLine()) != null && nextLine!.isNotEmpty) {
      final line = nextLine;
      if (!line.startsWith('//')) break;
      commentLines.add(shift()!);
    }

    return commentLines;
  }

  /// Advances to the end of the reader, consuming all remaining lines.
  void terminate() {
    _lineno += _lines.length;
    _lines.clear();
    _lookAhead = 0;
  }

  /// Returns the lines from the stack until (1) they run out, (2) a blank
  /// line is found with [breakOnBlankLines], or (3) [test] returns `true`
  /// for a line.
  ///
  /// * [terminator] stops at the line whose contents equal it.
  /// * [breakOnListContinuation] stops at a list continuation line (which is
  ///   then preserved).
  /// * [skipFirstLine] advances beyond the first line before scanning.
  /// * [preserveLastLine] pushes the stopping line back onto the stack.
  /// * [readLastLine] includes the stopping line in the result.
  /// * [skipLineComments] drops line comments from the result.
  /// * [skipProcessing] disables line (pre)processing for the scan.
  /// * [context] names the block in the unterminated warning and defaults to
  ///   [terminator]; [warnIfUnterminated] set to `false` suppresses the
  ///   warning.
  /// * [cursor] selects the start cursor for the warning; [cursorAtMark]
  ///   uses the cursor at the mark instead.
  List<String> readLinesUntil({
    String? terminator,
    bool breakOnBlankLines = false,
    bool breakOnListContinuation = false,
    bool skipFirstLine = false,
    bool preserveLastLine = false,
    bool readLastLine = false,
    bool skipLineComments = false,
    bool skipProcessing = false,
    String? context,
    bool warnIfUnterminated = true,
    Cursor? cursor,
    bool cursorAtMark = false,
    bool Function(String line)? test,
  }) {
    var breakOnListCont = breakOnListContinuation;
    var breakOnBlank = breakOnBlankLines;
    final result = <String>[];
    final origins = recordOrigins ? <LineOrigin>[] : null;
    var restoreProcessLines = false;
    if (processLines && skipProcessing) {
      processLines = false;
      restoreProcessLines = true;
    }
    Cursor? startCursor;
    var preserveLast = preserveLastLine;
    if (terminator != null) {
      startCursor = cursorAtMark ? null : cursor ?? this.cursor();
      breakOnBlank = false;
      breakOnListCont = false;
    }
    final skipComments = skipLineComments;
    var lineRead = false;
    var lineRestored = false;
    String? line;
    if (skipFirstLine) shift();
    while ((line = readLine()) != null) {
      final current = line!;
      final stop = terminator != null
          ? current == terminator
          : ((breakOnBlank && current.isEmpty) ||
                (breakOnListCont &&
                    lineRead &&
                    current == listContinuation &&
                    (preserveLast = true)) ||
                (test != null && test(current)));
      if (stop) {
        if (readLastLine) {
          result.add(current);
          origins?.add(_shiftOrigin);
        }
        if (preserveLast) {
          unshift(current);
          lineRestored = true;
        }
        break;
      }
      if (!(skipComments &&
          current.startsWith('//') &&
          !current.startsWith('///'))) {
        result.add(current);
        origins?.add(_shiftOrigin);
        lineRead = true;
      }
    }
    lastOrigins = origins ?? const [];
    if (restoreProcessLines) {
      processLines = true;
      if (lineRestored && terminator == null) _lookAhead -= 1;
    }
    if (terminator != null && terminator != line && warnIfUnterminated) {
      LoggerManager.logger.warn(
        'unterminated ${context ?? terminator} block',
        at: startCursor ?? this.cursorAtMark(),
      );
      unterminated = true;
    }
    return result;
  }

  /// Shifts the line off the stack and increments the line number.
  ///
  /// Internal: use directly only when [peekLine] already determined the line
  /// should be consumed; otherwise use [readLine]. The line number is
  /// incremented even when the stack is empty.
  @internal
  String? shift() {
    if (recordOrigins) {
      _shiftOrigin = _restoredOrigins.isNotEmpty
          ? _restoredOrigins.removeLast()
          : _originAt(_lineno);
      _shiftedOrigins.add(_shiftOrigin);
      if (_shiftedOrigins.length > 64) _shiftedOrigins.removeAt(0);
    }
    _lineno += 1;
    if (_lookAhead != 0) _lookAhead -= 1;
    return _lines.isEmpty ? null : _lines.removeLast();
  }

  /// Restores [line] to the stack and decrements the line number.
  ///
  /// Internal: see [shift].
  @internal
  void unshift(String line) {
    if (recordOrigins) _restoreOrigins(1);
    _lineno -= 1;
    _lookAhead += 1;
    _lines.add(line);
  }

  /// Restores [linesToRestore] to the stack and decrements the line number.
  ///
  /// Internal: see [shift].
  @internal
  void unshiftAll(List<String> linesToRestore) {
    if (recordOrigins) _restoreOrigins(linesToRestore.length);
    _lineno -= linesToRestore.length;
    _lookAhead += linesToRestore.length;
    _lines.addAll(linesToRestore.reversed);
  }

  /// Moves the origins of the [count] lines shifted last to the restored
  /// ones (a line restored that was never shifted keeps none).
  void _restoreOrigins(int count) {
    for (var i = 0; i < count && _shiftedOrigins.isNotEmpty; i++) {
      _restoredOrigins.add(_shiftedOrigins.removeLast());
    }
  }

  /// The cursor at the current line.
  Cursor cursor() => Cursor(_file, _dir, _path, _lineno);

  /// The cursor at [lineno] in the current file.
  Cursor cursorAtLine(int lineno) => Cursor(_file, _dir, _path, lineno);

  /// The cursor at the mark, or the current cursor when unmarked.
  Cursor cursorAtMark() => _mark?.dup() ?? cursor();

  /// The cursor on the line before the mark (or the current line).
  Cursor cursorBeforeMark() {
    final mark = _mark;
    if (mark != null) {
      return Cursor(mark.file, mark.dir, mark.path, mark.lineno - 1);
    }
    return Cursor(_file, _dir, _path, _lineno - 1);
  }

  /// The cursor at the previous line.
  Cursor cursorAtPrevLine() => Cursor(_file, _dir, _path, _lineno - 1);

  /// Marks the current cursor position. Always returns `true` so the call
  /// can be chained in boolean expressions.
  bool mark() {
    _mark = cursor();
    return true;
  }

  /// `path: line N` summary of the last line read.
  String get lineInfo => '$path: line $lineno';

  /// A copy of the remaining lines managed by this reader.
  List<String> get lines => _lines.reversed.toList();

  /// A copy of the remaining lines managed by this reader joined as a string.
  String get string => _lines.reversed.join(lf);

  /// The source lines for this reader joined as a string.
  String get source => _sourceLines.join(lf);

  /// Saves the state of the reader at the cursor.
  @internal
  void save() {
    _savedState = _captureState();
  }

  /// Restores the state saved by [save], discarding the saved state.
  /// Does nothing when no state was saved.
  @internal
  void restoreSave() {
    final saved = _savedState;
    if (saved == null) return;
    _restoreState(saved);
    _savedState = null;
    // The lines read since are read again, from their own positions.
    _shiftedOrigins.clear();
    _restoredOrigins.clear();
  }

  /// Discards state saved by [save].
  @internal
  void discardSave() {
    _savedState = null;
  }

  @override
  String toString() =>
      '#<Reader@${identityHashCode(this)} {path: '
      '${_inspect(_path)}, line: $_lineno}>';

  /// Processes a previously unvisited line.
  ///
  /// Internal (public so tests can call it): marks the line as
  /// processed and returns it unmodified. Returns `null` to drop the line
  /// and advance to the next one.
  @internal
  String? processLine(String line) {
    if (processLines) _lookAhead += 1;
    return line;
  }

  /// Captures this reader's saveable state.
  _ReaderState _captureState() => _ReaderState(
    lines: List<String>.of(_lines),
    file: _file,
    dir: _dir,
    remote: _remote,
    path: _path,
    lineno: _lineno,
    mark: _mark?.dup(),
    lookAhead: _lookAhead,
    processLines: processLines,
    unescapeNextLine: _unescapeNextLine,
    unterminated: unterminated,
  );

  /// Restores state captured by [_captureState].
  void _restoreState(_ReaderState saved) {
    _lines = saved.lines;
    _file = saved.file;
    _dir = saved.dir;
    _remote = saved.remote;
    _path = saved.path;
    _lineno = saved.lineno;
    _mark = saved.mark;
    _lookAhead = saved.lookAhead;
    processLines = saved.processLines;
    _unescapeNextLine = saved.unescapeNextLine;
    unterminated = saved.unterminated;
  }

  /// Prepares the source data for parsing.
  ///
  /// Converts the [source] text or the source [lines] into a list of lines
  /// ready for parsing. [normalize] controls whitespace handling.
  List<String> _prepareLines({
    String? source,
    List<String>? lines,
    _LineNormalization normalize = _LineNormalization.none,
  }) {
    switch (normalize) {
      case _LineNormalization.full:
        if (lines != null) return Helpers.prepareSourceArray(lines);
        return Helpers.prepareSourceString(source);
      case _LineNormalization.chomp:
        if (lines != null) {
          return Helpers.prepareSourceArray(lines, trimEnd: false);
        }
        return Helpers.prepareSourceString(source, trimEnd: false);
      case _LineNormalization.none:
        if (lines != null) return List<String>.of(lines);
        if (source != null) return source.withoutTrailingNewline().split(lf);
        return <String>[];
    }
  }
}

/// A saved [Reader] state.
final class _ReaderState {
  const new({
    required this.lines,
    required this.file,
    required this.dir,
    required this.remote,
    required this.path,
    required this.lineno,
    required this.mark,
    required this.lookAhead,
    required this.processLines,
    required this.unescapeNextLine,
    required this.unterminated,
  });

  final List<String> lines;
  final String? file;
  final String dir;
  final bool remote;
  final String path;
  final int lineno;
  final Cursor? mark;
  final int lookAhead;
  final bool processLines;
  final bool unescapeNextLine;
  final bool unterminated;
}

/// Methods for retrieving lines from AsciiDoc source files, evaluating
/// preprocessor directives as each line is read.
///
/// Port of `Asciidoctor::PreprocessorReader`.
class PreprocessorReader extends Reader {
  /// Initializes the preprocessor reader for [document] with source
  /// [lines].
  ///
  /// See [Reader.new] for [cursor] and [normalize]. Front matter is skipped
  /// when the document sets the `skip-front-matter` attribute.
  new(
    Document document,
    List<String> lines, {
    super.cursor,
    bool normalize = false,
  }) : _document = document,
       _sourcemap = document.sourcemap,
       _includes = document.catalog.includes,
       super(const <String>[]) {
    _init(lines: lines, normalize: normalize);
  }

  /// A preprocessor reader for the content of a delimited block that
  /// [outer] read without preprocessing it ([lines], which start at
  /// [cursor]): its directives run as the block's content is parsed, after
  /// the attribute entries before them (asciidoctor#3877). Includes in it
  /// count toward [outer]'s include depth.
  new nested(PreprocessorReader outer, List<String> lines, {super.cursor})
    : _document = outer._document,
      _sourcemap = outer._sourcemap,
      _includes = outer._includes,
      super(const <String>[]) {
    final depth = outer._includeStack.length;
    _maxdepth = switch (outer._maxdepth) {
      final max? => _MaxDepth(
        math.max(0, max.abs - depth),
        math.max(0, max.curr - depth),
        max.rel,
      ),
      null => null,
    };
    _sourceLines = lines;
    _lines = lines.reversed.toList();
  }

  /// Initializes the preprocessor reader for [document] with the AsciiDoc
  /// [source] text. See [PreprocessorReader.new].
  new fromString(
    Document document,
    String? source, {
    super.cursor,
    bool normalize = false,
  }) : _document = document,
       _sourcemap = document.sourcemap,
       _includes = document.catalog.includes,
       super(const <String>[]) {
    _init(source: source, normalize: normalize);
  }

  void _init({required bool normalize, String? source, List<String>? lines}) {
    final maxDepthValue = _document.attributes['max-include-depth'];
    final defaultDepth = maxDepthValue == null ? 64 : _toInt(maxDepthValue);
    // Track absolute max depth, current max depth for comparing to include
    // stack size, and relative max depth for reporting.
    // If _maxdepth is not set, built-in include functionality is disabled.
    _maxdepth = defaultDepth > 0
        ? _MaxDepth(defaultDepth, defaultDepth, defaultDepth)
        : null;
    _sourceLines = _prepareLines(
      source: source,
      lines: lines,
      normalize: normalize ? _LineNormalization.full : _LineNormalization.none,
    );
    _lines = _sourceLines.reversed.toList();
  }

  final Document _document;
  final bool _sourcemap;
  final Map<String, bool> _includes;
  _MaxDepth? _maxdepth;
  List<_IncludeFrame> _includeStack = <_IncludeFrame>[];
  bool _skipping = false;
  List<_ConditionalFrame> _conditionalStack = <_ConditionalFrame>[];
  List<IncludeProcessor>? _includeProcessorExtensions;
  bool _includeProcessorsChecked = false;
  _PreprocessorState? _savedPreprocessorState;

  @override
  bool hasMoreLines() => peekLine() != null;

  @override
  bool get isEmpty => peekLine() == null;

  /// Pops the include stack when the last line of an include has been
  /// reached, reporting unterminated preprocessor conditionals when the
  /// outermost source is exhausted. See [Reader.peekLine].
  @override
  String? peekLine({bool direct = false}) {
    final line = super.peekLine(direct: direct);
    if (line != null) return line;
    if (_includeStack.isEmpty) {
      Cursor? endCursor;
      _conditionalStack.removeWhere((conditional) {
        LoggerManager.logger.error(
          'detected unterminated preprocessor conditional directive: '
          '${conditional.name}::${conditional.target ?? ''}'
          '[${conditional.expr ?? ''}]',
          at: conditional.sourceLocation ?? (endCursor ??= cursorAtPrevLine()),
        );
        return true;
      });
      return null;
    } else {
      _popInclude();
      return peekLine(direct: direct);
    }
  }

  /// Pushes the [source] text onto the front of the reader and switches
  /// the context to the given [file], document-relative [path] and line
  /// info.
  ///
  /// Typically used in an include processor to add source read from the
  /// target. [lineno] defaults to 1. [attributes] are the include
  /// directive's attributes (`depth`, `indent`, `leveloffset`,
  /// `partial-option`).
  void pushInclude(
    String source, [
    String? file,
    String? path,
    int lineno = 1,
    Map<String, String> attributes = const <String, String>{},
  ]) => _pushInclude(
    source: source,
    file: file,
    path: path,
    lineno: lineno,
    attrs: attributes,
  );

  /// Pushes source [lines] onto the front of the reader. See
  /// [pushInclude].
  void pushIncludeLines(
    List<String> lines, [
    String? file,
    String? path,
    int lineno = 1,
    Map<String, String> attributes = const <String, String>{},
  ]) => _pushInclude(
    lines: lines,
    file: file,
    path: path,
    lineno: lineno,
    attrs: attributes,
  );

  void _pushInclude({
    String? source,
    List<String>? lines,
    String? file,
    String? path,
    int lineno = 1,
    Map<String, String> attrs = const <String, String>{},
    bool remote = false,
  }) {
    _includeStack.add(
      _IncludeFrame(
        lines: _lines,
        file: _file,
        dir: _dir,
        remote: _remote,
        path: _path,
        lineno: _lineno,
        maxdepth: _maxdepth,
        processLines: processLines,
      ),
    );
    if (file != null) {
      if (remote) {
        // The directory of a URI is the URI with the last path segment
        // removed.
        final uri = Uri.parse(file);
        final dirPath = _dirname(uri.path);
        _dir = uri.replace(path: dirPath == '/' ? '' : dirPath).toString();
      } else {
        _dir = _dirname(file);
      }
      _remote = remote;
      _path = path ?? Helpers.basename(file);
      // only process lines in AsciiDoc files
      if (processLines = asciidocExtensions.keys.any(file.endsWith)) {
        final dot = _path.lastIndexOf('.');
        final key = dot == -1 ? _path : _path.substring(0, dot);
        // NOTE registering the include as partial tracks it while not
        // making it visible to interdocument xrefs
        if (_includes[key] != true) {
          _includes[key] = !attrs.containsKey('partial-option');
        }
      }
    } else {
      _dir = '.';
      _remote = false;
      // we don't know what file type we have, so assume AsciiDoc
      processLines = true;
      if (path != null) {
        _path = path;
        // NOTE registering the include as partial tracks it while not
        // making it visible to interdocument xrefs
        final key = Helpers.rootname(path);
        if (_includes[key] != true) {
          _includes[key] = !attrs.containsKey('partial-option');
        }
      } else {
        _path = '<stdin>';
      }
    }

    _file = file;
    _lineno = lineno;

    final maxdepth = _maxdepth;
    final depthAttr = attrs['depth'];
    if (maxdepth != null && depthAttr != null) {
      final relMaxdepth = _toInt(depthAttr);
      if (relMaxdepth > 0) {
        var currMaxdepth = _includeStack.length + relMaxdepth;
        var rel = relMaxdepth;
        final absMaxdepth = maxdepth.abs;
        if (currMaxdepth > absMaxdepth) {
          // if relative depth exceeds absolute max depth, effectively ignore
          // relative depth request
          currMaxdepth = rel = absMaxdepth;
        }
        _maxdepth = _MaxDepth(absMaxdepth, currMaxdepth, rel);
      } else {
        _maxdepth = _MaxDepth(maxdepth.abs, _includeStack.length, 0);
      }
    }

    // effectively fill the buffer
    final prepared = _prepareIncludeLines(
      source: source,
      lines: lines,
      normalize: processLines
          ? _LineNormalization.full
          : _LineNormalization.chomp,
      include: true,
      skipFrontMatter: attrs.containsKey('skip-front-matter-option'),
      indent: attrs['indent'],
    );
    if (prepared.isEmpty) {
      _popInclude();
    } else {
      // FIXME we eventually want to handle leveloffset without affecting
      // the lines
      final leveloffsetAttr = attrs['leveloffset'];
      if (leveloffsetAttr != null) {
        final leveloffset = _document.attr('leveloffset');
        _lines = [
          if (leveloffset != null)
            ':leveloffset: $leveloffset'
          else
            ':leveloffset!:',
          '',
          ...prepared.reversed,
          '',
          ':leveloffset: $leveloffsetAttr',
        ];
        // compensate for these extra lines at the top
        _lineno -= 2;
      } else {
        _lines = prepared.reversed.toList();
      }
      _lookAhead = 0;
    }
  }

  /// The current include depth (size of the include stack).
  int get includeDepth => _includeStack.length;

  /// Whether the current line is under a preprocessor conditional
  /// (`ifdef`, `ifndef`, `ifeval`).
  bool get inConditional => _conditionalStack.isNotEmpty;

  /// The relative max include depth when pushing an include would exceed
  /// it, else `null` (also when includes are disabled; see
  /// [includesEnabled]).
  int? get exceedsMaxDepth {
    final maxdepth = _maxdepth;
    if (maxdepth == null) return null;
    if (_includeStack.length >= maxdepth.curr) return maxdepth.rel;
    return null;
  }

  /// Whether the built-in include directive is enabled (the
  /// `max-include-depth` attribute is positive).
  bool get includesEnabled => _maxdepth != null;

  /// Shifts the line off the stack, unescaping it first when the previous
  /// peek marked it escaped. See [Reader.shift].
  @internal
  @override
  String? shift() {
    if (_unescapeNextLine) {
      _unescapeNextLine = false;
      return super.shift()?.substring(1);
    }
    return super.shift();
  }

  /// Whether include processor extensions are registered.
  bool get hasIncludeProcessors {
    if (!_includeProcessorsChecked) {
      _includeProcessorsChecked = true;
      final exts = _document.extensions;
      if (exts != null && exts.hasIncludeProcessors) {
        _includeProcessorExtensions = [
          for (final ext in exts.includeProcessors) ext.instance,
        ];
      }
    }
    return _includeProcessorExtensions != null;
  }

  /// Creates a cursor for [file] at [lineno]; a [remote] file is a URI.
  Cursor createIncludeCursor(
    String file,
    String path,
    int lineno, {
    bool remote = false,
  }) {
    if (!remote) return Cursor(file, _dirname(file), path, lineno);
    var dir = _dirname(Uri.parse(file).path);
    if (dir == '') dir = '/';
    return Cursor(file, dir, path, lineno);
  }

  @override
  String toString() =>
      'PreprocessorReader(path: ${_inspect(_path)}, line: $_lineno, '
      'include depth: ${_includeStack.length})';

  @internal
  @override
  void save() {
    super.save();
    _savedPreprocessorState = _PreprocessorState(
      includeStack: List<_IncludeFrame>.of(_includeStack),
      maxdepth: _maxdepth,
      skipping: _skipping,
      conditionalStack: List<_ConditionalFrame>.of(_conditionalStack),
      includeProcessors: _includeProcessorExtensions,
      includeProcessorsChecked: _includeProcessorsChecked,
    );
  }

  @internal
  @override
  void restoreSave() {
    final saved = _savedPreprocessorState;
    super.restoreSave();
    if (saved == null) return;
    _includeStack = saved.includeStack;
    _maxdepth = saved.maxdepth;
    _skipping = saved.skipping;
    _conditionalStack = saved.conditionalStack;
    _includeProcessorExtensions = saved.includeProcessors;
    _includeProcessorsChecked = saved.includeProcessorsChecked;
    _savedPreprocessorState = null;
  }

  @internal
  @override
  void discardSave() {
    super.discardSave();
    _savedPreprocessorState = null;
  }

  /// Prepares the source, skipping front matter when the document sets the
  /// `skip-front-matter` attribute and dropping trailing blank lines.
  @override
  List<String> _prepareLines({
    String? source,
    List<String>? lines,
    _LineNormalization normalize = _LineNormalization.none,
  }) => _prepareIncludeLines(
    source: source,
    lines: lines,
    normalize: normalize,
    include: false,
    skipFrontMatter: _document.attributes.containsKey('skip-front-matter'),
  );

  /// Prepares the [source] text or [lines] of the document, or of an
  /// [include]: front matter is skipped when [skipFrontMatter] says so
  /// (and kept in the `front-matter` attribute for the document itself);
  /// the document drops trailing blank lines, an include adjusts its
  /// indentation when [indent] is set.
  List<String> _prepareIncludeLines({
    required bool include,
    String? source,
    List<String>? lines,
    _LineNormalization normalize = _LineNormalization.none,
    bool skipFrontMatter = false,
    String? indent,
  }) {
    final result = super._prepareLines(
      source: source,
      lines: lines,
      normalize: normalize,
    );

    if (skipFrontMatter) {
      final frontMatter = _skipFrontMatter(result);
      if (frontMatter != null && !include) {
        _document.attributes['front-matter'] = frontMatter.join(lf);
      }
    }

    if (include) {
      if (indent != null) {
        Parser.adjustIndentation(
          result,
          _toInt(indent),
          _toInt(_document.attr('tabsize')),
        );
      }
    } else {
      while (result.isNotEmpty && result.last.isEmpty) {
        result.removeLast();
      }
    }

    return result;
  }

  /// Processes a previously unvisited line, expanding preprocessor
  /// directives. See [Reader.processLine].
  @internal
  @override
  String? processLine(String line) {
    if (!processLines) return line;

    if (line.isEmpty) {
      if (_skipping) {
        shift();
        return null;
      }
      _lookAhead += 1;
      return line;
    }

    // NOTE highly optimized
    if (line.endsWith(']') && !line.startsWith('[') && line.contains('::')) {
      if (line.contains('if')) {
        final condMatch = conditionalDirectiveRx.firstMatch(line);
        if (condMatch != null) {
          // if escaped, mark as processed and return line unescaped
          if (condMatch.group(1) == r'\') {
            _unescapeNextLine = true;
            _lookAhead += 1;
            return line.substring(1);
          } else if (_preprocessConditionalDirective(
            condMatch.group(2)!,
            condMatch.group(3)!,
            condMatch.group(4),
            condMatch.group(5),
          )) {
            // move the pointer past the conditional line
            shift();
            // treat next line as uncharted territory
            return null;
          } else {
            // the line was not a valid conditional line
            // mark it as visited and return it
            _lookAhead += 1;
            return line;
          }
        }
      }
      if (_skipping) {
        shift();
        return null;
      }
      if (line.startsWith('inc') || line.startsWith(r'\inc')) {
        final incMatch = includeDirectiveRx.firstMatch(line);
        if (incMatch != null) {
          // if escaped, mark as processed and return line unescaped
          if (incMatch.group(1) == r'\') {
            _unescapeNextLine = true;
            _lookAhead += 1;
            return line.substring(1);
            // QUESTION should we strip whitespace from raw attributes in
            // Substitutors#parse_attributes? (check perf)
          } else if (_preprocessIncludeDirective(
            incMatch.group(2)!,
            incMatch.group(3),
          )) {
            // peek again since the content has changed
            return null;
          } else {
            // the line was not a valid include line and is unchanged
            // mark it as visited and return it
            _lookAhead += 1;
            return line;
          }
        }
      }
      // NOTE optimization to inline super
      _lookAhead += 1;
      return line;
    } else if (_skipping) {
      shift();
      return null;
    } else {
      // NOTE optimization to inline super
      _lookAhead += 1;
      return line;
    }
  }

  /// Preprocesses the conditional directive (`ifdef`, `ifndef`, `ifeval`,
  /// `endif`) under the cursor.
  ///
  /// Returns whether the cursor should be advanced.
  bool _preprocessConditionalDirective(
    String name,
    String target,
    String? delimiter,
    String? text,
  ) {
    var directiveTarget = target;
    // attributes are case insensitive
    final noTarget = directiveTarget.isEmpty;
    if (!noTarget) directiveTarget = downcase(directiveTarget);

    if (name == 'endif') {
      if (text != null) {
        LoggerManager.logger.error(
          'malformed preprocessor directive - text not permitted: '
          'endif::$directiveTarget[$text]',
          at: cursor(),
        );
      } else if (_conditionalStack.isEmpty) {
        LoggerManager.logger.error(
          'unmatched preprocessor directive: endif::$directiveTarget[]',
          at: cursor(),
        );
      } else if (noTarget || directiveTarget == _conditionalStack.last.target) {
        _conditionalStack.removeLast();
        _skipping =
            _conditionalStack.isNotEmpty && _conditionalStack.last.skipping;
      } else {
        LoggerManager.logger.error(
          'mismatched preprocessor directive: '
          'endif::$directiveTarget[], expected '
          'endif::${_conditionalStack.last.target ?? ''}[]',
          at: cursor(),
        );
      }
      return true;
    } else if (_skipping) {
      if (name == 'ifeval') {
        if (!(noTarget &&
            text != null &&
            evalExpressionRx.hasMatch(text.trimAscii()))) {
          return true;
        }
      } else if (noTarget) {
        return true;
      }
      // skip stays false; the tail below no-ops while skipping
      return _pushConditionalFrame(name, directiveTarget, text, false);
    } else {
      // QUESTION any way to wrap ifdef & ifndef logic up together?
      var skip = false;
      switch (name) {
        case 'ifdef':
          if (noTarget) {
            LoggerManager.logger.error(
              'malformed preprocessor directive - missing target: '
              'ifdef::[${text ?? ''}]',
              at: cursor(),
            );
            return true;
          }
          final parts = delimiter == null
              ? null
              : directiveTarget.split(delimiter == ',' ? ',' : '+');
          if (delimiter == ',') {
            // skip if no attribute is defined
            skip = !parts!.any(_document.attributes.containsKey);
          } else if (delimiter == '+') {
            // skip if any attribute is undefined
            skip = parts!.any(
              (attrName) => !_document.attributes.containsKey(attrName),
            );
          } else {
            // if the attribute is undefined, then skip
            skip = !_document.attributes.containsKey(directiveTarget);
          }
        case 'ifndef':
          if (noTarget) {
            LoggerManager.logger.error(
              'malformed preprocessor directive - missing target: '
              'ifndef::[${text ?? ''}]',
              at: cursor(),
            );
            return true;
          }
          final parts = delimiter == null
              ? null
              : directiveTarget.split(delimiter == ',' ? ',' : '+');
          if (delimiter == ',') {
            // skip if any attribute is defined
            skip = parts!.any(_document.attributes.containsKey);
          } else if (delimiter == '+') {
            // skip if all attributes are defined
            skip = parts!.every(_document.attributes.containsKey);
          } else {
            // if the attribute is defined, then skip
            skip = _document.attributes.containsKey(directiveTarget);
          }
        case 'ifeval':
          if (noTarget) {
            // the text in brackets must match a conditional expression
            final exprMatch = text == null
                ? null
                : evalExpressionRx.firstMatch(text.trimAscii());
            if (exprMatch != null) {
              // NOTE assignments must happen before call to resolveExprVal
              final lhs = exprMatch.group(1)!;
              // regex enforces a restricted set of math-related operations
              // (==, !=, <=, >=, <, >)
              final op = exprMatch.group(2)!;
              final rhs = exprMatch.group(3)!;
              try {
                skip = !_compareExprValues(
                  _resolveExprVal(lhs),
                  op,
                  _resolveExprVal(rhs),
                );
              } on Exception catch (_) {
                skip = true;
              }
            } else {
              LoggerManager.logger.error(
                'malformed preprocessor directive - '
                '${text != null ? 'invalid' : 'missing'} expression: '
                'ifeval::[${text ?? ''}]',
                at: cursor(),
              );
              return true;
            }
          } else {
            LoggerManager.logger.error(
              'malformed preprocessor directive - target not permitted: '
              'ifeval::$directiveTarget[${text ?? ''}]',
              at: cursor(),
            );
            return true;
          }
      }
      return _pushConditionalFrame(name, directiveTarget, text, skip);
    }
  }

  /// Records the conditional frame for [name], expanding single-line
  /// conditionals. Always returns `true`.
  bool _pushConditionalFrame(
    String name,
    String target,
    String? text,
    bool skip,
  ) {
    // conditional inclusion block
    if (name == 'ifeval') {
      if (skip) _skipping = true;
      _conditionalStack.add(
        _ConditionalFrame(
          name: name,
          expr: text,
          skip: skip,
          skipping: _skipping,
          sourceLocation: _sourcemap ? cursor() : null,
        ),
      );
      // single line conditional inclusion
    } else if (text != null) {
      if (!_skipping && !skip) {
        replaceNextLine(text.trimRightAscii());
        // HACK push dummy line to stand in for the opening conditional
        // directive that's subsequently dropped
        unshift('');
        // NOTE force line to be processed again if it looks like an include
        // directive
        // QUESTION should we just call preprocess_include_directive here?
        if (text.startsWith('include::')) _lookAhead -= 1;
      }
      // conditional inclusion block
    } else {
      if (skip) _skipping = true;
      _conditionalStack.add(
        _ConditionalFrame(
          name: name,
          target: target,
          skip: skip,
          skipping: _skipping,
          sourceLocation: _sourcemap ? cursor() : null,
        ),
      );
    }

    return true;
  }

  /// Preprocesses the directive to include the target document.
  ///
  /// Returns whether the line under the cursor was changed.
  bool _preprocessIncludeDirective(String target, String? attrlist) {
    final doc = _document;
    var expandedTarget = target;
    final attrMissing = AttributeMissing.parse(
      doc.attributes['attribute-missing'] ?? Compliance.attributeMissing,
    );
    if (target.contains(attrRefHead) &&
        (expandedTarget = substitutors.subAttributes(
          doc,
          target,
          attributeMissing: attrMissing == AttributeMissing.warn
              ? AttributeMissing.dropLine
              : attrMissing,
        )).isEmpty) {
      // The re-substitution check is pure (drop-line with ignore severity
      // logs nothing), so it is computed once for the branches below.
      final droppedDueToMissingAttr = substitutors
          .subAttributes(
            doc,
            '$target ',
            attributeMissing: AttributeMissing.dropLine,
            reportDroppedLine: false,
          )
          .isEmpty;
      final dropReason =
          attrMissing == AttributeMissing.warn && droppedDueToMissingAttr
          ? 'due to missing attribute'
          : 'because resolved target is blank';
      if (attrMissing == AttributeMissing.dropLine && droppedDueToMissingAttr) {
        LoggerManager.logger.info(
          'include dropped due to missing attribute: '
          'include::$target[${attrlist ?? ''}]',
          at: cursor(),
        );
        shift();
        return true;
      } else if (substitutors
          .parseAttributes(doc, attrlist, subInput: true)
          .containsKey('optional-option')) {
        LoggerManager.logger.info(
          'optional include dropped $dropReason: '
          'include::$target[${attrlist ?? ''}]',
          at: cursor(),
        );
        shift();
        return true;
      } else {
        LoggerManager.logger.warn(
          'include dropped $dropReason: '
          'include::$target[${attrlist ?? ''}]',
          at: cursor(),
        );
        // QUESTION should this line include target or expanded_target (or
        // escaped target?)
        return replaceNextLine(
          'Unresolved directive in $_path - '
          'include::$target[${attrlist ?? ''}]',
        );
      }
    } else {
      final ext = hasIncludeProcessors
          ? _findIncludeProcessor(expandedTarget)
          : null;
      if (ext != null) {
        shift();
        // FIXME parse attributes only if requested by extension
        ext.process(
          doc,
          this,
          expandedTarget,
          substitutors.parseAttributes(doc, attrlist, subInput: true),
        );
        return true;
        // if running in SafeMode::SECURE or greater, don't process this
        // directive; however, be friendly and at least make it a link to the
        // source document
      } else if (doc.safe >= SafeMode.secure) {
        // FIXME we don't want to use a passthrough or link macro if we're in
        // a verbatim context
        var linkTarget = expandedTarget;
        if (linkTarget.contains(' ')) linkTarget = 'pass:c[$linkTarget]';
        return replaceNextLine(
          'link:$linkTarget[${_includeLinkAttrlist(attrlist)}]',
        );
      } else if (_maxdepth != null) {
        final maxdepth = _maxdepth!;
        if (_includeStack.length >= maxdepth.curr) {
          LoggerManager.logger.error(
            'maximum include depth of ${maxdepth.rel} exceeded',
            at: cursor(),
          );
          return false;
        }

        final parsedAttrs = substitutors.parseAttributes(
          doc,
          attrlist,
          subInput: true,
        );
        final resolution = _resolveIncludePath(
          expandedTarget,
          attrlist,
          parsedAttrs,
        );
        // A null resolution means the directive line was already handled
        // (shifted or replaced) inside _resolveIncludePath.
        if (resolution == null) return true;

        Encoding encoding = utf8;
        final encName = parsedAttrs['encoding'];
        if (encName != null) {
          final resolved = _findEncoding(encName);
          if (resolved != null) encoding = resolved;
        }

        List<num>? incLinenos;
        Map<String, bool>? incTags;
        // NOTE attrlist is null if missing from include directive
        if (attrlist != null) {
          if (parsedAttrs.containsKey('lines')) {
            final collected = <num>[];
            for (final linedef in _splitDelimitedValue(parsedAttrs['lines']!)) {
              final rangeIdx = linedef.indexOf('..');
              if (rangeIdx != -1) {
                final from = _toInt(linedef.substring(0, rangeIdx));
                final toText = linedef.substring(rangeIdx + 2);
                final to = toText.isEmpty ? null : _toInt(toText);
                if (to == null || to < 0) {
                  collected
                    ..add(from)
                    ..add(double.infinity);
                } else {
                  for (var n = from; n <= to; n++) {
                    collected.add(n);
                  }
                }
              } else {
                collected.add(_toInt(linedef));
              }
            }
            if (collected.isNotEmpty) {
              collected.sort();
              incLinenos = collected.toSet().toList();
            }
          } else if (parsedAttrs.containsKey('tag')) {
            final tag = parsedAttrs['tag']!;
            if (tag.isNotEmpty && tag != '!') {
              incTags = tag.startsWith('!')
                  ? {tag.substring(1): false}
                  : {tag: true};
            }
          } else if (parsedAttrs.containsKey('tags')) {
            final tags = <String, bool>{};
            for (final tagdef in _splitDelimitedValue(parsedAttrs['tags']!)) {
              if (tagdef.startsWith('!')) {
                tags[tagdef.substring(1)] = false;
              } else if (tagdef.isNotEmpty && tagdef != '!') {
                tags[tagdef] = true;
              }
            }
            if (tags.isNotEmpty) incTags = tags;
          }
        }

        if (incLinenos != null) {
          return _includeLinesByNumber(
            resolution,
            expandedTarget,
            attrlist,
            parsedAttrs,
            encoding,
            incLinenos,
          );
        } else if (incTags != null) {
          return _includeLinesByTag(
            resolution,
            expandedTarget,
            attrlist,
            parsedAttrs,
            encoding,
            incTags,
          );
        } else if (parsedAttrs['parallel'] case final other?
            when resolution.type == _IncludeTargetType.file &&
                doc.safe < SafeMode.secure) {
          // Parallel texts (ADR-0019): the included document beside another
          // in the same scheme, unit by unit.
          final otherPath = doc.normalizeSystemPath(
            other,
            start: _dir,
            targetName: 'include file',
          );
          final text = io.isFile(otherPath)
              ? parallelText(resolution.path, otherPath)
              : null;
          if (text == null) {
            LoggerManager.logger.error(
              'no units to set side by side: $expandedTarget and $other',
              at: cursor(),
            );
            return replaceNextLine(
              'Unresolved directive in $_path - '
              'include::$expandedTarget[${attrlist ?? ''}]',
            );
          }
          shift();
          _pushInclude(
            source: text,
            file: resolution.path,
            path: resolution.relpath,
            attrs: parsedAttrs,
            remote: resolution.remote,
          );
        } else {
          final _IncludeContent raw;
          try {
            raw = _readIncludeRaw(resolution, encoding);
          } on _IncludeNotReadable {
            LoggerManager.logger.error(
              'include ${resolution.typeName} not readable: '
              '${resolution.path}',
              at: cursor(),
            );
            return replaceNextLine(
              'Unresolved directive in $_path - '
              'include::$expandedTarget[${attrlist ?? ''}]',
            );
          }
          // NOTE read content before shift so cursor is only advanced if IO
          // operation succeeds
          shift();
          // NOTE a decode failure raises here, after the shift, as
          // Asciidoctor does.
          final content = raw.text ?? _decodeIncludeBytes(raw.bytes!, encoding);
          _pushInclude(
            source: content,
            file: resolution.path,
            path: resolution.relpath,
            attrs: parsedAttrs,
            remote: resolution.remote,
          );
        }
        return true;
      }
      return false;
    }
  }

  /// Includes the selected 1-based line numbers from the resolved include.
  bool _includeLinesByNumber(
    _ResolvedInclude resolution,
    String expandedTarget,
    String? attrlist,
    Map<String, String> parsedAttrs,
    Encoding encoding,
    List<num> incLinenos,
  ) {
    List<String>? incLines;
    int? incOffset;
    try {
      final raw = _readIncludeRaw(resolution, encoding);
      // Decode failures while streaming the file are handled as an
      // unreadable include.
      final content =
          raw.text ??
          _tryDecodeIncludeBytes(raw.bytes!, encoding) ??
          (throw const _IncludeNotReadable());
      incLines = [];
      var incLineno = 0;
      final remaining = List<num>.of(incLinenos);
      var selectRemaining = false;
      for (final rawLine in _splitRawLines(content)) {
        incLineno += 1;
        final select = remaining.isEmpty ? null : remaining[0];
        if (selectRemaining ||
            (select is double && (selectRemaining = select.isInfinite))) {
          // NOTE record line where we started selecting
          incOffset ??= incLineno;
          incLines.add(rawLine.withoutTrailingNewline());
        } else {
          if (select == incLineno) {
            // NOTE record line where we started selecting
            incOffset ??= incLineno;
            incLines.add(rawLine.withoutTrailingNewline());
            remaining.removeAt(0);
          }
          if (remaining.isEmpty) break;
        }
      }
    } on _IncludeNotReadable {
      LoggerManager.logger.error(
        'include ${resolution.typeName} not readable: ${resolution.path}',
        at: cursor(),
      );
      return replaceNextLine(
        'Unresolved directive in $_path - '
        'include::$expandedTarget[${attrlist ?? ''}]',
      );
    }
    shift();
    // FIXME not accounting for skipped lines in reader line numbering
    final offset = incOffset;
    if (offset != null) {
      parsedAttrs['partial-option'] = '';
      _pushInclude(
        lines: incLines,
        file: resolution.path,
        path: resolution.relpath,
        lineno: offset,
        attrs: parsedAttrs,
        remote: resolution.remote,
      );
    }
    return true;
  }

  /// Includes the tag-selected lines from the resolved include.
  bool _includeLinesByTag(
    _ResolvedInclude resolution,
    String expandedTarget,
    String? attrlist,
    Map<String, String> parsedAttrs,
    Encoding encoding,
    Map<String, bool> incTags,
  ) {
    // The selection tables below mutate the tag map.
    final tags = Map<String, bool>.of(incTags);
    late bool select;
    late bool baseSelect;
    bool? wildcard;
    if (tags.containsKey('**')) {
      select = baseSelect = tags.remove('**')!;
      if (tags.containsKey('*')) {
        wildcard = tags.remove('*');
      } else if (!select && tags.isNotEmpty && !tags.values.first) {
        // NOTE an empty map counts as not starting with an exclusion.
        wildcard = true;
      }
    } else if (tags.containsKey('*')) {
      if (tags.keys.first == '*') {
        select = baseSelect = !(wildcard = tags.remove('*')!);
      } else {
        select = baseSelect = false;
        wildcard = tags.remove('*');
      }
    } else {
      select = baseSelect = !tags.containsValue(true);
    }

    List<String>? incLines;
    int? incOffset;
    try {
      final raw = _readIncludeRaw(resolution, encoding);
      // Decode failures while streaming the file are handled as an
      // unreadable include.
      final content =
          raw.text ??
          _tryDecodeIncludeBytes(raw.bytes!, encoding) ??
          (throw const _IncludeNotReadable());
      incLines = [];
      var incLineno = 0;
      final tagStack = <_TagFrame>[];
      final tagsSelected = <String>{};
      String? activeTag;
      for (final rawLine in _splitRawLines(content)) {
        incLineno += 1;
        final line = rawLine.withoutTrailingNewline();
        final tagMatch = line.contains('::') && line.contains('[]')
            ? tagDirectiveRx.firstMatch(line)
            : null;
        if (tagMatch != null) {
          final thisTag = tagMatch.group(2)!;
          if (tagMatch.group(1) != null) {
            // end tag
            if (thisTag == activeTag) {
              tagStack.removeLast();
              if (tagStack.isEmpty) {
                activeTag = null;
                select = baseSelect;
              } else {
                activeTag = tagStack.last.name;
                select = tagStack.last.select;
              }
            } else if (tags.containsKey(thisTag)) {
              final includeCursor = createIncludeCursor(
                resolution.path,
                expandedTarget,
                incLineno,
                remote: resolution.remote,
              );
              final idx = tagStack.lastIndexWhere(
                (frame) => frame.name == thisTag,
              );
              if (idx != -1) {
                tagStack.removeAt(idx);
                LoggerManager.logger.add(
                  Severity.warn,
                  LogMessage(
                    "mismatched end tag (expected '$activeTag' but found "
                    "'$thisTag') at line $incLineno of include "
                    '${resolution.typeName}: ${resolution.path}',
                    sourceLocation: cursor(),
                    includeLocation: includeCursor,
                  ),
                );
              } else {
                LoggerManager.logger.add(
                  Severity.warn,
                  LogMessage(
                    "unexpected end tag '$thisTag' at line $incLineno of "
                    'include ${resolution.typeName}: ${resolution.path}',
                    sourceLocation: cursor(),
                    includeLocation: includeCursor,
                  ),
                );
              }
            }
          } else if (tags.containsKey(thisTag)) {
            select = tags[thisTag]!;
            if (select) tagsSelected.add(thisTag);
            // QUESTION should we prevent tag from being selected when
            // enclosing tag is excluded?
            activeTag = thisTag;
            tagStack.add(_TagFrame(thisTag, incLineno, select: select));
          } else if (wildcard != null) {
            select = (activeTag == null || select) && wildcard;
            activeTag = thisTag;
            tagStack.add(_TagFrame(thisTag, incLineno, select: select));
          }
        } else if (select) {
          // NOTE record the line where we started selecting
          incOffset ??= incLineno;
          incLines.add(line);
        }
      }
      if (tagStack.isNotEmpty) {
        for (final frame in tagStack) {
          LoggerManager.logger.add(
            Severity.warn,
            LogMessage(
              "detected unclosed tag '${frame.name}' starting at line "
              '${frame.lineno} of include ${resolution.typeName}: '
              '${resolution.path}',
              sourceLocation: cursor(),
              includeLocation: createIncludeCursor(
                resolution.path,
                expandedTarget,
                frame.lineno,
                remote: resolution.remote,
              ),
            ),
          );
        }
      }
      tags.removeWhere((_, value) => !value);
      final missingTags = tags.keys
          .where((tag) => !tagsSelected.contains(tag))
          .toList();
      if (missingTags.isNotEmpty) {
        LoggerManager.logger.warn(
          "tag${missingTags.length > 1 ? 's' : ''} "
          "'${missingTags.join(', ')}' "
          'not found in include ${resolution.typeName}: ${resolution.path}',
          at: cursor(),
        );
      }
    } on _IncludeNotReadable {
      LoggerManager.logger.error(
        'include ${resolution.typeName} not readable: ${resolution.path}',
        at: cursor(),
      );
      return replaceNextLine(
        'Unresolved directive in $_path - '
        'include::$expandedTarget[${attrlist ?? ''}]',
      );
    }
    shift();
    final offset = incOffset;
    if (offset != null) {
      if (!(baseSelect && wildcard != false && tags.isEmpty)) {
        parsedAttrs['partial-option'] = '';
      }
      // FIXME not accounting for skipped lines in reader line numbering
      _pushInclude(
        lines: incLines,
        file: resolution.path,
        path: resolution.relpath,
        lineno: offset,
        attrs: parsedAttrs,
        remote: resolution.remote,
      );
    }
    return true;
  }

  /// Resolves the target of an include directive.
  ///
  /// Returns the resolved path, target type and document-relative path, or
  /// `null` when the directive line was already handled inline (shifted past
  /// or replaced with a fallback line).
  _ResolvedInclude? _resolveIncludePath(
    String target,
    String? attrlist,
    Map<String, String> attributes,
  ) {
    final doc = _document;
    var resolvedTarget = target;
    if (!Helpers.isUriish(resolvedTarget) && _remote) {
      resolvedTarget = '$_dir/$resolvedTarget';
    }
    if (Helpers.isUriish(resolvedTarget) || _remote) {
      if (!doc.hasAttr('allow-uri-read')) {
        LoggerManager.logger.warn(
          'cannot include contents of URI: $resolvedTarget '
          '(allow-uri-read attribute not enabled)',
          at: cursor(),
        );
        // FIXME we don't want to use a passthrough or link macro if we're in
        // a verbatim context
        var linkTarget = resolvedTarget;
        if (linkTarget.contains(' ')) linkTarget = 'pass:c[$linkTarget]';
        replaceNextLine('link:$linkTarget[${_includeLinkAttrlist(attrlist)}]');
        return null;
      }
      return _ResolvedInclude(
        resolvedTarget,
        _IncludeTargetType.uri,
        resolvedTarget,
      );
    } else {
      // include file is resolved relative to dir of current include, or
      // base_dir if within original docfile
      final incPath = doc.normalizeSystemPath(
        target,
        start: _dir,
        targetName: 'include file',
      );
      if (!io.isFile(incPath)) {
        if (attributes.containsKey('optional-option')) {
          LoggerManager.logger.info(
            'optional include dropped because include file not '
            'found: $incPath',
            at: cursor(),
          );
          shift();
          return null;
        } else {
          LoggerManager.logger.error(
            'include file not found: $incPath',
            at: cursor(),
          );
          replaceNextLine(
            'Unresolved directive in $_path - '
            'include::$target[${attrlist ?? ''}]',
          );
          return null;
        }
      }
      // NOTE relpath is the path relative to the root document (or base_dir,
      // if set)
      // QUESTION should we move relative_path method to Document
      final relpath = doc.pathResolver.relativePath(incPath, doc.baseDir);
      return _ResolvedInclude(incPath, _IncludeTargetType.file, relpath);
    }
  }

  /// Reads the raw include content: bytes for files, decoded text for URIs.
  ///
  /// Throws [_IncludeNotReadable] when the content cannot be read.
  _IncludeContent _readIncludeRaw(
    _ResolvedInclude resolution,
    Encoding encoding,
  ) {
    if (resolution.type == _IncludeTargetType.file) {
      // A file of a document in units, as the units engine renders it.
      if (_document.unitsReading?.linesOf(resolution.path) case final lines?) {
        return _IncludeContent.text('${lines.join('\n')}\n');
      }
      try {
        return _IncludeContent.bytes(io.readBytes(resolution.path));
      } on Exception catch (_) {
        throw const _IncludeNotReadable();
      }
    }
    try {
      return _IncludeContent.text(
        encoding.decode(_document.fetchUri(resolution.path).body),
      );
    } on Exception catch (_) {
      throw const _IncludeNotReadable();
    }
  }

  /// Pops the latest include frame, restoring the previous context.
  void _popInclude() {
    if (_includeStack.isEmpty) return;
    final frame = _includeStack.removeLast();
    _lines = frame.lines;
    _file = frame.file;
    _dir = frame.dir;
    _remote = frame.remote;
    _path = frame.path;
    _lineno = frame.lineno;
    _maxdepth = frame.maxdepth;
    processLines = frame.processLines;
    // FIXME kind of a hack
    //Document::AttributeEntry.new('infile', @file).save_to_next_block @document
    //Document::AttributeEntry.new('indir', ::File.dirname(@file))
    //  .save_to_next_block @document
    _lookAhead = 0;
  }

  /// Ignores front matter, commonly used in static site generators.
  ///
  /// Mutates [data] in place. Returns the front matter lines, or `null` when
  /// no (complete) front matter block is present.
  List<String>? _skipFrontMatter(
    List<String> data, [
    bool incrementLinenos = true,
  ]) {
    final delim = data.isEmpty ? null : data[0];
    if (delim != '---' && delim != '+++') return null;
    final originalData = List<String>.of(data);
    data.removeAt(0);
    final frontMatter = <String>[];
    if (incrementLinenos) _lineno += 1;
    while (true) {
      if (data.isEmpty) {
        data.insertAll(0, originalData);
        if (incrementLinenos) _lineno -= originalData.length;
        return null;
      }
      if (data[0] == delim) break;
      frontMatter.add(data.removeAt(0));
      if (incrementLinenos) _lineno += 1;
    }
    data.removeAt(0);
    if (incrementLinenos) _lineno += 1;
    return frontMatter;
  }

  /// Resolves the value of one side of an `ifeval` expression, coerced to
  /// the appropriate type.
  _Operand _resolveExprVal(String val) {
    var current = val;
    final bool quoted;
    if ((current.startsWith('"') && current.endsWith('"')) ||
        (current.startsWith("'") && current.endsWith("'"))) {
      quoted = true;
      current = current.length >= 2
          ? current.substring(1, current.length - 1)
          : '';
    } else {
      quoted = false;
    }

    // QUESTION should we substitute first?
    // QUESTION should we also require string to be single quoted (like block
    // attribute values?)
    if (current.contains(attrRefHead)) {
      current = substitutors.subAttributes(
        _document,
        current,
        attributeMissing: AttributeMissing.drop,
      );
    }

    if (quoted) {
      return _StringOperand(current);
    } else if (current.isEmpty) {
      return const _NullOperand();
    } else if (current == 'true') {
      return const _BoolOperand(value: true);
    } else if (current == 'false') {
      return const _BoolOperand(value: false);
    } else if (current.trimRightAscii().isEmpty) {
      return const _StringOperand(' ');
    } else if (current.contains('.')) {
      return _NumOperand(_parseFloatPrefix(current));
    } else {
      // fallback to coercing to integer, since we
      // require string values to be explicitly quoted
      return _NumOperand(_toInt(current));
    }
  }

  /// Finds the first include processor handling [target], or `null`.
  IncludeProcessor? _findIncludeProcessor(String target) {
    final extensions = _includeProcessorExtensions;
    if (extensions == null) return null;
    for (final ext in extensions) {
      if (ext.handles(_document, target)) return ext;
    }
    return null;
  }

  /// The attribute list of the link an include directive falls back to:
  /// the directive's own [attrlist], after `role=include` unless in compat
  /// mode.
  String _includeLinkAttrlist(String? attrlist) =>
      _document.hasAttr('compat-mode')
      ? attrlist ?? ''
      : 'role=include${attrlist == null ? '' : ',$attrlist'}';
}

/// A saved include context, restored when the include is exhausted.
final class _IncludeFrame {
  const new({
    required this.lines,
    required this.file,
    required this.dir,
    required this.remote,
    required this.path,
    required this.lineno,
    required this.maxdepth,
    required this.processLines,
  });

  final List<String> lines;
  final String? file;
  final String dir;
  final bool remote;
  final String path;
  final int lineno;
  final _MaxDepth? maxdepth;
  final bool processLines;
}

/// A saved [PreprocessorReader] state (beyond the [Reader] state).
final class _PreprocessorState {
  const new({
    required this.includeStack,
    required this.maxdepth,
    required this.skipping,
    required this.conditionalStack,
    required this.includeProcessors,
    required this.includeProcessorsChecked,
  });

  final List<_IncludeFrame> includeStack;
  final _MaxDepth? maxdepth;
  final bool skipping;
  final List<_ConditionalFrame> conditionalStack;
  final List<IncludeProcessor>? includeProcessors;
  final bool includeProcessorsChecked;
}

/// The content read for an include: raw file bytes or decoded URI text.
final class _IncludeContent {
  const new bytes(List<int> this.bytes) : text = null;
  const new text(String this.text) : bytes = null;

  final List<int>? bytes;
  final String? text;
}

/// One side of an `ifeval` comparison.
sealed class _Operand {
  const new();
}

final class _NullOperand extends _Operand {
  const new();
}

final class _StringOperand extends _Operand {
  const new(this.value);

  final String value;
}

final class _NumOperand extends _Operand {
  const new(this.value);

  final num value;
}

final class _BoolOperand extends _Operand {
  const new({required this.value});

  final bool value;
}

/// Absolute, current and relative max include depths.
class _MaxDepth {
  const new(this.abs, this.curr, this.rel);

  /// Absolute max depth (from `max-include-depth`).
  final int abs;

  /// Current max depth (compared against the include stack size).
  final int curr;

  /// Relative max depth (used in reports).
  final int rel;
}

/// An open preprocessor conditional frame.
class _ConditionalFrame {
  const new({
    required this.name,
    required this.skip,
    required this.skipping,
    this.target,
    this.expr,
    this.sourceLocation,
  });

  /// Directive name (`ifdef`, `ifndef` or `ifeval`).
  final String name;

  /// Lowercased target (`ifdef`/`ifndef` only).
  final String? target;

  /// Bracket text (`ifeval` only).
  final String? expr;

  /// Whether the frame's condition evaluated to skip.
  final bool skip;

  /// Whether the reader was skipping when the frame opened.
  final bool skipping;

  /// Location of the opening directive (when sourcemap is enabled).
  final Cursor? sourceLocation;
}

/// An open tag frame while filtering an include by tags.
class _TagFrame {
  const new(this.name, this.lineno, {required this.select});

  /// Tag name.
  final String name;

  /// Whether lines under the tag are selected.
  final bool select;

  /// 1-based line number of the opening tag directive.
  final int lineno;
}

/// Include target kinds.
enum _IncludeTargetType {
  /// A file on the file system.
  file,

  /// A remote resource.
  uri,
}

/// A resolved include target.
class _ResolvedInclude {
  const new(this.path, this.type, this.relpath);

  /// Resolved path (a file path, or a URI for remote targets).
  final String path;

  /// Target kind.
  final _IncludeTargetType type;

  /// Path relative to the root document.
  final String relpath;

  /// Whether the target is remote (a URI).
  bool get remote => type == _IncludeTargetType.uri;

  /// `file` or `uri`, as interpolated into log messages.
  String get typeName => type == _IncludeTargetType.file ? 'file' : 'uri';
}

/// Thrown when include content cannot be read (caught and reported).
class _IncludeNotReadable implements Exception {
  const new();
}

/// Thrown when `ifeval` operands cannot be compared (caught; drops content).
class _InvalidExprComparison implements Exception {
  const new();
}

/// Compares resolved `ifeval` operands with [op].
///
/// `==`/`!=` compare numbers with numbers, strings with strings and
/// booleans with booleans (mixed types never match; only null equals
/// null), while relational operators work on two numbers or two strings and
/// throw [_InvalidExprComparison] otherwise.
bool _compareExprValues(_Operand lhs, String op, _Operand rhs) {
  switch (op) {
    case '==':
      return _exprEquals(lhs, rhs);
    case '!=':
      return !_exprEquals(lhs, rhs);
    default:
      final comparison = _exprCompareTo(lhs, rhs);
      return switch (op) {
        '<' => comparison < 0,
        '>' => comparison > 0,
        '<=' => comparison <= 0,
        '>=' => comparison >= 0,
        _ => throw const _InvalidExprComparison(),
      };
  }
}

bool _exprEquals(_Operand lhs, _Operand rhs) => switch ((lhs, rhs)) {
  (_NullOperand(), _NullOperand()) => true,
  (_NumOperand(value: final a), _NumOperand(value: final b)) => a == b,
  (_StringOperand(value: final a), _StringOperand(value: final b)) => a == b,
  (_BoolOperand(value: final a), _BoolOperand(value: final b)) => a == b,
  _ => false,
};

int _exprCompareTo(_Operand lhs, _Operand rhs) => switch ((lhs, rhs)) {
  (_NumOperand(value: final a), _NumOperand(value: final b)) => a.compareTo(b),
  (_StringOperand(value: final a), _StringOperand(value: final b)) =>
    a.compareTo(b),
  _ => throw const _InvalidExprComparison(),
};

final RegExp _intPrefixRx = RegExp(r'^[+-]?\d[\d_]*');

/// Coerces [value] to an integer from its leading numeric prefix (else
/// 0); `null` yields 0.
int _toInt(String? value) {
  if (value == null) return 0;
  final match = _intPrefixRx.firstMatch(trimLeftAscii(value));
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.replaceAll('_', '')) ?? 0;
}

final RegExp _floatPrefixRx = RegExp(
  r'^[+-]?(?:\d[\d_]*)?(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?',
);

/// Coerces [value] to a double: leading
/// whitespace is skipped, then the leading numeric (or inf/nan) prefix is
/// parsed, else 0.0.
double _parseFloatPrefix(String value) {
  final text = trimLeftAscii(value);
  if (text.isEmpty) return 0;
  final lower = text.toLowerCase();
  final signedInf = RegExp('^[+-]?inf');
  final signedNan = RegExp('^[+-]?nan');
  if (signedInf.hasMatch(lower)) {
    return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  if (signedNan.hasMatch(lower)) return double.nan;
  final match = _floatPrefixRx.firstMatch(text);
  final number = match?.group(0)?.replaceAll('_', '') ?? '';
  return double.tryParse(number) ?? 0.0;
}

/// Splits [content] into raw lines; each line keeps its trailing newline except
/// possibly the last.
List<String> _splitRawLines(String content) {
  final lines = <String>[];
  var start = 0;
  var end = content.indexOf('\n', start);
  while (end != -1) {
    lines.add(content.substring(start, end + 1));
    start = end + 1;
    end = content.indexOf('\n', start);
  }
  if (start < content.length) lines.add(content.substring(start));
  return lines;
}

/// Splits a delimited include value on commas (when present) or semicolons,
/// dropping trailing empty entries.
List<String> _splitDelimitedValue(String value) {
  if (value.isEmpty) return [];
  final parts = value.contains(',') ? value.split(',') : value.split(';');
  var end = parts.length;
  while (end > 0 && parts[end - 1].isEmpty) {
    end--;
  }
  return parts.sublist(0, end);
}

/// Resolves an `encoding` attribute value to a Dart [Encoding], or `null`
/// when unknown (the caller then keeps UTF-8).
///
/// Only the encodings Dart decodes natively are supported; anything else
/// falls back to UTF-8, which then raises the invalid-Unicode error on
/// undecodable input.
Encoding? _findEncoding(String name) {
  switch (name.toLowerCase()) {
    case 'utf-8':
    case 'utf8':
      return utf8;
    case 'ascii':
    case 'us-ascii':
      return ascii;
    case 'iso-8859-1':
    case 'iso8859-1':
    case 'iso88591':
    case 'iso_8859-1':
    case 'latin1':
    case 'latin-1':
      return latin1;
    default:
      return null;
  }
}

/// Decodes include [bytes] strictly, raising an invalid-Unicode error on
/// undecodable input.
String _decodeIncludeBytes(List<int> bytes, Encoding encoding) =>
    _tryDecodeIncludeBytes(bytes, encoding) ??
    (throw const AsciidoctorException(
      'source is either binary or contains invalid Unicode data',
    ));

/// Decodes include [bytes] strictly, or returns `null` when they are not
/// valid in [encoding].
String? _tryDecodeIncludeBytes(List<int> bytes, Encoding encoding) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Returns the directory name of [path] (POSIX `dirname` semantics).
String _dirname(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2f) {
    end--;
  }
  var slash = -1;
  for (var i = end - 1; i >= 0; i--) {
    if (path.codeUnitAt(i) == 0x2f) {
      slash = i;
      break;
    }
  }
  if (slash == -1) return '.';
  while (slash > 1 && path.codeUnitAt(slash - 1) == 0x2f) {
    slash--;
  }
  if (slash == 0) return '/';
  return path.substring(0, slash);
}

/// Quotes [value] with backslash escapes, for [Object.toString].
String _inspect(String value) {
  final buffer = StringBuffer('"');
  for (final unit in value.codeUnits) {
    switch (unit) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5c:
        buffer.write(r'\\');
      case 0x0a:
        buffer.write(r'\n');
      case 0x0d:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        buffer.writeCharCode(unit);
    }
  }
  buffer.write('"');
  return buffer.toString();
}
