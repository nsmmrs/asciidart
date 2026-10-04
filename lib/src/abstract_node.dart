/// Base class for every node in a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/abstract_node.rb`.
///
/// Node contexts and other symbolic names are `String`s throughout
/// (`'paragraph'`, `'listing'`, ...).
///
/// Nodes reach the document and the converter through two small interfaces
/// declared here: [NodeDocument], implemented by `Document`, and
/// [NodeConverter], implemented by `Converter`. Nodes log through
/// [LoggerManager.logger].
///
/// The substitution methods (`applySubs`, `subQuotes` and friends) delegate
/// to the top-level functions in `substitutors.dart`, so every node answers
/// them.
library;

import 'dart:convert' show base64Encode, utf8;
import 'dart:io' show File, FileSystemException;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/callouts.dart';
import 'package:asciidoctor/src/document.dart' show Catalog;
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/substitutors.dart' as substitutors;

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
/// Port of the `convert` method on `Asciidoctor::Converter`; implemented by
/// `Converter`.
abstract interface class NodeConverter {
  /// Converts [node] to the output format, or returns `null` when the
  /// converter produces nothing for it.
  String? convert(AbstractNode node);
}

/// The `Document` API surface consumed by nodes.
///
/// Implemented by `Document`. Most members are satisfied
/// automatically because `Document` extends [AbstractBlock], which extends
/// [AbstractNode].
abstract interface class NodeDocument {
  /// The document-wide attributes.
  Map<String, String> get attributes;

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

  /// The document catalog (references, footnotes, images, callouts, ...).
  Catalog get catalog;

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
  String? attr(String name, [String? defaultValue, String? fallbackName]);

  /// Whether document attribute [name] is set, optionally comparing it
  /// against [expectedValue].
  ///
  /// Mirrors `AbstractNode#attr?` as inherited by `Document`.
  bool hasAttr(String name, [String? expectedValue, String? fallbackName]);

  /// Returns the next value in the sequence for the counter [name],
  /// seeding it with [seed] when seen for the first time.
  String counter(String name, [String? seed]);

  /// Increments the counter [counterName], stores it in [block]'s
  /// attributes, and returns the new value.
  String incrementAndStoreCounter(String counterName, AbstractBlock block);

  /// Replays the attribute entries recorded on [block] against the
  /// document.
  void playbackAttributes(AbstractBlock block);
}

/// An abstract base class that provides state and methods for managing a
/// node of AsciiDoc content.
///
/// The state and methods on this class are common to all content segments
/// in an AsciiDoc document. Port of `Asciidoctor::AbstractNode`.
abstract class AbstractNode {
  /// Creates a node with [parent] and [context].
  ///
  /// When [context] is `'document'`, the node refers to itself as its
  /// document (and must implement [NodeDocument]), ignoring [parent] (which
  /// stays `null`);
  /// otherwise the document is taken from [parent] (which may be `null`,
  /// leaving [document] unset until the node is attached with [parent] or
  /// `AbstractBlock.append`). [attributes] is copied; [nodeName] overrides
  /// the default node name, which is [context].
  new(
    AbstractBlock? parent,
    String context, {
    Map<String, String>? attributes,
    String? nodeName,
  }) : _parent = parent,
       _context = context,
       _nodeName = nodeName ?? context,
       attributes = attributes == null
           ? <String, String>{}
           : Map<String, String>.of(attributes) {
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

  /// The attributes of this node.
  final Map<String, String> attributes;

  /// The id of this node.
  String? id;

  String _context;
  String _nodeName;
  AbstractBlock? _parent;
  NodeDocument? _document;

  /// Whether this node is a block-level node.
  bool get isBlock;

  /// Whether this node is an inline node.
  bool get isInline;

  /// The context (type qualifier) of this node, e.g. `'paragraph'`.
  String get context => _context;

  /// Reassigns the context and re-derives [nodeName] from it.
  ///
  /// Defined here so every subclass shares the same behavior; meant for
  /// blocks.
  set context(String value) {
    _context = value;
    _nodeName = value;
  }

  /// The name of this node (the context, except on `Inline` nodes).
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

  /// The shared logger ([LoggerManager.logger]).
  LoggerBase get logger => LoggerManager.logger;

  /// The converter being used to convert the current document.
  NodeConverter get converter => document!.converter;

  /// Returns the value of attribute [name] on this node.
  ///
  /// If the attribute is not found on this node, [fallbackName] is given and
  /// this node is not the document node, returns the value of the document
  /// attribute named [fallbackName] instead. Otherwise returns
  /// [defaultValue].
  String? attr(String name, [String? defaultValue, String? fallbackName]) {
    final value = attributes[name];
    if (value != null) return value;
    if (fallbackName != null && parent != null) {
      final docValue = document!.attributes[fallbackName];
      if (docValue != null) return docValue;
    }
    return defaultValue;
  }

  /// Whether attribute [name] is defined, using the same lookup logic as
  /// [attr], optionally comparing against [expectedValue].
  ///
  /// If [expectedValue] is given, returns whether the resolved value equals
  /// it; otherwise returns whether the attribute was found.
  bool hasAttr(String name, [String? expectedValue, String? fallbackName]) {
    final useFallback = fallbackName != null && parent != null;
    if (expectedValue != null) {
      final value =
          attributes[name] ??
          (useFallback ? document!.attributes[fallbackName] : null);
      return expectedValue == value;
    }
    if (attributes.containsKey(name)) return true;
    if (useFallback) return document!.attributes.containsKey(fallbackName);
    return false;
  }

  /// Assigns [value] to attribute [name] on this node.
  ///
  /// Returns whether the assignment was performed (`false` only when
  /// [overwrite] is `false` and the attribute already exists).
  bool setAttr(String name, String value, {bool overwrite = true}) {
    if (!overwrite && attributes.containsKey(name)) return false;
    attributes[name] = value;
    return true;
  }

  /// Removes attribute [name] from this node.
  ///
  /// Returns the previous value, or `null` if the attribute was absent.
  String? removeAttr(String name) => attributes.remove(name);

  /// Whether the option [name] is enabled on this node.
  ///
  /// An option is enabled when the `<name>-option` attribute is defined.
  bool hasOption(String name) => attributes.containsKey('$name-option');

  /// Enables the option [name] on this node.
  void setOption(String name) {
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
  Map<String, String> updateAttributes(Map<String, String> newAttributes) {
    attributes.addAll(newAttributes);
    return attributes;
  }

  /// The space-separated role of this node.
  String? get role => attributes['role'];

  /// Sets the role attribute on this node (a single role name or a
  /// space-separated list of role names); `null` removes it.
  set role(String? names) {
    if (names == null) {
      attributes.remove('role');
    } else {
      attributes['role'] = names;
    }
  }

  /// Sets the role attribute on this node from a list of role [names].
  void setRoles(List<String> names) {
    attributes['role'] = names.join(' ');
  }

  /// The role names of this node.
  ///
  /// Empty when the `role` attribute is absent on this node.
  List<String> get roles {
    final value = attributes['role'];
    if (value == null) return <String>[];
    return _splitOnBlank(value);
  }

  /// Whether the role attribute is set on this node and, when
  /// [expectedValue] is given, whether it equals that value.
  bool hasRole([String? expectedValue]) {
    if (expectedValue == null) return attributes.containsKey('role');
    return expectedValue == attributes['role'];
  }

  /// Whether [name] is one of the roles of this node.
  bool includesRole(String name) {
    final value = attributes['role'];
    if (value == null) return false;
    // NOTE center + contains is faster than split + contains.
    return ' $value '.contains(' $name ');
  }

  /// Adds the role [name] to this node.
  ///
  /// Returns whether the role was added (`false` when already present).
  bool addRole(String name) {
    final value = attributes['role'];
    if (value == null) {
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
    if (value == null) return false;
    final parts = _splitOnBlank(value);
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
    if (value == null) return null;
    return applyReftextSubs(value);
  }

  /// Whether the `reftext` attribute is defined on this node.
  bool get hasReftext => attributes.containsKey('reftext');

  /// Splits [input] on runs of ASCII whitespace, dropping empty parts.
  ///
  /// Only ASCII whitespace separates (Dart's `\s` would also match Unicode
  /// spaces).
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

  /// Returns a reference or data URI to an icon image for [name].
  ///
  /// If the `icon` attribute is set on this node, its value is used as the
  /// target image path (adding the `icontype` extension when it has none);
  /// otherwise the path is built from [name] and `icontype` (default
  /// `'png'`). The result can be safely used in an image tag.
  String iconUri(String name) {
    final String icon;
    if (hasAttr('icon')) {
      var custom = attr('icon')!;
      // QUESTION should we be adding the extension if the icon is an
      // absolute URI?
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
        start: assetDirKey == null ? null : doc.attr(assetDirKey),
      );
    }
    String? uriTarget;
    if (Helpers.isUriish(targetImage)) {
      uriTarget = Helpers.encodeSpacesInUri(targetImage);
    } else if (assetDirKey != null) {
      final imagesBase = doc.attr(assetDirKey);
      if (imagesBase != null && Helpers.isUriish(imagesBase)) {
        uriTarget = normalizeWebPath(
          targetImage,
          start: imagesBase,
          preserveUriTarget: false,
        );
      }
    }
    if (uriTarget != null) {
      return doc.hasAttr('allow-uri-read')
          ? generateDataUriFromUri(
              uriTarget,
              cacheUri: doc.hasAttr('cache-uri'),
            )
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
      start: assetDirKey == null ? null : document!.attr(assetDirKey),
    );
  }

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
            start: document!.attr(assetDirKey),
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
  /// cannot be read.
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
  /// synchronous HTTP client, so URI fetching is not built in. Tests and
  /// embedders can override this method to supply URI data. Fetch failures
  /// surface as [Exception]s; anything else (including [UnimplementedError])
  /// propagates to the caller instead of taking the warning path.
  ({List<int> body, String? contentType}) fetchUri(String uri) =>
      throw UnimplementedError(
        'Synchronous URI fetching is not available in dart:io; '
        'override AbstractNode.fetchUri to supply URI data.',
      );

  /// Returns a data URI built from the image data read at [imageUri].
  ///
  /// When [cacheUri] is set, the (unavailable) URI cache library is
  /// required first, which throws a [StateError]. When
  /// the data cannot be retrieved, a warning is logged and [imageUri] is
  /// returned unchanged.
  String generateDataUriFromUri(String imageUri, {bool cacheUri = false}) {
    Helpers.requireOpenUri(cache: cacheUri);
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
    String assetRef, {
    String assetName = 'path',
    bool autocorrect = true,
  }) {
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
    String target, {
    String? start,
    bool preserveUriTarget = true,
  }) {
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
        // Fall through to the warn-or-null path below (the file exists but
        // cannot be read).
      }
    }
    if (warnOnFailure) {
      final docfile = attr('docfile');
      logger.warn(
        '${docfile ?? '<stdin>'}: '
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
  // TODO refactor other methods in this class to use this method were
  // possible (repurposing if necessary)
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
      // NOTE the assigned web path (a string) always counts as set.
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
              'could not retrieve contents of $assetLabel at URI: '
              '$resolvedTarget',
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

  /// Applies the substitutions [subs] (the normal substitutions by
  /// default; `null` applies none) to [text].
  ///
  /// Delegates to `substitutors.applySubs` with this node.
  String applySubs(
    String text, [
    List<String>? subs = substitutors.normalSubs,
  ]) => substitutors.applySubs(this, text, subs);

  /// Applies the substitutions [subs] to [lines] as one multi-line text,
  /// returning the result split back into lines.
  ///
  /// Delegates to `substitutors.applySubsToLines` with this node.
  List<String> applySubsToLines(
    List<String> lines, [
    List<String>? subs = substitutors.normalSubs,
  ]) => substitutors.applySubsToLines(this, lines, subs);

  /// Applies title substitutions to [text].
  ///
  /// Delegates to `substitutors.applyTitleSubs` with this node.
  String applyTitleSubs(String text) => substitutors.applyTitleSubs(this, text);

  /// Applies reference-text substitutions to [text].
  ///
  /// Delegates to `substitutors.applyReftextSubs` with this node.
  String applyReftextSubs(String text) =>
      substitutors.applyReftextSubs(this, text);

  /// Replaces XML special characters in [text].
  ///
  /// Delegates to `substitutors.subSpecialchars` (pure function).
  String subSpecialchars(String text) => substitutors.subSpecialchars(text);

  /// Applies replacements (e.g. `(C)`, `--`, `...`) to [text].
  ///
  /// Delegates to `substitutors.subReplacements` (pure function).
  String subReplacements(String text) => substitutors.subReplacements(text);

  /// Applies quote substitutions to [text].
  ///
  /// Delegates to `substitutors.subQuotes` with this node.
  String subQuotes(String text) => substitutors.subQuotes(this, text);

  /// Applies macro substitutions to [text].
  ///
  /// Delegates to `substitutors.subMacros` with this node.
  String subMacros(String text) => substitutors.subMacros(this, text);

  /// Substitutes [value] into the `%s` placeholder of [format].
  ///
  /// Delegates to
  /// `substitutors.subPlaceholder` (pure function).
  String subPlaceholder(String format, String value) =>
      substitutors.subPlaceholder(format, value);

  /// Resolves and assigns the substitutions for this block.
  ///
  /// Only meaningful on blocks (mirrors `Substitutors#commit_subs`, which
  /// reads the block's content model). Delegates to
  /// `substitutors.commitSubs`.
  void commitSubs() => substitutors.commitSubs(this as AbstractBlock);
}
