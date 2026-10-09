#!/usr/bin/env bash
# Clones the Ruby profiles' Asciidoctor checkouts (the corpus's profiles.toml)
# into $ASCII_DOCS_CACHE/refs and installs the gems the worker loads into an
# isolated GEM_HOME ($ASCII_DOCS_CACHE/gems); a profile with gems of its own
# gets them alone in $ASCII_DOCS_CACHE/gems-<profile>.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache="${ASCII_DOCS_CACHE:-$HOME/.cache/ascii-docs}"
mkdir -p "$cache/refs" "$cache/gems"
profiles="$root/../ptome/test/corpus/profiles.toml"
# name repo commit gems, one per Ruby profile
awk '
  function flush() { if (kind == "ruby") print name, repo, commit, (gems == "" ? "-" : gems) }
  /^\[/ && !/^\[[a-z0-9.-]+\.attributes\]/ { flush(); name = $0; gsub(/[\[\]"]/, "", name); kind = repo = commit = gems = "" }
  /^kind *=/ { kind = $3; gsub(/"/, "", kind) }
  /^repo *=/ { repo = $3; gsub(/"/, "", repo) }
  /^commit *=/ { commit = $3; gsub(/"/, "", commit) }
  /^gems *=/ { gems = $0; sub(/^gems *= *\[/, "", gems); sub(/\].*/, "", gems); gsub(/[" ]/, "", gems) }
  END { flush() }
' "$profiles" | while read -r name repo commit gems; do
  target="$cache/refs/$name"
  if [ ! -d "$target/.git" ]; then
    git init -q "$target"
    git -C "$target" remote add origin "$repo"
  fi
  if [ "$(git -C "$target" rev-parse -q --verify HEAD || true)" != "$commit" ]; then
    git -C "$target" fetch -q --depth 1 origin "$commit"
    git -C "$target" checkout -q --detach FETCH_HEAD
  fi
  echo "$name: $(git -C "$target" rev-parse --short HEAD)"
  if [ "$gems" != - ]; then
    home="$cache/gems-$name"
    for gem in ${gems//,/ }; do
      gname="${gem%%:*}" version="${gem##*:}"
      GEM_HOME="$home" GEM_PATH="$home" gem list -i "^$gname$" -v "$version" >/dev/null ||
        GEM_HOME="$home" GEM_PATH="$home" gem install -q --no-document "$gname" -v "$version"
    done
    echo "$name gems: $home"
  fi
done
export GEM_HOME="$cache/gems" GEM_PATH="$cache/gems"
# The worker's optional gems, then what Asciidoctor's own test suite needs
# (the pool captures the inputs its tests convert).
for gem in logger:1.7.0 base64:0.3.0 cgi:0.5.2 rouge:3.30.0 coderay:1.1.3 asciimath:2.0.6 \
    minitest:5.27.0 nokogiri:1.19.4 erubi:1.13.1 haml:6.4.0 slim:5.2.2 tilt:2.9.0 \
    concurrent-ruby:1.3.8 net-ftp:0.3.9 open-uri-cached:2.0.0 ostruct:0.6.3 rake:13.4.2; do
  name="${gem%%:*}" version="${gem##*:}"
  gem list -i "^$name$" -v "$version" >/dev/null || gem install -q --no-document "$name" -v "$version"
done
echo "gems: $GEM_HOME"
