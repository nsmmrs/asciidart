/// Node.js runtime detection for the JS build.
///
/// JS side of the [isRunningOnNode] platform seam (see
/// `template_loader.dart`), selected by the `dart.library.io` conditional
/// import. Uses only `dart:js_interop` (never `dart:io`), so this file
/// compiles for both JS runtimes.
library;

import 'dart:js_interop';

/// The Node.js `process` global, or `null` when absent.
///
/// A missing global reads as `undefined`, which surfaces as `null`
/// through the nullable static type — no `ReferenceError` is possible.
@JS('process')
external JSObject? get _nodeProcess;

/// Static view of the `process` global's `versions` member.
extension type _NodeProcess(JSObject _) implements JSObject {
  /// The `versions` member (`process.versions`), or `null` when absent.
  external JSObject? get versions;
}

/// Static view of the `process.versions` member's `node` entry.
extension type _NodeVersions(JSObject _) implements JSObject {
  /// The Node.js version string, or `null` when absent.
  external JSString? get node;
}

/// Whether the current runtime is Node.js.
///
/// Defensive port of `typeof process?.versions?.node === 'string'`: each
/// hop is null-checked before descending, so browsers (no `process`
/// global) and shims (missing `versions`/`node`) all read `false`.
bool isRunningOnNode() {
  final process = _nodeProcess;
  if (process == null) return false;
  final versions = _NodeProcess(process).versions;
  if (versions == null) return false;
  return _NodeVersions(versions).node != null;
}
