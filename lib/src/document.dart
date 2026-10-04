// Deprecated aliases mirror Ruby; removed only when upstream removes them.
// Positional params mirror Ruby signatures for port fidelity.
// ignore_for_file: remove_deprecations_in_breaking_versions, avoid_positional_boolean_parameters
/// The document node: root of a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/document.rb` (complete).
///
/// Ruby symbols (`:paragraph`, `:document`, ...) are represented as `String`s
/// throughout this port, so a Ruby context of `:document` becomes the Dart
/// string `'document'`.
///
/// Several collaborators live in waves that have not landed yet:
///
/// * The parser wave replaces the [Parser] stub (`parser.dart`) and un-skips
///   the parse-dependent tests. Until then [Document.parse] (and everything
///   that parses, such as [Document.convert]) throws [UnimplementedError].
/// * Ported backend converters (html5, docbook5, manpage) register
///   with [Converter] and [Document] resolves them through
///   [Converter.create]. Until a backend lands, [Document] carries a minimal
///   internal stub ([_BuiltinConverterStub]) that reports the built-in
///   backend traits (basebackend, filetype, outfilesuffix, htmlsyntax) so
///   constructor-level behavior is byte-identical; calling `convert` on the
///   stub throws [UnimplementedError]. [Document.convert] calls the
///   single-argument `NodeConverter.convert`.
/// * The substitutors wave fills in the private `_resolveDocinfoSubs`
///   stub (throwing [UnimplementedError] until then); [applyHeaderSubs]
///   and `_applyPassMacroSubs` are ported.
/// * Extension integration is ported: the `extensions` and
///   `extension_registry` options activate a [Registry] into
///   [Document.extensions], pre/tree/postprocessors and docinfo processors
///   run, and the `converter`/`converter_factory` options resolve through
///   [CustomFactory]/[ConverterFactory].
/// * [Document.syntaxHighlighter] resolves from the `source-highlighter`
///   attribute when the header is saved.
///
/// [Timings] (from `timings.dart`) records the read/parse/convert/write
/// phase durations surfaced via the `timings` option and `--timings`.
library;

import 'dart:convert' show Encoding, utf8;
import 'dart:io' show Directory, File, IOSink, Platform;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/callouts.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/docbook5.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/manpage.dart';
import 'package:asciidoctor/src/parser.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/substitutors.dart' as substitutors;
import 'package:asciidoctor/src/timings.dart';
import 'package:asciidoctor/src/version.dart';

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
  new(this.name, this.value, [bool? negate])
    : negate = negate ?? (value == null);

  /// The attribute name.
  final String name;

  /// The attribute value (`null` for an unset marker).
  final Object? value;

  /// Whether this entry unsets the attribute.
  final bool negate;

  /// Records this entry in [blockAttributes] under `'attribute_entries'`.
  ///
  /// Returns this entry. (Ruby keys the entry list with a symbol; the port
  /// uses the string `'attribute_entries'` per the symbols-become-strings
  /// convention.)
  DocumentAttributeEntry saveTo(Map<String, Object?> blockAttributes) {
    var entries = blockAttributes['attribute_entries'];
    if (entries == null || entries == false) {
      entries = <DocumentAttributeEntry>[];
      blockAttributes['attribute_entries'] = entries;
    }
    (entries as List<DocumentAttributeEntry>).add(this);
    return this;
  }
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
      text = squeezeChar(text.replaceAll(xmlSanitizeRx, ''), ' ').trim();
    }
    var sep = separator ?? ':';
    if (sep.isEmpty || !text.contains(sep = '$sep ')) {
      main = text;
      subtitle = null;
    } else {
      // Mirrors Ruby's `String#rpartition` (split at the last occurrence).
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
  final Object? imagesdir;

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

  /// The footnote index.
  final Object? index;

  /// The footnote id.
  final Object? id;

  /// The footnote text.
  final Object? text;
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

/// Minimal stand-in for a converter until the converter wave lands.
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
  Object? convert(AbstractNode node) => throw UnimplementedError(
    'Converter wave: no converter for backend "$backend" is ported yet.',
  );
}

/// Adapts a [Document] to the [ReaderDocument] interface.
///
/// A separate adapter (rather than `Document implements ReaderDocument`) is
/// required because [AbstractNode.normalizeSystemPath] takes `start` as a
/// named parameter while [ReaderDocument.normalizeSystemPath] takes it
/// positionally, so the two signatures cannot be satisfied by one method.
/// The substitutor entry points ([subAttributes], [parseAttributes])
/// delegate to the top-level `substitutors.dart` functions.
class _ReaderDocumentAdapter implements ReaderDocument {
  /// Creates an adapter delegating to [document].
  new(this._document);

  final Document _document;

  @override
  Map<String, Object?> get attributes => _document.attributes;

  @override
  Object? attr(String name) => _document.attr(name);

  @override
  bool attrSet(String name) => _document.hasAttr(name);

  @override
  bool get sourcemap => _document.sourcemap;

  @override
  int get safe => _document.safe;

  @override
  String get baseDir => _document.baseDir;

  @override
  PathResolver get pathResolver => _document.pathResolver;

  @override
  Map<String, bool?> get catalogIncludes =>
      _document.catalog['includes']! as Map<String, bool?>;

  @override
  List<ReaderIncludeProcessor>? get includeProcessors {
    // Port of the `Document` half of the include-processor lookup
    // (`PreprocessorReader#preprocess_include_directive` consults the
    // registry through the document): registered include processors
    // handle targets before the file system is tried.
    final exts = _document.extensions;
    if (exts == null || !exts.hasIncludeProcessors) return null;
    return exts.includeProcessors
        .map((ext) => ext.instance as ReaderIncludeProcessor)
        .toList();
  }

  @override
  String normalizeSystemPath(
    String target,
    String? start, {
    String? targetName,
  }) => _document.normalizeSystemPath(
    target,
    start: start,
    targetName: targetName ?? 'path',
  );

  @override
  String subAttributes(
    String text, {
    String? attributeMissing,
    String dropLineSeverity = 'info',
  }) => substitutors.subAttributes(
    _document,
    text,
    attributeMissing: attributeMissing,
    dropLineSeverity: dropLineSeverity,
  );

  @override
  Map<Object, String?> parseAttributes(
    String? attrlist, {
    bool subInput = false,
  }) => substitutors
      .parseAttributes(_document, attrlist, subInput: subInput)
      .cast<Object, String?>();

  @override
  String? readUri(Uri uri, Encoding encoding) =>
      _document.readUri(uri, encoding);
}

/// Exposes a reader [Cursor] as a [NodeSourceLocation].
class _CursorSourceLocation implements NodeSourceLocation {
  /// Creates a source location from [cursor].
  new(this._cursor);

  final Cursor _cursor;

  @override
  String? get file {
    final file = _cursor.file;
    return file is String ? file : file?.toString();
  }

  @override
  int? get lineno => _cursor.lineno;
}

/// The root node of a parsed AsciiDoc document.
///
/// Port of `Asciidoctor::Document`.
class Document extends AbstractBlock implements NodeDocument {
  /// Creates a document for [data] with [options].
  ///
  /// [data] is the AsciiDoc source as a string, a list of lines, or `null`
  /// for an empty document. [options] mirrors the Ruby options hash with
  /// string keys (`'safe'`, `'backend'`, `'doctype'`, `'attributes'`,
  /// `'standalone'`, `'header_footer'`, `'base_dir'`, `'to_file'`,
  /// `'to_dir'`, `'sourcemap'`, `'timings'`, `'input_mtime'` (a [DateTime]),
  /// `'parse_header_only'`, `'catalog_assets'`, `'converter'`, `'template_dirs'`,
  /// `'cursor'`, `'parent'`, ...). The map is copied, never mutated.
  new([Object? data, Map<String, Object?>? options]) : super(null, 'document') {
    final opts = Map<String, Object?>.of(options ?? const <String, Object?>{});
    final parentDoc = opts.remove('parent') as Document?;
    final attrOverrides = <String, Object?>{};
    String? parentDoctype;
    Object? inputMtime;

    if (parentDoc != null) {
      parentDocument = parentDoc;
      if (!isTruthy(opts['base_dir'])) opts['base_dir'] = parentDoc.baseDir;
      if (isTruthy(parentDoc.options['catalog_assets'])) {
        opts['catalog_assets'] = true;
      }
      final parentToDir = parentDoc.options['to_dir'];
      if (isTruthy(parentToDir)) opts['to_dir'] = parentToDir;
      catalog = <String, Object?>{
        ...parentDoc.catalog,
        'footnotes': <Footnote>[],
      };
      attrOverrides.addAll(parentDoc._attributeOverrides);
      attrOverrides.addAll(parentDoc.attributes);
      attrOverrides.remove('compat-mode');
      parentDoctype = attrOverrides.remove('doctype') as String?;
      attrOverrides.remove('notitle');
      attrOverrides.remove('showtitle');
      attrOverrides.remove('toc');
      final tocPlacement = attrOverrides.remove('toc-placement');
      attributes['toc-placement'] = isTruthy(tocPlacement)
          ? tocPlacement
          : 'auto';
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
      catalog = <String, Object?>{
        'ids': <String, Object?>{},
        'refs': <String, Object?>{},
        'footnotes': <Footnote>[],
        'links': <String>[],
        'images': <ImageReference>[],
        'callouts': Callouts(),
        'includes': <String, bool?>{},
      };
      final attrsOpt = opts['attributes'];
      if (attrsOpt != null) {
        if (attrsOpt is! Map) {
          throw ArgumentError.value(
            attrsOpt,
            'attributes',
            'must be a Map of attribute names to values',
          );
        }
        attrsOpt.forEach((key, val) {
          var name = key as String;
          Object? value = val;
          if (name.endsWith('@')) {
            if (name.startsWith('!')) {
              name = name.substring(1, name.length - 1);
              value = false;
            } else if (name.endsWith('!@')) {
              name = name.substring(0, name.length - 2);
              value = false;
            } else {
              name = name.substring(0, name.length - 1);
              value = '$value@';
            }
          } else if (name.startsWith('!')) {
            name = name.substring(1);
            value = value == '@' ? false : null;
          } else if (name.endsWith('!')) {
            name = name.substring(0, name.length - 1);
            value = value == '@' ? false : null;
          }
          attrOverrides[name.toLowerCase()] = value;
        });
      }
      final toFile = opts['to_file'];
      if (toFile is String) {
        attrOverrides['outfilesuffix'] = Helpers.extname(toFile) ?? '';
      }
      final safeOpt = opts['safe'];
      if (safeOpt == null || safeOpt == false) {
        safe = SafeMode.secure;
      } else if (safeOpt is int) {
        safe = safeOpt;
      } else {
        safe = safeModeValueForName(safeOpt.toString()) ?? SafeMode.secure;
      }
      inputMtime = opts.remove('input_mtime');
      _compatMode = attrOverrides.containsKey('compat-mode');
      sourcemap = isTruthy(opts['sourcemap']);
      _timings = opts.remove('timings') as Timings?;
      pathResolver = PathResolver(onWarn: (message) => logger.warn(message));
      extensions = null;
      if (opts.containsKey('header_footer') &&
          !opts.containsKey('standalone')) {
        opts['standalone'] = opts['header_footer'];
      }
    }

    _parsed = false;
    _reftexts = null;
    header = null;
    _headerAttributes = null;
    _attributeOverrides = attrOverrides;
    final standalone = opts['standalone'];
    this.options = Map<String, Object?>.unmodifiable(opts);

    final attrs = attributes;
    if (parentDoc == null) {
      attrs['attribute-undefined'] = Compliance.attributeUndefined;
      attrs['attribute-missing'] = Compliance.attributeMissing;
      attrs.addAll(defaultAttributes);
    }

    if (isTruthy(standalone)) {
      // Sync the embedded attribute with the standalone option value.
      attrOverrides['embedded'] = null;
      attrs['copycss'] = '';
      attrs['iconfont-remote'] = '';
      attrs['stylesheet'] = '';
      attrs['webfonts'] = '';
    } else {
      // Sync the embedded attribute with the standalone option value.
      attrOverrides['embedded'] = '';
      String? lastShowtitleKey;
      for (final key in attrOverrides.keys) {
        if (key == 'notitle' || key == 'showtitle') lastShowtitleKey = key;
      }
      if (attrOverrides.containsKey('showtitle') &&
          lastShowtitleKey == 'showtitle') {
        attrOverrides['notitle'] = _mirrorShowtitle(attrOverrides['showtitle']);
      } else if (attrOverrides.containsKey('notitle')) {
        attrOverrides['showtitle'] = _mirrorShowtitle(attrOverrides['notitle']);
      } else {
        attrs['notitle'] = '';
      }
    }

    attrOverrides['asciidoctor'] = '';
    attrOverrides['asciidoctor-version'] = Asciidoctor.version;

    final safeModeName = safeModeNameForValue(safe);
    attrOverrides['safe-mode-name'] = safeModeName;
    attrOverrides['safe-mode-${safeModeName ?? ''}'] = '';
    attrOverrides['safe-mode-level'] = safe;

    // The only way to set max-include-depth is via the API (default 64).
    if (!isTruthy(attrOverrides['max-include-depth'])) {
      attrOverrides['max-include-depth'] = 64;
    }
    // The only way to set allow-uri-read is via the API (disabled by default).
    if (!isTruthy(attrOverrides['allow-uri-read'])) {
      attrOverrides['allow-uri-read'] = null;
    }

    // Remap legacy attribute names.
    if (attrOverrides.containsKey('numbered')) {
      attrOverrides['sectnums'] = attrOverrides.remove('numbered');
    }
    if (attrOverrides.containsKey('hardbreaks')) {
      attrOverrides['hardbreaks-option'] = attrOverrides.remove('hardbreaks');
    }

    final baseDirOpt = opts['base_dir'];
    if (isTruthy(baseDirOpt)) {
      baseDir = attrOverrides['docdir'] = _expandBaseDir(baseDirOpt.toString());
    } else if (isTruthy(attrOverrides['docdir'])) {
      baseDir = attrOverrides['docdir']! as String;
    } else {
      baseDir = attrOverrides['docdir'] = Directory.current.path;
    }

    // Allow backend and doctype to be set using the options map.
    final backendOpt = opts['backend'];
    if (isTruthy(backendOpt)) {
      attrOverrides['backend'] = backendOpt.toString();
    }
    final doctypeOpt = opts['doctype'];
    if (isTruthy(doctypeOpt)) {
      attrOverrides['doctype'] = doctypeOpt.toString();
    }

    if (safe >= SafeMode.server) {
      // Restrict the document from setting copycss, source-highlighter
      // and backend.
      if (!isTruthy(attrOverrides['copycss'])) {
        attrOverrides['copycss'] = null;
      }
      if (!isTruthy(attrOverrides['source-highlighter'])) {
        attrOverrides['source-highlighter'] = null;
      }
      if (!isTruthy(attrOverrides['backend'])) {
        attrOverrides['backend'] = defaultBackend;
      }
      // Restrict the document from seeing docdir; trim docfile to a
      // relative path.
      if (parentDoc == null && attrOverrides.containsKey('docfile')) {
        final docfile = attrOverrides['docfile']! as String;
        final docdir = attrOverrides['docdir']! as String;
        final start = docdir.length + 1;
        attrOverrides['docfile'] = start <= docfile.length
            ? docfile.substring(start)
            : null;
      }
      attrOverrides['docdir'] = '';
      if (!isTruthy(attrOverrides['user-home'])) {
        attrOverrides['user-home'] = '.';
      }
      if (safe >= SafeMode.secure) {
        if (!attrOverrides.containsKey('max-attribute-value-size')) {
          attrOverrides['max-attribute-value-size'] = 4096;
        }
        // Assign linkcss (preventing CSS embedding) unless explicitly
        // disabled from the commandline or API.
        if (!attrOverrides.containsKey('linkcss')) {
          attrOverrides['linkcss'] = '';
        }
        // Restrict the document from enabling icons.
        if (!isTruthy(attrOverrides['icons'])) attrOverrides['icons'] = null;
      }
    } else {
      if (!isTruthy(attrOverrides['user-home'])) {
        attrOverrides['user-home'] = _userHome;
      }
    }

    // The only way to set max-attribute-value-size is via the API
    // (disabled by default).
    if (!isTruthy(attrOverrides['max-attribute-value-size'])) {
      attrOverrides['max-attribute-value-size'] = null;
    }
    final maxSize = attrOverrides['max-attribute-value-size'];
    _maxAttributeValueSize = isTruthy(maxSize)
        ? _rubyToInt(maxSize).abs()
        : null;

    final unlockedKeys = <String>[];
    for (final entry in attrOverrides.entries.toList()) {
      final key = entry.key;
      final val = entry.value;
      if (isTruthy(val)) {
        // A value ending in @ allows the document to override the value.
        var newVal = val;
        var verdict = false;
        if (val is String && val.endsWith('@')) {
          newVal = val.substring(0, val.length - 1);
          verdict = true;
        }
        attrs[key] = newVal;
        if (verdict) unlockedKeys.add(key);
      } else {
        // A nil or false value both unset the attribute; only a nil value
        // locks it.
        attrs.remove(key);
        if (val == false) unlockedKeys.add(key);
      }
    }
    for (final key in unlockedKeys) {
      attrOverrides.remove(key);
    }

    if (parentDoc != null) {
      _backend = attrs['backend'] as String?;
      // Reset the doctype unless it matches the default value.
      _doctype = attrs['doctype'] = parentDoctype;
      if (_doctype != defaultDoctype) {
        _updateDoctypeAttributes(defaultDoctype);
      }

      // Don't need to do the extra processing within our own document.
      reader = Reader(data, opts['cursor']);
      if (sourcemap) sourceLocation = _CursorSourceLocation(reader.cursor());

      // Now parse the lines in the reader into blocks.
      // Eagerly parse (for now) since a subdocument is not a publicly
      // accessible object.
      Parser.parse(reader, this);

      restoreAttributes();
      _parsed = true;
    } else {
      // Setup default backend and doctype.
      _backend = null;
      final initialBackend = (attrs['backend'] as String?) ?? defaultBackend;
      if (initialBackend == 'manpage') {
        _doctype = attrs['doctype'] = attrOverrides['doctype'] = 'manpage';
      } else {
        if (!isTruthy(attrs['doctype'])) attrs['doctype'] = defaultDoctype;
        _doctype = attrs['doctype'] as String?;
      }
      _updateBackendAttributes(initialBackend, true);

      // Fallback directories.
      if (!isTruthy(attrs['stylesdir'])) attrs['stylesdir'] = '.';
      if (!isTruthy(attrs['iconsdir'])) {
        final imagesdir = attrs.containsKey('imagesdir')
            ? '${attrs['imagesdir']}'
            : './images';
        attrs['iconsdir'] = '$imagesdir/icons';
      }

      _fillDatetimeAttributes(attrs, inputMtime);

      // Port of `Document#initialize` (lib/asciidoctor/document.rb:492-504):
      // activate the extensions registry. `Extensions` is always defined
      // in Dart, so extension initialization always runs for top-level
      // documents (nested documents inherit the parent registry above).
      final extRegistry = opts['extension_registry'];
      if (extRegistry is Registry) {
        extensions = extRegistry.activate(this);
      } else if (!opts.containsKey('extensions') ||
          opts['extensions'] == null) {
        if (Extensions.groups.isNotEmpty) {
          extensions = Registry().activate(this);
        }
      } else if (opts['extensions'] is void Function(Registry)) {
        extensions = Extensions.create(
          build: opts['extensions']! as void Function(Registry),
        ).activate(this);
      }

      reader = PreprocessorReader(
        _ReaderDocumentAdapter(this),
        data,
        Cursor(attrs['docfile'], baseDir),
        true,
      );
      if (sourcemap) sourceLocation = _CursorSourceLocation(reader.cursor());
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

  /// The document catalog (`'ids'`, `'refs'`, `'footnotes'`, `'links'`,
  /// `'images'`, `'callouts'`, `'includes'`).
  @override
  late final Map<String, Object?> catalog;

  /// Alias of [catalog] for backwards compatibility.
  Map<String, Object?> get references => catalog;

  /// The document counters.
  final Map<String, Object?> counters = <String, Object?>{};

  /// The level-0 section (i.e., doctitle). Only stores the title, not the
  /// header attributes.
  ///
  /// Written by the parser wave once the header is parsed (Ruby assigns the
  /// ivar directly; Dart exposes the field for the same purpose).
  Section? header;

  /// The base directory for converting this document.
  @override
  late final String baseDir;

  /// The resolved options used to initialize this document.
  late final Map<String, Object?> options;

  /// The outfilesuffix defined at the end of the header.
  String? outfilesuffix;

  /// The parent document of this nested document, if any.
  Document? parentDocument;

  /// The reader associated with this document.
  late Reader reader;

  /// Adapts this document to the [ReaderDocument] interface.
  ///
  /// Readers (e.g. the first-line preprocessing of AsciiDoc table cells)
  /// need a [ReaderDocument]; a separate adapter is required for the same
  /// reason as [_ReaderDocumentAdapter] (see its docs).
  ReaderDocument asReaderDocument() => _ReaderDocumentAdapter(this);

  /// The path resolver used to resolve paths in this document.
  @override
  late final PathResolver pathResolver;

  /// The converter associated with this document.
  ///
  /// A minimal stub until the converter wave lands (see the library docs).
  @override
  late NodeConverter converter;

  /// The syntax highlighter associated with this document.
  ///
  /// Resolved from the `source-highlighter` attribute when the header is
  /// saved; `null` unless the base backend is HTML and the named
  /// highlighter is registered.
  Object? syntaxHighlighter;

  /// The activated extensions registry associated with this document.
  ///
  /// `null` when no extension groups are registered and neither the
  /// `extension_registry` nor the `extensions` option was passed.
  Registry? extensions;

  Map<String, Object?> _attributeOverrides = <String, Object?>{};
  int? _maxAttributeValueSize;
  Map<String, Object?>? _headerAttributes;
  final Set<String> _attributesModified = <String>{};
  final Map<String, Object?> _docinfoProcessorExtensions = <String, Object?>{};
  Timings? _timings;
  bool _parsed = false;
  Map<String?, String>? _reftexts;

  /// Parses the AsciiDoc source stored in the [reader] into an AST.
  ///
  /// If [data] is given, a new [PreprocessorReader] is first assigned to
  /// [reader]. If parsing was already performed, returns this document
  /// without further processing. Returns this document.
  ///
  /// Throws [UnimplementedError] until the parser wave lands ([Parser.parse]
  /// is a stub).
  Document parse([Object? data]) {
    if (_parsed) return this;
    var doc = this;
    // Create the reader if data is provided (used when data is not known
    // at the time the Document object is created).
    if (isTruthy(data)) {
      reader = PreprocessorReader(
        _ReaderDocumentAdapter(this),
        data,
        Cursor(attributes['docfile'], baseDir),
        true,
      );
      if (sourcemap) sourceLocation = _CursorSourceLocation(reader.cursor());
    }

    // Port of `Document#parse` (lib/asciidoctor/document.rb:533-537):
    // preprocessor extensions run before parsing (never for nested
    // documents).
    final exts = parentDocument == null ? extensions : null;
    if (exts != null && exts.hasPreprocessors) {
      for (final ext in exts.preprocessors) {
        final result =
            (ext.processMethod as Object? Function(Document, Reader))(
              doc,
              reader,
            );
        if (result is Reader) reader = result;
      }
    }

    // Now parse the lines in the reader into blocks.
    Parser.parse(
      reader,
      this,
      headerOnly: isTruthy(options['parse_header_only']),
    );

    restoreAttributes();

    // Port of `Document#parse` (lib/asciidoctor/document.rb:543-549): tree
    // processor extensions run after parsing; a tree processor may replace
    // the document by returning a different Document.
    if (exts != null && exts.hasTreeProcessors) {
      for (final ext in exts.treeProcessors) {
        final result = (ext.processMethod as Object? Function(Document))(doc);
        if (result is Document && !identical(result, doc)) doc = result;
      }
    }

    _parsed = true;
    return doc;
  }

  /// Whether the source lines of the document have been parsed.
  bool get isParsed => _parsed;

  /// Gets the named counter and takes the next number in the sequence.
  ///
  /// Returns the next number in the sequence for the counter [name],
  /// seeding it with [seed] when seen for the first time.
  @override
  Object? counter(String name, [Object? seed]) {
    final parent = parentDocument;
    if (parent != null) return parent.counter(name, seed);
    final locked = attributeLocked(name);
    Object? currVal;
    var useCurrent = false;
    if (locked) {
      currVal = counters[name];
      useCurrent = isTruthy(currVal);
    }
    if (!useCurrent) {
      currVal = attributes[name];
      useCurrent = !_isNilOrEmpty(currVal);
    }
    Object? nextVal;
    if (useCurrent) {
      nextVal = counters[name] = _nextval(currVal);
    } else if (isTruthy(seed)) {
      if (seed is String) {
        final intval = _parseLeadingInt(seed);
        nextVal = counters[name] = (intval != null && intval.toString() == seed)
            ? intval
            : seed;
      } else {
        // An integer seed (or anything else) is used as is: Ruby compares
        // `seed == seed.to_i.to_s`, which is only true for strings.
        nextVal = counters[name] = seed;
      }
    } else {
      nextVal = counters[name] = 1;
    }
    if (!locked) attributes[name] = nextVal;
    return nextVal;
  }

  /// Increments the counter [counterName] and stores it in [block]'s
  /// attributes.
  ///
  /// Returns the next number in the sequence for the counter.
  @override
  Object? incrementAndStoreCounter(String counterName, AbstractBlock block) =>
      (DocumentAttributeEntry(
        counterName,
        counter(counterName),
      )..saveTo(block.attributes)).value;

  /// Alias of [incrementAndStoreCounter] for backwards compatibility.
  @Deprecated('Use incrementAndStoreCounter instead.')
  Object? counterIncrement(String counterName, AbstractBlock block) =>
      incrementAndStoreCounter(counterName, block);

  /// Registers a reference in the document catalog.
  ///
  /// [type] is `'ids'` (deprecated; registers in `'refs'` instead),
  /// `'refs'`, `'footnotes'`, or an asset type (`'links'`, `'images'`,
  /// ...) cataloged only when the `catalog_assets` option is set.
  Object? register(String type, Object? value) {
    switch (type) {
      case 'ids': // deprecated
        final entry = value! as List<Object?>;
        final id = entry[0]! as String;
        return register('refs', <Object?>[
          id,
          Inline(
            this,
            'anchor',
            text: entry[1] as String?,
            type: 'ref',
            id: id,
          ),
        ]);
      case 'refs':
        final entry = value! as List<Object?>;
        final refs = catalog['refs']! as Map<String, Object?>;
        final key = entry[0]! as String;
        // Ruby evaluates `(ref = value[1])` only when assigning, then
        // returns `ref` (nil when the key already exists).
        if (!isTruthy(refs[key])) {
          refs[key] = entry[1];
          return entry[1];
        }
        return null;
      case 'footnotes':
        final footnoteList = catalog['footnotes']! as List<Footnote>;
        footnoteList.add(value! as Footnote);
        return footnoteList;
      default:
        if (isTruthy(options['catalog_assets'])) {
          final stored = type == 'images'
              ? ImageReference(value! as String, attributes['imagesdir'])
              : value;
          // Throws when the catalog has no such table, mirroring Ruby's
          // NoMethodError on `nil.<<`.
          final assets = catalog[type]! as List;
          assets.add(stored);
          return assets;
        }
        return null;
    }
  }

  /// Scans registered references and returns the ID of the first reference
  /// matching the reference [text], or `null` if no reference is found.
  String? resolveId(String text) {
    final cached = _reftexts;
    if (cached != null) return cached[text];
    final refs = catalog['refs']! as Map<String, Object?>;
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

  static String? _xreftextOf(Object? ref) {
    if (ref is AbstractBlock) return ref.xreftext();
    return (ref! as Inline).xreftext();
  }

  /// Whether this document has any child section objects.
  @override
  bool get hasSections => nextSectionIndex > 0;

  /// Whether this book document has parts (level-0 sections).
  ///
  /// Returns `null` unless the doctype is `'book'` with a top-level
  /// structure to inspect, mirroring Ruby's true/false/nil tristate.
  bool? get multipart {
    if (doctype != 'book') return null;
    for (final block in blocks) {
      if (block.context != 'section') continue;
      final section = block as Section;
      if (section.level == 0) return true;
      if (!section.special) return null;
    }
    return false;
  }

  /// Whether the document has footnotes.
  bool get hasFootnotes => (catalog['footnotes']! as List<Footnote>).isNotEmpty;

  /// The footnotes registered in the document catalog.
  List<Footnote> get footnotes => catalog['footnotes']! as List<Footnote>;

  /// The callouts catalog.
  @override
  Callouts get callouts => catalog['callouts']! as Callouts;

  /// Whether this document is nested inside another one.
  @override
  bool nested() => parentDocument != null;

  /// Whether this is an embedded document.
  bool get embedded => attributes.containsKey('embedded');

  /// Whether extensions are activated for this document.
  ///
  /// Port of `Document#extensions?` (lib/asciidoctor/document.rb:676-678).
  bool get hasExtensions => extensions != null;

  /// The raw source for the document.
  String get source => reader.source;

  /// The raw source lines for the document.
  List<String?> get sourceLines => reader.sourceLines;

  /// Whether the base backend equals [base].
  bool basebackend(String base) => attributes['basebackend'] == base;

  /// The resolved doctitle (see [doctitle]).
  @override
  String? get title => doctitle() as String?;

  /// Sets the title on the document header, creating it when absent.
  ///
  /// Returns nothing; use the assigned value when chaining is needed.
  @override
  set title(String? value) {
    var sect = header;
    if (sect == null) {
      sect = header = Section(this, 0);
      sect.sectname = 'header';
    }
    sect.title = value;
  }

  /// Resolves the primary title for the document.
  ///
  /// Searches the document-level `title` attribute, the header title (or
  /// the title of the first section), and — when [useFallback] is set —
  /// the `untitled-label` attribute, returning the first non-empty value
  /// (or `null` when none resolves). When [partition] is truthy, the value
  /// is parsed into a [DocumentTitle] using [partition] as the separator
  /// (or the `title-separator` attribute when [partition] is `true`). When
  /// [sanitize] is set, XML elements are removed from the value.
  Object? doctitle({
    Object? partition,
    bool sanitize = false,
    bool useFallback = false,
  }) {
    var val = attributes['title'];
    if (!isTruthy(val)) {
      final sect = firstSection;
      if (sect != null) {
        val = sect.title;
      } else if (!(useFallback &&
          isTruthy(val = attributes['untitled-label']))) {
        return null;
      }
    }

    if (isTruthy(partition)) {
      final separator = partition == true
          ? attributes['title-separator'] as String?
          : partition as String?;
      return DocumentTitle(
        val! as String,
        separator: separator,
        sanitize: sanitize,
      );
    }
    // The `as` cast both checks and promotes `val` to String for the block
    // below; the `!` form would not promote.
    // ignore: cast_nullable_to_non_nullable
    if (sanitize && (val as String).contains('<')) {
      // `val` is promoted to String by the `as` cast in the condition.
      final str = val;
      return squeezeChar(str.replaceAll(xmlSanitizeRx, ''), ' ').trim();
    }
    return val;
  }

  /// Alias of [doctitle].
  Object? name({
    Object? partition,
    bool sanitize = false,
    bool useFallback = false,
  }) => doctitle(
    partition: partition,
    sanitize: sanitize,
    useFallback: useFallback,
  );

  /// Generates cross reference text that can refer to this document.
  @override
  String? xreftext([String? xrefstyle]) {
    final val = reftext;
    return (val != null && val.isNotEmpty) ? val : title;
  }

  /// The full name of the author.
  String? get author => attributes['author'] as String?;

  /// The authors of this document as [DocumentAuthor] records.
  List<DocumentAuthor> get authors {
    final attrs = attributes;
    if (!attrs.containsKey('author')) return <DocumentAuthor>[];
    final result = <DocumentAuthor>[
      DocumentAuthor(
        attrs['author'] as String?,
        attrs['firstname'] as String?,
        attrs['middlename'] as String?,
        attrs['lastname'] as String?,
        attrs['authorinitials'] as String?,
        attrs['email'] as String?,
      ),
    ];
    final numAuthors = (attrs['authorcount'] ?? 0) as int;
    if (numAuthors > 1) {
      for (var idx = 2; idx <= numAuthors; idx++) {
        result.add(
          DocumentAuthor(
            attrs['author_$idx'] as String?,
            attrs['firstname_$idx'] as String?,
            attrs['middlename_$idx'] as String?,
            attrs['lastname_$idx'] as String?,
            attrs['authorinitials_$idx'] as String?,
            attrs['email_$idx'] as String?,
          ),
        );
      }
    }
    return result;
  }

  /// The date of last revision for the document.
  String? get revdate => attributes['revdate'] as String?;

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
      if (block.context == 'section') return block as Section;
    }
    return null;
  }

  /// Whether the document has a header.
  bool get hasHeader => header != null;

  /// Appends [block] to this document, assigning an index first when the
  /// child is a section. Returns this document.
  @override
  AbstractBlock operator <<(AbstractBlock block) {
    if (block.context == 'section') assignNumeral(block);
    return super << block;
  }

  /// Called by the parser after parsing the header and before parsing the
  /// body, even if no header is found.
  ///
  /// Clearsplayback state from [unrootedAttributes], saves the header
  /// attributes, and — unless [headerValid] — flags an invalid header.
  /// Returns [unrootedAttributes].
  Map<Object, Object?> finalizeHeader(
    Map<Object, Object?> unrootedAttributes, [
    bool headerValid = true,
  ]) {
    _clearPlaybackAttributes(unrootedAttributes);
    _saveAttributes();
    if (!headerValid) unrootedAttributes['invalid-header'] = true;
    return unrootedAttributes;
  }

  /// Replays attribute assignments at the block level.
  @override
  void playbackAttributes(Map<String, Object?> blockAttributes) {
    if (!blockAttributes.containsKey('attribute_entries')) return;
    final entries =
        blockAttributes['attribute_entries']! as List<DocumentAttributeEntry>;
    for (final entry in entries) {
      final name = entry.name;
      if (entry.negate) {
        attributes.remove(name);
        if (name == 'compat-mode') _compatMode = false;
      } else {
        attributes[name] = entry.value;
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
  bool setHeaderAttribute(
    String name, [
    Object? value = '',
    bool overwrite = true,
  ]) {
    final attrs = _headerAttributes ?? attributes;
    if (!overwrite && attrs.containsKey(name)) return false;
    attrs[name] = value;
    return true;
  }

  /// Converts the AsciiDoc document using the converter.
  ///
  /// Throws [UnimplementedError] until the parser wave lands (conversion
  /// always parses first).
  @override
  Object? convert([Map<String, Object?> opts = const <String, Object?>{}]) {
    _timings?.start('convert');
    parse();
    if (safe < SafeMode.server && opts.isNotEmpty) {
      final outfile = opts['outfile'];
      if (isTruthy(outfile)) {
        attributes['outfile'] = outfile;
      } else {
        attributes.remove('outfile');
      }
      final outdir = opts['outdir'];
      if (isTruthy(outdir)) {
        attributes['outdir'] = outdir;
      } else {
        attributes.remove('outdir');
      }
    }

    Object? output;
    if (doctype == 'inline') {
      final block = blocks.isNotEmpty ? blocks[0] : header;
      if (block != null) {
        if (block.contentModel == 'compound' || block.contentModel == 'empty') {
          logger.warn(
            'no inline candidate; use the inline doctype to convert a single '
            'paragragh, verbatim, or raw block',
          );
        } else {
          output = block.content();
        }
      }
    } else {
      final String transform;
      if (opts.containsKey('standalone')) {
        transform = isTruthy(opts['standalone']) ? 'document' : 'embedded';
      } else if (opts.containsKey('header_footer')) {
        transform = isTruthy(opts['header_footer']) ? 'document' : 'embedded';
      } else {
        transform = isTruthy(options['standalone']) ? 'document' : 'embedded';
      }
      // `NodeConverter` only exposes the single-argument entry point; the
      // full `Converter` API takes the transform (Ruby: `convert self,
      // transform`). Stubs for unported backends keep throwing below.
      final nodeConverter = converter;
      output = nodeConverter is Converter
          ? nodeConverter.convert(this, transform)
          : nodeConverter.convert(this);
    }

    // Port of `Document#convert` (lib/asciidoctor/document.rb:971-976):
    // postprocessor extensions run after conversion (never for nested
    // documents).
    if (parentDocument == null) {
      final exts = extensions;
      if (exts != null && exts.hasPostprocessors) {
        for (final ext in exts.postprocessors) {
          output = Function.apply(ext.processMethod, [this, output]);
        }
      }
    }

    _timings?.record('convert');
    return output;
  }

  /// Alias of [convert].
  @Deprecated('Use convert instead.')
  @override
  Object? render([Map<String, Object?> opts = const <String, Object?>{}]) =>
      convert(opts);

  /// Writes [output] to [target].
  ///
  /// [target] is a [StringSink]/[IOSink] (written with a trailing newline)
  /// or a [String] file path.
  void write(Object? output, Object target) {
    _timings?.start('write');
    // Converter wave: converters implementing the writer brotherhood take
    // over here; until then output is always written directly.
    if (target is StringSink) {
      if (!_isNilOrEmpty(output)) {
        final text = _chomp(output! as String);
        target.write(text);
        target.write(lf);
      }
    } else if (target is IOSink) {
      if (!_isNilOrEmpty(output)) {
        target.write(_chomp(output! as String));
        target.writeln();
      }
    } else if (target is String) {
      // Ruby's `File.write target, output` coerces nil to empty.
      File(target).writeAsStringSync(output as String? ?? '');
    } else {
      throw ArgumentError.value(
        target,
        'target',
        'must be a StringSink, IOSink, or file path',
      );
    }
    // Ruby: only when the converter class responds to write_alternate_pages
    // (i.e. the manpage converter itself, not a template/composite chain).
    if (backend == 'manpage' &&
        target is String &&
        converter is ManpageConverter) {
      ManpageConverter.writeAlternatePages(
        attributes['mannames'] as List<Object?>?,
        attributes['manvolnum'],
        target,
      );
    }
    _timings?.record('write');
  }

  /// Returns the converted result of the child blocks.
  ///
  /// Per the AsciiDoc spec, the `title` attribute is removed before
  /// converting the body.
  @override
  Object? content() {
    attributes.remove('title');
    return super.content();
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
      if (docinfoAttr == null ||
          (docinfoAttr is String && docinfoAttr.isEmpty)) {
        if (attributes.containsKey('docinfo2')) {
          docinfo = <String>['private', 'shared'];
        } else if (attributes.containsKey('docinfo1')) {
          docinfo = <String>['shared'];
        } else {
          docinfo = isTruthy(docinfoAttr) ? <String>['private'] : null;
        }
      } else {
        docinfo = (docinfoAttr as String)
            .split(',')
            .map((keyword) => keyword.trim())
            .toList();
      }

      if (docinfo != null) {
        content = <String>[];
        final docinfoFile = 'docinfo$qualifier$suffix';
        final docinfoDir = attributes['docinfodir'] as String?;
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
            content.add(applySubs(sharedDocinfo, docinfoSubs)! as String);
          }
        }

        final docname = attributes['docname'];
        if (!_isNilOrEmpty(docname) &&
            (docinfo.contains('private') ||
                docinfo.contains('private-$location'))) {
          final docinfoPath = normalizeSystemPath(
            '$docname-$docinfoFile',
            start: docinfoDir,
          );
          // NOTE normalizing the lines is essential if substitutions run.
          final privateDocinfo = readAsset(docinfoPath, normalize: true);
          if (privateDocinfo != null) {
            content.add(applySubs(privateDocinfo, docinfoSubs)! as String);
          }
        }
      }
    }

    // Port of `Document#docinfo` (lib/asciidoctor/document.rb:1077-1085):
    // docinfo processor extensions contribute content for the location.
    if (extensions != null && docinfoProcessors(location)) {
      final extContent = content ?? <String>[];
      for (final ext
          in _docinfoProcessorExtensions[location]!
              as List<ProcessorExtension>) {
        final result = (ext.processMethod as Object? Function(Document))(this);
        if (result != null) extContent.add(result.toString());
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
  /// Port of `Document#docinfo_processors?`
  /// (lib/asciidoctor/document.rb:1087-1095).
  bool docinfoProcessors([String location = 'head']) {
    if (_docinfoProcessorExtensions.containsKey(location)) {
      // false means a lookup already ran and found nothing.
      return _docinfoProcessorExtensions[location] != false;
    }
    final exts = extensions;
    if (exts != null && exts.hasDocinfoProcessors(location)) {
      _docinfoProcessorExtensions[location] = exts.docinfoProcessors(location);
      return true;
    } else {
      _docinfoProcessorExtensions[location] = false;
      return false;
    }
  }

  /// Reads the include target [uri] decoded with [encoding].
  ///
  /// Returns `null` when the URI cannot be read. Used by the reader wave
  /// through the [ReaderDocument] adapter.
  String? readUri(Uri uri, Encoding encoding) {
    try {
      final response = fetchUri(uri.toString());
      return encoding.decode(response.body);
    } on Exception {
      return null;
    }
  }

  @override
  String toString() {
    final doctitleVal = header?.title;
    return '#$runtimeType@${identityHashCode(this)} '
        '{doctype: ${inspectString(doctype)}, '
        'doctitle: ${doctitleVal == null ? 'nil' : inspectString(doctitleVal)}, '
        'blocks: ${blocks.length}}';
  }

  /// Applies substitutions to the attribute [value].
  ///
  /// A value that is an inline passthrough macro takes the substitutions
  /// defined in it (or is left unmodified when none are specified);
  /// otherwise header substitutions are applied. The result is truncated
  /// to [_maxAttributeValueSize] bytes when a limit is configured.
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
      substitutors.applyHeaderSubs(this, value)! as String;

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
          substitutors.resolvePassSubs(this, subs) ?? <String>[],
        )!
        as String;
  }

  /// Safely truncates [str] to [max] bytes.
  ///
  /// A multibyte char split by the cut is dropped whole, so the result is
  /// always valid (mirrors the `valid_encoding?` loop in Ruby).
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
  /// resolves to no subs, matching Ruby's `nil` short-circuit in
  /// `apply_subs`).
  List<String> _resolveDocinfoSubs() {
    if (attributes.containsKey('docinfosubs')) {
      return substitutors.resolveSubs(
            this,
            attributes['docinfosubs'] as String?,
            'block',
            null,
            'docinfo',
          ) ??
          <String>[];
    }
    return <String>['attributes'];
  }

  /// Creates and initializes the converter for [backend].
  ///
  /// Returns `null` when no converter can be resolved (the caller raises).
  /// Ported backends resolve through [Converter.create]; anything else
  /// resolves only through the `converter` option (a [NodeConverter]) or
  /// `template_dirs` (a template chain, bare when the backend is unknown).
  NodeConverter? _createConverter(String backend, String? delegateBackend) {
    // Port of `Document#create_converter`
    // (lib/asciidoctor/document.rb:1153-1167).
    final converterOpts = <String, Object?>{
      'document': this,
      'htmlsyntax': attributes['htmlsyntax'],
    };
    final templateDirs = options['template_dirs'] ?? options['template_dir'];
    if (isTruthy(templateDirs)) {
      // Ruby's `[*template_dirs]` coerces a lone String to a one-element
      // Array; `template_cache` defaults to true only when the key is
      // absent (an explicit nil/false disables the cache).
      converterOpts['template_dirs'] = templateDirs is Iterable
          ? templateDirs.map((dir) => dir.toString()).toList()
          : [templateDirs.toString()];
      converterOpts['template_cache'] = options.containsKey('template_cache')
          ? options['template_cache']
          : true;
      converterOpts['template_engine'] = options['template_engine'];
      converterOpts['template_engine_options'] =
          options['template_engine_options'];
      converterOpts['eruby'] = options['eruby'];
      converterOpts['safe'] = safe;
      if (delegateBackend != null) {
        converterOpts['delegate_backend'] = delegateBackend;
      }
    }
    final custom = options['converter'];
    if (custom != null) {
      return CustomFactory(<String, Object?>{backend: custom})
          .create(backend, converterOpts);
    }
    final factoryOpt = options['converter_factory'];
    if (factoryOpt is ConverterFactory) {
      return factoryOpt.create(backend, converterOpts);
    }
    // Ensure the ported backends are registered (idempotent), then resolve
    // through the global factory.
    Html5Converter.registerFor();
    Docbook5Converter.registerFor();
    ManpageConverter.registerFor();
    final created = Converter.create(backend, converterOpts);
    if (created != null) return created;
    final builtin = _builtinTraits(backend, attributes['htmlsyntax']);
    if (builtin != null) return _BuiltinConverterStub(backend, builtin);
    if (isTruthy(templateDirs)) {
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
    Object? htmlsyntaxAttr,
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

  /// Deletes any attributes stored for playback.
  static void _clearPlaybackAttributes(Map<Object, Object?> attributes) {
    attributes.remove('attribute_entries');
  }

  /// Branches the attributes so the original state can be restored later.
  void _saveAttributes() {
    final attrs = attributes;
    if (!attrs.containsKey('doctitle')) {
      final doctitleVal = doctitle();
      if (doctitleVal != null) attrs['doctitle'] = doctitleVal;
    }

    // css-signature cannot be updated after header attributes are processed.
    id ??= attrs['css-signature'] as String?;

    final deletedToc2 = attrs.remove('toc2');
    final tocVal = isTruthy(deletedToc2) ? 'left' : attrs['toc'];
    if (isTruthy(tocVal)) {
      // toc-placement separates position from fitted slot vs macro.
      final tocPlacementVal = attrs.containsKey('toc-placement')
          ? attrs['toc-placement']
          : 'macro';
      final tocPositionVal =
          (isTruthy(tocPlacementVal) && tocPlacementVal != 'auto')
          ? tocPlacementVal
          : attrs['toc-position'];
      final toc = tocVal! as String;
      if (!(toc.isEmpty && _isNilOrEmpty(tocPositionVal))) {
        const defaultTocPosition = 'left';
        // TODOrename toc2 to aside-toc
        String? defaultTocClass = 'toc2';
        final position = _isNilOrEmpty(tocPositionVal)
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
        if (defaultTocClass != null && !isTruthy(attrs['toc-class'])) {
          attrs['toc-class'] = defaultTocClass;
        }
      }
    }

    final iconsVal = attrs['icons'];
    if (isTruthy(iconsVal) && !attrs.containsKey('icontype')) {
      if (iconsVal != '' && iconsVal != 'font') {
        attrs['icons'] = '';
        if (iconsVal != 'image') attrs['icontype'] = iconsVal;
      }
    }

    _compatMode = attrs.containsKey('compat-mode');
    if (_compatMode && attrs.containsKey('language')) {
      attrs['source-language'] = attrs['language'];
    }

    if (parentDocument == null) {
      final basebackend = attrs['basebackend'];
      if (basebackend == 'html') {
        final syntaxHlName = attrs['source-highlighter'];
        if (isTruthy(syntaxHlName) &&
            !isTruthy(attrs['$syntaxHlName-unavailable'])) {
          // Port of `Document#save_attributes`
          // (lib/asciidoctor/document.rb:1233-1242): resolve the syntax
          // highlighter, honoring the `syntax_highlighter_factory` and
          // `syntax_highlighters` options.
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
      outfilesuffix = attrs['outfilesuffix'] as String?;

      // Unfreeze "flexible" attributes.
      for (final name in flexibleAttributes) {
        // Turning a flexible attribute off should be permanent
        // (we may need more config if that's not always the case).
        if (_attributeOverrides.containsKey(name) &&
            isTruthy(_attributeOverrides[name])) {
          _attributeOverrides.remove(name);
        }
      }
    }

    _headerAttributes = Map<String, Object?>.of(attrs);
  }

  /// Assigns the local and document datetime attributes.
  ///
  /// Honors the `SOURCE_DATE_EPOCH` environment variable when set.
  static void _fillDatetimeAttributes(
    Map<String, Object?> attrs,
    Object? inputMtime,
  ) {
    // See https://reproducible-builds.org/specs/source-date-epoch/
    final epochEnv = Platform.environment['SOURCE_DATE_EPOCH'];
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
    if (isTruthy(localdateOpt)) {
      localdate = localdateOpt! as String;
      if (!isTruthy(attrs['localyear'])) {
        attrs['localyear'] = (localdate.indexOf('-') == 4)
            ? localdate.substring(0, 4)
            : null;
      }
    } else {
      localdate = attrs['localdate'] = _formatDate(now);
      if (!isTruthy(attrs['localyear'])) {
        attrs['localyear'] = now.year.toString();
      }
    }
    // %Z is OS dependent and may contain characters that aren't UTF-8
    // encoded, so the offset is formatted manually instead.
    if (!isTruthy(attrs['localtime'])) attrs['localtime'] = _formatTime(now);
    final localtime = attrs['localtime'];
    if (!isTruthy(attrs['localdatetime'])) {
      attrs['localdatetime'] = '$localdate $localtime';
    }
    // docdate, doctime and docdatetime default to localdate, localtime and
    // localdatetime when not otherwise set.
    final DateTime mtime;
    if (sourceDateEpoch != null) {
      mtime = sourceDateEpoch;
    } else if (inputMtime is DateTime) {
      mtime = inputMtime;
    } else if (isTruthy(inputMtime)) {
      throw ArgumentError.value(
        inputMtime,
        'input_mtime',
        'must be a DateTime',
      );
    } else {
      mtime = now;
    }
    final docdateOpt = attrs['docdate'];
    final String docdate;
    if (isTruthy(docdateOpt)) {
      docdate = docdateOpt! as String;
      if (!isTruthy(attrs['docyear'])) {
        attrs['docyear'] = (docdate.indexOf('-') == 4)
            ? docdate.substring(0, 4)
            : null;
      }
    } else {
      docdate = attrs['docdate'] = _formatDate(mtime);
      if (!isTruthy(attrs['docyear'])) {
        attrs['docyear'] = mtime.year.toString();
      }
    }
    if (!isTruthy(attrs['doctime'])) attrs['doctime'] = _formatTime(mtime);
    final doctime = attrs['doctime'];
    if (!isTruthy(attrs['docdatetime'])) {
      attrs['docdatetime'] = '$docdate $doctime';
    }
  }

  /// Formats [time] as `yyyy-MM-dd` (Ruby `%F`).
  static String _formatDate(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  /// Formats [time] as `HH:mm:ss <zone>` with `UTC` for a zero offset,
  /// else `+HHMM`/`-HHMM` (Ruby `%T %z`, with `UTC` for `+0000`).
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
      if (!isTruthy(attrs['htmlsyntax'])) attrs['htmlsyntax'] = 'html';
    }
    backend = backendAliases[backend] ?? backend;
    String? delegateBackend;
    if (actualBackend != null) {
      delegateBackend = backend;
      backend = actualBackend;
    }
    if (currentDoctype != null) {
      if (currentBackend != null) {
        attrs.remove('backend-$currentBackend');
        attrs.remove('backend-$currentBackend-doctype-$currentDoctype');
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
      throw UnimplementedError(
        "asciidoctor: FAILED: missing converter for backend '$backend'. "
        'Processing aborted.',
      );
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
      final converterTraits = resolvedConverter.backendTraits();
      traits = _BackendTraits(
        basebackend: converterTraits['basebackend']! as String,
        filetype: converterTraits['filetype']! as String,
        outfilesuffix: converterTraits['outfilesuffix']! as String,
        htmlsyntax: converterTraits['htmlsyntax'] as String?,
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
    if (isTruthy(currentFiletype)) {
      attrs.remove('filetype-$currentFiletype');
    }
    attrs['filetype'] = traits.filetype;
    attrs['filetype-${traits.filetype}'] = '';
    final pageWidth = defaultPageWidths[traits.basebackend];
    if (pageWidth != null) {
      attrs['pagewidth'] = pageWidth;
    } else {
      attrs.remove('pagewidth');
    }
    if (traits.basebackend != currentBasebackend) {
      if (currentDoctype != null) {
        if (currentBasebackend != null) {
          attrs.remove('basebackend-$currentBasebackend');
          attrs.remove(
            'basebackend-$currentBasebackend-doctype-$currentDoctype',
          );
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
    Map<String, Object?> attrs,
    String outfilesuffix,
    bool init,
  ) {
    if (init) {
      if (!isTruthy(attrs['outfilesuffix'])) {
        attrs['outfilesuffix'] = outfilesuffix;
      }
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

  /// Expands [path] against the working directory (Ruby `File.expand_path`).
  String _expandBaseDir(String path) {
    final absolute = pathResolver.isRoot(path)
        ? path
        : pathResolver.joinPath(<String>[Directory.current.path, path]);
    return pathResolver.expandPath(absolute);
  }

  /// The user's home directory (Ruby `USER_HOME`).
  static String get _userHome =>
      Platform.environment['HOME'] ?? Directory.current.path;

  /// Mirrors a `showtitle`/`notitle` API value to its counterpart.
  ///
  /// Port of `{nil => '', false => '@', '@' => false}[value]`.
  static Object? _mirrorShowtitle(Object? value) {
    if (value == null) return '';
    if (value == false) return '@';
    if (value == '@') return false;
    return null;
  }

  /// Returns the next value in the sequence after [current].
  ///
  /// Port of `Helpers.nextval`: integers increment; integer-looking strings
  /// increment numerically; anything else takes Ruby's `String#succ`.
  /// [current] is `null` only when a locked counter has no recorded value,
  /// which Ruby rejects (`NoMethodError`); here a [StateError] is thrown.
  static Object _nextval(Object? current) {
    if (current is int) return current + 1;
    if (current is BigInt) return current + BigInt.one;
    if (current is String) {
      final intval = _parseLeadingInt(current);
      if (intval != null && intval.toString() == current) {
        final next = intval + BigInt.one;
        return next.bitLength < 63 ? next.toInt() : next;
      }
      return _succ(current);
    }
    throw StateError('counter value must be an Integer or String: $current');
  }

  /// Parses the leading integer of [value] (Ruby `String#to_i`).
  ///
  /// Returns `null` when the value has no leading integer. [BigInt] is used
  /// so arbitrarily large values behave exactly like Ruby.
  static BigInt? _parseLeadingInt(String value) {
    final match = _leadingIntRx.firstMatch(value);
    if (match == null) return null;
    return BigInt.parse(match.group(0)!.trim());
  }

  static final RegExp _leadingIntRx = RegExp(r'^\s*[+-]?\d+');

  /// Converts [value] to an integer (Ruby `Object#to_i`).
  ///
  /// Only integers and strings occur in practice; anything else throws a
  /// [StateError] (mirroring Ruby's `NoMethodError`). Values exceeding the
  /// 64-bit range saturate at [_maxInt63] (used for sizes, where a huge
  /// value behaves like no effective limit).
  static int _rubyToInt(Object? value) {
    if (value is int) return value;
    if (value is BigInt) {
      return value.bitLength < 63 ? value.toInt() : _maxInt63;
    }
    if (value is String) {
      final match = _leadingIntRx.firstMatch(value);
      if (match == null) return 0;
      return int.tryParse(match.group(0)!.trim()) ?? _maxInt63;
    }
    throw StateError('cannot convert to integer: $value');
  }

  static const int _maxInt63 = 9223372036854775807;

  /// Returns the successor of [s] (Ruby `String#succ`).
  ///
  /// The last alphanumeric run (ASCII letters and digits) is incremented
  /// with carry; when it overflows, the carry crosses separators to the
  /// previous run when that run ends in the same class (digit or letter),
  /// else the carry char (`'1'`, `'a'`, `'A'`) is inserted at the run
  /// start. With no alphanumeric char, the last char is incremented by
  /// codepoint. Verified against CRuby, including `'19-99'` -> `'20-00'`,
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

  /// Whether [value] is `null` or an empty string (Ruby `nil_or_empty?`).
  ///
  /// Note `false` is *not* nil-or-empty (Ruby's `Object#nil_or_empty?`
  /// returns false).
  static bool _isNilOrEmpty(Object? value) =>
      value == null || (value is String && value.isEmpty);

  /// Removes one trailing line break (`\n`, `\r\n` or `\r`) from [s].
  ///
  /// Port of Ruby's `String#chomp` with no arguments.
  static String _chomp(String s) {
    if (s.endsWith('\n')) {
      return s.substring(0, s.length - (s.endsWith('\r\n') ? 2 : 1));
    }
    if (s.endsWith('\r')) return s.substring(0, s.length - 1);
    return s;
  }
}
