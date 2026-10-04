---
id: TASK-b98cxf
title: Reword Ruby-referencing comments to describe behavior
status: backlog
type: task
priority: 3
labels:
- idiomatic
parent: EPIC-k5nzlv
deps:
- EPIC-9frzpm
created: "2026-10-04T13:53:24.454999Z"
updated: "2026-10-04T13:53:24.454999Z"
---

About 630 comment lines in lib/ say things like 'mirrors Ruby's String#rpartition' or 'as in Ruby'. Reword compatibility quirks in terms of observable behavior and the reference release (for example 'Asciidoctor 2.0.26 emits X'), not the Ruby implementation. Delete comments that only name the Ruby method being ported (for example 'Port of Ruby's String#lstrip'). Wait until the retarget is done, because these comments are useful cross-references while comparing against the gem's sources. Work file by file; the heaviest are cli/options.dart, substitutors.dart, core_ext.dart, document.dart, reader.dart, cli/invoker.dart, table.dart, logging.dart, extensions.dart and converter.dart.