---
id: EPIC-2qq14f
title: "npm readiness: Asciidoctor.js-parity JS build for Node and browser (no publishing)"
status: done
type: epic
priority: 2
labels:
- npm
created: "2026-10-04T13:58:32.418908Z"
updated: "2026-10-04T20:42:48.039737Z"
---



Ship-ready (unpublished) npm package `asciidoctor-dart` (name per TASK-bpvxxh; free on npm 2026-10-04): one dart2js bundle serving Node + browser, Asciidoctor.js 4.1 (@asciidoctor/core, core 2.0.26) API parity, `asciidoctor-dart` CLI bin. Decided with user 2026-10-04: runtimes Node + browser; API = Asciidoctor.js parity; CLI = yes, bin `asciidoctor-dart`.

Probe (scratch copy of master): only compile error is the `9223372036854775807` literal (document.dart:2279); dart:io compiles but throws at runtime. With I/O stubbed, VM vs Node output byte-identical 90/90 (30 fixtures + syntax.adoc x html5/docbook5/manpage, secure mode). -O2 bundle 608 KB / 188 KB gz.

Known parity gaps to document, not fake: async JS processors/converters (Dart core is sync), allow-uri-read/HttpCache (no sync HTTP; fetchUri is a hook on VM too), SemanticHtml5Converter (Asciidoctor.js-only). Work happens in worktree ../asciidoctor-dart-npm (branch npm/readiness), never in the shared checkout. Publishing is a separate card, explicit go-ahead only. Plan: attachment npm-plan.md (copy of /home/nes/.claude/plans/zazzy-twirling-milner.md).