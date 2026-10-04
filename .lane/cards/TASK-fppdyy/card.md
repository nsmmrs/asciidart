---
id: TASK-fppdyy
title: "JS platform I/O seam: lib/src/io.dart conditional exports, JS-safe maxInt, no-dart:io gate"
status: backlog
type: task
priority: 2
labels:
- npm
- js
parent: EPIC-2qq14f
created: "2026-10-04T13:58:55.180427Z"
updated: "2026-10-04T13:58:55.180427Z"
---

dart-sass pattern: `lib/src/io.dart` exports `io/interface.dart` if (dart.library.io) `io/vm.dart` if (dart.library.js_interop) `io/js.dart`. Surface (from inventory): read bytes/string, isFile/isDirectory/exists, list dir, write/append, mkdirs, cwd, environment, pathSeparator, isWindows, sync read-all stdin, stdout/stderr as StringSink, exit code, pid, maxInt (VM literal lives in vm.dart only; JS 9007199254740991 — fixes _maxInt63 at document.dart:2279).

io/js.dart: Node mode uses fs/path/process injected by the npm wrapper into one global handle via dart:js_interop (bundle never references node:*); browser mode has no fs (reads fail like missing files so existing include-not-found warnings fire), cwd '/', empty env, stderr -> console.error. Fold template_node_detect_{js,stub}.dart into the seam (reuse isRunningOnNode()).

Replace dart:io in: writer, template_loader, document, timings, stylesheets, template, path_resolver, logging, helpers, load, abstract_node, manpage, reader, highlight/{rouge,pygments,coderay}. VM-only input types (File/RandomAccessFile/IOSink checks at load.dart:97, document.dart:1441) go behind a seam hook. Dart public API unchanged.

Gate: test failing if any lib/ file besides io/vm.dart and VM-only CLI parts imports dart:io/dart:isolate (dart2js does not catch it). Done when: dart compile js succeeds and a convert() probe runs on Node with real fs.