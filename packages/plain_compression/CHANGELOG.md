# Changelog

## 0.1.0-dev (unreleased)

- Renamed from `compression` to `plain_compression`, and moved with its
  history into the ptome pub workspace (github.com/nsmmrs/ptome,
  `packages/plain_compression`; ptome's ADR-0018).
- DEFLATE (with dynamic Huffman codes, and inflate), zlib and Adler-32,
  extracted from plain_pdf with their history.
- A Brotli decoder (RFC 7932), whose dictionary and transforms are
  generated from google/brotli 1.2.0, the dictionary checked against the
  RFC's SHA-256.
