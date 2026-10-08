#!/usr/bin/env bash
# Checks the upstream bug reproductions in test/bugfix: every test must pass
# on the ptome CLI and fail on the Ruby CLI (the bug is still upstream).
#
#   tool/bugfix_check.sh PTOME_EXE RUBY_EXE [TEST.bats...]
set -u
# A file that hangs (an endless loop in a fix) fails instead of stalling.
bats_path=$(type -P bats)
bats() { timeout 120 "$bats_path" "$@"; }
dart_exe=$1 ruby_exe=$2
shift 2
cd "$(dirname "$0")/.."
tests=("$@")
[ ${#tests[@]} -gt 0 ] || tests=(test/bugfix/*.bats)
status=0
for t in "${tests[@]}"; do
  if ! ASCIIDOCTOR_EXE=$dart_exe bats "$t" > /dev/null 2>&1; then
    echo "FAIL $t: does not pass on ptome"
    ASCIIDOCTOR_EXE=$dart_exe bats "$t" | sed 's/^/    /'
    status=1
  fi
  # Every test case of the file must fail on Ruby, except the guards named
  # "unchanged: ..." (behavior around the fix that must stay as it is).
  passed=$(ASCIIDOCTOR_EXE=$ruby_exe bats --formatter tap "$t" 2>/dev/null |
    grep '^ok ' | grep -vc '^ok [0-9]* unchanged: ')
  if [ "$passed" -ne 0 ]; then
    echo "FAIL $t: $passed test(s) pass on Ruby (not a reproduction)"
    status=1
  fi
done
[ $status -eq 0 ] && echo "bugfix_check: ${#tests[@]} file(s) ok"
exit $status
