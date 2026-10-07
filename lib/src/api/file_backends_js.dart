/// The backends that make files (PDF, EPUB) on JavaScript: separate parts
/// of the bundle, loaded the first time they're needed, so that what makes
/// HTML alone stays small.
library;

import 'package:asciidart/src/epub3/epub3.dart' deferred as epub3;
import 'package:asciidart/src/pdf/pdf.dart' deferred as pdf;
import 'package:asciidart/src/web_fonts.dart';

export 'package:asciidart/src/js/page_fonts.dart' show platformFonts;

final Set<String> _loaded = {};

/// Loads [backend]'s part of the bundle and registers its converter (and
/// the web font decoder's part: installed and given fonts may be WOFF).
Future<void> loadFileBackend(String backend) async {
  await loadWebFontDecoder();
  switch (backend) {
    case 'pdf':
      await pdf.loadLibrary();
      pdf.registerPdf();
    case 'epub3':
      await epub3.loadLibrary();
      epub3.registerEpub3();
  }
  _loaded.add(backend);
}

/// Registers [backend]'s converter, which must have been loaded.
void registerFileBackend(String backend) {
  if (!_loaded.contains(backend)) {
    throw StateError(
      'the $backend backend is loaded on demand in JavaScript: use the '
      'asynchronous conversion, or call Asciidart.loadBackend first',
    );
  }
}
