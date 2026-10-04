---
id: TASK-kmc90l
title: Switch the parity oracle to gem 2.0.26 and re-baseline benchmarks
status: backlog
type: task
priority: 1
labels:
- retarget
parent: EPIC-9frzpm
deps:
- TASK-ncfxdm
- TASK-qvp29w
- TASK-nc7zn5
- TASK-1wwqwn
created: "2026-10-04T13:42:23.176573Z"
updated: "2026-10-04T13:42:23.176573Z"
---

Diff upstream test/ v2.0.26 vs 30fb8cd5 and revert Dart test expectations / drop 2.1-only tests. Remove the --log-level probe/skip (test/e2e/helpers.bash) and the 3 --log-level e2e tests. Differential vs gem must be 96/96 identical (32 files x 3 backends). CI: pin gem 2.0.26, add gem-vs-Dart differential to the e2e job. Rewrite benchmark/PARITY.md, re-run benchmarks and update BASELINE.md, add adr/0003-target-latest-stable.md.