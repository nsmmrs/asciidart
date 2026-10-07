/// A block with the `unbreakable` option in the markup backends
/// (ADR-0012): HTML and EPUB give its element the class `unbreakable`,
/// which the stylesheets keep on one page (`break-inside: avoid`), and
/// DocBook a processing instruction its FO stylesheets keep together.
library;

final RegExp _firstTag = RegExp(r'^(\s*<[a-zA-Z][\w:-]*)([^>]*?)(\s*/?>)');
final RegExp _classAttr = RegExp(r'\sclass="([^"]*)"');

/// [html], a converted block, with the class `unbreakable` on its first
/// element.
String withUnbreakableClass(String html) {
  final tag = _firstTag.firstMatch(html);
  if (tag == null) return html;
  final attrs = tag[2]!;
  final classes = _classAttr.firstMatch(attrs);
  final marked = classes == null
      ? '$attrs class="unbreakable"'
      : attrs.replaceFirst(classes[0]!, ' class="${classes[1]} unbreakable"');
  return html.replaceRange(0, tag.end, '${tag[1]}$marked${tag[3]}');
}

/// [xml], a converted DocBook block, with DocBook XSL's
/// `<?dbfo keep-together="always"?>` as its first element's first child.
String withKeepTogether(String xml) {
  final tag = _firstTag.firstMatch(xml);
  if (tag == null || tag[3]!.trim() == '/>') return xml;
  return xml.replaceRange(tag.end, tag.end, '<?dbfo keep-together="always"?>');
}

/// Whether blocks named [nodeName] get the marks (not the structural
/// ones).
bool marksUnbreakable(String nodeName) =>
    !const {'document', 'section', 'preamble'}.contains(nodeName);
