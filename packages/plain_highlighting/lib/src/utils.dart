/// Port of `src/lib/utils.js` (`inherit` lives with the mode model).
library;

/// [value] with `&`, `<`, `>`, `"` and `'` escaped for HTML.
String escapeHtml(String value) {
  final buffer = StringBuffer();
  if (!writeEscapedHtml(buffer, value)) return value;
  return buffer.toString();
}

/// Writes [value] (from [start] to [end]) to [buffer] escaped as
/// [escapeHtml] does, in one pass (the slices between special characters
/// as they are); returns whether it had a special character.
bool writeEscapedHtml(
  StringBuffer buffer,
  String value, [
  int start = 0,
  int? end,
]) {
  var from = start;
  final n = end ?? value.length;
  for (var i = start; i < n; i++) {
    final String escaped;
    switch (value.codeUnitAt(i)) {
      case 0x26:
        escaped = '&amp;';
      case 0x3c:
        escaped = '&lt;';
      case 0x3e:
        escaped = '&gt;';
      case 0x22:
        escaped = '&quot;';
      case 0x27:
        escaped = '&#x27;';
      default:
        continue;
    }
    if (i > from) buffer.write(value.substring(from, i));
    buffer.write(escaped);
    from = i + 1;
  }
  if (from == start) {
    buffer.write(
      start == 0 && n == value.length ? value : value.substring(start, n),
    );
    return false;
  }
  if (from < n) buffer.write(value.substring(from, n));
  return true;
}
