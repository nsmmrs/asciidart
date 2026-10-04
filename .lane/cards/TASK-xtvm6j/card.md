---
id: TASK-xtvm6j
title: "Publish 0.1.0 to npm (asciidoctor-dart)"
status: backlog
type: task
priority: 2
labels:
- npm
- release
deps:
- EPIC-2qq14f
- EPIC-9frzpm
created: "2026-10-04T13:59:26.303265Z"
updated: "2026-10-04T13:59:26.303265Z"
---

From green master after EPIC-2qq14f and EPIC-9frzpm: build with tool/build-npm.sh, `npm publish` of build/npm (first publish manual, mirroring TASK-fb6syj), then decide on a tag-triggered publish workflow (check whether npm trusted publishing/provenance can be set up before or only after the first publish). Coordinate the version/tag with the pub.dev release. Outward-facing: only on explicit go-ahead.