# ADR-0004: Typed Public API

**Status:** Proposed (2026-10-04) — awaiting user acceptance. Nothing here
is implemented yet; the follow-up card is TASK-67yl6b.

## Context

The port carries Ruby's dynamic typing straight into Dart. In `lib/` there
are about 740 `Object?` types, 210 `Map<String, Object?>` option and
attribute maps, and 240 `isTruthy` calls. At the public boundary this
shows up as:

- `load(Object? input, [Map<String, Object?>? options])`, and the same shape
  for `loadFile`, `convert` and `convertFile`. Option keys are strings
  (`'safe'`, `'backend'`, `'to_file'`, ...), values are untyped, and typos
  fail silently.
- `convert(...)` returning `Object?`, so every caller casts to `String`.
- `AbstractNode.attr(name)` returning `Object?`, because attribute values
  really are mixed: strings, integers (`safe-mode-level`, counters),
  booleans and `null` (unset) all occur.
- Extension callbacks receiving `Map<Object, String?>` or
  `Map<String, Object?>` attribute maps, mirroring AsciiDoc's untyped
  attributes.

Inside the converter the dynamic typing does real work: attribute
semantics (`false` versus `null` versus `''`), positional attributes keyed
by integers, and byte-identical output (ADR-0001 D4) all depend on it.
Retyping the internals would be a large, risky rewrite with no output
benefit.

Changing the public API after 0.1.0 is possible (0.x allows breaking minor
releases) but costs every early user a migration, so the boundary is worth
settling first.

## Proposed decisions

1. **Type the entry points before 0.1.0; keep the internals dynamic.**
   Add an immutable `AsciidoctorOptions` class with typed, documented
   fields for the options a library user actually sets: `safe` (an enum),
   `backend`, `doctype`, `standalone`, `attributes`, `baseDir`, `toFile` /
   `toDir` / `mkdirs`, `templateDirs`, `extensions`, `logger`, `sourcemap`,
   `parseHeaderOnly`. It converts to the existing internal option map, so
   the parser and converters are untouched.
2. **Typed public signatures**, replacing the map-based ones in the public
   library (the map versions stay available internally for the CLI):
   - `Document load(String source, [AsciidoctorOptions options])`
   - `Document loadFile(String path, [AsciidoctorOptions options])`
   - `String convert(String source, [AsciidoctorOptions options])`
   - `Document convertFile(String path, [AsciidoctorOptions options])`
     (writes the output file and returns the document; use `loadFile` plus
     `Document.convert()` to get a string).
   Input as a list of lines, a `File` or a `RandomAccessFile` is dropped from
   the public surface; callers read the file themselves. `Document.convert()`
   returns `String`.
3. **Attributes stay `Object?`, with typed helpers.** Keep `attr()` as is
   (the values really are heterogeneous) and add `String? stringAttr(name)`
   and `int? intAttr(name)` for the common cases. Revisit after 0.1.0 if
   users ask for more.
4. **Extensions keep their current shape for 0.1.0.** Processor callbacks
   and `create_*` helpers mirror the Asciidoctor extension API, which users
   port from Ruby and JavaScript; typing their attribute maps is deferred
   to a later minor release with its own ADR.
5. **Template converter unchanged.** Mustache contexts are maps by nature;
   Dart transform functions already receive typed nodes.

## Consequences

- Library users get compile-time checked options and `String` results
  without casts, and the common path (`convert(source)`) reads like any
  Dart package.
- The internals keep their tested, byte-identical behavior; the façade is
  a thin translation layer with its own tests.
- The CLI keeps using the map-based functions, so no CLI behavior changes.
- Extension authors still work with loosely typed attributes until a
  follow-up decision.

## Alternatives considered

- **Keep the map API for 0.1.0.** Cheapest now, but the first breaking
  release would land on every early user.
- **Retype the internals.** Touches about 1,200 sites across the parser,
  substitutors and converters, risks output parity, and buys nothing a
  façade does not.
