---
id: TASK-pdp154
title: "Port reader + parser + document model"
status: done
type: task
priority: 1
labels:
- phase-2
- core
parent: EPIC-ckgkd2
deps:
- TASK-1b31rr
created: "2026-10-03T06:08:56.223328Z"
updated: "2026-10-03T09:41:50.742927Z"
---



Port reader.rb (1375), parser.rb (2801 lines, biggest file, highest risk), node model (abstract_node/block, section, list, table, inline, document). Gate: reader/parser/sections/lists/tables groups byte-identical via harness.