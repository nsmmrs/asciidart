# plain_highlighting

Syntax highlighting for 190+ languages in pure Dart. plain_highlighting is a port of
[highlight.js](https://highlightjs.org) 11.12.0: the same languages, the same
HTML, the same CSS classes, so every highlight.js theme works with it. It runs
wherever Dart runs (VM, AOT, web, Flutter), with no JavaScript runtime.

> plain_highlighting is an independent port, not affiliated with or endorsed by the
> highlight.js project.

```dart
import 'package:plain_highlighting/plain_highlighting.dart';

void main() {
  final result = highlighting.highlight('final x = 1;', language: 'dart');
  print(result.html);
  // <span class="hljs-keyword">final</span> x = <span class="hljs-number">1</span>;

  final auto = highlighting.highlightAuto('def greet(name):\n    return f"hi {name}"\n');
  print(auto.language); // python
}
```

- `highlight(code, language: ...)` highlights as a language (a name or an
  alias such as `js`, `sh`, `yml`).
- `highlightAuto(code)` picks the language that fits best, optionally among
  `languages: [...]`.
- `HighlightResult` has the `html`, the `language`, its `relevance`, and for
  auto-detection the runner-up (`secondBest`).
- `Highlighting(classPrefix: ...)` changes the `hljs-` prefix of the CSS classes.
- `highlightJsStyles` holds highlight.js's themes, each stylesheet by its
  name (`github`, `atom-one-dark`).

## Compatibility

plain_highlighting produces the same output as highlight.js 11.12.0, and is checked
against it:

- upstream's markup tests (568 cases over every language with tests) give
  byte-identical HTML (`test/markup_test.dart`);
- auto-detection picks the same language, with the same relevance and
  runner-up, as highlight.js for 766 samples (`test/detect_test.dart`);
- the language definitions are generated from highlight.js itself
  (`tool/generate/generate.mjs`): each upstream definition runs against the
  real highlight.js and the resulting mode graph is written out as data
  (compressed, read the first time a language is used), so the regular
  expressions, keywords and relevance are upstream's exactly.

Left out: the browser API (`highlightAll`, `highlightElement`), plugins, and
custom language definitions (all of highlight.js's built-in languages are
included).

## Development

```sh
dart test                          # markup, detection and unit tests
tool/vendor.sh --check             # vendor/ matches the pinned release
tool/vendor_styles.sh              # re-vendor and embed the themes
cd tool/generate && npm ci && cd ../..
node tool/generate/generate.mjs    # regenerate lib/src/languages
node tool/generate/reference.mjs   # regenerate test/reference/detect.json
```

The generated files are committed, so building plain_highlighting needs no Node.js.

## License

MIT (see [LICENSE](LICENSE)). The engine is ported from, and the language
definitions are generated from, highlight.js, whose BSD 3-Clause license is
included in LICENSE; `vendor/highlight.js` holds the upstream sources and
tests used, unchanged.
