#!/usr/bin/env bash
# Build the npm package (asciidart) into build/npm.
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
dart compile js ${DART2JS_FLAGS:--O2} --no-source-maps \
  -o "$tmp/core.js" "$root/lib/src/js/entry.dart" >/dev/null
# Keep the core working when bundlers rename its functions.
node "$root/tool/npm_pin_names.mjs" "$tmp/core.js" >/dev/null
# Let the core load its parts where it has no script of its own.
node "$root/tool/npm_current_script.mjs" "$tmp/core.js" >/dev/null
cp -R "$root/npm/." "$out/"
rm "$out/preamble.js"
# The parts of the core that load on demand (the PDF and EPUB backends):
# each an ES module whose function runs the part, loaded by a hook with a
# literal import() per part, so that bundlers split them out too.
mkdir -p "$out/parts"
loader="$tmp/loader.js"
{
  echo '// The table the core and its parts share their code through (a global'
  echo '// in a script, a variable of this module here).'
  echo 'var $__dart_deferred_initializers__ ='
  echo '  (self.$__dart_deferred_initializers__ = {})'
  echo '// Loads the parts of the core compiled to load on demand.'
  echo 'self.dartDeferredLibraryLoader = function (uri, onLoad, onError) {'
  echo "  var name = uri.slice(uri.lastIndexOf('/') + 1).replace(/\\?.*\$/, '')"
  echo '  var parts = {'
  for part in "$tmp"/core.js_*.part.js; do
    [ -e "$part" ] || continue
    base="$(basename "$part")"
    n="${base#core.js_}"; n="${n%.part.js}"
    {
      echo 'export default function (self, $__dart_deferred_initializers__) {'
      cat "$part"
      echo '}'
    } > "$out/parts/part-$n.js"
    echo "    '$base': function () { return import('./parts/part-$n.js') },"
  done
  echo '  }'
  echo '  var part = parts[name]'
  echo "  if (!part) return onError(new Error('asciidart: no part ' + name))"
  echo '  part().then(function (module) {'
  echo '    module.default(self, $__dart_deferred_initializers__)'
  echo '    onLoad()'
  echo '  }, onError)'
  echo '};'
} > "$loader"
cat "$root/npm/preamble.js" "$loader" "$tmp/core.js" > "$out/asciidart.js"
cp "$root/LICENSE" "$out/LICENSE"
# CommonJS copies of the type declarations, for require().
for decl in "$out"/types/*.d.ts; do
  sed "s#'\./\([a-z]*\)\.js'#'./\1.cjs'#g" "$decl" > "${decl%.d.ts}.d.cts"
done
chmod +x "$out/bin/asciidart.js"
echo "build-npm: built asciidart $version in $out"
