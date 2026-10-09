// `ptome check`: documents in units analyzed without converting them.
import 'package:ptome/src/cli/run.dart';
import 'package:test/test.dart';

const _fixtures = 'test/units/fixtures';

void main() {
  test('a document with problems: each listed, a summary, status 1', () async {
    final out = StringBuffer();
    final code = await runCliCode([
      'check',
      '$_fixtures/bible/sample.adoc',
    ], out: out);
    expect(code, 1);
    expect(
      out.toString(),
      contains('ptome: WARNING: sample.adoc:15:1: verse 6 after 2'),
    );
    expect(
      out.toString(),
      contains('3 bible.book, 4 bible.chapter, 13 bible.verse; 2 notes'),
    );
  });

  test('a document without problems: its summary, status 0', () async {
    final out = StringBuffer();
    final code = await runCliCode([
      'check',
      '-q',
      '$_fixtures/law/eu-sample.adoc',
    ], out: out);
    expect(code, 0);
    expect(out.toString(), contains('1 eu.article, 2 eu.paragraph'));
    expect(out.toString(), contains('0 errors, 0 warnings'));
  });

  test('usage on misuse, status 64', () async {
    final err = StringBuffer();
    expect(await runCliCode(['check'], err: err), 64);
    expect(err.toString(), contains('Usage: ptome check'));
  });

  test(
    '--format=json: an object for each document; --list its units',
    () async {
      final out = StringBuffer();
      final code = await runCliCode([
        'check',
        '--format=json',
        '--list',
        '$_fixtures/bible/sample.adoc',
      ], out: out);
      expect(code, 1);
      final text = out.toString();
      expect(text, startsWith('[\n{"path": '));
      expect(
        text,
        contains(
          '{"severity": "warning", "kind": "label", '
          '"message": "verse 6 after 2 (expected 3)", '
          '"path": "sample.adoc", "line": 15, "column": 1}',
        ),
      );
      expect(text, contains('"units": {"bible.book": 3, "bible.chapter": 4'));
      expect(
        text,
        contains(
          '{"id": "v-exo-34-6", "scheme": "bible", "level": "verse", '
          '"citation": "Exod 34:6", "path": "sample.adoc", "line": 15}',
        ),
      );
    },
  );
}
