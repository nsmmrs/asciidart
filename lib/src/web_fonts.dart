/// The decoder of WOFF and WOFF2 fonts (libpdf's): compiled in on the
/// Dart VM; on JavaScript, a part of the bundle loaded with the PDF and
/// EPUB backends (or by `loadWebFontDecoder`).
library;

export 'web_fonts/vm.dart' if (dart.library.js_interop) 'web_fonts/js.dart';
