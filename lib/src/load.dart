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
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemException;

import 'package:asciidoctor/src/abstract_node.dart' show SafeMode;
import 'package:asciidoctor/src/constants.dart' show defaultStylesheetKeys;
import 'package:asciidoctor/src/docbook5.dart' show Docbook5Converter;
import 'package:asciidoctor/src/document.dart' show Document;
import 'package:asciidoctor/src/helpers.dart' show Helpers;
import 'package:asciidoctor/src/html5.dart' show Html5Converter;
import 'package:asciidoctor/src/logging.dart' show LoggerManager;
import 'package:asciidoctor/src/options.dart';
import 'package:asciidoctor/src/path_resolver.dart' show PathResolver;
import 'package:asciidoctor/src/stylesheets.dart' show Stylesheets;

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
  final file = File(path);
  _probeReadable(file);
  return _load(_Input.file(file), options, parse: parse);
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
  final file = File(path);
  _probeReadable(file);
  return _convert(_Input.file(file), options, output);
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

/// The source of a document: AsciiDoc text or a file.
final class _Input {
  const new text(this.text) : file = null;
  const new file(File this.file) : text = null;

  final String? text;
  final File? file;
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
      final inputPath = docfile = _expandPath(file.path);
      final docfilesuffix = Helpers.extname(inputPath) ?? '';
      opts = opts.copyWith(
        inputMtime: file.lastModifiedSync(),
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
    final context =
        'asciidoctor: FAILED: ${docfile ?? '<stdin>'}: '
        'Failed to load AsciiDoc document';
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
    siblingPath = _expandPath(inputFile!.path);
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
      throw FileSystemException(
        'input file and output file cannot be the same: $outfile',
        outfile,
      );
    }
  } else if (writeToTarget) {
    // Write to an explicit file or directory.
    final baseDir = opts.baseDir;
    final workingDir = baseDir != null
        ? _expandPath(baseDir)
        : Directory.current.path;
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

    if (inputFile != null && outfile == _expandPath(inputFile.path)) {
      throw FileSystemException(
        'input file and output file cannot be the same: $outfile',
        outfile,
      );
    }

    if (mkdirs) {
      Helpers.mkdirP(outdir);
    } else if (!Directory(outdir).existsSync()) {
      // NOTE the directory is intentionally reported as it was passed.
      throw FileSystemException(
        'target directory does not exist: ${toDir ?? ''} '
        '(hint: set :mkdirs option)',
        outdir,
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
        warnOnFailure: !File(stylesheetDest).existsSync(),
        label: 'stylesheet',
      );
      if (stylesheetData != null) {
        final stylesheetOutdir = _dirname(stylesheetDest);
        if (stylesheetOutdir != stylesoutdir &&
            !Directory(stylesheetOutdir).existsSync()) {
          if (!mkdirs) {
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
  if (copySyntaxHlStylesheet) syntaxHl!.writeStylesheet(doc, stylesoutdir);
}

/// Opens [file] eagerly so that open errors (missing file, directory,
/// permissions) propagate unwrapped.
///
/// Named pipes are exempt: an eager probe would consume the writer
/// rendezvous and leave the real read blocked forever.
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

/// Reads [file] as UTF-8, strictly.
///
/// Undecodable bytes raise an invalid-data [ArgumentError].
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

/// Expands [path] against [base] (default: working directory).
///
/// Port of `File.expand_path`.
String _expandPath(String path, [String? base]) {
  final resolver = PathResolver();
  if (resolver.isRoot(path)) return resolver.expandPath(path);
  var start = base ?? Directory.current.path;
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
/// Known error types are reconstructed with the prefixed message; anything
/// else is returned unchanged.
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
