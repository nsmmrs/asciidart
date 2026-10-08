/// Tests for the top-level constants ported from `lib/asciidoctor.rb`.
///
/// Every expectation below is transcribed from a `ruby -Ilib` probe of the
/// real Ruby constants; the probe is named in a comment above each group:
///
/// - scalars/sets/maps: `ruby -Ilib -e 'require "asciidoctor"; ... puts
///   Asciidoctor::NULL.inspect ...'` (scalar dump)
/// - delimited blocks/lists/math: same harness dumping `DELIMITED_BLOCKS`,
///   `DELIMITED_BLOCK_HEADS/TAILS`, `*_BREAK_CHARS`, `NESTABLE_LIST_CONTEXTS`,
///   `ORDERED_LIST_*`, `*_MATH_DELIMITERS`, `STEM_TYPE_ALIASES` (table dump)
/// - attributes/compliance: same harness dumping `DEFAULT_ATTRIBUTES`,
///   `INTRINSIC_ATTRIBUTES`, `Compliance.keys` and each key value
///   (attribute dump)
/// - quote/replacement tables: same harness dumping `QUOTE_SUBS[false/true]`
///   triples and `REPLACEMENTS` triples with `Regexp#source` (table dump)
/// - behavior: `/tmp/probe_const.rb` replaying `String#match` captures and
///   `String#gsub` results for selected rules (behavior probe)
///
/// Ruby symbols map to Dart strings and Ruby `Set`s to Dart `Set`s; regexps
/// use the `rx.dart` character-class fragments per `PORTING-REGEXP.md`, so
/// pattern expectations are the Ruby sources with those documented rewrites
/// applied (`.`, → `[\s\S]`, `\p{Word}` → the UTS#18 union, `\p{Alnum}` →
/// the split fragments, `\p{Alpha}` → `\p{Alphabetic}`, and Ruby's ASCII
/// `\s`/`\S` spelled out, see [asciiSpace]).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

/// [pattern] with Ruby's ASCII-only `\S` spelled out as the port writes it
/// (`[^ \t\n\v\f\r]`; Dart's `\S` would exclude Unicode spaces too).
/// `[\s\S]` (any character) is unchanged.
String asciiSpace(String pattern) => pattern
    .replaceAll(r'[\s\S]', '\u0000')
    .replaceAll(r'\S', r'[^ \t\n\v\f\r]')
    .replaceAll('\u0000', r'[\s\S]');

void main() {
  group('characters and integers', () {
    test('tab is the tab character', () {
      // Probe: scalar dump (TAB="\t").
      expect(tab, equals('\t'));
    });

    test('maxInt is the boundless-operation bound', () {
      // Probe: scalar dump (MAX_INT=9007199254740991).
      expect(maxInt, equals(9007199254740991));
    });
  });

  group('byte order marks', () {
    test('bomBytesUtf8', () {
      // Probe: scalar dump (BOM_BYTES_UTF_8=[239, 187, 191]).
      expect(bomBytesUtf8, equals(<int>[0xef, 0xbb, 0xbf]));
    });

    test('bomBytesUtf16le', () {
      // Probe: scalar dump (BOM_BYTES_UTF_16LE=[255, 254]).
      expect(bomBytesUtf16le, equals(<int>[0xff, 0xfe]));
    });

    test('bomBytesUtf16be', () {
      // Probe: scalar dump (BOM_BYTES_UTF_16BE=[254, 255]).
      expect(bomBytesUtf16be, equals(<int>[0xfe, 0xff]));
    });
  });

  group('defaults', () {
    test('defaultDoctype', () {
      // Probe: scalar dump (DEFAULT_DOCTYPE="article").
      expect(defaultDoctype, equals('article'));
    });

    test('defaultBackend', () {
      // Probe: scalar dump (DEFAULT_BACKEND="html5").
      expect(defaultBackend, equals('html5'));
    });

    test('defaultStylesheetKeys', () {
      // Probe: scalar dump (DEFAULT_STYLESHEET_KEYS=["", "DEFAULT"]).
      expect(defaultStylesheetKeys, equals(<String>{'', 'DEFAULT'}));
    });

    test('defaultStylesheetName', () {
      // Probe: scalar dump (DEFAULT_STYLESHEET_NAME="asciidoctor.css").
      expect(defaultStylesheetName, equals('asciidoctor.css'));
    });

    test('backendAliases', () {
      // Probe: scalar dump (BACKEND_ALIASES={"html" => "html5",
      // "docbook" => "docbook5"}).
      expect(
        backendAliases,
        equals(<String, String>{'html': 'html5', 'docbook': 'docbook5'}),
      );
    });

    test('defaultPageWidths', () {
      // Probe: scalar dump (DEFAULT_PAGE_WIDTHS={"docbook" => 425}).
      expect(defaultPageWidths, equals(<String, int>{'docbook': 425}));
    });

    test('defaultExtensions', () {
      // Probe: scalar dump (DEFAULT_EXTENSIONS={"html" => ".html",
      // "docbook" => ".xml", "pdf" => ".pdf", "epub" => ".epub",
      // "manpage" => ".man", "asciidoc" => ".adoc"}).
      expect(
        defaultExtensions,
        equals(<String, String>{
          'html': '.html',
          'docbook': '.xml',
          'pdf': '.pdf',
          'epub': '.epub',
          'manpage': '.man',
          'asciidoc': '.adoc',
        }),
      );
    });

    test('asciidocExtensions', () {
      // Probe: scalar dump (ASCIIDOC_EXTENSIONS={".adoc" => true,
      // ".asciidoc" => true, ".asc" => true, ".ad" => true,
      // ".txt" => true}).
      expect(
        asciidocExtensions,
        equals(<String, bool>{
          '.adoc': true,
          '.asciidoc': true,
          '.asc': true,
          '.ad': true,
          '.txt': true,
        }),
      );
    });
  });

  group('markers and continuations', () {
    test('attrRefHead', () {
      // Probe: table dump (ATTR_REF_HEAD="{").
      expect(attrRefHead, equals('{'));
    });

    test('listContinuation', () {
      // Probe: table dump (LIST_CONTINUATION="+").
      expect(listContinuation, equals('+'));
    });

    test('hardLineBreak', () {
      // Probe: table dump (HARD_LINE_BREAK=" +").
      expect(hardLineBreak, equals(' +'));
    });
  });

  group('math', () {
    test('blockMathDelimiters', () {
      // Probe: table dump (BLOCK_MATH_DELIMITERS={asciimath: ["\\$", "\\$"],
      // latexmath: ["\\[", "\\]"]}).
      expect(
        blockMathDelimiters,
        equals(<String, List<String>>{
          'asciimath': <String>[r'\$', r'\$'],
          'latexmath': <String>[r'\[', r'\]'],
        }),
      );
    });

    test('stemTypeAliases', () {
      // Probe: table dump (STEM_TYPE_ALIASES={"latexmath" => "latexmath",
      // "latex" => "latexmath", "tex" => "latexmath"}, default "asciimath").
      expect(
        stemTypeAliases,
        equals(<String, String>{
          'latexmath': 'latexmath',
          'latex': 'latexmath',
          'tex': 'latexmath',
        }),
      );
    });
  });

  group('pinned versions', () {
    test('highlightJsVersion', () {
      // Probe: table dump (HIGHLIGHT_JS_VERSION="9.18.3").
      expect(highlightJsVersion, equals('9.18.3'));
    });
  });

  group('attributes', () {
    test('defaultAttributes', () {
      // Probe: attribute dump (DEFAULT_ATTRIBUTES, 20 entries).
      expect(
        defaultAttributes,
        equals(<String, String>{
          'appendix-caption': 'Appendix',
          'appendix-refsig': 'Appendix',
          'caution-caption': 'Caution',
          'chapter-refsig': 'Chapter',
          'example-caption': 'Example',
          'figure-caption': 'Figure',
          'important-caption': 'Important',
          'last-update-label': 'Last updated',
          'note-caption': 'Note',
          'part-refsig': 'Part',
          'prewrap': '',
          'sectids': '',
          'section-refsig': 'Section',
          'table-caption': 'Table',
          'tip-caption': 'Tip',
          'toc-placement': 'auto',
          'toc-title': 'Table of Contents',
          'untitled-label': 'Untitled',
          'version-label': 'Version',
          'warning-caption': 'Warning',
        }),
      );
    });

    test('flexibleAttributes', () {
      // Probe: table dump (FLEXIBLE_ATTRIBUTES=["sectnums"]).
      expect(flexibleAttributes, equals(<String>['sectnums']));
    });

    test('intrinsicAttributes', () {
      // Probe: attribute dump (INTRINSIC_ATTRIBUTES, 31 entries).
      expect(
        intrinsicAttributes,
        equals(<String, String>{
          'startsb': '[',
          'endsb': ']',
          'vbar': '|',
          'caret': '^',
          'asterisk': '*',
          'tilde': '~',
          'plus': '&#43;',
          'backslash': r'\',
          'backtick': '`',
          'blank': '',
          'empty': '',
          'sp': ' ',
          'two-colons': '::',
          'two-semicolons': ';;',
          'nbsp': '&#160;',
          'deg': '&#176;',
          'zwsp': '&#8203;',
          'quot': '&#34;',
          'apos': '&#39;',
          'lsquo': '&#8216;',
          'rsquo': '&#8217;',
          'ldquo': '&#8220;',
          'rdquo': '&#8221;',
          'wj': '&#8288;',
          'brvbar': '&#166;',
          'pp': '&#43;&#43;',
          'cpp': 'C&#43;&#43;',
          'cxx': 'C&#43;&#43;',
          'amp': '&',
          'lt': '<',
          'gt': '>',
        }),
      );
    });
  });

  group('quoteSubs', () {
    // Probe for this group: table dump (QUOTE_SUBS[false] has 12 entries,
    // QUOTE_SUBS[true] has 13 entries; sources via Regexp#source).

    test('is keyed by compat mode with the Ruby entry counts', () {
      expect(quoteSubs.keys, equals(<bool>{false, true}));
      expect(quoteSubs[false], hasLength(12));
      expect(quoteSubs[true], hasLength(13));
    });

    test('normal rules carry the Ruby types and scopes in order', () {
      expect(
        quoteSubs[false]!.map((q) => '${q.type}:${q.scope}'),
        equals(<String>[
          'strong:unconstrained',
          'strong:constrained',
          'double:constrained',
          'single:constrained',
          'monospaced:unconstrained',
          'monospaced:constrained',
          'emphasis:unconstrained',
          'emphasis:constrained',
          'mark:unconstrained',
          'mark:constrained',
          'superscript:unconstrained',
          'subscript:unconstrained',
        ]),
      );
    });

    test('compat rules carry the Ruby types and scopes in order', () {
      expect(
        quoteSubs[true]!.map((q) => '${q.type}:${q.scope}'),
        equals(<String>[
          'strong:unconstrained',
          'strong:constrained',
          'double:constrained',
          'emphasis:constrained',
          'single:constrained',
          'monospaced:unconstrained',
          'monospaced:constrained',
          'emphasis:unconstrained',
          'emphasis:constrained',
          'mark:unconstrained',
          'mark:constrained',
          'superscript:unconstrained',
          'subscript:unconstrained',
        ]),
      );
    });

    test('compat mode shares the unchanged normal rule objects', () {
      final normal = quoteSubs[false]!;
      final compat = quoteSubs[true]!;
      expect(identical(compat[0], normal[0]), isTrue);
      expect(identical(compat[1], normal[1]), isTrue);
      for (var i = 0; i < 6; i++) {
        expect(identical(compat[7 + i], normal[6 + i]), isTrue);
      }
      for (var i = 2; i < 7; i++) {
        expect(normal.contains(compat[i]), isFalse);
      }
    });

    test('normal patterns match the Ruby sources with rewrites applied', () {
      final patterns = quoteSubs[false]!.map((q) => q.pattern.pattern);
      expect(
        patterns,
        equals(
          <String>[
            // Ruby: \\?(?:\[([^\[\]]+)\])?\*\*(.+?)\*\*
            '\\\\?(?:$quoteAttributeListRxt)?\\*\\*($ccAll+?)\\*\\*',
            // Ruby: (^|[^\p{Word};:}])(?:\[...\\])?\*(\S|\S.*?\S)\*(?!\p{Word})
            '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt)?\\*(\\S|\\S$ccAll*?\\S)\\*(?!$cgWord)',
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?"`(\S|\S.*?\S)`"(?!\p{Word}),
            // an underscore allowed on either side (bugfix #2128)
            '(^|_|[^$ccWord;:}])(?:$quoteAttributeListRxt)?"`(\\S|\\S$ccAll*?\\S)`"(?!(?!_)$cgWord)',
            // Ruby: (^|[^\p{Word};:`}])(?:\[...\])?'`(\S|\S.*?\S)`'(?!\p{Word}),
            // likewise (bugfix #2128)
            "(^|_|[^$ccWord;:`}])(?:$quoteAttributeListRxt)?'`(\\S|\\S$ccAll*?\\S)`'(?!(?!_)$cgWord)",
            // Ruby: \\?(?:\[([^\[\]]+)\])?``(.+?)``
            '\\\\?(?:$quoteAttributeListRxt)?``($ccAll+?)``',
            // Ruby: (^|[^\p{Word};:"'`}])(?:\[...\])?`(\S|\S.*?\S)`(?![\p{Word}"'`])
            "(^|[^$ccWord;:\"'`}])(?:$quoteAttributeListRxt)?`(\\S|\\S$ccAll*?\\S)`(?![$ccWord\"'`])",
            // Ruby: \\?(?:\[([^\[\]]+)\])?__(.+?)__
            '\\\\?(?:$quoteAttributeListRxt)?__($ccAll+?)__',
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?_(\S|\S.*?\S)_(?!\p{Word}),
            // also after a curved quote's reference (bugfix #2128)
            '(^|&#82(?:16|20);|[^$ccWord;:}])(?:$quoteAttributeListRxt)?_(\\S|\\S$ccAll*?\\S)_(?!$cgWord)',
            // Ruby: \\?(?:\[([^\[\]]+)\])?##(.+?)##
            '\\\\?(?:$quoteAttributeListRxt)?##($ccAll+?)##',
            // Ruby: (^|[^\p{Word}&;:}])(?:\[...\])?#(\S|\S.*?\S)#(?!\p{Word})
            '(^|[^$ccWord&;:}])(?:$quoteAttributeListRxt)?#(\\S|\\S$ccAll*?\\S)#(?!$cgWord)',
            // Ruby: \\?(?:\[([^\[\]]+)\])?\^(\S+?)\^, with a bracketed
            // span as one unit (bugfix #4076)
            '\\\\?(?:$quoteAttributeListRxt)?\\^((?:\\[[^ \\t\\n\\v\\f\\r\\]]*\\]|\\S)+?)\\^',
            // Ruby: \\?(?:\[([^\[\]]+)\])?~(\S+?)~, likewise
            '\\\\?(?:$quoteAttributeListRxt)?~((?:\\[[^ \\t\\n\\v\\f\\r\\]]*\\]|\\S)+?)~',
          ].map(asciiSpace),
        ),
      );
    });

    test('compat patterns match the Ruby sources with rewrites applied', () {
      final compat = quoteSubs[true]!;
      final patterns = compat.map((q) => q.pattern.pattern).toList();
      // Shared entries reuse the normal patterns verbatim.
      expect(patterns[0], equals(quoteSubs[false]![0].pattern.pattern));
      expect(patterns[1], equals(quoteSubs[false]![1].pattern.pattern));
      expect(
        patterns.sublist(7),
        equals(quoteSubs[false]!.sublist(6).map((q) => q.pattern.pattern)),
      );
      expect(
        patterns.sublist(2, 7),
        equals(
          <String>[
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?``(\S|\S.*?\S)''(?!\p{Word})
            "(^|[^$ccWord;:}])(?:$quoteAttributeListRxt)?``(\\S|\\S$ccAll*?\\S)''(?!$cgWord)",
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?'(\S|\S.*?\S)'(?!\p{Word})
            "(^|[^$ccWord;:}])(?:$quoteAttributeListRxt)?'(\\S|\\S$ccAll*?\\S)'(?!$cgWord)",
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?`(\S|\S.*?\S)'(?!\p{Word})
            "(^|[^$ccWord;:}])(?:$quoteAttributeListRxt)?`(\\S|\\S$ccAll*?\\S)'(?!$cgWord)",
            // Ruby: \\?(?:\[([^\[\]]+)\])?\+\+(.+?)\+\+
            '\\\\?(?:$quoteAttributeListRxt)?\\+\\+($ccAll+?)\\+\\+',
            // Ruby: (^|[^\p{Word};:}])(?:\[...\])?\+(\S|\S.*?\S)\+(?!\p{Word})
            '(^|[^$ccWord;:}])(?:$quoteAttributeListRxt)?\\+(\\S|\\S$ccAll*?\\S)\\+(?!$cgWord)',
          ].map(asciiSpace),
        ),
      );
    });

    test('patterns pin the expanded fragments end to end', () {
      // Fully inlined expectations (no fragment interpolation) for one
      // unconstrained rule, one constrained rule and one compat-only rule.
      expect(
        quoteSubs[false]![0].pattern.pattern,
        equals(r'\\?(?:\[([^\[\]]+)\])?\*\*([\s\S]+?)\*\*'),
      );
      expect(
        quoteSubs[false]![1].pattern.pattern,
        equals(
          asciiSpace(
            r'(^|[^\p{Alphabetic}\p{Mark}\p{Decimal_Number}\p{Connector_Punctuation}\p{Join_Control};:}])(?:\[([^\[\]]+)\])?\*(\S|\S[\s\S]*?\S)\*(?!(?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control}))',
          ),
        ),
      );
      expect(
        quoteSubs[true]![3].pattern.pattern,
        equals(
          asciiSpace(
            r"(^|[^\p{Alphabetic}\p{Mark}\p{Decimal_Number}\p{Connector_Punctuation}\p{Join_Control};:}])(?:\[([^\[\]]+)\])?'(\S|\S[\s\S]*?\S)'(?!(?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control}))",
          ),
        ),
      );
    });

    test(
      'patterns carry multiline and unicode flags per PORTING-REGEXP.md',
      () {
        // In Ruby ^ is always line-anchored and /m lets `.` span newlines
        // (handled via `[\s\S]`); Dart needs multiLine for ^ and unicode for
        // \p{...} (rules B9/R3, B1/R1/R2).
        final normal = quoteSubs[false]!.map((q) => q.pattern).toList();
        final normalFlags = <List<bool>>[
          [false, false],
          [true, true],
          [true, true],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [false, false],
        ];
        for (var i = 0; i < normal.length; i++) {
          expect(
            normal[i].isMultiLine,
            equals(normalFlags[i][0]),
            reason: 'normal[$i]',
          );
          expect(
            normal[i].isUnicode,
            equals(normalFlags[i][1]),
            reason: 'normal[$i]',
          );
        }
        final compat = quoteSubs[true]!.map((q) => q.pattern).toList();
        final compatFlags = <List<bool>>[
          [false, false],
          [true, true],
          [true, true],
          [true, true],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [true, true],
          [false, false],
          [false, false],
        ];
        for (var i = 0; i < compat.length; i++) {
          expect(
            compat[i].isMultiLine,
            equals(compatFlags[i][0]),
            reason: 'compat[$i]',
          );
          expect(
            compat[i].isUnicode,
            equals(compatFlags[i][1]),
            reason: 'compat[$i]',
          );
        }
      },
    );

    test('rules match the Ruby behavior probe captures', () {
      // Probe: behavior probe (Q0, Q1, Q2, Q5, C2, C3, MULTI).
      List<String?> groups(RegExp rx, String input) {
        final m = rx.firstMatch(input)!;
        return List<String?>.generate(m.groupCount, (i) => m.group(i + 1));
      }

      final normal = quoteSubs[false]!;
      expect(
        groups(normal[0].pattern, '**bold**'),
        equals(<String?>[null, 'bold']),
      );
      expect(
        groups(normal[1].pattern, 'a *b* c'),
        equals(<String?>[' ', null, 'b']),
      );
      expect(
        groups(normal[2].pattern, 'say "`hi`"!'),
        equals(<String?>[' ', null, 'hi']),
      );
      expect(
        groups(normal[5].pattern, '`x`'),
        equals(<String?>['', null, 'x']),
      );
      expect(
        groups(normal[1].pattern, 'l1\n*x*\n'),
        equals(<String?>['\n', null, 'x']),
      );

      final compat = quoteSubs[true]!;
      expect(
        groups(compat[2].pattern, "``hi''"),
        equals(<String?>['', null, 'hi']),
      );
      expect(
        groups(compat[3].pattern, "say 'em' now"),
        equals(<String?>[' ', null, 'em']),
      );
    });
  });

  group('replacements', () {
    // Probe for this group: table dump (REPLACEMENTS, 13 entries with
    // Regexp#source, replacement string and scope).

    test('holds thirteen rules in Ruby order', () {
      expect(replacements, hasLength(13));
      expect(
        replacements.map((r) => '${r.replacement}:${r.scope}'),
        equals(<String>[
          '&#169;:none',
          '&#174;:none',
          '&#8482;:none',
          '&#8201;&#8212;&#8201;:none',
          '&#8212;&#8203;:leading',
          '&#8230;&#8203;:none',
          '&#8217;:none',
          '&#8217;:leading',
          '&#8594;:none',
          '&#8658;:none',
          '&#8592;:none',
          '&#8656;:none',
          ':bounding',
        ]),
      );
    });

    test('patterns match the Ruby sources with rewrites applied', () {
      expect(
        replacements.map((r) => r.pattern.pattern),
        equals(<String>[
          // Ruby: \\?\(C\)
          r'\\?\(C\)',
          // Ruby: \\?\(R\)
          r'\\?\(R\)',
          // Ruby: \\?\(TM\)
          r'\\?\(TM\)',
          // Ruby: (?: |\n|^|\\)--(?: |\n|$)
          r'(?: |\n|^|\\)--(?: |\n|$)',
          // Ruby: (\p{Word})\\?--(?=\p{Word}), with formatted text and
          // curved quotes as word boundaries (bugfix #1578, #3946)
          '($cgWord|</[^>]+>|&#82(?:17|21);)\\\\?--(?=$cgWord|<[^/!]|&#82(?:16|20);)',
          // Ruby: \\?\.\.\.
          r'\\?\.\.\.',
          // Ruby: \\?`'
          r"\\?`'",
          // Ruby: (\p{Alnum})\\?'(?=\p{Alpha})
          "($cgAlnum)\\\\?'(?=$cgAlpha)",
          // Ruby: \\?-&gt;
          r'\\?-&gt;',
          // Ruby: \\?=&gt;
          r'\\?=&gt;',
          // Ruby: \\?&lt;-
          r'\\?&lt;-',
          // Ruby: \\?&lt;=
          r'\\?&lt;=',
          // Ruby: \\?(&)amp;((?:[a-zA-Z][a-zA-Z]+\d{0,2}|#\d\d\d{0,4}|
          //   #x[\da-fA-F][\da-fA-F][\da-fA-F]{0,3});)
          r'\\?(&)amp;((?:[a-zA-Z][a-zA-Z]+\d{0,2}|#\d\d\d{0,4}|#x[\da-fA-F][\da-fA-F][\da-fA-F]{0,3});)',
        ]),
      );
    });

    test('word-boundary patterns pin the expanded fragments end to end', () {
      expect(
        replacements[4].pattern.pattern,
        equals(
          r'((?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control})|</[^>]+>|&#82(?:17|21);)\\?--(?=(?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control})|<[^/!]|&#82(?:16|20);)',
        ),
      );
      expect(
        replacements[7].pattern.pattern,
        equals(
          r"((?:\p{Alphabetic}|\p{Decimal_Number}))\\?'(?=\p{Alphabetic})",
        ),
      );
    });

    test(
      'patterns carry multiline and unicode flags per PORTING-REGEXP.md',
      () {
        for (var i = 0; i < replacements.length; i++) {
          final pattern = replacements[i].pattern;
          expect(
            pattern.isMultiLine,
            equals(i == 3),
            reason: 'replacements[$i]',
          );
          expect(
            pattern.isUnicode,
            equals(i == 4 || i == 7),
            reason: 'replacements[$i]',
          );
        }
      },
    );

    test('rules rewrite the Ruby behavior probe inputs identically', () {
      // Probe: behavior probe (R3, R5, R8).
      String apply(int i, String input) => input.replaceAll(
        replacements[i].pattern,
        replacements[i].replacement,
      );
      expect(apply(3, 'foo -- bar'), equals('foo&#8201;&#8212;&#8201;bar'));
      expect(apply(5, 'wait...'), equals('wait&#8230;&#8203;'));
      expect(apply(8, 'a -&gt; b'), equals('a &#8594; b'));
      expect(apply(0, '(C) 2024'), equals('&#169; 2024'));
    });
  });

  group('rule guards', () {
    // The substitutors skip a rule whose guard is absent from the text, so
    // every match a rule can make must contain its guard. Check that over
    // the fixture corpus (raw and XML-escaped, since replacements see
    // escaped text) plus hand-picked edge cases.
    final corpus = <String>[
      for (final file in Directory(
        'vendor/asciidoctor/test/fixtures',
      ).listSync(recursive: true))
        if (file is File && file.path.endsWith('.adoc'))
          file.readAsStringSync(),
      File('vendor/asciidoctor/data/reference/syntax.adoc').readAsStringSync(),
      File('vendor/asciidoctor/benchmark/sample-data/mdbasics.adoc')
          .readAsStringSync(),
      r'\**x** [role]*x* *x* "`x`" ',
      "'`x`' ``x`` `x` __x__ _x_ ##x## #x# ^x^ ~x~ ++x++ +x+ ``x'' 'x'",
      r'a <- b <= c => d -> e \(C) (R) (TM) a -- b a--b \... `',
      r"it's `' it\'s",
      r'\-&gt; &amp;amp;',
    ];
    final texts = [
      ...corpus,
      for (final text in corpus)
        text
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;'),
    ];

    void checkGuard(
      String name,
      RegExp pattern,
      bool Function(String match) admits,
    ) {
      var matched = 0;
      for (final text in texts) {
        for (final match in pattern.allMatches(text)) {
          matched++;
          expect(admits(match.group(0)!), isTrue, reason: '$name: $match');
        }
      }
      expect(matched, greaterThan(0), reason: '$name never matched');
    }

    test('every quote match has its opening then closing delimiter', () {
      for (final compat in [false, true]) {
        for (final (i, sub) in quoteSubs[compat]!.indexed) {
          checkGuard('quoteSubs[$compat][$i]', sub.pattern, sub.mayMatch);
        }
      }
    });

    test('every replacement match contains its guard', () {
      for (final (i, rule) in replacements.indexed) {
        checkGuard(
          'replacements[$i]',
          rule.pattern,
          (match) => match.contains(rule.guard),
        );
      }
    });

    test('mayMatch needs the closing delimiter after the opening one', () {
      final strong = quoteSubs[false]![1];
      expect(strong.mayMatch('a * b'), isFalse);
      expect(strong.mayMatch('*x*'), isTrue);
      final doubleQuote = quoteSubs[false]![2];
      expect(doubleQuote.mayMatch('`" then "`'), isFalse);
      expect(doubleQuote.mayMatch('"`x`"'), isTrue);
    });
  });

  group('Compliance', () {
    test('holds the Ruby default values', () {
      // Probe: attribute dump (Compliance.keys values in order).
      expect(Compliance.blockTerminatesParagraph, isTrue);
      expect(Compliance.strictVerbatimParagraphs, isTrue);
      expect(Compliance.underlineStyleSectionTitles, isTrue);
      expect(Compliance.unwrapStandalonePreamble, isTrue);
      expect(Compliance.attributeMissing, equals('skip'));
      expect(Compliance.attributeUndefined, equals('drop-line'));
      expect(Compliance.shorthandPropertySyntax, isTrue);
      expect(Compliance.naturalXrefs, isTrue);
      expect(Compliance.uniqueIdStartIndex, equals(2));
      expect(Compliance.markdownSyntax, isTrue);
    });

    test('keys lists the ten key names in definition order', () {
      // Probe: attribute dump (KEYS=[:block_terminates_paragraph, ...]).
      expect(
        Compliance.keys,
        equals(<String>{
          'block_terminates_paragraph',
          'strict_verbatim_paragraphs',
          'underline_style_section_titles',
          'unwrap_standalone_preamble',
          'attribute_missing',
          'attribute_undefined',
          'shorthand_property_syntax',
          'natural_xrefs',
          'unique_id_start_index',
          'markdown_syntax',
        }),
      );
    });
  });
}
