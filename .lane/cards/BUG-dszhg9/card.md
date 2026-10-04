---
id: BUG-dszhg9
title: CLI crashes with an unhandled FileSystemException when stdout is closed early
status: done
type: bug
priority: 2
labels:
- cli
created: "2026-10-04T14:09:40.412731Z"
updated: "2026-10-04T18:00:08.932189Z"
---


Repro: `build/asciidoctor --version | head -0` (or any output piped into a reader that exits early) prints an unhandled 'FileSystemException: writeFrom failed ... Broken pipe, errno = 32' stack trace from CliOptions.printVersion / stdout writes. The gem exits quietly. Fix in runCli/runCliCode: treat EPIPE on stdout as a normal early exit (no trace), and add a test. Found while verifying the version card.