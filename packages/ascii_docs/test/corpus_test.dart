// Every case converts with ptome to what the ptome profile recorded.
import 'package:ascii_docs/ascii_docs.dart';
import 'package:test/test.dart';

void main() {
  final corpus = Corpus.open();
  final profile = corpus.profiles.values.whereType<PtomeProfile>().single;
  for (final c in corpus.cases()) {
    group(c.id, () {
      for (final format in c.formats) {
        test(format.name, skip: c.knownIssues[format], () {
          final report = checkCases([c], profile, formats: {format});
          expect(
            report.failures.map((f) => '${f.testId}\n${f.detail}'),
            isEmpty,
          );
          expect(report.passed, 1, reason: 'no ptome expectation recorded');
        });
      }
    });
  }
}
