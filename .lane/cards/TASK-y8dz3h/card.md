---
id: TASK-y8dz3h
title: "Add Dart CI jobs (analyze/test/bats/diff)"
status: doing
type: task
priority: 2
labels:
- ci
parent: EPIC-ckgkd2
created: "2026-10-03T09:27:18.510038Z"
updated: "2026-10-03T09:27:26.331828Z"
---


New dart job in ci.yml (Dart stable): pub get, analyze, test, bats e2e + selfcheck. Do not touch Ruby jobs. Validate: yaml parses + local simulation green.