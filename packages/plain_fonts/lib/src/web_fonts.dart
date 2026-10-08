/// The WOFF and WOFF2 decoder as the font index uses it: compiled in on
/// the Dart VM; on JavaScript, a part of the program loaded on demand
/// (`FontIndex.loadWebFontDecoder`), so that programs that read no web
/// font don't carry the Brotli dictionary.
library;

export 'package:plain_fonts/src/platform/web_fonts_vm.dart'
    if (dart.library.js_interop) 'package:plain_fonts/src/platform/web_fonts_js.dart';
