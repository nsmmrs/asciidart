---
id: TASK-c004km
title: "Port CLI (options + invoker, flag parity)"
status: backlog
type: task
priority: 2
labels:
- phase-6
- cli
parent: EPIC-ckgkd2
deps:
- TASK-qrphvp
created: "2026-10-03T06:08:56.555203Z"
updated: "2026-10-03T06:08:56.555203Z"
---

Port cli/options.rb + cli/invoker.rb; ~30 flags (backends, doctypes, safe modes, templates, log/failure levels, timings, sourcemap). Cucumber .feature files become E2E CLI checks. Gate: invoker/options tests (122 blocks) green.