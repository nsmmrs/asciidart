---
id: TASK-9mfkvk
title: "Spike: template-converter strategy (Tilt has no Dart equivalent)"
status: done
type: task
priority: 2
labels:
- spike
- phase-4
parent: EPIC-ckgkd2
deps:
- TASK-3d1llw
created: "2026-10-03T06:08:56.425624Z"
updated: "2026-10-03T16:15:31.044821Z"
---


Ruby template.rb needs Tilt + Haml/Slim/ERB (no Dart equivalent). CORRECTION: Asciidoctor.js SHIPS its own template converter (EJS/Handlebars/Nunjucks/Pug) — no Tilt portability expected of any port. Early spike (TASK-9bp3rl, attached) recommends: static Dart plugin converters first, Mustache file templates second. Phase-4 implements that. Blocks custom-template parity only.