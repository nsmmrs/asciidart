# Dart port: custom converter templates — research result (READ-ONLY, no files written)

## Correction to the premise

Asciidoctor.js did **not** drop the template converter. It ships its own, documented at [Template Converter](https://docs.asciidoctor.org/asciidoctor.js/latest/extend/converter/template-converter/): built-in EJS / Handlebars / Nunjucks / Pug engines (optional npm deps) + plain-JS templates (`export default ({ node }) => ...`, loaded via dynamic `import()`), `-T/--template-dir` (repeatable), `template_dirs` API option, last-wins conflict resolution, `helpers.js` with `configure(context)` and per-engine isolated environments. Naming is `<node-name>.<ext>` (single extension, **no** backend infix — simpler than Ruby). The Ruby docs (`docs/modules/convert/pages/templates.adoc`) confirm: "Asciidoctor.js provides its own template converter, which means you have to develop a different set of templates." So **no Tilt-template portability is expected of any port** — the Dart port is free to define its own template story, following the Asciidoctor.js precedent.

## What must be reproducible (Ruby contract, from `lib/asciidoctor/converter/template.rb`, `converter.rb` Factory, CLI, `test/converter_test.rb`)

1. **Discovery**: scan each of `template_dirs` (non-recursive); descend into `<dir>/<backend>/`, and if `template_engine` is set, `<dir>/<engine>/` then `<dir>/<engine>/<backend>/`. File pattern `*.<engine>` or `*`.
2. **Naming**: basename minus double extension → transform name (`paragraph.html.slim` → `paragraph`); legacy `block_*` prefix stripped, `block_ruler` → `thematic_break`. Must match `node.node_name`.
3. **Overlay, not replacement**: `Factory.create` wraps `CompositeConverter(TemplateConverter, builtin)` when `template_dirs` is set and converter `supports_templates?`; missing transforms fall back to builtin. Pure `TemplateConverter` only for unknown backends (or `delegate_backend`).
4. **Render model**: the **node itself is the scope** (`template.render node, opts`); `opts` become locals; `document` template output `.strip`, others `.rstrip`; missing transform raises. `handles?(name)`, `register(name, template)` API.
5. **Engines**: Tilt dispatches on outer extension; defaults tuned per engine (ERB trim, Haml xhtml/html5, Slim `disable_escape`, `include_dirs`, Slim-embedded-Asciidoc safe-mode alignment); `template_engine_options` overrides; `eruby` selects erb/erubi/erubis; `helpers.rb` auto-required per dir.
6. **Caching**: `template_cache: true` (default) → process-global scan+template caches (thread-safe only with concurrent-ruby); Hash → custom cache; `false` → disabled. `clear_caches`.
7. **CLI/API surface**: `-T/--template-dir` repeatable → `template_dirs` array (coerced); `-E/--template-engine`; `template_dir` singular deprecated.

## Ranked options

### 1 (recommended): Static plugin converters (plain Dart) FIRST; Mustache file templates SECOND, behind the same `TemplateConverter`-shaped API

**Fidelity-vs-effort**: Best ratio. A `Converter` interface + `CompositeConverter` with per-transform function overrides reproduces ~90% of *behavioral* value (à-la-carte output override, fallback, `handles?`, `register`) at low effort, zero dependencies, and works on all Dart platforms (VM, AOT, web — no runtime code loading). File-based Mustache templates (`package:mustache_template`, flutter.dev-verified, v2.0.6, Dart 3, all platforms, spec-compliant, supports Map keys **and object members**, dotted paths, lambdas, partials, lenient mode) then add the no-Dart-toolchain authoring story: `paragraph.mustache` files + `template_dirs` scanning + last-wins resolution, mirroring Asciidoctor.js naming (single extension, no backend infix — or keep Ruby's double-extension parse for familiarity; Asciidoctor.js proves single-extension is acceptable).
**API sketch (template authors)**:
```dart
// (a) code-first: no files, no toolchain beyond Dart
Asciidoctor.convert(src, templateOverrides: {
  'paragraph': (node) => '<p class="para">${node.content}</p>',
});
// (b) file-based: templates/paragraph.mustache  →  <p class="paragraph">{{content}}</p>
Asciidoctor.convertFile(f, templateDirs: ['templates']); // CLI: -T templates
// helpers.dart equivalent: optional per-dir `helpers.dart` exporting
// Map<String, Function> lambdas/partials registered into the render context
```
Render context per node: a Map/object exposing `content`, `text`, `id`, `role`, `title`, `attr(name)`, `document`, `items` etc. (Mustache lambdas cover method-with-args cases like `attr 'lang'` via `{{#attr}}lang{{/attr}}`-style sections or pre-flattened keys).
**Migration story for Tilt users**: honest rewrite, exactly like the Asciidoctor.js migration (docs already tell users each runtime needs its own templates). Provide: (1) a node-name ↔ context table (same names as Ruby), (2) a `content`/`text`/`items` cookbook mapping Slim/Haml idioms → Mustache (`- if title?` → `{{#title}}`, `- items.each` → `{{#items}}`), (3) one worked example per engine (paragraph/sidebar/document). No automated Slim→Mustache transpiler — out of scope, and logic-full templates (arbitrary Ruby in `=` lines, `helpers.rb` code) cannot be mechanically translated into logic-less Mustache; those users take path (a) and port logic to Dart.
**Effort**: (a) ~days (interface + composite + registry already半岛 implied by port); (b) ~1–2 weeks (scanner, Mustache adapter, context builder, cache).

### 2: Mustache-only file templates (skip code-first overrides)

**Fidelity-vs-effort**: Medium fidelity (covers simple output tweaks, the common case) at medium-low effort, but strictly less expressive than option 1(a) for zero extra saving — any logic beyond sections/variables (conditionals on methods with args, `find_by`, custom helpers) needs Dart lambdas anyway, at which point you've built half of option 1. Also forces *all* customization through the filesystem, awkward for programmatic users and Flutter/web embeds. Only pick if the port wants a hard "templates are data files" constraint. Migration story same as 1(b), minus the escape hatch — Tilt users with logic-heavy templates are stranded.

### 3: Dart-native codegen (build_runner: `.dart.html`-ish templates → generated converter code)

**Fidelity-vs-effort**: Highest expressiveness (full Dart in templates, AOT-safe, no runtime parsing) but highest effort and worst authoring UX: template authors need the Dart toolchain + build step, `-T dir` at runtime stops working for logic templates (generated code must be compiled in), and you must design, document, and maintain a new template syntax or source-gen convention. Justifiable only if a hard requirement emerges for *compiled-in, logic-full, file-authored* templates (e.g., a Flutter app shipping custom rendering with no asset loading). Migration: same rewrite as option 1, plus build-setup docs. Defer unless option 1 proves insufficient.

### Explicitly NOT recommended: Tilt/Haml/Slim/ERB parity

Impossible in spirit: Dart has no runtime code evaluation (`dart:mirrors` removed, no `eval`, no dynamic `import()` of source files at runtime — contrast with Asciidoctor.js's dynamic-`import()` plain-JS templates). Any "embedded-Dart" file template would require writing a Dart expression parser/interpreter — a project in itself. Asciidoctor.js already set the precedent that ports define their own template language.

## What I could NOT determine (follow-up round)

1. **Mustache object-member depth**: `mustache_template` resolves "map key or object member" + dotted paths, but I did not verify whether *methods* (zero-arg getters vs. methods needing args, e.g. `attr('lang')`, `content(model:)`) are invocable from tags, or only fields/getters. This decides how much of the node API must be pre-flattened into the render Map. (One probe program settles it.)
2. **Whether the Dart port targets web/Flutter**: if VM/CLI-only, codegen (option 3) is more palatable and `dart:io` scanning is free; if web is in scope, runtime `-T` directory scanning is impossible there and option 1(a) + bundled-template assets become the primary story. This is **the** decision-driving question.
3. **HTML-escaping default**: Ruby Slim/Haml run with escaping disabled; Mustache escapes `{{x}}` by default (`{{{x}}}` raw). Need a decision: lenient+raw-by-default context (converters emit safe HTML already) vs. Mustache-default escaping. Affects every template example.
4. **Scope of `supports_templates?`/custom-backend emulation** (`backend: 'html5-tweaks:html'`, `delegate_backend`): unclear how far the Dart port intends to mirror converter-registry semantics; the template design inherits whatever the port's `Converter` architecture becomes.
5. **helpers story**: Ruby auto-requires `helpers.rb` (arbitrary code); Asciidoctor.js `helpers.js` exports `configure(context)` per engine. Dart equivalent (a `helpers.dart` of lambdas? or just "use option 1(a)") needs a UX decision, pending Q2.