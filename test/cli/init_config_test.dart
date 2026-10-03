/// Tests for the `init-config` scaffold and the reusable CLI entrypoint.
///
/// Covers `lib/src/cli/init_config.dart` (file generation, `--force`,
/// misuse diagnostics, constraint freshness vs. this package's pubspec)
/// and `lib/src/cli/run.dart` (the `init-config` dispatch; the
/// conversion path is owned by `invoker_test.dart` and the bats e2e
/// suite). Two subprocess tests prove the scaffold story end to end: the
/// stock binary serves `init-config`, and the generated project analyzes
/// cleanly offline with a path override to this checkout.
library;

import 'dart:io';

import 'package:asciidoctor/src/cli/init_config.dart';
import 'package:asciidoctor/src/cli/run.dart';
import 'package:test/test.dart';

/// Finds this package's root (the directory holding its pubspec).
String findPackageRoot() {
  var dir = Directory.current;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: asciidoctor')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'asciidoctor package root not found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Creates an empty temp directory, deleted after the test.
Directory makeTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Generates the scaffold into a fresh temp directory, asserting success.
Directory generateScaffold([List<String> extraArgs = const <String>[]]) {
  final dir = makeTempDir('init-config-test');
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runInitConfig([dir.path, ...extraArgs], out: out, err: err);
  expect(code, equals(0), reason: 'stderr: $err');
  expect(err.toString(), isEmpty);
  return dir;
}

void main() {
  group('runInitConfig', () {
    test('generates a pubspec, transforms stub, main and README', () {
      final dir = generateScaffold();
      final name = dir.path
          .split(Platform.pathSeparator)
          .last
          .toLowerCase()
          .replaceAll('-', '_');
      final pubspec = File('${dir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: $name'));
      expect(pubspec, contains('asciidoctor: $scaffoldAsciidoctorConstraint'));
      expect(pubspec, contains('sdk: $scaffoldSdkConstraint'));

      final transforms = File('${dir.path}/lib/transforms.dart')
          .readAsStringSync();
      expect(transforms, contains('void registerTransforms'));
      expect(transforms, contains("registerFunction('paragraph'"));

      final main = File('${dir.path}/bin/main.dart').readAsStringSync();
      expect(main, contains("import 'package:asciidoctor/asciidoctor.dart';"));
      expect(main, contains("import 'package:$name/transforms.dart';"));
      expect(main, contains('registerTransforms();'));
      expect(main, contains('await runCli(args);'));

      final readme = File('${dir.path}/README.md').readAsStringSync();
      expect(readme, contains('dart compile exe bin/main.dart'));
    });

    test('sanitizes the project name from the directory basename', () {
      final parent = makeTempDir('init-config-test');
      final target = '${parent.path}/My-Custom.Config';
      final code = runInitConfig(
        [target],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, equals(0));
      final pubspec = File('$target/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: my_custom_config'));
      final main = File('$target/bin/main.dart').readAsStringSync();
      expect(
        main,
        contains("import 'package:my_custom_config/transforms.dart';"),
      );
    });

    test('refuses to overwrite without --force, overwrites with it', () {
      final dir = generateScaffold();
      final err = StringBuffer();
      final code = runInitConfig([dir.path], out: StringBuffer(), err: err);
      expect(code, equals(1));
      expect(err.toString(), contains('refusing to overwrite'));
      expect(err.toString(), contains('--force'));

      final forced = runInitConfig(
        [dir.path, '--force'],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(forced, equals(0));
      expect(File('${dir.path}/bin/main.dart').existsSync(), isTrue);
    });

    test('reports misuse and answers --help', () {
      var err = StringBuffer();
      expect(
        runInitConfig(['--bogus'], out: StringBuffer(), err: err),
        equals(1),
      );
      expect(err.toString(), contains('unknown option'));

      err = StringBuffer();
      expect(
        runInitConfig(['a', 'b'], out: StringBuffer(), err: err),
        equals(1),
      );
      expect(err.toString(), contains('at most one directory'));

      final out = StringBuffer();
      expect(
        runInitConfig(['--help'], out: out, err: StringBuffer()),
        equals(0),
      );
      expect(out.toString(), contains('Usage: asciidoctor init-config'));
    });

    test('scaffold constraints match this package', () {
      // The generated pubspec must track releases: the asciidoctor
      // constraint matches this package's version and the SDK constraint
      // matches its own.
      final pubspec = File('${findPackageRoot()}/pubspec.yaml')
          .readAsStringSync();
      final version = RegExp(
        r'^version: (\S+)$',
        multiLine: true,
      ).firstMatch(pubspec)![1]!;
      expect(scaffoldAsciidoctorConstraint, equals('^$version'));
      final sdk = RegExp(
        r'^\s+sdk: (\S+)$',
        multiLine: true,
      ).firstMatch(pubspec)![1]!;
      expect(scaffoldSdkConstraint, equals(sdk));
    });
  });

  group('runCliCode', () {
    test(
      'dispatches init-config and reports --version without converting',
      () async {
        final dir = makeTempDir('init-config-test');
        final code = await runCliCode(
          ['init-config', dir.path],
          out: StringBuffer(),
          err: StringBuffer(),
        );
        expect(code, equals(0));
        expect(File('${dir.path}/pubspec.yaml').existsSync(), isTrue);

        final out = StringBuffer();
        final versionCode = await runCliCode(
          ['--version'],
          out: out,
          err: StringBuffer(),
        );
        expect(versionCode, equals(0));
        expect(out.toString(), contains('Asciidoctor'));
      },
    );

    test('returns 1 and reports uncaught errors', () async {
      // `--require` under `--trace` rethrows (an unloadable library),
      // exercising the uncaught-exception path: message plus backtrace
      // on the error sink, exit 1.
      final dir = makeTempDir('init-config-test');
      final input = File('${dir.path}/input.adoc')..writeAsStringSync('hi\n');
      final err = StringBuffer();
      final code = await runCliCode(
        ['--trace', '--require', 'definitely-not-a-library', input.path],
        out: StringBuffer(),
        err: err,
      );
      expect(code, equals(1));
      expect(err.toString(), contains('definitely-not-a-library'));
    });
  });

  group('scaffold end to end (subprocess)', () {
    test(
      'the stock binary serves init-config into the current directory',
      () async {
        final dir = makeTempDir('init-config-test');
        final result = await Process.run('dart', [
          'run',
          '${findPackageRoot()}/bin/asciidoctor.dart',
          'init-config',
        ], workingDirectory: dir.path);
        expect(
          result.exitCode,
          equals(0),
          reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
        expect(File('${dir.path}/pubspec.yaml').existsSync(), isTrue);
        expect(File('${dir.path}/lib/transforms.dart').existsSync(), isTrue);
        expect(File('${dir.path}/bin/main.dart').existsSync(), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'the scaffold analyzes cleanly offline with a path override',
      () async {
        final dir = generateScaffold();
        final pubspec = File('${dir.path}/pubspec.yaml');
        pubspec.writeAsStringSync(
          '${pubspec.readAsStringSync()}\n'
          'dependency_overrides:\n'
          '  asciidoctor:\n'
          '    path: ${findPackageRoot()}\n',
        );
        final pubGet = await Process.run('dart', [
          'pub',
          'get',
          '--offline',
        ], workingDirectory: dir.path);
        expect(
          pubGet.exitCode,
          equals(0),
          reason: 'pub get failed:\n${pubGet.stdout}\n${pubGet.stderr}',
        );
        final analyze = await Process.run('dart', [
          'analyze',
        ], workingDirectory: dir.path);
        expect(
          analyze.exitCode,
          equals(0),
          reason: 'analyze failed:\n${analyze.stdout}\n${analyze.stderr}',
        );
        expect(analyze.stdout as String, contains('No issues found!'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
