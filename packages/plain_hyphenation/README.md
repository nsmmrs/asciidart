# plain_hyphenation

Hyphenation in pure Dart, as TeX hyphenates: Liang's algorithm over the
[hyph-utf8](https://github.com/hyphenation/tex-hyphen) patterns of 72
languages, with each language's hyphenmins and exceptions.

```dart
import 'package:plain_hyphenation/plain_hyphenation.dart';

final english = hyphenatorFor('en')!; // en-US patterns
english.hyphenate('hyphenation'); // [2, 6]: hy-phen-ation
patternTag('de-AT'); // 'de-1996'
```

`hyphenatorFor` takes a language tag (`en`, `en_US`, `de`, `pt-BR`) and
finds its patterns through the tag itself, an alias (`de` reads as
`de-1996`) or its primary language. `PatternHyphenator` hyphenates with
any patterns and exceptions you give it.

The patterns are compiled ahead of time to tries (breadth-first, with
each node's digits shared), stored Brotli-compressed, one stream per
language family (about 470 KB for all 72 languages); a family is decoded
the first time one of its languages is used, straight into typed arrays,
and words are hyphenated by walking the trie, with nothing allocated but
the result.

Tests check every language's patterns against the vendored files, and
hyphenate the words of the Universal Declaration of Human Rights in 19
languages against typst's hypher and Hyphenopoly (`tool/oracles/`, the
`tools` tag): they agree on almost every word, and where they disagree with
each other, one of them agrees with this package. Given the same patterns,
pub.dev's `hyphenation` package breaks every word as this one does.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, whose PDF backend hyphenates with it.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The patterns keep their own licences (MIT,
BSD, LPPL, public domain and other permissive ones; GPL, LGPL and MPL
patterns are left out), reproduced in
[vendor/hyph-utf8/NOTICES.md](vendor/hyph-utf8/NOTICES.md).
