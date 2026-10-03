---
id: TASK-ffdnc8
title: "Scaffold Dart package + differential harness (Ruby oracle)"
status: done
type: task
priority: 1
labels:
- phase-0
- infra
parent: EPIC-ckgkd2
created: "2026-10-03T06:08:56.108224Z"
updated: "2026-10-03T07:43:51.223434Z"
---



New pub package in-repo; port version/timings/logging. Harness runs Ruby Asciidoctor.convert vs Dart over test/fixtures and diffs stdout/exit. Port benchmark/benchmark.rb for the Ruby baseline first. Gate: harness runs, baseline recorded.