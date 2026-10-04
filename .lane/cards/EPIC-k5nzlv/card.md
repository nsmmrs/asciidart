---
id: EPIC-k5nzlv
title: "Make the port read as Dart, not transliterated Ruby"
status: doing
type: epic
priority: 2
labels:
- idiomatic
created: "2026-10-04T13:53:24.434710Z"
updated: "2026-10-04T14:09:50.491893Z"
---


Reduce Ruby references in names, comments, user-facing text and API shape to the minimum. Keep legitimate ones: the Ruby-language highlighter (highlight/ruby_scanner.dart, 'ruby' lexer entries), the `eruby` option, README attribution, and the test/e2e gem-oracle wrapper. Output must stay byte-identical (ADR-0001 D4): rename and reword only, never change behavior. Starts after the 2.0.26 retarget lands, so renames don't add noise to its diffs. Hiding core_ext from the public API is already TASK-03yrhq.