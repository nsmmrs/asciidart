#!/usr/bin/env bash
# Installs the oracle test/temml_test.dart compares plain_math's LaTeX
# with: Temml 0.14.0 (needs Node.js and npm).
set -euo pipefail
cd "$(dirname "$0")"
(cd temml && npm ci --silent)
