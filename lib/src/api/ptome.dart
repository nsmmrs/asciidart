part of 'api.dart';

/// The output formats.
enum Backend {
  /// HTML 5 (the default).
  html5,

  /// HTML 5 written as XML (XHTML).
  xhtml5,

  /// DocBook 5.
  docbook5,

  /// A man page (troff).
  manpage,

  /// A PDF file (see [Ptome.convertToBytes]).
  pdf,

  /// An EPUB 3 file (see [Ptome.convertToBytes]).
  epub3;

  /// Whether the output is a file of its own format (bytes, not text).
  bool get makesFile => this == pdf || this == epub3;
}

/// A font given to a conversion as bytes: a TrueType, OpenType, WOFF or
/// WOFF2 file and its name (`Inter-Regular.ttf`). PDFs and EPUBs find it
/// as they find installed fonts, by the file's name, then by the family it
/// names.
final class FontFile {
  /// The font file [name] with [bytes].
  const new(this.name, this.bytes);

  /// The file's name.
  final String name;

  /// The file's contents.
  final List<int> bytes;
}

/// How much a document may reach outside itself.
enum SafeMode {
  /// No restrictions: includes and assets may come from anywhere.
  unsafe(impl.SafeMode.unsafe),

  /// Includes and assets only from below the base directory.
  safe(impl.SafeMode.safe),

  /// Like [safe], and the document may not set attributes that change how
  /// it is processed (such as `docinfo`).
  server(impl.SafeMode.server),

  /// Like [server], and no file is read at all: `include::` directives
  /// become links. The default for the API.
  secure(impl.SafeMode.secure);

  new(this._level);

  final int _level;
}

/// Parses and converts AsciiDoc with one configuration.
///
/// An instance holds everything that shapes a conversion: the safe mode,
/// attributes, extensions, output overrides and highlighters. It keeps no
/// state between documents, so one instance can be used for any number of
/// them, and two instances never affect each other.
///
/// ```dart
/// final ad = Ptome(attributes: {'icons': 'font'});
/// final html = ad.convert('NOTE: Hello');
/// ```
final class Ptome {
  /// Creates a configuration.
  ///
  /// [attributes] apply to every document (and win over the document's own
  /// assignments, as `-a` does on the command line, unless the value ends
  /// in `@`); a key ending in `!` unsets the attribute. [html] overrides
  /// the HTML of individual nodes. [templateDirs] holds Mustache templates
  /// that replace the built-in HTML of the nodes they name, as `-T` does.
  /// [highlighters] adds syntax highlighters, by the `source-highlighter`
  /// value that selects them. [baseDir] is where relative paths in
  /// documents are resolved from (default: the document's directory, or
  /// the working directory). [onDiagnostic] sees every message as it is
  /// reported, including those of [convert], which returns only the
  /// output. [fonts] are found by PDFs and EPUBs before the installed
  /// fonts; in a browser, so are the page's web fonts ([pageFonts]) and
  /// the [localFonts] families of the visitor's fonts.
  const new({
    this.safe = SafeMode.secure,
    this.attributes = const {},
    this.extensions = const [],
    this.html,
    this.templateDirs = const [],
    this.highlighters = const {},
    this.baseDir,
    this.onDiagnostic,
    this.fonts = const [],
    this.pageFonts = true,
    this.localFonts = const [],
  });

  /// How much documents may reach outside themselves.
  final SafeMode safe;

  /// Attributes applied to every document.
  final Map<String, String> attributes;

  /// The extensions in effect.
  final List<Extension> extensions;

  /// Overrides the HTML of individual nodes.
  final HtmlOverride? html;

  /// Directories of Mustache templates.
  final List<String> templateDirs;

  /// Syntax highlighters, by name.
  final Map<String, Highlighter> highlighters;

  /// Where relative paths in documents are resolved from.
  final String? baseDir;

  /// Called with every diagnostic as it is reported.
  final void Function(Diagnostic diagnostic)? onDiagnostic;

  /// Fonts given as bytes, found before the installed ones.
  final List<FontFile> fonts;

  /// In a browser, whether the asynchronous conversions to PDF and EPUB
  /// find the page's web fonts (after [fonts]): the sources of its
  /// `@font-face` rules, fetched again (usually from the browser's cache;
  /// they must be same-origin or allow CORS), by the families the fonts
  /// name. Elsewhere it does nothing.
  final bool pageFonts;

  /// In a browser, the families taken from the visitor's installed fonts
  /// for the asynchronous conversions to PDF and EPUB, through the Local
  /// Font Access API: Chromium-based browsers only, on HTTPS, after the
  /// visitor allows it (the conversion must start from a click or a key
  /// press for the browser to ask). Elsewhere it does nothing (the Dart VM
  /// and Node.js find installed fonts in the font folders).
  final List<String> localFonts;

  /// Loads the code of [backend]. On the Dart VM every backend is there;
  /// on JavaScript the PDF and EPUB backends load the first time an
  /// asynchronous conversion needs them, and [convertToBytes] needs them
  /// loaded.
  Future<void> loadBackend(Backend backend) =>
      file_backends.loadFileBackend(backend.name);

  /// [body] with [fonts], then [more], found before the installed fonts.
  T _withFonts<T>(
    T Function() body, [
    List<(String, List<int>)> more = const [],
  ]) => impl.Fonts.withFonts({
    for (final font in fonts) font.name: font.bytes,
    for (final (name, bytes) in more)
      if (!fonts.any((font) => font.name == name)) name: bytes,
  }, body);

  /// [body] with [fonts], and for [backend]s that make files, the page's
  /// and the visitor's fonts asked for ([pageFonts], [localFonts]).
  Future<T> _withAllFonts<T>(Backend backend, Future<T> Function() body) async {
    final more = backend.makesFile
        ? await file_backends.platformFonts(
            page: pageFonts,
            localFamilies: localFonts,
          )
        : const <(String, List<int>)>[];
    return await _withFonts(body, more);
  }

  /// Throws unless [backend] makes a file.
  static void _requireFile(Backend backend) {
    if (!backend.makesFile) {
      throw ArgumentError.value(backend, 'backend', 'makes text: use convert');
    }
  }

  /// Converts [source] to a file of [backend]'s format, a PDF or an EPUB:
  /// the file's bytes. [path] names the source (for messages, and as the
  /// base for relative paths, images included); [attributes] add to the
  /// instance's.
  ///
  /// On JavaScript the backend must have been loaded ([loadBackend], or
  /// any [convertToBytesAsync]).
  Uint8List convertToBytes(
    String source, {
    required Backend backend,
    String? path,
    Doctype? doctype,
    Map<String, String> attributes = const {},
  }) {
    _requireFile(backend);
    file_backends.registerFileBackend(backend.name);
    return _withFonts(() {
      final document = parse(
        source,
        path: path,
        backend: backend,
        doctype: doctype,
        standalone: true,
        attributes: attributes,
      );
      return document._run(() {
        document._doc.convert();
        return document._doc.outputBytes ?? Uint8List(0);
      });
    });
  }

  /// Like [convertToBytes], loading the backend when it isn't, waiting for
  /// [IncludeResolver]s that return a `Future`, fetching remote content
  /// when the `allow-uri-read` attribute is set, and doing the work that
  /// doesn't depend on order (images, compression) on other cores.
  Future<Uint8List> convertToBytesAsync(
    String source, {
    required Backend backend,
    String? path,
    Doctype? doctype,
    Map<String, String> attributes = const {},
  }) async {
    _requireFile(backend);
    await loadBackend(backend);
    return await _withAllFonts(backend, () async {
      final document = await parseAsync(
        source,
        path: path,
        backend: backend,
        doctype: doctype,
        standalone: true,
        attributes: attributes,
      );
      final doc = document._doc;
      document._run(() => impl.awaitingWorkers(doc.convert));
      await doc.finish();
      return document._run<Uint8List>(() => doc.outputBytes ?? Uint8List(0));
    });
  }

  /// Parses [source] into a [Document].
  ///
  /// [path] names the source (for messages, and as the base for relative
  /// paths); [backend], [doctype] and [standalone] set what the document
  /// is parsed for, as some attributes depend on them; [attributes] add to
  /// the instance's attributes.
  Document parse(
    String source, {
    String? path,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = false,
    Map<String, String> attributes = const {},
  }) {
    if (backend.makesFile) file_backends.registerFileBackend(backend.name);
    return _parse(
      source,
      _options(
        _Includes(async: false),
        path: path,
        backend: backend,
        doctype: doctype,
        standalone: standalone,
        attributes: attributes,
      ),
    );
  }

  /// Parses only the header of [source] (title, authors, attributes) into a
  /// [Document] without blocks; much faster than [parse] for reading
  /// metadata.
  Document parseHeader(
    String source, {
    String? path,
    Map<String, String> attributes = const {},
  }) => _parse(
    source,
    _options(
      _Includes(async: false),
      path: path,
      attributes: attributes,
      headerOnly: true,
    ),
  );

  /// Converts [source]: the body only, or a complete document when
  /// [standalone] is `true`. [backend] makes text ([convertToBytes] makes
  /// PDFs and EPUBs).
  String convert(
    String source, {
    String? path,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = false,
    Map<String, String> attributes = const {},
  }) {
    if (backend.makesFile) {
      throw ArgumentError.value(
        backend,
        'backend',
        'makes a file: use convertToBytes',
      );
    }
    return parse(
      source,
      path: path,
      backend: backend,
      doctype: doctype,
      standalone: standalone,
      attributes: attributes,
    ).convert();
  }

  /// Like [parse], waiting for [IncludeResolver]s that return a `Future`,
  /// and fetching remote content (includes, and assets read from a URI)
  /// when the `allow-uri-read` attribute is set.
  Future<Document> parseAsync(
    String source, {
    String? path,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = false,
    Map<String, String> attributes = const {},
  }) async {
    if (backend.makesFile) await loadBackend(backend);
    impl.AsciidoctorOptions optionsFor(_Includes includes) => _options(
      includes,
      path: path,
      backend: backend,
      doctype: doctype,
      standalone: standalone,
      attributes: attributes,
    );
    final includes = await _settleIncludes(
      optionsFor,
      (options) => impl.load(source, options: options),
    );
    final options = optionsFor(includes);
    return (await _document(
        (collector) =>
            collector.run(() => impl.loadAsync(source, options: options)),
      ))
      .._origin = (
        source: source,
        // The includes are settled: an edited source parses without waiting.
        parse: (edited) => _parse(edited, options),
      );
  }

  /// Like [convert], waiting for [IncludeResolver]s that return a `Future`,
  /// and fetching remote content when the `allow-uri-read` attribute is
  /// set.
  Future<String> convertAsync(
    String source, {
    String? path,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool standalone = false,
    Map<String, String> attributes = const {},
  }) async {
    if (backend.makesFile) {
      throw ArgumentError.value(
        backend,
        'backend',
        'makes a file: use convertToBytesAsync',
      );
    }
    impl.AsciidoctorOptions optionsFor(_Includes includes) => _options(
      includes,
      path: path,
      backend: backend,
      doctype: doctype,
      standalone: standalone,
      attributes: attributes,
    );
    final includes = await _settleIncludes(
      optionsFor,
      (options) => impl.load(source, options: options),
    );
    final options = optionsFor(includes);
    return await _guardAsync(
      () =>
          _Collector(onDiagnostic)
              .run(() => impl.convertAsync(source, options)),
    );
  }

  /// Runs silent parses (with [load]) until every [IncludeResolver] future
  /// the document needs has completed, and returns the resolved content.
  Future<_Includes> _settleIncludes(
    impl.AsciidoctorOptions Function(_Includes includes) optionsFor,
    void Function(impl.AsciidoctorOptions options) load,
  ) async {
    final includes = _Includes(async: true);
    if (!extensions.any((e) => e is IncludeResolver)) return includes;
    const maxPasses = 32;
    for (var pass = 0; pass < maxPasses; pass++) {
      final options = optionsFor(includes);
      try {
        impl.LoggerManager.scoped(impl.NullLogger(), () => load(options));
        // The real parse reports the failure.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        break;
      }
      if (!includes.hasPending) break;
      await includes.settle();
    }
    return includes;
  }

  /// The public document for what [load] returns, with the diagnostics
  /// collected while loading.
  Future<Document> _document(
    Future<impl.Document> Function(_Collector collector) load,
  ) async {
    final collector = _Collector(onDiagnostic);
    final doc = await _guardAsync(() => load(collector));
    return (_view(doc) as Document).._collector = collector;
  }

  Document _parse(String source, impl.AsciidoctorOptions options) {
    final collector = _Collector(onDiagnostic);
    final doc = _guard(
      () => collector.run(() => impl.load(source, options: options)),
    );
    return (_view(doc) as Document)
      .._collector = collector
      .._origin = (source: source, parse: (edited) => _parse(edited, options));
  }

  impl.AsciidoctorOptions _options(
    _Includes includes, {
    String? path,
    Backend backend = Backend.html5,
    Doctype? doctype,
    bool? standalone,
    Map<String, String> attributes = const {},
    bool headerOnly = false,
  }) {
    final override = html;
    final docfile = path == null ? null : _absolute(path);
    final directory = docfile == null ? null : _directoryOf(docfile);
    return impl.AsciidoctorOptions(
      safe: safe._level,
      backend: backend.name,
      doctype: doctype?.name,
      attributes: {
        if (docfile != null && directory != null) ...{
          'docfile': docfile,
          'docdir': directory,
        },
        ...this.attributes,
        ...attributes,
      },
      standalone: standalone,
      baseDir: baseDir ?? directory,
      sourcemap: true,
      parseHeaderOnly: headerOnly,
      templateDirs: templateDirs,
      converterFactory: override == null ? null : _overrideFactory(override),
      extensions: extensions.isEmpty
          ? null
          : (registry) {
              for (final extension in extensions) {
                extension._register(registry, includes);
              }
            },
      syntaxHighlighters: highlighters.isEmpty
          ? null
          : {
              for (final MapEntry(key: name, value: highlighter)
                  in highlighters.entries)
                name: (_, _, _) => _HighlighterAdapter(name, highlighter),
            },
    );
  }
}

/// [path] made absolute against the working directory, where the platform
/// has one (not in a browser).
String _absolute(String path) {
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path)) {
    return path;
  }
  try {
    return '${impl.currentDirectory}/$path';
    // Browsers have no working directory: keep the path as given.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return path;
  }
}

/// The directory part of [path] (`.` when it has none).
String _directoryOf(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  if (slash < 0) return '.';
  return slash == 0 ? path.substring(0, 1) : path.substring(0, slash);
}

/// The default configuration: `secure` safe mode, no attributes, no
/// extensions.
const Ptome asciidoc = Ptome();

/// The version of Ptome.
const String ptomeVersion = impl.Asciidoctor.packageVersion;

/// The Asciidoctor release Ptome is compatible with.
const String asciidoctorVersion = impl.Asciidoctor.version;

/// The command line's processor [options] with [Ptome]'s configuration
/// added: its extensions, output override and highlighters, its attributes
/// and template directories under those of the command line.
///
/// Used by `runCli` in `package:ptome/cli.dart`; not exported.
impl.AsciidoctorOptions configureCli(
  Ptome ptome,
  impl.AsciidoctorOptions options,
) {
  final mine = ptome._options(_Includes(async: false));
  return options.copyWith(
    attributes: {...ptome.attributes, ...options.attributes},
    templateDirs: [...ptome.templateDirs, ...options.templateDirs],
    converterFactory: mine.converterFactory,
    extensions: mine.extensions,
    syntaxHighlighters: mine.syntaxHighlighters,
  );
}
