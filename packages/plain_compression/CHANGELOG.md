# Changelog

## 0.1.0-dev (unreleased)

- DEFLATE (with dynamic Huffman codes, and inflate), zlib and Adler-32,
  extracted from libpdf with their history.
- A Brotli decoder (RFC 7932), whose dictionary and transforms are
  generated from google/brotli 1.2.0, the dictionary checked against the
  RFC's SHA-256.
