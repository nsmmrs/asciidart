# ADR-0004: Static Typing End to End

**Status:** Final — accepted by user 2026-10-04 ("We shouldn't have a single
bit of dynamic typing. Everything needs to be typed from end to end."). An
earlier draft proposed only a typed façade over dynamic internals; the user
rejected that.

## Context

The port carried Ruby's dynamic typing straight into Dart: about 740
`Object?` types, 210 `Map<String, Object?>` option and attribute maps, and
240 `isTruthy` calls in `lib/`. That shows up in the public API
(`load(Object? input, [Map<String, Object?>? options])`, `convert` returning
`Object?`, `attr()` returning `Object?`, untyped extension attribute maps)
and throughout the internals.

## Decisions

1. **No dynamic typing anywhere.** Not in the public API, not in the
   internals, not in the extension API or the template converter. `Object?`
   and `dynamic` are allowed only where a value is genuinely unconstrained
   and opaque to the converter (none are expected).
2. **Attributes are strings with typed fields.** Document and block
   attribute maps become `Map<String, String>`; AsciiDoc attributes are
   strings in the language. Positional attributes become a separate typed
   list. Numeric internals (table `rowcount`/`colcount`, column
   `colpcwidth`, `safe-mode-level`, counters, ...) become typed fields on
   the nodes, formatted once where an attribute value is needed. Unset and
   soft-unset (`false`) states are modeled explicitly rather than with
   `null`/`false` values.
3. **Typed options.** Each entry point takes an immutable options class
   (`AsciidoctorOptions` and friends) with typed fields; the CLI builds the
   same class. The string-keyed option maps are removed.
4. **Typed results.** `convert` returns `String`; converters return
   `String`; node `convert()` returns `String`.
5. **Typed extensions.** Processor callbacks, `create*` helpers and
   registration use typed parameters and typed attribute access.
6. **Output does not change.** The refactor keeps converted output
   byte-identical to Asciidoctor 2.0.26 (ADR-0001 D4); `tool/parity.sh` and
   the e2e suite gate every step.

## Consequences

- A large refactor across the parser, substitutions, converters and
  extensions, done incrementally behind the parity gate.
- The public API changes completely before 0.1.0, which is the cheapest
  time to change it.
- The npm build (EPIC-2qq14f) builds its JavaScript façade on the typed
  API.

## Implementation

Tracked as TASK-67yl6b and its follow-up cards.
