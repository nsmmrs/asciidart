/// The backends that make files (PDF, EPUB) on the Dart VM: compiled in,
/// registered when first used (on JavaScript, `file_backends_js.dart`
/// loads them on demand).
library;

import 'package:ptome/src/epub3/epub3.dart';
import 'package:ptome/src/pdf/pdf.dart';

/// Makes [backend]'s code ready (here, registers it).
Future<void> loadFileBackend(String backend) async =>
    registerFileBackend(backend);

/// The fonts of the platform that aren't installed in font folders: none
/// on the Dart VM (in a browser, the page's and the visitor's).
Future<List<(String, List<int>)>> platformFonts({
  required bool page,
  required List<String> localFamilies,
}) async => const [];

/// Registers [backend]'s converter.
void registerFileBackend(String backend) {
  switch (backend) {
    case 'pdf':
      registerPdf();
    case 'epub3':
      registerEpub3();
  }
}
