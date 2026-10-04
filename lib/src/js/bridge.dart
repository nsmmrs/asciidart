/// The API the npm package's JavaScript facade calls into (see
/// `entry.dart`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidoctor/src/cli/diagnostics.dart';
import 'package:asciidoctor/src/cli/run.dart';
import 'package:asciidoctor/src/cursor.dart';
import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/js/convert.dart';
import 'package:asciidoctor/src/js/nodes.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
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

/// Reads [object] as a cursor, when it has a `lineno`.
Cursor? cursorOf(JSAny? object) {
  if (object == null || !object.isA<JSObject>()) return null;
  final cursor = object as JSObject;
  final lineno = intOrNull(prop(cursor, 'lineno'));
  if (lineno == null) return null;
  return Cursor(
    stringOrNull(prop(cursor, 'file')),
    stringOrNull(prop(cursor, 'dir')),
    stringOrNull(prop(cursor, 'path')),
    lineno,
  );
}
