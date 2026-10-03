---
id: TASK-y8y4t3
title: "Port e2e coverage to bats suite (pre-port, runs against any CLI)"
status: doing
type: task
priority: 1
labels:
- phase-0
- e2e
parent: EPIC-ckgkd2
created: "2026-10-03T07:40:33.804749Z"
updated: "2026-10-03T07:41:41.399389Z"
---


No black-box suite exists (cucumber+invoker are in-process Ruby). Port cucumber scenarios + invoker/options cases to test/e2e/*.bats, parameterized by ASCIIDOCTOR_EXE so the same suite runs against the gem exe and the future Dart exe. Gate: green on gem exe before the port starts (ADR-0001 D6).