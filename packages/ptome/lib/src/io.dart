/// File system, process and network access for the platform the package
/// runs on: `dart:io` on the Dart VM, the Node.js built-ins (or nothing,
/// in a browser) on JavaScript.
///
/// Library code reaches the platform only through this seam, so the same
/// sources compile to native code and to JavaScript.
library;

export 'io/interface.dart'
    if (dart.library.io) 'io/vm.dart'
    if (dart.library.js_interop) 'io/js.dart';
export 'io/page_files.dart';
export 'io/types.dart';
