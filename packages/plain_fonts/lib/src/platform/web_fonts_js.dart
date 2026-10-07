/// The WOFF and WOFF2 decoder on JavaScript: a part of the program, loaded
/// when first needed.
library;

import 'dart:typed_data';

import 'package:fonts/src/woff.dart' deferred as woff;

/// Decodes WOFF and WOFF2 fonts to the fonts they wrap; null until
/// [loadWebFontDecoder] has loaded it.
Uint8List Function(List<int> bytes)? get webFontDecoder => _decoder;
Uint8List Function(List<int> bytes)? _decoder;

/// Loads [webFontDecoder]'s part of the program.
Future<void> loadWebFontDecoder() async {
  if (_decoder != null) return;
  await woff.loadLibrary();
  _decoder = woff.decodeWebFont;
}
