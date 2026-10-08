/// SHA-256 (FIPS 180-4), for checking downloaded files against the
/// digests they are pinned to.
library;

import 'dart:typed_data';

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// The SHA-256 digest of [data], in lowercase hexadecimal.
String sha256Hex(List<int> data) {
  final length = data.length;
  final padded = Uint8List(((length + 9 + 63) ~/ 64) * 64)
    ..setRange(0, length, data);
  padded[length] = 0x80;
  final bits = length * 8;
  final view = ByteData.sublistView(padded)
    ..setUint32(padded.length - 8, bits ~/ 0x100000000)
    ..setUint32(padded.length - 4, bits & 0xffffffff);
  final h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final w = Uint32List(64);
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  for (var block = 0; block < padded.length; block += 64) {
    for (var t = 0; t < 16; t++) {
      w[t] = view.getUint32(block + 4 * t);
    }
    for (var t = 16; t < 64; t++) {
      final s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var t = 0; t < 64; t++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final t1 = (hh + s1 + ch + _k[t] + w[t]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    for (final (i, v) in [a, b, c, d, e, f, g, hh].indexed) {
      h[i] = (h[i] + v) & 0xffffffff;
    }
  }
  return [for (final v in h) v.toRadixString(16).padLeft(8, '0')].join();
}
