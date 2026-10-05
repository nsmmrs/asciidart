/// Port of `src/lib/utils.js` (`inherit` lives with the mode model).
library;

final RegExp _htmlSpecial = RegExp('[&<>"\']');

/// [value] with `&`, `<`, `>`, `"` and `'` escaped for HTML.
String escapeHtml(String value) {
  if (!_htmlSpecial.hasMatch(value)) return value;
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}
