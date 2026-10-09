// Documents in units (ADR-0019): ptome reads the units syntax itself, and
// its output equals its output for the oracle's rendering of the same
// document (`*.lowered.adoc`, written by the loci experiment's lowering).
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const _fixtures = 'test/units/fixtures';

String _convert(String path, String backend) => loadFile(
  path,
  options: AsciidoctorOptions(
    safe: SafeMode.unsafe,
    backend: backend,
    standalone: true,
    attributes: const {'reproducible': ''},
  ),
).convert();

void main() {
  for (final doc in ['bible/sample', 'law/eu-sample']) {
    for (final backend in ['html5', 'docbook5']) {
      test('$doc ($backend): the same as its rendering', () {
        expect(
          _convert('$_fixtures/$doc.adoc', backend),
          _convert('$_fixtures/$doc.lowered.adoc', backend),
        );
      });
    }
  }

  test('markers become anchors and labels; notes, ranges and terms render', () {
    final html = _convert('$_fixtures/bible/sample.adoc', 'html5');
    expect(html, contains('id="v-exo-34-6"'));
    expect(html, contains('<sup>6</sup>'));
    // The divine name in small capitals, the words of Jesus as a range.
    expect(html, contains('<span class="nd">Lord</span>'));
    expect(html, contains('<span class="wj">Blessed'));
    // A reference by address is a link to the verse.
    expect(html, contains('href="#v-exo-34-6"'));
    expect(html, isNot(contains('@ ')));
  });

  test('parallel texts: two documents side by side, by address', () {
    final html = _convert('$_fixtures/bible/psalm23-parallel.adoc', 'html5');
    // A heading that is only a marker shows its unit's name.
    expect(html, contains('<h4 id="_psalms_23">Psalms 23</h4>'));
    // Each verse a row: the translation beside it, matched by address.
    final row = RegExp(
      r'<tr>\s*<td[^>]*><p[^>]*><a id="v-psa-23-1"></a><sup>1</sup>&#160;'
      r'The LORD <em>is</em> my shepherd; I shall not want.</p></td>\s*'
      '<td[^>]*><p[^>]*><sup>1</sup>&#160;Dominus regit me, et nihil '
      'mihi deerit:</p></td>',
    );
    expect(html, matches(row));
  });

  test('a document without :units: is read as before', () {
    final dir = Directory.systemTemp.createTempSync('units');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/plain.adoc')
      ..writeAsStringSync('= Plain\n\n@ stays text, note:x[not a note].\n');
    expect(
      _convert(file.path, 'html5'),
      contains('@ stays text, note:x[not a note].'),
    );
  });

  test('labels out of order warn through the logger', () {
    final dir = Directory.systemTemp.createTempSync('units');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/schemes').createSync();
    for (final name in ['bible', 'kjv', 'canon-protestant']) {
      File('$_fixtures/schemes/$name.yml')
          .copySync('${dir.path}/schemes/$name.yml');
    }
    final file = File('${dir.path}/doc.adoc')
      ..writeAsStringSync(
        '= Doc\n:units: bible, kjv\n\n== @EXO\n\n=== @3\n\n'
        '@ One.\n@5 Five.\n@2 Two.\n',
      );
    final logger = MemoryLogger();
    final previous = LoggerManager.logger;
    LoggerManager.logger = logger;
    addTearDown(() => LoggerManager.logger = previous);
    _convert(file.path, 'html5');
    expect(
      logger.messages.map((m) => m.message.text).join('\n'),
      contains('doc.adoc:10'),
    );
  });
}
