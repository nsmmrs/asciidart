#!/usr/bin/env bash
# Refresh vendor/asciidoctor-pdf/ from the asciidoctor-pdf release the PDF
# backend matches (see vendor/README.md), then regenerate the embedded
# assets (lib/src/pdf/assets.g.dart).
#
# Usage: tool/vendor_asciidoctor_pdf.sh [GEM_HOME]
#   GEM_HOME  a gem home with asciidoctor-pdf 2.3.27 installed (default: a
#             temporary one, installed with `gem install`)
#
# Vendored: the bundled themes and fonts (data/); the icon fonts the gem
# uses through prawn-icon 3.0.0 (Font Awesome Free 5.15.1, Foundation
# Icons 3, PaymentFont), with their licenses and maps of icon names to
# code points written here (icons/<set>.tsv): Font Awesome's from the
# fonts' own glyph names, Foundation Icons' and PaymentFont's from their
# projects' MIT-licensed style sheets (prawn-icon's own files are not
# vendored); and from the v2.3.27 tag the spec suite (spec/*.rb,
# spec/spec_helper, spec/fixtures; not the reference PNGs) and the
# examples, which tool/pdf_parity.dart converts with the gem and with
# asciidart. Needs python3 with fontTools.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=2.3.27
icon_version=3.0.0

gem_home="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -z "$gem_home" ]; then
  gem_home="$tmp/gems"
  gem install --no-document --install-dir "$gem_home" \
    asciidoctor:2.0.26 "asciidoctor-pdf:$version" > /dev/null
fi
gem_dir="$gem_home/gems/asciidoctor-pdf-$version"
icon_dir="$gem_home/gems/prawn-icon-$icon_version"
for dir in "$gem_dir" "$icon_dir"; do
  [ -d "$dir" ] || { echo "vendor_asciidoctor_pdf: $dir not found" >&2; exit 1; }
done

out="$tmp/out"
mkdir -p "$out/data" "$out/icons" "$out/test"
cp -R "$gem_dir/data/themes" "$gem_dir/data/fonts" "$out/data/"
cp "$gem_dir/LICENSE" "$out/LICENSE"
for set in fab far fas fi pf; do
  mkdir -p "$out/icons/$set"
  cp "$icon_dir/data/fonts/$set/"*.ttf "$icon_dir/data/fonts/$set/LICENSE" \
    "$out/icons/$set/"
done
curl -sSfL -o "$tmp/fi.css" \
  https://raw.githubusercontent.com/zurb/foundation-icon-fonts/master/foundation-icons.css
curl -sSfL -o "$tmp/pf.css" \
  https://raw.githubusercontent.com/AlexanderPoellmann/PaymentFont/master/css/paymentfont.css
python3 - "$out/icons" "$tmp" "$icon_dir/data/fonts" <<'PY'
import re, sys
from fontTools.ttLib import TTFont
icons, tmp, prawn = sys.argv[1:4]
def write(name, entries):
    with open(f'{icons}/{name}.tsv', 'w') as f:
        for icon, cp in sorted(entries.items()):
            f.write(f'{icon}\t{cp:x}\n')
    # The same icons as prawn-icon's map (its names minus the font's
    # version entry), so nothing the gem draws is missing.
    theirs = [l.split(':')[0].strip() for l in open(f'{prawn}/{name}/{name}.yml')
              if l.startswith('  ') and not l.strip().startswith('__')]
    missing = set(theirs) - set(entries)
    print(f'{name}: {len(entries)} icons, not in the font: {sorted(missing)}')
for name, file in [('fas', 'fa-solid'), ('far', 'fa-regular'), ('fab', 'fa-brands')]:
    font = TTFont(f'{icons}/{name}/{file}.ttf')
    write(name, {g: cp for cp, g in font.getBestCmap().items()
                 if not re.fullmatch(r'uni[0-9A-F]{4,6}', g)
                 and g not in ('.notdef', 'space')})
for name in ('fi', 'pf'):
    css = open(f'{tmp}/{name}.css').read()
    entries = {}
    for selectors, code in re.findall(r'([^{}]+)\{[^}]*content:\s*"\\([0-9a-fA-F]+)"', css):
        for icon in re.findall(rf'\.{name}-([\w-]+):before', selectors):
            entries[icon] = int(code, 16)
    if name == 'pf':
        # prawn-icon names U+F01E "gpb" (the style sheet: "gbp"); documents
        # written for the gem may use either.
        entries['gpb'] = entries['gbp']
    write(name, entries)
PY

git init -q "$tmp/repo"
git -C "$tmp/repo" remote add origin https://github.com/asciidoctor/asciidoctor-pdf.git
git -C "$tmp/repo" fetch -q --depth 1 origin "refs/tags/v$version"
git -C "$tmp/repo" checkout -q FETCH_HEAD
mkdir -p "$out/test/spec"
cp "$tmp/repo/spec/"*.rb "$out/test/spec/"
cp -R "$tmp/repo/spec/spec_helper" "$tmp/repo/spec/fixtures" "$out/test/spec/"
cp -R "$tmp/repo/examples" "$out/test/examples"

rm -rf "$root/vendor/asciidoctor-pdf"
mv "$out" "$root/vendor/asciidoctor-pdf"
echo "vendor_asciidoctor_pdf: vendored asciidoctor-pdf $version, prawn-icon $icon_version"
