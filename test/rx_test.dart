import 'package:asciidoctor/src/rx.dart';
import 'package:test/test.dart';

/// Returns `[fullMatch, group1, ...]` for the first match of [rx] in
/// [input], or `null` when there is no match.
///
/// Every expectation below was observed by running the same input
/// against the real Ruby pattern (`ruby -Ilib -rasciidoctor -e`), except
/// [inlineLinkRx], whose opal branch was observed in Node (same
/// JS-semantics engine family as Dart), and the noted B2/R5 opal cases.
List<String?>? groupsOf(RegExp rx, String input) {
  final m = rx.firstMatch(input);
  if (m == null) return null;
  return [for (var i = 0; i <= m.groupCount; i++) m.group(i)];
}

void main() {
  group('document header', () {
    test('authorInfoLineRx', () {
      expect(groupsOf(authorInfoLineRx, 'Doc Writer <doc@example.com>'), [
        'Doc Writer <doc@example.com>',
        'Doc',
        'Writer',
        null,
        'doc@example.com',
      ]);
      expect(groupsOf(authorInfoLineRx, 'Mary_Sue Brontë'), [
        'Mary_Sue Brontë',
        'Mary_Sue',
        'Brontë',
        null,
        null,
      ]);
      expect(groupsOf(authorInfoLineRx, 'Joe'), [
        'Joe',
        'Joe',
        null,
        null,
        null,
      ]);
      expect(groupsOf(authorInfoLineRx, 'A B C <a@b.c>'), [
        'A B C <a@b.c>',
        'A',
        'B',
        'C',
        'a@b.c',
      ]);
      // \p{Word} includes digits, so a leading digit still matches.
      expect(groupsOf(authorInfoLineRx, '1Joe'), [
        '1Joe',
        '1Joe',
        null,
        null,
        null,
      ]);
      expect(groupsOf(authorInfoLineRx, ''), isNull);
      expect(groupsOf(authorInfoLineRx, 'Joe Xtra Person Here <a@b>'), isNull);
    });

    test('authorDelimiterRx', () {
      expect(groupsOf(authorDelimiterRx, 'a; b'), ['; ']);
      expect(groupsOf(authorDelimiterRx, 'a;b'), isNull);
      expect(groupsOf(authorDelimiterRx, 'a;'), [';']);
    });

    test('revisionInfoLineRx', () {
      expect(groupsOf(revisionInfoLineRx, 'v1.0'), [
        'v1.0',
        null,
        'v1.0',
        null,
      ]);
      expect(groupsOf(revisionInfoLineRx, '2013-01-01'), [
        '2013-01-01',
        null,
        '2013-01-01',
        null,
      ]);
      expect(
        groupsOf(
          revisionInfoLineRx,
          'v1.0, 2013-01-01: Ring in the new year release',
        ),
        [
          'v1.0, 2013-01-01: Ring in the new year release',
          '1.0',
          '2013-01-01',
          'Ring in the new year release',
        ],
      );
      expect(groupsOf(revisionInfoLineRx, '1.0, Jan 01, 2013'), [
        '1.0, Jan 01, 2013',
        '1.0',
        'Jan 01, 2013',
        null,
      ]);
      expect(groupsOf(revisionInfoLineRx, ': foo'), isNull);
    });

    test('manpageTitleVolnumRx', () {
      expect(groupsOf(manpageTitleVolnumRx, 'asciidoctor(1)'), [
        'asciidoctor(1)',
        'asciidoctor',
        '1',
      ]);
      expect(groupsOf(manpageTitleVolnumRx, 'asciidoctor ( 1 )'), [
        'asciidoctor ( 1 )',
        'asciidoctor',
        '1',
      ]);
      expect(groupsOf(manpageTitleVolnumRx, 'foo'), isNull);
    });

    test('manpageNamePurposeRx', () {
      expect(groupsOf(manpageNamePurposeRx, 'asciidoctor - converts stuff'), [
        'asciidoctor - converts stuff',
        'asciidoctor',
        'converts stuff',
      ]);
      expect(groupsOf(manpageNamePurposeRx, 'a-b'), isNull);
      expect(groupsOf(manpageNamePurposeRx, 'a - b - c'), [
        'a - b - c',
        'a',
        'b - c',
      ]);
    });
  });

  group('preprocessor directives', () {
    test('conditionalDirectiveRx', () {
      expect(groupsOf(conditionalDirectiveRx, 'ifdef::foo[]'), [
        'ifdef::foo[]',
        null,
        'ifdef',
        'foo',
        null,
        null,
      ]);
      expect(groupsOf(conditionalDirectiveRx, r'\ifdef::foo[]'), [
        r'\ifdef::foo[]',
        r'\',
        'ifdef',
        'foo',
        null,
        null,
      ]);
      expect(groupsOf(conditionalDirectiveRx, 'ifeval::["{v}" >= "0.1.0"]'), [
        'ifeval::["{v}" >= "0.1.0"]',
        null,
        'ifeval',
        '',
        null,
        '"{v}" >= "0.1.0"',
      ]);
      expect(groupsOf(conditionalDirectiveRx, 'endif::[]'), [
        'endif::[]',
        null,
        'endif',
        '',
        null,
        null,
      ]);
      expect(groupsOf(conditionalDirectiveRx, 'endif::a+b[]'), [
        'endif::a+b[]',
        null,
        'endif',
        'a+b',
        '+',
        null,
      ]);
      expect(groupsOf(conditionalDirectiveRx, 'ifdef::foo[bar]'), [
        'ifdef::foo[bar]',
        null,
        'ifdef',
        'foo',
        null,
        'bar',
      ]);
      expect(groupsOf(conditionalDirectiveRx, 'ifdef:foo[]'), isNull);
    });

    test('evalExpressionRx', () {
      expect(groupsOf(evalExpressionRx, '"{v}" >= "0.1.0"'), [
        '"{v}" >= "0.1.0"',
        '"{v}"',
        '>=',
        '"0.1.0"',
      ]);
      expect(groupsOf(evalExpressionRx, 'a == b'), ['a == b', 'a', '==', 'b']);
      expect(groupsOf(evalExpressionRx, 'a=b'), isNull);
      expect(groupsOf(evalExpressionRx, 'a = b'), isNull);
      expect(groupsOf(evalExpressionRx, 'a != b'), ['a != b', 'a', '!=', 'b']);
      expect(groupsOf(evalExpressionRx, 'a < b'), ['a < b', 'a', '<', 'b']);
    });

    test('includeDirectiveRx', () {
      expect(groupsOf(includeDirectiveRx, 'include::chapter1.ad[]'), [
        'include::chapter1.ad[]',
        null,
        'chapter1.ad',
        null,
      ]);
      expect(groupsOf(includeDirectiveRx, 'include::example.txt[lines=1]'), [
        'include::example.txt[lines=1]',
        null,
        'example.txt',
        'lines=1',
      ]);
      expect(groupsOf(includeDirectiveRx, r'\include::x[]'), [
        r'\include::x[]',
        r'\',
        'x',
        null,
      ]);
      expect(groupsOf(includeDirectiveRx, 'include::a b[]'), [
        'include::a b[]',
        null,
        'a b',
        null,
      ]);
      expect(groupsOf(includeDirectiveRx, 'include::[]'), isNull);
      expect(groupsOf(includeDirectiveRx, 'include::a['), isNull);
    });

    test('tagDirectiveRx', () {
      expect(groupsOf(tagDirectiveRx, '// tag::try-catch[]'), [
        'tag::try-catch[]',
        null,
        'try-catch',
      ]);
      expect(groupsOf(tagDirectiveRx, '// end::try-catch[]'), [
        'end::try-catch[]',
        'e',
        'try-catch',
      ]);
      expect(groupsOf(tagDirectiveRx, 'xtag::foo[]'), isNull);
      // multiLine: matches on a later line.
      expect(groupsOf(tagDirectiveRx, 'a\n// end::x[] trailing'), [
        'end::x[]',
        'e',
        'x',
      ]);
    });
  });

  group('attribute entries and references', () {
    test('attributeEntryRx', () {
      expect(groupsOf(attributeEntryRx, ':foo: bar'), [
        ':foo: bar',
        'foo',
        'bar',
      ]);
      expect(groupsOf(attributeEntryRx, ':First Name: Dan'), [
        ':First Name: Dan',
        'First Name',
        'Dan',
      ]);
      expect(groupsOf(attributeEntryRx, ':sectnums!:'), [
        ':sectnums!:',
        'sectnums!',
        null,
      ]);
      expect(groupsOf(attributeEntryRx, ':!toc:'), [':!toc:', '!toc', null]);
      expect(groupsOf(attributeEntryRx, ':foo:'), [':foo:', 'foo', null]);
      expect(groupsOf(attributeEntryRx, ':foo:  spaced  '), [
        ':foo:  spaced  ',
        'foo',
        'spaced  ',
      ]);
      expect(groupsOf(attributeEntryRx, 'foo: bar'), isNull);
      expect(groupsOf(attributeEntryRx, ':café: x'), [':café: x', 'café', 'x']);
    });

    test('invalidAttributeNameCharsRx', () {
      expect(groupsOf(invalidAttributeNameCharsRx, 'foo'), isNull);
      expect(groupsOf(invalidAttributeNameCharsRx, 'foo bar'), [' ']);
      expect(groupsOf(invalidAttributeNameCharsRx, 'a+b'), ['+']);
      expect(groupsOf(invalidAttributeNameCharsRx, 'café'), isNull);
      // Join controls are word characters in Ruby too (ZWJ/ZWNJ).
      expect(groupsOf(invalidAttributeNameCharsRx, '\u200d'), isNull);
      expect(groupsOf(invalidAttributeNameCharsRx, 'a\u200db'), isNull);
    });

    test('attributeEntryPassMacroRx', () {
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:[text]'), [
        'pass:[text]',
        null,
        'text',
      ]);
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:a[{a}]'), [
        'pass:a[{a}]',
        'a',
        '{a}',
      ]);
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:[a\nb]'), [
        'pass:[a\nb]',
        null,
        'a\nb',
      ]);
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:[x] trailing'), isNull);
      // String-anchored (B2): no match when not the whole string.
      expect(groupsOf(attributeEntryPassMacroRx, 'x\npass:[a]'), isNull);
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:[a]\npass:[b]'), [
        'pass:[a]\npass:[b]',
        null,
        'a]\npass:[b',
      ]);
      // Opal `$` is absolute end (R5); MRI `\Z` would match "pass:[x]".
      expect(groupsOf(attributeEntryPassMacroRx, 'pass:[x]\n'), isNull);
    });

    test('attributeReferenceRx', () {
      expect(groupsOf(attributeReferenceRx, '{foobar}'), [
        '{foobar}',
        null,
        'foobar',
        null,
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, r'\{foobar}'), [
        r'\{foobar}',
        r'\',
        'foobar',
        null,
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, '{set:foo:bar}'), [
        '{set:foo:bar}',
        null,
        'set:foo:bar',
        'set',
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, '{counter:n:1}'), [
        '{counter:n:1}',
        null,
        'counter:n:1',
        'counter',
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, '{counter2:n:1}'), [
        '{counter2:n:1}',
        null,
        'counter2:n:1',
        'counter2',
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, '{set:name!}'), [
        '{set:name!}',
        null,
        'set:name!',
        'set',
        null,
      ]);
      expect(groupsOf(attributeReferenceRx, r'{foo\}'), [
        r'{foo\}',
        null,
        'foo',
        null,
        r'\',
      ]);
      expect(groupsOf(attributeReferenceRx, '{}'), isNull);
      expect(groupsOf(attributeReferenceRx, '{a b}'), isNull);
      expect(groupsOf(attributeReferenceRx, '{café}'), [
        '{café}',
        null,
        'café',
        null,
        null,
      ]);
    });
  });

  group('paragraphs and delimited blocks', () {
    test('blockAnchorRx', () {
      expect(groupsOf(blockAnchorRx, '[[café]]'), ['[[café]]', 'café', null]);
      expect(groupsOf(blockAnchorRx, '[[idname]]'), [
        '[[idname]]',
        'idname',
        null,
      ]);
      expect(groupsOf(blockAnchorRx, '[[idname,Reference Text]]'), [
        '[[idname,Reference Text]]',
        'idname',
        'Reference Text',
      ]);
      expect(groupsOf(blockAnchorRx, '[[]]'), ['[[]]', null, null]);
      expect(groupsOf(blockAnchorRx, '[[1abc]]'), isNull);
      expect(groupsOf(blockAnchorRx, '[[a]]x'), isNull);
    });

    test('blockAttributeListRx', () {
      expect(groupsOf(blockAttributeListRx, '[quote, Adam Smith]'), [
        '[quote, Adam Smith]',
        'quote, Adam Smith',
      ]);
      expect(groupsOf(blockAttributeListRx, '[NOTE]'), ['[NOTE]', 'NOTE']);
      expect(groupsOf(blockAttributeListRx, '[{lead}]'), [
        '[{lead}]',
        '{lead}',
      ]);
      expect(groupsOf(blockAttributeListRx, '[.role]'), ['[.role]', '.role']);
      expect(groupsOf(blockAttributeListRx, '[#id]'), ['[#id]', '#id']);
      expect(groupsOf(blockAttributeListRx, '[%opt]'), ['[%opt]', '%opt']);
      expect(groupsOf(blockAttributeListRx, '["a"]'), ['["a"]', '"a"']);
      expect(groupsOf(blockAttributeListRx, '[]'), ['[]', '']);
      expect(groupsOf(blockAttributeListRx, '[a'), isNull);
    });

    test('blockAttributeLineRx', () {
      expect(groupsOf(blockAttributeLineRx, '[[id]]'), ['[[id]]']);
      expect(groupsOf(blockAttributeLineRx, '[quote]'), ['[quote]']);
      expect(groupsOf(blockAttributeLineRx, '[[]]'), ['[[]]']);
      expect(groupsOf(blockAttributeLineRx, '[[1]]'), isNull);
      expect(groupsOf(blockAttributeLineRx, '[]'), ['[]']);
    });

    test('blockTitleRx', () {
      expect(groupsOf(blockTitleRx, '.Title'), ['.Title', 'Title']);
      expect(groupsOf(blockTitleRx, '..Title'), ['..Title', '.Title']);
      expect(groupsOf(blockTitleRx, '. Title'), isNull);
      expect(groupsOf(blockTitleRx, '.'), isNull);
    });

    test('admonitionParagraphRx', () {
      expect(groupsOf(admonitionParagraphRx, 'NOTE: x'), ['NOTE: ', 'NOTE']);
      expect(groupsOf(admonitionParagraphRx, 'TIP:\tx'), ['TIP:\t', 'TIP']);
      expect(groupsOf(admonitionParagraphRx, 'NOTE:x'), isNull);
      expect(groupsOf(admonitionParagraphRx, 'note: x'), isNull);
      expect(groupsOf(admonitionParagraphRx, 'CAUTION: x'), [
        'CAUTION: ',
        'CAUTION',
      ]);
    });

    test('literalParagraphRx', () {
      expect(groupsOf(literalParagraphRx, ' Foo'), [' Foo', ' Foo']);
      expect(groupsOf(literalParagraphRx, '\tFoo'), ['\tFoo', '\tFoo']);
      expect(groupsOf(literalParagraphRx, 'Foo'), isNull);
      expect(groupsOf(literalParagraphRx, ' '), [' ', ' ']);
    });
  });

  group('section titles', () {
    test('atxSectionTitleRx', () {
      expect(groupsOf(atxSectionTitleRx, '== Foo'), ['== Foo', '==', 'Foo']);
      expect(groupsOf(atxSectionTitleRx, '== Foo =='), [
        '== Foo ==',
        '==',
        'Foo',
      ]);
      expect(groupsOf(atxSectionTitleRx, '=== Foo'), ['=== Foo', '===', 'Foo']);
      // `=={0,5}` also accepts one or six markers.
      expect(groupsOf(atxSectionTitleRx, '= Foo'), ['= Foo', '=', 'Foo']);
      expect(groupsOf(atxSectionTitleRx, '==Foo'), isNull);
      expect(groupsOf(atxSectionTitleRx, '====== x'), [
        '====== x',
        '======',
        'x',
      ]);
      expect(groupsOf(atxSectionTitleRx, '== '), isNull);
    });

    test('extAtxSectionTitleRx', () {
      expect(groupsOf(extAtxSectionTitleRx, '## Foo'), ['## Foo', '##', 'Foo']);
      expect(groupsOf(extAtxSectionTitleRx, '## Foo ##'), [
        '## Foo ##',
        '##',
        'Foo',
      ]);
      expect(groupsOf(extAtxSectionTitleRx, '# Foo'), ['# Foo', '#', 'Foo']);
      expect(groupsOf(extAtxSectionTitleRx, '####### x'), isNull);
    });

    test('setextSectionTitleRx', () {
      expect(groupsOf(setextSectionTitleRx, 'Foo'), ['Foo', 'Foo']);
      expect(groupsOf(setextSectionTitleRx, '.Foo'), isNull);
      expect(groupsOf(setextSectionTitleRx, '123'), ['123', '123']);
      expect(groupsOf(setextSectionTitleRx, '!!!'), isNull);
      expect(groupsOf(setextSectionTitleRx, 'Café'), ['Café', 'Café']);
      expect(groupsOf(setextSectionTitleRx, ''), isNull);
    });

    test('inlineSectionAnchorRx', () {
      expect(groupsOf(inlineSectionAnchorRx, 'Title [[id]]'), [
        ' [[id]]',
        null,
        'id',
        null,
      ]);
      expect(groupsOf(inlineSectionAnchorRx, 'Title [[id,Ref]]'), [
        ' [[id,Ref]]',
        null,
        'id',
        'Ref',
      ]);
      expect(groupsOf(inlineSectionAnchorRx, '[[id]]'), isNull);
      expect(groupsOf(inlineSectionAnchorRx, 'Title [[1]]'), isNull);
    });

    test('invalidSectionIdCharsRx', () {
      expect(groupsOf(invalidSectionIdCharsRx, '<b>x</b>'), ['<b>']);
      expect(groupsOf(invalidSectionIdCharsRx, '&amp;'), ['&amp;']);
      expect(groupsOf(invalidSectionIdCharsRx, 'a b'), isNull);
      expect(groupsOf(invalidSectionIdCharsRx, 'a+b'), ['+']);
      expect(groupsOf(invalidSectionIdCharsRx, '&#169;'), ['&#169;']);
      expect(groupsOf(invalidSectionIdCharsRx, '&#x27;'), ['&#x27;']);
      expect(groupsOf(invalidSectionIdCharsRx, 'café'), isNull);
    });

    test('sectionLevelStyleRx', () {
      expect(groupsOf(sectionLevelStyleRx, 'sect1'), ['sect1']);
      expect(groupsOf(sectionLevelStyleRx, 'sect12'), isNull);
      expect(groupsOf(sectionLevelStyleRx, 'sectx'), isNull);
    });
  });

  group('lists', () {
    test('anyListRx', () {
      expect(groupsOf(anyListRx, '* Foo'), ['* ']);
      expect(groupsOf(anyListRx, '- Foo'), ['- ']);
      expect(groupsOf(anyListRx, '. Foo'), ['. ']);
      expect(groupsOf(anyListRx, '1. Foo'), ['1. ']);
      expect(groupsOf(anyListRx, 'a. Foo'), ['a. ']);
      expect(groupsOf(anyListRx, 'i) Foo'), ['i) ']);
      expect(groupsOf(anyListRx, 'a) Foo'), isNull);
      expect(groupsOf(anyListRx, 'foo:: bar'), ['foo:: ']);
      expect(groupsOf(anyListRx, 'foo;; bar'), ['foo;; ']);
      expect(groupsOf(anyListRx, '<1> Foo'), ['<1> ']);
      expect(groupsOf(anyListRx, '//comment'), isNull);
      expect(groupsOf(anyListRx, '• Foo'), ['• ']);
      expect(groupsOf(anyListRx, 'plain'), isNull);
    });

    test('unorderedListRx', () {
      expect(groupsOf(unorderedListRx, '* Foo'), ['* Foo', '*', 'Foo']);
      expect(groupsOf(unorderedListRx, '** Foo'), ['** Foo', '**', 'Foo']);
      expect(groupsOf(unorderedListRx, '- Foo'), ['- Foo', '-', 'Foo']);
      expect(groupsOf(unorderedListRx, '• Foo'), ['• Foo', '•', 'Foo']);
      expect(groupsOf(unorderedListRx, '*Foo'), isNull);
      expect(groupsOf(unorderedListRx, '  * Foo'), ['  * Foo', '*', 'Foo']);
    });

    test('orderedListRx', () {
      expect(groupsOf(orderedListRx, '. Foo'), ['. Foo', '.', 'Foo']);
      expect(groupsOf(orderedListRx, '.. Foo'), ['.. Foo', '..', 'Foo']);
      expect(groupsOf(orderedListRx, '1. Foo'), ['1. Foo', '1.', 'Foo']);
      expect(groupsOf(orderedListRx, 'a. Foo'), ['a. Foo', 'a.', 'Foo']);
      expect(groupsOf(orderedListRx, 'A. Foo'), ['A. Foo', 'A.', 'Foo']);
      expect(groupsOf(orderedListRx, 'i) Foo'), ['i) Foo', 'i)', 'Foo']);
      expect(groupsOf(orderedListRx, 'I) Foo'), ['I) Foo', 'I)', 'Foo']);
      expect(groupsOf(orderedListRx, 'iv) Foo'), ['iv) Foo', 'iv)', 'Foo']);
      expect(groupsOf(orderedListRx, '1) Foo'), isNull);
      expect(groupsOf(orderedListRx, 'a) Foo'), isNull);
    });

    test('orderedListMarkerRxMap', () {
      expect(groupsOf(orderedListMarkerRxMap['arabic']!, '1.'), ['1.']);
      expect(groupsOf(orderedListMarkerRxMap['arabic']!, 'a.'), isNull);
      expect(groupsOf(orderedListMarkerRxMap['loweralpha']!, 'a.'), ['a.']);
      expect(groupsOf(orderedListMarkerRxMap['loweralpha']!, 'A.'), isNull);
      expect(groupsOf(orderedListMarkerRxMap['lowerroman']!, 'iv.'), isNull);
      expect(groupsOf(orderedListMarkerRxMap['lowerroman']!, 'iv)'), ['iv)']);
      expect(groupsOf(orderedListMarkerRxMap['lowerroman']!, 'IV)'), isNull);
      expect(groupsOf(orderedListMarkerRxMap['upperalpha']!, 'A.'), ['A.']);
      expect(groupsOf(orderedListMarkerRxMap['upperroman']!, 'IV)'), ['IV)']);
      expect(groupsOf(orderedListMarkerRxMap['upperroman']!, 'iv)'), isNull);
    });

    test('descriptionListRx', () {
      expect(groupsOf(descriptionListRx, 'foo::'), [
        'foo::',
        'foo',
        '::',
        null,
      ]);
      expect(groupsOf(descriptionListRx, 'foo:: bar'), [
        'foo:: bar',
        'foo',
        '::',
        'bar',
      ]);
      expect(groupsOf(descriptionListRx, 'foo::: bar'), [
        'foo::: bar',
        'foo',
        ':::',
        'bar',
      ]);
      expect(groupsOf(descriptionListRx, 'foo:::: bar'), [
        'foo:::: bar',
        'foo',
        '::::',
        'bar',
      ]);
      expect(groupsOf(descriptionListRx, 'foo;; bar'), [
        'foo;; bar',
        'foo',
        ';;',
        'bar',
      ]);
      expect(groupsOf(descriptionListRx, '// foo:: bar'), isNull);
      expect(groupsOf(descriptionListRx, '::'), isNull);
    });

    test('descriptionListSiblingRx', () {
      expect(groupsOf(descriptionListSiblingRx['::']!, 'foo:: bar'), [
        'foo:: bar',
        'foo',
        '::',
        'bar',
      ]);
      expect(groupsOf(descriptionListSiblingRx['::']!, 'foo::: bar'), isNull);
      expect(groupsOf(descriptionListSiblingRx[':::']!, 'foo::: bar'), [
        'foo::: bar',
        'foo',
        ':::',
        'bar',
      ]);
      expect(groupsOf(descriptionListSiblingRx['::::']!, 'foo:::: bar'), [
        'foo:::: bar',
        'foo',
        '::::',
        'bar',
      ]);
      expect(groupsOf(descriptionListSiblingRx['::::']!, 'foo:: bar'), isNull);
      expect(groupsOf(descriptionListSiblingRx[';;']!, 'foo;; bar'), [
        'foo;; bar',
        'foo',
        ';;',
        'bar',
      ]);
      expect(groupsOf(descriptionListSiblingRx[';;']!, 'foo:: bar'), isNull);
    });

    test('calloutListRx', () {
      expect(groupsOf(calloutListRx, '<1> Foo'), ['<1> Foo', '1', 'Foo']);
      expect(groupsOf(calloutListRx, '<.> Foo'), ['<.> Foo', '.', 'Foo']);
      expect(groupsOf(calloutListRx, '<1>Foo'), isNull);
      expect(groupsOf(calloutListRx, '<a> Foo'), isNull);
    });

    test('calloutExtractRx', () {
      expect(groupsOf(calloutExtractRx, 'foo <1>'), [
        '<1>',
        null,
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRx, '// <1>'), [
        '// <1>',
        '// ',
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRx, '# <2>'), [
        '# <2>',
        '# ',
        null,
        '',
        '2',
      ]);
      expect(groupsOf(calloutExtractRx, '-- <3>'), [
        '-- <3>',
        '-- ',
        null,
        '',
        '3',
      ]);
      expect(groupsOf(calloutExtractRx, ';; <4>'), [
        ';; <4>',
        ';; ',
        null,
        '',
        '4',
      ]);
      expect(groupsOf(calloutExtractRx, '<!--1-->'), [
        '<!--1-->',
        null,
        null,
        '--',
        '1',
      ]);
      expect(groupsOf(calloutExtractRx, '<.>'), ['<.>', null, null, '', '.']);
      expect(groupsOf(calloutExtractRx, r'\<1>'), [
        r'\<1>',
        null,
        r'\',
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRx, 'x <1> y'), isNull);
      expect(groupsOf(calloutExtractRx, '<1> <2>'), [
        '<1>',
        null,
        null,
        '',
        '1',
      ]);
    });

    test('calloutExtractRxt and calloutExtractRxMap', () {
      expect(
        calloutExtractRxt,
        r'(\\)?<()(\d+|\.)>(?=(?: ?\\?<(?:\d+|\.)>)*$)',
      );
      expect(
        calloutExtractRxMap['//'].pattern,
        r'(// ?)?(\\)?<()(\d+|\.)>(?=(?: ?\\?<(?:\d+|\.)>)*$)',
      );
      expect(groupsOf(calloutExtractRxMap['//'], 'x // <1>'), [
        '// <1>',
        '// ',
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRxMap['//'], 'x <1>'), [
        '<1>',
        null,
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRxMap[''], '<1>'), [
        '<1>',
        '',
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutExtractRxMap['#'], 'x # <2>'), [
        '# <2>',
        '# ',
        null,
        '',
        '2',
      ]);
      expect(groupsOf(calloutExtractRxMap['#'], 'x <2>'), [
        '<2>',
        null,
        null,
        '',
        '2',
      ]);
      expect(groupsOf(calloutExtractRxMap['--'], 'x -- <3>'), [
        '-- <3>',
        '-- ',
        null,
        '',
        '3',
      ]);
      expect(groupsOf(calloutExtractRxMap[';;'], 'x ;; <4>'), [
        ';; <4>',
        ';; ',
        null,
        '',
        '4',
      ]);
      // Cached like the Ruby default-proc Hash.
      expect(
        identical(calloutExtractRxMap['//'], calloutExtractRxMap['//']),
        isTrue,
      );
    });

    test('calloutScanRx', () {
      expect(groupsOf(calloutScanRx, 'a <1>'), ['<1>', '', '1']);
      expect(groupsOf(calloutScanRx, r'\<1>'), [r'\<1>', '', '1']);
      expect(groupsOf(calloutScanRx, 'a <1> b'), isNull);
      expect(
        calloutScanRx
            .allMatches('a <1> <2>')
            .map((m) => [m.group(0), m.group(1), m.group(2)])
            .toList(),
        [
          ['<1>', '', '1'],
          ['<2>', '', '2'],
        ],
      );
      expect(calloutScanRx.allMatches('a <!--1--> b'), isEmpty);
    });

    test('calloutSourceRx', () {
      expect(groupsOf(calloutSourceRx, 'foo &lt;1&gt;'), [
        '&lt;1&gt;',
        null,
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutSourceRx, '// &lt;1&gt;'), [
        '// &lt;1&gt;',
        '// ',
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutSourceRx, 'x &lt;1&gt; y'), isNull);
    });

    test('calloutSourceRxt and calloutSourceRxMap', () {
      expect(
        calloutSourceRxt,
        r'(\\)?&lt;()(\d+|\.)&gt;(?=(?: ?\\?&lt;(?:\d+|\.)&gt;)*$)',
      );
      expect(groupsOf(calloutSourceRxMap['#'], 'x # &lt;2&gt;'), [
        '# &lt;2&gt;',
        '# ',
        null,
        '',
        '2',
      ]);
      expect(groupsOf(calloutSourceRxMap[''], '&lt;1&gt;'), [
        '&lt;1&gt;',
        '',
        null,
        '',
        '1',
      ]);
      expect(groupsOf(calloutSourceRxMap[';;'], 'x ;; &lt;4&gt;'), [
        ';; &lt;4&gt;',
        ';; ',
        null,
        '',
        '4',
      ]);
      expect(
        identical(calloutSourceRxMap['#'], calloutSourceRxMap['#']),
        isTrue,
      );
    });

    test('listRxMap', () {
      expect(identical(listRxMap['ulist'], unorderedListRx), isTrue);
      expect(identical(listRxMap['olist'], orderedListRx), isTrue);
      expect(identical(listRxMap['dlist'], descriptionListRx), isTrue);
      expect(identical(listRxMap['colist'], calloutListRx), isTrue);
    });
  });

  group('tables', () {
    test('columnSpecRx', () {
      expect(groupsOf(columnSpecRx, '1*h'), ['1*h', '1', null, null, 'h']);
      expect(groupsOf(columnSpecRx, '2*'), ['2*', '2', null, null, null]);
      expect(groupsOf(columnSpecRx, '^3e'), ['^3e', null, '^', '3', 'e']);
      expect(groupsOf(columnSpecRx, '3'), ['3', null, null, '3', null]);
      expect(groupsOf(columnSpecRx, 'h'), ['h', null, null, null, 'h']);
      expect(groupsOf(columnSpecRx, '~'), ['~', null, null, '~', null]);
      expect(groupsOf(columnSpecRx, '1*^h'), ['1*^h', '1', '^', null, 'h']);
      expect(groupsOf(columnSpecRx, '12'), ['12', null, null, '12', null]);
      expect(groupsOf(columnSpecRx, '25%'), ['25%', null, null, '25%', null]);
      expect(groupsOf(columnSpecRx, ''), ['', null, null, null, null]);
      expect(groupsOf(columnSpecRx, '1x2'), isNull);
    });

    test('cellSpecStartRx', () {
      expect(groupsOf(cellSpecStartRx, '2.3+<.>m'), [
        '2.3+<.>m',
        '2.3',
        '+',
        '<.>',
        'm',
      ]);
      expect(groupsOf(cellSpecStartRx, 'h'), ['h', null, null, null, 'h']);
      expect(groupsOf(cellSpecStartRx, '>'), ['>', null, null, '>', null]);
      expect(groupsOf(cellSpecStartRx, '2*'), ['2*', '2', '*', null, null]);
      expect(groupsOf(cellSpecStartRx, ''), ['', null, null, null, null]);
      expect(groupsOf(cellSpecStartRx, ' '), [' ', null, null, null, null]);
      expect(groupsOf(cellSpecStartRx, '2x'), isNull);
    });

    test('cellSpecEndRx', () {
      expect(groupsOf(cellSpecEndRx, ' h'), [' h', null, null, null, 'h']);
      expect(groupsOf(cellSpecEndRx, ' 2*'), [' 2*', '2', '*', null, null]);
      expect(groupsOf(cellSpecEndRx, 'x h'), [' h', null, null, null, 'h']);
      expect(groupsOf(cellSpecEndRx, 'h'), isNull);
    });
  });

  group('block macros', () {
    test('customBlockMacroRx', () {
      expect(groupsOf(customBlockMacroRx, 'gist::123456[]'), [
        'gist::123456[]',
        'gist',
        '123456',
        null,
      ]);
      expect(groupsOf(customBlockMacroRx, 'gist::123[attrs]'), [
        'gist::123[attrs]',
        'gist',
        '123',
        'attrs',
      ]);
      expect(groupsOf(customBlockMacroRx, 'name::[x]'), [
        'name::[x]',
        'name',
        '',
        'x',
      ]);
      expect(groupsOf(customBlockMacroRx, 'FOO::a[]'), [
        'FOO::a[]',
        'FOO',
        'a',
        null,
      ]);
      expect(groupsOf(customBlockMacroRx, '9foo::a[]'), [
        '9foo::a[]',
        '9foo',
        'a',
        null,
      ]);
      expect(groupsOf(customBlockMacroRx, '-foo::a[]'), isNull);
      expect(groupsOf(customBlockMacroRx, 'foo:bar[]'), isNull);
      expect(groupsOf(customBlockMacroRx, 'foo::a b[]'), [
        'foo::a b[]',
        'foo',
        'a b',
        null,
      ]);
      expect(groupsOf(customBlockMacroRx, 'café::a[]'), [
        'café::a[]',
        'café',
        'a',
        null,
      ]);
    });

    test('blockMediaMacroRx', () {
      expect(groupsOf(blockMediaMacroRx, 'image::a.png[Alt]'), [
        'image::a.png[Alt]',
        'image',
        'a.png',
        'Alt',
      ]);
      expect(groupsOf(blockMediaMacroRx, 'video::http://x[y]'), [
        'video::http://x[y]',
        'video',
        'http://x',
        'y',
      ]);
      expect(groupsOf(blockMediaMacroRx, 'audio::a.mp3[]'), [
        'audio::a.mp3[]',
        'audio',
        'a.mp3',
        null,
      ]);
      expect(groupsOf(blockMediaMacroRx, 'photo::a[]'), isNull);
    });

    test('blockTocMacroRx', () {
      expect(groupsOf(blockTocMacroRx, 'toc::[]'), ['toc::[]', null]);
      expect(groupsOf(blockTocMacroRx, 'toc::[levels=2]'), [
        'toc::[levels=2]',
        'levels=2',
      ]);
      expect(groupsOf(blockTocMacroRx, 'toc::[x'), isNull);
    });
  });

  group('inline macros', () {
    test('inlineAnchorRx', () {
      expect(groupsOf(inlineAnchorRx, '[[id]]'), [
        '[[id]]',
        null,
        'id',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineAnchorRx, '[[id,Ref]]'), [
        '[[id,Ref]]',
        null,
        'id',
        'Ref',
        null,
        null,
      ]);
      expect(groupsOf(inlineAnchorRx, 'anchor:id[]'), [
        'anchor:id[]',
        null,
        null,
        null,
        'id',
        null,
      ]);
      expect(groupsOf(inlineAnchorRx, 'anchor:id[Ref]'), [
        'anchor:id[Ref]',
        null,
        null,
        null,
        'id',
        'Ref',
      ]);
      expect(groupsOf(inlineAnchorRx, r'\[[id]]'), [
        r'\[[id]]',
        r'\',
        'id',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineAnchorRx, '[[1x]]'), isNull);
      expect(groupsOf(inlineAnchorRx, 'a [[i d]] b'), isNull);
    });

    test('inlineAnchorScanRx', () {
      expect(groupsOf(inlineAnchorScanRx, 'a [[id]] b'), [
        ' [[id]]',
        'id',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineAnchorScanRx, '[[id]]'), [
        '[[id]]',
        'id',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineAnchorScanRx, 'x anchor:id[Ref] y'), [
        ' anchor:id[Ref]',
        null,
        null,
        'id',
        'Ref',
      ]);
      expect(groupsOf(inlineAnchorScanRx, 'anchor:id[]'), [
        'anchor:id[]',
        null,
        null,
        'id',
        null,
      ]);
    });

    test('leadingInlineAnchorRx', () {
      expect(groupsOf(leadingInlineAnchorRx, '[[id]]'), ['[[id]]', 'id', null]);
      expect(groupsOf(leadingInlineAnchorRx, '[[id,ref]] rest'), [
        '[[id,ref]]',
        'id',
        'ref',
      ]);
      expect(groupsOf(leadingInlineAnchorRx, ' [[id]]'), isNull);
    });

    test('inlineBiblioAnchorRx', () {
      expect(groupsOf(inlineBiblioAnchorRx, '[[[Fowler_1997]]]'), [
        '[[[Fowler_1997]]]',
        'Fowler_1997',
        null,
      ]);
      expect(groupsOf(inlineBiblioAnchorRx, '[[[a,b]]]'), [
        '[[[a,b]]]',
        'a',
        'b',
      ]);
      expect(groupsOf(inlineBiblioAnchorRx, '[[a]]'), isNull);
    });

    test('inlineEmailRx', () {
      expect(groupsOf(inlineEmailRx, 'doc.writer@example.com'), [
        'doc.writer@example.com',
        null,
      ]);
      expect(groupsOf(inlineEmailRx, 'a@b.co'), ['a@b.co', null]);
      expect(groupsOf(inlineEmailRx, 'x@y.zzzzz'), ['x@y.zzzzz', null]);
      expect(groupsOf(inlineEmailRx, 'a@b.c'), isNull);
      expect(groupsOf(inlineEmailRx, 'a @b.com'), isNull);
      expect(groupsOf(inlineEmailRx, 'Contact a&b@c.de today'), [
        'b@c.de',
        null,
      ]);
      expect(groupsOf(inlineEmailRx, 'write <tom@x.io> now'), [
        'tom@x.io',
        null,
      ]);
      expect(groupsOf(inlineEmailRx, 'josé@x.io'), ['josé@x.io', null]);
    });

    test('inlineFootnoteMacroRx', () {
      expect(groupsOf(inlineFootnoteMacroRx, 'footnote:[text]'), [
        'footnote:[text]',
        null,
        null,
        'text',
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnote:id[text]'), [
        'footnote:id[text]',
        null,
        'id',
        'text',
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnote:id[]'), [
        'footnote:id[]',
        null,
        'id',
        null,
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnoteref:[id,text]'), [
        'footnoteref:[id,text]',
        'ref',
        null,
        'id,text',
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnoteref:[id]'), [
        'footnoteref:[id]',
        'ref',
        null,
        'id',
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnote:[a\nb]'), [
        'footnote:[a\nb]',
        null,
        null,
        'a\nb',
      ]);
      expect(groupsOf(inlineFootnoteMacroRx, 'footnote:[x]</a>'), isNull);
    });

    test('inlineImageMacroRx', () {
      expect(groupsOf(inlineImageMacroRx, 'image:a.png[Alt]'), [
        'image:a.png[Alt]',
        'a.png',
        'Alt',
      ]);
      expect(groupsOf(inlineImageMacroRx, 'icon:gh[large]'), [
        'icon:gh[large]',
        'gh',
        'large',
      ]);
      expect(groupsOf(inlineImageMacroRx, 'image:http://e.com/a.png[Alt]'), [
        'image:http://e.com/a.png[Alt]',
        'http://e.com/a.png',
        'Alt',
      ]);
      expect(groupsOf(inlineImageMacroRx, r'\image:a.png[Alt]'), [
        r'\image:a.png[Alt]',
        'a.png',
        'Alt',
      ]);
      expect(groupsOf(inlineImageMacroRx, 'image:a[b]'), [
        'image:a[b]',
        'a',
        'b',
      ]);
      expect(groupsOf(inlineImageMacroRx, 'image:[x]'), isNull);
      expect(groupsOf(inlineImageMacroRx, 'image:a.png[]'), [
        'image:a.png[]',
        'a.png',
        '',
      ]);
    });

    test('inlineIndextermMacroRx', () {
      expect(groupsOf(inlineIndextermMacroRx, '((Tigers))'), [
        '((Tigers))',
        null,
        null,
        'Tigers',
      ]);
      expect(groupsOf(inlineIndextermMacroRx, '(((Tigers)))'), [
        '(((Tigers)))',
        null,
        null,
        '(Tigers)',
      ]);
      expect(groupsOf(inlineIndextermMacroRx, 'indexterm2:[x]'), [
        'indexterm2:[x]',
        'indexterm2',
        'x',
        null,
      ]);
      expect(groupsOf(inlineIndextermMacroRx, 'indexterm:[x]'), [
        'indexterm:[x]',
        'indexterm',
        'x',
        null,
      ]);
      expect(groupsOf(inlineIndextermMacroRx, '((a\nb))'), [
        '((a\nb))',
        null,
        null,
        'a\nb',
      ]);
    });

    test('inlineKbdBtnMacroRx', () {
      expect(groupsOf(inlineKbdBtnMacroRx, 'kbd:[F3]'), [
        'kbd:[F3]',
        null,
        'kbd',
        'F3',
      ]);
      expect(groupsOf(inlineKbdBtnMacroRx, 'btn:[Save]'), [
        'btn:[Save]',
        null,
        'btn',
        'Save',
      ]);
      expect(groupsOf(inlineKbdBtnMacroRx, r'\kbd:[x]'), [
        r'\kbd:[x]',
        r'\',
        'kbd',
        'x',
      ]);
      expect(groupsOf(inlineKbdBtnMacroRx, 'kbd:[a\nb]'), [
        'kbd:[a\nb]',
        null,
        'kbd',
        'a\nb',
      ]);
      expect(groupsOf(inlineKbdBtnMacroRx, 'key:[x]'), isNull);
    });

    test('inlineLinkRx follows the opal branch', () {
      // Expectations observed in Node against the opal source (rx.rb:525)
      // with the catalog rewrites; the one structural opal-vs-MRI
      // difference is group 2 (":" vs "") on the &lt; path.
      expect(groupsOf(inlineLinkRx, 'https://github.com'), [
        'https://github.com',
        '',
        null,
        'https://',
        null,
        null,
        null,
        'github.com',
        'm',
      ]);
      expect(groupsOf(inlineLinkRx, 'go https://x.io/y?a=b now'), [
        ' https://x.io/y?a=b',
        ' ',
        null,
        'https://',
        null,
        null,
        null,
        'x.io/y?a=b',
        'b',
      ]);
      expect(groupsOf(inlineLinkRx, 'https://x[GitHub]'), [
        'https://x[GitHub]',
        '',
        null,
        'https://',
        'x',
        'GitHub',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineLinkRx, 'link:https://x[]'), [
        'link:https://x[]',
        'link:',
        null,
        'https://',
        'x',
        '',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineLinkRx, '(https://x.io)'), [
        '(https://x.io',
        '(',
        null,
        'https://',
        null,
        null,
        null,
        'x.io',
        'o',
      ]);
      expect(groupsOf(inlineLinkRx, 'see &lt;https://x.io&gt; here'), [
        '&lt;https://x.io&gt;',
        '&lt;',
        ':',
        'https://',
        null,
        null,
        'x.io',
        null,
        null,
      ]);
      // Group-2-unset + trailing entity, no &lt; opener: (?!\2) fails under
      // JS semantics exactly where MRI's \2 fails under Onigmo, so both
      // engines take the generic branch and keep the entity. Expectation
      // observed against the MRI oracle (Asciidoctor::InlineLinkRx).
      expect(groupsOf(inlineLinkRx, 'see https://a&gt; now'), [
        ' https://a&gt;',
        ' ',
        null,
        'https://',
        null,
        null,
        null,
        'a&gt;',
        ';',
      ]);
      expect(groupsOf(inlineLinkRx, '"https://x.io[]"'), [
        '"https://x.io[]',
        '"',
        null,
        'https://',
        'x.io',
        '',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlineLinkRx, 'ftp://f/x'), [
        'ftp://f/x',
        '',
        null,
        'ftp://',
        null,
        null,
        null,
        'f/x',
        'x',
      ]);
      expect(groupsOf(inlineLinkRx, 'https://x.io/a, b'), [
        'https://x.io/a',
        '',
        null,
        'https://',
        null,
        null,
        null,
        'x.io/a',
        'a',
      ]);
      expect(groupsOf(inlineLinkRx, 'no link here'), isNull);
      expect(groupsOf(inlineLinkRx, 'a\nhttps://x.io\nb'), [
        'https://x.io',
        '',
        null,
        'https://',
        null,
        null,
        null,
        'x.io',
        'o',
      ]);
      expect(groupsOf(inlineLinkRx, 'x &lt;https://x.io&gt;'), [
        '&lt;https://x.io&gt;',
        '&lt;',
        ':',
        'https://',
        null,
        null,
        'x.io',
        null,
        null,
      ]);
    });

    test('inlineLinkMacroRx', () {
      expect(groupsOf(inlineLinkMacroRx, 'link:path[label]'), [
        'link:path[label]',
        null,
        'path',
        'label',
      ]);
      expect(groupsOf(inlineLinkMacroRx, 'mailto:a@b[]'), [
        'mailto:a@b[]',
        'mailto',
        'a@b',
        '',
      ]);
      expect(groupsOf(inlineLinkMacroRx, 'link:a[b\nc]'), [
        'link:a[b\nc]',
        null,
        'a',
        'b\nc',
      ]);
      expect(groupsOf(inlineLinkMacroRx, 'link:[x]'), [
        'link:[x]',
        null,
        '',
        'x',
      ]);
      expect(groupsOf(inlineLinkMacroRx, r'\link:a[b]'), [
        r'\link:a[b]',
        null,
        'a',
        'b',
      ]);
    });

    test('macroNameRx', () {
      expect(groupsOf(macroNameRx, 'foo'), ['foo']);
      expect(groupsOf(macroNameRx, 'foo-bar'), ['foo-bar']);
      expect(groupsOf(macroNameRx, '9foo'), ['9foo']);
      expect(groupsOf(macroNameRx, '-foo'), isNull);
      expect(groupsOf(macroNameRx, 'foo bar'), isNull);
      expect(groupsOf(macroNameRx, ''), isNull);
      expect(groupsOf(macroNameRx, 'café'), ['café']);
    });

    test('inlineStemMacroRx', () {
      expect(groupsOf(inlineStemMacroRx, 'stem:[x != 0]'), [
        'stem:[x != 0]',
        'stem',
        null,
        'x != 0',
      ]);
      expect(groupsOf(inlineStemMacroRx, 'asciimath:[x]'), [
        'asciimath:[x]',
        'asciimath',
        null,
        'x',
      ]);
      expect(groupsOf(inlineStemMacroRx, r'latexmath:[\sqrt{4} = 2]'), [
        r'latexmath:[\sqrt{4} = 2]',
        'latexmath',
        null,
        r'\sqrt{4} = 2',
      ]);
      expect(groupsOf(inlineStemMacroRx, 'stem:latin[x]'), [
        'stem:latin[x]',
        'stem',
        'latin',
        'x',
      ]);
      expect(groupsOf(inlineStemMacroRx, 'stem:[]'), isNull);
      expect(groupsOf(inlineStemMacroRx, 'math:[x]'), isNull);
    });

    test('inlineMenuMacroRx', () {
      expect(groupsOf(inlineMenuMacroRx, 'menu:File[Save]'), [
        'menu:File[Save]',
        'File',
        'Save',
      ]);
      expect(groupsOf(inlineMenuMacroRx, 'menu:Edit[]'), [
        'menu:Edit[]',
        'Edit',
        null,
      ]);
      expect(groupsOf(inlineMenuMacroRx, 'menu:View[A > B]'), [
        'menu:View[A > B]',
        'View',
        'A > B',
      ]);
      expect(groupsOf(inlineMenuMacroRx, 'menu:F[]'), ['menu:F[]', 'F', null]);
      expect(groupsOf(inlineMenuMacroRx, 'menu:File[]'), [
        'menu:File[]',
        'File',
        null,
      ]);
      expect(groupsOf(inlineMenuMacroRx, 'menu:[x]'), isNull);
      expect(groupsOf(inlineMenuMacroRx, 'menu:Café[x]'), [
        'menu:Café[x]',
        'Café',
        'x',
      ]);
    });

    test('inlineMenuRx', () {
      expect(groupsOf(inlineMenuRx, '"File &gt; New"'), [
        '"File &gt; New"',
        'File &gt; New',
      ]);
      expect(groupsOf(inlineMenuRx, '"A&gt;B"'), isNull);
      expect(groupsOf(inlineMenuRx, 'File &gt; New'), isNull);
    });

    test('inlinePassRx modern form', () {
      final entry = inlinePassRx[false]!;
      expect(entry.delimiter, '+');
      expect(entry.endTrim, '-]');
      expect(groupsOf(entry.pattern, '+text+'), [
        '+text+',
        '',
        null,
        null,
        null,
        null,
        '+text+',
        '+',
        'text',
      ]);
      expect(groupsOf(entry.pattern, 'x +text+ y'), [
        ' +text+',
        ' ',
        null,
        null,
        null,
        null,
        '+text+',
        '+',
        'text',
      ]);
      expect(groupsOf(entry.pattern, '[x-]+text+'), [
        '[x-]+text+',
        '',
        '[',
        'x-',
        null,
        null,
        '+text+',
        '+',
        'text',
      ]);
      expect(groupsOf(entry.pattern, '+a\nb+'), [
        '+a\nb+',
        '',
        null,
        null,
        null,
        null,
        '+a\nb+',
        '+',
        'a\nb',
      ]);
      expect(groupsOf(entry.pattern, '`text`'), isNull);
      expect(groupsOf(entry.pattern, 'a+b'), isNull);
      expect(groupsOf(entry.pattern, 'x++y'), isNull);
    });

    test('inlinePassRx compat form', () {
      final entry = inlinePassRx[true]!;
      expect(entry.delimiter, '`');
      expect(entry.endTrim, isNull);
      expect(groupsOf(entry.pattern, '`text`'), [
        '`text`',
        '',
        null,
        null,
        null,
        null,
        '`text`',
        '`',
        'text',
      ]);
      expect(groupsOf(entry.pattern, 'a `x` b'), [
        ' `x`',
        ' ',
        null,
        null,
        null,
        null,
        '`x`',
        '`',
        'x',
      ]);
      expect(groupsOf(entry.pattern, '`a\nb`'), [
        '`a\nb`',
        '',
        null,
        null,
        null,
        null,
        '`a\nb`',
        '`',
        'a\nb',
      ]);
      expect(groupsOf(entry.pattern, 'ab`x`'), isNull);
      expect(groupsOf(entry.pattern, ' `x`y'), isNull);
      // Group 5 matches a literal backslash, so `[foo]` followed by
      // `)` cannot take the quote-attribute branch; matching starts
      // at `)` instead.
      expect(groupsOf(entry.pattern, ' ([foo])`code`'), [
        ')`code`',
        ')',
        null,
        null,
        null,
        null,
        '`code`',
        '`',
        'code',
      ]);
      expect(groupsOf(entry.pattern, '([foo])`code`'), [
        ')`code`',
        ')',
        null,
        null,
        null,
        null,
        '`code`',
        '`',
        'code',
      ]);
      expect(groupsOf(entry.pattern, 'a([foo])`code`'), [
        ')`code`',
        ')',
        null,
        null,
        null,
        null,
        '`code`',
        '`',
        'code',
      ]);
      expect(groupsOf(entry.pattern, ' ([foo]`code`'), [
        '([foo]`code`',
        '(',
        null,
        null,
        'foo',
        null,
        '`code`',
        '`',
        'code',
      ]);
      expect(groupsOf(entry.pattern, '([foo]`code`'), [
        '([foo]`code`',
        '(',
        null,
        null,
        'foo',
        null,
        '`code`',
        '`',
        'code',
      ]);
      expect(groupsOf(entry.pattern, 'x [a]`b` y'), [
        ' [a]`b`',
        ' ',
        null,
        null,
        'a',
        null,
        '`b`',
        '`',
        'b',
      ]);
      expect(groupsOf(entry.pattern, '`x`'), [
        '`x`',
        '',
        null,
        null,
        null,
        null,
        '`x`',
        '`',
        'x',
      ]);
    });

    test('inlinePassMacroRx', () {
      expect(groupsOf(inlinePassMacroRx, '+++text+++'), [
        '+++text+++',
        null,
        null,
        '',
        '+++',
        'text',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlinePassMacroRx, r'$$text$$'), [
        r'$$text$$',
        null,
        null,
        '',
        r'$$',
        'text',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlinePassMacroRx, 'pass:[x]'), [
        'pass:[x]',
        null,
        null,
        null,
        null,
        null,
        '',
        null,
        'x',
      ]);
      expect(groupsOf(inlinePassMacroRx, 'pass:quotes[text]'), [
        'pass:quotes[text]',
        null,
        null,
        null,
        null,
        null,
        '',
        'quotes',
        'text',
      ]);
      expect(groupsOf(inlinePassMacroRx, 'pass:[]'), [
        'pass:[]',
        null,
        null,
        null,
        null,
        null,
        '',
        null,
        '',
      ]);
      expect(groupsOf(inlinePassMacroRx, '++x++'), [
        '++x++',
        null,
        null,
        '',
        '++',
        'x',
        null,
        null,
        null,
      ]);
      expect(groupsOf(inlinePassMacroRx, '[a]+++x+++'), [
        '[a]+++x+++',
        '',
        'a',
        '',
        '+++',
        'x',
        null,
        null,
        null,
      ]);
    });

    test('inlineXrefMacroRx', () {
      expect(groupsOf(inlineXrefMacroRx, '&lt;&lt;id&gt;&gt;'), [
        '&lt;&lt;id&gt;&gt;',
        'id',
        null,
        null,
      ]);
      expect(groupsOf(inlineXrefMacroRx, '&lt;&lt;id,ref&gt;&gt;'), [
        '&lt;&lt;id,ref&gt;&gt;',
        'id,ref',
        null,
        null,
      ]);
      expect(groupsOf(inlineXrefMacroRx, 'xref:id[ref]'), [
        'xref:id[ref]',
        null,
        'id',
        'ref',
      ]);
      expect(groupsOf(inlineXrefMacroRx, 'xref:id[]'), [
        'xref:id[]',
        null,
        'id',
        null,
      ]);
      expect(groupsOf(inlineXrefMacroRx, 'xref:{id}[ref]'), [
        'xref:{id}[ref]',
        null,
        '{id}',
        'ref',
      ]);
      expect(groupsOf(inlineXrefMacroRx, '<<id>>'), isNull);
    });
  });

  group('layout', () {
    test('hardLineBreakRx', () {
      expect(groupsOf(hardLineBreakRx, 'foo +'), ['foo +', 'foo']);
      expect(groupsOf(hardLineBreakRx, 'foo  +'), ['foo  +', 'foo ']);
      expect(groupsOf(hardLineBreakRx, 'foo+'), isNull);
      expect(groupsOf(hardLineBreakRx, 'a +\nb'), ['a +', 'a']);
      expect(groupsOf(hardLineBreakRx, '+'), isNull);
    });

    test('markdownThematicBreakRx', () {
      expect(groupsOf(markdownThematicBreakRx, '---'), ['---', '-', '']);
      expect(groupsOf(markdownThematicBreakRx, '- - -'), ['- - -', '-', ' ']);
      expect(groupsOf(markdownThematicBreakRx, '***'), ['***', '*', '']);
      expect(groupsOf(markdownThematicBreakRx, '___'), ['___', '_', '']);
      expect(groupsOf(markdownThematicBreakRx, '---x'), isNull);
      expect(groupsOf(markdownThematicBreakRx, ' ----'), isNull);
      expect(groupsOf(markdownThematicBreakRx, '--'), isNull);
      expect(groupsOf(markdownThematicBreakRx, '-*-'), isNull);
    });

    test('extLayoutBreakRx', () {
      expect(groupsOf(extLayoutBreakRx, "'''"), ["'''", null, null]);
      expect(groupsOf(extLayoutBreakRx, '---'), ['---', '-', '']);
      expect(groupsOf(extLayoutBreakRx, '- - -'), ['- - -', '-', ' ']);
      expect(groupsOf(extLayoutBreakRx, '----'), isNull);
      expect(groupsOf(extLayoutBreakRx, '<<<'), ['<<<', null, null]);
      expect(groupsOf(extLayoutBreakRx, '<<'), isNull);
      expect(groupsOf(extLayoutBreakRx, 'xxx'), isNull);
    });
  });

  group('general', () {
    test('blankLineRx', () {
      expect(groupsOf(blankLineRx, '\n\n'), ['\n\n']);
      expect(groupsOf(blankLineRx, '\n\n\n'), ['\n\n\n']);
      expect(groupsOf(blankLineRx, '\n'), isNull);
      expect(groupsOf(blankLineRx, 'a\n\nb'), ['\n\n']);
    });

    test('escapedSpaceRx', () {
      expect(groupsOf(escapedSpaceRx, r'\ '), [r'\ ', ' ']);
      expect(groupsOf(escapedSpaceRx, r'a\ b'), [r'\ ', ' ']);
      expect(groupsOf(escapedSpaceRx, 'ab'), isNull);
      expect(groupsOf(escapedSpaceRx, '\\\tn'), ['\\\t', '\t']);
    });

    test('replaceableTextRx', () {
      expect(groupsOf(replaceableTextRx, 'a & b'), ['&']);
      expect(groupsOf(replaceableTextRx, "a'b"), ["'"]);
      expect(groupsOf(replaceableTextRx, 'a -- b'), ['--']);
      expect(groupsOf(replaceableTextRx, 'a...b'), ['...']);
      expect(groupsOf(replaceableTextRx, '(C)'), ['(C)']);
      expect(groupsOf(replaceableTextRx, '(R)'), ['(R)']);
      expect(groupsOf(replaceableTextRx, '(TM)'), ['(TM)']);
      expect(groupsOf(replaceableTextRx, '(M)'), isNull);
      expect(groupsOf(replaceableTextRx, '(CM)'), ['(CM)']);
      expect(groupsOf(replaceableTextRx, 'plain'), isNull);
    });

    test('spaceDelimiterRx', () {
      expect(groupsOf(spaceDelimiterRx, 'a  b'), ['a  ', 'a']);
      expect(groupsOf(spaceDelimiterRx, r'a\ b'), isNull);
      expect(groupsOf(spaceDelimiterRx, 'a\nb'), ['a\n', 'a']);
      expect(groupsOf(spaceDelimiterRx, 'ab'), isNull);
    });

    test('subModifierSniffRx', () {
      expect(groupsOf(subModifierSniffRx, '+'), ['+']);
      expect(groupsOf(subModifierSniffRx, '-'), ['-']);
      expect(groupsOf(subModifierSniffRx, 'x'), isNull);
    });

    test('trailingDigitsRx', () {
      expect(groupsOf(trailingDigitsRx, 'docbook5'), ['5']);
      expect(groupsOf(trailingDigitsRx, 'html5'), ['5']);
      expect(groupsOf(trailingDigitsRx, 'abc'), isNull);
      expect(groupsOf(trailingDigitsRx, 'a1\nb'), ['1']);
    });

    test('uriSniffRx', () {
      expect(groupsOf(uriSniffRx, 'http://x'), ['http://']);
      expect(groupsOf(uriSniffRx, 'https://x'), ['https://']);
      expect(groupsOf(uriSniffRx, 'file:///p'), ['file://']);
      expect(groupsOf(uriSniffRx, 'data:info'), ['data:']);
      expect(groupsOf(uriSniffRx, 'c:/x'), isNull);
      expect(groupsOf(uriSniffRx, r'C:\x'), isNull);
      // String-anchored (B2): no match on a later line.
      expect(groupsOf(uriSniffRx, 'x\nhttp://y'), isNull);
      expect(groupsOf(uriSniffRx, 'ftp://h/p'), ['ftp://']);
    });

    test('xmlSanitizeRx', () {
      expect(groupsOf(xmlSanitizeRx, '<b>'), ['<b>']);
      expect(groupsOf(xmlSanitizeRx, 'a<b>c'), ['<b>']);
      expect(groupsOf(xmlSanitizeRx, '<>'), isNull);
      expect(groupsOf(xmlSanitizeRx, '<a b="c">'), ['<a b="c">']);
    });
  });

  group('fragments and flags', () {
    test('character class fragments', () {
      expect(ccAll, r'[\s\S]');
      expect(ccAny, r'[^\n]');
      expect(ccEol, r'$');
      expect(ccAlpha, r'\p{Alphabetic}');
      expect(cgAlpha, r'\p{Alphabetic}');
      expect(ccAlnum, r'\p{Alphabetic}\p{Decimal_Number}');
      expect(cgAlnum, r'(?:\p{Alphabetic}|\p{Decimal_Number})');
      expect(cgBlank, r'[ \t]');
      expect(
        ccWord,
        r'\p{Alphabetic}\p{Mark}\p{Decimal_Number}\p{Connector_Punctuation}\p{Join_Control}',
      );
      expect(
        cgWord,
        r'(?:\p{Alphabetic}|\p{Mark}|\p{Decimal_Number}|\p{Connector_Punctuation}|\p{Join_Control})',
      );
      expect(quoteAttributeListRxt, r'\[([^\]]+)\]');
    });

    test('anchor and unicode flags', () {
      // B2: string-anchored, so no multiLine.
      expect(attributeEntryPassMacroRx.isMultiLine, isFalse);
      expect(uriSniffRx.isMultiLine, isFalse);
      // B9/R3: ^/$ anchors get multiLine.
      expect(authorInfoLineRx.isMultiLine, isTrue);
      expect(tagDirectiveRx.isMultiLine, isTrue);
      expect(calloutScanRx.isMultiLine, isTrue);
      expect(hardLineBreakRx.isMultiLine, isTrue);
      expect(trailingDigitsRx.isMultiLine, isTrue);
      expect(blockTitleRx.isMultiLine, isTrue);
      // No anchors, no multiLine.
      expect(blankLineRx.isMultiLine, isFalse);
      expect(inlinePassMacroRx.isMultiLine, isFalse);
      expect(inlineFootnoteMacroRx.isMultiLine, isFalse);
      // R2: \w-from-Word / \p fragments get unicode.
      expect(authorInfoLineRx.isUnicode, isTrue);
      expect(inlineEmailRx.isUnicode, isTrue);
      expect(setextSectionTitleRx.isUnicode, isTrue);
      expect(uriSniffRx.isUnicode, isTrue);
      expect(macroNameRx.isUnicode, isTrue);
      // No fragments, no unicode (incl. opal inlineLinkRx: CG_BLANK
      // maps to ASCII, so no unicode flag is needed).
      expect(inlineLinkRx.isUnicode, isFalse);
      expect(inlineLinkRx.isMultiLine, isTrue);
      expect(revisionInfoLineRx.isUnicode, isFalse);
      expect(inlineImageMacroRx.isUnicode, isFalse);
    });
  });
}
