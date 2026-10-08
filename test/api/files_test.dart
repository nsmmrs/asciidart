/// Scenario 8 of `doc/api.md`: files, through `package:ptome/io.dart`.
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/io.dart';
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

void main() {
  group('8. files', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ptome-api.'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('convertFile and convertTree', () async {
      final docs = Directory('${tmp.path}/docs/guide')
        ..createSync(recursive: true);
      File('${tmp.path}/docs/index.adoc').writeAsStringSync('= Home\n\nhi');
      File('${docs.path}/start.adoc').writeAsStringSync('= Start\n\ngo');
      File('${tmp.path}/docs/_partial.adoc').writeAsStringSync('skip');
      // Writing outside the documents' directory needs the unsafe mode.
      const ad = Ptome(safe: SafeMode.unsafe);

      final doc = await ad.convertFile('${tmp.path}/docs/index.adoc');
      expect(doc.title, 'Home');
      expect(File('${tmp.path}/docs/index.html').existsSync(), isTrue);

      final out = '${tmp.path}/build';
      final results = await ad
          .convertTree('${tmp.path}/docs', toDir: out)
          .toList();
      expect(
        [for (final r in results) r.outputPath.substring(out.length + 1)],
        ['guide/start.html', 'index.html'],
      );
      expect(File('$out/guide/start.html').readAsStringSync(), contains('go'));
    });

    test('parseFile resolves includes in the safe mode', () async {
      File('${tmp.path}/part.adoc').writeAsStringSync('included');
      File('${tmp.path}/main.adoc').writeAsStringSync('include::part.adoc[]');
      const ad = Ptome(safe: SafeMode.safe);
      final doc = await ad.parseFile('${tmp.path}/main.adoc');
      expect(doc.plainText, 'included');
    });
  });
}
