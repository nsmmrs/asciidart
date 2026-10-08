# plain_unicode

Unicode text algorithms in pure Dart, generated from the Unicode Character
Database, so they give the same results on the Dart VM and compiled to
JavaScript (whose own tables differ in age and in rules):

- **Line breaking** (UAX #14, Unicode 18.0.0): `lineBreaks(text)` lists
  the break opportunities of a text, mandatory or not, and
  `lineBreakClass(codePoint)` gives a code point's class. It passes every
  case of the conformance test, `LineBreakTest.txt`.
- **Case mapping** (Unicode 17.0.0): `upperCase` and `lowerCase` map each
  code point fully, special mappings included (`ß` to `SS`, `İ` to `i̇`).
  `lowerCase(text, finalSigma: true)` applies the Final_Sigma rule, as
  JavaScript's `toLowerCase` does; without it every capital sigma becomes
  `σ`, as Ruby's `String#downcase` does. The tables match Ruby 4.0.7 and
  Node.js 26 for every code point.

```dart
import 'package:plain_unicode/plain_unicode.dart';

upperCase('straße'); // 'STRASSE'
lowerCase('ΣΟΦΟΣ', finalSigma: true); // 'σοφος'
lineBreaks('Hello, world').map((b) => b.offset); // (7, 12)
```

Each table pins its Unicode version (`lineBreakUnicodeVersion`,
`caseMappingUnicodeVersion`); the generators in `tool/` rebuild them from
the files in `vendor/ucd/`. Graphemes and normalization are left to the
`characters` and `unorm_dart` packages.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace: plain_pdf breaks lines with it, ptome maps case as Asciidoctor
(Ruby) does with it, and plain_highlighting lower-cases as highlight.js
(JavaScript) does with it.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The Unicode Character Database files in
`vendor/ucd/` and the tables generated from them are under the Unicode
License v3 (`vendor/ucd/*/license.txt`).
