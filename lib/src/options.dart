/// Options for loading and converting AsciiDoc documents.
library;

import 'package:asciidoctor/src/abstract_node.dart' show SafeMode;
import 'package:asciidoctor/src/converter.dart'
    show Converter, ConverterFactory;
import 'package:asciidoctor/src/extensions.dart' show Registry;
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart'
    show SyntaxHighlighterFactory, SyntaxHighlighterFactoryFn;
import 'package:asciidoctor/src/logging.dart' show LoggerBase, NullLogger;
import 'package:asciidoctor/src/remote.dart' show UriReader;
import 'package:asciidoctor/src/template_loader.dart' show TemplateCache;
import 'package:asciidoctor/src/timings.dart' show Timings;
import 'package:meta/meta.dart';

/// How a document is loaded and converted.
///
/// Every field is optional; the defaults match Asciidoctor's API defaults
/// (for example [safe] defaults to [SafeMode.secure]).
final class AsciidoctorOptions {
  /// Creates an options object.
  const new({
    this.safe = SafeMode.secure,
    this.backend,
    this.doctype,
    this.attributes = const <String, String?>{},
    this.standalone,
    this.baseDir,
    this.toFile,
    this.toDir,
    this.mkdirs = false,
    this.sourcemap = false,
    this.timings,
    this.parseHeaderOnly = false,
    this.catalogAssets = false,
    this.converter,
    this.converterFactory,
    this.templateDirs = const <String>[],
    this.templateEngine,
    this.templateCache = true,
    this.templateCacheStore,
    this.extensions,
    this.extensionRegistry,
    this.logger,
    this.syntaxHighlighterFactory,
    this.syntaxHighlighters,
    this.inputMtime,
    this.uriReader,
  });

  /// The safe mode level (see [SafeMode]).
  final int safe;

  /// The backend to convert to (e.g. `html5`, `docbook5`, `manpage`).
  final String? backend;

  /// The document type (e.g. `article`, `book`, `manpage`).
  final String? doctype;

  /// Document attributes that override the ones defined in the document.
  ///
  /// A `null` value unsets the attribute. Name and value suffixes follow
  /// Asciidoctor: a value ending in `@` (or a name ending in `@`) lets the
  /// document override it; a name with a leading or trailing `!` unsets the
  /// attribute, and `!name@` or `name!@` unsets it softly (the document may
  /// set it again).
  final Map<String, String?> attributes;

  /// Whether to produce a standalone document (with header and footer).
  ///
  /// When `null`, conversion to a file is standalone and conversion to a
  /// string is embedded.
  final bool? standalone;

  /// The base directory for resolving relative paths (default: the
  /// directory of the input file, else the working directory).
  final String? baseDir;

  /// The output file path, relative to [toDir] or the working directory.
  ///
  /// The special value `/dev/null` loads the document without converting.
  final String? toFile;

  /// The output directory.
  final String? toDir;

  /// Whether to create missing output directories.
  final bool mkdirs;

  /// Whether to record the source location of each block.
  final bool sourcemap;

  /// Records the time spent in each processing phase, when given.
  final Timings? timings;

  /// Whether to parse only the document header.
  final bool parseHeaderOnly;

  /// Whether to catalog links and images while converting.
  final bool catalogAssets;

  /// The converter to use, overriding the one registered for the backend.
  final Converter? converter;

  /// The factory used to create the converter.
  final ConverterFactory? converterFactory;

  /// Directories containing custom converter templates.
  final List<String> templateDirs;

  /// The template engine (`mustache` or `dart`).
  final String? templateEngine;

  /// Whether to cache scanned templates across documents.
  final bool templateCache;

  /// A custom template cache, used instead of the shared one.
  final TemplateCache? templateCacheStore;

  /// Registers extensions for this document only.
  final void Function(Registry registry)? extensions;

  /// The extension registry to use for this document.
  final Registry? extensionRegistry;

  /// The logger to use while loading and converting, replacing
  /// `LoggerManager.logger` (use a `NullLogger` to silence messages).
  final LoggerBase? logger;

  /// The factory used to create the syntax highlighter.
  final SyntaxHighlighterFactory? syntaxHighlighterFactory;

  /// Syntax highlighters available to this document, by name.
  final Map<String, SyntaxHighlighterFactoryFn>? syntaxHighlighters;

  /// The modification time of the input file (feeds `docdate`).
  final DateTime? inputMtime;

  /// Reads remote content when the `allow-uri-read` attribute is set:
  /// includes, images embedded as data URIs and stylesheets or other
  /// assets read from a URI.
  ///
  /// Without a reader, remote content is unavailable and the conversion
  /// warns as for any unreadable content. The asynchronous entry points
  /// (`loadAsync`, `convertAsync`, ...) fetch remote content over HTTP and
  /// supply a reader for it.
  final UriReader? uriReader;

  /// Returns a copy with the given fields replaced.
  AsciidoctorOptions copyWith({
    int? safe,
    String? backend,
    String? doctype,
    Map<String, String?>? attributes,
    bool? standalone,
    String? baseDir,
    String? toFile,
    String? toDir,
    bool? mkdirs,
    bool? sourcemap,
    Timings? timings,
    bool? parseHeaderOnly,
    bool? catalogAssets,
    Converter? converter,
    ConverterFactory? converterFactory,
    List<String>? templateDirs,
    String? templateEngine,
    bool? templateCache,
    TemplateCache? templateCacheStore,
    void Function(Registry registry)? extensions,
    Registry? extensionRegistry,
    LoggerBase? logger,
    SyntaxHighlighterFactory? syntaxHighlighterFactory,
    Map<String, SyntaxHighlighterFactoryFn>? syntaxHighlighters,
    DateTime? inputMtime,
    UriReader? uriReader,
  }) => AsciidoctorOptions(
    safe: safe ?? this.safe,
    backend: backend ?? this.backend,
    doctype: doctype ?? this.doctype,
    attributes: attributes ?? this.attributes,
    standalone: standalone ?? this.standalone,
    baseDir: baseDir ?? this.baseDir,
    toFile: toFile ?? this.toFile,
    toDir: toDir ?? this.toDir,
    mkdirs: mkdirs ?? this.mkdirs,
    sourcemap: sourcemap ?? this.sourcemap,
    timings: timings ?? this.timings,
    parseHeaderOnly: parseHeaderOnly ?? this.parseHeaderOnly,
    catalogAssets: catalogAssets ?? this.catalogAssets,
    converter: converter ?? this.converter,
    converterFactory: converterFactory ?? this.converterFactory,
    templateDirs: templateDirs ?? this.templateDirs,
    templateEngine: templateEngine ?? this.templateEngine,
    templateCache: templateCache ?? this.templateCache,
    templateCacheStore: templateCacheStore ?? this.templateCacheStore,
    extensions: extensions ?? this.extensions,
    extensionRegistry: extensionRegistry ?? this.extensionRegistry,
    logger: logger ?? this.logger,
    syntaxHighlighterFactory:
        syntaxHighlighterFactory ?? this.syntaxHighlighterFactory,
    syntaxHighlighters: syntaxHighlighters ?? this.syntaxHighlighters,
    inputMtime: inputMtime ?? this.inputMtime,
    uriReader: uriReader ?? this.uriReader,
  );

  /// Returns a copy whose output targets are exactly [toFile] and [toDir]
  /// (`null` clears a target).
  @internal
  AsciidoctorOptions withTargets({String? toFile, String? toDir}) =>
      AsciidoctorOptions(
        safe: safe,
        backend: backend,
        doctype: doctype,
        attributes: attributes,
        standalone: standalone,
        baseDir: baseDir,
        toFile: toFile,
        toDir: toDir,
        mkdirs: mkdirs,
        sourcemap: sourcemap,
        timings: timings,
        parseHeaderOnly: parseHeaderOnly,
        catalogAssets: catalogAssets,
        converter: converter,
        converterFactory: converterFactory,
        templateDirs: templateDirs,
        templateEngine: templateEngine,
        templateCache: templateCache,
        templateCacheStore: templateCacheStore,
        extensions: extensions,
        extensionRegistry: extensionRegistry,
        logger: logger,
        syntaxHighlighterFactory: syntaxHighlighterFactory,
        syntaxHighlighters: syntaxHighlighters,
        inputMtime: inputMtime,
        uriReader: uriReader,
      );

  /// Returns a copy for a discovery pass of the asynchronous entry points:
  /// remote content comes from [uriReader], nothing is logged or timed, and
  /// no output target is set.
  @internal
  AsciidoctorOptions forDiscovery(UriReader uriReader) => AsciidoctorOptions(
    safe: safe,
    backend: backend,
    doctype: doctype,
    attributes: attributes,
    standalone: standalone,
    baseDir: baseDir,
    sourcemap: sourcemap,
    parseHeaderOnly: parseHeaderOnly,
    catalogAssets: catalogAssets,
    converter: converter,
    converterFactory: converterFactory,
    templateDirs: templateDirs,
    templateEngine: templateEngine,
    templateCache: templateCache,
    templateCacheStore: templateCacheStore,
    extensions: extensions,
    extensionRegistry: extensionRegistry?.snapshot(),
    logger: NullLogger(),
    syntaxHighlighterFactory: syntaxHighlighterFactory,
    syntaxHighlighters: syntaxHighlighters,
    inputMtime: inputMtime,
    uriReader: uriReader,
  );
}
