# ADR-0005: JavaScript Build (npm package `asciidart`)

**Status:** Final — scope decided with the user on 2026-10-04: runtimes
Node.js and the browser, an API at parity with Asciidoctor.js 4.1, and a CLI
bin named `asciidart`. The package is built and tested but not
published (ADR-0001 deferred stages; publishing is its own lane card).

## Context

ADR-0001 planned a JS bundle alongside the native executables. The first
probe compiled the whole core with dart2js once one literal that JavaScript
cannot represent (`9223372036854775807` in `document.dart`) was gone; with
`dart:io` stubbed out, VM and Node.js output was byte-identical on every
fixture and backend. The remaining questions were how to compile, how to
reach the file system and network from both runtimes, and what API to put
in front of the core.

The reference for the API is Asciidoctor.js 4.1.0 (`@asciidoctor/core`): a
rewrite of Asciidoctor in JavaScript that reports core version 2.0.26, the
release this port matches (ADR-0003). Its API is promise based
(`load`, `convert`, ...), with Asciidoctor's node classes, extension DSL and
converter classes.

## Decisions

1. **dart2js, not dart2wasm.** One `-O2` dart2js bundle serves Node.js
   (>= 20.19) and browsers. dart2wasm would need WasmGC in every target
   runtime and a JS loader per runtime, and adds no output benefit; dart-sass
   ships the same way. The bundle is about 710 KB (220 KB gzipped).
2. **One I/O seam.** `lib/src/io.dart` exports a VM implementation
   (`dart:io`) or a JavaScript one (`dart:js_interop`) by conditional
   import; nothing else in the library imports either. On Node.js the JS
   side reaches `node:fs` and `node:zlib` through
   `process.getBuiltinModule`, so the bundle needs no `require` and no
   bundler shims; in the browser, file access reports an I/O error and
   remote content goes through `fetch`. `test/platform_seam_test.dart`
   enforces the boundary.
3. **Synchronous core, asynchronous API.** The core stays synchronous (it
   is the same code as the VM build, which keeps the output identical).
   The facade's `load`/`convert` return promises: they run the async Dart
   entry points (`loadAsync`, `convertAsync`), which prefetch remote content
   when `allow-uri-read` is set and otherwise convert in one pass.
4. **Hand-written facade over a typed bridge.** `lib/src/js/` exports a
   small `@JSExport` bridge over the public Dart API (node views, extension
   registries, readers, node factories, converters). `npm/src/` wraps it in
   ES module classes with the Asciidoctor.js names: real classes for
   `instanceof` and subclassing (`class X extends Html5Converter`),
   identity-cached wrappers (the same Dart node always yields the same JS
   object), getters and `get*` methods. Types are hand-written
   (`npm/types/index.d.ts`, plus `.d.cts` copies for `require`).
5. **Callbacks are synchronous.** The core calls converters and extensions
   synchronously, so their functions must return values, not promises (a
   promise is rejected with a clear error). Inside such a callback, node
   methods that return promises at the top level (`getContent()`,
   `convert()`, ...) return their values directly; `await` works either
   way.
6. **Facade objects hide the core.** A facade object keeps its view as a
   non-enumerable property, and arrays from the core are copied into plain
   arrays. dart2js objects (and Dart lists, which carry their runtime type
   as a symbol-keyed property) otherwise make `util.inspect` and
   `assert.deepStrictEqual` walk the compiled core's heap: one failing
   assertion on a node ran a test process out of memory.
7. **Errors keep their identity.** An error thrown by a converter or an
   extension reaches the caller as the same object; errors raised by the
   core reject with a JS `Error` (`name` `AsciidoctorError` for document
   errors) carrying the core's message.
8. **The CLI is the Dart CLI.** `asciidart` runs `runCli` from the
   bundle; the e2e suite and the parity gate run against it in CI.

## Gaps

- No asynchronous converters or extensions (decision 5). Asciidoctor.js
  allows them; porting such code means making the functions synchronous.
- No Asciidoctor.js-only features: the semantic HTML converter, the HTTP
  cache classes, highlight.js integration, `Timings`, and the internal
  modules some Asciidoctor.js tests import (parser, substitutors, path
  resolver).
- Templates (`template_dirs`) need file access, so they work on Node.js
  only.
- The CodeRay highlighter keeps the VM build's limits (Ruby and text
  scanners only).

## Verification

- `test/npm`: API, exports, package contents, esbuild bundling, and all
  fixtures in Chromium identical to Node.js.
- `dart test -p node`; bats e2e and `tool/parity.sh` against the Node CLI.
- publint and are-the-types-wrong clean; `tsc --strict` over typical usage.
- The Asciidoctor.js 4.1.0 suite runs against the package as an informal
  compatibility measure (not a gate): its failures are dominated by the
  gaps above and by behavior newer than 2.0.26.
- Throughput on Node.js is within 10% of the Dart AOT binary and ahead of
  Asciidoctor.js 4.1.0 on every backend (`benchmark/BASELINE.md`).
