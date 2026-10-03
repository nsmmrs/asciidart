import 'dart:io';

import 'package:asciidoctor/asciidoctor.dart';
import 'package:test/test.dart';

/// `dart test` runs with the package root as the working directory, while
/// [Platform.script] points at a temp kernel file, so resolve the CLI
/// entry point against the current directory.
String get _cliScript =>
    '${Directory.current.path}${Platform.pathSeparator}bin'
    '${Platform.pathSeparator}asciidoctor.dart';

void main() {
  test('version constant matches pubspec', () {
    expect(Asciidoctor.version, equals('0.1.0'));
  });

  test('CLI --version exits 0 and prints version', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      _cliScript,
      '--version',
    ]);
    expect(result.exitCode, equals(0));
    expect(result.stdout as String, contains(Asciidoctor.version));
  });

  test('CLI --help exits 0', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      _cliScript,
      '--help',
    ]);
    expect(result.exitCode, equals(0));
    expect(result.stdout as String, contains('Usage:'));
  });
}
