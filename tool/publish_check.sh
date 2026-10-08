#!/usr/bin/env bash
# Checks that each workspace package would publish (`dart pub publish
# --dry-run`): no errors and no warnings, except that a package may depend
# on a pre-release of a sibling that hasn't been released yet (its version
# still ends in -dev; libraries are released in dependency order, each with
# its own tag, as RELEASING.md says).
#
#   tool/publish_check.sh [package...]    (default: every package)
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
packages=("$@")
[ ${#packages[@]} -gt 0 ] || packages=($(ls packages))
status=0
for pkg in "${packages[@]}"; do
  out="$(cd "packages/$pkg" && dart pub publish --dry-run 2>&1)"
  code=$?
  # The warnings, one a line, but the expected ones.
  warnings="$(printf '%s\n' "$out" | grep '^\* ' | while read -r line; do
    dep="$(printf '%s' "$line" | sed -n 's/.*needs \([a-z_]*\) version \([^,]*\),.*/\1 \2/p')"
    if [ -n "$dep" ]; then
      set -- $dep
      if [ -f "packages/$1/pubspec.yaml" ] && [[ "$2" == *-dev ]]; then
        continue
      fi
    fi
    printf '%s\n' "$line"
  done)"
  if [ $code -ne 0 ] && [ $code -ne 65 ]; then
    echo "FAILED $pkg (exit $code)"; printf '%s\n' "$out" | tail -20; status=1
  elif [ -n "$warnings" ]; then
    echo "FAILED $pkg"; printf '%s\n' "$warnings"; status=1
  else
    echo "ok $pkg$([ $code -eq 65 ] && echo ' (depends on unreleased siblings)')"
  fi
done
exit $status
