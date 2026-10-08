#!/usr/bin/env bash
# Installs the oracle test/harfbuzz_test.dart compares plain_typesetting's
# shaping with: HarfBuzz (harfbuzzjs 1.6.3, WebAssembly; needs Node.js and
# npm).
set -euo pipefail
cd "$(dirname "$0")"
(cd harfbuzz && npm ci --silent)
