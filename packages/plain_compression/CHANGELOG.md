# Changelog

## 0.1.0-dev (unreleased)

- Faster checksums, same values: CRC-32 slices by 8 and Adler-32 reads
  typed bytes eight at a time.
- A table-driven inflater (two-level tables, output written in place,
  stored blocks copied whole): 3-5x faster on compressed data, 25x on
  stored blocks; the same errors for damaged streams. A large result
  (256 KiB or more) is a view of a larger buffer.
- The Brotli dictionary is base64-decoded by dart:convert: its first use
  takes about 1 ms, not 7.
- A faster encoder writing the same bytes: rolling hash, zlib's quick
  match rejection and distance-code table, word compares, typed block
  tables and one bit buffer: 1.4x on text, 2x on images, 6x stored.
- A faster Brotli decoder: a bit buffer, two-level prefix-code tables and
  a literal loop that keeps its context: 1.35-1.5x.
- CRC-32, gzip (RFC 1952) and ZIP archives: a reproducible writer and a
  bounds-checked reader, both with ZIP64. They come from ptome's EPUB
  writer; plain_pdf's PNG reader and ptome's EPUB use them.
- Renamed from `compression` to `plain_compression`, and moved with its
  history into the ptome pub workspace (github.com/nsmmrs/ptome,
  `packages/plain_compression`; ptome's ADR-0018).
- DEFLATE (with dynamic Huffman codes, and inflate), zlib and Adler-32,
  extracted from plain_pdf with their history.
- A Brotli decoder (RFC 7932), whose dictionary and transforms are
  generated from google/brotli 1.2.0, the dictionary checked against the
  RFC's SHA-256.
