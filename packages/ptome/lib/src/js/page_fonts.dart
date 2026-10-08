/// The fonts a browser has that aren't in font folders (the page's web
/// fonts, the visitor's installed ones), found by the npm package's browser
/// entry point.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// What finds the page's and the visitor's fonts, set by the npm package's
/// browser entry point (`npm/src/page_fonts.js`): a function of whether
/// to take the page's fonts and the families to take from the visitor's,
/// whose promise resolves to `{name, bytes}` objects.
JSFunction? fontSource;

/// The page's fonts (when [page]) and the visitor's of [localFamilies],
/// in a browser; none elsewhere.
Future<List<(String, List<int>)>> platformFonts({
  required bool page,
  required List<String> localFamilies,
}) async {
  final source = fontSource;
  if (source == null || (!page && localFamilies.isEmpty)) return const [];
  final result =
      source.callAsFunction(
            null,
            page.toJS,
            [for (final family in localFamilies) family.toJS].toJS,
          )!
          as JSPromise<JSArray<JSObject>>;
  return [
    for (final file in (await result.toDart).toDart)
      (
        (file['name']! as JSString).toDart,
        (file['bytes']! as JSUint8Array).toDart,
      ),
  ];
}
