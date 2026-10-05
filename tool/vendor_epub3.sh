#!/usr/bin/env bash
# Refresh vendor/asciidoctor-epub3/ from the asciidoctor-epub3 gem the EPUB3
# backend matches (see vendor/README.md), then regenerate the embedded
# assets (lib/src/epub3/assets.g.dart).
#
# Usage: tool/vendor_epub3.sh [GEM_HOME]
#   GEM_HOME  a gem home with asciidoctor-epub3 2.3.0 installed (default: a
#             temporary one, installed with `gem install`)
#
# The gem compiles its SCSS stylesheets at conversion time; the vendored
# copies are compiled here once, with the gem's own Sass engine and options
# (compressed), so they are byte for byte what the gem writes. The Font
# Awesome icon metadata is reduced to the names, code points and renames
# the converter uses.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=2.3.0

gem_home="${1:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -z "$gem_home" ]; then
  gem_home="$tmp/gems"
  gem install --no-document --install-dir "$gem_home" \
    asciidoctor:2.0.26 "asciidoctor-epub3:$version" > /dev/null
fi
gem_dir="$gem_home/gems/asciidoctor-epub3-$version"
[ -d "$gem_dir" ] || { echo "vendor_epub3: $gem_dir not found" >&2; exit 1; }

out="$tmp/out"
mkdir -p "$out/styles" "$out/images" "$out/test"

# The spec fixtures of the release (tool/epub_parity.dart converts them
# with the gem and with asciidart).
git init -q "$tmp/repo"
git -C "$tmp/repo" remote add origin https://github.com/asciidoctor/asciidoctor-epub3.git
git -C "$tmp/repo" fetch -q --depth 1 origin "refs/tags/v$version"
git -C "$tmp/repo" checkout -q FETCH_HEAD
cp -R "$tmp/repo/spec/fixtures" "$out/test/fixtures"
cp "$gem_dir/LICENSE" "$gem_dir/NOTICE.adoc" "$out/"
cp -R "$gem_dir/data/fonts" "$out/fonts"
rm -f "$out/fonts/awesome/icons.yml" "$out/fonts/awesome/shims.yml"
cp "$gem_dir"/data/images/* "$out/images/"

GEM_HOME="$gem_home" GEM_PATH="$gem_home" ruby -e '
  require "sass"
  require "yaml"
  styles, out = ARGV
  %w[epub3 epub3-css3-only epub3-fonts].each do |name|
    scss = File.join styles, "#{name}.scss"
    css = Sass::Engine.new(File.read(scss), syntax: :scss, cache: false,
      load_paths: [styles], style: :compressed).render
    File.write File.join(out, "styles", "#{name}.css"), css
  end
  awesome = File.join styles, "..", "fonts", "awesome"
  icons = YAML.load_file(File.join(awesome, "icons.yml"))
    .to_h { |name, data| [name, data["unicode"]] }
  shims = YAML.load_file(File.join(awesome, "shims.yml"))
    .to_h { |name, data| [name, data["name"]] }
    .reject { |_, target| target.nil? }
  # One line per icon (icon, name, code point) and per renamed icon (shim,
  # old name, new name), tab-separated.
  File.open File.join(out, "fonts", "awesome", "icons.tsv"), "w" do |f|
    icons.each { |name, code| f.puts "icon\t#{name}\t#{code}" }
    shims.each { |name, target| f.puts "shim\t#{name}\t#{target}" }
  end
' "$gem_dir/data/styles" "$out"

rm -rf "$root/vendor/asciidoctor-epub3"
cp -R "$out" "$root/vendor/asciidoctor-epub3"
(cd "$root" && dart run tool/embed_epub3.dart)
echo "vendor_epub3: vendor/asciidoctor-epub3 refreshed from asciidoctor-epub3 $version"
