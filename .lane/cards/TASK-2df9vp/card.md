---
id: TASK-2df9vp
title: "Spike: Ruby Onigmo vs Dart RegExp semantic gaps"
status: done
type: task
priority: 2
labels:
- spike
- phase-1
parent: EPIC-ckgkd2
deps:
- TASK-ffdnc8
created: "2026-10-03T06:08:56.145435Z"
updated: "2026-10-03T07:55:00.685087Z"
---



Advisory: catalog regexp gaps hitting rx.rb/parser/substitutors (lookbehind, possessive quantifiers, encoding behavior). Output: gap list + rewrite rules for the port. Informs foundation + parser work; blocks nothing.