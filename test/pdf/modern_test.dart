// The modern engine (the default): what it does differently from the
// asciidoctor-pdf compatibility mode, read back from the PDFs it makes.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// The content of [pdf], uncompressed (its drawing operators readable).
String _content(String pdf) {
  final out = '$pdf.qdf';
  Process.runSync('qpdf', ['--qdf', '--object-streams=disable', pdf, out]);
  return latin1.decode(File(out).readAsBytesSync());
}

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

    test('the theme may ask for line-by-line breaking', () {
      final greedy = _pages(
        _pdf(_paragraph, theme: 'base_line_breaking: greedy\n'),
      ).first;
      expect(greedy, hasLength(5));
      expect(greedy.last, 'REST.');
    });

    test('a paragraph that starts with an index term starts at the margin', () {
      final pdf = _pdf(
        '(((hypermedia client)))\n(((web browser)))\nAnd, finally.\n\n'
        'Plain.\n\n[index]\n== Index\n',
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      double left(String word) => double.parse(
        RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      expect(left('And,'), left('Plain.'));
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
        final warnings = [
          for (final m in logger.messages)
            if (m.severity == Severity.warn) m.message,
        ];
        expect(warnings.map((m) => m.text), [
          'table column 1 is too narrow for its text; the text overflows it',
        ]);
        // The table's line (after the header attribute and a blank line,
        // its attribute list is line 3, its delimiter line 4).
        expect(warnings.single.sourceLocation?.lineno, 4);
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

  group('running content numerals', () {
    // Parts and chapters numbered, a preface and the contents not.
    const book =
        '= Book\n:doctype: book\n:sectnums:\n:partnums:\n:toc:\n\n'
        '[preface]\n== Preface\n\nBefore.\n\n'
        '= Part One\n\n== Chapter One\n\nText.\n\n'
        '== Chapter Two\n\nText.\n';
    const theme =
        'footer:\n  recto: &both\n    right:\n'
        '      content: '
        "'P[{part-numeral}] C[{chapter-numeral}] {page-number}'\n"
        '  verso: *both\n'
        // Each chapter here is a page: its opener.
        'running_content_on_openers: true\n';

    /// The footer of each page that has one.
    List<String> footers(String pdf) => [
      for (final page
          in (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout
                  as String)
              .split('\f'))
        if (RegExp(r'P\[.*$').firstMatch(page.trim()) case final m?) m[0]!,
    ];

    for (final compat in [false, true]) {
      test("are the part's and the chapter's"
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(_pdf(book, theme: theme, compat: compat));
        // A line that refers to a numeral the page hasn't (the contents,
        // the preface, the part's own page) is left out, as in the gem.
        expect(pages, ['P[I] C[1] 3', 'P[I] C[2] 4']);
      });

      test('name a chapter whose title is hidden'
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(
          _pdf(
            '= Book\n:doctype: book\n\n[colophon%notitle]\n== Copy\n\nText.\n',
            theme: theme.replaceFirst(
              'P[{part-numeral}] C[{chapter-numeral}] {page-number}',
              'P[{chapter-title}]',
            ),
            compat: compat,
          ),
        );
        expect(pages, ['P[Copy]']);
      });

      if (!compat) {
        test('a Mustache template, its numeral part optional', () {
          final pdf = _pdf(
            book,
            theme:
                'footer:\n  title_style: basic\n  recto: &both\n    right:\n'
                "      content: '{{#chapter-numeral}}{{chapter-numeral}}. "
                "{{/chapter-numeral}}{{chapter-title}} · {page-number}'\n"
                '  verso: *both\n'
                'running_content_on_openers: true\n',
          );
          final lines = [
            for (final page in _pages(pdf))
              if (page.isNotEmpty) page.last,
          ];
          // The preface has no numeral: its title alone, the line kept.
          expect(lines, contains('Preface · 1'));
          expect(lines, contains('1. Chapter One · 3'));
        });
      }

      test('go with titles without numbers (title_style: basic)'
          '${compat ? ' (compatibility mode)' : ''}', () {
        final pages = footers(
          _pdf(
            book,
            theme: theme
                .replaceFirst('footer:\n', 'footer:\n  title_style: basic\n')
                .replaceFirst(
                  '{page-number}',
                  '{page-number} {part-title} / {chapter-title}',
                ),
            compat: compat,
          ),
        );
        expect(pages, [
          'P[I] C[1] 3 Part One / Chapter One',
          'P[I] C[2] 4 Part One / Chapter Two',
        ]);
      });
    }
  }, skip: _tools ? false : 'needs poppler');

  group('index', () {
    const book =
        '= Doc\n:doctype: book\n\n== Chap\n\n'
        '((alpha)) and ((alpha)) and ((hypermedia)).\n\n<<<\n\n'
        'More ((alpha)).\n\n[index]\n== Index\n';

    /// The index's lines (the last page's).
    List<String> index(String pdf) =>
        _pages(pdf).lastWhere((page) => page.isNotEmpty);

    test('lists each page once', () {
      expect(index(_pdf(book)), contains('alpha, 1, 2'));
      // The gem lists a page for each use.
      expect(index(_pdf(book, compat: true)), contains('alpha, 1, 1, 2'));
    });

    test('is set in the index font', () {
      double height(String pdf) {
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        final m = RegExp(
          r'yMin="([\d.]+)" xMax="[\d.]+" yMax="([\d.]+)">hypermedia,<',
        ).firstMatch(bbox)!;
        return double.parse(m[2]!) - double.parse(m[1]!);
      }

      final small = _pdf(book, theme: 'index_font_size: 6\n');
      expect(height(small), lessThan(height(_pdf(book)) * 0.7));
    });

    test('may set the page numbers in a column, without letters', () {
      final pdf = _pdf(
        book,
        theme:
            'index_pagenum_text_align: right\n'
            'index_category_headings: false\n',
      );
      final lines = index(pdf);
      expect(lines, isNot(contains('A')));
      expect(lines, isNot(contains('H')));
      expect(
        lines.any((l) => RegExp(r'^alpha\s{4,}1, 2$').hasMatch(l)),
        isTrue,
      );
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      // The words of each line (by its top), and where the line ends.
      final lineWords = <String, List<String>>{};
      final lineEnds = <String, double>{};
      for (final m in RegExp(
        r'yMin="([\d.]+)" xMax="([\d.]+)"[^>]*>([^<]*)<',
      ).allMatches(bbox)) {
        (lineWords[m[1]!] ??= []).add(m[3]!);
        lineEnds[m[1]!] = double.parse(m[2]!);
      }
      double end(String term) =>
          lineEnds[lineWords.entries
              .lastWhere((e) => e.value.first == term)
              .key]!;
      // Both entries' numbers end at the column's right edge.
      expect(end('alpha'), closeTo(end('hypermedia'), 0.01));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('openers', () {
    const book =
        '= Book\n:doctype: book\n:sectnums:\n:partnums:\n\n'
        '[colophon%notitle%nofooter]\n== Copy\n\nCopyright.\n\n'
        '= Part One\n\n== Chapter One\n\nText.\n\n<<<\n\nMore text.\n';
    const footer =
        'footer:\n  recto: &both\n    right:\n'
        "      content: 'F{page-number}'\n  verso: *both\n";

    /// The text of each page.
    List<String> pages(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .split('\f')
            .map((page) => page.trim())
            .where((page) => page.isNotEmpty)
            .toList();

    test('have no running content, nor pages with nofooter', () {
      final text = pages(_pdf(book, theme: footer));
      // The title page; the copyright page; the part; the chapter's
      // opening page; its second page, the only one with a footer.
      expect(text, hasLength(5));
      expect(text[1], 'Copyright.');
      expect(text[2], isNot(contains('F')));
      expect(text[3], isNot(contains('F')));
      expect(text[4], endsWith('F4'));
    });

    test('have it when the theme says so', () {
      final text = pages(
        _pdf(book, theme: '${footer}running_content_on_openers: true\n'),
      );
      expect(text[3], endsWith('F3'));
      // The compatibility mode: the gem's pages, nofooter on a section
      // ignored.
      final compat = pages(_pdf(book, theme: footer, compat: true));
      expect(compat[1], endsWith('F1'));
      expect(compat[3], endsWith('F3'));
    });

    test('may set the label on a line of its own (a template)', () {
      final text = pages(
        _pdf(
          book,
          theme:
              'heading_h1_content: "{{signifier}} {{numeral}}\\n{{title}}"\n'
              'heading_h2_content: "{{#numeral}}{{signifier}} {{numeral}}'
              '\\n{{/numeral}}{{title}}"\n',
        ),
      );
      expect(text[2], 'Part I\nPart One');
      expect(text[3], startsWith('Chapter 1\nChapter One'));
      expect(pages(_pdf(book))[3], startsWith('Chapter 1. Chapter One'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('footnotes', () {
    const book =
        '= Doc\n:doctype: book\n\n== One\n\n'
        'First page.footnote:[The first note.]\n\n<<<\n\n'
        'Second page.footnote:[The second note.]\n\nLast words.\n';

    test('are at the bottom of the page of their reference', () {
      final pages = _pages(_pdf(book));
      expect(pages[1], ['One', '[1]', 'First page.', '[1] The first note.']);
      // Below the text that follows the reference.
      expect(pages[2], [
        '[2]',
        'Second page.',
        'Last words.',
        '[2] The second note.',
      ]);
    });

    test('may go at the end of the chapter, as in the gem', () {
      final pages = _pages(_pdf(book, theme: 'footnotes_placement: end\n'));
      expect(pages[1], ['One', '[1]', 'First page.']);
      expect(pages[2].last, '[2] The second note.');
      expect(pages[2], contains('[1] The first note.'));
    });

    const twoChapters =
        '= Doc\n:doctype: book\n\n== One\n\n'
        'A.footnote:[First.] B.footnote:[Second.]\n\n<<<\n\n'
        'C.footnote:[Third.]\n\n== Two\n\nD.footnote:[Fourth.]\n';

    /// The footnote labels on each page with any, as their notes show them.
    List<List<String>> notes(String pdf) => [
      for (final page in _pages(pdf))
        if (page.any((l) => RegExp(r'^\[\d+\] \w').hasMatch(l)))
          [
            for (final l in page)
              if (RegExp(r'^\[\d+\] \w').hasMatch(l)) l,
          ],
    ];

    test('may be numbered on each page', () {
      final pdf = _pdf(twoChapters, theme: 'footnotes_numbering: page\n');
      expect(notes(pdf), [
        ['[1] First.', '[2] Second.'],
        ['[1] Third.'],
        ['[1] Fourth.'],
      ]);
      // The references have the same numbers.
      expect(_pages(pdf)[1][1], matches(RegExp(r'^\[1\]\s+\[2\]$')));
    });

    test('may be numbered through the document', () {
      final pdf = _pdf(twoChapters, theme: 'footnotes_numbering: document\n');
      expect(notes(pdf), [
        ['[1] First.', '[2] Second.'],
        ['[3] Third.'],
        ['[4] Fourth.'],
      ]);
      // From 1 in each chapter by default, as in the gem.
      expect(notes(_pdf(twoChapters)).last, ['[1] Fourth.']);
    });

    test("may show links' URIs (show-link-uri=footnote)", () {
      const source =
          '= Doc\n:show-link-uri: footnote\n\n'
          'See https://htmx.org[htmx] and https://example.org.\n';
      final text = _pages(_pdf(source)).first.join('\n');
      expect(text, contains('[1] https://htmx.org'));
      // A bare link shows its URI already.
      expect(text, isNot(contains('[2]')));
      final compat = _pages(_pdf(source, compat: true)).first.join('\n');
      expect(compat, contains('htmx [https://htmx.org]'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('syntax highlighting', () {
    const source =
        '= Doc\n:source-highlighter: highlight.js\n\n'
        '[source,python]\n----\ndef index(): # <1>\n    return 1\n----\n'
        '<1> A function.\n';

    // GitHub's keyword color, #d73a49.
    const keyword = '0.84314 0.22745 0.28627 rg';

    test('colors the tokens as the highlight.js theme does', () {
      expect(_content(_pdf(source)), contains(keyword));
      final text = _pages(_pdf(source)).first.join('\n');
      expect(text, contains('def index():'));
      expect(text, contains('A function.'));
    });

    test('in the theme highlightjs-theme names', () {
      final monokai = _content(
        _pdf(source.replaceFirst('\n\n', '\n:highlightjs-theme: monokai\n\n')),
      );
      expect(monokai, isNot(contains(keyword)));
      // Monokai's keyword color, #f92672.
      expect(monokai, contains('0.97647 0.14902 0.44706 rg'));
    });

    test('not in the compatibility mode, as in the gem', () {
      expect(_content(_pdf(source, compat: true)), isNot(contains(keyword)));
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('a section with a styled role', () {
    const source =
        '= Doc\n:doctype: book\n\n== Chap\n\nText.\n\n'
        '[.html-note]\n=== Notes\n\nIn the box.\n';
    const theme =
        'section_role_html_note_background_color: F5F5FF\n'
        'section_role_html_note_padding: 12\n'
        'section_role_html_note_font_size: 7\n'
        'section_role_html_note_heading_font_size: 8\n';
    // The fill, #F5F5FF.
    const fill = '0.96078 0.96078 1 rg';

    double height(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final m = RegExp(
        'yMin="([\\d.]+)" xMax="[\\d.]+" yMax="([\\d.]+)">$word<',
      ).firstMatch(bbox)!;
      return double.parse(m[2]!) - double.parse(m[1]!);
    }

    test('is set in a box, in its own fonts', () {
      final pdf = _pdf(source, theme: theme);
      expect(_content(pdf), contains(fill));
      expect(height(pdf, 'box.'), lessThan(height(pdf, 'Text.') * 0.8));
      expect(height(pdf, 'Notes'), lessThan(height(pdf, 'Chap') * 0.6));
    });

    test('is a section as before in the compatibility mode', () {
      expect(
        _content(_pdf(source, theme: theme, compat: true)),
        isNot(contains(fill)),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('floating images', () {
    final svg = base64.encode(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" '
        'viewBox="0 0 400 300"><rect width="400" height="300"/></svg>',
      ),
    );
    final book = [
      '= Doc\n:doctype: book\n\n== Chap\n',
      for (var i = 1; i <= 14; i++)
        'Paragraph $i with some words in it to fill a line or two.\n',
      '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=100%]\n',
      'After the image.\n\n== Next\n\nNext chapter.\n',
    ].join('\n');

    /// The text of each page, its lines joined.
    List<String> pages(String pdf) =>
        _pages(pdf).map((lines) => lines.join('\n')).toList();

    test("go to the next page when they don't fit, the text filling in", () {
      final text = pages(_pdf(book, theme: 'image_placement: auto\n'));
      expect(text[1], contains('After the image.'));
      expect(text[2], startsWith('Figure 1. The figure'));
      // The next chapter after the figure, on its own page.
      expect(text[3], startsWith('Next'));
    });

    test('may go to the bottom or the top of the page they fit on', () {
      final short = [
        '= Doc\n:doctype: book\n\n== Chap\n',
        'Before the image.\n',
        '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n',
        'After the image.\n',
      ].join('\n');
      List<String> lines(String placement) =>
          _pages(_pdf(short, theme: 'image_placement: $placement\n'))[1];
      expect(lines('bottom'), [
        'Chap',
        'Before the image.',
        'After the image.',
        'Figure 1. The figure',
      ]);
      expect(lines('top'), [
        'Figure 1. The figure',
        'Chap',
        'Before the image.',
        'After the image.',
      ]);
      // In place where it fits.
      expect(lines('next'), [
        'Chap',
        'Before the image.',
        'Figure 1. The figure',
        'After the image.',
      ]);
    });

    test('stay in a sidebar', () {
      final inSidebar = [
        '= Doc\n:doctype: book\n\n== Chap\n',
        '****\nBefore the image.\n',
        '.The figure\nimage::data:image/svg+xml;base64,$svg[pdfwidth=50%]\n',
        'After the image.\n****\n',
      ].join('\n');
      expect(_pages(_pdf(inSidebar, theme: 'image_placement: bottom\n'))[1], [
        'Chap',
        'Before the image.',
        'Figure 1. The figure',
        'After the image.',
      ]);
    });

    test('stay in place without image_placement: auto', () {
      final text = pages(_pdf(book));
      expect(text[2], contains('After the image.'));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('a family without an italic or bold face', () {
    const theme =
        'font:\n  catalog:\n    merge: true\n    Upright:\n'
        '      normal: yrsa-regular-latin.ttf\n'
        'base_font_family: Upright\n';
    const source = 'Plain, _slanted_ and *stroked*.\n';

    test('has them made from its regular face', () {
      final pdf = _pdf(source, theme: theme);
      final content = _content(pdf);
      expect(content, contains('1 0 0.2 1 '));
      expect(content, contains(' w\n2 Tr'));
      expect(
        _pages(pdf).first.join(' '),
        contains('Plain, slanted and stroked.'),
      );
    });

    test('has its regular face in the compatibility mode', () {
      final content = _content(_pdf(source, theme: theme, compat: true));
      expect(content, isNot(contains('1 0 0.2 1 ')));
      expect(content, isNot(contains('2 Tr')));
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('space around blocks', () {
    const source =
        '= Doc\n:doctype: book\n\n== Chap\n\nBefore.\n\n'
        '----\ncode\n----\n\nAfter.\n\n____\nQuoted.\n____\n\nLast.\n';

    /// The top of [word] on the first page with text.
    double top(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      return double.parse(
        RegExp('yMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
    }

    // The default theme: 12 points below each block.
    test('each kind of block has its own space below', () {
      final plain = _pdf(source);
      final spaced = _pdf(source, theme: 'code_margin_bottom: 30\n');
      // After the code: 18 points further down; above it, as before.
      expect(top(spaced, 'code'), closeTo(top(plain, 'code'), 0.01));
      expect(top(spaced, 'After.') - top(plain, 'After.'), closeTo(18, 0.01));
    });

    test('space above collapses with the space below the block before', () {
      final plain = _pdf(source);
      // 20 above the code, after a paragraph's 12 below: 20, not 32.
      final spaced = _pdf(source, theme: 'code_margin_top: 20\n');
      expect(top(spaced, 'code') - top(plain, 'code'), closeTo(8, 0.01));
      // Less than the space below the block before: nothing changes.
      final less = _pdf(source, theme: 'quote_margin_top: 6\n');
      expect(top(less, 'Quoted.'), closeTo(top(plain, 'Quoted.'), 0.01));
    });

    test('after a heading, what its margin below leaves', () {
      const first = '= Doc\n:doctype: book\n\n== Chap\n\n----\ncode\n----\n';
      final plain = _pdf(first, theme: 'heading_margin_bottom: 6\n');
      final spaced = _pdf(
        first,
        theme: 'heading_margin_bottom: 6\ncode_margin_top: 20\n',
      );
      expect(top(spaced, 'code') - top(plain, 'code'), closeTo(14, 0.01));
    });

    test("a quote's attribution: its own space above, aligned right", () {
      const quote = '[quote, Ted Nelson]\n____\nQuoted.\n____\n';
      double left(String pdf, String word) {
        final bbox =
            Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
        return double.parse(
          RegExp('xMin="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
        );
      }

      final plain = _pdf(quote);
      final styled = _pdf(
        quote,
        theme: 'quote_cite_margin_top: 2\nquote_cite_text_align: right\n',
      );
      // The default theme: 12 points above it.
      expect(top(plain, 'Nelson') - top(styled, 'Nelson'), closeTo(10, 0.01));
      expect(left(styled, 'Nelson'), greaterThan(left(plain, 'Nelson') + 200));
    });

    test("are the gem's in the compatibility mode", () {
      final plain = _pdf(source, compat: true);
      final spaced = _pdf(
        source,
        theme: 'code_margin_bottom: 30\ncode_margin_top: 20\n',
        compat: true,
      );
      expect(top(spaced, 'After.'), closeTo(top(plain, 'After.'), 0.01));
    });
  }, skip: _tools ? false : 'needs poppler');

  test("the title page's author delimiter keeps its spaces", () {
    const book = '= Book\nAda One; Bob Two\n:doctype: book\n\n== C\n\nText.\n';
    double gap(String pdf) {
      final bbox =
          Process.runSync('pdftotext', [
                '-f',
                '1',
                '-l',
                '1',
                '-bbox',
                pdf,
                '-',
              ]).stdout
              as String;
      double at(String word, String side) => double.parse(
        RegExp('$side="([\\d.]+)"[^>]*>$word<').firstMatch(bbox)![1]!,
      );
      return at('Bob', 'xMin') - at('One', 'xMax');
    }

    const theme = "title_page_authors_delimiter: '    '\n";
    final four = gap(_pdf(book, theme: theme));
    final one = gap(_pdf(book, theme: theme, compat: true));
    expect(four, greaterThan(one * 3));
  }, skip: _tools ? false : 'needs poppler');

  test('the contents may list titles without numbers', () {
    const book =
        '= Book\n:doctype: book\n:toc:\n:sectnums:\n\n== One\n\nText.\n';
    String contents(String pdf) => _pages(pdf)[1].join('\n');
    expect(contents(_pdf(book)), contains('1. One'));
    final plain = contents(
      _pdf(book, theme: "toc_entry_content: '{{title}}'\n"),
    );
    expect(plain, contains('One'));
    expect(plain, isNot(contains('1. One')));
  }, skip: _tools ? false : 'needs poppler');

  test('a definition term may run in before its description', () {
    const source =
        'Hypermedia Control:: A hypermedia control is an element in a '
        'hypermedia that describes (or controls) some sort of interaction, '
        'often with a remote server, by encoding information about that '
        'interaction directly and completely within itself.\n';
    final pdf = _pdf(
      source,
      theme:
          'description_list_term_display: inline\n'
          'description_list_description_indent: 20\n',
    );
    final lines = _pages(pdf).first;
    expect(lines.first, startsWith('Hypermedia Control A hypermedia control'));
    final bbox =
        Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
    final lefts = [
      for (final m in RegExp(r'<line xMin="([\d.]+)"').allMatches(
        Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout
            as String,
      ))
        double.parse(m[1]!),
    ];
    // The lines after the first hang 20 points in.
    expect(lefts[1] - lefts[0], closeTo(20, 0.5));
    expect(bbox, contains('>Control<'));
  }, skip: _tools ? false : 'needs poppler');

  test('callout markers may be text', () {
    const source =
        '[source,ruby]\n----\nputs 1 # <1>\nputs 2 # <2>\n----\n'
        '<1> One.\n<2> Two.\n';
    const theme =
        "conum_glyphs: '[{{number}}]'\n"
        "callout_list_marker_content: '{{number}}.'\n"
        'conum_font_style: bold\n';
    final text = _pages(_pdf(source, theme: theme)).first.join('\n');
    expect(text, contains('1. One.'));
    expect(text, contains('2. Two.'));
    // The markers in the code are left out of its text: count the glyphs
    // drawn. Each `[1]` is three where a circled number is one; each
    // `1.` in the list two.
    int glyphs(String pdf) => [
      for (final array in RegExp(
        r'\[([^\]]*)\]\s*TJ',
      ).allMatches(_content(pdf)))
        for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!))
          hex[1]!.length ~/ 4,
    ].fold(0, (a, b) => a + b);
    expect(
      glyphs(_pdf(source, theme: theme)) - glyphs(_pdf(source)),
      2 * 2 + 2 * 1,
    );
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('blank pages', () {
    // A prepress book: each chapter starts on a recto page, so a
    // one-page chapter leaves a blank verso page before the next.
    const book =
        '= Book\n:doctype: book\n:media: prepress\n\n'
        '== One\n\nFirst chapter.\n\n== Two\n\nSecond chapter.\n';

    /// The text of each page of [pdf], the page number included.
    List<String> pages(String pdf) =>
        (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout as String)
            .split('\f')
            .map((page) => page.trim())
            .toList();

    // Pages: the title page, a blank one before the body (never with
    // running content), chapter One, a blank verso, chapter Two.
    test('carry no running content', () {
      expect(pages(_pdf(book))[3], isEmpty);
      // The compatibility mode numbers it, as the gem does.
      expect(pages(_pdf(book, compat: true))[3], '2');
    });

    test('carry it when the theme says so', () {
      final themed = pages(
        _pdf(book, theme: 'running_content_on_blank_pages: true\n'),
      );
      expect(themed[3], '2');
    });
  }, skip: _tools ? false : 'needs poppler');

  group('table styles', () {
    /// The box of [word] in [pdf] (y down from the top).
    ({double xMin, double xMax, double height}) box(String pdf, String word) {
      final bbox =
          Process.runSync('pdftotext', ['-bbox', pdf, '-']).stdout as String;
      final m = RegExp(
        r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" '
        'yMax="([\\d.]+)">$word<',
      ).firstMatch(bbox)!;
      return (
        xMin: double.parse(m[1]!),
        xMax: double.parse(m[3]!),
        height: double.parse(m[4]!) - double.parse(m[2]!),
      );
    }

    test('a table role takes its keys from the theme once', () {
      final pdf = _pdf(
        '|===\n|Plain\n|===\n\n[.big]\n|===\n|Styled\n|===\n',
        theme: 'table_role_big_font_size: 16\n',
      );
      expect(box(pdf, 'Styled').height, greaterThan(box(pdf, 'Plain').height));
      // The compatibility mode doesn't read the key.
      final compat = _pdf(
        '|===\n|Plain\n|===\n\n[.big]\n|===\n|Styled\n|===\n',
        compat: true,
        theme: 'table_role_big_font_size: 16\n',
      );
      expect(
        box(compat, 'Styled').height,
        closeTo(box(compat, 'Plain').height, 0.01),
      );
    });

    test("a cell whose text has a role takes that role's cell keys", () {
      final pdf = _pdf(
        '[cols="1,1"]\n|===\n|[.paid]#Paid# |Open\n|===\n',
        theme: 'table_cell_role_paid_text_align: right\n',
      );
      final paid = box(pdf, 'Paid');
      final open = box(pdf, 'Open');
      // Right-aligned in the first column: it ends near the second's
      // start; the second starts at its left.
      expect(open.xMin - paid.xMax, lessThan(20));
    });
  }, skip: _tools ? false : 'needs poppler');

  group('print', () {
    /// An ICC header: an output (printer) profile for [space].
    String profile(String space) {
      final file = File('${_dir.path}/${space.trim()}.icc')
        ..writeAsBytesSync(Uint8List(132)..setAll(12, 'prtr$space'.codeUnits));
      return file.path;
    }

    String qdf(String pdf) =>
        Process.runSync('qpdf', [
              '--qdf',
              '--object-streams=disable',
              pdf,
              '-',
            ], stdoutEncoding: latin1).stdout
            as String;

    const book = '= Print\n:doctype: book\n\n== One\n\nText.\n';

    test('PDF/X-4: an output intent, the identification, print boxes', () {
      final logger = MemoryLogger();
      final pdf = _pdf(
        ':pdf-standard: PDF/X-4\n:pdf-output-intent: ${profile('RGB ')}\n'
        '$book',
        logger: logger,
      );
      final text = qdf(pdf);
      expect(text, startsWith('%PDF-1.6'));
      expect(text, contains('/S /GTS_PDFX'));
      expect(text, contains('/N 3'));
      expect(text, contains('/Trapped /False'));
      expect(text, contains('/TrimBox'));
      expect([
        for (final m in logger.messages)
          if (m.severity == Severity.warn) m,
      ], isEmpty);
    });

    test('PDF/X-4 with a CMYK condition warns of the RGB content', () {
      final logger = MemoryLogger();
      _pdf(
        ':pdf-standard: PDF/X-4\n:pdf-output-intent: ${profile('CMYK')}\n'
        '$book',
        logger: logger,
      );
      expect(
        logger.messages.map((m) => m.message.text),
        contains(startsWith('the text, lines and images are in RGB')),
      );
    });

    test('PDF/X-4 without a profile is a plain PDF, with an error', () {
      final logger = MemoryLogger();
      final pdf = _pdf(':pdf-standard: PDF/X-4\n$book', logger: logger);
      expect(qdf(pdf), isNot(contains('/OutputIntents')));
      expect(
        logger.messages.map((m) => m.message.text),
        contains(startsWith('PDF/X-4 needs the ICC profile')),
      );
    });

    test('a bleed grows the sheet past the trimmed page', () {
      final pdf = _pdf(book, theme: 'page_bleed: 9\n');
      final boxes = Process.runSync('pdfinfo', ['-box', pdf]).stdout as String;
      expect(boxes, matches(RegExp(r'MediaBox:\s+-9\.00\s+-9\.00')));
      expect(boxes, matches(RegExp(r'TrimBox:\s+0\.00\s+0\.00')));
    });

    test('the layout report lists the blocks that break across pages', () {
      final source = StringBuffer(':pdf-layout-report: report.txt\n\n');
      for (var i = 0; i < 40; i++) {
        source.write('Paragraph $i.\n\n');
      }
      source.write(
        '----\n${[for (var i = 0; i < 40; i++) 'line $i'].join('\n')}\n----\n',
      );
      final pdf = _pdf(source.toString());
      final report = File('${File(pdf).parent.path}/report.txt');
      expect(
        report.readAsStringSync(),
        matches(
          RegExp(r'^d\d+\.adoc: line 83: listing on pages (\d+)-(?!\1)\d+\n$'),
        ),
      );
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');

  group('numerals and small capitals', () {
    const noto = '''
font:
  catalog:
    Noto:
      normal: notoserif-features.ttf
      italic: notoserif-features.ttf
      bold: notoserif-features.ttf
      bold_italic: notoserif-features.ttf
base:
  font-family: Noto
''';

    /// The glyph codes the pages of [pdf] show, in order.
    List<String> codes(String pdf) {
      final qdf =
          Process.runSync('qpdf', [
                '--qdf',
                '--object-streams=disable',
                pdf,
                '-',
              ], stdoutEncoding: latin1).stdout
              as String;
      return [
        for (final array in RegExp(r'\[([^\]]*)\]\s*TJ').allMatches(qdf))
          for (final hex in RegExp('<([0-9a-fA-F]*)>').allMatches(array[1]!))
            hex[1]!,
      ];
    }

    test("an ordered list's numbers in old-style figures", () {
      const source = ':nofooter:\n\n. One\n. Two\n';
      final lining = codes(_pdf(source, theme: noto));
      final oldstyle = codes(
        _pdf(
          source,
          theme: '${noto}olist_marker_font_variant_numeric: oldstyle-nums\n',
        ),
      );
      // The numbers change, the items' text doesn't.
      expect(oldstyle, isNot(lining));
      expect(oldstyle.length, lining.length);
    });

    test('old-style numerals by the theme', () {
      const source = ':nofooter:\n\nIn 2026.';
      final lining = codes(_pdf(source, theme: noto));
      final oldstyle = codes(
        _pdf(
          source,
          theme: '${noto}base_font_variant_numeric: oldstyle-nums\n',
        ),
      );
      expect(oldstyle, isNot(lining));
      // The same text either way.
      expect(
        _pages(
          _pdf(
            source,
            theme: '${noto}base_font_variant_numeric: oldstyle-nums\n',
          ),
        ).first,
        ['In 2026.'],
      );
    });

    test('small capitals by a role', () {
      const source = ':nofooter:\n\nSome [.sc]#Small Caps# here.';
      const theme = '${noto}role_sc_font_variant: small-caps\n';
      expect(
        codes(_pdf(source, theme: theme)),
        isNot(codes(_pdf(source, theme: noto))),
      );
      expect(_pages(_pdf(source, theme: theme)).first, [
        'Some Small Caps here.',
      ]);
    });

    test('small capitals a font lacks are smaller capitals', () {
      // The default theme's Noto Serif subset has no smcp.
      final pdf = _pdf(
        ':nofooter:\n\nSome [.sc]#Small Caps# here.',
        theme: 'role_sc_font_variant: small-caps\n',
      );
      expect(_pages(pdf).first, ['Some SMALL CAPS here.']);
    });
  }, skip: _tools && _has('qpdf') ? false : 'needs poppler and qpdf');
}
