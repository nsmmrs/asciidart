import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/pdf/engine.dart';
import 'package:test/test.dart';

void main() {
  PdfEngine engine(String source, MemoryLogger logger) =>
      PdfEngine.of(load(source), logger);

  test('the modern engine by default', () {
    final logger = MemoryLogger();
    expect(engine('text', logger), PdfEngine.modern);
    expect(logger.messages, isEmpty);
  });

  test('pdf-compat selects the asciidoctor-pdf compatibility mode', () {
    final logger = MemoryLogger();
    expect(engine(':pdf-compat:\n\ntext', logger), PdfEngine.asciidoctorPdf);
    expect(
      engine(':pdf-compat: asciidoctor-pdf\n\ntext', logger),
      PdfEngine.asciidoctorPdf,
    );
    expect(logger.messages, isEmpty);
  });

  test('an unknown pdf-compat value is reported', () {
    final logger = MemoryLogger();
    expect(
      engine(':pdf-compat: prawn\n\ntext', logger),
      PdfEngine.asciidoctorPdf,
    );
    expect(
      logger.messages.single.message.text,
      contains('unknown pdf-compat value'),
    );
  });
}
