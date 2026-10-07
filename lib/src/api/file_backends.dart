/// The backends that make files (PDF, EPUB) on the Dart VM: compiled in,
/// registered when first used (on JavaScript, `file_backends_js.dart`
/// loads them on demand).
library;

import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/pdf/pdf.dart';

/// Makes [backend]'s code ready (here, registers it).
Future<void> loadFileBackend(String backend) async =>
    registerFileBackend(backend);

/// Registers [backend]'s converter.
void registerFileBackend(String backend) {
  switch (backend) {
    case 'pdf':
      registerPdf();
    case 'epub3':
      registerEpub3();
  }
}
