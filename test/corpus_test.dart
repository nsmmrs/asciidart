// Every case converts with asciidart to what the asciidart profile recorded.
import 'package:ascii_docs/ascii_docs.dart';
import 'package:test/test.dart';

void main() {
  final corpus = Corpus.open();
  final profile = corpus.profiles.values.whereType<AsciidartProfile>().single;
  for (final c in corpus.cases()) {
    group(c.id, () {
      for (final format in c.formats) {
        test(format.name, () {
          final report = checkCases([c], profile, formats: {format});
          expect(
            report.failures.map((f) => '${f.testId}\n${f.detail}'),
            isEmpty,
          );
          expect(report.passed, 1, reason: 'no asciidart expectation recorded');
        });
      }
    });
  }
}
