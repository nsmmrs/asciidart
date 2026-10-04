---
id: TASK-vvk9z0
title: "Node parity gates: bats e2e + differential on the Node CLI, dart test -p node"
status: backlog
type: task
priority: 2
labels:
- npm
- js
- parity
parent: EPIC-2qq14f
deps:
- TASK-s39q3t
created: "2026-10-04T13:59:03.825570Z"
updated: "2026-10-04T13:59:03.825570Z"
---

Reuse existing tools. Add `test/e2e/bin/asciidoctor-node` shim (`node build/npm/bin/asciidoctor-dart.js "$@"`); full bats suite must pass with ASCIIDOCTOR_EXE pointing at it. `tool/differential.dart --exe-a asciidoctor --exe-b "node .../asciidoctor-dart.js"` on html5/docbook5/manpage: 96/96 vs gem 2.0.26 once EPIC-9frzpm lands (before that, compare against the Dart VM exe).

Run `dart test -p node` across the Dart suite to catch JS-semantics drift (int range/bit ops, regex, number formatting); tag test files whose own code uses dart:io with @TestOn('vm'). Record counts in a comment.