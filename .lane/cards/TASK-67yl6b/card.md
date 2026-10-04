---
id: TASK-67yl6b
title: "Typed options and entry points (ADR-0004)"
status: backlog
type: task
priority: 2
labels:
- idiomatic
- api
parent: EPIC-k5nzlv
deps:
- TASK-txhd50
created: "2026-10-04T14:17:36.134031Z"
updated: "2026-10-04T14:17:36.134031Z"
---

Implement ADR-0004 once accepted: immutable AsciidoctorOptions (typed safe enum, backend, doctype, standalone, attributes, baseDir, toFile/toDir/mkdirs, templateDirs, extensions, logger, sourcemap, parseHeaderOnly) translating to the internal option map; public load/loadFile/convert/convertFile with String/path inputs and String/Document results; Document.convert() returns String; stringAttr/intAttr helpers. CLI keeps the internal map API. Tests for the translation layer; parity gate unchanged.