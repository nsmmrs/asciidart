# ADR-0007: The npm API Is a Generated Projection of the Dart API

**Status:** Final, decided with the user on 2026-10-05 as step 6 of the
roadmap ("npm: a generated 1:1 projection of the Dart API"). Supersedes
decisions 3 to 7 of ADR-0005; its decisions 1, 2 and 8 (dart2js, the I/O
seam, the CLI) still stand.

## Context

ADR-0005 put an Asciidoctor.js 4.1-shaped facade in front of the core. It
was about 2,000 lines of hand-written JavaScript, a hand-written bridge and
hand-written types. Since then two things changed:

- **The Dart API is new.** It is private by default and designed from usage
  scenarios (`doc/api.md`, ADR-0006): a configuration object, a sealed tree
  of typed nodes and callback extensions. The Asciidoctor.js shape
  (`getTitle()`, the extension DSL, `convert_<name>` converter classes) no
  longer matches anything in it.
- **asciidart diverges on purpose.** It fixes upstream bugs and restructures
  the code (ADR-0006), so imitating Asciidoctor.js's API buys little. The
  npm package was never published, so no users depend on that API.

## Decisions

1. **Generated, 1:1.** `tool/generate_js.dart` reads the public libraries
   (`lib/asciidart.dart`, `lib/io.dart`) with the analyzer. It writes the
   Dart side (`lib/src/js/api.g.dart`), the JavaScript classes
   (`npm/src/api.g.js`) and the TypeScript declarations
   (`npm/types/index.d.ts`, with the dartdoc comments as JSDoc). Names are
   the Dart names. The type mappings are:

   | Dart | JavaScript |
   | --- | --- |
   | named parameters | a trailing options object |
   | enums | their names, as frozen objects of strings |
   | lists, sets and maps | arrays and plain objects |
   | futures | promises |
   | streams | async iterables |
   | `FutureOr` returned by a callback | a value or a promise |
   | functions | functions, in both directions |
   | `descendants<T>()` | `descendants(Class)` |
   | `[]` and `[]=` | `get` and `set` |

   A type the generator does not know fails the run, naming the member.
   CI runs `generate_js.dart --check`, so a change to the Dart API
   reaches npm in the same commit.
2. **Real classes, members on prototypes.** Each member is declared once,
   on the JavaScript class whose Dart class declares it. It calls one flat
   table of Dart functions (`Core`), with the object as the first argument;
   Dart then dispatches overrides. Projected objects are created with
   `Object.create(Class.prototype)`, so `instanceof` and subclass checks are
   native, and constructors of node classes throw when called directly.
   `createJSInteropWrapper` per class was tried first. It repeated every
   inherited member in every concrete class and allocated one closure per
   member per object, for 360 KB more bundle; this layout costs about
   60 KB.
3. **No own properties.** `npm/src/core.js` keeps the Dart object behind
   each projected object in a `WeakMap`. Projected objects have no own
   properties, so `util.inspect` (even with `showHidden`), assertion
   messages and deep equality never reach the compiled core's heap. A
   failing `assert` on a node ran the test process out of memory three
   times before this. One consequence: `deepStrictEqual` treats two
   distinct nodes of the same class as equal, so compare them by identity.
4. **Identity.** The same Dart object always yields the same JavaScript
   object (an `Expando` cache), so `===` and `Map` keys work.
5. **Synchronous like Dart.** `parse` and `convert` return values;
   `parseAsync`, `convertAsync` and the file functions return promises.
   Callbacks run synchronously, except `IncludeResolver`, which may return a
   promise (as in Dart, with `parseAsync`).
6. **Errors.**
   - An error thrown by a JavaScript callback reaches the caller as the same
     object. It is carried through Dart inside a plain `Error`, because
     dart2js alters `TypeError` and `RangeError` objects that Dart code
     catches.
   - `AsciidartException` is a JavaScript `Error` subclass.
   - An argument of the wrong type raises a `TypeError`.
   - Any other failure raises an `Error` with the Dart stack trace as
     `dartStack`.
7. **JavaScript implementations.** Abstract Dart classes meant to be
   implemented, such as `Highlighter`, are plain JavaScript base classes. A
   JavaScript subclass is wrapped in a generated Dart adapter when it
   crosses into Dart.

## Consequences

- Asciidoctor.js code does not port unchanged: it maps to the scenarios in
  `doc/api.md`, which read the same in Dart and JavaScript
  (`test/api/scenarios_test.dart` and `test/npm/api.test.mjs` are twins).
- Adding to the Dart API adds to the npm API with no hand-written code. A
  type the projection cannot express has to be redesigned in Dart, or
  taught to the generator.
- The bundle is about 2.47 MB, 0.65 MB gzipped. Most of it is hilite's
  languages; see the card on bundle size.

## Verification

- `test/npm`:
  - the scenarios, identity, `instanceof`, inspection, errors, promises,
    files and a JavaScript highlighter;
  - the exports matching the declarations;
  - the package contents;
  - esbuild bundling;
  - every fixture in Chromium, identical to Node.js.
- `tsc` over `test/npm/types/usage.ts`; publint and are-the-types-wrong.
- bats e2e and `tool/parity.sh` against the Node.js CLI.
