# Custom converter templates (cookbook)

This cookbook is for Tilt users (ERB/Haml/Slim) moving to the Dart port.
Tilt templates cannot run on Dart — there is no runtime code evaluation —
so each runtime needs its own templates (the same stance Asciidoctor.js
takes with its own template converter). The Dart port offers two paths
([ADR-0002](../../adr/0002-template-converter-strategy.md)):

- **(a) Code-first overrides (primary):** per-transform Dart functions.
  No files, no IO, works on all platforms (VM, AOT, web).
- **(b) Mustache files (secondary):** `paragraph.mustache`-style files
  under `-T/--template-dir` directories (CLI parity with Ruby `-T`).

Both paths overlay per-transform overrides on top of the built-in
converter: an override wins for its transform, and everything else falls
back to the built-in converter. When both a function and a Mustache
template are registered for one transform, the function wins.

## Path (b): Mustache files

```sh
mkdir -p templates
cat > templates/paragraph.mustache <<'EOF'
<p>{{content}}</p>
EOF
asciidoctor -T templates doc.adoc
```

Resolution rules (deliberately simpler than Ruby):

- Only `*.mustache` files load; the transform name is the basename minus
  `.mustache` (`paragraph.mustache` goes to `paragraph`). There is no
  `block_` prefix and no `block_ruler` to `thematic_break` renaming.
- Directories scan top level only (no recursion); missing directories
  are skipped; with several `-T` flags the last directory wins per
  transform.
- There are no per-engine or per-backend subdirectories: the same file
  serves every backend (no `html5/` infix, no `.html.slim` split).
- `-E/--template-engine` accepts `mustache` (the file scan) and `dart`
  (code-registered transforms only; scans no files). Any other engine
  fails exactly like Ruby's missing Tilt engine. Without `-T`, `-E`
  stays inert.
- There is no `helpers.rb`: custom helpers are Dart lambdas registered
  through path (a) and injected into the render context (see below).

`template_cache` mirrors Ruby's process-lifetime cache: absent or `true`
shares the global cache, `false`/`null` disables it, and a
`TemplateCache` instance is a custom store.

## Transform names

The transform is the node's node name (usually its context). The
complete html5 set, grouped by kind:

| Group | Transforms |
| --- | --- |
| Document | `document`, `embedded`, `preamble`, `section`, `floating_title` |
| Blocks | `paragraph`, `sidebar`, `example`, `quote`, `verse`, `literal`, `listing`, `stem`, `open`, `pass`, `page_break`, `thematic_break`, `toc`, `admonition` |
| Media | `image`, `audio`, `video` |
| Lists and tables | `ulist`, `olist`, `dlist`, `colist`, `table` |
| Special | `outline` (the TOC; called with an internal `toclevels` option) |
| Inline | `inline_quoted`, `inline_anchor`, `inline_break`, `inline_button`, `inline_callout`, `inline_footnote`, `inline_image`, `inline_indexterm`, `inline_kbd`, `inline_menu` |

(The docbook5/manpage sets are analogous.) Any name without an override
falls back to the built-in converter, so a directory holding only
`paragraph.mustache` changes just paragraphs. To override the whole page,
register `document` (standalone) or `embedded` (embedded output).

## Render context

Mustache resolves Map keys and dotted paths only — Dart object members
are invisible to it — so each node is pre-flattened to a Map before
rendering. Missing keys render as empty output (lenient), and
`{{var}}` interpolation is raw by default (converter output is
already-safe HTML; Mustache-default escaping would double-escape every
`{{content}}`).

| Key | Value per node kind |
| --- | --- |
| `content` | Converted content. Blocks: the converted string; lists: the raw item list (iterate `items` instead); inlines: the text. |
| `text` | Inline/list-item text; `null` elsewhere. |
| `title` | Converted block title (caption excluded; the doctitle on documents); `null` on inlines. |
| `caption` | Block caption (`Figure 1.`, and so on); `null` elsewhere. |
| `id`, `role`, `roles` | The node id, first role, and all roles. |
| `context`, `node_name` | The node context (for example `paragraph`) and node name (for example `inline_quoted` on inlines). |
| `attributes` | Shallow copy of the node attributes (dotted lookups such as `{{attributes.foo}}` and truthiness sections). |
| `attr` | Section lambda for attributes with arguments: `{{#attr}}name{{/attr}}`, with an optional `=default` suffix (`{{#attr}}lang=en{{/attr}}`). Falls back to document attributes. |
| `document` | Shallow document map (`title`, `attributes`); `null` while detached. Never nested recursively. |
| `items` | List items, each pre-flattened (description-list pairs become maps with `terms` and `description`); `null` on non-lists. |
| `sections` | Child sections of a document or section, each pre-flattened (nesting recurses); `null` elsewhere. This is what a custom `outline` template iterates. |

Per-call options and registered helpers merge in as top-level keys
(call-site values win on collision).

Examples:

```mustache
{{! paragraph.mustache }}
<p>{{content}}</p>
```

```mustache
{{! sidebar.mustache }}
<aside>{{#title}}<header><h1>{{title}}</h1></header>{{/title}}{{content}}</aside>
```

```mustache
{{! outline.mustache — custom TOC }}
<ul>{{#sections}}<li>{{title}}</li>{{/sections}}</ul>
```

```mustache
{{! image.mustache — attribute reads }}
<figure><img src="{{attributes.target}}" alt="{{attributes.alt}}"></figure>
```

## Path (a): Dart functions

Register one function per transform name; the handler receives the node
(the full node API — no flattening) and the optional per-call options:

```dart
import 'package:asciidoctor/asciidoctor.dart';

final registry = TemplateRegistry();
registry.registerFunction('paragraph', (node, [opts]) {
  final content = (node as Block).content();
  return '<p class="custom">$content</p>';
});
// Function plus Mustache template for one transform: the function wins.
registry.registerTemplate('paragraph', '<p>{{content}}</p>');

final converter = TemplateConverter('html5', {}, registry)
    .withFallback(Html5Converter('html5'));
```

Custom helpers for Mustache templates are lambdas evaluated against the
node on every render and injected into the context:

```dart
registry.registerHelper('shout', (node) => node.attr('title').toString().toUpperCase());
// paragraph.mustache: <p>{{shout}}: {{content}}</p>
```

Functions registered on the process-wide `TemplateRegistry.global`
engage for every conversion in the process — including ones with no
`-T` directory — because the converter factory merges them into every
template chain it builds. That is the seam custom binaries use.

## When to graduate from Mustache to functions

- Stay on Mustache while the override is markup reshaping: reordering
  `{{content}}`/`{{title}}`/attributes, adding wrappers or classes.
- Graduate to a function when the template needs logic Mustache cannot
  express: conditionals beyond truthiness, loops over anything but
  `items`/`sections`, computed values, or access to node methods
  outside the flattened context (for example section numbers or list
  markers).
- Graduate when the override must run on the web (no `-T` directory
  enumeration there) or ship inside one binary with no data files.

## XMonad-style custom binary

The CLI entrypoint is a reusable library function, `runCli(args)`, so a
project can compile its path-(a) overrides into its own binary:

```sh
asciidoctor init-config my-config
cd my-config
dart pub get
```

This generates a project — `pubspec.yaml`, `lib/transforms.dart` (one
example `registerFunction`), `bin/main.dart` (registers the transforms,
then calls `runCli`), and a README. Edit the transforms, then run or
compile:

```sh
dart run bin/main.dart doc.adoc        # JIT, for development
dart compile exe bin/main.dart -o my-asciidoctor
./my-asciidoctor doc.adoc              # AOT, for distribution
```

Notes:

- `init-config` takes an optional target directory (default: the
  current directory) and refuses to overwrite existing scaffold files
  unless `--force` is given. A file literally named `init-config` can
  still be converted by spelling it `./init-config`.
- There is no `--rebuild` helper: re-run `dart compile exe` yourself.
- `-j/--jobs` parallel conversion runs files on worker isolates, which
  do not inherit in-process registrations; combine custom functions
  with `-j` only via `-T` Mustache templates (or a single job).
