---
id: TASK-03yrhq
title: "Minimal public API: split libraries, hide internals"
status: backlog
type: task
priority: 2
labels:
- release
created: "2026-10-04T13:42:23.192659Z"
updated: "2026-10-04T13:42:23.192659Z"
---

Replace the bare barrel exports with show-lists across asciidoctor.dart (load/convert, AST, logging, SafeMode, Compliance), extensions.dart, converter.dart, syntax_highlighter.dart, cli.dart (runCli). Hide core_ext (leaks String/Map/RegExp extensions), rx, parser, substitutors, CLI internals, etc. Completeness: dartdoc 0 no-canonical-found warnings. Add meta; @internal on cross-file-only members of exported classes. Update bin/, init-config scaffold, doc/templates.md, README, example. Plan: /home/nes/.claude/plans/gentle-prancing-ritchie.md section B.