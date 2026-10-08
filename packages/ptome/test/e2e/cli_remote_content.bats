#!/usr/bin/env bats
# Black-box CLI cases for remote content read with -a allow-uri-read:
# includes and data-URI images fetched from a loopback HTTP server.

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
  command -v python3 >/dev/null || skip 'python3 serves the remote content'
}

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir srv
}

teardown() {
  if [ -n "${server_pid:-}" ]; then kill "$server_pid" 2>/dev/null || true; fi
}

# Serves ./srv on a free loopback port, exported as $port.
start_server() {
  port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  python3 -m http.server "$port" --bind 127.0.0.1 --directory srv >/dev/null 2>&1 &
  server_pid=$!
  for _ in $(seq 50); do
    python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/')" 2>/dev/null && return 0
    sleep 0.1
  done
  echo 'HTTP server did not start'
  return 1
}

@test "remote include is read when allow-uri-read is set" {
  printf 'remote *content*\n\ninclude::nested.adoc[]\n' > srv/inc.adoc
  printf 'nested content\n' > srv/nested.adoc
  start_server
  printf 'before\n\ninclude::http://127.0.0.1:%s/inc.adoc[]\n\nafter\n' "$port" > doc.adoc
  run --separate-stderr -- "$EXE" -a allow-uri-read -e -o - doc.adoc
  [ "$status" -eq 0 ]
  assert_output_contains '<p>remote <strong>content</strong></p>'
  assert_output_contains '<p>nested content</p>'
  assert_output_contains '<p>after</p>'
  [ -z "$stderr" ]
}

@test "remote include without allow-uri-read becomes a link" {
  printf 'remote content\n' > srv/inc.adoc
  start_server
  printf 'include::http://127.0.0.1:%s/inc.adoc[]\n' "$port" > doc.adoc
  run --separate-stderr -- "$EXE" -e -o - doc.adoc
  [ "$status" -eq 0 ]
  assert_output_contains "href=\"http://127.0.0.1:$port/inc.adoc\""
  assert_not_contains "$output" 'remote content'
}

@test "missing remote include is reported as unreadable" {
  start_server
  printf 'include::http://127.0.0.1:%s/missing.adoc[]\n' "$port" > doc.adoc
  run --separate-stderr -- "$EXE" -a allow-uri-read -e -o - doc.adoc
  [ "$status" -eq 0 ]
  assert_stderr_contains 'include uri not readable'
}

@test "remote image is embedded as a data URI" {
  printf 'GIF89a' > srv/dot.gif
  start_server
  printf 'image::http://127.0.0.1:%s/dot.gif[Dot]\n' "$port" > doc.adoc
  run --separate-stderr -- "$EXE" -a allow-uri-read -a data-uri -e -o - doc.adoc
  [ "$status" -eq 0 ]
  assert_output_contains 'src="data:image/gif;base64,R0lGODlh"'
}
