/// Port of `test/attribute_list_test.rb`.
library;

import 'package:asciidoctor/src/attribute_list.dart';
import 'package:test/test.dart';

/// Block double whose [applySubs] must never be invoked.
class _ThrowingBlock implements SubsApplier {
  @override
  String applySubs(String value) =>
      throw StateError('apply_subs should not be called');
}

void main() {
  Map<Object, String?> parseInto(
    String line, [
    SubsApplier? block,
    List<String?> positionalAttrs = const [],
  ]) {
    final attributes = <Object, String?>{};
    AttributeList(line, block).parseInto(attributes, positionalAttrs);
    return attributes;
  }

  group('AttributeList', () {
    test('collect unnamed attribute', () {
      expect(parseInto('quote'), equals({1: 'quote'}));
    });

    test('collect unnamed attribute double-quoted', () {
      expect(parseInto('"quote"'), equals({1: 'quote'}));
    });

    test('collect empty unnamed attribute double-quoted', () {
      expect(parseInto('""'), equals({1: ''}));
    });

    test(
      'collect unnamed attribute double-quoted containing escaped quote',
      () {
        expect(parseInto(r'"ba\"zaar"'), equals({1: 'ba"zaar'}));
      },
    );

    test('collect unnamed attribute single-quoted', () {
      expect(parseInto("'quote'"), equals({1: 'quote'}));
    });

    test('collect empty unnamed attribute single-quoted', () {
      expect(parseInto("''"), equals({1: ''}));
    });

    test('collect isolated single quote positional attribute', () {
      expect(parseInto("'", _ThrowingBlock()), equals({1: "'"}));
    });

    test('collect isolated single quote attribute value', () {
      expect(parseInto("name='", _ThrowingBlock()), equals({'name': "'"}));
    });

    test(
      'collect attribute value as is if it has only leading single quote',
      () {
        expect(
          parseInto("name='{val}", _ThrowingBlock()),
          equals({'name': "'{val}"}),
        );
      },
    );

    test(
      'collect unnamed attribute single-quoted containing escaped quote',
      () {
        expect(parseInto(r"'ba\'zaar'"), equals({1: "ba'zaar"}));
      },
    );

    test('collect unnamed attribute with dangling delimiter', () {
      expect(parseInto('quote , '), equals({1: 'quote', 2: null}));
    });

    test(
      'collect unnamed attribute in second position after empty attribute',
      () {
        expect(parseInto(', John Smith'), equals({1: null, 2: 'John Smith'}));
      },
    );

    test('collect unnamed attributes', () {
      expect(
        parseInto('first, second one, third'),
        equals({1: 'first', 2: 'second one', 3: 'third'}),
      );
    });

    test('collect blank unnamed attributes', () {
      expect(
        parseInto('first,,third,'),
        equals({1: 'first', 2: null, 3: 'third', 4: null}),
      );
    });

    test('collect unnamed attribute enclosed in equal signs', () {
      expect(parseInto('=foo='), equals({1: '=foo='}));
    });

    test('collect named attribute', () {
      expect(parseInto('foo=bar'), equals({'foo': 'bar'}));
    });

    test('collect named attribute double-quoted', () {
      expect(parseInto('foo="bar"'), equals({'foo': 'bar'}));
    });

    test('collect named attribute with double-quoted empty value', () {
      expect(
        parseInto('height=100,caption="",link="images/octocat.png"'),
        equals({'height': '100', 'caption': '', 'link': 'images/octocat.png'}),
      );
    });

    test('collect named attribute single-quoted', () {
      expect(parseInto("foo='bar'"), equals({'foo': 'bar'}));
    });

    test('collect named attribute with single-quoted empty value', () {
      expect(
        parseInto("height=100,caption='',link='images/octocat.png'"),
        equals({'height': '100', 'caption': '', 'link': 'images/octocat.png'}),
      );
    });

    test('collect single named attribute with empty value', () {
      expect(parseInto('foo='), equals({'foo': ''}));
    });

    test('collect single named attribute with empty value when followed by '
        'other attributes', () {
      expect(parseInto('foo=,bar=baz'), equals({'foo': '', 'bar': 'baz'}));
    });

    test('collect named attributes unquoted', () {
      expect(
        parseInto('first=value, second=two, third=3'),
        equals({'first': 'value', 'second': 'two', 'third': '3'}),
      );
    });

    test('collect named attributes quoted', () {
      expect(
        parseInto('first=\'value\', second="value two", third=three'),
        equals({'first': 'value', 'second': 'value two', 'third': 'three'}),
      );
    });

    test('collect named attributes quoted containing non-semantic spaces', () {
      expect(
        parseInto(
          '     first    =     \'value\', second     ="value two"     , '
          'third=       three      ',
        ),
        equals({'first': 'value', 'second': 'value two', 'third': 'three'}),
      );
    });

    test('collect mixed named and unnamed attributes', () {
      expect(
        parseInto('first, second="value two", third=three, Sherlock Holmes'),
        equals({
          1: 'first',
          'second': 'value two',
          'third': 'three',
          4: 'Sherlock Holmes',
        }),
      );
    });

    test('collect mixed empty named and blank unnamed attributes', () {
      expect(
        parseInto('first,,third=,,fifth=five'),
        equals({1: 'first', 2: null, 'third': '', 4: null, 'fifth': 'five'}),
      );
    });

    test('collect options attribute', () {
      expect(
        parseInto("quote, options='opt1,,opt2 , opt3'"),
        equals({
          1: 'quote',
          'opt1-option': '',
          'opt2-option': '',
          'opt3-option': '',
        }),
      );
    });

    test('collect opts attribute as options', () {
      expect(
        parseInto("quote, opts='opt1,,opt2 , opt3'"),
        equals({
          1: 'quote',
          'opt1-option': '',
          'opt2-option': '',
          'opt3-option': '',
        }),
      );
    });

    test('should ignore options attribute if empty', () {
      expect(parseInto('quote, opts='), equals({1: 'quote'}));
    });

    test('collect and rekey unnamed attributes', () {
      expect(
        parseInto('first, second one, third, fourth', null, ['a', 'b', 'c']),
        equals({
          1: 'first',
          2: 'second one',
          3: 'third',
          4: 'fourth',
          'a': 'first',
          'b': 'second one',
          'c': 'third',
        }),
      );
    });

    test('should not assign nil to attribute mapped to missing positional '
        'attribute', () {
      expect(
        parseInto('alt text,,100', null, ['alt', 'width', 'height']),
        equals({
          1: 'alt text',
          2: null,
          3: '100',
          'alt': 'alt text',
          'height': '100',
        }),
      );
    });

    test('rekey positional attributes', () {
      final attributes = <Object, String?>{1: 'source', 2: 'java'};
      AttributeList.rekeyAttributes(attributes, [
        'style',
        'language',
        'linenums',
      ]);
      expect(
        attributes,
        equals({1: 'source', 2: 'java', 'style': 'source', 'language': 'java'}),
      );
    });
  });
}
