/// The API the npm package's JavaScript facade calls into (see
/// `entry.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/cli/diagnostics.dart';
import 'package:asciidoctor/src/cli/run.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/docbook5.dart';
import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/extensions.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/js/convert.dart';
import 'package:asciidoctor/src/js/extensions.dart' as ext;
import 'package:asciidoctor/src/js/nodes.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/manpage.dart';
import 'package:asciidoctor/src/options.dart';
import 'package:asciidoctor/src/version.dart';

@JS('Error')
external JSFunction get _errorConstructor;

/// A JavaScript promise for [body]'s result; a failure rejects it with a
/// JavaScript `Error` carrying the failure's message (see [describe]).
JSPromise<T> _promise<T extends JSAny?>(Future<T> Function() body) =>
    JSPromise<T>(
      (JSFunction resolve, JSFunction reject) {
        unawaited(
          Future<T>.sync(body).then(
            (value) => resolve.callAsFunction(null, value),
            onError: (Object error, StackTrace stack) {
              // An error thrown by JavaScript code (a converter or an
              // extension) reaches the caller unchanged. This library only
              // compiles with dart2js, which leaves JavaScript errors as
              // they are.
              // ignore: invalid_runtime_check_with_js_interop_types
              if (error is JSObject) {
                reject.callAsFunction(null, error);
                return;
              }
              final jsError = _errorConstructor.callAsConstructor<JSObject>(
                describe(error).toJS,
              );
              if (error is AsciidoctorException) {
                jsError.setProperty('name'.toJS, 'AsciidoctorError'.toJS);
              }
              jsError.setProperty('dartStack'.toJS, '$stack'.toJS);
              reject.callAsFunction(null, jsError);
            },
          ),
        );
      }.toJS,
    );

/// The top-level functions of the facade.
@JSExport()
final class ApiBridge {
  /// The version of this package.
  String get version => Asciidoctor.packageVersion;

  /// The version of Asciidoctor whose behavior this package matches.
  String get coreVersion => Asciidoctor.version;

  /// Runs the CLI with [args], resolving to the exit code.
  JSPromise<JSNumber> runCli(JSArray<JSString> args) =>
      runCliCode([for (final arg in args.toDart) arg.toDart])
          .then((code) => code.toJS)
          .toJS;

  /// Loads [input] (a string, an array of lines or UTF-8 bytes) with the
  /// facade [options], resolving to the document's view.
  JSPromise<JSObject> load(JSAny? input, JSObject? options) {
    return _promise(() {
      final settings = _Settings.of(options);
      return loadAsync(
        _source(input),
        options: settings.options,
        parse: settings.parse,
      ).then((doc) => wrapNode(doc)!);
    });
  }

  /// Loads the file at [path] with the facade [options], resolving to the
  /// document's view.
  JSPromise<JSObject> loadFile(String path, JSObject? options) {
    return _promise(() {
      final settings = _Settings.of(options);
      return loadFileAsync(
        path,
        options: settings.options,
        parse: settings.parse,
      ).then((doc) => wrapNode(doc)!);
    });
  }

  /// Converts [input] with the facade [options], resolving to the output,
  /// or to the document's view when the output was written to a file.
  JSPromise<JSAny> convert(JSAny? input, JSObject? options) => _promise(() {
    final settings = _Settings.of(options);
    final source = _source(input);
    if (settings.writesToTarget) {
      return convertToTargetAsync(
        source,
        settings.options,
      ).then<JSAny>((doc) => wrapNode(doc)!);
    }
    return convertAsync(
      source,
      settings.options,
    ).then<JSAny>((output) => output.toJS);
  });

  /// Converts the file at [path] with the facade [options], resolving to
  /// the document's view, or to the output when `to_file` is `false`.
  JSPromise<JSAny> convertFile(String path, JSObject? options) => _promise(() {
    final settings = _Settings.of(options);
    if (settings.returnsString) {
      final output = StringBuffer();
      return convertFileAsync(
        path,
        settings.options,
        output,
      ).then<JSAny>((_) => output.toString().toJS);
    }
    return convertFileAsync(
      path,
      settings.options,
    ).then<JSAny>((doc) => wrapNode(doc)!);
  });

  /// Sends every log record to [handler] (called with the severity number,
  /// the message text and the source location object or `null`), asking
  /// [level] for the current level number.
  void setLogHandler(JSFunction handler, JSFunction level) {
    LoggerManager.logger = _ForwardingLogger(handler, level);
  }

  /// Restores the default logger (standard error).
  void resetLogHandler() {
    LoggerManager.logger = null;
  }

  /// Registers a global extension group running [build] with a registry
  /// view; returns the group's name.
  String registerExtensionGroup(String? name, JSFunction build) =>
      ext.registerExtensionGroup(name, build);

  /// Unregisters the global extension groups named [names], or all of them
  /// when [names] is `null`.
  void unregisterExtensions(JSArray<JSString>? names) {
    if (names == null) {
      Extensions.unregisterAll();
    } else {
      Extensions.unregister([for (final name in names.toDart) name.toDart]);
    }
  }

  /// The names of the global extension groups.
  JSArray<JSString> extensionGroupNames() => jsStrings(Extensions.groups.keys);

  /// A standalone registry view whose group runs [build] (when given).
  JSObject createRegistry(String? name, JSFunction? build) =>
      ext.createRegistry(name, build);

  /// The node factories of processors.
  JSObject get factories => _factories ??= ext.createFactoryBridge();
  JSObject? _factories;

  /// Registers converters for [backends] made by [create], which is called
  /// with the backend name and returns a converter object (see
  /// [JsConverter]).
  void registerConverter(JSFunction create, JSArray<JSString> backends) {
    Converter.register(
      (backend, opts) => JsConverter(
        backend,
        create.callAsFunction(null, backend.toJS)! as JSObject,
      ),
      [for (final backend in backends.toDart) backend.toDart],
    );
  }

  /// Unregisters the converters registered from JavaScript.
  void unregisterConverters() => Converter.unregisterAll();

  /// Converts the node view [node] with the built-in converter for
  /// [backend] (`html5`, `docbook5` or `manpage`).
  String? convertBuiltIn(String backend, JSAny? node, String? transform) {
    final dart = unwrapNode(node);
    if (dart == null) {
      throw const AsciidoctorException('convert expects a node');
    }
    return _builtIn(backend).convert(dart, transform);
  }

  /// Whether the built-in converter for [backend] handles [transform].
  bool builtInHandles(String backend, String transform) =>
      _builtIn(backend).handles(transform);

  final Map<String, Converter> _builtIns = {};

  Converter _builtIn(String backend) =>
      _builtIns[backend] ??= switch (backend) {
        'html5' => Html5Converter(backend),
        'docbook5' => Docbook5Converter(backend),
        'manpage' => ManpageConverter(backend),
        _ => throw AsciidoctorException('no built-in converter for $backend'),
      };

  /// The traits of [backend] (on top of [basebackend], when given).
  JSObject deriveBackendTraits(String backend, String? basebackend) {
    final traits = BackendTraits.derive(backend, basebackend);
    return jsStringMap({
      'basebackend': traits.basebackend,
      'filetype': traits.filetype,
      'outfilesuffix': traits.outfilesuffix,
      'htmlsyntax': ?traits.htmlsyntax,
    });
  }
}

/// A converter written in JavaScript: an object with a
/// `convert(nodeView, transform)` method, and optionally `handles` and the
/// backend traits `basebackend`, `filetype`, `outfilesuffix` and
/// `htmlsyntax`.
final class JsConverter extends Converter {
  /// Creates the converter for [backend] calling [delegate].
  new(super.backend, this.delegate) {
    final basebackend = stringOrNull(prop(delegate, 'basebackend'));
    final outfilesuffix = stringOrNull(prop(delegate, 'outfilesuffix'));
    if (basebackend != null || outfilesuffix != null) {
      final derived = BackendTraits.derive(backend, basebackend);
      backendTraits = BackendTraits(
        basebackend: derived.basebackend,
        filetype: stringOrNull(prop(delegate, 'filetype')) ?? derived.filetype,
        outfilesuffix: outfilesuffix ?? derived.outfilesuffix,
        htmlsyntax:
            stringOrNull(prop(delegate, 'htmlsyntax')) ?? derived.htmlsyntax,
      );
    }
  }

  /// The JavaScript converter.
  final JSObject delegate;

  @override
  String? convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) {
    final result = delegate.callMethod<JSAny?>(
      'convert'.toJS,
      wrapNode(node),
      (transform ?? node.nodeName).toJS,
    );
    return stringOrNull(result);
  }

  @override
  bool handles(String transform) {
    final handles = prop(delegate, 'handles');
    if (handles == null || !handles.isA<JSFunction>()) return true;
    return boolOr(
      delegate.callMethod<JSAny?>('handles'.toJS, transform.toJS),
      orElse: false,
    );
  }
}

/// The source text of a facade input.
String? _source(JSAny? input) {
  if (input == null) return null;
  if (input.isA<JSString>()) return (input as JSString).toDart;
  if (isArray(input)) return stringList(input).join('\n');
  if (input.isA<JSUint8Array>()) {
    return utf8.decode((input as JSUint8Array).toDart);
  }
  return '$input';
}

/// The typed options and entry point switches of a facade options object.
final class _Settings {
  const new(
    this.options, {
    this.parse = true,
    this.writesToTarget = false,
    this.returnsString = false,
  });

  factory of(JSObject? object) {
    if (object == null) return const _Settings(AsciidoctorOptions());
    final toFile = prop(object, 'to_file');
    final toDir = stringOrNull(prop(object, 'to_dir'));
    final toFilePath = stringOrNull(toFile);
    final standalone =
        prop(object, 'standalone') ?? prop(object, 'header_footer');
    final options = AsciidoctorOptions(
      safe: safeModeOf(prop(object, 'safe')),
      backend: stringOrNull(prop(object, 'backend')),
      doctype: stringOrNull(prop(object, 'doctype')),
      attributes: attributeOverrides(prop(object, 'attributes')),
      standalone: standalone == null ? null : boolOr(standalone, orElse: false),
      baseDir: stringOrNull(prop(object, 'base_dir')),
      toFile: toFilePath,
      toDir: toDir,
      mkdirs: boolOr(prop(object, 'mkdirs'), orElse: false),
      sourcemap: boolOr(prop(object, 'sourcemap'), orElse: false),
      parseHeaderOnly: boolOr(prop(object, 'parse_header_only'), orElse: false),
      catalogAssets: boolOr(prop(object, 'catalog_assets'), orElse: false),
      templateDirs: [
        ...stringList(prop(object, 'template_dirs')),
        ?stringOrNull(prop(object, 'template_dir')),
      ],
      templateEngine: stringOrNull(prop(object, 'template_engine')),
      templateCache: boolOr(prop(object, 'template_cache'), orElse: true),
      extensionRegistry: ext.unwrapHandle<Registry>(
        prop(object, 'extension_registry'),
      ),
      converter: switch (prop(object, 'converter')) {
        final JSObject converter? when prop(converter, 'convert') != null =>
          JsConverter(
            stringOrNull(prop(object, 'backend')) ?? 'html5',
            converter,
          ),
        _ => null,
      },
    );
    return _Settings(
      options,
      parse: boolOr(prop(object, 'parse'), orElse: true),
      writesToTarget: toFilePath != null || toDir != null,
      returnsString:
          toFile != null &&
          toFile.isA<JSBoolean>() &&
          !(toFile as JSBoolean).toDart,
    );
  }

  final AsciidoctorOptions options;
  final bool parse;
  final bool writesToTarget;
  final bool returnsString;
}

/// A logger sending every record to the facade's current logger.
final class _ForwardingLogger extends LoggerBase {
  new(this._handler, this._level) : super(Severity.debug);

  final JSFunction _handler;
  final JSFunction _level;
  Severity? _maxSeverity;

  @override
  Severity get level {
    final value = _level.callAsFunction();
    final number = value == null ? null : intOrNull(value);
    return number == null ? Severity.warn : Severity.fromValue(number);
  }

  @override
  Severity? get maxSeverity => _maxSeverity;

  @override
  void add(Severity severity, LogMessage message) {
    final max = _maxSeverity;
    if (max == null || severity.value > max.value) _maxSeverity = severity;
    _handler.callAsFunction(
      null,
      severity.value.toJS,
      message.text.toJS,
      jsCursor(message.sourceLocation),
    );
  }

  @override
  Future<void> close() async {}
}

/// Creates the facade's view of the bridge.
JSObject createApiBridge() => createJSInteropWrapper<ApiBridge>(ApiBridge());
