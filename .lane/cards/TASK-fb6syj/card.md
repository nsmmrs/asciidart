---
id: TASK-fb6syj
title: Publish 0.1.0 to pub.dev
status: backlog
type: task
priority: 2
labels:
- release
deps:
- TASK-03yrhq
- TASK-c177z4
- TASK-zs44d6
- TASK-67yl6b
- BUG-fwc380
created: "2026-10-04T13:42:23.246900Z"
updated: "2026-10-04T14:32:48.242035Z"
---



From green master: manual `dart pub publish` (first publish must be manual), tag v0.1.0 + push, enable pub.dev automated publishing for nsmmrs/asciidoctor-dart (tag pattern v{{version}}), create GitHub Release (optionally attach tool/build-exes.sh binaries + SHA256SUMS). Outward-facing: only on explicit go-ahead.