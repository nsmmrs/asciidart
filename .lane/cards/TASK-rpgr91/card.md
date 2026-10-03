---
id: TASK-rpgr91
title: "Port parser.rb (2801 lines, highest risk)"
status: done
type: task
priority: 1
labels:
- phase-2
- parser
parent: EPIC-ckgkd2
deps:
- TASK-td6m02
- TASK-hws3v4
created: "2026-10-03T09:03:12.005770Z"
updated: "2026-10-03T10:29:58.819270Z"
---




Port parser.rb to parser.dart (replace stub). Needs merged model + reader + document. Un-skip reader indent tests. Port parser_test (66) + integration groups. Verdict gate: reader/parser/sections/lists/tables byte-identical via harness. No barrel edits.