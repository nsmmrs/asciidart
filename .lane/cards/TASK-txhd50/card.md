---
id: TASK-txhd50
title: "Decision record: typed public API instead of Object? and option maps"
status: done
type: task
priority: 2
labels:
- idiomatic
- api
parent: EPIC-k5nzlv
deps:
- EPIC-9frzpm
created: "2026-10-04T13:53:24.463329Z"
updated: "2026-10-04T14:58:41.290948Z"
---




The deepest Ruby trait is dynamic typing carried straight into Dart: about 813 `Object?` types, 214 `Map<String, Object?>` option maps and 242 `isTruthy` calls in lib/. Examples: `load(Object? input, [Map<String, Object?>? options])`, `AbstractNode.attr()` returning `Object?`, `convert()` returning `Object?`/`dynamic`. Write an ADR deciding whether and when to move to typed options (a class or record), typed attribute access, and typed convert results, including the effect on the extensions API and template converter. Decide before the 0.1.0 publish (TASK-fb6syj) if possible, since changing the public API after publishing costs more. The ADR settles scope; the implementation becomes its own card(s).