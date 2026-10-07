/// The WOFF and WOFF2 decoder on JavaScript: a part of the bundle, loaded
/// when first needed, so that what makes HTML alone stays small.
library;

import 'dart:typed_data';

import 'package:libpdf/libpdf.dart' deferred as woff;

/// Decodes WOFF and WOFF2 fonts to the fonts they wrap; null until
/// [loadWebFontDecoder] has loaded it.
Uint8List Function(List<int> bytes)? get webFontDecoder => _decoder;
Uint8List Function(List<int> bytes)? _decoder;

/// Loads [webFontDecoder]'s part of the bundle.
Future<void> loadWebFontDecoder() async {
  if (_decoder != null) return;
  await woff.loadLibrary();
  _decoder = woff.decodeWebFont;
}
