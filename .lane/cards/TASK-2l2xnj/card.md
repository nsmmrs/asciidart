---
id: TASK-2l2xnj
title: "npm release readiness: CI npm job, package lint, ADR, README, JS benchmark"
status: done
type: task
priority: 2
labels:
- npm
- docs
- ci
parent: EPIC-2qq14f
deps:
- TASK-fppdyy
- TASK-s39q3t
- TASK-vvk9z0
- TASK-p0qg86
- TASK-9dh25p
created: "2026-10-04T13:59:26.289769Z"
updated: "2026-10-04T20:42:48.019207Z"
---


CI (.github/workflows/ci.yml) `npm` job: setup-dart + setup-node (matrix: engines floor + current LTS); tool/build-npm.sh; facade node --test suite; ported Asciidoctor.js tests; bats e2e + differential on the Node CLI; Playwright browser smoke + esbuild check; dart test -p node; `npm pack --dry-run` with asserted file list; npx publint; npx @arethetypeswrong/cli --pack; `npm publish --dry-run`. No publish workflow (belongs to the publish card).

ADR adr/000N-js-build.md (next free number; retarget plans 0003): dart2js over dart2wasm (browser + Node reach, dart-sass precedent), single bundle with injected built-ins, I/O seam, sync core behind async API, gap list. Point ADR-0001 'deferred stages' at it.

README 'JavaScript / npm' section; amend TASK-zs44d6's planned 'web/JS is unsupported' line. Benchmark: Node CLI row (optionally Asciidoctor.js 4.1) in benchmark/BASELINE.md via benchmark/bench-exe.rb (ADR-0001 gem/VM/AOT/JS deliverable).

Done when (end-to-end): VM checks + no-dart:io gate green; dart test -p node green; bats e2e green on Node CLI; differential 96/96 vs gem 2.0.26; Asciidoctor.js suite pass count recorded with failures mapped; browser smoke + esbuild green; pack/publint/attw/publish --dry-run clean; scratch consumer installs the .tgz via import and require, and `npx asciidoctor-dart --version` line 1 equals the gem's.