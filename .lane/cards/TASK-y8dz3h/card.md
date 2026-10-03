---
id: TASK-y8dz3h
title: "Add Dart CI jobs (analyze/test/bats/diff)"
status: done
type: task
priority: 2
labels:
- ci
parent: EPIC-ckgkd2
created: "2026-10-03T09:27:18.510038Z"
updated: "2026-10-03T09:31:31.917552Z"
---



New dart job in ci.yml (Dart stable): pub get, analyze, test, bats e2e + selfcheck. Do not touch Ruby jobs. Validate: yaml parses + local simulation green.