#!/usr/bin/env bash
# Resolves each workspace package on its own, against the published versions
# of its sibling packages (ADR-0018). Inside the workspace siblings always
# resolve locally, so a missing version bump would go unnoticed; this check
# catches it. A package whose siblings aren't all on pub.dev yet is skipped.
#
#   tool/standalone.sh [package...]    (default: every package)
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
packages=("$@")
[ ${#packages[@]} -gt 0 ] || packages=($(ls packages))
siblings=" $(ls packages | tr '\n' ' ') "
status=0
for pkg in "${packages[@]}"; do
  dir="packages/$pkg"
  # The siblings this package depends on (dependencies and dev_dependencies).
  deps=$(awk '/^(dependencies|dev_dependencies):/{on=1; next} /^[^ ]/{on=0}
              on && /^  [a-z_]+:/{sub(":.*", "", $1); print $1}' "$dir/pubspec.yaml")
  missing=""
  for dep in $deps; do
    [[ "$siblings" == *" $dep "* ]] || continue
    code=$(curl -s -o /dev/null -w '%{http_code}' "https://pub.dev/api/packages/$dep")
    [ "$code" = 200 ] || missing="$missing $dep"
  done
  if [ -n "$missing" ]; then
    echo "skip $pkg: not on pub.dev yet:$missing"
    continue
  fi
  echo "== $pkg"
  printf 'resolution:\n' > "$dir/pubspec_overrides.yaml"
  if (cd "$dir" && dart pub get && dart analyze --fatal-infos .); then
    echo "ok $pkg"
  else
    echo "FAILED $pkg resolves or analyzes differently on its own"
    status=1
  fi
  rm -f "$dir/pubspec_overrides.yaml"
done
exit $status
