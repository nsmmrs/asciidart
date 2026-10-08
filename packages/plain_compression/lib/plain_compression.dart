/// plain_compression: DEFLATE (RFC 1951) with its zlib (RFC 1950) and gzip
/// (RFC 1952) wrappers, which compress to the same bytes on every
/// platform; a Brotli decoder (RFC 7932); CRC-32; and ZIP archives, a
/// reproducible writer and a reader. Pure Dart, without dependencies, so it
/// runs on the Dart VM and compiled to JavaScript alike.
library;

export 'src/brotli.dart' show brotliDecode;
export 'src/crc32.dart' show crc32;
export 'src/flate.dart' show adler32, deflate, inflate, zlibDecode, zlibEncode;
export 'src/gzip.dart' show gzipDecode, gzipEncode;
export 'src/zip.dart' show ZipEntry, ZipMethod, ZipWriter, readZip;
