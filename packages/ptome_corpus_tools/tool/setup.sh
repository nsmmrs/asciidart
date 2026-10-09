#!/usr/bin/env bash
# Installs what the tools run:
# - the bundle that makes the corpus's goldens (goldens/<release>/Gemfile.lock),
#   in $ASCII_DOCS_CACHE/bundle-<release>;
# - the Asciidoctor checkouts the pool, anchor and fuzz commands use, in
#   $ASCII_DOCS_CACHE/refs, with their gems in $ASCII_DOCS_CACHE/gems.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache="${ASCII_DOCS_CACHE:-$HOME/.cache/ascii-docs}"
mkdir -p "$cache/refs" "$cache/gems"

for gemfile in "$root"/goldens/*/Gemfile; do
  release="$(basename "$(dirname "$gemfile")")"
  BUNDLE_GEMFILE="$gemfile" BUNDLE_PATH="$cache/bundle-$release" bundle install --quiet
  echo "$release: $cache/bundle-$release"
done

while read -r name commit; do
  target="$cache/refs/$name"
  if [ ! -d "$target/.git" ]; then
    git init -q "$target"
    git -C "$target" remote add origin https://github.com/asciidoctor/asciidoctor.git
  fi
  if [ "$(git -C "$target" rev-parse -q --verify HEAD || true)" != "$commit" ]; then
    git -C "$target" fetch -q --depth 1 origin "$commit"
    git -C "$target" checkout -q --detach FETCH_HEAD
  fi
  echo "$name: $(git -C "$target" rev-parse --short HEAD)"
done <<'REFS'
asciidoctor-2.0.26 0b99b39c9df884d4aec13bba45f03cdbab505769
asciidoctor-main 30fb8cd5f7145c57274b04524ceaa99812f830e0
REFS
export GEM_HOME="$cache/gems" GEM_PATH="$cache/gems"
for gem in logger:1.7.0 base64:0.3.0 cgi:0.5.2 rouge:3.30.0 coderay:1.1.3 asciimath:2.0.6 \
    minitest:5.27.0 nokogiri:1.19.4 erubi:1.13.1 haml:6.4.0 slim:5.2.2 tilt:2.9.0 \
    concurrent-ruby:1.3.8 net-ftp:0.3.9 open-uri-cached:2.0.0 ostruct:0.6.3 rake:13.4.2; do
  name="${gem%%:*}" version="${gem##*:}"
  gem list -i "^$name$" -v "$version" >/dev/null || gem install -q --no-document "$name" -v "$version"
done
echo "gems: $GEM_HOME"
