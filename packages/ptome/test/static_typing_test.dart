/// Guards the end-to-end static typing of the package.
///
/// The analyzer already runs with `strict-casts`, `strict-inference` and
/// `strict-raw-types`, which catch implicit `dynamic`. These checks catch
/// what the analyzer allows: the explicit `dynamic` type anywhere in the
/// sources, and `Object?` in the library outside the few places where an
/// untyped value is the contract (the Mustache template context, `Map` and
/// `StringSink` overrides).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Library files allowed to mention `Object?`, with the reason.
const Map<String, String> objectBoundaries = {
  // Mustache renders untyped maps; the context builder is the one place
  // where typed nodes become template values.
  'lib/src/template_context.dart': 'Mustache template context',
  'lib/src/template.dart': 'Mustache render input',
  // `Map.operator []` and `Map.remove` take `Object?` keys.
  'lib/src/parser.dart': 'Map overrides on BlockAttributes',
  // JSON is untyped; the page map is the one JSON file the library reads.
  'lib/src/page_map.dart': 'JSON decode',
  // The I/O seam's `StringSink` implementations take `Object?` writes.
  'lib/src/io/vm.dart': 'StringSink implementation',
  'lib/src/io/js.dart': 'StringSink implementations',
};

/// The Dart sources under [roots], as paths relative to the package root.
List<String> dartSources(List<String> roots) => [
  for (final root in roots)
    if (Directory(root).existsSync())
      for (final entity in Directory(root).listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart'))
          entity.path.replaceAll(r'\', '/'),
]..sort();

/// [source] with comments and string literal contents blanked out, so
/// that only code is searched.
String codeOnly(String source) => source
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
    .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

/// The `line: text` locations in [path] whose code matches [pattern].
List<String> findings(String path, RegExp pattern) {
  final lines = File(path).readAsLinesSync();
  return [
    for (var i = 0; i < lines.length; i++)
      if (pattern.hasMatch(codeOnly(lines[i])))
        '$path:${i + 1}: ${lines[i].trim()}',
  ];
}

void main() {
  test('no source uses the dynamic type', () {
    final dynamicRx = RegExp(r'\bdynamic\b');
    final hits = [
      for (final path in dartSources([
        'lib',
        'bin',
        'tool',
        'test',
        'benchmark',
      ]))
        ...findings(path, dynamicRx),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the library uses Object? only at documented boundaries', () {
    final objectRx = RegExp(r'\bObject\?');
    final hits = [
      for (final path in dartSources(['lib']))
        if (!objectBoundaries.containsKey(path)) ...findings(path, objectRx),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the analyzer runs with strict type checks', () {
    final options = File('analysis_options.yaml').readAsStringSync();
    for (final check in [
      'strict-casts',
      'strict-inference',
      'strict-raw-types',
    ]) {
      expect(options, contains('$check: true'));
    }
  });
}
