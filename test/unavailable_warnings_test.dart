/// Features the port lacks warn once, as Asciidoctor does when the library
/// behind them is missing; the wording is the port's own.
library;

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

List<String> warningsOf(void Function() body) {
  final logger = MemoryLogger();
  final saved = LoggerManager.logger;
  LoggerManager.logger = logger;
  try {
    body();
  } finally {
    LoggerManager.logger = saved;
  }
  return [
    for (final message in logger.messages)
      if (message.severity == Severity.warn) message.message.text,
  ];
}

const source =
    '[source,ruby]\n----\nputs 1\n----\n\n[source,ruby]\n----\n2\n----\n';

void main() {
  for (final (name, reset) in [
    ('Rouge', RougeAdapter.resetUnavailableWarning),
    ('Pygments', PygmentsAdapter.resetUnavailableWarning),
  ]) {
    test('$name warns once that highlighting is not available', () {
      reset();
      final warnings = warningsOf(() {
        for (var i = 0; i < 2; i++) {
          convert(
            source,
            AsciidoctorOptions(
              safe: SafeMode.safe,
              attributes: {'source-highlighter': name.toLowerCase()},
            ),
          );
        }
      });
      expect(warnings, [
        '$name syntax highlighting is not available. Functionality disabled.',
      ]);
    });
  }

  test('DocBook warns once per document that AsciiMath stays text', () {
    final warnings = warningsOf(() {
      convert(
        'asciimath:[x] and asciimath:[y]\n\n[asciimath]\n++++\nz\n++++\n',
        const AsciidoctorOptions(backend: 'docbook5'),
      );
    });
    const expected =
        'AsciiMath to MathML conversion is not available. '
        'Functionality disabled.';
    expect(warnings, [expected]);
  });
}
