import 'package:ptome/src/xml_balance.dart';
import 'package:test/test.dart';

void main() {
  test('well-formed XML comes back unchanged', () {
    for (final xml in [
      '<p>Some <em>text</em> and <br/> an <img src="a.png"/> image.</p>',
      '<simpara>A <link xl:href="https://htmx.org">link</link>.</simpara>',
      '<?xml version="1.0"?>\n<!DOCTYPE x>\n<a><!-- <b> --><![CDATA[<c>]]></a>',
      '<a title="x > y">text</a>',
      '',
    ]) {
      expect(identical(balanceXml(xml), xml), isTrue, reason: xml);
    }
  });

  test('closes what an ending element leaves open', () {
    expect(
      balanceXml('<primary><emphasis>hyperscript</primary>'),
      '<primary><emphasis>hyperscript</emphasis></primary>',
    );
  });

  test('leaves out an end tag with no open element', () {
    expect(
      balanceXml('<simpara>an _event filter</emphasis> syntax</simpara>'),
      '<simpara>an _event filter syntax</simpara>',
    );
  });

  test('both, as the index term case gives them', () {
    expect(
      balanceXml(
        '<indexterm><primary><emphasis>hyperscript</primary></indexterm>'
        '<simpara>an event filter</emphasis> here</simpara>',
      ),
      '<indexterm><primary><emphasis>hyperscript</emphasis></primary>'
      '</indexterm><simpara>an event filter here</simpara>',
    );
  });
}
