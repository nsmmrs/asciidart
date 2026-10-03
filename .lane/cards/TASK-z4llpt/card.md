---
id: TASK-z4llpt
title: "Distribution tooling: CI e2e-on-Dart, native-exe builds, pubspec readiness (NO publishing)"
status: done
type: task
priority: 2
labels:
- phase-8
- release
parent: EPIC-ckgkd2
created: "2026-10-03T06:08:56.698029Z"
updated: "2026-10-03T11:06:23.346867Z"
---




pub publish config; dart compile exe matrix (Win/Mac/Linux x arch) with GitHub release archives; dart compile js npm package; CI mirroring ci.yml (multi-OS, lint, corpus gate); install docs.