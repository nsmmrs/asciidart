/// Node.js runtime detection fallback for native targets.
///
/// VM/stub side of the [isRunningOnNode] platform seam (see
/// `template_loader.dart`): native targets have no `process.versions.node`,
/// so detection is a constant `false` with no `dart:js_interop` import.
library;

/// Whether the current runtime is Node.js. Always `false` on the Dart VM
/// and AOT targets.
bool isRunningOnNode() => false;
