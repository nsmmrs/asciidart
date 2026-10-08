#!/usr/bin/env bash
# Clones the Ruby profiles' Asciidoctor checkouts (profiles.toml) into
# $ASCII_DOCS_CACHE/refs and installs the gems the worker loads into an
# isolated GEM_HOME ($ASCII_DOCS_CACHE/gems).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache="${ASCII_DOCS_CACHE:-$HOME/.cache/ascii-docs}"
mkdir -p "$cache/refs" "$cache/gems"
# name repo commit, one per Ruby profile
awk '
  /^\[/ { name = $0; gsub(/[\[\]"]/, "", name); kind = repo = commit = "" }
  /^kind *=/ { kind = $3; gsub(/"/, "", kind) }
  /^repo *=/ { repo = $3; gsub(/"/, "", repo) }
  /^commit *=/ { commit = $3; gsub(/"/, "", commit); if (kind == "ruby") print name, repo, commit }
' "$root/profiles.toml" | while read -r name repo commit; do
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
done
export GEM_HOME="$cache/gems" GEM_PATH="$cache/gems"
for gem in logger:1.7.0 base64:0.3.0 cgi:0.5.2 rouge:3.30.0 coderay:1.1.3 asciimath:2.0.6; do
  name="${gem%%:*}" version="${gem##*:}"
  gem list -i "^$name$" -v "$version" >/dev/null || gem install -q --no-document "$name" -v "$version"
done
echo "gems: $GEM_HOME"
