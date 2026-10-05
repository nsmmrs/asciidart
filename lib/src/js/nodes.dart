/// JavaScript views of document nodes, for the npm package's facade (see
/// `bridge.dart`).
///
/// Every node is exposed through one [NodeBridge] object (created once per
/// node, so the facade can keep one wrapper per node). Its methods follow
/// the Asciidoctor.js names; a method that does not apply to the node's
/// kind returns `null` or an empty result.
library;

// The bridge is called from JavaScript with positional arguments, under the
// Asciidoctor.js method names (getters and setters included); the facade
// documents the API.
// ignore_for_file: public_member_api_docs, use_setters_to_change_properties
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/js/convert.dart';
import 'package:asciidart/src/js/extensions.dart' show wrapRegistry;
import 'package:asciidart/src/list.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/substitutors.dart' as subs_lib;
import 'package:asciidart/src/table.dart';

final Expando<JSObject> _wrappers = Expando<JSObject>('NodeBridge');

/// The JavaScript view of [node] (the same object every time), or `null`.
JSObject? wrapNode(AbstractNode? node) {
  if (node == null) return null;
  return _wrappers[node] ??= createJSInteropWrapper<NodeBridge>(
    NodeBridge(node),
  );
}

/// The node behind the JavaScript view [value] (a [NodeBridge] object or a
/// facade object holding one as `$bridge`).
AbstractNode? unwrapNode(JSAny? value) {
  if (value == null || !value.isA<JSObject>()) return null;
  var object = value as JSObject;
  final inner = object.getProperty<JSAny?>(r'$bridge'.toJS);
  if (inner != null && inner.isA<JSObject>()) object = inner as JSObject;
  final handle = object.getProperty<JSAny?>('handle'.toJS);
  if (handle == null || !handle.isA<JSBoxedDartObject>()) return null;
  final node = (handle as JSBoxedDartObject).toDart;
  return node is AbstractNode ? node : null;
}

JSArray<JSObject> _nodes(Iterable<AbstractNode> nodes) =>
    [for (final node in nodes) wrapNode(node)!].toJSArray;

/// The JavaScript view of one node.
@JSExport()
final class NodeBridge {
  /// Creates the view of [node].
  new(this.node);

  /// The node.
  final AbstractNode node;

  /// The node, boxed for the way back into Dart.
  JSBoxedDartObject get handle => node.toJSBox;

  /// The facade class for this node: `document`, `section`, `block`,
  /// `inline`, `list`, `list_item`, `table`, `table_cell` or
  /// `table_column`.
  String get kind => switch (node) {
    Document() => 'document',
    Section() => 'section',
    ListBlock() => 'list',
    ListItem() => 'list_item',
    Table() => 'table',
    Cell() => 'table_cell',
    Column() => 'table_column',
    Inline() => 'inline',
    _ => 'block',
  };

  AbstractBlock? get _block => switch (node) {
    final AbstractBlock block => block,
    _ => null,
  };

  // AbstractNode

  String? getId() => node.id;

  void setId(String? id) => node.id = id;

  String getContext() => node.context;

  String getNodeName() => node.nodeName;

  JSObject? getParent() => wrapNode(node.parent);

  JSObject? getDocument() => wrapNode(node.document as AbstractNode?);

  bool isBlock() => node.isBlock;

  bool isInline() => node.isInline;

  String? getAttribute(String name, String? defaultValue, String? fallback) =>
      node.attr(name, defaultValue, fallback);

  JSObject getAttributes() => jsStringMap(node.attributes);

  bool hasAttribute(String name, String? expected, String? fallback) =>
      node.hasAttr(name, expected, fallback);

  bool setAttribute(String name, String? value, bool overwrite) =>
      node.setAttr(name, value ?? '', overwrite: overwrite);

  String? removeAttribute(String name) => node.removeAttr(name);

  bool hasOption(String name) => node.hasOption(name);

  void setOption(String name) => node.setOption(name);

  JSArray<JSString> getOptions() => jsStrings(node.enabledOptions);

  String? getRole() => node.role;

  void setRole(String? names) => node.role = names;

  JSArray<JSString> getRoles() => jsStrings(node.roles);

  bool hasRole(String? name) => node.hasRole(name);

  bool addRole(String name) => node.addRole(name);

  bool removeRole(String name) => node.removeRole(name);

  /// Applies [subs] to [text] (a string or an array of lines): the normal
  /// substitutions when [subs] is `undefined`, none when it is `null`, or
  /// the names in an array or a comma-separated spec.
  JSAny applySubs(JSAny? text, JSAny? subs, bool normal) {
    final names = normal ? subs_lib.normalSubs : _subsOf(subs);
    if (text != null && isArray(text)) {
      return jsStrings(
        subs_lib.applySubsToLines(node, stringList(text), names),
      );
    }
    return subs_lib.applySubs(node, stringOrNull(text) ?? '', names).toJS;
  }

  List<String>? _subsOf(JSAny? subs) {
    if (subs == null) return null;
    if (isArray(subs)) return stringList(subs);
    return subs_lib.expandSubs(node, stringOrNull(subs) ?? '');
  }

  /// Applies the one substitution [name] to [text].
  String substitute(String name, String text) => switch (name) {
    'specialcharacters' => subs_lib.subSpecialchars(text),
    'quotes' => subs_lib.subQuotes(node, text),
    'attributes' => subs_lib.subAttributes(node, text),
    'replacements' => subs_lib.subReplacements(text),
    'macros' => subs_lib.subMacros(node, text),
    'post_replacements' => subs_lib.subPostReplacements(node, text),
    'callouts' => subs_lib.subCallouts(node, text),
    'header' => subs_lib.applyHeaderSubs(node, text),
    'title' => subs_lib.applyTitleSubs(node, text),
    'reftext' => subs_lib.applyReftextSubs(node, text),
    _ => throw ArgumentError.value(name, 'name', 'unknown substitution'),
  };

  /// Resolves the substitution spec [subs] for [type] (`block` or
  /// `inline`), or `null` when it names none.
  JSArray<JSString>? resolveSubs(
    String? subs,
    String type,
    JSAny? defaults,
    String? subject,
  ) => switch (subs_lib.resolveSubs(
    node,
    subs,
    type,
    defaults == null ? null : stringList(defaults),
    subject,
  )) {
    final names? => jsStrings(names),
    null => null,
  };

  String? getReftext() => node.reftext;

  bool hasReftext() => node.hasReftext;

  String getIconUri(String name) => node.iconUri(name);

  String getImageUri(String target, String? assetDirKey) =>
      node.imageUri(target, assetDirKey ?? 'imagesdir');

  String getMediaUri(String target, String? assetDirKey) =>
      node.mediaUri(target, assetDirKey ?? 'imagesdir');

  String normalizeWebPath(String target, String? start, bool preserveUri) =>
      node.normalizeWebPath(
        target,
        start: start,
        preserveUriTarget: preserveUri,
      );

  String normalizeSystemPath(String target, String? start, String? jail) =>
      node.normalizeSystemPath(target, start: start, jail: jail);

  String? readAsset(String path, bool warnOnFailure) =>
      node.readAsset(path, warnOnFailure: warnOnFailure);

  // AbstractBlock

  JSArray<JSObject> getBlocks() => _nodes(_block?.blocks ?? const []);

  bool hasBlocks() => _block?.hasBlocks ?? false;

  void append(JSAny? child) {
    final block = unwrapNode(child);
    if (block is AbstractBlock) _block?.append(block);
  }

  String? getTitle() => switch (node) {
    final Document doc => doc.doctitle(),
    final AbstractBlock block => block.title,
    _ => null,
  };

  void setTitle(String? title) => _block?.title = title;

  bool hasTitle() => switch (node) {
    final Document doc => doc.doctitle() != null,
    final AbstractBlock block => block.hasTitle,
    _ => false,
  };

  String? getCaption() => _block?.caption;

  void setCaption(String? caption) => _block?.caption = caption;

  String getCaptionedTitle() => _block?.captionedTitle() ?? '';

  String? getStyle() => _block?.style;

  void setStyle(String? style) => _block?.style = style;

  int? getLevel() => _block?.level;

  void setLevel(int? level) => _block?.level = level;

  String? getContentModel() => _block?.contentModel;

  void setContentModel(String model) => _block?.contentModel = model;

  JSObject? getSourceLocation() => jsCursor(_block?.sourceLocation);

  String? getFile() => _block?.file;

  int? getLineNumber() => _block?.lineno;

  JSArray<JSObject> getSections() => _nodes(_block?.sections ?? const []);

  bool hasSections() => _block?.hasSections ?? false;

  String? getNumeral() => _block?.numeral;

  void setNumeral(String? numeral) => _block?.numeral = numeral;

  JSArray<JSString> getSubstitutions() => jsStrings(_block?.subs ?? const []);

  bool hasSubstitution(String name) => _block?.hasSub(name) ?? false;

  void addSubstitution(String name) {
    final block = _block;
    if (block != null && !block.subs.contains(name)) block.subs.add(name);
  }

  void removeSubstitution(String name) => _block?.removeSub(name);

  String? getXrefText(String? xrefstyle) => switch (node) {
    final AbstractBlock block => block.xreftext(xrefstyle),
    final Inline inline => inline.xreftext(xrefstyle),
    _ => null,
  };

  JSObject? getNextAdjacentBlock() => wrapNode(_block?.nextAdjacentBlock());

  String? getAlt() => switch (node) {
    final AbstractBlock block => block.alt,
    final Inline inline => inline.alt,
    _ => null,
  };

  void assignCaption(String? value, String? captionContext) =>
      _block?.assignCaption(value, captionContext);

  /// The blocks matching [context], [style], [role] and [id], filtered by
  /// [filter] (which returns `true`, `false`, `'prune'`, `'reject'` or
  /// `'stop'` for a node view, as in Asciidoctor.js).
  JSArray<JSObject> findBy(
    String? context,
    String? style,
    String? role,
    String? id,
    bool traverseDocuments,
    JSFunction? filter,
  ) {
    final block = _block;
    if (block == null) return <JSObject>[].toJSArray;
    return _nodes(
      block.findBy(
        context: context,
        style: style,
        role: role,
        id: id,
        traverseDocuments: traverseDocuments,
        filter: filter == null
            ? null
            : (candidate) =>
                  _verdict(filter.callAsFunction(null, wrapNode(candidate))),
      ),
    );
  }

  static FindByVerdict _verdict(JSAny? result) {
    if (result == null) return FindByVerdict.skip;
    if (result.isA<JSBoolean>()) {
      return (result as JSBoolean).toDart
          ? FindByVerdict.accept
          : FindByVerdict.skip;
    }
    return switch (stringOrNull(result)) {
      'prune' => FindByVerdict.prune,
      'reject' => FindByVerdict.reject,
      'stop' => FindByVerdict.stop,
      _ => FindByVerdict.accept,
    };
  }

  String? getContent() => switch (node) {
    final Cell cell => cell.content(),
    final AbstractBlock block => block.content(),
    _ => null,
  };

  String? convert() => switch (node) {
    final Document doc => doc.convert(),
    final AbstractBlock block => block.convert(),
    final Inline inline => inline.convert(),
    _ => null,
  };

  // Block

  String getSource() => switch (node) {
    final Block block => block.source(),
    final Document doc => doc.source,
    _ => '',
  };

  JSArray<JSString> getSourceLines() => jsStrings(switch (node) {
    final Block block => block.lines,
    final Document doc => doc.sourceLines,
    _ => const <String>[],
  });

  void setLines(JSArray<JSString> lines) {
    if (node case final Block block) {
      block.lines = [for (final line in lines.toDart) line.toDart];
    }
  }

  // Section

  int getIndex() => switch (node) {
    final Section section => section.index,
    _ => 0,
  };

  String? getSectionName() => switch (node) {
    final Section section => section.sectname,
    _ => null,
  };

  void setSectionName(String? name) {
    if (node case final Section section) section.sectname = name;
  }

  bool isSpecial() => switch (node) {
    final Section section => section.special,
    _ => false,
  };

  bool isNumbered() => switch (node) {
    final Section section => section.numbered,
    _ => false,
  };

  String sectnum(String? delimiter, String? append) => switch (node) {
    final Section section => section.sectnum(delimiter ?? '.', append),
    _ => '',
  };

  // Inline

  String? getText() => switch (node) {
    final Inline inline => inline.text,
    final ListItem item => item.text,
    final Cell cell => cell.text,
    _ => null,
  };

  void setText(String? text) {
    switch (node) {
      case final Inline inline:
        inline.text = text;
      case final ListItem item:
        item.text = text;
      case final Cell cell:
        cell.text = text;
    }
  }

  String? getType() => switch (node) {
    final Inline inline => inline.type,
    _ => null,
  };

  String? getTarget() => switch (node) {
    final Inline inline => inline.target,
    _ => null,
  };

  // List and ListItem

  JSArray<JSAny> getItems() {
    if (node case final ListBlock list) {
      if (list.context == 'dlist') {
        return [
          for (final entry in list.entries)
            [_nodes(entry.terms), wrapNode(entry.description)].toJSArray,
        ].toJSArray;
      }
      return _nodes(list.items);
    }
    return <JSAny>[].toJSArray;
  }

  bool hasItems() => switch (node) {
    final ListBlock list => list.hasItems,
    _ => false,
  };

  bool hasText() => switch (node) {
    final ListItem item => item.hasText,
    _ => false,
  };

  bool isOutline() => switch (node) {
    final ListBlock list => list.isOutline,
    _ => false,
  };

  bool isSimple() => switch (node) {
    final ListItem item => item.isSimple,
    _ => false,
  };

  bool isCompound() => switch (node) {
    final ListItem item => item.isCompound,
    _ => false,
  };

  JSObject? getExtensions() => switch (node) {
    final Document doc when doc.extensions != null => wrapRegistry(
      doc.extensions!,
    ),
    _ => null,
  };

  void commitSubs() {
    if (node is AbstractBlock) node.commitSubs();
  }

  String? getMarker() => switch (node) {
    final ListItem item => item.marker,
    _ => null,
  };

  void setMarker(String? marker) {
    if (node case final ListItem item) item.marker = marker;
  }

  // Table

  JSArray<JSArray<JSObject>> _rows(List<List<Cell>> rows) =>
      [for (final row in rows) _nodes(row)].toJSArray;

  JSObject getRows() {
    final object = JSObject();
    if (node case final Table table) {
      object
        ..setProperty('head'.toJS, _rows(table.rows.head))
        ..setProperty('body'.toJS, _rows(table.rows.body))
        ..setProperty('foot'.toJS, _rows(table.rows.foot));
    }
    return object;
  }

  JSArray<JSObject> getColumns() => switch (node) {
    final Table table => _nodes(table.columns),
    _ => <JSObject>[].toJSArray,
  };

  JSObject? getColumn() => switch (node) {
    final Cell cell => wrapNode(cell.column),
    _ => null,
  };

  int? getColumnSpan() => switch (node) {
    final Cell cell => cell.colspan,
    _ => null,
  };

  int? getRowSpan() => switch (node) {
    final Cell cell => cell.rowspan,
    _ => null,
  };

  JSObject? getInnerDocument() => switch (node) {
    final Cell cell => wrapNode(cell.innerDocument),
    _ => null,
  };

  // Document

  Document? get _doc => switch (node) {
    final Document doc => doc,
    _ => null,
  };

  JSAny? getDoctitle(bool partition, bool sanitize, bool useFallback) {
    final doc = _doc;
    if (doc == null) return null;
    if (!partition) {
      return doc.doctitle(sanitize: sanitize, useFallback: useFallback)?.toJS;
    }
    final title = doc.partitionedTitle(
      sanitize: sanitize,
      useFallback: useFallback,
    );
    if (title == null) return null;
    return JSObject()
      ..setProperty('main'.toJS, title.main.toJS)
      ..setProperty('subtitle'.toJS, title.subtitle?.toJS)
      ..setProperty('combined'.toJS, title.combined.toJS)
      ..setProperty('sanitized'.toJS, title.sanitized.toJS);
  }

  String? getAuthor() => _doc?.author;

  JSArray<JSObject> getAuthors() => [
    for (final author in _doc?.authors ?? const <DocumentAuthor>[])
      (JSObject()
        ..setProperty('name'.toJS, author.name?.toJS)
        ..setProperty('firstname'.toJS, author.firstname?.toJS)
        ..setProperty('middlename'.toJS, author.middlename?.toJS)
        ..setProperty('lastname'.toJS, author.lastname?.toJS)
        ..setProperty('initials'.toJS, author.initials?.toJS)
        ..setProperty('email'.toJS, author.email?.toJS)),
  ].toJSArray;

  JSObject? getHeader() => wrapNode(_doc?.header);

  bool hasHeader() => _doc?.hasHeader ?? false;

  int getSafe() => _doc?.safe ?? SafeMode.secure;

  String? getBackend() => _doc?.backend;

  String? getDoctype() => _doc?.doctype;

  String? getBaseDir() => _doc?.baseDir;

  String? getOutfilesuffix() => _doc?.outfilesuffix;

  bool getSourcemap() => _doc?.sourcemap ?? false;

  void setSourcemap(bool value) => _doc?.sourcemap = value;

  bool getCompatMode() => _doc?.compatMode ?? false;

  bool isNested() => _doc?.nested() ?? false;

  bool isEmbedded() => _doc?.embedded ?? false;

  bool hasFootnotes() => _doc?.hasFootnotes ?? false;

  JSArray<JSObject> getFootnotes() => [
    for (final footnote in _doc?.footnotes ?? const <Footnote>[])
      (JSObject()
        ..setProperty('index'.toJS, footnote.index.toJS)
        ..setProperty('id'.toJS, footnote.id?.toJS)
        ..setProperty('text'.toJS, footnote.text.toJS)),
  ].toJSArray;

  JSArray<JSObject> getImages() => [
    for (final image in _doc?.catalog.images ?? const <ImageReference>[])
      (JSObject()
        ..setProperty('target'.toJS, image.target.toJS)
        ..setProperty('imagesdir'.toJS, image.imagesdir?.toJS)),
  ].toJSArray;

  JSArray<JSString> getLinks() => jsStrings(_doc?.catalog.links ?? const []);

  JSObject getRefs() {
    final object = JSObject();
    _doc?.catalog.refs.forEach(
      (id, ref) => object.setProperty(id.toJS, wrapNode(ref)),
    );
    return object;
  }

  JSArray<JSString> getIncludes() =>
      jsStrings(_doc?.catalog.includes.keys ?? const []);

  String counter(String name, String? seed) => _doc?.counter(name, seed) ?? '';

  void restoreAttributes() => _doc?.restoreAttributes();

  String? setDocumentAttribute(String name, String? value) =>
      _doc?.setAttribute(name, value ?? '');

  bool deleteAttribute(String name) => _doc?.deleteAttribute(name) ?? false;

  bool isAttributeLocked(String name) => _doc?.attributeLocked(name) ?? false;

  bool setHeaderAttribute(String name, String? value, bool overwrite) =>
      _doc?.setHeaderAttribute(name, value ?? '', overwrite: overwrite) ??
      false;

  String convertDocument(JSAny? standalone) {
    final doc = _doc;
    if (doc == null) return '';
    return doc.convert(
      standalone: standalone == null || !standalone.isA<JSBoolean>()
          ? null
          : (standalone as JSBoolean).toDart,
    );
  }

  String getDocinfo(String? location, String? suffix) =>
      _doc?.docinfo(location ?? 'head', suffix) ?? '';

  bool hasExtensions() => _doc?.hasExtensions ?? false;

  bool getNotitle() => _doc?.notitle ?? false;

  bool getNoheader() => _doc?.noheader ?? false;

  bool getNofooter() => _doc?.nofooter ?? false;

  JSObject? getFirstSection() => wrapNode(_doc?.firstSection);

  bool isBasebackend(String base) => _doc?.basebackend(base) ?? false;

  String? resolveId(String text) => _doc?.resolveId(text);

  bool isParsed() => _doc?.isParsed ?? false;

  JSObject? parse() {
    final doc = _doc;
    if (doc == null) return null;
    return wrapNode(doc.parse());
  }

  JSObject? getParentDocument() => wrapNode(_doc?.parentDocument);

  String? getRevisionDate() => node.attr('revdate');

  String? getRevisionNumber() => node.attr('revnumber');

  String? getRevisionRemark() => node.attr('revremark');
}
