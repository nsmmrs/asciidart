// Deprecated aliases mirror Ruby; removed only when upstream removes them.
// ignore_for_file: remove_deprecations_in_breaking_versions
// Positional params mirror Ruby signatures for port fidelity.
// ignore_for_file: avoid_positional_boolean_parameters
/// Line reader with preprocessor directive support for the Dart port of
/// Asciidoctor.
///
/// Port of `lib/asciidoctor/reader.rb` (`Reader`, `PreprocessorReader` and
/// `Reader::Cursor`).
///
/// The reader is a line stack with a 1-based line number. Lines are stored in
/// reverse so the next line is always the last element. [Reader] is a plain
/// line source; [PreprocessorReader] additionally expands conditional
/// (`ifdef`/`ifndef`/`ifeval`/`endif`) and `include` preprocessor directives
/// as lines are read.
///
/// Several names in this file are temporary homes for concepts owned by waves
/// that have not landed yet; each is marked `TEMPORARY` with the owning wave:
/// the `rx.dart` regular expressions, the `logging.dart` log surface, the
/// `SafeMode` constants and the [ReaderDocument]/[ReaderIncludeProcessor]
/// interfaces (owned by the `document.dart` and `extensions.dart` waves).
library;

import 'dart:convert' show Encoding, ascii, latin1, utf8;
import 'dart:io' show File, FileSystemEntity;

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/parser.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/rx.dart';

/// A log message carrying source context.
///
/// TEMPORARY: a minimal stand-in for the `logging.dart`
/// `message_with_context` hash; unified with that port when it lands.
class LogMessage {
  /// Creates a message with [text] and optional source locations.
  const new(this.text, {this.sourceLocation, this.includeLocation});

  /// The message text, without location prefix.
  final String text;

  /// Location of the line under the cursor when the message was logged.
  final Cursor? sourceLocation;

  /// Location inside an include file the message refers to, if any.
  final Cursor? includeLocation;

  @override
  String toString() {
    final location = sourceLocation;
    return location == null ? text : '$location: $text';
  }
}

/// Builds a [LogMessage]. Temporary stand-in for `Logging#message_with_context`
/// (see [LogMessage]).
LogMessage _messageWithContext(
  String text, {
  Cursor? sourceLocation,
  Cursor? includeLocation,
}) => LogMessage(
  text,
  sourceLocation: sourceLocation,
  includeLocation: includeLocation,
);

/// Minimal document surface consumed by [PreprocessorReader].
///
/// TEMPORARY interface, defined by the reader wave because `document.dart`
/// has not landed yet. It covers exactly what `reader.rb` touches on
/// `Document` (attribute lookup, substitution, include resolution inputs and
/// the include catalog). The `document.dart` wave unifies this with the real
/// `Document`, which must then implement (or absorb) this surface:
///
/// * [attributes] is the live attribute map; the reader reads
///   `skip-front-matter`, `max-include-depth`, `attribute-missing` and
///   conditional names from it and stores `front-matter` in it.
/// * [attr]/[attrSet] mirror `Document#attr`/`Document#attr?` for the single
///   names the reader queries (`leveloffset`, `tabsize`, `allow-uri-read`,
///   `compat-mode`, `cache-uri`).
/// * [subAttributes]/[parseAttributes] are the `Substitutors` entry points
///   used for include targets, include attr lists and `ifeval` operands.
/// * [normalizeSystemPath]/[pathResolver]/[baseDir] resolve include files;
///   [catalogIncludes] is the `catalog[:includes]` table; [safe] and
///   [sourcemap] gate secure-mode and location tracking.
/// * [includeProcessors] are the registered include processor extensions, or
///   `null` when the extensions framework has none.
/// * [readUri] fetches an include target over HTTP. Dart has no synchronous
///   HTTP client, so URI transport is injected here instead of living in the
///   reader (where Ruby uses OpenURI directly). Returns the decoded body, or
///   `null` when the URI is not readable.
abstract class ReaderDocument {
  /// Live document attributes.
  Map<String, Object?> get attributes;

  /// Resolves the attribute [name], or `null` when undefined.
  Object? attr(String name);

  /// Whether the attribute [name] is defined.
  bool attrSet(String name);

  /// Whether source locations are tracked.
  bool get sourcemap;

  /// Safe mode level (see [SafeMode]).
  int get safe;

  /// Base directory include files resolve against.
  String get baseDir;

  /// Path resolver used for include paths.
  PathResolver get pathResolver;

  /// Include catalog mapping an include path (sans extension) to `true`, or
  /// to `null` for a partial include that stays invisible to xrefs.
  Map<String, bool?> get catalogIncludes;

  /// Registered include processor extensions, or `null` when there are none.
  List<ReaderIncludeProcessor>? get includeProcessors;

  /// Resolves the include [target] against [start], honoring the safe-mode
  /// jail. Mirrors `AbstractNode#normalize_system_path`.
  String normalizeSystemPath(
    String target,
    String? start, {
    String? targetName,
  });

  /// Substitutes attribute references in [text]. Mirrors
  /// `Substitutors#sub_attributes` for the options the reader uses.
  String subAttributes(
    String text, {
    String? attributeMissing,
    String dropLineSeverity = 'info',
  });

  /// Parses an include directive attr list. Mirrors
  /// `Substitutors#parse_attributes` for the options the reader uses.
  Map<Object, String?> parseAttributes(
    String? attrlist, {
    bool subInput = false,
  });

  /// Reads the include target [uri] decoded with [encoding].
  ///
  /// Returns `null` when the URI cannot be read.
  String? readUri(Uri uri, Encoding encoding);
}

/// Minimal include processor extension surface consumed by
/// [PreprocessorReader].
///
/// TEMPORARY interface mirroring the two `IncludeProcessor` methods
/// `reader.rb` calls (`handles?` and the process method). The
/// `extensions.dart` wave unifies this with the real extension types.
abstract class ReaderIncludeProcessor {
  /// Whether this processor handles the given include [target].
  bool handles(ReaderDocument document, String target);

  /// Pushes the content for [target] onto [reader].
  void process(
    ReaderDocument document,
    PreprocessorReader reader,
    String target,
    Map<Object, String?> attributes,
  );
}

/// A file position: the file, directory, document-relative path and 1-based
/// line number of a line under the cursor.
///
/// Port of `Asciidoctor::Reader::Cursor`.
class Cursor {
  /// Creates a cursor. [file] is a path string, a [Uri], or `null`;
  /// [dir] is a path string or a [Uri].
  new(this.file, [this.dir, this.path, this.lineno = 1]);

  /// The file under the cursor, if known.
  final Object? file;

  /// The directory of [file], if known.
  final Object? dir;

  /// The document-relative path of [file].
  final String? path;

  /// The 1-based line number under the cursor.
  int lineno;

  /// Advances the line number by [num].
  void advance(int num) {
    lineno += num;
  }

  /// Returns a copy of this cursor (port of Ruby's `Cursor#dup`, used for
  /// source locations in `lib/asciidoctor/table.rb` and `lib/asciidoctor/parser.rb`).
  Cursor dup() => Cursor(file, dir, path, lineno);

  /// `path: line N` summary of this cursor.
  String get lineInfo => '$path: line $lineno';

  @override
  String toString() => lineInfo;
}

/// How source lines are normalized during preparation.
enum _LineNormalization {
  /// No normalization; string input is chomped and split only.
  none,

  /// Coerce to Unicode and strip trailing whitespace (Ruby `normalize: true`).
  full,

  /// Strip a single trailing record separator only (Ruby `normalize: :chomp`).
  chomp,
}

/// Methods for retrieving lines from AsciiDoc source.
///
/// Port of `Asciidoctor::Reader`. Lines are held on a stack in reverse; the
/// next line is the last element. A `null` entry behaves exactly as in Ruby:
/// it peeks as end-of-data but still occupies (and is consumed from) the
/// stack when read directly.
class Reader {
  /// Initializes the reader.
  ///
  /// [data] is a string, a list of lines (which may contain `null` entries),
  /// or `null` for an empty reader. [cursor] is a file path string, a
  /// [Cursor], or `null` (stdin). When [normalize] is set, lines are
  /// normalized as in Ruby (`normalize: true`); [skipFrontMatter] is honored
  /// by [PreprocessorReader] only, exactly like the Ruby `opts` entry.
  new([
    Object? data,
    Object? cursor,
    bool normalize = false,
    bool skipFrontMatter = false,
  ]) {
    if (cursor == null) {
      _file = null;
      _dir = '.';
      _path = '<stdin>';
      _lineno = 1;
    } else if (cursor is String) {
      _file = cursor;
      _dir = _dirname(cursor);
      _path = Helpers.basename(cursor);
      _lineno = 1;
    } else if (cursor is Cursor) {
      final cursorFile = cursor.file;
      if (cursorFile != null) {
        _file = cursorFile;
        _dir = cursor.dir ?? _dirnameOf(cursorFile);
        _path =
            cursor.path ??
            (cursorFile is String
                ? Helpers.basename(cursorFile)
                : Helpers.basename(cursorFile.toString()));
      } else {
        _file = null;
        _dir = cursor.dir ?? '.';
        _path = cursor.path ?? '<stdin>';
      }
      _lineno = cursor.lineno;
    } else {
      throw ArgumentError('cursor must be a String, a Cursor, or null');
    }
    _sourceLines = _prepareLines(
      data,
      normalize: normalize ? _LineNormalization.full : _LineNormalization.none,
      skipFrontMatter: skipFrontMatter,
    );
    _lines = _sourceLines.reversed.toList();
    _mark = null;
    _lookAhead = 0;
    processLines = true;
    _unescapeNextLine = false;
    unterminated = false;
    _savedState = null;
  }

  /// Sentinel for [readLinesUntil]'s [cursor] parameter selecting the cursor
  /// at the mark (resolved lazily, as with Ruby's `cursor: :at_mark`).
  static const Object atMark = _AtMark();

  /// Default `context` marker for [readLinesUntil], selecting the terminator.
  static const Object _defaultContext = Object();

  Object? _file;
  late Object _dir;
  late String _path;
  late int _lineno;
  late List<String?> _lines;
  late List<String?> _sourceLines;
  List<Object?>? _mark;
  int _lookAhead = 0;

  /// Whether lines are processed using [processLine] on first visit.
  bool processLines = true;
  bool _unescapeNextLine = false;

  /// Whether the end of the reader was reached with a delimited block open.
  bool unterminated = false;
  List<Object?>? _savedState;

  /// The file under the cursor, if known.
  Object? get file => _file;

  /// The directory of [file].
  Object get dir => _dir;

  /// The document-relative path of [file].
  String get path => _path;

  /// The 1-based offset of the current line.
  int get lineno => _lineno;

  /// The live document source lines (normal order).
  List<String?> get sourceLines => _sourceLines;

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

  /// Alias of [isEmpty].
  bool get isEof => isEmpty;

  /// Whether the next line is empty (or there are no more lines). Does not
  /// consume the line.
  bool isNextLineEmpty() => peekLine().isNilOrEmpty;

  /// Peeks at the next line of source data. Processes the line if not
  /// already visited, but does not consume it.
  ///
  /// When [direct] is set, processing is bypassed and the top stack element
  /// is returned immediately. Returns `null` when there is no more data.
  String? peekLine([bool direct = false]) {
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
  List<String> peekLines([int? num, bool direct = false]) {
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
  List<String?> readLines() {
    final lines = <String?>[];
    // hasMoreLines triggers preprocessing in subclasses.
    while (hasMoreLines()) {
      lines.add(shift());
    }
    return lines;
  }

  /// Alias of [readLines].
  List<String?> readlines() => readLines();

  /// Gets the remaining lines of source data joined as a string.
  String read() => readLines().map((line) => line ?? '').join(lf);

  /// Advances past the next line, returning whether a line was consumed.
  bool advance() => shift() != null;

  /// Pushes [lineToRestore] as the next line to read. The line is marked as
  /// processed immediately.
  void unshiftLine(String lineToRestore) {
    unshift(lineToRestore);
  }

  /// Alias of [unshiftLine].
  void restoreLine(String lineToRestore) => unshiftLine(lineToRestore);

  /// Pushes [linesToRestore] as the next lines to read. The lines are marked
  /// as processed immediately.
  void unshiftLines(List<String> linesToRestore) {
    unshiftAll(linesToRestore);
  }

  /// Alias of [unshiftLines].
  void restoreLines(List<String> linesToRestore) =>
      unshiftLines(linesToRestore);

  /// Replaces the next line with [replacement]. Returns `true`.
  bool replaceNextLine(String replacement) {
    shift();
    unshift(replacement);
    return true;
  }

  /// Alias of [replaceNextLine]. Deprecated in Ruby; kept for parity.
  @Deprecated('Use replaceNextLine instead.')
  bool replaceLine(String replacement) => replaceNextLine(replacement);

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
  ///   then preserved, as in Ruby).
  /// * [skipFirstLine] advances beyond the first line before scanning.
  /// * [preserveLastLine] pushes the stopping line back onto the stack.
  /// * [readLastLine] includes the stopping line in the result.
  /// * [skipLineComments] drops line comments from the result.
  /// * [skipProcessing] disables line (pre)processing for the scan.
  /// * [context] names the block in the unterminated warning and defaults to
  ///   [terminator]; pass an explicit `null` to suppress the warning.
  /// * [cursor] selects the start cursor for the warning, or [atMark] to use
  ///   the cursor at the mark.
  List<String> readLinesUntil({
    String? terminator,
    bool breakOnBlankLines = false,
    bool breakOnListContinuation = false,
    bool skipFirstLine = false,
    bool preserveLastLine = false,
    bool readLastLine = false,
    bool skipLineComments = false,
    bool skipProcessing = false,
    Object? context = _defaultContext,
    Object? cursor,
    bool Function(String line)? test,
  }) {
    final result = <String>[];
    var restoreProcessLines = false;
    if (processLines && skipProcessing) {
      processLines = false;
      restoreProcessLines = true;
    }
    Object? startCursor;
    var preserveLast = preserveLastLine;
    if (terminator != null) {
      startCursor = cursor ?? this.cursor();
      breakOnBlankLines = false;
      breakOnListContinuation = false;
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
          : ((breakOnBlankLines && current.isEmpty) ||
                (breakOnListContinuation &&
                    lineRead &&
                    current == listContinuation &&
                    (preserveLast = true)) ||
                (test != null && test(current)));
      if (stop) {
        if (readLastLine) result.add(current);
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
        lineRead = true;
      }
    }
    if (restoreProcessLines) {
      processLines = true;
      if (lineRestored && terminator == null) _lookAhead -= 1;
    }
    final effectiveContext = identical(context, _defaultContext)
        ? terminator
        : context;
    if (terminator != null && terminator != line && effectiveContext != null) {
      var start = startCursor;
      if (identical(start, atMark)) start = cursorAtMark();
      LoggerManager.logger.warn(
        _messageWithContext(
          'unterminated $effectiveContext block',
          sourceLocation: start as Cursor?,
        ),
      );
      unterminated = true;
    }
    return result;
  }

  /// Shifts the line off the stack and increments the line number.
  ///
  /// Internal: use directly only when [peekLine] already determined the line
  /// should be consumed; otherwise use [readLine]. The line number is
  /// incremented even when the stack is empty, exactly as in Ruby.
  String? shift() {
    _lineno += 1;
    if (_lookAhead != 0) _lookAhead -= 1;
    return _lines.isEmpty ? null : _lines.removeLast();
  }

  /// Restores [line] to the stack and decrements the line number.
  ///
  /// Internal: see [shift].
  void unshift(String line) {
    _lineno -= 1;
    _lookAhead += 1;
    _lines.add(line);
  }

  /// Restores [linesToRestore] to the stack and decrements the line number.
  ///
  /// Internal: see [shift].
  void unshiftAll(List<String> linesToRestore) {
    _lineno -= linesToRestore.length;
    _lookAhead += linesToRestore.length;
    _lines.addAll(linesToRestore.reversed);
  }

  /// The cursor at the current line.
  Cursor cursor() => Cursor(_file, _dir, _path, _lineno);

  /// The cursor at [lineno] in the current file.
  Cursor cursorAtLine(int lineno) => Cursor(_file, _dir, _path, lineno);

  /// The cursor at the mark, or the current cursor when unmarked.
  Cursor cursorAtMark() {
    final mark = _mark;
    return mark != null
        ? Cursor(mark[0], mark[1], mark[2] as String?, mark[3]! as int)
        : cursor();
  }

  /// The cursor on the line before the mark (or the current line).
  Cursor cursorBeforeMark() {
    final mark = _mark;
    if (mark != null) {
      return Cursor(
        mark[0],
        mark[1],
        mark[2] as String?,
        (mark[3]! as int) - 1,
      );
    }
    return Cursor(_file, _dir, _path, _lineno - 1);
  }

  /// The cursor at the previous line.
  Cursor cursorAtPrevLine() => Cursor(_file, _dir, _path, _lineno - 1);

  /// Marks the current cursor position. Always returns `true` so the call
  /// can be chained in boolean expressions, as in Ruby.
  bool mark() {
    _mark = [_file, _dir, _path, _lineno];
    return true;
  }

  /// `path: line N` summary of the last line read.
  String get lineInfo => '$path: line $lineno';

  /// A copy of the remaining lines managed by this reader.
  List<String?> get lines => _lines.reversed.toList();

  /// A copy of the remaining lines managed by this reader joined as a string.
  String get string => _lines.reversed.map((line) => line ?? '').join(lf);

  /// The source lines for this reader joined as a string.
  String get source => _sourceLines.map((line) => line ?? '').join(lf);

  /// Saves the state of the reader at the cursor.
  void save() {
    _savedState = _captureState();
  }

  /// Restores the state saved by [save], discarding the saved state.
  /// Does nothing when no state was saved.
  void restoreSave() {
    final saved = _savedState;
    if (saved == null) return;
    _restoreState(saved);
    _savedState = null;
  }

  /// Discards state saved by [save].
  void discardSave() {
    _savedState = null;
  }

  @override
  String toString() =>
      '#<$runtimeType@${identityHashCode(this)} {path: ${_inspect(_path)}, line: $_lineno}>';

  /// Processes a previously unvisited line.
  ///
  /// Internal (public for parity with Ruby's test seam): marks the line as
  /// processed and returns it unmodified. Returns `null` to drop the line
  /// and advance to the next one.
  String? processLine(String line) {
    if (processLines) _lookAhead += 1;
    return line;
  }

  /// Captures this reader's saveable state.
  List<Object?> _captureState() => [
    List<String?>.of(_lines),
    _file,
    _dir,
    _path,
    _lineno,
    if (_mark == null) null else List<Object?>.of(_mark!),
    _lookAhead,
    processLines,
    _unescapeNextLine,
    unterminated,
  ];

  /// Restores state captured by [_captureState].
  void _restoreState(List<Object?> saved) {
    _lines = saved[0]! as List<String?>;
    _file = saved[1];
    _dir = saved[2]!;
    _path = saved[3]! as String;
    _lineno = saved[4]! as int;
    _mark = saved[5] as List<Object?>?;
    _lookAhead = saved[6]! as int;
    processLines = saved[7]! as bool;
    _unescapeNextLine = saved[8]! as bool;
    unterminated = saved[9]! as bool;
  }

  /// Prepares the source data for parsing.
  ///
  /// Converts [data] into a list of lines ready for parsing. [normalize]
  /// controls encoding/whitespace handling; [skipFrontMatter] is honored by
  /// the [PreprocessorReader] override only.
  ///
  /// Unlike Ruby, no encoding rescue is needed: Dart strings are always
  /// valid Unicode.
  List<String?> _prepareLines(
    Object? data, {
    _LineNormalization normalize = _LineNormalization.none,
    bool skipFrontMatter = false,
  }) {
    // NOTE results are normalized to a runtime List<String?> so later
    // mutations (front matter restore, null entries) never hit covariance
    // checks against a List<String>.
    switch (normalize) {
      case _LineNormalization.full:
        if (data is List) {
          return List<String?>.of(
            Helpers.prepareSourceArray(
              data.map((line) => line as String).toList(),
            ),
          );
        }
        return List<String?>.of(Helpers.prepareSourceString(data as String?));
      case _LineNormalization.chomp:
        if (data is List) {
          return List<String?>.of(
            Helpers.prepareSourceArray(
              data.map((line) => line as String).toList(),
              false,
            ),
          );
        }
        return List<String?>.of(
          Helpers.prepareSourceString(data as String?, false),
        );
      case _LineNormalization.none:
        if (data is List) return List<String?>.from(data);
        if (data != null) {
          return <String?>[...(data as String).chomp().split(lf)];
        }
        return [];
    }
  }
}

/// Methods for retrieving lines from AsciiDoc source files, evaluating
/// preprocessor directives as each line is read.
///
/// Port of `Asciidoctor::PreprocessorReader`.
class PreprocessorReader extends Reader {
  /// Initializes the preprocessor reader for [document].
  ///
  /// See [Reader.new] for [data], [cursor] and [normalize]. Front matter is
  /// skipped when the document sets the `skip-front-matter` attribute.
  new(
    ReaderDocument document, [
    Object? data,
    Object? cursor,
    bool normalize = false,
  ]) : _document = document,
       _sourcemap = document.sourcemap,
       _includes = document.catalogIncludes,
       super(
         data,
         cursor,
         normalize,
         _isTruthy(document.attributes['skip-front-matter']),
       ) {
    final maxDepthValue = document.attributes['max-include-depth'];
    final defaultDepth = maxDepthValue == null || maxDepthValue == false
        ? 64
        : _toInt(maxDepthValue);
    // Track absolute max depth, current max depth for comparing to include
    // stack size, and relative max depth for reporting.
    // If _maxdepth is not set, built-in include functionality is disabled.
    _maxdepth = defaultDepth > 0
        ? _MaxDepth(defaultDepth, defaultDepth, defaultDepth)
        : null;
    _includeStack = [];
    _skipping = false;
    _conditionalStack = [];
    _includeProcessorExtensions = null;
    _includeProcessorsChecked = false;
    _savedPreprocessorState = null;
  }

  final ReaderDocument _document;
  final bool _sourcemap;
  final Map<String, bool?> _includes;
  _MaxDepth? _maxdepth;
  late List<List<Object?>> _includeStack;
  late bool _skipping;
  late List<_ConditionalFrame> _conditionalStack;
  List<ReaderIncludeProcessor>? _includeProcessorExtensions;
  bool _includeProcessorsChecked = false;
  List<Object?>? _savedPreprocessorState;

  /// The stack of active include frames.
  List<List<Object?>> get includeStack => _includeStack;

  @override
  bool hasMoreLines() => peekLine() != null;

  @override
  bool get isEmpty => peekLine() == null;

  /// Pops the include stack when the last line of an include has been
  /// reached, reporting unterminated preprocessor conditionals when the
  /// outermost source is exhausted. See [Reader.peekLine].
  @override
  String? peekLine([bool direct = false]) {
    final line = super.peekLine(direct);
    if (line != null) return line;
    if (_includeStack.isEmpty) {
      Cursor? endCursor;
      _conditionalStack.removeWhere((conditional) {
        LoggerManager.logger.error(
          _messageWithContext(
            'detected unterminated preprocessor conditional directive: '
            '${conditional.name}::${conditional.target ?? ''}[${conditional.expr ?? ''}]',
            sourceLocation:
                conditional.sourceLocation ??
                (endCursor ??= cursorAtPrevLine()),
          ),
        );
        return true;
      });
      return null;
    } else {
      _popInclude();
      return peekLine(direct);
    }
  }

  /// Pushes [data] onto the front of the reader and switches the context to
  /// the given [file], document-relative [path] and line info.
  ///
  /// Typically used in an include processor to add source read from the
  /// target. [lineno] defaults to 1. Returns this reader.
  PreprocessorReader pushInclude(
    Object? data, [
    Object? file,
    String? path,
    int lineno = 1,
    Map<Object, String?>? attributes,
  ]) {
    final attrs = attributes ?? <Object, String?>{};
    _includeStack.add([
      _lines,
      _file,
      _dir,
      _path,
      _lineno,
      _maxdepth,
      processLines,
    ]);
    final includeFile = file;
    if (includeFile != null) {
      if (includeFile is String) {
        _dir = _dirname(includeFile);
      } else if (includeFile is Uri) {
        final dirPath = _dirname(includeFile.path);
        _dir = includeFile.replace(path: dirPath == '/' ? '' : dirPath);
      } else {
        throw ArgumentError('file must be a String, a Uri, or null');
      }
      // NOTE _file keeps the original object (a Uri stays a Uri); only the
      // local string form is used for path computations below.
      final fileString = includeFile.toString();
      _path = path ?? Helpers.basename(fileString);
      // only process lines in AsciiDoc files
      if (processLines = asciidocExtensions.keys.any(fileString.endsWith)) {
        final dot = _path.lastIndexOf('.');
        final key = dot == -1 ? _path : _path.substring(0, dot);
        // NOTE registering the include with a null value tracks it while not
        // making it visible to interdocument xrefs
        if (_includes[key] == null) {
          _includes[key] = attrs['partial-option'] != null ? null : true;
        }
      }
    } else {
      _dir = '.';
      // we don't know what file type we have, so assume AsciiDoc
      processLines = true;
      if (path != null) {
        _path = path;
        // NOTE registering the include with a null value tracks it while not
        // making it visible to interdocument xrefs
        final key = Helpers.rootname(path);
        if (_includes[key] == null) {
          _includes[key] = attrs['partial-option'] != null ? null : true;
        }
      } else {
        _path = '<stdin>';
      }
    }

    _file = includeFile;
    _lineno = lineno;

    if (_maxdepth != null && attrs.containsKey('depth')) {
      final relMaxdepth = _toInt(attrs['depth']);
      if (relMaxdepth > 0) {
        var currMaxdepth = _includeStack.length + relMaxdepth;
        var rel = relMaxdepth;
        final absMaxdepth = _maxdepth!.abs;
        if (currMaxdepth > absMaxdepth) {
          // if relative depth exceeds absolute max depth, effectively ignore
          // relative depth request
          currMaxdepth = rel = absMaxdepth;
        }
        _maxdepth = _MaxDepth(absMaxdepth, currMaxdepth, rel);
      } else {
        _maxdepth = _MaxDepth(_maxdepth!.abs, _includeStack.length, 0);
      }
    }

    // effectively fill the buffer
    final prepared = _prepareLines(
      data,
      normalize: processLines
          ? _LineNormalization.full
          : _LineNormalization.chomp,
      include: true,
      indent: attrs['indent'],
      skipFrontMatter: attrs['skip-front-matter-option'] != null,
    );
    if (prepared.isEmpty) {
      _popInclude();
    } else {
      // FIXME we eventually want to handle leveloffset without affecting
      // the lines
      if (attrs.containsKey('leveloffset')) {
        final leveloffset = _document.attr('leveloffset');
        _lines = [
          if (_isTruthy(leveloffset))
            ':leveloffset: $leveloffset'
          else
            ':leveloffset!:',
          '',
          ...prepared.reversed,
          '',
          ':leveloffset: ${attrs['leveloffset']}',
        ];
        // compensate for these extra lines at the top
        _lineno -= 2;
      } else {
        _lines = prepared.reversed.toList();
      }

      // FIXME kind of a hack
      //Document::AttributeEntry.new('infile', @file).save_to_next_block @document
      //Document::AttributeEntry.new('indir', @dir).save_to_next_block @document
      _lookAhead = 0;
    }
    return this;
  }

  /// The current include depth (size of the include stack).
  int get includeDepth => _includeStack.length;

  /// Whether pushing an include would exceed the max include depth.
  ///
  /// Returns `null` when no max depth is set (includes disabled), `false`
  /// when the current max depth will not be exceeded, and the relative max
  /// include depth when it will be exceeded.
  Object? get exceedsMaxDepth {
    final maxdepth = _maxdepth;
    if (maxdepth == null) return null;
    if (_includeStack.length >= maxdepth.curr) return maxdepth.rel;
    return false;
  }

  /// Alias of [exceedsMaxDepth].
  Object? get exceededMaxDepth => exceedsMaxDepth;

  /// Shifts the line off the stack, unescaping it first when the previous
  /// peek marked it escaped. See [Reader.shift].
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
      _includeProcessorExtensions = _document.includeProcessors;
    }
    return _includeProcessorExtensions != null;
  }

  /// Creates a cursor for [file] (a path string or [Uri]) at [lineno].
  Cursor createIncludeCursor(Object file, String path, int lineno) {
    if (file is String) {
      return Cursor(file, _dirname(file), path, lineno);
    } else if (file is Uri) {
      var dir = _dirname(file.path);
      if (dir == '') dir = '/';
      return Cursor(file.toString(), dir, path, lineno);
    }
    throw ArgumentError('file must be a String or a Uri');
  }

  @override
  String toString() =>
      '#<$runtimeType@${identityHashCode(this)} {path: ${_inspect(_path)}, line: $_lineno, include depth: ${_includeStack.length}, include stack: [${_includeStack.map((inc) => inc.toString()).join(', ')}]}>';

  @override
  void save() {
    super.save();
    _savedPreprocessorState = [
      List<List<Object?>>.of(_includeStack),
      _maxdepth,
      _skipping,
      List<_ConditionalFrame>.of(_conditionalStack),
      _includeProcessorExtensions,
      _includeProcessorsChecked,
    ];
  }

  @override
  void restoreSave() {
    final saved = _savedPreprocessorState;
    super.restoreSave();
    if (saved == null) return;
    _includeStack = saved[0]! as List<List<Object?>>;
    _maxdepth = saved[1] as _MaxDepth?;
    _skipping = saved[2]! as bool;
    _conditionalStack = saved[3]! as List<_ConditionalFrame>;
    _includeProcessorExtensions = saved[4] as List<ReaderIncludeProcessor>?;
    _includeProcessorsChecked = saved[5]! as bool;
    _savedPreprocessorState = null;
  }

  @override
  void discardSave() {
    super.discardSave();
    _savedPreprocessorState = null;
  }

  /// Prepares include [data], skipping front matter and adjusting
  /// indentation for includes, or dropping trailing blank lines otherwise.
  @override
  List<String?> _prepareLines(
    Object? data, {
    _LineNormalization normalize = _LineNormalization.none,
    bool skipFrontMatter = false,
    bool include = false,
    Object? indent,
  }) {
    final result = super._prepareLines(data, normalize: normalize);

    if (skipFrontMatter) {
      final frontMatter = _skipFrontMatter(result);
      if (frontMatter != null && !include) {
        _document.attributes['front-matter'] = frontMatter
            .map((line) => line ?? '')
            .join(lf);
      }
    }

    if (include) {
      if (indent != null) {
        // Port of the `Parser.adjust_indentation!` call in
        // `PreprocessorReader#prepare_lines` (lib/asciidoctor/reader.rb:803).
        // The include path always normalizes to non-null strings, so the
        // `?? ''` fallback never fires in practice.
        final lines = List<String>.of(result.map((line) => line ?? ''));
        Parser.adjustIndentation(
          lines,
          _toInt(indent),
          _toInt(_document.attr('tabsize')),
        );
        for (var i = 0; i < lines.length; i++) {
          result[i] = lines[i];
        }
      }
    } else {
      while (result.isNotEmpty && (result.last?.isEmpty ?? false)) {
        result.removeLast();
      }
    }

    return result;
  }

  /// Processes a previously unvisited line, expanding preprocessor
  /// directives. See [Reader.processLine].
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
    // attributes are case insensitive
    final noTarget = target.isEmpty;
    if (!noTarget) target = target.toLowerCase();

    if (name == 'endif') {
      if (text != null) {
        LoggerManager.logger.error(
          _messageWithContext(
            'malformed preprocessor directive - text not permitted: '
            'endif::$target[$text]',
            sourceLocation: cursor(),
          ),
        );
      } else if (_conditionalStack.isEmpty) {
        LoggerManager.logger.error(
          _messageWithContext(
            'unmatched preprocessor directive: endif::$target[]',
            sourceLocation: cursor(),
          ),
        );
      } else if (noTarget || target == _conditionalStack.last.target) {
        _conditionalStack.removeLast();
        _skipping = _conditionalStack.isEmpty
            ? false
            : _conditionalStack.last.skipping;
      } else {
        LoggerManager.logger.error(
          _messageWithContext(
            'mismatched preprocessor directive: endif::$target[], expected '
            'endif::${_conditionalStack.last.target ?? ''}[]',
            sourceLocation: cursor(),
          ),
        );
      }
      return true;
    } else if (_skipping) {
      if (name == 'ifeval') {
        if (!(noTarget &&
            text != null &&
            evalExpressionRx.hasMatch(text.trim()))) {
          return true;
        }
      } else if (noTarget) {
        return true;
      }
      // skip stays false; the tail below no-ops while skipping
      return _pushConditionalFrame(name, target, text, false);
    } else {
      // QUESTION any way to wrap ifdef & ifndef logic up together?
      var skip = false;
      switch (name) {
        case 'ifdef':
          if (noTarget) {
            LoggerManager.logger.error(
              _messageWithContext(
                'malformed preprocessor directive - missing target: '
                'ifdef::[${text ?? ''}]',
                sourceLocation: cursor(),
              ),
            );
            return true;
          }
          final parts = delimiter == null
              ? null
              : target.split(delimiter == ',' ? ',' : '+');
          if (delimiter == ',') {
            // skip if no attribute is defined
            skip = !parts!.any(
              (attrName) => _document.attributes.containsKey(attrName),
            );
          } else if (delimiter == '+') {
            // skip if any attribute is undefined
            skip = parts!.any(
              (attrName) => !_document.attributes.containsKey(attrName),
            );
          } else {
            // if the attribute is undefined, then skip
            skip = !_document.attributes.containsKey(target);
          }
        case 'ifndef':
          if (noTarget) {
            LoggerManager.logger.error(
              _messageWithContext(
                'malformed preprocessor directive - missing target: '
                'ifndef::[${text ?? ''}]',
                sourceLocation: cursor(),
              ),
            );
            return true;
          }
          final parts = delimiter == null
              ? null
              : target.split(delimiter == ',' ? ',' : '+');
          if (delimiter == ',') {
            // skip if any attribute is defined
            skip = parts!.any(
              (attrName) => _document.attributes.containsKey(attrName),
            );
          } else if (delimiter == '+') {
            // skip if all attributes are defined
            skip = parts!.every(
              (attrName) => _document.attributes.containsKey(attrName),
            );
          } else {
            // if the attribute is defined, then skip
            skip = _document.attributes.containsKey(target);
          }
        case 'ifeval':
          if (noTarget) {
            // the text in brackets must match a conditional expression
            final exprMatch = text == null
                ? null
                : evalExpressionRx.firstMatch(text.trim());
            if (exprMatch != null) {
              // NOTE assignments must happen before call to resolveExprVal
              // for compatibility with Opal
              final lhs = exprMatch.group(1)!;
              // regex enforces a restricted set of math-related operations
              // (==, !=, <=, >=, <, >)
              final op = exprMatch.group(2)!;
              final rhs = exprMatch.group(3)!;
              try {
                skip =
                    _compareExprValues(
                      _resolveExprVal(lhs),
                      op,
                      _resolveExprVal(rhs),
                    )
                    ? false
                    : true;
              } catch (_) {
                skip = true;
              }
            } else {
              LoggerManager.logger.error(
                _messageWithContext(
                  'malformed preprocessor directive - '
                  '${text != null ? 'invalid expression' : 'missing expression'}: '
                  'ifeval::[${text ?? ''}]',
                  sourceLocation: cursor(),
                ),
              );
              return true;
            }
          } else {
            LoggerManager.logger.error(
              _messageWithContext(
                'malformed preprocessor directive - target not permitted: '
                'ifeval::$target[${text ?? ''}]',
                sourceLocation: cursor(),
              ),
            );
            return true;
          }
      }
      return _pushConditionalFrame(name, target, text, skip);
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
        replaceNextLine(text.rstrip());
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
    final attrMissingValue = doc.attributes['attribute-missing'];
    final attrMissing = attrMissingValue == null || attrMissingValue == false
        ? Compliance.attributeMissing
        : attrMissingValue.toString();
    if (target.contains(attrRefHead) &&
        (expandedTarget = doc.subAttributes(
          target,
          attributeMissing: attrMissing == 'warn' ? 'drop-line' : attrMissing,
        )).isEmpty) {
      // The re-substitution check is pure (drop-line with ignore severity
      // logs nothing), so it is computed once for the branches below.
      final droppedDueToMissingAttr = doc
          .subAttributes(
            '$target ',
            attributeMissing: 'drop-line',
            dropLineSeverity: 'ignore',
          )
          .isEmpty;
      if (attrMissing == 'drop-line' && droppedDueToMissingAttr) {
        LoggerManager.logger.info(
          () => _messageWithContext(
            'include dropped due to missing attribute: '
            'include::$target[${attrlist ?? ''}]',
            sourceLocation: cursor(),
          ),
        );
        shift();
        return true;
      } else if (doc
          .parseAttributes(attrlist, subInput: true)
          .containsKey('optional-option')) {
        LoggerManager.logger.info(
          () => _messageWithContext(
            'optional include dropped '
            '${attrMissing == 'warn' && droppedDueToMissingAttr ? 'due to missing attribute' : 'because resolved target is blank'}: '
            'include::$target[${attrlist ?? ''}]',
            sourceLocation: cursor(),
          ),
        );
        shift();
        return true;
      } else {
        LoggerManager.logger.warn(
          _messageWithContext(
            'include dropped '
            '${attrMissing == 'warn' && droppedDueToMissingAttr ? 'due to missing attribute' : 'because resolved target is blank'}: '
            'include::$target[${attrlist ?? ''}]',
            sourceLocation: cursor(),
          ),
        );
        // QUESTION should this line include target or expanded_target (or
        // escaped target?)
        return replaceNextLine(
          'Unresolved directive in $_path - include::$target[${attrlist ?? ''}]',
        );
      }
    } else {
      final ext = hasIncludeProcessors
          ? _findIncludeProcessor(doc, expandedTarget)
          : null;
      if (ext != null) {
        shift();
        // FIXME parse attributes only if requested by extension
        ext.process(
          doc,
          this,
          expandedTarget,
          doc.parseAttributes(attrlist, subInput: true),
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
        final linkAttrlist = doc.attrSet('compat-mode')
            ? (attrlist ?? '')
            : 'role=include${attrlist != null ? ',$attrlist' : ''}';
        return replaceNextLine('link:$linkTarget[$linkAttrlist]');
      } else if (_maxdepth != null) {
        final maxdepth = _maxdepth!;
        if (_includeStack.length >= maxdepth.curr) {
          LoggerManager.logger.error(
            _messageWithContext(
              'maximum include depth of ${maxdepth.rel} exceeded',
              sourceLocation: cursor(),
            ),
          );
          return false;
        }

        final parsedAttrs = doc.parseAttributes(attrlist, subInput: true);
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
            for (final linedef in _splitDelimitedValue(
              parsedAttrs['lines'] ?? '',
            )) {
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
            final tag = parsedAttrs['tag'] ?? '';
            if (tag.isNotEmpty && tag != '!') {
              incTags = tag.startsWith('!')
                  ? {tag.substring(1): false}
                  : {tag: true};
            }
          } else if (parsedAttrs.containsKey('tags')) {
            final tags = <String, bool>{};
            for (final tagdef in _splitDelimitedValue(
              parsedAttrs['tags'] ?? '',
            )) {
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
        } else {
          final Object raw;
          try {
            raw = _readIncludeRaw(resolution, encoding);
          } on _IncludeNotReadable {
            LoggerManager.logger.error(
              _messageWithContext(
                'include ${resolution.typeName} not readable: ${resolution.path}',
                sourceLocation: cursor(),
              ),
            );
            return replaceNextLine(
              'Unresolved directive in $_path - '
              'include::$expandedTarget[${attrlist ?? ''}]',
            );
          }
          // NOTE read content before shift so cursor is only advanced if IO
          // operation succeeds
          shift();
          // NOTE a decode failure raises here, after the shift, exactly as
          // Ruby raises from push_include after shifting.
          final content = raw is String
              ? raw
              : _decodeIncludeBytes(raw as List<int>, encoding);
          pushInclude(
            content,
            resolution.path,
            resolution.relpath,
            1,
            parsedAttrs,
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
    Map<Object, String?> parsedAttrs,
    Encoding encoding,
    List<num> incLinenos,
  ) {
    List<String>? incLines;
    int? incOffset;
    try {
      String content;
      try {
        final raw = _readIncludeRaw(resolution, encoding);
        content = raw is String
            ? raw
            : _decodeIncludeBytes(raw as List<int>, encoding);
      } on ArgumentError {
        // Ruby rescues decode failures raised while streaming the file, so
        // they are handled as an unreadable include here.
        throw const _IncludeNotReadable();
      }
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
          incLines.add(rawLine.chomp());
        } else {
          if (select == incLineno) {
            // NOTE record line where we started selecting
            incOffset ??= incLineno;
            incLines.add(rawLine.chomp());
            remaining.removeAt(0);
          }
          if (remaining.isEmpty) break;
        }
      }
    } on _IncludeNotReadable {
      LoggerManager.logger.error(
        _messageWithContext(
          'include ${resolution.typeName} not readable: ${resolution.path}',
          sourceLocation: cursor(),
        ),
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
      pushInclude(
        incLines,
        resolution.path,
        resolution.relpath,
        offset,
        parsedAttrs,
      );
    }
    return true;
  }

  /// Includes the tag-selected lines from the resolved include.
  bool _includeLinesByTag(
    _ResolvedInclude resolution,
    String expandedTarget,
    String? attrlist,
    Map<Object, String?> parsedAttrs,
    Encoding encoding,
    Map<String, bool> incTags,
  ) {
    // The selection tables below mutate the tag map, as in Ruby.
    final tags = Map<String, bool>.of(incTags);
    late bool select;
    late bool baseSelect;
    bool? wildcard;
    if (tags.containsKey('**')) {
      select = baseSelect = tags.remove('**')!;
      if (tags.containsKey('*')) {
        wildcard = tags.remove('*');
      } else if (!select && tags.isNotEmpty && !tags.values.first) {
        // NOTE the isNotEmpty guard mirrors Ruby, where first on an empty
        // map yields nil, which != false.
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
      String content;
      try {
        final raw = _readIncludeRaw(resolution, encoding);
        content = raw is String
            ? raw
            : _decodeIncludeBytes(raw as List<int>, encoding);
      } on ArgumentError {
        // Ruby rescues decode failures raised while streaming the file, so
        // they are handled as an unreadable include here.
        throw const _IncludeNotReadable();
      }
      incLines = [];
      var incLineno = 0;
      final tagStack = <_TagFrame>[];
      final tagsSelected = <String>{};
      String? activeTag;
      for (final rawLine in _splitRawLines(content)) {
        incLineno += 1;
        final line = rawLine.chomp();
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
              );
              final idx = tagStack.lastIndexWhere(
                (frame) => frame.name == thisTag,
              );
              if (idx != -1) {
                tagStack.removeAt(idx);
                LoggerManager.logger.warn(
                  _messageWithContext(
                    "mismatched end tag (expected '$activeTag' but found "
                    "'$thisTag') at line $incLineno of include "
                    '${resolution.typeName}: ${resolution.path}',
                    sourceLocation: cursor(),
                    includeLocation: includeCursor,
                  ),
                );
              } else {
                LoggerManager.logger.warn(
                  _messageWithContext(
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
            tagStack.add(_TagFrame(thisTag, select, incLineno));
          } else if (wildcard != null) {
            select = activeTag != null && !select ? false : wildcard;
            activeTag = thisTag;
            tagStack.add(_TagFrame(thisTag, select, incLineno));
          }
        } else if (select) {
          // NOTE record the line where we started selecting
          incOffset ??= incLineno;
          incLines.add(line);
        }
      }
      if (tagStack.isNotEmpty) {
        for (final frame in tagStack) {
          LoggerManager.logger.warn(
            _messageWithContext(
              "detected unclosed tag '${frame.name}' starting at line "
              '${frame.lineno} of include ${resolution.typeName}: ${resolution.path}',
              sourceLocation: cursor(),
              includeLocation: createIncludeCursor(
                resolution.path,
                expandedTarget,
                frame.lineno,
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
          _messageWithContext(
            "tag${missingTags.length > 1 ? 's' : ''} '${missingTags.join(', ')}' "
            'not found in include ${resolution.typeName}: ${resolution.path}',
            sourceLocation: cursor(),
          ),
        );
      }
    } on _IncludeNotReadable {
      LoggerManager.logger.error(
        _messageWithContext(
          'include ${resolution.typeName} not readable: ${resolution.path}',
          sourceLocation: cursor(),
        ),
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
      pushInclude(
        incLines,
        resolution.path,
        resolution.relpath,
        offset,
        parsedAttrs,
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
    Map<Object, String?> attributes,
  ) {
    final doc = _document;
    var resolvedTarget = target;
    if (!Helpers.isUriish(resolvedTarget) && _dir is! String) {
      resolvedTarget = '$_dir/$resolvedTarget';
    }
    if (Helpers.isUriish(resolvedTarget) || _dir is! String) {
      if (!doc.attrSet('allow-uri-read')) {
        LoggerManager.logger.warn(
          _messageWithContext(
            'cannot include contents of URI: $resolvedTarget '
            '(allow-uri-read attribute not enabled)',
            sourceLocation: cursor(),
          ),
        );
        // FIXME we don't want to use a passthrough or link macro if we're in
        // a verbatim context
        var linkTarget = resolvedTarget;
        if (linkTarget.contains(' ')) linkTarget = 'pass:c[$linkTarget]';
        final linkAttrlist = doc.attrSet('compat-mode')
            ? (attrlist ?? '')
            : 'role=include${attrlist != null ? ',$attrlist' : ''}';
        replaceNextLine('link:$linkTarget[$linkAttrlist]');
        return null;
      }
      Helpers.requireOpenUri(doc.attrSet('cache-uri'));
      return _ResolvedInclude(
        Uri.parse(resolvedTarget),
        _IncludeTargetType.uri,
        resolvedTarget,
      );
    } else {
      // include file is resolved relative to dir of current include, or
      // base_dir if within original docfile
      final incPath = doc.normalizeSystemPath(
        target,
        _dir as String?,
        targetName: 'include file',
      );
      if (!FileSystemEntity.isFileSync(incPath)) {
        if (attributes.containsKey('optional-option')) {
          LoggerManager.logger.info(
            () => _messageWithContext(
              'optional include dropped because include file not found: $incPath',
              sourceLocation: cursor(),
            ),
          );
          shift();
          return null;
        } else {
          LoggerManager.logger.error(
            _messageWithContext(
              'include file not found: $incPath',
              sourceLocation: cursor(),
            ),
          );
          replaceNextLine(
            'Unresolved directive in $_path - include::$target[${attrlist ?? ''}]',
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
  Object _readIncludeRaw(_ResolvedInclude resolution, Encoding encoding) {
    if (resolution.type == _IncludeTargetType.file) {
      try {
        return File(resolution.path as String).readAsBytesSync();
      } catch (_) {
        throw const _IncludeNotReadable();
      }
    } else {
      String? content;
      try {
        content = _document.readUri(resolution.path as Uri, encoding);
      } catch (_) {
        content = null;
      }
      if (content == null) throw const _IncludeNotReadable();
      return content;
    }
  }

  /// Pops the latest include frame, restoring the previous context.
  void _popInclude() {
    if (_includeStack.isEmpty) return;
    final frame = _includeStack.removeLast();
    _lines = frame[0]! as List<String?>;
    _file = frame[1];
    _dir = frame[2]!;
    _path = frame[3]! as String;
    _lineno = frame[4]! as int;
    _maxdepth = frame[5] as _MaxDepth?;
    processLines = frame[6]! as bool;
    // FIXME kind of a hack
    //Document::AttributeEntry.new('infile', @file).save_to_next_block @document
    //Document::AttributeEntry.new('indir', ::File.dirname(@file)).save_to_next_block @document
    _lookAhead = 0;
  }

  /// Ignores front matter, commonly used in static site generators.
  ///
  /// Mutates [data] in place. Returns the front matter lines, or `null` when
  /// no (complete) front matter block is present.
  List<String?>? _skipFrontMatter(
    List<String?> data, [
    bool incrementLinenos = true,
  ]) {
    final delim = data.isEmpty ? null : data[0];
    if (delim != '---' && delim != '+++') return null;
    final originalData = List<String?>.of(data);
    data.removeAt(0);
    final frontMatter = <String?>[];
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
  Object? _resolveExprVal(String val) {
    final bool quoted;
    if ((val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))) {
      quoted = true;
      val = val.length >= 2 ? val.substring(1, val.length - 1) : '';
    } else {
      quoted = false;
    }

    // QUESTION should we substitute first?
    // QUESTION should we also require string to be single quoted (like block
    // attribute values?)
    if (val.contains(attrRefHead)) {
      val = _document.subAttributes(val, attributeMissing: 'drop');
    }

    if (quoted) {
      return val;
    } else if (val.isEmpty) {
      return null;
    } else if (val == 'true') {
      return true;
    } else if (val == 'false') {
      return false;
    } else if (val.rstrip().isEmpty) {
      return ' ';
    } else if (val.contains('.')) {
      return _rubyToDouble(val);
    } else {
      // fallback to coercing to integer, since we
      // require string values to be explicitly quoted
      return _toInt(val);
    }
  }

  /// Finds the first include processor handling [target], or `null`.
  ReaderIncludeProcessor? _findIncludeProcessor(
    ReaderDocument doc,
    String target,
  ) {
    final extensions = _includeProcessorExtensions;
    if (extensions == null) return null;
    for (final ext in extensions) {
      if (ext.handles(doc, target)) return ext;
    }
    return null;
  }
}

/// Sentinel type backing [Reader.atMark].
class _AtMark {
  const new();
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
  const new(this.name, this.select, this.lineno);

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

  /// Resolved path (a string for files, a [Uri] for remote targets).
  final Object path;

  /// Target kind.
  final _IncludeTargetType type;

  /// Path relative to the root document.
  final String relpath;

  /// `file` or `uri`, as interpolated into log messages.
  String get typeName => type == _IncludeTargetType.file ? 'file' : 'uri';
}

/// Thrown when include content cannot be read (caught and reported).
class _IncludeNotReadable {
  const new();
}

/// Thrown when `ifeval` operands cannot be compared (caught; drops content).
class _InvalidExprComparison {
  const new();
}

/// Compares resolved `ifeval` operands with [op].
///
/// Mirrors Ruby's `Object#send` semantics: `==`/`!=` compare numbers with
/// numbers, strings with strings and booleans with booleans (mixed types
/// never match; only `null` equals `null`), while relational operators work
/// on two numbers or two strings and throw [_InvalidExprComparison]
/// otherwise.
bool _compareExprValues(Object? lhs, String op, Object? rhs) {
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

bool _exprEquals(Object? lhs, Object? rhs) {
  if (lhs == null || rhs == null) return lhs == null && rhs == null;
  if (lhs is num && rhs is num) return lhs == rhs;
  if (lhs is String && rhs is String) return lhs == rhs;
  if (lhs is bool && rhs is bool) return lhs == rhs;
  return false;
}

int _exprCompareTo(Object? lhs, Object? rhs) {
  if (lhs is num && rhs is num) return lhs.compareTo(rhs);
  if (lhs is String && rhs is String) return lhs.compareTo(rhs);
  throw const _InvalidExprComparison();
}

/// Ruby truthiness: only `null` and `false` are falsy.
bool _isTruthy(Object? value) => value != null && value != false;

final RegExp _intPrefixRx = RegExp(r'^[+-]?\d[\d_]*');

/// Coerces [value] to an integer with Ruby's `to_i` semantics: an [int] is
/// returned as is, a [double] is truncated, and a [String] contributes its
/// leading numeric prefix (else 0). Anything else yields 0.
int _toInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is! String) return 0;
  final match = _intPrefixRx.firstMatch(value.trimLeft());
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.replaceAll('_', '')) ?? 0;
}

final RegExp _floatPrefixRx = RegExp(
  r'^[+-]?(?:\d[\d_]*)?(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?',
);

/// Coerces [value] to a double with Ruby's `to_f` semantics: leading
/// whitespace is skipped, then the leading numeric (or inf/nan) prefix is
/// parsed, else 0.0.
double _rubyToDouble(String value) {
  final text = value.trimLeft();
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

/// Splits [content] into raw lines with Ruby's `each_line` semantics: each
/// line keeps its trailing newline except possibly the last.
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
/// dropping trailing empty entries as Ruby's default `split` does.
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
/// when unknown (the caller then keeps UTF-8, as Ruby does when
/// `Encoding.find` fails).
///
/// Only the encodings Dart decodes natively are supported; anything else
/// falls back to UTF-8, which then raises the invalid-Unicode error on
/// undecodable input, exactly as in Ruby.
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

/// Decodes include [bytes] strictly, raising Ruby's invalid-Unicode error on
/// undecodable input.
String _decodeIncludeBytes(List<int> bytes, Encoding encoding) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    throw ArgumentError(
      'source is either binary or contains invalid Unicode data',
    );
  }
}

/// Returns the directory name of [path] with Ruby's posix `File.dirname`
/// semantics.
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

/// Returns the directory of the cursor [file] (a path string or [Uri]).
Object _dirnameOf(Object file) {
  if (file is String) return _dirname(file);
  if (file is Uri) {
    final dirPath = _dirname(file.path);
    return file.replace(path: dirPath == '/' ? '' : dirPath);
  }
  throw ArgumentError('file must be a String or a Uri');
}

/// Quotes [value] with Ruby's `String#inspect` escaping (for [Object.toString]
/// parity; untested surface).
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
