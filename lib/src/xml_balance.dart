/// Keeps XML output well-formed where AsciiDoc markup leaves it broken
/// (emphasis that opens inside an index term and closes after it, say):
/// the DocBook and EPUB backends pass their output through [balanceXml].
library;

final RegExp _tokenRx = RegExp(
  r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<![^>]*>|'
  r'''<(/?)([A-Za-z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>''',
);

/// [xml] with its tags paired: an end tag with no open element is left
/// out, and elements left open inside an element that ends are closed
/// there. Well-formed XML comes back unchanged.
String balanceXml(String xml) {
  final open = <String>[];
  StringBuffer? out;
  var last = 0;
  for (final m in _tokenRx.allMatches(xml)) {
    final name = m[2];
    if (name == null || m[4] == '/') continue;
    if (m[1] != '/') {
      open.add(name);
      continue;
    }
    if (open.isNotEmpty && open.last == name) {
      open.removeLast();
      continue;
    }
    // A repair: the text so far, then the end tags the element needs.
    out ??= StringBuffer();
    out.write(xml.substring(last, m.start));
    last = m.end;
    if (open.contains(name)) {
      while (open.last != name) {
        out.write('</${open.removeLast()}>');
      }
      open.removeLast();
      out.write(m[0]);
    }
  }
  if (out == null) return xml;
  out.write(xml.substring(last));
  return out.toString();
}
