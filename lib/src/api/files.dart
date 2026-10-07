part of 'api.dart';

/// The result of converting one file with [AsciidartFiles.convertTree].
final class FileConversion {
  const new _(this.inputPath, this.outputPath, this.document);

  /// The AsciiDoc file.
  final String inputPath;

  /// The file the output was written to.
  final String outputPath;

  /// The converted document, with its diagnostics.
  final Document document;
}

/// Reading and writing files (`package:asciidart/io.dart`).
///
/// These follow the [Asciidart.safe] mode like everything else: to let a
/// document include files from below its own directory, use
/// `SafeMode.safe`; to write output outside the base directory (the
/// document's directory, unless [Asciidart.baseDir] says otherwise), or to
/// include files from anywhere, use `SafeMode.unsafe`.
extension AsciidartFiles on Asciidart {
  /// Parses the AsciiDoc file at [path].
  ///
  /// Waits for [IncludeResolver]s that return a `Future`, and fetches
  /// remote content when the `allow-uri-read` attribute is set, like
  /// [Asciidart.parseAsync].
  Future<Document> parseFile(
    String path, {
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = false,
    Map<String, String> attributes = const {},
  }) async {
    if (backend.makesFile) await loadBackend(backend);
    impl.AsciidoctorOptions optionsFor(_Includes includes) => _options(
      includes,
      backend: backend,
      doctype: doctype,
      standalone: standalone,
      attributes: attributes,
    );
    final includes = await _settleIncludes(
      optionsFor,
      (options) => impl.loadFile(path, options: options),
    );
    final options = optionsFor(includes);
    return await _withFonts(
      () => _document(
        (collector) =>
            collector.run(() => impl.loadFileAsync(path, options: options)),
      ),
    );
  }

  /// Converts the AsciiDoc file at [path] and writes the result: to
  /// [toFile] when given (relative to [toDir], if any), else into [toDir],
  /// else next to the input file, named after it with the extension of the
  /// output format (a PDF or an EPUB too). [mkdirs] creates missing output
  /// directories. The output is a complete document unless [standalone] is
  /// `false`.
  ///
  /// Returns the converted document, with its diagnostics.
  Future<Document> convertFile(
    String path, {
    String? toFile,
    String? toDir,
    bool mkdirs = false,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = true,
    Map<String, String> attributes = const {},
  }) async {
    if (backend.makesFile) await loadBackend(backend);
    impl.AsciidoctorOptions optionsFor(_Includes includes) => _options(
      includes,
      backend: backend,
      doctype: doctype,
      standalone: standalone,
      attributes: attributes,
    ).copyWith(toFile: toFile, toDir: toDir, mkdirs: mkdirs);
    final includes = await _settleIncludes(
      optionsFor,
      (options) => impl.loadFile(path, options: options),
    );
    final options = optionsFor(includes);
    return await _withFonts(
      () => _document(
        (collector) =>
            collector.run(() => impl.convertFileAsync(path, options)),
      ),
    );
  }

  /// Converts every AsciiDoc file (`*.adoc`) below [directory] into
  /// [toDir], keeping the folder structure, and reports each result as it
  /// is written.
  ///
  /// Files and folders whose names start with `_` or `.` are skipped:
  /// by convention they hold partials meant to be included, not documents
  /// of their own.
  Stream<FileConversion> convertTree(
    String directory, {
    required String toDir,
    Backend backend = Backend.html5,
    Doctype? doctype,
    Map<String, String> attributes = const {},
  }) async* {
    final separator = impl.pathSeparator;
    for (final relative in _adocFiles(directory, '')) {
      final input = '$directory$separator$relative';
      final slash = relative.lastIndexOf(separator);
      final outDir = slash < 0
          ? toDir
          : '$toDir$separator${relative.substring(0, slash)}';
      final document = await convertFile(
        input,
        toDir: outDir,
        mkdirs: true,
        backend: backend,
        doctype: doctype,
        attributes: attributes,
      );
      final suffix = document.attributes['outfilesuffix'] ?? '.html';
      final outfile =
          document.attributes['outfile'] ??
          '$outDir$separator${_stem(relative)}$suffix';
      yield FileConversion._(input, outfile, document);
    }
  }
}

/// The `*.adoc` files below [directory] (paths relative to it, under
/// [prefix]), sorted, skipping names that start with `_` or `.`.
List<String> _adocFiles(String directory, String prefix) {
  final separator = impl.pathSeparator;
  final entries = impl.listDirectory(directory)
    ..sort((a, b) => a.name.compareTo(b.name));
  return [
    for (final entry in entries)
      if (!entry.name.startsWith('_') && !entry.name.startsWith('.'))
        if (entry.isDirectory)
          ..._adocFiles(entry.path, '$prefix${entry.name}$separator')
        else if (entry.isFile && entry.name.endsWith('.adoc'))
          '$prefix${entry.name}',
  ];
}

String _stem(String relative) {
  final name = relative.substring(relative.lastIndexOf(impl.pathSeparator) + 1);
  return name.substring(0, name.length - '.adoc'.length);
}
