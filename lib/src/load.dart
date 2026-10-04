/// Top-level load and convert entry points.
///
/// Port of `lib/asciidoctor/load.rb` ([load], [loadFile]) and
/// `lib/asciidoctor/convert.rb` ([convert], [convertFile]).
///
/// * [load] and [loadFile] parse AsciiDoc into a [Document].
/// * [convert] converts AsciiDoc source to a string.
/// * [convertFile] converts a file and writes the result next to it, to the
///   `toFile`/`toDir` targets in the options, or to an output sink.
/// * [convertToTarget] converts AsciiDoc source and writes the result to
///   the `toFile`/`toDir` targets in the options or to an output sink.
library;

import 'dart:convert' show utf8;

import 'package:asciidoctor/src/abstract_node.dart' show SafeMode;
import 'package:asciidoctor/src/constants.dart' show defaultStylesheetKeys;
import 'package:asciidoctor/src/docbook5.dart' show Docbook5Converter;
import 'package:asciidoctor/src/document.dart' show Document;
import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/helpers.dart' show Helpers;
import 'package:asciidoctor/src/html5.dart' show Html5Converter;
import 'package:asciidoctor/src/http_fetch.dart' show fetchHttp;
import 'package:asciidoctor/src/io.dart' as io;
import 'package:asciidoctor/src/logging.dart' show LoggerManager;
import 'package:asciidoctor/src/options.dart';
import 'package:asciidoctor/src/path_resolver.dart' show PathResolver;
import 'package:asciidoctor/src/remote.dart';
import 'package:asciidoctor/src/stylesheets.dart' show Stylesheets;
import 'package:meta/meta.dart';

/// Parses the AsciiDoc [source] (an empty document when `null`) into a
/// [Document].
///
/// Unless [parse] is `false`, the document is parsed before it is
/// returned.
Document load(
  String? source, {
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool parse = true,
}) => _load(_Input.text(source), options, parse: parse);

/// Parses the AsciiDoc file at [path] into a [Document].
///
/// The `docfile`, `docdir`, `docfilesuffix` and `docname` attributes are
/// set from [path], and the file's modification time feeds `docdate`.
/// Unless [parse] is `false`, the document is parsed before it is
/// returned.
Document loadFile(
  String path, {
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool parse = true,
}) {
  _probeReadable(path);
  return _load(_Input.file(path), options, parse: parse);
}

/// Converts the AsciiDoc [source] (an empty document when `null`) and
/// returns the result.
///
/// The output is embedded (no header and footer) unless
/// [AsciidoctorOptions.standalone] is set. The `toFile` and `toDir` options
/// do not apply (see [convertToTarget]).
String convert(
  String? source, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) {
  if (options.toFile != null || options.toDir != null) {
    throw ArgumentError(
      'convert returns the output; use convertToTarget to write it to a file',
    );
  }
  return _load(_Input.text(source), options).convert();
}

/// Converts the AsciiDoc file at [path] and writes the result.
///
/// The output goes to [output] when given; otherwise to
/// [AsciidoctorOptions.toFile] (relative to [AsciidoctorOptions.toDir],
/// else the working directory), else into [AsciidoctorOptions.toDir], else
/// next to the input file, named after it with the backend's file
/// extension. A `toFile` of `/dev/null` loads the document without
/// converting it. Output written to a file is standalone unless
/// [AsciidoctorOptions.standalone] is `false`.
///
/// Returns the document.
Document convertFile(
  String path, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  StringSink? output,
]) {
  _probeReadable(path);
  return _convert(_Input.file(path), options, output);
}

/// Converts the AsciiDoc [source] (an empty document when `null`) and
/// writes the result to [output] when given, else to the
/// [AsciidoctorOptions.toFile] and [AsciidoctorOptions.toDir] targets (see
/// [convertFile]), one of which is then required.
///
/// Returns the document.
Document convertToTarget(
  String? source, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  StringSink? output,
]) {
  if (output == null && options.toFile == null && options.toDir == null) {
    throw ArgumentError(
      'convertToTarget needs an output sink or a toFile or toDir option',
    );
  }
  return _convert(_Input.text(source), options, output);
}

/// Like [load], reading remote content with [fetch].
///
/// When the `allow-uri-read` attribute is set, the remote content the
/// document needs (includes, assets read from a URI) is fetched with
/// [fetch] (an HTTP GET by default) and supplied through
/// [AsciidoctorOptions.uriReader]; see [convertAsync].
Future<Document> loadAsync(
  String? source, {
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool parse = true,
  UriFetcher fetch = fetchHttp,
}) async {
  final input = _Input.text(source);
  final reader = await _prefetch(input, options, fetch, convert: false);
  return _load(input, options.copyWith(uriReader: reader), parse: parse);
}

/// Like [loadFile], reading remote content with [fetch] (see [loadAsync]).
Future<Document> loadFileAsync(
  String path, {
  AsciidoctorOptions options = const AsciidoctorOptions(),
  bool parse = true,
  UriFetcher fetch = fetchHttp,
}) async {
  _probeReadable(path);
  final input = _Input.file(path);
  final reader = await _prefetch(input, options, fetch, convert: false);
  return _load(input, options.copyWith(uriReader: reader), parse: parse);
}

/// Like [convert], reading remote content with [fetch].
///
/// When the `allow-uri-read` attribute is set, the document is converted
/// once silently to find the remote content it reads (includes, images
/// embedded as data URIs, stylesheets and other assets read from a URI),
/// which is fetched with [fetch] (an HTTP GET by default); this repeats until
/// no new content is needed, since fetched content can refer to more.
/// The document is then converted for real with the fetched content
/// supplied through [AsciidoctorOptions.uriReader]. Content that cannot be
/// fetched is reported as unreadable, as in the synchronous API.
///
/// With the `cache-uri` attribute set, fetched content is kept for later
/// conversions in the same process.
Future<String> convertAsync(
  String? source, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  UriFetcher fetch = fetchHttp,
]) async {
  final reader = await _prefetch(_Input.text(source), options, fetch);
  return convert(source, options.copyWith(uriReader: reader));
}

/// Like [convertFile], reading remote content with [fetch] (see
/// [convertAsync]).
Future<Document> convertFileAsync(
  String path, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  StringSink? output,
  UriFetcher fetch = fetchHttp,
]) async {
  _probeReadable(path);
  final reader = await _prefetch(_Input.file(path), options, fetch);
  return convertFile(path, options.copyWith(uriReader: reader), output);
}

/// Like [convertToTarget], reading remote content with [fetch] (see
/// [convertAsync]).
Future<Document> convertToTargetAsync(
  String? source, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
  StringSink? output,
  UriFetcher fetch = fetchHttp,
]) async {
  final reader = await _prefetch(_Input.text(source), options, fetch);
  return convertToTarget(source, options.copyWith(uriReader: reader), output);
}

/// Fetches the remote content that converting the AsciiDoc file at [path]
/// (or [source], when [path] is `null`) reads into [cache], by URI (`null`
/// for content that could not be fetched); see [convertAsync].
///
/// For the CLI, which converts several inputs with one [cachedUriReader].
@internal
Future<void> prefetchRemoteContent(
  AsciidoctorOptions options,
  Map<String, RemoteResource?> cache, {
  String? path,
  String? source,
  UriFetcher fetch = fetchHttp,
}) async {
  final input = path == null ? _Input.text(source) : _Input.file(path);
  if (path != null) _probeReadable(path);
  await _prefetch(input, options, fetch, cache: cache);
}

/// A reader serving the remote content in [cache] (filled by
/// [prefetchRemoteContent]).
@internal
UriReader cachedUriReader(Map<String, RemoteResource?> cache) =>
    (uri) => cache[uri] ?? (throw AsciidoctorException('cannot read $uri'));

/// Remote content kept across conversions for documents that set the
/// `cache-uri` attribute, by URI (`null` for content that failed).
final Map<String, RemoteResource?> _sharedUriCache = {};

/// The most discovery passes run for one document; each pass fetches at
/// least one new URI, so this bounds documents that keep naming new ones.
const int _maxDiscoveryPasses = 32;

/// Finds and fetches the remote content [input] reads, returning a reader
/// that serves it.
///
/// Runs silent discovery passes (parsing, and converting unless [convert]
/// is `false`) with a reader that records the URIs it is asked for, then
/// fetches the new ones, until a pass asks for nothing new. A
/// [AsciidoctorOptions.uriReader] given by the caller is consulted first.
Future<UriReader> _prefetch(
  _Input input,
  AsciidoctorOptions options,
  UriFetcher fetch, {
  bool convert = true,
  Map<String, RemoteResource?>? cache,
}) async {
  final fetched = cache ?? <String, RemoteResource?>{};
  final callerReader = options.uriReader;
  RemoteResource read(String uri, Set<String> missing) {
    if (callerReader != null) {
      try {
        return callerReader(uri);
      } on Exception {
        // Fall back to fetching.
      }
    }
    if (!fetched.containsKey(uri)) {
      missing.add(uri);
      throw AsciidoctorException('cannot read $uri: not fetched yet');
    }
    return fetched[uri] ??
        (throw AsciidoctorException('cannot read $uri: fetch failed'));
  }

  final savedLogger = LoggerManager.logger;
  try {
    for (var pass = 0; pass < _maxDiscoveryPasses; pass++) {
      final missing = <String>{};
      final Document doc;
      try {
        doc = _load(input, options.forDiscovery((uri) => read(uri, missing)));
        if (convert) doc.convert();
      } on Object {
        // The real run reports the failure.
        break;
      }
      if (missing.isEmpty) break;
      final shared = doc.hasAttr('cache-uri');
      await Future.wait([
        for (final uri in missing)
          if (shared && _sharedUriCache.containsKey(uri))
            Future<void>.sync(() => fetched[uri] = _sharedUriCache[uri])
          else
            _fetchInto(fetched, uri, fetch, shared: shared),
      ]);
    }
  } finally {
    LoggerManager.logger = savedLogger;
  }
  RemoteResource readFetched(String uri) => read(uri, <String>{});
  return readFetched;
}

/// Fetches [uri] with [fetch] into [fetched] (`null` on failure), and into
/// the shared cache when [shared] is set.
Future<void> _fetchInto(
  Map<String, RemoteResource?> fetched,
  String uri,
  UriFetcher fetch, {
  required bool shared,
}) async {
  RemoteResource? resource;
  try {
    resource = await fetch(Uri.parse(uri));
    // A failed fetch is reported as unreadable content by the real run.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    resource = null;
  }
  fetched[uri] = resource;
  if (shared) _sharedUriCache[uri] = resource;
}

/// The source of a document: AsciiDoc text or a file.
final class _Input {
  const new text(this.text) : file = null;
  const new file(String this.file) : text = null;

  final String? text;

  /// The path of the input file.
  final String? file;
}

Document _load(_Input input, AsciidoctorOptions options, {bool parse = true}) {
  // Make the built-in converters available (idempotent).
  Html5Converter.registerFor();
  Docbook5Converter.registerFor();
  String? docfile;
  try {
    final timings = options.timings;
    timings?.start('read');

    final logger = options.logger;
    if (logger != null && logger != LoggerManager.logger) {
      LoggerManager.logger = logger;
    }

    var opts = options;
    final String? source;
    final file = input.file;
    if (file != null) {
      final inputPath = docfile = _expandPath(file);
      final docfilesuffix = Helpers.extname(inputPath) ?? '';
      opts = opts.copyWith(
        inputMtime: io.modificationTime(file),
        attributes: <String, String?>{
          ...opts.attributes,
          'docfile': inputPath,
          'docdir': _dirname(inputPath),
          'docfilesuffix': docfilesuffix,
          'docname': Helpers.basename(inputPath, dropSuffix: docfilesuffix),
        },
      );
      source = _readFileString(file);
    } else {
      source = input.text;
    }

    timings
      ?..record('read')
      ..start('parse');

    var doc = Document(source, opts);
    if (parse) doc = doc.parse();
    timings?.record('parse');
    return doc;
  } catch (e, st) {
    final context = 'failed to load ${docfile ?? '<stdin>'}';
    Error.throwWithStackTrace(_withContext(e, context), st);
  }
}

Document _convert(
  _Input input,
  AsciidoctorOptions options,
  StringSink? output,
) {
  final toDir = options.toDir;
  final mkdirs = options.mkdirs;
  final toFile = options.toFile;

  if (toFile == '/dev/null' && output == null) {
    return _load(input, options.withTargets());
  }

  final inputFile = input.file;
  final String? siblingPath;
  final bool writeToTarget;
  if (output != null) {
    siblingPath = null;
    writeToTarget = false;
  } else if (toFile != null || toDir != null) {
    siblingPath = null;
    writeToTarget = true;
  } else {
    siblingPath = _expandPath(inputFile!);
    writeToTarget = false;
  }

  var opts = options;
  if (opts.standalone == null && (siblingPath != null || writeToTarget)) {
    opts = opts.copyWith(standalone: true);
  }

  // NOTE outfile may be controlled by document attributes, so the outfile is
  // resolved only after loading.
  String? outdir;
  if (siblingPath != null) {
    outdir = _dirname(siblingPath);
  } else if (writeToTarget) {
    if (toDir != null) {
      outdir = toFile != null
          ? _dirname(_expandPath(toFile, toDir))
          : _expandPath(toDir);
    } else {
      outdir = _dirname(_expandPath(toFile!));
    }
  }

  // NOTE the toDir option is always set when outputting to a file.
  final doc = _load(
    input,
    opts.withTargets(toFile: writeToTarget ? toFile : null, toDir: outdir),
  );

  String? outfile;
  if (siblingPath != null) {
    // Write to a file in the same directory.
    outfile = _joinPath(
      outdir!,
      '${doc.attributes['docname'] ?? ''}${doc.outfilesuffix ?? ''}',
    );
    if (outfile == siblingPath) {
      throw AsciidoctorException(
        'input file and output file cannot be the same: $outfile',
      );
    }
  } else if (writeToTarget) {
    // Write to an explicit file or directory.
    final baseDir = opts.baseDir;
    final workingDir = baseDir != null
        ? _expandPath(baseDir)
        : io.currentDirectory;
    // QUESTION should the jail be the working_dir or doc.base_dir???
    final jail = doc.safe >= SafeMode.safe ? workingDir : null;
    if (toDir != null) {
      outdir = doc.normalizeSystemPath(
        toDir,
        start: workingDir,
        jail: jail,
        targetName: 'to_dir',
        recover: false,
      );
      if (toFile != null) {
        final resolvedOutfile = outfile = doc.normalizeSystemPath(
          toFile,
          start: outdir,
          targetName: 'to_dir',
          recover: false,
        );
        // Reestablish outdir as the final target directory (in the case
        // toFile had directory segments).
        outdir = _dirname(resolvedOutfile);
      } else {
        outfile = _joinPath(
          outdir,
          '${doc.attributes['docname'] ?? ''}${doc.outfilesuffix ?? ''}',
        );
      }
    } else {
      final resolvedOutfile = outfile = doc.normalizeSystemPath(
        toFile,
        start: workingDir,
        jail: jail,
        targetName: 'to_dir',
        recover: false,
      );
      // Establish outdir as the final target directory (in the case toFile
      // had directory segments).
      outdir = _dirname(resolvedOutfile);
    }

    if (inputFile != null && outfile == _expandPath(inputFile)) {
      throw AsciidoctorException(
        'input file and output file cannot be the same: $outfile',
      );
    }

    if (mkdirs) {
      Helpers.mkdirP(outdir);
    } else if (!io.isDirectory(outdir)) {
      // NOTE the directory is intentionally reported as it was passed.
      throw AsciidoctorException(
        'target directory does not exist: ${toDir ?? outdir} '
        '(set the mkdirs option to create it)',
      );
    }
  }

  if (output != null) {
    doc.writeTo(doc.convert(), output);
    return doc;
  }

  final converted = doc.convert(outfile: outfile, outdir: outdir);
  doc.writeFile(converted, outfile!);
  _copyStylesheets(doc, outdir!, mkdirs: mkdirs);
  return doc;
}

/// Copies the stylesheets a document written to [outdir] links to, when
/// the `linkcss` and `copycss` attributes ask for it.
void _copyStylesheets(Document doc, String outdir, {required bool mkdirs}) {
  // NOTE document cannot control this behavior if safe >= SafeMode.server.
  // NOTE skip if stylesdir is a URI.
  final stylesdir = doc.attr('stylesdir');
  if (doc.safe >= SafeMode.secure ||
      !doc.hasAttr('linkcss') ||
      !doc.hasAttr('copycss') ||
      !doc.basebackend('html') ||
      (stylesdir != null && Helpers.isUriish(stylesdir))) {
    return;
  }
  final stylesheet = doc.attr('stylesheet');
  var copyAsciidoctorStylesheet = false;
  var copyUserStylesheet = false;
  if (defaultStylesheetKeys.contains(stylesheet)) {
    copyAsciidoctorStylesheet = true;
  } else if (stylesheet != null && !Helpers.isUriish(stylesheet)) {
    copyUserStylesheet = true;
  }
  final syntaxHl = doc.syntaxHighlighter;
  final copySyntaxHlStylesheet = syntaxHl?.wantsStylesheetFile(doc) ?? false;
  if (!copyAsciidoctorStylesheet &&
      !copyUserStylesheet &&
      !copySyntaxHlStylesheet) {
    return;
  }
  final stylesoutdir = doc.normalizeSystemPath(
    stylesdir,
    start: outdir,
    jail: doc.safe >= SafeMode.safe ? outdir : null,
  );
  if (mkdirs) {
    Helpers.mkdirP(stylesoutdir);
  } else if (!io.isDirectory(stylesoutdir)) {
    throw AsciidoctorException(
      'target stylesheet directory does not exist: $stylesoutdir '
      '(set the mkdirs option to create it)',
    );
  }

  if (copyAsciidoctorStylesheet) {
    Stylesheets.instance.writePrimaryStylesheet(stylesoutdir);
  } else if (copyUserStylesheet) {
    final copycss = doc.attr('copycss');
    final String stylesheetSrc;
    if (copycss == null || copycss.isEmpty) {
      stylesheetSrc = doc.normalizeSystemPath(stylesheet);
    } else {
      // NOTE in this case, copycss is a source location (but cannot be a
      // URI).
      stylesheetSrc = doc.normalizeSystemPath(copycss);
    }
    final stylesheetDest = doc.normalizeSystemPath(
      stylesheet,
      start: stylesoutdir,
      jail: doc.safe >= SafeMode.safe ? outdir : null,
    );
    // NOTE don't warn if src can't be read and dest already exists.
    if (stylesheetSrc != stylesheetDest) {
      final stylesheetData = doc.readAsset(
        stylesheetSrc,
        warnOnFailure: !io.isFile(stylesheetDest),
        label: 'stylesheet',
      );
      if (stylesheetData != null) {
        final stylesheetOutdir = _dirname(stylesheetDest);
        if (stylesheetOutdir != stylesoutdir &&
            !io.isDirectory(stylesheetOutdir)) {
          if (!mkdirs) {
            throw AsciidoctorException(
              'target stylesheet directory does not exist: $stylesoutdir '
              '(set the mkdirs option to create it)',
            );
          }
          Helpers.mkdirP(stylesheetOutdir);
        }
        io.writeString(stylesheetDest, stylesheetData);
      }
    }
  }
  if (copySyntaxHlStylesheet) syntaxHl!.writeStylesheet(doc, stylesoutdir);
}

/// Opens the file at [path] eagerly so that open errors (missing file,
/// directory, permissions) propagate unwrapped.
///
/// Named pipes are exempt: an eager probe would consume the writer
/// rendezvous and leave the real read blocked forever.
void _probeReadable(String path) {
  if (io.isPipe(path)) return;
  io.probeReadable(path);
}

/// Reads the file at [path] as UTF-8, strictly.
///
/// Undecodable bytes raise an [AsciidoctorException].
String _readFileString(String path) {
  final bytes = io.readBytes(path);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const AsciidoctorException(
      'source is either binary or contains invalid Unicode data',
    );
  }
}

/// Expands [path] against [base] (default: working directory).
///
/// Port of `File.expand_path`.
String _expandPath(String path, [String? base]) {
  final resolver = PathResolver();
  if (resolver.isRoot(path)) return resolver.expandPath(path);
  var start = base ?? io.currentDirectory;
  if (start.length > 1) start = start.replaceAll(RegExp(r'/+$'), '');
  return resolver.expandPath(resolver.joinPath([start, path]));
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
/// Failures caused by the input or the environment gain the context;
/// anything else (programming errors, extension failures) is returned
/// unchanged.
Object _withContext(Object error, String context) => switch (error) {
  AsciidoctorException(:final message) => AsciidoctorException(
    '$context: $message',
  ),
  io.IoException(
    :final message,
    :final path,
    :final reason,
    :final errorCode,
  ) =>
    io.IoException(
      '$context: $message',
      path: path,
      reason: reason,
      errorCode: errorCode,
    ),
  _ => error,
};
