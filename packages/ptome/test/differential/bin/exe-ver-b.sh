#!/bin/sh
# Fake converter B: stamps only; must normalize identical to exe-ver-a.sh.
printf '%s\n' \
  '<meta name="generator" content="Asciidoctor 0.1.0">' \
  'Last updated 1999-12-31 23:59:59 +0000' \
  'body text here'
