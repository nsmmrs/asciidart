// Callouts linked both ways (and linted) with the callout-links
// attribute: asciidart's, off by default (Asciidoctor has neither).
import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

const _source = '''
= Doc

----
a <1>
b <2>
c <1>
----
<1> One.
<2> Two.
''';

String _html(String source, {Map<String, String> attributes = const {}}) =>
    convert(
      source,
      AsciidoctorOptions(safe: SafeMode.safe, attributes: attributes),
    );

void main() {
  test('markers and items stay as Asciidoctor has them by default', () {
    final html = _html(_source);
    expect(html, contains('a <b class="conum">(1)</b>'));
    expect(html, isNot(contains('conum-link')));
    expect(html, contains('<p>One.</p>'));
  });

  test('each marker links to its item, each item back to its first', () {
    final html = _html(_source, attributes: {'callout-links': ''});
    expect(
      html,
      contains(
        'c <a id="CO1-3" class="conum-link" href="#CO1-3-item" '
        'style="user-select:none"><b class="conum">(1)</b></a>',
      ),
    );
    expect(
      html,
      contains(
        '<p><a id="CO1-1-item"></a><a id="CO1-3-item"></a>One. '
        '<a class="conum-back" href="#CO1-1" title="Back to the code">'
        '&#8617;</a></p>',
      ),
    );
  });

  test('with font icons, the item number links back', () {
    final html = _html(
      _source,
      attributes: {'callout-links': '', 'icons': 'font'},
    );
    expect(
      html,
      contains(
        '<td><a href="#CO1-2"><i class="conum" data-value="2"></i><b>2</b>'
        '</a></td>\n<td><a id="CO1-2-item"></a>Two.</td>',
      ),
    );
  });

  group('lint', () {
    List<String> messages(String source, Map<String, String> attributes) {
      final logger = MemoryLogger();
      convert(
        source,
        AsciidoctorOptions(
          safe: SafeMode.safe,
          attributes: attributes,
          logger: logger,
        ),
      );
      return [for (final m in logger.messages) m.message.text];
    }

    const unmatched = '''
----
a <1>
b <2>
c <3>
----
<1> One.
<2> Two.

----
x <1>
----
''';

    test('reports callouts no item or list explains', () {
      expect(messages(unmatched, {'callout-links': ''}), [
        'no callout list item for <3>',
        'no callout list for <1>',
      ]);
    });

    test('is off without callout-links', () {
      expect(messages(unmatched, const {}), isEmpty);
    });
  });
}
