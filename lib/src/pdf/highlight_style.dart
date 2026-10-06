/// Syntax highlighting in the PDF (modern engine): a highlight.js theme
/// (`highlightjs-theme`, as the HTML backends use it) read for the colors,
/// weights and styles of hilite's token classes, and hilite's HTML turned
/// into the PDF backend's text markup with them.
library;

import 'package:asciidart/src/pdf/hljs_styles.g.dart';

/// A selector of a theme rule: compound class selectors (`.hljs-title
/// .class_`), each a descendant of the one before.
typedef _Selector = List<Set<String>>;

/// A rule of a theme: its selectors, its declarations, and its place in
/// the stylesheet.
final class _Rule {
  const new(this.selectors, this.order, {this.color, this.bold, this.italic});

  final List<_Selector> selectors;
  final String? color;
  final bool? bold;
  final bool? italic;
  final int order;
}

/// A token's style: its color (six hex digits) and whether it is bold or
/// italic.
typedef TokenStyle = ({String? color, bool bold, bool italic});

/// The token styles of a highlight.js theme.
final class HighlightStyle {
  new _(this._rules);

  /// The theme in the stylesheet [css]: the rules whose selectors are
  /// made of classes alone.
  factory parse(String css) {
    // Custom properties (`--hljs-hue-1: #0274C5`), wherever declared.
    final variables = {
      for (final m in RegExp(r'(--[\w-]+)\s*:\s*([^;}]+)').allMatches(css))
        m[1]!: m[2]!.trim(),
    };
    String resolve(String value) =>
        value.replaceAllMapped(RegExp(r'var\((--[\w-]+)[^)]*\)'), (m) {
          return variables[m[1]!] ?? '';
        });
    final rules = <_Rule>[];
    for (final m in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
      final selectors = <_Selector>[];
      for (final selector in m[1]!.split(',')) {
        final parts = selector.trim().split(RegExp(r'\s+'));
        if (parts.any((part) => !_compoundRx.hasMatch(part))) continue;
        selectors.add([
          for (final part in parts)
            {...part.split('.').where((name) => name.isNotEmpty)},
        ]);
      }
      if (selectors.isEmpty) continue;
      String? color;
      bool? bold;
      bool? italic;
      for (final declaration in m[2]!.split(';')) {
        final colon = declaration.indexOf(':');
        if (colon < 0) continue;
        final property = declaration.substring(0, colon).trim();
        final value = resolve(declaration.substring(colon + 1).trim())
            .toLowerCase();
        switch (property) {
          case 'color':
            color = _hex(value) ?? color;
          case 'font-weight':
            bold = const {
              'bold',
              'bolder',
              '600',
              '700',
              '800',
              '900',
            }.contains(value);
          case 'font-style':
            italic = value == 'italic' || value == 'oblique';
        }
      }
      if (color == null && bold == null && italic == null) continue;
      rules.add(
        _Rule(
          selectors,
          rules.length,
          color: color,
          bold: bold,
          italic: italic,
        ),
      );
    }
    return HighlightStyle._(rules);
  }

  /// The theme [name] (`github` when highlight.js has no theme of that
  /// name), or null when there is none at all.
  static HighlightStyle? named(String? name) {
    final css =
        highlightJsStyles[name ?? 'github'] ?? highlightJsStyles['github'];
    return css == null ? null : HighlightStyle.parse(css);
  }

  final List<_Rule> _rules;

  static final RegExp _compoundRx = RegExp(r'^(\.[\w-]+)+$');

  /// The style of a token with [classes] inside elements with [outer]
  /// classes (nearest last): of each property, the value of the most
  /// specific rule that matches, the last one of those.
  TokenStyle styleOf(Set<String> classes, List<Set<String>> outer) {
    (int, int)? colorRank;
    (int, int)? boldRank;
    (int, int)? italicRank;
    String? color;
    var bold = false;
    var italic = false;
    bool better((int, int) rank, (int, int)? than) =>
        than == null ||
        rank.$1 > than.$1 ||
        (rank.$1 == than.$1 && rank.$2 > than.$2);
    for (final rule in _rules) {
      for (final selector in rule.selectors) {
        if (!_matches(selector, classes, outer)) continue;
        final rank = (
          selector.fold(0, (sum, compound) => sum + compound.length),
          rule.order,
        );
        if (rule.color case final value? when better(rank, colorRank)) {
          (color, colorRank) = (value, rank);
        }
        if (rule.bold case final value? when better(rank, boldRank)) {
          (bold, boldRank) = (value, rank);
        }
        if (rule.italic case final value? when better(rank, italicRank)) {
          (italic, italicRank) = (value, rank);
        }
      }
    }
    return (color: color, bold: bold, italic: italic);
  }

  /// Whether [selector] matches a token with [classes] inside [outer].
  static bool _matches(
    _Selector selector,
    Set<String> classes,
    List<Set<String>> outer,
  ) {
    if (!classes.containsAll(selector.last)) return false;
    var at = outer.length - 1;
    for (var i = selector.length - 2; i >= 0; i--) {
      while (at >= 0 && !outer[at].containsAll(selector[i])) {
        at--;
      }
      if (at < 0) return false;
      at--;
    }
    return true;
  }

  /// The style of the code a theme's `.hljs` rule gives (its color).
  TokenStyle get base => styleOf(const {'hljs'}, const []);

  /// [html] (hilite's, with `<span class="hljs-...">` around tokens) as
  /// the PDF backend's markup: each token's span as `<font color>`,
  /// `<strong>` and `<em>`. Other spans are left as they are.
  String markup(String html) {
    final out = StringBuffer();
    // The classes of the spans open, and the closing tags of each (null
    // for a span left as it is).
    final outer = <Set<String>>[
      {'hljs'},
    ];
    final closing = <String?>[];
    var last = 0;
    for (final m in _spanRx.allMatches(html)) {
      out.write(html.substring(last, m.start));
      last = m.end;
      if (m[0] == '</span>') {
        if (closing.isEmpty) {
          out.write(m[0]);
          continue;
        }
        final close = closing.removeLast();
        if (close == null) {
          out.write(m[0]);
        } else {
          outer.removeLast();
          out.write(close);
        }
        continue;
      }
      final classes = {...m[1]!.split(' ').where((c) => c.isNotEmpty)};
      if (!classes.any((c) => c.startsWith('hljs-'))) {
        closing.add(null);
        out.write(m[0]);
        continue;
      }
      final style = styleOf(classes, outer);
      outer.add(classes);
      final open = StringBuffer();
      final close = StringBuffer();
      if (style.color case final color?) {
        open.write('<font color="#$color">');
        close.write('</font>');
      }
      if (style.bold) {
        open.write('<strong>');
        close.write('</strong>');
      }
      if (style.italic) {
        open.write('<em>');
        close.write('</em>');
      }
      out.write(open);
      closing.add(close.toString().split(RegExp('(?=</)')).reversed.join());
    }
    out.write(html.substring(last));
    return out.toString();
  }

  static final RegExp _spanRx = RegExp('<span class="([^"]*)">|</span>');

  /// The six hex digits of the CSS color [value] (hex, `rgb()` or a
  /// common name), or null.
  static String? _hex(String value) {
    if (value.startsWith('#')) {
      final digits = value.substring(1);
      if (RegExp(r'^[0-9a-f]+$').hasMatch(digits)) {
        return switch (digits.length) {
          3 || 4 => [for (final c in digits.split('').take(3)) '$c$c'].join(),
          6 || 8 => digits.substring(0, 6),
          _ => null,
        }?.toUpperCase();
      }
      return null;
    }
    if (RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(value) case final m?) {
      final parts = m[1]!.split(RegExp(r'[\s,/]+'));
      if (parts.length < 3) return null;
      final channels = [
        for (final part in parts.take(3))
          if (part.endsWith('%'))
            ((double.tryParse(part.replaceAll('%', '')) ?? 0) * 2.55).round()
          else
            int.tryParse(part) ?? 0,
      ];
      return [
        for (final c in channels)
          c.clamp(0, 255).toRadixString(16).padLeft(2, '0'),
      ].join().toUpperCase();
    }
    return _named[value];
  }

  /// The CSS color names the themes use.
  static const Map<String, String> _named = {
    'black': '000000',
    'white': 'FFFFFF',
    'red': 'FF0000',
    'green': '008000',
    'blue': '0000FF',
    'navy': '000080',
    'gray': '808080',
    'grey': '808080',
    'silver': 'C0C0C0',
    'maroon': '800000',
    'purple': '800080',
    'fuchsia': 'FF00FF',
    'olive': '808000',
    'teal': '008080',
    'aqua': '00FFFF',
    'yellow': 'FFFF00',
    'lime': '00FF00',
    'orange': 'FFA500',
    'brown': 'A52A2A',
    'darkgreen': '006400',
    'darkblue': '00008B',
    'darkred': '8B0000',
    'darkgray': 'A9A9A9',
    'darkgrey': 'A9A9A9',
    'lightgray': 'D3D3D3',
    'lightgrey': 'D3D3D3',
    'dimgray': '696969',
    'dimgrey': '696969',
    'gold': 'FFD700',
    'pink': 'FFC0CB',
    'violet': 'EE82EE',
    'indigo': '4B0082',
    'crimson': 'DC143C',
    'coral': 'FF7F50',
    'tomato': 'FF6347',
    'salmon': 'FA8072',
    'khaki': 'F0E68C',
    'tan': 'D2B48C',
    'wheat': 'F5DEB3',
    'chocolate': 'D2691E',
    'peru': 'CD853F',
    'sienna': 'A0522D',
    'steelblue': '4682B4',
    'slategray': '708090',
    'slategrey': '708090',
    'cadetblue': '5F9EA0',
    'darkorange': 'FF8C00',
    'darkviolet': '9400D3',
    'darkcyan': '008B8B',
    'darkmagenta': '8B008B',
    'darkolivegreen': '556B2F',
    'firebrick': 'B22222',
    'forestgreen': '228B22',
    'goldenrod': 'DAA520',
    'darkgoldenrod': 'B8860B',
    'seagreen': '2E8B57',
    'olivedrab': '6B8E23',
    'royalblue': '4169E1',
    'midnightblue': '191970',
    'orchid': 'DA70D6',
    'plum': 'DDA0DD',
    'magenta': 'FF00FF',
    'cyan': '00FFFF',
  };
}
