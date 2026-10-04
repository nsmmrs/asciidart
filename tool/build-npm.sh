#!/usr/bin/env bash
# Build the npm package (asciidoctor-dart) into build/npm.
#
# Compiles the Dart core to one JavaScript bundle with dart2js and assembles
# it with the checked-in package sources (npm/) and the license. Release
# TOOLING only: it never publishes anything.
#
# Usage: tool/build-npm.sh [--output-dir DIR]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/npm"

while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir) out="$2"; shift 2 ;;
    --output-dir=*) out="${1#*=}"; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "build-npm: unknown argument: $1" >&2; exit 2 ;;
  esac
done

version="$(sed -n 's/^version: //p' "$root/pubspec.yaml")"
package_version="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$root/npm/package.json")"
if [ "$version" != "$package_version" ]; then
  echo "build-npm: npm/package.json version $package_version != pubspec $version" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"
(cd "$root" && dart pub get >/dev/null)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
dart compile js -O2 --no-source-maps \
  -o "$tmp/core.js" "$root/lib/src/js/entry.dart" >/dev/null
cp -R "$root/npm/." "$out/"
rm "$out/preamble.js"
cat "$root/npm/preamble.js" "$tmp/core.js" > "$out/asciidoctor-dart.js"
cp "$root/LICENSE" "$out/LICENSE"
# CommonJS copies of the type declarations, for require().
for decl in "$out"/types/*.d.ts; do
  sed "s#'\./\([a-z]*\)\.js'#'./\1.cjs'#g" "$decl" > "${decl%.d.ts}.d.cts"
done
chmod +x "$out/bin/asciidoctor-dart.js"
echo "build-npm: built asciidoctor-dart $version in $out"
