#!/usr/bin/env bash
# Installs the oracles test/latex_oracles_test.dart compares plain_math's
# LaTeX with: Temml 0.14.0 and KaTeX 0.19.0 (needs Node.js and npm).
set -euo pipefail
cd "$(dirname "$0")"
(cd latex && npm ci --silent)
