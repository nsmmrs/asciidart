#!/usr/bin/env bash
# Builds the oracles test/oracles_test.dart compares plain_hyphenation
# with: typst's hypher (Rust; needs cargo) and Hyphenopoly 6.0.0
# (JavaScript and WebAssembly; needs Node.js and npm).
set -euo pipefail
cd "$(dirname "$0")"
(cd hyphenopoly && npm ci --silent)
(cd hypher && cargo build --release --quiet)
