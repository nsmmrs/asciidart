#!/bin/sh
# Fake converter A: canned output with one line differing from exe-b.sh.
# Ignores its arguments (the harness passes backend/outfile/quiet/input).
printf '%s\n' 'line one' 'line two' 'line three from A' 'line four' 'line five'
