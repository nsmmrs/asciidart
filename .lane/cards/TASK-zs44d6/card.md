---
id: TASK-zs44d6
title: "Branding, docs, package contents and CI for first release"
status: done
type: task
priority: 2
labels:
- release
deps:
- EPIC-9frzpm
- TASK-03yrhq
- TASK-67yl6b
- TASK-rr7cpv
- TASK-dv2cr4
- TASK-hmq3w2
created: "2026-10-04T13:42:23.230695Z"
updated: "2026-10-04T20:42:48.026060Z"
---



Drop pubspec homepage, unofficial description + README note; rewrite issue templates, delete FUNDING.yml. User-first README + CONTRIBUTING.md; CHANGELOG accuracy; stale dart/ paths; mangled TODO comments; richer example. .pubignore (repeat .gitignore entries; exclude benchmark/tool/test/adr/data/man/PORTING-REGEXP.md; verify -h topics from activated install). CI: publish --dry-run, ubuntu/macos/windows matrix, tag-triggered publish workflow. Plan: /home/nes/.claude/plans/gentle-prancing-ritchie.md section D.