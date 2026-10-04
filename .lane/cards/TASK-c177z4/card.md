---
id: TASK-c177z4
title: "Version identity: report 2.0.26 and add asciidoctor-dart-version"
status: backlog
type: task
priority: 2
labels:
- release
deps:
- EPIC-9frzpm
created: "2026-10-04T13:42:23.212685Z"
updated: "2026-10-04T13:42:23.212685Z"
---

Asciidoctor.version = '2.0.26' (feeds {asciidoctor-version}, generator meta, manpage Generator); add Asciidoctor.packageVersion = '0.1.0' (test it equals pubspec), asciidoctor-dart-version attribute, and 'asciidoctor-dart 0.1.0' on the --version runtime line (line 1 stays byte-identical to the gem). Plan: /home/nes/.claude/plans/gentle-prancing-ritchie.md section C.