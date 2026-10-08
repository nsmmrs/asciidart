/// compression: DEFLATE (RFC 1951) and its zlib wrapper (RFC 1950), which
/// compress to the same bytes on every platform, and a Brotli decoder
/// (RFC 7932). Pure Dart, without dependencies, so they run on the Dart VM
/// and compiled to JavaScript alike.
library;

export 'src/brotli.dart' show brotliDecode;
export 'src/flate.dart' show adler32, deflate, inflate, zlibDecode, zlibEncode;
