#!/usr/bin/env bash
# Build standalone release executables for the Dart Asciidoctor CLI.
#
# Release TOOLING only: this script compiles a native executable with
# `dart compile exe` and writes a SHA256SUMS file next to it. It never
# publishes anywhere (no pub registry, no npm/JS — see adr/0001).
#
# Usage:
#   tool/build-exes.sh [--output-dir DIR] [--os NAME] [--arch NAME]
#
# `dart compile exe` always builds for the HOST platform, so --os/--arch only
# override the filename label (best-effort for macOS/Windows naming; produce
# those artifacts by running this script on the respective host).
#
# Output: <output-dir>/asciidoctor-<os>-<arch>[.exe] plus SHA256SUMS.
set -euo pipefail

OUTPUT_DIR="dist"
OS_OVERRIDE=""
ARCH_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: tool/build-exes.sh [--output-dir DIR] [--os NAME] [--arch NAME]

Build a standalone release executable for the Dart Asciidoctor CLI with
`dart compile exe` (tooling only; never publishes anywhere).

`dart compile exe` always builds for the HOST platform, so --os/--arch only
override the filename label (best-effort for macOS/Windows naming; produce
those artifacts by running this script on the respective host).

Output: <output-dir>/asciidoctor-<os>-<arch>[.exe] plus SHA256SUMS.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --output-dir=*) OUTPUT_DIR="${1#*=}"; shift ;;
    --os) OS_OVERRIDE="$2"; shift 2 ;;
    --os=*) OS_OVERRIDE="${1#*=}"; shift ;;
    --arch) ARCH_OVERRIDE="$2"; shift 2 ;;
    --arch=*) ARCH_OVERRIDE="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

detect_os() {
  case "$(uname -s)" in
    Linux*) echo linux ;;
    Darwin*) echo macos ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) echo windows ;;
    *) echo "$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo x64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo "$(uname -m)" ;;
  esac
}

OS="${OS_OVERRIDE:-$(detect_os)}"
ARCH="${ARCH_OVERRIDE:-$(detect_arch)}"
EXT=""
[ "$OS" = "windows" ] && EXT=".exe"

mkdir -p "$OUTPUT_DIR"
OUT="$OUTPUT_DIR/asciidoctor-$OS-$ARCH$EXT"

command -v dart >/dev/null || { echo "error: 'dart' is not on PATH" >&2; exit 1; }

echo "==> dart pub get"
dart pub get --directory=dart

echo "==> dart compile exe -> $OUT"
dart compile exe dart/bin/asciidoctor.dart -o "$OUT"

echo "==> sha256sum"
(cd "$OUTPUT_DIR" && sha256sum asciidoctor-* > SHA256SUMS)
cat "$OUTPUT_DIR/SHA256SUMS"

echo "built: $OUT"
