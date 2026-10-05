/// The PDF backend (`-b pdf`): registration with the converter registry.
///
/// The backend is registered by the CLI (it embeds the bundled themes and
/// fonts), not by the web-safe library.
library;

import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/pdf/converter.dart';

export 'package:asciidart/src/pdf/converter.dart' show PdfConverter;

bool _registered = false;

/// Registers the `pdf` backend (once).
void registerPdf() {
  if (_registered) return;
  _registered = true;
  Converter.register(PdfConverter.new, ['pdf'], provided: true);
}
