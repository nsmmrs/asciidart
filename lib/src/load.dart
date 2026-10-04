// Dynamic dispatch here mirrors Ruby duck typing; covered by tests.
// ignore_for_file: avoid_dynamic_calls
/// Top-level load and convert entry points for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/load.rb` ([load], [loadFile]) and
/// `lib/asciidoctor/convert.rb` ([convert], [convertFile]). Ruby's
/// deprecated `render`/`render_file` aliases are intentionally not ported.
///
/// Option keys are [String]s (`'safe'`, `'backend'`, `'attributes'`,
/// `'standalone'`, `'to_file'`, `'to_dir'`, `'mkdirs'`, `'timings'`,
/// `'logger'`, `'parse'`, ...), matching [Document]. The options map is never
/// mutated; the document receives a copy.
///
/// Accepted `input` types mirror the Ruby branches: a [File] (read from disk;
/// `docfile`/`docdir`/`docname`/`docfilesuffix` attributes are assigned), a
/// [RandomAccessFile] (the rewindable-IO branch; rewound, then read fully), a
/// [String], a [List] of lines (copied, as Ruby's `drop 0` does), or `null`
/// (and `false`, as in Ruby) for an empty document. Anything else raises an
/// [ArgumentError]. There is no synchronous in-memory IO type in `dart:io`,
/// so callers with buffered bytes should decode to a [String] first.
///
/// [loadFile] and [convertFile] accept a [String] path, a [File], or a [Uri]
/// (the `Pathname` analog) as the filename.
///
/// One deliberate divergence: Ruby treats a [File] passed as `'to_file'` as
/// an output stream (it responds to `write`); here only [StringSink] values
/// (e.g. [StringBuffer], `IOSink`) select stream mode, while [File] and [Uri]
/// values are treated as output paths, since `dart:io` offers no synchronous
/// string-writing file stream accepted by [Document.write].
library;

import 'dart:convert' show utf8;
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemException,
        RandomAccessFile;

import 'package:asciidoctor/src/abstract_node.dart' show SafeMode;
import 'package:asciidoctor/src/constants.dart'
    show defaultStylesheetKeys, nullChar;
import 'package:asciidoctor/src/core_ext.dart' show isTruthy;
import 'package:asciidoctor/src/docbook5.dart' show Docbook5Converter;
import 'package:asciidoctor/src/document.dart' show Document;
import 'package:asciidoctor/src/helpers.dart' show Helpers;
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart'
    show SyntaxHighlighterBase;
import 'package:asciidoctor/src/html5.dart' show Html5Converter;
import 'package:asciidoctor/src/logging.dart'
    show LoggerBase, LoggerManager, NullLogger;
import 'package:asciidoctor/src/path_resolver.dart' show PathResolver;
import 'package:asciidoctor/src/rx.dart' show escapedSpaceRx, spaceDelimiterRx;
import 'package:asciidoctor/src/stylesheets.dart' show Stylesheets;
import 'package:asciidoctor/src/timings.dart' show Timings;

/// Parses the AsciiDoc source [input] into a [Document].
///
/// See the library documentation for the accepted [input] types. Unless
/// `options['parse']` is `false`, the document is parsed before it is
/// returned. Failures are re-raised with an
/// `asciidoctor: FAILED: <file>: Failed to load AsciiDoc document - ...`
/// message prefix, preserving the error type where possible (mirroring
/// Ruby's same-class re-wrap); [UnimplementedError] — the port's not-yet-
/// ported signal — always propagates unchanged.
Document load(Object? input, [Map<String, Object?>? options]) {
  // Reproduces Ruby's lazy-`require` side effect (converters become
  // available once the API is used). Idempotent; the manpage converter has
  // no registration yet (TASK-g1gk6g).
  Html5Converter.registerFor();
  Docbook5Converter.registerFor();
  final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
  var attrs = <String, Object?>{};
  try {
    final timings = opts['timings'];
    if (timings is Timings) timings.start('read');

    if (opts.containsKey('logger') && opts['logger'] != LoggerManager.logger) {
      final replacement = opts['logger'];
      LoggerManager.logger = (replacement == null || replacement == false)
          ? NullLogger()
          : replacement as LoggerBase;
    }

    attrs = _coerceAttributes(opts['attributes']);

    Object? source;
    if (input is File) {
      opts['input_mtime'] = input.lastModifiedSync();
      final inputPath = _absolutePath(input.path);
      attrs['docfile'] = inputPath;
      attrs['docdir'] = _dirname(inputPath);
      final docfilesuffix = Helpers.extname(inputPath) ?? '';
      attrs['docfilesuffix'] = docfilesuffix;
      attrs['docname'] = Helpers.basename(inputPath, docfilesuffix);
      source = _readFileString(input);
    } else if (input is RandomAccessFile) {
      source = _readRandomAccessString(input);
    } else if (input is String) {
      source = input;
    } else if (input is List<Object?>) {
      source = List.of(input);
    } else if (input == null || input == false) {
      source = null;
    } else {
      throw ArgumentError('unsupported input type: ${input.runtimeType}');
    }

    if (timings is Timings) {
      timings
        ..record('read')
        ..start('parse');
    }

    opts['attributes'] = attrs;
    final doc = opts['parse'] == false
        ? Document(source, opts)
        : Document(source, opts).parse();
    if (timings is Timings) timings.record('parse');
    return doc;
  } catch (e, st) {
    if (e is UnimplementedError) rethrow;
    final context =
        "asciidoctor: FAILED: ${attrs['docfile'] ?? '<stdin>'}: "
        'Failed to load AsciiDoc document';
    Error.throwWithStackTrace(_withContext(e, context), st);
  }
}

/// Parses the AsciiDoc source file at [filename] into a [Document].
///
/// [filename] is a [String] path, a [File], or a [Uri]. The file is opened
/// eagerly so that open errors (missing file, directory, permissions)
/// propagate unwrapped, as Ruby's `File.open` block does.
Document loadFile(Object? filename, [Map<String, Object?>? options]) {
  final file = File(_filenameToPath(filename));
  _probeReadable(file);
  return load(file, options);
}

/// Parses the AsciiDoc source [input] into a [Document] and converts it to
/// the specified backend format.
///
/// When the output is written to a file (or stream), the [Document] is
/// returned; otherwise the converted [String] is returned. A `'to_file'` of
/// `'/dev/null'` loads and returns the [Document] without converting.
///
/// See [load] for the accepted [input] types. `options['to_dir']`,
/// `options['to_file']` and `options['mkdirs']` control the output target;
/// `options['parse']` is always ignored (conversion implies parsing).
Object? convert(Object? input, [Map<String, Object?>? options]) {
  final opts = (Map<String, Object?>.of(options ?? const <String, Object?>{}))
    ..remove('parse');
  var toDir = opts.remove('to_dir');
  if (toDir is File || toDir is Uri) toDir = _coercePath(toDir);
  final mkdirs = opts.remove('mkdirs');
  var toFile = opts.remove('to_file');

  String? siblingPath;
  Object? writeToTarget;
  Object? streamOutput;

  if (toFile == true || toFile == null) {
    if (isTruthy(toDir)) {
      writeToTarget = toDir;
    } else if (input is File) {
      siblingPath = _absolutePath(input.path);
    }
    toFile = null;
  } else if (toFile == false) {
    toFile = null;
  } else if (toFile == '/dev/null') {
    return load(input, opts);
  } else if (toFile is StringSink) {
    streamOutput = toFile;
  } else {
    if (toFile is File || toFile is Uri) toFile = _coercePath(toFile);
    writeToTarget = toFile;
    opts['to_file'] = toFile;
  }

  if (!opts.containsKey('standalone')) {
    if (siblingPath != null || isTruthy(writeToTarget)) {
      opts['standalone'] = opts.containsKey('header_footer')
          ? opts['header_footer']
          : true;
    } else if (opts.containsKey('header_footer')) {
      opts['standalone'] = opts['header_footer'];
    }
  }

  // NOTE outfile may be controlled by document attributes, so the outfile is
  // resolved only after loading.
  String? outdir;
  if (siblingPath != null) {
    outdir = _dirname(siblingPath);
    opts['to_dir'] = outdir;
  } else if (isTruthy(writeToTarget)) {
    if (isTruthy(toDir)) {
      if (isTruthy(toFile)) {
        outdir = _dirname(_expandPath(toFile, toDir));
        opts['to_dir'] = outdir;
      } else {
        outdir = _expandPath(toDir);
        opts['to_dir'] = outdir;
      }
    } else if (isTruthy(toFile)) {
      outdir = _dirname(_expandPath(toFile));
      opts['to_dir'] = outdir;
    }
  }

  // NOTE the 'to_dir' option is always set when outputting to a file.
  // NOTE the 'to_file' option is only passed if assigned an explicit path.
  final doc = load(input, opts);

  Object? outfile;
  if (siblingPath != null) {
    // Write to a file in the same directory.
    final siblingOutfile = _joinPath(
      outdir!,
      '${doc.attributes['docname'] ?? ''}${doc.outfilesuffix ?? ''}',
    );
    outfile = siblingOutfile;
    if (outfile == siblingPath) {
      throw FileSystemException(
        'input file and output file cannot be the same: $outfile',
        siblingOutfile,
      );
    }
  } else if (isTruthy(writeToTarget)) {
    // Write to an explicit file or directory.
    final workingDir = opts.containsKey('base_dir')
        ? _expandPath(opts['base_dir'])
        : Directory.current.path;
    // QUESTION should the jail be the working_dir or doc.base_dir???
    final jail = doc.safe >= SafeMode.safe ? workingDir : null;
    if (isTruthy(toDir)) {
      outdir = doc.normalizeSystemPath(
        toDir! as String,
        start: workingDir,
        jail: jail,
        targetName: 'to_dir',
        recover: false,
      );
      if (isTruthy(toFile)) {
        final resolvedOutfile = doc.normalizeSystemPath(
          toFile! as String,
          start: outdir,
          targetName: 'to_dir',
          recover: false,
        );
        outfile = resolvedOutfile;
        // Reestablish outdir as the final target directory (in the case
        // to_file had directory segments).
        outdir = _dirname(resolvedOutfile);
      } else {
        outfile = _joinPath(
          outdir,
          "${doc.attributes['docname'] ?? ''}${doc.outfilesuffix ?? ''}",
        );
      }
    } else if (isTruthy(toFile)) {
      final resolvedOutfile = doc.normalizeSystemPath(
        toFile! as String,
        start: workingDir,
        jail: jail,
        targetName: 'to_dir',
        recover: false,
      );
      outfile = resolvedOutfile;
      // Establish outdir as the final target directory (in the case to_file
      // had directory segments).
      outdir = _dirname(resolvedOutfile);
    }

    if (input is File && outfile == _absolutePath(input.path)) {
      throw FileSystemException(
        'input file and output file cannot be the same: $outfile',
        outfile as String?,
      );
    }

    if (isTruthy(mkdirs)) {
      Helpers.mkdirP(outdir!);
    } else if (!Directory(outdir!).existsSync()) {
      // NOTE the directory is intentionally reported as it was passed.
      throw FileSystemException(
        'target directory does not exist: ${toDir ?? ''} '
        '(hint: set :mkdirs option)',
        outdir,
      );
    }
  } else {
    // Write to a stream (or return the output string).
    outfile = toFile;
    outdir = null;
  }

  final Object? output;
  if (outfile != null && streamOutput == null) {
    output = doc.convert({'outfile': outfile, 'outdir': outdir});
  } else {
    output = doc.convert();
  }

  if (outfile != null) {
    doc.write(output, outfile);

    // NOTE document cannot control this behavior if safe >= SafeMode.server.
    // NOTE skip if stylesdir is a URI.
    final stylesdir = doc.attr('stylesdir');
    if (streamOutput == null &&
        doc.safe < SafeMode.secure &&
        doc.hasAttr('linkcss') &&
        doc.hasAttr('copycss') &&
        doc.basebackend('html') &&
        !(isTruthy(stylesdir) &&
            stylesdir is String &&
            Helpers.isUriish(stylesdir))) {
      final stylesheet = doc.attr('stylesheet');
      var copyAsciidoctorStylesheet = false;
      var copyUserStylesheet = false;
      if (defaultStylesheetKeys.contains(stylesheet)) {
        copyAsciidoctorStylesheet = true;
      } else if (stylesheet is String && !Helpers.isUriish(stylesheet)) {
        copyUserStylesheet = true;
      }
      final syntaxHl = doc.syntaxHighlighter;
      final hlAdapter = syntaxHl is SyntaxHighlighterBase ? syntaxHl : null;
      final copySyntaxHlStylesheet =
          hlAdapter?.wantsStylesheetFile(doc) ?? false;
      if (copyAsciidoctorStylesheet ||
          copyUserStylesheet ||
          copySyntaxHlStylesheet) {
        final stylesoutdir = doc.normalizeSystemPath(
          stylesdir as String?,
          start: outdir,
          jail: doc.safe >= SafeMode.safe ? outdir : null,
        );
        if (isTruthy(mkdirs)) {
          Helpers.mkdirP(stylesoutdir);
        } else if (!Directory(stylesoutdir).existsSync()) {
          throw FileSystemException(
            'target stylesheet directory does not exist: $stylesoutdir '
            '(hint: set :mkdirs option)',
            stylesoutdir,
          );
        }

        if (copyAsciidoctorStylesheet) {
          Stylesheets.instance.writePrimaryStylesheet(stylesoutdir);
        } else if (copyUserStylesheet) {
          final copycss = doc.attr('copycss');
          final String stylesheetSrc;
          if (copycss == '' || copycss == true) {
            stylesheetSrc = doc.normalizeSystemPath(stylesheet! as String);
          } else {
            // NOTE in this case, copycss is a source location (but cannot
            // be a URI).
            stylesheetSrc = doc.normalizeSystemPath(_coercePath(copycss));
          }
          final stylesheetDest = doc.normalizeSystemPath(
            stylesheet! as String,
            start: stylesoutdir,
            jail: doc.safe >= SafeMode.safe ? outdir : null,
          );
          // NOTE don't warn if src can't be read and dest already exists.
          if (stylesheetSrc != stylesheetDest) {
            final stylesheetData = doc.readAsset(
              stylesheetSrc,
              warnOnFailure: !File(stylesheetDest).existsSync(),
              label: 'stylesheet',
            );
            if (stylesheetData != null) {
              final stylesheetOutdir = _dirname(stylesheetDest);
              if (stylesheetOutdir != stylesoutdir &&
                  !Directory(stylesheetOutdir).existsSync()) {
                if (!isTruthy(mkdirs)) {
                  throw FileSystemException(
                    'target stylesheet directory does not exist: $stylesoutdir '
                    '(hint: set :mkdirs option)',
                    stylesoutdir,
                  );
                }
                Helpers.mkdirP(stylesheetOutdir);
              }
              File(stylesheetDest).writeAsStringSync(stylesheetData);
            }
          }
        }
        if (copySyntaxHlStylesheet && hlAdapter != null) {
          hlAdapter.writeStylesheet(doc, stylesoutdir);
        }
      }
    }
    return doc;
  }
  return output;
}

/// Parses the AsciiDoc source file at [filename] into a [Document] and
/// converts it to the specified backend format.
///
/// [filename] is a [String] path, a [File], or a [Uri]. Returns the
/// [Document] when the output is written to a file (or stream), else the
/// converted [String]. See [convert] for details.
Object? convertFile(Object? filename, [Map<String, Object?>? options]) {
  final file = File(_filenameToPath(filename));
  _probeReadable(file);
  return convert(file, options);
}

/// Opens [file] eagerly so that open errors (missing file, directory,
/// permissions) propagate unwrapped, as Ruby's `File.open` block does
/// (`lib/asciidoctor/convert.rb`, `convert_file`).
///
/// Named pipes are exempt: Ruby opens the handle once and reads from it,
/// while an eager probe here would consume the writer rendezvous and leave
/// the real read in [load] blocked forever.
void _probeReadable(File file) {
  try {
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.pipe) {
      return;
    }
  } on Exception catch (_) {
    // Fall through to the probe, which raises the InvalidPath error.
  }
  file.openSync().closeSync();
}

/// Coerces the `'attributes'` option [value] to a fresh attribute map.
///
/// Accepts `null` (yields `{}`), a [Map] (copied), a [List] of `k=v` entries,
/// a [String] of blank-separated `k=v` entries (with `\`-escaped blanks kept
/// literal), or a duck-typed map exposing `keys` and `[]` (a [Function]
/// `keys` is invoked). Anything else raises an [ArgumentError].
Map<String, Object?> _coerceAttributes(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  if (value is List<Object?>) {
    final attrs = <String, Object?>{};
    for (final entry in value) {
      _assignAttributeEntry(attrs, entry! as String);
    }
    return attrs;
  }
  if (value is String) {
    final attrs = <String, Object?>{};
    for (final entry in _splitAttributeEntries(value)) {
      _assignAttributeEntry(attrs, entry);
    }
    return attrs;
  }
  // Duck-typed map (port of the `respond_to?(:keys)` branch).
  try {
    final dynamic keys = (value as dynamic).keys;
    final resolvedKeys = keys is Function ? keys() : keys;
    final attrs = <String, Object?>{};
    for (final key in resolvedKeys as Iterable<Object?>) {
      attrs[key.toString()] = (value as dynamic)[key];
    }
    return attrs;
    // Duck-type probe (port of `respond_to?(:keys)`): Dart has no
    // respond_to?, so NoSuchMethodError is the probe signal.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    throw ArgumentError(
      'illegal type for attributes option: ${value.runtimeType}',
    );
  }
}

/// Assigns the `k=v` [entry] into [attrs] (a bare `k` assigns `''`).
///
/// Mirrors Ruby's `partition '='` (and the identical `-a` parsing in
/// `cli/options.rb`, consulted read-only).
void _assignAttributeEntry(Map<String, Object?> attrs, String entry) {
  final idx = entry.indexOf('=');
  if (idx == -1) {
    attrs[entry] = '';
  } else {
    attrs[entry.substring(0, idx)] = entry.substring(idx + 1);
  }
}

/// Splits an attributes [String] into `k=v` entries.
///
/// Condenses unescaped blanks to [nullChar], unescapes `\`-escaped blanks,
/// then splits; trailing empty fields are dropped, as Ruby's `split` does.
List<String> _splitAttributeEntries(String value) {
  final condensed = value
      .replaceAllMapped(spaceDelimiterRx, (m) => '${m.group(1)}$nullChar')
      .replaceAllMapped(escapedSpaceRx, (m) => m.group(1)!);
  if (condensed.isEmpty) return <String>[];
  final entries = condensed.split(nullChar);
  var end = entries.length;
  while (end > 0 && entries[end - 1].isEmpty) {
    end--;
  }
  return entries.sublist(0, end);
}

/// Reads [file] as UTF-8, strictly.
///
/// Undecodable bytes raise Ruby's invalid-data [ArgumentError] (normally
/// raised by the reader, which only ever sees valid Dart strings).
String _readFileString(File file) {
  final bytes = file.readAsBytesSync();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw ArgumentError(
      'source is either binary or contains invalid Unicode data',
    );
  }
}

/// Rewinds [input] and reads it fully as UTF-8, strictly.
String _readRandomAccessString(RandomAccessFile input) {
  input.setPositionSync(0);
  final length = input.lengthSync();
  final bytes = <int>[];
  while (bytes.length < length) {
    final chunk = input.readSync(length - bytes.length);
    if (chunk.isEmpty) break;
    bytes.addAll(chunk);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw ArgumentError(
      'source is either binary or contains invalid Unicode data',
    );
  }
}

/// Coerces a [loadFile]/[convertFile] [filename] to a path string.
String _filenameToPath(Object? filename) {
  if (filename is String) return filename;
  if (filename is File) return filename.path;
  if (filename is Uri) return filename.toFilePath();
  throw ArgumentError.value(
    filename,
    'filename',
    'must be a String path, a File, or a Uri',
  );
}

/// Coerces a path-like [value] ([String], [File], [Uri]) to a path string.
///
/// Anything else raises a [TypeError], as Ruby's `File.expand_path` does for
/// values without a path conversion.
String _coercePath(Object? value) {
  if (value is String) return value;
  if (value is File) return value.path;
  if (value is Uri) return value.toFilePath();
  return value! as String;
}

/// Returns the absolute form of [path] (port of `File.absolute_path`).
///
/// Like Ruby, `.` and `..` segments are resolved lexically (unlike
/// [File.absolute], which merely prefixes the working directory).
String _absolutePath(String path) => _expandPath(path);

/// Expands [path] against [base] (default: working directory).
///
/// Port of `File.expand_path` (including the `to_path` coercions).
String _expandPath(Object? path, [Object? base]) {
  final target = _coercePath(path);
  final resolver = PathResolver();
  if (resolver.isRoot(target)) return resolver.expandPath(target);
  var start = base == null ? Directory.current.path : _coercePath(base);
  if (start.length > 1) start = start.replaceAll(RegExp(r'/+$'), '');
  return resolver.expandPath(resolver.joinPath([start, target]));
}

/// Returns the directory name of posix [path] (port of `File.dirname`).
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

/// Joins [parent] and [child] with `/` (port of `File.join`).
String _joinPath(String parent, String child) {
  final base = parent.endsWith('/')
      ? parent.substring(0, parent.length - 1)
      : parent;
  return '$base/$child';
}

/// Re-wraps [error] with the load-failure [context] message.
///
/// Known error types are reconstructed with the prefixed message (mirroring
/// Ruby's same-class re-wrap); anything else is returned unchanged (mirroring
/// Ruby's fallback when wrapping fails).
Object _withContext(Object error, String context) {
  if (error is ArgumentError) {
    return ArgumentError('$context - ${error.message}');
  }
  if (error is StateError) {
    return StateError('$context - ${error.message}');
  }
  if (error is FormatException) {
    return FormatException(
      '$context - ${error.message}',
      error.source,
      error.offset,
    );
  }
  if (error is FileSystemException) {
    return FileSystemException(
      '$context - ${error.message}',
      error.path,
      error.osError,
    );
  }
  return error;
}
