// The PDF converter without the default themes' fonts: built-in PDF fonts
// stand in for them and icons are shown as text, each said once.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(registerPdf);
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('missing_fonts_test.');
    // No fonts at all.
    Fonts.installed = FontIndex([
      '${dir.path}/fonts',
    ], cacheFile: '${dir.path}/cache.tsv');
  });
  tearDown(() {
    Fonts.installed = null;
    dir.deleteSync(recursive: true);
  });

  List<String> convert(String source) {
    File('${dir.path}/doc.adoc').writeAsStringSync(source);
    final logger = MemoryLogger();
    convertFile(
      '${dir.path}/doc.adoc',
      AsciidoctorOptions(
        safe: SafeMode.unsafe,
        backend: 'pdf',
        toFile: '${dir.path}/doc.pdf',
        attributes: const {'pdf-theme': 'default'},
        logger: logger,
      ),
    );
    expect(File('${dir.path}/doc.pdf').existsSync(), isTrue);
    return [
      for (final m in logger.messages)
        if (m.severity == Severity.warn) '${m.message}',
    ];
  }

  test('built-in fonts stand in for the theme fonts, said once', () {
    final messages = convert(
      '= Doc\n\nPlain, *bold*, _italic_ and `code`.\n\nMore `code`.\n',
    );
    expect(
      messages,
      containsAll([
        contains('font family Noto Serif is not installed: using Times-Roman'),
        contains('using Times-Bold for Noto Serif (bold)'),
        contains('font family M+ 1mn is not installed: using Courier'),
      ]),
    );
    expect(
      messages.where((m) => m.contains('Courier for M+ 1mn')),
      hasLength(1),
    );
    expect(messages, everyElement(contains('ptome doctor')));
  });

  test(
    'icons are shown as their text when their font is missing',
    () {
      final messages = convert(
        '= Doc\n:icons: font\n\nicon:heart[2x] and icon:heart[] again\n\n'
        'NOTE: A note.\n',
      );
      expect(
        messages.where((m) => m.contains('the fas icon font is not installed')),
        hasLength(1),
      );
      final text =
          Process.runSync('pdftotext', ['${dir.path}/doc.pdf', '-']).stdout
              as String;
      expect(text, contains('[heart] and [heart] again'));
      expect(text, contains('NOTE'));
    },
    skip: Process.runSync('which', ['pdftotext']).exitCode == 0
        ? false
        : 'needs pdftotext',
  );
}
