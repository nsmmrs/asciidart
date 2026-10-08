/// Keeps XML output well-formed where AsciiDoc markup leaves it broken
/// (emphasis that opens inside an index term and closes after it, say):
/// the DocBook and EPUB backends pass their output through [balanceXml].
library;

/// A start, end or empty-element tag of an XML text (see [xmlTags]).
typedef XmlTag = ({int start, int end, String name, bool closing, bool empty});

/// The tags of [xml] in order, comments, CDATA sections, processing
/// instructions and declarations passed over: a hand-written scan
/// matching what this pattern finds (`allMatches`), many times faster.
///
/// ```text
/// <!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<![^>]*>|
/// <(/?)([A-Za-z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>
/// ```
Iterable<XmlTag> xmlTags(String xml) sync* {
  final length = xml.length;
  var at = xml.indexOf('<');
  while (at >= 0) {
    final end = _skippedEnd(xml, at) ?? -1;
    if (end >= 0) {
      at = xml.indexOf('<', end);
      continue;
    }
    if (_tag(xml, at, length) case final tag?) {
      yield tag;
      at = xml.indexOf('<', tag.end);
      continue;
    }
    at = xml.indexOf('<', at + 1);
  }
}

/// The end of the comment, CDATA section, processing instruction or
/// declaration at [at] (a `<`), or null when there is none.
int? _skippedEnd(String xml, int at) {
  if (xml.startsWith('<!--', at)) {
    final close = xml.indexOf('-->', at + 4);
    if (close >= 0) return close + 3;
  }
  if (xml.startsWith('<![CDATA[', at)) {
    final close = xml.indexOf(']]>', at + 9);
    if (close >= 0) return close + 3;
  }
  if (xml.startsWith('<?', at)) {
    final close = xml.indexOf('?>', at + 2);
    if (close >= 0) return close + 2;
  }
  if (xml.startsWith('<!', at)) {
    final close = xml.indexOf('>', at + 2);
    if (close >= 0) return close + 1;
  }
  return null;
}

/// The tag at [at] (a `<`), or null when there is none.
XmlTag? _tag(String xml, int at, int length) {
  var i = at + 1;
  final closing = i < length && xml.codeUnitAt(i) == 0x2f;
  if (closing) i++;
  if (i >= length || !_isLetter(xml.codeUnitAt(i))) return null;
  final nameStart = i;
  i++;
  while (i < length && _isNameChar(xml.codeUnitAt(i))) {
    i++;
  }
  final name = xml.substring(nameStart, i);
  // The attributes, lazily: the tag ends at the first `/>` or `>` outside
  // quotes; an unclosed quote means no tag.
  while (i < length) {
    final char = xml.codeUnitAt(i);
    if (char == 0x2f && i + 1 < length && xml.codeUnitAt(i + 1) == 0x3e) {
      return (start: at, end: i + 2, name: name, closing: closing, empty: true);
    }
    if (char == 0x3e) {
      return (
        start: at,
        end: i + 1,
        name: name,
        closing: closing,
        empty: false,
      );
    }
    if (char == 0x22 || char == 0x27) {
      final close = xml.indexOf(String.fromCharCode(char), i + 1);
      if (close < 0) return null;
      i = close + 1;
    } else {
      i++;
    }
  }
  return null;
}

bool _isLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a;

/// `[\w:.-]`.
bool _isNameChar(int c) =>
    _isLetter(c) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5f ||
    c == 0x3a ||
    c == 0x2e ||
    c == 0x2d;

/// [xml] with its tags paired: an end tag with no open element is left
/// out, and elements left open inside an element that ends are closed
/// there. Well-formed XML comes back unchanged.
String balanceXml(String xml) {
  final open = <String>[];
  StringBuffer? out;
  var last = 0;
  for (final tag in xmlTags(xml)) {
    if (tag.empty) continue;
    final name = tag.name;
    if (!tag.closing) {
      open.add(name);
      continue;
    }
    if (open.isNotEmpty && open.last == name) {
      open.removeLast();
      continue;
    }
    // A repair: the text so far, then the end tags the element needs.
    out ??= StringBuffer();
    out.write(xml.substring(last, tag.start));
    last = tag.end;
    if (open.contains(name)) {
      while (open.last != name) {
        out.write('</${open.removeLast()}>');
      }
      open.removeLast();
      out.write(xml.substring(tag.start, tag.end));
    }
  }
  if (out == null) return xml;
  out.write(xml.substring(last));
  return out.toString();
}
