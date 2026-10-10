// `ptome doctor`, offline: the fonts looked up in folders of the test's
// choosing, downloads answered by a fake that serves the fonts vendored
// with asciidoctor-pdf.
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:ptome/src/cli/doctor.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/remote.dart';
import 'package:test/test.dart';

import '../vendored_fonts.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('doctor_test.'));
  tearDown(() => tmp.deleteSync(recursive: true));

  FontIndex index(List<String> dirs) =>
      FontIndex(dirs, cacheFile: '${tmp.path}/cache.tsv');

  Future<(int, String, String)> doctor(
    List<String> args, {
    List<String> fonts = const [],
    bool interactive = false,
    String answer = '',
    Future<RemoteResource> Function(Uri uri)? fetch,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runDoctor(
      args,
      out: out,
      err: err,
      index: () => index(fonts),
      installDirectory: '${tmp.path}/installed',
      fetch: fetch ?? (uri) => throw StateError('no download expected: $uri'),
      interactive: interactive,
      readLine: () => answer,
    );
    return (code, '$out', '$err');
  }

  test('finds the vendored fonts: everything is installed', () async {
    final (code, out, _) = await doctor([
      '--check',
    ], fonts: vendoredFontDirectories);
    expect(code, 0);
    expect(out, contains('Every font is installed.'));
    expect(out, contains('M+ 1mn'));
    expect(out, isNot(contains('missing')));
  });

  test('--check reports what is missing, with status 1', () async {
    final (code, out, _) = await doctor(
      ['--check'],
      fonts: ['vendor/asciidoctor-pdf/icons'],
    );
    expect(code, 1);
    expect(out, matches(RegExp('Noto Serif +missing')));
    expect(out, matches(RegExp('PaymentFont +installed')));
    expect(out, contains('6 of 11 fonts are missing'));
  });

  test('without a terminal or --yes, says how to install', () async {
    final (code, out, _) = await doctor([]);
    expect(code, 1);
    expect(out, contains('Noto Serif from Google Fonts'));
    expect(out, contains('Font Awesome Free 5.15.1'));
    expect(out, contains('Run `ptome doctor --yes` to install them.'));
    expect(Directory('${tmp.path}/installed').existsSync(), isFalse);
  });

  test('asks, and installs nothing when the answer is no', () async {
    final (code, out, _) = await doctor([], interactive: true, answer: 'n');
    expect(code, 1);
    expect(out, contains('Download and install them? [y/N] '));
    expect(out, contains('Nothing installed.'));
  });

  test('installs what checks out, and reports what does not', () async {
    // Google Fonts' list for any family names files at fake URLs; a font
    // file is a vendored font of that family when there is one (else Noto
    // Serif's); the pinned files are the vendored icon fonts, of which
    // only Foundation Icons and PaymentFont are the very files pinned.
    List<int> vendored(String path) => File(path).readAsBytesSync();
    Future<RemoteResource> fetch(Uri uri) async {
      List<int> body;
      if (uri.host == 'fonts.google.com') {
        final family = uri.queryParameters['family']!;
        final manifest = {
          'manifest': {
            'files': [
              {'filename': 'OFL.txt', 'contents': 'License of $family'},
            ],
            'fileRefs': [
              for (final name in _googleFiles)
                {'filename': name, 'url': 'https://gstatic.test/$family/$name'},
            ],
          },
        };
        body = utf8.encode(")]}'\n${jsonEncode(manifest)}");
      } else if (uri.host == 'gstatic.test') {
        final family = uri.pathSegments.first;
        final file = uri.pathSegments.last;
        body = vendored(switch (family) {
          'Noto Serif' =>
            'vendor/asciidoctor-pdf/data/fonts/notoserif-${switch (file) {
              'NotoSerif-Bold.ttf' => 'bold',
              'NotoSerif-Italic.ttf' => 'italic',
              'NotoSerif-BoldItalic.ttf' => 'bold_italic',
              _ => 'regular',
            }}-subset.ttf',
          'Noto Emoji' =>
            'vendor/asciidoctor-pdf/data/fonts/notoemoji-subset.ttf',
          'Noto Sans Math' => 'data/pdf-fonts/notosansmath-regular.ttf',
          _ => 'vendor/asciidoctor-pdf/data/fonts/notoserif-regular-subset.ttf',
        });
      } else {
        final name = uri.pathSegments.last;
        body = switch (name) {
          'foundation-icons.ttf' => vendored(
            'vendor/asciidoctor-pdf/icons/fi/foundation-icons.ttf',
          ),
          'paymentfont-webfont.ttf' => vendored(
            'vendor/asciidoctor-pdf/icons/pf/paymentfont-webfont.ttf',
          ),
          _ => vendored('vendor/asciidoctor-pdf/icons/fas/fa-solid.ttf'),
        };
      }
      return (body: body, contentType: null);
    }

    final (code, out, err) = await doctor(['--yes'], fetch: fetch);
    expect(code, 1);
    final installed = Directory('${tmp.path}/installed')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(
      installed,
      containsAll([
        'NotoSerif-Regular.ttf',
        'NotoSerif-BoldItalic.ttf',
        'NotoSerif-OFL.txt',
        'NotoEmoji-Regular.ttf',
        'NotoSansMath-Regular.ttf',
      ]),
    );
    expect(
      File('${tmp.path}/installed/NotoSerif-OFL.txt').readAsStringSync(),
      'License of Noto Serif',
    );
    // A file that isn't the family asked for, a file that isn't the one
    // pinned: not installed.
    expect(installed, isNot(contains('MPLUS1Code-Regular.ttf')));
    expect(installed, isNot(contains('fa-solid-900.ttf')));
    expect(err, contains('is not a font of M PLUS 1 Code (Noto Serif)'));
    expect(err, contains('its SHA-256 differs'));
    expect(out, contains('installed Noto Serif'));
    expect(out, contains('fonts could not be installed'));
  });

  test('--help, and unknown options', () async {
    expect((await doctor(['--help'])).$2, contains('Usage: ptome doctor'));
    final (code, _, err) = await doctor(['--bogus']);
    expect(code, 64);
    expect(err, contains('unknown option --bogus'));
  });
}

/// The files the fake Google Fonts lists for every family.
const List<String> _googleFiles = [
  'static/NotoSerif-Regular.ttf',
  'static/NotoSerif-Bold.ttf',
  'static/NotoSerif-Italic.ttf',
  'static/NotoSerif-BoldItalic.ttf',
  'static/NotoSans-Regular.ttf',
  'static/MPLUS1Code-Regular.ttf',
  'static/NotoEmoji-Regular.ttf',
  'NotoSansMath-Regular.ttf',
  'MPLUS1p-Regular.ttf',
];
