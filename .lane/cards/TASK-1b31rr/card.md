---
id: TASK-1b31rr
title: "Port foundation: rx, helpers, core_ext, paths, locales, stylesheets"
status: backlog
type: task
priority: 1
labels:
- phase-1
- core
parent: EPIC-ckgkd2
deps:
- TASK-ffdnc8
created: "2026-10-03T06:08:56.125938Z"
updated: "2026-10-03T06:08:56.125938Z"
---

Port rx.rb (728 lines), helpers, core_ext, path_resolver, attribute_list, callouts. Embed data/locale (37 files) + stylesheets as resources. Quarantine Ruby-regexp-vs-Dart-RegExp gaps here. Gate: foundation behavior tests green.