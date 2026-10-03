---
id: TASK-nq0wgj
title: "Port highlighter adapters (6, direct tests; no framework)"
status: done
type: task
priority: 3
labels:
- phase-7
- highlight
parent: EPIC-ckgkd2
created: "2026-10-03T09:27:18.493103Z"
updated: "2026-10-03T09:42:25.956968Z"
---



Adapters are pure string transformers (verified). Full: highlightjs/prettify/html_pipeline. Lexer-backed (rouge/coderay/pygments): format/wrap logic + Lexer seam (real lexers later). Framework needs Document — later wave. No barrel edits.