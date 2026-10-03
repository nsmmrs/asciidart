---
id: TASK-1b31rr
title: "Port foundation: rx, helpers, core_ext, paths, locales, stylesheets"
status: done
type: task
priority: 1
labels:
- phase-1
- core
parent: EPIC-ckgkd2
deps:
- TASK-ffdnc8
- TASK-y8y4t3
created: "2026-10-03T06:08:56.125938Z"
updated: "2026-10-03T08:35:28.620049Z"
---




Port rx.rb (728 lines), helpers, core_ext, path_resolver, attribute_list, callouts. Embed data/locale (37 files) + stylesheets as resources. Quarantine Ruby-regexp-vs-Dart-RegExp gaps here. Gate: foundation behavior tests green.