#!/usr/bin/env bash
# Installs the oracle test/oracles_test.dart compares plain_hyphenation
# with: Hyphenopoly 6.0.0 (JavaScript and WebAssembly; needs Node.js and
# npm).
set -euo pipefail
cd "$(dirname "$0")"
(cd hyphenopoly && npm ci --silent)
