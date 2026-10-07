/// The HTML-like markup asciidoctor-pdf's inline converters write
/// (`<strong>`, `<a href="...">`, `<font size="...">`, `<span style=...>`,
/// `<img>`, `<br>`, character references), parsed as its grammar parses it
/// and turned into text fragments styled by the theme, as its
/// `FormattedText::Transform` does.
library;

import 'package:asciidart/src/pdf/theme.dart';

/// A parsed markup node.
sealed class MarkupNode {
  const new();
}

/// Text.
final class MarkupText extends MarkupNode {
  /// The text [value].
  const new(this.value);

  /// The text.
  final String value;
}

/// A character reference (`&amp;`, `&#160;`, `&#xa0;`).
final class MarkupCharRef extends MarkupNode {
  /// The reference to [text].
  const new(this.text);

  /// The character referred to.
  final String text;
}

/// An element: a tag with attributes and (unless it is `<br>` or
/// `<img>`) content.
final class MarkupElement extends MarkupNode {
  /// The element [name] with [attributes] and [content] (null for a void
  /// element).
  const new(this.name, this.attributes, this.content);

  /// The tag name.
  final String name;

  /// The attributes.
  final Map<String, String> attributes;

  /// The content, or null for `<br>` and `<img>`.
  final List<MarkupNode>? content;
}

const Set<String> _tagNames = {
  'a',
  'strong',
  'em',
  'code',
  'font',
  'span',
  'button',
  'kbd',
  'sup',
  'sub',
  'mark',
  'menu',
  'del',
};

const Map<String, String> _namedRefs = {
  'amp': '&',
  'apos': "'",
  'gt': '>',
  'lt': '<',
  'nbsp': ' ',
  'quot': '"',
};

/// The nodes of [text], or null when the markup can't be parsed (the gem
/// then logs an error and shows the text as it is).
List<MarkupNode>? parseMarkup(String text) {
  final parser = _Parser(text);
  final nodes = parser.complex();
  return parser.at == text.length ? nodes : null;
}

final class _Parser {
  new(this.text);

  final String text;
  int at = 0;

  bool _startsWith(String s) => text.startsWith(s, at);

  List<MarkupNode> complex() {
    final nodes = <MarkupNode>[];
    while (at < text.length) {
      final node = _cdata() ?? _element() ?? _charref();
      if (node == null) break;
      nodes.add(node);
    }
    return nodes;
  }

  MarkupNode? _cdata() {
    final start = at;
    while (at < text.length && text[at] != '<' && text[at] != '&') {
      at++;
    }
    return at > start ? MarkupText(text.substring(start, at)) : null;
  }

  MarkupNode? _charref() {
    final m = RegExp(
      '&(?:#([0-9]{2,6})|#x([0-9a-fA-F]{2,5})|(amp|apos|gt|lt|nbsp|quot));',
    ).matchAsPrefix(text, at);
    if (m == null) return null;
    at = m.end;
    final String value;
    if (m[1] != null) {
      value = String.fromCharCode(int.parse(m[1]!));
    } else if (m[2] != null) {
      value = String.fromCharCode(int.parse(m[2]!, radix: 16));
    } else {
      value = _namedRefs[m[3]!]!;
    }
    return MarkupCharRef(value);
  }

  MarkupNode? _element() {
    if (!_startsWith('<')) return null;
    final start = at;
    // A void element: <br>, <img ...>, optionally self-closed.
    for (final name in ['br', 'img']) {
      if (_startsWith('<$name')) {
        at += 1 + name.length;
        final attributes = _attributes();
        final close = RegExp(' */?>').matchAsPrefix(text, at);
        if (close != null && (close[0] == '>' || close[0]!.endsWith('/>'))) {
          // `(spaces? '/')? '>'`: spaces only before a slash.
          if (close[0]!.trimLeft() == '>' && close[0] != '>') {
            at = start;
          } else {
            at = close.end;
            return MarkupElement(name, attributes, null);
          }
        } else {
          at = start;
        }
      }
    }
    // A start tag, its content, and an end tag (of any name).
    final name = _tagName(at + 1);
    if (name == null) return null;
    at += 1 + name.length;
    final attributes = _attributes();
    if (!_startsWith('>')) {
      at = start;
      return null;
    }
    at++;
    final content = complex();
    if (!_startsWith('</')) {
      at = start;
      return null;
    }
    final endName = _tagName(at + 2);
    if (endName == null || !text.startsWith('>', at + 2 + endName.length)) {
      at = start;
      return null;
    }
    at += 3 + endName.length;
    return MarkupElement(name, attributes, content);
  }

  /// The tag name at [index] (the grammar's ordered choice: `a` before
  /// `a`-prefixed names, as PEG tries them).
  String? _tagName(int index) {
    for (final name in _tagNames) {
      if (text.startsWith(name, index)) return name;
    }
    return null;
  }

  Map<String, String> _attributes() {
    final attributes = <String, String>{};
    while (true) {
      final m = RegExp(' +([a-z_]+)="([^"]*)"').matchAsPrefix(text, at);
      if (m == null) break;
      attributes[m[1]!] = m[2]!;
      at = m.end;
    }
    return attributes;
  }
}

/// A font style of a fragment.
enum FragmentStyle {
  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Underlined.
  underline,

  /// Struck through.
  strikethrough,

  /// Subscript.
  subscript,

  /// Superscript.
  superscript,

  /// Normal (clears bold and italic when merged).
  normal,

  /// Emphasized, as the modern engine sets emphasis: italic in upright
  /// text, upright in italic text (nested emphasis toggles it).
  emphasis,
}

/// What draws a fragment besides its text.
enum FragmentCallback {
  /// A background and border behind the text.
  textBackgroundAndBorder,

  /// An inline image.
  inlineImage,

  /// Text aligned in a fixed width.
  inlineTextAligner,

  /// A named destination at the fragment.
  inlineDestinationMarker,
}

/// A run of text with its formatting (the gem's fragment hash).
final class Fragment {
  /// A fragment of [text].
  new(this.text);

  /// The text.
  String text;

  /// The styles.
  Set<FragmentStyle>? styles;

  /// The font family.
  String? font;

  /// The size: points (`10.5`) or relative (`1.2em`, `80%`).
  String? size;

  /// The color: a theme color.
  ThemeColor? color;

  /// The link target (a URL or `#anchor`).
  String? link;

  /// The internal anchor the text links to.
  String? anchor;

  /// The name of the destination the fragment marks.
  String? name;

  /// The kind of destination or term (`indexterm`, `xref`...).
  String? type;

  /// The background color.
  ThemeColor? backgroundColor;

  /// The border color.
  ThemeColor? borderColor;

  /// The border width.
  num? borderWidth;

  /// The space between the text and its border.
  num? borderOffset;

  /// The border radius.
  num? borderRadius;

  /// The color of underlines and strike-throughs.
  ThemeColor? textDecorationColor;

  /// The width of underlines and strike-throughs.
  num? textDecorationWidth;

  /// The text transform (`uppercase`...).
  String? textTransform;

  /// The alignment in a fixed [width].
  String? align;

  /// A fixed width (`2em`, `20pt`).
  String? width;

  /// What draws the fragment besides its text.
  List<FragmentCallback>? callbacks;

  /// Whether the fragment joins the next one without a break (`wj`).
  bool wj = false;

  /// Whether the fragment is decoration that text extraction and copying
  /// leave out (a callout marker; class `artifact`).
  bool artifact = false;

  /// The key of a label the layout gives the fragment's text (a footnote
  /// reference's number on its page; `label` attribute of a link).
  String? label;

  /// The OpenType features the fragment is set with in the modern engine
  /// (`smcp`, `onum`...), from its roles.
  Set<String>? features;

  /// An inline image: its path, format, width and fit.
  String? imagePath;

  /// The image's format.
  String? imageFormat;

  /// The image's width.
  String? imageWidth;

  /// The image's fit.
  String? imageFit;

  /// Identifies an image fragment across splits.
  int? objectId;

  /// Whether the fragment is a destination marker (no text of its own).
  bool get isMarker =>
      callbacks?.contains(FragmentCallback.inlineDestinationMarker) ?? false;

  /// A copy of this fragment (with copies of its sets and lists).
  Fragment copy({String? text}) => Fragment(text ?? this.text)
    ..styles = styles == null ? null : {...styles!}
    ..font = font
    ..size = size
    ..color = color
    ..link = link
    ..anchor = anchor
    ..name = name
    ..type = type
    ..backgroundColor = backgroundColor
    ..borderColor = borderColor
    ..borderWidth = borderWidth
    ..borderOffset = borderOffset
    ..borderRadius = borderRadius
    ..textDecorationColor = textDecorationColor
    ..textDecorationWidth = textDecorationWidth
    ..textTransform = textTransform
    ..align = align
    ..width = width
    ..callbacks = callbacks == null ? null : [...callbacks!]
    ..wj = wj
    ..artifact = artifact
    ..label = label
    ..features = features == null ? null : {...features!}
    ..imagePath = imagePath
    ..imageFormat = imageFormat
    ..imageWidth = imageWidth
    ..imageFit = imageFit
    ..objectId = objectId;
}

/// The OpenType features of the CSS `font-variant` and
/// `font-variant-numeric` values the theme's roles may name.
const Map<String, String> _features = {
  'small-caps': 'smcp',
  'oldstyle-nums': 'onum',
  'lining-nums': 'lnum',
  'tabular-nums': 'tnum',
  'proportional-nums': 'pnum',
};

/// The OpenType feature of [value], a CSS `font-variant` or
/// `font-variant-numeric` value, if it names one.
String? fontFeature(String? value) => _features[value];

/// The formatting a tag, class or role gives (the gem's theme settings).
final class FragmentSettings {
  /// Settings.
  new({
    this.color,
    this.font,
    this.size,
    this.styles,
    this.clearStyles = false,
    this.backgroundColor,
    this.borderWidth,
    this.borderColor,
    this.borderOffset,
    this.borderRadius,
    this.textDecorationColor,
    this.textDecorationWidth,
    this.textTransform,
    this.align,
    this.callbacks,
  });

  /// The font color.
  ThemeColor? color;

  /// The font family.
  String? font;

  /// The font size.
  String? size;

  /// The styles to add (`normal` clears bold and italic).
  Set<FragmentStyle>? styles;

  /// Whether the settings clear the styles (a role with `font-style:
  /// normal` and no decoration).
  bool clearStyles;

  /// The background color.
  ThemeColor? backgroundColor;

  /// The border width.
  num? borderWidth;

  /// The border color.
  ThemeColor? borderColor;

  /// The space between text and border.
  num? borderOffset;

  /// The border radius.
  num? borderRadius;

  /// The color of decorations.
  ThemeColor? textDecorationColor;

  /// The width of decorations.
  num? textDecorationWidth;

  /// The text transform.
  String? textTransform;

  /// The alignment in a fixed width.
  String? align;

  /// What draws the fragment besides its text.
  List<FragmentCallback>? callbacks;

  /// The OpenType features (modern engine).
  Set<String>? features;

  /// Applies the settings to [fragment] (the gem's `update_fragment`).
  void applyTo(Fragment fragment) {
    if (color != null) fragment.color = color;
    if (features case final add?) {
      fragment.features = {...?fragment.features, ...add};
    }
    if (font != null) fragment.font = font;
    if (size != null) fragment.size = size;
    if (styles != null || clearStyles) {
      final current = fragment.styles ??= {};
      if (styles case final add?) {
        final merged = {...add};
        if (merged.remove(FragmentStyle.normal)) {
          current
            ..remove(FragmentStyle.bold)
            ..remove(FragmentStyle.italic);
        }
        current.addAll(merged);
      } else {
        current.clear();
      }
    }
    if (backgroundColor != null) fragment.backgroundColor = backgroundColor;
    if (borderWidth != null) fragment.borderWidth = borderWidth;
    if (borderColor != null) fragment.borderColor = borderColor;
    if (borderOffset != null) fragment.borderOffset = borderOffset;
    if (borderRadius != null) fragment.borderRadius = borderRadius;
    if (textDecorationColor != null) {
      fragment.textDecorationColor = textDecorationColor;
    }
    if (textDecorationWidth != null) {
      fragment.textDecorationWidth = textDecorationWidth;
    }
    if (textTransform != null) fragment.textTransform = textTransform;
    if (align != null) fragment.align = align;
    if (callbacks != null) fragment.callbacks = [...callbacks!];
  }
}

/// [value] as a theme color (the base theme keeps colors as strings).
ThemeColor? themeColor(ThemeValue? value) => switch (value) {
  null || ThemeNull() => null,
  final ThemeColor color => color,
  ThemeString(:final value) when value == 'transparent' =>
    const TransparentColor(),
  ThemeString(:final value) => HexColor(value.toUpperCase()),
  ThemeNumber(:final value) => HexColor('$value'.padLeft(6, '0').toUpperCase()),
  _ => null,
};

/// The styles of a theme `font_style` and `text_decoration`.
Set<FragmentStyle>? toStyles(String? fontStyle, [String? textDecoration]) {
  final styles = switch (fontStyle) {
    'bold' => {FragmentStyle.bold},
    'italic' => {FragmentStyle.italic},
    'bold_italic' => {FragmentStyle.bold, FragmentStyle.italic},
    'normal_italic' => {FragmentStyle.normal, FragmentStyle.italic},
    _ => null,
  };
  final decoration = switch (textDecoration) {
    'underline' => FragmentStyle.underline,
    'line-through' => FragmentStyle.strikethrough,
    _ => null,
  };
  if (decoration == null) return styles;
  return styles == null ? {decoration} : (styles..add(decoration));
}

/// Turns parsed markup into fragments styled by a theme (the gem's
/// `FormattedText::Transform`, merging adjacent text nodes).
final class MarkupTransform {
  /// A transform with the settings of [theme] (built-in defaults when
  /// null).
  new({Theme? theme, this.invertEmphasis = false, this.keepIndexSpace = false})
    : _settings = theme == null ? _defaults() : _fromTheme(theme);

  /// Whether the space before a concealed index term stays when no space
  /// follows the term (`When (((HTML)))HTML`: the modern engine's), rather
  /// than being dropped always (the gem's).
  final bool keepIndexSpace;

  final Map<String, FragmentSettings> _settings;

  /// Whether emphasis is set against its surroundings
  /// ([FragmentStyle.emphasis]) rather than always in italic.
  final bool invertEmphasis;

  static Map<String, FragmentSettings> _defaults() => {
    'button': FragmentSettings(font: 'Courier', styles: {FragmentStyle.bold}),
    'code': FragmentSettings(font: 'Courier'),
    'kbd': FragmentSettings(font: 'Courier', styles: {FragmentStyle.italic}),
    'link': FragmentSettings(color: const HexColor('0000FF')),
    'mark': FragmentSettings(
      backgroundColor: const HexColor('FFFF00'),
      callbacks: [FragmentCallback.textBackgroundAndBorder],
    ),
    'menu': FragmentSettings(styles: {FragmentStyle.bold}),
    'line-through': FragmentSettings(styles: {FragmentStyle.strikethrough}),
    'underline': FragmentSettings(styles: {FragmentStyle.underline}),
    'big': FragmentSettings(size: '1.667em'),
    'small': FragmentSettings(size: '0.8333em'),
  };

  static Map<String, FragmentSettings> _fromTheme(Theme theme) {
    String? s(String key) => theme.string(key);
    num? n(String key) => theme.number(key);
    ThemeColor? c(String key) => themeColor(theme.value(key));
    FragmentSettings boxed(String category, {String? fontFallback}) {
      final background = c('${category}_background_color');
      final borderWidth = n('${category}_border_width');
      final boxed = background != null || borderWidth != null;
      final offset = boxed ? n('${category}_border_offset') : null;
      return FragmentSettings(
        color: c('${category}_font_color'),
        font: s('${category}_font_family') ?? fontFallback,
        size: s('${category}_font_size'),
        styles: toStyles(s('${category}_font_style')),
        backgroundColor: background,
        borderWidth: borderWidth,
        borderColor: borderWidth == null
            ? null
            : c('${category}_border_color') ?? c('base_border_color'),
        borderOffset: offset,
        borderRadius: boxed ? n('${category}_border_radius') : null,
        align: offset != null ? 'center' : null,
        callbacks: boxed ? [FragmentCallback.textBackgroundAndBorder] : null,
      );
    }

    final linkBackground = c('link_background_color');
    final linkOffset = linkBackground == null ? null : n('link_border_offset');
    final markBackground = c('mark_background_color');
    final markOffset = markBackground == null ? null : n('mark_border_offset');
    final settings = <String, FragmentSettings>{
      'button': boxed('button'),
      'code': boxed('codespan'),
      'kbd': boxed('kbd', fontFallback: s('codespan_font_family')),
      'link': FragmentSettings(
        color: c('link_font_color'),
        font: s('link_font_family'),
        size: s('link_font_size'),
        styles: toStyles(s('link_font_style'), s('link_text_decoration')),
        textDecorationColor: c('link_text_decoration_color'),
        textDecorationWidth: n('link_text_decoration_width'),
        backgroundColor: linkBackground,
        borderOffset: linkOffset,
        align: linkOffset != null ? 'center' : null,
        callbacks: linkBackground == null
            ? null
            : [FragmentCallback.textBackgroundAndBorder],
      ),
      'mark': FragmentSettings(
        color: c('mark_font_color'),
        styles: toStyles(s('mark_font_style')),
        backgroundColor: markBackground,
        borderOffset: markOffset,
        align: markOffset != null ? 'center' : null,
        callbacks: markBackground == null
            ? null
            : [FragmentCallback.textBackgroundAndBorder],
      ),
      'menu': FragmentSettings(
        color: c('menu_font_color'),
        font: s('menu_font_family'),
        size: s('menu_font_size'),
        styles: toStyles(s('menu_font_style')),
      ),
      // A callout marker as text (the modern engine's `conum_glyphs`
      // template): its style and figures.
      'conum-text': FragmentSettings(styles: toStyles(s('conum_font_style')))
        ..features = switch (_features[s('conum_font_variant_numeric')]) {
          final String feature => {feature},
          null => null,
        },
    };
    final styled = <String>{};
    for (final key in theme.keys) {
      if (!key.startsWith('role_')) continue;
      final rest = key.substring(5);
      final split = rest.indexOf('_');
      if (split < 0) continue;
      final role = rest.substring(0, split);
      final property = rest.substring(split + 1);
      final value = theme.value(key);
      final target = settings[role] ??= FragmentSettings();
      switch (property) {
        case 'background_color':
          target.backgroundColor = themeColor(value);
        case 'border_color':
          target.borderColor = themeColor(value);
        case 'border_offset':
          target.borderOffset = theme.number(key);
        case 'border_radius':
          target.borderRadius = theme.number(key);
        case 'border_width':
          target.borderWidth = theme.number(key);
          if (value != null &&
              theme.value('role_${role}_border_color') == null) {
            target.borderColor = c('base_border_color');
          }
        case 'font_color':
          target.color = themeColor(value);
        case 'font_family':
          target.font = theme.string(key);
        case 'font_size':
          target.size = theme.string(key);
        case 'text_decoration_color':
          target.textDecorationColor = themeColor(value);
        case 'text_decoration_width':
          target.textDecorationWidth = theme.number(key);
        case 'text_transform':
          target.textTransform = theme.string(key);
        case 'font_variant' || 'font_variant_numeric':
          // The modern engine's OpenType features, as CSS names them.
          if (_features[theme.string(key)] case final feature?) {
            (target.features ??= {}).add(feature);
          }
        case 'font_style' || 'text_decoration':
          styled.add(role);
      }
    }
    for (final role in styled) {
      final styles = toStyles(
        theme.string('role_${role}_font_style'),
        theme.string('role_${role}_text_decoration'),
      );
      settings[role]!
        ..styles = styles
        ..clearStyles = styles == null;
    }
    settings
      ..putIfAbsent(
        'line-through',
        () => FragmentSettings(styles: {FragmentStyle.strikethrough}),
      )
      ..putIfAbsent(
        'underline',
        () => FragmentSettings(styles: {FragmentStyle.underline}),
      );
    final baseSize = theme.number('base_font_size')?.toDouble() ?? 12;
    String relative(num size) => '${rubyNumber(_round5(size / baseSize))}em';
    settings
      ..putIfAbsent(
        'big',
        () => FragmentSettings(
          size: switch (theme.number('base_font_size_large')) {
            final large? => relative(large),
            null => '1.1667em',
          },
        ),
      )
      ..putIfAbsent(
        'small',
        () => FragmentSettings(
          size: switch (theme.number('base_font_size_small')) {
            final small? => relative(small),
            null => '0.8333em',
          },
        ),
      );
    return settings;
  }

  static double _round5(double value) =>
      (value * 100000).roundToDouble() / 100000;

  /// Whether the node after [node] in [nodes] starts with a space (or
  /// there is none).
  static bool _spaceAfter(List<MarkupNode> nodes, MarkupNode node) {
    final at = nodes.indexOf(node);
    if (at + 1 >= nodes.length) return true;
    return switch (nodes[at + 1]) {
      MarkupText(:final value) => value.startsWith(RegExp(r'\s')),
      _ => false,
    };
  }

  /// The fragments of [nodes], inheriting [inherited].
  List<Fragment> apply(
    List<MarkupNode> nodes, [
    List<Fragment>? into,
    Fragment? inherited,
  ]) {
    final fragments = into ?? <Fragment>[];
    var previousIsText = false;
    // The modern engine: a concealed index term between two spaces (the
    // one before it in an element, a term's gap) leaves one.
    var dropLeadingSpace = false;
    void text(String given) {
      var value = given;
      if (dropLeadingSpace) {
        dropLeadingSpace = false;
        value = value.replaceFirst(RegExp(r'^\s+'), '');
        if (value.isEmpty) return;
      }
      if (previousIsText) {
        final last = fragments.removeLast();
        fragments.add(_clone(inherited, '${last.text}$value'));
      } else {
        fragments.add(_clone(inherited, value));
      }
      previousIsText = true;
    }

    for (final node in nodes) {
      switch (node) {
        case MarkupElement(
          :final name,
          :final attributes,
          content: final content?,
        ):
          if (content.isEmpty) {
            if (previousIsText && fragments.last.text.endsWith(' ')) {
              final last = fragments.last;
              last.text = last.text.substring(0, last.text.length - 1);
            }
            continue;
          }
          final fragment = _build(_clone(inherited, ''), name, attributes);
          if (name == 'a' &&
              fragment.type == 'indexterm' &&
              attributes['visible'] == null &&
              previousIsText &&
              fragments.last.text.endsWith(' ') &&
              !(keepIndexSpace && !_spaceAfter(nodes, node))) {
            final last = fragments.last;
            last.text = last.text.substring(0, last.text.length - 1);
          } else if (keepIndexSpace &&
              name == 'a' &&
              fragment.type == 'indexterm' &&
              attributes['visible'] == null &&
              !previousIsText &&
              fragments.isNotEmpty &&
              fragments.last.text.endsWith(' ') &&
              _spaceAfter(nodes, node)) {
            dropLeadingSpace = true;
          }
          var children = content;
          if (fragment.textTransform case final transform?) {
            fragment.textTransform = null;
            children = _transformText(content, transform);
          }
          apply(children, fragments, fragment);
          previousIsText = false;
        case MarkupElement(name: 'img', :final attributes):
          final image =
              Fragment('[${(attributes['alt'] ?? '').replaceAll('​', '')}]')
                ..imagePath = attributes['src']
                ..imageFormat = attributes['format']
                ..objectId = identityHashCode(node);
          if (inherited?.callbacks?.contains(
                FragmentCallback.textBackgroundAndBorder,
              ) ??
              false) {
            image
              ..callbacks = [
                FragmentCallback.textBackgroundAndBorder,
                FragmentCallback.inlineImage,
              ]
              ..borderColor = inherited!.borderColor
              ..borderOffset = inherited.borderOffset
              ..borderRadius = inherited.borderRadius
              ..borderWidth = inherited.borderWidth
              ..backgroundColor = inherited.backgroundColor;
          } else {
            image.callbacks = [FragmentCallback.inlineImage];
          }
          for (final className in (attributes['class'] ?? '').split(' ')) {
            final settings = _settings[className];
            if (className.isEmpty || settings == null) continue;
            settings.applyTo(image);
            if (image.backgroundColor != null ||
                (image.borderColor != null && image.borderWidth != null)) {
              image.callbacks = {
                FragmentCallback.textBackgroundAndBorder,
                ...?image.callbacks,
              }.toList();
            }
          }
          if (inherited case final parent?) {
            if (parent.link != null) {
              image.link = parent.link;
            } else if (parent.anchor != null) {
              image.anchor = parent.anchor;
            }
          }
          image
            ..imageWidth = attributes['width']
            ..imageFit = attributes['fit'];
          fragments.add(image);
          previousIsText = false;
        case MarkupElement():
          // <br>
          text('\n');
        case MarkupCharRef(text: final value):
          text(value);
        case MarkupText(:final value):
          text(value);
      }
    }
    return fragments;
  }

  Fragment _clone(Fragment? fragment, String text) =>
      fragment == null ? Fragment(text) : fragment.copy(text: text);

  Fragment _build(Fragment fragment, String tag, Map<String, String> attrs) {
    var result = fragment;
    final styles = result.styles ??= {};
    switch (tag) {
      case 'strong':
        styles.add(FragmentStyle.bold);
      case 'em' when invertEmphasis:
        if (!styles.remove(FragmentStyle.emphasis)) {
          styles.add(FragmentStyle.emphasis);
        }
      case 'em':
        styles.add(FragmentStyle.italic);
      case 'button' || 'code' || 'kbd' || 'mark' || 'menu':
        _settings[tag]?.applyTo(result);
      case 'font':
        if (attrs['name'] case final value?) result.font = value;
        if (attrs['size'] case final value?) {
          if (value.endsWith('em')) {
            if (value != '1em') result.size = value;
          } else {
            result.size = rubyNumber(_toF(value));
          }
        }
        if (attrs['width'] case final value?) {
          result
            ..width = value
            ..align = 'center';
        }
        if (attrs['color'] case final value? when value.isNotEmpty) {
          result.color = switch (value[0]) {
            '#' =>
              RegExp(r'^#[0-9a-fA-F]{3,6}$').hasMatch(value)
                  ? HexColor(
                      value.length == 7
                          ? value.substring(1)
                          : value
                                .substring(1, 4)
                                .split('')
                                .map((c) => '$c$c')
                                .join(),
                    )
                  : result.color,
            '[' => CmykThemeColor([
              for (final (i, part)
                  in value
                      .substring(1)
                      .replaceFirst(RegExp(r'\]$'), '')
                      .split(', ')
                      .take(4)
                      .indexed)
                if (i < 4 && _toI(part) == _toF(part))
                  _toI(part)
                else if (i < 4)
                  _toF(part),
            ]),
            _ => HexColor(value),
          };
        }
      case 'a':
        var visible = true;
        if (attrs.isNotEmpty) {
          if (attrs['label'] case final value?) result.label = value;
          if (attrs['anchor'] case final value?) {
            result.anchor = value;
          } else if (attrs['href'] case final value?) {
            result.link = value.contains(';') ? _decodeRefs(value) : value;
          } else if (attrs['id'] case final value?) {
            final marker = Fragment('')
              ..name = value
              ..callbacks = [FragmentCallback.inlineDestinationMarker]
              ..wj = result.wj;
            if (attrs['type'] case final type?) marker.type = type;
            result = marker;
            visible = false;
          }
        }
        if (visible) _settings['link']?.applyTo(result);
      case 'sub':
        styles.add(FragmentStyle.subscript);
      case 'sup':
        styles.add(FragmentStyle.superscript);
      case 'del':
        styles.add(FragmentStyle.strikethrough);
      default:
        // span
        for (final style
            in (attrs['style'] ?? '').replaceAll(' ', '').split(';')) {
          final colon = style.indexOf(':');
          if (colon < 0) continue;
          final name = style.substring(0, colon);
          final value = style.substring(colon + 1);
          final hex =
              value.startsWith('#') &&
              RegExp(r'^#[0-9a-fA-F]{3,6}$').hasMatch(value);
          String expand(String v) => v.length == 7
              ? v.substring(1)
              : v.substring(1, 4).split('').map((c) => '$c$c').join();
          switch (name) {
            case 'color' when hex:
              result.color = HexColor(expand(value));
            case 'font-weight' when value == 'bold':
              styles.add(FragmentStyle.bold);
            case 'font-style' when value == 'italic':
              styles.add(FragmentStyle.italic);
            case 'align' || 'text-align':
              result.align = value;
            case 'width':
              result.width = value;
            case 'background-color' when hex:
              result
                ..backgroundColor = HexColor(expand(value))
                ..callbacks = [FragmentCallback.textBackgroundAndBorder];
          }
        }
    }
    for (final className in (attrs['class'] ?? '').split(' ')) {
      if (className.isEmpty) continue;
      if (className == 'wj') result.wj = true;
      if (className == 'artifact') result.artifact = true;
      final settings = _settings[className];
      if (settings == null) continue;
      settings.applyTo(result);
      if (result.backgroundColor != null ||
          (result.borderColor != null && result.borderWidth != null)) {
        result.callbacks = {
          FragmentCallback.textBackgroundAndBorder,
          ...?result.callbacks,
        }.toList();
        if (result.borderOffset != null) result.align = 'center';
      }
    }
    if (result.styles?.isEmpty ?? false) result.styles = null;
    if (result.align != null) {
      result.callbacks = {
        ...?result.callbacks,
        FragmentCallback.inlineTextAligner,
      }.toList();
    }
    return result;
  }

  static String _decodeRefs(String value) => value.replaceAllMapped(
    RegExp(
      r'&(?:(amp|apos|gt|lt|nbsp|quot)|#(?:(\d\d\d{0,4})|x([0-9a-fA-F]{2}[0-9a-fA-F]{0,3})));',
    ),
    (m) => m[1] != null
        ? _namedRefs[m[1]!]!
        : String.fromCharCode(
            m[2] != null ? int.parse(m[2]!) : int.parse(m[3]!, radix: 16),
          ),
  );

  static double _toF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)').stringMatch(text) ?? '',
      ) ??
      0;

  static int _toI(String text) =>
      int.tryParse(RegExp(r'^\s*[+-]?\d+').stringMatch(text)?.trim() ?? '') ??
      0;

  /// [content] with its text transformed (the transform applies to the
  /// text as a whole, then the pieces are put back).
  List<MarkupNode> _transformText(List<MarkupNode> content, String transform) {
    final chunks = <String>[];
    void extract(List<MarkupNode> nodes) {
      for (final node in nodes) {
        switch (node) {
          case MarkupText(:final value):
            chunks.add(value);
          case MarkupElement(content: final children?):
            extract(children);
          default:
            break;
        }
      }
    }

    extract(content);
    final transformed = transformText(chunks.join(), transform).runes.toList();
    var index = 0;
    List<MarkupNode> restore(List<MarkupNode> nodes) => [
      for (final node in nodes)
        switch (node) {
          MarkupText(:final value) => () {
            final length = value.runes.length;
            final piece = String.fromCharCodes(
              transformed.sublist(
                index.clamp(0, transformed.length),
                (index + length).clamp(0, transformed.length),
              ),
            );
            index += length;
            return MarkupText(piece);
          }(),
          MarkupElement(:final name, :final attributes, content: final c?) =>
            MarkupElement(name, attributes, restore(c)),
          _ => node,
        },
    ];
    return restore(content);
  }
}

/// [text] transformed by a theme `text_transform` (`uppercase`,
/// `lowercase`, `capitalize`, `smallcaps`, `none`).
String transformText(String text, String transform) {
  // Only the text between tags and character references changes.
  String pcdata(RegExp filter, String Function(String) change) =>
      text.replaceAllMapped(
        filter,
        (match) => match[2] != null ? change(match[2]!) : match[1]!,
      );
  final markup = _xmlMarkup.hasMatch(text);
  switch (transform) {
    case 'uppercase':
      return markup
          ? pcdata(_pcdataFilter, (t) => t.toUpperCase())
          : text.toUpperCase();
    case 'lowercase':
      return text.contains('<')
          ? pcdata(_tagFilter, (t) => t.toLowerCase())
          : text.toLowerCase();
    case 'capitalize':
      return markup
          ? pcdata(_pcdataFilter, _capitalizeWords)
          : _capitalizeWords(text);
    case 'smallcaps':
      return markup ? pcdata(_pcdataFilter, _smallCaps) : _smallCaps(text);
    default:
      return text;
  }
}

final RegExp _xmlMarkup = RegExp(r'&#?[a-z\d]+;|<');
final RegExp _pcdataFilter = RegExp(r'(&#?[a-z\d]+;|<[^>]+>)|([^&<]+)');
final RegExp _tagFilter = RegExp('(<[^>]+>)|([^<]+)');

/// Each run of visible characters with its first character upper case
/// and the rest lower case (Ruby's `capitalize`).
String _capitalizeWords(String text) =>
    text.replaceAllMapped(RegExp(r'[^\s\x00-\x1f\x7f]+'), (match) {
      final word = match[0]!;
      final first = String.fromCharCode(word.runes.first);
      return first.toUpperCase() + word.substring(first.length).toLowerCase();
    });

// The gem's small capitals (ғ, ǫ and s, more widely supported, in place of
// ꜰ, ꞯ and ꜱ; o and x as they are).
const String _smallCapsFrom = 'abcdefghijklmnopqrstuvwxyz';
const String _smallCapsTo = 'ᴀʙᴄᴅᴇғɢʜɪᴊᴋʟᴍɴoᴘǫʀsᴛᴜᴠᴡxʏᴢ';

String _smallCaps(String text) {
  final out = StringBuffer();
  for (final char in text.split('')) {
    final index = _smallCapsFrom.indexOf(char);
    out.write(
      index < 0
          ? char
          : String.fromCharCode(_smallCapsTo.runes.elementAt(index)),
    );
  }
  return out.toString();
}
