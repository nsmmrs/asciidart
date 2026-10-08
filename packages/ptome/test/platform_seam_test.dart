/// Guards the I/O seam (`lib/src/io.dart`) that lets the library compile
/// to JavaScript.
///
/// dart2js accepts imports of `dart:io` and `dart:isolate` and fails only
/// at run time, so this test keeps them confined to the VM side of the
/// seam, and `dart:js_interop` to its JavaScript side.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Files (or directories, ending in `/`) allowed to import each platform
/// library.
const Map<String, Set<String>> allowedImports = {
  'dart:io': {'lib/src/io/vm.dart'},
  'dart:isolate': {'lib/src/parallel/pool_isolate.dart'},
  'dart:js_interop': {'lib/src/io/js.dart', 'lib/src/js/'},
  'dart:js_interop_unsafe': {'lib/src/io/js.dart', 'lib/src/js/'},
};

/// Whether [path] is covered by one of the [allowed] files or directories.
bool isAllowed(Set<String> allowed, String path) => allowed.any(
  (entry) => entry.endsWith('/') ? path.startsWith(entry) : path == entry,
);

void main() {
  test('platform libraries are imported only behind the seam', () {
    final violations = <String>[];
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final importRx = RegExp("^import '(dart:[a-z_]+)'", multiLine: true);
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      for (final match in importRx.allMatches(file.readAsStringSync())) {
        final library = match[1]!;
        final allowed = allowedImports[library];
        if (allowed != null && !isAllowed(allowed, path)) {
          violations.add('$path imports $library');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
