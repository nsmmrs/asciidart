/// The entry point of the npm package's compiled bundle.
///
/// Running the bundle installs the bridge the JavaScript facade calls into
/// as `globalThis.asciidoctorDart`. On Node.js, the package's wrapper first
/// injects the Node.js built-ins as `globalThis.asciidoctorDartHost` (see
/// `io/js.dart`).
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidoctor/src/js/bridge.dart';

/// The real global object (the bundle's own `self` shadows it; see
/// `npm/preamble.js`).
@JS('globalThis')
external JSObject get _global;

void main() {
  _global.setProperty('asciidoctorDart'.toJS, createApiBridge());
}
