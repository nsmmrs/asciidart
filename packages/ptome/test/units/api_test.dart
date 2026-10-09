// The units of a document written in units, through the public API.
import 'package:ptome/io.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

const _fixtures = 'test/units/fixtures';

void main() {
  const ptome = Ptome(safe: SafeMode.unsafe);

  test('a document lists its units, in order, with their addresses', () async {
    final doc = await ptome.parseFile('$_fixtures/bible/sample.adoc');
    final units = doc.units;
    expect(units.first.level, 'book');
    expect(units.first.labels, {'book': 'EXO'});
    final verse = units.firstWhere((u) => u.id == 'v-exo-34-6');
    expect(verse.scheme, 'bible');
    expect(verse.level, 'verse');
    expect(verse.depth, 2);
    expect(verse.labels, {'book': 'EXO', 'chapter': '34', 'verse': '6'});
    expect(verse.reftext, 'Exodus 34:6');
    expect(verse.citation, 'Exod 34:6');
    expect(verse.line, 15);
    expect(verse.path, endsWith('sample.adoc'));
  });

  test('a unit by ID or by address', () async {
    final doc = await ptome.parseFile('$_fixtures/bible/sample.adoc');
    expect(doc.unit('v-mat-5-3')?.citation, 'Matt 5:3');
    expect(doc.unit('Exodus 34:6')?.id, 'v-exo-34-6');
    expect(doc.unit('Exod 34:6-7')?.id, 'v-exo-34-6');
    expect(doc.unit('Ps 3')?.id, 'c-psa-3');
    expect(doc.unit('Rev 22:21'), isNull);
  });

  test('a document not written in units has none', () {
    final doc = ptome.parse('= Plain\n\n@ text');
    expect(doc.units, isEmpty);
    expect(doc.unit('1:1'), isNull);
  });

  test('units, notes and units of blocks are nodes of their own', () async {
    final doc = await ptome.parseFile('$_fixtures/bible/sample.adoc');
    final verses = doc.descendants<Paragraph>();
    final inlines = [
      for (final p in verses)
        for (final i in p.inlines) i,
    ];
    final mark = inlines.whereType<UnitMark>().firstWhere(
      (m) => m.id == 'v-exo-34-6',
    );
    expect(mark.isStart, isTrue);
    expect(mark.level, 'verse');
    expect(mark.citation, 'Exod 34:6');
    expect(mark.label, '6');
    final call = inlines.whereType<NoteCall>().first;
    expect(call.stream, 'x');
    expect(call.caller, 'a');
    expect(inlines.whereType<NoteEntry>().first.stream, 'x');

    final law = await ptome.parseFile('$_fixtures/law/eu-sample.adoc');
    final point = law.descendants<UnitBlock>().firstWhere(
      (u) => u.id == 'art-6-1-a',
    );
    expect(point.level, 'point');
    expect(point.citation, 'Article 6(1)(a)');
    expect(point.blocks.single, isA<Paragraph>());
  });
}
