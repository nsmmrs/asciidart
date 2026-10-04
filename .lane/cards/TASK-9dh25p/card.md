---
id: TASK-9dh25p
title: "npm API: Asciidoctor.js 4.1 parity facade (Promise-based load/loadFile/convert/convertFile, AST, extensions)"
status: doing
type: task
priority: 2
labels:
- npm
- js
- api
parent: EPIC-2qq14f
deps:
- TASK-s39q3t
- TASK-03yrhq
- TASK-c177z4
created: "2026-10-03T16:08:29.483649Z"
updated: "2026-10-04T18:42:05.711358Z"
---


Reference: @asciidoctor/core@4.1.0 tarball (types/*.d.ts ~6.8k lines, src/index.js; reports core 2.0.26 = our retarget) plus its repo tests at tag v4.1.0, shallow-cloned into scratchpad.

Architecture: Dart `lib/src/js/bridge.dart` exports a flat handle-based bridge over the PUBLIC Dart API (after TASK-03yrhq). Hand-written ESM classes in `npm/src/` give the Asciidoctor.js shape: real classes (instanceof, `class X extends ConverterBase`), Promises, getters (getTitle(), getBlocks(), ...). Wrappers identity-cached (same Dart node -> same JS object).

Surface: getVersion (package 0.1.0), getCoreVersion ('2.0.26'), load/loadFile/convert/convertFile -> Promise; Document, AbstractNode, AbstractBlock, Block, Section, Inline, List, ListItem, Table+children, DocumentTitle, Author, Footnote, ImageReference, RevisionInfo, Cursor; Logger, LoggerManager, MemoryLogger, NullLogger, Severity, LogMessage; SafeMode, ContentModel, Timings; Extensions/Registry + all processor kinds with DSL (this.named, this.process); Reader, PreprocessorReader; ConverterFactory, ConverterBase, Html5Converter; SyntaxHighlighter + base/factory. Options: JS object -> snake_case Dart map via dartify, special-casing registries, converter instances, Buffer/Uint8Array input.

Types: adapt @asciidoctor/core .d.ts (MIT; keep their notice in npm/types/ and LICENSE); tsc check that our types match the claimed subset.

Gaps (README + ADR; claim only what tests verify): async processors/converters throw a clear error when a callback returns a thenable (sync Dart core); allow-uri-read / HttpCache* unsupported; SemanticHtml5Converter (Asciidoctor.js-only, not Ruby 2.0.26).

Verify: run Asciidoctor.js's own node --test suite against our package with the import aliased to asciidoctor-dart; record pass count; every failure becomes a fix or a listed gap.