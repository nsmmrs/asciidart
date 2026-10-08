/// CRC-32 (ISO-HDLC, as ZIP, gzip and PNG compute it).
library;

import 'dart:typed_data';

/// The CRC-32 of [bytes], or of the bytes from [start] to [end], continuing
/// from [crc] (the CRC of the bytes before, 0 for none).
int crc32(List<int> bytes, {int start = 0, int? end, int crc = 0}) {
  var c = crc ^ 0xffffffff;
  final stop = end ?? bytes.length;
  for (var i = start; i < stop; i++) {
    c = _table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

final Uint32List _table = Uint32List.fromList([
  for (var n = 0; n < 256; n++) _entry(n),
]);

int _entry(int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
}
