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
        "      content: 'P[{part-numeral}] C[{chapter-numeral}] {page-number}'\n"
        '  verso: *both\n';

    /// The footer of each page that has one.
    List<String> footers(String pdf) => [
      for (final page
          in (Process.runSync('pdftotext', ['-layout', pdf, '-']).stdout
                  as String)
              .split('\f'))
        if (RegExp(r'P\[.*$').firstMatch(page.trim()) case final m?) m[0]!,
    ];

    for (final compat in [false, true]) {
      test('are the part\'s and the chapter\'s'
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
