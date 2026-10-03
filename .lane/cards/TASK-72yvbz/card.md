---
id: TASK-72yvbz
title: "Port syntax-highlighter framework (registry/factory/Document integration)"
status: done
type: task
priority: 3
labels:
- phase-7
- highlight
parent: EPIC-ckgkd2
deps:
- TASK-3d1llw
created: "2026-10-03T06:08:56.629905Z"
updated: "2026-10-03T10:23:33.076069Z"
---




Passthroughs first (highlight.js, prettify, html-pipeline); then rouge/coderay/pygments strategy (embed/shell-out/defer). Gate: syntax_highlighter_test.rb (76 blocks) dispositioned.