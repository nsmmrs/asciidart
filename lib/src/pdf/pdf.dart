/// The PDF backend (`-b pdf`): registration with the converter registry.
///
/// The backend is registered by the CLI (it embeds the bundled themes and
/// fonts), not by the web-safe library.
library;

import 'package:ptome/src/converter.dart';
import 'package:ptome/src/extensions.dart';
import 'package:ptome/src/pdf/converter.dart';

export 'package:ptome/src/pdf/converter.dart' show PdfConverter;

bool _registered = false;

/// Registers the `pdf` backend (once).
void registerPdf() {
  if (_registered) return;
  _registered = true;
  Converter.register(PdfConverter.new, ['pdf'], provided: true);
  // Blocks keep where they start in the source, so that layout problems
  // name it.
  Extensions.register(
    name: 'ptome-pdf',
    build: (registry) {
      final document = registry.document;
      if (document != null && document.backend == 'pdf') {
        document.sourcemap = true;
      }
    },
  );
}
