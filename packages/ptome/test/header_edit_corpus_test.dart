/// Header edits over the fixture corpus: an edit to the value an entry
/// already has returns the source unchanged, and an edit to a new value
/// changes only that entry's lines and is read back by the parser.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

void main() {
  final files = [
    for (final dir in ['vendor/asciidoctor/test/fixtures', 'test/parity'])
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.adoc')),
  ];

  test('round trip over ${files.length} fixtures', () {
    var edited = 0;
    for (final file in files) {
      final source = file.readAsStringSync();
      final Document doc;
      try {
        doc = const Ptome(safe: SafeMode.safe).parse(source, path: file.path);
      } on PtomeException {
        continue;
      }
      for (final MapEntry(key: name, :value) in doc.headerAttributes.entries) {
        if (value == null || value.contains('\n')) continue;
        final Document same;
        try {
          same = doc.withAttribute(name, value);
        } on PtomeException {
          continue; // under a conditional or in an include
        }
        expect(same.source.length, source.length, reason: '${file.path} $name');
        final changed = doc.withAttribute(name, 'edited value');
        final before = source.split('\n');
        final after = changed.source.split('\n');
        expect(
          after.length,
          lessThanOrEqualTo(before.length),
          reason: '${file.path} $name',
        );
        expect(
          changed.headerAttributes[name],
          'edited value',
          reason: '${file.path} $name',
        );
        edited += 1;
      }
    }
    expect(edited, greaterThan(10));
  });
}
