/// Port of the CodeRay 1.1.3 HTML encoder (`encoders/html.rb` with
/// `encoders/html/numbering.rb`, the `:table` branch of
/// `encoders/html/output.rb`, and the `:alpha` style lookup from
/// `encoders/html/css.rb` + `styles/alpha.rb`).
///
/// Covers exactly the option surface asciidoctor uses
/// (`CodeRay::Duo[lang, :html, opts]` with `css`, `line_numbers`,
/// `line_number_start`, `line_number_anchors: false`, `highlight_lines`
/// and `bold_every: false`; everything else at its default):
///
/// * Token text is HTML-escaped (`&`, `"`, `>`, `<`, tabs to 8 spaces,
///   ASCII control characters to spaces) and wrapped in
///   `<span class="...">` ([CssMode.classes]) or `<span style="...">`
///   ([CssMode.inline], styles from the `alpha` theme).
/// * Token groups become nested spans (a bare `<span>` when the kind has
///   no CSS class).
/// * Inline line numbers split multiline spans at line breaks first (the
///   original's `break_lines`).
/// * `Numbering` (line counting, inline prefixes, the line-number table,
///   highlighted line numbers) is ported exactly, including the upstream
///   `max_width` off-by-one.
///
/// Never ported (unreachable on the asciidoctor path): `:wrap`, `:title`,
/// `:hint`, line-number anchors, bolding, and the `Output#stylesheet`
/// helpers.
library;

import 'package:asciidoctor/src/highlight/coderay_tokens.dart';
import 'package:asciidoctor/src/highlight/highlight.dart';

/// Encodes a CodeRay token stream as an HTML fragment.
///
/// Feed tokens through the [CoderayTokenSink] interface, then read the
/// finished fragment from [finish]. Mirrors `Encoder#encode` with the
/// scanner streaming directly into the encoder (`:tokens => self`).
class CoderayHtmlEncoder implements CoderayTokenSink {
  /// Creates an encoder for one highlight operation.
  ///
  /// [css] selects class or inline-style spans, [lineNumbers] the numbering
  /// mode, [startLine] the number of the first line, and [highlightLines]
  /// the 1-based lines whose numbers are emphasized.
  new({
    this.css = CssMode.classes,
    this.lineNumbers,
    this.startLine = 1,
    this.highlightLines = const <int>[],
  });

  /// Whether spans carry classes or inline styles (the `:css` option).
  final CssMode css;

  /// The line numbering mode (the `:line_numbers` option).
  final LineNumbersMode? lineNumbers;

  /// The number of the first line (the `:line_number_start` option).
  final int startLine;

  /// The 1-based line numbers to emphasize (the `:highlight_lines`
  /// option, as a list; the original converts it to a set).
  final List<int> highlightLines;

  /// The number of spaces a tab expands to (the `:tab_width` option,
  /// always at its default on the asciidoctor path).
  final int tabWidth = 8;

  final StringBuffer _out = StringBuffer();
  final List<String> _opened = <String>[];
  String? _lastOpened;

  /// Whether group nesting feeds span lookup (the original's
  /// `@set_last_opened`: set exactly in `:style` mode, since `:hint` is
  /// always off on the asciidoctor path).
  bool get _trackLastOpened => css == CssMode.inline;

  /// Whether multiline spans split at line breaks (the `:break_lines`
  /// option, forced on for inline line numbers).
  bool get _breakLines => lineNumbers == LineNumbersMode.inline;

  @override
  void textToken(String text, String kind) {
    final style = _spanForKinds(
      _lastOpened != null ? <String>[kind, ..._opened] : kind,
    );
    var escaped = _escapeHtml(text);
    if (_breakLines &&
        (style != null || _opened.isNotEmpty) &&
        escaped.contains('\n')) {
      escaped = _breakLinesIn(escaped, style);
    }
    if (style != null) {
      _out
        ..write(style)
        ..write(escaped)
        ..write('</span>');
    } else {
      _out.write(escaped);
    }
  }

  @override
  void beginGroup(String kind) {
    _out.write(
      _spanForKinds(_lastOpened != null ? <String>[kind, ..._opened] : kind) ??
          '<span>',
    );
    _opened.add(kind);
    if (_trackLastOpened) _lastOpened = kind;
  }

  @override
  void endGroup(String kind) {
    if (_opened.isNotEmpty) {
      _opened.removeLast();
      _out.write('</span>');
      if (_lastOpened != null) {
        _lastOpened = _opened.isEmpty ? null : _opened.last;
      }
    }
  }

  /// Closes open spans, applies line numbering, and returns the HTML
  /// fragment (port of `HTML#finish` for the asciidoctor option surface).
  String finish() {
    while (_opened.isNotEmpty) {
      _opened.removeLast();
      _out.write('</span>');
    }
    _lastOpened = null;
    var html = _out.toString();
    if (lineNumbers != null) html = _addLineNumbers(html);
    return html;
  }

  /// Returns the opening span for [kinds] (a kind or a kind plus its
  /// enclosing groups), or `null` when no span is emitted.
  ///
  /// A span is emitted exactly when the current kind has a CSS class; in
  /// `:style` mode the `style` attribute always renders (possibly empty),
  /// resolved from the `alpha` theme over the nested classes.
  String? _spanForKinds(Object kinds) {
    final String first;
    final List<String> nested;
    if (kinds is List<String>) {
      first = kinds.first;
      nested = kinds;
    } else {
      first = kinds as String;
      nested = <String>[first];
    }
    if (coderayTokenClass(first) == null) return null;
    if (css == CssMode.inline) {
      final classes = nested.map((kind) => coderayTokenClass(kind) ?? '');
      final style = _styleForClasses(classes.toList());
      // A missing rule renders a bare span; an empty rule still renders
      // the (empty) attribute — the original's `if style` distinguishes
      // `nil` from `''`, both of which the lookup can return.
      return style == null ? '<span>' : '<span style="$style">';
    }
    return '<span class="${coderayTokenClass(first)}">';
  }

  /// Resolves nested CSS classes to an inline style (port of
  /// `CSS#get_style_for_css_classes` over the `alpha` theme).
  ///
  /// [classes] holds the current class first, then the enclosing classes
  /// from outermost to innermost. The lookup tries the full enclosing
  /// context first, then progressively drops the outermost class —
  /// matching the original's `1.upto size` walk over
  /// `css_classes[offset..-1]` — and returns the first hit, or `null`
  /// when every context misses (each miss overwrites the accumulator
  /// with `nil`, so a total miss returns `nil`, not the `''` seed).
  String? _styleForClasses(List<String> classes) {
    final table = _alphaStyles[classes.first];
    // Unreachable in practice (every class the scanners emit has table
    // rows); mirrors the original's `return '' unless cl`.
    if (table == null) return '';
    for (var offset = 1; offset <= classes.length; offset++) {
      final style = table[classes.sublist(offset).join('\n')];
      if (style != null) return style;
    }
    return null;
  }

  /// Splits [text] at line breaks, closing and reopening every open span
  /// around each break (port of `HTML#break_lines`).
  String _breakLinesIn(String text, String? style) {
    final reopen = StringBuffer();
    for (var index = 0; index < _opened.length; index++) {
      // The current kind first, then its enclosing groups from outermost
      // to innermost (the original's `[kind, *opened[0...index]]`).
      final kinds = index == 0
          ? _opened[0]
          : <String>[_opened[index], ..._opened.sublist(0, index)];
      reopen.write(_spanForKinds(kinds) ?? '<span>');
    }
    final close =
        '${'</span>' * _opened.length}${style != null ? '</span>' : ''}';
    final open = '$reopen${style ?? ''}';
    return text.replaceAll('\n', '$close\n$open');
  }

  /// Escapes HTML metacharacters, tabs and control characters (port of the
  /// `HTML_ESCAPE` substitution, including the tab-width expansion).
  String _escapeHtml(String text) {
    StringBuffer? out;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      final replacement = _escapeFor(unit);
      if (replacement == null) {
        out?.writeCharCode(unit);
      } else {
        (out ??= StringBuffer(text.substring(0, i))).write(replacement);
      }
    }
    return out == null ? text : out.toString();
  }

  /// The escape replacement for [unit], or `null` when emitted as-is.
  String? _escapeFor(int unit) {
    switch (unit) {
      case 0x26:
        return '&amp;';
      case 0x22:
        return '&quot;';
      case 0x3E:
        return '&gt;';
      case 0x3C:
        return '&lt;';
      case 0x09:
        return ' ' * tabWidth;
      default:
        // ASCII control characters other than tab, newline and carriage
        // return become spaces (port of the `HTML_ESCAPE` control range;
        // `\r` never occurs in normalized input but is preserved like the
        // original, whose escape pattern excludes it).
        if (unit < 0x20 && unit != 0x0A && unit != 0x0D) return ' ';
        return null;
    }
  }

  /// Applies line numbering to [html] (port of `Numbering.number!` with
  /// `line_number_anchors: false` and `bold_every: false`).
  String _addLineNumbers(String html) {
    final lineCount = _countLines(html);
    final highlighted = highlightLines.toSet();
    String renderNumber(int number) => highlighted.contains(number)
        ? '<strong class="highlighted">$number</strong>'
        : '$number';
    if (lineNumbers == LineNumbersMode.inline) {
      // NOTE the upstream off-by-one: the width derives from
      // `start + line_count`, not the last line number.
      final maxWidth = (startLine + lineCount).toString().length;
      final out = StringBuffer();
      var number = startLine;
      for (final line in _splitLines(html)) {
        final indent = ' ' * (maxWidth - number.toString().length);
        out.write(
          '<span class="line-numbers">$indent${renderNumber(number)}</span>$line',
        );
        number++;
      }
      return out.toString();
    }
    final numbers = StringBuffer();
    for (var n = startLine; n < startLine + lineCount; n++) {
      numbers
        ..write(renderNumber(n))
        ..write('\n');
    }
    return '<table class="CodeRay"><tr>\n'
        '  <td class="line-numbers"><pre>$numbers</pre></td>\n'
        '  <td class="code"><pre>$html</pre></td>\n'
        '</tr></table>\n';
  }

  /// Counts the source lines behind [html] (port of the `Numbering`
  /// line-count preamble: trailing closing spans after the last newline
  /// do not start a new line).
  int _countLines(String html) {
    final lastNewline = html.lastIndexOf('\n');
    if (lastNewline == -1) return 1;
    final after = html.substring(lastNewline + 1);
    final newlineCount = '\n'.allMatches(html).length;
    return _trailingSpansOnly.hasMatch(after) ? newlineCount : newlineCount + 1;
  }

  /// Splits [html] into lines that keep their terminators (port of the
  /// `:inline` numbering substitution `/^.*$\n?/`: a trailing newline
  /// terminates the last line rather than starting an empty one, while
  /// empty output still yields one empty line — both verified against the
  /// oracle).
  Iterable<String> _splitLines(String html) sync* {
    if (html.isEmpty) {
      yield '';
      return;
    }
    var start = 0;
    while (start < html.length) {
      final newline = html.indexOf('\n', start);
      if (newline == -1) {
        yield html.substring(start);
        return;
      }
      yield html.substring(start, newline + 1);
      start = newline + 1;
    }
  }
}

/// Matches trailing closing spans after the last newline (port of
/// `/\A(?:<\/span>)*\z/`; `$` without `multiLine` is the absolute end).
final RegExp _trailingSpansOnly = RegExp(r'^(?:</span>)*$');

/// Inline styles of the CodeRay `alpha` theme (port of the parsed
/// `CodeRay::Styles::Alpha::TOKEN_COLORS` lookup).
///
/// Maps the current CSS class to its enclosing-context styles: the
/// empty key holds the bare (context-free) rule, any other key joins
/// the enclosing classes from outermost to innermost with newlines.
///
/// GENERATED from CodeRay 1.1.3 - do not edit by hand. Regenerate
/// with:
/// ```sh
/// ruby -e "require 'coderay'; require 'json'; \
///   puts JSON.pretty_generate(
///     CodeRay::Encoders::HTML::CSS.new(:alpha)
///       .instance_variable_get(:@styles)
///       .to_h { |k, v| [k.to_s, v.to_h { |kk, vv| \
///         [kk.map(&:to_s), vv] }] })"
/// ```
/// and reformat as below (keys sorted, contexts newline-joined).
const Map<String, Map<String, String>>
_alphaStyles = <String, Map<String, String>>{
  'annotation': <String, String>{'': 'color:#007'},
  'attribute-name': <String, String>{'': 'color:#b48'},
  'attribute-value': <String, String>{'': 'color:#700'},
  'binary': <String, String>{'': 'color:#549'},
  'change': <String, String>{
    'change': 'color:#88f',
    '': 'color:#bbf;background:#007',
  },
  'char': <String, String>{
    'binary': 'color:#325',
    'comment': 'color:#444',
    'key': 'color:#60f',
    'string': 'color:#b0b',
    '': 'color:#D20',
  },
  'class': <String, String>{'': 'color:#B06;font-weight:bold'},
  'class-variable': <String, String>{'': 'color:#369'},
  'color': <String, String>{'': 'color:#0A0'},
  'comment': <String, String>{'': 'color:#777'},
  'constant': <String, String>{'': 'color:#036;font-weight:bold'},
  'content': <String, String>{
    'char': 'color:#D20',
    'function': 'color:#037',
    'map': 'color:#808',
    'regexp': 'color:#808',
    'shell': 'color:#2B2',
    'string': 'color:#D20',
    'symbol': 'color:#A60',
  },
  'debug': <String, String>{
    '': 'color:white!important;background:blue!important',
  },
  'decorator': <String, String>{'': 'color:#B0B'},
  'definition': <String, String>{'': 'color:#099;font-weight:bold'},
  'delete': <String, String>{
    'delete': 'color:#c00;background:transparent;font-weight:bold',
    '': 'background:hsla(0,100%,50%,0.12)',
  },
  'delimiter': <String, String>{
    'binary': 'color:#325',
    'char': 'color:#710',
    'comment': 'color:#444',
    'function': 'color:#059',
    'key': 'color:#404',
    'map': 'color:#40A',
    'regexp': 'color:#404',
    'shell': 'color:#161',
    'string': 'color:#710',
    'symbol': 'color:#740',
    '': 'color:black',
  },
  'directive': <String, String>{'': 'color:#088;font-weight:bold'},
  'docstring': <String, String>{'': 'color:#D42'},
  'doctype': <String, String>{'': 'color:#34b'},
  'done': <String, String>{'': 'text-decoration:line-through;color:gray'},
  'entity': <String, String>{'': 'color:#800;font-weight:bold'},
  'error': <String, String>{'': 'color:#F00;background-color:#FAA'},
  'escape': <String, String>{'': 'color:#666'},
  'exception': <String, String>{'': 'color:#C00;font-weight:bold'},
  'eyecatcher': <String, String>{
    'delete': 'background-color:hsla(0,100%,50%,0.2);border:1pxsolidhsla(0,100%,45%,0.5);margin:-1px;border-bottom:none;border-top-left-radius:5px;border-top-right-radius:5px',
    'insert': 'background-color:hsla(120,100%,50%,0.2);border:1pxsolidhsla(120,100%,25%,0.5);margin:-1px;border-top:none;border-bottom-left-radius:5px;border-bottom-right-radius:5px',
  },
  'filename': <String, String>{'head': 'color:white'},
  'float': <String, String>{'': 'color:#60E'},
  'function': <String, String>{'': 'color:#06B;font-weight:bold'},
  'global-variable': <String, String>{'': 'color:#d70'},
  'head': <String, String>{
    'head': 'color:#f4f',
    '': 'color:#f8f;background:#505',
  },
  'hex': <String, String>{'': 'color:#02b'},
  'id': <String, String>{'': 'color:#33D;font-weight:bold'},
  'imaginary': <String, String>{'': 'color:#f00'},
  'important': <String, String>{'': 'color:#D00'},
  'include': <String, String>{'': 'color:#B44;font-weight:bold'},
  'inline': <String, String>{
    '': 'background-color:hsla(0,0%,0%,0.07);color:black',
  },
  'inline-delimiter': <String, String>{'': 'font-weight:bold;color:#666'},
  'insert': <String, String>{
    'insert': 'color:#0c0;background:transparent;font-weight:bold',
    '': 'background:hsla(120,100%,50%,0.12)',
  },
  'instance-variable': <String, String>{'': 'color:#33B'},
  'integer': <String, String>{'': 'color:#00D'},
  'key': <String, String>{'': 'color:#606'},
  'keyword': <String, String>{'': 'color:#080;font-weight:bold'},
  'label': <String, String>{'': 'color:#970;font-weight:bold'},
  'local-variable': <String, String>{'': 'color:#950'},
  'map': <String, String>{'': 'background-color:hsla(200,100%,50%,0.06)'},
  'modifier': <String, String>{'regexp': 'color:#C2C', 'string': 'color:#E40'},
  'namespace': <String, String>{'': 'color:#707;font-weight:bold'},
  'octal': <String, String>{'': 'color:#40E'},
  'operator': <String, String>{'': ''},
  'predefined': <String, String>{'': 'color:#369;font-weight:bold'},
  'predefined-constant': <String, String>{'': 'color:#069'},
  'predefined-type': <String, String>{'': 'color:#0a8;font-weight:bold'},
  'preprocessor': <String, String>{'': 'color:#579'},
  'pseudo-class': <String, String>{'': 'color:#00C;font-weight:bold'},
  'regexp': <String, String>{'': 'background-color:hsla(300,100%,50%,0.06)'},
  'reserved': <String, String>{'': 'color:#080;font-weight:bold'},
  'shell': <String, String>{'': 'background-color:hsla(120,100%,50%,0.06)'},
  'string': <String, String>{'': 'background-color:hsla(0,100%,50%,0.05)'},
  'symbol': <String, String>{'': 'color:#A60'},
  'tag': <String, String>{'': 'color:#070;font-weight:bold'},
  'type': <String, String>{'': 'color:#339;font-weight:bold'},
  'value': <String, String>{'': 'color:#088'},
  'variable': <String, String>{'': 'color:#037'},
};
