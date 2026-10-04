---
id: TASK-s39q3t
title: "npm package build: single dart2js bundle, tool/build-npm.sh, Node/browser wrappers, asciidoctor-dart CLI bin"
status: doing
type: task
priority: 2
labels:
- npm
- js
parent: EPIC-2qq14f
deps:
- TASK-fppdyy
created: "2026-10-04T13:58:55.217636Z"
updated: "2026-10-04T18:20:46.029582Z"
---


One `dart compile js -O2` bundle from `lib/src/js/entry.dart` registering the library bridge + runCli on the injected handle. Checked-in `npm/`: package.json template, npm README, wrappers node.cjs/node.mjs (inject Node built-ins) and browser.mjs (none), bin/asciidoctor-dart.js.

`tool/build-npm.sh` (build-exes.sh style): pub get, dart2js, assemble gitignored build/npm/, stamp version from pubspec, copy LICENSE, never publish.

package.json: name asciidoctor-dart, type module, MIT, exports['.'] with types/browser/import/require (modeled on @asciidoctor/core), bin {asciidoctor-dart}, files whitelist, engines.node, repository, unofficial-port description. Dart test: npm version == pubspec version.

CLI on JS: exit via process.exitCode (no hard exit mid-write); -j falls back to serial when isolates unavailable (identical output); init-config errors 'only available in the Dart CLI'; --version line 1 byte-identical to gem, runtime line 'Runtime Environment (asciidoctor-dart 0.1.0; Node.js vX)' (coordinate with TASK-c177z4).