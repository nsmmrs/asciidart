@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

/// `dart test` runs with the package root as the working directory, while
/// [Platform.script] points at a temp kernel file, so resolve the CLI
/// entry point against the current directory.
String get _cliScript =>
    '${Directory.current.path}${Platform.pathSeparator}bin'
    '${Platform.pathSeparator}ptome.dart';

void main() {
  test('version reports the matched Asciidoctor release', () {
    expect(Asciidoctor.version, equals('2.1.0.alpha.0'));
  });

  test('package version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(Asciidoctor.packageVersion, equals(version));
  });

  test('documents expose both versions as attributes', () {
    final doc = load('text');
    expect(doc.attr('asciidoctor-version'), equals('2.1.0.alpha.0'));
    expect(doc.attr('ptome-version'), equals(Asciidoctor.packageVersion));
  });

  test('CLI --version exits 0 and prints version', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      _cliScript,
      '--version',
    ]);
    expect(result.exitCode, equals(0));
    expect(
      result.stdout as String,
      startsWith(
        'Ptome ${Asciidoctor.packageVersion} '
        '(compatible with Asciidoctor ${Asciidoctor.version})',
      ),
    );
    expect(result.stdout as String, contains('Runtime Environment (Dart '));
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
