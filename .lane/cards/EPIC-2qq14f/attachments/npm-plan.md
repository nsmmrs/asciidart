# Plan: make the JS build ready for npm (no release)

## Context

ADR-0001 promises a dart-sass-style npm JS build, but the repo has none yet. The pub.dev release plan (`gentle-prancing-ritchie.md`) defers JS, saying it's blocked by `dart:io` and the `_maxInt63` const.

The goal is a package named `asciidoctor-dart` (name decided in TASK-bpvxxh, still free on npm as of 2026-10-04) that is ready to publish. Its scope, as chosen:

- **Runtimes:** Node and the browser.
- **API:** parity with Asciidoctor.js (`@asciidoctor/core` 4.1.0).
- **CLI:** an `asciidoctor-dart` bin.

Publishing stays out of scope and happens only on an explicit go-ahead.

**Probe results.** I ran these on a `git archive master` copy in the scratchpad; the shared checkout was not touched.

- `dart compile js` has only one compile error: the `9223372036854775807` literal at `lib/src/document.dart:2279`. Importing `dart:io` compiles, but every call into it throws `Unsupported operation` at runtime. The first one hit is `Platform.pathSeparator` in `PathResolver`.
- After stubbing `Platform`, `Directory.current` and `stderr`, I ran 30 fixtures plus `syntax.adoc` through the html5, docbook5 and manpage backends (standalone, secure mode, logs sent to a `MemoryLogger`). VM and Node output were **byte-identical, 90 of 90**. The core engine is JS-clean; the work is at the I/O boundary.
- The `-O2` bundle is 608 KB, 188 KB gzipped.
- `@asciidoctor/core` 4.1.0 is a native ESM rewrite that reports core version **2.0.26**, the same target as the master retarget (EPIC-9frzpm).
  - Its API is async throughout: about 150 `await`s in `parser.js` alone, extension `process` callbacks may return Promises, and browser includes use `fetch`.
  - Its types are 6.8k lines under `types/*.d.ts`, and they are the API reference for this plan.
- `dart:io` is used in 16 non-CLI files and in `lib/src/cli/*`. `-j` uses isolates (`cli/parallel.dart`, `job_pool.dart`).
- `fetchUri` (`abstract_node.dart:653`) is an override hook even on the VM, so not supporting `allow-uri-read` on JS is not a regression.

**Concurrency.** Another session is working in `/home/nes/Work/ports/asciidoctor-dart`, which currently has branch `retarget/data` checked out. All of this work happens in a **separate worktree**:

```sh
git worktree add ../asciidoctor-dart-npm -b npm/readiness master
```

Never check out, commit, or run `lane` writes in the shared checkout. Create the lane cards on the worktree branch; each card is a new file, so they won't conflict with the retarget cards. Rebase onto `master` as the retarget cards merge.

## Sequencing and dependencies

| Step | Depends on | Can start now? |
| --- | --- | --- |
| 1. I/O seam and int fix, plus a CI gate that compiles to JS | none | yes |
| 2. Single bundle, npm build, JS CLI, Node e2e/differential | 1 | yes |
| 3. Browser backend and browser test | 1, 2 | yes |
| 4. Asciidoctor.js-parity API facade | 2, TASK-03yrhq (public API split), TASK-c177z4 (versions) | after those land |
| 5. Docs, ADR, CI hardening, publish dry-run | 1–4 | last |

The step 1 diff in `document.dart`, `reader.dart` and `load.dart` is limited to imports and the I/O call sites, so conflicts with the retarget reverts should be small and mechanical. The Dart public API doesn't change, so pub 0.1.0 (TASK-fb6syj) isn't blocked.

**Lane cards** (created in the worktree):

- EPIC "npm readiness: JS build for Node and browser (no publishing)"
- One task for each of steps 1–5, with deps as in the table above.
- Reparent TASK-9dh25p under the epic as step 4.
- A deferred "Publish 0.1.0 to npm" card that requires explicit go-ahead.

## Step 1: Platform I/O seam (the dart-sass pattern)

- Add `lib/src/io.dart`:
  ```dart
  export 'io/interface.dart'
      if (dart.library.io) 'io/vm.dart'
      if (dart.library.js_interop) 'io/js.dart';
  ```
  `interface.dart` holds the signatures and throws `UnsupportedError`.
- The surface is derived from the inventory above:
  - **Files:** read bytes and string, `isFile`, `isDirectory`, `exists`, list a directory (template loader), write and append (writer, logfile), mkdirs.
  - **Process:** `cwd`, `environment`, `pathSeparator`, `isWindows`, read all of stdin synchronously, `stdout`/`stderr` as `StringSink`, set the exit code, `pid`.
  - **Constants:** `maxInt`. The VM value `9223372036854775807` lives in `vm.dart`, which dart2js never compiles; JS uses `9007199254740991`. This fixes `_maxInt63`.
- `io/js.dart` has two runtime modes, picked once at startup:
  - **Node:** it uses `fs`, `path` and `process` objects that the npm wrapper injects into one global handle via `dart:js_interop`. The bundle itself never references `node:*`, which keeps it bundler-safe.
  - **Browser:** no filesystem. File reads fail in the same way as missing files, so the existing "include file not found" warning paths fire. `cwd` is `/`, the environment is empty, and `stderr` goes to `console.error`.
- Fold `lib/src/template_node_detect_js.dart` and `template_node_detect_stub.dart` into the seam. Reuse `isRunningOnNode()` as the mode switch, then delete both files.
- Replace the `dart:io` imports in these files: `writer`, `template_loader`, `document`, `timings`, `stylesheets`, `template`, `path_resolver`, `logging`, `helpers`, `load`, `abstract_node`, `manpage`, `reader`, `highlight/{rouge,pygments,coderay}`.
  - The VM-only input types (`File`, `RandomAccessFile`, `IOSink` checks in `load.dart:97`, `document.dart:1441`) move behind a seam hook. That hook is a type test in `vm.dart` and returns `null` in `js.dart`.
- **Gate:** add a test that fails if any file under `lib/` other than `io/vm.dart` and the VM-only CLI pieces imports `dart:io` or `dart:isolate`. dart2js won't catch this at compile time.

## Step 2: Bundle, npm package layout, and the JS CLI

- **One dart2js bundle** (`dart compile js -O2`), following dart-sass. Its entry point is `lib/src/js/entry.dart`, which registers the library bridge and `runCli` on the injected handle.
- **CLI on JS:**
  - `cli/run.dart` uses seam exit codes; on Node that's `process.exitCode`, never a hard exit mid-write.
  - `-j` falls back to serial when isolates are unavailable, which keeps output identical.
  - `init-config` scaffolds a Dart project, so on JS it fails with a clear message ("only available in the Dart CLI").
  - Per TASK-c177z4, `--version` line 1 stays byte-identical to the gem. The runtime line becomes `Runtime Environment (asciidoctor-dart 0.1.0; Node.js vX)`.
- **Checked-in `npm/` sources:**
  - `package.json` template.
  - `README.md` for npm.
  - Wrappers: `node.cjs` and `node.mjs` inject the Node built-ins; `browser.mjs` injects none.
  - `bin/asciidoctor-dart.js`.
  - The JS facade (step 4) and `types/*.d.ts`.
- **`tool/build-npm.sh`,** in the same style as `tool/build-exes.sh`:
  - Runs `pub get`, then dart2js, and assembles `build/npm/`. That path is already gitignored via `build/`.
  - Stamps the version from `pubspec.yaml` and copies `LICENSE`.
  - Never publishes.
- **package.json:**
  - `name: asciidoctor-dart`, `type: module`, `license: MIT`.
  - `exports["."]` with `types`, `browser`, `import` and `require` conditions, modeled on `@asciidoctor/core`.
  - `bin: { "asciidoctor-dart": ... }`, a `files` whitelist, `engines.node`, `repository`, and an "unofficial port" description.
- Add a Dart test asserting the npm package version equals the pubspec version, next to the `packageVersion` test planned in TASK-c177z4.
- **Parity on Node using existing tools:**
  - Add a `test/e2e/bin/asciidoctor-node` shim (`node build/npm/bin/asciidoctor-dart.js "$@"`) and run the full bats suite against it.
  - Run `tool/differential.dart --exe-a asciidoctor --exe-b "node …/asciidoctor-dart.js"` on html5, docbook5 and manpage. Expect 96 of 96 once the retarget lands; before that, compare against the Dart VM exe.
- Run `dart test -p node` across the Dart suite to catch JS-semantics drift (ints, regex, number formatting). Tag test files whose test code itself uses `dart:io` with `@TestOn('vm')`.

## Step 3: Browser

- Ship the browser wrapper as the `browser` export condition, with no `node:*` imports.
- Browser behavior: in-memory only. File includes behave like missing files. A JS `IncludeProcessor` extension is the supported way to supply include content, which needs step 4.
- **Test:** add a Playwright smoke spec (`test/npm/browser.spec.mjs`) that loads `build/npm/browser.mjs` in headless Chromium.
  - It converts the probe corpus inline (secure mode).
  - It compares against VM-generated goldens.
- Add a bundler check: `esbuild --bundle --platform=browser` on a one-line consumer must succeed with no Node-builtin errors.

## Step 4: Asciidoctor.js 4.1 API facade (TASK-9dh25p)

- **Reference:** the `@asciidoctor/core@4.1.0` tarball (`types/`, `src/index.js`), plus its repo's tests at tag `v4.1.0`, shallow-cloned into the scratchpad.
- **Architecture:**
  - Dart (`lib/src/js/bridge.dart`) exports a flat, handle-based bridge over the **public** Dart API (after TASK-03yrhq).
  - Hand-written ESM JS classes in `npm/src/` provide the Asciidoctor.js shape. That shape needs real classes for `instanceof` and subclassing (`class X extends ConverterBase`), Promises, and getter names (`getTitle()`, `getBlocks()`, …).
  - Wrappers are identity-cached, so the same Dart node always gives the same JS object.
- **Surface:**
  - Functions: `getVersion` (returns package 0.1.0), `getCoreVersion` (returns `2.0.26`), and `load`, `loadFile`, `convert`, `convertFile`, all returning Promises.
  - AST: `Document`, `AbstractNode`, `AbstractBlock`, `Block`, `Section`, `Inline`, `List`, `ListItem`, `Table` and children, `DocumentTitle`, `Author`, `Footnote`, `ImageReference`, `RevisionInfo`, `Cursor`.
  - Logging: `Logger`, `LoggerManager`, `MemoryLogger`, `NullLogger`, `Severity`, `LogMessage`.
  - Constants and timing: `SafeMode`, `ContentModel`, `Timings`.
  - Extensions: `Extensions` and `Registry`, plus all processor kinds with their DSL (`this.named(…)`, `this.process(…)`).
  - Readers: `Reader`, `PreprocessorReader`.
  - Converters: `ConverterFactory`, `ConverterBase`, `Html5Converter`.
  - Highlighters: `SyntaxHighlighter` and its base/factory.
- **Options:** JS objects map to the snake_case Dart options map via `dartify`. Registries, converter instances and `Buffer`/`Uint8Array` inputs get special handling.
- **Types:** adapt the `@asciidoctor/core` `.d.ts` files (MIT; keep their copyright notice in `npm/types/` and `LICENSE`). Add a `tsc` check that our types match the subset we claim.
- **Known gaps.** List these in the README and ADR, and claim only what the tests verify:
  - **Async processors and converters.** JS extension or converter callbacks run synchronously inside the sync Dart core. One that returns a thenable throws a clear error ("asynchronous processors are not supported").
  - **`allow-uri-read` / `HttpCache*`.** No sync HTTP is available; on the VM this is also unimplemented.
  - **`SemanticHtml5Converter`.** It is Asciidoctor.js-only and not part of Ruby 2.0.26.
- **Verification:** run Asciidoctor.js's own `node --test` suite against our package with its import aliased to `asciidoctor-dart`. Record the pass count, and file every failure as either a fix or a documented gap.

## Step 5: Docs, ADR, CI

- **CI:** add an `npm` job to `.github/workflows/ci.yml`:
  - Setup: setup-dart, then setup-node with a matrix of the `engines` floor and the current LTS.
  - Build and verify: `tool/build-npm.sh`, the facade's `node --test` suite, the ported Asciidoctor.js tests, and the bats e2e and differential runs against the Node CLI.
  - Browser and Dart-on-Node: the Playwright browser smoke test, the esbuild check, and `dart test -p node`.
  - Package checks: `npm pack --dry-run` with an asserted file list, `npx publint`, `npx @arethetypeswrong/cli --pack`, and `npm publish --dry-run`.
  - No publish workflow yet; that belongs to the deferred release card.
- **ADR:** add `adr/000N-js-build.md`, using the next free number since retarget plans 0003. It covers:
  - dart2js over dart2wasm (browser and Node reach, the dart-sass precedent).
  - The single bundle with injected built-ins.
  - The I/O seam.
  - The sync core behind an async API.
  - The gap list.
- Point ADR-0001's "deferred stages" at the new ADR.
- **README:** add a "JavaScript / npm" section. Also amend TASK-zs44d6's planned "web/JS is unsupported" README line.
- **Benchmark:** add a Node CLI row (and optionally Asciidoctor.js 4.1) to `benchmark/BASELINE.md` with `benchmark/bench-exe.rb`. This fulfils the "gem vs VM vs AOT vs JS" deliverable in ADR-0001.

## Critical files

- **New:**
  - `lib/src/io.dart` and `lib/src/io/{interface,vm,js}.dart`
  - `lib/src/js/{entry,bridge}.dart`
  - `npm/**`
  - `tool/build-npm.sh`
  - `test/e2e/bin/asciidoctor-node`
  - `test/npm/**`
  - the new ADR
- **Modified:**
  - The 16 non-CLI `dart:io` files listed in step 1.
  - `lib/src/cli/{run,invoker,options,parallel}.dart`.
  - `lib/src/template_loader.dart` (the seam fold).
  - `.github/workflows/ci.yml`, `README.md`, `adr/0001-dart-rewrite-goals.md`.
- **Reused:** the `isRunningOnNode()` interop pattern, `tool/build-exes.sh` conventions, `tool/differential.dart`, the bats suite and its `ASCIIDOCTOR_EXE` shims, and `MemoryLogger`.

## Verification (end to end)

1. `dart analyze --fatal-infos .`, `dart format --set-exit-if-changed .`, `dart test`, and the new no-`dart:io` gate all pass on the VM.
2. `dart test -p node` passes; only files tagged `@TestOn('vm')` are excluded.
3. `tool/build-npm.sh`, then `bats test/e2e/` with `ASCIIDOCTOR_EXE=test/e2e/bin/asciidoctor-node`, passes the full suite.
4. The differential harness reports gem 2.0.26 vs the Node CLI identical on all three backends (96 of 96 after the retarget).
5. The Asciidoctor.js 4.1 test suite runs against `build/npm` with the pass count recorded, and each failure is mapped to a fix or a listed gap.
6. Browser: the Playwright smoke test is green and the esbuild browser bundle succeeds.
7. `npm pack --dry-run` shows only the whitelisted files. `publint`, `attw` and `npm publish --dry-run` report no errors.
8. In a scratch consumer, `npm i ../build/npm/asciidoctor-dart-0.1.0.tgz` works with both `import` and `require`, and `npx asciidoctor-dart --version` prints line 1 identical to the gem.
