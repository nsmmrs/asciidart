# plain_math

Math notations to MathML in pure Dart, and MathML as a typed tree:

- **AsciiMath** to MathML, byte for byte as the `asciimath` gem 2.0.6
  writes it (Asciidoctor's `stem` converter).
- **LaTeX** math to MathML: the commands of LaTeX's and amsmath's math
  mode that documents use (the set KaTeX and MathJax have in common),
  `\text` with TeX's text mode, and the matrix, `cases`, `array` and
  alignment environments. The commands it doesn't read are shown as their
  names and reported.
- **MathML** to a typed tree (`MathNode`: tokens, rows, scripts,
  fractions, radicals, tables...), read by a small, strict XML reader of
  its own, for layout.

```dart
import 'package:plain_math/plain_math.dart';

asciimathToMathml('sqrt(x^2+1)');
// <math><msqrt><mrow><msup><mi>x</mi><mn>2</mn></msup><mo>+</mo>...

final unknown = <String>{};
final tree = latexToMath(r'\frac{a}{b} + \foo', unknown: unknown);
// tree is a MathRow of a MathFraction, an operator and a MathToken;
// unknown == {r'\foo'}
```

Tests compare the AsciiMath converter with the gem's output for 1,250
expressions (the gem spec's examples and every symbol of its table), the
MathML reader with package:xml over every document they write, and, with
the `tools` tag, the LaTeX converter with Temml over the examples of
Temml's screen tests (KaTeX's, the Mozilla torture test and LaTeXML's;
`tool/oracles/`).

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, whose PDF backend lays out its trees and whose HTML, DocBook
and EPUB backends write its MathML.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE).
