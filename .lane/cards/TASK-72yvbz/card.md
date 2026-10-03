---
id: TASK-72yvbz
title: "Port syntax highlighters (6 adapters)"
status: backlog
type: task
priority: 3
labels:
- phase-7
- highlight
parent: EPIC-ckgkd2
deps:
- TASK-3d1llw
created: "2026-10-03T06:08:56.629905Z"
updated: "2026-10-03T06:08:56.629905Z"
---

Passthroughs first (highlight.js, prettify, html-pipeline); then rouge/coderay/pygments strategy (embed/shell-out/defer). Gate: syntax_highlighter_test.rb (76 blocks) dispositioned.