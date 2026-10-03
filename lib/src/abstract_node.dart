/// Base class for every node in a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/abstract_node.rb`.
///
/// Ruby symbols (`:paragraph`, `:document`, ...) are represented as `String`s
/// throughout this port, so a Ruby `context` of `:listing` becomes the Dart
/// string `'listing'`.
///
/// Several collaborators of [AbstractNode] live in waves that have not landed
/// yet. Their node-facing slices are declared here as small interfaces so
/// this file compiles standalone with sound null safety:
///
/// * [NodeDocument] — the `Document` API surface nodes consume. Implemented
///   by `Document` (document wave), which extends [AbstractBlock].
/// * [NodeConverter] — the `Converter#convert` entry point. Implemented by
///   the converter wave.
/// * [NodeLogger] — the logger API. The logging wave provides the concrete
///   `Logger`, `MemoryLogger` and `NullLogger` implementations.
///
/// The substitution methods ([applySubs], [subQuotes] and friends) are ported
/// as stubs that throw [UnimplementedError] until the substitutors wave
/// replaces their bodies.
library;

import 'dart:convert' show base64Encode, utf8;
import 'dart:io' show File, FileSystemException, stderr;

import 'abstract_block.dart';
import 'callouts.dart';
import 'helpers.dart';
import 'path_resolver.dart';

/// Line feed. Port of the `LF` constant in `lib/asciidoctor.rb`.
const String lf = '\n';

/// Safe mode levels. Port of the `SafeMode` module in `lib/asciidoctor.rb`.
abstract final class SafeMode {
  /// Disables all security features enforced by Asciidoctor.
  static const int unsafe = 0;

  /// Prevents access to files outside the parent directory of the source file.
  static const int safe = 1;

  /// Additionally forbids the document from setting attributes that would
  /// affect its own conversion.
  static const int server = 10;

  /// Additionally disallows reading files from the file system (the default).
  static const int secure = 20;
}

/// The converter entry point consumed by nodes.
///
/// Port of the `convert` method on `Asciidoctor::Converter`. The converter
/// wave implements this interface.
abstract interface class NodeConverter {
  /// Converts [node] to the output format.
  Object? convert(AbstractNode node);
}

/// The logger API consumed by nodes.
///
/// Mirrors the `::Logger` severity methods used through the `Logging` mixin.
/// The logging wave implements this interface with `Logger`, `MemoryLogger`
/// and `NullLogger`.
abstract interface class NodeLogger {
  /// Logs [message] at debug severity.
  void debug(Object? message);

  /// Logs [message] at info severity.
  void info(Object? message);

  /// Logs [message] at warning severity.
  void warn(Object? message);

  /// Logs [message] at error severity.
  void error(Object? message);

  /// Logs [message] at fatal severity.
  void fatal(Object? message);
}

/// Default [NodeLogger], writing to stderr.
///
/// Mirrors `Asciidoctor::Logger` with the default level (`WARN`, so debug and
/// info messages are dropped) and `BasicFormatter` severity labels (`WARNING`
/// for warn, `FAILED` for fatal).
final class _StderrNodeLogger implements NodeLogger {
  /// Creates the default stderr logger.
  const _StderrNodeLogger();

  @override
  void debug(Object? message) {}

  @override
  void info(Object? message) {}

  @override
  void warn(Object? message) {
    stderr.writeln('asciidoctor: WARNING: $message');
  }

  @override
  void error(Object? message) {
    stderr.writeln('asciidoctor: ERROR: $message');
  }

  @override
  void fatal(Object? message) {
    stderr.writeln('asciidoctor: FAILED: $message');
  }
}

/// The `Document` API surface consumed by nodes.
///
/// Implemented by `Document` (document wave). Most members are satisfied
/// automatically because `Document` extends [AbstractBlock], which extends
/// [AbstractNode].
abstract interface class NodeDocument {
  /// The document-wide attributes.
  Map<String, Object?> get attributes;

  /// The converter used to convert the document.
  NodeConverter get converter;

  /// The safe mode level the document runs under (see [SafeMode]).
  int get safe;

  /// The base directory used to resolve relative paths.
  String get baseDir;

  /// The path resolver used to resolve system and web paths.
  PathResolver get pathResolver;

  /// Whether the document runs in AsciiDoc compatibility mode.
  bool get compatMode;

  /// The document catalog (`'refs'`, `'callouts'`, ...).
  ///
  /// Mirrors `Document#catalog` (whose Ruby keys are symbols; the port uses
  /// their string names).
  Map<String, Object?> get catalog;

  /// The document callouts catalog.
  ///
  /// Mirrors `Document#callouts` (which reads the catalog entry).
  Callouts get callouts;

  /// Whether this document is nested inside another one.
  ///
  /// Mirrors `Document#nested?`.
  bool nested();

  /// Whether source locations are tracked for blocks.
  ///
  /// Mirrors `Document#sourcemap`.
  bool get sourcemap;

  /// Returns the value of document attribute [name], or [defaultValue].
  ///
  /// Mirrors `AbstractNode#attr` as inherited by `Document`.
  Object? attr(Object name, [Object? defaultValue, Object? fallbackName]);

  /// Whether document attribute [name] is set, optionally comparing it
  /// against [expectedValue].
  ///
  /// Mirrors `AbstractNode#attr?` as inherited by `Document`.
  bool hasAttr(Object name, [Object? expectedValue, Object? fallbackName]);

  /// Returns the next number in the sequence for the counter [name],
  /// seeding it with [seed] when seen for the first time.
  Object? counter(String name, [Object? seed]);

  /// Increments the counter [counterName], stores it in [block]'s
  /// attributes, and returns the new value.
  Object? incrementAndStoreCounter(String counterName, AbstractBlock block);

  /// Replays block-level attribute assignments against the document.
  void playbackAttributes(Map<String, Object?> blockAttributes);
}

/// An abstract base class that provides state and methods for managing a
/// node of AsciiDoc content.
///
/// The state and methods on this class are common to all content segments
/// in an AsciiDoc document. Port of `Asciidoctor::AbstractNode`.
abstract class AbstractNode {
  /// The shared logger used by every node.
  ///
  /// Mirrors `LoggerManager.logger` / `LoggerManager#logger=`. Tests
  /// replace it with a recording logger.
  static NodeLogger currentLogger = const _StderrNodeLogger();

  /// The attributes of this node.
  final Map<String, Object?> attributes;

  /// Passthrough slots stashed while substitutions run.
  ///
  /// Internal: written and cleared by the substitutors wave. Each entry maps
  /// `text`, `subs` and optionally `type` / `attributes`.
  final List<Map<String, Object?>> passthroughs = <Map<String, Object?>>[];

  /// The id of this node.
  String? id;

  String _context;
  String _nodeName;
  AbstractBlock? _parent;
  NodeDocument? _document;

  /// Creates a node with [parent] and [context].
  ///
  /// When [context] is `'document'`, the node refers to itself as its
  /// document (and must implement [NodeDocument]), ignoring [parent] (which
  /// stays `null`, as in Ruby, where a document never assigns `@parent`);
  /// otherwise the document is taken from [parent] (which may be `null`,
  /// leaving [document] unset until the node is attached with [parent] or
  /// `<<`). [attributes] is copied; [nodeName] overrides the default node
  /// name, which is [context].
  AbstractNode(
    AbstractBlock? parent,
    String context, {
    Map<String, Object?>? attributes,
    String? nodeName,
  }) : _parent = parent,
       _context = context,
       _nodeName = nodeName ?? context,
       attributes = attributes == null
           ? <String, Object?>{}
           : Map<String, Object?>.of(attributes) {
    if (context == 'document') {
      if (this is! NodeDocument) {
        throw StateError(
          'A node with context "document" must implement NodeDocument.',
        );
      }
      _parent = null;
      _document = this as NodeDocument;
    } else if (parent != null) {
      _document = parent.document;
    }
  }

  /// Whether this node is a block-level node.
  bool get isBlock;

  /// Whether this node is an inline node.
  bool get isInline;

  /// The context (type qualifier) of this node, e.g. `'paragraph'`.
  String get context => _context;

  /// Reassigns the context and re-derives [nodeName] from it.
  ///
  /// Ruby defines `context=` on `AbstractBlock` only; it lives here so every
  /// subclass across libraries shares the same behavior. Prefer using it on
  /// blocks.
  set context(String value) {
    _context = value;
    _nodeName = value;
  }

  /// The name of this node (the context, except on [Inline] nodes).
  String get nodeName => _nodeName;

  /// The parent block of this node.
  AbstractBlock? get parent => _parent;

  /// Associates this node with a new [parent] block.
  ///
  /// Also re-points [document] at the parent's document. Returns nothing;
  /// use the assigned value when chaining is needed.
  set parent(AbstractBlock parent) {
    _parent = parent;
    _document = parent.document;
  }

  /// The document to which this node belongs (`null` while detached).
  NodeDocument? get document => _document;

  /// The shared logger. Mirrors the `logger` method from the `Logging` mixin.
  NodeLogger get logger => currentLogger;

  /// The converter being used to convert the current document.
  NodeConverter get converter => document!.converter;

  /// Returns the value of attribute [name] on this node.
  ///
  /// If the attribute is not found on this node, [fallbackName] is set and
  /// this node is not the document node, returns the value of that
  /// attribute (or [name] when [fallbackName] is `true`) from the document
  /// node instead. Otherwise returns [defaultValue]. A stored value of
  /// `null` or `false` counts as "not found", exactly as in Ruby.
  Object? attr(Object name, [Object? defaultValue, Object? fallbackName]) {
    final key = name.toString();
    final value = attributes[key];
    if (value != null && value != false) return value;
    if (fallbackName != null && fallbackName != false && parent != null) {
      final fallbackKey = (fallbackName == true ? name : fallbackName)
          .toString();
      final docValue = document!.attributes[fallbackKey];
      if (docValue != null && docValue != false) return docValue;
    }
    return defaultValue;
  }

  /// Whether attribute [name] is defined, using the same lookup logic as
  /// [attr], optionally comparing against [expectedValue].
  ///
  /// If [expectedValue] is truthy, returns whether the resolved value equals
  /// it; otherwise returns whether the attribute was found. A [fallbackName]
  /// of `true` falls back to [name] on the document.
  bool hasAttr(Object name, [Object? expectedValue, Object? fallbackName]) {
    final key = name.toString();
    final useFallback =
        fallbackName != null && fallbackName != false && parent != null;
    final fallbackKey = useFallback
        ? (fallbackName == true ? name : fallbackName).toString()
        : null;
    if (expectedValue != null && expectedValue != false) {
      var value = attributes[key];
      if (value == null || value == false) {
        value = useFallback ? document!.attributes[fallbackKey!] : null;
      }
      return expectedValue == value;
    }
    if (attributes.containsKey(key)) return true;
    if (useFallback) return document!.attributes.containsKey(fallbackKey!);
    return false;
  }

  /// Assigns [value] to attribute [name] on this node.
  ///
  /// Returns whether the assignment was performed (`false` only when
  /// [overwrite] is `false` and the attribute already exists).
  bool setAttr(String name, [Object? value = '', bool overwrite = true]) {
    if (!overwrite && attributes.containsKey(name)) return false;
    attributes[name] = value;
    return true;
  }

  /// Removes attribute [name] from this node.
  ///
  /// Returns the previous value, or `null` if the attribute was absent.
  Object? removeAttr(String name) => attributes.remove(name);

  /// Whether the option [name] is enabled on this node.
  ///
  /// An option is enabled when the `<name>-option` attribute is defined.
  bool hasOption(Object name) {
    final value = attributes['$name-option'];
    return value != null && value != false;
  }

  /// Enables the option [name] on this node.
  void setOption(Object name) {
    attributes['$name-option'] = '';
  }

  /// The names of the options enabled on this node.
  Set<String> get enabledOptions {
    final result = <String>{};
    for (final key in attributes.keys) {
      if (key.endsWith('-option')) {
        result.add(key.substring(0, key.length - '-option'.length));
      }
    }
    return result;
  }

  /// Updates the attributes of this node with [newAttributes].
  ///
  /// Returns the updated attributes of this node.
  Map<String, Object?> updateAttributes(Map<String, Object?> newAttributes) {
    attributes.addAll(newAttributes);
    return attributes;
  }

  /// The space-separated role of this node.
  Object? get role => attributes['role'];

  /// The role names of this node.
  ///
  /// Empty when the `role` attribute is absent on this node.
  List<String> get roles {
    final value = attributes['role'];
    if (value is! String) return <String>[];
    return _splitOnBlank(value);
  }

  /// Whether the role attribute is set on this node and, when
  /// [expectedValue] is given, whether it equals that value.
  bool hasRole([Object? expectedValue]) {
    if (expectedValue == null || expectedValue == false) {
      return attributes.containsKey('role');
    }
    return expectedValue == attributes['role'];
  }

  /// Whether [name] is one of the roles of this node.
  bool includesRole(String name) {
    final value = attributes['role'];
    if (value == null || value == false) return false;
    // NOTE center + contains is faster than split + contains.
    return ' $value '.contains(' $name ');
  }

  /// Sets the role attribute on this node.
  ///
  /// Accepts a single role name, a space-separated string of role names, or
  /// a (possibly nested) list of role names, which is flattened and joined
  /// with spaces exactly like Ruby's `Array#join`.
  set role(Object? names) {
    attributes['role'] = names is List<Object?> ? _joinAll(names) : names;
  }

  /// Adds the role [name] to this node.
  ///
  /// Returns whether the role was added (`false` when already present).
  bool addRole(String name) {
    final value = attributes['role'];
    if (value == null || value == false) {
      attributes['role'] = name;
      return true;
    }
    // NOTE center + contains is faster than split + contains.
    if (' $value '.contains(' $name ')) return false;
    attributes['role'] = '$value $name';
    return true;
  }

  /// Removes the role [name] from this node.
  ///
  /// Returns whether the role was removed.
  bool removeRole(String name) {
    final value = attributes['role'];
    if (value == null || value == false) return false;
    final parts = _splitOnBlank(value as String);
    if (!parts.remove(name)) return false;
    if (parts.isEmpty) {
      attributes.remove('role');
    } else {
      attributes['role'] = parts.join(' ');
    }
    return true;
  }

  /// The value of the `reftext` attribute with substitutions applied.
  String? get reftext {
    final value = attributes['reftext'];
    if (value == null || value == false) return null;
    return applyReftextSubs(value as String);
  }

  /// Whether the `reftext` attribute is defined on this node.
  bool get hasReftext => attributes.containsKey('reftext');

  /// Splits [input] on runs of ASCII whitespace, dropping empty parts.
  ///
  /// Mirrors Ruby's `String#split` with no arguments (which sees ASCII
  /// whitespace only, unlike Dart's unicode-aware `\s`).
  static List<String> _splitOnBlank(String input) {
    final parts = <String>[];
    var start = -1;
    for (var i = 0; i < input.length; i++) {
      final unit = input.codeUnitAt(i);
      final isBlank =
          unit == 0x20 ||
          unit == 0x09 ||
          unit == 0x0A ||
          unit == 0x0B ||
          unit == 0x0C ||
          unit == 0x0D;
      if (isBlank) {
        if (start >= 0) {
          parts.add(input.substring(start, i));
          start = -1;
        }
      } else if (start < 0) {
        start = i;
      }
    }
    if (start >= 0) parts.add(input.substring(start));
    return parts;
  }

  /// Joins [items] with spaces, flattening nested lists and mapping `null`
  /// to the empty string, exactly like Ruby's `Array#join(' ')`.
  static String _joinAll(List<Object?> items) {
    final flat = <String>[];
    void collect(Object? item) {
      if (item is List<Object?>) {
        for (final child in item) {
          collect(child);
        }
      } else if (item != null) {
        flat.add('$item');
      } else {
        flat.add('');
      }
    }

    for (final item in items) {
      collect(item);
    }
    return flat.join(' ');
  }

  /// Returns a reference or data URI to an icon image for [name].
  ///
  /// If the `icon` attribute is set on this node, its value is used as the
  /// target image path (adding the `icontype` extension when it has none);
  /// otherwise the path is built from [name] and `icontype` (default
  /// `'png'`). The result can be safely used in an image tag.
  String iconUri(String name) {
    final String icon;
    if (hasAttr('icon')) {
      var custom = attr('icon') as String;
      // QUESTION should we be adding the extension if the icon is an absolute URI?
      if (!Helpers.hasExtname(custom)) {
        custom = '$custom.${document!.attr('icontype', 'png')}';
      }
      icon = custom;
    } else {
      icon = '$name.${document!.attr('icontype', 'png')}';
    }
    return imageUri(icon, 'iconsdir');
  }

  /// Returns a URI reference or data URI to the [targetImage].
  ///
  /// A target that is already a URI reference is left untouched. Otherwise
  /// the target is resolved relative to the directory from [assetDirKey]
  /// (default `'imagesdir'`). When the `data-uri` document attribute is set
  /// (and safe mode is below [SafeMode.secure]), the image is embedded as a
  /// data URI. The result can be safely used in an image tag.
  String imageUri(String targetImage, [String? assetDirKey = 'imagesdir']) {
    final doc = document!;
    if (doc.safe >= SafeMode.secure || !doc.hasAttr('data-uri')) {
      return normalizeWebPath(
        targetImage,
        assetDirKey == null
            ? null
            : _stringOrNull(attr(assetDirKey, null, true)),
      );
    }
    String? uriTarget;
    if (Helpers.isUriish(targetImage)) {
      uriTarget = Helpers.encodeSpacesInUri(targetImage);
    } else if (assetDirKey != null) {
      final imagesBase = _stringOrNull(attr(assetDirKey, null, true));
      if (imagesBase != null && Helpers.isUriish(imagesBase)) {
        uriTarget = normalizeWebPath(targetImage, imagesBase, false);
      }
    }
    if (uriTarget != null) {
      return doc.hasAttr('allow-uri-read')
          ? generateDataUriFromUri(uriTarget, doc.hasAttr('cache-uri'))
          : uriTarget;
    }
    return generateDataUri(targetImage, assetDirKey);
  }

  /// Returns a URI reference to the target [media].
  ///
  /// A target that is already a URI reference is left untouched. Otherwise
  /// the target is resolved relative to the directory from [assetDirKey]
  /// (default `'imagesdir'`). The result can be safely used in a media tag
  /// (`img`, `audio`, `video`).
  String mediaUri(String media, [String? assetDirKey = 'imagesdir']) {
    return normalizeWebPath(
      media,
      assetDirKey == null ? null : _stringOrNull(attr(assetDirKey, null, true)),
    );
  }

  /// Returns [value] when it is a string, otherwise `null`.
  ///
  /// Directory attributes resolve to strings; a `false` (or otherwise
  /// non-string) value is treated as absent, matching how Ruby's path
  /// helpers treat falsy values.
  static String? _stringOrNull(Object? value) => value is String ? value : null;

  /// Returns a data URI embedding the image at [targetImage].
  ///
  /// The path is first secured through [normalizeSystemPath] (relative to
  /// [assetDirKey] when given), then read and base64-encoded. When the file
  /// cannot be read, a warning is logged and an empty data URI is returned.
  String generateDataUri(String targetImage, [String? assetDirKey]) {
    final ext = Helpers.extname(targetImage, null);
    final mimetype = ext == null
        ? 'application/octet-stream'
        : ext == '.svg'
        ? 'image/svg+xml'
        : 'image/${ext.length > 1 ? ext.substring(1) : ''}';

    final imagePath = assetDirKey == null
        ? normalizeSystemPath(targetImage)
        : normalizeSystemPath(
            targetImage,
            start: _stringOrNull(attr(assetDirKey, null, true)),
            targetName: 'image',
          );

    final bytes = _readBytes(imagePath);
    if (bytes != null) {
      // NOTE base64Encode is equivalent to Base64.strict_encode64.
      return 'data:$mimetype;base64,${base64Encode(bytes)}';
    }
    logger.warn('image to embed not found or not readable: $imagePath');
    return 'data:$mimetype;base64,';
    // uncomment to return 1 pixel white dot instead
    //'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=='
  }

  /// Reads the file at [path], returning `null` when it does not exist or
  /// cannot be read (mirroring Ruby's `File.readable?` gate).
  static List<int>? _readBytes(String path) {
    if (!File(path).existsSync()) return null;
    try {
      return File(path).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Fetches [uri] over HTTP(S).
  ///
  /// Returns the response body bytes and content type. The default
  /// implementation throws [UnimplementedError]: `dart:io` offers no
  /// synchronous HTTP client, so URI fetching awaits a later wave (which
  /// may make these methods asynchronous). Tests and embedders can override
  /// this seam to supply URI data. Fetch failures surface as [Exception]s;
  /// anything else (including [UnimplementedError]) propagates to the
  /// caller instead of taking the warning path.
  ({List<int> body, String? contentType}) fetchUri(String uri) =>
      throw UnimplementedError(
        'Synchronous URI fetching is not available in dart:io; '
        'override AbstractNode.fetchUri to supply URI data.',
      );

  /// Returns a data URI built from the image data read at [imageUri].
  ///
  /// When [cacheUri] is set, the (unavailable) URI cache library is
  /// required first, mirroring Ruby's `LoadError` with a [StateError]. When
  /// the data cannot be retrieved, a warning is logged and [imageUri] is
  /// returned unchanged.
  String generateDataUriFromUri(String imageUri, [bool cacheUri = false]) {
    Helpers.requireOpenUri(cacheUri);
    try {
      final response = fetchUri(imageUri);
      final mimetype = response.contentType;
      // NOTE base64Encode is equivalent to Base64.strict_encode64.
      return 'data:${mimetype ?? ''};base64,${base64Encode(response.body)}';
    } on Exception {
      logger.warn('could not retrieve image data from URI: $imageUri');
      return imageUri;
      // uncomment to return empty data (however, mimetype needs to be resolved)
      //%(data:#{mimetype}:base64,)
      // uncomment to return 1 pixel white dot instead
      //'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=='
    }
  }

  /// Resolves and normalizes [assetRef] against the document base directory.
  ///
  /// Delegates to [normalizeSystemPath] with the start path set to the
  /// document base directory. [assetName] names the target in messages;
  /// [autocorrect] controls recovery from illegal paths.
  String normalizeAssetPath(
    String assetRef, [
    String assetName = 'path',
    bool autocorrect = true,
  ]) {
    return normalizeSystemPath(
      assetRef,
      start: document!.baseDir,
      targetName: assetName,
      recover: autocorrect,
    );
  }

  /// Resolves and normalizes a secure path from [target] and [start].
  ///
  /// See [PathResolver.systemPath] for details. The resolved path is
  /// confined to [jail] (defaulting to the document base directory) when the
  /// document safe level is [SafeMode.safe] or greater. [targetName] names
  /// the target in messages; [recover] controls recovery from illegal
  /// paths.
  String normalizeSystemPath(
    String? target, {
    String? start,
    String? jail,
    String targetName = 'path',
    bool recover = true,
  }) {
    final doc = document!;
    var startPath = start;
    var jailPath = jail;
    if (doc.safe < SafeMode.safe) {
      if (startPath != null) {
        if (!doc.pathResolver.isRoot(startPath)) {
          startPath = doc.pathResolver.joinPath([doc.baseDir, startPath]);
        }
      } else {
        startPath = doc.baseDir;
      }
    } else {
      startPath ??= doc.baseDir;
      jailPath ??= doc.baseDir;
    }
    return doc.pathResolver.systemPath(
      target,
      start: startPath,
      jail: jailPath,
      recover: recover,
      targetName: targetName,
    );
  }

  /// Normalizes the web path to [target], resolved against [start].
  ///
  /// See [PathResolver.webPath] for details. When [preserveUriTarget] is
  /// set (the default) and [target] is already a URI, it is returned with
  /// spaces encoded instead of being resolved.
  String normalizeWebPath(
    String target, [
    String? start,
    bool preserveUriTarget = true,
  ]) {
    if (preserveUriTarget && Helpers.isUriish(target)) {
      return Helpers.encodeSpacesInUri(target);
    }
    return document!.pathResolver.webPath(target, start);
  }

  /// Reads the file at [path], assuming the path is safe to read.
  ///
  /// Returns the file contents, or `null` when the file does not exist or
  /// cannot be read (logging a warning first when [warnOnFailure] is set).
  /// When [normalize] is set, the lines are normalized and joined with [lf].
  String? readAsset(
    String path, {
    bool warnOnFailure = false,
    bool normalize = false,
    String? label,
  }) {
    if (File(path).existsSync()) {
      try {
        // QUESTION should we chomp content if normalize is false?
        final content = File(path).readAsStringSync();
        return normalize
            ? Helpers.prepareSourceString(content).join(lf)
            : content;
      } on FileSystemException {
        // Fall through to the warn-or-nil path below (the file exists but
        // cannot be read, which Ruby's `File.readable?` gate would reject).
      }
    }
    if (warnOnFailure) {
      final docfile = document!.attr('docfile');
      logger.warn(
        '${docfile == null || docfile == false ? '<stdin>' : docfile}: '
        '${label ?? 'file'} does not exist or cannot be read: $path',
      );
    }
    return null;
  }

  /// Resolves [target] as a URI or system path, then reads its contents.
  ///
  /// When [target] (or [start]) is a URI, the contents are fetched only when
  /// the `allow-uri-read` document attribute is set, using the URI cache
  /// when `cache-uri` is also set. Otherwise [target] is resolved with
  /// [normalizeSystemPath] and read from the file system. [label] names the
  /// target in messages, [normalize] normalizes the data, [warnOnFailure]
  /// (default `true`) warns when the target cannot be read, and
  /// [warnIfEmpty] warns when the contents are empty.
  ///
  /// Returns the contents, or `null` when the target cannot be read.
  // TODO refactor other methods in this class to use this method were possible (repurposing if necessary)
  String? readContents(
    String target, {
    String? label,
    bool normalize = false,
    String? start,
    bool warnOnFailure = true,
    bool warnIfEmpty = false,
  }) {
    final doc = document!;
    var resolvedTarget = target;
    String? contents;
    var targetIsUri = Helpers.isUriish(resolvedTarget);
    if (!targetIsUri && start != null && Helpers.isUriish(start)) {
      // NOTE the assigned web path (a string) is always truthy in Ruby.
      resolvedTarget = doc.pathResolver.webPath(resolvedTarget, start);
      targetIsUri = true;
    }
    final assetLabel = label ?? 'asset';
    if (targetIsUri) {
      if (doc.hasAttr('allow-uri-read')) {
        if (doc.hasAttr('cache-uri')) {
          Helpers.requireLibrary('open-uri/cached', 'open-uri-cached');
        }
        try {
          final body = utf8.decode(fetchUri(resolvedTarget).body);
          contents = normalize
              ? Helpers.prepareSourceString(body).join(lf)
              : body;
        } on Exception {
          if (warnOnFailure) {
            logger.warn(
              'could not retrieve contents of $assetLabel at URI: $resolvedTarget',
            );
          }
        }
      } else if (warnOnFailure) {
        logger.warn(
          'cannot retrieve contents of $assetLabel at URI: $resolvedTarget '
          '(allow-uri-read attribute not enabled)',
        );
      }
    } else {
      resolvedTarget = normalizeSystemPath(
        target,
        start: start,
        targetName: assetLabel,
      );
      contents = readAsset(
        resolvedTarget,
        normalize: normalize,
        warnOnFailure: warnOnFailure,
        label: label,
      );
    }
    if (contents != null && warnIfEmpty && contents.isEmpty) {
      logger.warn('contents of $assetLabel is empty: $resolvedTarget');
    }
    return contents;
  }

  /// Whether [str] is a URI.
  @Deprecated('Use Helpers.isUriish instead.')
  bool isUri(String str) => Helpers.isUriish(str);

  /// Applies the substitutions [subs] to [source].
  ///
  /// [source] is a [String] or a [List] of lines (mirroring Ruby, where the
  /// verbatim path passes the lines array and gets an array back). Two
  /// vacuous cases are implemented faithfully, matching Ruby's
  /// `return text if text.empty? || !subs` guard and the no-op loop over an
  /// empty [subs] list: empty text is returned as is, a `null` [subs]
  /// returns the text unchanged, and an empty [subs] list returns strings
  /// unchanged while arrays go through the join/split round-trip (a fresh
  /// array, never the input). Anything else throws [UnimplementedError]
  /// until the substitutors wave lands.
  Object? applySubs(Object? source, [List<String>? subs]) {
    final text = source;
    if (text == null) {
      // Ruby raises NoMethodError on `nil.empty?`.
      throw StateError('applySubs: text must not be null');
    }
    if (text is String && text.isEmpty) return text;
    if (text is List<Object?> && text.isEmpty) return text;
    if (text is! String && text is! List<Object?>) {
      throw StateError('applySubs: text must be a String or a List');
    }
    if (subs == null) return text;
    if (subs.isEmpty) {
      if (text is List<Object?>) return text.join(lf).split(lf);
      return text;
    }
    throw UnimplementedError(
      'Substitutors wave: AbstractNode.applySubs with non-empty subs '
      'is not yet ported.',
    );
  }

  /// Applies title substitutions to [text].
  ///
  /// Ruby aliases this to `apply_subs` (defaulting to the normal
  /// substitutions, which always perform real work on non-empty text).
  /// Empty text is returned as is; anything else throws
  /// [UnimplementedError] until the substitutors wave lands.
  Object? applyTitleSubs(Object? text) {
    if (text is String && text.isEmpty) return text;
    throw UnimplementedError(
      'Substitutors wave: AbstractNode.applyTitleSubs is not yet ported.',
    );
  }

  /// Applies reference-text substitutions to [text].
  ///
  /// Substitutors wave: stub throwing [UnimplementedError].
  String applyReftextSubs(String text) => throw UnimplementedError(
    'Substitutors wave: AbstractNode.applyReftextSubs is not yet ported.',
  );

  /// Replaces XML special characters in [text].
  ///
  /// Substitutors wave: stub throwing [UnimplementedError].
  String subSpecialchars(String text) => throw UnimplementedError(
    'Substitutors wave: AbstractNode.subSpecialchars is not yet ported.',
  );

  /// Applies replacements (e.g. `(C)`, `--`, `...`) to [text].
  ///
  /// Substitutors wave: stub throwing [UnimplementedError].
  String subReplacements(String text) => throw UnimplementedError(
    'Substitutors wave: AbstractNode.subReplacements is not yet ported.',
  );

  /// Applies quote substitutions to [text].
  ///
  /// Substitutors wave: stub throwing [UnimplementedError].
  String subQuotes(String text) => throw UnimplementedError(
    'Substitutors wave: AbstractNode.subQuotes is not yet ported.',
  );

  /// Substitutes [value] into the `%s` placeholder of [format].
  ///
  /// Ruby aliases this to `sprintf`. Substitutors wave: stub throwing
  /// [UnimplementedError] (that wave may generalize the signature).
  String subPlaceholder(String format, Object? value) =>
      throw UnimplementedError(
        'Substitutors wave: AbstractNode.subPlaceholder is not yet ported.',
      );

  /// Resolves and assigns the substitutions for this block.
  ///
  /// Substitutors wave: stub throwing [UnimplementedError].
  void commitSubs() => throw UnimplementedError(
    'Substitutors wave: AbstractNode.commitSubs is not yet ported.',
  );
}
