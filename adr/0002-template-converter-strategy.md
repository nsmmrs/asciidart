# ADR-0002: Custom Converter Templates Strategy

**Status:** Final — accepted by user 2026-10-03 (T5: web viable; XMonad-style
scaffold in scope; no recompile helper).

## Context

Ruby Asciidoctor supports user-supplied converter templates via Tilt
(ERB/Haml/Slim/...): `-T/--template-dir` directories overlay per-node-name
templates on top of the built-in converter, with fallback for missing
transforms (`lib/asciidoctor/converter/template.rb`). Dart has no Tilt
equivalent and no runtime code evaluation (`dart:mirrors` removed, no `eval`,
no dynamic source import), so Tilt-template compatibility is impossible.

Precedent: Asciidoctor.js ships its own template converter (EJS / Handlebars
/ Nunjucks / Pug + plain-JS templates) and the Ruby docs state plainly that
each runtime needs its own templates. No cross-runtime template portability
is expected of any port. (Early spike report, recorded on TASK-9mfkvk.)

## Decisions

### T1. Two-path story — PROPOSED (spike option 1)

- **(a) Code-first overrides (primary):** per-transform Dart functions
  registered through the `Converter`/`CompositeConverter` API — no files, no
  toolchain beyond Dart, works on all platforms (VM, AOT, web).
- **(b) File-based Mustache templates (secondary):** `paragraph.mustache`
  files under `template_dirs` (CLI `-T` parity), single extension, no backend
  infix (Asciidoctor.js naming precedent), last-wins resolution, fallback to
  the built-in converter. Engine: `package:mustache_template` (verified
  2.0.6 in pub cache).

Effort estimate (from spike): (a) days, (b) 1–2 weeks. Tilt users get an
honest rewrite with a node-name/context cookbook; logic-heavy templates take
path (a). No Slim→Mustache transpiler (out of scope).

Explicitly NOT pursued: Tilt/Haml/Slim/ERB parity (impossible in spirit),
build_runner codegen templates (deferred unless path (a) proves insufficient
for a compiled-in logic-full use case).

### T2. Render context is pre-flattened Maps — PROVEN by probe

Correction to the spike: `mustache_template` 2.0.6 does **not** resolve Dart
object members. Probe (`/tmp/mprobe`, offline, 2026-10-03) results:

- `{{title}}` against an object with field/getter/zero-arg method
  `title`/`text`/`content` → all throw `Value was missing`.
- Map keys + dotted paths (`{{node.title}}`) → work.
- Section lambdas (`String Function(LambdaContext)`) → work; this is how
  methods-with-args surface (`{{#attr}}lang{{/attr}}`-style).
- `htmlEscapeValues: false` named flag exists; `lenient: true` renders
  missing keys as empty.

So the context builder pre-flattens each node to
`content`/`text`/`id`/`role`/`title`/`attr(name)`-via-lambda/`document`/`items`
Maps. No reflection needed anywhere.

### T3. Escaping default — PROPOSED: raw (`htmlEscapeValues: false`)

Ruby Slim/Haml templates run with escaping disabled, and converter output is
already-safe HTML. Mustache-default escaping would double-escape every
`{{content}}`. Decision: raw-by-default to match Ruby semantics; template
examples use `{{x}}` for converter HTML.

### T4. Helpers story — PROPOSED: lambdas via path (a), no `helpers.dart`

Ruby auto-requires per-dir `helpers.rb` (arbitrary code); Asciidoctor.js uses
`helpers.js` with `configure(context)`. Dart file templates get no code
loading: custom helpers are Dart lambdas registered through path (a) and
injected into the render context. Documented as the one intentional gap vs
Ruby `-T`, forced by the platform.

### T5. Platform split — DECIDED: web stays viable (three-way loader seam)

- Dart VM / AOT: `dart:io` directory scan (the `-T` CLI path).
- JS on Node: Node `fs` via JS interop, selected by runtime detection
  (`typeof process?.versions?.node`), so one npm bundle serves both
  environments. Same last-wins semantics as the VM scanner.
- JS in browser: runtime template registration only
  (`registerTemplate(name, source)` / template map in options); directory
  enumeration is impossible and `-T` is VM/CLI-only.

No build-time template injection for the JS build (rejected by user).
The renderer + pre-flattened context (T2) are shared, platform-free code;
only source loading sits behind the seam.

### T6. XMonad-style build-time config — DECIDED: scaffold in scope

Path (a) ships with a first-class custom-binary story: the CLI entrypoint
is a reusable library function (`runCli(args)`), and an `init-config`
scaffold generates a user project (pubspec + `transforms.dart` stub +
`main.dart`) that registers Dart functions and compiles with
`dart compile exe`. The cookbook documents this as the graduation path
from Mustache files. No `--rebuild`-style recompile helper (deferred
until requested; users run `dart compile exe` themselves).

## Consequences

- Template wave work items: context builder, `template_dirs` scanner +
  last-wins resolution, Mustache adapter, cache semantics (`template_cache`),
  CLI `-T`/`-E` wiring (options port carries the flags; `-E` accepts only
  `mustache` + `dart` until further engines exist), cookbook docs.
- `-E/--template-engine` keeps flag parity but with a Dart-side engine
  vocabulary; unknown engines error exactly like Ruby's missing Tilt engine.
- `supports_templates?` / custom-backend emulation (`delegate_backend`)
  inherits whatever the port's `Converter` architecture becomes (Q4);
  revisit when the converter wave lands.
