@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/cli/compat_config.dart';
import 'package:asciidart/src/cli/options.dart';
import 'package:asciidart/src/compat.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('compat'));
  tearDown(() => root.deleteSync(recursive: true));

  group('parseCompat', () {
    test('true, an empty value or all: every format', () {
      for (final value in ['true', '', 'all', ' TRUE ']) {
        expect(parseCompat(value), CompatFormat.values.toSet(), reason: value);
      }
    });

    test('false or none: no format', () {
      expect(parseCompat('false'), isEmpty);
      expect(parseCompat('none'), isEmpty);
    });

    test('a list of formats, by format or backend name', () {
      expect(parseCompat('html, pdf'), {CompatFormat.html, CompatFormat.pdf});
      expect(parseCompat('xhtml5,multipage_html5'), {CompatFormat.html});
      expect(parseCompat('epub3,docbook5,manpage'), {
        CompatFormat.epub,
        CompatFormat.docbook,
        CompatFormat.manpage,
      });
    });

    test('unknown names are reported and skipped', () {
      final unknown = <String>[];
      expect(parseCompat('pdf,odt', onUnknown: unknown.add), {
        CompatFormat.pdf,
      });
      expect(unknown, ['odt']);
    });
  });

  group('resolveCompat', () {
    late Directory project;
    late Directory nested;
    late Directory config;
    final warnings = <String>[];
    setUp(() {
      warnings.clear();
      project = Directory('${root.path}/project')..createSync();
      nested = Directory('${project.path}/doc/chapters')
        ..createSync(recursive: true);
      config = Directory('${root.path}/config/asciidart')
        ..createSync(recursive: true);
    });
    String? resolve([Map<String, String> env = const {}]) => resolveCompat(
      env: {'XDG_CONFIG_HOME': '${root.path}/config', ...env},
      startDir: nested.path,
      warn: warnings.add,
    );

    test('nothing set: null', () => expect(resolve(), isNull));

    test('the nearest asciidart.yml above the input', () {
      File('${project.path}/asciidart.yml').writeAsStringSync('compat: pdf\n');
      expect(resolve(), 'pdf');
      File('${project.path}/doc/asciidart.yml')
          .writeAsStringSync('compat: [html, epub]\n');
      expect(resolve(), 'html,epub');
    });

    test('true and false as YAML booleans', () {
      File('${project.path}/asciidart.yml').writeAsStringSync('compat: true\n');
      expect(resolve(), 'true');
      File('${project.path}/asciidart.yml')
          .writeAsStringSync('compat: false\n');
      expect(resolve(), 'false');
    });

    test('the user configuration when the project sets none', () {
      File('${config.path}/config.yml').writeAsStringSync('compat: html\n');
      expect(resolve(), 'html');
      File('${project.path}/asciidart.yml').writeAsStringSync('# no compat\n');
      expect(resolve(), 'html');
      File('${project.path}/asciidart.yml').writeAsStringSync('compat: pdf\n');
      expect(resolve(), 'pdf');
    });

    test('ASCIIDART_COMPAT first', () {
      File('${project.path}/asciidart.yml').writeAsStringSync('compat: pdf\n');
      expect(resolve({'ASCIIDART_COMPAT': 'epub'}), 'epub');
    });

    test('a file that is not a configuration is reported', () {
      File('${project.path}/asciidart.yml').writeAsStringSync('- one\n');
      expect(resolve(), isNull);
      expect(warnings.single, contains('not a configuration file'));
      File('${project.path}/asciidart.yml')
          .writeAsStringSync('compat: {pdf: yes}\n');
      expect(resolve(), isNull);
      expect(warnings.last, contains('compat: expected true, false'));
    });
  });

  group('the CLI', () {
    late File input;
    setUp(() {
      input = File('${root.path}/doc.adoc')..writeAsStringSync('= Doc\n');
    });
    Map<String, String>? attributes(
      List<String> args, [
      Map<String, String> env = const {},
    ]) {
      final (:options, :exitCode) = CliOptions.parseArgs(
        [...args, input.path],
        out: StringBuffer(),
        err: StringBuffer(),
        environment: {'XDG_CONFIG_HOME': '${root.path}/none', ...env},
      );
      expect(exitCode, isNull);
      return options.attributes;
    }

    test('sets the configured value as a default the document overrides', () {
      expect(attributes(const [], {'ASCIIDART_COMPAT': 'pdf'}), {
        'asciidoctor-compat': 'pdf@',
      });
      File('${root.path}/asciidart.yml').writeAsStringSync('compat: true\n');
      expect(attributes(const []), {'asciidoctor-compat': 'true@'});
    });

    test('-a asciidoctor-compat wins, set or unset', () {
      const env = {'ASCIIDART_COMPAT': 'pdf'};
      expect(attributes(['-a', 'asciidoctor-compat=html'], env), {
        'asciidoctor-compat': 'html',
      });
      expect(attributes(['-a', 'asciidoctor-compat!'], env), {
        'asciidoctor-compat!': '',
      });
    });

    test('nothing configured: no attribute', () {
      expect(attributes(const []), isNull);
    });
  });
}
