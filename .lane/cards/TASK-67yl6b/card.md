---
id: TASK-67yl6b
title: "Static typing end to end (ADR-0004)"
status: done
type: task
priority: 2
labels:
- idiomatic
- api
parent: EPIC-k5nzlv
deps:
- BUG-fwc380
created: "2026-10-04T14:17:36.134031Z"
updated: "2026-10-04T17:49:06.227019Z"
---



Implement ADR-0004 (Final): remove all Object?/dynamic option maps, attribute maps, results and extension maps. Attributes become Map<String, String> with positional attributes as a typed list, numeric internals (rowcount, colcount, colpcwidth, safe-mode-level, counters) as typed node fields formatted once, and unset/soft-unset modeled explicitly. Typed options classes for the entry points and the CLI; convert/converters return String; typed extension API (processor callbacks, create* helpers, registration) and template converter. Output byte-identical throughout (tool/parity.sh + e2e gate each step). Split into sub-cards as the work is sized.