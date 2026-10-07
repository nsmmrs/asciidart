# fonts

TrueType, OpenType, WOFF and WOFF2 fonts in pure Dart:

- **Reading fonts.** `OpenTypeFont.parse` reads metrics, character maps,
  glyph outlines and bounds, kerning (`kern` and GPOS pairs), OpenType
  substitutions (single, multiple, ligatures), names and the MATH table,
  from a font file, a collection, or a WOFF or WOFF2 font.
- **Web fonts.** `decodeWebFont` gives the TrueType or OpenType font a
  WOFF or WOFF2 font wraps, its WOFF2 table transforms undone as the
  reference decoder does.
- **Subsetting.** `glyphClosure`, `subsetTrueType` and `subsetCff` keep
  only the glyphs a document uses, their ids unchanged, for embedding.
- **Installed fonts.** `FontIndex` finds fonts by file name, or by family
  and style (the nearest style when the one asked for isn't there). It
  looks in the user's and the system's font folders (on Linux, macOS and
  Windows, on the Dart VM and on Node.js), in folders of your choosing,
  and among fonts given as bytes. It reads only each file's `name` and
  `OS/2` tables, and caches what it read by path, size and modification
  time.

```dart
import 'package:fonts/fonts.dart';

final installed = FontIndex.system(cacheFile: '/tmp/font-index.tsv');
final serif = installed.find('Noto Serif', bold: true);
if (serif != null) {
  final font = OpenTypeFont.parse(installed.fontBytes(serif.path));
  print('${font.familyName}: ${font.numGlyphs} glyphs');
}
```

Fonts that can't be read throw a `FontFormatException`.

On JavaScript the WOFF and WOFF2 decoder (with its Brotli dictionary) is
loaded on demand: `await FontIndex.loadWebFontDecoder()` before indexing
web fonts, so that programs that read none don't carry it. A `FontFiles`
implementation gives the index files from elsewhere.

The library was extracted from [libpdf](https://github.com/nsmmrs/libpdf)
(reading, subsetting, web fonts) and
[asciidart](https://github.com/nsmmrs/asciidart) (the index). Compression
comes from [compression](https://github.com/nsmmrs/compression).

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The test fonts are under their own licenses;
see [test/fonts/README.md](test/fonts/README.md).
