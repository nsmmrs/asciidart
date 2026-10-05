/// The document node: root of a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/document.rb` (complete).
///
/// Node contexts and other symbolic names are `String`s throughout
/// (`'paragraph'`, `'document'`, ...).
///
/// The backend converters (html5, docbook5, manpage) register with
/// [Converter] and are resolved through [Converter.create]; an unknown
/// backend fails when the converter is first needed. The `extensions` and
/// `extension_registry` options activate a [Registry] into
/// [Document.extensions], and the `converter`/`converter_factory` options
/// resolve through [CustomFactory]/[ConverterFactory].
/// [Document.syntaxHighlighter] resolves from the `source-highlighter`
/// attribute when the header is saved.
///
/// [Timings] (from `timings.dart`) records the read/parse/convert/write
/// phase durations surfaced via the `timings` option and `--timings`.
library;

import 'dart:convert' show utf8;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/callouts.dart';
import 'package:asciidart/src/constants.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/core_ext.dart';
import 'package:asciidart/src/docbook5.dart';
import 'package:asciidart/src/errors.dart';
import 'package:asciidart/src/extensions.dart';
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/highlight/syntax_highlighter.dart';
import 'package:asciidart/src/html5.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/manpage.dart';
import 'package:asciidart/src/options.dart';
import 'package:asciidart/src/parser.dart';
import 'package:asciidart/src/path_resolver.dart';
import 'package:asciidart/src/reader.dart';
import 'package:asciidart/src/remote.dart';
import 'package:asciidart/src/rx.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/substitutors.dart' as substitutors;
import 'package:asciidart/src/text_case.dart';
import 'package:asciidart/src/timings.dart';
import 'package:asciidart/src/version.dart';
import 'package:meta/meta.dart';

/// Resolves a safe mode [name] (case-insensitive) to its level.
///
/// Port of `SafeMode.value_for_name`. Returns `null` for unknown names.
int? safeModeValueForName(String name) {
  switch (name.toUpperCase()) {
    case 'UNSAFE':
      return SafeMode.unsafe;
    case 'SAFE':
      return SafeMode.safe;
    case 'SERVER':
      return SafeMode.server;
    case 'SECURE':
      return SafeMode.secure;
    default:
      return null;
  }
}

/// Resolves a safe mode [value] to its name.
///
/// Port of `SafeMode.name_for_value`. Returns `null` for unknown levels.
String? safeModeNameForValue(int value) {
  switch (value) {
    case SafeMode.unsafe:
      return 'unsafe';
    case SafeMode.safe:
      return 'safe';
    case SafeMode.server:
      return 'server';
    case SafeMode.secure:
      return 'secure';
    default:
      return null;
  }
}

/// A block-level attribute assignment recorded for later playback.
///
/// Port of `Asciidoctor::Document::AttributeEntry`.
class DocumentAttributeEntry {
  /// Creates an entry assigning [value] to [name].
  ///
  /// [negate] defaults to whether [value] is `null` (an unset marker).
  new(this.name, this.value, {bool? negate})
    : negate = negate ?? (value == null);

  /// The attribute name.
  final String name;

  /// The attribute value (`null` for an unset marker).
  final String? value;

  /// Whether this entry unsets the attribute.
  final bool negate;
}

/// A parsed and stored partitioned title (title and subtitle).
///
/// Port of `Asciidoctor::Document::Title`.
class DocumentTitle {
  /// Parses [val] into a main title and an optional subtitle.
  ///
  /// When [sanitize] is set and the value contains `<`, XML tags are
  /// stripped, blank runs are squeezed and the value is trimmed. The value
  /// is then split at the last occurrence of [separator] (default `':'`)
  /// followed by a space; [main] is the text before it and [subtitle] the
  /// text after it. With no separator match, [main] is the whole value and
  /// [subtitle] is `null`. [combined] is the (possibly sanitized) value.
  new(String val, {String? separator, bool sanitize = false}) {
    _sanitized = sanitize;
    var text = val;
    if (sanitize && text.contains('<')) {
      text = collapseRuns(text.replaceAll(xmlSanitizeRx, ''), ' ').trimAscii();
    }
    var sep = separator ?? ':';
    if (sep.isEmpty || !text.contains(sep = '$sep ')) {
      main = text;
      subtitle = null;
    } else {
      // Split at the last occurrence.
      final idx = text.lastIndexOf(sep);
      main = text.substring(0, idx);
      subtitle = text.substring(idx + sep.length);
    }
    combined = text;
  }

  /// The main title.
  late final String main;

  /// The main title (alias of [main]).
  String get title => main;

  /// The subtitle, or `null` when the value has no subtitle part.
  late final String? subtitle;

  /// The (possibly sanitized) combined title value.
  late final String combined;

  bool _sanitized = false;

  /// Whether the value was sanitized.
  bool get sanitized => _sanitized;

  /// Whether a subtitle was parsed.
  bool get hasSubtitle => subtitle != null;

  /// The combined title value.
  @override
  String toString() => combined;
}

/// Information about an author extracted from document attributes.
///
/// Port of `Asciidoctor::Document::Author`.
class DocumentAuthor {
  /// Creates an author record.
  const new(
    this.name,
    this.firstname,
    this.middlename,
    this.lastname,
    this.initials,
    this.email,
  );

  /// The full name of the author.
  final String? name;

  /// The first name of the author.
  final String? firstname;

  /// The middle name of the author.
  final String? middlename;

  /// The last name of the author.
  final String? lastname;

  /// The initials of the author.
  final String? initials;

  /// The email address of the author.
  final String? email;
}

/// A registered image with the `imagesdir` in effect when registered.
///
/// Port of `Asciidoctor::Document::ImageReference`.
class ImageReference {
  /// Creates an image reference for [target] with [imagesdir].
  const new(this.target, this.imagesdir);

  /// The image target.
  final String target;

  /// The value of the `imagesdir` attribute when registered.
  final String? imagesdir;

  /// The image target.
  @override
  String toString() => target;
}

/// A registered footnote.
///
/// Port of `Asciidoctor::Document::Footnote`.
class Footnote {
  /// Creates a footnote with [index], [id] and [text].
  const new(this.index, this.id, this.text);

  /// The footnote index (its number).
  final String index;

  /// The footnote id, if any.
  final String? id;

  /// The footnote text.
  final String text;
}

/// The document catalog: references, footnotes, links, images, callouts
/// and includes collected while parsing and converting.
///
/// Port of `Document#catalog`.
final class Catalog {
  /// Creates an empty catalog.
  new()
    : refs = <String, AbstractNode>{},
      footnotes = <Footnote>[],
      links = <String>[],
      images = <ImageReference>[],
      callouts = Callouts(),
      includes = <String, bool>{};

  /// Creates a catalog for a nested document: everything is shared with
  /// [parent] except the footnotes.
  new nested(Catalog parent)
    : refs = parent.refs,
      footnotes = <Footnote>[],
      links = parent.links,
      images = parent.images,
      callouts = parent.callouts,
      includes = parent.includes;

  /// Referenceable nodes (blocks, sections and anchors) by id.
  final Map<String, AbstractNode> refs;

  /// The registered footnotes.
  final List<Footnote> footnotes;

  /// The cataloged link targets (only with the `catalogAssets` option).
  final List<String> links;

  /// The cataloged images (only with the `catalogAssets` option).
  final List<ImageReference> images;

  /// The callouts.
  final Callouts callouts;

  /// The included files, by path without extension; `false` marks a
  /// partial include.
  final Map<String, bool> includes;
}

/// An attribute override from the API before it is applied: a value, an
/// unset (locked) or a soft unset (the document may set it again).
sealed class _Override {
  const new();
}

final class _SetValue extends _Override {
  const new(this.value);

  final String value;
}

final class _Unset extends _Override {
  const new();
}

final class _SoftUnset extends _Override {
  const new();
}

/// Backend traits: the basebackend, filetype, outfilesuffix and (for HTML)
/// htmlsyntax derived from a backend name.
///
/// Port of the `BackendTraits` values `Converter.derive_backend_traits and
/// the built-in converters report.
class _BackendTraits {
  /// Creates backend traits.
  const new({
    required this.basebackend,
    required this.filetype,
    required this.outfilesuffix,
    this.htmlsyntax,
  });

  /// The base backend (e.g. `'html'` for `'html5'`).
  final String basebackend;

  /// The file type (e.g. `'html'`, `'xml'`, `'man'`).
  final String filetype;

  /// The output file suffix (e.g. `'.html'`).
  final String outfilesuffix;

  /// The HTML syntax (`'html'` or `'xml'`), if applicable.
  final String? htmlsyntax;
}

/// Placeholder converter that only reports backend traits.
///
/// Carries the backend [traits] when they are known (a built-in backend, or
/// a template chain delegating to one); otherwise ([traits] is `null`) the
/// traits are derived from the backend name, mirroring the
/// `Converter::BackendTraits === converter` / `elsif converter` branches in
/// `update_backend_attributes`. [convert] always throws [UnimplementedError].
class _BuiltinConverterStub implements NodeConverter {
  /// Creates a stub for [backend] with [traits] (`null` to derive).
  const new(this.backend, this.traits);

  /// The backend this stub converts to.
  final String backend;

  /// The backend traits, or `null` when they must be derived.
  final _BackendTraits? traits;

  /// Whether this stub reports backend traits (the `BackendTraits` branch).
  bool get hasTraits => traits != null;

  @override
  String? convert(AbstractNode node) =>
      throw UnsupportedError('no converter for backend "$backend"');
}

/// The root node of a parsed AsciiDoc document.
///
/// Port of `Asciidoctor::Document`.
class Document extends AbstractBlock implements NodeDocument {
  /// Creates a document for the AsciiDoc [source] (an empty document when
  /// `null`) with [options].
  new([String? source, AsciidoctorOptions options = const AsciidoctorOptions()])
    : this._create(source, null, options, null, null);

  /// Creates a document for the AsciiDoc source [lines] with [options].
  new lines(
    List<String> lines, [
    AsciidoctorOptions options = const AsciidoctorOptions(),
  ]) : this._create(null, lines, options, null, null);

  /// Creates a document nested in [parent] (the content of an AsciiDoc
  /// table cell) from [lines], parsing it eagerly.
  ///
  /// [cursor] is the position of the content in the parent's source.
  @internal
  new nested(Document parent, List<String> lines, {Cursor? cursor})
    : this._create(
        null,
        lines,
        AsciidoctorOptions(
          standalone: false,
          baseDir: parent.baseDir,
          catalogAssets: parent.options.catalogAssets,
          toDir: parent.options.toDir,
        ),
        parent,
        cursor,
      );

  new _create(
    String? source,
    List<String>? lines,
    AsciidoctorOptions options,
    Document? parentDoc,
    Cursor? cursor,
  ) : super(null, BlockContext.document) {
    final attrOverrides = <String, _Override>{};
    String? parentDoctype;

    if (parentDoc != null) {
      parentDocument = parentDoc;
      catalog = Catalog.nested(parentDoc.catalog);
      parentDoc._attributeOverrides.forEach((key, value) {
        attrOverrides[key] = value == null ? const _Unset() : _SetValue(value);
      });
      parentDoc.attributes.forEach((key, value) {
        attrOverrides[key] = _SetValue(value);
      });
      attrOverrides.remove('compat-mode');
      parentDoctype = switch (attrOverrides.remove('doctype')) {
        _SetValue(:final value) => value,
        _ => null,
      };
      attrOverrides
        ..remove('notitle')
        ..remove('showtitle')
        ..remove('toc');
      attributes['toc-placement'] = switch (attrOverrides.remove(
        'toc-placement',
      )) {
        _SetValue(:final value) => value,
        _ => 'auto',
      };
      attrOverrides.remove('toc-position');
      safe = parentDoc.safe;
      _compatMode = parentDoc.compatMode;
      if (_compatMode) attributes['compat-mode'] = '';
      outfilesuffix = parentDoc.outfilesuffix;
      sourcemap = parentDoc.sourcemap;
      _timings = null;
      pathResolver = parentDoc.pathResolver;
      converter = parentDoc.converter;
      extensions = parentDoc.extensions;
      syntaxHighlighter = parentDoc.syntaxHighlighter;
    } else {
      parentDocument = null;
      catalog = Catalog();
      options.attributes.forEach((key, value) {
        var name = key;
        _Override override;
        if (name.endsWith('@')) {
          if (name.startsWith('!')) {
            name = name.substring(1, name.length - 1);
            override = const _SoftUnset();
          } else if (name.endsWith('!@')) {
            name = name.substring(0, name.length - 2);
            override = const _SoftUnset();
          } else {
            name = name.substring(0, name.length - 1);
            override = _SetValue('${value ?? ''}@');
          }
        } else if (name.startsWith('!')) {
          name = name.substring(1);
          override = value == '@' ? const _SoftUnset() : const _Unset();
        } else if (name.endsWith('!')) {
          name = name.substring(0, name.length - 1);
          override = value == '@' ? const _SoftUnset() : const _Unset();
        } else {
          override = value == null ? const _Unset() : _SetValue(value);
        }
        attrOverrides[downcase(name)] = override;
      });
      final toFile = options.toFile;
      if (toFile != null) {
        attrOverrides['outfilesuffix'] = _SetValue(
          Helpers.extname(toFile) ?? '',
        );
      }
      safe = options.safe;
      _compatMode = attrOverrides.containsKey('compat-mode');
      sourcemap = options.sourcemap;
      _timings = options.timings;
      pathResolver = PathResolver(onWarn: (message) => logger.warn(message));
      extensions = null;
    }

    _parsed = false;
    _reftexts = null;
    header = null;
    _headerAttributes = null;
    this.options = options;
    final standalone = options.standalone ?? false;

    final attrs = attributes;
    if (parentDoc == null) {
      attrs['attribute-undefined'] = Compliance.attributeUndefined;
      attrs['attribute-missing'] = Compliance.attributeMissing;
      attrs.addAll(defaultAttributes);
    }

    if (standalone) {
      // Sync the embedded attribute with the standalone option value.
      attrOverrides['embedded'] = const _Unset();
      attrs['copycss'] = '';
      attrs['iconfont-remote'] = '';
      attrs['stylesheet'] = '';
      attrs['webfonts'] = '';
    } else {
      // Sync the embedded attribute with the standalone option value.
      attrOverrides['embedded'] = const _SetValue('');
      String? lastShowtitleKey;
      for (final key in attrOverrides.keys) {
        if (key == 'notitle' || key == 'showtitle') lastShowtitleKey = key;
      }
      if (attrOverrides.containsKey('showtitle') &&
          lastShowtitleKey == 'showtitle') {
        attrOverrides['notitle'] = _mirrorShowtitle(
          attrOverrides['showtitle']!,
        );
      } else if (attrOverrides.containsKey('notitle')) {
        attrOverrides['showtitle'] = _mirrorShowtitle(
          attrOverrides['notitle']!,
        );
      } else {
        attrs['notitle'] = '';
      }
    }

    attrOverrides['asciidoctor'] = const _SetValue('');
    attrOverrides['asciidoctor-version'] = const _SetValue(Asciidoctor.version);
    attrOverrides['asciidart-version'] = const _SetValue(
      Asciidoctor.packageVersion,
    );

    final safeModeName = safeModeNameForValue(safe);
    attrOverrides['safe-mode-name'] = safeModeName == null
        ? const _Unset()
        : _SetValue(safeModeName);
    attrOverrides['safe-mode-${safeModeName ?? ''}'] = const _SetValue('');
    attrOverrides['safe-mode-level'] = _SetValue('$safe');

    // The only way to set max-include-depth is via the API (default 64).
    if (attrOverrides['max-include-depth'] is! _SetValue) {
      attrOverrides['max-include-depth'] = const _SetValue('64');
    }
    // The only way to set allow-uri-read is via the API (disabled by default).
    if (attrOverrides['allow-uri-read'] is! _SetValue) {
      attrOverrides['allow-uri-read'] = const _Unset();
    }

    // Remap legacy attribute names.
    if (attrOverrides.containsKey('numbered')) {
      attrOverrides['sectnums'] = attrOverrides.remove('numbered')!;
    }
    if (attrOverrides.containsKey('hardbreaks')) {
      attrOverrides['hardbreaks-option'] = attrOverrides.remove('hardbreaks')!;
    }

    final baseDirOpt = options.baseDir;
    final docdirOverride = attrOverrides['docdir'];
    if (baseDirOpt != null) {
      baseDir = _expandBaseDir(baseDirOpt);
      attrOverrides['docdir'] = _SetValue(baseDir);
    } else if (docdirOverride is _SetValue) {
      baseDir = docdirOverride.value;
    } else {
      baseDir = io.currentDirectory;
      attrOverrides['docdir'] = _SetValue(baseDir);
    }

    // Allow backend and doctype to be set using the options.
    if (options.backend case final backend?) {
      attrOverrides['backend'] = _SetValue(backend);
    }
    if (options.doctype case final doctype?) {
      attrOverrides['doctype'] = _SetValue(doctype);
    }

    if (safe >= SafeMode.server) {
      // Restrict the document from setting copycss, source-highlighter
      // and backend.
      if (attrOverrides['copycss'] is! _SetValue) {
        attrOverrides['copycss'] = const _Unset();
      }
      if (attrOverrides['source-highlighter'] is! _SetValue) {
        attrOverrides['source-highlighter'] = const _Unset();
      }
      if (attrOverrides['backend'] is! _SetValue) {
        attrOverrides['backend'] = const _SetValue(defaultBackend);
      }
      // Restrict the document from seeing docdir; trim docfile to a
      // relative path.
      final docfileOverride = attrOverrides['docfile'];
      if (parentDoc == null && docfileOverride != null) {
        final docfile = (docfileOverride as _SetValue).value;
        final docdir = (attrOverrides['docdir']! as _SetValue).value;
        final start = docdir.length + 1;
        attrOverrides['docfile'] = start <= docfile.length
            ? _SetValue(docfile.substring(start))
            : const _Unset();
      }
      attrOverrides['docdir'] = const _SetValue('');
      if (attrOverrides['user-home'] is! _SetValue) {
        attrOverrides['user-home'] = const _SetValue('.');
      }
      if (safe >= SafeMode.secure) {
        if (!attrOverrides.containsKey('max-attribute-value-size')) {
          attrOverrides['max-attribute-value-size'] = const _SetValue('4096');
        }
        // Assign linkcss (preventing CSS embedding) unless explicitly
        // disabled from the commandline or API.
        if (!attrOverrides.containsKey('linkcss')) {
          attrOverrides['linkcss'] = const _SetValue('');
        }
        // Restrict the document from enabling icons.
        if (attrOverrides['icons'] is! _SetValue) {
          attrOverrides['icons'] = const _Unset();
        }
      }
    } else {
      if (attrOverrides['user-home'] is! _SetValue) {
        attrOverrides['user-home'] = _SetValue(_userHome);
      }
    }

    // The only way to set max-attribute-value-size is via the API
    // (disabled by default).
    final maxSize = attrOverrides['max-attribute-value-size'];
    if (maxSize is _SetValue) {
      _maxAttributeValueSize = _toIntSaturating(maxSize.value).abs();
    } else {
      attrOverrides['max-attribute-value-size'] = const _Unset();
      _maxAttributeValueSize = null;
    }

    final lockedOverrides = <String, String?>{};
    attrOverrides.forEach((key, override) {
      switch (override) {
        case _SetValue(:final value):
          // A value ending in @ allows the document to override the value.
          if (value.endsWith('@')) {
            attrs[key] = value.substring(0, value.length - 1);
          } else {
            attrs[key] = value;
            lockedOverrides[key] = value;
          }
        case _Unset():
          // An unset locks the attribute; a soft unset does not.
          attrs.remove(key);
          lockedOverrides[key] = null;
        case _SoftUnset():
          attrs.remove(key);
      }
    });
    _attributeOverrides = lockedOverrides;

    if (parentDoc != null) {
      _backend = attrs['backend'];
      // Reset the doctype unless it matches the default value.
      _doctype = parentDoctype;
      if (parentDoctype == null) {
        attrs.remove('doctype');
      } else {
        attrs['doctype'] = parentDoctype;
      }
      if (_doctype != defaultDoctype) {
        _updateDoctypeAttributes(defaultDoctype);
      }

      // Don't need to do the extra processing within our own document.
      reader = Reader(lines ?? const <String>[], cursor: cursor);
      if (sourcemap) sourceLocation = reader.cursor();

      // Now parse the lines in the reader into blocks.
      // Eagerly parse (for now) since a subdocument is not a publicly
      // accessible object.
      Parser.parse(reader, this);

      restoreAttributes();
      _parsed = true;
    } else {
      // Setup default backend and doctype.
      _backend = null;
      final initialBackend = attrs['backend'] ?? defaultBackend;
      if (initialBackend == 'manpage') {
        _doctype = attrs['doctype'] = 'manpage';
        _attributeOverrides['doctype'] = 'manpage';
      } else {
        _doctype = attrs['doctype'] ??= defaultDoctype;
      }
      _updateBackendAttributes(initialBackend, true);

      // Fallback directories.
      attrs['stylesdir'] ??= '.';
      if (!attrs.containsKey('iconsdir')) {
        attrs['iconsdir'] = '${attrs['imagesdir'] ?? './images'}/icons';
      }

      _fillDatetimeAttributes(attrs, options.inputMtime);

      // Activate the extensions registry. Nested documents inherit the
      // parent registry (above).
      final extRegistry = options.extensionRegistry;
      final buildExtensions = options.extensions;
      if (extRegistry != null) {
        extRegistry.activate(this);
        extensions = extRegistry;
      } else if (buildExtensions != null) {
        extensions = Extensions.create(build: buildExtensions)..activate(this);
      } else if (Extensions.groups.isNotEmpty) {
        extensions = Registry()..activate(this);
      }

      reader = lines != null
          ? PreprocessorReader(
              this,
              lines,
              cursor: Cursor(attrs['docfile'], baseDir),
              normalize: true,
            )
          : PreprocessorReader.fromString(
              this,
              source,
              cursor: Cursor(attrs['docfile'], baseDir),
              normalize: true,
            );
      if (sourcemap) sourceLocation = reader.cursor();
    }
  }

  /// A read-only integer value indicating the level of security enforced
  /// while processing this document (see [SafeMode]).
  @override
  late final int safe;

  /// Whether AsciiDoc compatibility mode is enabled.
  @override
  bool get compatMode => _compatMode;
  bool _compatMode = false;

  /// The cached value of the backend attribute for this document.
  String? get backend => _backend;
  String? _backend;

  /// The cached value of the doctype attribute for this document.
  String? get doctype => _doctype;
  String? _doctype;

  /// Whether source map information is tracked by the parser.
  @override
  bool sourcemap = false;

  /// The document catalog.
  @override
  late final Catalog catalog;

  /// The document counters.
  final Map<String, String> counters = <String, String>{};

  /// The level-0 section (i.e., doctitle). Only stores the title, not the
  /// header attributes.
  ///
  /// Written by the parser once the header is parsed.
  Section? header;

  /// The attribute entries of the document header, in source order (`null`
  /// before the header is parsed or when it has none).
  ///
  /// Written by the parser when it finishes the header.
  List<DocumentAttributeEntry>? headerAttributeEntries;

  /// The base directory for converting this document.
  @override
  late final String baseDir;

  /// The options used to initialize this document.
  late final AsciidoctorOptions options;

  /// The outfilesuffix defined at the end of the header.
  String? outfilesuffix;

  /// The parent document of this nested document, if any.
  Document? parentDocument;

  /// The reader associated with this document.
  late Reader reader;

  /// The path resolver used to resolve paths in this document.
  @override
  late final PathResolver pathResolver;

  /// The converter associated with this document.
  ///
  /// Resolved from the backend when the backend attributes are updated.
  @override
  late NodeConverter converter;

  /// The syntax highlighter associated with this document.
  ///
  /// Resolved from the `source-highlighter` attribute when the header is
  /// saved; `null` unless the base backend is HTML and the named
  /// highlighter is registered.
  SyntaxHighlighterBase? syntaxHighlighter;

  /// The activated extensions registry associated with this document.
  ///
  /// `null` when no extension groups are registered and neither the
  /// `extensionRegistry` nor the `extensions` option was passed.
  Registry? extensions;

  /// Attributes locked by the API: the value, or `null` for a locked unset.
  Map<String, String?> _attributeOverrides = <String, String?>{};
  int? _maxAttributeValueSize;
  Map<String, String>? _headerAttributes;
  final Set<String> _attributesModified = <String>{};
  final Map<String, List<ProcessorExtension<DocinfoProcessor>>>
  _docinfoProcessorExtensions =
      <String, List<ProcessorExtension<DocinfoProcessor>>>{};
  Timings? _timings;
  bool _parsed = false;
  Map<String?, String>? _reftexts;

  /// Parses the AsciiDoc source stored in the [reader] into an AST.
  ///
  /// If parsing was already performed, returns this document without
  /// further processing. Returns the parsed document (a tree processor may
  /// replace it).
  Document parse() {
    if (_parsed) return this;
    var doc = this;

    // Preprocessor extensions run before parsing (never for nested
    // documents).
    final exts = parentDocument == null ? extensions : null;
    if (exts != null && exts.hasPreprocessors) {
      for (final ext in exts.preprocessors) {
        final result = ext.instance.process(doc, reader);
        if (result != null) reader = result;
      }
    }

    // Now parse the lines in the reader into blocks.
    Parser.parse(reader, this, headerOnly: options.parseHeaderOnly);

    restoreAttributes();

    // Tree processor extensions run after parsing; a tree processor may
    // replace the document by returning a different Document.
    if (exts != null && exts.hasTreeProcessors) {
      for (final ext in exts.treeProcessors) {
        final result = ext.instance.process(doc);
        if (result != null && !identical(result, doc)) doc = result;
      }
    }

    _parsed = true;
    return doc;
  }

  /// Whether the source lines of the document have been parsed.
  bool get isParsed => _parsed;

  /// Gets the named counter and takes the next value in the sequence.
  ///
  /// Returns the next value in the sequence for the counter [name]: the
  /// next integer for a numeric counter, else the successor string (`a`,
  /// `b`, ...). A counter seen for the first time starts at [seed]
  /// (default `1`).
  @override
  String counter(String name, [String? seed]) {
    final parent = parentDocument;
    if (parent != null) return parent.counter(name, seed);
    final locked = attributeLocked(name);
    String? currVal;
    if (locked) currVal = counters[name];
    if (currVal == null) {
      final attrVal = attributes[name];
      currVal = attrVal == null || attrVal.isEmpty ? null : attrVal;
    }
    final String nextVal;
    if (currVal != null) {
      nextVal = counters[name] = _nextval(currVal);
    } else if (seed != null) {
      nextVal = counters[name] = seed;
    } else {
      nextVal = counters[name] = '1';
    }
    if (!locked) attributes[name] = nextVal;
    return nextVal;
  }

  /// Increments the counter [counterName] and records the new value as an
  /// attribute entry on [block], so it is replayed when the block is
  /// converted.
  ///
  /// Returns the next value in the sequence for the counter.
  @override
  String incrementAndStoreCounter(String counterName, AbstractBlock block) {
    final value = counter(counterName);
    (block.attributeEntries ??= <DocumentAttributeEntry>[]).add(
      DocumentAttributeEntry(counterName, value),
    );
    return value;
  }

  /// Registers [node] in the document catalog under [id].
  ///
  /// Returns whether the reference was registered (`false` when [id] is
  /// already taken).
  bool registerRef(String id, AbstractNode node) {
    final refs = catalog.refs;
    if (refs.containsKey(id)) return false;
    refs[id] = node;
    return true;
  }

  /// Registers [footnote] in the document catalog.
  void registerFootnote(Footnote footnote) {
    catalog.footnotes.add(footnote);
  }

  /// Catalogs the link [target] when the `catalogAssets` option is set.
  void registerLink(String target) {
    if (options.catalogAssets) catalog.links.add(target);
  }

  /// Catalogs the image [target] (with the current `imagesdir`) when the
  /// `catalogAssets` option is set.
  void registerImage(String target) {
    if (options.catalogAssets) {
      catalog.images.add(ImageReference(target, attributes['imagesdir']));
    }
  }

  /// Reads the remote resource at [uri] through the `uriReader` option
  /// (of the root document, for a nested document).
  @override
  RemoteResource fetchUri(String uri) {
    final reader = (parentDocument ?? this).options.uriReader;
    if (reader == null) {
      throw AsciidoctorException('cannot read $uri: no URI reader');
    }
    return reader(uri);
  }

  /// Scans registered references and returns the ID of the first reference
  /// matching the reference [text], or `null` if no reference is found.
  String? resolveId(String text) {
    final cached = _reftexts;
    if (cached != null) return cached[text];
    final refs = catalog.refs;
    if (_parsed) {
      // Set eagerly to prevent nested lazy init.
      final accum = <String?, String>{};
      _reftexts = accum;
      for (final entry in refs.entries) {
        accum.putIfAbsent(_xreftextOf(entry.value), () => entry.key);
      }
      return accum[text];
    }
    String? resolvedId;
    // Set eagerly to prevent nested lazy init.
    final accum = <String?, String>{};
    _reftexts = accum;
    for (final entry in refs.entries) {
      final xreftext = _xreftextOf(entry.value);
      // Short-circuit early since this table is thrown away anyway.
      if (xreftext == text) {
        resolvedId = entry.key;
        break;
      }
      accum.putIfAbsent(xreftext, () => entry.key);
    }
    _reftexts = null;
    return resolvedId;
  }

  static String? _xreftextOf(AbstractNode ref) => switch (ref) {
    AbstractBlock() => ref.xreftext(),
    Inline() => ref.xreftext(),
    _ => null,
  };

  /// Whether this document has any child section objects.
  @override
  bool get hasSections => nextSectionIndex > 0;

  /// Whether the document has footnotes.
  bool get hasFootnotes => catalog.footnotes.isNotEmpty;

  /// The footnotes registered in the document catalog.
  List<Footnote> get footnotes => catalog.footnotes;

  /// The callouts catalog.
  @override
  Callouts get callouts => catalog.callouts;

  /// Whether this document is nested inside another one.
  @override
  bool nested() => parentDocument != null;

  /// Whether this is an embedded document.
  bool get embedded => attributes.containsKey('embedded');

  /// Whether extensions are activated for this document.
  bool get hasExtensions => extensions != null;

  /// The raw source for the document.
  String get source => reader.source;

  /// The raw source lines for the document.
  List<String> get sourceLines => reader.sourceLines;

  /// Whether the base backend equals [base].
  bool basebackend(String base) => attributes['basebackend'] == base;

  /// The resolved doctitle (see [doctitle]).
  @override
  String? get title => doctitle();

  /// Sets the title on the document header, creating it when absent.
  @override
  set title(String? value) {
    var sect = header;
    sect ??= (header = Section(this, 0))..sectname = 'header';
    sect.title = value;
  }

  /// Resolves the primary title for the document.
  ///
  /// Searches the document-level `title` attribute, the header title (or
  /// the title of the first section), and — when [useFallback] is set —
  /// the `untitled-label` attribute, returning the first value found (or
  /// `null` when none resolves). When [sanitize] is set, XML elements are
  /// removed from the value.
  String? doctitle({bool sanitize = false, bool useFallback = false}) {
    var val = attributes['title'];
    if (val == null) {
      final sect = firstSection;
      if (sect != null) {
        val = sect.title;
      } else if (useFallback) {
        val = attributes['untitled-label'];
      }
      if (val == null) return null;
    }
    if (sanitize && val.contains('<')) {
      return collapseRuns(val.replaceAll(xmlSanitizeRx, ''), ' ').trimAscii();
    }
    return val;
  }

  /// Resolves the primary title for the document (see [doctitle]) and
  /// partitions it into a main title and a subtitle at [separator]
  /// (default: the `title-separator` attribute, else `:`).
  ///
  /// Returns `null` when no title resolves.
  DocumentTitle? partitionedTitle({
    String? separator,
    bool sanitize = false,
    bool useFallback = false,
  }) {
    var val = attributes['title'];
    if (val == null) {
      final sect = firstSection;
      if (sect != null) {
        val = sect.title;
      } else if (useFallback) {
        val = attributes['untitled-label'];
      }
      if (val == null) return null;
    }
    return DocumentTitle(
      val,
      separator: separator ?? attributes['title-separator'],
      sanitize: sanitize,
    );
  }

  /// Generates cross reference text that can refer to this document.
  @override
  String? xreftext([String? xrefstyle]) {
    final val = reftext;
    return (val != null && val.isNotEmpty) ? val : title;
  }

  /// The full name of the author.
  String? get author => attributes['author'];

  /// The authors of this document as [DocumentAuthor] records.
  List<DocumentAuthor> get authors {
    final attrs = attributes;
    if (!attrs.containsKey('author')) return <DocumentAuthor>[];
    final result = <DocumentAuthor>[
      DocumentAuthor(
        attrs['author'],
        attrs['firstname'],
        attrs['middlename'],
        attrs['lastname'],
        attrs['authorinitials'],
        attrs['email'],
      ),
    ];
    final numAuthors = parseLeadingInt(attrs['authorcount']);
    if (numAuthors > 1) {
      for (var idx = 2; idx <= numAuthors; idx++) {
        result.add(
          DocumentAuthor(
            attrs['author_$idx'],
            attrs['firstname_$idx'],
            attrs['middlename_$idx'],
            attrs['lastname_$idx'],
            attrs['authorinitials_$idx'],
            attrs['email_$idx'],
          ),
        );
      }
    }
    return result;
  }

  /// The date of last revision for the document.
  String? get revdate => attributes['revdate'];

  /// Whether the `notitle` attribute is set.
  bool get notitle => attributes.containsKey('notitle');

  /// Whether the `noheader` attribute is set.
  bool get noheader => attributes.containsKey('noheader');

  /// Whether the `nofooter` attribute is set.
  bool get nofooter => attributes.containsKey('nofooter');

  /// The header section, or the first section when there is no header.
  Section? get firstSection {
    final head = header;
    if (head != null) return head;
    for (final block in blocks) {
      if (block is Section) return block;
    }
    return null;
  }

  /// Whether the document has a header.
  bool get hasHeader => header != null;

  /// Appends [block] to this document, assigning an index first when the
  /// child is a section.
  @override
  void append(AbstractBlock block) {
    if (block.context == BlockContext.section) assignNumeral(block);
    super.append(block);
  }

  /// Called by the parser after parsing the header and before parsing the
  /// body, even if no header is found.
  ///
  /// Saves the header attributes.
  @internal
  void finalizeHeader() {
    _saveAttributes();
  }

  /// Replays the attribute entries recorded on [block] against the
  /// document.
  @override
  void playbackAttributes(AbstractBlock block) {
    final entries = block.attributeEntries;
    if (entries == null) return;
    for (final entry in entries) {
      final name = entry.name;
      final value = entry.value;
      if (entry.negate || value == null) {
        attributes.remove(name);
        if (name == 'compat-mode') _compatMode = false;
      } else {
        attributes[name] = value;
        if (name == 'compat-mode') _compatMode = true;
      }
    }
  }

  /// Restores the attributes to the previously saved state (the header).
  void restoreAttributes() {
    if (parentDocument == null) callouts.rewind();
    final saved = _headerAttributes!;
    attributes
      ..clear()
      ..addAll(saved);
  }

  /// Sets the attribute [name] on the document unless the name is locked.
  ///
  /// Returns the substituted value, or `null` when the attribute is locked.
  /// Assigning `backend` or `doctype` additionally updates the
  /// backend-related attributes while the header is being parsed.
  String? setAttribute(String name, [String value = '']) {
    if (attributeLocked(name)) return null;
    final resolved = value.isEmpty ? value : applyAttributeValueSubs(value);
    // NOTE if _headerAttributes is set, we're beyond the document header.
    if (_headerAttributes != null) {
      attributes[name] = resolved;
    } else {
      switch (name) {
        case 'backend':
          _updateBackendAttributes(
            resolved,
            _attributesModified.remove('htmlsyntax') && resolved == _backend,
          );
        case 'doctype':
          _updateDoctypeAttributes(resolved);
        default:
          attributes[name] = resolved;
      }
      _attributesModified.add(name);
    }
    return resolved;
  }

  /// Deletes the attribute [name] from the document unless locked.
  ///
  /// Returns whether the attribute was deleted.
  bool deleteAttribute(String name) {
    if (attributeLocked(name)) return false;
    attributes.remove(name);
    _attributesModified.add(name);
    return true;
  }

  /// Whether the attribute [name] is locked (assigned via the API).
  bool attributeLocked(String name) => _attributeOverrides.containsKey(name);

  /// Assigns [value] to the attribute [name] in the document header.
  ///
  /// The assignment is visible when the header attributes are restored
  /// (typically between processor phases). Returns whether the assignment
  /// was performed (`false` only when [overwrite] is `false` and the
  /// attribute already exists).
  bool setHeaderAttribute(String name, String value, {bool overwrite = true}) {
    final attrs = _headerAttributes ?? attributes;
    if (!overwrite && attrs.containsKey(name)) return false;
    attrs[name] = value;
    return true;
  }

  /// Converts the AsciiDoc document using the converter (parsing it first
  /// if needed).
  ///
  /// [standalone] overrides the `standalone` option. [outfile] and
  /// [outdir] name the output file and directory (they set the `outfile`
  /// and `outdir` attributes below the server safe mode; passing any
  /// argument clears whichever of the two is left out).
  @override
  String convert({bool? standalone, String? outfile, String? outdir}) {
    _timings?.start('convert');
    parse();
    if (safe < SafeMode.server &&
        (standalone != null || outfile != null || outdir != null)) {
      if (outfile != null) {
        attributes['outfile'] = outfile;
      } else {
        attributes.remove('outfile');
      }
      if (outdir != null) {
        attributes['outdir'] = outdir;
      } else {
        attributes.remove('outdir');
      }
    }

    var output = '';
    if (doctype == 'inline') {
      final block = blocks.isNotEmpty ? blocks[0] : header;
      if (block != null) {
        if (block.contentModel == ContentModel.compound ||
            block.contentModel == ContentModel.empty) {
          logger.warn(
            'no inline candidate; use the inline doctype to convert a single '
            'paragragh, verbatim, or raw block',
          );
        } else {
          output = block.content() ?? '';
        }
      }
    } else {
      final transform = (standalone ?? options.standalone ?? false)
          ? 'document'
          : 'embedded';
      final nodeConverter = converter;
      output =
          (nodeConverter is Converter
              ? nodeConverter.convert(this, transform)
              : nodeConverter.convert(this)) ??
          '';
    }

    // Postprocessor extensions run after conversion (never for nested
    // documents).
    if (parentDocument == null) {
      final exts = extensions;
      if (exts != null && exts.hasPostprocessors) {
        for (final ext in exts.postprocessors) {
          output = ext.instance.process(this, output);
        }
      }
    }

    _timings?.record('convert');
    return output;
  }

  /// Writes [output] to [sink], followed by a newline (nothing is written
  /// when [output] is empty).
  void writeTo(String output, StringSink sink) {
    _timings?.start('write');
    if (output.isNotEmpty) {
      sink
        ..write(output.withoutTrailingNewline())
        ..write(lf);
    }
    _timings?.record('write');
  }

  /// Writes [output] to the file at [path], then any alternate man pages
  /// the manpage converter produces.
  void writeFile(String output, String path) {
    _timings?.start('write');
    io.writeString(path, output);
    // Only when the converter itself writes alternate pages (the manpage
    // converter, not a template or composite chain).
    if (backend == 'manpage' && converter is ManpageConverter) {
      ManpageConverter.writeAlternatePages(
        mannames,
        attributes['manvolnum'],
        path,
      );
    }
    _timings?.record('write');
  }

  /// The names a man page documents (from the NAME section), set by the
  /// parser for the manpage doctype.
  List<String>? mannames;

  /// Returns the converted result of the child blocks.
  ///
  /// Per the AsciiDoc spec, the `title` attribute is removed before
  /// converting the body.
  @override
  String content() {
    attributes.remove('title');
    return super.content()!;
  }

  /// Reads the docinfo file(s) for inclusion in the document template.
  ///
  /// If the `docinfo1` attribute is set, reads the `docinfo<suffix>` file.
  /// If the `docinfo` attribute is set, reads the
  /// `<docname>-docinfo<suffix>` file. If the `docinfo2` attribute is set,
  /// reads both files in that order. [location] selects the docinfo
  /// location (`'head'` by default); [suffix] defaults to [outfilesuffix].
  ///
  /// Returns the contents of the docinfo file(s), or the empty string when
  /// no files are found or the safe mode is secure or greater.
  String docinfo([String location = 'head', String? suffix]) {
    List<String>? content;
    if (safe < SafeMode.secure) {
      final qualifier = location == 'head' ? '' : '-$location';
      suffix ??= outfilesuffix;

      final docinfoAttr = attributes['docinfo'];
      List<String>? docinfo;
      if (docinfoAttr == null || docinfoAttr.isEmpty) {
        if (attributes.containsKey('docinfo2')) {
          docinfo = <String>['private', 'shared'];
        } else if (attributes.containsKey('docinfo1')) {
          docinfo = <String>['shared'];
        } else {
          docinfo = docinfoAttr != null ? <String>['private'] : null;
        }
      } else {
        docinfo = docinfoAttr
            .split(',')
            .map((keyword) => keyword.trimAscii())
            .toList();
      }

      if (docinfo != null) {
        content = <String>[];
        final docinfoFile = 'docinfo$qualifier$suffix';
        final docinfoDir = attributes['docinfodir'];
        final docinfoSubs = _resolveDocinfoSubs();
        if (docinfo.contains('shared') ||
            docinfo.contains('shared-$location')) {
          final docinfoPath = normalizeSystemPath(
            docinfoFile,
            start: docinfoDir,
          );
          // NOTE normalizing the lines is essential if substitutions run.
          final sharedDocinfo = readAsset(docinfoPath, normalize: true);
          if (sharedDocinfo != null) {
            content.add(applySubs(sharedDocinfo, docinfoSubs));
          }
        }

        final docname = attributes['docname'];
        if (!docname.isNullOrEmpty &&
            (docinfo.contains('private') ||
                docinfo.contains('private-$location'))) {
          final docinfoPath = normalizeSystemPath(
            '$docname-$docinfoFile',
            start: docinfoDir,
          );
          // NOTE normalizing the lines is essential if substitutions run.
          final privateDocinfo = readAsset(docinfoPath, normalize: true);
          if (privateDocinfo != null) {
            content.add(applySubs(privateDocinfo, docinfoSubs));
          }
        }
      }
    }

    // Docinfo processor extensions contribute content for the location.
    if (extensions != null && docinfoProcessors(location)) {
      final extContent = content ?? <String>[];
      for (final ext in _docinfoProcessorExtensions[location]!) {
        final result = ext.instance.process(this);
        if (result != null) extContent.add(result);
      }
      return extContent.join(lf);
    } else if (content != null) {
      return content.join(lf);
    } else {
      return '';
    }
  }

  /// Whether docinfo processor extensions are registered for [location].
  ///
  /// Port of `Document#docinfo_processors?`.
  bool docinfoProcessors([String location = 'head']) {
    final cached = _docinfoProcessorExtensions[location];
    if (cached != null) return cached.isNotEmpty;
    final exts = extensions;
    if (exts != null && exts.hasDocinfoProcessors(location)) {
      _docinfoProcessorExtensions[location] = exts.docinfoProcessors(location);
      return true;
    }
    _docinfoProcessorExtensions[location] =
        const <ProcessorExtension<DocinfoProcessor>>[];
    return false;
  }

  @override
  String toString() {
    final doctitleVal = header?.title;
    return 'Document(doctype: ${debugQuote(doctype)}, '
        'doctitle: ${debugQuote(doctitleVal)}, blocks: ${blocks.length})';
  }

  /// Applies substitutions to the attribute [value].
  ///
  /// A value that is an inline passthrough macro takes the substitutions
  /// defined in it (or is left unmodified when none are specified);
  /// otherwise header substitutions are applied. The result is truncated
  /// to [_maxAttributeValueSize] bytes when a limit is configured.
  @internal
  String applyAttributeValueSubs(String value) {
    final match = attributeEntryPassMacroRx.firstMatch(value);
    final String result;
    if (match != null) {
      result = _applyPassMacroSubs(match.group(2) ?? '', match.group(1));
    } else {
      result = applyHeaderSubs(value);
    }
    final maxSize = _maxAttributeValueSize;
    return maxSize != null ? _limitBytesize(result, maxSize) : result;
  }

  /// Applies header substitutions to [value].
  ///
  /// Port of `Substitutors#apply_header_subs` (via
  /// `Document#apply_attribute_value_subs` in `lib/asciidoctor/document.rb`).
  String applyHeaderSubs(String value) =>
      substitutors.applyHeaderSubs(this, value);

  /// Applies the passthrough-macro [subs] to [value].
  ///
  /// Port of the pass-macro branch of `Document#apply_attribute_value_subs`
  /// (`lib/asciidoctor/document.rb`): a `null` subs list stores the value
  /// verbatim, otherwise the resolved pass subs are applied.
  String _applyPassMacroSubs(String value, String? subs) {
    if (subs == null) return value;
    return substitutors.applySubs(
      this,
      value,
      substitutors.resolvePassSubs(this, subs) ?? <Sub>[],
    );
  }

  /// Safely truncates [str] to [max] bytes.
  ///
  /// A multibyte char split by the cut is dropped whole, so the result is
  /// always valid.
  static String _limitBytesize(String str, int max) {
    final bytes = utf8.encode(str);
    if (bytes.length <= max) return str;
    var end = max;
    while (end > 0) {
      // Find the start of the last char in the prefix.
      var charStart = end - 1;
      while (charStart >= 0 && (bytes[charStart] & 0xC0) == 0x80) {
        charStart--;
      }
      if (charStart < 0) {
        end = 0;
        break;
      }
      final lead = bytes[charStart];
      final expectedLength = lead < 0x80
          ? 1
          : lead < 0xE0
          ? 2
          : lead < 0xF0
          ? 3
          : 4;
      if (charStart + expectedLength <= end) break;
      end = charStart;
    }
    return utf8.decode(bytes.sublist(0, end));
  }

  /// Resolves the substitutions to apply to docinfo files.
  ///
  /// From the `docinfosubs` attribute when set, else `['attributes']`
  /// (port of `resolve_docinfo_subs`; document.rb:1146; an empty value
  /// resolves to no subs).
  List<Sub> _resolveDocinfoSubs() {
    if (attributes.containsKey('docinfosubs')) {
      return substitutors.resolveSubs(
            this,
            attributes['docinfosubs'],
            SubsScope.block,
            null,
            'docinfo',
          ) ??
          <Sub>[];
    }
    return [Sub.attributes];
  }

  /// Creates and initializes the converter for [backend].
  ///
  /// Returns `null` when no converter can be resolved (the caller raises).
  /// Built-in backends resolve through [Converter.create]; anything else
  /// resolves only through the `converter` option or `templateDirs` (a
  /// template chain, bare when the backend is unknown).
  NodeConverter? _createConverter(String backend, String? delegateBackend) {
    final templateDirs = options.templateDirs;
    final converterOpts = ConverterOptions(
      document: this,
      htmlsyntax: attributes['htmlsyntax'],
      templateDirs: templateDirs,
      templateCache: options.templateCache,
      templateCacheStore: options.templateCacheStore,
      templateEngine: options.templateEngine,
      safe: safe,
      delegateBackend: templateDirs.isEmpty ? null : delegateBackend,
    );
    final custom = options.converter;
    if (custom != null) {
      return (CustomFactory()..registerInstance(custom, [backend])).create(
        backend,
        converterOpts,
      );
    }
    final factory = options.converterFactory;
    if (factory != null) return factory.create(backend, converterOpts);
    // Ensure the built-in backends are registered (idempotent), then
    // resolve through the global factory.
    Html5Converter.registerFor();
    Docbook5Converter.registerFor();
    ManpageConverter.registerFor();
    final created = Converter.create(backend, converterOpts);
    if (created != null) return created;
    final builtin = _builtinTraits(backend, attributes['htmlsyntax']);
    if (builtin != null) return _BuiltinConverterStub(backend, builtin);
    if (templateDirs.isNotEmpty) {
      // A template chain: traits come from the delegate backend when it is
      // built in, else they are derived from the backend name.
      if (delegateBackend != null) {
        final delegateTraits = _builtinTraits(
          delegateBackend,
          attributes['htmlsyntax'],
        );
        if (delegateTraits != null) {
          return _BuiltinConverterStub(backend, delegateTraits);
        }
      }
      return _BuiltinConverterStub(backend, null);
    }
    return null;
  }

  /// The traits of the built-in converter for [backend], or `null`.
  ///
  /// The html5 converter reports `xml` htmlsyntax when the `htmlsyntax`
  /// attribute ([htmlsyntaxAttr]) is `'xml'`, else `html`.
  static _BackendTraits? _builtinTraits(
    String backend,
    String? htmlsyntaxAttr,
  ) {
    switch (backend) {
      case 'html5':
        return _BackendTraits(
          basebackend: 'html',
          filetype: 'html',
          outfilesuffix: '.html',
          htmlsyntax: htmlsyntaxAttr == 'xml' ? 'xml' : 'html',
        );
      case 'docbook5':
        return const _BackendTraits(
          basebackend: 'docbook',
          filetype: 'xml',
          outfilesuffix: '.xml',
        );
      case 'manpage':
        return const _BackendTraits(
          basebackend: 'manpage',
          filetype: 'man',
          outfilesuffix: '.man',
        );
      default:
        return null;
    }
  }

  /// Derives backend traits from [backend].
  ///
  /// Port of `Converter.derive_backend_traits`.
  static _BackendTraits _deriveBackendTraits(
    String backend, [
    String? basebackend,
  ]) {
    final base = basebackend ?? backend.replaceFirst(trailingDigitsRx, '');
    final suffix = defaultExtensions[base];
    final String filetype;
    final String outfilesuffix;
    if (suffix != null) {
      outfilesuffix = suffix;
      filetype = suffix.substring(1);
    } else {
      filetype = base;
      outfilesuffix = '.$base';
    }
    return _BackendTraits(
      basebackend: base,
      filetype: filetype,
      outfilesuffix: outfilesuffix,
      htmlsyntax: filetype == 'html' ? 'html' : null,
    );
  }

  /// Branches the attributes so the original state can be restored later.
  void _saveAttributes() {
    final attrs = attributes;
    if (!attrs.containsKey('doctitle')) {
      final doctitleVal = doctitle();
      if (doctitleVal != null) attrs['doctitle'] = doctitleVal;
    }

    // css-signature cannot be updated after header attributes are processed.
    id ??= attrs['css-signature'];

    final deletedToc2 = attrs.remove('toc2');
    final tocVal = deletedToc2 != null ? 'left' : attrs['toc'];
    if (tocVal != null) {
      // toc-placement separates position from fitted slot vs macro.
      final tocPlacementVal = attrs.containsKey('toc-placement')
          ? attrs['toc-placement']
          : 'macro';
      final tocPositionVal =
          tocPlacementVal != null && tocPlacementVal != 'auto'
          ? tocPlacementVal
          : attrs['toc-position'];
      final toc = tocVal;
      if (!(toc.isEmpty && tocPositionVal.isNullOrEmpty)) {
        const defaultTocPosition = 'left';
        // TODO rename toc2 to aside-toc
        String? defaultTocClass = 'toc2';
        final position = tocPositionVal == null || tocPositionVal.isEmpty
            ? (toc.isEmpty ? defaultTocPosition : toc)
            : tocPositionVal;
        attrs['toc'] = '';
        attrs['toc-placement'] = 'auto';
        switch (position) {
          case 'left' || '<' || '&lt;':
            attrs['toc-position'] = 'left';
          case 'right' || '>' || '&gt;':
            attrs['toc-position'] = 'right';
          case 'top' || '^':
            attrs['toc-position'] = 'top';
          case 'bottom' || 'v':
            attrs['toc-position'] = 'bottom';
          case 'preamble' || 'macro':
            attrs['toc-position'] = 'content';
            attrs['toc-placement'] = position;
            defaultTocClass = null;
          default:
            attrs.remove('toc-position');
            defaultTocClass = null;
        }
        if (defaultTocClass != null) attrs['toc-class'] ??= defaultTocClass;
      }
    }

    final iconsVal = attrs['icons'];
    if (iconsVal != null && !attrs.containsKey('icontype')) {
      if (iconsVal != '' && iconsVal != 'font') {
        attrs['icons'] = '';
        if (iconsVal != 'image') attrs['icontype'] = iconsVal;
      }
    }

    _compatMode = attrs.containsKey('compat-mode');
    if (_compatMode && attrs.containsKey('language')) {
      attrs['source-language'] = attrs['language']!;
    }

    if (parentDocument == null) {
      final basebackend = attrs['basebackend'];
      if (basebackend == 'html') {
        final syntaxHlName = attrs['source-highlighter'];
        if (syntaxHlName != null &&
            !attrs.containsKey('$syntaxHlName-unavailable')) {
          // Resolve the syntax highlighter, honoring the
          // `syntaxHighlighterFactory` and `syntaxHighlighters` options.
          syntaxHighlighter = SyntaxHighlighter.resolveForDocument(this);
        }
        // Enable toc and sectnums (i.e., numbered) by default in DocBook
        // backend.
      } else if (basebackend == 'docbook') {
        // NOTE attributesModified goes away once attribute storage and
        // tracking is centralized.
        if (!attributeLocked('toc') && !_attributesModified.contains('toc')) {
          attrs['toc'] = '';
        }
        if (!attributeLocked('sectnums') &&
            !_attributesModified.contains('sectnums')) {
          attrs['sectnums'] = '';
        }
      }

      // NOTE pin the outfilesuffix after the header is parsed.
      outfilesuffix = attrs['outfilesuffix'];

      // Unfreeze "flexible" attributes.
      for (final name in flexibleAttributes) {
        // Turning a flexible attribute off should be permanent
        // (we may need more config if that's not always the case).
        if (_attributeOverrides[name] != null) {
          _attributeOverrides.remove(name);
        }
      }
    }

    _headerAttributes = Map<String, String>.of(attrs);
  }

  /// Assigns the local and document datetime attributes.
  ///
  /// Honors the `SOURCE_DATE_EPOCH` environment variable when set.
  static void _fillDatetimeAttributes(
    Map<String, String> attrs,
    DateTime? inputMtime,
  ) {
    // See https://reproducible-builds.org/specs/source-date-epoch/
    final epochEnv = io.environment['SOURCE_DATE_EPOCH'];
    final DateTime now;
    final DateTime? sourceDateEpoch;
    if (epochEnv == null || epochEnv.isEmpty) {
      now = DateTime.now();
      sourceDateEpoch = null;
    } else {
      sourceDateEpoch = DateTime.fromMillisecondsSinceEpoch(
        int.parse(epochEnv) * 1000,
        isUtc: true,
      );
      now = sourceDateEpoch;
    }
    final localdateOpt = attrs['localdate'];
    final String localdate;
    if (localdateOpt != null) {
      localdate = localdateOpt;
      if (!attrs.containsKey('localyear') && localdate.indexOf('-') == 4) {
        attrs['localyear'] = localdate.substring(0, 4);
      }
    } else {
      localdate = attrs['localdate'] = _formatDate(now);
      attrs['localyear'] ??= now.year.toString();
    }
    // %Z is OS dependent and may contain characters that aren't UTF-8
    // encoded, so the offset is formatted manually instead.
    final localtime = attrs['localtime'] ??= _formatTime(now);
    attrs['localdatetime'] ??= '$localdate $localtime';
    // docdate, doctime and docdatetime default to localdate, localtime and
    // localdatetime when not otherwise set.
    final mtime = sourceDateEpoch ?? inputMtime ?? now;
    final docdateOpt = attrs['docdate'];
    final String docdate;
    if (docdateOpt != null) {
      docdate = docdateOpt;
      if (!attrs.containsKey('docyear') && docdate.indexOf('-') == 4) {
        attrs['docyear'] = docdate.substring(0, 4);
      }
    } else {
      docdate = attrs['docdate'] = _formatDate(mtime);
      attrs['docyear'] ??= mtime.year.toString();
    }
    final doctime = attrs['doctime'] ??= _formatTime(mtime);
    attrs['docdatetime'] ??= '$docdate $doctime';
  }

  /// Formats [time] as `yyyy-MM-dd`.
  static String _formatDate(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  /// Formats [time] as `HH:mm:ss <zone>` with `UTC` for a zero offset,
  /// else `+HHMM`/`-HHMM`.
  static String _formatTime(DateTime time) {
    final offset = time.timeZoneOffset;
    final zone = offset == Duration.zero
        ? 'UTC'
        : '${offset.isNegative ? '-' : '+'}'
              '${offset.inHours.abs().toString().padLeft(2, '0')}'
              '${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')} $zone';
  }

  /// Updates the backend attributes to reflect [newBackend].
  ///
  /// Also updates the related doctype attributes when the doctype is
  /// assigned. Returns the resolved backend, or `null` when unchanged.
  String? _updateBackendAttributes(String newBackend, [bool init = false]) {
    if (!init && newBackend == _backend) return null;
    final attrs = attributes;
    final currentBackend = _backend;
    final currentBasebackend = attrs['basebackend'];
    final currentDoctype = _doctype;
    String? actualBackend;
    var backend = newBackend;
    if (backend.contains(':')) {
      final idx = backend.indexOf(':');
      actualBackend = backend.substring(0, idx);
      backend = backend.substring(idx + 1);
    }
    if (backend.startsWith('xhtml')) {
      attrs['htmlsyntax'] = 'xml';
      backend = backend.substring(1);
    } else if (backend.startsWith('html')) {
      attrs['htmlsyntax'] ??= 'html';
    }
    backend = backendAliases[backend] ?? backend;
    String? delegateBackend;
    if (actualBackend != null) {
      delegateBackend = backend;
      backend = actualBackend;
    }
    if (currentDoctype != null) {
      if (currentBackend != null) {
        attrs
          ..remove('backend-$currentBackend')
          ..remove('backend-$currentBackend-doctype-$currentDoctype');
      }
      attrs['backend-$backend-doctype-$currentDoctype'] = '';
      attrs['doctype-$currentDoctype'] = '';
    } else if (currentBackend != null) {
      attrs.remove('backend-$currentBackend');
    }
    attrs['backend-$backend'] = '';
    // QUESTION should the _backend assignment wait until the converter
    // is created?
    _backend = attrs['backend'] = backend;
    // (Re)initialize the converter.
    final resolvedConverter = _createConverter(backend, delegateBackend);
    if (resolvedConverter == null) {
      // NOTE ideally the converter isn't needed before the converter
      // phase, but it is.
      throw AsciidoctorException("missing converter for backend '$backend'");
    }
    final _BackendTraits traits;
    if (resolvedConverter is _BuiltinConverterStub &&
        resolvedConverter.hasTraits) {
      traits = resolvedConverter.traits!;
      final htmlsyntax = traits.htmlsyntax;
      if (htmlsyntax != null) attrs['htmlsyntax'] = htmlsyntax;
      _assignOutfilesuffix(attrs, traits.outfilesuffix, init);
    } else if (resolvedConverter is Converter) {
      // Port of the `Converter::BackendTraits === converter` branch of
      // `update_backend_attributes` (lib/asciidoctor/document.rb:1203-1212):
      // a resolved converter carries its own traits (in particular, it may
      // override `htmlsyntax`, as `Converter.create 'html5', htmlsyntax:
      // 'xml'` does).
      final converterTraits = resolvedConverter.backendTraits;
      traits = _BackendTraits(
        basebackend: converterTraits.basebackend,
        filetype: converterTraits.filetype,
        outfilesuffix: converterTraits.outfilesuffix,
        htmlsyntax: converterTraits.htmlsyntax,
      );
      final htmlsyntax = traits.htmlsyntax;
      if (htmlsyntax != null) attrs['htmlsyntax'] = htmlsyntax;
      _assignOutfilesuffix(attrs, traits.outfilesuffix, init);
    } else {
      traits = _deriveBackendTraits(backend);
      _assignOutfilesuffix(attrs, traits.outfilesuffix, init);
    }
    converter = resolvedConverter;
    final currentFiletype = attrs['filetype'];
    if (currentFiletype != null) attrs.remove('filetype-$currentFiletype');
    attrs['filetype'] = traits.filetype;
    attrs['filetype-${traits.filetype}'] = '';
    final pageWidth = defaultPageWidths[traits.basebackend];
    if (pageWidth != null) {
      attrs['pagewidth'] = '$pageWidth';
    } else {
      attrs.remove('pagewidth');
    }
    if (traits.basebackend != currentBasebackend) {
      if (currentDoctype != null) {
        if (currentBasebackend != null) {
          attrs
            ..remove('basebackend-$currentBasebackend')
            ..remove('basebackend-$currentBasebackend-doctype-$currentDoctype');
        }
        attrs['basebackend-${traits.basebackend}-doctype-$currentDoctype'] = '';
      } else if (currentBasebackend != null) {
        attrs.remove('basebackend-$currentBasebackend');
      }
      attrs['basebackend-${traits.basebackend}'] = '';
      attrs['basebackend'] = traits.basebackend;
    }
    return backend;
  }

  /// Assigns the converter [outfilesuffix] during backend setup.
  void _assignOutfilesuffix(
    Map<String, String> attrs,
    String outfilesuffix,
    bool init,
  ) {
    if (init) {
      attrs['outfilesuffix'] ??= outfilesuffix;
    } else {
      if (!attributeLocked('outfilesuffix')) {
        attrs['outfilesuffix'] = outfilesuffix;
      }
    }
  }

  /// Updates the doctype and backend attributes for [newDoctype].
  ///
  /// Returns the doctype, or `null` when unchanged.
  String? _updateDoctypeAttributes(String? newDoctype) {
    if (newDoctype == null || newDoctype == _doctype) return null;
    final currentBackend = _backend;
    final currentBasebackend = attributes['basebackend'];
    final currentDoctype = _doctype;
    final attrs = attributes;
    if (currentDoctype != null) {
      attrs.remove('doctype-$currentDoctype');
      if (currentBackend != null) {
        attrs.remove('backend-$currentBackend-doctype-$currentDoctype');
        attrs['backend-$currentBackend-doctype-$newDoctype'] = '';
      }
      if (currentBasebackend != null) {
        attrs.remove('basebackend-$currentBasebackend-doctype-$currentDoctype');
        attrs['basebackend-$currentBasebackend-doctype-$newDoctype'] = '';
      }
    } else {
      if (currentBackend != null) {
        attrs['backend-$currentBackend-doctype-$newDoctype'] = '';
      }
      if (currentBasebackend != null) {
        attrs['basebackend-$currentBasebackend-doctype-$newDoctype'] = '';
      }
    }
    attrs['doctype-$newDoctype'] = '';
    _doctype = attrs['doctype'] = newDoctype;
    return newDoctype;
  }

  /// Expands [path] against the working directory.
  String _expandBaseDir(String path) {
    final absolute = pathResolver.isRoot(path)
        ? path
        : pathResolver.joinPath(<String>[io.currentDirectory, path]);
    return pathResolver.expandPath(absolute);
  }

  /// The user's home directory.
  static String get _userHome => io.environment['HOME'] ?? io.currentDirectory;

  /// Mirrors a `showtitle`/`notitle` API override to its counterpart: an
  /// unset sets the counterpart, a soft unset sets it softly (`@`), a soft
  /// set (`@`) unsets it softly, and any other value unsets it.
  static _Override _mirrorShowtitle(_Override value) => switch (value) {
    _Unset() => const _SetValue(''),
    _SoftUnset() => const _SetValue('@'),
    _SetValue(value: '@') => const _SoftUnset(),
    _SetValue() => const _Unset(),
  };

  /// Returns the next value in the sequence after [current]: the next
  /// integer when [current] spells one, else its string successor
  /// ([_succ]).
  static String _nextval(String current) {
    final intval = _parseLeadingInt(current);
    if (intval != null && intval.toString() == current) {
      return (intval + BigInt.one).toString();
    }
    return _succ(current);
  }

  /// Parses the leading integer of [value].
  ///
  /// Returns `null` when the value has no leading integer. [BigInt] is used
  /// so arbitrarily large values parse exactly.
  static BigInt? _parseLeadingInt(String value) {
    final match = _leadingIntRx.firstMatch(value);
    if (match == null) return null;
    return BigInt.parse(match.group(0)!.trimAscii());
  }

  static final RegExp _leadingIntRx = RegExp(r'^[ \t\n\v\f\r]*[+-]?\d+');

  /// Converts [value] to an integer by its leading integer (else 0).
  ///
  /// Values exceeding the 64-bit range saturate at the largest integer
  /// (used for sizes, where a huge value behaves like no effective limit).
  static int _toIntSaturating(String value) {
    final match = _leadingIntRx.firstMatch(value);
    if (match == null) return 0;
    final parsed = BigInt.parse(match.group(0)!.trimAscii());
    if (parsed.isValidInt) return parsed.toInt();
    return parsed.isNegative ? -_maxInt : _maxInt;
  }

  static final int _maxInt = ((BigInt.one << 63) - BigInt.one).toInt();

  /// Returns the successor of [s] (`'a'` to `'b'`, `'az'` to `'ba'`,
  /// `'9'` to `'10'`).
  ///
  /// The last alphanumeric run (ASCII letters and digits) is incremented
  /// with carry; when it overflows, the carry crosses separators to the
  /// previous run when that run ends in the same class (digit or letter),
  /// else the carry char (`'1'`, `'a'`, `'A'`) is inserted at the run
  /// start. With no alphanumeric char, the last char is incremented by
  /// codepoint. Verified against Asciidoctor, including `'19-99'` -> `'20-00'`,
  /// `'a-9'` -> `'a-10'`, `'9-Z'` -> `'9-AA'` and `'a-Z'` -> `'b-A'`.
  static String _succ(String s) {
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    bool isUpper(int c) => c >= 0x41 && c <= 0x5A;
    bool isLower(int c) => c >= 0x61 && c <= 0x7A;
    bool isAlnum(int c) => isDigit(c) || isUpper(c) || isLower(c);

    if (s.isEmpty) return s;
    final units = s.codeUnits;
    var runEnd = units.length - 1;
    while (runEnd >= 0 && !isAlnum(units[runEnd])) {
      runEnd--;
    }
    if (runEnd < 0) {
      final runes = s.runes.toList();
      final last = runes.removeLast();
      return String.fromCharCodes(<int>[...runes, last + 1]);
    }
    final buf = List<int>.of(units);
    var runStart = runEnd;
    while (runStart > 0 && isAlnum(buf[runStart - 1])) {
      runStart--;
    }
    while (true) {
      var carry = true;
      var carryChar = 0x31;
      var i = runEnd;
      while (carry && i >= runStart) {
        final c = buf[i];
        if (isDigit(c)) {
          if (c == 0x39) {
            buf[i] = 0x30;
            carryChar = 0x31;
          } else {
            buf[i] = c + 1;
            carry = false;
          }
        } else if (isLower(c)) {
          if (c == 0x7A) {
            buf[i] = 0x61;
            carryChar = 0x61;
          } else {
            buf[i] = c + 1;
            carry = false;
          }
        } else {
          if (c == 0x5A) {
            buf[i] = 0x41;
            carryChar = 0x41;
          } else {
            buf[i] = c + 1;
            carry = false;
          }
        }
        i--;
      }
      if (!carry) return String.fromCharCodes(buf);
      var prev = runStart - 1;
      while (prev >= 0 && !isAlnum(buf[prev])) {
        prev--;
      }
      if (prev < 0 || isDigit(buf[prev]) != (carryChar == 0x31)) {
        buf.insert(runStart, carryChar);
        return String.fromCharCodes(buf);
      }
      runEnd = prev;
      runStart = prev;
      while (runStart > 0 && isAlnum(buf[runStart - 1])) {
        runStart--;
      }
    }
  }
}
