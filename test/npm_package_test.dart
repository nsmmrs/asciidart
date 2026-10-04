/// Checks on the npm package sources (`npm/`).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidoctor/src/version.dart';
import 'package:test/test.dart';

void main() {
  final package = jsonDecode(
    File('npm/package.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the npm package version matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(package['version'], equals(version));
    expect(package['version'], equals(Asciidoctor.packageVersion));
  });

  test('every packaged file exists in the sources or the build', () {
    final files = (package['files']! as List<Object?>).cast<String>();
    const built = {'asciidoctor-dart.js', 'types/'};
    for (final file in files) {
      if (built.contains(file)) continue;
      final path = 'npm/$file';
      expect(
        FileSystemEntity.typeSync(path),
        isNot(FileSystemEntityType.notFound),
        reason: path,
      );
    }
  });
}
