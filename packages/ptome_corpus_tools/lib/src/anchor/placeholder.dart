/// Blank stand-ins for the images pool documents read: same format and
/// dimensions (what conversions look at), none of the original pixels.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A blank image like the one at [path], or null if [path] isn't an image
/// format this can write.
Uint8List? placeholderImage(String path) {
  final lower = path.toLowerCase();
  final encode = switch (lower) {
    _ when lower.endsWith('.png') => img.encodePng,
    _ when lower.endsWith('.jpg') || lower.endsWith('.jpeg') => img.encodeJpg,
    _ when lower.endsWith('.gif') => img.encodeGif,
    _ when lower.endsWith('.bmp') => img.encodeBmp,
    _ => null,
  };
  if (encode == null) return null;
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  final blank = img.Image(
    width: decoded?.width ?? 1,
    height: decoded?.height ?? 1,
  );
  img.fill(blank, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(encode(blank));
}
