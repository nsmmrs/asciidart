// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

final bool _tools = _has('pdftotext');

late Directory _dir;
var _count = 0;

/// [source] converted to PDF (in the compatibility mode with [compat];
/// with the theme [theme], YAML extending the default theme, its fonts
/// in the test fonts), its messages logged to [logger].
String _pdf(
  String source, {
  bool compat = false,
  String? theme,
  LoggerBase? logger,
}) {
  final input = File('${_dir.path}/d${_count++}.adoc')
    ..writeAsStringSync(source);
  final out = '${input.path}.pdf';
  final themeFile = theme == null
      ? null
      : (File('${input.path}-theme.yml')
          ..writeAsStringSync('extends: default\n$theme'));
  convertFile(
    input.path,
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      attributes: {
        if (compat) 'pdf-compat': '',
        if (themeFile != null) ...{
          'pdf-theme': themeFile.path,
          'pdf-fontsdir': '${Directory.current.path}/test/pdf/fixtures/fonts',
        },
      },
      logger: logger,
    ),
  );
  return out;
}

/// The lines of text on each page of [pdf] (the footer's page number
/// left out).
List<List<String>> _pages(String pdf) => [
  for (final page
      in (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
          .split('\f'))
    [
      for (final line in page.split('\n'))
        if (line.trim().isNotEmpty && !RegExp(r'^\d+$').hasMatch(line.trim()))
          line.trim(),
    ],
];

/// The words of [lines], those hyphenated at a line end joined.
List<String> _words(List<String> lines) => lines
    .join('\n')
    .replaceAll(RegExp('[-\u00ad]\n'), '')
    .split(RegExp(r'\s+'));

const _paragraph =
    'Hypermedia is a concept extending the idea of hypertext by allowing '
    'for more complex interactions with the user and the network. The '
    'hypertext transfer protocol, used to transfer hypermedia documents, is '
    'the backbone of the modern web, and its architecture has been '
    'described at length by Roy Fielding in his dissertation, which '
    'introduced the term representational state transfer, or REST.';

void main() {
  setUpAll(() {
    registerPdf();
    _dir = Directory.systemTemp.createTempSync('asciidart-modern.');
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('justified text', () {
    test('breaks where spacing is most even, not line by line', () {
      final greedy = _pages(_pdf(_paragraph, compat: true)).first;
      final optimal = _pages(_pdf(_paragraph)).first;
      // Prawn's wrap leaves "REST." alone on a fifth line; the whole
      // paragraph fits on four.
      expect(greedy, hasLength(5));
      expect(greedy.last, 'REST.');
      expect(optimal, hasLength(4));
      expect(_words(optimal), _words(greedy));
    });

    test('lines stay within the column', () {
      final pdf = _pdf('$_paragraph\n\n$_paragraph $_paragraph');
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      // A4 with the default theme's margins (0.67in on each side).
      const right = 595.28 - 48.24;
      for (final m in RegExp(r'xMax="([\d.]+)"').allMatches(bbox)) {
        expect(double.parse(m[1]!), lessThanOrEqualTo(right + 0.5));
      }
    });
  }, skip: _tools ? false : 'needs poppler');

  test('a paragraph leaves neither a widow nor an orphan', () {
    // A filler paragraph of hard-broken lines pushes an eight-line
    // paragraph down the page a line at a time, across the page break
    // (in the compatibility mode, one of these leaves a line alone at
    // the bottom).
    for (var filler = 38; filler < 48; filler++) {
      final source = [
        for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
        'Filler end.\n\nzz $_paragraph $_paragraph',
      ].join();
      final pages = _pages(_pdf(source));
      if (pages.length < 2) continue;
      bool ofParagraph(String line) =>
          !line.startsWith('Filler') && line.isNotEmpty;
      final before = pages[0].where(ofParagraph).length;
      final after = pages[1].where(ofParagraph).length;
      expect(
        before == 0 || before >= 2,
        isTrue,
        reason: 'filler $filler: $before line(s) at the bottom',
      );
      expect(
        after == 0 || after >= 2,
        isTrue,
        reason: 'filler $filler: $after line(s) at the top',
      );
    }
  }, skip: _tools ? false : 'needs poppler');

  group('hyphenation', () {
    // Long words in a narrow column (a quarter-width table cell),
    // justified.
    String narrow(String header) =>
        '$header\n[cols="1,3"]\n|===\na|[.text-justify]\n'
        '$_paragraph\n| \n|===\n';

    /// Whether a line of [pdf] ends with a hyphen that isn't in the
    /// source (the soft hyphen's glyph, as Prawn draws it).
    bool hyphenated(String pdf) => _pages(pdf).any(
      (page) => page.any(
        (line) => line
            .split(RegExp(r'\s+'))
            .any(
              (word) =>
                  word.endsWith('\u00ad') ||
                  word.endsWith('-') && !_paragraph.contains(word),
            ),
      ),
    );

    test('breaks justified words in the modern engine', () {
      final pdf = _pdf(narrow(''));
      expect(hyphenated(pdf), isTrue);
      // The words are whole again with the hyphens at line ends joined.
      expect(
        _words(_pages(pdf).expand((page) => page).toList()).join(' '),
        contains('representational state transfer'),
      );
    });

    test('leaves code spans whole', () {
      const code =
          '`representational` `characteristically` `internationalization` '
          '`disproportionately` `incomprehensibilities`';
      final pdf = _pdf(
        '[cols="1,3"]\n|===\na|[.text-justify]\n$code $code\n| \n|===\n',
      );
      expect(hyphenated(pdf), isFalse);
    });

    test('is off with hyphens unset', () {
      expect(hyphenated(_pdf(narrow(':hyphens!:\n'))), isFalse);
    });

    test('is asked for in the compatibility mode, as in the gem', () {
      expect(hyphenated(_pdf(narrow(''), compat: true)), isFalse);
      expect(hyphenated(_pdf(narrow(':hyphens:\n'), compat: true)), isTrue);
    });

    test('reports a language without patterns', () {
      final logger = MemoryLogger();
      expect(
        hyphenated(_pdf(narrow(':hyphens: tlh\n'), logger: logger)),
        isFalse,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains('no hyphenation patterns for tlh; not hyphenating'),
      );
    });
  }, skip: _tools ? false : 'needs poppler');

  group(
    'typography',
    () {
      // Yrsa, which has standard ligatures (fi) and GPOS kerning.
      const yrsa = '''
font:
  catalog:
    Yrsa:
      normal: yrsa-regular-latin.ttf
      italic: yrsa-italic-latin.ttf
      bold: yrsa-regular-latin.ttf
      bold_italic: yrsa-italic-latin.ttf
base:
  font-family: Yrsa
''';

      /// The glyphs the pages of [pdf] show (2 bytes each in a CID font).
      int glyphs(String pdf) {
        final qdf =
            Process.runSync('qpdf', [
                  '--qdf',
                  '--object-streams=disable',
                  pdf,
                  '-',
                ], stdoutEncoding: latin1).stdout
                as String;
        var count = 0;
        for (final array in RegExp(r'\[([^\]]*)\]\s*TJ').allMatches(qdf)) {
          for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!)) {
            count += hex[1]!.length ~/ 4;
          }
        }
        return count;
      }

      test('standard ligatures, unless the theme turns them off', () {
        const text = 'The official office files.';
        final ligated = glyphs(_pdf(text, theme: yrsa));
        final plain = glyphs(
          _pdf(text, theme: '${yrsa}base_font_ligatures: none\n'),
        );
        expect(ligated, lessThan(plain));
        // The same text either way.
        expect(
          _pages(_pdf(text, theme: yrsa)).first,
          _pages(_pdf(text, theme: '${yrsa}base_font_ligatures: none\n')).first,
        );
      });

      /// The fonts [pdf] uses, by PostScript name (without the subset tag).
      Set<String> fonts(String pdf) => {
        for (final line
            in (Process.runSync('pdffonts', [pdf]).stdout as String)
                .split('\n')
                .skip(2))
          if (line.trim().isNotEmpty) line.split(' ').first.split('+').last,
      };

      test('emphasis inside italic text is upright', () {
        const source =
            ':nofooter:\n\npass:[<em>Outer <em>inner</em> outer.</em>]';
        expect(fonts(_pdf(source)), {'NotoSerif-Italic', 'NotoSerif'});
        // The compatibility mode sets it all in italic, as the gem does.
        expect(fonts(_pdf(source, compat: true)), {'NotoSerif-Italic'});
        expect(fonts(_pdf(source, theme: 'base_emphasis_inversion: false\n')), {
          'NotoSerif-Italic',
        });
      });

      test('emphasis in an italic block is upright', () {
        const source =
            ':nofooter:\n\n[verse]\n____\nAn _emphasized_ word.\n____\n';
        const theme = 'verse_font_style: italic\n';
        expect(fonts(_pdf(source, theme: theme)), {
          'NotoSerif-Italic',
          'NotoSerif',
        });
      });

      test('first-line indents skip the first paragraph after a heading or '
          'a block', () {
        const theme = 'prose_text_indent_inner: 24\nprose_margin_inner: 0\n';
        final pdf = _pdf(
          '== Heading\n\nFirst paragraph.\n\nSecond paragraph.\n\n'
          '* item\n\nAfter the list.\n\nAnd another.\n',
          theme: theme,
        );
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        double x(String word) => double.parse(
          RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
        );
        const margin = 48.24;
        expect(x('First'), closeTo(margin, 0.01));
        expect(x('Second'), closeTo(margin + 24, 0.01));
        expect(x('After'), closeTo(margin, 0.01));
        expect(x('And'), closeTo(margin + 24, 0.01));
      });

      test('an indent may be given in ems', () {
        // The default theme's base font size is 10.5.
        final pdf = _pdf(
          'First paragraph.\n\nSecond paragraph.\n',
          theme: 'prose_text_indent_inner: 2em\n',
        );
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        final x = double.parse(
          RegExp(r'xMin="([\d.]+)"[^>]*>Second<').firstMatch(bbox)![1]!,
        );
        expect(x, closeTo(48.24 + 21, 0.01));
      });
    },
    skip: _tools && _has('qpdf') && _has('pdffonts')
        ? false
        : 'needs poppler and qpdf',
  );

  group('fragmentation', () {
    /// The text of [pdf], every page in order, without whitespace (in
    /// layout mode, which keeps hyphens at line ends).
    String compact(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .replaceAll(RegExp(r'\s+'), '');

    /// A listing of [lines] lines of distinct text, some indented, one
    /// in [long] lines far wider than the page.
    List<String> listing(int n, int lines, {int long = 0}) => [
      for (var i = 0; i < lines; i++)
        [
          '${'  ' * (i % 3)}listing$n line$i = call(argument$i);',
          if (long > 0 && i % long == long - 1) ' // ${'wide$n-$i ' * 24}',
        ].join(),
    ];

    test('every listing line appears once, in order, within the margin', () {
      final listings = [
        for (var n = 0; n < 16; n++)
          listing(n, 3 + (n * 7) % 37, long: n.isEven ? 5 : 0),
      ];
      final source = StringBuffer(':nofooter:\n\n');
      for (final (n, lines) in listings.indexed) {
        source
          ..write('Paragraph $n before the listing. ' * (1 + n % 4))
          ..write('\n\n');
        if (n % 3 == 0) source.write('.Listing $n\n');
        source.write('----\n${lines.join('\n')}\n----\n\n');
      }
      final pdf = _pdf(source.toString());
      final text = compact(pdf);
      for (final (n, lines) in listings.indexed) {
        final whole = lines.join().replaceAll(RegExp(r'\s+'), '');
        expect(whole.allMatches(text).length, 1, reason: 'listing $n');
      }
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      const right = 595.28 - 48.24;
      for (final m in RegExp(r'xMax="([\d.]+)"').allMatches(bbox)) {
        expect(double.parse(m[1]!), lessThanOrEqualTo(right + 0.5));
      }
    });

    test('a listing leaves neither a widow nor an orphan', () {
      final code = listing(0, 12).join('\n');
      for (var filler = 40; filler < 52; filler++) {
        final source = [
          ':nofooter:\n\n',
          for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
          'Filler end.\n\n----\n$code\n----\n',
        ].join();
        final pages = _pages(_pdf(source));
        if (pages.length < 2) continue;
        bool ofListing(String line) => line.contains('listing0');
        final before = pages[0].where(ofListing).length;
        final after = pages[1].where(ofListing).length;
        expect(
          before == 0 || before >= 2,
          isTrue,
          reason: 'filler $filler: $before line(s) at the bottom',
        );
        expect(
          after == 0 || after >= 2,
          isTrue,
          reason: 'filler $filler: $after line(s) at the top',
        );
      }
    });

    test('a caption stays with its listing', () {
      final code = listing(0, 30).join('\n');
      for (var filler = 40; filler < 50; filler++) {
        final source = [
          ':nofooter:\n\n',
          for (var i = 0; i < filler; i++) 'Filler line $i. +\n',
          'Filler end.\n\n.The caption\n----\n$code\n----\n',
        ].join();
        for (final page in _pages(_pdf(source))) {
          final caption = page.indexWhere((l) => l.contains('The caption'));
          if (caption < 0) continue;
          expect(
            caption + 1 < page.length && page[caption + 1].contains('listing0'),
            isTrue,
            reason: 'filler $filler: the caption ends its page',
          );
        }
      }
    });

    test(
      'text in a column too narrow for a character is kept, with a warning',
      () {
        final logger = MemoryLogger();
        final pdf = _pdf(
          ':nofooter:\n\n[cols="1,400"]\n|===\n|Wxyz |\n|===\n',
          logger: logger,
        );
        expect(compact(pdf), contains('Wxyz'));
        expect(logger.messages.map((m) => m.message.text), [
          'table column 1 is too narrow for its text; the text overflows it',
        ]);
      },
    );

    test('a wrapped line goes on with a hanging indent', () {
      final pdf = _pdf(
        ':nofooter:\n\n----\n    start ${'word ' * 40}end\nnext\n----\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final words = [
        for (final m in RegExp(
          r'xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([^<]*)<',
        ).allMatches(bbox))
          (double.parse(m[1]!), double.parse(m[2]!), m[3]!),
      ];
      final start = words.firstWhere((w) => w.$3 == 'start');
      final next = words.firstWhere((w) => w.$3 == 'next');
      // The first word of each line after the first of the source line.
      final continued = <double>[];
      double? lastY;
      for (final w in words) {
        if (w.$2 <= start.$2 || w.$2 >= next.$2) continue;
        if (w.$2 != lastY) continued.add(w.$1);
        lastY = w.$2;
      }
      expect(continued, isNotEmpty);
      // The default theme's code font size is 10.5... at 0.8: 8.4; 1em.
      for (final x in continued) {
        expect(x, greaterThan(start.$1));
      }
      expect(next.$1, lessThan(start.$1));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('callouts', () {
    const source =
        ':nofooter:\n\n----\nconst a = 1; // <1>\nconst b = 2; // <2>\n'
        'const c = 3; // <1>\n----\n<1> First.\n<2> Second.\n';

    String qdf(String pdf) =>
        Process.runSync('qpdf', [
              '--qdf',
              '--object-streams=disable',
              pdf,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;

    test('markers are left out of the copied code', () {
      final modern = _pages(_pdf(source)).first;
      expect(modern.take(3), ['const a = 1;', 'const b = 2;', 'const c = 3;']);
      // The compatibility mode copies them, as the gem's PDF does.
      final compat = _pages(_pdf(source, compat: true)).first;
      expect(compat.first, 'const a = 1; ①');
    });

    test('markers link to their items and items back', () {
      final pdf = qdf(_pdf(source));
      final names = {
        for (final m in RegExp(
          r'^\s*\((CO[^)]*)\)',
          multiLine: true,
        ).allMatches(pdf))
          m[1]!,
      };
      expect(names, {
        'CO1-1', 'CO1-2', 'CO1-3', //
        'CO1-1-item', 'CO1-2-item', 'CO1-3-item',
      });
      final links = [
        for (final m in RegExp(r'/Dest \(([^)]*)\)').allMatches(pdf)) m[1]!,
      ]..sort();
      expect(links, [
        'CO1-1', 'CO1-1-item', 'CO1-2', 'CO1-2-item', 'CO1-3-item', //
      ]);
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');
}
