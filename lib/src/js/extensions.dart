/// Extensions written in JavaScript, for the npm package's facade (see
/// `bridge.dart`).
///
/// The facade collects each processor's configuration and `process`
/// function with the Asciidoctor.js DSL and registers it here; the core
/// calls the function synchronously with views of its nodes and readers.
library;

// The bridge is called from JavaScript with positional arguments under the
// Asciidoctor.js names; the facade documents the API.
// ignore_for_file: public_member_api_docs, avoid_positional_boolean_parameters

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/js/convert.dart';
import 'package:asciidoctor/src/js/nodes.dart';
import 'package:asciidoctor/src/reader.dart';

final Expando<JSObject> _readerViews = Expando<JSObject>('ReaderBridge');
final Expando<JSObject> _registryViews = Expando<JSObject>('RegistryBridge');

/// The JavaScript view of [reader] (the same object every time).
JSObject wrapReader(Reader reader) => _readerViews[reader] ??=
    createJSInteropWrapper<ReaderBridge>(ReaderBridge(reader));

/// The JavaScript view of [registry] (the same object every time).
JSObject wrapRegistry(Registry registry) => _registryViews[registry] ??=
    createJSInteropWrapper<RegistryBridge>(RegistryBridge(registry));

/// The Dart object boxed as the `handle` of the view [value] (or of the
/// facade object holding the view as `$bridge`).
T? unwrapHandle<T extends Object>(JSAny? value) {
  if (value == null || !value.isA<JSObject>()) return null;
  var object = value as JSObject;
  final inner = object.getProperty<JSAny?>(r'$bridge'.toJS);
  if (inner != null && inner.isA<JSObject>()) object = inner as JSObject;
  final handle = object.getProperty<JSAny?>('handle'.toJS);
  if (handle == null || !handle.isA<JSBoxedDartObject>()) return null;
  final dart = (handle as JSBoxedDartObject).toDart;
  return dart is T ? dart : null;
}

/// Throws when [result] is a promise: the core runs extensions
/// synchronously.
JSAny? _sync(JSAny? result, String kind) {
  if (result != null && result.isA<JSObject>()) {
    final then = (result as JSObject).getProperty<JSAny?>('then'.toJS);
    if (then != null && then.isA<JSFunction>()) {
      throw AsciidoctorException(
        'the process function of a $kind returned a promise; '
        'asynchronous extensions are not supported',
      );
    }
  }
  return result;
}

/// The JavaScript view of one reader.
@JSExport()
final class ReaderBridge {
  new(this.reader);

  final Reader reader;

  JSBoxedDartObject get handle => reader.toJSBox;

  /// Whether the reader also resolves preprocessor directives.
  bool get isPreprocessor => reader is PreprocessorReader;

  JSArray<JSString> getLines() => jsStrings(reader.lines);

  JSArray<JSString> readLines() => jsStrings(reader.readLines());

  String? readLine() => reader.readLine();

  String? peekLine() => reader.peekLine();

  bool hasMoreLines() => reader.hasMoreLines();

  bool isEmpty() => reader.isEmpty;

  bool advance() => reader.advance();

  int? skipBlankLines() => reader.skipBlankLines();

  void unshiftLine(String line) => reader.unshiftLine(line);

  String getSource() => reader.source;

  JSArray<JSString> getSourceLines() => jsStrings(reader.sourceLines);

  JSObject? getCursor() => jsCursor(reader.cursor());

  int getLineNumber() => reader.lineno;

  String? getFile() => reader.file;

  String getPath() => reader.path;

  JSArray<JSString> peekLines(int? count, bool direct) =>
      jsStrings(reader.peekLines(count, direct: direct));

  bool isNextLineEmpty() => reader.isNextLineEmpty();

  /// Reads lines until a terminator or another condition in [options] (the
  /// Asciidoctor.js option names) or until [test] accepts a line.
  JSArray<JSString> readLinesUntil(JSObject? options, JSFunction? test) {
    bool flag(String name) =>
        options != null && boolOr(prop(options, name), orElse: false);
    return jsStrings(
      reader.readLinesUntil(
        terminator: options == null
            ? null
            : stringOrNull(prop(options, 'terminator')),
        breakOnBlankLines: flag('break_on_blank_lines'),
        breakOnListContinuation: flag('break_on_list_continuation'),
        skipFirstLine: flag('skip_first_line'),
        preserveLastLine: flag('preserve_last_line'),
        readLastLine: flag('read_last_line'),
        skipLineComments: flag('skip_line_comments'),
        skipProcessing: flag('skip_processing'),
        context: options == null
            ? null
            : stringOrNull(prop(options, 'context')),
        test: test == null
            ? null
            : (line) =>
                  boolOr(test.callAsFunction(null, line.toJS), orElse: false),
      ),
    );
  }

  void pushInclude(
    JSAny? data,
    String? file,
    String? path,
    int? lineno,
    JSObject? attributes,
  ) {
    final preprocessor = reader;
    if (preprocessor is! PreprocessorReader) return;
    final attrs = <String, String>{
      for (final entry in attributeOverrides(attributes).entries)
        entry.key: entry.value ?? '',
    };
    if (data != null && isArray(data)) {
      preprocessor.pushIncludeLines(
        stringList(data),
        file,
        path,
        lineno ?? 1,
        attrs,
      );
    } else {
      preprocessor.pushInclude(
        stringOrNull(data) ?? '',
        file,
        path,
        lineno ?? 1,
        attrs,
      );
    }
  }
}

/// Reads the facade's processor configuration into [config].
void _configure(ProcessorConfig config, JSObject? object) {
  if (object == null) return;
  final contexts = stringList(prop(object, 'contexts'));
  if (contexts.isNotEmpty) config.contexts = contexts.toSet();
  if (stringOrNull(prop(object, 'content_model')) case final model?) {
    config.contentModel = model;
  }
  final positional = stringList(prop(object, 'positional_attrs'));
  if (positional.isNotEmpty) config.positionalAttrs = positional;
  final defaults = prop(object, 'default_attrs');
  if (defaults != null && defaults.isA<JSObject>()) {
    config.defaultAttrs = {
      for (final entry in attributeOverrides(defaults).entries)
        entry.key: entry.value ?? '',
    };
  }
  if (stringOrNull(prop(object, 'format')) case final format?) {
    config.format = format;
  }
  if (stringOrNull(prop(object, 'regexp')) case final source?) {
    config.regexp = RegExp(source);
  }
  if (stringOrNull(prop(object, 'location')) case final location?) {
    config.location = location;
  }
  config.preferred = boolOr(prop(object, 'preferred'), orElse: false);
}

JSObject _attributesObject(Map<String, String> attributes) =>
    jsStringMap(attributes);

/// Copies the attributes the JavaScript code left on [object] back into
/// [attributes] (process functions may edit the attributes they receive).
void _syncAttributes(JSObject object, Map<String, String> attributes) {
  attributes
    ..clear()
    ..addAll({
      for (final entry in attributeOverrides(object).entries)
        if (entry.value != null) entry.key: entry.value!,
    });
}

/// The JavaScript view of one extension registry.
@JSExport()
final class RegistryBridge {
  new(this.registry);

  final Registry registry;

  JSBoxedDartObject get handle => registry.toJSBox;

  JSObject? getDocument() => wrapNode(registry.document);

  void addPreprocessor(JSObject? config, JSFunction process) {
    final processor = Preprocessor()
      ..onProcess = (document, reader) {
        final result = _sync(
          process.callAsFunction(null, wrapNode(document), wrapReader(reader)),
          'preprocessor',
        );
        return unwrapHandle<Reader>(result) ?? reader;
      };
    _configure(processor.config, config);
    registry.preprocessor(processor: processor);
  }

  void addTreeProcessor(JSObject? config, JSFunction process) {
    final processor = TreeProcessor()
      ..onProcess = (document) {
        final result = _sync(
          process.callAsFunction(null, wrapNode(document)),
          'tree processor',
        );
        final replacement = unwrapNode(result);
        return replacement is Document ? replacement : null;
      };
    _configure(processor.config, config);
    registry.treeProcessor(processor: processor);
  }

  void addPostprocessor(JSObject? config, JSFunction process) {
    final processor = Postprocessor()
      ..onProcess = (document, output) {
        final result = _sync(
          process.callAsFunction(null, wrapNode(document), output.toJS),
          'postprocessor',
        );
        return stringOrNull(result) ?? output;
      };
    _configure(processor.config, config);
    registry.postprocessor(processor: processor);
  }

  void addIncludeProcessor(
    JSObject? config,
    JSFunction process,
    JSFunction? handles,
  ) {
    final processor = IncludeProcessor()
      ..onProcess = (document, reader, target, attributes) {
        _sync(
          process.callAsFunction(
            null,
            wrapNode(document),
            wrapReader(reader),
            target.toJS,
            _attributesObject(attributes),
          ),
          'include processor',
        );
      };
    if (handles != null) {
      processor.onHandles = (target) {
        final result = handles.callAsFunction(null, target.toJS);
        return boolOr(result, orElse: false);
      };
    }
    _configure(processor.config, config);
    registry.includeProcessor(processor: processor);
  }

  void addDocinfoProcessor(JSObject? config, JSFunction process) {
    final processor = DocinfoProcessor()
      ..onProcess = (document) => stringOrNull(
        _sync(
          process.callAsFunction(null, wrapNode(document)),
          'docinfo processor',
        ),
      );
    _configure(processor.config, config);
    registry.docinfoProcessor(processor: processor);
  }

  void addBlock(String name, JSObject? config, JSFunction process) {
    final processor = BlockProcessor(name)
      ..onProcess = (parent, reader, attributes) {
        final attrs = _attributesObject(attributes);
        final result = _sync(
          process.callAsFunction(
            null,
            wrapNode(parent),
            wrapReader(reader),
            attrs,
          ),
          'block processor',
        );
        _syncAttributes(attrs, attributes);
        final block = unwrapNode(result);
        return block is AbstractBlock ? block : null;
      };
    _configure(processor.config, config);
    registry.block(processor: processor);
  }

  void addBlockMacro(String name, JSObject? config, JSFunction process) {
    final processor = BlockMacroProcessor(name)
      ..onProcess = (parent, target, attributes) {
        final attrs = _attributesObject(attributes);
        final result = _sync(
          process.callAsFunction(null, wrapNode(parent), target.toJS, attrs),
          'block macro processor',
        );
        _syncAttributes(attrs, attributes);
        final block = unwrapNode(result);
        return block is AbstractBlock ? block : null;
      };
    _configure(processor.config, config);
    registry.blockMacro(processor: processor);
  }

  void addInlineMacro(String name, JSObject? config, JSFunction process) {
    final processor = InlineMacroProcessor(name)
      ..onProcess = (parent, target, attributes) {
        final attrs = _attributesObject(attributes);
        final result = _sync(
          process.callAsFunction(null, wrapNode(parent), target.toJS, attrs),
          'inline macro processor',
        );
        _syncAttributes(attrs, attributes);
        final inline = unwrapNode(result);
        return inline is Inline ? inline : null;
      };
    _configure(processor.config, config);
    registry.inlineMacro(processor: processor);
  }
}

/// A processor used only for its node factories.
final class _Factories extends Processor {
  @override
  bool get hasOnProcess => false;
}

final _Factories _factories = _Factories();

Map<String, String> _attrs(JSAny? object) => {
  for (final entry in attributeOverrides(object).entries)
    entry.key: entry.value ?? '',
};

AbstractBlock _parentOf(JSAny? view) {
  final parent = unwrapNode(view);
  if (parent is! AbstractBlock) {
    throw const AsciidoctorException('the parent must be a block');
  }
  return parent;
}

/// The node factories of processors (`createBlock`, `createInline`, ...).
@JSExport()
final class FactoryBridge {
  JSObject createBlock(
    JSAny? parent,
    String context,
    JSAny? source,
    JSAny? attributes,
    String? contentModel,
  ) {
    final block = _parentOf(parent);
    final attrs = _attrs(attributes);
    final created = source != null && isArray(source)
        ? _factories.createBlockFromLines(
            block,
            context,
            stringList(source),
            attrs,
            contentModel: contentModel,
          )
        : _factories.createBlock(
            block,
            context,
            stringOrNull(source),
            attrs,
            contentModel: contentModel,
          );
    return wrapNode(created)!;
  }

  JSObject createImageBlock(JSAny? parent, JSAny? attributes) => wrapNode(
    _factories.createImageBlock(_parentOf(parent), _attrs(attributes)),
  )!;

  JSObject createInline(
    JSAny? parent,
    String context,
    String? text,
    String? type,
    String? target,
    String? id,
    JSAny? attributes,
  ) {
    final node = unwrapNode(parent);
    return wrapNode(
      _factories.createInline(
        node is AbstractBlock ? node : null,
        context,
        text,
        type: type,
        target: target,
        id: id,
        attributes: attributes == null ? null : _attrs(attributes),
      ),
    )!;
  }

  JSObject createList(JSAny? parent, String context, JSAny? attributes) =>
      wrapNode(
        _factories.createList(
          _parentOf(parent),
          context,
          attributes == null ? null : _attrs(attributes),
        ),
      )!;

  /// A reader of [data] (a string or an array of lines), positioned at
  /// [cursor]; a preprocessor reader for [document] when given.
  JSObject createReader(JSAny? data, JSAny? cursor, JSAny? document) {
    final at = cursorOf(cursor);
    final doc = unwrapNode(document);
    final lines = data != null && isArray(data) ? stringList(data) : null;
    final Reader reader;
    if (doc is Document) {
      reader = lines == null
          ? PreprocessorReader.fromString(doc, stringOrNull(data), cursor: at)
          : PreprocessorReader(doc, lines, cursor: at);
    } else {
      reader = lines == null
          ? Reader.fromString(stringOrNull(data), cursor: at)
          : Reader(lines, cursor: at);
    }
    return wrapReader(reader);
  }

  JSObject createListItem(JSAny? parent, String? text) =>
      wrapNode(_factories.createListItem(_parentOf(parent), text))!;

  JSObject createSection(
    JSAny? parent,
    String title,
    JSAny? attributes,
    int? level,
    JSAny? numbered,
  ) => wrapNode(
    _factories.createSection(
      _parentOf(parent),
      title,
      _attrs(attributes),
      level: level,
      numbered: numbered == null || !numbered.isA<JSBoolean>()
          ? null
          : (numbered as JSBoolean).toDart,
    ),
  )!;

  JSObject parseContent(JSAny? parent, JSAny? content, JSAny? attributes) {
    final block = _parentOf(parent);
    final reader =
        unwrapHandle<Reader>(content) ??
        (content != null && isArray(content)
            ? Reader(stringList(content))
            : Reader.fromString(stringOrNull(content)));
    return wrapNode(
      _factories.parseContent(
        block,
        reader,
        attributes == null ? null : _attrs(attributes),
      ),
    )!;
  }
}

/// The view of the node factories.
JSObject createFactoryBridge() =>
    createJSInteropWrapper<FactoryBridge>(FactoryBridge());

/// Registers a global extension group running [build] with the registry's
/// view; returns the group's name.
String registerExtensionGroup(String? name, JSFunction build) =>
    Extensions.register(
      name: name,
      build: (registry) => build.callAsFunction(null, wrapRegistry(registry)),
    );

/// A standalone registry whose group runs [build] (when given).
JSObject createRegistry(String? name, JSFunction? build) => wrapRegistry(
  Extensions.create(
    name: name,
    build: build == null
        ? null
        : (registry) => build.callAsFunction(null, wrapRegistry(registry)),
  ),
);
