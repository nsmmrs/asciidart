/// Port of `test/substitutions_test.rb` for `lib/src/substitutors.dart`.
///
/// Ruby's suite drives substitutions through parsed blocks
/// (`block_from_string`) and full document conversion. The parser and
/// converter waves have not landed, so this port constructs [Document] +
/// [Block] manually ([blockFromString]) and converts inline nodes through
/// [FakeInlineConverter], a faithful test-local reimplementation of the
/// `inline_*` templates of the html5 and docbook5 converters (the only two
/// backends the Ruby file exercises). Each test preserves the Ruby
/// assertions; adaptations are marked with `PORT:` comments.
///
/// Tests needing full document conversion (footnote lists, section titles,
/// multi-block documents) or parsing (attribute entries, doctitle handling)
/// are skipped with a reason instead of being commented out.
library;

import 'dart:io' show Directory, File;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/highlight/syntax_highlighter.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/substitutors.dart';
import 'package:test/test.dart';

/// A single backslash, mirroring the `BACKSLASH` constant in the Ruby suite.
const String bs = r'\';

/// Records log messages for assertions.
class FakeLogger implements NodeLogger {
  /// Messages by severity.
  final List<Object?> debugs = <Object?>[];
  final List<Object?> infos = <Object?>[];
  final List<Object?> warns = <Object?>[];
  final List<Object?> errors = <Object?>[];
  final List<Object?> fatals = <Object?>[];

  @override
  void debug(Object? message) {
    debugs.add(message);
  }

  @override
  void info(Object? message) {
    infos.add(message);
  }

  @override
  void warn(Object? message) {
    warns.add(message);
  }

  @override
  void error(Object? message) {
    errors.add(message);
  }

  @override
  void fatal(Object? message) {
    fatals.add(message);
  }

  /// Whether no messages were recorded at any severity.
  bool get isEmpty =>
      debugs.isEmpty &&
      infos.isEmpty &&
      warns.isEmpty &&
      errors.isEmpty &&
      fatals.isEmpty;
}

/// Runs [body] with [logger] installed as the shared node logger.
T withFakeLogger<T>(FakeLogger logger, T Function() body) {
  final prev = AbstractNode.currentLogger;
  AbstractNode.currentLogger = logger;
  try {
    return body();
  } finally {
    AbstractNode.currentLogger = prev;
  }
}

/// Test-local reimplementation of the html5/docbook5 `inline_*` templates.
///
/// Only inline nodes are converted; anything else throws. The html5 branch
/// assumes HTML syntax (empty void-element slash); the docbook branch never
/// has the asciimath gem available.
class FakeInlineConverter implements NodeConverter {
  @override
  Object? convert(AbstractNode node) {
    final doc = node.document! as Document;
    final docbook = doc.attributes['basebackend'] == 'docbook';
    final inline = node as Inline;
    switch (node.nodeName) {
      case 'inline_quoted':
        return docbook ? _docbookQuoted(inline) : _htmlQuoted(inline);
      case 'inline_anchor':
        return docbook ? _docbookAnchor(inline, doc) : _htmlAnchor(inline, doc);
      case 'inline_break':
        return docbook ? '${inline.text}<?asciidoc-br?>' : '${inline.text}<br>';
      case 'inline_button':
        return docbook
            ? '<guibutton>${inline.text}</guibutton>'
            : '<b class="button">${inline.text}</b>';
      case 'inline_callout':
        return docbook ? _docbookCallout(inline) : _htmlCallout(inline, doc);
      case 'inline_footnote':
        return docbook ? _docbookFootnote(inline) : _htmlFootnote(inline);
      case 'inline_image':
        return docbook ? _docbookImage(inline, doc) : _htmlImage(inline, doc);
      case 'inline_indexterm':
        return docbook
            ? _docbookIndexterm(inline, doc)
            : (inline.type == 'visible' ? inline.text ?? '' : '');
      case 'inline_kbd':
        return docbook ? _docbookKbd(inline) : _htmlKbd(inline);
      case 'inline_menu':
        return docbook ? _docbookMenu(inline) : _htmlMenu(inline, doc);
      default:
        throw StateError('FakeInlineConverter cannot convert $node.');
    }
  }
}

const List<String> _noTags = <String>['', ''];

/// Mirrors `QUOTE_TAGS` in `converter/html5.rb` (tag pair + `true` when the
/// tag carries attributes).
const Map<String, List<Object>> _htmlQuoteTags = <String, List<Object>>{
  'monospaced': ['<code>', '</code>', true],
  'emphasis': ['<em>', '</em>', true],
  'strong': ['<strong>', '</strong>', true],
  'double': ['&#8220;', '&#8221;'],
  'single': ['&#8216;', '&#8217;'],
  'mark': ['<mark>', '</mark>', true],
  'superscript': ['<sup>', '</sup>', true],
  'subscript': ['<sub>', '</sub>', true],
  'asciimath': [r'$', r'$'],
  'latexmath': [r'\(', r'\)'],
};

String _htmlQuoted(Inline node) {
  final tags = _htmlQuoteTags[node.type] ?? _noTags;
  final open = tags[0] as String;
  final close = tags[1] as String;
  final hasTag = tags.length > 2;
  final text = node.text ?? '';
  if (node.id != null) {
    final classAttr = node.hasRole() ? ' class="${node.role}"' : '';
    if (hasTag) {
      return '${open.substring(0, open.length - 1)} id="${node.id}"$classAttr>$text$close';
    } else {
      return '<span id="${node.id}"$classAttr>$open$text$close</span>';
    }
  } else if (node.hasRole()) {
    if (hasTag) {
      return '${open.substring(0, open.length - 1)} class="${node.role}">$text$close';
    } else {
      return '<span class="${node.role}">$open$text$close</span>';
    }
  } else {
    return '$open$text$close';
  }
}

/// Mirrors `QUOTE_TAGS` in `converter/docbook5.rb`.
const Map<String, List<Object>> _docbookQuoteTags = <String, List<Object>>{
  'monospaced': ['<literal>', '</literal>'],
  'emphasis': ['<emphasis>', '</emphasis>', true],
  'strong': ['<emphasis role="strong">', '</emphasis>', true],
  'double': ['<quote role="double">', '</quote>', true],
  'single': ['<quote role="single">', '</quote>', true],
  'mark': ['<emphasis role="marked">', '</emphasis>'],
  'superscript': ['<superscript>', '</superscript>'],
  'subscript': ['<subscript>', '</subscript>'],
};

String _docbookQuoted(Inline node) {
  if (node.type == 'asciimath') {
    // The asciimath gem is never available in Dart.
    node.logger.warn(
      "optional gem 'asciimath' is not available. Functionality disabled.",
    );
    return '<inlineequation><mathphrase><![CDATA[${node.text}]]></mathphrase></inlineequation>';
  } else if (node.type == 'latexmath') {
    // unhandled math; pass source to alt and required mathphrase element;
    // dblatex will process alt as LaTeX math
    final equation = node.text ?? '';
    return '<inlineequation><alt><![CDATA[$equation]]></alt><mathphrase><![CDATA[$equation]]></mathphrase></inlineequation>';
  }
  final tags = _docbookQuoteTags[node.type] ?? const ['', '', true];
  final open = tags[0] as String;
  final close = tags[1] as String;
  final supportsPhrase = tags.length > 2;
  final text = node.text ?? '';
  final String quotedText;
  if (node.hasRole()) {
    if (supportsPhrase) {
      quotedText = '$open<phrase role="${node.role}">$text</phrase>$close';
    } else {
      quotedText =
          '${open.substring(0, open.length - 1)} role="${node.role}">$text$close';
    }
  } else {
    quotedText = '$open$text$close';
  }
  return node.id != null
      ? '<anchor${_commonAttributes(node.id, null, null)}/>$quotedText'
      : quotedText;
}

/// Mirrors `common_attributes` in `converter/docbook5.rb`.
String _commonAttributes(String? id, Object? role, String? reftext) {
  var attrs = '';
  if (id != null) {
    attrs = ' xml:id="$id"${isTruthy(role) ? ' role="$role"' : ''}';
  } else if (isTruthy(role)) {
    attrs = ' role="$role"';
  }
  if (reftext != null) {
    var label = reftext;
    if (label.contains('<')) {
      label = label.replaceAll(xmlSanitizeRx, '');
      if (label.contains(' ')) label = squeezeChar(label, ' ').trim();
    }
    if (label.contains('"')) label = label.replaceAll('"', '&quot;');
    attrs = '$attrs xreflabel="$label"';
  }
  return attrs;
}

/// Reference text of [node] with reftext substitutions applied.
String? _inlineReftext(Inline node) {
  final value = node.text;
  return value == null ? null : applyReftextSubs(node, value)! as String;
}

String? _htmlAnchor(Inline node, Document doc) {
  switch (node.type) {
    case 'xref':
      final path = node.attributes['path'];
      if (isTruthy(path)) {
        final attrs = _appendLinkConstraintAttrs(
          node,
          node.hasRole() ? [' class="${node.role}"'] : <String>[],
        ).join();
        return '<a href="${node.target}"$attrs>${node.text ?? path}</a>';
      }
      final attrs = node.hasRole() ? ' class="${node.role}"' : '';
      return '<a href="${node.target}"$attrs>${node.text ?? _resolveXrefText(node, doc)}</a>';
    case 'ref':
      return '<a id="${node.id}"></a>';
    case 'link':
      final attrs = <String>[];
      if (node.id != null) attrs.add(' id="${node.id}"');
      if (node.hasRole()) attrs.add(' class="${node.role}"');
      if (node.hasAttr('title')) attrs.add(' title="${node.attr('title')}"');
      return '<a href="${node.target}"${_appendLinkConstraintAttrs(node, attrs).join()}>${node.text}</a>';
    case 'bibref':
      return '<a id="${node.id}"></a>[${_inlineReftext(node) ?? node.id}]';
    default:
      node.logger.warn('unknown anchor type: ${node.type}');
      return null;
  }
}

/// Resolves display text for an xref without explicit link text.
String _resolveXrefText(Inline node, Document doc) {
  final refs = doc.catalog['refs']! as Map<String, Object?>;
  final refid = node.attributes['refid'] as String?;
  final ref = refid == null ? null : refs[refid];
  String? text;
  if (ref is AbstractBlock) {
    text = ref.xreftext();
  } else if (ref is Inline) {
    text = ref.xreftext();
  }
  if (text != null && text.contains('<a')) {
    text = text.replaceAll(RegExp(r'<(?:a\b[^>]*|/a)>'), '');
  }
  return text ?? ((refid == null || refid.isEmpty) ? '[^top]' : '[$refid]');
}

String? _docbookAnchor(Inline node, Document doc) {
  switch (node.type) {
    case 'ref':
      final id = node.id!;
      return '<anchor${_commonAttributes(id, null, _inlineReftext(node) ?? '[$id]')}/>';
    case 'xref':
      final path = node.attributes['path'];
      if (isTruthy(path)) {
        return '<link xl:href="${node.target}">${node.text ?? path}</link>';
      }
      var linkend = node.attributes['refid'] as String?;
      if (linkend == null || linkend.isEmpty) {
        // Q: should we warn instead of generating a document ID on demand?
        linkend = doc.id ??= '__${doc.doctype}-root__';
      }
      // NOTE the xref tag in DocBook does not support explicit link text,
      // so the link tag must be used instead
      final text = node.text;
      return text != null
          ? '<link linkend="$linkend">$text</link>'
          : '<xref linkend="$linkend"/>';
    case 'link':
      return '<link xl:href="${node.target}">${node.text}</link>';
    case 'bibref':
      final text = '[${_inlineReftext(node) ?? node.id}]';
      return '<anchor${_commonAttributes(node.id, null, text)}/>$text';
    default:
      node.logger.warn('unknown anchor type: ${node.type}');
      return null;
  }
}

/// Mirrors `append_link_constraint_attrs` in `converter/html5.rb`.
List<String> _appendLinkConstraintAttrs(Inline node, List<String> attrs) {
  final rel = node.hasOption('nofollow') ? 'nofollow' : null;
  final window = node.attributes['window'];
  if (isTruthy(window)) {
    attrs.add(' target="$window"');
    if (window == '_blank' || node.hasOption('noopener')) {
      attrs.add(rel != null ? ' rel="$rel noopener"' : ' rel="noopener"');
    }
  } else if (rel != null) {
    attrs.add(' rel="$rel"');
  }
  return attrs;
}

/// Mirrors `encode_attribute_value` in `converter/html5.rb`.
String _encodeAttrValue(String val) =>
    val.contains('"') ? val.replaceAll('"', '&quot;') : val;

/// Converted alt text of [node], mirroring `AbstractBlock#alt`.
String _inlineAlt(Inline node) {
  final text = node.attributes['alt'];
  if (!isTruthy(text)) return '';
  final source = text.toString();
  if (source == node.attributes['default-alt']) {
    return subSpecialchars(source);
  }
  final converted = subSpecialchars(source);
  return replaceableTextRx.hasMatch(converted)
      ? subReplacements(converted)
      : converted;
}

String _htmlCallout(Inline node, Document doc) {
  if (doc.hasAttr('icons', 'font')) {
    return '<i class="conum" data-value="${node.text}"></i><b>(${node.text})</b>';
  } else if (doc.hasAttr('icons')) {
    final src = node.iconUri('callouts/${node.text}');
    return '<img src="$src" alt="${node.text}">';
  } else if (node.attributes['guard'] is List) {
    return '&lt;!--<b class="conum">(${node.text})</b>--&gt;';
  } else {
    return '${node.attributes['guard'] ?? ''}<b class="conum">(${node.text})</b>';
  }
}

String _docbookCallout(Inline node) =>
    '<co${_commonAttributes(node.id, null, null)}/>';

String? _htmlFootnote(Inline node) {
  final index = node.attr('index');
  if (isTruthy(index)) {
    if (node.type == 'xref') {
      return '<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_$index" title="View footnote.">$index</a>]</sup>';
    } else {
      final idAttr = node.id != null ? ' id="_footnote_${node.id}"' : '';
      return '<sup class="footnote"$idAttr>[<a id="_footnoteref_$index" class="footnote" href="#_footnotedef_$index" title="View footnote.">$index</a>]</sup>';
    }
  } else if (node.type == 'xref') {
    return '<sup class="footnoteref red" title="Unresolved footnote reference.">[${node.text}]</sup>';
  }
  return null;
}

String _docbookFootnote(Inline node) {
  if (node.type == 'xref') {
    return '<footnoteref linkend="${node.target}"/>';
  } else {
    return '<footnote${_commonAttributes(node.id, null, null)}><simpara>${node.text}</simpara></footnote>';
  }
}

String _htmlImage(Inline node, Document doc) {
  final target = node.target!;
  final type = node.type ?? 'image';
  String? src;
  final String img;
  if (type == 'icon') {
    final icons = doc.attr('icons');
    if (icons == 'font') {
      var iClass = 'fa fa-$target';
      if (node.hasAttr('size')) iClass = '$iClass fa-${node.attr('size')}';
      if (node.hasAttr('flip')) {
        iClass = '$iClass fa-flip-${node.attr('flip')}';
      } else if (node.hasAttr('rotate')) {
        iClass = '$iClass fa-rotate-${node.attr('rotate')}';
      }
      final attrs = node.hasAttr('title')
          ? ' title="${node.attr('title')}"'
          : '';
      img = '<i class="$iClass"$attrs></i>';
    } else if (isTruthy(icons)) {
      var attrs = node.hasAttr('width') ? ' width="${node.attr('width')}"' : '';
      if (node.hasAttr('height')) {
        attrs = '$attrs height="${node.attr('height')}"';
      }
      if (node.hasAttr('title')) {
        attrs = '$attrs title="${node.attr('title')}"';
      }
      img =
          '<img src="${node.iconUri(target)}" alt="${_encodeAttrValue(_inlineAlt(node))}"$attrs>';
    } else {
      img = '[${_inlineAlt(node)}&#93;';
    }
  } else {
    var attrs = node.hasAttr('width') ? ' width="${node.attr('width')}"' : '';
    if (node.hasAttr('height')) {
      attrs = '$attrs height="${node.attr('height')}"';
    }
    if (node.hasAttr('title')) {
      attrs = '$attrs title="${node.attr('title')}"';
    }
    if ((node.hasAttr('format', 'svg') || target.contains('.svg')) &&
        doc.safe < SafeMode.secure) {
      if (node.hasOption('inline')) {
        img =
            _readSvgContents(node, target) ??
            '<span class="alt">${_inlineAlt(node)}</span>';
      } else if (node.hasOption('interactive')) {
        final fallback = node.hasAttr('fallback')
            ? '<img src="${node.imageUri(node.attr('fallback').toString())}" alt="${_encodeAttrValue(_inlineAlt(node))}"$attrs>'
            : '<span class="alt">${_inlineAlt(node)}</span>';
        img =
            '<object type="image/svg+xml" data="${src = node.imageUri(target)}"$attrs>$fallback</object>';
      } else {
        img =
            '<img src="${src = node.imageUri(target)}" alt="${_encodeAttrValue(_inlineAlt(node))}"$attrs>';
      }
    } else {
      img =
          '<img src="${src = node.imageUri(target)}" alt="${_encodeAttrValue(_inlineAlt(node))}"$attrs>';
    }
  }
  var wrapped = img;
  if (node.hasAttr('link')) {
    final linkVal = node.attr('link').toString();
    final href = linkVal != 'self' ? linkVal : src;
    if (href != null) {
      wrapped =
          '<a class="image" href="$href"${_appendLinkConstraintAttrs(node, <String>[]).join()}>$img</a>';
    }
  }
  final idAttr = node.id != null ? ' id="${node.id}"' : '';
  var classAttrVal = type;
  if (node.hasRole()) {
    classAttrVal = node.hasAttr('float')
        ? '$type ${node.attr('float')} ${node.role}'
        : '$type ${node.role}';
  } else if (node.hasAttr('float')) {
    classAttrVal = '$type ${node.attr('float')}';
  }
  return '<span$idAttr class="$classAttrVal">$wrapped</span>';
}

/// Matches an XML preamble before the root `<svg>` element.
/// Port of `SvgPreambleRx` (non-opal branch) in `converter/html5.rb`.
final RegExp _svgPreambleRx = RegExp(r'^[\s\S]*?(?=<svg[\s>])');

/// Matches the root `<svg>` start tag.
/// Port of `SvgStartTagRx` (non-opal branch) in `converter/html5.rb`.
final RegExp _svgStartTagRx = RegExp(r'^<svg(?:\s[^>]*)?>');

/// Matches a dimension attribute on the `<svg>` start tag.
/// Port of `DimensionAttributeRx` in `converter/html5.rb`.
final RegExp _dimensionAttributeRx = RegExp(
  '\\s(?:width|height|style)=(["\'])[^\\n]*?\\1',
);

/// Reads and prepares inline SVG contents, mirroring `read_svg_contents` in
/// `converter/html5.rb`.
String? _readSvgContents(Inline node, String target) {
  final doc = node.document! as Document;
  var svg = node.readContents(
    target,
    start: doc.attr('imagesdir')?.toString(),
    normalize: true,
    label: 'SVG',
    warnIfEmpty: true,
  );
  if (svg == null || svg.isEmpty) return null;
  if (!svg.startsWith('<svg')) {
    svg = svg.replaceFirst(_svgPreambleRx, '');
  }
  String? oldStartTag;
  String? newStartTag;
  var noMatch = false;
  // NOTE width, height and style attributes are removed if either width or
  // height is specified
  for (final dim in const ['width', 'height']) {
    if (!node.hasAttr(dim)) continue;
    if (newStartTag == null) {
      if (noMatch) continue;
      final startTagMatch = _svgStartTagRx.firstMatch(svg);
      if (startTagMatch == null) {
        noMatch = true;
        continue;
      }
      newStartTag = (oldStartTag = startTagMatch.group(
        0,
      )!).replaceAll(_dimensionAttributeRx, '');
    }
    // NOTE a unitless value in HTML is assumed to be px, so we can pass
    // the value straight through
    newStartTag =
        '${newStartTag.substring(0, newStartTag.length - 1)} $dim="${node.attr(dim)}">';
  }
  if (newStartTag != null) {
    svg = '$newStartTag${svg.substring(oldStartTag!.length)}';
  }
  return svg;
}

String _docbookImage(Inline node, Document doc) {
  final isIcon = node.type == 'icon';
  final fileref = isIcon
      ? node.iconUri(node.target!)
      : node.imageUri(node.target!);
  var img =
      '<inlinemediaobject${_commonAttributes(node.id, node.role, null)}>\n'
      '<imageobject>\n'
      '<imagedata fileref="$fileref"${_imageSizeAttributes(node.attributes)}/>\n'
      '</imageobject>\n'
      '<textobject><phrase>${_inlineAlt(node)}</phrase></textobject>\n'
      '</inlinemediaobject>';
  if (!isIcon && node.hasAttr('link')) {
    final linkHref = node.attr('link').toString();
    img =
        '<link xl:href="${linkHref == 'self' ? fileref : linkHref}">$img</link>';
  }
  return img;
}

/// Mirrors `image_size_attributes` in `converter/docbook5.rb`.
String _imageSizeAttributes(Map<String, Object?> attributes) {
  if (attributes.containsKey('scaledwidth')) {
    return ' width="${attributes['scaledwidth']}"';
  } else if (attributes.containsKey('scale')) {
    // QUESTION should we set the viewport using width and depth? (the
    // scaled image would be contained within this box)
    //width_attribute = (attributes.key? 'width') ? %( width="#{...}") : ''
    //depth_attribute = (attributes.key? 'height') ? %( depth="#{...}") : ''
    return ' scale="${attributes['scale']}"';
  } else {
    final widthAttribute = attributes.containsKey('width')
        ? ' contentwidth="${attributes['width']}"'
        : '';
    final depthAttribute = attributes.containsKey('height')
        ? ' contentdepth="${attributes['height']}"'
        : '';
    return '$widthAttribute$depthAttribute';
  }
}

String _docbookIndexterm(Inline node, Document doc) {
  final see = node.attr('see');
  final String rel;
  if (isTruthy(see)) {
    rel = '\n<see>$see</see>';
  } else {
    final seeAlsoList = node.attr('see-also');
    if (isTruthy(seeAlsoList)) {
      rel = (seeAlsoList! as List)
          .map((seeAlso) => '\n<seealso>$seeAlso</seealso>')
          .join();
    } else {
      rel = '';
    }
  }
  if (node.type == 'visible') {
    return '<indexterm>\n<primary>${node.text}</primary>$rel\n</indexterm>${node.text}';
  }
  final terms = (node.attributes['terms']! as List).cast<String>();
  final numterms = terms.length;
  if (numterms > 2) {
    final promotion = doc.hasOption('indexterm-promotion')
        ? '\n<indexterm>\n<primary>${terms[1]}</primary><secondary>${terms[2]}</secondary>\n</indexterm>\n<indexterm>\n<primary>${terms[2]}</primary>\n</indexterm>'
        : '';
    return '<indexterm>\n<primary>${terms[0]}</primary><secondary>${terms[1]}</secondary><tertiary>${terms[2]}</tertiary>$rel\n</indexterm>$promotion';
  } else if (numterms > 1) {
    final promotion = doc.hasOption('indexterm-promotion')
        ? '\n<indexterm>\n<primary>${terms[1]}</primary>\n</indexterm>'
        : '';
    return '<indexterm>\n<primary>${terms[0]}</primary><secondary>${terms[1]}</secondary>$rel\n</indexterm>$promotion';
  } else {
    return '<indexterm>\n<primary>${terms[0]}</primary>$rel\n</indexterm>';
  }
}

String _htmlKbd(Inline node) {
  final keys = (node.attr('keys')! as List).cast<String>();
  if (keys.length == 1) {
    return '<kbd>${keys[0]}</kbd>';
  } else {
    return '<span class="keyseq"><kbd>${keys.join('</kbd>+<kbd>')}</kbd></span>';
  }
}

String _docbookKbd(Inline node) {
  final keys = (node.attr('keys')! as List).cast<String>();
  if (keys.length == 1) {
    return '<keycap>${keys[0]}</keycap>';
  } else {
    return '<keycombo><keycap>${keys.join('</keycap><keycap>')}</keycap></keycombo>';
  }
}

String _htmlMenu(Inline node, Document doc) {
  final caret = doc.hasAttr('icons', 'font')
      ? '&#160;<i class="fa fa-angle-right caret"></i> '
      : '&#160;<b class="caret">&#8250;</b> ';
  final submenuJoiner = '</b>$caret<b class="submenu">';
  final menu = node.attr('menu');
  final submenus = (node.attr('submenus')! as List).cast<String>();
  if (submenus.isEmpty) {
    final menuitem = node.attr('menuitem');
    if (isTruthy(menuitem)) {
      return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="menuitem">$menuitem</b></span>';
    } else {
      return '<b class="menuref">$menu</b>';
    }
  } else {
    return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="submenu">${submenus.join(submenuJoiner)}</b>$caret<b class="menuitem">${node.attr('menuitem')}</b></span>';
  }
}

String _docbookMenu(Inline node) {
  final menu = node.attr('menu');
  final submenus = (node.attr('submenus')! as List).cast<String>();
  if (submenus.isEmpty) {
    final menuitem = node.attr('menuitem');
    if (isTruthy(menuitem)) {
      return '<menuchoice><guimenu>$menu</guimenu> <guimenuitem>$menuitem</guimenuitem></menuchoice>';
    } else {
      return '<guimenu>$menu</guimenu>';
    }
  } else {
    return '<menuchoice><guimenu>$menu</guimenu> <guisubmenu>${submenus.join('</guisubmenu> <guisubmenu>')}</guisubmenu> <guimenuitem>${node.attr('menuitem')}</guimenuitem></menuchoice>';
  }
}

/// Creates a document like `document_from_string` (without parsing).
Document makeDoc({
  Map<String, Object?> attributes = const {},
  String backend = 'html5',
  Object? safe,
  String? doctype,
  bool catalogAssets = false,
}) {
  final opts = <String, Object?>{
    'attributes': Map<String, Object?>.of(attributes),
    'standalone': false,
  };
  if (backend != 'html5') opts['backend'] = backend;
  if (safe != null) opts['safe'] = safe;
  if (doctype != null) opts['doctype'] = doctype;
  if (catalogAssets) opts['catalog_assets'] = true;
  final doc = Document([], opts);
  doc.converter = FakeInlineConverter();
  return doc;
}

/// Creates a paragraph block like `block_from_string` (without parsing).
Block blockFromString(
  String src, {
  Map<String, Object?> attributes = const {},
  String backend = 'html5',
  Object? safe,
  String? doctype,
  bool catalogAssets = false,
}) {
  final doc = makeDoc(
    attributes: attributes,
    backend: backend,
    safe: safe,
    doctype: doctype,
    catalogAssets: catalogAssets,
  );
  final block = Block(doc, 'paragraph');
  block.lines = src.isEmpty ? <String>[] : src.chomp().split('\n');
  block.subs = List<String>.of(normalSubs);
  return block;
}

/// Converted content of a simple block (mirrors `Block#content`).
String contentOf(Block block) =>
    applySubs(block, block.source(), block.subs)! as String;

/// Collapses inter-tag whitespace like the Ruby `gsub(/>\s+</, '><')`.
String squeezeTags(String value) => value.replaceAll(RegExp(r'>\s+<'), '><');

/// Counts non-overlapping occurrences of [pattern] in [value].
int countOccurrences(String value, String pattern) =>
    pattern.allMatches(value).length;

/// Resolves the Ruby `test/` directory (for fixture files).
String findTestDir() {
  for (final candidate in const ['test']) {
    if (Directory('$candidate/fixtures').existsSync() &&
        File('$candidate/fixtures/circle.svg').existsSync()) {
      // The path resolver requires an absolute, normalized jail.
      return Directory(candidate).resolveSymbolicLinksSync();
    }
  }
  throw StateError('Cannot locate test/fixtures/circle.svg.');
}

void main() {
  group('Substitutions', () {
    group('Dispatcher', () {
      test('apply normal substitutions', () {
        final para = blockFromString(
          '[blue]_http://asciidoc.org[AsciiDoc]_ & [red]*Ruby*\n'
          '&#167; Making +++<u>documentation</u>+++ together +\nsince (C) {inception_year}.',
        );
        para.document!.attributes['inception_year'] = '2012';
        final result = applySubs(para, para.source());
        expect(
          result,
          '<em class="blue"><a href="http://asciidoc.org">AsciiDoc</a></em> &amp; <strong class="red">Ruby</strong>\n'
          '&#167; Making <u>documentation</u> together<br>\nsince &#169; 2012.',
        );
      });

      test('apply_subs should not modify string directly', () {
        const input = '<html> -- the root of all web';
        final para = blockFromString(input);
        final paraSource = para.source();
        final result = applySubs(para, paraSource);
        expect(result, '&lt;html&gt;&#8201;&#8212;&#8201;the root of all web');
        expect(paraSource, input);
      });

      test(
        'should not drop trailing blank lines when performing substitutions',
        () {
          // PORT: `[%hardbreaks]` is a block attribute line consumed by
          // the parser (parser wave); emulate with source + option.
          final para = blockFromString('this\nis\n-> {program}');
          para.attributes['hardbreaks-option'] = '';
          para.lines.add('');
          para.lines.add('');
          para.document!.attributes['program'] = 'Asciidoctor';
          var result = applySubs(para, para.lines);
          expect(result, [
            'this<br>',
            'is<br>',
            '&#8594; Asciidoctor<br>',
            '<br>',
            '',
          ]);
          result = applySubs(para, para.lines.join('\n'));
          expect(result, 'this<br>\nis<br>\n&#8594; Asciidoctor<br>\n<br>\n');
        },
      );

      test('should expand subs passed to expand_subs', () {
        final para = blockFromString('{program}\n*bold*\n2 > 1');
        para.document!.attributes['program'] = 'Asciidoctor';
        expect(expandSubs(para, ['specialchars']), ['specialcharacters']);
        expect(expandSubs(para, ['none']), isNull);
        expect(expandSubs(para, ['normal']), [
          'specialcharacters',
          'quotes',
          'attributes',
          'replacements',
          'macros',
          'post_replacements',
        ]);
      });

      test('apply_subs should allow the subs argument to be nil', () {
        // PORT: `[pass]` is a block attribute line consumed by the parser
        // (parser wave); the parsed paragraph source is `*raw*`.
        final block = blockFromString('*raw*');
        final result = applySubs(block, block.source(), null);
        expect(result, '*raw*');
      });
    });

    group('Quotes', () {
      test('single-line double-quoted string', () {
        var para = blockFromString(
          "``a few quoted words''",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          '&#8220;a few quoted words&#8221;',
        );

        para = blockFromString('"`a few quoted words`"');
        expect(
          subQuotes(para, para.source()),
          '&#8220;a few quoted words&#8221;',
        );

        para = blockFromString('"`a few quoted words`"', backend: 'docbook');
        expect(
          subQuotes(para, para.source()),
          '<quote role="double">a few quoted words</quote>',
        );
      });

      test('escaped single-line double-quoted string', () {
        var para = blockFromString(
          '$bs``a few quoted words'
          "''",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          "&#8216;`a few quoted words&#8217;'",
        );

        para = blockFromString(
          '$bs$bs``a few quoted words'
          "''",
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), "``a few quoted words''");

        para = blockFromString('$bs"`a few quoted words`"');
        expect(subQuotes(para, para.source()), '"`a few quoted words`"');

        para = blockFromString('$bs$bs"`a few quoted words`"');
        expect(subQuotes(para, para.source()), '$bs"`a few quoted words`"');
      });

      test('multi-line double-quoted string', () {
        var para = blockFromString(
          "``a few\nquoted words''",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          '&#8220;a few\nquoted words&#8221;',
        );

        para = blockFromString('"`a few\nquoted words`"');
        expect(
          subQuotes(para, para.source()),
          '&#8220;a few\nquoted words&#8221;',
        );
      });

      test('double-quoted string with inline single quote', () {
        var para = blockFromString(
          "``Here's Johnny!''",
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), "&#8220;Here's Johnny!&#8221;");

        para = blockFromString('"`Here\'s Johnny!`"');
        expect(subQuotes(para, para.source()), "&#8220;Here's Johnny!&#8221;");
      });

      test('double-quoted string with inline backquote', () {
        var para = blockFromString(
          "``Here`s Johnny!''",
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), '&#8220;Here`s Johnny!&#8221;');

        para = blockFromString('"`Here`s Johnny!`"');
        expect(subQuotes(para, para.source()), '&#8220;Here`s Johnny!&#8221;');
      });

      test('double-quoted string around monospaced text', () {
        var para = blockFromString(
          '"'
          '``E=mc^2^` is the solution!`'
          '"',
        );
        expect(
          applySubs(para, para.source()),
          '&#8220;`E=mc<sup>2</sup>` is the solution!&#8221;',
        );

        para = blockFromString(
          '"'
          '```E=mc^2^`` is the solution!`'
          '"',
        );
        expect(
          applySubs(para, para.source()),
          '&#8220;<code>E=mc<sup>2</sup></code> is the solution!&#8221;',
        );
      });

      test('single-line single-quoted string', () {
        var para = blockFromString(
          "`a few quoted words'",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          '&#8216;a few quoted words&#8217;',
        );

        para = blockFromString("'`a few quoted words`'");
        expect(
          subQuotes(para, para.source()),
          '&#8216;a few quoted words&#8217;',
        );

        para = blockFromString("'`a few quoted words`'", backend: 'docbook');
        expect(
          subQuotes(para, para.source()),
          '<quote role="single">a few quoted words</quote>',
        );
      });

      test('escaped single-line single-quoted string', () {
        var para = blockFromString(
          '$bs`a few quoted words'
          "'",
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), "`a few quoted words'");

        para = blockFromString("$bs'`a few quoted words`'");
        expect(subQuotes(para, para.source()), "'`a few quoted words`'");
      });

      test('multi-line single-quoted string', () {
        var para = blockFromString(
          "`a few\nquoted words'",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          '&#8216;a few\nquoted words&#8217;',
        );

        para = blockFromString("'`a few\nquoted words`'");
        expect(
          subQuotes(para, para.source()),
          '&#8216;a few\nquoted words&#8217;',
        );
      });

      test('single-quoted string with inline single quote', () {
        var para = blockFromString(
          "`That isn't what I did.'",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          "&#8216;That isn't what I did.&#8217;",
        );

        para = blockFromString("'`That isn't what I did.`'");
        expect(
          subQuotes(para, para.source()),
          "&#8216;That isn't what I did.&#8217;",
        );
      });

      test('single-quoted string with inline backquote', () {
        var para = blockFromString(
          '`Here`s Johnny!'
          "'",
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), '&#8216;Here`s Johnny!&#8217;');

        para = blockFromString("'`Here`s Johnny!`'");
        expect(subQuotes(para, para.source()), '&#8216;Here`s Johnny!&#8217;');
      });

      test('single-line constrained marked string', () {
        //para = block_from_string('#a few words#', attributes: { 'compat-mode' => '' })
        //assert_equal 'a few words', para.sub_quotes(para.source)

        final para = blockFromString('#a few words#');
        expect(subQuotes(para, para.source()), '<mark>a few words</mark>');
      });

      test('escaped single-line constrained marked string', () {
        final para = blockFromString('$bs#a few words#');
        expect(subQuotes(para, para.source()), '#a few words#');
      });

      test('multi-line constrained marked string', () {
        //para = block_from_string %(#a few\nwords#), attributes: { 'compat-mode' => '' }
        //assert_equal %(a few\nwords), para.sub_quotes(para.source)

        final para = blockFromString('#a few\nwords#');
        expect(subQuotes(para, para.source()), '<mark>a few\nwords</mark>');
      });

      test('constrained marked string should not match entity references', () {
        final para = blockFromString(
          '111 #mark a# 222 "`quote a`" 333 #mark b# 444',
        );
        expect(
          subQuotes(para, para.source()),
          '111 <mark>mark a</mark> 222 &#8220;quote a&#8221; 333 <mark>mark b</mark> 444',
        );
      });

      test('single-line unconstrained marked string', () {
        //para = block_from_string('##--anything goes ##', attributes: { 'compat-mode' => '' })
        //assert_equal '--anything goes ', para.sub_quotes(para.source)

        final para = blockFromString('##--anything goes ##');
        expect(subQuotes(para, para.source()), '<mark>--anything goes </mark>');
      });

      test('escaped single-line unconstrained marked string', () {
        final para = blockFromString('$bs$bs##--anything goes ##');
        expect(subQuotes(para, para.source()), '##--anything goes ##');
      });

      test('multi-line unconstrained marked string', () {
        //para = block_from_string %(##--anything\ngoes ##), attributes: { 'compat-mode' => '' }
        //assert_equal %(--anything\ngoes ), para.sub_quotes(para.source)

        final para = blockFromString('##--anything\ngoes ##');
        expect(
          subQuotes(para, para.source()),
          '<mark>--anything\ngoes </mark>',
        );
      });

      test('single-line constrained marked string with role', () {
        final para = blockFromString('[statement]#a few words#');
        expect(
          subQuotes(para, para.source()),
          '<span class="statement">a few words</span>',
        );
      });

      test('does not recognize attribute list with left square bracket on formatted text', () {
        final para = blockFromString(
          'key: [ *before [.redacted]#redacted# after* ]',
        );
        expect(
          subQuotes(para, para.source()),
          'key: [ <strong>before <span class="redacted">redacted</span> after</strong> ]',
        );
      });

      test('should ignore enclosing square brackets when processing formatted text with attribute list', () {
        // PORT: `doc.convert` with inline doctype renders the single
        // paragraph content; the parser wave owns block parsing.
        final para = blockFromString('nums = [1, 2, 3, [.blue]#4#]');
        expect(
          contentOf(para),
          'nums = [1, 2, 3, <span class="blue">4</span>]',
        );
      });

      test('single-line constrained strong string', () {
        final para = blockFromString('*a few strong words*');
        expect(
          subQuotes(para, para.source()),
          '<strong>a few strong words</strong>',
        );
      });

      test('escaped single-line constrained strong string', () {
        final para = blockFromString('$bs*a few strong words*');
        expect(subQuotes(para, para.source()), '*a few strong words*');
      });

      test('multi-line constrained strong string', () {
        final para = blockFromString('*a few\nstrong words*');
        expect(
          subQuotes(para, para.source()),
          '<strong>a few\nstrong words</strong>',
        );
      });

      test('constrained strong string containing an asterisk', () {
        final para = blockFromString('*bl*ck*-eye');
        expect(subQuotes(para, para.source()), '<strong>bl*ck</strong>-eye');
      });

      test('constrained strong string containing an asterisk and multibyte word chars', () {
        final para = blockFromString('*黑*眼圈*');
        expect(subQuotes(para, para.source()), '<strong>黑*眼圈</strong>');
      });

      test('single-line constrained quote variation emphasized string', () {
        final para = blockFromString('_a few emphasized words_');
        expect(
          subQuotes(para, para.source()),
          '<em>a few emphasized words</em>',
        );
      });

      test(
        'escaped single-line constrained quote variation emphasized string',
        () {
          final para = blockFromString('${bs}_a few emphasized words_');
          expect(subQuotes(para, para.source()), '_a few emphasized words_');
        },
      );

      test('escaped single quoted string', () {
        final para = blockFromString("$bs'a few emphasized words'");
        // NOTE the \' is replaced with ' by the :replacements
        // substitution, later in the substitution pipeline
        expect(subQuotes(para, para.source()), "$bs'a few emphasized words'");
      });

      test('multi-line constrained emphasized quote variation string', () {
        final para = blockFromString('_a few\nemphasized words_');
        expect(
          subQuotes(para, para.source()),
          '<em>a few\nemphasized words</em>',
        );
      });

      test('single-quoted string containing an emphasized phrase', () {
        var para = blockFromString(
          "`I told him, 'Just go for it!''",
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          '&#8216;I told him, <em>Just go for it!</em>&#8217;',
        );

        para = blockFromString("'`I told him, 'Just go for it!'`'");
        expect(
          subQuotes(para, para.source()),
          "&#8216;I told him, 'Just go for it!'&#8217;",
        );
      });

      test('escaped single-quotes inside emphasized words are restored', () {
        var para = blockFromString(
          "'Here$bs's Johnny!'",
          attributes: {'compat-mode': ''},
        );
        expect(applySubs(para, para.source()), "<em>Here's Johnny!</em>");

        para = blockFromString("'Here$bs's Johnny!'");
        expect(applySubs(para, para.source()), "'Here's Johnny!'");
      });

      test('single-line constrained emphasized underline variation string', () {
        final para = blockFromString('_a few emphasized words_');
        expect(
          subQuotes(para, para.source()),
          '<em>a few emphasized words</em>',
        );
      });

      test(
        'escaped single-line constrained emphasized underline variation string',
        () {
          final para = blockFromString('${bs}_a few emphasized words_');
          expect(subQuotes(para, para.source()), '_a few emphasized words_');
        },
      );

      test('multi-line constrained emphasized underline variation string', () {
        final para = blockFromString('_a few\nemphasized words_');
        expect(
          subQuotes(para, para.source()),
          '<em>a few\nemphasized words</em>',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('single-line constrained monospaced string', () {
        var para = blockFromString(
          '`a few <{monospaced}> words`',
          attributes: {'monospaced': 'monospaced', 'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '<code>a few &lt;{monospaced}&gt; words</code>',
        );

        para = blockFromString(
          '`a few <{monospaced}> words`',
          attributes: {'monospaced': 'monospaced'},
        );
        expect(
          applySubs(para, para.source()),
          '<code>a few &lt;monospaced&gt; words</code>',
        );
      });

      test('constrained monospaced honors : boundary, allows >', () {
        final para = blockFromString('x');
        // Ruby boundary `[^CC_WORD;:"...]`: ':' blocks the quote, '>' does
        // not. Regression test: the merged port once had '>' here.
        expect(subQuotes(para, ':`x`'), equals(':`x`'));
        expect(subQuotes(para, '>`x`'), equals('><code>x</code>'));
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('single-line constrained monospaced string with role', () {
        var para = blockFromString(
          '[input]`a few <{monospaced}> words`',
          attributes: {'monospaced': 'monospaced', 'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '<code class="input">a few &lt;{monospaced}&gt; words</code>',
        );

        para = blockFromString(
          '[input]`a few <{monospaced}> words`',
          attributes: {'monospaced': 'monospaced'},
        );
        expect(
          applySubs(para, para.source()),
          '<code class="input">a few &lt;monospaced&gt; words</code>',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped single-line constrained monospaced string', () {
        var para = blockFromString(
          '$bs`a few <monospaced> words`',
          attributes: {'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '`a few &lt;monospaced&gt; words`',
        );

        para = blockFromString('$bs`a few <monospaced> words`');
        expect(
          applySubs(para, para.source()),
          '`a few &lt;monospaced&gt; words`',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped single-line constrained monospaced string with role', () {
        var para = blockFromString(
          '[input]$bs`a few <monospaced> words`',
          attributes: {'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '[input]`a few &lt;monospaced&gt; words`',
        );

        para = blockFromString('[input]$bs`a few <monospaced> words`');
        expect(
          applySubs(para, para.source()),
          '[input]`a few &lt;monospaced&gt; words`',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped role on single-line constrained monospaced string', () {
        var para = blockFromString(
          '$bs[input]`a few <monospaced> words`',
          attributes: {'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '[input]<code>a few &lt;monospaced&gt; words</code>',
        );

        para = blockFromString('$bs[input]`a few <monospaced> words`');
        expect(
          applySubs(para, para.source()),
          '[input]<code>a few &lt;monospaced&gt; words</code>',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test(
        'escaped role on escaped single-line constrained monospaced string',
        () {
          var para = blockFromString(
            '$bs[input]$bs`a few <monospaced> words`',
            attributes: {'compat-mode': ''},
          );
          expect(
            applySubs(para, para.source()),
            '$bs[input]`a few &lt;monospaced&gt; words`',
          );

          para = blockFromString('$bs[input]$bs`a few <monospaced> words`');
          expect(
            applySubs(para, para.source()),
            '$bs[input]`a few &lt;monospaced&gt; words`',
          );
        },
      );

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('should ignore role that ends with transitional role on constrained monospace span', () {
        final para = blockFromString('[foox-]`leave it alone`');
        expect(
          applySubs(para, para.source()),
          '<code class="foox-">leave it alone</code>',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped single-line constrained monospace string with forced compat role', () {
        final para = blockFromString('[x-]$bs`leave it alone`');
        expect(applySubs(para, para.source()), '[x-]`leave it alone`');
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped forced compat role on single-line constrained monospace string', () {
        final para = blockFromString('$bs[x-]`just *mono*`');
        expect(
          applySubs(para, para.source()),
          '[x-]<code>just <strong>mono</strong></code>',
        );
      });

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('multi-line constrained monospaced string', () {
        var para = blockFromString(
          '`a few\n<{monospaced}> words`',
          attributes: {'monospaced': 'monospaced', 'compat-mode': ''},
        );
        expect(
          applySubs(para, para.source()),
          '<code>a few\n&lt;{monospaced}&gt; words</code>',
        );

        para = blockFromString(
          '`a few\n<{monospaced}> words`',
          attributes: {'monospaced': 'monospaced'},
        );
        expect(
          applySubs(para, para.source()),
          '<code>a few\n&lt;monospaced&gt; words</code>',
        );
      });

      test('single-line unconstrained strong chars', () {
        final para = blockFromString('**Git**Hub');
        expect(subQuotes(para, para.source()), '<strong>Git</strong>Hub');
      });

      test('escaped single-line unconstrained strong chars', () {
        final para = blockFromString('$bs**Git**Hub');
        expect(subQuotes(para, para.source()), '<strong>*Git</strong>*Hub');
      });

      test('multi-line unconstrained strong chars', () {
        final para = blockFromString('**G\ni\nt\n**Hub');
        expect(subQuotes(para, para.source()), '<strong>G\ni\nt\n</strong>Hub');
      });

      test('unconstrained strong chars with inline asterisk', () {
        final para = blockFromString('**bl*ck**-eye');
        expect(subQuotes(para, para.source()), '<strong>bl*ck</strong>-eye');
      });

      test('unconstrained strong chars with role', () {
        final para = blockFromString('Git[blue]**Hub**');
        expect(
          subQuotes(para, para.source()),
          'Git<strong class="blue">Hub</strong>',
        );
      });

      // TODOthis is not the same result as AsciiDoc, though I don't
      // understand why AsciiDoc gets what it gets
      test('escaped unconstrained strong chars with role', () {
        final para = blockFromString('Git$bs[blue]**Hub**');
        expect(
          subQuotes(para, para.source()),
          'Git[blue]<strong>*Hub</strong>*',
        );
      });

      test('single-line unconstrained emphasized chars', () {
        final para = blockFromString('__Git__Hub');
        expect(subQuotes(para, para.source()), '<em>Git</em>Hub');
      });

      test('escaped single-line unconstrained emphasized chars', () {
        final para = blockFromString('${bs}__Git__Hub');
        expect(subQuotes(para, para.source()), '__Git__Hub');
      });

      test(
        'escaped single-line unconstrained emphasized chars around word',
        () {
          final para = blockFromString('$bs${bs}__GitHub__');
          expect(subQuotes(para, para.source()), '__GitHub__');
        },
      );

      test('multi-line unconstrained emphasized chars', () {
        final para = blockFromString('__G\ni\nt\n__Hub');
        expect(subQuotes(para, para.source()), '<em>G\ni\nt\n</em>Hub');
      });

      test('unconstrained emphasis chars with role', () {
        final para = blockFromString('[gray]__Git__Hub');
        expect(subQuotes(para, para.source()), '<em class="gray">Git</em>Hub');
      });

      test('escaped unconstrained emphasis chars with role', () {
        final para = blockFromString('$bs[gray]__Git__Hub');
        expect(subQuotes(para, para.source()), '[gray]__Git__Hub');
      });

      test('single-line constrained monospaced chars', () {
        var para = blockFromString(
          'call +save()+ to persist the changes',
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          'call <code>save()</code> to persist the changes',
        );

        para = blockFromString('call [x-]+save()+ to persist the changes');
        expect(
          applySubs(para, para.source()),
          'call <code>save()</code> to persist the changes',
        );

        para = blockFromString('call `save()` to persist the changes');
        expect(
          subQuotes(para, para.source()),
          'call <code>save()</code> to persist the changes',
        );
      });

      test('single-line constrained monospaced chars with role', () {
        var para = blockFromString(
          'call [method]+save()+ to persist the changes',
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          'call <code class="method">save()</code> to persist the changes',
        );

        para = blockFromString(
          'call [method x-]+save()+ to persist the changes',
        );
        expect(
          applySubs(para, para.source()),
          'call <code class="method">save()</code> to persist the changes',
        );

        para = blockFromString('call [method]`save()` to persist the changes');
        expect(
          subQuotes(para, para.source()),
          'call <code class="method">save()</code> to persist the changes',
        );
      });

      test('escaped single-line constrained monospaced chars', () {
        var para = blockFromString(
          'call $bs+save()+ to persist the changes',
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          'call +save()+ to persist the changes',
        );

        para = blockFromString('call $bs`save()` to persist the changes');
        expect(
          subQuotes(para, para.source()),
          'call `save()` to persist the changes',
        );
      });

      test('escaped single-line constrained monospaced chars with role', () {
        var para = blockFromString(
          'call [method]$bs+save()+ to persist the changes',
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          'call [method]+save()+ to persist the changes',
        );

        para = blockFromString(
          'call [method]$bs`save()` to persist the changes',
        );
        expect(
          subQuotes(para, para.source()),
          'call [method]`save()` to persist the changes',
        );
      });

      test('escaped role on single-line constrained monospaced chars', () {
        var para = blockFromString(
          'call $bs[method]+save()+ to persist the changes',
          attributes: {'compat-mode': ''},
        );
        expect(
          subQuotes(para, para.source()),
          'call [method]<code>save()</code> to persist the changes',
        );

        para = blockFromString(
          'call $bs[method]`save()` to persist the changes',
        );
        expect(
          subQuotes(para, para.source()),
          'call [method]<code>save()</code> to persist the changes',
        );
      });

      test(
        'escaped role on escaped single-line constrained monospaced chars',
        () {
          var para = blockFromString(
            'call $bs[method]$bs+save()+ to persist the changes',
            attributes: {'compat-mode': ''},
          );
          expect(
            subQuotes(para, para.source()),
            'call $bs[method]+save()+ to persist the changes',
          );

          para = blockFromString(
            'call $bs[method]$bs`save()` to persist the changes',
          );
          expect(
            subQuotes(para, para.source()),
            'call $bs[method]`save()` to persist the changes',
          );
        },
      );

      // NOTE must use apply_subs because constrained monospaced is handled
      // as a passthrough
      test('escaped single-line constrained passthrough string with forced compat role', () {
        final para = blockFromString('[x-]$bs+leave it alone+');
        expect(applySubs(para, para.source()), '[x-]+leave it alone+');
      });

      test('single-line unconstrained monospaced chars', () {
        var para = blockFromString(
          'Git++Hub++',
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), 'Git<code>Hub</code>');

        para = blockFromString('Git[x-]++Hub++');
        expect(applySubs(para, para.source()), 'Git<code>Hub</code>');

        para = blockFromString('Git``Hub``');
        expect(subQuotes(para, para.source()), 'Git<code>Hub</code>');
      });

      test('escaped single-line unconstrained monospaced chars', () {
        var para = blockFromString(
          'Git$bs++Hub++',
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), 'Git+<code>Hub</code>+');

        para = blockFromString(
          'Git$bs$bs++Hub++',
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), 'Git++Hub++');

        para = blockFromString('Git$bs``Hub``');
        expect(subQuotes(para, para.source()), 'Git``Hub``');
      });

      test('multi-line unconstrained monospaced chars', () {
        var para = blockFromString(
          'Git++\nH\nu\nb++',
          attributes: {'compat-mode': ''},
        );
        expect(subQuotes(para, para.source()), 'Git<code>\nH\nu\nb</code>');

        para = blockFromString('Git[x-]++\nH\nu\nb++');
        expect(applySubs(para, para.source()), 'Git<code>\nH\nu\nb</code>');

        para = blockFromString('Git``\nH\nu\nb``');
        expect(subQuotes(para, para.source()), 'Git<code>\nH\nu\nb</code>');
      });

      test('single-line superscript chars', () {
        final para = blockFromString(
          "x^2^ = x * x, e = mc^2^, there's a 1^st^ time for everything",
        );
        expect(
          subQuotes(para, para.source()),
          "x<sup>2</sup> = x * x, e = mc<sup>2</sup>, there's a 1<sup>st</sup> time for everything",
        );
      });

      test('escaped single-line superscript chars', () {
        final para = blockFromString('x$bs^2^ = x * x');
        expect(subQuotes(para, para.source()), 'x^2^ = x * x');
      });

      test('does not match superscript across whitespace', () {
        final para = blockFromString('x^(n\n-\n1)^');
        expect(subQuotes(para, para.source()), para.source());
      });

      test('allow spaces in superscript if spaces are inserted using an attribute reference', () {
        final para = blockFromString(
          'Night ^A{sp}poem{sp}by{sp}Jane{sp}Kondo^.',
        );
        expect(
          applySubs(para, para.source()),
          'Night <sup>A poem by Jane Kondo</sup>.',
        );
      });

      test(
        'allow spaces in superscript if text is wrapped in a passthrough',
        () {
          final para = blockFromString('Night ^+A poem by Jane Kondo+^.');
          expect(
            applySubs(para, para.source()),
            'Night <sup>A poem by Jane Kondo</sup>.',
          );
        },
      );

      test('does not match adjacent superscript chars', () {
        final para = blockFromString('a ^^ b');
        expect(subQuotes(para, para.source()), 'a ^^ b');
      });

      test(
        'does not confuse superscript and links with blank window shorthand',
        () {
          final para = blockFromString(
            'http://localhost[Text^] on the 21^st^ and 22^nd^',
          );
          expect(
            contentOf(para),
            '<a href="http://localhost" target="_blank" rel="noopener">Text</a> on the 21<sup>st</sup> and 22<sup>nd</sup>',
          );
        },
      );

      test('single-line subscript chars', () {
        final para = blockFromString('H~2~O');
        expect(subQuotes(para, para.source()), 'H<sub>2</sub>O');
      });

      test('escaped single-line subscript chars', () {
        final para = blockFromString('H$bs~2~O');
        expect(subQuotes(para, para.source()), 'H~2~O');
      });

      test('does not match subscript across whitespace', () {
        final para = blockFromString('project~ view\non\nGitHub~');
        expect(subQuotes(para, para.source()), para.source());
      });

      test('does not match adjacent subscript chars', () {
        final para = blockFromString('a ~~ b');
        expect(subQuotes(para, para.source()), 'a ~~ b');
      });

      test('does not match subscript across distinct URLs', () {
        final para = blockFromString(
          'http://www.abc.com/~def[DEF] and http://www.abc.com/~ghi[GHI]',
        );
        expect(subQuotes(para, para.source()), para.source());
      });

      test('quoted text with role shorthand', () {
        final para = blockFromString('[.white.red-background]#alert#');
        expect(
          subQuotes(para, para.source()),
          '<span class="white red-background">alert</span>',
        );
      });

      test('quoted text with id shorthand', () {
        final para = blockFromString('[#bond]#007#');
        expect(subQuotes(para, para.source()), '<span id="bond">007</span>');
      });

      test('quoted text with id and role shorthand', () {
        final para = blockFromString('[#bond.white.red-background]#007#');
        expect(
          subQuotes(para, para.source()),
          '<span id="bond" class="white red-background">007</span>',
        );
      });

      test('quoted text with id and role shorthand with roles before id', () {
        final para = blockFromString('[.white.red-background#bond]#007#');
        expect(
          subQuotes(para, para.source()),
          '<span id="bond" class="white red-background">007</span>',
        );
      });

      test('quoted text with id and role shorthand with roles around id', () {
        final para = blockFromString('[.white#bond.red-background]#007#');
        expect(
          subQuotes(para, para.source()),
          '<span id="bond" class="white red-background">007</span>',
        );
      });

      test('quoted text with id and role shorthand using docbook backend', () {
        final para = blockFromString(
          '[#bond.white.red-background]#007#',
          backend: 'docbook',
        );
        expect(
          subQuotes(para, para.source()),
          '<anchor xml:id="bond"/><phrase role="white red-background">007</phrase>',
        );
      });

      test(
        'should not assign role attribute if shorthand style has no roles',
        () {
          final para = blockFromString('[#idname]*blah*');
          expect(contentOf(para), '<strong id="idname">blah</strong>');
        },
      );

      test(
        'should remove trailing spaces from role defined using shorthand',
        () {
          final para = blockFromString('[.rolename ]*blah*');
          expect(contentOf(para), '<strong class="rolename">blah</strong>');
        },
      );

      test('should allow role to be defined using attribute reference', () {
        // PORT: `convert_string_to_embedded` with inline doctype renders
        // the single paragraph content.
        final para = blockFromString(
          '[{rolename}]#phrase#',
          attributes: {'rolename': 'red'},
        );
        expect(contentOf(para), '<span class="red">phrase</span>');
      });

      test('should ignore attributes after comma', () {
        final para = blockFromString('[red, foobar]#alert#');
        expect(
          subQuotes(para, para.source()),
          '<span class="red">alert</span>',
        );
      });

      test('should remove leading and trailing spaces around role after ignoring attributes after comma', () {
        final para = blockFromString('[ red , foobar]#alert#');
        expect(
          subQuotes(para, para.source()),
          '<span class="red">alert</span>',
        );
      });

      test('should not assign role if value before comma is empty', () {
        final para = blockFromString('[,]#anonymous#');
        expect(subQuotes(para, para.source()), 'anonymous');
      });

      test('inline passthrough with id and role set using shorthand', () {
        for (final attrlist in const ['#idname.rolename', '.rolename#idname']) {
          final para = blockFromString('[$attrlist]+pass+');
          expect(
            contentOf(para),
            '<span id="idname" class="rolename">pass</span>',
          );
        }
      });
    });

    group('Macros', () {
      test('a single-line link macro should be interpreted as a link', () {
        final para = blockFromString('link:/home.html[]');
        expect(
          subMacros(para, para.source()),
          '<a href="/home.html" class="bare">/home.html</a>',
        );
      });

      test(
        'a single-line link macro with text should be interpreted as a link',
        () {
          final para = blockFromString('link:/home.html[Home]');
          expect(
            subMacros(para, para.source()),
            '<a href="/home.html">Home</a>',
          );
        },
      );

      test('a mailto macro should be interpreted as a mailto link', () {
        final para = blockFromString('mailto:doc.writer@asciidoc.org[]');
        expect(
          subMacros(para, para.source()),
          '<a href="mailto:doc.writer@asciidoc.org">doc.writer@asciidoc.org</a>',
        );
      });

      test(
        'a mailto macro with text should be interpreted as a mailto link',
        () {
          final para = blockFromString(
            'mailto:doc.writer@asciidoc.org[Doc Writer]',
          );
          expect(
            subMacros(para, para.source()),
            '<a href="mailto:doc.writer@asciidoc.org">Doc Writer</a>',
          );
        },
      );

      test('a mailto macro with text and subject should be interpreted as a mailto link', () {
        final para = blockFromString(
          'mailto:doc.writer@asciidoc.org[Doc Writer, Pull request]',
        );
        expect(
          subMacros(para, para.source()),
          '<a href="mailto:doc.writer@asciidoc.org?subject=Pull%20request">Doc Writer</a>',
        );
      });

      test('a mailto macro with text, subject and body should be interpreted as a mailto link', () {
        final para = blockFromString(
          'mailto:doc.writer@asciidoc.org[Doc Writer, Pull request, Please accept my pull request]',
        );
        expect(
          subMacros(para, para.source()),
          '<a href="mailto:doc.writer@asciidoc.org?subject=Pull%20request&amp;body=Please%20accept%20my%20pull%20request">Doc Writer</a>',
        );
      });

      test(
        'a mailto macro with subject and body only should use e-mail as text',
        () {
          final para = blockFromString(
            'mailto:doc.writer@asciidoc.org[,Pull request,Please accept my pull request]',
          );
          expect(
            subMacros(para, para.source()),
            '<a href="mailto:doc.writer@asciidoc.org?subject=Pull%20request&amp;body=Please%20accept%20my%20pull%20request">doc.writer@asciidoc.org</a>',
          );
        },
      );

      test('a mailto macro supports id and role attributes', () {
        final para = blockFromString(
          'mailto:doc.writer@asciidoc.org[,id=contact,role=icon]',
        );
        expect(
          subMacros(para, para.source()),
          '<a href="mailto:doc.writer@asciidoc.org" id="contact" class="icon">doc.writer@asciidoc.org</a>',
        );
      });

      test('should recognize inline email addresses', () {
        for (final input in const [
          'doc.writer@asciidoc.org',
          'author+website@4fs.no',
          'john@domain.uk.co',
          'name@somewhere.else.com',
          'joe_bloggs@mail_server.com',
          'joe-bloggs@mail-server.com',
          'joe.bloggs@mail.server.com',
          'FOO@BAR.COM',
          'docs@writing.ninja',
        ]) {
          final para = blockFromString(input);
          expect(
            subMacros(para, para.source()),
            '<a href="mailto:$input">$input</a>',
          );
        }
      });

      test('should recognize inline email address containing an ampersand', () {
        final para = blockFromString('bert&ernie@sesamestreet.com');
        expect(
          applySubs(para, para.source()),
          '<a href="mailto:bert&amp;ernie@sesamestreet.com">bert&amp;ernie@sesamestreet.com</a>',
        );
      });

      test(
        'should recognize inline email address surrounded by angle brackets',
        () {
          final para = blockFromString('<doc.writer@asciidoc.org>');
          expect(
            applySubs(para, para.source()),
            '&lt;<a href="mailto:doc.writer@asciidoc.org">doc.writer@asciidoc.org</a>&gt;',
          );
        },
      );

      test('should ignore escaped inline email address', () {
        final para = blockFromString('${bs}doc.writer@asciidoc.org');
        expect(subMacros(para, para.source()), 'doc.writer@asciidoc.org');
      });

      test('a single-line raw url should be interpreted as a link', () {
        final para = blockFromString('http://google.com');
        expect(
          subMacros(para, para.source()),
          '<a href="http://google.com" class="bare">http://google.com</a>',
        );
      });

      test(
        'a single-line raw url with text should be interpreted as a link',
        () {
          final para = blockFromString('http://google.com[Google]');
          expect(
            subMacros(para, para.source()),
            '<a href="http://google.com">Google</a>',
          );
        },
      );

      test(
        'a multi-line raw url with text should be interpreted as a link',
        () {
          final para = blockFromString('http://google.com[Google\nHomepage]');
          expect(
            subMacros(para, para.source()),
            '<a href="http://google.com">Google\nHomepage</a>',
          );
        },
      );

      test('a single-line raw url with attribute as text should be interpreted as a link with resolved attribute', () {
        final para = blockFromString('http://google.com[{google_homepage}]');
        para.document!.attributes['google_homepage'] = 'Google Homepage';
        expect(
          subMacros(para, subAttributes(para, para.source())),
          '<a href="http://google.com">Google Homepage</a>',
        );
      });

      test('should not resolve an escaped attribute in link text', () {
        for (final entry in const {
          'http://google.com': r'http://google.com[\{google_homepage}]',
          'http://google.com?q=,':
              r'link:http://google.com?q=,[\{google_homepage}]',
        }.entries) {
          final para = blockFromString(entry.value);
          para.document!.attributes['google_homepage'] = 'Google Homepage';
          expect(
            subMacros(para, subAttributes(para, para.source())),
            '<a href="${entry.key}">{google_homepage}</a>',
          );
        }
      });

      test(
        'a single-line escaped raw url should not be interpreted as a link',
        () {
          final para = blockFromString('${bs}http://google.com');
          expect(subMacros(para, para.source()), 'http://google.com');
        },
      );

      test(
        'a comma separated list of links should not include commas in links',
        () {
          final para = blockFromString(
            'http://foo.com, http://bar.com, http://example.org',
          );
          expect(
            subMacros(para, para.source()),
            '<a href="http://foo.com" class="bare">http://foo.com</a>, '
            '<a href="http://bar.com" class="bare">http://bar.com</a>, '
            '<a href="http://example.org" class="bare">http://example.org</a>',
          );
        },
      );

      test('a single-line image macro should be interpreted as an image', () {
        final para = blockFromString('image:tiger.png[]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.png" alt="tiger"></span>',
        );
      });

      test('should use the imagesdir attribute defined on image macro when resolving image path', () {
        // PORT: the `:imagesdir:` attribute entry and document structure
        // belong to the parser wave; emulate with document attributes.
        final para = blockFromString(
          'Great job! image:rainbow.png[imagesdir=stickers]',
          attributes: {'imagesdir': 'images'},
        );
        expect(contentOf(para), contains('src="stickers/rainbow.png"'));
      });

      test('should replace underscore and hyphen with space in generated alt text for an inline image', () {
        final para = blockFromString('image:tiger-with-family_1.png[]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger-with-family_1.png" alt="tiger with family 1"></span>',
        );
      });

      test('a single-line image macro with text should be interpreted as an image with alt text', () {
        final para = blockFromString('image:tiger.png[Tiger]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.png" alt="Tiger"></span>',
        );
      });

      test('should encode special characters in alt text of inline image', () {
        const input = 'A tiger\'s "roar" is < a bear\'s "growl"';
        const expected =
            'A tiger&#8217;s &quot;roar&quot; is &lt; a bear&#8217;s &quot;growl&quot;';
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        final para = blockFromString('image:tiger-roar.png[$input]');
        expect(
          squeezeTags(contentOf(para)),
          '<span class="image"><img src="tiger-roar.png" alt="$expected"></span>',
        );
      });

      test('an image macro with SVG image and text should be interpreted as an image with alt text', () {
        final para = blockFromString('image:tiger.svg[Tiger]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.svg" alt="Tiger"></span>',
        );
      });

      test('an image macro with an interactive SVG image and alt text should be converted to an object element', () {
        final para = blockFromString(
          'image:tiger.svg[Tiger,opts=interactive]',
          safe: 10,
          attributes: {'imagesdir': 'images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><object type="image/svg+xml" data="images/tiger.svg"><span class="alt">Tiger</span></object></span>',
        );
      });

      test('an image macro with an interactive SVG image, fallback and alt text should be converted to an object element', () {
        final para = blockFromString(
          'image:tiger.svg[Tiger,fallback=tiger.png,opts=interactive]',
          safe: 10,
          attributes: {'imagesdir': 'images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><object type="image/svg+xml" data="images/tiger.svg"><img src="images/tiger.png" alt="Tiger"></object></span>',
        );
      });

      test('an image macro with an inline SVG image should be converted to an svg element', () {
        final para = blockFromString(
          'image:circle.svg[Tiger,100,opts=inline]',
          safe: 10,
          attributes: {'imagesdir': 'fixtures', 'docdir': findTestDir()},
        );
        final result = squeezeTags(subMacros(para, para.source()));
        expect(result, matches(RegExp(r'<svg\s[^>]*width="100"[^>]*>')));
        expect(result, isNot(matches(RegExp(r'<svg\s[^>]*width="500"[^>]*>'))));
        expect(
          result,
          isNot(matches(RegExp(r'<svg\s[^>]*height="500"[^>]*>'))),
        );
        expect(result, isNot(matches(RegExp(r'<svg\s[^>]*style="[^>]*>'))));
      });

      test('should ignore link attribute if value is self and image target is inline SVG', () {
        final para = blockFromString(
          'image:circle.svg[Tiger,100,opts=inline,link=self]',
          safe: 10,
          attributes: {'imagesdir': 'fixtures', 'docdir': findTestDir()},
        );
        final result = squeezeTags(subMacros(para, para.source()));
        expect(result, matches(RegExp(r'<svg\s[^>]*width="100"[^>]*>')));
        expect(result, isNot(contains('<a href=')));
      });

      test('an image macro with an inline SVG image should be converted to an svg element even when data-uri is set', () {
        final para = blockFromString(
          'image:circle.svg[Tiger,100,opts=inline]',
          safe: 10,
          attributes: {
            'data-uri': '',
            'imagesdir': 'fixtures',
            'docdir': findTestDir(),
          },
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          matches(RegExp(r'<svg\s[^>]*width="100">')),
        );
      });

      test('an image macro with an SVG image should not use an object element when safe mode is secure', () {
        final para = blockFromString(
          'image:tiger.svg[Tiger,opts=interactive]',
          attributes: {'imagesdir': 'images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="images/tiger.svg" alt="Tiger"></span>',
        );
      });

      test('a single-line image macro with text containing escaped square bracket should be interpreted as an image with alt text', () {
        final para = blockFromString('image:tiger.png[[Another$bs] Tiger]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.png" alt="[Another] Tiger"></span>',
        );
      });

      test('a single-line image macro with text and dimensions should be interpreted as an image with alt text and dimensions', () {
        final para = blockFromString('image:tiger.png[Tiger, 200, 100]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.png" alt="Tiger" width="200" height="100"></span>',
        );
      });

      test('a single-line image macro with text and dimensions should be interpreted as an image with alt text and dimensions in docbook', () {
        final para = blockFromString(
          'image:tiger.png[Tiger, 200, 100]',
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<inlinemediaobject><imageobject><imagedata fileref="tiger.png" contentwidth="200" contentdepth="100"/></imageobject><textobject><phrase>Tiger</phrase></textobject></inlinemediaobject>',
        );
      });

      test('a single-line image macro with scaledwidth attribute should be supported in docbook', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,scaledwidth=25%]',
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<inlinemediaobject><imageobject><imagedata fileref="tiger.png" width="25%"/></imageobject><textobject><phrase>Tiger</phrase></textobject></inlinemediaobject>',
        );
      });

      test('a single-line image macro with scaled attribute should be supported in docbook', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,scale=200]',
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<inlinemediaobject><imageobject><imagedata fileref="tiger.png" scale="200"/></imageobject><textobject><phrase>Tiger</phrase></textobject></inlinemediaobject>',
        );
      });

      test('should pass through role on image macro to DocBook output', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,200,role=animal]',
          backend: 'docbook',
        );
        expect(
          subMacros(para, para.source()),
          contains('<inlinemediaobject role="animal">'),
        );
      });

      test('a single-line image macro with text and link should be interpreted as a linked image with alt text', () {
        final para = blockFromString(
          'image:tiger.png[Tiger, link="http://en.wikipedia.org/wiki/Tiger"]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><a class="image" href="http://en.wikipedia.org/wiki/Tiger"><img src="tiger.png" alt="Tiger"></a></span>',
        );
      });

      test('an inline image macro with link should be interpreted as a linked image in docbook', () {
        final para = blockFromString(
          'image:apache license 2_0.png[Apache License 2.0,link=http://www.apache.org/licenses/LICENSE-2.0]',
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<link xl:href="http://www.apache.org/licenses/LICENSE-2.0"><inlinemediaobject><imageobject><imagedata fileref="apache%20license%202_0.png"/></imageobject><textobject><phrase>Apache License 2.0</phrase></textobject></inlinemediaobject></link>',
        );
      });

      test('a single-line image macro with text and link to self should be interpreted as a self-referencing image with alt text', () {
        final para = blockFromString(
          'image:tiger.png[Tiger, link=self]',
          attributes: {'imagesdir': 'img'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><a class="image" href="img/tiger.png"><img src="img/tiger.png" alt="Tiger"></a></span>',
        );
      });

      test('an inline image macro with text and link to self should be interpreted as a self-referencing image in docbook', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,link=self]',
          attributes: {'imagesdir': 'img'},
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<link xl:href="img/tiger.png"><inlinemediaobject><imageobject><imagedata fileref="img/tiger.png"/></imageobject><textobject><phrase>Tiger</phrase></textobject></inlinemediaobject></link>',
        );
      });

      test('should link to data URI if value of link attribute is self and inline image is embedded', () {
        final para = blockFromString(
          'image:circle.svg[Tiger,100,link=self]',
          safe: 10,
          attributes: {
            'data-uri': '',
            'imagesdir': 'fixtures',
            'docdir': findTestDir(),
          },
        );
        final output = squeezeTags(subMacros(para, para.source()));
        expect(
          countOccurrences(
            output,
            '<a class="image" href="data:image/svg+xml;base64,',
          ),
          1,
        );
        expect(
          countOccurrences(output, '<img src="data:image/svg+xml;base64,'),
          1,
        );
      });

      test('rel=noopener should be added to an image with a link that targets the _blank window', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,link=http://en.wikipedia.org/wiki/Tiger,window=_blank]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><a class="image" href="http://en.wikipedia.org/wiki/Tiger" target="_blank" rel="noopener"><img src="tiger.png" alt="Tiger"></a></span>',
        );
      });

      test('rel=noopener should be added to an image with a link that targets a named window when the noopener option is set', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,link=http://en.wikipedia.org/wiki/Tiger,window=name,opts=noopener]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><a class="image" href="http://en.wikipedia.org/wiki/Tiger" target="name" rel="noopener"><img src="tiger.png" alt="Tiger"></a></span>',
        );
      });

      test('rel=nofollow should be added to an image with a link when the nofollow option is set', () {
        final para = blockFromString(
          'image:tiger.png[Tiger,link=http://en.wikipedia.org/wiki/Tiger,opts=nofollow]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><a class="image" href="http://en.wikipedia.org/wiki/Tiger" rel="nofollow"><img src="tiger.png" alt="Tiger"></a></span>',
        );
      });

      test('a multi-line image macro with text and dimensions should be interpreted as an image with alt text and dimensions', () {
        final para = blockFromString(
          'image:tiger.png[Another\nAwesome\nTiger, 200,\n100]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image"><img src="tiger.png" alt="Another Awesome Tiger" width="200" height="100"></span>',
        );
      });

      test('an inline image macro with a url target should be interpreted as an image', () {
        final para = blockFromString(
          'Beware of the image:http://example.com/images/tiger.png[tiger].',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          'Beware of the <span class="image"><img src="http://example.com/images/tiger.png" alt="tiger"></span>.',
        );
      });

      test('an inline image macro with a float attribute should be interpreted as a floating image', () {
        final para = blockFromString(
          'image:http://example.com/images/tiger.png[tiger, float="right"] Beware of the tigers!',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="image right"><img src="http://example.com/images/tiger.png" alt="tiger"></span> Beware of the tigers!',
        );
      });

      test('should propagate id attribute on inline image', () {
        final para = blockFromString(
          'image:ruby.png[Ruby logo,id=ruby-logo] is the Ruby logo',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span id="ruby-logo" class="image"><img src="ruby.png" alt="Ruby logo"></span> is the Ruby logo',
        );
      });

      test('should propagate id attribute on inline image and use alt text as reftext when converting to DocBook', () {
        final para = blockFromString(
          'image:ruby.png[Ruby logo,id=ruby-logo] is the Ruby logo',
          backend: 'docbook',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<inlinemediaobject xml:id="ruby-logo"><imageobject><imagedata fileref="ruby.png"/></imageobject><textobject><phrase>Ruby logo</phrase></textobject></inlinemediaobject> is the Ruby logo',
        );
      });

      test('should prepend value of imagesdir attribute to inline image target if target is relative path', () {
        final para = blockFromString(
          'Beware of the image:tiger.png[tiger].',
          attributes: {'imagesdir': './images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          'Beware of the <span class="image"><img src="./images/tiger.png" alt="tiger"></span>.',
        );
      });

      test('should not prepend value of imagesdir attribute to inline image target if target is absolute path', () {
        final para = blockFromString(
          'Beware of the image:/tiger.png[tiger].',
          attributes: {'imagesdir': './images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          'Beware of the <span class="image"><img src="/tiger.png" alt="tiger"></span>.',
        );
      });

      test('should not prepend value of imagesdir attribute to inline image target if target is url', () {
        final para = blockFromString(
          'Beware of the image:http://example.com/images/tiger.png[tiger].',
          attributes: {'imagesdir': './images'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          'Beware of the <span class="image"><img src="http://example.com/images/tiger.png" alt="tiger"></span>.',
        );
      });

      test('should match an inline image macro if target contains a space character', () {
        final para = blockFromString(
          'Beware of the image:big cats.png[] around here.',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          'Beware of the <span class="image"><img src="big%20cats.png" alt="big cats"></span> around here.',
        );
      });

      test('should not match an inline image macro if target contains a newline character', () {
        final para = blockFromString(
          'Fear not. There are no image:big\ncats.png[] around here.',
        );
        final result = subMacros(para, para.source());
        expect(result, isNot(contains('<img ')));
        expect(result, contains('image:big\ncats.png[]'));
      });

      test('should not match an inline image macro if target begins or ends with space character', () {
        for (final input in const [
          'image: big cats.png[]',
          'image:big cats.png []',
        ]) {
          final para = blockFromString(
            'Fear not. There are no $input around here.',
          );
          final result = subMacros(para, para.source());
          expect(result, isNot(contains('<img ')));
          expect(result, contains(input));
        }
      });

      test('should not detect a block image macro found inline', () {
        final para = blockFromString(
          'Not an inline image macro image::tiger.png[].',
        );
        final result = subMacros(para, para.source());
        expect(result, isNot(contains('<img ')));
        expect(result, contains('image::tiger.png[]'));
      });

      // NOTE this test verifies attributes get substituted eagerly in
      // target of image in title
      test('should substitute attributes in target of inline image in section title', () {
        // PORT: section titles are assigned during parsing (parser wave);
        // emulate with a paragraph carrying the same substituted text.
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString(
            'image:{iconsdir}/dot.gif[dot] Title',
            attributes: {
              'data-uri': '',
              'iconsdir': 'fixtures',
              'docdir': findTestDir(),
            },
            safe: 'server',
            catalogAssets: true,
          );
          contentOf(para);
          final doc = para.document! as Document;
          final images = doc.catalog['images']! as List;
          expect(images.length, 1);
          expect(images[0].toString(), 'fixtures/dot.gif');
          expect(images[0].imagesdir, isNull);
          expect(logger.isEmpty, isTrue);
        });
      });

      test(
        'an icon macro should be interpreted as an icon if icons are enabled',
        () {
          final para = blockFromString(
            'icon:github[]',
            attributes: {'icons': ''},
          );
          expect(
            squeezeTags(subMacros(para, para.source())),
            '<span class="icon"><img src="./images/icons/github.png" alt="github"></span>',
          );
        },
      );

      test(
        'an icon macro should be interpreted as alt text if icons are disabled',
        () {
          final para = blockFromString('icon:github[]');
          expect(
            squeezeTags(subMacros(para, para.source())),
            '<span class="icon">[github&#93;</span>',
          );
        },
      );

      test('should not mangle icon with link if icons are disabled', () {
        final para = blockFromString('icon:github[link=https://github.com]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon"><a class="image" href="https://github.com">[github&#93;</a></span>',
        );
      });

      test('should not mangle icon inside link if icons are disabled', () {
        final para = blockFromString(
          'https://github.com[icon:github[] GitHub]',
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<a href="https://github.com"><span class="icon">[github&#93;</span> GitHub</a>',
        );
      });

      test('an icon macro should output alt text if icons are disabled and alt is given', () {
        final para = blockFromString('icon:github[alt="GitHub"]');
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon">[GitHub&#93;</span>',
        );
      });

      test('an icon macro should be interpreted as a font-based icon when icons=font', () {
        final para = blockFromString(
          'icon:github[]',
          attributes: {'icons': 'font'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon"><i class="fa fa-github"></i></span>',
        );
      });

      test('an icon macro with a size should be interpreted as a font-based icon with a size when icons=font', () {
        final para = blockFromString(
          'icon:github[4x]',
          attributes: {'icons': 'font'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon"><i class="fa fa-github fa-4x"></i></span>',
        );
      });

      test('an icon macro with flip should be interpreted as a flipped font-based icon when icons=font', () {
        final para = blockFromString(
          'icon:shield[fw,flip=horizontal]',
          attributes: {'icons': 'font'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon"><i class="fa fa-shield fa-fw fa-flip-horizontal"></i></span>',
        );
      });

      test('an icon macro with rotate should be interpreted as a rotated font-based icon when icons=font', () {
        final para = blockFromString(
          'icon:shield[fw,rotate=90]',
          attributes: {'icons': 'font'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon"><i class="fa fa-shield fa-fw fa-rotate-90"></i></span>',
        );
      });

      test('an icon macro with a role and title should be interpreted as a font-based icon with a class and title when icons=font', () {
        final para = blockFromString(
          'icon:heart[role="red", title="Heart me"]',
          attributes: {'icons': 'font'},
        );
        expect(
          squeezeTags(subMacros(para, para.source())),
          '<span class="icon red"><i class="fa fa-heart" title="Heart me"></i></span>',
        );
      });

      test('should use the imagesdir attribute on the node when resolving the icon path', () {
        final doc = makeDoc(
          attributes: {'iconsdir': 'assets/icons', 'icons': 'image'},
        );
        final icon = Inline(
          doc,
          'image',
          type: 'icon',
          attributes: {'iconsdir': 'chapter-1/icons'},
        );
        expect(icon.iconUri('wave'), 'chapter-1/icons/wave.png');
      });

      test('a single-line footnote macro should be registered and output as a footnote', () {
        final para = blockFromString(
          'Sentence text footnote:[An example footnote.].',
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
        final doc = para.document! as Document;
        expect(doc.footnotes.length, 1);
        final footnote = doc.footnotes.first;
        expect(footnote.index, 1);
        expect(footnote.id, isNull);
        expect(footnote.text, 'An example footnote.');
      });

      test('a multi-line footnote macro should be registered and output as a footnote without newline', () {
        final para = blockFromString(
          'Sentence text footnote:[An example footnote\nwith wrapped text.].',
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
        final doc = para.document! as Document;
        expect(doc.footnotes.length, 1);
        final footnote = doc.footnotes.first;
        expect(footnote.index, 1);
        expect(footnote.id, isNull);
        expect(footnote.text, 'An example footnote with wrapped text.');
      });

      test('an escaped closing square bracket in a footnote should be unescaped when converted', () {
        final para = blockFromString('footnote:[a $bs] b].');
        expect(
          subMacros(para, para.source()),
          '<sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
        final doc = para.document! as Document;
        expect(doc.footnotes.length, 1);
        expect(doc.footnotes.first.text, 'a ] b');
      });

      test('a footnote macro can be directly adjacent to preceding word', () {
        final para = blockFromString(
          'Sentence textfootnote:[An example footnote.].',
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text<sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
      });

      test('a footnote macro may contain an escaped backslash', () {
        final para = blockFromString(
          'footnote:[$bs]]\nfootnote:[a $bs] b]\nfootnote:[a $bs]$bs] b]',
        );
        subMacros(para, para.source());
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 3);
        expect(footnotes[0].text, ']');
        expect(footnotes[1].text, 'a ] b');
        expect(footnotes[2].text, 'a ]] b');
      });

      test('a footnote macro may contain a link macro', () {
        final para = blockFromString(
          'Share your code. footnote:[https://github.com[GitHub]]',
        );
        expect(
          subMacros(para, para.source()),
          'Share your code. <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(footnotes[0].text, '<a href="https://github.com">GitHub</a>');
      });

      test('a footnote macro may contain a plain URL', () {
        final para = blockFromString(
          'the JLine footnote:[https://github.com/jline/jline2]\nlibrary.',
        );
        expect(
          subMacros(para, para.source()),
          'the JLine <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>\nlibrary.',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(
          footnotes[0].text,
          '<a href="https://github.com/jline/jline2" class="bare">https://github.com/jline/jline2</a>',
        );
      });

      test(
        'a footnote macro followed by a semi-colon may contain a plain URL',
        () {
          final para = blockFromString(
            'the JLine footnote:[https://github.com/jline/jline2];\nlibrary.',
          );
          expect(
            subMacros(para, para.source()),
            'the JLine <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>;\nlibrary.',
          );
          final footnotes = (para.document! as Document).footnotes;
          expect(footnotes.length, 1);
        },
      );

      test('a footnote macro may contain text formatting', () {
        final para = blockFromString(
          'You can download patches from the product page.footnote:[Only available with an _active_ subscription.]',
        );
        // PORT: `para.convert` renders paragraph content (the quotes sub
        // runs before the macros sub, formatting the footnote content).
        contentOf(para);
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(
          footnotes[0].text,
          'Only available with an <em>active</em> subscription.',
        );
      });

      test('an externalized footnote macro may contain text formatting', () {
        // PORT: the `:fn-disclaimer:` attribute entry is parsed by the
        // reader (parser wave); emulate its header substitutions, which
        // apply the `q` subs to the pass macro content when stored.
        final para = blockFromString(
          'You can download patches from the production page.{fn-disclaimer}',
        );
        para.document!.attributes['fn-disclaimer'] = applySubs(
          para,
          'footnote:[Only available with an _active_ subscription.]',
          ['quotes'],
        );
        contentOf(para);
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(
          footnotes[0].text,
          'Only available with an <em>active</em> subscription.',
        );
      });

      test('a footnote macro may contain a shorthand xref', () {
        // specialcharacters escaping is simulated
        final para = blockFromString(
          'text footnote:[&lt;&lt;_install,install&gt;&gt;]',
        );
        final doc = para.document! as Document;
        doc.register('refs', [
          '_install',
          Inline(
            doc,
            'anchor',
            text: 'Install',
            type: 'ref',
            target: '_install',
          ),
          'Install',
        ]);
        expect(
          subMacros(para, para.source()),
          'text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
        expect(doc.footnotes.length, 1);
        expect(doc.footnotes[0].text, '<a href="#_install">install</a>');
      });

      test('a footnote macro may contain an xref macro', () {
        final para = blockFromString('text footnote:[xref:_install[install]]');
        final doc = para.document! as Document;
        doc.register('refs', [
          '_install',
          Inline(
            doc,
            'anchor',
            text: 'Install',
            type: 'ref',
            target: '_install',
          ),
          'Install',
        ]);
        expect(
          subMacros(para, para.source()),
          'text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
        expect(doc.footnotes.length, 1);
        expect(doc.footnotes[0].text, '<a href="#_install">install</a>');
      });

      test('a footnote macro may contain an anchor macro', () {
        final para = blockFromString('text footnote:[a [[b]] [[c$bs]$bs] d]');
        expect(
          subMacros(para, para.source()),
          'text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(footnotes[0].text, 'a <a id="b"></a> [[c]] d');
      });

      test('subsequent footnote macros with escaped URLs should be restored in DocBook', () {
        // PORT: `convert_string_to_embedded` with inline doctype renders
        // the single paragraph content.
        const input =
            'foofootnote:[+http://example.com+]barfootnote:[+http://acme.com+]baz';
        final para = blockFromString(input, backend: 'docbook');
        expect(
          contentOf(para),
          'foo<footnote><simpara>http://example.com</simpara></footnote>bar<footnote><simpara>http://acme.com</simpara></footnote>baz',
        );
      });

      test('should increment index of subsequent footnote macros', () {
        final para = blockFromString(
          'Sentence text footnote:[An example footnote.]. Sentence text footnote:[Another footnote.].',
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text <sup class="footnote">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>. Sentence text <sup class="footnote">[<a id="_footnoteref_2" class="footnote" href="#_footnotedef_2" title="View footnote.">2</a>]</sup>.',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 2);
        expect(footnotes[0].index, 1);
        expect(footnotes[0].id, isNull);
        expect(footnotes[0].text, 'An example footnote.');
        expect(footnotes[1].index, 2);
        expect(footnotes[1].id, isNull);
        expect(footnotes[1].text, 'Another footnote.');
      });

      test('a footnoteref macro with id and single-line text should be registered and output as a footnote', () {
        final para = blockFromString(
          'Sentence text footnoteref:[ex1, An example footnote.].',
          attributes: {'compat-mode': ''},
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text <sup class="footnote" id="_footnote_ex1">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(footnotes.first.index, 1);
        expect(footnotes.first.id, 'ex1');
        expect(footnotes.first.text, 'An example footnote.');
      });

      test('a footnoteref macro with id and multi-line text should be registered and output as a footnote without newlines', () {
        final para = blockFromString(
          'Sentence text footnoteref:[ex1, An example footnote\nwith wrapped text.].',
          attributes: {'compat-mode': ''},
        );
        expect(
          subMacros(para, para.source()),
          'Sentence text <sup class="footnote" id="_footnote_ex1">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
        );
        final footnotes = (para.document! as Document).footnotes;
        expect(footnotes.length, 1);
        expect(footnotes.first.index, 1);
        expect(footnotes.first.id, 'ex1');
        expect(footnotes.first.text, 'An example footnote with wrapped text.');
      });

      test(
        'a footnoteref macro with id should refer to footnoteref with same id',
        () {
          final para = blockFromString(
            'Sentence text footnoteref:[ex1, An example footnote.]. Sentence text footnoteref:[ex1].',
            attributes: {'compat-mode': ''},
          );
          expect(
            subMacros(para, para.source()),
            'Sentence text <sup class="footnote" id="_footnote_ex1">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>. Sentence text <sup class="footnoteref">[<a class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>.',
          );
          final footnotes = (para.document! as Document).footnotes;
          expect(footnotes.length, 1);
          expect(footnotes.first.index, 1);
          expect(footnotes.first.id, 'ex1');
          expect(footnotes.first.text, 'An example footnote.');
        },
      );

      test('an unresolved footnote reference should produce a warning message and output fallback text in red', () {
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString('Sentence text.footnote:ex1[]');
          final output = subMacros(para, para.source());
          expect(
            output,
            'Sentence text.<sup class="footnoteref red" title="Unresolved footnote reference.">[ex1]</sup>',
          );
          expect(logger.warns, ['invalid footnote reference: ex1']);
        });
      });

      test('using a footnoteref macro should generate a warning when compat mode is not enabled', () {
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString(
            'Sentence text.footnoteref:[fn1,Commentary on this sentence.]',
          );
          subMacros(para, para.source());
          expect(logger.warns, [
            'found deprecated footnoteref macro: footnoteref:[fn1,Commentary on this sentence.]; use footnote macro with target instead',
          ]);
        });
      });

      test('inline footnote macro can be used to define and reference a footnote reference', () {
        // PORT: needs multi-paragraph parsing and footnote-list rendering.
        markTestSkipped(
          'parser wave (document structure) and converter wave (footnote list)',
        );
      });

      test('should parse multiple footnote references in a single line', () {
        // PORT: the `#footnotes` list assertion belongs to the converter
        // wave; the substitution-level behavior is asserted exactly.
        final para = blockFromString(
          r'notable text.footnote:id[about this [text\]], footnote:id[], footnote:id[]',
        );
        final output = subMacros(para, para.source());
        expect(countOccurrences(output, ' id="_footnote_id"'), 1);
        expect(countOccurrences(output, '<sup class="footnoteref">'), 2);
        expect(
          countOccurrences(
            output,
            '<a class="footnote" href="#_footnotedef_1"',
          ),
          2,
        );
        expect(
          countOccurrences(output, '<a id="_footnoteref_1" class="footnote"'),
          1,
        );
        expect((para.document! as Document).footnotes.length, 1);
      });

      test('should not register footnote with id and text if id already registered', () {
        // PORT: the `:fn-notable-text:` attribute entry is parsed by the
        // reader (parser wave); emulate its stored value (header subs
        // leave it unchanged) on a shared document.
        final doc = makeDoc();
        doc.attributes['fn-notable-text'] = 'footnote:id[about this text]';
        Block paraFor(String line) {
          final para = Block(doc, 'paragraph');
          para.lines = [line];
          para.subs = List<String>.of(normalSubs);
          return para;
        }

        final first = paraFor('notable text.{fn-notable-text}');
        expect(contentOf(first), contains('<sup class="footnote"'));
        final second = paraFor('more notable text.{fn-notable-text}');
        expect(contentOf(second), contains('<sup class="footnoteref">'));
        expect(doc.footnotes.length, 1);
      });

      test(
        'should not resolve an inline footnote macro missing both id and text',
        () {
          // PORT: `convert_string_to_embedded` over two paragraphs; each
          // paragraph is substituted independently here.
          for (final line in const [
            'The footnote:[] macro can be used for defining and referencing footnotes.',
            'The footnoteref:[] macro is now deprecated.',
          ]) {
            expect(contentOf(blockFromString(line)), contains(line));
          }
        },
      );

      test('inline footnote macro can define a numeric id without conflicting with auto-generated ID', () {
        // PORT: the `#footnotes` list assertion belongs to the converter
        // wave; the paragraph output is asserted exactly.
        final para = blockFromString(
          'You can download the software from the product page.footnote:1[Option only available if you have an active subscription.]',
        );
        expect(
          contentOf(para),
          'You can download the software from the product page.<sup class="footnote" id="_footnote_1">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
      });

      test('inline footnote macro can define an id that uses any word characters in Unicode', () {
        // PORT: the `#footnotes` list assertion belongs to the converter
        // wave; the paragraph outputs are asserted exactly.
        final doc = makeDoc();
        Block paraFor(String line) {
          final para = Block(doc, 'paragraph');
          para.lines = [line];
          para.subs = List<String>.of(normalSubs);
          return para;
        }

        expect(
          contentOf(
            paraFor(
              "L'origine du mot for\u00eat{blank}footnote:for\u00eat[un massif forestier] est complexe.",
            ),
          ),
          'L&#8217;origine du mot for\u00eat<sup class="footnote" id="_footnote_for\u00eat">[<a id="_footnoteref_1" class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup> est complexe.',
        );
        expect(
          contentOf(
            paraFor(
              "Qu'est-ce qu'une for\u00eat ?{blank}footnote:for\u00eat[]",
            ),
          ),
          'Qu&#8217;est-ce qu&#8217;une for\u00eat ?<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_1" title="View footnote.">1</a>]</sup>',
        );
      });

      test(
        'should be able to reference a bibliography entry in a footnote',
        () {
          // PORT: needs bibliography list parsing and footnote-list rendering.
          markTestSkipped(
            'parser wave (lists, sections) and converter wave (footnote list)',
          );
        },
      );

      test(
        'footnotes in headings are expected to be numbered out of sequence',
        () {
          // PORT: needs section parsing and footnote-list rendering.
          markTestSkipped(
            'parser wave (sections) and converter wave (footnote list)',
          );
        },
      );

      test('a single-line index term macro with a primary term should be registered as an index reference', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        for (final macro in const ['indexterm:[Tigers]', '(((Tigers)))']) {
          final para = blockFromString('$sentence$macro');
          final output = subMacros(para, para.source());
          expect(output, sentence);
        }
      });

      test('a single-line index term macro with primary and secondary terms should be registered as an index reference', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        for (final macro in const [
          'indexterm:[Big cats, Tigers]',
          '(((Big cats, Tigers)))',
        ]) {
          final para = blockFromString('$sentence$macro');
          final output = subMacros(para, para.source());
          expect(output, sentence);
        }
      });

      test('a single-line index term macro with primary, secondary and tertiary terms should be registered as an index reference', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        for (final macro in const [
          'indexterm:[Big cats,Tigers , Panthera tigris]',
          '(((Big cats,Tigers , Panthera tigris)))',
        ]) {
          final para = blockFromString('$sentence$macro');
          final output = subMacros(para, para.source());
          expect(output, sentence);
        }
      });

      test('a multi-line index term macro should be compacted and registered as an index reference', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        for (final macro in const [
          'indexterm:[Panthera\ntigris]',
          '(((Panthera\ntigris)))',
        ]) {
          final para = blockFromString('$sentence$macro');
          final output = subMacros(para, para.source());
          expect(output, sentence);
        }
      });

      test('should escape concealed index term if second bracket is preceded by a backslash', () {
        // PORT: assert the paragraph content instead of the converted
        // document.
        final para = blockFromString(
          'National Institute of Science and Technology ($bs((NIST)))',
        );
        expect(
          contentOf(para),
          'National Institute of Science and Technology (((NIST)))',
        );
      });

      test('should only escape enclosing brackets if concealed index term is preceded by a backslash', () {
        // PORT: assert the paragraph content instead of the converted
        // document.
        final para = blockFromString(
          'National Institute of Science and Technology $bs(((NIST)))',
        );
        expect(
          contentOf(para),
          'National Institute of Science and Technology (NIST)',
        );
      });

      test('should not split index terms on commas inside of quoted terms', () {
        final inputs = [
          'Tigers are big, scary cats.\nindexterm:[Tigers, "[Big\\],\nscary cats"]\n',
          'Tigers are big, scary cats.\n(((Tigers, "[Big],\nscary cats")))\n',
        ];
        for (final input in inputs) {
          final para = blockFromString(input);
          final output = subMacros(para, para.source());
          expect(output, '${input.split('\n').first}\n');
        }
      });

      test('normal substitutions are performed on an index term macro', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        for (final macro in const ['indexterm:[*Tigers*]', '(((*Tigers*)))']) {
          final para = blockFromString('$sentence$macro');
          final output = applySubs(para, para.source());
          expect(output, sentence);
        }
      });

      test('registers multiple index term macros', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.';
        const macros = '(((Tigers)))\n(((Animals,Cats)))';
        final para = blockFromString('$sentence\n$macros');
        final output = subMacros(para, para.source());
        expect(output.rstrip(), sentence);
      });

      test('an index term macro with round bracket syntax may contain round brackets in term', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        const macro = '(((Tiger (Panthera tigris))))';
        final para = blockFromString('$sentence$macro');
        expect(subMacros(para, para.source()), sentence);
      });

      test('visible shorthand index term macro should not consume trailing round bracket', () {
        const input = '(text with ((index term)))';
        const expected =
            '(text with <indexterm>\n<primary>index term</primary>\n</indexterm>index term)';
        final para = blockFromString(input, backend: 'docbook');
        expect(subMacros(para, para.source()), expected);
      });

      test('visible shorthand index term macro should not consume leading round bracket', () {
        const input = '(((index term)) for text)';
        const expected =
            '(<indexterm>\n<primary>index term</primary>\n</indexterm>index term for text)';
        final para = blockFromString(input, backend: 'docbook');
        expect(subMacros(para, para.source()), expected);
      });

      test('an index term macro with square bracket syntax may contain square brackets in term', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.\n';
        final para = blockFromString(
          '${sentence}indexterm:[Tiger [Panthera tigris$bs]]',
        );
        expect(subMacros(para, para.source()), sentence);
      });

      test('a single-line index term 2 macro should be registered as an index reference and retain term inline', () {
        const sentence =
            'The tiger (Panthera tigris) is the largest cat species.';
        for (final macro in const [
          'The indexterm2:[tiger] (Panthera tigris) is the largest cat species.',
          'The ((tiger)) (Panthera tigris) is the largest cat species.',
        ]) {
          final para = blockFromString(macro);
          expect(subMacros(para, para.source()), sentence);
        }
      });

      test('a multi-line index term 2 macro should be compacted and registered as an index reference and retain term inline', () {
        const sentence = 'The panthera tigris is the largest cat species.';
        for (final macro in const [
          'The indexterm2:[ panthera\ntigris ] is the largest cat species.',
          'The (( panthera\ntigris )) is the largest cat species.',
        ]) {
          final para = blockFromString(macro);
          expect(subMacros(para, para.source()), sentence);
        }
      });

      test('registers multiple index term 2 macros', () {
        final para = blockFromString(
          'The ((tiger)) (Panthera tigris) is the largest ((cat)) species.',
        );
        expect(
          subMacros(para, para.source()),
          'The tiger (Panthera tigris) is the largest cat species.',
        );
      });

      test('should escape visible index term if preceded by a backslash', () {
        final para = blockFromString(
          'The $bs((tiger)) (Panthera tigris) is the largest $bs((cat)) species.',
        );
        expect(
          subMacros(para, para.source()),
          'The ((tiger)) (Panthera tigris) is the largest ((cat)) species.',
        );
      });

      test('normal substitutions are performed on an index term 2 macro', () {
        final para = blockFromString(
          'The ((*tiger*)) (Panthera tigris) is the largest cat species.',
        );
        expect(
          applySubs(para, para.source()),
          'The <strong>tiger</strong> (Panthera tigris) is the largest cat species.',
        );
      });

      test('index term 2 macro with round bracket syntax should not interfere with index term macro with round bracket syntax', () {
        final para = blockFromString(
          'The ((panthera tigris)) is the largest cat species.\n(((Big cats,Tigers)))',
        );
        expect(
          subMacros(para, para.source()),
          'The panthera tigris is the largest cat species.\n',
        );
      });

      test(
        'should parse visible shorthand index term with see and seealso',
        () {
          // PORT: assert the paragraph content instead of the converted
          // document.
          final para = blockFromString(
            '((Flash >> HTML 5)) has been supplanted by ((HTML 5 &> CSS 3 &> SVG)).',
            backend: 'docbook',
          );
          final output = contentOf(para);
          expect(
            output,
            contains(
              '<indexterm>\n<primary>Flash</primary>\n<see>HTML 5</see>\n</indexterm>',
            ),
          );
          expect(
            output,
            contains(
              '<indexterm>\n<primary>HTML 5</primary>\n<seealso>CSS 3</seealso>\n<seealso>SVG</seealso>\n</indexterm>',
            ),
          );
        },
      );

      test(
        'should parse concealed shorthand index term with see and seealso',
        () {
          // PORT: assert the paragraph content instead of the converted
          // document.
          final para = blockFromString(
            'Flash(((Flash >> HTML 5))) has been supplanted by HTML 5(((HTML 5 &> CSS 3 &> SVG))).',
            backend: 'docbook',
          );
          final output = contentOf(para);
          expect(
            output,
            contains(
              '<indexterm>\n<primary>Flash</primary>\n<see>HTML 5</see>\n</indexterm>',
            ),
          );
          expect(
            output,
            contains(
              '<indexterm>\n<primary>HTML 5</primary>\n<seealso>CSS 3</seealso>\n<seealso>SVG</seealso>\n</indexterm>',
            ),
          );
        },
      );

      test('should parse visible index term macro with see and seealso', () {
        // PORT: assert the paragraph content instead of the converted
        // document.
        final para = blockFromString(
          'indexterm2:[Flash,see=HTML 5] has been supplanted by indexterm2:[HTML 5,see-also="CSS 3, SVG"].',
          backend: 'docbook',
        );
        final output = contentOf(para);
        expect(
          output,
          contains(
            '<indexterm>\n<primary>Flash</primary>\n<see>HTML 5</see>\n</indexterm>',
          ),
        );
        expect(
          output,
          contains(
            '<indexterm>\n<primary>HTML 5</primary>\n<seealso>CSS 3</seealso>\n<seealso>SVG</seealso>\n</indexterm>',
          ),
        );
      });

      test('should parse concealed index term macro with see and seealso', () {
        // PORT: assert the paragraph content instead of the converted
        // document.
        final para = blockFromString(
          'Flashindexterm:[Flash,see=HTML 5] has been supplanted by HTML 5indexterm:[HTML 5,see-also="CSS 3, SVG"].',
          backend: 'docbook',
        );
        final output = contentOf(para);
        expect(
          output,
          contains(
            '<indexterm>\n<primary>Flash</primary>\n<see>HTML 5</see>\n</indexterm>',
          ),
        );
        expect(
          output,
          contains(
            '<indexterm>\n<primary>HTML 5</primary>\n<seealso>CSS 3</seealso>\n<seealso>SVG</seealso>\n</indexterm>',
          ),
        );
      });

      test('should honor secondary and tertiary index terms when primary index term is quoted and contains equals sign', () {
        const sentence = 'Assigning variables.';
        const expected =
            '$sentence<indexterm><primary>name=value</primary><secondary>variable</secondary><tertiary>assignment</tertiary></indexterm>';
        for (final macro in const [
          'indexterm:["name=value",variable,assignment]',
          '(((name=value,variable,assignment)))',
        ]) {
          final para = blockFromString('$sentence$macro', backend: 'docbook');
          expect(subMacros(para, para.source()).replaceAll('\n', ''), expected);
        }
      });
    });

    group('Button macro', () {
      test('btn macro', () {
        final para = blockFromString(
          'btn:[Save]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<b class="button">Save</b>');
      });

      test('btn macro that spans multiple lines', () {
        final para = blockFromString(
          'btn:[Rebase and\nmerge]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<b class="button">Rebase and merge</b>',
        );
      });

      test('btn macro for docbook backend', () {
        final para = blockFromString(
          'btn:[Save]',
          backend: 'docbook',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<guibutton>Save</guibutton>');
      });
    });

    group('Keyboard macro', () {
      test('kbd macro with single key', () {
        final para = blockFromString(
          'kbd:[F3]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<kbd>F3</kbd>');
      });

      test('kbd macro with single backslash key', () {
        final para = blockFromString(
          'kbd:[$bs ]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<kbd>$bs</kbd>');
      });

      test('kbd macro with single key, docbook backend', () {
        final para = blockFromString(
          'kbd:[F3]',
          backend: 'docbook',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<keycap>F3</keycap>');
      });

      test('kbd macro with key combination', () {
        final para = blockFromString(
          'kbd:[Ctrl+Shift+T]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd></span>',
        );
      });

      test('kbd macro with key combination that spans multiple lines', () {
        final para = blockFromString(
          'kbd:[Ctrl +\nT]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>T</kbd></span>',
        );
      });

      test('kbd macro with key combination, docbook backend', () {
        final para = blockFromString(
          'kbd:[Ctrl+Shift+T]',
          backend: 'docbook',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<keycombo><keycap>Ctrl</keycap><keycap>Shift</keycap><keycap>T</keycap></keycombo>',
        );
      });

      test(
        'kbd macro with key combination delimited by pluses with spaces',
        () {
          final para = blockFromString(
            'kbd:[Ctrl + Shift + T]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd></span>',
          );
        },
      );

      test('kbd macro with key combination delimited by commas', () {
        final para = blockFromString(
          'kbd:[Ctrl,Shift,T]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd></span>',
        );
      });

      test(
        'kbd macro with key combination delimited by commas with spaces',
        () {
          final para = blockFromString(
            'kbd:[Ctrl, Shift, T]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>T</kbd></span>',
          );
        },
      );

      test('kbd macro with key combination delimited by plus containing a comma key', () {
        final para = blockFromString(
          'kbd:[Ctrl+,]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>,</kbd></span>',
        );
      });

      test('kbd macro with key combination delimited by commas containing a plus key', () {
        final para = blockFromString(
          'kbd:[Ctrl, +, Shift]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>+</kbd>+<kbd>Shift</kbd></span>',
        );
      });

      test(
        'kbd macro with key combination where last key matches plus delimiter',
        () {
          final para = blockFromString(
            'kbd:[Ctrl + +]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>+</kbd></span>',
          );
        },
      );

      test(
        'kbd macro with key combination where last key matches comma delimiter',
        () {
          final para = blockFromString(
            'kbd:[Ctrl, ,]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>,</kbd></span>',
          );
        },
      );

      test('kbd macro with key combination containing escaped bracket', () {
        final para = blockFromString(
          'kbd:[Ctrl + $bs]]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>]</kbd></span>',
        );
      });

      test('kbd macro with key combination ending in backslash', () {
        final para = blockFromString(
          'kbd:[Ctrl + $bs ]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="keyseq"><kbd>Ctrl</kbd>+<kbd>$bs</kbd></span>',
        );
      });

      test('kbd macro looks for delimiter beyond first character', () {
        final para = blockFromString(
          'kbd:[,te]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<kbd>,te</kbd>');
      });

      test('kbd macro restores trailing delimiter as key value', () {
        final para = blockFromString(
          'kbd:[te,]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<kbd>te,</kbd>');
      });
    });

    group('Menu macro', () {
      test('should process menu using macro sytnax', () {
        final para = blockFromString(
          'menu:File[]',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<b class="menuref">File</b>');
      });

      test('should process menu for docbook backend', () {
        final para = blockFromString(
          'menu:File[]',
          backend: 'docbook',
          attributes: {'experimental': ''},
        );
        expect(subMacros(para, para.source()), '<guimenu>File</guimenu>');
      });

      test('should process multiple menu macros in same line', () {
        final para = blockFromString(
          'menu:File[] and menu:Edit[]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<b class="menuref">File</b> and <b class="menuref">Edit</b>',
        );
      });

      test('should process menu with menu item using macro syntax', () {
        final para = blockFromString(
          'menu:File[Save As&#8230;]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">File</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Save As&#8230;</b></span>',
        );
      });

      test('should process menu macro that spans multiple lines', () {
        final para = blockFromString(
          'menu:Preferences[Compile\non\nSave]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">Preferences</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Compile\non\nSave</b></span>',
        );
      });

      test('should unescape escaped closing bracket in menu macro', () {
        final para = blockFromString(
          'menu:Preferences[Compile [on$bs] Save]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">Preferences</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Compile [on] Save</b></span>',
        );
      });

      test('should process menu with menu item using macro syntax when fonts icons are enabled', () {
        final para = blockFromString(
          'menu:Tools[More Tools &gt; Extensions]',
          attributes: {'experimental': '', 'icons': 'font'},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">Tools</b>&#160;<i class="fa fa-angle-right caret"></i> <b class="submenu">More Tools</b>&#160;<i class="fa fa-angle-right caret"></i> <b class="menuitem">Extensions</b></span>',
        );
      });

      test('should process menu with menu item for docbook backend', () {
        final para = blockFromString(
          'menu:File[Save As&#8230;]',
          backend: 'docbook',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<menuchoice><guimenu>File</guimenu> <guimenuitem>Save As&#8230;</guimenuitem></menuchoice>',
        );
      });

      test(
        'should process menu with menu item in submenu using macro syntax',
        () {
          final para = blockFromString(
            'menu:Tools[Project &gt; Build]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="menuseq"><b class="menu">Tools</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">Project</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Build</b></span>',
          );
        },
      );

      test(
        'should process menu with menu item in submenu for docbook backend',
        () {
          final para = blockFromString(
            'menu:Tools[Project &gt; Build]',
            backend: 'docbook',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<menuchoice><guimenu>Tools</guimenu> <guisubmenu>Project</guisubmenu> <guimenuitem>Build</guimenuitem></menuchoice>',
          );
        },
      );

      test('should process menu with menu item in submenu using macro syntax and comma delimiter', () {
        final para = blockFromString(
          'menu:Tools[Project, Build]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">Tools</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">Project</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Build</b></span>',
        );
      });

      test('should process menu with menu item using inline syntax', () {
        final para = blockFromString(
          '"File &gt; Save As&#8230;"',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">File</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Save As&#8230;</b></span>',
        );
      });

      test(
        'should process menu with menu item in submenu using inline syntax',
        () {
          final para = blockFromString(
            '"Tools &gt; Project &gt; Build"',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="menuseq"><b class="menu">Tools</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">Project</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Build</b></span>',
          );
        },
      );

      test(
        'inline menu syntax should not match closing quote of XML attribute',
        () {
          final para = blockFromString(
            '<span class="xmltag">&lt;node&gt;</span><span class="classname">r</span>',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="xmltag">&lt;node&gt;</span><span class="classname">r</span>',
          );
        },
      );

      test(
        'should process menu macro with items containing multibyte characters',
        () {
          final para = blockFromString(
            'menu:视图[放大, 重置]',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="menuseq"><b class="menu">视图</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">放大</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">重置</b></span>',
          );
        },
      );

      test(
        'should process inline menu with items containing multibyte characters',
        () {
          final para = blockFromString(
            '"视图 &gt; 放大 &gt; 重置"',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="menuseq"><b class="menu">视图</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">放大</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">重置</b></span>',
          );
        },
      );

      test('should process a menu macro with a target that begins with a character reference', () {
        final para = blockFromString(
          'menu:&#8942;[More Tools, Extensions]',
          attributes: {'experimental': ''},
        );
        expect(
          subMacros(para, para.source()),
          '<span class="menuseq"><b class="menu">&#8942;</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">More Tools</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Extensions</b></span>',
        );
      });

      test(
        'should not process a menu macro with a target that ends with a space',
        () {
          final para = blockFromString(
            'menu:foo [bar] menu:File[Save]',
            attributes: {'experimental': ''},
          );
          final result = subMacros(para, para.source());
          expect(countOccurrences(result, '<span class="menuseq">'), 1);
          expect(countOccurrences(result, '<b class="menu">File</b>'), 1);
        },
      );

      test(
        'should process an inline menu that begins with a character reference',
        () {
          final para = blockFromString(
            '"&#8942; &gt; More Tools &gt; Extensions"',
            attributes: {'experimental': ''},
          );
          expect(
            subMacros(para, para.source()),
            '<span class="menuseq"><b class="menu">&#8942;</b>&#160;<b class="caret">&#8250;</b> <b class="submenu">More Tools</b>&#160;<b class="caret">&#8250;</b> <b class="menuitem">Extensions</b></span>',
          );
        },
      );
    });

    group('Passthroughs', () {
      test('collect inline triple plus passthroughs', () {
        final para = blockFromString('+++<code>inline code</code>+++');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>inline code</code>');
        expect(passthroughs[0]['subs']! as List, isEmpty);
      });

      test('collect multi-line inline triple plus passthroughs', () {
        final para = blockFromString('+++<code>inline\ncode</code>+++');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>inline\ncode</code>');
        expect(passthroughs[0]['subs']! as List, isEmpty);
      });

      test('collect inline double dollar passthroughs', () {
        final para = blockFromString(r'$$<code>{code}</code>$$');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>{code}</code>');
        expect(passthroughs[0]['subs'], ['specialcharacters']);
      });

      test('collect inline double plus passthroughs', () {
        final para = blockFromString('++<code>{code}</code>++');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>{code}</code>');
        expect(passthroughs[0]['subs'], ['specialcharacters']);
      });

      test('should not crash if role on passthrough is enclosed in quotes', () {
        for (final input in [
          "['role']$bs++This++++++++++++",
          "['role']$bs+++++++++This++++++++++++",
        ]) {
          final para = blockFromString(input);
          expect(contentOf(para), contains('<span class="\'role\'">'));
        }
      });

      test('should allow inline double plus passthrough to be escaped using backslash', () {
        final para = blockFromString(
          'you need to replace `int a = n$bs++;` with `int a = ++n;`!',
        );
        expect(
          applySubs(para, para.source()),
          'you need to replace <code>int a = n++;</code> with <code>int a = ++n;</code>!',
        );
      });

      test('should allow inline double plus passthrough with attributes to be escaped using backslash', () {
        final para = blockFromString('=[attrs]$bs$bs++text++');
        expect(applySubs(para, para.source()), '=[attrs]++text++');
      });

      test('collect multi-line inline double dollar passthroughs', () {
        final para = blockFromString('\$\$<code>\n{code}\n</code>\$\$');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>\n{code}\n</code>');
        expect(passthroughs[0]['subs'], ['specialcharacters']);
      });

      test('collect multi-line inline double plus passthroughs', () {
        final para = blockFromString('++<code>\n{code}\n</code>++');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], '<code>\n{code}\n</code>');
        expect(passthroughs[0]['subs'], ['specialcharacters']);
      });

      test('collect passthroughs from inline pass macro', () {
        final para = blockFromString(
          "pass:specialcharacters,quotes[<code>['code'$bs]</code>]",
        );
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], "<code>['code']</code>");
        expect(passthroughs[0]['subs'], ['specialcharacters', 'quotes']);
      });

      test('collect multi-line passthroughs from inline pass macro', () {
        final para = blockFromString(
          "pass:specialcharacters,quotes[<code>['more\ncode'$bs]</code>]",
        );
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(
          result,
          '$passStart'
          '0'
          '$passEnd',
        );
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], "<code>['more\ncode']</code>");
        expect(passthroughs[0]['subs'], ['specialcharacters', 'quotes']);
      });

      test('should find and replace placeholder duplicated by substitution', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        const input =
            r'+first passthrough+ followed by link:$$http://example.com/__u_no_format_me__$$[] with passthrough';
        final para = blockFromString(input);
        expect(
          contentOf(para),
          'first passthrough followed by <a href="http://example.com/__u_no_format_me__" class="bare">http://example.com/__u_no_format_me__</a> with passthrough',
        );
      });

      test('resolves sub shorthands on inline pass macro', () {
        final para = blockFromString('pass:q,a[*<{backend}>*]');
        final result = extractPassthroughs(para, para.source());
        final passthroughs = para.passthroughs;
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['subs'], ['quotes', 'attributes']);
        expect(restorePassthroughs(para, result), '<strong><html5></strong>');
      });

      test('inline pass macro supports incremental subs', () {
        final para = blockFromString('pass:n,-a[<{backend}>]');
        final result = extractPassthroughs(para, para.source());
        expect(para.passthroughs.length, 1);
        expect(restorePassthroughs(para, result), '&lt;{backend}&gt;');
      });

      test(
        'should not recognize pass macro with invalid substitution list',
        () {
          for (final subs in const [',', '42', 'a,']) {
            final para = blockFromString('pass:$subs[foobar]');
            expect(
              extractPassthroughs(para, para.source()),
              'pass:$subs[foobar]',
            );
          }
        },
      );

      test('should warn if substitutions on pass macro are invalid', () {
        const subs = 'bogus';
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString(
            'pass:$subs[++]',
            attributes: {'stem': 'asciimath'},
          );
          expect(contentOf(para), '++');
          expect(logger.warns, [
            'invalid substitution type for passthrough macro: $subs',
          ]);
        });
      });

      test('should allow content of inline pass macro to be empty', () {
        final para = blockFromString('pass:[]');
        final result = extractPassthroughs(para, para.source());
        expect(para.passthroughs.length, 1);
        expect(restorePassthroughs(para, result), '');
      });

      test('restore inline passthroughs without subs', () {
        final para = blockFromString('some ${passStart}0$passEnd to study');
        extractPassthroughs(para, '');
        para.passthroughs.add({
          'text': '<code>inline code</code>',
          'subs': <String>[],
        });
        expect(
          restorePassthroughs(para, para.source()),
          'some <code>inline code</code> to study',
        );
      });

      test('restore inline passthroughs with subs', () {
        final para = blockFromString(
          'some ${passStart}0$passEnd to study in the ${passStart}1$passEnd programming language',
        );
        extractPassthroughs(para, '');
        para.passthroughs.add({
          'text': '<code>{code}</code>',
          'subs': ['specialcharacters'],
        });
        para.passthroughs.add({
          'text': '{language}',
          'subs': ['specialcharacters'],
        });
        expect(
          restorePassthroughs(para, para.source()),
          'some &lt;code&gt;{code}&lt;/code&gt; to study in the {language} programming language',
        );
      });

      test('should restore nested passthroughs', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        final para = blockFromString(
          r"+Sometimes you feel pass:q[`mono`].+ Sometimes you +$$don't$$+.",
        );
        expect(
          contentOf(para),
          "Sometimes you feel <code>mono</code>. Sometimes you don't.",
        );
      });

      test('should not fail to restore remaining passthroughs after processing inline passthrough with macro substitution', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        final para = blockFromString('pass:m[.] pass:[.]');
        expect(contentOf(para), '. .');
      });

      test('should honor role on double plus passthrough', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        final para = blockFromString(
          'Print the version using [var]++{asciidoctor-version}++.',
        );
        expect(
          contentOf(para),
          'Print the version using <span class="var">{asciidoctor-version}</span>.',
        );
      });

      test('complex inline passthrough macro', () {
        const textToEscape =
            "[(] <'basic form'> <'logical operator'> <'basic form'> [)]";
        var para = blockFromString('\$\$$textToEscape\$\$');
        extractPassthroughs(para, para.source());
        var passthroughs = para.passthroughs;
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], textToEscape);

        const escaped =
            r"[(\] <'basic form'> <'logical operator'> <'basic form'> [)\]";
        para = blockFromString('pass:specialcharacters[$escaped]');
        extractPassthroughs(para, para.source());
        passthroughs = para.passthroughs;
        expect(passthroughs.length, 1);
        expect(passthroughs[0]['text'], textToEscape);
      });

      test('inline pass macro with a composite sub', () {
        final para = blockFromString('pass:verbatim[<{backend}>]');
        expect(contentOf(para), '&lt;{backend}&gt;');
      });

      test(
        'should support constrained passthrough in middle of monospace span',
        () {
          final para = blockFromString('a `foo +bar+ baz` kind of thing');
          expect(contentOf(para), 'a <code>foo bar baz</code> kind of thing');
        },
      );

      test('should support constrained passthrough in monospace span preceded by escaped boxed attrlist with transitional role', () {
        final para = blockFromString('$bs[x-]`foo +bar+ baz`');
        expect(contentOf(para), '[x-]<code>foo bar baz</code>');
      });

      test('should treat monospace phrase with escaped boxed attrlist with transitional role as monospace', () {
        final para = blockFromString('$bs[x-]`*foo* +bar+ baz`');
        expect(
          contentOf(para),
          '[x-]<code><strong>foo</strong> bar baz</code>',
        );
      });

      test('should ignore escaped attrlist with transitional role on monospace phrase if not proceeded by [', () {
        final para = blockFromString('${bs}x-]`*foo* +bar+ baz`');
        expect(
          contentOf(para),
          '$bs'
          'x-]<code><strong>foo</strong> bar baz</code>',
        );
      });

      test('should not process passthrough inside transitional literal monospace span', () {
        final para = blockFromString('a [x-]`foo +bar+ baz` kind of thing');
        expect(contentOf(para), 'a <code>foo +bar+ baz</code> kind of thing');
      });

      test('should support constrained passthrough in monospace phrase with attrlist', () {
        final para = blockFromString('[.role]`foo +bar+ baz`');
        expect(contentOf(para), '<code class="role">foo bar baz</code>');
      });

      test('should support attrlist on a literal monospace phrase', () {
        final para = blockFromString('[.baz]`+foo--bar+`');
        expect(contentOf(para), '<code class="baz">foo--bar</code>');
      });

      test('should not process an escaped passthrough macro inside a monospaced phrase', () {
        final para = blockFromString(
          'use the `$bs'
          'pass:c[]` macro',
        );
        expect(contentOf(para), 'use the <code>pass:c[]</code> macro');
      });

      test('should not process an escaped passthrough macro inside a monospaced phrase with attributes', () {
        final para = blockFromString(
          'use the [syntax]`$bs'
          'pass:c[]` macro',
        );
        expect(
          contentOf(para),
          'use the <code class="syntax">pass:c[]</code> macro',
        );
      });

      test('should honor an escaped single plus passthrough inside a monospaced phrase', () {
        final para = blockFromString(
          'use `$bs+{author}+` to show an attribute reference',
          attributes: {'author': 'Dan'},
        );
        expect(
          contentOf(para),
          'use <code>+Dan+</code> to show an attribute reference',
        );
      });
    });

    group('Math macros', () {
      test('should passthrough text in asciimath macro and surround with AsciiMath delimiters', () {
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString(
            'asciimath:[x/x={(1,if x!=0),(text{undefined},if x=0):}]',
            attributes: {'attribute-missing': 'warn'},
          );
          expect(
            contentOf(para),
            r'$x/x={(1,if x!=0),(text{undefined},if x=0):}$',
          );
          expect(logger.isEmpty, isTrue);
        });
      });

      test('should not recognize asciimath macro with no content', () {
        final para = blockFromString('asciimath:[]');
        expect(contentOf(para), 'asciimath:[]');
      });

      test('should perform specialcharacters subs on asciimath macro content in html backend by default', () {
        final para = blockFromString('asciimath:[a < b]');
        expect(contentOf(para), r'$a &lt; b$');
      });

      test('should convert contents of asciimath macro to MathML in DocBook output if asciimath gem is available', () {
        markTestSkipped(
          'requires the asciimath Ruby gem, which has no Dart equivalent in this wave',
        );
      });

      test('should not perform specialcharacters subs on asciimath macro content in Docbook output if asciimath gem not available', () {
        // PORT: the asciimath gem is never available in Dart, so the
        // converter always takes the unavailable path.
        final para = blockFromString('asciimath:[a < b]', backend: 'docbook');
        expect(
          contentOf(para),
          '<inlineequation><mathphrase><![CDATA[a < b]]></mathphrase></inlineequation>',
        );
      });

      test('should honor explicit subslist on asciimath macro', () {
        final para = blockFromString(
          'asciimath:attributes[{expr}]',
          attributes: {'expr': 'x != 0'},
        );
        expect(contentOf(para), r'$x != 0$');
      });

      test('should passthrough text in latexmath macro and surround with LaTeX math delimiters', () {
        final para = blockFromString(
          'latexmath:[C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}]',
        );
        expect(
          contentOf(para),
          '\\(C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}\\)',
        );
      });

      test('should strip legacy LaTeX math delimiters around latexmath content if present', () {
        final para = blockFromString(
          'latexmath:[\$C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}\$]',
        );
        expect(
          contentOf(para),
          '\\(C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}\\)',
        );
      });

      test('should not recognize latexmath macro with no content', () {
        final para = blockFromString('latexmath:[]');
        expect(contentOf(para), 'latexmath:[]');
      });

      test('should unescape escaped square bracket in equation', () {
        final para = blockFromString('latexmath:[$bs${'sqrt'}[3$bs]{x}]');
        expect(contentOf(para), '\\($bs${'sqrt'}[3]{x}\\)');
      });

      test('should perform specialcharacters subs on latexmath macro in html backend by default', () {
        final para = blockFromString('latexmath:[a < b]');
        expect(contentOf(para), r'\(a &lt; b\)');
      });

      test('should not perform specialcharacters subs on latexmath macro content in docbook backend by default', () {
        final para = blockFromString('latexmath:[a < b]', backend: 'docbook');
        expect(
          contentOf(para),
          '<inlineequation><alt><![CDATA[a < b]]></alt><mathphrase><![CDATA[a < b]]></mathphrase></inlineequation>',
        );
      });

      test('should honor explicit subslist on latexmath macro', () {
        final para = blockFromString(
          'latexmath:attributes[{expr}]',
          attributes: {'expr': '$bs${'sqrt'}{4} = 2'},
        );
        expect(contentOf(para), '\\($bs${'sqrt'}{4} = 2\\)');
      });

      test('should passthrough math macro inside another passthrough', () {
        var para = blockFromString(
          'the text `asciimath:[x = y]` should be passed through as +literal+ text',
          attributes: {'compat-mode': ''},
        );
        expect(
          contentOf(para),
          'the text <code>asciimath:[x = y]</code> should be passed through as <code>literal</code> text',
        );

        para = blockFromString(
          'the text [x-]`asciimath:[x = y]` should be passed through as `literal` text',
        );
        expect(
          contentOf(para),
          'the text <code>asciimath:[x = y]</code> should be passed through as <code>literal</code> text',
        );

        para = blockFromString(
          'the text `+asciimath:[x = y]+` should be passed through as `literal` text',
        );
        expect(
          contentOf(para),
          'the text <code>asciimath:[x = y]</code> should be passed through as <code>literal</code> text',
        );
      });

      test('should not recognize stem macro with no content', () {
        final para = blockFromString('stem:[]');
        expect(contentOf(para), 'stem:[]');
      });

      test('should passthrough text in stem macro and surround with AsciiMath delimiters if stem attribute is asciimath, empty, or not set', () {
        for (final attributes in const [
          <String, String>{},
          {'stem': ''},
          {'stem': 'asciimath'},
          {'stem': 'bogus'},
        ]) {
          final logger = FakeLogger();
          withFakeLogger(logger, () {
            final para = blockFromString(
              'stem:[x/x={(1,if x!=0),(text{undefined},if x=0):}]',
              attributes: {...attributes, 'attribute-missing': 'warn'},
            );
            expect(
              contentOf(para),
              r'$x/x={(1,if x!=0),(text{undefined},if x=0):}$',
            );
            expect(logger.isEmpty, isTrue);
          });
        }
      });

      test('should passthrough text in stem macro and surround with LaTeX math delimiters if stem attribute is latexmath, latex, or tex', () {
        for (final attributes in const [
          {'stem': 'latexmath'},
          {'stem': 'latex'},
          {'stem': 'tex'},
        ]) {
          final para = blockFromString(
            'stem:[C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}]',
            attributes: attributes,
          );
          expect(
            contentOf(para),
            '\\(C = $bs${'alpha'} + $bs${'beta'} Y^{$bs${'gamma'}} + $bs${'epsilon'}\\)',
          );
        }
      });

      test('should apply substitutions specified on stem macro', () {
        for (final input in const [
          'stem:c,a[sqrt(x) <=> {solve-for-x}]',
          'stem:n,-r[sqrt(x) <=> {solve-for-x}]',
        ]) {
          final para = blockFromString(
            input,
            attributes: {'stem': 'asciimath', 'solve-for-x': '13'},
          );
          expect(contentOf(para), r'$sqrt(x) &lt;=&gt; 13$');
        }
      });

      test('should replace passthroughs inside stem expression', () {
        final cases = [
          ['stem:[+1+]', r'$1$'],
          [
            'stem:[+$bs${'infty'}-(+$bs${'infty'})]',
            '\$$bs${'infty'}-($bs${'infty'})\$',
          ],
          [
            'stem:[+++$bs${'infty'}-(+$bs${'infty'})++]',
            '\$+$bs${'infty'}-(+$bs${'infty'})\$',
          ],
        ];
        for (final c in cases) {
          final para = blockFromString(c[0], attributes: {'stem': ''});
          expect(contentOf(para), c[1]);
        }
      });

      test('should allow passthrough inside stem expression to be escaped', () {
        final cases = [
          ['stem:[$bs+] and stem:[+]', r'$+$ and $+$'],
          ['stem:[$bs+1+]', r'$+1+$'],
        ];
        for (final c in cases) {
          final para = blockFromString(c[0], attributes: {'stem': ''});
          expect(contentOf(para), c[1]);
        }
      });

      test(
        'should not recognize stem macro with invalid substitution list',
        () {
          for (final subs in const [',', '42', 'a,']) {
            final para = blockFromString(
              'stem:$subs[x^2]',
              attributes: {'stem': 'asciimath'},
            );
            expect(contentOf(para), 'stem:$subs[x^2]');
          }
        },
      );

      test('should warn if substitutions on stem macro are invalid', () {
        const subs = 'bogus';
        final logger = FakeLogger();
        withFakeLogger(logger, () {
          final para = blockFromString(
            'stem:$subs[x^2]',
            attributes: {'stem': 'asciimath'},
          );
          expect(contentOf(para), r'$x^2$');
          expect(logger.warns, [
            'invalid substitution type for stem macro: $subs',
          ]);
        });
      });
    });

    group('Replacements', () {
      test('unescapes XML entities', () {
        final para = blockFromString('< &quot; &there4; &#34; &#x22; >');
        expect(
          applySubs(para, para.source()),
          '&lt; &quot; &there4; &#34; &#x22; &gt;',
        );
      });

      test('replaces arrows', () {
        final para = blockFromString('<- -> <= => $bs<- $bs-> $bs<= $bs=>');
        expect(
          applySubs(para, para.source()),
          '&#8592; &#8594; &#8656; &#8658; &lt;- -&gt; &lt;= =&gt;',
        );
      });

      test('replaces dashes', () {
        const input =
            '-- foo foo--bar foo$bs--bar foo -- bar foo $bs-- bar\n'
            'stuff in between\n'
            '-- foo\n'
            'stuff in between\n'
            'foo --\n'
            'stuff in between\n'
            'foo --\n';
        const expected =
            '&#8201;&#8212;&#8201;foo foo&#8212;&#8203;bar foo--bar foo&#8201;&#8212;&#8201;bar foo -- bar\n'
            'stuff in between&#8201;&#8212;&#8201;foo\n'
            'stuff in between\n'
            'foo&#8201;&#8212;&#8201;stuff in between\n'
            'foo&#8201;&#8212;&#8201;';
        final para = blockFromString(input);
        expect(subReplacements(para.source()), expected);
      });

      test('replaces dashes between multibyte word characters', () {
        final para = blockFromString('富--巴');
        expect(subReplacements(para.source()), '富&#8212;&#8203;巴');
      });

      test('replaces marks', () {
        final para = blockFromString('(C) (R) (TM) $bs(C) $bs(R) $bs(TM)');
        expect(
          subReplacements(para.source()),
          '&#169; &#174; &#8482; (C) (R) (TM)',
        );
      });

      test('preserves entity references', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        const input = '&amp; &#169; &#10004; &#128512; &#x2022; &#x1f600;';
        final para = blockFromString(input);
        expect(contentOf(para), input);
      });

      test('only preserves named entities with two or more letters', () {
        // PORT: `convert_inline_string` renders the single paragraph
        // content.
        final para = blockFromString('&amp; &a; &gt;');
        expect(contentOf(para), '&amp; &amp;a; &gt;');
      });

      test('replaces punctuation', () {
        final para = blockFromString(
          "John's Hideout is the Whites`' place... foo$bs'bar",
        );
        expect(
          subReplacements(para.source()),
          "John&#8217;s Hideout is the Whites&#8217; place&#8230;&#8203; foo'bar",
        );
      });

      test('should replace right single quote marks', () {
        final given = [
          "`'Twas the night",
          "a `'57 Chevy!",
          "the whites`' place",
          "the whites`'.",
          "the whites`'--where the wild things are",
          "the whites`'\nhave",
          "It's Mary`'s little lamb.",
          "consecutive single quotes '' are not modified",
          "he is 6' tall",
          "$bs`'",
        ];
        final expected = [
          '&#8217;Twas the night',
          'a &#8217;57 Chevy!',
          'the whites&#8217; place',
          'the whites&#8217;.',
          'the whites&#8217;--where the wild things are',
          'the whites&#8217;\nhave',
          'It&#8217;s Mary&#8217;s little lamb.',
          "consecutive single quotes '' are not modified",
          "he is 6' tall",
          "`'",
        ];
        for (var i = 0; i < given.length; i++) {
          final para = blockFromString(given[i]);
          expect(subReplacements(para.source()), expected[i]);
        }
      });
    });

    group('Post replacements', () {
      test('line break inserted after line with line break character', () {
        final para = blockFromString('First line +\nSecond line');
        final result =
            applySubs(para, para.lines, expandSubs(para, 'post_replacements'))!
                as List;
        expect(result.first, 'First line<br>');
      });

      test('line break inserted after line wrap with hardbreaks enabled', () {
        final para = blockFromString(
          'First line\nSecond line',
          attributes: {'hardbreaks': ''},
        );
        final result =
            applySubs(para, para.lines, expandSubs(para, 'post_replacements'))!
                as List;
        expect(result.first, 'First line<br>');
      });

      test('line break character stripped from end of line with hardbreaks enabled', () {
        final para = blockFromString(
          'First line +\nSecond line',
          attributes: {'hardbreaks': ''},
        );
        final result =
            applySubs(para, para.lines, expandSubs(para, 'post_replacements'))!
                as List;
        expect(result.first, 'First line<br>');
      });

      test(
        'line break not inserted for single line with hardbreaks enabled',
        () {
          final para = blockFromString(
            'First line',
            attributes: {'hardbreaks': ''},
          );
          final result =
              applySubs(
                    para,
                    para.lines,
                    expandSubs(para, 'post_replacements'),
                  )!
                  as List;
          expect(result.first, 'First line');
        },
      );
    });

    group('Resolve subs', () {
      test('should resolve subs for block', () {
        // PORT: `empty_document parse: true` is just a document here;
        // commit_subs needs no parsed content.
        final doc = makeDoc();
        final block = Block(doc, 'paragraph');
        block.attributes['subs'] = 'quotes,normal';
        commitSubs(block);
        expect(block.subs, [
          'quotes',
          'specialcharacters',
          'attributes',
          'replacements',
          'macros',
          'post_replacements',
        ]);
      });

      test('should resolve specialcharacters sub as highlight for source block when source highlighter is coderay', () {
        final doc = makeDoc(attributes: {'source-highlighter': 'coderay'});
        // PORT: bare Document construction skips save_attributes, so
        // resolve the highlighter explicitly (Ruby's `parse: true` does
        // this via the parse path).
        doc.syntaxHighlighter = SyntaxHighlighter.resolveForDocument(doc);
        final block = Block(doc, 'listing', contentModel: 'verbatim');
        block.style = 'source';
        block.attributes['subs'] = 'specialcharacters';
        block.attributes['language'] = 'ruby';
        commitSubs(block);
        expect(block.subs, ['highlight']);
      });

      test('should resolve specialcharacters sub as highlight for source block when source highlighter is pygments', () {
        markTestSkipped(
          "requires a pygments backend (mirrors the Ruby test gate `if: ENV['PYGMENTS_VERSION']`); with no backend canHighlight is false",
        );
      });

      test('should not replace specialcharacters sub with highlight for source block when source highlighter is not set', () {
        final doc = makeDoc();
        final block = Block(doc, 'listing', contentModel: 'verbatim');
        block.style = 'source';
        block.attributes['subs'] = 'specialcharacters';
        block.attributes['language'] = 'ruby';
        commitSubs(block);
        expect(block.subs, ['specialcharacters']);
      });

      test(
        'should not use subs if subs option passed to block constructor is nil',
        () {
          // PORT: the Block constructor's eager `commitSubs()` method still
          // throws until the merger wires it; replicate the constructor
          // effects (clear subs attr, prevent resolution) and call the
          // ported top-level commitSubs directly.
          final doc = makeDoc();
          final block = Block(doc, 'paragraph', attributes: {'subs': 'quotes'});
          block.attributes.remove('subs');
          block.defaultSubs = <String>[];
          expect(block.subs, isEmpty);
          commitSubs(block);
          expect(block.subs, isEmpty);
        },
      );

      test('should not use subs if subs option passed to block constructor is empty array', () {
        // PORT: same constructor emulation as above (empty list seeds
        // defaultSubs).
        final doc = makeDoc();
        final block = Block(doc, 'paragraph', attributes: {'subs': 'quotes'});
        block.attributes.remove('subs');
        block.defaultSubs = <String>[];
        expect(block.subs, isEmpty);
        commitSubs(block);
        expect(block.subs, isEmpty);
      });

      test('should use subs from subs option passed to block constructor', () {
        // PORT: same constructor emulation as above (list seeds
        // defaultSubs and is resolved eagerly).
        final doc = makeDoc();
        final block = Block(doc, 'paragraph', attributes: {'subs': 'quotes'});
        block.attributes.remove('subs');
        block.defaultSubs = <String>['specialcharacters'];
        commitSubs(block);
        expect(block.subs, ['specialcharacters']);
        commitSubs(block);
        expect(block.subs, ['specialcharacters']);
      });

      test('should use subs from subs attribute if subs option is not passed to block constructor', () {
        final doc = makeDoc();
        final block = Block(doc, 'paragraph', attributes: {'subs': 'quotes'});
        expect(block.subs, isEmpty);
        // in this case, we have to call commit_subs to resolve the subs
        commitSubs(block);
        expect(block.subs, ['quotes']);
      });

      test('should use subs from subs attribute if subs option passed to block constructor is default', () {
        // PORT: same constructor emulation as above (`default` honors
        // the subs attribute eagerly).
        final doc = makeDoc();
        final block = Block(doc, 'paragraph', attributes: {'subs': 'quotes'});
        block.defaultSubs = null;
        commitSubs(block);
        expect(block.subs, ['quotes']);
        commitSubs(block);
        expect(block.subs, ['quotes']);
      });

      test('should use built-in subs if subs option passed to block constructor is default and subs attribute is absent', () {
        // PORT: same constructor emulation as above (`default` falls
        // back to the context built-ins eagerly).
        final doc = makeDoc();
        final block = Block(doc, 'paragraph');
        block.defaultSubs = null;
        commitSubs(block);
        expect(block.subs, [
          'specialcharacters',
          'quotes',
          'attributes',
          'replacements',
          'macros',
          'post_replacements',
        ]);
        commitSubs(block);
        expect(block.subs, [
          'specialcharacters',
          'quotes',
          'attributes',
          'replacements',
          'macros',
          'post_replacements',
        ]);
      });
    });

    group('Resolve lines to highlight', () {
      // Expected values verified against the Ruby oracle
      // (`Block#resolve_lines_to_highlight` on a 5-line source).
      const source = 'a\nb\nc\nd\ne\n';

      test('single line without start', () {
        expect(resolveLinesToHighlight(source, '2'), [2]);
      });

      test('line list without start', () {
        expect(resolveLinesToHighlight(source, '1,3'), [1, 3]);
      });

      test('line range without start', () {
        expect(resolveLinesToHighlight(source, '2..4'), [2, 3, 4]);
      });

      test('open-ended range without start', () {
        expect(resolveLinesToHighlight(source, '2..-1'), [2, 3, 4, 5, 6]);
      });

      test('start shifts resolved lines down by start - 1', () {
        expect(resolveLinesToHighlight(source, '6', 5), [2]);
      });

      test('start shifts ranges down by start - 1', () {
        expect(resolveLinesToHighlight(source, '2..4', 5), [-2, -1, 0]);
        expect(resolveLinesToHighlight(source, '2..-1', 5), [-2, -1, 0, 1, 2]);
      });
    });
  });
}
