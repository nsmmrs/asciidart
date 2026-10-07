/// The WOFF and WOFF2 decoder, compiled in.
library;

import 'dart:typed_data';

import 'package:fonts/src/woff.dart';

/// Decodes WOFF and WOFF2 fonts to the fonts they wrap.
Uint8List Function(List<int> bytes)? get webFontDecoder => decodeWebFont;

/// Makes [webFontDecoder] ready (here, it always is).
Future<void> loadWebFontDecoder() async {}
