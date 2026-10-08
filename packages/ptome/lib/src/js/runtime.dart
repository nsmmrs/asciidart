/// The runtime of the JavaScript projection (`api.g.dart`): one JavaScript
/// object per Dart object, conversions, callbacks and errors.
///
/// The npm package's `npm/src/core.js` calls [initRuntime] with the helpers
/// only JavaScript can provide (creating an instance of a projected class,
/// throwing a value as is, calling a function so that its errors survive
/// the trip through Dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ptome/ptome.dart' show PtomeException;
import 'package:ptome/src/cli/diagnostics.dart' show describe;

/// The helpers `npm/src/core.js` provides.
extension type Helpers._(JSObject _) implements JSObject {
  /// A new instance of the projected class [kind] standing for [box] (a
  /// boxed Dart object), without running its constructor.
  external JSObject create(JSString kind, JSBoxedDartObject box);

  /// The boxed Dart object [value] stands for, if it is a projected object.
  external JSBoxedDartObject? boxOf(JSAny? value);

  /// The symbol of the error a carrier error carries.
  external JSSymbol get carried;

  /// `Symbol.asyncIterator`.
  external JSSymbol get asyncIterator;

  /// Throws [error] as is.
  external void throwRaw(JSAny? error);

  /// Calls [f] with [args]; an error it throws comes back wrapped in a
  /// carrier error, which Dart code does not alter.
  external JSAny? invoke(JSFunction f, JSArray<JSAny?> args);

  /// Calls the method [name] of [target], as [invoke].
  external JSAny? invokeMethod(
    JSObject target,
    JSString name,
    JSArray<JSAny?> args,
  );

  /// A JavaScript error of the projected exception class [name].
  external JSObject error(JSString name, JSString message);

  /// A carrier error for [error], which Dart code does not alter.
  external JSObject carry(JSAny? error);
}

late Helpers _helpers;

/// Installs the [helpers] from `npm/src/core.js`.
void initRuntime(JSObject helpers) => _helpers = helpers as Helpers;

final Expando<JSObject> _handles = Expando('ptome JavaScript objects');

/// The JavaScript object for [o], an instance of the projected class
/// [kind]: the same object every time.
JSObject handle(Object o, String kind) =>
    _handles[o] ??= _helpers.create(kind.toJS, o.toJSBox);

/// The Dart object of type [T] behind [value], if it is a projected object
/// standing for one.
T? tryUnwrap<T extends Object>(JSAny? value) =>
    switch (_helpers.boxOf(value)?.toDart) {
      final T dart => dart,
      _ => null,
    };

/// The Dart object of type [T] behind [value]; a [TypeError] for anything
/// else.
T unwrap<T extends Object>(JSAny? value) =>
    tryUnwrap<T>(value) ??
    _throwTypeError('expected a $T, got ${_describeJs(value)}');

/// Whether [value] is `undefined` or `null`.
bool isMissing(JSAny? value) => value == null || value.isUndefinedOrNull;

/// [value] as a string.
String str(JSAny? value) {
  if (value.isA<JSString>()) return (value! as JSString).toDart;
  _throwTypeError('expected a string, got ${_describeJs(value)}');
}

/// [value] as an integer.
int integer(JSAny? value) {
  if (value.isA<JSNumber>()) return (value! as JSNumber).toDartInt;
  _throwTypeError('expected an integer, got ${_describeJs(value)}');
}

/// [value] as a number.
num number(JSAny? value) {
  if (value.isA<JSNumber>()) return (value! as JSNumber).toDartDouble;
  _throwTypeError('expected a number, got ${_describeJs(value)}');
}

/// [value] as a boolean.
bool boolean(JSAny? value) {
  if (value.isA<JSBoolean>()) return (value! as JSBoolean).toDart;
  _throwTypeError('expected a boolean, got ${_describeJs(value)}');
}

/// [value] as a function.
JSFunction fn(JSAny? value) {
  if (value.isA<JSFunction>()) return value! as JSFunction;
  _throwTypeError('expected a function, got ${_describeJs(value)}');
}

/// The elements of the array [value] (an iterable is accepted too).
List<JSAny?> list(JSAny? value) {
  if (value.isA<JSArray>()) return (value! as JSArray<JSAny?>).toDart;
  _throwTypeError('expected an array, got ${_describeJs(value)}');
}

/// The bytes [value] holds: a `Uint8Array` (or another typed array, an
/// `ArrayBuffer`, an array of numbers).
Uint8List bytes(JSAny? value) {
  if (value.isA<JSUint8Array>()) return (value! as JSUint8Array).toDart;
  if (value.isA<JSArrayBuffer>()) {
    return (value! as JSArrayBuffer).toDart.asUint8List();
  }
  if (value.isA<JSArray>()) {
    return Uint8List.fromList([for (final x in list(value)) integer(x)]);
  }
  _throwTypeError('expected a Uint8Array, got ${_describeJs(value)}');
}

/// [bytes] as a `Uint8Array`.
JSUint8Array jsBytes(List<int> bytes) =>
    (bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toJS;

@JS('Object.keys')
external JSArray<JSString> _keys(JSObject o);

/// The properties of the plain object [value].
Iterable<MapEntry<String, JSAny?>> entries(JSAny? value) {
  if (!value.isA<JSObject>()) {
    _throwTypeError('expected an object, got ${_describeJs(value)}');
  }
  final o = value! as JSObject;
  return [
    for (final key in _keys(o).toDart)
      MapEntry(key.toDart, o.getProperty<JSAny?>(key)),
  ];
}

/// A new JavaScript array of [values] (never a Dart list, whose JavaScript
/// form carries type information that tools such as `util.inspect` walk).
JSArray<JSAny?> jsArray(Iterable<JSAny?> values) {
  final array = JSArray<JSAny?>();
  for (final v in values) {
    array.callMethod<JSAny?>('push'.toJS, v);
  }
  return array;
}

/// A new plain object with [properties].
JSObject jsObject(Map<String, JSAny?> properties) {
  final o = JSObject();
  for (final MapEntry(:key, :value) in properties.entries) {
    o.setProperty(key.toJS, value);
  }
  return o;
}

/// Whether the options object [options] has the property [name].
bool hasOption(JSAny? options, String name) =>
    !isMissing(options) &&
    !(options! as JSObject).getProperty<JSAny?>(name.toJS).isUndefined;

/// The property [name] of the options object [options], if present.
JSAny? option(JSAny? options, String name) => isMissing(options)
    ? null
    : (options! as JSObject).getProperty<JSAny?>(name.toJS);

/// Calls the JavaScript function [f] with [args].
JSAny? invoke(JSFunction f, List<JSAny?> args) =>
    _helpers.invoke(f, jsArray(args));

/// Calls the method [name] of the JavaScript object [target] with [args].
JSAny? invokeMethod(JSObject target, String name, List<JSAny?> args) =>
    _helpers.invokeMethod(target, name.toJS, jsArray(args));

/// A promise for [future]'s value, converted with [convert].
JSPromise<JSAny?> promise<T>(Future<T> future, JSAny? Function(T) convert) =>
    JSPromise<JSAny?>(
      (JSFunction resolve, JSFunction reject) {
        unawaited(
          future.then(
            (value) => resolve.callAsFunction(null, convert(value)),
            onError: (Object error, StackTrace stack) =>
                reject.callAsFunction(null, _jsErrorFor(error, stack)),
          ),
        );
      }.toJS,
    );

/// [value] (a value or a promise for one), converted with [convert].
FutureOr<T> futureOr<T>(JSAny? value, T Function(JSAny?) convert) {
  if (value.isA<JSPromise>()) {
    return (value! as JSPromise<JSAny?>).toDart.then(convert);
  }
  return convert(value);
}

/// [value] (a value, or a future for one) as JavaScript: a promise for a
/// future, else the converted value.
JSAny? jsFutureOr<T>(FutureOr<T> value, JSAny? Function(T) convert) =>
    value is Future<T> ? promise(value, convert) : convert(value);

/// An async iterable over [stream]'s values, converted with [convert].
JSObject asyncIterable<T>(Stream<T> stream, JSAny? Function(T) convert) {
  final iterator = StreamIterator(stream);
  final jsIterator = JSObject()
    ..setProperty(
      'next'.toJS,
      () {
        return promise(
          iterator.moveNext(),
          (hasNext) => JSObject()
            ..setProperty('done'.toJS, (!hasNext).toJS)
            ..setProperty(
              'value'.toJS,
              hasNext ? convert(iterator.current) : null,
            ),
        );
      }.toJS,
    )
    ..setProperty(
      'return'.toJS,
      () {
        return promise(
          iterator.cancel(),
          (_) => JSObject()..setProperty('done'.toJS, true.toJS),
        );
      }.toJS,
    );
  return JSObject()
    ..setProperty(_helpers.asyncIterator, (() => jsIterator).toJS);
}

/// Throws [error], caught at the boundary of a call from JavaScript, as a
/// JavaScript error (an error thrown by JavaScript code, as it was).
Never fail(Object error, StackTrace stack) {
  _helpers.throwRaw(_jsErrorFor(error, stack));
  throw StateError('unreachable');
}

JSAny _jsErrorFor(Object error, StackTrace stack) {
  // An error thrown by a JavaScript callback, carried through Dart: the
  // original error. This library only compiles with dart2js, which leaves
  // JavaScript objects as they are.
  // ignore: invalid_runtime_check_with_js_interop_types
  if (error is JSObject) {
    final carried = error.getProperty<JSAny?>(_helpers.carried);
    return carried.isUndefined ? error : carried!;
  }
  if (error is PtomeException) {
    return _helpers.error('PtomeException'.toJS, error.message.toJS);
  }
  return _helpers.error(
    (error is TypeError ? 'TypeError' : 'Error').toJS,
    describe(error).toJS,
  )..setProperty('dartStack'.toJS, '$stack'.toJS);
}

Never _throwTypeError(String message) {
  // Carried, so that the boundary hands it to JavaScript unaltered.
  _helpers.throwRaw(
    _helpers.carry(_helpers.error('TypeError'.toJS, message.toJS)),
  );
  throw StateError('unreachable');
}

String _describeJs(JSAny? value) {
  if (value == null || value.isUndefined) return 'undefined';
  if (value.isNull) return 'null';
  return value.typeofEquals('object') ? 'an object' : value.typeofString();
}

extension on JSAny {
  String typeofString() => typeofEquals('string')
      ? 'a string'
      : typeofEquals('number')
      ? 'a number'
      : typeofEquals('boolean')
      ? 'a boolean'
      : typeofEquals('function')
      ? 'a function'
      : 'a value';
}
