---
id: BUG-jlr4kn
title: CLI error output includes Dart exception class prefixes
status: done
type: bug
priority: 2
labels:
- cli
- parity
created: "2026-10-04T14:36:39.770662Z"
updated: "2026-10-04T18:00:08.917145Z"
---


Repro: `echo hi | asciidoctor -b pdf -o - -` prints 'UnimplementedError: asciidoctor: FAILED: missing converter for backend 'pdf'. Processing aborted.' where Asciidoctor 2.0.26 prints the message without a prefix. Cause: Invoker reports failures with e.toString(), which adds Dart prefixes (UnimplementedError:, Bad state:, Invalid argument(s):). Fix: report the error's message, matching Asciidoctor's rendering (plain message; Asciidoctor appends ' (RuntimeError)' only for RuntimeError), and add e2e cases for unknown backend and other fatal paths. Also reconsider throwing UnimplementedError for a missing converter (it is a user error, not unported code).